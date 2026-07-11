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
resampled to 32 kHz. If samples/factory.sndjfact exists (the committed
factory, exported by patcher.html) its pool section is used verbatim;
a bare samples/pool.bin also works.
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
    # drums live at 8 kHz (factory kit slots are tuned -24): quarter ARAM
    s = resample(trim_tail(samples), rate, 8000)
    s = s[:int(8 * max_ms)]
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
DRUM_KITS = []                       # sample-folder kits retired for now
DRUM_MS = {'BD': 200, 'SD': 170, 'CP': 170, 'CY': 195, 'HO': 160}  # else 112
SF2_FONT = 'mario_paint'    # melodics come from this font (drums stay Seb's)
MP_FONT = 'mario_paint'
SMW_FONT = 'super_mario_world'

# pitched sounds, in pool order. The first four are the SMW classics
# (tracks 1-5 default to pool 0-4), then three Mario Paint icons, then
# the option-1 songbook fill from both fonts.
MELODICS = [                # (font, preset, pool name[, semitone trim])
    # trims correct wrong font root keys, by ear
    (SMW_FONT, 'Xylophone',       'SW XYLO'),
    (SMW_FONT, 'Steel Drums',     'SW STEEL'),
    (SMW_FONT, 'E. Piano',        'SW EPIAN'),
    (SMW_FONT, 'Slap Bass',       'SW SLAP', 1),
    (MP_FONT,  'Square',          'MPSQUARE'),
    (MP_FONT,  'Recorder',        'MP RECRD'),
    (MP_FONT,  'Acoustic Guitar', 'MP GUITR'),
    (SMW_FONT, 'Trombone',        'SW TBONE'),
    (SMW_FONT, 'Trumpet',         'SW TRMPT'),
    (SMW_FONT, 'Violin 1',        'SW STRNG'),
    (SMW_FONT, 'Nylon Guitar',    'SW NYLON'),
    (SMW_FONT, 'Saxophone',       'SW SAX'),
    (MP_FONT,  'Organ 1',         'MP ORGAN'),
    (MP_FONT,  'Vibraphone',      'MP VIBES'),
    (MP_FONT,  'Glockenspiel',    'MP GLOCK'),
    (MP_FONT,  'Acoustic Bass',   'MP ABASS'),
]
SMW_KIT = [                 # kit 0: SMW percussion, by SAMPLE name
    ('kick-1',       'SW KICK', 160),
    ('snare-1',      'SW SNARE', 200),
    ('snare2-1',     'SW SNAR2', 200),
    ('hisnare-1',    'SW HISNR', 160),
    ('hihat-1',      'SW HAT', 160),
    ('bongo-1',      'SW BONGO', 160),
    ('dewL',         'SW DEW', 160),
    ('orchestrahit', 'SW ORCH', 250),
    ('2R',           'SW BEEP', 160),
    ('dddde-1R',     'SW ROLL', 250),   # the riding-yoshi drum roll
]
MP_KIT = [                  # kit 1: Mario Paint percussion (by preset)
    ('Kick',        'MP KICK', 160),
    ('Snare',       'MP SNARE', 160),
    ('Snap',        'MP SNAP', 160),
    ('Woodblock 1', 'MP WOOD1', 160),
    ('Woodblock 2', 'MP WOOD2', 160),
    ('Pop 1',       'MP POP', 160),
    ('Dog',         'MP DOG', 160),
    ('Cat',         'MP CAT', 150),
    ('Pig',         'MP PIG', 160),
    ('Bird',        'MP BIRD', 160),
    ('Yoshi',       'MP YOSHI', 160),
    ('Undo Dog',    'MP UNDO', 160),
]
TOYBOX = [                  # kit 2: the Mario Paint toybox (by preset)
    ('Bongo 1',       'MPBONGO1', 200),
    ('Bongo 2',       'MPBONGO2', 200),
    ('Tom',           'MP TOM', 200),
    ('Splash',        'MPSPLASH', 200),
    ('Slide Whistle', 'MP SLIDE', 250),
    ('Glass Shatter', 'MP GLASS', 200),
    ('Clown Honk',    'MP HONK', 160),
    ('Baby',          'MP BABY', 250),
    ('Voice 1',       'MPVOICE1', 200),
    ('Cheering',      'MP CHEER', 250),
]


