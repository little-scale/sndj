# sndj — User Manual

**sndj** is a music tracker for the Super Nintendo / Super Famicom,
inspired by LSDJ and built as a sibling of
[smsggdj](https://github.com/little-scale/smsggdj) (Master System /
Game Gear) and [genmddj](https://github.com/little-scale/genmddj)
(Mega Drive / Genesis). If you know either sibling — or LSDJ — you
already know how to drive it: notes live in phrases, phrases in
chains, chains in a song grid, and everything is played and edited
with the d-pad and a couple of modifier buttons.

What makes the SNES special is the chip: the S-DSP is an 8-voice
sampler with hardware envelopes, a stereo mixer with signed (phase-
inverting) volumes, a noise generator, voice-to-voice pitch
modulation, and a real echo unit with an 8-tap FIR filter in its
feedback path. sndj is designed around those things rather than in
spite of them: every voice can play samples, drum kits, drawn
wavetables or noise, and the echo room is a first-class, sequencable
instrument.

---

## 1. Getting started

1. Put `sndj.sfc` on a flashcart (or open it in an emulator — Mesen 2
   and ares are both great) and boot it.
2. Press **Start** on the splash. You land on the **SONG** screen:
   8 track columns, one per hardware voice.
3. Hold **A** and tap the d-pad to move between screens (the map is
   printed at the top of every screen). Go right twice to reach
   **PHRASE**.
4. On an empty note cell, hold **B** and tap any d-pad direction: a
   note appears immediately and auditions. Keep holding B and tap
   left/right to nudge it by semitones, up/down by octaves.
5. Press **Start**. You're sequencing.

Tempo and pitch are identical on PAL and NTSC machines — the SNES
audio unit has its own crystal. A 50 Hz console only changes the
picture.

## 2. The controls

The whole tracker is four buttons plus the d-pad. The rule that makes
it feel instant: **the button already held selects what the next
press means.** There are no simultaneous-press timing windows.

| Button | Role |
|--------|------|
| **d-pad** | move the cursor |
| **B** | *edit*: tap = insert / act · hold + d-pad = nudge the value under the cursor (left/right small, up/down big) · double-tap = paste / clone · hold B + tap **A** = cut |
| **Y** | *context*: hold + ←/→ = previous/next channel · hold + ↑/↓ = previous/next chain, phrase, kit or table (on those screens) · Y+B = block select |
| **A** | *screens*: hold + d-pad = navigate the screen map · **A+B** = contextual play (see below) |
| **Start** | play / stop the whole song from any screen — the arrangement enters at the song cursor row |
| **L / R** | channel left / right (shortcut for Y+←/→) |
| **Select** | jump to LIVE and back |
| **X** | mute / solo (hold + ↑/↓ mute, ←/→ solo, on SONG/LIVE) |

Only d-pad + B + Y + A + Start are load-bearing; L, R, X and Select
are shortcuts to things the core grammar can already do.

### Editing in detail

- **Insert**: tap B on an empty cell to insert (notes bring the last
  used instrument with them; commands bring their letter *and* last
  value). On an empty **note** cell, B-hold + any d-pad tap inserts
  straight away, so entry and nudging are one gesture.
- **Nudge**: hold B, tap d-pad. **Left/right always steps by 1**
  (the low nibble); **up/down steps the high nibble** (±16) on byte
  parameters, an **octave** (±12) on anything in semitones (notes,
  transpose, chord offsets, kit tune), and ±4 on short ranges.
  Power-of-two ranges wrap around; the rest clamp.
- **Delete / cut**: hold B, tap **A**. Cutting a note also clears its
  instrument column; the cut cell goes to the clipboard.
- **Paste / mint / clone**: double-tap B. On a cell whose kind
  matches the clipboard, it pastes. On an **empty** chain/phrase
  reference cell (SONG or CHAIN screens) it *mints* the next unused
  chain/phrase. On a **populated** reference cell it *clones* the
  content into a fresh slot and points the cell there — see
  §4, Quick duplicates.
- **Audition**: tapping B on a note (or nudging one) plays it with
  its instrument — but only while the transport is stopped, so edits
  during playback never double-strike. Tapping B on the instrument
  column auditions that row's note through that instrument. Tapping B
  on a **C** chord command auditions the whole chord — root plus the
  two offset voices — through that row's note and instrument.
- Command cells only accept an insert while **empty** (nudge or cut
  first to change a written command), so tapping a command to hear or
  inspect it can never overwrite it.

### Block select

Hold **Y** and tap **B** to drop an anchor, then move the cursor: the
marked region highlights. B copies it, B+A cuts it, double-tap B
elsewhere pastes it. Works in PHRASE, CHAIN and SONG.

### Transport

- **Start** is the song transport on every screen: stop when
  playing, else play **the arrangement at the SONG cursor row** —
  every track enters at the chain at-or-above that row (the one
  "covering" it) and loops its block from there; a column with
  nothing above stays silent. Drill from a song cell into its chain
  or phrase and Start sounds exactly the context you're looking at.
- **A+B** is *contextual*: if anything is playing, it stops. Else on
  SONG it plays all tracks from the cursor row; on CHAIN it plays
  just that chain from its top; on PHRASE it loops just that phrase
  from its top. (Per-track stops live in LIVE mode — §11.)
- A chain that ends in the song grid loops back to the top of its
  track's contiguous block — so a 4-row loop keeps looping without
  needing the grid filled to the bottom.
- On play, each track **enters at the first populated cell at/above
  the start row** — the chain covering that row keeps sounding, so
  starting mid-song sounds like the song sounds there.
- **Playback indicators**: the triangle, and only that. On CHAIN,
  PHRASE and GROOVE a gutter triangle marks the playing row; on SONG
  **each playing track gets its own triangle**, in the gap left of
  the cell it is playing — the 8 tracks are independent playheads
  (they walk their own chains and loop their own blocks; there is no
  single "song position"). Cells are never painted over. A fully
  empty column stays silent.

## 3. The screens

Hold **A** and tap the d-pad to move around the map:

```
[O][P]   [W][H]      OPTIONS  PROJECT        WAVE   HELP
[S][C][P][I][T]      SONG  CHAIN  PHRASE  INSTR  TABLE
[F][G][K][E][F]      FILES  GROOVE  KIT   ECHO   FIR
```

The middle row is the composing spine. Columns mean something: sound
design (WAVE, KIT) sits above the instruments that use it; the room
(ECHO, FIR) sits below. OPTIONS↔PROJECT and FILES↔GROOVE also link
left/right.

| Screen | What lives there |
|--------|------------------|
| **SONG** | 8 track columns × rows of chain numbers. The arrangement. |
| **CHAIN** | 16 phrase slots + per-slot transpose. |
| **PHRASE** | 16 rows × NOTE · INSTR · CMD · VALUE. The actual notes. |
| **INSTR** | instrument editor (SMP/KIT/WAV/NSE), envelope, vol, pan, echo, table. |
| **TABLE** | 16-row per-tick automation: level, transpose and a command per row. |
| **WAVE** | draw 32-sample single-cycle waves in 8 banks. |
| **KIT** | build drum kits: 16 slots of sample + tune + volume; **Y + ↑/↓** pages between kits (the same gesture that pages chains, phrases and tables). |
| **HELP** | the paged button + command reference. **Hold A alone for ~2.5 s on any screen** to toggle it (and again to jump back); plain d-pad turns the pages. |
| **GROOVE** | the two-step groove pair — the song's feel. |
| **ECHO** | the room: delay, feedback, level, per-voice sends. |
| **FIR** | the echo filter's 8 taps, hex-editable, with presets. |
| **PROJECT** | song name, BPM, transpose, LIVE mode. (A fresh song: FILES → LOAD on the empty row.) |
| **FILES** | save / load / rename songs in cart SRAM. |
| **OPTIONS** | device settings: palette, cloning depth, video readout, SYNC / MIDI takeover (§13a). |

## 4. Making a song

The data model, bottom-up:

- A **PHRASE** is 16 rows — one bar of 1/16th notes. Each row can
  hold a note, an instrument, and one command.
- A **CHAIN** is a list of up to 16 phrases, each with a semitone
  transpose. One chain ≈ one musical part.
- The **SONG** grid arranges chains vertically per track. All 8
  tracks run in lockstep rows but walk their own chains.

Phrases, chains and instruments are *shared pools* — putting phrase
`03` in two chains reuses the same 16 rows. That's a feature (edit
once, change everywhere) and a trap (edit once, change everywhere),
which is what cloning is for:

