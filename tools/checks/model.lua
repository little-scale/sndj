-- model.lua — M5 gate: the sibling-parity edit scenario. Builds a two-track
-- song entirely through the pad grammar (SONG cells -> chains -> phrases,
-- transpose on the chain entry), navigates the screen map with A+d-pad,
-- plays it, and asserts both voices land the right pitches.
--
-- Layout under test:
--   V1 row0 = chain 00 -> phrase 00 (tsp 0)  -> C-4 -> voice 0 pitch $0800
--   V2 row0 = chain 01 -> phrase 01 (tsp 12) -> C-4 -> voice 1 pitch $1000

local frames = 0
local _booted = false
local fails = 0
local pad = {}
local env0_peak, env1_peak = 0, 0

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
  [30] = { start = true }, [32] = {},                     -- SONG
  [36] = { b = true }, [38] = {},                         -- V1r0 = chain 00
  [42] = { right = true }, [44] = {},                     -- cursor to V2
  [48] = { b = true }, [50] = {},                         -- V2r0 = chain 00
  [54] = { b = true }, [56] = { b = true, right = true }, -- nudge -> 01
  [58] = { b = true }, [60] = {},
  [64] = { a = true }, [66] = { a = true, right = true }, -- into CHAIN 01
  [68] = {},
  [72] = { b = true }, [74] = {},                         -- entry0 phrase 00
  [78] = { b = true }, [80] = { b = true, right = true }, -- nudge -> 01
  [82] = { b = true }, [84] = {},
  [88] = { right = true }, [90] = {},                     -- TSP column
  [94] = { b = true }, [96] = { b = true, up = true },    -- tsp +12
  [98] = { b = true }, [100] = {},
  [104] = { a = true }, [106] = { a = true, right = true }, -- into PHRASE 01
  [108] = {},
  [112] = { b = true }, [114] = {},                       -- C-4 at row 0
  [118] = { a = true }, [120] = { a = true, left = true }, -- back to CHAIN
  [122] = {},
  [126] = { a = true }, [128] = { a = true, left = true }, -- back to SONG
  [130] = {},
  [134] = { left = true }, [136] = {},                    -- cursor to V1
  [140] = { a = true }, [142] = { a = true, right = true }, -- into CHAIN 00
  [144] = {},
  [146] = { left = true }, [148] = {},                    -- back to PHR column
  [152] = { b = true }, [154] = {},                       -- entry0 = 01 (buf)
  [156] = { b = true }, [158] = { b = true, left = true }, -- nudge -> 00
  [160] = { b = true }, [162] = {},
  [164] = { a = true }, [166] = { a = true, right = true }, -- into PHRASE 00
  [168] = {},
  [172] = { b = true }, [174] = {},                       -- C-4 at row 0
  [178] = { a = true }, [180] = { a = true, left = true }, [182] = {},
  [186] = { a = true }, [188] = { a = true, left = true }, [190] = {},
  [196] = { start = true }, [198] = {},                   -- play the song
  [220] = { start = true }, [222] = {},                   -- stop
}

emu.addEventCallback(function() emu.setInput(pad, 0) end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if not _booted then
    if emu.read(1, emu.memType.snesWorkRam) == 0x5D then _booted = true end
    return
  end
  frames = frames + 1
  if frames > 196 then
    if emu.read(0x08, emu.memType.spcDspRegisters) > env0_peak then
      env0_peak = emu.read(0x08, emu.memType.spcDspRegisters)
    end
    if emu.read(0x18, emu.memType.spcDspRegisters) > env1_peak then
      env1_peak = emu.read(0x18, emu.memType.spcDspRegisters)
    end
  end
  if script[frames] then pad = script[frames] end

  if frames == 70 then
    check(wram(0x000C) == 2, "A+Right descended into CHAIN")
    check(wram(0x001A) == 1, "editing chain 01")
    check(wram(0x2000) == 0, "SONG V1 row0 = chain 00")
    check(wram(0x2080) == 1, "SONG V2 row0 = chain 01")
  elseif frames == 110 then
    check(wram(0x000C) == 1, "A+Right descended into PHRASE")
    check(wram(0x0018) == 1, "editing phrase 01")
    check(wram(0x3720) == 1, "chain 01 entry0 -> phrase 01")
    check(wram(0x3721) == 12, "chain 01 entry0 transpose +12")
  elseif frames == 194 then
    -- zero-tune sample for the exact pitch asserts (factory melodics
    -- carry loop-quantise tune corrections)
    emu.write(0x2401, 12, emu.memType.snesWorkRam)
  elseif frames == 192 then
    check(wram(0x000C) == 3, "A+Left climbed back to SONG")
    check(wram(0x3700) == 0, "chain 00 entry0 -> phrase 00")
    check(wram(0x3701) == 0, "chain 00 entry0 transpose 0")
    check(wram(0x4300) == 49, "phrase 00 row0 = C-4")
    check(wram(0x4340) == 49, "phrase 01 row0 = C-4")
  elseif frames == 212 - 2 then
    check(env0_peak > 0 and env1_peak > 0, "both envelopes alive (peaks " ..
      env0_peak .. "/" .. env1_peak .. ")")
  elseif frames == 212 then
    check(wram(0x0016) == 1, "song playing")
    check(wram(0x0020) == 0 and wram(0x0021) == 1, "tracks loaded chains 00/01")
    check(wram(0x0028) == 0 and wram(0x0029) == 1, "tracks playing phrases 00/01")
    local p0 = dsp(0x02) + dsp(0x03) * 256
    local p1 = dsp(0x12) + dsp(0x13) * 256
    check(p0 == 0x0800, "voice 0 pitch C-4 ($" .. string.format("%04X", p0) .. ")")
    check(p1 == 0x1000, "voice 1 pitch C-5 via +12 transpose ($" ..
      string.format("%04X", p1) .. ")")
  elseif frames == 228 then
    check(wram(0x0016) == 0, "stopped")
    local out = os.getenv("SNDJ_SONG_SHOT")
    if out then
      local png = emu.takeScreenshot()
      local f = io.open(out, "wb")
      f:write(png)
      f:close()
      print("info: song screenshot -> " .. out)
    end
    if fails == 0 then
      print("ALL PASS model.lua")
      emu.stop(0)
    else
      print("FAILED model.lua: " .. fails)
      emu.stop(1)
    end
  end
end, emu.eventType.endFrame)
