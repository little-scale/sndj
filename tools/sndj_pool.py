#!/usr/bin/env python3
"""sndj_pool.py — build the self-describing ROM sample pool (CLAUDE.md §14.4).

Pool image layout (little endian):
  +0   8   magic "SNDJPOOL"
  +8   1   format version (1)
  +9   1   entry count N
  +10  6   reserved
  +16  N x 16-byte entries:
        +0  8  name (ASCII, space padded)
        +8  2  BRR data offset (from the start of the pool image)
        +10 2  BRR byte length (multiple of 9)
        +12 2  loop block index ($FFFF = one-shot)
        +14 2  reserved
  then the BRR data, concatenated.

If samples/pool.bin exists it is used verbatim (production pool); otherwise
the factory pool is synthesized here (pad, bass, pluck, kick, snare, hat) —
real WAV ingestion arrives with the browser patcher, which writes pool.bin.
"""
import math
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sndj_brr


def synth_pad():
    return sndj_brr.gen_pad(), 0          # 128-sample loop


def synth_bass():
    # two-cycle deep saturated sine, 256-sample loop (125 Hz at $1000)
    out = []
    for i in range(256):
        t = 2 * math.pi * i / 256
        v = math.tanh(2.2 * math.sin(t) + 0.6 * math.sin(2 * t))
        out.append(int(v * 26000))
    return out, 0


def synth_pluck():
    # decaying bright harmonic stack, one-shot-ish with a short loop tail
    n = 2048
    out = []
    for i in range(n):
        t = i / 32000
        env = math.exp(-t * 18)
        ph = 2 * math.pi * 440 * t
        v = (math.sin(ph) + 0.5 * math.sin(2 * ph) + 0.25 * math.sin(3 * ph)
             + 0.12 * math.sin(5 * ph))
        out.append(int(v / 1.87 * 24000 * env))
    return out, None


def synth_kick():
    n = 4096
    out = []
    ph = 0.0
    for i in range(n):
        t = i / 32000
        f = 40 + 140 * math.exp(-t * 28)
        ph += 2 * math.pi * f / 32000
        env = math.exp(-t * 14)
        v = math.sin(ph) * env
        if i < 64:
            v += (1 - i / 64) * 0.6 * (1 if i % 7 < 3 else -1)  # click
        out.append(int(max(-1, min(1, v)) * 28000))
    return out, None


def synth_snare(seed=0x1234):
    n = 3072
    out = []
    lfsr = seed
    for i in range(n):
        t = i / 32000
        lfsr = (lfsr >> 1) ^ (-(lfsr & 1) & 0xB400)
        noise = (lfsr / 32768) - 1
        tone = math.sin(2 * math.pi * 190 * t)
        env_n = math.exp(-t * 22)
        env_t = math.exp(-t * 35)
        v = 0.7 * noise * env_n + 0.5 * tone * env_t
        out.append(int(max(-1, min(1, v)) * 26000))
    return out, None


def synth_hat(seed=0xACE1):
    n = 1024
    out = []
    lfsr = seed
    prev = 0
    for i in range(n):
        t = i / 32000
        lfsr = (lfsr >> 1) ^ (-(lfsr & 1) & 0xB400)
        noise = (lfsr / 32768) - 1
        hp = noise - prev                 # crude highpass
        prev = noise
        env = math.exp(-t * 60)
        out.append(int(max(-1, min(1, hp * 0.9)) * 24000 * env))
    return out, None


FACTORY = [
    ("PAD", synth_pad),
    ("BASS", synth_bass),
    ("PLUCK", synth_pluck),
    ("KICK", synth_kick),
    ("SNARE", synth_snare),
    ("HAT", synth_hat),
]


def build_pool():
    entries = []
    blobs = []
    for name, fn in FACTORY:
        samples, loop = fn()
        samples = samples[:len(samples) // 16 * 16]
        brr = sndj_brr.encode(samples, loop_block=loop)
        entries.append((name, len(brr), loop))
        blobs.append(brr)
    header = b"SNDJPOOL" + bytes([1, len(entries)]) + bytes(6)
    table = b""
    off = 16 + 16 * len(entries)
    for (name, size, loop), blob in zip(entries, blobs):
        loop_blk = 0xFFFF if loop is None else loop
        table += name.ljust(8)[:8].encode() + struct.pack(
            "<HHH", off, size, loop_blk) + bytes(2)
        off += size
    return header + table + b"".join(blobs)


def main(out_path):
    src = os.path.join(os.path.dirname(os.path.dirname(
        os.path.abspath(__file__))), "samples", "pool.bin")
    if os.path.exists(src):
        data = open(src, "rb").read()
        assert data[:8] == b"SNDJPOOL", "samples/pool.bin: bad magic"
        print(f"sndj_pool: using committed samples/pool.bin ({len(data)} bytes)")
    else:
        data = build_pool()
        print(f"sndj_pool: synthesized factory pool "
              f"({data[9]} samples, {len(data)} bytes)")
    RESERVED = 0x17FFA
    assert len(data) <= RESERVED, f"pool {len(data)} exceeds {RESERVED}"
    data = data + b"\xFF" * (RESERVED - len(data))
    open(out_path, "wb").write(data)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "build/pool.bin")
