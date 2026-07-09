-- mailbox.lua — M2 gate: SPC700 driver uploads, mailbox round-trips,
-- a CPU-issued SCB write lands in a DSP register, tick telemetry flows,
-- and a dead APU produces a visible "APU?" timeout instead of a hang.
--
-- WRAM map (frozen block, src/ram.inc): $01 magic_boot, $0D apu_status,
-- $11 apu_tick, $12 hb_val. Heartbeat: hb_val -> DSP MVOLL ($0C) every
-- 64 frames (into unused DSP reg $1D).

local frames = 0
local _booted = false
local fails = 0
local tick_sample = -1
local pad = {}

local function wram(addr)
  return emu.read(addr, emu.memType.snesWorkRam)
end

local function dsp(reg)
  return emu.read(reg, emu.memType.spcDspRegisters)
end

local function check(cond, msg)
  if cond then
    print("PASS " .. msg)
  else
    print("FAIL " .. msg)
    fails = fails + 1
  end
end

local function cell(x, y)
  return emu.read(0x0400 + (y * 32 + x) * 2, emu.memType.snesWorkRam)
      + emu.read(0x0400 + (y * 32 + x) * 2 + 1, emu.memType.snesWorkRam) * 256
end

local function onFrame()
  if not _booted then
    if emu.read(1, emu.memType.snesWorkRam) == 0x5D then _booted = true end
    return
  end
  frames = frames + 1

  if frames == 20 then
    check(wram(0x0001) == 0x5D, "boot completed with APU upload in path")
    check(wram(0x000D) == 0, "apu_status ok after driver upload")
    tick_sample = wram(0x0011)
  elseif frames == 50 then
    local t = wram(0x0011)
    check(t ~= tick_sample, "APU tick telemetry advancing (" ..
      tick_sample .. " -> " .. t .. ")")
    -- after audio + echo init: unmuted, echo idle at EDL 0 (buffer at $FF00)
    check(dsp(0x6C) == 0x20, "DSP FLG unmuted, echo idle at EDL 0 ($" ..
      string.format("%02X", dsp(0x6C)) .. ")")
  elseif frames == 100 then
    -- heartbeat fires at ROM frame 64 (~lua frame 75): check after it
    local hb = wram(0x0012)
    local mv = dsp(0x1D)
    check(hb > 0, "heartbeat counter running (hb=" .. hb .. ")")
    check(mv == hb, "SCB path: heartbeat landed in DSP reg $1D (" ..
      mv .. " == " .. hb .. ")")
  elseif frames == 104 then
    pad = { start = true }     -- leave the splash: chrome draws off-splash
  elseif frames == 107 then
    pad = {}
  elseif frames == 110 then
    -- kill the APU: fill the driver region with SLEEP opcodes ($EF).
    -- The next heartbeat must time out visibly, not hang.
    for a = 0x0200, 0x0FFF do
      emu.write(a, 0xEF, emu.memType.spcRam)
    end
    print("info: APU driver frozen (SLEEP-filled) to force a timeout")
  elseif frames == 250 then
    -- next heartbeat hits the dead mailbox; timeout is ~0.4s (~25 frames)
    check(wram(0x000D) == 1, "apu_status flags the timeout")
    -- "APU?" drawn accent at (27,1): inverted 'A' (tile 33+96), attr $2400
    check(cell(27, 1) == (string.byte("A") - 32 + 96 | 0x2400), "UI shows APU? warning")
    check(cell(30, 1) == (string.byte("?") - 32 + 96 | 0x2400), "UI shows APU? question mark")
    -- and the machine is still alive:
    local fc = wram(0x0002) + wram(0x0003) * 256
    check(fc > 200, "CPU survived the APU death (frames=" .. fc .. ")")
    if fails == 0 then
      print("ALL PASS mailbox.lua")
      emu.stop(0)
    else
      print("FAILED mailbox.lua: " .. fails)
      emu.stop(1)
    end
  end
end

emu.addEventCallback(function() emu.setInput(pad, 0) end, emu.eventType.inputPolled)
emu.addEventCallback(onFrame, emu.eventType.endFrame)
