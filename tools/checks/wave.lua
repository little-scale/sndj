-- wave.lua — M10 gate: drawn wavetables compile to looped BRRs in ARAM
-- scratch, WAV instruments play them (SRCN 32+, pitch -2 oct), the B
-- command wave-sequences per row, NSE drives NON + the global noise
-- clock, and WAVE-screen edits land in ARAM immediately.

local frames = 0
local _booted = false
local fails = 0
local pad = {}
local W = emu.memType.snesWorkRam

local function wram(a) return emu.read(a, W) end
local function poke(a, v) emu.write(a, v, W) end
local function dsp(r) return emu.read(r, emu.memType.spcDspRegisters) end
local function aram(a) return emu.read(a, emu.memType.spcRam) end

local function check(cond, msg)
  if cond then
    print("PASS " .. msg)
  else
    print("FAIL " .. msg)
    fails = fails + 1
  end
end

local script = {}
local t = 70                       -- boot now includes echo cfg + wave sync
local function gest(b, gap) script[t]=b; t=t+2; script[t]={}; t=t+(gap or 2) end
local function bnudge(dir, gap)
  script[t]={b=true}; t=t+2
  script[t]={b=true,[dir]=true}; t=t+2
  script[t]={b=true}; t=t+2
  script[t]={}; t=t+(gap or 2)
end

gest({ start = true }, 4)          -- SONG
local play = t + 2
t = play + 60
local stop = t
gest({ start = true }, 6)          -- stop
-- navigate to WAVE: CHAIN -> PHRASE -> INSTR -> A+Up
gest({ a = true, right = true }, 4)
gest({ a = true, right = true }, 4)
gest({ a = true, right = true }, 4)
gest({ a = true, up = true }, 6)
local at_wave = t
bnudge("down", 8)                  -- sine column 0: 8 -> 7 (recompile)
local edited = t + 10

emu.addEventCallback(function() emu.setInput(pad, 0) end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if not _booted then
    if emu.read(1, emu.memType.snesWorkRam) == 0x5D then _booted = true end
    return
  end
  frames = frames + 1
  if script[frames] then pad = script[frames] end
  if frames == play then pad = { start = true } end
  if frames == play + 2 then pad = {} end

  if frames == 66 then
    -- boot state: compiled banks + directory entries
    check(aram(0x1100) == 0xB0, "bank 0 BRR block 0 header (range 11)")
    check(aram(0x1109) == 0xB3, "bank 0 BRR block 1 header (END+LOOP)")
    check(aram(0x1080) == 0x00 and aram(0x1081) == 0x11 and
          aram(0x1082) == 0x00 and aram(0x1083) == 0x11,
          "directory entry 32 -> wave slot 0")
    check(aram(0x1084) == 0x12 and aram(0x1085) == 0x11,
          "directory entry 33 -> wave slot 1 ($1112)")
    -- author the test song: WAV instrument 1 (bank 1), NSE instrument 2
    poke(0x2000, 0)
    poke(0x3700, 0)
    poke(0x2410, 2)          -- instr 1: type WAV
    poke(0x2411, 1)          -- bank 1 (triangle)
    poke(0x2412, 0x2F)
    poke(0x2413, 0xCA)
    poke(0x2414, 0x50)
    poke(0x2415, 0x50)
    poke(0x2420, 3)          -- instr 2: type NSE
    poke(0x2421, 0)
    poke(0x2422, 0x2F)
    poke(0x2423, 0xCA)
    poke(0x2424, 0x50)
    poke(0x2425, 0x50)
    -- phrase 0: r0 C-4 wav1 | r4 B02 | r8 G-4 nse2 | r12 C-4 wav1
    poke(0x4300, 49)
    poke(0x4301, 1)
    poke(0x4310, 0)
    poke(0x4311, 0xFF)
    poke(0x4312, 2)          -- B
    poke(0x4313, 2)          -- bank 2 (saw)
    poke(0x4320, 56)         -- G-4 (idx 55 -> clock 23)
    poke(0x4321, 2)
    poke(0x4330, 49)
    poke(0x4331, 1)
  elseif frames == play + 8 then
    check(dsp(0x04) == 33, "WAV instrument routes SRCN to wave slot 33")
    check(dsp(0x02) + dsp(0x03) * 256 == 0x0200,
      "WAV pitch dropped 2 octaves ($0200 for C-4)")
    check(dsp(0x3D) == 0, "no noise yet")
  elseif frames == play + 32 then
    check(dsp(0x04) == 34, "B02 wave-sequenced to bank 2 (SRCN 34)")
  elseif frames == play + 56 then
    check(dsp(0x3D) == 0x01, "NSE set the voice's NON bit")
    check(dsp(0x6C) % 32 == 23, "noise clock follows the note (G-4 -> 23)")
  elseif frames == at_wave then
    check(wram(0x0C) == 7, "A+Up from INSTR opened WAVE")
    local out = os.getenv("SNESDJ_WAVE_SHOT")
    if out then
      local png = emu.takeScreenshot()
      local f = io.open(out, "wb")
      f:write(png)
      f:close()
    end
  elseif frames == edited then
    -- sine col 0: 8 -> 7 => first data byte: (7-8)&15 <<4 | (9-8)&15 = $F1
    check(wram(0x3100) == 7, "edit stored in the song block")
    check(aram(0x1101) == 0xF1, "edit recompiled + re-uploaded to ARAM ($" ..
      string.format("%02X", aram(0x1101)) .. ")")
    if fails == 0 then
      print("ALL PASS wave.lua")
      emu.stop(0)
    else
      print("FAILED wave.lua: " .. fails)
      emu.stop(1)
    end
  end
end, emu.eventType.endFrame)
