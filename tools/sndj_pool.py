#!/usr/bin/env python3
"""sndj_pool.py — build the self-describing ROM sample pool (CLAUDE.md §14.4).

Pool image layout v2 (little endian; offsets/sizes in 9-byte BRR blocks so
16-bit fields address up to 576 KB):
  +0   8   magic "SNDJPOOL"
  +8   1   format version (2)
  +9   1   entry count N (max 56)
  +10  6   reserved
  +16  N x 16-byte entries:
        +0  8  name (ASCII, space padded)
        +8  2  BRR offset in blocks (from the start of the pool image)
        +10 2  BRR length in blocks
        +12 2  loop block index within the sample ($FFFF = one-shot)
        +14 2  reserved
  then the BRR data. Each sample is padded so its data never crosses a
  32 KB ROM bank boundary (the console reads with 16-bit in-bank math).

Factory content ("game authentic"): melodic samples extracted from
soundfonts/*.sf2 plus two drum kits from samples/ (808, 909), trimmed and
resampled to 32 kHz. If samples/pool.bin exists it is used verbatim.
"""
import math
import os
import struct
import sys
import wave

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sndj_brr

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESERVED = 0x27FFA          # banks 1-5 minus the 6-byte SNPOOL marker
BANK0_SPAN = 0x7FFA         # data bytes available in the marker bank
BANK_SPAN = 0x8000
MAX_ENTRIES = 56            # ARAM directory slots 0-55 (56-63 are waves)


# ---------------------------------------------------------------- ingestion
def resample(samples, src_rate, dst_rate=32000):
    if src_rate == dst_rate:
        return list(samples)
    ratio = src_rate / dst_rate
    n = int(len(samples) / ratio)
    out = []
    for i in range(n):
        p = i * ratio
        i0 = int(p)
        fr = p - i0
        a = samples[i0]
        b = samples[i0 + 1] if i0 + 1 < len(samples) else a
        out.append(int(a + (b - a) * fr))
    return out


def read_wav(path):
    w = wave.open(path, 'rb')
    n = w.getnframes()
    raw = w.readframes(n)
    ch = w.getnchannels()
    if w.getsampwidth() == 2:
        data = struct.unpack('<%dh' % (n * ch), raw)
    else:
        raise ValueError('16-bit WAV only: ' + path)
    if ch > 1:
        data = data[::ch]
    return list(data), w.getframerate()


def trim_tail(samples, floor=300):
    end = len(samples)
    while end > 16 and abs(samples[end - 1]) < floor:
        end -= 1
    return samples[:end]


