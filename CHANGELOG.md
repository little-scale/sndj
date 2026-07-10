# Changelog

All notable changes to sndj. First release will be **v0.1**; versions
increment by **0.01** thereafter (v0.1 → v0.11 → v0.12 → …).

## 0.1.0-dev (unreleased)

- KARP needs no ECHO-screen setup anymore: **flipping TYPE to KARP
  sizes the room to a string automatically** (DELAY pulls to 1 when
  it's 0 or >2 — a NEW song sits at the ARAM max, which made the
  string an untuned wash). Feedback never needs touching (SUSTAIN
  writes it per note) and EON MASK is bypassed. B-tap audition on
  INSTR now plucks the real string too (it took the plain-pitch path
  before).

- KARP's **DAMP is a true tone control now**: the tap kernel always
  sums to 127, so SUSTAIN alone sets how long the string rings and
  DAMP only moves brightness (smoothing sides spread around the
  tuning pair — dark strings lose treble faster, the classic KS
  filter). Previously DAMP scaled overall gain and was nearly
  indistinguishable from SUSTAIN. The FIR-tab prototype uses the
  same kernel. Tip: VOL L/R is the dry pick — 00 for pure string,
  level on ECHO L/R.

- **New instrument type: KARP** — Karplus-Strong on the echo loop.
  The note rings the room's nearest partial (exciter = any wave bank,
  fired as a burst at the partial's exact pitch) and a per-note 2-tap
  FIR pulls it into tune while doubling as the string's damping
  filter. Fields: BANK / DAMP / BURST / SUSTAIN. Chromatic from ~F#6
  at DELAY 1, ~F#5 at DELAY 2; the harmonic series below. One string
  per song — KARP owns the echo while it plays. Type names now render
  4 characters (KARP reads as KARP).

- **KARP prototype** in the patcher's FIR tab: Karplus-Strong on the
  echo loop (the room as a string). Pick a note, hit pluck — the comb
  rings the note's nearest partial and a 2-tap FIR supplies the
  fractional delay that pulls it into tune (doubling as the classic
  KS damping filter). The console KARP instrument type is designed
  (CLAUDE.md M-KARP); this validates the tuning math by ear first.

- ECHO screen breathing room: the ledger reads as three rows (RAM /
  FREE / +ms of possible delay), and the DELAY cost (-KB and ms) sits
  on its own row under the field instead of crowding the right edge.

- **Per-instrument LOOP override** (SMP): a new INSTR field — POOL /
  ON / OFF. Force a looped import to play one-shot (pad becomes stab)
  or a one-shot to loop whole (hit becomes drone), per instrument,
  with the same pool sample doing both at once. Under the hood every
  sample now uploads with LOOP+END on its final block and loop-or-not
  is purely the ARAM directory's choice: one-shots loop into the
  silent stub, and an override costs one alias directory entry —
  zero extra sample RAM.

- Patcher SLICES tab: **every cut is draggable** — the space between
  the trim handles divides equally, then each orange boundary nudges
  onto the transient by hand. Custom cuts bake by padding each slice
  to the widest with silent blocks, so the console's equal grid lands
  exactly on your cuts with zero engine changes (the byte cost of the
  padding shows before you commit).
- Patcher SLICES tab: **trim then slice** — drag the red edge handles
  to crop dead air (a lossless block cut, no re-encode; **apply trim**
  writes it into the pool slot, and assigning a boot instrument
  applies it automatically), and clicking a slice now plays **just
  that slice**, not through to the sample's end.
- Fixed: **trim +36 played back an octave off** — the one-shot WAV
  path clamped its storage rate at 8 kHz (the OfflineAudioContext
  floor) while still baking -36 into the tune. The decode context now
  stays legal while the JS resampler carries on to 4 kHz, and the
  baked tune derives from the rate actually stored, so the two can
  never drift again.

- **Patcher: six tabs** — POOL / BOOT / KITS / SLICES / FIR /
  PALETTES (the boot instruments move out of the sample list). The
  new SLICES tab is a chop designer: pick a pool sample and a count,
  see the equal block-aligned grid on the waveform, click a slice to
  audition it through the BRR path (fresh decoder state at the cut,
  like the DSP at KON), and assign the result to a boot instrument in
  one click.

- **12 factory boot instruments** (was 8): NEW seeds instruments 0-11
  from the factory rows and their samples load into audio RAM at
  boot; the patcher's boot editor voices all 12. The factory
  container is SNDJFACT v3 (12-byte rows); v1/v2 files still import,
  the new slots defaulting to SMP on sample 0.

