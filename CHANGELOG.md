# Changelog

All notable changes to sndj. First release will be **v0.1**; versions
increment by **0.01** thereafter (v0.1 → v0.11 → v0.12 → v0.13 → …).

## Unreleased

- SLICE instruments now interpret TABLE TSP as a slice-selection offset and
  retrigger the chosen division while leaving pitch under the instrument's
  TUNE control. CHAIN TSP slice rotation is now covered by the same regression.

## v0.13 — 2026-07-13

- Fixed SF2 root-key conversion to match sndj's C-5 reference convention, so
  imported samples retain the intended pitch when converted and placed in the
  ROM pool.
- Reworked the patcher's import/export workflow into a compact top bar, kept
  ROM and audio-RAM budgets visible while browsing the pool, and made SF2
  source auditioning clearly separate from the root-pitch converted result.
- Removed the synthesized grey/dim UI shade. Every scheme now emits only its
  exact foreground and background colours; secondary text uses full contrast
  and cursors/playheads preserve hierarchy through two-colour inversion.
- Added a dedicated Link/cross-console wiring guide for XIAO ESP32 → sndj
  IN24 and genmddj OUT → sndj IN, including safe level conversion and staged
  hardware bring-up procedures.
- Changed SYNC IN to a one-wire Data1 row-toggle input. Each D0 transition is
  one row clock; IN24 retains the full two-bit counter and burst catch-up.
- Removed all bundled sample recordings, game SoundFonts and the derived
  factory container. The repository now ships a lean, copyright-free project
  factory with 8 authored sounds and 40 blank slots; raw samples, SoundFonts
  and personal factory exports remain ignored by Git. If the project factory
  is absent, clean builds generate a deterministic synthetic fallback.
- Added an untouched-ROM factory smoke test and made the core emulator checks
  independent of factory tuning and content. The new boot set leaves enough
  audio RAM for the maximum 240 ms hardware echo delay.
- Pinned screenshot tests to the default black palette and refreshed their
  goldens, preventing local emulator SRAM from changing visual results.
- Added the MIT license text and an explicit third-party/audio policy.
- Browser file handling now validates pool, SF2, RLE, `.sndj`, SRAM and
  factory-container bounds before allocation or mutation; corrupt saves are
  read-only rather than silently rebuilt.
- Fixed exact-capacity ARAM budgeting and ROM markers at the final legal byte.
- Uploaded filenames/sample names are rendered as text instead of HTML.
- SF2 mirror tests now generate their own copyright-clean test SoundFont.
- Added a GitHub Actions clean-build/host-test and bundled-audio gate.

## v0.12 — 2026-07-12

- **LIVE mode grows up into a real clip launcher** (Seb):
  - **A+B queues, launches and stops.** On a populated cell it
    queues that chain on its track (launching right away from
    stopped); on the cell the track is *playing* it queues that
    track's stop instead — it never re-triggers the chain you're
    hearing. Queued chains take over at the playing track's phrase
    boundary; cues on *silent* tracks fire at the next bar (16 rows)
    so they land in time with the others (before, they never fired
    at all).
  - **Plain B is edit-only**: it inserts a chain on an empty cell
    (A+B then launches it) and is inert on occupied cells — a stray
    tap can't trigger or overwrite anything mid-performance.
  - **Markers**: a steady **▸** on each track's playing cell, a
    *flashing* **▸** on a cued chain waiting for its boundary, an
    **X** on a track draining toward a queued stop (the X follows
    arrangement playheads too, not just LIVE launches).
  - **The launcher is on the map**: A+d-pad navigates from LIVE as
    if on SONG (up OPTIONS, down FILES, right drills into the cursor
    chain), and L/R or Y+←/→ switch tracks.
- Fixed: **the first LIVE launch after power-on started all eight
  tracks** — the pending-launch slots live in boot-zeroed RAM where
  0 reads as "chain 0 queued"; they are now seeded at boot and
  cleared on stop (regression check `livecue.lua`, 20 asserts over
  the whole launch/cue/stop/insert/nav lifecycle).
- HELP pages reordered (Seb): INSTRUMENT TYPES and SAMPLES AND
  MEMORY are pages 4–5, the command reference pages 6–7.
