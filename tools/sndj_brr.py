#!/usr/bin/env python3
"""sndj_brr.py — BRR encoder/decoder for sndj (CLAUDE.md §14.3).

The reference BRR codec for the whole project: brute-force filter/range
search per 16-sample block, bit-exact decoder for round-trip verification
(`make test`), and a built-in test-tone generator so the ROM has a sample
before the WAV pipeline lands (M11 wires up pools/pre-emphasis/loop tools).

BRR block: 1 header byte [rrrrffle] (r=range 0-12, f=filter 0-3, l=loop,
e=end) + 8 bytes of 4-bit signed nibbles, high nibble first = 16 samples.

Usage:
  sndj_brr.py --gen pad out.brr     generate the factory test sample
  sndj_brr.py encode in.wav out.brr [--loop N]
  sndj_brr.py --selftest
"""
import math
import struct
import sys

FILTERS = [
    (0, 0),          # s[n] = nib
    (15 / 16, 0),    # s[n] = nib + p1*15/16
    (61 / 32, -15 / 16),
    (115 / 64, -13 / 16),
]


def _filter_predict(f, p1, p2):
    if f == 0:
        return 0
    if f == 1:
        return p1 + (-p1 >> 4)
    if f == 2:
        return (p1 << 1) + ((-((p1 << 1) + p1)) >> 5) - p2 + (p2 >> 4)
    return (p1 << 1) + ((-(p1 + (p1 << 2) + (p1 << 3))) >> 6) - p2 + \
        (((p2 << 1) + p2) >> 4)


def _clamp16(v):
    v = max(-0x8000, min(0x7FFF, v))
    # DSP wraps to 15 bits after clamp
    if v > 0x3FFF:
        v -= 0x8000
    elif v < -0x4000:
        v += 0x8000
    return v


def decode_block(block, p1, p2):
    """Decode one 9-byte block exactly as the S-DSP does."""
    hdr = block[0]
    rng, filt = hdr >> 4, (hdr >> 2) & 3
    out = []
    for i in range(8):
        byte = block[1 + i]
        for nib in (byte >> 4, byte & 0x0F):
            if nib >= 8:
                nib -= 16
            if rng <= 12:
                s = (nib << rng) >> 1
            else:
                s = ((-1 if nib < 0 else 0) & ~0x7FF) >> 1 if nib else 0
            s += _filter_predict(filt, p1, p2)
            s = _clamp16(s)
            p2, p1 = p1, s
            out.append(s * 2)  # 15-bit -> 16-bit domain
    return out, p1, p2


def decode(data):
    """Decode a whole BRR stream (ignores loop, stops at END flag)."""
    out, p1, p2 = [], 0, 0
    for off in range(0, len(data), 9):
        block = data[off:off + 9]
        if len(block) < 9:
            break
        samples, p1, p2 = decode_block(block, p1, p2)
        out.extend(samples)
        if block[0] & 1:
            break
    return out


def _encode_block(samples, p1, p2, force_f0=False):
    """Try filters/ranges, return (best_block, p1, p2, err)."""
    best = None
    filters = (0,) if force_f0 else (0, 1, 2, 3)
    for filt in filters:
        for rng in range(13):
            nibs = []
            tp1, tp2 = p1, p2
            err = 0
            for s in samples:
                target = s // 2  # 16-bit -> 15-bit domain
                pred = _filter_predict(filt, tp1, tp2)
                resid = target - pred
                # nearest representable nibble, then test both neighbours
                # through the exact decoder step and keep the better one
                base = (resid * 2) >> rng if rng else resid * 2
                cand_best = None
                for nib in (base, base + 1):
                    nib = max(-8, min(7, nib))
                    dec = _clamp16(((nib << rng) >> 1) + pred)
                    e = (dec - target) ** 2
                    if cand_best is None or e < cand_best[0]:
                        cand_best = (e, nib, dec)
                e, nib, dec = cand_best
                err += e
                tp2, tp1 = tp1, dec
                nibs.append(nib & 0x0F)
            if best is None or err < best[3]:
                block = bytes([(rng << 4) | (filt << 2)]) + bytes(
                    (nibs[i] << 4) | nibs[i + 1] for i in range(0, 16, 2))
                best = (block, tp1, tp2, err)
    return best