- **New instrument type: SLICE** — chop any pool sample (a breakbeat,
  a vocal) into 2-16 equal parts for free: slices are audio-RAM
  directory aliases into the sample the song already loaded. The note
  picks the slice (wrapping past the count, so melodies chop), FADE
  sets how fast each slice dies (0 = bleed into the next like an open
  sampler pad), TUNE transposes the whole set, and the PHRASE note
  column reads as sample-name + slice number. The patcher's boot
  instruments grew a type picker (SMP/KIT/WAV/NSE/SLICE) + slices
  count, and the factory container is now SNDJFACT v2 (v1 files still
  import).

- **Consistent playback indicators** on SONG / CHAIN / PHRASE (the
  GROOVE convention everywhere): a plain arrow in the gutter left of
  the data marks the playing row, the playing value carries the
  highlight, row labels stay dim. PHRASE's playhead now follows any
  track playing the edited phrase (it only watched track 1 before)
  and the playing row's cells light up.

- **SAVE is name-keyed** (genmddj parity): the working song stores
  under its name — a same-named file is overwritten, a new name saves
  a new file; the cursor slot plays no part. LOAD copies the file's
  name back into the song. Fixes the "song name reverted to SONG"
  trap where renaming a saved file was silently stamped over by the
  next save.
- **FILES menu confirm**: B arms the chosen action and it reads
  **SURE?** — a second B runs it. Moving disarms; a new **CANC**
  item (or A) closes the menu without running anything.

- **One nudge grammar everywhere**: B + left/right steps any field by
  1 (the low nibble); B + up/down steps the high nibble (±16) on byte
  fields, an octave (±12) on semitone fields (notes, transpose, chord
  offsets, kit tune), ±4 on short ranges — and power-of-two ranges
  wrap instead of clamping. INSTR/ECHO/KIT/PROJECT all follow.
- Field screens highlight the **value** under the cursor, not the
  label (ECHO, INSTR, OPTIONS).

- Fixed: **double-tap (paste / mint / clone) was humanly impossible** —
  the window was 6 frames (100 ms); it's now genmddj's 24 (~400 ms),
  with a pending-tap flag so the generous window can't misfire: any
  cursor move or screen change ends the gesture, and two ordinary
  taps in different places no longer read as a pair.

- PHRASE shows **sample names on kit rows**: when a row's instrument
  is a KIT, the note cell reads the first three letters of the slot's
  pool sample (silent slots read `---`) — a pitch means nothing there.
- Fixed: the ECHO screen's EON gate toggles drew invisibly (only the
  ACCENT attribute carries the inverted glyph bank; HILITE spaces are
  blank). Solid cells now render.

- The committed factory is now a single **`samples/factory.sndjfact`**
  (patcher's export-factory file): the build reads its pool and kits
  directly, replacing pool.bin/kits.bin. Round two of Seb's factory:
  kit 0 filled to 16 slots with the new -EDIT drum set (boot 34.6 KB,
  echo ceiling EDL 12 / 192 ms).

- **Echo routing is a real gate now**: a voice sends to the room only
  when its instrument's ECHO flag is on **and** its channel's bit in
  the EON MASK is open (masks previously got overwritten by every
  instrument trigger — they "did nothing"). New songs open all gates,
  so the instrument flag alone still works; `E` and MIDI CC 91 edit
  the channel gate. Same instrument wet on one track, dry on another.

- patcher: **export factory / import factory** — the whole factory
  identity (pool, kits, boot instruments, FIR presets, palettes) in
  one small `.sndjfact` file, applyable onto any loaded ROM. Share a
  voicing, keep versions, or hand it straight to the build.

- ECHO: the RAM/FREE ledger sits at the top, above the DELAY it
  trades against, and the DELAY row reads both ways — `0C -24KB 192MS`.
- ECHO's RAM/FREE ledger also reads the free space as **time**: a
  `+NNNms` readout of how much longer the delay could get from here
  (2 KB steps, capped by the register's 15).

- patcher: one tuning rule everywhere — **the pool tune fully encodes
  a sample's storage rate** (8 kHz sf2 one-shots now bake -24 there
  too), and **kit slots default to tune 0**, staying purely musical.
  Previously the two conventions could stack to -48 (two octaves low)
  when a trimmed import landed in a kit. The factory kit's existing
  -24 slots still sum correctly against their tune-0 pool entries.

- patcher: **trim now works on every import and compensates itself** —
  it stores the data N semitones lower-rate (half size per octave) and
  bakes the offsetting tune into the pool slot, so playback pitch is
  unchanged with no manual pairing. Dragged loop-less WAVs previously
  took a legacy path that ignored trim entirely (full-rate, tune 0).

- WAV imports aren't one-shot-only anymore: a `.wav` carrying a
  sampler (`smpl`) loop imports **melodic** through the same in-tune
  pipeline as soundfont presets (loop points exact, root key
  honoured); choosing melodic without one loops the **whole file**
  (single-cycle / seamless sources, root C-4 + trim). The auto mode
  picks per file, one-shot stays the fallback.

- **The factory bank is Seb's curated set** (extracted from a patcher
  session and committed as `samples/pool.bin` + `samples/kits.bin`,
  both baked verbatim into every build): 7 melodics — xylophone,
  violin, trombone, steel drum, saxophone, slap bass, crystal — 11
  one-shot drums assembled as kit 0, and 30 cleared slots as canvas.
  Boot residency 29.9 KB, echo ceiling EDL 14 (224 ms).
