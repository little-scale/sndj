-- live_mint.lua — LIVE keeps B transport-safe while sharing SONG's
-- double-tap chain mint/clone grammar.

local frames = 0
local booted = false
local fails = 0
local pad = {}
local W = emu.memType.snesWorkRam

local function wram(a) return emu.read(a, W) end
local function poke(a, v) emu.write(a, v, W) end

local function check(cond, msg)
  if cond then
    print("PASS " .. msg)
  else
    print("FAIL " .. msg)
    fails = fails + 1
  end
end

local script = {
  [14] = { start = true }, [16] = {},             -- splash -> SONG
  [20] = { select = true }, [22] = {},            -- SONG -> LIVE
  [26] = { right = true }, [28] = {},             -- track 2, populated
  [32] = { b = true }, [34] = {},
  [38] = { b = true }, [40] = {},                 -- clone chain 0 -> 1
  [46] = { down = true }, [48] = {},              -- empty row
  [52] = { b = true }, [54] = {},
  [58] = { b = true }, [60] = {},                 -- mint chain 2
  [66] = { up = true }, [68] = {},
  [72] = { left = true }, [74] = {},              -- back to chain 0
  [78] = { a = true, b = true }, [80] = {},       -- launch still A+B
}

emu.addEventCallback(function() emu.setInput(pad, 0) end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if not booted then
    if wram(1) == 0x5D then booted = true end
    return
  end
  frames = frames + 1
  if script[frames] then pad = script[frames] end

  if frames == 18 then
    -- Chain 0 is observably populated and appears in two LIVE cells.
    poke(0x2000, 0)
    poke(0x2080, 0)
    poke(0x3700, 0)
    poke(0x4300, 49)
    poke(0x4301, 0)
  elseif frames == 24 then
    check(wram(0x0C) == 8, "Select opened LIVE")
  elseif frames == 44 then
    check(wram(0x2080) == 1, "LIVE double-B cloned a populated chain")
    check(wram(0x3720) == 0, "LIVE chain clone copied its phrase reference")
    check(wram(0x16) == 0, "LIVE clone did not start transport")
  elseif frames == 64 then
    check(wram(0x2081) == 2, "LIVE double-B minted a fresh chain on an empty cell")
    check(wram(0x16) == 0, "LIVE mint did not start transport")
  elseif frames == 86 then
    check(wram(0x16) == 1, "LIVE A+B still launches transport")
    check(wram(0x20) == 0, "LIVE A+B launched the selected chain")
    if fails == 0 then
      print("ALL PASS live_mint.lua")
      emu.stop(0)
    else
      print("FAILED live_mint.lua: " .. fails)
      emu.stop(1)
    end
  end
end, emu.eventType.endFrame)
