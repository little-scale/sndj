# HARDWARE.md — sndj on real silicon

Notes from hardware bring-up. The controller-port sync pinout, level
shifting and the ESP32 bridge get documented here as the rigs are
verified (CLAUDE.md §12-13); what's below is verified today.

The build instructions and pin-by-pin adapters for XIAO Link → sndj and
genmddj OUT → sndj are in [`LINK-SYNC-WIRING.md`](LINK-SYNC-WIRING.md).

## Reference rig

- **FXPak Pro** (SD2SNES) in a SNES/SFC console is the reference cart.
  SRAM: 32 KB, LoROM $70:0000. The boot splash's version + git-hash
  stamp is the stale-flash detector — check it before trusting a test.

## Silicon errata the code guards against

### APU mailbox port glitch (found v0.1 hardware bring-up, 2026-07-11)

An SPC700 read of a mailbox port ($2140-3) that lands **during** the
S-CPU's write can return **mixed bits** — neither the old nor the new
value. Emulators (including Mesen 2) do not model this, so it only
appears on real hardware, and because the S-CPU (21.477 MHz) and APU
(24.576 MHz) clocks are asynchronous, the collision phase — and the
corruption — differs on every reset.

Symptom as first seen: sample uploads sheared by one 3-byte round
(garbled BRR playback) or ended early by a phantom zero byte
(instruments silently mapped to the stub), different instruments
affected each boot.

Defenses (CLAUDE.md invariant #13):

- the driver **double-reads port 0** until two consecutive reads agree
  before acting on it (main command poll and bulk rounds);
- bulk mode accepts **only the expected successor counter** (1..255,
  wrapping, 0 reserved as the end marker) — a glitched byte is ignored,
  not adopted;
- the CPU **resyncs and retries once** on any upload timeout
  (`apu_resync`: port 0 = 0 converges both sides to sequence 0);
- transfers are kept to **one bulk session per sample** (the BRR LOOP
  bit is patched into the stream in transit, not sent separately).

### SRAM powers up as $FF

Fresh or unformatted battery RAM reads $FF everywhere. Anything that
persists in the SRAM header must be **seeded at format** and
**range-checked at boot** — masking is not validation ($FF & 7 = 7
picked palette 7 on every reset until this was fixed).

## Emulator vs hardware differences observed

| Behavior | Mesen 2 | Hardware |
|---|---|---|
| Port read during write | clean old/new value | can return mixed bits |
| Live ENVX reads via $F2/$F3 | return 0 (meters flat) | real values (meters live) |
| SRAM initial contents | whatever the .srm file holds | $FF |