### Quick duplicates and cloning

Double-tap **B** on a chain/phrase number:

- empty cell → **mint** the next unused chain/phrase (numbered for
  you).
- populated cell → **clone**: copy the content to a fresh slot and
  repoint this cell, leaving the original untouched everywhere else.

OPTIONS → CLONE decides how deep a *chain* clone goes: **SLIM**
copies the chain but shares its phrases; **DEEP** clones the phrases
too (duplicates inside the chain stay duplicates). Phrase clones are
always real copies.

## 5. Instruments

The INSTR screen groups its fields — identity / envelope / mix / tune
& motion / chord span / table — and hides what a type never reads:
KIT keeps envelope and echo but drops VOL, FINE and VIB (the kit
slots own volume and tune); NSE drops SAMPLE and everything pitched;
WAV shows everything with SAMPLE reading **BANK**; SLICE swaps the
ADSR for **ATTACK + FADE** and gains **TUNE**. The **INSTR number is
itself the first field** — nudge it (B + d-pad) to switch which
instrument you're editing, or **Y + ↑/↓** flips previous/next (TABLE
and PHRASE answer the same gesture).

64 instrument slots, all pre-populated at NEW so every number makes a
sound. An instrument's **TYPE** decides what the voice does:

| Type | What it plays |
|------|----------------|
| **SMP** | a BRR sample from the ROM pool (melodic, looped or one-shot) |
| **KIT** | a drum kit: the note row picks a slot (C-4 = slot 0, C#4 = slot 1, wrapping every 16) — the PHRASE note column shows the slot's **sample name** instead of a pitch |
| **WAV** | a drawn 32-sample wavetable loop from the WAVE screen |
| **NSE** | the DSP noise generator; the note sets the noise clock, or the instrument's CLOCK field pins it |
| **SLICE** | one pool sample (a breakbeat, a vocal, anything) cut into **SLICES** equal parts; the note picks the slice, wrapping past the count — the PHRASE note column shows two letters of the sample's name + the slice number |
| **KARP** | Karplus-Strong: the echo loop becomes a plucked string — the note rings the room's nearest partial, tuned by a per-note FIR pull. One string per song (it owns the echo section) |

Any type can go on any of the 8 voices — there are no special
channels. Eight kits at once is legal. **The first 8 instruments are
the factory boot set** — their samples land in audio RAM at power-on,
and the patcher's boot-instruments editor voices all 8 (type, sample
  / kit / bank, loop, slice count). A clean build uses the eight-instrument
  rights-cleared project factory; its authored sounds occupy pool slots 00-07.
  Slots 08-63 start as SMP on sample 0, ready to re-voice, and a personal
  factory pack may replace the complete boot set.
  Audio RAM only holds what the song *references* —
