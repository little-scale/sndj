# sndj user tools

Everything in this folder is for **musicians**, not developers: no
toolchain, no install, nothing to compile. Download the folder (keep
`sndj.js` next to the `.html` files) and open any tool in a browser —
they run entirely locally, nothing is uploaded anywhere.

| Tool | What it does |
|------|--------------|
| `patcher.html` | Drop a built `sndj.sfc` and replace pool **samples**, **kits**, **boot instruments**, **FIR presets** (a full designer with a live frequency-response plot and echo-loop audition) (WAV or `.sf2` drops, auditioned through a bit-exact BRR + Gaussian model of the console), **palettes**, and **factory defaults** — then download a patched ROM with a fixed checksum. |
| `savetool.html` | Drop a cart save (`.srm`) to view, extract, insert, rename and erase songs as portable `.sndj` files — plus a read-only song viewer, and (with the ROM dropped alongside for its sample pool) a **play button per song**: the reference sequencer + S-DSP model render the real console sound in the browser. |
| `als2sndj.html` | Drop an Ableton Live Set (`.als`), MIDI file (`.mid`) or MML text and get a `.sndj` song (tracks → V1–V8, tempo → TMPO, velocity → `X`, note ends → `OFF`) — or drop a `.sndj` and get a Live Set / MML back. Built-in song viewer. See `ALS.md`. |
| `spcexport.html` | Drop a `.sndj` (or `.srm` + pick a slot) plus the ROM: render the song offline to a 32 kHz stereo **WAV**, or capture one song loop as a standard **`.spc`** (register log + samples + a ~100-byte replayer) that plays in any SPC player. |

`sndj.js` is the shared library behind all of them (save format, BRR
codec, S-DSP model). It is also a Node module: `node sndj.js --selftest`.
