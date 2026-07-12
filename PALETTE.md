# sndj palettes

The UI is drawn from a **two-colour palette scheme** (background and
text), genmddj-style: cursors, playheads and titles render as palette
*negatives* (an inverted copy of the glyph set). Rulers, empty cells and
other formerly dimmed elements use the full text colour: no third or
derived shade is emitted. Eight factory schemes ship in the ROM's marker-wrapped
`SNPAL0` block (16 bytes each — see the layout below), so tools can
repaint a built ROM without a toolchain.

Select a scheme on **OPTIONS → PALETTE** (B-hold + left/right). The
choice applies instantly and persists in the cartridge save (reserved
SRAM header byte `$0007`).

## Rendering roles (derived from the two colours)

| role | rendering |
|------|-----------|
| bg | backdrop (colour 0) |
| text | normal cells |
| secondary text | rulers, empty cells — full text colour |
| cursor / selection | palette negative (inverted glyphs) |
| playheads, titles, meters | palette negative |

The strict two-colour output is deliberate: composite and RF displays can
erase a mathematically distinct midpoint shade even when it looks clear over
RGB or in an emulator. Semantic hierarchy comes from position and inversion,
not reduced contrast.

## Factory schemes

The genmddj set, same order and indices (its Mega Drive nibble levels
mapped through the MD DAC ramp), so the family reads the same on a
shelf of consoles.

| # | name | bg | text | notes |
|---|------|----|------|-------|
| 0 | BLK | black | white | the family default |
| 1 | WHT | white | black | inverted, for daylight |
| 2 | KIDD | vivid blue | yellow | Alex Kidd |
| 3 | AMBR | dark maroon | amber | amber terminal |
| 4 | CYAN | navy | cyan | |
| 5 | PINK | purple | magenta | |
| 6 | NEON | light blue | neon pink | |
| 7 | MINT | dark teal | mint | |

Exact RGB values live in `tools/maketables.py` (`SCHEMES`) — edit there
and rebuild, or patch the `SNPAL0` block in a built ROM.

## ROM block (`SNPAL0`)

8 schemes × 16 bytes, immediately after the `SNPAL0` marker. Per
scheme, little-endian 15-bit BGR words:

```
+0 bg   +2 text   +4..15 pad
```

`patcher.html` gains a palette tab against this block (planned); until
then `user-tools/sndj.js`'s `findMarker(rom, 'SNPAL0')` locates it for any
tool.