point an instrument or kit slot at any pool sample and it loads on the
spot, so the rest of the pool costs nothing until you use it (the ECHO
screen's RAM/FREE line shows the live balance).

### INSTR fields

- **ENV** — hardware ADSR (attack, decay, sustain level, sustain
  rate). It runs on the chip and costs nothing. The `Q` command can
  override it with GAIN ramps per row.
- **VOL L / R** — signed! A negative volume inverts that side's
  phase: instant width. (The `U` command does this per row.)
- **FINE** — signed fine-tune, 1/256ths of a semitone.
- **LOOP** (SMP) — **POOL** plays the sample as it was imported;
  **ON** forces a loop (a one-shot loops whole — drones and textures
  from any hit); **OFF** forces one-shot (a looped pad becomes a
  stab). Per *instrument*, not per sample: the same pool sample can
  loop on one instrument and stab on another, for free.
- **ECHO** — ON/OFF: does this *sound* want the room? The voice only
  sends when this is ON **and** the channel's gate is open in ECHO's
  EON MASK (open by default) — so one instrument can be wet on one
  track and dry on another.
- **PMOD** — this voice's pitch is modulated by the voice to its
  *left*. Put a quiet sine (WAV) on the left track, melody on the
  right: FM-flavoured growls and bells. The screen shows the pairing
  (`V4 ← V3`).
- **VIB** — vibrato, two nibbles **speed**·**depth** (`00` = none): a
  triangle pitch wobble that runs on every note this instrument
  plays. The `V` command overrides it for one note (`V00` = hold that
  note straight); the next plain note reloads the instrument's value.
- **TRM** — tremolo, same **speed**·**depth** nibbles: dips the
  volume below the set VOL L/R level (only ever downward, so it
  rides on top of the hardware envelope).
- **TBL / TBS** — attach a table (`--` = none) and set its clock:
  TBS `1`–`F` runs a table row every n ticks; TBS `0` is *note-sync*
  — each new note advances the table one row (great for cycling
  chords, sample-offsets, pan patterns).

### KARP — the room as a string

Karplus-Strong on real hardware: the echo delay line is the string,
the FIR is its damping filter, and every note re-tunes the room. Set
the song's **DELAY to 1 or 2** on ECHO (the string only costs 2-4 KB
of audio RAM) and point a KARP instrument at an exciter:

