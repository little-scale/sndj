-- slice.lua — the SLICE instrument type: equal block-aligned divisions of
-- one pool sample as directory alias entries (zero extra ARAM). The note
-- picks the slice wrapped mod n, pitch is native +/- TUNE, the envelope
-- synthesizes from the ATK nibble + FADE rate. Editing SLICES on the
-- INSTR screen rebuilds the residency windows.
--
-- Blob under test: authored one-shot slot 7. Alias step size is derived from
-- its current BRR block count so factory content can change independently.

local frames = 0
local _booted = false
local fails = 0
local pad = {}
local R = emu.memType.snesPrgRom
local POOL = 0x8006
local SLICE_SAMPLE = 7

local function wram(a) return emu.read(a, emu.memType.snesWorkRam) end
local function poke(a, v) emu.write(a, v, emu.memType.snesWorkRam) end
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

local function row(r, note, instr)
  local base = 0x4300 + r * 4
  poke(base, note); poke(base + 1, instr)
end

local script = {
  [14] = { start = true }, [16] = {},
  -- SONG -> CHAIN -> PHRASE -> INSTR
  [34] = { a = true }, [36] = { a = true, right = true }, [38] = {},
  [42] = { a = true }, [44] = { a = true, right = true }, [46] = {},
  [50] = { a = true }, [52] = { a = true, right = true }, [54] = {},
  -- cursor to SLICES (fields 0-3 visible for SLICE), nudge 3 -> 4
  [58] = { down = true }, [60] = {},
  [62] = { down = true }, [64] = {},
  [66] = { down = true }, [68] = {},
  [72] = { b = true }, [74] = { b = true, right = true },
  [76] = { b = true }, [78] = {},
  -- the rebuild re-uploads every resident sample (~2 s, main loop
  -- blocked); everything below waits it out
  [260] = { a = true }, [262] = { a = true, left = true }, [264] = {},
  [268] = { a = true }, [270] = { a = true, left = true }, [272] = {},
  [276] = { a = true }, [278] = { a = true, left = true }, [280] = {},
  [290] = { start = true }, [292] = {},
  [386] = { start = true }, [388] = {},
  [400] = { start = true }, [402] = {},
}

local srcns, pitches = {}, {}
local function collect()
  srcns[#srcns + 1] = dsp(0x04)
  pitches[#pitches + 1] = dsp(0x02) + dsp(0x03) * 256
end

emu.addEventCallback(function() emu.setInput(pad, 0) end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if not _booted then
    if emu.read(1, emu.memType.snesWorkRam) == 0x5D then _booted = true end
    return
  end
  frames = frames + 1
  if script[frames] then pad = script[frames] end

  if frames == 30 then
    poke(0x2000, 0)          -- V1 r0 = chain 0
    poke(0x3700, 0)          -- chain 0 e0 = phrase 0
    -- instrument 0: SLICE of an authored one-shot, 3 slices (gesture -> 4),
    -- ATK F + FADE 8, TUNE 0
    poke(0x2400, 4)
    poke(0x2401, SLICE_SAMPLE)
    poke(0x2406, 0)           -- core runner already neutralizes pool tuning
    poke(0x2402, 0x8F)
    poke(0x2407, 0x20)
    poke(0x2409, 0)
    row(0, 1, 0)             -- slice 0
    row(4, 2, 0)             -- slice 1
    row(8, 3, 0)             -- slice 2
    row(12, 4, 0)            -- slice 3
  elseif frames == 250 then
    check(wram(0x2407) == 0x30, "B+Right nudged SLICES 3 -> 4")
  elseif frames == 296 or frames == 321 or frames == 346 or frames == 371 then
    collect()
  elseif frames == 380 then
    check(srcns[2] == srcns[1] + 1 and srcns[3] == srcns[1] + 2
      and srcns[4] == srcns[1] + 3,
      "notes 1-4 walk consecutive slice SRCNs (" .. srcns[1] .. ".." .. srcns[4] .. ")")
    -- Equal windows use floor(total BRR blocks / slice count).
    local ok = true
    local e = POOL + 16 + SLICE_SAMPLE * 16
    local blocks = rom(e + 10) + rom(e + 11) * 256
    local step = math.floor(blocks / 4) * 9
    local a0 = aram(0x1000 + srcns[1] * 4) + aram(0x1001 + srcns[1] * 4) * 256
    for k = 1, 3 do
      local ak = aram(0x1000 + (srcns[1] + k) * 4) + aram(0x1001 + (srcns[1] + k) * 4) * 256
      if ak ~= a0 + k * step then ok = false end
    end
    check(ok, "4 alias entries at equal " .. step .. "-byte steps")
    check(pitches[1] == 0x1000 and pitches[4] == 0x1000,
      "slices play at native pitch (notes pick, not tune)")
    check(dsp(0x05) == 0x8F,
      string.format("ADSR1 = ATK nibble, decay 0 ($%02X)", dsp(0x05)))
    check(dsp(0x06) == 0xF6,
      string.format("ADSR2 = sus 7 + FADE 8 -> SR 22 ($%02X)", dsp(0x06)))
  elseif frames == 394 then
    poke(0x2409, 12)         -- TUNE +12
    row(0, 5, 0)             -- note 5 wraps to slice 0
  elseif frames == 412 then
    check(dsp(0x04) == srcns[1],
      "note 5 wrapped mod 4 back to slice 0 (SRCN " .. dsp(0x04) .. ")")
    local p = dsp(0x02) + dsp(0x03) * 256
    check(p == 0x2000,
      string.format("TUNE +12 transposes the whole kit of slices ($%04X)", p))
    if fails == 0 then
      print("ALL PASS slice.lua")
      emu.stop(0)
    else
      print("FAILED slice.lua: " .. fails)
      emu.stop(1)
    end
  end
end, emu.eventType.endFrame)
