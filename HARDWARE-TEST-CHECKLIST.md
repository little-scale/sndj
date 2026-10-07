# sndj hardware test checklist — current development build

This checklist covers the editor and engine changes made from the first
external feedback round. Run it on a real SNES or Super Famicom before the
next release.

Release candidate:

- ROM: `build/sndj.sfc`
- Expected version: `0.15`
- A release ROM must show its tagged commit hash without a trailing `+`.
- Verify the ROM SHA-256 against the checksum published with the GitHub
  release before hardware testing.

Record the exact build shown by your ROM when testing. Rebuilds after further
changes may have a different checksum.

## Test record

| Item | Record |
|------|--------|
| Console / motherboard revision | |
| Region | PAL / NTSC |
| Cartridge or flash device | |
| Video output and display | RF / composite / S-Video / RGB / other |
| Audio connection | TV / headphones / mixer / capture interface |
| Controller | |
| ROM build shown on screen | |
| Test date | |
| Tester | |

Before testing, back up any important SRAM. Prefer a new unsaved song so old
project data cannot influence the result. For audio faults, a direct stereo
recording is much more useful than a phone recording of the television.

Status marks used below: `[ ]` not tested, `[x]` pass, `[!]` failed or unclear.

## 1. Boot and general smoke test

- [ ] The ROM boots to the splash screen without corruption or a black screen.
- [ ] The default font is complete and readable on every screen.
- [ ] SONG, CHAIN, PHRASE, INSTR, TABLE, WAVE and LIVE can all be opened.
- [ ] Start begins and stops playback normally.
- [ ] Saving, resetting the console and loading the song still works.
- [ ] If testing a ROM with a font replaced in the browser patcher, the
      replacement font appears correctly. This verifies the relocated banked
      font asset as well as the normal boot path.

Notes:

---

## 2. Same-row `B`, `S` and `U` commands

These commands previously ran before a note reloaded its instrument, allowing
the reload to overwrite the command.

### `B` — WAV bank

1. Make WAV banks 0 and 3 audibly different, such as a sine-like wave and a
   narrow pulse.
2. Use a WAV instrument whose default bank is 0.
3. Enter a note with `B03` on the same PHRASE row.
4. Play the phrase.

- [ ] The very first note uses bank 3; bank 0 is not heard first.

### `S` — pitch sweep

1. Enter a note with a clearly audible upward sweep such as `S40` on the same
   row.
2. Play from the beginning of the phrase.

- [ ] The sweep starts on that note, without waiting for another row.

### `U` — surround phase

1. Use a sustained stereo sample and put `U10`, then `U00`, on note rows.
2. Listen through a stereo capture or monitor a mono sum on a mixer.

- [ ] The phase setting changes on the same note row.
- [ ] `U00` returns the voice to normal phase.

Notes:

---

## 3. Delay/kill boundary

Use the default `6/6` groove.

1. On row 0 enter a note with `D06`.
2. Leave the following row empty and loop the phrase several times.

- [ ] The `D06` note is never heard. A six-tick row contains tick 0 through
      tick 5, so tick 6 is already outside that row.

3. Add command-only `K00` on row 1 and repeat.

- [ ] The delayed note is never heard, including as a very short click or
      one-tick note at the row boundary.

Control check:

1. Change `D06` to `D05`.

- [ ] A very short note is now heard before `K00`, proving the test phrase and
      instrument are working.

Notes:

---

## 4. WAV legato-slide octave

1. Use a WAV instrument and play a sustained C-3.
2. On a later row enter C-4 with `L10`.
3. On another phrase play a plain C-4 with the same WAV instrument for
   comparison.

- [ ] The slide lands on the same pitch as the plain C-4.
- [ ] It does not land on C-5, one octave above the displayed target.

Notes:

---

## 5. Arpeggio and retrigger persistence

### Arpeggio

1. Enter a note with `A47`.
2. Leave several following rows empty.
3. Add command-only `A00` later in the phrase.

- [ ] The 0/+4/+7 arpeggio continues across the empty rows.
- [ ] `A00` stops it and returns immediately to the base pitch.

Loop-repeat check:

1. Remove `A00` and loop a phrase containing only the `A47` note.
2. First disable the instrument's ECHO flag and use a dry ECHO setup.
3. Listen to at least four phrase passes, then repeat with echo enabled.

- [ ] In the dry test, every pass has the same pitch order and attack.
- [ ] Any variation introduced only with echo enabled is the expected echo
      memory from earlier passes, not a changing arpeggio sequence.
