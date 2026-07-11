-- project.lua — the PROJECT screen: A+Up from CHAIN; TSP/MODE
-- edit the song header; TSP transposes triggers; MODE=LIVE makes the
-- S map position open the launcher. NEW is NOT here (FILES owns it:
-- LOAD on the empty row) — the cursor wraps after 4 fields.
--
-- WRAM: ui_mode $0C, pj_cur $2DB, header at $3600 (TSP +1, MODE +17),
-- phrase 0 row 0 at $4300.

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

local script = {
  [14] = { start = true }, [16] = {},          -- splash -> SONG
  [20] = { b = true }, [22] = {},              -- chain 00 at (0,0)
  [26] = { a = true },
  [28] = { a = true, right = true },
  [30] = {},                                   -- CHAIN
  [34] = { a = true },
  [36] = { a = true, up = true },
  [38] = {},                                   -- PROJECT
  -- down x2 -> TSP (the GROOVE field left for the GROOVE screen),
  -- one nudge up = +12 (an octave)
  [44] = { down = true }, [46] = {},
  [48] = { down = true }, [50] = {},
  [58] = { b = true },
  [60] = { b = true, up = true },   -- +12
  [62] = { b = true },
  [64] = { b = true },
  [66] = { b = true },
  [68] = { b = true },
  [70] = { b = true },
  [72] = {},
  -- down -> MODE, toggle to LIVE
  [78] = { down = true }, [80] = {},
  [84] = { b = true },
  [86] = { b = true, right = true },
  [88] = { b = true },
  [90] = {},
  -- play with TSP +12 (zero-tune sample poked below)
  [100] = { start = true }, [102] = {},
  [130] = { start = true }, [132] = {},        -- stop
  -- cursor is on MODE already; one Down wraps to NAME (no NEW field)
  [140] = { down = true }, [142] = {},
}

emu.addEventCallback(function() emu.setInput(pad, 0) end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if not _booted then
    if emu.read(1, emu.memType.snesWorkRam) == 0x5D then _booted = true end
    return
  end
  frames = frames + 1
  if script[frames] then pad = script[frames] end

  if frames == 42 then
    check(wram(0x0C) == 12, "A+Up opened PROJECT from CHAIN")
    -- author a note for the transpose test
    poke(0x3700, 0)
    poke(0x4300, 49)         -- C-4
    poke(0x4301, 0)
    poke(0x2401, 7)          -- BD
    poke(0x2406, 0xEF)       -- FINE -17 cancels BD's pool fine: net zero
  elseif frames == 74 then
    check(wram(0x3601) == 12, "TSP nudged to +12")
  elseif frames == 92 then
    check(wram(0x3611) == 1, "MODE toggled to LIVE")
  elseif frames == 120 then
    check(wram(0x16) == 1, "playing")
    local p = dsp(0x02) + dsp(0x03) * 256
    check(p == 0x1000, "song transpose +12 raised C-4 an octave ($" ..
      string.format("%04X", p) .. ")")
  elseif frames == 138 then
    check(wram(0x2DB) == 3, "cursor sits on MODE (field 3, the last)")
  elseif frames == 148 then
    check(wram(0x2DB) == 0, "no NEW field: the cursor wraps after MODE")
    check(wram(0x4300) == 49, "the song survived (NEW lives on FILES)")
    if fails == 0 then
      print("ALL PASS project.lua")
      emu.stop(0)
    else
      print("FAILED project.lua: " .. fails)
      emu.stop(1)
    end
  end
end, emu.eventType.endFrame)
