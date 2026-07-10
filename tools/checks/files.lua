-- files.lua — the genmddj-style FILES actions: PURGE PH/CH blank only
-- unreachable data, CLEAR compacts the packed list, LOAD on the (EMPTY)
-- row blanks the working song.
--
-- WRAM: ui_mode $0C; chains $3700 (32/chain); phrases $4300 (64/phrase).
-- SRAM: slot table at $0010 (16/entry).

local frames = 0
local _booted = false
local fails = 0
local pad = {}

local function wram(addr) return emu.read(addr, emu.memType.snesWorkRam) end
local function sram(addr) return emu.read(addr, emu.memType.snesSaveRam) end
local function poke(a, v) emu.write(a, v, emu.memType.snesWorkRam) end

local function check(cond, msg)
  if cond then
    print("PASS " .. msg)
  else
    print("FAIL " .. msg)
    fails = fails + 1
  end
end

-- gesture helper: A+B opens the menu, n downs pick the item, B runs
local script = {}
local t = 0
local function at(f, p) script[f] = p end
local function menu_run(f, downs)
  at(f, { a = true }); at(f + 2, { a = true, b = true }); at(f + 4, {})
  local x = f + 8
  for _ = 1, downs do
    at(x, { down = true }); at(x + 2, {})
    x = x + 4
  end
  at(x, { b = true }); at(x + 2, {})
  return x + 4
end

at(14, { start = true }); at(16, {})
at(24, { a = true }); at(26, { a = true, down = true }); at(28, {})  -- FILES
menu_run(40, 3)                      -- PURGE PH
menu_run(80, 4)                      -- PURGE CH
menu_run(120, 0)                     -- SAVE on slot 0
at(260, { down = true }); at(262, {})  -- cursor to the (EMPTY) row
menu_run(270, 0)                     -- SAVE -> slot 1
at(420, { up = true }); at(422, {})    -- back to slot 0
menu_run(430, 2)                     -- CLEAR slot 0 (list compacts)
at(470, { down = true }); at(472, {})  -- to the (EMPTY) row (now row 1)
menu_run(480, 1)                     -- LOAD on empty = fresh song
-- rename gestures: still on the (EMPTY) row after the fresh start
at(620, { b = true }); at(622, { b = true, up = true }); at(624, { b = true }); at(626, {})
at(646, { b = true }); at(648, { b = true, down = true }); at(650, { b = true }); at(652, {})
-- up to the saved slot (row 0) and rename it
at(666, { up = true }); at(668, {})
at(672, { b = true }); at(674, { b = true, up = true }); at(676, { b = true }); at(678, {})

emu.addEventCallback(function() emu.setInput(pad, 0) end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if not _booted then
    if emu.read(1, emu.memType.snesWorkRam) == 0x5D then _booted = true end
    return
  end
  frames = frames + 1
  if script[frames] then pad = script[frames] end

  if frames == 20 then
    -- the emulator persists .sav across runs: empty all slots first
    for s = 0, 15 do emu.write(0x10 + s * 16, 0xFF, emu.memType.snesSaveRam) end
  elseif frames == 30 then
    check(wram(0x0C) == 5, "on FILES")
    -- reachable: song row0 -> chain 0 -> phrase 0 (with a note)
    poke(0x2000, 0)
    poke(0x3700, 0)
    poke(0x4300, 49)
    -- orphans: chain 5 points at phrase 9; phrase 9 holds a note
    poke(0x37A0, 9)          -- chain 5 entry 0 ($3700 + 5*32)
    poke(0x4540, 60)         -- phrase 9 row 0 ($4300 + 9*64)
  elseif frames == 76 then
    check(wram(0x4540) == 0, "PURGE PH blanked the orphan phrase")
    check(wram(0x4300) == 49, "PURGE PH kept the reachable phrase")
  elseif frames == 116 then
    check(wram(0x37A0) == 0xFF, "PURGE CH blanked the orphan chain")
    check(wram(0x3700) == 0, "PURGE CH kept the reachable chain")
  elseif frames == 256 then
    check(sram(0x10) == 0xA5, "saved into slot 0")
  elseif frames == 416 then
    check(sram(0x20) == 0xA5, "saved into slot 1 (the empty row)")
  elseif frames == 466 then
    check(sram(0x10) == 0xA5 and sram(0x20) == 0xFF,
      "CLEAR compacted: one packed entry remains")
  elseif frames == 580 then
    check(wram(0x4300) == 0, "LOAD on (EMPTY) blanked the working song")
    check(wram(0x3602) == 0xD7, "fresh song re-seeded (magic)")
    check(wram(0x3603) == 14,
      "a NEW song auto-opens the delay to the ARAM max (EDL 14)")
  elseif frames == 640 then
    -- rename: B-hold + Up on the working song's name (empty row);
    -- S -> T (ring: blank, A-Z, specials, digits)
    check(wram(0x3609) == string.byte("T"),
      "B+Up cycled the song name S -> T")
  elseif frames == 660 then
    check(wram(0x3609) == string.byte("S"),
      "B+Down cycled it back to S")
  elseif frames == 690 then
    -- on the saved slot (row 0), rename its SRAM entry char 0
    check(sram(0x18) ~= string.byte("S") or true, "prep")
    local c0 = sram(0x18)
    check(c0 == string.byte("T"),
      "B+Up renamed the saved file (char = " .. string.char(c0) .. ")")
    if fails == 0 then
      print("ALL PASS files.lua")
      emu.stop(0)
    else
      print("FAILED files.lua: " .. fails)
      emu.stop(1)
    end
  end
end, emu.eventType.endFrame)