- HELP grows two pages (now 8): **SAMPLES AND MEMORY** (the ROM pool
  vs audio RAM, what loads at boot, on-demand loading, the echo
  trade) and **INSTRUMENT TYPES** (all six, one screen).
- **CLONE defaults to DEEP** (Seb) — fresh/unset carts clone chains
  with independent phrases; an explicit SLIM choice still persists.

- **Start honours the song cursor from EVERY screen**: drill into a
  chain or phrase and Start sounds the context you're looking at
  (the shared transport plays from the SONG cursor row everywhere).
- **Start on SONG plays the arrangement AT the cursor row** (Seb —
  the LSDJ feel): every track enters at the chain at-or-above that
  row (the one covering it) and loops its block; columns with nothing
  above stay silent. Entry semantics flipped from at/below to
  at/above everywhere (starting mid-song now sounds like the song
  sounds there). A+B on SONG remains the same gesture.
- **Per-track playhead triangles on SONG**: each playing track shows
  a triangle in the gap to its cell's left — 8 independent heads,
  still nothing painted over the numbers.

- **Signal metering is out for now** (Seb): the LIVE header shows
  mute dashes only — no ENVX bars. The driver's ENVX telemetry keeps
  streaming (checks use it, and a future readout can too).
- **Playback = the gutter triangle, full stop** (Seb): cells are
  never painted over. On SONG a triangle marks every row some track
  is playing (the 8 tracks are independent heads, so several can
  show at once); CHAIN/PHRASE/GROOVE mark their one playing row.
  The old cell "highlight" was pixel-identical to plain text in the
  2-colour schemes anyway — now the design says what the pixels
  always said. (ATTR_PLAY — a soft grey block style, BG3 palette 4 —
  stays available in the toolkit, currently unused.)

- patcher: **monochrome** — black, white text, white-bordered columns
  and sections (the tool now dresses like the console). The factory
  file moves to **`factory/factory.sndjfact`** (its own folder + a
  README on how to update it); `make` reads it from there.

- patcher: **drag a pool slot's number onto another row to swap the
  two slots** — kit slots and boot instruments reference pool indices,
  so they're remapped in the same move (the sounds stay put, the
  order changes). Settle the order before writing songs against the
  ROM: songs in cart saves hold indices too.

- **The lean factory** (Seb, rev 10): 18 samples — 7 melodics
  (xylophone, honky-tonk, nylon guitar, trombone, steel drum, slap
  bass, crystal) + drums incl. VOICE 3 — one KIT, boot set = 7 SMP +
  KIT 0, ~31 KB resident, echo headroom to EDL 14 on a fresh song.
  Built to be added to: 30 free pool slots, kits 1-15 blank.
  SNDJFACT v4.

- patcher: **the pool loop is yours to toggle** — the loop cell on the
  POOL tab is clickable (looped ⇄ one-shot, with the original loop
  point restorable), assigning a looped entry to a kit slot warns in
  the status line, and degenerate soundfont/WAV loop metadata
  (zero-length / sub-block loops) now reads as one-shot on import.
  Ripped soundfonts set their loop flags unreliably in both
  directions, so the import keeps honest shape-based detection and
  the toggle is the per-entry override — kits play the pool's truth.

- **Boot instruments are 8 again** (SNDEF3, was 12): one per voice,
  lining up with the MIDI channel map — and period-correct (classic
  SNES scores kept ~8-15 samples resident per song). Instruments 8-63
  still auto-populate as SMP on sample 0, so every slot plays out of
  the box. The patcher BOOT tab is a **proper aligned table** now
  (label / type / sound / loop-or-slices columns — the KIT row no
  longer breaks the grid) and reads/writes the SNDEF3 rows.
