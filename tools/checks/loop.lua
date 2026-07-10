-- loop.lua — the SMP LOOP override (record byte 7 bits 1-2): every
-- sample uploads with LOOP+END on its final block, so loop-or-not is
-- purely the ARAM directory's choice. A per-instrument override gets
-- one alias entry: OFF re-points a looped sample's loop at the silent
-- stub (plays once); ON gives a one-shot a whole-sample loop.
--
-- Instruments under test: I1 = VIOLIN 1 (pool 1, looped at block 629),
-- forced OFF; I2 -> PERCUSSI (pool 7, one-shot), forced ON.

local frames = 0
local _booted = false
local fails = 0
local pad = {}
local W = emu.memType.snesWorkRam

local function wram(a) return emu.read(a, W) end
local function poke(a, v) emu.write(a, v, W) end
local function dsp(r) return emu.read(r, emu.memType.spcDspRegisters) end
local function aram(a) return emu.read(a, emu.memType.spcRam) end
local function dirw(slot, o) return aram(0x1000 + slot * 4 + o) + aram(0x1001 + slot * 4 + o) * 256 end

local function check(cond, msg)
  if cond then
    print("PASS " .. msg)
  else
    print("FAIL " .. msg)
    fails = fails + 1
  end
end

local script = {
  [14] = { start = true }, [16] = {},
  -- SONG -> CHAIN -> PHRASE -> INSTR (context descent lands on I1,
  -- the phrase row's instrument)
  [34] = { a = true }, [36] = { a = true, right = true }, [38] = {},
  [42] = { a = true }, [44] = { a = true, right = true }, [46] = {},
  [50] = { a = true }, [52] = { a = true, right = true }, [54] = {},
  -- cursor to LOOP (I1 is SMP: fields 0 INSTR, 1 TYPE, 2 SAMPLE, 4 LOOP)
  [66] = { down = true }, [68] = {},
  [70] = { down = true }, [72] = {},
  [74] = { down = true }, [76] = {},
  -- nudge LOOP 1 -> 2 (poked to 1=ON below; the gesture makes it OFF)
  [80] = { b = true }, [82] = { b = true, right = true },
  [84] = { b = true }, [86] = {},
  -- rebuild runs ~2s; then back to SONG and play
  [300] = { a = true }, [302] = { a = true, left = true }, [304] = {},
  [308] = { a = true }, [310] = { a = true, left = true }, [312] = {},
  [316] = { a = true }, [318] = { a = true, left = true }, [320] = {},
  [330] = { start = true }, [332] = {},
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
    poke(0x2000, 0)            -- V1 r0 = chain 0
    poke(0x2080, 1)            -- V2 r0 = chain 1
    poke(0x3700, 0)            -- chain 0 e0 = phrase 0
    poke(0x3720, 1)            -- chain 1 e0 = phrase 1
    -- I1 = VIOLIN (SMP sample 1, looped); LOOP=1 pre-poke, the gesture
    -- nudges it to 2 = one-shot and rebuilds residency
    poke(0x2411, 1)
    poke(0x2417, 0x02)         -- byte7: LOOP override 1 (ON)
    -- I2 = SMP on PERCUSSI (pool 7, one-shot), LOOP forced ON by poke
    -- (the same rebuild publishes both aliases)
    poke(0x2421, 7)
    poke(0x2427, 0x02 * 1)     -- placeholder; set properly below
    poke(0x2427, 0x02)         -- byte7: LOOP override 1 (ON)
    poke(0x4300, 49)           -- phrase 0 row 0: C-4, I1
    poke(0x4301, 1)
    poke(0x4340, 49)           -- phrase 1 row 0: C-4, I2
    poke(0x4341, 2)
  elseif frames == 290 then
    check(wram(0x2417) == 0x04, string.format(
      "B+Right nudged LOOP ON -> OFF (byte7 $%02X, ui %02X)",
      wram(0x2417), wram(0x0C)))
  elseif frames == 350 then
    -- voice 0 = I1 (VIOLIN forced one-shot): alias loop -> the stub
    local s0 = dsp(0x04)
    local s1 = dsp(0x14)
    check(s0 > 0, "I1 plays through an alias SRCN (" .. s0 .. ")")
    check(dirw(s0, 2) == 0x1200,
      "forced one-shot: alias loop -> the silent stub")
    check(dirw(s0, 0) ~= 0x1200,
      "alias start is the real sample")
    -- voice 1 = I2 (one-shot forced to loop): alias loop == start
    check(s1 > 0 and s1 ~= s0, "I2 has its own alias (" .. s1 .. ")")
    check(dirw(s1, 2) == dirw(s1, 0),
      "forced loop on a one-shot: whole-sample loop (loop == start)")
  elseif frames == 425 then
    -- late in the phrase (before row 0 retriggers): the forced
    -- one-shot violin (~0.3 s) has died; the forced-loop percussion
    -- (13 ms one-shot looping whole) is still sounding
    check(dsp(0x08) == 0,
      "forced one-shot ended (ENVX " .. dsp(0x08) .. ")")
    check(dsp(0x18) > 0, "forced loop still sounding (ENVX " .. dsp(0x18) .. ")")
    if fails == 0 then
      print("ALL PASS loop.lua")
      emu.stop(0)
    else
      print("FAILED loop.lua: " .. fails)
      emu.stop(1)
    end
  end
end, emu.eventType.endFrame)
