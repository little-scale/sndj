-- factory.lua — smoke-test the untouched project factory: container-derived
-- pool metadata, boot residency, real pool tuning, audible output and echo
-- headroom. Core checks run separately with pool tuning neutralized.

local frames, fails, peak = 0, 0, 0
local booted = false
local pad = {}
local W = emu.memType.snesWorkRam
local R = emu.memType.snesPrgRom
local POOL = 0x8006

local function wram(a) return emu.read(a, W) end
local function poke(a, v) emu.write(a, v, W) end
local function rom(a) return emu.read(a, R) end
local function dsp(r) return emu.read(r, emu.memType.spcDspRegisters) end
local function s8(v) return v >= 128 and v - 256 or v end

local function check(cond, msg)
  if cond then print("PASS " .. msg)
  else print("FAIL " .. msg); fails = fails + 1 end
end

local function entry(i)
  local e = POOL + 16 + i * 16
  return {
    blocks = rom(e + 10) + rom(e + 11) * 256,
    semis = s8(rom(e + 14)), fine = s8(rom(e + 15)),
  }
end

local function raw_pitch(note)
  note = math.max(0, math.min(95, note))
  local semi, octave = note % 12, math.floor(note / 12)
  local top = math.floor(0x4000 * 2 ^ (semi / 12) + 0.5)
  return math.floor(top / 2 ^ (7 - octave))
end

local function tuned_pitch(note, sample)
  local e = entry(sample)
  local n = math.max(0, math.min(95, note + e.semis))
  local frac = e.fine
  if frac < 0 then
    if n == 0 then frac = 0 else n = n - 1; frac = frac + 256 end
  end
  local base = raw_pitch(n)
  if frac == 0 or n == 95 then return base end
  return base + math.floor((raw_pitch(n + 1) - base) * frac / 256)
end

local function factory_shape()
  local count, active = rom(POOL + 9), 0
  for i = 0, count - 1 do if entry(i).blocks > 1 then active = active + 1 end end
  check(count == 48, "factory exposes 48 editable pool slots")
  check(active == 8, "factory has 8 authored sounds (" .. active .. ")")

  local needed = {}
  for i = 0, 7 do
    local p, typ, sound = 0x2400 + i * 16, wram(0x2400 + i * 16) & 7,
      wram(0x2401 + i * 16)
    if typ == 0 or typ == 3 or typ == 4 then
      needed[sound] = true
    elseif typ == 1 then
      for slot = 0, 15 do
        local k = 0x3200 + sound * 64 + slot * 4
        if wram(k + 2) ~= 0 then needed[wram(k)] = true end
      end
    end
  end
  local ok, n = true, 0
  for sample in pairs(needed) do
    n = n + 1
    if sample >= count or wram(0x97 + sample) == 0 then ok = false end
  end
  check(ok and n > 0, "all " .. n .. " boot-referenced sounds are resident")

  local bytes = 0
  for sample = 0, count - 1 do
    if wram(0x97 + sample) ~= 0 then bytes = bytes + entry(sample).blocks * 9 end
  end
  local max_edl = math.min(15, math.floor((0x10000 - (0x1209 + bytes)) / 2048))
  check(max_edl == 15, "lean residency leaves maximum EDL 15 (240 ms)")
end

local script = {
  [14] = { start = true }, [16] = {},       -- splash -> SONG
  [30] = { start = true }, [32] = {},       -- play the authored row
}

emu.addEventCallback(function() emu.setInput(pad, 0) end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if not booted then
    if wram(1) == 0x5D then booted = true end
    return
  end
  frames = frames + 1
  if script[frames] then pad = script[frames] end
  if frames > 32 then peak = math.max(peak, dsp(0x08)) end

  if frames == 22 then
    factory_shape()
    -- A minimal song using factory sample 0 with its real storage tuning.
    poke(0x2000, 0); poke(0x3700, 0)
    poke(0x2400, 0); poke(0x2401, 0); poke(0x2406, 0)
    poke(0x4300, 49); poke(0x4301, 0)
  elseif frames == 52 then
    local p = dsp(0x02) + dsp(0x03) * 256
    local expected = tuned_pitch(48, 0)
    local e = entry(0)
    check(e.semis ~= 0 or e.fine ~= 0,
      "factory sample 0 carries lean storage tuning (" .. e.semis .. ":" .. e.fine .. ")")
    check(p == expected, string.format(
      "real pool tuning reached DSP exactly ($%04X)", p))
    check(dsp(0x04) == wram(0x97), "factory sample 0 uses its resident SRCN")
    check(peak > 0, "factory sample is audible (ENVX peak " .. peak .. ")")
    if fails == 0 then print("ALL PASS factory.lua"); emu.stop(0)
    else print("FAILED factory.lua: " .. fails); emu.stop(1) end
  end
end, emu.eventType.endFrame)