def prep_oneshot(samples, rate, max_ms):
    s = resample(trim_tail(samples), rate)
    s = s[:int(32 * max_ms)]
    # short fade-out so the END block doesn't click
    fade = min(256, len(s))
    for i in range(fade):
        s[len(s) - fade + i] = s[len(s) - fade + i] * (fade - i) // fade
    return s[:len(s) // 16 * 16]


# ---------------------------------------------------------------- SF2 reader
def sf2_samples(path):
    data = open(path, 'rb').read()
    smpl = shdr = None

    def walk(pos, end):
        nonlocal smpl, shdr
        while pos < end - 8:
            cid = data[pos:pos + 4]
            size = struct.unpack('<I', data[pos + 4:pos + 8])[0]
            body = pos + 8
            if cid == b'LIST':
                walk(body + 4, body + size)
            elif cid == b'smpl':
                smpl = body
            elif cid == b'shdr':
                shdr = (body, size)
            pos = body + size + (size & 1)
    walk(12, len(data))
    out = []
    for i in range(shdr[1] // 46 - 1):
        r = shdr[0] + i * 46
        name = data[r:r + 20].split(b'\0')[0].decode('latin1')
        start, end, ls, le, rate = struct.unpack('<IIIII', data[r + 20:r + 40])
        pcm = struct.unpack('<%dh' % (end - start),
                            data[smpl + start * 2:smpl + end * 2])
        loop = (ls - start, le - start) if le > ls >= start else None
        out.append({'name': name, 'pcm': list(pcm), 'rate': rate, 'loop': loop})
    return out


# ---------------------------------------------------------------- factory set
DRUM_KITS = [('01 808', '808'), ('02 909', '909')]
DRUM_MS = {'BD': 220, 'SD': 180, 'CP': 180, 'CY': 260, 'HO': 200}  # else 130
SF2_PICKS = 8               # first N loopable melodic samples by size


def build_factory():
    entries = []            # (name, samples, loop_block or None)
    # melodics from the SSF2 font: 32 kHz native, looped, mid-sized
    sf2_path = None
    sf_dir = os.path.join(ROOT, 'soundfonts')
    if os.path.isdir(sf_dir):
        for f in sorted(os.listdir(sf_dir)):
            if 'street_fighter' in f.lower() and f.lower().endswith('.sf2'):
                sf2_path = os.path.join(sf_dir, f)
                break
    if sf2_path:
        cands = [s for s in sf2_samples(sf2_path)
                 if s['loop'] and 1000 <= len(s['pcm']) <= 14000]
        cands.sort(key=lambda s: len(s['pcm']))
        step = max(1, len(cands) // SF2_PICKS)
        for k, s in enumerate(cands[::step][:SF2_PICKS]):
            pcm = resample(s['pcm'], s['rate'])
            scale = 32000 / s['rate']
            loop_start = int(s['loop'][0] * scale)
            loop_block = (loop_start // 16 * 16) // 16
            pcm = pcm[:len(pcm) // 16 * 16]
            if loop_block * 16 >= len(pcm):
                loop_block = 0
            entries.append((f'SF2 {k:02d}', pcm, loop_block))
    # two drum kits, 16 slots each, drum-machine order preserved
    for folder, tag in DRUM_KITS:
        d = os.path.join(ROOT, 'samples', folder)
        seen = {}
        for f in sorted(os.listdir(d)):
            if not f.lower().endswith('.wav'):
                continue
            code = f.split()[1].split('.')[0]
            seen[code] = seen.get(code, 0) + 1
            name = f'{tag} {code}' if seen[code] == 1 else f'{tag} {code}{seen[code]}'
            pcm, rate = read_wav(os.path.join(d, f))
            ms = DRUM_MS.get(code, 180)
            pcm = prep_oneshot(pcm, rate, ms)
            if len(pcm) < 16:
                pcm = [0] * 16
            entries.append((name, pcm, None))
    return entries


# ---------------------------------------------------------------- pool image
def bank_pad(offset, size):
    """Return filler needed so [offset, offset+size) stays in one bank.
    Offsets are relative to the pool image; the image starts 6 bytes into
    bank 1's 32 KB window."""
    def bank_of(o):
        return 0 if o < BANK0_SPAN else 1 + (o - BANK0_SPAN) // BANK_SPAN

    def bank_end(o):
        b = bank_of(o)
        return BANK0_SPAN if b == 0 else BANK0_SPAN + b * BANK_SPAN
    if bank_of(offset) == bank_of(offset + size - 1):
        return 0
    return bank_end(offset) - offset


def build_pool(entries):
    assert len(entries) <= MAX_ENTRIES, f'{len(entries)} entries (max {MAX_ENTRIES})'
    blobs = []
    for name, pcm, loop in entries:
        brr = sndj_brr.encode(pcm, loop_block=loop)
        blobs.append((name, brr, loop))
    table = b''
    data = b''
    base = 16 + 16 * len(blobs)
    assert base % 9 != 0 or True
    # data area starts block-aligned right after the table (pad to 9)
    data_start = (base + 8) // 9 * 9
    off = data_start
    chunks = []
    for name, brr, loop in blobs:
        pad = bank_pad(off, len(brr))
        if pad:
            pad = (pad + 8) // 9 * 9      # keep block alignment
            chunks.append(b'\xFF' * pad)
            off += pad
        assert off % 9 == 0
        loop_blk = 0xFFFF if loop is None else loop
        table += name.ljust(8)[:8].encode() + struct.pack(
            '<HHH', off // 9, len(brr) // 9, loop_blk) + bytes(2)
        chunks.append(brr)
        off += len(brr)
    header = b'SNDJPOOL' + bytes([2, len(blobs)]) + bytes(6)
    img = header + table
    img += b'\xFF' * (data_start - len(img))
    img += b''.join(chunks)
    return img


def main(out_path):
    src = os.path.join(ROOT, 'samples', 'pool.bin')
    if os.path.exists(src):
        data = open(src, 'rb').read()
        assert data[:8] == b'SNDJPOOL', 'samples/pool.bin: bad magic'
        print(f'sndj_pool: using committed samples/pool.bin ({len(data)} bytes)')
    else:
        entries = build_factory()
        data = build_pool(entries)
        names = ' '.join(e[0].replace(' ', '_') for e in entries)
        print(f'sndj_pool: factory pool: {len(entries)} samples, '
              f'{len(data)} bytes\n  {names}')
    assert len(data) <= RESERVED, f'pool {len(data)} exceeds {RESERVED}'
    data = data + b'\xFF' * (RESERVED - len(data))
    open(out_path, 'wb').write(data)


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'build/pool.bin')
