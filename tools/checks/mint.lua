-- mint.lua — minting and cloning (genmddj §4): B double-tap on an empty
-- SONG/CHAIN reference cell mints the next free blank chain/phrase; on
-- a populated cell it clones (SONG chains honour OPTIONS CLONE
-- SLIM/DEEP; phrase clones are always independent).
--
-- WRAM: grid $2000, chains $3700 (32 ea), phrases $4300 (64 ea),
-- opt_clone $312.

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

local script = {
  [14] = { start = true }, [16] = {},           -- splash -> SONG
  -- double-tap the empty (0,0): mints chain 0
  [20] = { b = true }, [22] = {},
  [24] = { b = true }, [26] = {},
  -- down to (0,1), double-tap: mints chain 1
  [34] = { down = true }, [36] = {},
  [40] = { b = true }, [42] = {},
  [44] = { b = true }, [46] = {},
  -- back to (0,0), double-tap the populated cell: SLIM clone
  [54] = { up = true }, [56] = {},
  [60] = { b = true }, [62] = {},
  [64] = { b = true }, [66] = {},
  -- DEEP clone (opt_clone poked below)
  [76] = { b = true }, [78] = {},
  [80] = { b = true }, [82] = {},
  -- into the chain (now chain 3), entry 1: mint a phrase
  [90] = { a = true }, [92] = { a = true, right = true }, [94] = {},
  [100] = { down = true }, [102] = {},
  [106] = { b = true }, [108] = {},
  [110] = { b = true }, [112] = {},
  -- entry 0 (populated): phrase clone
  [120] = { up = true }, [122] = {},
  [126] = { b = true }, [128] = {},
  [130] = { b = true }, [132] = {},
}

emu.addEventCallback(function() emu.setInput(pad, 0) end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if not _booted then
    if emu.read(1, emu.memType.snesWorkRam) == 0x5D then _booted = true end
    return
  end
  frames = frames + 1
  if script[frames] then pad = script[frames] end

  if frames == 18 then
    -- the emulator persists .sav across runs: pin CLONE to SLIM
    emu.write(0x0008, 0, emu.memType.snesSaveRam)
    poke(0x312, 0)
  elseif frames == 30 then
    check(wram(0x2000) == 0, "double-tap on empty minted chain 0")
    -- populate chain 0 + phrase 0 so later taps see content
    poke(0x3700, 0)
    poke(0x4300, 49)
  elseif frames == 50 then
    check(wram(0x2001) == 1, "next mint took the next blank (chain 1)")
    poke(0x3720, 1)          -- populate chain 1 so it stops being free
    poke(0x4340, 60)         -- and phrase 1
  elseif frames == 70 then
    check(wram(0x2000) == 2, "double-tap on populated cell cloned to chain 2")
    check(wram(0x3740) == 0, "SLIM clone shares phrase 0")
    poke(0x312, 1)           -- OPTIONS CLONE -> DEEP
  elseif frames == 86 then
    check(wram(0x2000) == 3, "DEEP clone landed in chain 3")
    check(wram(0x3760) == 2, "DEEP clone repointed at a fresh phrase (2)")
    check(wram(0x4380) == 49, "the cloned phrase copied its rows")
  elseif frames == 116 then
    check(wram(0x3762) == 3, "CHAIN double-tap on empty minted phrase 3")
    poke(0x43C0, 60)         -- populate it so it stops being free
  elseif frames == 136 then
    check(wram(0x3760) == 4, "phrase clone is always an independent copy (4)")
    check(wram(0x4400) == 49, "the phrase clone copied its rows")
    if fails == 0 then
      print("ALL PASS mint.lua")
      emu.stop(0)
    else
      print("FAILED mint.lua: " .. fails)
      emu.stop(1)
    end
  end
end, emu.eventType.endFrame)
