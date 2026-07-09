#!/usr/bin/env python3
"""test_sf2.py — emit fixture JSON for the JS SF2 mirror test.

Preps one melodic and one one-shot from each font with the exact
factory pipeline and dumps entries (pcm via BRR bytes, loop, tune)."""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sndj_pool
import sndj_brr

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CASES = [
    ('mario_paint', 'Acoustic Guitar', 'melodic', 0),
    ('mario_paint', 'Recorder', 'melodic', 0),
    ('super_mario_world', 'Slap Bass', 'melodic', 1),
    ('mario_paint', 'Yoshi', 'oneshot', 160),
    ('super_mario_world', None, 'oneshot-name:orchestrahit', 250),
]


def find_font(tag):
    d = os.path.join(ROOT, 'soundfonts')
    for f in sorted(os.listdir(d)):
        if tag in f.lower() and f.lower().endswith('.sf2'):
            return os.path.join(d, f)
    return None


def main():
    out = []
    for tag, preset, kind, arg in CASES:
        path = find_font(tag)
        smp = sndj_pool.sf2_samples(path)
        if kind.startswith('oneshot-name:'):
            name = kind.split(':')[1]
            s = next(x for x in smp if x['name'] == name)
            kind = 'oneshot'
        elif kind == 'oneshot':
            s = next(x for x in smp if x.get('preset') == preset)
        else:
            s = next(x for x in smp if x['loop'] and x.get('preset') == preset)
        if kind == 'melodic':
            root_eff = (s.get('root', 60) or 60) - s.get('corr', 0) / 100.0
            if not 24 <= root_eff <= 108:
                root_eff = 60
            shift = 61 - root_eff + arg
            scale = 2 ** (-shift / 12)
            ideal = scale * 32000 / s['rate']
            ls, le = s['loop']
            loop_len = le - ls
            target = max(16, round(loop_len * ideal / 16) * 16)
            factor = target / loop_len
            pcm = sndj_pool.resample(s['pcm'], s['rate'], s['rate'] * factor)
            ls_out = round(ls * factor)
            cut = ls_out % 16
            pcm = pcm[cut:]
            ls_out -= cut
            end = ls_out + target
            while len(pcm) < end:
                pcm.append(pcm[len(pcm) - target])
            pcm = pcm[:end]
            import math
            cents = 1200 * math.log2(factor / ideal)
            semis = int(round(cents / 100))
            fine = max(-128, min(127, int(round((cents - semis * 100) * 2.56))))
            brr = sndj_brr.encode(pcm, loop_block=ls_out // 16)
            out.append({'tag': tag, 'preset': preset or s['name'], 'kind': kind,
                        'arg': arg, 'loopBlock': ls_out // 16,
                        'tuneSemis': semis, 'tuneFine': fine,
                        'brr': list(brr)})
        else:
            pcm = sndj_pool.prep_oneshot(s['pcm'], s['rate'], arg)
            if len(pcm) < 16:
                pcm = [0] * 16
            brr = sndj_brr.encode(pcm, loop_block=None)
            out.append({'tag': tag, 'preset': preset or s['name'], 'kind': kind,
                        'arg': arg, 'loopBlock': None,
                        'tuneSemis': 0, 'tuneFine': 0,
                        'brr': list(brr)})
    json.dump(out, open(sys.argv[1], 'w'))
    print(f"test_sf2: fixture with {len(out)} cases -> {sys.argv[1]}")


if __name__ == '__main__':
    main()