def build_factory():
    entries = []
    sf_dir = os.path.join(ROOT, 'soundfonts')

    def find_font(tag):
        if not os.path.isdir(sf_dir):
            return None
        for f in sorted(os.listdir(sf_dir)):
            if tag in f.lower() and f.lower().endswith('.sf2'):
                return os.path.join(sf_dir, f)
        return None

    fonts = {}
    for tag in {MP_FONT, SMW_FONT}:
        path = find_font(tag)
        fonts[tag] = sf2_samples(path) if path else []

    # pitched sounds: exact-loop resample (see below), tune residual in
    # the entry fields
    for pick in MELODICS:
        font, preset, short = pick[:3]
        trim = pick[3] if len(pick) > 3 else 0
        s = next((x for x in fonts[font]
                  if x['loop'] and x.get('preset') == preset), None)
        if s is None:
            continue
        root_eff = (s.get('root', 60) or 60) - s.get('corr', 0) / 100.0
        if not 24 <= root_eff <= 108:
            root_eff = 60
        shift = 61 - root_eff + trim
        scale = 2 ** (-shift / 12)
        ideal = scale * 32000 / s['rate']
        ls, le = s['loop']
        loop_len = le - ls
        target = max(16, round(loop_len * ideal / 16) * 16)
        factor = target / loop_len
        pcm = resample(s['pcm'], s['rate'], s['rate'] * factor)
        ls_out = round(ls * factor)
        trim = ls_out % 16
        pcm = pcm[trim:]
        ls_out -= trim
        end = ls_out + target
        while len(pcm) < end:
            pcm.append(pcm[len(pcm) - target])
        pcm = pcm[:end]
        loop_block = ls_out // 16
        cents = 1200 * math.log2(factor / ideal)
        semis = int(round(cents / 100))
        fine = max(-128, min(127, int(round((cents - semis * 100) * 2.56))))
        entries.append((short, pcm, loop_block, semis, fine))

    # kits: 8 kHz one-shots (kit slots seed tune -24). SMW picks go by
    # SAMPLE name (its Percussion preset shares one name); their SF2
    # loop flags are whole-sample sustains, so loops are ignored.
    for sname, short, cap in SMW_KIT:
        s = next((x for x in fonts[SMW_FONT] if x['name'] == sname), None)
        if s is None:
            continue
        pcm = prep_oneshot(s['pcm'], s['rate'], cap)
        entries.append((short, pcm if len(pcm) >= 16 else [0] * 16, None))
    for kit in (MP_KIT, TOYBOX):
        for preset, short, cap in kit:
            s = next((x for x in fonts[MP_FONT]
                      if x.get('preset') == preset), None)
            if s is None:
                continue
            pcm = prep_oneshot(s['pcm'], s['rate'], cap)
            entries.append((short, pcm if len(pcm) >= 16 else [0] * 16, None))
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


def factory_pool():
    """the pool section of the committed .sndjfact, if present"""
    fact = os.path.join(ROOT, 'samples', 'factory.sndjfact')
    if not os.path.exists(fact):
        return None
    d = open(fact, 'rb').read()
    assert d[:8] == b'SNDJFACT' and d[8] in (1, 2, 3, 4), 'factory.sndjfact: bad magic'
    plen = d[12] | (d[13] << 8) | (d[14] << 16)
    return d[16:16 + plen]


def main(out_path):
    data = factory_pool()
    if data is not None:
        assert data[:8] == b'SNDJPOOL', 'factory pool: bad magic'
        print(f'sndj_pool: pool from samples/factory.sndjfact ({len(data)} bytes)')
    elif os.path.exists(os.path.join(ROOT, 'samples', 'pool.bin')):
        data = open(os.path.join(ROOT, 'samples', 'pool.bin'), 'rb').read()
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