- **BANK** — the wave that plucks the string (saw = bright pick,
  sine = soft thumb, the gritty bank = snap). It fires as a fast
  burst at the exact frequency of the note's nearest room partial.
- **DAMP** — string material: low = dark nylon (the treble dies
  fast), high = bright steel. It never changes how long the string
  rings — that's SUSTAIN's job alone.
- **BURST** — the seed: high values are the classic KS pluck (a
  burst about one trip around the loop, ~16-32 ms); low values *bow*
  the string with a longer excitation instead.
- **SUSTAIN** — the loop feedback: how long the string rings.
- **Hear the string, not the pick**: VOL L/R is the *dry exciter*
  level — set it to 00 for pure string and put the string's volume
  on the ECHO screen's ECHO L / ECHO R. All four fields apply on the
  very next note.
- The note picks the nearest partial of the room and a 2-tap FIR
  pulls it into tune. Chromatic from about **F#6 at DELAY 1 / F#5 at
  DELAY 2**; below that, notes land on the room's harmonic series —
  natural-horn intonation, gorgeous for basses and drones.

One string per song: KARP owns FEEDBACK and the FIR taps while it
plays, and anything else with ECHO on plays *through* the string.
Arpeggios ring multiple partials at once — a harp cloud from one
track. Design plucks in the patcher's FIR tab (the KARP row) before
committing.

### SLICE — chopping a break

Point a SLICE instrument's SAMPLE at any pool one-shot and set
**SLICES** (2–16). The sample divides into that many equal,
block-aligned parts at **zero audio-RAM cost** — slices are directory
aliases into the sample the song already loaded. Then:

- **The note picks the slice.** Note 1 (C-0) = slice 0, note 2 =
  slice 1, … wrapping past the count — so any melodic line is a valid
  chop sequence, and transpose commands *rotate the chop*.
- **FADE** is the whole envelope story: each slice plays from its
  start toward the end of the sample, fading at the FADE rate
  (`0` = never — slices ring into each other like an open sampler
  pad; `8` = the factory middle; `F` = tightest gate). ATTACK still
  softens the front.
- **TUNE** transposes the whole slice set in semitones (notes pick
  slices, so pitch lives here); FINE trims cents.
- Pitch commands act on the playing slice —
  `L` slides a break in flight.

