# SAVEFORMAT.md — the SNDJ1 save format

This file owns the byte layout of both the WRAM song block and the SRAM
image. It moves in the same commit as any change to either (CLAUDE.md
invariant #12).

## The WRAM song block (what gets saved)

One contiguous block at `$7E:2000..$7E:72FF` (`SB..SB_END`, $5300 bytes),
**layout v2**: fixed-size sections first, growable pools last, so future
phrase growth moves nothing else. Save/load is a straight copy.

| offset | size  | contents |
|--------|-------|----------|
| $0000  | $0400 | song grid: 8 tracks x 128 rows (chain id, $FF empty) |
| $0400  | $0400 | 64 instruments x 16 bytes (see below) |
| $0800  | $0800 | 32 tables x 64 bytes: 16 rows of two (command, value) pairs, run per tick by the instrument's TABLE field (record byte 12) |
| $1000  | $0100 | 16 grooves x 16 ticks-per-row entries |
| $1100  | $0100 | 8 wave banks x 32 samples |
| $1200  | $0400 | 16 kits x 16 slots x 4 bytes (sample, tune, vol, flags; a slot with vol 0 is empty) |
| $1600  | $0100 | song header: groove, transpose, magic $D7 at +2, echo block at +3 (EDL, feedback, EVOL L/R, EON mask, FIR preset id — $FF = custom), song name at +9 (8 ASCII, space padded — stamped into the slot entry on SAVE, taken from it on LOAD), MODE at +17 (0 SONG / 1 LIVE), tick BPM at +18 (80-255, 0 = 150), the song's 8 signed FIR taps at +19 |
| $1700  | $0C00 | 96 chains x 16 entries x 2 bytes (phrase, transpose) |
| $2300  | $3000 | 192 phrases x 16 rows x 4 bytes (note, instr, cmd, val) |

Instrument record (16 bytes): type (0 SMP, 1 KIT, 2 WAV, 3 NSE,
4 SLICE), sample, ADSR1 (low 7 bits), ADSR2, vol L, vol R, fine-tune
(signed 1/256 semitone, interpolated between pitch-table entries),
flags (bit 0 = EON echo send; bits 1-2 = the SMP LOOP override:
0 pool default / 1 force loop / 2 force one-shot; bits 4-7 = SLICES-1
for the SLICE type),
GRP span, GRP offsets x3, TABLE (byte 12, >= 32 = none), TBS (byte 13,
ticks per table row, 0 = note-sync), VIB (byte 14, vibrato speed/depth
nibbles), TRM (byte 15, tremolo speed/depth nibbles).

SLICE type reinterpretations: byte 1 = the blob (pool sample) sliced
into equal, block-aligned divisions; byte 2 = ATK nibble (low, the
shared ADSR position) + FADE nibble (high — the hardware sustain rate
the trigger synthesizes: 0 = ring/bleed, F = fastest cut); byte 9
(OFS 1's byte) = TUNE, signed whole semitones for the whole slice set.
Bytes 3 (ADSR2) and 8/10/11 (GRP) are unused by the SLICE trigger.

Cell conventions: note 0 = empty, 1-96 = C-0..B-7, 97 = OFF; instrument
$FF = none; command 0 = none, 1-26 = A-Z.

## ROM pool entry tune (bytes +14/+15)

Each 16-byte pool entry ends with a default tune: +14 signed whole
semitones, +15 signed fine (1/256 semitone). The engine sums this with
the instrument's FINE byte (record byte 6) at trigger time; kit slots
add it to their own semitone tune. Factory melodics bake their SF2 root
key into the resample and carry 0/0 here.

## SRAM image (32 KB at $70:0000) — SNDJ1 v2, variable packing

```
$0000  5   magic "SNDJ1"
$0005  1   format version (2)
$0006  1   reserved
$0007  1   device option: palette scheme
$0008  1   device option: CLONE (0 SLIM / 1 DEEP)
$0009  7   reserved
$0010  256 directory: 16 entries x 16 bytes
$0110  ... heap: RLE-packed songs, densely packed (~31.7 KB)
```

Directory entry (16 bytes):

| offset | size | contents |
|--------|------|----------|
| 0      | 1    | status: $FF empty, $A5 valid |
| 1      | 2    | heap offset (little endian) |
| 3      | 2    | packed size |
| 5      | 2    | CRC-16/CCITT of the packed bytes ($FFFF seed) |
| 7      | 1    | reserved |
| 8      | 8    | name (ASCII, space padded) |

Valid entries are packed (0..used-1) and the heap is dense: no holes.
Heap order may differ from entry order after overwrites. SAVE packs at
the free end, flips the entry (status byte last), then closes the old
block's hole by sliding everything above it down; CLEAR drops the
entry, slides the directory down one slot and closes the hole the same
way. A power cut mid-slide can tear at most the songs above the hole —
their CRCs catch it — and never touches songs below it. A save that
doesn't fit the remaining heap is refused (`FULL`).

## Save image (what actually gets packed)

The phrase pool interleaves `note,instr,cmd,val` per row and chains
interleave `phrase,transpose`, which defeats run-length coding (empty
rows are `00 FF ...`). The save image therefore stores both pools
**column-planar**:

```
image[$0000..$0BFF] = all note bytes   (phrase pool, stride 4)
image[$0C00..$17FF] = all instr bytes
image[$1800..$23FF] = all cmd bytes
image[$2400..$2FFF] = all val bytes
image[$3000..$35FF] = all chain phrase ids  (chain pool, stride 2)
image[$3600..$3BFF] = all chain transposes
image[$3C00..$52FF] = the rest of the block ($0000-$16FF), linear
```

An empty song packs to ~330 bytes this way. Both packers stage the image
in WRAM at `$7E:8000` before/after the RLE pass.

## RLE codec

Byte stream; unpacking stops after exactly $5300 output bytes.

- control `$00-$7F`: copy the next `c+1` bytes literally (1-128)
- control `$80-$FF`: repeat the next byte `c-$80+3` times (3-130)

Reference implementations: `src/save.asm` (65816 pack + unpack),
`tools/sndj_rle.py` (Python mirror, self-tested by `make test`), and the
Lua verifier inside `tools/checks/save.lua`, which unpacks the console-
packed SRAM bytes and compares them against a pre-save WRAM snapshot.

CRC-16/CCITT: polynomial $1021, initial value $FFFF, no reflection, no
final xor — over the packed bytes only.
