-- palette.lua — palette schemes: OPTIONS reachable with A+Up from SONG,
-- B-hold + Right cycles to scheme 1 (WHT: black text on white bg $7FFF),
-- the choice lands in CGRAM via the NMI drain, persists in SRAM $0007,
-- and survives a reset. Scheme 0 (boot default) is BLK.
--
-- WRAM: ui_mode $0C, opt_pal $1D4, pal_buf $1D6 (colour n at +n*2).

local frames = 0
local _booted = false
local fails = 0
local pad = {}

local function wram(addr) return emu.read(addr, emu.memType.snesWorkRam) end
local function sram(addr) return emu.read(addr, emu.memType.snesSaveRam) end
local function palbuf(n)
  return wram(0x1D6 + n * 2) + wram(0x1D7 + n * 2) * 256
end
local function cgram(n)
  return emu.read(n * 2, emu.memType.snesCgRam)
       + emu.read(n * 2 + 1, emu.memType.snesCgRam) * 256
end

local function check(cond, msg)
  if cond then
    print("PASS " .. msg)
  else
    print("FAIL " .. msg)
    fails = fails + 1
  end
end

local stage = "prep"

emu.addEventCallback(function() emu.setInput(pad, 0) end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if not _booted then
    if emu.read(1, emu.memType.snesWorkRam) == 0x5D then _booted = true end
    return
  end
  frames = frames + 1

  if stage == "prep" and frames == 10 then
    -- the emulator persists .sav across runs: pin the scheme byte to 0
    -- and reboot so the test always starts from scheme 0
    emu.write(0x0007, 0, emu.memType.snesSaveRam)
    emu.reset()
    _booted = false
    frames = 0
    stage = "boot"
  elseif stage == "boot" and frames == 20 then
    check(wram(0x1D4) == 0, "boots on scheme 0")
    pad = { start = true }
    stage = "song"
  elseif stage == "song" and frames == 23 then
    pad = {}
    stage = "nav"
  elseif stage == "nav" and frames == 28 then
    pad = { a = true }
  elseif stage == "nav" and frames == 30 then
    pad = { a = true, up = true }
  elseif stage == "nav" and frames == 32 then
    pad = {}
    stage = "on_options"
  elseif stage == "on_options" and frames == 38 then
    check(wram(0x0C) == 10, "A+Up opened OPTIONS from SONG")
    pad = { b = true }
    stage = "cycle"
  elseif stage == "cycle" and frames == 40 then
    pad = { b = true, right = true }
  elseif stage == "cycle" and frames == 42 then
    pad = { b = true }
  elseif stage == "cycle" and frames == 44 then
    pad = {}
    stage = "applied"
  elseif stage == "applied" and frames == 52 then
    check(wram(0x1D4) == 1, "B+Right selected scheme 1 (WHT)")
    check(palbuf(0) == 0x7FFF and palbuf(2) == 0x0000,
      "pal_buf holds white bg / black text")
    local strict = true
    for i = 0, 15 do
      local c = palbuf(i)
      if c ~= 0x7FFF and c ~= 0x0000 then strict = false end
    end
    check(strict, "all UI palette entries use only background or text")
    check(palbuf(14) == 0x0000 and palbuf(15) == 0x0000,
      "DIM renders at full text contrast")
    check(cgram(1) == 0x7FFF, "NMI drained the scheme into CGRAM (negative ink = bg)")
    check(cgram(17) == 0x7FFF and cgram(19) == 0x0000,
      "playheads use the same two-colour negative as cursors")
    check(sram(0x0007) == 1, "scheme persisted in SRAM $0007")
    emu.reset()
    _booted = false
    stage = "reboot"
    frames = 0
  elseif stage == "reboot" and frames == 30 then
    check(wram(0x1D4) == 1, "scheme 1 restored from SRAM after reset")
    check(cgram(1) == 0x7FFF, "CGRAM rebuilt from the persisted scheme")
    if fails == 0 then
      print("ALL PASS palette.lua")
      emu.stop(0)
    else
      print("FAILED palette.lua: " .. fails)
      emu.stop(1)
    end
  end
end, emu.eventType.endFrame)