A 16-slice break costs 16 of the 56 sample directory slots while its
instrument exists; if the directory can't fit the window the slices
fall silent rather than eating other samples (drop the count or free
an instrument).

## 6. Tables

A table is 16 rows of **V · TSP · CMD**, run per tick while the voice
plays — automation that belongs to the instrument, not the phrase:

- **V** — set the voice's level (01–7F, like the `X` command)
- **TSP** — transpose the playing note by signed semitones
- **CMD** — one command + value, the exact PHRASE letters

`00` in any column means "no change", so blank rows are silent
passthroughs. `H` in the command column hops to a table row, making
loops:

```
row 0  V20  --  ---     pull the voice down
row 1  --   --  M30     duck the master
row 2  --  +0C  ---     up an octave
row 3  --   --  H02     loop rows 2-3
```

D, I and J are row-scoped and do nothing inside tables.

## 7. Grooves, tempo, timing

TMPO on PROJECT sets the BPM (80–255); **the groove** — one public
two-step pair — decides how many engine ticks the odd and even rows
last (default 6/6 = straight). Swing is just an uneven pair: `7/5`
lilts, `8/4` swings hard. The GROOVE screen edits the two steps with
a live BPM readout, and **`G xy` writes the pair from a phrase** —
`G84` throws the swing on the drop, `G66` snaps it straight. `T`
changes BPM. Tick timing comes from the sound unit's own timer, so
it's identical on every console, PAL or NTSC.

## 8. Command reference

One command column per phrase row; the same letters work in tables.
Values are hex (`xy` = two nibbles).

| Cmd | Name | What it does |
|-----|------|--------------|
| `A xy` | arpeggio | cycle root, +x, +y semitones each tick |
| `B 0x` | wave bank | switch a WAV voice to bank x (wave-sequencing) |
| `C xy` | chord | fan +x / +y semitones onto the two voices to the right; `C00` chord off |
| `D 0x` | delay | trigger this row's note x ticks late |
| `F xy` | fine tune | per-track detune, signed 1/256 semitones |
| `G xy` | groove | set the groove pair: x ticks / y ticks per row (G66 straight, G84 swing) |
| `H 0x` | hop | jump to the next chain entry (in tables: to table row x) |
| `I xy` | play mask | 8-bit mask over passes: the note only fires on set bits (`AA` = every other pass) |
| `J xy` | pass transpose | on passes picked by 4-bit mask x, transpose the note by signed nibble y |
| `K 0x` | kill | key-off after x ticks (`K00` = immediately) |
| `L 0x` | legato slide | slide to this row's note at rate x, no retrigger |
| `M xy` | master volume | set the master level |
| `N 0x` | noise clock | set the global noise rate (shared by all NSE voices) |
| `P xy` | pan | position: `00` left, `80` centre, `FF` right |
| `Q xy` | GAIN override | hardware envelope ramp: mode x (1 direct, 2 lin↓, 3 exp↓, 4 lin↑, 5 bent↑) value/rate y; `Q00` back to ADSR |
| `R 0x` | retrigger | re-strike the note every x ticks |
| `S xy` | sweep | pitch sweep up at rate x or down at rate y |
| `T xy` | tempo | set BPM (hex; `96` = 150) |
| `U xy` | surround | invert L (x≠0) / R (y≠0) phase for width |
| `V xy` | vibrato | override the instrument's VIB for this note: speed x, depth y (`V00` = off) |
| `X xy` | volume | accent: set this voice's level (both sides, `00`-`7F`); persists like `P` until the voice reloads its instrument |
| `Y 0x` | FIR preset | switch the echo filter curve (global) |
| `Z 0x` | pitch-mod | enable (`Z01`) / disable modulation by the left voice |

### Varying a phrase — I and J

Because chains loop, `I` and `J` turn one phrase into several bars:
`I AA` plays the note only on alternating passes; `J 13` transposes
+3 on passes matching mask 1. A single 16-row phrase becomes a
4-bar figure with movement.