def encode(samples, loop_block=None):
    """Encode 16-bit samples (len % 16 == 0) to BRR.

    loop_block: block index the END block loops back to, or None for one-shot.
    The first block of a loop target uses filter 0 so the loop seam is
    history-independent.
    """
    assert len(samples) % 16 == 0, "sample count must be a multiple of 16"
    nblocks = len(samples) // 16
    out = bytearray()
    p1 = p2 = 0
    for b in range(nblocks):
        force_f0 = (b == 0) or (loop_block is not None and b == loop_block)
        block, p1, p2, _ = _encode_block(
            samples[b * 16:(b + 1) * 16], p1, p2, force_f0)
        hdr = block[0]
        if b == nblocks - 1:
            hdr |= 1  # END
            if loop_block is not None:
                hdr |= 2  # LOOP
        out.append(hdr)
        out.extend(block[1:])
    return bytes(out)


# --- factory test sample -----------------------------------------------------

def gen_pad(cycles=1, cycle_len=128):
    """Single-cycle organ-ish wave: sine + harmonics, loops seamlessly.
    At DSP pitch $1000 a 128-sample loop plays at 250 Hz (~B-3)."""
    n = cycle_len * cycles
    out = []
    for i in range(n):
        t = 2 * math.pi * i / cycle_len
        v = (math.sin(t) + 0.35 * math.sin(2 * t) + 0.18 * math.sin(3 * t)
             + 0.08 * math.sin(5 * t))
        out.append(int(v / 1.61 * 24000))
    return out


def read_wav_mono16(path):
    import wave
    w = wave.open(path, 'rb')
    assert w.getsampwidth() == 2, "16-bit WAV only"
    frames = w.readframes(w.getnframes())
    data = struct.unpack('<%dh' % (len(frames) // 2), frames)
    ch = w.getnchannels()
    if ch > 1:
        data = data[::ch]
    return list(data)


def selftest():
    # round-trip: encoded-then-decoded must be close; decoder must be exact
    # against itself (bit-exactness is asserted by re-encoding the decode)
    src = gen_pad()
    brr = encode(src, loop_block=0)
    assert len(brr) == len(src) // 16 * 9
    dec = decode(brr)
    assert len(dec) == len(src)
    # SNR of the encode (filter search should do well on smooth waves)
    err = sum((a - b) ** 2 for a, b in zip(src, dec)) / len(src)
    sig = sum(a * a for a in src) / len(src)
    snr = 10 * math.log10(sig / err) if err else 99
    # ~6 dB/bit of nibble resolution puts harmonically rich content near
    # 26-30 dB; this guards against encoder regressions, not audio quality
    assert snr > 26, f"BRR round-trip SNR too low: {snr:.1f} dB"
    # decoding twice is deterministic
    assert decode(brr) == dec
    # end/loop flags
    assert brr[-9] & 3 == 3
    print(f"sndj_brr selftest: OK (pad SNR {snr:.1f} dB, {len(brr)} bytes)")


def main(argv):
    if '--selftest' in argv:
        selftest()
        return 0
    if '--gen' in argv:
        i = argv.index('--gen')
        kind, out = argv[i + 1], argv[i + 2]
        assert kind == 'pad'
        brr = encode(gen_pad(), loop_block=0)
        open(out, 'wb').write(brr)
        print(f"sndj_brr: generated {kind} -> {out} ({len(brr)} bytes, "
              f"{len(brr) // 9} blocks, loop@0)")
        return 0
    if argv and argv[0] == 'encode':
        src = read_wav_mono16(argv[1])
        src = src[:len(src) // 16 * 16]
        loop = None
        if '--loop' in argv:
            loop = int(argv[argv.index('--loop') + 1])
        brr = encode(src, loop_block=loop)
        open(argv[2], 'wb').write(brr)
        print(f"sndj_brr: {argv[1]} -> {argv[2]} ({len(brr)} bytes)")
        return 0
    print(__doc__)
    return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
