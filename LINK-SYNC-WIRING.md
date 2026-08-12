# Link and cross-console sync wiring

This guide covers two ways to drive **sndj** through SNES/SFC controller port 2:

1. a Seeed XIAO ESP32-C3 or ESP32-S3 running
   [smsggdj-link-esp32](https://github.com/little-scale/smsggdj-link-esp32),
   with sndj set to **SYNC: IN24**; and
2. a Mega Drive / Genesis running
   [genmddj](https://github.com/little-scale/genmddj) in **SYNC: OUT**, with
   sndj set to **SYNC: IN**.

IN24 reads only bit 0 of the bridge's rolling counter as a persistent toggle.
sndj samples Data1 four times per video frame; each transition is one received
24-PPQN clock, and every sixth advances a row independently of the project's
local tempo. IN uses the same bit but treats every transition as a complete row.
Data2 is deliberately ignored in both modes: this avoids counter bit-order
ambiguity, at the cost of being unable to recover two transitions that occur
between polls. The wire carries clock state but not song position or a separate
transport command.

> **Hardware status:** sndj's IN/IN24 one-wire and row-gating paths pass the
> emulator-in-the-loop sync test. **genmddj SYNC OUT → sndj SYNC IN was
> verified on real Mega Drive and SNES/SFC hardware on 2026-08-03**, using the
> three-conductor counter cable documented below. sndj IN consumed Data1 only;
> the cable also carried Data2. **XIAO/Chip Bridge → sndj IN24 was confirmed to
> deliver clock on hardware in August 2026; its former two-bit decoder ran
> exactly 2x fast.** The current one-wire Data1 fix awaits timing confirmation.

## SNES controller port 2

The SNES controller connector has seven pins:

| SNES pin | Signal | Sync-input use |
|---:|---|---|
| 1 | +5 V | Translator power only, if required |
| 2 | controller clock | leave unconnected |
| 3 | controller latch | leave unconnected |
| **4** | **Data1 / `$4017` bit 0** | **IN/IN24 clock toggle** |
| 5 | Data2 / `$4017` bit 1 | leave unconnected; ignored by IN/IN24 |
| 6 | IOBit | leave unconnected for IN/IN24 |
| **7** | **ground** | **common ground** |

Connector drawings can be viewed from different sides. When making an adapter
from an extension cable, identify every conductor with a continuity meter; do
not rely on insulation colours. See the
[SNES controller-port reference](https://wiki.superfamicom.org/schematics-ports-and-pinouts).

Standard SNES pads use only pins 1, 2, 3, 4 and 7, so many extension cables
omit conductors for pins 5 and 6 even when the moulded connector appears to
have seven positions. This does not affect IN or IN24: both now require only
Data1 and ground.

Power both machines off before connecting or disconnecting the adapter. Never
join the power outputs of two independently powered devices.

## XIAO ESP32 bridge to sndj IN24

The existing bridge emits **24 PPQN**. sndj must therefore use **IN24**, which
divides the received clock by six to obtain four tracker rows per beat. Literal
**IN** would treat every 24-PPQN transition as a complete row and run six times
too fast.

### Direction

The required clock signal travels in one direction only:

```text
XIAO counter bit 0  ─────────►  SNES controller-port Data1
```

The SNES does not drive Data1 in IN24. Its controller clock, latch and IOBit
signals are not part of this connection. Bidirectional level
translation is therefore unnecessary for Link clock sync. MIDI takeover is a
separate mode with different line directions and is outside this wiring path.

### XIAO pin map

| Counter | XIAO ESP32-C3 | XIAO ESP32-S3 | Destination |
|---|---|---|---|
| **bit 0** | **D1 / GPIO3** | **D3 / GPIO4** | **SNES pin 4, Data1** |
| bit 1 | D2 / GPIO4 | D4 / GPIO5 | leave unconnected; ignored |
| ground | GND | GND | SNES pin 7, ground |

The C3 is the simplest Link-only bridge. The S3 also supports USB-MIDI clock
and MIDI takeover; for an unambiguous Link test, issue `c link` and `k off` in
its serial console so the outputs remain assigned to the counter.

### Safe 3.3 V to 5 V interface

Do not place the XIAO GPIOs directly on SNES 5 V logic. Configuring a GPIO as
open-drain stops it from actively driving high, but a released pin can still be
exposed to the voltage supplied by the other side's pull-up. ESP32 GPIO is not
specified as 5 V tolerant.

A `74AHCT125` or `74HCT125` makes a simple one-way interface:

```text
XIAO bit 0 ──┬──► HCT buffer ──[330 Ω–1 kΩ]──► SNES pin 4
             └── 10 kΩ pull-up to XIAO 3V3

XIAO GND ───────── HCT GND ───────────────────► SNES pin 7
SNES pin 1 (+5 V) ─► HCT VCC only
```

- Tie the used channel's active-low output-enable pin low.
- Put a 100 nF ceramic bypass capacitor beside the buffer between VCC and GND.
- Tie unused buffer inputs to a defined level.
- Power the XIAO from USB. **Do not connect SNES +5 V to the XIAO 5 V pin.**

A correctly wired BSS138 level-shifter channel also works, although its
bidirectional ability is not needed here.

### Link bring-up procedure

1. Flash the C3 or S3 bridge and provision Wi-Fi on the same LAN as Ableton.
2. With power off, connect translated bit 0 and ground to SNES controller port
   2. Leave bit 1 / Data2 disconnected. Keep the normal controller in port 1.
3. Enable Link and **Start Stop Sync** in Ableton Live.
4. Stop Ableton's transport.
5. Set sndj to **OPTIONS → SYNC: IN24**.
6. Press Start in sndj. The transport should display **WAIT**.
7. Start Ableton. sndj's OPTIONS screen should show the RX count increasing,
   and the first received clock should play row 0.
8. Stop sndj locally before another Link start, then re-arm it to WAIT. The wire
   has no independent stop or song-position message.

The bridge's default latency offset was tuned on SMS hardware. Use `z` in the
bridge console to begin at zero for SNES testing, adjust with `m <milliseconds>`,
and use `s` only after the SNES offset has been measured.

## Mega Drive genmddj OUT to sndj IN

genmddj's OUT mode writes a two-bit counter to controller port 2 TR and TH and
increments it **once per tracker row**. Its TR/bit-0 line therefore toggles on
every row. sndj's IN mode reads only that persistent toggle: a changed state is
one row clock. The verified cable also carries TH/bit 1 to Data2, although IN
deliberately ignores that second line.

### Cross-console cable

> **Hardware verified 2026-08-03:** a Mega Drive running genmddj in
> **SYNC OUT** successfully drove a SNES/SFC running sndj in **SYNC IN** with
> the following three connections. Data2 was present in the tested cable but is
> not required by the current one-bit IN mode.

| Mega Drive port 2 | Meaning | SNES port 2 |
|---|---|---|
| **pin 9, TR** | row toggle (counter bit 0) | **pin 4, Data1** |
| **pin 7, TH** | counter bit 1 (present, ignored by IN) | **pin 5, Data2** |
| **pin 8, GND** | common ground | **pin 7, GND** |

Recommended adapter:

```text
Mega Drive DE-9 pin 9 (TR) ──[330 Ω–1 kΩ]──► SNES pin 4 (Data1)
Mega Drive DE-9 pin 7 (TH) ──[330 Ω–1 kΩ]──► SNES pin 5 (Data2)
Mega Drive DE-9 pin 8 (GND) ─────────────────► SNES pin 7 (GND)
```

SNES pin numbers here are shown from the console-socket side: pin 1 is at the
flat end and pin 7 at the rounded end. The controller plug's mating face is
mirrored. When repinning a cable shell, confirm pins 4, 5 and 7 from the wire
side with a continuity meter before applying power.

This is a one-way 5 V-logic connection from the Mega Drive to the SNES input;
no level translator should be required. The small series resistor is sensible
fault protection during bring-up. The verified cable includes TH → Data2, but
sndj IN ignores this line, so a minimal IN-only cable may omit it. Do **not**
connect Mega Drive pin 5 (+5 V) to SNES pin 1 (+5 V), and leave every other
pin unconnected.

### Cross-console bring-up procedure

1. With both consoles powered off, connect the three-conductor adapter to controller
   port 2 on each console. Use the normal controllers in port 1.
2. Set genmddj to **SYNC: OUT** and sndj to **SYNC: IN**.
3. Start or arm sndj first so that it displays **WAIT**.
4. Start genmddj. Its first row-count change releases sndj from WAIT and starts
   sndj row 0. genmddj is now the tempo and groove master.
5. Stop both transports before restarting; re-arm sndj before starting genmddj
   again.

There is no song-position transfer. Arrange both projects so the intended
starting material is under their respective cursors before arming. The slave's
groove is ignored for row timing while in IN; the varying intervals between the
master's row clocks carry genmddj's groove feel across the cable.

One-frame-scale phase uncertainty is expected because each console samples the
counter on its own video/tick schedule. Test NTSC/NTSC first, then PAL and mixed
regions. The count protocol itself is region-independent.

## First hardware-test checklist

- Confirm connector pins with continuity mode before applying power.
- Confirm the XIAO side of the translator never exceeds 3.3 V.
- Confirm the SNES Data1 level switches cleanly. Data2 is not required.
- Verify sndj's RX count rises before judging musical alignment.
- Test 60, 120 and 180 BPM, abrupt tempo changes, stop/re-arm/restart, and a
  deliberate Link/Wi-Fi interruption.
- Listen for missed or doubled rows across the full test tempo range.
- Record console models, video regions, flashcarts, translator circuit and the
  measured latency offset when marking a setup as hardware-verified.
