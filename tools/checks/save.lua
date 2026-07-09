-- save.lua — M8 gate: save -> verify (Lua RLE mirror of the packed SRAM
-- bytes against a pre-save WRAM snapshot) -> corrupt -> load -> byte-
-- identical song block -> hardware reset -> load -> still identical.

local frames = 0
local _booted = false
local fails = 0
local pad = {}
local W = emu.memType.snesWorkRam
local S = emu.memType.snesSaveRam

local function wram(a) return emu.read(a, W) end
local function poke(a, v) emu.write(a, v, W) end
local function sram(a) return emu.read(a, S) end

local function check(cond, msg)
  if cond then
    print("PASS " .. msg)
  else
    print("FAIL " .. msg)
    fails = fails + 1
  end
end

local SB, SBEND = 0x2000, 0x7300
local snapshot = nil

local function snap()
  local t = {}
  for a = SB, SBEND - 1 do t[#t + 1] = wram(a) end
  return t
end

local function block_equal(t)
  for i, v in ipairs(t) do
    if wram(SB + i - 1) ~= v then return false, i - 1 end
  end
  return true
end

-- Lua mirror: unpack region bytes, un-planar (image v2: 4 phrase planes,
-- 2 chain planes, then the rest), compare to snapshot
local BLOCK, PH_OFF, PH_LEN = 0x5300, 0x2300, 0x3000
local CH_OFF, CH_LEN = 0x1700, 0x0C00
local function verify_packed(off, size, t)
  local base = 0x110 + off
  local img = {}
  local i = base
  while #img < BLOCK do
    local c = sram(i)
    i = i + 1
    if c < 0x80 then
      for k = 0, c do
        img[#img + 1] = sram(i + k)
      end
      i = i + c + 1
    else
      local b = sram(i)
      i = i + 1
      for _ = 1, c - 0x80 + 3 do img[#img + 1] = b end
    end
  end
  if i - base ~= size then
    return false, "stream length " .. (i - base) .. " != " .. size
  end
  local n = PH_LEN / 4
  for col = 0, 3 do
    for k = 0, n - 1 do
      local blk_off = PH_OFF + col + k * 4
      if img[col * n + k + 1] ~= t[blk_off + 1] then
        return false, "phrase byte " .. blk_off
      end
    end
  end
  local m = CH_LEN / 2
  for col = 0, 1 do
    for k = 0, m - 1 do
      local blk_off = CH_OFF + col + k * 2
      if img[PH_LEN + col * m + k + 1] ~= t[blk_off + 1] then
        return false, "chain byte " .. blk_off
      end
    end
  end
  for off = 0, CH_OFF - 1 do
    if img[PH_LEN + CH_LEN + off + 1] ~= t[off + 1] then
      return false, "byte " .. off
    end
  end
  return true
end

local stage = "boot"
local t0 = 0

emu.addEventCallback(function() emu.setInput(pad, 0) end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if not _booted then
    if emu.read(1, emu.memType.snesWorkRam) == 0x5D then _booted = true end
    return
  end
  frames = frames + 1

  if stage == "boot" and frames == 20 then
    pad = { start = true }
    stage = "to_song"
    t0 = frames + 2
  elseif stage == "to_song" and frames == t0 then
    pad = {}
    -- author a song directly (pad grammar covered elsewhere)
    poke(0x2000, 0)            -- V1 r0 = chain 0
    poke(0x3700, 0)            -- chain0 e0 = phrase 0
    poke(0x3701, 5)            -- transpose 5
    for r = 0, 15, 2 do
      poke(0x4300 + r * 4, 49 + r) -- notes
      poke(0x4300 + r * 4 + 1, 0)  -- instrument 0
      poke(0x4300 + r * 4 + 2, 22) -- V
      poke(0x4300 + r * 4 + 3, 0x48)
    end
    poke(0x2408, 2)            -- GRP 2
    poke(0x3000, 3)            -- groove tweak
    stage = "snapshot"
    t0 = frames + 4
  elseif stage == "snapshot" and frames == t0 then
    snapshot = snap()
    check(sram(0) == string.byte("S") and sram(4) == string.byte("1"),
      "SRAM formatted with SNDJ1 magic")
    pad = { a = true }
    stage = "nav1"
    t0 = frames + 2
  elseif stage == "nav1" and frames == t0 then
    pad = { a = true, down = true }
    stage = "nav2"
    t0 = frames + 2
  elseif stage == "nav2" and frames == t0 then
    pad = {}
    stage = "on_files"
    t0 = frames + 4
  elseif stage == "on_files" and frames == t0 then
    check(wram(0x0C) == 5, "A+Down opened FILES")
    pad = { a = true }         -- A+B opens the action menu
    stage = "menu_a"
    t0 = frames + 2
  elseif stage == "menu_a" and frames == t0 then
    pad = { a = true, b = true }
    stage = "menu_ab"
    t0 = frames + 2
  elseif stage == "menu_ab" and frames == t0 then
    pad = {}
    stage = "do_save"
    t0 = frames + 4
  elseif stage == "do_save" and frames == t0 then
    check(wram(0x1CE) == 1, "action menu open")
    pad = { b = true }         -- item 0 = SAVE
    stage = "saving"
    t0 = frames + 2
  elseif stage == "saving" and frames == t0 then
    pad = {}
    stage = "saved"
    t0 = frames + 90           -- packing blocks the main loop ~0.5 s
  elseif stage == "saved" and frames == t0 then
    check(sram(0x10) == 0xA5, "slot 0 table entry valid")
    local off = sram(0x11) + sram(0x12) * 256
    local size = sram(0x13) + sram(0x14) * 256
    check(off == 0, "first save packs at the heap start (off=" .. off .. ")")
    check(size > 0 and size < 0x7EF0, "packed size sane (" .. size .. ")")
    local ok, why = verify_packed(off, size, snapshot)
    check(ok, "Lua RLE mirror: packed bytes decode to the exact song block" ..
      (ok and "" or (" [" .. tostring(why) .. "]")))
    -- corrupt the live song
    for a = SB, SB + 0x200 do poke(a, 0x11) end
    poke(0x3000, 9)
    check(not block_equal(snapshot), "song block corrupted for the test")
    pad = { a = true }
    stage = "lmenu_a"
    t0 = frames + 2
  elseif stage == "lmenu_a" and frames == t0 then
    pad = { a = true, b = true }
    stage = "lmenu_ab"
    t0 = frames + 2
  elseif stage == "lmenu_ab" and frames == t0 then
    pad = {}
    stage = "lmenu_dn"
    t0 = frames + 4
  elseif stage == "lmenu_dn" and frames == t0 then
    pad = { down = true }      -- item 1 = LOAD
    stage = "lmenu_dn2"
    t0 = frames + 2
  elseif stage == "lmenu_dn2" and frames == t0 then
    pad = {}
    stage = "do_load"
    t0 = frames + 2
  elseif stage == "do_load" and frames == t0 then
    pad = { b = true }
    stage = "loading"
    t0 = frames + 4
  elseif stage == "loading" and frames == t0 then
    pad = {}
    stage = "loaded"
    t0 = frames + 60
  elseif stage == "loaded" and frames == t0 then
    local ok, at = block_equal(snapshot)
    check(ok, "load restored a byte-identical song block" ..
      (ok and "" or (" (first diff at $" .. string.format("%04X", at) .. ")")))
    emu.reset()
    _booted = false          -- re-arm the boot gate; frames pause until
    stage = "rebooting"      -- the reboot completes
    t0 = frames + 10
  elseif stage == "rebooting" and frames == t0 then
    pad = { start = true }
    stage = "reboot_song"
    t0 = frames + 2
  elseif stage == "reboot_song" and frames == t0 then
    pad = { a = true }
    stage = "reboot_nav"
    t0 = frames + 2
  elseif stage == "reboot_nav" and frames == t0 then
    pad = { a = true, down = true }
    stage = "reboot_nav2"
    t0 = frames + 2
  elseif stage == "reboot_nav2" and frames == t0 then
    pad = {}
    stage = "reboot_load"
    t0 = frames + 4
  elseif stage == "reboot_load" and frames == t0 then
    check(wram(0x0C) == 5, "FILES reachable after reset")
    check(sram(0x10) == 0xA5, "slot survived the reset")
    pad = { a = true }
    stage = "rmenu_a"
    t0 = frames + 2
  elseif stage == "rmenu_a" and frames == t0 then
    pad = { a = true, b = true }
    stage = "rmenu_ab"
    t0 = frames + 2
  elseif stage == "rmenu_ab" and frames == t0 then
    pad = {}
    stage = "rmenu_dn"
    t0 = frames + 4
  elseif stage == "rmenu_dn" and frames == t0 then
    pad = { down = true }      -- item 1 = LOAD
    stage = "rmenu_dn2"
    t0 = frames + 2
  elseif stage == "rmenu_dn2" and frames == t0 then
    pad = {}
    stage = "rmenu_b"
    t0 = frames + 2
  elseif stage == "rmenu_b" and frames == t0 then
    pad = { b = true }
    stage = "reboot_loading"
    t0 = frames + 4
  elseif stage == "reboot_loading" and frames == t0 then
    pad = {}
    stage = "final"
    t0 = frames + 60
  elseif stage == "final" and frames == t0 then
    local ok, at = block_equal(snapshot)
    check(ok, "save survived reset: song block byte-identical" ..
      (ok and "" or (" (first diff at $" .. string.format("%04X", at) .. ")")))
    if fails == 0 then
      print("ALL PASS save.lua")
      emu.stop(0)
    else
      print("FAILED save.lua: " .. fails)
      emu.stop(1)
    end
  end
end, emu.eventType.endFrame)
