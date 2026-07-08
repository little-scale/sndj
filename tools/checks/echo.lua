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
-- EDL: 0 -> +4 -> +1 -> +1 = 6 (each walks the safe reconfig)
nudge("up", 45)
nudge("right", 45)
nudge("right", 50)
local edl6 = t
-- EDL walk: 6 -> 10 -> 14 (long waits: old-delay flush + offset wrap)
nudge("up", 70)
nudge("up", 80)
local edl14 = t
-- back down to 3: -4 -4 -4 (clamps at 2) +1
nudge("down", 80)
nudge("down", 70)
nudge("down", 60)
nudge("right", 60)
local edl3 = t
-- FIR field (down 5) -> preset 1
gest({ down = true })
gest({ down = true })
gest({ down = true })
gest({ down = true })
gest({ down = true })
nudge("right", 10)
local fir1 = t
-- EON field (up 1) -> +1
gest({ up = true })
nudge("right", 10)
local eon1 = t
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
    -- phrase 0: row0 = note + Y03 (FIR comb), row4 = note + X00 (EON off)
    poke(0x4300, 49)
    poke(0x4301, 0)
    poke(0x4302, 25)         -- Y
    poke(0x4303, 3)
    poke(0x4310, 49)
    poke(0x4311, 0xFF)
    poke(0x4312, 24)         -- X
    poke(0x4313, 0)
    aram_snap = snap_aram()
  elseif frames == at_echo then
    check(wram(0x0C) == 6, "navigated to the ECHO screen")
    check(dsp(0x2C) == 0x30 and dsp(0x0D) == 0x30,
      "echo volume/feedback applied at boot")
  elseif frames == edl6 then
    check(dsp(0x7D) == 6, "EDL walked to 6")
    check(dsp(0x6D) == 0xD0, "ESA tracks EDL (top of ARAM)")
    check(dsp(0x6C) == 0x00, "FLG re-enabled after reconfig")
    check(aram_intact(aram_snap), "samples intact at EDL 6")
  elseif frames == edl14 then
    check(dsp(0x7D) == 14, "EDL walked to 14")
    check(dsp(0x6D) == 0x90, "ESA tracks EDL 14")
    check(aram_intact(aram_snap), "samples intact at EDL 14")
  elseif frames == edl3 then
    check(dsp(0x7D) == 3, "EDL walked back to 3")
    check(dsp(0x6D) == 0xE8, "ESA tracks EDL 3")
    check(aram_intact(aram_snap), "samples intact after the whole walk")
  elseif frames == fir1 then
    check(dsp(0x0F) == 0x58 and dsp(0x1F) == 0x30 and dsp(0x2F) == 0x12,
      "FIR preset 1 (DARK) taps written")
  elseif frames == eon1 then
    check(dsp(0x4D) == 0x01, "EON mask edit reached the DSP")
  elseif frames == cmds_done then
    check(dsp(0x0F) == 0x40 and dsp(0x3F) == 0x40,
      "Y03 selected the COMB FIR preset mid-song")
    check(dsp(0x4D) == 0x00, "X00 cleared the voice's echo send")
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
