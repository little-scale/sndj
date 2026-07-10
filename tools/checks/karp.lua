-- karp.lua — the KARP instrument type (M-KARP): Karplus-Strong on the
-- echo loop. A trigger writes the note's 2-tap FIR pair (fractional
-- pull + damping, scaled by DAMP), feedback = SUSTAIN, and KONs the
-- exciter wave bank at the comb partial's exact pitch with a fast
-- burst envelope and a forced echo send.
--
-- Instrument: type 5, bank 2 (saw), DAMP 8 (side 14, pair 99),
-- BURST 6, SUSTAIN $70. The tap total is always 127: SUSTAIN owns
-- ring time, DAMP colors. EDL 1 table:
--   A-5 (idx 69): pitch $0E00, i0 0 fr 0 -> C0 113, C2 14
--   C-6 (idx 72): pitch $10C5, i0 6 fr 255 -> C5 14, C6 1, C7 112

local frames = 0
local _booted = false
local fails = 0
local pad = {}
local W = emu.memType.snesWorkRam

local function wram(a) return emu.read(a, W) end
local function poke(a, v) emu.write(a, v, W) end
local function dsp(r) return emu.read(r, emu.memType.spcDspRegisters) end

local function check(cond, msg)
  if cond then
    print("PASS " .. msg)
  else
    print("FAIL " .. msg)
    fails = fails + 1
  end
end

local function firtaps()
  local t = {}
  for i = 0, 7 do t[i] = dsp(0x0F + i * 16) end
  return t
end

local script = {
  [14] = { start = true }, [16] = {},
  [44] = { start = true }, [46] = {},
  -- phase 2: flipping another instrument's TYPE to KARP at EDL 12
  -- must size the room back to a string (DELAY 1). SONG draws heavy
  -- while playing: 4-frame pulses
  [100] = { start = true }, [104] = {},
  [110] = { a = true }, [114] = { a = true, right = true }, [118] = {},
  [124] = { a = true }, [128] = { a = true, right = true }, [132] = {},
  [138] = { a = true }, [142] = { a = true, right = true }, [146] = {},
  [152] = { y = true }, [156] = { y = true, down = true }, [160] = {},
  [166] = { down = true }, [170] = {},
  [176] = { b = true }, [180] = { b = true, right = true },
  [184] = { b = true }, [188] = {},
}

emu.addEventCallback(function() emu.setInput(pad, 0) end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if not _booted then
    if emu.read(1, W) == 0x5D then _booted = true end
    return
  end
  frames = frames + 1
  if script[frames] then pad = script[frames] end

  if frames == 30 then
    poke(0x2000, 0)          -- V1 r0 = chain 0
    poke(0x3700, 0)          -- chain 0 e0 = phrase 0
    poke(0x3603, 1)          -- song EDL 1 (the 16 ms string)
    poke(0x2400, 5)          -- instrument 0: KARP
    poke(0x2401, 2)          -- exciter = wave bank 2 (saw)
    poke(0x2402, 0x68)       -- BURST 6 | DAMP 8
    poke(0x2403, 0x70)       -- SUSTAIN
    poke(0x2407, 0)          -- no echo flag needed: KARP forces the send
    poke(0x4300, 70)         -- row 0: A-5 (idx 69)
    poke(0x4301, 0)
    poke(0x4310, 73)         -- row 4: C-6 (idx 72)
    poke(0x4311, 0)
  elseif frames == 54 then
    -- row 0: A-5
    check(dsp(0x04) == 58, "exciter SRCN = wave bank 2 (" .. dsp(0x04) .. ")")
    local p = dsp(0x02) + dsp(0x03) * 256
    check(p == 0x0E00, string.format(
      "A-5 excites partial 14 at its exact pitch ($%04X)", p))
    check(dsp(0x05) == 0xFF, string.format(
      "burst envelope: instant attack, decay 7 ($%02X)", dsp(0x05)))
    check(dsp(0x06) == 0x19, string.format(
      "burst tail: SL 0, SR from the seed table (BURST 6 -> 25, $%02X)",
      dsp(0x06)))
    check(dsp(0x0D) == 0x70, string.format(
      "feedback = SUSTAIN ($%02X)", dsp(0x0D)))
    check(dsp(0x4D) & 1 == 1, "echo send forced on for the exciter")
    local t = firtaps()
    check(t[0] == 113 and t[1] == 0 and t[2] == 14 and t[7] == 0,
      "A-5 taps: pair+left at C0, side at C2 (" .. t[0] .. "/" .. t[2] .. ")")
    check(t[0] + t[1] + t[2] == 127, "tap total 127: DAMP never changes gain")
  elseif frames == 94 then
    -- row 4: C-6 — the fractional pair lands at taps 6/7
    local p = dsp(0x02) + dsp(0x03) * 256
    check(p == 0x10C5, string.format(
      "C-6 excites partial 17, pulled 7 samples ($%04X)", p))
    local t = firtaps()
    check(t[5] == 14 and t[6] == 1 and t[7] == 112 and t[0] == 0,
      "C-6 taps: side 5, pair 6/7 with the right side merged (" ..
      t[5] .. "/" .. t[6] .. "/" .. t[7] .. ")")
    check(t[5] + t[6] + t[7] == 127, "tap total 127 at the top edge too")
    check(wram(0x16) == 1, "still playing (no runaway)")
  elseif frames == 106 then
    poke(0x3603, 12)         -- a big hall again
    poke(0x2410, 4)          -- I1 pre-staged at SLICE (one nudge to KARP)
    poke(0x2411, 2)
  elseif frames == 430 then
    check(wram(0x3603) == 1,
      "TYPE -> KARP sized the room to a string (EDL " .. wram(0x3603) .. ")")
    check(wram(0x2410) == 5, "I1 is KARP")
    if fails == 0 then
      print("ALL PASS karp.lua")
      emu.stop(0)
    else
      print("FAILED karp.lua: " .. fails)
      emu.stop(1)
    end
  end
end, emu.eventType.endFrame)
