# Changelog

## 0.1.0-dev (unreleased)

- **M1 — Boot & bus.** LoROM/FastROM skeleton boots to a splash with version +
  git build stamp, HDMA backdrop gradient, custom 8x8 UI font, factory
  palette, pad input with DAS auto-repeat, and a cursor grid stub.
  Headless verification: `make check` (Mesen 2 testrunner asserts),
  `make shot` / `make shot-diff` (golden screenshots).
- **M2 — APU bring-up.** SPC700 driver (wla-spc700) uploads at boot via the
  IPL protocol; flip-bit mailbox with timeouts everywhere; SCB register
  writes land in the DSP; APU tick telemetry on port 3; a dead APU shows an
  `APU?` warning instead of hanging.
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
