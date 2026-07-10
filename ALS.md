# Ableton / MIDI / MML ⇄ sndj converters

**Built — `user-tools/als2sndj.html`.** A browser tool (offline, no install)
that gets music into and back out of sndj three ways:

- **`.als` / `.mid` → `.sndj`** — Ableton Live Sets and Standard MIDI Files
  repackaged as chains/phrases. Load the result from the savetool or the
  FILES screen.
- **`.sndj` → `.als`** — a minimal Session-view Live Set (one MIDI clip per
  16 phrase rows per track, master tempo set from TMPO); open it in Live.
- **MML text ⇄ `.sndj`** — one line per voice, classic note notation (§4).

The conversion core is DOM-free and fixture-tested by `tools/test_als.js`
in `make test` (MML round trip must converge byte-identically; MIDI and
`.sndj`-wrap fixtures assert exact block bytes).

## 1. Scope (locked)

Deliberately narrowed to the tractable, high-value path — the same contract
as genmddj's converter, adjusted for what the SNES actually adds:

- **MIDI clips only.** Audio onset/pitch detection is out of scope.
- **Monophonic per voice — highest note wins** at each 16th. No voice
  allocation, no arp. Polyphony reductions are counted in the report.
- **16th-note grid, 4/4 assumed.** Triplets and odd meters quantise lossily.
- **First 8 tracks/channels → V1–V8** in order; the rest are skipped
  (reported). The instrument column is the track index 0–7.
- **Note-offs ARE mapped** (unlike genmddj — sndj phrases have a real
  `OFF`). A note's end writes `OFF` at the following row if that row is
  free; a new note on that row simply retriggers instead. Toggleable
  ("write OFF at note ends", default on).
- **Velocity → `X xy`** (voice level 00–7F) is optional (default on).
  Off = uniform instrument volume.
- **Tempo IS imported** (unlike genmddj — sndj has a real TMPO field):
  Live's master tempo, the first SMF `FF 51` meta, or MML `t<n>`, clamped
  to TMPO's 80–255 and written to the song header. The groove ships as the
  stock 6/6, so TMPO reads exactly the source BPM.
- **No device adaptation.** sndj instruments are samples, not patches;
  imported songs get 64 plain SMP instruments (0–7 on pool samples 0–7) so
  every voice sounds out of the box on the factory pool. Ableton
  instrument/device settings are ignored.

## 2. What lands where

| Source | sndj |
|---|---|
| Session clip (per track) | phrases (16 rows each), deduplicated |
| Contiguous non-empty scenes | one run → chains of ≤16 phrase steps |
| Empty scene | chain boundary |
| MIDI channel n (SMF) | one continuous clip → V(n)'s chains |
| Note pitch | note byte = MIDI − 11 (C4=60 → `C-4`); out-of-range folds by octaves (reported) |
| Note length | `OFF` row at the note end (if free) |
| Velocity 1–127 | `X` command, param 00–7F |
| Tempo | TMPO (header BPM), clamped 80–255 |
| Set/file name | song name (8 chars, A–Z 0–9) |

Pool limits — 192 phrases, 96 chains, 128 song rows — truncate with a ⚠ in
the report, never silently.

**Blank on import:** WAVE banks and kits (they live in the song block but
are drawn/built on console or seeded by NEW; the converter can't reach the
ROM's factory sets). An imported song that needs WAV/KIT/NSE/SLICE/KARP
types is a two-step job: import, then retype instruments on the INSTR
screen.

## 3. Export (`.sndj` → `.als` / MML)

The exporter walks each track's song column → chains → phrases and emits
one 4-beat clip per 16 rows. Note durations are the row distance to the
next note or `OFF`; `X` params become velocities; chain transpose is baked
into the pitches. Trailing silence is trimmed (the one lossy step —
re-importing the export reproduces the song minus empty tail phrases, and
is byte-stable from then on; `make test` asserts this).

## 4. MML grammar

One line per voice, `V1`–`V8`:

```
t128
V1 o4 l8 c e g >c< g e c4 r4
V2 o2 l4 c g v9 c2 & c8
```

- notes `c d e f g a b`, accidentals `+`/`#`/`-`
- `o<n>` octave (C4 = MIDI 60), `>` / `<` octave up/down
- `l<n>` default length; `4` `8.` `16` per-note lengths, `.` dotted,
  `&` tie, `r` rest
- `v<n>` velocity 0–15 (scaled to `X` 00–7F)
- `@<n>` instrument 0–63
- `t<n>` tempo → TMPO
- `;` comment to end of line

A rest after a note becomes an `OFF`; back-to-back notes retrigger without
one — exactly how the tracker plays them.

## 5. Files

| File | Role |
|---|---|
| `user-tools/als2sndj.html` | the converter (imports `user-tools/sndj.js`) |
| `tools/test_als.js` | fixture tests, run by `make test` |

Song viewer (SONG/CHAIN/PHRASE tables) is built in — check what a
conversion produced before flashing it anywhere.
