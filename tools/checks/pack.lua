-- pack.lua — SNDJ1 v2 variable packing: saves append to the heap,
-- overwrites and clears close their holes, the directory stays packed,
-- and every surviving song's CRC still verifies afterwards.
--
-- After each operation the checker rebuilds the invariant from SRAM:
-- entries 0..used-1 valid, offsets contiguous ascending, and each
-- block's CRC-16/CCITT matches its entry.

local frames = 0
local _booted = false
local fails = 0
local pad = {}

local function wram(addr) return emu.read(addr, emu.memType.snesWorkRam) end
local function poke(a, v) emu.write(a, v, emu.memType.snesWorkRam) end
local function sram(addr) return emu.read(addr, emu.memType.snesSaveRam) end

local function check(cond, msg)
  if cond then
    print("PASS " .. msg)
  else
    print("FAIL " .. msg)
    fails = fails + 1
  end
end

local function crc16(bytes)
  local crc = 0xFFFF
  for _, b in ipairs(bytes) do
    crc = crc ~ (b << 8)
    for _ = 1, 8 do
      if (crc & 0x8000) ~= 0 then
        crc = ((crc << 1) ~ 0x1021) & 0xFFFF
      else
        crc = (crc << 1) & 0xFFFF
      end
    end
  end
  return crc
end

-- the whole-format invariant: packed directory, DENSE heap (no holes;
-- heap order may differ from entry order after overwrites), CRCs
local function verify(tag)
  local seen_free = false
  local ok = true
  local blocks = {}
  for s = 0, 15 do
    local e = 0x10 + s * 16
    if sram(e) == 0xA5 then
      if seen_free then
        ok = false
        print("  entry " .. s .. " valid after a free one (unpacked dir)")
        break
      end
      local off = sram(e + 1) + sram(e + 2) * 256
      local size = sram(e + 3) + sram(e + 4) * 256
      local crc = sram(e + 5) + sram(e + 6) * 256
      local data = {}
      for i = 0, size - 1 do data[#data + 1] = sram(0x110 + off + i) end
      if crc16(data) ~= crc then
        ok = false
        print("  entry " .. s .. " CRC mismatch")
        break
      end
      blocks[#blocks + 1] = { off = off, size = size }
    else
      seen_free = true
    end
  end
  if ok then
    table.sort(blocks, function(a, b) return a.off < b.off end)
    local expected = 0
    for _, b in ipairs(blocks) do
      if b.off ~= expected then
        ok = false
        print(string.format("  hole: block at %04X, expected %04X", b.off, expected))
        break
      end
      expected = expected + b.size
    end
  end
  check(ok, tag)
end

-- menu helper: A+B opens, n downs, B arms (SURE?), a second B runs
local script = {}
local function menu_run(f, downs)
  script[f] = { a = true }
  script[f + 2] = { a = true, b = true }
  script[f + 4] = {}
  local x = f + 8
  for _ = 1, downs do
    script[x] = { down = true }
    script[x + 2] = {}
    x = x + 4
  end
  script[x] = { b = true }
  script[x + 2] = {}
  script[x + 4] = { b = true }
  script[x + 6] = {}
  return x + 8
end

script[14] = { start = true }
script[16] = {}
script[24] = { a = true }
script[26] = { a = true, down = true }
script[28] = {}                       -- FILES
menu_run(40, 0)                       -- SAVE -> slot 0 ("SONG", small)
script[200] = { down = true }         -- to the (EMPTY) row
script[202] = {}
-- SAVE is name-keyed: rename the working song S -> T so the save appends
script[206] = { b = true }
script[208] = { b = true, up = true }
script[210] = { b = true }
script[212] = {}
menu_run(220, 0)                      -- SAVE -> slot 1 ("TONG", bigger song)
script[370] = { down = true }         -- to the new (EMPTY) row
script[372] = {}
script[376] = { b = true }            -- rename back T -> S
script[378] = { b = true, down = true }
script[380] = { b = true }
script[382] = {}
menu_run(390, 0)                      -- SAVE over the "SONG" file (now bigger: hole)
script[544] = { up = true }
script[546] = {}
script[548] = { up = true }
script[550] = {}
menu_run(560, 2)                      -- CLEAR slot 0 (slides slot 1 down)

emu.addEventCallback(function() emu.setInput(pad, 0) end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if not _booted then
    if emu.read(1, emu.memType.snesWorkRam) == 0x5D then _booted = true end
    return
  end
  frames = frames + 1
  if script[frames] then pad = script[frames] end

  if frames == 18 then
    for s = 0, 15 do emu.write(0x10 + s * 16, 0xFF, emu.memType.snesSaveRam) end
    poke(0x3700, 0)
    poke(0x4300, 49)          -- a small song
  elseif frames == 190 then
    verify("save 0: packed + CRC clean")
    -- densify the song so the next saves are bigger
    for r = 0, 15 do
      poke(0x4340 + r * 4, 40 + r)
      poke(0x4342 + r * 4, (r % 26) + 1)
      poke(0x4343 + r * 4, r * 17)
    end
    poke(0x3702, 1)
  elseif frames == 360 then
    verify("save 1 appended: packed + CRC clean")
  elseif frames == 540 then
    verify("overwrite of slot 0 closed its hole")
    check(sram(0x10) == 0xA5 and sram(0x20) == 0xA5, "both songs live")
  elseif frames == 700 then
    verify("clear + slide kept the survivor intact")
    check(sram(0x10) == 0xA5 and sram(0x20) == 0xFF,
      "directory packed down to one entry")
    if fails == 0 then
      print("ALL PASS pack.lua")
      emu.stop(0)
    else
      print("FAILED pack.lua: " .. fails)
      emu.stop(1)
    end
  end
end, emu.eventType.endFrame)