- [ ] If the dry passes still differ, save the `.sndj` project and record a
      direct audio example; the automated check currently sees the same
      0/+4/+7 pitch set with no stray pitches.

Screen-rate check:

1. While the same A47 arrangement plays, move between PHRASE and INSTR.

- [ ] The arpeggio runs at the same speed on both screens. INSTR previously
      redrew its entire static layout every frame, collapsed pairs of audio
      ticks, and made the arpeggio sound approximately half-speed.

### Retrigger

1. Enter a sustained note with `R03`.
2. Leave several following rows empty.
3. Add command-only `R00` later in the phrase.

- [ ] Retriggering continues across the empty rows.
- [ ] `R00` stops further retriggers.
- [ ] A new note while `R03` is active restarts the retrigger cadence cleanly.

Notes:

---

## 6. Chord and tremolo

### Instrument tremolo on chord voices

1. Give an instrument a pronounced TRM value such as `4F`.
2. Enter a sustained note with chord command `C47`.

- [ ] The root and both added chord voices tremolo together.
- [ ] No member voice remains at a fixed volume while the root tremolos.

### Latched chord behavior

1. After `C47`, enter notes on later rows, including a note using a different
   instrument number.
2. Add `C00`, followed by another note.

- [ ] The chord remains active across following rows and instrument changes.
- [ ] The note after `C00` is no longer expanded into a chord.

### New `W` tremolo command

1. Set an instrument's TRM field to `00`.
2. Enter a sustained note with `W4F` on the same row.
3. Enter a second note without any command.
4. Add command-only `W00` on a later row.

- [ ] `W4F` produces a clear tremolo immediately on that note.
- [ ] The second plain note continues using the `W4F` tremolo.
- [ ] `W00` stops the tremolo and restores the undipped level immediately.
- [ ] There is no frozen quiet level after `W00`.

Notes:

---

## 7. Rectangular block selection

Prepare two adjacent rows with values in NOTE, INSTR, CMD and VALUE.

1. Place the cursor on INSTR in the first row.
2. Hold Y and tap B to anchor block selection.
3. Use right and down to select a rectangle covering INSTR through VALUE over
   both rows.

- [ ] Only the selected rectangle is highlighted; it is not one row or one
      column smaller on neighbouring columns.
- [ ] All four d-pad directions resize the rectangle sensibly.

4. Tap B to copy, move to another INSTR cell and double-tap B to paste.

- [ ] INSTR, CMD and VALUE paste into both rows.
- [ ] NOTE cells at the destination remain unchanged.

5. Select only NOTE cells over several rows, then hold B and tap A to cut.

- [ ] The selected notes clear.
- [ ] Their INSTR, CMD and VALUE cells remain unchanged.
- [ ] Holding B first and then tapping A works reliably; simultaneous timing
      is not required.

6. Repeat a small block cut on SONG and CHAIN.

- [ ] Left/right extends SONG selection across track columns.
- [ ] Left/right extends CHAIN selection across PHR and TSP columns.
- [ ] The CHAIN highlight is balanced; PHR and TSP cover the same selected
      rows rather than appearing one cell or row out of alignment.
- [ ] Copy and paste reproduce the arbitrary X/Y rectangle on both screens.
- [ ] Held-B then A also cuts selected blocks on SONG and CHAIN.

Notes:

---

## 8. TABLE transpose empty and zero states

1. In TABLE, place the cursor on an empty TSP field showing `--`.
2. Tap B once.

- [ ] The field now shows an explicit `00`.
- [ ] During playback, `00` resets the voice to its note's base pitch after
      an earlier nonzero TSP value.

3. Hold B and tap up, then down.

- [ ] B+up changes `00` to `0C` (+12 semitones, one octave).
- [ ] B+down returns `0C` to explicit `00`, not `--`.
- [ ] Left/right changes the value by one semitone.

4. Hold B and tap A.

- [ ] The explicit `00` clears back to `--`.

Notes:

---

## 9. Single-use block clipboard

1. Copy and paste a block successfully.
2. Move to a populated chain reference on SONG or a populated phrase reference
   on CHAIN.
3. Double-tap B again.

- [ ] The previous block is not pasted a second time.
- [ ] The normal reference clone action runs instead.

Notes:

---

## 10. PHRASE navigation follows its chain

1. Make a chain with phrase `00` at entry 0, a blank entry 1 and phrase `02`
   at entry 2.
