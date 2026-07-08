#!/usr/bin/env python3
"""maketables.py — generate ROM data tables for snesdj.

Emits into the build directory:
  pal.bin      — 512-byte CGRAM image (factory palette, semantic slots)
  gradient.bin — HDMA table for the per-scanline backdrop gradient
                 (transfer mode 3 -> $2121: sets CGRAM addr 0, writes colour)

The factory palette follows the sibling semantic slots: bg / text / accent /
highlight, plus a two-colour vertical gradient pair (PALETTE.md will own the
full factory set; this is palette 0, "FACTORY").
"""
import sys


def bgr15(r, g, b):
    """r,g,b 0-255 -> SNES 15-bit BGR."""
    return ((b >> 3) << 10) | ((g >> 3) << 5) | (r >> 3)


# --- Factory palette (semantic slots) --------------------------------------
BG        = (16, 18, 40)      # deep blue-black
TEXT      = (222, 226, 232)   # near-white
DIM       = (96, 104, 136)    # dimmed text / rulers
ACCENT    = (255, 176, 32)    # amber accent (cursor, highlights)
HILITE    = (64, 208, 200)    # cyan highlight (playhead, meters)
GRAD_TOP  = (10, 10, 28)
GRAD_BOT  = (44, 26, 64)

def cgram():
    pal = [0] * 256
    # colour 0: backdrop base (gradient HDMA overrides per line)
    pal[0] = bgr15(*BG)
    # BG3 palette 0: normal text     (0=transp, 1=dim, 2=text, 3=text)
    pal[1] = bgr15(*DIM)
    pal[2] = bgr15(*TEXT)
    pal[3] = bgr15(*TEXT)
    # BG3 palette 1: accent text     (cursor row / selected)
    pal[5] = bgr15(*DIM)
    pal[6] = bgr15(*ACCENT)
    pal[7] = bgr15(*ACCENT)
    # BG3 palette 2: highlight text  (playhead / meters)
    pal[9]  = bgr15(*DIM)
    pal[10] = bgr15(*HILITE)
    pal[11] = bgr15(*HILITE)
    # BG3 palette 3: dim text        (empty cells, rulers)
    pal[13] = bgr15(*DIM)
    pal[14] = bgr15(*DIM)
    pal[15] = bgr15(*DIM)
    out = bytearray()
    for c in pal:
        out += bytes((c & 0xFF, c >> 8))
    return bytes(out)


def gradient(lines=224):
    """HDMA table: per-line CGRAM colour 0 write (mode 3 -> $2121)."""
    out = bytearray()
    for y in range(lines):
        t = y / (lines - 1)
        r = round(GRAD_TOP[0] + (GRAD_BOT[0] - GRAD_TOP[0]) * t)
        g = round(GRAD_TOP[1] + (GRAD_BOT[1] - GRAD_TOP[1]) * t)
        b = round(GRAD_TOP[2] + (GRAD_BOT[2] - GRAD_TOP[2]) * t)
        c = bgr15(r, g, b)
        # entry: [count=1] then mode-3 payload -> $2121,$2121,$2122,$2122
        # (CGRAM addr 0 written twice, then colour low/high)
        out += bytes((1, 0, 0, c & 0xFF, c >> 8))
    out.append(0)  # end of table
    return bytes(out)


def main(build_dir):
    with open(f'{build_dir}/pal.bin', 'wb') as f:
        f.write(cgram())
    grad = gradient()
    with open(f'{build_dir}/gradient.bin', 'wb') as f:
        f.write(grad)
    print(f"maketables: pal.bin (512 bytes), gradient.bin ({len(grad)} bytes)")


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'build')
