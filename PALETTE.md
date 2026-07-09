# snesdj palettes

The UI is drawn from a **palette scheme**: seven 15-bit BGR colours with
semantic roles, from which the engine builds CGRAM and the per-scanline
HDMA backdrop gradient at apply time. Eight factory schemes ship in the
ROM's marker-wrapped `SNPAL0` block (16 bytes each — see the layout
below), so tools can repaint a built ROM without a toolchain.

Select a scheme on **OPTIONS → PALETTE** (B-hold + left/right). The
choice applies instantly and persists in the cartridge save (reserved
SRAM header byte `$0007`).

## Semantic slots

| slot | role |
|------|------|
| bg | backdrop base (colour 0; the gradient modulates it per line) |
| text | normal cells |
| dim | rulers, empty cells, labels |
| accent | cursor and selections |
| hilite | playheads, meters, screen titles |
| grad top / grad bottom | the HDMA backdrop ramp (derived: bg towards black / bg towards text) |

These are the same roles as smsggdj/genmddj, so a scheme is conceptually
portable across the family.

## Factory schemes

Scheme 0 is the snesdj house style; 1–7 are the genmddj set carried
over (its Mega Drive nibble levels mapped through the MD DAC ramp), so
the family reads the same on a shelf of consoles.

| # | name | bg | text | notes |
|---|------|----|------|-------|
| 0 | SNES | deep blue-black | near-white | amber accent, cyan hilite (default) |
| 1 | BLK | black | white | the genmddj/smsggdj default |
| 2 | WHT | white | black | inverted, for daylight |
| 3 | KIDD | vivid blue | yellow | Alex Kidd |
| 4 | AMBR | dark maroon | amber | amber terminal |
| 5 | CYAN | navy | cyan | |
| 6 | PINK | purple | magenta | |
| 7 | MINT | dark teal | mint | |

Exact RGB values live in `tools/maketables.py` (`SCHEMES`) — edit there
and rebuild, or patch the `SNPAL0` block in a built ROM.

## ROM block (`SNPAL0`)

8 schemes × 16 bytes, immediately after the `SNPAL0` marker. Per
scheme, little-endian 15-bit BGR words:

```
+0  bg   +2 text   +4 dim   +6 accent   +8 hilite
+10 grad top   +12 grad bottom   +14 pad
```

`patcher.html` gains a palette tab against this block (planned); until
then `tools/sndj.js`'s `findMarker(rom, 'SNPAL0')` locates it for any
tool.
