-- cmd3.lua — the phrase-variation pair: I (play-count mask decides
-- WHETHER a row fires each pass) and J (mask x + signed nibble y decide
-- WHAT pitch). One looping phrase, asserts across two passes.
--
-- Rows (groove 6 ~= 6 frames/row, pass = 16 rows ~= 96 frames):
--   r0: C-4 + I55 — plays on even passes only ($55 bit0 = 1)
--   r2: E-4 + J22 — pass 1 transposed +2 (mask $2 = bit1)

local frames = 0
local _booted = false
local fails = 0
local pad = {}
local kon_p0 = -1

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

emu.addEventCallback(function() emu.setInput(pad, 0) end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if not _booted then
    if emu.read(1, emu.memType.snesWorkRam) == 0x5D then _booted = true end
    return
  end
  frames = frames + 1
  if frames == 14 then pad = { start = true } end
  if frames == 17 then pad = {} end

  if frames == 30 then
    poke(0x2000, 0)
    poke(0x3700, 0)
    poke(0x2401, 7)          -- BD
    poke(0x2406, 0xEF)       -- FINE -17 cancels BD's pool fine: net zero
    poke(0x4300, 49)         -- r0: C-4
    poke(0x4301, 0)
    poke(0x4302, 9)          -- I
    poke(0x4303, 0x55)
    poke(0x4308, 53)         -- r2: E-4
    poke(0x4309, 0)
    poke(0x430A, 10)         -- J
    poke(0x430B, 0x22)
  elseif frames == 44 then
    pad = { start = true }
  elseif frames == 46 then
    pad = {}
  elseif frames == 53 then
    -- pass 0 row 0: I55 bit0 set -> C-4 fires
    local p = dsp(0x02) + dsp(0x03) * 256
    check(p == 0x0800, "pass 0: I55 lets row 0 fire (C-4)")
  elseif frames == 65 then
    -- pass 0 row 2: J22 mask bit0 clear -> plain E-4
    local p = dsp(0x02) + dsp(0x03) * 256
    check(p == 0x0A14, "pass 0: J22 leaves row 2 at E-4")
  elseif frames == 141 then
    kon_p0 = wram(0x15)      -- kons before pass 1 row 0
  elseif frames == 149 then
    -- pass 1 row 0: I55 bit1 clear -> the note drops
    check(wram(0x15) == kon_p0, "pass 1: I55 drops row 0 (no KON)")
    local p = dsp(0x02) + dsp(0x03) * 256
    check(p == 0x0A14, "pass 1: pitch still row 2's E-4")
  elseif frames == 161 then
    -- pass 1 row 2: J22 bit1 set -> E-4 + 2 = F#4
    local p = dsp(0x02) + dsp(0x03) * 256
    check(p == 0x0B50, "pass 1: J22 transposes row 2 to F#4 ($" ..
      string.format("%04X", p) .. ")")
    if fails == 0 then
      print("ALL PASS cmd3.lua")
      emu.stop(0)
    else
      print("FAILED cmd3.lua: " .. fails)
      emu.stop(1)
    end
  end
end, emu.eventType.endFrame)
