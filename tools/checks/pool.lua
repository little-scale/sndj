-- pool.lua — pool v2 + residency gate: the banked ROM pool parses, only
-- referenced samples upload (factory song: 5 SMP instruments + the 808
-- kit), the directory points at intact BRR data, and LSDJ-style kits
-- trigger the right sample/tune/vol from the note's slot.

local frames = 0
local _booted = false
local fails = 0
local pad = {}
local W = emu.memType.snesWorkRam
local R = emu.memType.snesPrgRom

local function wram(a) return emu.read(a, W) end
local function poke(a, v) emu.write(a, v, W) end
local function dsp(r) return emu.read(r, emu.memType.spcDspRegisters) end
local function aram(a) return emu.read(a, emu.memType.spcRam) end
local function rom(a) return emu.read(a, R) end

local function check(cond, msg)
  if cond then
    print("PASS " .. msg)
  else
    print("FAIL " .. msg)
    fails = fails + 1
  end
end

-- pool starts at PRG offset $8006 (bank 1, after the SNPOOL marker)
local POOL = 0x8006
local function pool_entry(i)
  local e = POOL + 16 + i * 16
  return {
    off = (rom(e + 8) + rom(e + 9) * 256) * 9,
    blocks = rom(e + 10) + rom(e + 11) * 256,
    loop = rom(e + 12) + rom(e + 13) * 256,
  }
end

emu.addEventCallback(function() emu.setInput(pad, 0) end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if not _booted then
    if emu.read(1, W) == 0x5D then _booted = true end
    return
  end
  frames = frames + 1

  if frames == 14 then pad = { start = true } end
  if frames == 17 then pad = {} end

  if frames == 40 then
    check(rom(POOL) == string.byte("S") and rom(POOL + 8) == 2,
      "pool v2 magic in ROM bank 1")
    local count = rom(POOL + 9)
    check(count == 45, "factory pool has 45 samples (" .. count .. ")")
    check(aram(0x1000) == 0x00 and aram(0x1001) == 0x12,
      "directory slot 0 -> silent stub")
    check(aram(0x1200) == 0x01, "silent stub BRR (END block) uploaded")
    -- auto-populated instruments reference every pool sample, so the
    -- resident set is samples 0..39 in pool order until the echo-aware
    -- ceiling; over-budget samples map to the silent stub
    local cursor = 0x1200 + 9
    local all_ok = true
    local slot = 1
    srcn_of = {}
    for s = 0, count - 1 do
      local e = pool_entry(s)
      local endcur = cursor + e.blocks * 9
      if slot < 56 and math.floor(endcur / 256) < 0xFF then
        local dstart = aram(0x1000 + slot * 4) + aram(0x1001 + slot * 4) * 256
        if dstart ~= cursor then
          all_ok = false
          print(string.format("  slot %d: dir %04X != cursor %04X",
            slot, dstart, cursor))
          break
        end
        for k = 0, 8 do
          if aram(cursor + k) ~= rom(POOL + e.off + k) then
            all_ok = false
            print(string.format("  slot %d: byte %d mismatch", slot, k))
            break
          end
        end
        srcn_of[s] = slot
        cursor = endcur
        slot = slot + 1
      end
    end
    check(all_ok, "residency: referenced samples uploaded in order (" ..
      (slot - 1) .. " resident)")
    check(srcn_of[8] ~= nil and srcn_of[13] ~= nil,
      "the 808 kit samples made the budget")
    check(wram(0x3240) == 24 and wram(0x3241) == 0xF4 and wram(0x3242) == 0x50,
      "kit 1 slot 0 = MP KICK (pool 24, tune -12)")
    check(wram(0x326C) == 35, "kit 1 slot 11 = MP UNDO")
    check(wram(0x3272) == 0, "kit 1 slots 12-15 empty")
    check(wram(0x3280) == 36 and wram(0x3282) == 0x50,
      "kit 2 slot 0 = SW KICK (pool 36)")
    check(wram(0x32A0) == 44, "kit 2 slot 8 = SW BEEP")
    check(wram(0x32A6) == 0, "kit 2 slots 9-15 empty")
    check(wram(0x27A0) == 1 and wram(0x27A1) == 2, "instrument 58 is KIT 2")
    -- author a kit test: instrument 7 is factory KIT 0 (the 808)
    poke(0x2000, 0)          -- grid V1r0 = chain 0
    poke(0x3700, 0)          -- chain0 e0 = phrase 0
    poke(0x4300, 49)         -- C-4 -> slot 0 (808 BD)
    poke(0x4301, 7)          -- instrument 7 = KIT
    poke(0x4310, 54)         -- F-4 -> slot 5 (808 MC)
    poke(0x4311, 0xFF)
    poke(0x3200 + 5 * 4 + 1, 12)   -- kit0 slot5 tune = +12 (SB_KITS = $3200)
  elseif frames == 44 then
    pad = { start = true }
  elseif frames == 46 then
    pad = {}
  elseif frames == 54 then
    check(wram(0x16) == 1, "playing")
    -- C-4 -> kit slot 0 -> 808 BD (pool 8)
    check(dsp(0x04) == srcn_of[8], "kit slot 0 routed to the 808 BD (SRCN " ..
      tostring(srcn_of[8]) .. ")")
    check(dsp(0x02) + dsp(0x03) * 256 == 0x0800,
      "16 kHz factory drum tuned -12 ($0800)")
    check(dsp(0x00) == 0x50 and dsp(0x01) == 0x50, "kit slot volume applied")
    check(dsp(0x08) > 0, "kick envelope alive")
  elseif frames == 80 then
    -- row 4: F-4 -> slot 5 (808 MC, pool 13), tuned +12
    check(dsp(0x04) == srcn_of[13], "kit slot 5 routed to the 808 MC (SRCN " ..
      tostring(srcn_of[13]) .. ")")
    check(dsp(0x02) + dsp(0x03) * 256 == 0x2000,
      "per-slot tune +12 doubled the pitch")
    if fails == 0 then
      print("ALL PASS pool.lua")
      emu.stop(0)
    else
      print("FAILED pool.lua: " .. fails)
      emu.stop(1)
    end
  end
end, emu.eventType.endFrame)
