-- nav.lua — the screen map: OPTIONS<->PROJECT and FILES<->GROOVE link
-- horizontally, HELP sits above TABLE (vertical only), KIT sits below
-- PHRASE between GROOVE and ECHO, and WAVE A+Right is bank select.
--
-- Map:  [O][P][ ][W][K]
--       [S][C][P][I][T]
--       [F][G][ ][E][F]

local frames = 0
local _booted = false
local fails = 0
local pad = {}

local function wram(addr) return emu.read(addr, emu.memType.snesWorkRam) end
local function poke(a, v) emu.write(a, v, emu.memType.snesWorkRam) end

local function check(cond, msg)
  if cond then
    print("PASS " .. msg)
  else
    print("FAIL " .. msg)
    fails = fails + 1
  end
end

local script = {}
local function gest(f, dir)
  script[f] = { a = true }
  script[f + 2] = { a = true, [dir] = true }
  script[f + 4] = {}
end
script[14] = { start = true }
script[16] = {}
gest(24, "up")        -- SONG -> OPTIONS
gest(32, "right")     -- OPTIONS -> PROJECT
gest(40, "left")      -- PROJECT -> OPTIONS
gest(48, "down")      -- OPTIONS -> SONG
gest(56, "down")      -- SONG -> FILES
gest(64, "right")     -- FILES -> GROOVE
gest(72, "left")      -- GROOVE -> FILES
gest(80, "up")        -- FILES -> SONG
gest(88, "right")     -- SONG -> CHAIN (needs content)
gest(96, "right")     -- CHAIN -> PHRASE
gest(104, "right")    -- PHRASE -> INSTR
gest(112, "right")    -- INSTR -> TABLE
gest(120, "up")       -- TABLE -> HELP
gest(128, "down")     -- HELP -> TABLE
gest(136, "left")     -- TABLE -> INSTR
gest(144, "up")       -- INSTR -> WAVE
gest(152, "right")    -- WAVE: A+Right = bank select, NOT a screen move

emu.addEventCallback(function() emu.setInput(pad, 0) end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if not _booted then
    if emu.read(1, emu.memType.snesWorkRam) == 0x5D then _booted = true end
    return
  end
  frames = frames + 1
  if script[frames] then pad = script[frames] end

  if frames == 20 then
    poke(0x2000, 0)          -- content for the spine descent
    poke(0x3700, 0)
    poke(0x4300, 49)
    poke(0x4301, 0)
  elseif frames == 30 then
    check(wram(0x0C) == 10, "SONG A+Up -> OPTIONS")
  elseif frames == 38 then
    check(wram(0x0C) == 12, "OPTIONS A+Right -> PROJECT")
  elseif frames == 46 then
    check(wram(0x0C) == 10, "PROJECT A+Left -> OPTIONS")
  elseif frames == 62 then
    check(wram(0x0C) == 5, "SONG A+Down -> FILES")
  elseif frames == 70 then
    check(wram(0x0C) == 11, "FILES A+Right -> GROOVE")
  elseif frames == 78 then
    check(wram(0x0C) == 5, "GROOVE A+Left -> FILES")
  elseif frames == 118 then
    check(wram(0x0C) == 14, "spine reached TABLE")
  elseif frames == 126 then
    check(wram(0x0C) == 15, "TABLE A+Up -> HELP")
  elseif frames == 134 then
    check(wram(0x0C) == 14, "HELP A+Down -> TABLE")
  elseif frames == 150 then
    check(wram(0x0C) == 7, "INSTR A+Up -> WAVE")
  elseif frames == 158 then
    check(wram(0x0C) == 7, "WAVE A+Right stays (bank select, no KIT hop)")
    if fails == 0 then
      print("ALL PASS nav.lua")
      emu.stop(0)
    else
      print("FAILED nav.lua: " .. fails)
      emu.stop(1)
    end
  end
end, emu.eventType.endFrame)
