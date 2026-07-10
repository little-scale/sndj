-- namesave.lua — name-keyed SAVE (genmddj dir_save parity) and the rename
-- machinery around it. Regression for the "song name reverted to SONG" bug:
-- SAVE stores the working song under its header name (overwriting the
-- same-named file or appending a new one — the cursor slot plays no part),
-- renaming a saved file forks it, and LOAD copies the file's name back
-- into the song header.

local frames = 0
local _booted = false
local fails = 0
local pad = {}
local W = emu.memType.snesWorkRam
local S = emu.memType.snesSaveRam

local function check(cond, msg)
  if cond then
    print("PASS " .. msg)
  else
    print("FAIL " .. msg)
    fails = fails + 1
  end
end

local function name8(mem, base)
  local s = ""
  for i = 0, 7 do s = s .. string.char(emu.read(base + i, mem)) end
  return s
end
local function header() return name8(W, 0x3609) end          -- SB_HEADER + SH_NAME
local function slotname(n) return name8(S, 0x10 + n * 16 + 8) end
local function slotstat(n) return emu.read(0x10 + n * 16, S) end

-- gesture helper: A+B opens the menu, n downs pick the item,
-- B arms (SURE?), a second B confirms and runs
local script = {}
local function at(f, p) script[f] = p end
local function menu_run(f, downs)
  at(f, { a = true }); at(f + 2, { a = true, b = true }); at(f + 4, {})
  local x = f + 8
  for _ = 1, downs do
    at(x, { down = true }); at(x + 2, {})
    x = x + 4
  end
  at(x, { b = true }); at(x + 2, {})           -- arm: SURE?
  at(x + 4, { b = true }); at(x + 6, {})       -- confirm: run and close
  return x + 8
end

-- NOTE: a save/load occupies the main loop for dozens of frames (planar
-- stage + RLE pack); gestures during it are eaten. Leave >=120 frames
-- after every confirm, like files.lua does.
at(14, { start = true }); at(16, {})
at(24, { a = true }); at(26, { a = true, down = true }); at(28, {})  -- FILES
-- rename the working song ((EMPTY) row): B-hold + Up, S -> T
at(40, { b = true }); at(42, { b = true, up = true })
at(44, { b = true }); at(46, {})
menu_run(60, 0)                       -- SAVE -> file "TONG"
-- rename the FILE (cursor sits on the saved slot 0): T -> U
at(190, { b = true }); at(192, { b = true, up = true })
at(194, { b = true }); at(196, {})
menu_run(210, 0)                      -- SAVE again: appends a new "TONG"
at(344, { up = true }); at(346, {})   -- ensure cursor on slot 0 (clamped)
menu_run(350, 1)                      -- LOAD the renamed "UONG" file
-- leave FILES and come back: everything must persist
at(490, { a = true }); at(492, { a = true, up = true }); at(494, {})
at(500, { a = true }); at(502, { a = true, down = true }); at(504, {})

emu.addEventCallback(function() emu.setInput(pad, 0) end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if not _booted then
    if emu.read(1, W) == 0x5D then _booted = true end
    return
  end
  frames = frames + 1
  if frames == 20 then
    -- empty packed directory (entries incl. names: prior runs leave
    -- saves — and stale name bytes — in the shared .srm)
    for i = 0, 255 do emu.write(0x10 + i, 0xFF, S) end
  end
  if script[frames] then pad = script[frames] end

  if frames == 54 then
    check(header() == "TONG    ",
      "B+Up on the (EMPTY) row renamed the working song (" .. header() .. ")")
  elseif frames == 184 then
    check(slotstat(0) == 0xA5, "SAVE created file 0")
    check(slotname(0) == "TONG    ",
      "the file carries the song's name (" .. slotname(0) .. ")")
  elseif frames == 204 then
    check(slotname(0) == "UONG    ",
      "B+Up on the saved slot renamed the file (" .. slotname(0) .. ")")
    check(header() == "TONG    ",
      "...and left the working song's name alone (" .. header() .. ")")
  elseif frames == 340 then
    check(slotstat(1) == 0xA5, "re-save appended a second file")
    check(slotname(1) == "TONG    ",
      "the new file took the song's name (" .. slotname(1) .. ")")
    check(slotname(0) == "UONG    ",
      "the renamed file survived the save (" .. slotname(0) .. ")")
  elseif frames == 480 then
    check(header() == "UONG    ",
      "LOAD copied the file's name into the header (" .. header() .. ")")
  elseif frames == 520 then
    check(header() == "UONG    " and slotname(0) == "UONG    "
      and slotname(1) == "TONG    ",
      "names survive leaving and re-entering FILES (" .. header() ..
      "/" .. slotname(0) .. "/" .. slotname(1) .. ")")
    if fails == 0 then
      print("ALL PASS namesave.lua")
      emu.stop(0)
    else
      print("FAILED namesave.lua: " .. fails)
      emu.stop(1)
    end
  end
end, emu.eventType.endFrame)
