-- pool.lua — pool v2 + residency gate, independent of factory content.
-- Every boot-referenced sample must be mapped, directory data must match ROM,
-- loop ownership must be reflected in the directory, and a KIT trigger must
-- route through a resident pool sample.

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
local function aram(a) return emu.read(a, emu.memType.spcRam) end

local function check(cond, msg)
  if cond then print("PASS " .. msg)
  else print("FAIL " .. msg); fails = fails + 1 end
end

local function entry(i)
  local e = POOL + 16 + i * 16
  return {
    off = (rom(e + 8) + rom(e + 9) * 256) * 9,
    blocks = rom(e + 10) + rom(e + 11) * 256,
    loop = rom(e + 12) + rom(e + 13) * 256,
  }
end

local function dirw(slot, word)
  return aram(0x1000 + slot * 4 + word) +
    aram(0x1001 + slot * 4 + word) * 256
end

local function boot_references()
  local needed = {}
  for i = 0, 7 do
    local p = 0x2400 + i * 16
    local typ, sound = wram(p) & 7, wram(p + 1)
    if typ == 0 or typ == 3 or typ == 4 then
      needed[sound] = true
    elseif typ == 1 then
      for slot = 0, 15 do
        local k = 0x3200 + sound * 64 + slot * 4
        if wram(k + 2) ~= 0 then needed[wram(k)] = true end
      end
    end
  end
  return needed
end

local script = {
  [14] = { start = true }, [16] = {},
  [44] = { start = true }, [46] = {},
}

emu.addEventCallback(function() emu.setInput(pad, 0) end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if not booted then
    if wram(1) == 0x5D then booted = true end
    return
  end
  frames = frames + 1
  if script[frames] then pad = script[frames] end
  if frames > 46 then peak = math.max(peak, dsp(0x08)) end

  if frames == 38 then
    local count = rom(POOL + 9)
    check(rom(POOL) == string.byte("S") and rom(POOL + 8) == 2,
      "pool v2 magic in ROM bank 1")
    check(count > 0 and count <= 56, "pool count is within the 56-slot limit (" .. count .. ")")
    check(aram(0x1000) == 0x00 and aram(0x1001) == 0x12 and aram(0x1200) == 0x01,
      "silent directory slot and END block are installed")

    local needed, mapped, data_ok = boot_references(), 0, true
    for sample in pairs(needed) do
      local srcn = sample < count and wram(0x97 + sample) or 0
      if srcn == 0 then data_ok = false
      else
        mapped = mapped + 1
        local e, start = entry(sample), dirw(srcn, 0)
        for k = 0, 8 do
          local want = rom(POOL + e.off + k)
          if e.blocks == 1 and k == 0 then want = want | 2 end
          if aram(start + k) ~= want then data_ok = false end
        end
        local want_loop = e.loop == 0xFFFF and 0x1200 or start + e.loop * 9
        if dirw(srcn, 2) ~= want_loop then data_ok = false end
      end
    end
    check(data_ok and mapped > 0,
      "all " .. mapped .. " boot-referenced samples map to intact BRR + loop directories")

    -- Author a content-neutral kit using sample 0, which is boot resident.
    poke(0x2470, 1); poke(0x2471, 0); poke(0x2476, 0)
    poke(0x3200, 0); poke(0x3201, 0); poke(0x3202, 0x50); poke(0x3203, 0)
    poke(0x2000, 0); poke(0x3700, 0)
    poke(0x4300, 49); poke(0x4301, 7)
  elseif frames == 62 then
    local srcn = wram(0x97)
    local pitch = dsp(0x02) + dsp(0x03) * 256
    check(srcn > 0 and dsp(0x04) == srcn,
      "KIT slot routed through resident pool sample 0 (SRCN " .. srcn .. ")")
    check(pitch == 0x1000, string.format("neutral KIT slot plays native pitch ($%04X)", pitch))
    check(dsp(0x00) == 0x50 and dsp(0x01) == 0x50, "KIT slot volume applied")
    check(peak > 0, "KIT trigger is audible (ENVX peak " .. peak .. ")")
    check(wram(0x27A0) == 0 and wram(0x27A1) == 0,
      "instrument 58 defaults to SMP sample 0")
    if fails == 0 then print("ALL PASS pool.lua"); emu.stop(0)
    else print("FAILED pool.lua: " .. fails); emu.stop(1) end
  end
end, emu.eventType.endFrame)
