#!/usr/bin/env python3
"""sndj_rle.py — Python mirror of the SNDJ1 RLE codec (SAVEFORMAT.md).

- control $00-$7F: copy next c+1 literal bytes (1-128)
- control $80-$FF: repeat next byte c-$80+3 times (3-130)

The 65816 implementation lives in src/save.asm; tools/checks/save.lua
verifies the console-packed stream against this format at emulator level.
"""
import sys


def pack(data):
    out = bytearray()
    i, n = 0, len(data)
    lit_start = None

    def flush_lit(end):
        nonlocal lit_start
        s = lit_start
        while s is not None and s < end:
            chunk = min(128, end - s)
            out.append(chunk - 1)
            out.extend(data[s:s + chunk])
            s += chunk
        lit_start = None

    while i < n:
        run = 1
        while i + run < n and data[i + run] == data[i] and run < 130:
            run += 1
        if run >= 3:
            flush_lit(i)
            out.append(0x80 + run - 3)
            out.append(data[i])
            i += run
        else:
            if lit_start is None:
                lit_start = i
            i += run
    flush_lit(i)
    return bytes(out)


def unpack(data, size):
    out = bytearray()
    i = 0
    while len(out) < size:
        c = data[i]
        i += 1
        if c < 0x80:
            out.extend(data[i:i + c + 1])
            i += c + 1
        else:
            out.extend(data[i:i + 1] * (c - 0x80 + 3))
            i += 1
    assert len(out) == size, "stream overshoots the unpacked size"
    return bytes(out)


BLOCK_SZ = 0x5300     # SAVEFORMAT.md v2
PHRASES_OFF = 0x2300  # interleaved phrase pool at the END of the block
PHRASES_LEN = 0x3000


CHAINS_OFF = 0x1700
CHAINS_LEN = 0x0C00


def to_image(block):
    """Reorder the song block into the column-planar save image:
    [4 phrase planes][2 chain planes][the rest of the block, linear]."""
    assert len(block) == BLOCK_SZ
    img = bytearray()
    for col in range(4):
        img.extend(block[PHRASES_OFF + col:PHRASES_OFF + PHRASES_LEN:4])
    for col in range(2):
        img.extend(block[CHAINS_OFF + col:CHAINS_OFF + CHAINS_LEN:2])
    img.extend(block[:CHAINS_OFF])
    return bytes(img)


def from_image(img):
    assert len(img) == BLOCK_SZ
    block = bytearray(BLOCK_SZ)
    n = PHRASES_LEN // 4
    for col in range(4):
        block[PHRASES_OFF + col:PHRASES_OFF + PHRASES_LEN:4] = \
            img[col * n:(col + 1) * n]
    m = CHAINS_LEN // 2
    for col in range(2):
        block[CHAINS_OFF + col:CHAINS_OFF + CHAINS_LEN:2] = \
            img[PHRASES_LEN + col * m:PHRASES_LEN + (col + 1) * m]
    block[:CHAINS_OFF] = img[PHRASES_LEN + CHAINS_LEN:]
    return bytes(block)


def crc16(data):
    crc = 0xFFFF
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021 if crc & 0x8000 else crc << 1) & 0xFFFF
    return crc


def selftest():
    import random
    rnd = random.Random(1)
    cases = [
        bytes(BLOCK_SZ),                                    # all zero
        bytes([0xFF]) * BLOCK_SZ,                           # all $FF
        bytes(rnd.randrange(256) for _ in range(BLOCK_SZ)),  # noise
        (b"\x00" * 100 + b"ABC" + b"\x55" * 300) * 40 + bytes(BLOCK_SZ),
    ]
    for i, src in enumerate(c[:BLOCK_SZ] for c in cases):
        p = pack(src)
        u = unpack(p, len(src))
        assert u == src, f"case {i} round-trip failed"
    assert crc16(b"123456789") == 0x29B1, "CRC-16/CCITT check value"
    # image reorder round-trip + empty-song packing size
    empty = bytearray(BLOCK_SZ)
    for i in range(PHRASES_OFF + 1, PHRASES_OFF + PHRASES_LEN, 4):
        empty[i] = 0xFF          # instr column = none
    for i in range(CHAINS_OFF, CHAINS_OFF + CHAINS_LEN, 2):
        empty[i] = 0xFF          # chain phrase entries = empty
    for i in range(0x0000, 0x0400):
        empty[i] = 0xFF          # song grid = empty
    empty = bytes(empty)
    assert from_image(to_image(empty)) == empty
    packed = pack(to_image(empty))
    assert len(packed) < 768, f"empty song image packs to {len(packed)}"
    print(f"sndj_rle selftest: OK (empty song image packs to "
          f"{len(packed)} bytes)")


if __name__ == '__main__':
    if '--selftest' in sys.argv:
        selftest()
    else:
        print(__doc__)