## 9. Echo & FIR — the room

The SNES has a real hardware echo: a delay line in audio RAM, stereo
return level, feedback, and an 8-tap FIR filter *inside the feedback
loop*. This is the DKC cathedral, and in sndj it's sequenced like an
instrument:

- **ECHO screen** — EDL sets the delay (0–240 ms in 16 ms steps).
  The screen shows what each step costs (`-12KB` beside DELAY) plus a
  live **RAM / FREE ledger** — how much audio RAM the song's resident
  samples hold, what the current delay leaves free, and how many
  **+ms** of extra delay that free space could still buy — and won't
  let the buffer grow into your samples. Feedback, return level L/R,
  and per-voice send toggles live here too.
- **FIR screen** — the 8 filter taps as signed hex bytes. Eight
  presets (FLAT, DARK, BRIGHT, COMB, SOFT, DKC HALL, METAL, USER)
  recall with Y+↑/↓; B+d-pad hand-tweaks a tap (the readout shows
  `--` for a custom curve). The song *owns* its taps — they save
  with it.
- **Per row** — `E` throws a voice into or out of the room, `Y`
  flips the filter curve on the drop.

Recipes: long dark hall = EDL 12+, DARK curve, moderate feedback.
Tempo-synced slapback = EDL near one row's length. Metallic comb =
METAL curve with high feedback. Design taps precisely in
the patcher's FIR designer (a live frequency plot + echo-loop
audition), then punch
the hex in on the FIR screen.

## 10. WAVE and KIT

- **WAVE** — draw a 32-sample wave with the d-pad; it compiles to a
  looped BRR and uploads live, so you hear edits as you draw. Eight
  banks; the `B` command steps through them per tick for
  wave-sequencing, and a table full of `B` commands is a wavetable
  synth. Single-cycle waves through the SNES's Gaussian interpolator
  have a soft, rounded character all their own.
- **KIT** — 16 slots per kit, each slot = pool sample + signed
  semitone tune + volume. On a KIT instrument the phrase's note
  column picks the slot. Factory authors can deliberately store one-shots at
  lower rates for a crunchy early-sampler flavour.
- **NSE** — the note column sets the *global* noise clock (32
  rates). All noise voices share it; the last writer wins. Same
  idiom as the PSG siblings.

## 11. Live mode

Set MODE to LIVE on PROJECT (or press **Select**): the SONG grid
becomes a clip launcher. **A+B** (the contextual-play gesture) on a
cell queues that chain on its track; from stopped it launches right
away. Plain **B** stays an edit key and never touches the transport.

- A chain queued on a *playing* track takes over at the track's next
  phrase boundary. A chain queued on a *silent* track fires at the
  next bar (16 rows) so it lands in time with the others.
- **A+B on the cell a track is playing queues its stop** — it never
  re-triggers the chain you're hearing. The track finishes its
  phrase and goes quiet.
- **B on an empty cell inserts a chain**, exactly like SONG's tap —
  build material without leaving the launcher, then A+B to launch
  it. B on an occupied cell does nothing (a stray tap can't
  overwrite or trigger anything mid-set).
- **The launcher is still on the map**: A+d-pad navigates from LIVE
  as if you were on SONG (up OPTIONS, down FILES, right drills into
  the cursor chain), and L/R or Y+←/→ switch tracks.
- Launched chains loop on their own cell — LIVE never walks the song
  grid downward.

The grid tells you what's happening: a steady **▸** marks each
track's playing cell, a *flashing* **▸** marks a cued chain waiting
for its boundary, and an **X** marks a track draining toward a
queued stop.

X-modifier mutes and solos (hold X, ↑/↓ mute, ←/→ solo), and muted
tracks show a dash in the header. **Start** from stopped launches
every populated cell on the cursor row at once; **Start** while
playing stops everything.

## 12. Saving — the FILES screen

Songs save into cart SRAM, packed tight: 16 slots share one ~31.7 KB
heap, so short songs take only the space they need. The screen shows
SRAM type, free space, and each song's size in KB.

