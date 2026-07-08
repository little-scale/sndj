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
- **M3 — First voice.** BRR encoder/decoder (`tools/sndj_brr.py`, brute-force
  filter/range search, bit-exact decode, self-tested); factory loop-pad
  sample + directory bulk-uploaded to ARAM; pitch table generated from a
  single tuning source; B on the grid auditions a two-octave C-major scale
  on voice 0 with hardware ADSR. (`make wav` arrives with the sndj.js DSP
  model in M15 — Mesen exposes no headless audio capture.)
