# sndj

<p align="center"><img src="art/sndj-logo.png" alt="sndj"></p>

An LSDJ-inspired music tracker for the **Super Nintendo / Super Famicom**,
written in 65816 + SPC700 assembly. The third sibling of
[smsggdj](https://github.com/little-scale/smsggdj) (SMS/Game Gear) and
[genmddj](https://github.com/little-scale/genmddj) (Mega Drive): same data
model, same control grammar, same screen map — built around what only the
S-DSP can do: BRR samples through Gaussian interpolation, a hardware echo
with an 8-tap FIR filter, per-voice hardware envelopes, drawn wavetables,
and 8 full-citizen voices.

> **Releases:** grab the latest ROM from
> [Releases](../../releases/latest) — flash it to an FXPak/SD2SNES or
> open it in Mesen 2 / ares / bsnes.

## Status

Milestones **M1–M14** of the plan (see CLAUDE.md §19) are built on the
console side — sync and MIDI takeover pass their emulated gates and
await real-hardware bring-up. What works today:

- **8-track sequencer** — phrases (16 rows), chains, 128-row song grid,
  per-entry transpose; groove-driven timing clocked by the APU's own
  crystal (tempo and pitch are region-free by construction)
- **All thirteen screens** — SONG, CHAIN, PHRASE, INSTR, TABLE, WAVE,
  KIT, GROOVE, ECHO, FIR, FILES, PROJECT, OPTIONS (plus the LIVE view)
  on the sibling 2-D map (A+d-pad), with the shared B-grammar
  everywhere and play indicators on every playing surface
- **Six instrument types** — sample (SMP), kit (KIT), drawn wavetable
  (WAV), noise (NSE), **SLICE** (chop any pool sample into up to 16
  parts for free — the note picks the slice) and **KARP** (Karplus-
  Strong on the echo loop: the room becomes a plucked string, a
  technique no commercial SNES soundtrack ever shipped); hardware
  ADSR, GRP chord spans, per-instrument VIB/TRM and loop overrides.
  The factory boots 12 instruments and audio RAM only holds what
  songs reference — the rest of the pool loads on demand, with the
  live RAM/FREE balance on the ECHO screen
- **The complete 24-command set** — one executor shared by phrases and
  tables (summary below)
- **Echo & FIR** — the SNES's room as an instrument: delay with live
  ARAM cost, feedback, per-voice sends, 8 patchable FIR curves;
  reconfiguration runs an erratum-safe driver sequence
- **Sync & MIDI (console side)** — OPTIONS → SYNC: **IN** follows a
  sibling master (1 clock/row), **IN24** follows the Ableton Link
  bridge (no reflash), **PULSE** drives Volca/PO gear, and **MIDI**
  turns sndj into an 8-voice sample module (channels 1–8 → V1–V8,
  velocity, program change, pitch bend, CC 7/10/91/74). OUT is
  reserved pending the cross-sibling wiring decision
- **Save/load** — 16 variable-packed, journalled songs in 32 KB SRAM
  (SNDJ1 v2); a power cut can't eat the previous good save
- **LIVE mode** — quantised chain launching, mute/solo, ENVX meters
- **Browser tools** — zero-toolchain, fully local: `user-tools/
  patcher.html` is a tabbed ROM workshop (sample pool with SoundFont
  drag-import and bit-exact BRR audition, drum-kit builder, boot
  instruments, FIR designer with live response plot, palettes, ROM +
  audio-RAM budget meters); `user-tools/savetool.html` manages cart
  saves and `.sndj` song files (CLI twin: `tools/savetool.py`). Both
  import `user-tools/sndj.js` — the shared library with a
  sample-accurate S-DSP model and a BRR codec byte-matched to the
  Python reference

Still to come: hardware verification of sync/MIDI (M12/M14), the sync
OUT master, the JS reference sequencer with Ableton/WAV/.spc export
(M15), release (M16).

## Controls

The sibling grammar: **the button already held selects what the next
press means** — no simultaneous-press timing windows.

| Input | Does |
|-------|------|
| **d-pad** | move the cursor |
| **B** | tap = insert / audition · hold + d-pad = nudge · double-tap = paste / mint / clone · hold + **A** = cut |
| **Y** (hold) | + ←/→ channel · + ↑/↓ page · + B block select |
| **A** (hold) | + d-pad navigate the screen map · **A+B** contextual play / stop |
| **Start** | play / stop the song |
| **L / R** | channel − / + |
| **Select** | jump to LIVE and back |
| **X** (hold) | + ↑/↓ mute · + ←/→ solo (SONG/LIVE) |

## Row commands

24 letters, the same grammar in phrases and tables — `MANUAL.md` has
the full reference:

> **A** arpeggio · **B** wave bank · **C** chord fan · **D** delay ·
> **E** echo send · **F** fine tune · **G** groove pair · **H** hop ·
> **I** play-count mask · **J** pass-transpose · **K** kill ·
> **L** slide · **M** master volume · **N** noise clock · **P** pan ·
> **Q** GAIN override · **R** retrig · **S** sweep · **T** tempo ·
> **U** surround · **V** vibrato override · **X** volume/accent ·
> **Y** FIR preset · **Z** pitch-mod

## Building

Requires WLA-DX (`brew install wla-dx`), Python 3, Node, and
[Mesen 2](https://github.com/SourMesen/Mesen2) for the verification loop.

```
make            # build/sndj.sfc (+ git-stamped dev copy)
make run        # launch in Mesen 2
make check      # emulator-in-the-loop assertions — the ground truth
make test       # host-side unit tests (BRR, RLE, sndj.js, tools)
make shot-diff  # golden-screenshot comparison
```

`make check` runs 31 Lua suites (300+ assertions) against machine state:
DSP registers, ARAM bytes, WRAM song data, screen shadow maps, timing.
Every hardware-relevant bug found so far has a regression check.

## Documents

- **CLAUDE.md** — the master plan and agent guide (the contract)
- **SAVEFORMAT.md** — WRAM song block + SRAM byte layouts
- **CHANGELOG.md** — per-milestone user-facing notes

MIT. Built on the work of the SNES/SFC homebrew and reverse-engineering
communities (fullsnes, anomie's docs, the SNES dev wiki).