- Cursor a slot, open the menu (A+B): **SAVE**, **LOAD**, **CLEAR**,
  **PURGE PH** / **PURGE CH** (blank phrases/chains unreachable from
  the song grid — pool hygiene), **CANC**.
- Every action asks for a confirm: the first **B** arms it and the
  item reads **SURE?** — tap **B** again to run it. Moving the cursor
  disarms; **CANC** (or **A**) closes the menu without running
  anything.
- **SAVE stores the song under its name.** A file with the same name
  is overwritten; a new name saves a new file. The cursor slot plays
  no part — renaming a saved file then saving *forks* the song, and
  the renamed file keeps living.
- LOAD brings the file's name back with it. LOAD on the `(EMPTY)` row
  starts a fresh song.
- **Rename**: hold **B** on a name character and tap **Up/Down** to
  cycle it (blank → A–Z → `-`/`.` → 0–9 going up; the reverse going
  down). On the `(EMPTY)` row this names the working song (the name
  the next SAVE uses); on a saved slot it renames that file.
- Saves are journalled — a power cut mid-save can never eat the
  previous good copy.

`user-tools/savetool.html` opens the `.srm` on a computer: view any
song's SONG/CHAIN/PHRASE data read-only, extract songs as `.sndj`
files, rename them, share them, rebuild cart images. Drop the
matching `sndj.sfc` next to it and every song gets a **play**
button — the browser plays the song through a bit-exact model of the
console's sound chip, using the ROM's own samples.

## 13. Options

| Option | Meaning |
|--------|---------|
| **PALETTE** | two-colour UI schemes (cursors render as negatives) |
| **CLONE** | SLIM / DEEP chain cloning (§4) — DEEP is the default |
| **VIDEO** | readout of the console standard — NTSC 60 Hz / PAL 50 Hz. Display only: pitch and tempo come from the audio crystal and never change. |
| **SYNC** | clock sync / MIDI takeover mode (§13a) |
| **KEY DELAY** | frames a d-pad direction is held before it auto-repeats (4–30, default 14) |
| **KEY RATE** | frames between auto-repeats once rolling (1–8, default 3 — lower = faster) |
| **TAP WIN** | the B double-tap (paste / mint / clone) window in frames (10–40, default 24) |

Options persist on the cart across power cycles.

## 13a. Syncing to other gear (OPTIONS → SYNC)

sndj locks to other machines over **controller port 2**, speaking the
same wire protocol as its siblings — a genmddj or smsggdj master, or
the ESP32 Link bridge, drives it with no changes on their side.

- **OFF** — no sync (default).
- **OUT** — reserved (master clock; not wired yet).
- **PULSE** — analog clock out for Volca / Pocket Operator gear: a
  2 PPQN pulse on pin 6 while playing.
- **IN** — **follow** a sibling master (one row per clock). Press
  Start and the transport arms — the top-right shows **WAIT** — then
  locks to the first clock (which plays row 0). The master owns the
  tempo; your groove is ignored until you leave IN. No song-position
  pointer: each unit plays from its own cursor, LSDJ-style.
- **MIDI** — MIDI note takeover, below.
- **IN24** — follow a **24 PPQN** source (the Ableton Link bridge);
  same WAIT-then-lock behaviour, six clocks per row.

While IN/IN24 is armed, OPTIONS shows a live **RX** clock counter —
if it climbs, the wire works.

The XIAO-to-SNES and Mega-Drive-to-SNES cable diagrams, level conversion and
bring-up sequence are in [`LINK-SYNC-WIRING.md`](LINK-SYNC-WIRING.md).

### MIDI takeover (SYNC: MIDI)

sndj becomes an **8-voice BRR sample module**: keep the transport
stopped, and a keyboard or DAW plays the voices live through the
ESP32-S3 bridge (the same 3-wire link the clock sync uses).

