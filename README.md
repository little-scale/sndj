# snesdj

An LSDJ-inspired music tracker for the **Super Nintendo / Super Famicom**,
written in 65816 + SPC700 assembly. The third sibling of
[smsggdj](https://github.com/little-scale/smsggdj) (SMS/Game Gear) and
[genmddj](https://github.com/little-scale/genmddj) (Mega Drive): same data
model, same control grammar, same screen map — built around what only the
S-DSP can do: BRR samples through Gaussian interpolation, a hardware echo
with an 8-tap FIR filter, per-voice hardware envelopes, drawn wavetables,
and 8 full-citizen voices.

## Status

Milestones **M1–M11 and M13** of the plan (see CLAUDE.md §19) are built and
verified. What works today, all playable in an emulator:

- **8-track sequencer** — phrases (16 rows), chains, 128-row song grid,
  per-entry transpose; groove-driven timing clocked by the APU's own
  crystal (tempo and pitch are region-free by construction)
- **Screens** — SONG, CHAIN, PHRASE, INSTR, WAVE, ECHO, FILES, LIVE on the
  sibling 2-D map (A+d-pad), with the shared B-grammar everywhere
  (tap insert/audition, B+d-pad nudge, Y+B cut)
- **Instruments** — sample (SMP), kit (KIT, v1 chromatic mapping), drawn
  wavetable (WAV), noise (NSE); ADSR/volumes/GRP chord spans; GRP renders
  chords from a single phrase column
- **Commands** — A arpeggio, B wave bank, D delay, G groove, H hop,
  K kill, L slide, P pan, R retrig, T tempo (live APU timer retune),
  V vibrato, X echo send, Y FIR preset
- **Echo & FIR** — the SNES's room as an instrument: delay with live ARAM
  cost, feedback, per-voice sends, 8 factory FIR curves; reconfiguration
  runs an erratum-safe driver sequence (including the free-running echo
  offset wrap — see the M9 commit)
- **Sample pool** — six factory samples (pad/bass/pluck + synthesized
  kick/snare/hat) in a self-describing, marker-wrapped ROM pool
- **Save/load** — 4 journalled SRAM slots (SNDJ1 format, SAVEFORMAT.md);
  a power cut can't eat the previous good save
- **LIVE mode** — quantised chain launching, mute/solo, ENVX meters
- **Browser tool** — `tools/patcher.html` replaces pool samples with your
  WAVs entirely locally, via `tools/sndj.js` (the shared JS library whose
  BRR codec byte-matches the Python reference)

Still to come: sync (M12) and MIDI takeover (M14) — designed, but their
gates need real hardware rigs; TABLE screen; the rest of the browser
ecosystem (M15); release (M16).

## Building

Requires WLA-DX (`brew install wla-dx`), Python 3, Node, and
[Mesen 2](https://github.com/SourMesen/Mesen2) for the verification loop.

```
make            # build/snesdj.sfc (+ git-stamped dev copy)
make run        # launch in Mesen 2
make check      # emulator-in-the-loop assertions — the ground truth
make test       # host-side unit tests (BRR, RLE, sndj.js, tools)
make shot-diff  # golden-screenshot comparison
```

`make check` runs 12 Lua suites (~150 assertions) against machine state:
DSP registers, ARAM bytes, WRAM song data, screen shadow maps, timing.
Every hardware-relevant bug found so far has a regression check.

## Documents

- **CLAUDE.md** — the master plan and agent guide (the contract)
- **SAVEFORMAT.md** — WRAM song block + SRAM byte layouts
- **CHANGELOG.md** — per-milestone user-facing notes

MIT. Built on the work of the SNES/SFC homebrew and reverse-engineering
communities (fullsnes, anomie's docs, the SNES dev wiki).
