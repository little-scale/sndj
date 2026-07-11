-- chordtap.lua — PHRASE cmd-column B-tap: a tap on a C command auditions
-- the chord (root + x/y offsets, voices 0/1/2) through the row's note +
-- instrument, and a tap on any non-empty command cell no longer clobbers
-- it (the genmddj only-drop-into-empty rule).

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

local function row(r, note, instr, cmd, val)
  local base = 0x4300 + r * 4
  poke(base, note); poke(base + 1, instr)
  poke(base + 2, cmd); poke(base + 3, val)
end

local script = {
  [30] = { start = true }, [32] = {},                                -- SONG
  [38] = { a = true }, [40] = { a = true, right = true }, [42] = {}, -- CHAIN
  [44] = { a = true }, [46] = { a = true, right = true }, [48] = {}, -- PHRASE
  -- cursor to the CMD column
  [52] = { right = true }, [54] = {},
  [56] = { right = true }, [58] = {},
  -- B tap on the C47 cell -> chord audition
  [62] = { b = true }, [64] = {},
  -- down twice to row 2 (a G command), tap -> must do nothing
  [74] = { down = true }, [76] = {},
  [78] = { down = true }, [80] = {},
  [84] = { b = true }, [86] = {},
}

emu.addEventCallback(function() emu.setInput(pad, 0) end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if not _booted then
    if emu.read(1, emu.memType.snesWorkRam) == 0x5D then _booted = true end
    return
  end
  frames = frames + 1
  if script[frames] then pad = script[frames] end

  if frames == 34 then
    poke(0x2000, 0)           -- grid: track 0 row 0 = chain 0
    poke(0x3700, 0)           -- chain 0 entry 0 = phrase 0
    poke(0x2401, 7)           -- instr 0 -> BD
    poke(0x2406, 0xEF)        -- FINE -17 cancels BD's pool fine: net zero tune
    row(0, 49, 0, 3, 0x47)    -- C-4, instr 0, C47: major chord
    row(2, 0, 0xFF, 7, 0x10)  -- G10 on row 2: non-C command
  elseif frames == 50 then
    check(wram(0x000C) == 1, "navigated to the PHRASE screen")
  elseif frames == 60 then
    check(wram(0x0019) == 2, "cursor on the CMD column")
  elseif frames == 72 then
    check(wram(0x4302) == 3 and wram(0x4303) == 0x47,
      "tap left the C47 cell intact")
    check(wram(0x0015) == 1, "tap auditioned (1 KON)")
    local p0 = dsp(0x02) + dsp(0x03) * 256
    local p1 = dsp(0x12) + dsp(0x13) * 256
    local p2 = dsp(0x22) + dsp(0x23) * 256
    check(p0 == 0x0800 and p1 == 0x0A14 and p2 == 0x0BFC,
      "audition fanned the chord like playback (" ..
      string.format("%04X/%04X/%04X", p0, p1, p2) .. ")")
  elseif frames == 92 then
    check(wram(0x000F) == 2, "cursor on row 2")
    check(wram(0x430A) == 7, "tap left the G command intact (no clobber)")
    check(wram(0x0015) == 1, "non-C tap stayed silent (still 1 KON)")
    if fails == 0 then
      print("ALL PASS chordtap.lua")
      emu.stop(0)
    else
      print("FAILED chordtap.lua: " .. fails)
      emu.stop(1)
    end
  end
end, emu.eventType.endFrame)
