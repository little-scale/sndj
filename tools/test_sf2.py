#!/usr/bin/env python3
"""Generate a tiny copyright-clean SF2 and Python reference fixture.

The Node test reads the same generated font and verifies that the browser and
Python pipelines produce byte-identical BRR, loop, and tuning results. Keeping
the fixture synthetic avoids making the test suite depend on bundled or local
third-party SoundFonts.
"""
import json
import math
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sndj_pool
import sndj_brr


def chunk(tag, body):
    return tag + struct.pack('<I', len(body)) + body + (b'\0' if len(body) & 1 else b'')


def fixed_name(name, size=20):
    return name.encode('ascii')[:size].ljust(size, b'\0')


def make_font(path):
    melodic = [round(math.sin(2 * math.pi * i / 32) * 18000) for i in range(160)]
    oneshot = [round((1 - i / 95) * math.sin(2 * math.pi * i / 11) * 16000)
               for i in range(96)]
    pcm = melodic + oneshot + [0] * 46
    smpl = struct.pack('<%dh' % len(pcm), *pcm)

    # One preset -> one instrument -> two sample zones.
    phdr = (fixed_name('Synthetic') + struct.pack('<HHHIII', 0, 0, 0, 0, 0, 0) +
            fixed_name('EOP') + struct.pack('<HHHIII', 0, 0, 1, 0, 0, 0))
    pbag = struct.pack('<HHHH', 0, 0, 1, 0)
    pgen = struct.pack('<HH', 41, 0)
    inst = fixed_name('Generated') + struct.pack('<H', 0) + \
        fixed_name('EOI') + struct.pack('<H', 2)
    ibag = struct.pack('<HHHHHH', 0, 0, 1, 0, 2, 0)
    igen = struct.pack('<HHHH', 53, 0, 53, 1)
    shdr = (
        fixed_name('Loop tone') + struct.pack('<IIIIIBbHH',
            0, len(melodic), 32, 128, 32000, 60, -7, 0, 1) +
        fixed_name('One shot') + struct.pack('<IIIIIBbHH',
            len(melodic), len(melodic) + len(oneshot),
            len(melodic), len(melodic), 22050, 64, 11, 0, 1) +
        fixed_name('EOS') + struct.pack('<IIIIIBbHH',
            len(melodic) + len(oneshot), len(melodic) + len(oneshot),
            0, 0, 32000, 60, 0, 0, 1)
    )
    pdta = b'pdta' + b''.join((
        chunk(b'phdr', phdr), chunk(b'pbag', pbag), chunk(b'pgen', pgen),
        chunk(b'inst', inst), chunk(b'ibag', ibag), chunk(b'igen', igen),
        chunk(b'shdr', shdr),
    ))
    body = b'sfbk' + chunk(b'LIST', b'sdta' + chunk(b'smpl', smpl)) + chunk(b'LIST', pdta)
    with open(path, 'wb') as f:
        f.write(b'RIFF' + struct.pack('<I', len(body)) + body)


def melodic_case(s):
    root_eff = (s.get('root', 60) or 60) - s.get('corr', 0) / 100.0
    shift = 72 - root_eff
    ideal = 2 ** (-shift / 12) * 32000 / s['rate']
    ls, le = s['loop']
    target = max(16, round((le - ls) * ideal / 16) * 16)
    factor = target / (le - ls)
    pcm = sndj_pool.resample(s['pcm'], s['rate'], s['rate'] * factor)
    ls_out = round(ls * factor)
    cut = ls_out % 16
    pcm = pcm[cut:]
    ls_out -= cut
    end = ls_out + target
    while len(pcm) < end:
        pcm.append(pcm[len(pcm) - target])
    cents = 1200 * math.log2(factor / ideal)
    semis = int(round(cents / 100))
    fine = max(-128, min(127, int(round((cents - semis * 100) * 2.56))))
    loop = ls_out // 16
    return {'sample': s['name'], 'kind': 'melodic', 'arg': 0,
            'loopBlock': loop, 'tuneSemis': semis, 'tuneFine': fine,
            'brr': list(sndj_brr.encode(pcm[:end], loop_block=loop))}


def oneshot_case(s):
    pcm = sndj_pool.prep_oneshot(s['pcm'], s['rate'], 80)
    if len(pcm) < 16:
        pcm = [0] * 16
    return {'sample': s['name'], 'kind': 'oneshot', 'arg': 80,
            'loopBlock': None, 'tuneSemis': 0, 'tuneFine': 0,
            'brr': list(sndj_brr.encode(pcm, loop_block=None))}


def main():
    fixture_path = os.path.abspath(sys.argv[1])
    font_path = os.path.splitext(fixture_path)[0] + '.sf2'
    make_font(font_path)
    samples = sndj_pool.sf2_samples(font_path)
    cases = [melodic_case(samples[0]), oneshot_case(samples[1])]
    with open(fixture_path, 'w') as f:
        json.dump({'font': font_path, 'cases': cases}, f)
    print(f'test_sf2: generated font + {len(cases)} cases -> {fixture_path}')


if __name__ == '__main__':
    main()