- NSE instruments gained a **CLOCK** field (the repurposed sample
  byte): 0 = the note column sets the noise rate as before, 1-32 pins
  the rate so a hat sounds the same on any note. The INSTR screen
  shows it as CLOCK / NOTE for noise types.

- The instrument NUMBER is the INSTR screen's first field (sibling
  grammar): nudge it to switch instruments in place.
- INSTR grew up: fields are **grouped** (identity / envelope / mix /
  tune & motion / chord / table) with blank rows between, **Y + ↑/↓
  flips instruments** without leaving the screen (matching PHRASE and
  TABLE), and each TYPE **hides the fields it never reads** — KIT
  drops VOL/FINE/VIB/GRP (slots own those), NSE drops SAMPLE and all
  pitch fields, WAV relabels SAMPLE to BANK. The sample field's range
  follows the type (kit 0-15, bank 0-7). Goldens regenerated.

- Fixed: WAV instruments in a GRP span or `C` chord played their
  member voices an octave up — the fanout skipped the wavetable's
  -1-octave shift. Auditions had the same mirror; both fixed, with a
  wave.lua chord assert.

- The patcher's left half is **tabbed** now — SAMPLES / KITS / FIR /
  PALETTES — with the soundfont panel persistent on the right (drags
  land on whichever tab is open). No more scroll marathon.
- The **FIR designer merged into the patcher** (firdesign.html
  retired): a collapsible section in the soundfont column with the
  live frequency-response plot, tap sliders/hex, and the echo-loop
  audition (EDL + feedback), writing the loaded ROM's 8 preset slots
  in place — one drop, one export, for samples, kits, boot
  instruments, palettes and the room.

- **Fixed: a track whose column starts with empty rows never played.**
  Tracks now enter at the first populated cell at/below the start row
  (the genmddj rule), so a chain placed at row 01 joins the song; a
  fully empty column still stays silent. Regression check: entry.lua.
- **Play indicators everywhere**: CHAIN gained a playhead arrow with
  the playing entry highlighted (any track walking the edited chain);
  SONG highlights the row label of every playing row (the playing cell
  already inverts); GROOVE's step marker moved to the LEFT of the
  ticks column, drawn plain, with the tick value carrying the
  highlight instead.
- **NEW opens the room automatically**: PROJECT NEW (and FILES
  load-on-empty) set the delay to whatever the resident sample set
  allows — EDL 15 with the factory set. Boot stays at EDL 0 so power-on
  is instant. Under the hood: echo reconfig is now idempotent (an
  unchanged EDL skips the driver's drain — song loads no longer stall
  up to 240 ms), the driver skips the 280 ms offset-wrap drain when the
  buffer GROWS (only shrinks can strand an in-flight offset), and the
  CPU holds its heartbeat off for the reconfig's deaf window instead of
  freezing the UI on a blocked mailbox.

