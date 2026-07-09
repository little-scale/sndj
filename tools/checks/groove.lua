-- groove.lua — the GROOVE screen: reachable with A+Down from CHAIN,
-- B+d-pad edits steps live (clamped 1-15), and a faster groove really
-- advances rows faster (grooves ARE the tempo).
--
-- WRAM: ui_mode $0C, grooves at $3000 (16 x 16), eng_row $17.

local frames = 0
local _booted = false
local fails = 0
local pad = {}

local function wram(addr) return emu.read(addr, emu.memType.snesWorkRam) end
local function poke(a, v) emu.write(a, v, emu.memType.snesWorkRam) end

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
  [36] = { a = true, down = true },
  [38] = {},                                   -- GROOVE
  -- step 0: 6 -> 3 (B held + left x3)
  [44] = { b = true },
  [46] = { b = true, left = true },
  [48] = { b = true },
  [50] = { b = true, left = true },
  [52] = { b = true },
  [54] = { b = true, left = true },
  [56] = { b = true },
  [58] = {},
  -- nudge down past the floor must clamp at 1 (B held + down = -4)
  [62] = { b = true },
  [64] = { b = true, down = true },
  [66] = { b = true },
  [68] = {},
  -- then up +4 -> 5, and B tap on step 1 repeats it
  [72] = { b = true },
  [74] = { b = true, up = true },
  [76] = { b = true },
  [78] = {},
  [84] = { down = true }, [86] = {},           -- cursor to step 1
  [94] = { b = true }, [96] = {},              -- tap: repeat 5
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
    check(wram(0x0C) == 11, "A+Down opened GROOVE from CHAIN")
  elseif frames == 60 then
    check(wram(0x3000) == 3, "step 0 nudged 6 -> 3")
  elseif frames == 70 then
    check(wram(0x3000) == 1, "nudge clamps at 1 tick")
  elseif frames == 80 then
    check(wram(0x3000) == 5, "up nudge landed on 5")
  elseif frames == 100 then
    check(wram(0x3001) == 5, "B tap repeated the value on step 1")
    -- author the rest fast and play: all steps 3 = double speed
    for i = 0, 15 do poke(0x3000 + i, 3) end
    poke(0x3700, 0)          -- chain 0 entry 0 = phrase 0
    poke(0x4300, 49)
  elseif frames == 104 then
    pad = { start = true }
  elseif frames == 106 then
    pad = {}
  elseif frames == 136 then
    -- 30 frames at 3 ticks/row ~= 10 rows (vs ~5 at groove 6); sample
    -- before the 16-row phrase wrap
    local row = wram(0x17)
    check(wram(0x16) == 1, "playing")
    check(row >= 8 and row <= 13, "groove 3 doubles the row rate (row=" .. row .. ")")
    if fails == 0 then
      print("ALL PASS groove.lua")
      emu.stop(0)
    else
      print("FAILED groove.lua: " .. fails)
      emu.stop(1)
    end
  end
end, emu.eventType.endFrame)
