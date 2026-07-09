-- table.lua — per-tick instrument tables: the trigger starts the
-- instrument's table, both command columns execute through the shared
-- executor each tick, and H hops the table's own rows.
--
-- Table 0 (all factory instruments point at it; empty = no-op):
--   row 0: P00 | X01   pan hard left + echo send, same tick
--   row 1: M30         master volume $30
--   row 2: H01         hop -> rows 1-2 loop forever
--
-- WRAM: tables at $2800 (64/table, 4/row); trk_tbl $2FF, row $307.

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
    poke(0x2000, 0)
    poke(0x3700, 0)
    poke(0x2401, 23)         -- instr 0 -> SW ORCH
    poke(0x4300, 49)         -- C-4, instrument 0 (its TABLE field is 0)
    poke(0x4301, 0)
    -- table 0
    poke(0x2800, 16)         -- P
    poke(0x2801, 0x00)
    poke(0x2802, 24)         -- X (column 2, same tick)
    poke(0x2803, 0x01)
    poke(0x2804, 13)         -- M
    poke(0x2805, 0x30)
    poke(0x2808, 8)          -- H
    poke(0x2809, 0x01)
  elseif frames == 44 then
    pad = { start = true }
  elseif frames == 46 then
    pad = {}
  elseif frames == 52 then
    check(wram(0x2FF) == 0, "trigger started the instrument's table 0")
    check(dsp(0x00) == 0x7F and dsp(0x01) == 0x00,
      "row 0 col 1: P00 panned hard left")
    check(dsp(0x4D) ~= 0 and (dsp(0x4D) % 2) == 1,
      "row 0 col 2: X01 raised the echo send the same tick")
  elseif frames == 58 then
    check(dsp(0x0C) == 0x30 and dsp(0x1C) == 0x30,
      "row 1: M30 set master volume")
  elseif frames == 80 then
    local r = wram(0x307)
    check(r == 1 or r == 2, "H01 keeps the table looping rows 1-2 (row=" ..
      r .. ")")
    if fails == 0 then
      print("ALL PASS table.lua")
      emu.stop(0)
    else
      print("FAILED table.lua: " .. fails)
      emu.stop(1)
    end
  end
end, emu.eventType.endFrame)
