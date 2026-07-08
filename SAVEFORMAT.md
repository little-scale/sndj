# SAVEFORMAT.md — the SNDJ1 save format

This file owns the byte layout of both the WRAM song block and the SRAM
image. It moves in the same commit as any change to either (CLAUDE.md
invariant #12).

## The WRAM song block (what gets saved)

One contiguous block at `$7E:2000..$7E:57FF` (`SB..SB_END`, $3800 bytes).
Offsets are frozen; save/load is a straight copy of this block.

| offset | size  | contents |
|--------|-------|----------|
| $0000  | $2000 | 128 phrases x 16 rows x 4 bytes (note, instr, cmd, val) |
| $2000  | $0800 | 64 chains x 16 entries x 2 bytes (phrase, transpose) |
| $2800  | $0400 | song grid: 8 tracks x 128 rows (chain id, $FF empty) |
| $2C00  | $0200 | 32 instruments x 16 bytes (see below) |
| $2E00  | $0800 | 32 tables x 64 bytes (reserved until tables land) |
| $3600  | $0080 | 8 grooves x 16 ticks-per-row entries |
| $3680  | $0100 | 8 wave banks x 32 samples (reserved until WAVE lands) |
| $3780  | $0080 | song header: groove, transpose, magic $D7 at +2, echo block at +3 (EDL, feedback, EVOL L/R, EON mask, FIR preset) |

Instrument record (16 bytes): type, sample, ADSR1 (low 7 bits), ADSR2,
vol L, vol R, fine-tune, flags, GRP span, GRP offsets x3, reserved x4.

Cell conventions: note 0 = empty, 1-96 = C-0..B-7, 97 = OFF; instrument
$FF = none; command 0 = none, 1-26 = A-Z.

## SRAM image (32 KB at $70:0000)

```
$0000  5   magic "SNDJ1"
$0005  1   format version (1)
$0006  1   free-region hint (recomputed at boot if wrong)
$0007  9   reserved
$0010  64  slot table: 4 entries x 16 bytes
$0050  176 reserved
$0100  5 x $1880 data regions (0..4)
```

Slot table entry (16 bytes):

| offset | size | contents |
|--------|------|----------|
| 0      | 1    | status: $FF empty, $A5 valid |
| 1      | 1    | data region index (0-4) |
| 2      | 2    | packed size (little endian) |
| 4      | 2    | CRC-16/CCITT of the packed bytes ($FFFF seed) |
| 6      | 8    | name (ASCII, space padded) |
| 14     | 2    | reserved |

**Journalling:** 4 logical slots share 5 physical regions; at least one
region is always unreferenced. A save packs into that free region first
and flips the table entry (status byte last) only after the write
completed and fit. A power cut mid-write never touches the previous good
save. (The 16-byte entry flip itself is the only unprotected window; the
CRC catches a torn entry.)

A save that packs larger than a region ($1880) is refused — the UI shows
`FULL` and SRAM is untouched.

## Save image (what actually gets packed)

The phrase pool interleaves `note,instr,cmd,val` per row, which defeats
run-length coding (empty rows are `00 FF 00 00`). The save image therefore
stores the phrase pool **column-planar**:

```
image[$0000..$07FF] = all note bytes   (block offset 0, 4, 8, ...)
image[$0800..$0FFF] = all instr bytes  (offset 1, 5, 9, ...)
image[$1000..$17FF] = all cmd bytes
image[$1800..$1FFF] = all val bytes
image[$2000..$37FF] = the rest of the block, linear
```

An empty song packs to well under 300 bytes this way. Both packers stage
the image in WRAM at `$7E:6000` before/after the RLE pass.

## RLE codec

Byte stream; unpacking stops after exactly $3800 output bytes.

- control `$00-$7F`: copy the next `c+1` bytes literally (1-128)
- control `$80-$FF`: repeat the next byte `c-$80+3` times (3-130)

Reference implementations: `src/save.asm` (65816 pack + unpack),
`tools/sndj_rle.py` (Python mirror, self-tested by `make test`), and the
Lua verifier inside `tools/checks/save.lua`, which unpacks the console-
packed SRAM bytes and compares them against a pre-save WRAM snapshot.

CRC-16/CCITT: polynomial $1021, initial value $FFFF, no reflection, no
final xor — over the packed bytes only.
