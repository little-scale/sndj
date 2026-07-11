-- entry.lua — song-column entry semantics (Seb, 2026-07-12): playing
-- from a row means "the arrangement AT that row" — each track enters
-- at the first populated cell at/ABOVE the start row (the chain
-- covering it). Nothing above = the column is silent. SONG's Start
-- plays from the cursor row (LSDJ feel).

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
    poke(0x2401, 7)          -- instr 0 -> BD
    poke(0x2406, 0xEF)       -- FINE -17 cancels BD's pool fine: net zero
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
    pad = { start = true }             -- Start at cursor row 0
  elseif frames == 46 then
    pad = {}
  elseif frames == 60 then
    check(wram(0x16) == 1, "playing")
    check(wram(0x20) == 0 and wram(0x38) == 0,
      "track 1 covers row 0 (chain 0)")
    check(wram(0x2F) == 0xFF,
      "track 8 has nothing at/above row 0: silent")
    -- stop, cursor down 3, Start again: row 3 is covered by both
  elseif frames == 66 then
    pad = { start = true }             -- stop
  elseif frames == 68 then
    pad = {}
  elseif frames == 72 then
    pad = { down = true }
  elseif frames == 74 then
    pad = {}
  elseif frames == 78 then
    pad = { down = true }
  elseif frames == 80 then
    pad = {}
  elseif frames == 84 then
    pad = { down = true }
  elseif frames == 86 then
    pad = {}
  elseif frames == 90 then
    pad = { start = true }             -- play the arrangement at row 3
  elseif frames == 92 then
    pad = {}
  elseif frames == 106 then
    check(wram(0x16) == 1, "playing from row 3")
    check(wram(0x20) == 0 and wram(0x38) == 0,
      "track 1 entered the chain covering row 3 (chain 0 at row 0)")
    check(wram(0x27) == 1 and wram(0x3F) == 1,
      "track 8 entered the chain covering row 3 (chain 1 at row 1)")
    check(wram(0x2F) ~= 0xFF, "track 8 is not halted")
    local p0 = dsp(0x02) + dsp(0x03) * 256
    local p7 = dsp(0x72) + dsp(0x73) * 256
    check(p0 == 0x0800 and p7 == 0x1000,
      "both entries pitched their voices ($" ..
      string.format("%04X/$%04X", p0, p7) .. ")")
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
