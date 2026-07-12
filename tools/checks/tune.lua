-- tune.lua — instrument FINE (rec byte 6, signed 1/256 semitone) bends the
-- pitch by table interpolation. +64 = +quarter semitone above C-4; -64
-- borrows from B-3. Expected values mirror the asm exactly:
--   C-4 base $0800, C#4 $0879 -> +64: $0800 + (121*64>>8)  = $081E
--   B-3 $078D, delta 115      -> -64: $078D + (115*192>>8) = $07E3

local frames = 0
local _booted = false
local fails = 0
local pad = {}

local function wram(addr) return emu.read(addr, emu.memType.snesWorkRam) end
local function poke(addr, v) emu.write(addr, v, emu.memType.snesWorkRam) end
local function dsp(reg) return emu.read(reg, emu.memType.spcDspRegisters) end

local function check(cond, msg)
  if cond then
    print("PASS " .. msg)
  else
    print("FAIL " .. msg)
    fails = fails + 1
  end
end

emu.addEventCallback(function() emu.setInput(pad, 0) end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if not _booted then
    if emu.read(1, emu.memType.snesWorkRam) == 0x5D then _booted = true end
    return
  end
  frames = frames + 1
  if frames == 14 then pad = { start = true } end
  if frames == 17 then pad = {} end

  if frames == 40 then
    poke(0x2000, 0)          -- grid V1 row 0 = chain 0
    poke(0x3700, 0)          -- chain 0 entry 0 = phrase 0
    poke(0x4300, 49)         -- C-4
    poke(0x4301, 0)          -- instrument 0 (factory SMP)
    poke(0x2401, 7)           -- available sound; pool tune is neutral here
    poke(0x2406, 0x40)       -- +64 (a quarter semitone)
  elseif frames == 44 then
    pad = { start = true }
  elseif frames == 46 then
    pad = {}
  elseif frames == 56 then
    check(wram(0x16) == 1, "playing")
    local p = dsp(0x02) + dsp(0x03) * 256
    check(p == 0x081E, "FINE +64 lands a quarter semitone up ($" ..
      string.format("%04X", p) .. ")")
  elseif frames == 60 then
    pad = { start = true }   -- stop
  elseif frames == 62 then
    pad = {}
    poke(0x2406, 0xC0)       -- -64 (borrows from B-3)
  elseif frames == 66 then
    pad = { start = true }   -- play again
  elseif frames == 68 then
    pad = {}
  elseif frames == 78 then
    local p = dsp(0x02) + dsp(0x03) * 256
    check(p == 0x07E3, "FINE -64 borrows from B-3 ($" ..
      string.format("%04X", p) .. ")")
    if fails == 0 then
      print("ALL PASS tune.lua")
      emu.stop(0)
    else
      print("FAILED tune.lua: " .. fails)
      emu.stop(1)
    end
  end
end, emu.eventType.endFrame)
