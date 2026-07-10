-- table.lua — instrument tables: TBL picks the table (>= 32 = nil),
-- TBS clocks it (n ticks/row; 0 = advance per note). A row is
-- (V, TSP, CMD, VAL): voice level, signed transpose, ONE command
-- through the shared executor; zero = no change. H hops the table.
--
-- Table 0:
--   row 0: V20          level $20 on the voice
--   row 1: M30          master volume $30 (the command column)
--   row 2: TSP +12      pitch doubles (an octave up off the note)
--   row 3: H02          hop -> rows 2-3 loop forever
--
-- WRAM: tables at $2800 (64/table, 4/row); trk_tbl $2FF, row $307.

local frames = 0
local _booted = false
local fails = 0
local pad = {}
local base_pitch = 0

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
    poke(0x2401, 12)         -- instr 0 -> SW ORCH
    poke(0x4300, 49)         -- C-4, instrument 0
    poke(0x4301, 0)
    poke(0x240C, 0)          -- instr 0: TBL = 0
    poke(0x240D, 1)          -- TBS = every tick
    poke(0x2407, 1)          -- instr 0: ECHO flag on (E gates the channel)
    -- note-sync + nil coverage: notes on rows 4 and 6 use instr 1
    -- (TBL nil from factory) then instr 2 with TBS 0
    poke(0x4310, 49)         -- row 4: instr 1, no table
    poke(0x4311, 1)
    poke(0x4318, 49)         -- row 6: instr 2, note-sync table 1
    poke(0x4319, 2)
    poke(0x431C, 49)         -- row 7: instr 2 again (advances one row)
    poke(0x431D, 2)
    poke(0x2411, 12)         -- instr 1/2 -> BONGO 2 too
    poke(0x2421, 12)
    poke(0x241C, 0xFF)       -- instr 1 TBL nil (factory default, explicit)
    poke(0x242C, 1)          -- instr 2: TBL = 1
    poke(0x242D, 0)          -- TBS = note-sync
    -- table 1: M values per note (CMD col = bytes 2/3)
    poke(0x2842, 13)
    poke(0x2843, 0x10)
    poke(0x2846, 13)
    poke(0x2847, 0x20)
    -- table 0
    poke(0x2800, 0x20)       -- row 0: V $20
    poke(0x2806, 13)         -- row 1: M $30 (the command column)
    poke(0x2807, 0x30)
    poke(0x2809, 12)         -- row 2: TSP +12
    poke(0x280E, 8)          -- row 3: H02
    poke(0x280F, 0x02)
  elseif frames == 44 then
    pad = { start = true }
  elseif frames == 46 then
    pad = {}
  elseif frames == 48 then
    check(wram(0x2FF) == 0, "trigger started the instrument's table 0")
    check(dsp(0x00) == 0x20 and dsp(0x01) == 0x20,
      "row 0: V20 retargeted the voice level")
    base_pitch = dsp(0x02) + dsp(0x03) * 256
  elseif frames == 58 then
    check(dsp(0x0C) == 0x30 and dsp(0x1C) == 0x30,
      "row 1: M30 set master volume (the command column)")
    local p = dsp(0x02) + dsp(0x03) * 256
    check(math.abs(p - base_pitch * 2) <= 2,
      "row 2: TSP +12 doubled the pitch (" .. base_pitch .. " -> " .. p .. ")")
  elseif frames == 70 then
    local r = wram(0x307)
    check(r == 2 or r == 3, "H02 keeps the table looping rows 2-3 (row=" ..
      r .. ")")
  elseif frames == 78 then
    -- row 4 triggered instr 1: TBL nil ends the running table
    check(wram(0x2FF) == 0xFF, "TBL -- (nil) stops the voice's table")
  elseif frames == 86 then
    -- row 6: instr 2, note-sync: exactly one row ran (M10), no more
    check(dsp(0x0C) == 0x10, "TBS 0: first note ran one table row (M10)")
  elseif frames == 102 then
    -- row 7: the next note advanced to row 1 (M20)
    check(dsp(0x0C) == 0x20, "TBS 0: the next note advanced the table (M20)")
    if fails == 0 then
      print("ALL PASS table.lua")
      emu.stop(0)
    else
      print("FAILED table.lua: " .. fails)
      emu.stop(1)
    end
  end
end, emu.eventType.endFrame)
