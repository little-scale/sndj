# Changelog

## 0.1.0-dev (unreleased)

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