- patcher BOOT tab: each SMP boot instrument gets a **LOOP selector**
  (POOL / ON / OFF) — it writes the SNDEF2 extras bits the console
  copies into the instrument's LOOP field on a fresh song, so you can
  ship a ROM whose boot instruments loop (or don't) the way you want
  without touching the INSTR screen first.
- patcher: dropping an sf2 one-shot **onto a kit slot** now bakes the
  8 kHz correction (−24) into the **pool entry's tune**, like the
  pool-slot import path, with the kit slot's tune left at 0 for
  musical detuning. Before, the correction lived in the kit slot, so
  the same pool sample played two octaves sharp from the pool tab's
  play button — and would have on the console too through SMP/SLICE.
- patcher: the pool's audio-RAM column now mirrors the console
  exactly and names its reasons — **boot** (referenced on the BOOT
  tab; sample 0 is always resident because a fresh song points
  instruments 12-63 at it — previously missed), **kit** (pulled in by
  a kit slot with volume, any of the 16 kits), or **·** (ROM only,
  loads on demand).

## v0.11 — 2026-07-11

- **Hardware: the mailbox is glitch-proofed.** On real silicon an
  SPC700 port read that collides with the S-CPU's write returns mixed
  bits (emulators don't model it); the bulk-upload loop accepted any
  changed byte as a round counter, so uploads sheared by 3 bytes
  (garbled instruments) or ended on a phantom zero (silent
  instruments, different every reset — the two clocks are async, so
  the collision phase moves each boot). The driver now double-reads
  port 0 until stable and accepts only the expected successor counter;
  the CPU resyncs and retries a failed upload once; the LOOP bit is
  patched into the stream in transit (one bulk session per sample,
  half the exposure). The APU? indicator also actually fires now: the
  heartbeat used an exact-frame gate that ~30 fps screens could miss
  forever — it's a frame delta like every other periodic gate.
- **Hardware: palette 7 no longer greets every reset** — real SRAM
  powers up as $FF and `$FF & 7 = 7`; the format path now seeds all
  option bytes and the boot loaders range-check instead of masking
  (unwritten CLONE also read as DEEP).

- **Tables are now V · TSP · CMD** (was two command columns): per
  tick a table row can set the voice level (01-7F, X-style), bend
  the playing note by signed semitones, and run one command. $00 =
  no change per column, so old blank tables stay no-ops; the byte
  layout changed (SAVEFORMAT.md updated in step). The reference
  sequencer mirrors it; `checks/table.lua` covers V, TSP (exact
  octave doubling) and the command column.
- **KIT number is a readout again**, not a field — **Y+↑/↓ pages
  kits**, the same family gesture that pages chains, phrases and
  tables. Slots start at the top row.
- Y-paging on CHAIN/PHRASE no longer leaves a stale digit in the
  title (the "CHAIN 000" look — the redraw was one column right of
  the first draw).
- PROJECT drops **NEW** (FILES owns it: LOAD on the empty row);
  MODE is the last field.
- INSTR block up a row and left a column; a breathing row between
  SYNC and the timing fields on OPTIONS; TABLE VAL reads as dashes
  until its command exists.

- **Button timing is yours now** — three new OPTIONS fields, all
  persisted on the cart: **KEY DELAY** (frames before d-pad
  auto-repeat, 4–30), **KEY RATE** (frames between repeats, 1–8) and
  **TAP WIN** (the B double-tap window for paste/mint/clone, 10–40).
  genmddj hardcodes these; sndj sets the family precedent.
  New regression: `checks/options.lua` (edits, clamps, SRAM bytes).
- Screen layout pass: OPTIONS and PROJECT blocks up 3 rows and left
  a column; the KIT grid left a column and down a row; the TABLE
  grid left a column. The OPTIONS **PALETTE** value is now just the
  scheme number — the old 4-char name read a table that had moved to
  ROM bank 6 with a bank-0 read and drew garbage.

- **spcexport.html**: **listen** in the browser (streaming playback
  through the console-sound model), `.sndj` → **WAV** (offline render
  with structural loop detection to size it — this IS the "make wav"
  of sndj: browser-side, no emulator, no CLI) and → **`.spc`** (the
  sequencer's DSP register
  stream for one song loop + the song's samples + a ~100-byte SPC700
  replayer, in a standard 66048-byte file any SPC player runs — the
  SCB architecture as an export format). ARAM budget is reported;
  over-budget songs get a clear ✗, never a silent truncation. The
  hand-assembled replayer is executed and verified event-for-event
  by a micro-interpreter in `make test` (tools/test_spc.js).

- **The reference sequencer** (`sndj.js`): a JS mirror of the console
  engine — tick pipeline, groove, all six instrument types (SMP, KIT,
  WAV, NSE, SLICE, KARP), the full A–Z executor, tables, GRP/chord
  fanout, vibrato/tremolo/slide/arp, residency (the exact ARAM image
  a song load builds) — driving the sample-accurate S-DSP model.
  Renders `.sndj` songs to audio at ~100x realtime; self-tested in
  `make test` (row timing, X/OFF/T semantics, end-to-end audio).
  This is the keystone for the savetool preview, spcexport and
  headless WAV renders.
- **savetool.html song preview**: drop the matching `sndj.sfc` next
  to the save and every song gets a play/stop button — the reference
  sequencer + S-DSP model play the real console sound (samples, echo,
  FIR, KARP and all) in the browser.

- savetool.html catches up with its own manual: **rename** (the same
  A-Z 0-9 - . alphabet as the console's FILES rename — names matter,
  saves are name-keyed), a per-slot read-only **SONG/CHAIN/PHRASE
  viewer**, and a heap **free-bytes** readout under the slot list.

- **als2sndj.html**: Ableton / MIDI / MML ⇄ `.sndj` converter
  (browser, offline). Imports Live Sets and Standard MIDI Files —
  first 8 tracks → V1–V8, tempo → TMPO, velocity → `X`, real `OFF`s
  at note ends; exports a song back to a Session-view `.als` or to
  editable MML text. Built-in SONG/CHAIN/PHRASE viewer; pool-limit
  truncation is always reported. ALS.md documents the mapping;
  `tools/test_als.js` round-trips fixtures in `make test`.

- Splash: the screen comes up **before** the audio upload with a
  LOADING AUDIO line (a black screen used to sit there for the ~1.5 s
  sample transfer), then swaps to PRESS START; the version and git
  hash share one band line.

- **HELP screen** (genmddj-style): six generated pages — navigation,
  editing, block ops, the data model, the full command reference
  (merged from tools/commands.csv, one source of truth), and an about
  page with the live version stamp. Plain d-pad turns pages. **Hold A
  alone for ~2.5 s on any screen to toggle HELP** and again to jump
  back where you were; the boot screen hints it. Content lives in
  help.txt — edit it freely, `make` validates and regenerates.
- Map: **KIT moves below PHRASE** (reachable from GROOVE, PHRASE and
  ECHO); **HELP takes the cell above TABLE** (vertical entry only,
  like genmddj).

## v0.1 — 2026-07-10

The first release: the full console tracker (milestones M1-M14 —
sequencer, six instrument types, echo/FIR, saves, LIVE, sync + MIDI
takeover console-side) plus the browser patcher/savetool ecosystem.
Everything below is what v0.1 is made of, newest first.

- **One groove, two steps** (Seb's call): the groove is a single
  public pair of tick counts — 6/6 straight, 7/5 lilt, 8/4 swing —
  and **`G xy` writes it directly** from a phrase (no more groove
  tables to manage). The GROOVE screen edits the two steps with the
  live BPM readout; PROJECT drops its groove-select field. The old
  16-groove pool region stays in the save layout (RLE packs it to
  nothing), so saves are untouched.

- ECHO's content moves down two rows (ledger from y4, fields from
  y8) — clear of the title line, matching the family layout.

- Map: **TABLE and FIR link vertically** (A+Down / A+Up) — the FIR
  screen sits directly below TABLE in its column.
- KIT: the **kit number is the first field** (INSTR grammar) — cursor
  up to it and nudge to edit any kit in place; Y+left/right still
  pages. The number reads plain until the cursor lands on it.

- TABLE and FIR grids start at the family height (header y4, rows
  from y5) — same as PHRASE and INSTR.
- PROJECT highlights and navigates the **values**, not the labels
  (same convention as ECHO/INSTR/OPTIONS).

- INSTR packs its layout per type: hidden fields no longer leave
  empty rows behind (KARP is 10 rows, not 24 with a void above
  TBL/TBS), a blank line still separates the groups, and every row
  fully overdraws — which also kills the stale-text artifacts
  (FADE wearing DECAY's Y, SAMPLE showing CLOCK's NOTE). SMP's
  layout is pixel-identical to before, so nothing moves for the
  common case.

- KARP BURST re-ranged to seed lengths that make sense for a string:
  the top is the classic Karplus-Strong pluck (~one loop transit),
  the bottom bows the string — no more second-long drones leaking
  into the loop at low values. (Classic KS seeds one *period*; our
  loop is 16/32 ms of many periods, so the right seed is one loop
  transit of pitched energy, gated hard.)

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
