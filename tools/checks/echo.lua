-- echo.lua — M9 gate: the ECHO screen configures the room through the
-- driver's safe reconfiguration; an EDL walk never corrupts resident
-- samples or the directory (CLAUDE.md invariant #4); FIR presets and the
-- X/Y commands land in the DSP.

local frames = 0
local _booted = false
local fails = 0
local pad = {}
local W = emu.memType.snesWorkRam

local function wram(a) return emu.read(a, W) end
local function poke(a, v) emu.write(a, v, W) end
local function dsp(r) return emu.read(r, emu.memType.spcDspRegisters) end
local function aram(a) return emu.read(a, emu.memType.spcRam) end

local function check(cond, msg)
  if cond then
    print("PASS " .. msg)
  else
    print("FAIL " .. msg)
    fails = fails + 1
  end
end

local aram_snap = nil
local function snap_aram()
  local t = {}
  for a = 0x1000, 0x1003 do t[#t + 1] = aram(a) end      -- directory
  for a = 0x1200, 0x1247 do t[#t + 1] = aram(a) end      -- sample BRR
  return t
end
local function aram_intact(t)
  local i = 1
  for a = 0x1000, 0x1003 do
    if aram(a) ~= t[i] then return false end
    i = i + 1
  end
  for a = 0x1200, 0x1247 do
    if aram(a) ~= t[i] then return false end
    i = i + 1
  end
  return true
end

-- input scripting
local script = {}
local t = 30
local function gest(buttons, gap)
  script[t] = buttons
  t = t + 2
  script[t] = {}
  t = t + (gap or 2)
end
local function nudge(dir, wait)
  script[t] = { b = true }
  t = t + 2
  script[t] = { b = true, [dir] = true }
  t = t + 2
  script[t] = { b = true }
  t = t + 2
  script[t] = {}
  t = t + (wait or 2)
end

gest({ start = true }, 4)                 -- SONG
-- poke navigation context happens at frame 26 (below)
gest({ a = true, right = true }, 4)       -- CHAIN
gest({ a = true, right = true }, 4)       -- PHRASE
gest({ a = true, right = true }, 4)       -- INSTR
gest({ a = true, down = true }, 6)        -- ECHO
local at_echo = t
-- Boot ships EDL 0 (instant boot; NEW auto-opens the room instead). One
-- hardware-sized reconfiguration proves the safe clear; factory.lua verifies
-- the current residency ceiling separately without timing input during clears.
nudge("up", 2500)
local edl4 = t
-- FIR field (down 5) -> preset 1
gest({ down = true })
gest({ down = true })
gest({ down = true })
gest({ down = true })
gest({ down = true })
nudge("right", 10)
local fir1 = t
-- EON field: $FF default wraps to 0 (+1), then a second +1 opens ch 1
gest({ up = true })
nudge("right", 10)
local eon1 = t
nudge("right", 6)
-- Y/X commands via playback (song already has chain0/phrase0 context)
local play = t + 4
local cmds_done = play + 40

emu.addEventCallback(function() emu.setInput(pad, 0) end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if not _booted then
    if emu.read(1, emu.memType.snesWorkRam) == 0x5D then _booted = true end
    return
  end
  frames = frames + 1
  if script[frames] then pad = script[frames] end
  if frames == play then pad = { start = true } end
  if frames == play + 2 then pad = {} end

  if frames == 26 then
    poke(0x2000, 0)          -- V1r0 = chain 0
    poke(0x3700, 0)          -- chain0 e0 = phrase 0
    -- phrase 0: row0 = note + Y03 (FIR comb), row4 = note + E00 (EON off)
    poke(0x4300, 49)
    poke(0x4301, 0)
    poke(0x4302, 25)         -- Y
    poke(0x4303, 3)
    poke(0x4310, 49)
    poke(0x4311, 0xFF)
    poke(0x4312, 5)          -- E
    poke(0x4313, 0)
    poke(0x2407, 1)          -- instr 0: ECHO flag on (the sound opts in)
    aram_snap = snap_aram()
  elseif frames == at_echo then
    check(wram(0x0C) == 6, "navigated to the ECHO screen")
    check(dsp(0x2C) == 0x30 and dsp(0x0D) == 0x30,
      "echo volume/feedback applied at boot")
    check(dsp(0x7D) == 0, "boot ships EDL 0")
  elseif frames == edl4 then
    check(dsp(0x7D) == 4, "EDL walked to 4")
    check(dsp(0x6D) == 0xE0, "ESA follows")
    check(dsp(0x6C) == 0x00, "FLG re-enabled after reconfig")
    check(aram_intact(aram_snap), "samples intact at EDL 4")
  elseif frames == fir1 then
    check(dsp(0x0F) == 0x58 and dsp(0x1F) == 0x30 and dsp(0x2F) == 0x12,
      "FIR preset 1 (DARK) taps written")
  elseif frames == eon1 then
    check(wram(0x3607) == 0x00, "EON mask edits the song header ($FF wraps)")
    check(dsp(0x4D) == 0x00, "all gates shut: no sends")
  elseif frames == play + 12 then
    check(dsp(0x4D) % 2 == 1,
      "instrument ECHO + open gate = the voice sends")
  elseif frames == cmds_done then
    check(dsp(0x0F) == 0x40 and dsp(0x3F) == 0x40,
      "Y03 selected the COMB FIR preset mid-song")
    check(dsp(0x4D) == 0x00, "E00 shut the channel's gate")
    check(aram_intact(aram_snap), "samples intact after command playback")
    if fails == 0 then
      print("ALL PASS echo.lua")
      emu.stop(0)
    else
      print("FAILED echo.lua: " .. fails)
      emu.stop(1)
    end
  end
end, emu.eventType.endFrame)