- **MIDI channels 1–8 map 1:1 onto V1–V8** (9–16 are ignored).
- Each voice remembers its own **current instrument**, seeded on
  entry to channel−1 (ch 1 → instr 00 … ch 8 → 07) and changed live
  by **Program Change** (0–63 → the instrument pool). The instrument
  is never sent over MIDI — only notes, like a phrase INSTR column.
- **Velocity** drives the voice level, **pitch bend** bends ±2
  semitones (kits don't bend), note-off releases the hardware
  envelope. Kits play their slots chromatically.
- **CC 7** = volume, **CC 10** = pan, **CC 91** = echo send on/off,
  **CC 74** = FIR preset — the room stays playable from the DAW.
- OPTIONS shows the decode monitor while in MIDI mode: **RX** counts
  every decoded event, plus the last frame's raw bytes — the console
  half of the two-sided bring-up diagnostic.

Entering the mode silences everything and re-seeds the channel map;
leaving it (or a MIDI panic message) releases all voices.

## 14. Quick reference

```
B tap        insert / act            A(hold)+dpad  screen map
B hold+dpad  nudge (LR fine, UD big) A+B           contextual play/stop
B dbl-tap    paste / mint / clone    Start         song play/stop
B hold+A     cut                     L / R         channel -/+
Y hold+LR    channel -/+             Select        LIVE
Y hold+UD    page                    X hold+dpad   mute/solo
Y+B          block select
```

## 15. The companion tools (`user-tools/`)

Zero-toolchain browser apps — download the folder, open the HTML,
everything runs locally:

- **patcher.html** — the ROM workshop, in tabs: **POOL** (replace
  pool slots from WAVs — sampler-loop WAVs import melodic, in tune —
  or dropped SoundFonts — several stack at once,
  drag a font slot onto a pool slot — with per-slot tune, rename,
  loop toggle and slot reordering, a C-5 reference tone, and ROM +
  audio-RAM budget meters that mirror the console's math), **BOOT**
  (the 8 boot instruments — type, sound, loop/slices — so you control
  what preloads into audio RAM), **KITS** (the factory drum kits:
  drag a one-shot straight onto a kit slot), **SLICES** (the chop
  designer), **FIR** (the echo filter designer: response plot, tap
  sliders, echo-loop audition, writes the 8 ROM presets), and
  **PALETTES**. Every audition runs through a bit-exact model of the
  console's BRR + Gaussian playback, so what you hear in the browser
  is what the cart plays. The main custom-sample workflow starts in
  [**simple-sf2-editor**](https://github.com/little-scale/simple-sf2-editor):
  prepare a WAV's pitch, trim, loop, crossfade and SNES-oriented
  16-sample alignment there, export SF2, then drag the result into the
  patcher's SoundFont panel for BRR conversion and ROM-pool import.
- **savetool.html** — song manager for cart saves (§12).
- **spcexport.html** — listen to and share your songs: drop a
  `.sndj` (or a cart save and pick a slot) plus the ROM. A **listen**
  button plays the song right there through the console-sound model;
  then export either a **WAV** (the whole song rendered offline,
  with a loop detector to size the render) or a standard **`.spc`**
  file that plays in any SPC player — your song's samples plus its
  register stream for one full loop, replayed by a tiny program baked
  into the file. If a busy song's log doesn't fit the 64 KB, the
  report says so and by how much.
- **als2sndj.html** — Ableton / MIDI / MML converter, both directions:
  drop an `.als` Live Set or `.mid` (first 8 tracks → V1–V8, tempo →
  TMPO, velocities → `X`, note ends → `OFF`), get a `.sndj`; drop a
  `.sndj`, get a Live Set back or MML text you can edit and re-import.
  A built-in viewer shows the SONG/CHAIN/PHRASE data before you commit.
  ALS.md documents the mapping and the MML grammar.

All of them share `sndj.js`, the reference library (keep it next to
them). Python command-line mirrors of the same operations live in
`tools/` for people who script.

---

*sndj is MIT-licensed and built on the shoulders of the SNES homebrew
and reverse-engineering communities. Sibling manuals: smsggdj and
genmddj.*
