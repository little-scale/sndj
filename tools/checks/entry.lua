-- entry.lua — song-column entry semantics (genmddj DESIGN §5.4): a track
-- enters at the FIRST POPULATED CELL at/below the start row, so a chain
-- placed at row 1 with row 0 empty still sounds from Start; a fully
-- empty column halts. (The user-reported track-8 silence bug.)

local frames = 0
local _booted = false
local fails = 0
local pad = {}

local function wram(addr) return emu.read(addr, emu.memType.snesWorkRam) end
local function poke(a, v) emu.write(a, v, emu.memType.snesWorkRam) end
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

  if frames == 30 then
    poke(0x2401, 23)         -- instr 0 -> tune-0 sample
    -- track 0: chain 0 at row 0; track 7: row 0 EMPTY, chain 1 at row 1
    poke(0x2000, 0)
    poke(0x2000 + 7 * 128 + 1, 1)
    poke(0x3700, 0)          -- chain 0 e0 = phrase 0
    poke(0x3720, 1)          -- chain 1 e0 = phrase 1
    poke(0x4300, 49)         -- phrase 0 row 0: C-4 i0
    poke(0x4301, 0)
    poke(0x4340, 61)         -- phrase 1 row 0: C-5 i0
    poke(0x4341, 0)
  elseif frames == 44 then
    pad = { start = true }
  elseif frames == 46 then
    pad = {}
  elseif frames == 60 then
    check(wram(0x16) == 1, "playing")
    check(wram(0x27) == 1, "track 8 entered at its first populated row (chain 1)")
    check(wram(0x3F) == 1, "track 8's song row is 1")
    check(wram(0x2F) ~= 0xFF, "track 8 is not halted")
    -- both voices sound (one batched KON covers both)
    local p0 = dsp(0x02) + dsp(0x03) * 256
    local p7 = dsp(0x72) + dsp(0x73) * 256
    check(p0 == 0x0800 and p7 == 0x1000,
      "both entries pitched their voices ($" ..
      string.format("%04X/$%04X", p0, p7) .. ")")
    -- tracks 1-6 (fully empty columns) stay halted
    check(wram(0x29) == 0xFF and wram(0x2E) == 0xFF,
      "empty columns halt as before")
    if fails == 0 then
      print("ALL PASS entry.lua")
      emu.stop(0)
    else
      print("FAILED entry.lua: " .. fails)
      emu.stop(1)
    end
  end
end, emu.eventType.endFrame)
