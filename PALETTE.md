# snesdj palettes

The UI is drawn from a **palette scheme**: five 15-bit BGR colours with
semantic roles (solid backdrop — no gradient), from which the engine
builds CGRAM at apply time. Eight factory schemes ship in the ROM's
marker-wrapped `SNPAL0` block (16 bytes each — see the layout below),
so tools can repaint a built ROM without a toolchain.

Select a scheme on **OPTIONS → PALETTE** (B-hold + left/right). The
choice applies instantly and persists in the cartridge save (reserved
SRAM header byte `$0007`).

## Semantic slots

| slot | role |
|------|------|
| bg | backdrop (colour 0) |
| text | normal cells |
| dim | rulers, empty cells, labels |
| accent | cursor and selections |
| hilite | playheads, meters, screen titles |

These are the same roles as smsggdj/genmddj, so a scheme is conceptually
portable across the family.

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
+0 bg   +2 text   +4 dim   +6 accent   +8 hilite   +10..15 pad
```

`patcher.html` gains a palette tab against this block (planned); until
then `tools/sndj.js`'s `findMarker(rom, 'SNPAL0')` locates it for any
tool.
