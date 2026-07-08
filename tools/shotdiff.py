#!/usr/bin/env python3
"""shotdiff.py — compare a screenshot to its golden, ignoring masked rows.

The splash shows the git build stamp, which changes every commit; its text
row is masked out of the comparison. Pure-python PNG decode (zlib), no PIL.

Usage: shotdiff.py <shot.png> <golden.png> [mask_y0 mask_y1]
"""
import struct
import sys
import zlib


def read_png(path):
    data = open(path, 'rb').read()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', path
    pos, idat, w, h, bpp = 8, b'', 0, 0, 3
    while pos < len(data):
        ln, typ = struct.unpack('>I4s', data[pos:pos + 8])
        chunk = data[pos + 8:pos + 8 + ln]
        if typ == b'IHDR':
            w, h, depth, ctype = struct.unpack('>IIBB', chunk[:10])
            assert depth == 8 and ctype in (2, 6), "unsupported PNG"
            bpp = 3 if ctype == 2 else 4
        elif typ == b'IDAT':
            idat += chunk
        pos += 12 + ln
    raw = zlib.decompress(idat)
    stride = w * bpp
    rows = []
    prev = bytearray(stride)
    p = 0
    for _y in range(h):
        f = raw[p]
        line = bytearray(raw[p + 1:p + 1 + stride])
        p += 1 + stride
        if f == 1:
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 0xFF
        elif f == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif f == 3:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + (a + prev[i]) // 2) & 0xFF
        elif f == 4:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                pp = a + b - c
                pa, pb, pc = abs(pp - a), abs(pp - b), abs(pp - c)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        rows.append(bytes(line))
        prev = line
    return w, h, rows


def main():
    shot, golden = sys.argv[1], sys.argv[2]
    my0 = int(sys.argv[3]) if len(sys.argv) > 3 else -1
    my1 = int(sys.argv[4]) if len(sys.argv) > 4 else -1
    w1, h1, r1 = read_png(shot)
    w2, h2, r2 = read_png(golden)
    if (w1, h1) != (w2, h2):
        print(f"shotdiff: size mismatch {w1}x{h1} vs {w2}x{h2}")
        return 1
    bad = 0
    for y in range(h1):
        if my0 <= y < my1:
            continue
        if r1[y] != r2[y]:
            bad += 1
    if bad:
        print(f"shotdiff: {bad} differing rows: {shot} vs {golden}")
        return 1
    print(f"shotdiff: match ({shot})")
    return 0


if __name__ == '__main__':
    sys.exit(main())
