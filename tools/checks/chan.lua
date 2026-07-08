-- chan.lua — channel switching: L/R shoulders (and Y+left/right) re-target
-- CHAIN at the adjacent track's chain for this song row; empty tracks no-op.
--
-- Setup: chain 00 at (track 0, row 0), chain 01 at (track 1, row 0), enter
-- track 0's chain, then hop R / R(no-op) / L / Y+right.
-- WRAM: ui_mode $0C, ed_chain $1A, song_cx $1B.

local frames = 0
local _booted = false
local fails = 0
local pad = {}

local function wram(addr) return emu.read(addr, emu.memType.snesWorkRam) end

local function check(cond, msg)
  if cond then
    print("PASS " .. msg)
  else
    print("FAIL " .. msg)
    fails = fails + 1
  end
end

local script = {
  [30] = { start = true }, [32] = {},          -- SONG
  [36] = { b = true }, [38] = {},              -- chain 00 at (0,0)
  [42] = { right = true }, [44] = {},          -- cursor -> track 1
  [48] = { b = true }, [50] = {},              -- chain 00 at (1,0)
  [54] = { b = true },
  [56] = { b = true, right = true },
  [58] = { b = true },
  [60] = {},                                   -- nudge (1,0) -> chain 01
  [64] = { left = true }, [66] = {},           -- cursor -> track 0
  [70] = { a = true },
  [72] = { a = true, right = true },
  [74] = {},                                   -- CHAIN (chain 00)
  [80] = { r = true }, [82] = {},              -- R: hop to track 1's chain
  [90] = { r = true }, [92] = {},              -- R again: track 2 empty, no-op
  [100] = { l = true }, [102] = {},            -- L: back to track 0
  [110] = { y = true },
  [112] = { y = true, right = true },
  [114] = {},                                  -- Y+right: hop right again
}

emu.addEventCallback(function() emu.setInput(pad, 0) end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if not _booted then
    if emu.read(1, emu.memType.snesWorkRam) == 0x5D then _booted = true end
    return
  end
  frames = frames + 1
  if script[frames] then pad = script[frames] end

  if frames == 62 then
    check(wram(0x2000) == 0, "chain 00 at (track 0, row 0)")
    check(wram(0x2080) == 1, "chain 01 at (track 1, row 0)")
  elseif frames == 78 then
    check(wram(0x0C) == 2, "on CHAIN")
    check(wram(0x1A) == 0 and wram(0x1B) == 0, "editing track 0's chain 00")
  elseif frames == 86 then
    check(wram(0x1A) == 1 and wram(0x1B) == 1, "R hopped to track 1's chain 01")
  elseif frames == 96 then
    check(wram(0x1A) == 1 and wram(0x1B) == 1, "R into empty track 2 is a no-op")
  elseif frames == 106 then
    check(wram(0x1A) == 0 and wram(0x1B) == 0, "L hopped back to track 0")
  elseif frames == 118 then
    check(wram(0x1A) == 1 and wram(0x1B) == 1, "Y+right hops like R")
    if fails == 0 then
      print("ALL PASS chan.lua")
      emu.stop(0)
    else
      print("FAILED chan.lua: " .. fails)
      emu.stop(1)
    end
  end
end, emu.eventType.endFrame)
