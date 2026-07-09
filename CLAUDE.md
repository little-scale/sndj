# CLAUDE.md — sndj

This file is the master plan and working guide for agents (Claude Code / Opus)
building **sndj**. It is written before any code exists; as milestones land,
sections here graduate into DESIGN.md (the contract), MANUAL.md (the player's
guide), SAVEFORMAT.md, and HARDWARE.md, exactly as in the sibling repos.
Until then, **this document is the contract.** Read the relevant section before
making design decisions; decisions marked ⚖ SETTLED are not to be re-litigated.

---

## 1. Project identity

**sndj** — an LSDJ-inspired music tracker for the **Super Nintendo /
Super Famicom**, written in **65816 + SPC700 assembly**. It is the third
sibling of:

- **[smsggdj](https://github.com/little-scale/smsggdj)** — Sega Master System / Game Gear (Z80, SN76489 PSG)
- **[genmddj](https://github.com/little-scale/genmddj)** — Sega Mega Drive / Genesis / Nomad (68000 + Z80, YM2612 + SN76489)

The sibling contract — what carries over **verbatim in spirit** unless the SNES
hardware forces otherwise:

1. **Data model**: notes live in PHRASEs (16 rows = 1/16th notes), phrases live
   in CHAINs, chains are arranged per-track in the SONG grid. Tracks map 1:1 to
   hardware voices. Tracks do not own instruments/phrases/chains — they play
   *out of* shared pools.
2. **Control grammar** (⚖ SETTLED, from DESIGN.md §3 of smsggdj): two modifier
   buttons; *the button already held when the other arrives selects the
   action*; never introduce simultaneous-press timing windows. Item-level
   modifier = insert/edit/nudge/paste/audition; project-level modifier =
   screen navigation and transport.
3. **Screen set**: SONG / CHAIN / PHRASE / INSTR / TABLE / WAVE / GROOVE /
   ECHO / FILES / PROJECT / OPTIONS / LIVE, arranged on a 2-D screen map
   navigated by (screen-modifier held) + d-pad. sndj adds SNES-specific
   screens (KIT, FIR, MIDI — §8).
4. **Command set**: the shared A–Z single-letter command language, one executor
   shared by phrase and table columns, `cmd_chars`/`cmd_order` id↔letter↔rank
   mapping. SNES-specific commands extend the set; shared letters keep shared
   semantics (§10).
5. **Grooves are the tempo** (DESIGN §9 in smsggdj): TMPO is a live readout
   derived from the active groove, not an independent clock.
6. **Sync family**: `OFF / OUT / PULSE / IN / IN24`, numbered like genmddj;
   OUT/IN are 1-clock-per-row (lock two machines at any tempo), IN24 is
   24 PPQN for the Ableton Link ESP32 bridge. Cross-sibling sync is a design
   goal: a Mega Drive and a SNES on one cable must lock (§12).
7. **Engine split** (genmddj model): the main CPU owns *everything* — song
   data, editor, UI, per-tick sequencer. The sound CPU is a pure chip servant
   holding no song state. Per tick, the main CPU computes desired chip state,
   diffs against a locally held shadow, and ships only the changes as a small
   **Sound Control Block (SCB)** (§3).
8. **Ecosystem**: browser-first, zero-toolchain tools for musicians (ROM
   patchers for samples/palette/font/presets, a save/song manager, the
   Ableton/MIDI/MML converter), plus Python CLI mirrors of each; one shared,
   node-testable JS library (the `smdj4.js` pattern) that every tool imports
   (§17).
9. **Build hygiene**: `make` emits version + git-hash-stamped dev copies;
   `make dist` emits version-only release copies; boot splash shows the build
   stamp to catch stale flashes; per-version CHANGELOG.md; MIT license.

Naming (⚖ SETTLED unless Seb objects):

| Thing              | Name                        |
|--------------------|-----------------------------|
| Repo / project     | `sndj`                    |
| ROM                | `build/sndj.sfc`          |
| Song file          | `.sndj`                     |
| Save format magic  | `SNDJ1` (family: SMDJ3/4)   |
| SPC driver blob    | `build/driver.spc700.bin`   |
| Reference JS lib   | `tools/sndj.js`             |
| ESP32 bridge repo  | `sndj-link-esp32`         |

Voices (8): `V1`–`V8`, all hosted by the S-DSP. Unlike the siblings there is
no chip heterogeneity — every voice is a full citizen (sample, kit, wavetable,
or noise). Heterogeneity on the SNES comes from *instrument type*, not from
which column you're in. This is the single biggest data-model relaxation
versus the siblings and should be embraced, not fought.

---

## 2. The instrument: what makes the SNES sound special

The S-DSP is not a synthesizer chip with a sampler bolted on — it is a
**sampler with a mixing console, a modulation bus, and a room built in**.
sndj should be designed around the five things only this chip does:

1. **BRR + Gaussian interpolation = the SNES timbre.** All samples are
   4-bit-nibble BRR blocks (9 bytes → 16 samples, four prediction filters),
   played back through a 4-tap Gaussian interpolator that rolls off highs.
   The grit of BRR quantisation under the softness of the Gaussian filter *is*
   the sound (Super Metroid, DKC, Secret of Mana). Consequence for tooling:
   the browser patcher must audition samples through a **bit-exact BRR
   encode→decode→Gaussian→32 kHz** path so what you hear is what the console
   plays, and the encoder must offer **treble pre-emphasis** to pre-compensate
   the Gaussian rolloff (the classic BRRtools trick).
2. **Hardware echo with an 8-tap FIR filter.** A true delay line in APU RAM
   (EDL = 0–15 → 0–240 ms in 16 ms steps, 2 KB per step), per-voice echo
   send (EON), stereo echo volume, feedback, and — uniquely — an 8-tap FIR in
   the feedback path. This is the cathedral of DKC and the metallic slapback
   of a hundred soundtracks. sndj gives it two dedicated screens (ECHO for
   the send/level/feedback/time, FIR for the taps) and a browser FIR designer
   with a live frequency-response plot (§11, §17).
3. **Pitch modulation (PMON).** Voice *n*'s pitch can be modulated by voice
   *n−1*'s output — sample-rate phase modulation between arbitrary sampled
   waveforms. FM-adjacent growls, bells, and vibrato-from-audio that neither
   sibling can do. Exposed as a per-instrument flag plus a command; the voice
   ordering constraint (modulator must sit on the voice to the left) becomes a
   *musical* property of track layout.
4. **Hardware envelopes: ADSR and GAIN.** Per-voice ADSR (attack/decay/
   sustain-level/sustain-rate) runs on the chip with no CPU cost; GAIN mode
   offers direct level plus four ramp shapes (linear inc/dec, bent line,
   exponential dec) that can be re-triggered mid-note for tremolo/gate
   effects. The engine leans on these instead of software volume ramps —
   the opposite of the siblings, where every envelope is CPU-computed.
5. **Per-voice stereo with signed volumes.** VOL L/R are signed bytes: a
   negative volume inverts phase → the "surround" width trick. Plus a global
   noise generator (per-voice NON switch, one global noise clock, 32 rates)
   that keeps the PSG-noise idiom of the siblings alive.

Two facts of life that shape everything:

- **The DSP is reachable only from the SPC700**, through two registers
  (`$F2` address / `$F3` data). The main CPU talks to the SPC700 only through
  four mailbox ports (`$2140–$2143`). The genmddj SCB architecture is
  therefore not just a stylistic carry-over — it is the only sane design.
- **Audio RAM is 64 KB, total, shared** by the SPC700 driver, the sample
  directory, all resident BRR data, and the echo buffer. Budgeting this RAM
  is a first-class design activity (§14). The echo buffer *eats sample space
  live* — EDL 15 costs 30 KB.

One genuine SNES advantage worth designing around: **the APU has its own
24.576 MHz crystal, identical in every region.** DSP sample rate, pitch, and
SPC700 timers are region-independent. genmddj needs separate VIDEO and CLOCK
options; sndj needs only **VIDEO** (50/60 Hz display + NMI rate). If the
engine tick is derived from an SPC700 timer rather than NMI (§3.4), *tempo*
becomes region-independent too, and PAL vs NTSC affects nothing but the
picture.

---

## 3. System architecture

### 3.1 Division of labour (⚖ SETTLED — genmddj model)

The **65816 (S-CPU) owns everything**: song data, editor/UI/PPU, input, the
per-tick sequencer pipeline (groove → row advance → trigger/commands →
table step → software LFO → kill → DSP shadow update → mute gate), save/load,
and sync. Each tick it computes the DSP register state it wants, **diffs it
against a CPU-held shadow of all 128 DSP registers**, packs only the changes
into a **Sound Control Block**, and pushes it through the 4-byte mailbox.

The **SPC700 is a pure chip servant**. Its resident driver (~2–4 KB):

- drains SCBs from the mailbox into the DSP (`$F2/$F3` pairs),
- enforces the DSP write-ordering rules the CPU shouldn't have to know
  (KON/KOF spacing, FLG handling around echo reconfiguration — §20),
- runs the **timer-derived master tick** (§3.4) and reports tick numbers back,
- streams **meter telemetry** back to the CPU (per-voice ENVX/OUTX snapshots)
  for the UI's envelope meters (§6),
- accepts **bulk uploads** (sample-to-ARAM transfers, driver hot-patches)
  via a length-prefixed block protocol,
- holds no song state.

### 3.2 Mailbox protocol

Four ports is tight; the protocol must be boringly robust:

- **Port 0**: CPU→APU command/sequence byte (with a flip-bit handshake, the
  standard SNES idiom). Every transfer is acknowledged by the APU echoing the
  sequence byte back on its port 0. All waits have timeouts; a timeout drops
  to a visible `APU?` status on screen rather than hanging (agents: never
  write a spin-forever loop here — it is the #1 bring-up hang).
- **Ports 1–2**: 16-bit payload (register index + value pairs, or block
  length/address during bulk mode).
- **Port 3**: APU→CPU telemetry lane — current tick low byte, then a rotating
  ENVX snapshot, so the CPU can both *phase-lock its sequencer to the APU
  tick* and drive meters without ever stalling the audio side.

SCB framing mirrors genmddj: `[count] [reg,val] × count`, with two escape
opcodes: `E0 nn` = "enter bulk upload, nn pages follow" and `E1` = "tick
barrier — apply everything above atomically at the next tick edge". The tick
barrier is what keeps 8-voice KON events sample-synchronous.

### 3.3 Boot

The IPL ROM upload protocol (`$AA/$BB` ready handshake, `$CC` kick) loads the
SPC700 driver at boot; the driver then switches to the mailbox protocol.
The driver binary is assembled by `wla-spc700` in the same `make` as the main
ROM and linked in as a data blob — one tree, one build, like the Z80 blob in
genmddj.

### 3.4 The master tick (⚖ SETTLED)

The engine tick is generated by **SPC700 Timer 0** (8 kHz base, divided to the
tick rate implied by the groove/tempo math) and reported to the CPU via
port 3. The NMI/VBlank drives *only* video and input. Consequences:

- Tempo and pitch are identical on PAL and NTSC consoles with zero tables.
- The tempo resolution is fine-grained (8 kHz base) instead of frame-quantised
  — the groove math from the siblings ports over but the tick source is
  better.
- The CPU sequencer runs from the main loop when it observes a new tick
  number, never inside NMI (keeps NMI short; VRAM discipline §20).
- Sync IN modes (§12) override the timer: in `IN`/`IN24` the CPU forwards
  externally-clocked ticks to the APU ("tick lease"), so slaved tempo also
  bypasses the frame clock.

### 3.5 Memory map (initial; refine in DESIGN.md)

- **Cart**: LoROM, 1 MB baseline (expandable to 4 MB), FastROM
  (3.58 MHz) — the 65816 does all sequencing + UI, take the free speed.
  Banks: code/tables/font/logo in banks $80–$81; **self-describing sample
  pool** (§14.4) occupying the upper banks, mirroring the genmddj
  banks-2–7 pool contract so the browser patcher can locate and replace it
  by magic marker, not by hard offset.
- **WRAM**: song data as **one contiguous block** (waves, phrase pool,
  chains, song grid, instruments, tables, grooves — offsets frozen in
  SAVEFORMAT.md) so save/load is a straight copy to SRAM. 128 KB WRAM is
  luxurious; leave the door open for a bigger song (more phrases than the
  siblings) but freeze the block layout early because the save format
  depends on it.
- **SRAM**: 32 KB baseline (max compatibility with flashcarts + real
  boards), N song slots (§15).
- **ARAM (64 KB)**: driver + directory + resident samples + echo (§14).

---

## 4. Toolchain — how an Opus agent develops and debugs this

The agent loop must be: **edit → `make` → headless run → machine-readable
assertions → (optionally) pixel/screenshot check → commit at milestone
boundaries.** Everything below exists to make that loop fast and
deterministic.

### 4.1 Assemblers (⚖ SETTLED)

**WLA-DX** for both CPUs — `wla-65816` for the S-CPU, `wla-spc700` for the
driver, `wlalink` to link. Rationale: one assembler family across all three
siblings (smsggdj is already WLA-DX), one directive dialect, one set of
Makefile idioms, and WLA-DX's `.SNESHEADER`-style support handles the LoROM
header/checksum. The genmddj alternative (vasm) has no SPC700 target;
ca65/asar are noted as fallbacks only if a blocking WLA-DX bug appears
(document it in CLAUDE.md if so).

Single-translation-unit build per CPU, exactly like smsggdj: the Makefile
assembles `src/main.asm` (which `.INCLUDE`s everything) and
`src/apu/driver.asm` separately, links the driver as a binary blob.
Adding a file = add an `.INCLUDE` *and* a Makefile prerequisite.

### 4.2 Emulators

- **Mesen 2** — the primary dev emulator. Best-in-class SNES debugger:
  synchronized 65816 *and* SPC700 stepping, DSP register viewer, memory
  viewers for ARAM, event viewer, and a **Lua scripting API usable in a
  headless test-runner mode**. This is the agent's assertion harness (§4.3).
- **ares** — accuracy referee; run before every release and when Mesen and
  hardware disagree. Also the future home of a sndj `ares-link-sync`
  counterpart if desired (the existing ares fork pattern).
- **bsnes-plus** — secondary SPC700/DSP debugging opinion when chasing driver
  bugs.
- `make run` launches Mesen 2 with the fresh ROM. Config note for the
  Makefile: pin the emulator to normal speed / audio-synced (the Emulicious
  `AudioSync=true` lesson — a free-running emulator invalidates every timing
  observation).

### 4.3 Headless verification (`make test`, `make check`, `make shot`)

- **`make test`** — host-side tests, no emulator: `node tools/sndj.js`
  self-test (format geometry, RLE codec), `python tools/test_brr.py`
  (BRR encoder round-trip vs the reference decoder, bit-exact), the
  **65816-RLE mirror** (the asm unpacker vs the Python packer, the
  `rle_z80mirror.py` pattern), and a JS syntax check of every browser tool.
- **`make check`** — emulator-in-the-loop: Mesen 2 test-runner boots the ROM
  with `tools/check.lua`, which drives scripted input, then asserts on
  machine state: DSP shadow contents at tick N, KON bitmasks after a
  scripted note entry, ARAM bytes after a sample upload, WRAM song-block
  CRC after a save/load cycle. Assertions print `PASS`/`FAIL` lines and set
  the exit code — this is the agent's ground truth, not eyeballing.
  Keep a library of scenario scripts in `tools/checks/` (boot, note-entry,
  save-load, echo-reconfig, sync-in) and grow it with every bug fixed:
  **every hardware-verified bug gets a regression check.**
- **`make shot`** — headless screenshot via a small libretro harness
  (genmddj's `tools/emu/` pattern; use the Mesen or bsnes libretro core,
  fetched separately, not committed). Golden images live in
  `tools/goldens/`; `make shot-diff` pixel-compares. Screens are static text
  UIs — goldens are cheap and catch layout regressions instantly.
- **`make wav`** — headless audio render of the bundled demo song to WAV via
  the emulator, N seconds, for A/B listening and (later) automated spectral
  sanity checks (e.g. "echo on adds energy after 100 ms" — coarse asserts
  only; audio DSP is verified by the BRR/driver unit paths, not by FFT
  golden files).

### 4.4 Real hardware loop

- **FXPak Pro (SD2SNES)** is the reference cart. Its USB port +
  **usb2snes/QUsb2Snes protocol** gives the agent (via a small
  `tools/usb2snes.py`) live ROM upload, WRAM/SRAM read-write, and reset —
  a hardware debug loop nearly as tight as the emulator one. Use it to:
  push dev builds without SD-card shuffling, snapshot WRAM song blocks,
  and verify SRAM persistence for SAVEFORMAT work.
- The boot splash **build stamp** (short git hash, `+` suffix for dirty
  tree, regenerated into `build/buildid.inc` each build) is the stale-flash
  detector — the recurring gotcha named in smsggdj's CLAUDE.md. Keep it.
- Hardware matrix to verify per release: NTSC SFC, PAL SNES (50 Hz video,
  tempo must *not* change — that's the timer-tick design proving itself),
  FXPak Pro SRAM, real controller, sync cable between two units, and the
  ESP32 bridge.

### 4.5 Reference documents the agent should keep at hand

- fullsnes (nocash) — the S-CPU/PPU/APU bible; anomie's docs for timing.
- The SNES dev wiki BRR + DSP pages; the known KON/KOF and echo-buffer
  erratum notes (§20 encodes the ones that matter as invariants).
- The sibling repos themselves: smsggdj `DESIGN.md` (data model, command
  set, control scheme) and genmddj `MANUAL.md` (screens, FM editor as the
  template for the deep-edit screens) are *upstream specs* — when in doubt
  about editor behaviour, do what the siblings do.

### 4.6 Make targets (summary)

```
make            # build/sndj.sfc + version+hash dev copies + driver blob
make run        # launch in Mesen 2
make check      # emulator-in-the-loop Lua assertions (agent ground truth)
make test       # host-side unit tests (sndj.js, BRR, RLE mirror, JS lint)
make shot       # headless screenshot -> build/shot.png
make shot-diff  # compare against tools/goldens/
make wav        # headless N-second audio render of the demo song
make demo       # self-playing attract build (sndj-demo.sfc)
make dist       # version-only release ROMs for the GitHub release
make clean
```

---

## 5. Repository layout & documentation set

```
sndj/
  src/                65816 sources: main, ppu, input, engine, editor,
                      scb, sync, midi, save  (single .INCLUDE tree)
  src/apu/            SPC700 driver: driver, mailbox, dsp, tick, upload
  tools/              Python build tools + check scripts (the toolchain)
    makefont.py  maketables.py  makelogo.py  makedemo.py
    sndj_brr.py       WAV -> BRR encoder (pre-emphasis, loop tools)
    sndj_pool.py      samples/ -> self-describing ROM pool image
    savetool.py       CLI mirror of savetool.html
    usb2snes.py       FXPak live-debug helper
    check.lua + checks/    Mesen test-runner assertions
    sndj.js           THE shared JS library (format, RLE, BRR codec,
                      reference sequencer, DSP model) — node self-test
    patcher.html  savetool.html  firdesign.html  kitbuild.html
    als2sndj.html  spcexport.html  sramconvert.html
  samples/            sample sources; samples/pool.bin = production bank
  instrument-patches/ factory instrument/kit presets
  songs/              bundled demo song(s)
  art/                logo (tri-pixel-editor source + exports)
  CLAUDE.md  DESIGN.md  MANUAL.md  SAVEFORMAT.md  HARDWARE.md
  CHANGELOG.md  PALETTE.md  PRESETS.md  ALS.md  README.md  Makefile  LICENSE
```

Documentation contract (identical roles to the siblings): **DESIGN.md** is
the settled-decision contract; **SAVEFORMAT.md** must be updated in the same
commit as any WRAM song-block layout change; **MANUAL.md** is written for the
musician and updated per milestone; **HARDWARE.md** covers the controller-port
pinout, sync cabling, level shifting, and the FXPak notes; **CHANGELOG.md**
gets user-facing bullets as changes land, `str_version` in `src/main.asm`
drives the splash and the `make dist` filenames.

---

## 6. Graphics & UI

### 6.1 Video mode and layers (⚖ SETTLED unless a blocker appears)

- **BG Mode 1**. BG3 (2 bpp, high priority) is the **text UI layer** — the
  entire tracker interface lives here, 8×8 tiles, 32×28 visible cells at
  256×224. BG1 (4 bpp) is the **dynamic layer**: per-voice envelope meters,
  the LIVE-mode state strip, the logo on the splash. BG2 is parked (blank or
  subtle backdrop art). Sprites: cursor, playheads (one per track column),
  block-select marquee.
- **HDMA gradient** on the backdrop colour — a per-scanline CGRAM colour-0
  ramp. This is the cheap, unmistakably-SNES flourish: every palette in
  PALETTE.md defines not just the UI colours but a two-colour vertical
  gradient. One HDMA channel, one table, zero CPU cost per frame.
- **Font**: same 8×8 font pipeline as the siblings — `makefont.py` renders
  the source PNG/glyph description into `build/font.bin` as 2 bpp tiles.
  The font block in ROM is wrapped in a magic marker (`SNFONT`) so
  `patcher.html` can replace it (§17).
- **Palettes**: SNES CGRAM is 15-bit BGR — 32,768 colours, by far the
  richest of the three machines. PALETTE.md defines the factory set
  (name, 4 UI colours + gradient pair per entry); the palette bank is a
  marker-wrapped ROM block for the patcher. Keep the *semantic* palette
  slots identical to the siblings (bg / text / accent / highlight) so
  palette files are conceptually portable across the family.

### 6.2 Per-voice metering (new, SNES-only)

The DSP exposes **ENVX** (current envelope, 7-bit) and **OUTX** (current
output, signed 7-bit) per voice, readable by the SPC700. The driver samples
all eight ENVX values once per tick and streams them up port 3; the CPU draws
eight small vertical meters in the SONG and LIVE screen headers. This is
cheap, honest (it's the *chip's* envelope, not a guess), and something
neither sibling can do. A single-voice **oscilloscope** built from OUTX
streaming is a stretch goal (M-SCOPE) — bandwidth through one telemetry port
is the constraint; do meters first, scope only if the mailbox has headroom.

### 6.3 VRAM discipline

All VRAM/CGRAM/OAM writes happen in VBlank via a queued-writes system (a
small "VRAM transaction buffer" the editor fills and the NMI drains), or
under force-blank during screen transitions. The editor never touches PPU
ports directly. This is the SNES analogue of smsggdj's DI/EI-guarded VDP
pairs and is a hard invariant (§20).

---

## 7. Controls

SNES pad: d-pad, B (bottom), Y (left), A (right), X (top), L, R, Select,
Start. Mapping preserves the sibling grammar exactly and spends the extra
buttons on accelerators, not new grammar:

- **D-pad** — move the cursor.
- **B** — *item modifier* (the siblings' B/1): tap = insert / edit ·
  hold + d-pad = nudge value (L/R small, U/D big) · double-tap = paste ·
  tap on a note = audition it.
- **Y** — *context modifier* (the siblings' A/2-within-context):
  Y+B = block select · Y+←/→ = switch channel · Y+↑/↓ = page.
- **A** — *screen modifier* (the siblings' C): A (held) + d-pad = navigate
  the screen map · A+B = play from cursor (solo this screen).
- **Start** — play / stop the song; in LIVE, launch the cursor row.
- **L / R** — channel left / right from anywhere (redundant with Y+←/→ by
  design — shoulder access keeps the right thumb on B while surfing tracks).
- **X** — inspect/help: tap on a command letter = one-line command help in
  the status bar; tap on an instrument = audition with its full envelope;
  hold + d-pad in SONG/LIVE = mute (↑/↓) and solo (←/→) the cursor track.
- **Select** — jump straight to LIVE from anywhere; in LIVE, jump back to
  the previous screen. (A single dedicated performance toggle earns its
  button.)

Rule for new gestures (⚖ SETTLED): must fit the held-modifier frame; L/R/X/
Select may only ever be *shortcuts to things the core grammar can already
do*, so a three-button description of sndj (d-pad + B + Y + A + Start)
remains complete and sibling-identical.

---

## 8. Screens

Eleven screens on the genmddj-style 2-D map, navigated with A (held) +
d-pad (smsggdj letters — PHRASE and PROJECT share P, FILES and FIR
share F; MIDI takeover is a SYNC option in OPTIONS, not a screen; LIVE
is a MODE menu item, not a screen — Select still toggles the live view):

```
[O][P][ ][W][K]      OPTIONS  PROJECT   -    WAVE   KIT
[S][C][P][I][T]      SONG     CHAIN   PHRASE INSTR  TABLE
[F][G][ ][E][F]      FILES    GROOVE    -    ECHO   FIR
```

Middle row is the composing spine (identical to the siblings). The column
alignment is meaningful, as in genmddj: WAVE/KIT sit above INSTR/TABLE
(sound design above the instrument that uses it), ECHO/FIR sit below
INSTR/TABLE (the room below the voices), MIDI sits above PHRASE
(external input above note input).

- **SONG** — 8 track columns (`V1`–`V8`) × chain rows; ENVX meters in the
  header; mute/solo state per column.
- **CHAIN** — phrase list + per-entry transpose, as siblings.
- **PHRASE** — 16 rows × (NOTE, IN, CMD, VAL). Two command columns is a
  possible later luxury (WRAM allows it) but ship with one for sibling
  parity and save-format simplicity. ⚖ SETTLED: one command column in v1.
- **INSTR** — the instrument editor, type-switched (§9): SMP / KIT / WAV /
  NSE. Common block: name, type, envelope (ADSR or GAIN), vol, pan,
  echo send (EON), pitch-mod flag, GRP (chord/unison group span), TSP.
- **KIT** — kit builder: 12–16 slots, each = sample id + tune + vol +
  ADSR-override + echo flag. A kit is playable on *any* voice (the SNES has
  no F6-style special channel — kits are just instruments).
- **WAVE** — the drawn-wavetable editor, sibling-style: 8 banks × 32-sample
  frames drawn with the d-pad. On SNES a frame is compiled on the fly into a
  tiny looped BRR (32 samples = 2 blocks, filter 0 = verbatim) and uploaded
  to a reserved ARAM scratch slot; wave sequencing/morphing arrives via the
  familiar `B` bank command and tables. Single-cycle waves through Gaussian
  interpolation at 32 kHz have a lovely soft-synth character — this screen
  is where the siblings' PSG-era wavetable idiom meets the SNES voice.
- **TABLE** — per-tick automation tables, shared executor with PHRASE.
- **GROOVE** — as siblings; TMPO readout lives in PROJECT and derives from
  the groove (tempo *is* the groove).
- **ECHO** — the room: EDL (delay 0–240 ms, with its ARAM cost displayed
  live as "-N KB samples"), feedback, echo vol L/R, per-voice EON toggles,
  FIR preset selector. Changing EDL walks the safe reconfiguration sequence
  (§20) behind the scenes.
- **FIR** — the 8 tap values as editable signed hex bytes plus an
  ASCII-art magnitude sketch; 8 factory curves (flat, dark, bright, comb,
  bandpass, "DKC hall", "metal plate", user). Deep editing happens in the
  browser designer (§17.4); the FIR screen is for hardware-side tweaks and
  preset recall.
- **LIVE** — the clip launcher, genmddj-style: per-track chain launching,
  quantised to row/bar, mute/solo via X-modifier.
- **MIDI** — status + mapping for MIDI takeover mode (§13): per-voice
  channel assignment, mono/poly pool mode, PC→instrument table, activity
  lights. Entering the screen does not enable the mode; OPTIONS → MIDI does.
- **FILES** — SRAM slots: save/load/erase, slot names, used/free bytes.
- **PROJECT** — song-level: TMPO readout, transpose, echo defaults, NEW.
- **OPTIONS** — persistent device settings: VIDEO 50/60 (display only —
  pitch and tempo are region-free on SNES, surface that proudly as
  `CLOCK: N/A (APU XTAL)`), SYNC mode, MIDI on/off, palette, font, key
  repeat, meter style.

---

## 9. Voices & instrument model

All 8 voices are DSP sample voices; instrument type decides behaviour:

| Type | Plays on | Essence |
|------|----------|---------|
| **SMP** | V1–V8 | Melodic BRR sample: sample id, loop on/off, fine-tune, ADSR/GAIN, pan, EON, PMOD flag, GRP span, drive via commands/tables |
| **KIT** | V1–V8 | Note row selects a kit slot (sample+tune+vol+env packaged); the drum idiom of F6/KIT, but on any voice, up to 8 kits at once |
| **WAV** | V1–V8 | Drawn 32-sample single-cycle wavetable, looped BRR; `B` command switches banks per tick for wave-sequencing |
| **NSE** | V1–V8 | DSP noise (NON on): pitch column sets the *global* noise clock (32 rates) — like the siblings, noise "frequency" is one shared resource; last-writer-wins is the documented rule |

Instrument parameters worth calling out:

- **ENV**: `ADSR a/d/s/r` or `GAIN mode/value`. GAIN's re-triggerable ramps
  are exposed to the command set (`Q` — §10) for hardware tremolo/gate.
- **GRP** (from genmddj's GROUP): an instrument on voice *n* may drive
  voices *n+1..n+k* with per-member semitone offsets — unisons, fifths,
  full chords from one phrase column. With 8 voices this is much more
  spacious than on the Mega Drive; a 4-note pad from one track is routine.
- **PMOD**: flag = "this voice is modulated by its left neighbour".
  The INSTR screen shows the pairing explicitly (`V4 ← V3`), and the manual
  documents the idiom: put a sine WAV on the left voice as the modulator,
  keep its VOL at 0 to make it inaudible, sequence timbre via the
  modulator's pitch column. FM-flavoured sounds, SNES-style.
- **Sample offset**: BRR is block-addressed; `O xx` starts playback at block
  `xx` — free granular/mangle material, and the closest thing to a
  wave-start command a sampler this size can give.

Factory content: `instrument-patches/` ships a preset bank (marker-wrapped
in ROM, patchable): basses, keys, pads, the classic "SNES strings",
a chip-adjacent WAV set matching the siblings' default waves (sibling
continuity: a song sketched on smsggdj should have tonal cousins here),
plus two kits (acoustic-ish, 909-ish). PRESETS.md documents them.

## 10. Command set

One executor, shared by PHRASE and TABLE, `cmd_chars`/`cmd_order` mapping —
the genmddj machinery verbatim. Shared letters keep shared meanings:

```
A  arpeggio            I  play-count mask     R  retrig
B  wave-bank select    J  pass-transpose      S  sweep
C  chord override      K  kill note           T  tempo
D  delay note          L  slide/legato        V  vibrato (VIB override)
E  echo send (voice)   M  master volume       X  volume/accent
F  fine pitch          N  noise clock (glob)
G  groove select       P  pan (signed L/R)
H  hop
```

SNES-specific additions (Y stays "chip-special" as in smsggdj-FM):

```
Q xy  GAIN override — mode x (direct/lin+/lin-/bent/exp-) value y; Q00 back to ADSR
U xy  surround — invert phase of L (x) / R (y) for width tricks
Y 0x  FIR preset select (global; recalls into the song's taps)
Z xx  pitch-mod enable on this voice (uses left neighbour)
```

⚖ SETTLED (Seb, 2026-07-09, revised same day): O (sample offset) and W
are dropped. **X is the family volume/accent** (genmddj's X), not echo:
`X xy` sets the voice's level (both sides, 00-7F), persisting like P
until the voice reloads its instrument. **The echo send lives on E**
(`E01` on, `E00` off) — E's sibling meaning (envelope re-slope) is
hardware-ADSR turf here, already covered by Q. V overrides the
instrument's VIB field per note; TRM is instrument-only. The set above
is complete: 24 live.

Command help one-liners (the X-button inspect, §7) live in a ROM string
table generated by `maketables.py` from a single source-of-truth CSV that
also emits the MANUAL.md command appendix — one file, three artifacts,
no drift.

---

## 11. Echo & FIR — the signature subsystem

Design intent: make the SNES's room a *sequenced instrument*, not a static
mix setting.

- **Per-song echo config** in PROJECT (EDL, feedback, EVOL L/R, FIR preset);
  **per-voice sends** in INSTR/ECHO; **per-tick motion** via `E`/`Y`
  commands and tables — feedback sweeps, FIR flips on the drop, kill-the-
  room-for-one-bar. All through the SCB diff path like any register.
- **ARAM economics are shown, not hidden**: the ECHO screen displays the
  live trade (`EDL 6 = 96ms = 12.0KB`), and FILES/PROJECT warn when a
  loaded song's sample set + echo request exceed 64 KB (the browser tools
  enforce the same budget with the same shared code — sndj.js owns the
  budget calculator).
- **Safe reconfiguration** is a driver-side service: the CPU asks for
  `EDL=n`; the SPC700 executes the mute → ECEN off → wait(old delay) →
  move ESA → set EDL → clear buffer → re-enable sequence. The sequencer
  never needs to know the erratum exists (§20 lists it anyway).
- The **FIR designer** (browser, §17.4) is where taps are *designed*
  (response plot, phase, presets, audition through the JS DSP model);
  the ROM's FIR screen recalls and nudges.

Idioms to document in MANUAL.md ("the room chapter"): DKC-style long dark
hall (EDL 12–15, negative-lobe FIR, moderate feedback); tempo-synced
slapback (EDL chosen from tempo table — provide the table); metallic comb
(alternating-sign taps, high feedback); pseudo-chorus (short EDL, phase
tricks with U). This chapter is the "lean in to what makes the SNES
special" deliverable in user-facing form.

---

## 12. Sync

- **Physical layer**: SNES controller port 2. The port has two data lines
  plus the **IOBit** (pin 6), which the CPU can both drive (`$4201` bit 7)
  and read (`$4213` bit 7) — one pin, both directions, perfect for the
  1-clock-per-row family protocol. Latch/clock lines are available for the
  richer ingest modes. HARDWARE.md gets the 7-pin connector pinout, the
  "sacrifice an extension cable" sourcing note, and the **5 V ↔ 3.3 V level
  shifting** requirement for the ESP32 bridge (same lesson as the Game Gear
  link work).
- **Modes** (⚖ SETTLED — numbered identically to genmddj/smsggdj):
  `OFF / OUT / PULSE / IN / IN24` (+ MIDI in slot 4, as on genmddj).
  OUT/IN = 1 clock per row; IN24 = 24 PPQN for the Link bridge. In IN
  modes the external clock drives ROW advance (fx keep the APU tick).
  **Status (2026-07-09)**: IN/IN24/PULSE/MIDI built (`src/sync.asm`,
  `src/midi.asm`; checks `sync.lua`/`midi.lua` inject clocks on the
  real pin-read paths); **OUT is a selectable dummy** — the SNES can
  drive only IOBit, so a single-line row clock locks sndj→sndj but a
  genmddj slave needs a ten-line "edge IN" patch or the bridge as
  translator; decision pending. 🔩 hardware bring-up pending.
- **Cross-sibling cable**: a DE-9 ↔ SNES-plug adapter locks a Mega Drive
  and a SNES (or SMS) on one row clock — an explicit test case in the
  release checklist. One rig, three consoles, one transport.
- **Bridge**: `sndj-link-esp32` (XIAO ESP32-C3, level-shifted), a port of
  smsggdj-link-esp32 — Ableton Link → IN24 counter. An emulator-side
  counterpart via the ares-link-sync pattern is optional later.
- **VJ future**: sync OUT is already sufficient for a future SNES VJ
  companion ROM (the smsggdj VJ pattern); no extra provision needed now,
  but don't design the port protocol in a way that precludes a second
  sndj listening on IN.

---

## 13. MIDI takeover mode

sndj as an **8-voice BRR sample module**, driven live from a DAW or
keyboard through the controller-port bridge.

- **Transport (as built, `src/midi.asm`)**: the genmddj-proven 2-wire
  protocol, verbatim, so the ESP32-S3 bridge firmware serves all three
  siblings with no reflash: the console is the clock master — CLK =
  IOBit (port 2 pin 6, `$4201` bit 7, push-pull; the open-drain RC-ramp
  lesson is inherited), DAT = D0 (pin 4, `$4017` bit 0). Per event the
  S3 presents a leading flag bit (1 = a 3-byte bridge-normalised frame
  follows: `type<<4|channel`, d1, d2; 0 = queue empty), MSB first,
  sampled on the rising edge, next bit presented on the falling edge.
  Auto-joypad reading stays ON (pads keep working); the drain runs once
  per frame from the main loop, gated on `$4212`, capped at 8
  events/frame. The earlier latch/clock nibble-ingest sketch is
  superseded — no manual pad strobing needed.
- **Mapping** (v1 built: channels 1-8 → V1-V8 fixed, PC → instrument
  0-63, velocity → level, bend ±2 semi, CC7/10/91/74, RX monitor on
  OPTIONS; the rest below is the v2 wishlist). Per-voice MIDI channel,
  or **pool mode**
  (one channel, 8-voice round-robin polyphony with voice stealing —
  genuinely playable pads); Program Change → instrument; velocity → volume
  (curve in OPTIONS); pitch bend → pitch (range setting); CC1 → vibrato
  depth; CC7/CC10 → vol/pan; CC91 → echo send; CC74 → FIR preset (because
  it's funny and useful). Notes ignore the sequencer entirely — takeover
  means takeover — but the ECHO/FIR config and metering stay live, and the
  ENVX meters make it a performance display.
- **Hybrid mode** (stretch, M-MIDI2): tracks flagged `EXT` in SONG are
  MIDI-driven while the rest keep sequencing — the tracker as its own
  backing band.
- The same framed-ingest path is deliberately shared with IN24 sync and any
  future data ingest (sample streaming over the bridge is *not* planned —
  ROM/ARAM own samples — but the framing leaves room).

---

## 14. Samples: pipeline, budget, pool

### 14.1 ARAM budget (the central constraint)

```
$0000-$00FF  zero page, stack                 0.25 KB
$0200-$0FFF  driver code, mailbox, voice state ~3.5 KB
$1000-$10FF  sample directory (64 × 4 bytes)   0.25 KB
$1100-$11FF  WAV scratch slots (8 live waves)  0.25 KB  (2-block BRRs)
$1200-ESA    resident BRR sample data          the remainder
ESA -$FFFF   echo buffer = EDL × 2 KB          0-30 KB
```

Worked defaults: EDL 6 (96 ms) leaves **≈ 47 KB** of resident samples;
EDL 15 leaves ≈ 29 KB. The ECHO screen, the patcher, and sndj.js all
compute from this one table.

### 14.2 Residency model (⚖ SETTLED for v1)

**All samples referenced by a song are resident in ARAM** — uploaded from
the ROM pool at song load (and at instrument-edit time), via the bulk
mailbox mode. No mid-song streaming in v1: it keeps the engine honest, the
mailbox quiet during playback, and the budget legible to the musician.
Long-sample **streaming from ROM through the mailbox into a ring buffer**
(the Tales-of-Phantasia trick) is a defined stretch milestone (M-STREAM)
gated on the mailbox having proven headroom.

### 14.3 BRR pipeline

`tools/sndj_brr.py`: WAV → BRR with brute-force filter/range search per
block, optional **Gaussian pre-emphasis** (compensate the interpolator's
rolloff), loop-point snapping to 16-sample boundaries with crossfade-assist,
resample-to-budget ("fit this WAV in N blocks"), and a bit-exact decoder
used by `make test` for round-trip verification. The same codec is ported
into `sndj.js` (one reference, two languages, mirror-tested — the
rle_z80mirror discipline applied to BRR).

### 14.4 The ROM pool

`samples/pool.bin` — the committed, production, **self-describing** pool
(magic header, entry table: name, BRR offset, block count, loop block,
default tune), baked verbatim if present; otherwise `make` converts
`samples/*.wav`. Marker-wrapped in upper ROM banks at a documented offset
so `patcher.html` can find, list, replace, and re-tune entries without a
toolchain. One pool serves all builds. (Identical contract to the siblings'
pool — genmddj DESIGN §10.3 is the model.)

---

## 15. Save format & SRAM

- **SRAM**: 32 KB baseline (LoROM, $70:0000–), the safe intersection of
  flashcarts and real boards. Header declares it honestly; FXPak verified.
  A `BIGSAVE` build flag for 64/128 KB carts can come later without format
  change (slots just multiply).
- **Format `SNDJ1`** (SAVEFORMAT.md owns the byte layout): slot table +
  N song slots, each an RLE-packed image of the contiguous WRAM song block
  (§3.5), CRC-16 per slot, format/version bytes, dirty-flag journal so a
  power cut mid-save never eats the *previous* good save (write to the
  shadow slot, then flip the table entry).
- Target: **≥ 4 slots in 32 KB** → packed song ≤ ~7.5 KB. The RLE codec is
  the shared one (65816 unpacker mirror-tested against Python/JS packers).
  Sizing the phrase/chain/instrument pools to hit this target is an early
  DESIGN.md task — start from smsggdj's SMDJ4 pool sizes, scale phrase
  count up modestly (WRAM is not the constraint; SRAM is).
- Songs reference ROM samples **by name+hash, not index**, so a song saved
  against one patched ROM degrades gracefully on another (missing sample →
  named placeholder, not a crash) — this rule exists because the patcher
  ecosystem makes every user's ROM different.


---

## 16. Options & project settings (summary)

**OPTIONS (device-persistent, saved in a reserved SRAM stub):** VIDEO 50/60
(display + NMI only; pitch/tempo are APU-crystal-derived and region-free —
display this fact as a feature), SYNC mode (OFF/OUT/PULSE/IN/IN24), MIDI
on/off + poll rate, palette, font, key-repeat (DAS) speeds, meter style
(ENVX bars / off), audition volume.

**PROJECT (per-song):** TMPO readout (from groove), song transpose, default
groove, echo defaults (EDL/feedback/EVOL/FIR preset), master vol, NEW
(re-seeds the 8 preset waves from `default_waves`, exactly like smsggdj).

---

## 17. The browser ecosystem

Zero-toolchain, drag-and-drop, all offline-capable single-file HTML apps,
all importing **`user-tools/sndj.js`** — the single shared library containing:
the `.sndj`/`SNDJ1` format geometry, the RLE codec, the BRR encoder/decoder,
the ARAM budget calculator, **a reference implementation of the sequencer
engine**, and **a bit-exact JS model of the S-DSP** (gaussian table, BRR
decode, ADSR/GAIN, echo + FIR, noise, PMON). `node tools/sndj.js` self-tests
all of it; `make test` runs it. The DSP model is the keystone: it is what
lets every tool below *play actual SNES sound in the browser*.

### 17.1 `patcher.html` — the ROM patcher

Drop a built `sndj.sfc`, then patch any of:

- **Samples**: drop WAVs → BRR encode with per-sample trim/gain/tanh
  soft-clip/fades/loop tools (the smsggdj patcher feature set) *plus*
  pre-emphasis amount and target-block budget; audition the **exact console
  sound** (BRR→Gaussian→32 kHz through the JS DSP); live ARAM budget bar
  against the song's echo setting; write back a new pool.
- **Palettes**: edit the factory set in 15-bit colour with live preview of
  every screen (goldens re-rendered client-side), including the HDMA
  gradient pair.
- **Font**: drop a PNG glyph sheet or edit in-place, 8×8.
- **Factory presets / waves / kits**: replace the instrument-patch bank and
  `default_waves`.
- **Settings**: default OPTIONS baked into the ROM (a marker-wrapped
  defaults block) — ship a ROM pre-set to PAL/OUT/your palette.

Checksum is recomputed on export; filenames carry the base ROM's version.

### 17.2 `savetool.html` — songs & saves

SNDJ1-native: drop a `.srm`/emulator `.sav` → view slots, names, sizes,
CRCs; extract slots to `.sndj` files; assemble a cart image from `.sndj`
files; erase/reorder; **song viewer** (read-only SONG/CHAIN/PHRASE
rendering, styled like the ROM); **song preview player** — the sndj.js
reference sequencer driving the JS DSP model, with the ROM's sample pool
supplied by dropping the ROM alongside (samples resolve by name+hash, §15).
Legacy/foreign migration hooks stubbed from day one (the smsggdj
migrate.html lesson: formats change, plan the door).

### 17.3 `als2sndj` — the Ableton path (ALS.md documents it)

Bidirectional, like the genmddj tool:

- **Import**: `.als` (gzip-XML parsed client-side), `.mid`, or **MML** text
  → `.sndj`. Clip-per-track → chains/phrases; MIDI channels → voices;
  note→kit-slot maps; quantise report ("what I moved to fit 16 rows/bar");
  velocity → volume commands; program changes → instruments.
- **Export**: `.sndj` → `.als` (clips per track, one MIDI clip per chain,
  tempo from groove, echo settings as a text note in the set) and → `.mid`.
  Round-trip fidelity is tested in `make test` on fixture songs.

### 17.4 `firdesign.html` — the FIR designer

The 8 taps as sliders/hex; live magnitude (and phase) response plot;
preset library (the ROM's 8 curves + a community section); **audition**:
run any dropped sample or the built-in noise/click through the full JS
echo+FIR+feedback model at chosen EDL; export as a ROM-patchable preset
bank or copy-paste hex for the FIR screen. This tool is the flagship
"lean into the SNES" artifact — nothing like it exists for musicians.

### 17.5 `kitbuild.html` — kit assembler

Drag samples (from the pool or new WAVs) into 16 slots, per-slot tune/vol/
envelope/echo, keyboard audition, export as an instrument-patch bank entry
or straight into a ROM via the patcher's machinery.

### 17.6 `spcexport.html` — .spc & WAV export

Two paths, honest about their trade-offs:

- **WAV render** (primary): reference sequencer + JS DSP render the whole
  `.sndj` offline to 32 kHz stereo WAV (and an optional 2× oversampled
  "archival" render). Deterministic, full-length, ships first.
- **.spc capture** (secondary): run the reference sequencer, log the
  timestamped DSP write stream for one full song loop, RLE the log, and
  bake it into a 64 KB SPC image with a ~200-byte SPC700 replayer + the
  song's samples. Plays in any .spc player. Constraint (document it in the
  tool): log + samples must fit 64 KB — busy songs export a truncated loop
  with a clear report. This mirrors the SCB architecture perfectly: the
  tracker's own diff stream *is* the .spc.

### 17.7 `sramconvert.html`

Raw `.srm` ⇄ emulator save-state-adjacent formats as needed (Mesen/ares/
snes9x `.srm` are all raw, so this may reduce to size-fixing/trimming —
keep the tool anyway for the FXPak `.srm` naming/size conventions and for
gzip variants).

### 17.8 CLI mirrors

Every browser tool has a Python CLI twin (`savetool.py`, `sndj_brr.py`,
`sndj_pool.py`, `als2sndj.py`, `spcexport.py`) sharing fixture-based
tests with the JS via `make test` — the agent automates with the CLIs, the
musician gets the browser.

---

## 18. Additional features & tools worth building

- **Demo/attract build** (`make demo`): auto-plays the bundled song from
  boot — the exhibition build.
- **Command CSV → three artifacts** (§10): ROM help strings, MANUAL.md
  appendix, and sndj.js command metadata from one source file.
- **`tools/budget.py`**: given a `.sndj` + pool, print the ARAM ledger
  (driver/dir/waves/samples/echo) — also run in `make check` against the
  bundled song.
- **Golden screenshot set** covering all 13 screens (§4.3) — regenerate
  with `make goldens` after intentional UI changes.
- **Regression check library** `tools/checks/` — grows monotonically;
  every hardware-found bug lands a check.
- **PALETTE.md / PRESETS.md / ALS.md** — sibling-identical docs.
- **Tri-pixel logo**: wordmark drawn in tri-pixel-editor (family
  branding), `makelogo.py` converts `art/` exports.
- **usb2snes live-tweak mode** (dev only): `tools/usb2snes.py poke` writes
  the WRAM DSP-shadow — tune echo/FIR on real silicon from a laptop
  without rebuilding. Cheap to build, enormous for voicing the factory
  presets on hardware.
- Explicit **non-goals for v1** (⚖ SETTLED): no MSU-1, no expansion chips
  (SA-1/SuperFX), no mouse support, no mid-song sample streaming, no
  second command column, no software mixing beyond the 8 DSP voices.

---

## 19. Milestones

Commit at every milestone boundary; each has a verification gate
(`make check` scenarios + hardware items marked 🔩).

- **M1 — Boot & bus.** LoROM skeleton, FastROM, NMI, splash + build stamp,
  font/palette pipelines, input with DAS repeat. Gate: golden of splash;
  pad-echo check script.
- **M2 — APU bring-up.** IPL upload of the SPC700 driver, mailbox with
  handshake+timeout, SCB path end-to-end: CPU pokes a DSP register via SCB,
  Lua asserts the DSP value. Gate: `checks/mailbox.lua`; deliberate-timeout
  test shows `APU?` instead of hanging.
- **M3 — A voice.** Directory + one baked BRR sample, KON via SCB, ADSR,
  pitch table (from `maketables.py`, single tuning source also emitted to
  sndj.js). Gate: `make wav` renders a scale; KON/pitch asserts.
- **M4 — Engine core.** Tick from SPC Timer 0 (§3.4), groove pipeline,
  phrase playback on one voice, PHRASE screen with full B-grammar editing.
  Gate: scripted note entry → audio + state asserts; PHRASE golden.
- **M5 — Data model complete.** SONG/CHAIN screens, 8 tracks, chains,
  transpose, copy/paste/clone, block ops. Gate: sibling-parity edit
  scenario script passes.
- **M6 — Instruments.** INSTR screen, SMP type end-to-end, instrument
  pool, GRP groups, audition. Gate: GRP chord renders 3 voices from one
  column (WAV render + KON mask assert).
- **M7 — Commands & tables.** Shared executor, core A–W set, TABLE screen.
  Gate: per-command check scripts (at least A, D, G, H, K, L, P, R, T, V).
- **M8 — Save/load.** WRAM block frozen, SAVEFORMAT.md written, SRAM
  slots, FILES screen, RLE mirror test. 🔩 FXPak SRAM persistence. Gate:
  save→reset→load→CRC-identical WRAM.
- **M9 — Echo & FIR.** ECHO/FIR screens, safe-reconfig service, E/Y
  commands, budget display. 🔩 listen on hardware (emulator echo is good
  but the room is the product). Gate: echo-reconfig check (no ARAM
  corruption — assert sample bytes intact after EDL walk).
- **M10 — WAVE & KIT & NSE.** Wavetable compile-to-BRR path, WAVE screen,
  `B` command, KIT type + screen, NSE type with global-clock rule.
  Gate: wave-morph render; kit round-trip.
- **M11 — Sample pool & patcher.** Self-describing pool, bulk upload at
  song load, `sndj_brr.py` + JS mirror, `patcher.html` (samples first,
  then palette/font/presets/settings). Gate: patch a pool in the browser,
  boot it, `checks/pool.lua` verifies directory integrity.
- **M12 — Sync.** IOBit OUT/IN/PULSE, IN24 ingest, tick lease. 🔩 two-unit
  lock test; 🔩 cross-sibling cable vs genmddj; ESP32 bridge port. Gate:
  emulated-clock check locks row advance to injected edges.
- **M13 — LIVE mode.** Launcher, quantise, mute/solo, meters in header.
  Gate: LIVE golden; launch-quantise assert.
- **M14 — MIDI takeover.** Ingest framing, MIDI screen, mapping, pool
  polyphony. 🔩 bridge + keyboard latency feel test. Gate: injected MIDI
  stream → KON pattern assert.
- **M15 — Ecosystem round-out.** savetool, als2sndj (both directions),
  spcexport (WAV then .spc), firdesign, kitbuild, budget tool, demo build,
  factory content pass (🔩 voiced via usb2snes on hardware), MANUAL.md.
- **M16 — Release.** Hardware matrix (§4.4), goldens regenerated,
  CHANGELOG dated, `make dist`, tag, `gh release create` with versioned
  ROMs. Stretch queue thereafter: M-SCOPE (OUTX oscilloscope), M-STREAM
  (long-sample streaming), M-MIDI2 (hybrid EXT tracks), BIGSAVE.

---

## 20. Hard invariants

The list every agent reads before touching `src/`:

1. **Mailbox waits always time out.** No unbounded spin on `$2140–$2143`,
   ever — boot, bulk, or tick path. Timeout ⇒ visible `APU?` state +
   re-handshake attempt.
2. **Only the SPC700 touches the DSP**, and only the driver's writer
   routine touches `$F2/$F3` — one code path enforces ordering rules.
3. **KON/KOF spacing**: never write KON for a voice within the same or
   adjacent driver slice as its KOF; the driver serialises (the DSP samples
   KON every other output frame — back-to-back writes drop notes). The
   tick-barrier opcode exists so the CPU never micro-manages this.
4. **Echo buffer discipline**: the region `[ESA, ESA+EDL×2KB)` belongs to
   the DSP whenever ECEN is enabled — it *writes* there even at zero echo
   volume. Never place samples in it; never change ESA/EDL with echo
   enabled; the safe-reconfig sequence (mute → ECEN off → wait old-delay →
   move → clear → enable) is the only way (§11). Misconfigured echo
   silently corrupts sample RAM — the classic SNES audio bug class.
5. **BRR geometry**: 9-byte block alignment; loop points on 16-sample
   boundaries; every sample ends with an END-flagged block (a runaway BRR
   read plays garbage forever); directory entries are validated at upload.
6. **VRAM/CGRAM/OAM writes only via the VBlank transaction queue or under
   force-blank** (§6.3). The editor never writes PPU ports directly.
7. **NMI stays short**: drain VRAM queue, read pads (respect `$4212`
   auto-read completion before touching `$4218+`; manual strobing only in
   MIDI/sync ingest with auto-read disabled), set a frame flag, out.
   The sequencer runs in the main loop off the APU tick, never in NMI.
8. **65816 register-width discipline**: documented convention — natural
   state is `M=1,X=1` (8-bit) everywhere; any routine that widens must
   restore; interrupt entry re-asserts. Direct page fixed per module and
   documented in `main.asm`'s header.
9. **No mul/div on hot paths** — ROM lookup tables; where unavoidable use
   the 5A22 hardware multiplier/divider (`$4202+`) with the mandated
   cycle-wait, never inside NMI while HDMA is active (known silicon
   erratum territory — keep hardware math out of NMI entirely).
10. **Per-region tables are video-only.** Nothing in pitch/tempo may
    depend on VIDEO; the APU crystal is the sole musical timebase (§3.4).
11. **SRAM writes go through the journal** (§15): shadow-slot write, CRC,
    then table flip — never in-place.
12. **SAVEFORMAT.md moves in the same commit** as any WRAM song-block or
    SRAM layout change; **DESIGN.md** in the same commit as any settled-
    decision change.

---

## 21. Settled decisions index (⚖)

For fast lookup — full rationale in the sections cited:

| # | Decision | § |
|---|----------|---|
| 1 | Sibling data model, control grammar, screen map, A–Z executor | 1, 7, 8, 10 |
| 2 | CPU-owns-everything / SPC700-servant SCB architecture | 3.1 |
| 3 | Engine tick from SPC700 Timer 0; NMI is video-only | 3.4 |
| 4 | WLA-DX toolchain (65816 + SPC700 + wlalink) | 4.1 |
| 5 | BG Mode 1; BG3 text UI; HDMA gradient backdrop | 6.1 |
| 6 | Button map B/Y/A/Start core; L,R,X,Select are shortcuts only | 7 |
| 7 | One command column in PHRASE (v1) | 8 |
| 8 | All-resident samples; no mid-song streaming (v1) | 14.2 |
| 9 | 32 KB SRAM, SNDJ1, ≥4 slots, journalled saves | 15 |
| 10 | Sync modes OFF/OUT/PULSE/IN/IN24, genmddj numbering, IOBit line | 12 |
| 11 | Samples referenced by name+hash in songs | 15 |
| 12 | v1 non-goals: no MSU-1/expansion chips/streaming/2nd cmd column | 18 |

## 22. Open questions for Seb

1. **Pool sizes**: phrase/chain/instrument/table counts — start at SMDJ4
   sizes or scale up (SRAM slot target is the constraint, §15)?
2. **KIT slot count**: 12 vs 16 per kit; and should NOTE in a KIT phrase
   map chromatically-with-retune above the slot count (LSDJ-style)?
3. **FIR screen depth**: hex taps + presets only (proposed), or a full
   on-console tap editor?
4. **Wordmark**: tri-pixel session for the sndj logo — same family
   geometry, new mark?
5. **Factory sample identity**: share source material with the smsggdj
   pool for family continuity, or an all-new 32 kHz-native bank?
6. **MIDI pool-mode default**: round-robin vs lowest-free voice
   allocation (affects release-tail behaviour with long ADSRs)?

---

*sndj — a sibling to smsggdj and genmddj, built on the work of the
SNES/SFC homebrew and reverse-engineering communities. MIT.*
