# Changelog

## 0.1.0-dev (unreleased)

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
- Kit 2 is the Mario Paint kit: KICK, SNARE, SNAP, WOOD1/2, POP, DOG,
  CAT, PIG, BIRD, YOSHI, UNDO DOG (16 kHz one-shots, slots 12-15
  free); instrument 58 plays it. All 52 pool samples stay resident.

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
