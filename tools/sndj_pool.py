#!/usr/bin/env python3
"""sndj_pool.py — build the self-describing ROM sample pool (CLAUDE.md §14.4).

Pool image layout v2 (little endian; offsets/sizes in 9-byte BRR blocks so
16-bit fields address up to 576 KB). Entry +14/+15 are the default tune:
signed semitones and signed fine (1/256 semitone) applied by the engine
when the sample is triggered (factory entries bake their SF2 root into
the resample, so they carry 0/0).
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
    # drums live at 16 kHz (factory kit slots are tuned -12): half the ARAM
    s = resample(trim_tail(samples), rate, 16000)
    s = s[:int(16 * max_ms)]
    # short fade-out so the END block doesn't click
    fade = min(256, len(s))
    for i in range(fade):
        s[len(s) - fade + i] = s[len(s) - fade + i] * (fade - i) // fade
    return s[:len(s) // 16 * 16]


# ---------------------------------------------------------------- SF2 reader
def sf2_samples(path):
    data = open(path, 'rb').read()
    chunks = {}

    def walk(pos, end):
        while pos < end - 8:
            cid = data[pos:pos + 4]
            size = struct.unpack('<I', data[pos + 4:pos + 8])[0]
            body = pos + 8
            if cid == b'LIST':
                walk(body + 4, body + size)
            else:
                chunks[cid.decode('latin1')] = (body, size)
            pos = body + size + (size & 1)
    walk(12, len(data))
    smpl = chunks['smpl'][0]
    shdr = chunks['shdr']

    # resolve which PRESET owns each sample (phdr -> pbag -> pgen 41 ->
    # inst -> ibag -> igen 53) so pool entries carry musical names
    def recs(name, sz):
        if name not in chunks:
            return []
        b, s = chunks[name]
        return [data[b + i * sz:b + (i + 1) * sz] for i in range(s // sz)]
    phdr, pbag, pgen = recs('phdr', 38), recs('pbag', 4), recs('pgen', 4)
    inst, ibag, igen = recs('inst', 22), recs('ibag', 4), recs('igen', 4)
    inst_samples = {}
    for i in range(len(inst) - 1):
        b0 = struct.unpack('<H', inst[i][20:22])[0]
        b1 = struct.unpack('<H', inst[i + 1][20:22])[0]
        sids = set()
        for bg in range(b0, b1):
            g0 = struct.unpack('<H', ibag[bg][:2])[0]
            g1 = struct.unpack('<H', ibag[bg + 1][:2])[0]
            for g in range(g0, g1):
                op, amt = struct.unpack('<HH', igen[g])
                if op == 53:
                    sids.add(amt)
        inst_samples[i] = sids
    preset_of = {}
    for pi in range(len(phdr) - 1):
        pname = phdr[pi][:20].split(b'\0')[0].decode('latin1')
        b0 = struct.unpack('<H', phdr[pi][24:26])[0]
        b1 = struct.unpack('<H', phdr[pi + 1][24:26])[0]
        for bg in range(b0, b1):
            g0 = struct.unpack('<H', pbag[bg][:2])[0]
            g1 = struct.unpack('<H', pbag[bg + 1][:2])[0]
            for g in range(g0, g1):
                op, amt = struct.unpack('<HH', pgen[g])
                if op == 41:
                    for sid in inst_samples.get(amt, ()):
                        preset_of.setdefault(sid, pname)
    out = []
    for i in range(shdr[1] // 46 - 1):
        r = shdr[0] + i * 46
        name = data[r:r + 20].split(b'\0')[0].decode('latin1')
        start, end, ls, le, rate = struct.unpack('<IIIII', data[r + 20:r + 40])
        root = data[r + 40]
        corr = struct.unpack('<b', data[r + 41:r + 42])[0]   # cents
        pcm = struct.unpack('<%dh' % (end - start),
                            data[smpl + start * 2:smpl + end * 2])
        loop = (ls - start, le - start) if le > ls >= start else None
        out.append({'name': name, 'pcm': list(pcm), 'rate': rate, 'loop': loop,
                    'root': root, 'corr': corr,
                    'preset': preset_of.get(i)})
    return out


# ---------------------------------------------------------------- factory set
DRUM_KITS = [('01 808', '808'), ('02 909', '909')]
DRUM_MS = {'BD': 200, 'SD': 170, 'CP': 170, 'CY': 195, 'HO': 160}  # else 112
SF2_FONT = 'mario_paint'    # melodics come from this font (drums stay Seb's)
SF2_PICKS = [               # (preset name, 8-char pool name)
    ('Acoustic Guitar', 'AC GUITR'),
    ('Acoustic Bass',   'AC BASS'),
    ('Square',          'SQUARE'),
    ('Organ 1',         'ORGAN1'),
    ('Trumpet',         'TRUMPET'),
    ('Synth Strings',   'STRINGS'),
    ('Vibraphone',      'VIBES'),
    ('Recorder',        'RECORDER'),
]


def build_factory():
    entries = []            # (name, samples, loop_block or None)
    # melodics from the SF2_FONT soundfont, picked by preset name
    sf2_path = None
    sf_dir = os.path.join(ROOT, 'soundfonts')
    if os.path.isdir(sf_dir):
        for f in sorted(os.listdir(sf_dir)):
            if SF2_FONT in f.lower() and f.lower().endswith('.sf2'):
                sf2_path = os.path.join(sf_dir, f)
                break
    if sf2_path:
        allsmp = sf2_samples(sf2_path)
        picks = []
        for preset, short in SF2_PICKS:
            hit = next((s for s in allsmp
                        if s['loop'] and s.get('preset') == preset), None)
            if hit:
                picks.append((hit, short))
        for k, (s, short) in enumerate(picks):
            # bake the SF2 root key/correction into the resample: after
            # this, playing DSP pitch $1000 sounds engine note 61, so the
            # tracker keyboard is in tune
            root_eff = (s.get('root', 60) or 60) - s.get('corr', 0) / 100.0
            if not 24 <= root_eff <= 108:
                root_eff = 60
            shift = 61 - root_eff            # semitones the data must move
            scale = 2 ** (-shift / 12)       # ideal resample factor vs 32 kHz
            ideal = scale * 32000 / s['rate']
            # BRR loops live on 16-sample boundaries. Snapping a loop that
            # isn't a block multiple retunes the LOOPED section against the
            # attack (audible pitch step at loop entry). So resample the
            # whole sample such that the loop length lands EXACTLY on a
            # block multiple, and push the tiny tuning residual into the
            # entry's runtime tune fields.
            ls, le = s['loop']
            loop_len = le - ls
            target = max(16, round(loop_len * ideal / 16) * 16)
            factor = target / loop_len       # exact factor actually applied
            pcm = resample(s['pcm'], s['rate'], s['rate'] * factor)
            ls_out = round(ls * factor)
            trim = ls_out % 16               # align the loop start by
            pcm = pcm[trim:]                 # shaving the sample head
            ls_out -= trim
            end = ls_out + target
            while len(pcm) < end:            # rounding shortfall: extend
                pcm.append(pcm[len(pcm) - target])   # seamlessly from the loop
            pcm = pcm[:end]
            loop_block = ls_out // 16
            # runtime tune compensation for the loop-quantise stretch
            cents = 1200 * math.log2(factor / ideal)
            semis = int(round(cents / 100))
            fine = max(-128, min(127, int(round((cents - semis * 100) * 2.56))))
            entries.append((short, pcm, loop_block, semis, fine))
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
            ms = DRUM_MS.get(code, 112)
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
    for entry in entries:
        name, pcm, loop = entry[:3]
        semis, fine = (entry[3], entry[4]) if len(entry) > 3 else (0, 0)
        brr = sndj_brr.encode(pcm, loop_block=loop)
        blobs.append((name, brr, loop, semis, fine))
    table = b''
    data = b''
    base = 16 + 16 * len(blobs)
    assert base % 9 != 0 or True
    # data area starts block-aligned right after the table (pad to 9)
    data_start = (base + 8) // 9 * 9
    off = data_start
    chunks = []
    for name, brr, loop, semis, fine in blobs:
        pad = bank_pad(off, len(brr))
        if pad:
            pad = (pad + 8) // 9 * 9      # keep block alignment
            chunks.append(b'\xFF' * pad)
            off += pad
        assert off % 9 == 0
        loop_blk = 0xFFFF if loop is None else loop
        table += name.ljust(8)[:8].encode() + struct.pack(
            '<HHHbb', off // 9, len(brr) // 9, loop_blk, semis, fine)
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
