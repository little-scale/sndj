-- vibtrm.lua — instrument VIB/TRM (record bytes 14/15): vibrato and tremolo
-- run from the instrument with no phrase command; a row V overrides the
-- instrument's VIB for that note only (V00 = off), and the next plain
-- trigger reloads it. Tremolo dips VOL L/R below the set level, never above.

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

local p_lo, p_hi = 0xFFFF, 0
local v_lo, v_hi = 0xFF, 0
local function collect()
  local p = dsp(0x02) + dsp(0x03) * 256
  local v = dsp(0x00)
  if p < p_lo then p_lo = p end
  if p > p_hi then p_hi = p end
  if v < v_lo then v_lo = v end
  if v > v_hi then v_hi = v end
end
local function reset_window()
  p_lo, p_hi, v_lo, v_hi = 0xFFFF, 0, 0xFF, 0
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
    poke(0x2000, 0)          -- grid: track 0 row 0 = chain 0
    poke(0x3700, 0)          -- chain 0 entry 0 = phrase 0
    poke(0x2401, 12)         -- instr 0 -> BONGO 2 (tune 0)
    poke(0x240E, 0x48)       -- instr 0 VIB: speed 4, depth 8
    poke(0x240F, 0x4F)       -- instr 0 TRM: speed 4, depth 15
    row(0, 49, 0, 0, 0)      -- C-4, no command: instrument LFOs alone
    row(4, 49, 0, 22, 0)     -- C-4 + V00: vibrato off for this note
    row(8, 49, 0, 0, 0)      -- C-4 plain: instrument VIB reloads
    row(12, 49, 0, 24, 0x20) -- C-4 + X20: accent — TRM dips from $20
  elseif frames == 44 then
    pad = { start = true }
  elseif frames == 46 then
    pad = {}
  elseif frames >= 50 and frames <= 68 then
    collect()
  elseif frames == 70 then
    check(p_lo < 0x0800 and p_hi > 0x0800,
      "instrument VIB modulates around C-4 with no command ($" ..
      string.format("%04X-$%04X", p_lo, p_hi) .. ")")
    check(p_lo >= 0x0700 and p_hi <= 0x0900, "VIB 48 depth bounded")
    check(v_lo < 0x50 and v_hi <= 0x50,
      "instrument TRM dips VOL L below $50, never above (" ..
      string.format("%02X-%02X", v_lo, v_hi) .. ")")
    check(v_lo ~= v_hi, "TRM is moving")
  elseif frames >= 76 and frames <= 92 then
    collect()
  elseif frames == 74 then
    reset_window()
  elseif frames == 94 then
    check(p_lo == 0x0800 and p_hi == 0x0800,
      "V00 killed the instrument vibrato for this note ($" ..
      string.format("%04X-$%04X", p_lo, p_hi) .. ")")
    check(v_lo < 0x50, "V00 left the tremolo running")
    reset_window()
  elseif frames >= 100 and frames <= 116 then
    collect()
  elseif frames == 118 then
    check(p_lo < 0x0800 and p_hi > 0x0800,
      "the next plain note reloaded the instrument VIB ($" ..
      string.format("%04X-$%04X", p_lo, p_hi) .. ")")
    reset_window()
  elseif frames >= 124 and frames <= 140 then
    collect()
  elseif frames == 142 then
    check(v_hi <= 0x20 and v_lo < 0x20,
      "X20 accent retargets the level; TRM dips from it (" ..
      string.format("%02X-%02X", v_lo, v_hi) .. ")")
    if fails == 0 then
      print("ALL PASS vibtrm.lua")
      emu.stop(0)
    else
      print("FAILED vibtrm.lua: " .. fails)
      emu.stop(1)
    end
  end
end, emu.eventType.endFrame)
