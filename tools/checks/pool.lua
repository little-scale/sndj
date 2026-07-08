-- pool.lua — M11 gate: the ROM pool uploads to ARAM with an intact
-- directory (every entry's start/loop point at real BRR data that matches
-- the ROM bytes), and KIT instruments map notes to pool samples.

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

-- locate the pool in PRG ROM by its SNPOOL marker + SNDJPOOL magic
local function find_pool()
  local sig = { 0x53, 0x4E, 0x50, 0x4F, 0x4F, 0x4C,          -- "SNPOOL"
                0x53, 0x4E, 0x44, 0x4A, 0x50, 0x4F, 0x4F, 0x4C } -- "SNDJPOOL"
  for base = 0, 0x43000, 0x8000 do
    local hit = true
    for i, b in ipairs(sig) do
      if rom(base + i - 1) ~= b then hit = false break end
    end
    if hit then return base + 6 end
  end
  return nil
end

emu.addEventCallback(function() emu.setInput(pad, 0) end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if not _booted then
    if emu.read(1, emu.memType.snesWorkRam) == 0x5D then _booted = true end
    return
  end
  frames = frames + 1

  if frames == 40 then pad = { start = true } end
  if frames == 43 then pad = {} end

  if frames == 70 then
    local pool = find_pool()
    check(pool ~= nil, "SNPOOL marker + magic found in ROM")
    if not pool then
      print("FAILED pool.lua: no pool")
      emu.stop(1)
      return
    end
    local count = rom(pool + 9)
    check(count == 6, "factory pool has 6 samples (" .. count .. ")")
    -- walk the directory: entries at ARAM $1000, samples from $1200
    local cursor = 0x1200
    local all_ok = true
    for i = 0, count - 1 do
      local e = pool + 16 + i * 16
      -- entry fields: +8 offset, +10 size, +12 loop block
      local offset = rom(e + 8) + rom(e + 9) * 256
      local bytes = rom(e + 10) + rom(e + 11) * 256
      local dstart = aram(0x1000 + i * 4) + aram(0x1001 + i * 4) * 256
      if dstart ~= cursor then
        all_ok = false
        print(string.format("  entry %d: dir start %04X != cursor %04X",
          i, dstart, cursor))
      end
      -- first 9 BRR bytes match the ROM pool data
      for k = 0, 8 do
        if aram(cursor + k) ~= rom(pool + offset + k) then
          all_ok = false
          print(string.format("  entry %d: ARAM byte %d mismatch", i, k))
          break
        end
      end
      -- last block carries END; loop flag only for looped entries
      local lasthdr = aram(cursor + bytes - 9)
      local loopblk = rom(e + 12) + rom(e + 13) * 256
      if lasthdr % 2 ~= 1 then
        all_ok = false
        print(string.format("  entry %d: last header %02X lacks END", i, lasthdr))
      end
      if loopblk ~= 0xFFFF then
        local dloop = aram(0x1002 + i * 4) + aram(0x1003 + i * 4) * 256
        if dloop ~= cursor + loopblk * 9 then
          all_ok = false
          print(string.format("  entry %d: loop %04X wrong", i, dloop))
        end
      end
      cursor = cursor + bytes
    end
    check(all_ok, "directory integrity: all entries point at their BRR data")
    check(cursor < 0xD000, "pool fits under the echo region (top at $" ..
      string.format("%04X", cursor) .. ")")
    -- author a KIT test: instrument 1 = KIT; notes pick pool slots
    poke(0x2000, 0)
    poke(0x3700, 0)
    poke(0x2410, 1)          -- type KIT
    poke(0x2412, 0x2F)
    poke(0x2413, 0xCA)
    poke(0x2414, 0x50)
    poke(0x2415, 0x50)
    poke(0x4300, 49)         -- C-4 -> idx 48 -> slot 0 (PAD)
    poke(0x4301, 1)
    poke(0x4310, 52)         -- D#4 -> idx 51 -> slot 3 (KICK)
    poke(0x4311, 0xFF)
  elseif frames == 80 then
    pad = { start = true }
  elseif frames == 82 then
    pad = {}
  elseif frames == 90 then
    check(dsp(0x04) == 0, "KIT: C-4 plays pool slot 0")
    check(dsp(0x02) + dsp(0x03) * 256 == 0x1000, "KIT plays at native rate")
  elseif frames == 110 then
    check(dsp(0x08) > 0, "kit voice envelope alive right after the kick")
  elseif frames == 116 then
    check(dsp(0x04) == 3, "KIT: D#4 plays pool slot 3 (KICK)")
    if fails == 0 then
      print("ALL PASS pool.lua")
      emu.stop(0)
    else
      print("FAILED pool.lua: " .. fails)
      emu.stop(1)
    end
  end
end, emu.eventType.endFrame)