2. Descend from entry 0 into PHRASE.
3. Move the PHRASE cursor to a recognisable row and column.
4. Hold Y and tap down, then hold Y and tap up.

- [ ] Y+down opens phrase `02` and skips the blank chain entry.
- [ ] Y+up returns to phrase `00`.
- [ ] Navigation wraps when passing the first or last populated chain entry.
- [ ] The edit row and column stay in the same position while changing phrase.

Notes:

---

## 11. TABLE mint and clone from INSTR

1. On an instrument whose TBL field reads `--`, double-tap B on TBL.

- [ ] A new table number is assigned.

2. Enter a distinctive value in that table.
3. Return to the instrument's populated TBL field and double-tap B again.

- [ ] A different table number is assigned.
- [ ] The new table contains the copied value.
- [ ] Editing the clone does not change the original table.
- [ ] Repeating this on another blank instrument does not silently reuse an
      already assigned but still-empty table.

Notes:

---

## 12. LIVE mint and clone

Stop transport before this test.

1. In LIVE, double-tap B on an empty cell.

- [ ] A fresh chain is minted into the cell.
- [ ] Transport remains stopped.

2. Put recognisable content in that chain and double-tap B on its populated
   LIVE cell.

- [ ] The cell is repointed to a cloned chain containing the same references.
- [ ] Transport remains stopped.

3. Press A+B on the selected cell.

- [ ] A+B still launches or queues it normally.
- [ ] A single B on a populated LIVE cell neither launches nor overwrites it.

Notes:

---

## 13. Slide/sweep playback context

The reported phrase began with blank rows followed by an `L` note. `L` needs
an already sounding source note: SONG playback may supply one from an earlier
phrase, while isolated CHAIN/PHRASE playback has no source. The engine now
handles that isolated case deterministically by sounding the written `L` note
as an anchor instead of sliding stale pitch from a previous playback.

First reproduce the attached example in isolation:

1. Put blank rows before the first note, then place `C-6 L07` on row 6.
2. Start the isolated phrase with A+B several times, including after auditioning
   unrelated notes.

- [ ] Every isolated start now sounds the same.
- [ ] The first `L` note sounds as a normal C-6 anchor; it cannot slide because
      there is no earlier note in that transport.

Then build one short song containing:

- a slow `L` slide between two sustained notes; and
- a separate sustained note with an obvious `S` sweep.

Include a plain anchor note before the `L` target. Without moving the SONG
start row, use **Start** to start and stop the same arrangement from each
screen below. Do not audition a cell with B between runs.

| Screen | L smooth | S smooth | Lingering note or pitch | Notes |
|--------|----------|----------|--------------------------|-------|
| SONG | [ ] | [ ] | [ ] | |
| CHAIN | [ ] | [ ] | [ ] | |
| PHRASE | [ ] | [ ] | [ ] | |
| INSTR | [ ] | [ ] | [ ] | |
| TABLE | [ ] | [ ] | [ ] | |
| WAVE | [ ] | [ ] | [ ] | |
| KIT | [ ] | [ ] | [ ] | |
| GROOVE | [ ] | [ ] | [ ] | |
| ECHO | [ ] | [ ] | [ ] | |
| FIR | [ ] | [ ] | [ ] | |
| PROJECT | [ ] | [ ] | [ ] | |
| HELP | [ ] | [ ] | [ ] | |

Expected result: Start plays the same arrangement identically from every
screen. A+B is deliberately different: on CHAIN and PHRASE it starts that
isolated object from its top, so it should not be used for this comparison.
If one screen still differs when using Start, capture:

- the `.sndj` song or SRAM;
- a direct audio recording;
- the screen where playback was started;
- the selected SONG row;
- whether any note had just been auditioned with B; and
- whether the fault survives stop/start, changing screen, or a console reset.

Notes:

---

## 14. Final regression pass

- [ ] Existing songs load and sound unchanged apart from the intentional
      command corrections above.
- [ ] SONG, CHAIN and PHRASE editing still responds at normal speed.
- [ ] LIVE launch quantisation still occurs at phrase boundaries.
- [ ] No unexpected stuck notes occur after Stop.
- [ ] No screen shows corrupt text, incorrect colours or damaged cursors.
- [ ] A save made by this build survives a hardware reset and reload.

## Reporting a failure

For each failed item, record the checklist section, exact button order, screen,
song data involved, and whether it reproduces after reset. Preserve the
failing `.sndj` or SRAM before simplifying it; the smallest reproducible copy
can be made afterwards.
