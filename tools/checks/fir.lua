-- fir.lua — the FIR screen: A+Right from ECHO; B+d-pad edits a tap in
-- the song header AND the live DSP register, marking the curve custom;
-- Y+Down recalls the next ROM preset into the taps.
--
-- WRAM: ui_mode $0C, header FIR id $3611+... SH_FIR = header+8 ($3608),
-- taps at header+19 ($3613). DSP FIR tap n = n*16+$0F.

local frames = 0
local _booted = false
local fails = 0
local pad = {}

local function wram(addr) return emu.read(addr, emu.memType.snesWorkRam) end
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
  [14] = { start = true }, [16] = {},
  -- SONG -> INSTR (via chain/phrase would need content; use the map:
  -- SONG right needs a chain, so go SONG -> down FILES? no: ECHO is
  -- below INSTR: A+Right x3 needs content. Take the long way:
  -- poke a chain so A+Right works.
  [24] = { a = true }, [26] = { a = true, right = true }, [28] = {},  -- CHAIN
  [32] = { a = true }, [34] = { a = true, right = true }, [36] = {},  -- PHRASE
  [40] = { a = true }, [42] = { a = true, right = true }, [44] = {},  -- INSTR
  [48] = { a = true }, [50] = { a = true, down = true }, [52] = {},   -- ECHO
  [56] = { a = true }, [58] = { a = true, right = true }, [60] = {},  -- FIR
  -- nudge tap 0 up by 16 (B held + up)
  [66] = { b = true },
  [68] = { b = true, up = true },
  [70] = { b = true },
  [72] = {},
  -- recall preset 1 (DARK): Y held + down
  [80] = { y = true },
  [82] = { y = true, down = true },
  [84] = {},
}

emu.addEventCallback(function() emu.setInput(pad, 0) end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if not _booted then
    if emu.read(1, emu.memType.snesWorkRam) == 0x5D then _booted = true end
    return
  end
  frames = frames + 1
  if script[frames] then pad = script[frames] end

  if frames == 20 then
    -- content so the spine navigation descends
    emu.write(0x2000, 0, emu.memType.snesWorkRam)
    emu.write(0x3700, 0, emu.memType.snesWorkRam)
    emu.write(0x4300, 49, emu.memType.snesWorkRam)
    emu.write(0x4301, 0, emu.memType.snesWorkRam)
  elseif frames == 62 then
    check(wram(0x0C) == 13, "A+Right opened FIR from ECHO")
    check(wram(0x3613) == 0x7F, "taps seeded from FLAT (T0 = $7F)")
  elseif frames == 76 then
    check(wram(0x3613) == 0x8F, "B+Up nudged T0 by +16")
    check(dsp(0x0F) == 0x8F, "tap edit reached the DSP live")
    check(wram(0x3608) == 0xFF, "hand edit marks the curve custom")
  elseif frames == 90 then
    check(wram(0x3608) == 0, "Y+Down recalled preset 0 (custom wraps to 0)")
    check(wram(0x3613) == 0x7F and dsp(0x0F) == 0x7F,
      "preset recall rewrote taps + DSP")
    if fails == 0 then
      print("ALL PASS fir.lua")
      emu.stop(0)
    else
      print("FAILED fir.lua: " .. fails)
      emu.stop(1)
    end
  end
end, emu.eventType.endFrame)
