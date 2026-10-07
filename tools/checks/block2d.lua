-- block2d.lua — CHAIN and SONG block selection expands in both dimensions.
-- Clipboard cells are packed row-major even though SONG storage is column-major.

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
  [30] = { start = true }, [32] = {},

  -- SONG: anchor V2 row 2, stretch to V3 row 3, copy.
  [40] = { y = true }, [42] = { y = true, b = true }, [44] = {},
  [48] = { right = true }, [50] = {},
  [54] = { down = true }, [56] = {},
  [60] = { b = true }, [62] = {},
  -- Paste at V5 row 5.
  [72] = { b = true }, [74] = {}, [78] = { b = true }, [80] = {},

  -- Descend from SONG V1 row 0 into CHAIN 00.
  [92] = { a = true }, [94] = { a = true, right = true }, [96] = {},
  -- CHAIN: anchor PHR row 2, stretch to TSP row 3, copy.
  [104] = { y = true }, [106] = { y = true, b = true }, [108] = {},
  [112] = { right = true }, [114] = {},
  [118] = { down = true }, [120] = {},
  [124] = { b = true }, [126] = {},
  -- Paste at PHR row 5.
  [136] = { b = true }, [138] = {}, [142] = { b = true }, [144] = {},

  -- CHAIN -> PHRASE -> INSTR -> TABLE, then coarse-nudge TSP upward.
  [154] = { a = true }, [156] = { a = true, right = true }, [158] = {},
  [164] = { a = true }, [166] = { a = true, right = true }, [168] = {},
  [172] = { a = true }, [174] = { a = true, right = true }, [176] = {},
  [184] = { right = true }, [186] = {},
  [190] = { b = true }, [192] = {},
  [196] = { b = true }, [198] = { b = true, up = true },
  [200] = { b = true }, [202] = {},
}

emu.addEventCallback(function() emu.setInput(pad, 0) end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if not booted then
    if wram(1) == 0x5D then booted = true end
    return
  end
  frames = frames + 1
  if script[frames] then pad = script[frames] end

  if frames == 36 then
    -- Distinct 2x2 SONG source rectangle, rows 2-3 / tracks 1-2.
    poke(0x2082, 0x11); poke(0x2102, 0x21)
    poke(0x2083, 0x12); poke(0x2103, 0x22)
    poke(0x1B, 1); poke(0x1C, 2); poke(0x1D, 0)
  elseif frames == 66 then
    check(wram(0xE4) == 3 and wram(0xE5) == 2 and wram(0x0C23) == 2,
      "SONG copied a 2-row x 2-track rectangle")
    check(wram(0x7400) == 0x11 and wram(0x7401) == 0x21 and
      wram(0x7402) == 0x12 and wram(0x7403) == 0x22,
      "SONG clipboard is packed row-major")
  elseif frames == 68 then
    poke(0x1B, 4); poke(0x1C, 5)
  elseif frames == 84 then
    check(wram(0x2205) == 0x11 and wram(0x2285) == 0x21 and
      wram(0x2206) == 0x12 and wram(0x2286) == 0x22,
      "SONG pasted both rows and tracks at the destination cell")
    check(wram(0xE4) == 0 and wram(0x0C23) == 0,
      "SONG rectangle paste consumed the clipboard")
  elseif frames == 88 then
    poke(0x2000, 0)
    poke(0x1B, 0); poke(0x1C, 0); poke(0x1D, 0)
  elseif frames == 100 then
    check(wram(0x0C) == 2, "navigated to CHAIN 00")
    -- Distinct 2x2 CHAIN source rectangle, rows 2-3 / PHR+TSP.
    poke(0x3704, 0x0A); poke(0x3705, 0x01)
    poke(0x3706, 0x0B); poke(0x3707, 0x02)
    poke(0x1E, 2); poke(0x1F, 0)
  elseif frames == 130 then
    check(wram(0xE4) == 2 and wram(0xE5) == 2 and wram(0x0C23) == 2,
      "CHAIN copied a 2-row x 2-column rectangle")
    check(wram(0x7400) == 0x0A and wram(0x7401) == 0x01 and
      wram(0x7402) == 0x0B and wram(0x7403) == 0x02,
      "CHAIN clipboard contains balanced PHR/TSP rows")
  elseif frames == 132 then
    poke(0x1E, 5); poke(0x1F, 0)
  elseif frames == 150 then
    check(wram(0x370A) == 0x0A and wram(0x370B) == 0x01 and
      wram(0x370C) == 0x0B and wram(0x370D) == 0x02,
      "CHAIN pasted the full rectangle without lopsided columns")
    poke(0x3700, 0); poke(0x1E, 0); poke(0x1F, 0)
    poke(0x4301, 0); poke(0x240C, 0)
  elseif frames == 180 then
    check(wram(0x0C) == 14, "navigated from CHAIN through INSTR to TABLE")
    poke(0x2801, 0)
  elseif frames == 194 then
    check(wram(0x2801) == 0x80,
      "TABLE TSP tap inserted explicit 00 instead of leaving --")
  elseif frames == 206 then
    check(wram(0x2801) == 12,
      "TABLE TSP coarse-up changed 00 to +12 semitones")
    if fails == 0 then
      print("ALL PASS block2d.lua")
      emu.stop(0)
    else
      print("FAILED block2d.lua: " .. fails)
      emu.stop(1)
    end
  end
end, emu.eventType.endFrame)
