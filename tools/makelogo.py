#!/usr/bin/env python3
"""makelogo.py — render art/sndj-logo.png to BG3 2bpp tiles.

Pure-python PNG decode (non-interlaced RGBA/RGB/greyscale), nearest
downscale to LOGO_W x LOGO_H tiles, threshold to ink (colour 3, so the
logo draws in the palette's text colour). Emits:
  build/logo.bin  — 2bpp tiles, row-major
  build/logo.inc  — LOGO_TW / LOGO_TH / LOGO_NTILES defines
"""
import os
import struct
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOGO_TW = 22            # tiles wide (176 px)
LOGO_TH = 10            # tiles tall (80 px)


def read_png(path):
    data = open(path, 'rb').read()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', 'not a PNG'
    pos = 8
    w = h = bitdepth = ctype = None
    idat = b''
    while pos < len(data):
        ln = struct.unpack('>I', data[pos:pos + 4])[0]
        typ = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + ln]
        if typ == b'IHDR':
            w, h, bitdepth, ctype, _, _, interlace = struct.unpack('>IIBBBBB', body)
            assert bitdepth == 8 and interlace == 0, 'need 8-bit non-interlaced'
        elif typ == b'IDAT':
            idat += body
        pos += 12 + ln
    raw = zlib.decompress(idat)
    ch = {0: 1, 2: 3, 4: 2, 6: 4}[ctype]
    stride = w * ch
    px = bytearray(w * h * ch)
    prev = bytearray(stride)
    p = 0
    for y in range(h):
        f = raw[p]
        line = bytearray(raw[p + 1:p + 1 + stride])
        p += 1 + stride
        for i in range(stride):
            a = line[i - ch] if i >= ch else 0
            b = prev[i]
            c = prev[i - ch] if i >= ch else 0
            if f == 1:
                line[i] = (line[i] + a) & 0xFF
            elif f == 2:
                line[i] = (line[i] + b) & 0xFF
            elif f == 3:
                line[i] = (line[i] + (a + b) // 2) & 0xFF
            elif f == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        px[y * stride:(y + 1) * stride] = line
        prev = line

    def ink(x, y):
        o = (y * w + x) * ch
        if ctype == 6:
            r, g, b, a = px[o:o + 4]
            return a > 128 and (r + g + b) < 384
        if ctype == 2:
            r, g, b = px[o:o + 3]
            return (r + g + b) < 384
        if ctype == 4:
            return px[o + 1] > 128 and px[o] < 128
        return px[o] < 128
    return w, h, ink


def main(out_bin, out_inc):
    w, h, ink = read_png(os.path.join(ROOT, 'art', 'sndj-logo.png'))
    tw, th = LOGO_TW * 8, LOGO_TH * 8
    # nearest-neighbour sample, preserving aspect inside the tile box
    scale = min(tw / w, th / h)
    ow, oh = int(w * scale), int(h * scale)
    ox, oy = (tw - ow) // 2, (th - oh) // 2
    grid = [[False] * tw for _ in range(th)]
    for y in range(oh):
        sy = min(h - 1, int(y / scale))
        for x in range(ow):
            sx = min(w - 1, int(x / scale))
            grid[oy + y][ox + x] = ink(sx, sy)
    out = bytearray()
    for ty in range(LOGO_TH):
        for tx in range(LOGO_TW):
            for r in range(8):
                b = 0
                for i in range(8):
                    if grid[ty * 8 + r][tx * 8 + i]:
                        b |= 0x80 >> i
                out += bytes((b, b))    # colour 3 = the palette text colour
    with open(out_bin, 'wb') as f:
        f.write(out)
    with open(out_inc, 'w') as f:
        f.write(f".DEFINE LOGO_TW {LOGO_TW}\n.DEFINE LOGO_TH {LOGO_TH}\n"
                f".DEFINE LOGO_NTILES {LOGO_TW * LOGO_TH}\n")
    print(f"makelogo: {w}x{h} -> {LOGO_TW}x{LOGO_TH} tiles ({len(out)} bytes)")


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