- **The factory model got lean and legible.** Instruments 00-06 are
  pitched SMP melodics, 07 is KIT 0 (SMW percussion); slots 08-63
  ship as SMP-on-sample-0 and kits 1-15 as blank canvases. Since
  audio RAM only holds *referenced* samples, boot residency drops
  from 51.5 KB to 19 KB — echo headroom out of the box goes from
  EDL 4 to the full EDL 15 — and the rest of the pool loads on demand
  the moment an instrument or kit slot points at it. The **ECHO
  screen shows a live RAM/FREE ledger** balanced against the delay
  setting, and the patcher mirrors the same truth: a **RAM column**
  on every pool slot (boot vs on-demand), the ARAM bar computed on
  the boot set, and the **boot instruments themselves editable**
  (I0-I6 sample pickers + the kit id) so you control what preloads.

- patcher.html grew a **kit builder**: the factory kits moved from
  code into a marker-wrapped `SNKIT0` ROM block (16 kits x 16 slots x
  sample/tune/vol; NEW copies it verbatim), and the patcher edits it —
  per-slot sample picker, tune, vol, play, clear, and **dropping a
  soundfont slot straight onto a kit slot** one-shots it into the
  first free pool slot and wires it up at tune -24. Pool slots are
  also **renamable** now, and a **clear ALL** button blanks the whole
  pool for building a ROM from scratch.
- patcher.html: pool slots show an editable **tune** column
  (semitones : 1/256ths — the pool's per-entry default tune, summed
  into every console trigger), and **audition applies it**, on both
  halves of the page. The cheap fix for a soundfont with a wrong root
  key: no resample, no extra bytes.
- patcher.html: the soundfont mode defaults to **auto** — looped
  samples prep melodic, loop-less ones prep one-shot — and a melodic
  request on a loop-less sample falls through to one-shot instead of
  failing with a message parked off-screen (the "silent play button").
  Import status names the mode that was actually used.
- patcher.html: pool slots gained a **clear** button (9 bytes of
  silence — instantly frees the budget), and the soundfont panel
  **stacks multiple .sf2 files**: drop them one after another, each
  gets a group header with an unload ×, and slots from any font drag
  onto the pool side by side.
- patcher.html shows the **audio-RAM budget**, not just the ROM one: a
  second bar tracks the pool against the 59.2 KB of ARAM samples share
  with the echo buffer, reporting the echo headroom the console will
  allow (`EDL n = n*16 ms`) — red with a warning when samples overflow
  and would fall silent. `sndj.js` owns the calculator
  (`aramBudget`, mirroring `pool.asm`'s residency math, selftested).
- patcher.html: soundfonts now open in their own **panel beside the
  pool** — drop an `.sf2` (on either drop zone) and every sample
  becomes a slot with its own **play** button, auditioned through the
  real console pipeline (root-key resample or 8 kHz one-shot, then
  BRR encode/decode) with the panel's mode/trim/cap settings.
  **Drag a soundfont slot onto a pool slot** to import it there — the
  old pick-a-preset dropdown is gone.

- **Sync (M12, console side) + MIDI takeover (M14, console side).**
  OPTIONS → SYNC now works: **IN** follows a sibling master one row
  per clock, **IN24** follows the 24-PPQN Ableton Link bridge (÷6) —
  both with WAIT arming (Start holds silently, the first clock plays
  row 0) and lossless 2-bit catch-up, wire-identical to genmddj so no
  bridge reflash is needed. **PULSE** drives a 2 PPQN Volca/PO clock
  on pin 6. **MIDI** turns sndj into an 8-voice sample module:
  channels 1-8 map onto V1-V8, velocity → level, Program Change →
  instrument, pitch bend ±2 semi, CC 7/10/91/74 = vol/pan/echo/FIR,
  with a live RX monitor on OPTIONS. OUT is selectable but inert for
  now. The mode persists on the cart. Hardware bring-up still to come
  (checks inject clocks/frames on the real pin-read paths).

- Command reshuffle to match the family: **`X` is now volume/accent**
  (as in genmddj) — `X xy` sets the voice's level (both sides, 00-7F),
  persisting like `P` until the instrument reloads. **The echo send
  moved to `E`** (`E01` in, `E00` out). Accent, pan (`P`), surround
  (`U`) and tremolo now compose: they all act on one live per-voice
  level instead of fighting over the DSP registers. 24 letters live.
- Instruments gained **VIB** and **TRM** (smsggdj-style): vibrato and
  tremolo as instrument settings, speed·depth nibbles each. VIB is the
  familiar triangle pitch wobble on every note; TRM dips VOL L/R below
  the set level (down only, so it composes with the hardware ADSR).
  The `V` command now *overrides* the instrument's VIB for one note
  (`V00` = straight), and works from tables too (it was inert there).
- PHRASE: tapping B on a `C` chord command auditions the chord (root
  + both offset voices) through the row's note and instrument. Command
  cells now only accept a B-tap insert while empty (the genmddj rule),
  so auditioning can never overwrite a written command.

- SNDJ1 v2 saves: genmddj-style variable packing — a 16-entry
  directory over one dense ~31.7 KB heap replaces the four fixed
  slots. Saves append and flip the entry; overwrites and clears close
  their holes by sliding the tail (per-song CRCs guard a power cut
  mid-slide). Old v1 saves reformat on first boot.
- The repo split into toolchain and musician halves: the browser apps
  (patcher, savetool, firdesign) and sndj.js moved to `user-tools/` —
  download that one folder and everything runs locally, no toolchain.
- MANUAL.md: the player's guide — controls, screens, the full
  23-command reference, the echo/FIR room chapter, saving, tools.
- sndj.js gained a sample-accurate S-DSP model (ported from blargg's
  snes_spc): BRR through the real Gaussian interpolator, hardware
  ADSR/GAIN with the rate-counter table, noise LFSR, pitch modulation,
  and the full echo/FIR/feedback path with the chip's truncation
  quirks — the keystone that lets the browser tools play actual
  console sound. Plus a WAV builder for offline renders.
- FILES looks like genmddj now: SRAM/FREE readout, a divider carrying
  the song count, names with decimal sizes (N.NKB), block cursor on
  the name, and the rename ring runs blank-A..Z-specials one way and
  digits the other. savetool.html/.py and sndj.js speak v2.
- Fixed: renaming in FILES (B-hold + Up/Down on a name character) —
  the character-ring search clobbered the name index, so the new
  letter landed at the ring position instead of the name (silently
  overwriting header bytes up to the FIR taps). Works on both the
  working song's name and saved slots; regression checks added.

- Instrument tables grow up: TBL has a real nil state (-- ; factory
  instruments ship with no table) and a TBS field clocks the table —
  n ticks per row, or 0 to advance one row per note with the position
  persisting across triggers. INSTR's ECHO field reads ON/OFF.

- OPTIONS: VIDEO now reads the detected console standard (NTSC 60HZ /
  PAL 50HZ via STAT78) — the SNES can't switch standards in software,
  and tempo/pitch ride the region-free APU crystal either way; the
  redundant CLOCK row is gone.
- Map: OPTIONS<->PROJECT and FILES<->GROOVE link left/right; KIT sits
  above TABLE (A+Up/Down); the WAVE->KIT hop is removed so A+Right on
  WAVE is purely bank select.

- Minting and cloning (genmddj §4): B double-tap on an empty SONG/
  CHAIN reference cell mints the next free blank chain/phrase; on a
  populated cell it clones into a fresh slot and repoints. OPTIONS
  gains CLONE SLIM/DEEP (persisted): SLIM chain clones share phrases,
  DEEP copies them (duplicate entries stay consistent; falls back to
  SLIM when phrases run out). Phrase clones are always independent.
  A matching-kind clipboard still pastes.

- TABLE screen + runtime: 32 tables of 16 rows x two (command, value)
  columns run per tick through the shared executor; the instrument's
  new TABLE field starts its table at every trigger, and H inside a
  table hops the table's own rows (row-scoped D/I/J are inert there).
  A+Right from INSTR follows the instrument's table; playhead markers
  show live positions.
- Splash lost the pad-echo test row; A+B plays a phrase/chain from its
  top; the command set is settled at 23 (E/O/W dropped).

- Eight more commands: C chord override (C47 fans a major chord onto
  the two voices to the right of ANY instrument; C00 back to the
  record's GRP), F fine tune, M master volume, N noise clock, S sweep
  up/down, Q GAIN override (direct + the four hardware ramps, Q00 back
  to ADSR), U surround (invert L/R phase), Z pitch-mod enable. 21 of
  25 planned commands now live; E I O W remain.

- Boot splash carries the tri-pixel SNDJ wordmark (art/sndj-logo.png
  via makelogo.py, drawn in the palette text colour) over a full-width
  inverted version band and the git build stamp — the genmddj layout.

- SF2 import in the browser: patcher.html takes .sf2 drops on any pool
  slot with a preset picker and melodic/one-shot modes — the exact
  factory pipeline (root-key bake, exact-loop resample, tune fields),
  mirror-tested byte-identical between JS and python.
- FIR screen (A+Right from ECHO): the song owns its 8 taps now (saved
  in the header); B+d-pad edits them live, Y+up/down recalls ROM
  presets, hand edits read as a custom curve. ECHO's FIR field and the
  Y command copy presets into the song's taps.

- Screen titles and track headers render plain (only cursors/selection
  invert); track columns are numbered 1-8; grids sit one row lower.
- TMPO is editable on PROJECT (80-255, drives the APU timer instantly
  and at play start); the GROOVE readout scales with it.
- WAV instruments play in tune (C-4 = 261.6 Hz): the 32-sample loop
  gets a +1 semi / -52 fine tune context and a single octave drop
  instead of the flat -2 octaves. Auditions match playback.
- FILES matches genmddj: the action menu adds PURGE PH / PURGE CH
  (blank data unreachable from the SONG grid, FREED nn report), CLEAR
  compacts the packed list, LOAD on the (EMPTY) row blanks the working
  song for a fresh start.

- Palettes are two colours (bg + text), genmddj-style: cursors,
  playheads and titles render as palette negatives via an inverted
  glyph set; dim derives as the channel average. Deleting a note also
  deletes its instrument; B-hold + d-pad on an empty note cell inserts
  immediately; auditions only sound while the transport is stopped.

- GROOVE screen (A+Down from CHAIN): edit each groove's 16 ticks-per-
  row steps live (B+d-pad, clamped 1-15; B tap repeats; Y+up/down
  pages grooves) with a derived BPM readout and a playing-step marker.
  Tempo is finally editable — grooves ARE the tempo.
- PROJECT screen (A+Up from CHAIN): song name, TMPO readout, default
  groove, song transpose (applied at trigger), MODE SONG/LIVE (LIVE
  makes the S map position open the launcher), and NEW with a
  tap-to-confirm.

- patcher.html gains a palette editor (8 schemes x 5 colours, snapped
  to 15-bit BGR) alongside the sample pool; factory defaults (track
  instruments + kit layout) are marker-wrapped as SNDEF0 so tools can
  re-voice a built ROM. Verified end to end: a ROM patched purely via
  markers boots with the patched colours and defaults.

- Tuning fixes by ear: SW SLAP +1 semitone, MP RECRD +2 (per-pick trim
  field in the pool builder for wrong font root keys).
- The ECHO screen's EDL edit now clamps to the ARAM actually free
  above the resident samples, so the echo buffer can never grow into
  (and corrupt) sample data; regression-checked.
- Kit 0 gains SW ROLL — the riding-Yoshi drum roll from the SMW font.

- PHRASE editing flow: inserting a note also writes the last-used
  instrument; tapping B on the IN column auditions that row's note
  with the inserted instrument; inserting a command brings its last
  value along with the letter.

- Transport: Start plays/stops the whole song on every screen; A+B is
  the contextual control — stop when playing, else play all tracks
  from the cursor (SONG), just the chain (CHAIN) or just the phrase
  (PHRASE).
- A chain in the song grid loops back to the top of its contiguous
  block instead of running into empty rows (with a guard so a block
  that never yields a phrase halts the track gracefully).

- Factory melodics now come from the Mario Paint soundfont, picked by
  preset: AC GUITR, AC BASS, SQUARE, ORGAN1, TRUMPET, GLOCKEN, VIBES,
  RECORDER. Drums stay the provided 808/909 kits.
- Factory content is the classic-SNES songbook now: 16 pitched
  instruments led by the SMW four (XYLO, STEEL, EPIANO, SLAP) and the
  Mario Paint three (SQUARE, RECORDER, GUITAR), then TBONE, TRUMPET,
  STRINGS, NYLON, SAX, ORGAN, VIBES, GLOCKEN, ABASS. Three kits: SMW
  percussion (kit 0, the track-8 default), Mario Paint percussion
  (kit 1) and the MP toybox (kit 2: bongos, tom, splash, slide
  whistle, glass, honk, baby, voice, cheering). Sample-folder kits
  (808/909) are retired for now. Kit one-shots live at 8 kHz (slots
  tune -24); 47 samples resident at 51.8 of 60.7 KB.

- Project renamed **sndj** (in line with smsggdj/genmddj): ROM is
  build/sndj.sfc, splash and cart title updated. Save magic (SNDJ1),
  song files (.sndj) and the JS library (sndj.js) already carried the
  name.

- Block select everywhere (Y+B, stretch, B copy / Y cut / A cancel,
  B double-tap paste) on PHRASE, CHAIN and SONG.
- Single-cell cut is B held + A tap (the cut value feeds the next
  insert, as before).
- SONG/CHAIN/PHRASE grids sit four rows lower (headers at row 7,
  grids at row 8) and PHRASE cells line up under the NOTE/IN/CMD ruler.
- Palette schemes: the genmddj 8 (BLK default, WHT, KIDD, AMBR, CYAN,
  PINK, NEON, MINT), selectable on the new OPTIONS screen (A+Up from
  SONG), applied instantly, persisted in SRAM; solid backdrop; marker-
  wrapped SNPAL0 block for patching.
- Fixed the SMP pitch step at loop entry: looped SF2 samples now
  resample so the loop is an exact BRR-block multiple (the old
  block-snapping retuned the looped section against the attack by up
  to ~2 semitones); the small stretch residual rides the pool entry's
  tune fields. Pool entries are named after their SF2 presets
  (FLUTE2, STEELGUI, SLAPBASS, SHAMISEN, TRUMPET, ...).
- Right-column chrome moved to the top right, smsggdj-style: 16-bit
  tick counter (APU? on fault), PLAY/STOP, then the mini map with the
  sibling letters (PHRASE = P, FIR = F); MIDI and LIVE left the map.
- FILES is genmddj-style: slot list with names and sizes, (EMPTY)
  slots, live renaming (B-hold + d-pad), A+B action menu with
  SAVE / LOAD / CLEAR, a used-slots readout; playback stops on entry.
  Songs carry an 8-character name in the song header.
- Channel switching: L/R shoulders (or Y+left/right) hop tracks on SONG,
  CHAIN and PHRASE.
- Per-instrument echo send (ECHO field) and fine-tune (FINE field,
  1/256 semitone with table interpolation).
- All 64 instrument slots ship populated: every pool sample, the eight
  wave banks, both kits and noise are playable from a new song.
- Factory pool retuned from the SF2 root keys and resized (16 kHz drums,
  loop-end truncation) so all 40 samples are resident at once.
- New browser tools: savetool.html (cart saves and .sndj songs, with a
  savetool.py CLI twin) and firdesign.html (FIR designer that patches
  ROM preset slots).

- **M1 — Boot & bus.** LoROM/FastROM skeleton boots to a splash with version +
  git build stamp, HDMA backdrop gradient, custom 8x8 UI font, factory
  palette, pad input with DAS auto-repeat, and a cursor grid stub.
  Headless verification: `make check` (Mesen 2 testrunner asserts),
  `make shot` / `make shot-diff` (golden screenshots).
- **M2 — APU bring-up.** SPC700 driver (wla-spc700) uploads at boot via the
  IPL protocol; flip-bit mailbox with timeouts everywhere; SCB register
  writes land in the DSP; APU tick telemetry on port 3; a dead APU shows an
  `APU?` warning instead of hanging.
- **Kits, residency & game-authentic factory content.** LSDJ-style kits:
  16 kits x 16 slots (sample + signed tune + volume), notes pick slots
  chromatically; KIT screen (A+Right from WAVE) with per-slot audition;
  factory kits 0/1 = the 808 and 909 from samples/. Pool format v2:
  block-addressed offsets spanning ROM banks 1-5 (up to 160 KB), factory
  pool = 8 SSF2 melodics + 32 drums. Per-song sample residency: only the
  samples a song references upload to ARAM (scanned from instruments +
  kit slots, echo-aware budget, silent-stub fallback); sample-field edits
  re-upload live. H now hops immediately (the H row plays the next
  phrase's row 0, so phrases shorten cleanly). FIR presets are
  marker-wrapped (SNFIR0) for browser patching. NEW seeds instruments
  0-7 (5 samples, wave, noise, kit) matching the planned MIDI defaults.
- **M13 — LIVE mode.** The clip launcher: Select toggles LIVE from any
  screen; B queues the cursor cell's chain on its track and it launches
  exactly at that track's next phrase boundary (quantised — verified to
  the row); from stopped, B launches immediately. X+up/down mutes the
  cursor track (voices keyed off), X+left/right solos (again to clear).
  Per-voice ENVX telemetry streams up from the driver into header meters
  (flat in Mesen, which doesn't service live ENVX reads; real on
  hardware — the same path verifiably round-trips FLG).
- **M11 — Sample pool & the first browser tool.** Self-describing SNDJPOOL
  in ROM (marker-wrapped, 16 KB reserved so it can grow in place): six
  factory samples — pad, bass, pluck, and synthesized kick/snare/hat —
  uploaded at boot with an auto-built ARAM directory. KIT instruments (v1)
  map notes chromatically onto pool samples at native rate. `tools/sndj.js`
  lands: the shared JS library (BRR codec byte-matching the Python
  reference, pool format, RLE, CRC, tuning), node self-tested.
  `tools/patcher.html`: drop a ROM, replace pool samples with WAVs
  (resampled + BRR-encoded locally), audition the decoded BRR, export a
  checksum-fixed patched ROM — verified end-to-end by booting a
  node-patched ROM through checks/pool.lua.
- **M10 — Wavetables & noise (KIT waits for the M11 sample pool).** WAVE
  screen: draw 32-sample single-cycle waves with the pad (B+up/down shapes,
  B+left/right drags, Y+left/right pages banks); every edit compiles the
  bank to a tiny looped BRR and re-uploads it live. 8 factory waves seeded
  by NEW; waves save with the song. WAV instrument type plays the drawn
  banks; the B command wave-sequences banks per row; NSE type drives the
  DSP noise generator with the note as the global noise clock.
- **M9 — Echo & FIR.** The ECHO screen: delay (with its ARAM cost shown
  live), feedback, echo volume L/R, per-voice send mask, FIR preset with
  tap display; 8 factory FIR curves; X (echo send on/off) and Y (FIR
  preset) commands. EDL/ESA changes run a driver-side safe sequence that
  also waits out the DSP's free-running echo offset — without that wait, a
  shrunk delay line writes past its buffer and wraps into low ARAM,
  eating samples (now a regression check). Echo config saves with the song.
- **M8 — Save/load.** SNDJ1 SRAM format (SAVEFORMAT.md): 4 journalled slots
  over 5 regions — a save packs into an always-free region and flips the
  table entry last, so a power cut can't eat the previous good save.
  Column-planar RLE (an empty song packs to ~220 bytes), CRC-16 guarded
  loads, FILES screen (A+Down from SONG). `make test` runs the Python RLE
  mirror; the emulator check decodes the console-packed SRAM bytes in Lua
  and requires a byte-identical song block after save -> corrupt -> load
  -> hardware reset -> load.
- **M7 — Commands (partial: TABLE screen still to come).** The command
  executor with per-tick effect processing on every track: A arpeggio,
  D delay (within the row), G groove select, H hop, K kill, L slide/legato
  (no retrigger, exact-target landing), P pan, R retrigger, T tempo (the
  APU timer is retuned live — grooves stay the fine tempo), V vibrato.
  DAS auto-repeat is now frame-delta based so heavy screens can't slow it.
- **M6 — Instruments.** INSTR screen (field-list editor: type, sample, full
  ADSR, stereo volume, GRP span + three semitone offsets); per-track
  instrument selection from the phrase column with per-voice register
  shadows (regs only ship when the instrument changes); GRP chords: one
  phrase column drives up to three extra voices with offsets; auditions
  use the row's instrument.
- **M5 — Data model complete.** SONG (8 tracks x 128 rows) and CHAIN screens;
  A+d-pad navigates the screen map (SONG <-> CHAIN <-> PHRASE, descending
  through the cursor's context); 8-track chain playback with per-entry
  transpose, per-track song-row advance, batched KON/KOF; Y+B is cut
  (deleted value becomes the next insert); Start plays what the current
  screen shows (song / looped chain / looped phrase).
- **M4 — Engine core.** WRAM song block (128 phrases, 64 chains, grooves);
  groove-driven row engine clocked by the APU timer (region-free 60.15 Hz
  ticks); PHRASE screen with the sibling B-grammar (tap insert+audition,
  B+d-pad nudge by semitone/octave, Y+B clear), playhead.
- **M3 — First voice.** BRR encoder/decoder (`tools/sndj_brr.py`, brute-force
  filter/range search, bit-exact decode, self-tested); factory loop-pad
  sample + directory bulk-uploaded to ARAM; pitch table generated from a
  single tuning source; B on the grid auditions a two-octave C-major scale
  on voice 0 with hardware ADSR. (`make wav` arrives with the sndj.js DSP
  model in M15 — Mesen exposes no headless audio capture.)
