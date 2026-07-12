-- phrase.lua — M4 gate: PHRASE screen B-grammar editing writes the song
-- block, nudge/clear work, and groove-driven playback advances rows and
-- keys notes with the right pitches.
--
-- WRAM: song block at $7E2000 (phrase 0 row r note byte = $2000 + r*4);
-- frozen vars: $15 kon_count, $16 eng_playing, $17 eng_row, $18 eng_phrase,
-- $0E..: cur handled via $0F? cursor row = cur_y ($0F), ed_col ($19).

local frames = 0
local _booted = false
local fails = 0
local pad = {}

local function wram(addr) return emu.read(addr, emu.memType.snesWorkRam) end
local function dsp(reg) return emu.read(reg, emu.memType.spcDspRegisters) end

local function check(cond, msg)
  if cond then
    print("PASS " .. msg)
  else
    print("FAIL " .. msg)
    fails = fails + 1
  end
end

local script = {
  [30] = { start = true }, [32] = {},          -- SONG
  [34] = { b = true }, [36] = {},              -- insert chain 00
  [38] = { a = true }, [40] = { a = true, right = true }, [42] = {},  -- CHAIN
  [44] = { b = true }, [46] = {},              -- insert phrase 00
  [48] = { a = true }, [50] = { a = true, right = true }, [52] = {},  -- PHRASE
  -- B tap on row 0 note column -> insert C-4
  [56] = { b = true }, [58] = {},
  -- B held + Right tap -> nudge to C#4
  [62] = { b = true },
  [64] = { b = true, right = true },
  [66] = { b = true },
  [68] = {},
  -- down twice -> row 2, B tap -> insert C#4 (last note propagates)
  [70] = { down = true }, [72] = {},
  [74] = { down = true }, [76] = {},
  [78] = { b = true }, [80] = {},
  -- row 3: insert, then block-select it (Y+B) and cut (Y again)
  [82] = { down = true }, [84] = {},
  [92] = { b = true }, [94] = {},
  [100] = { y = true },
  [102] = { y = true, b = true },
  [104] = {},
  [108] = { y = true },
  [110] = {},
  -- play (phrase mode: loops this phrase on track 0)
  [120] = { start = true }, [122] = {},
  -- stop
  [190] = { start = true }, [192] = {},
  -- block copy rows 0-2, paste at row 8 (B double-tap)
  [212] = { up = true }, [214] = {},
  [218] = { up = true }, [220] = {},
  [224] = { up = true }, [226] = {},
  [230] = { y = true },
  [232] = { y = true, b = true },
  [234] = {},
  [238] = { down = true }, [240] = {},
  [244] = { down = true }, [246] = {},
  [250] = { b = true }, [252] = {},        -- copy + exit
  [256] = { down = true }, [258] = {},
  [262] = { down = true }, [264] = {},
  [268] = { down = true }, [270] = {},
  [274] = { down = true }, [276] = {},
  [280] = { down = true }, [282] = {},
  [286] = { down = true }, [288] = {},     -- cursor on row 8
  [294] = { b = true }, [296] = {},
  [298] = { b = true }, [300] = {},        -- double-tap = paste
  -- B held + A tap: cut the pasted cell on row 8
  [320] = { b = true },
  [322] = { b = true, a = true },
  [324] = { b = true },
  [326] = {},
}

emu.addEventCallback(function() emu.setInput(pad, 0) end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if not _booted then
    if emu.read(1, emu.memType.snesWorkRam) == 0x5D then _booted = true end
    return
  end
  frames = frames + 1
  if script[frames] then pad = script[frames] end

  if frames == 54 then
    check(wram(0x000C) == 1, "navigated to the PHRASE screen")
    check(wram(0x3602) == 0xD7, "song block initialised (magic)")
  elseif frames == 60 then
    check(wram(0x4300) == 49, "B tap inserted C-4 (note 49) at row 0")
    check(wram(0x0015) == 1, "insert auditioned (1 KON)")
  elseif frames == 69 then
    check(wram(0x4300) == 50, "B+Right nudged row 0 to C#4 (50)")
    check(wram(0x0015) == 2, "nudge auditioned (2 KONs)")
  elseif frames == 81 then
    check(wram(0x000F) == 2, "cursor on row 2")
    check(wram(0x4308) == 50, "B tap inserted last note (C#4) at row 2")
  elseif frames == 98 then
    check(wram(0x430C) == 50, "row 3 inserted before the cut")
  elseif frames == 114 then
    check(wram(0x430C) == 0, "block cut cleared row 3 (Y+B, Y)")
    check(wram(0x0016) == 0, "not playing yet")
    -- zero-tune sample for the exact pitch asserts below
    emu.write(0x2401, 7, emu.memType.snesWorkRam)
    emu.write(0x2406, 0, emu.memType.snesWorkRam) -- pool tune is neutral in core checks
  elseif frames == 132 then
    check(wram(0x0016) == 1, "Start began playback")
  elseif frames == 180 then
    check(wram(0x0016) == 1, "still playing")
    local row = wram(0x0017)
    -- ~60 frames at 60.15Hz ticks / groove 6 = ~10 rows in
    check(row >= 7 and row <= 12, "groove-timed row advance (row=" .. row .. ")")
    check(wram(0x0015) >= 4, "playback keyed notes (kons=" .. wram(0x0015) .. ")")
    local p = wram(0x0013) + wram(0x0014) * 256
    check(p == 0x0800 or p == 0x0879,
      "last engine pitch is C-4/C#4 ($" .. string.format("%04X", p) .. ")")
    local dp = dsp(0x02) + dsp(0x03) * 256
    check(dp == p, "DSP V0 pitch matches engine")
  elseif frames == 198 then
    check(wram(0x0016) == 0, "Start stopped playback")
  elseif frames == 254 then
    check(wram(0xE4) == 1 and wram(0xE5) == 3, "block copy: 3 phrase rows in the clip")
  elseif frames == 308 then
    check(wram(0x4320) == 50, "paste row 8 = C#4")
    check(wram(0x4324) == 0, "paste row 9 empty (from empty row 1)")
    check(wram(0x4328) == 50, "paste row 10 = C#4")
  elseif frames == 332 then
    check(wram(0x4320) == 0, "B held + A cut row 8")
  elseif frames == 340 then
    local out = os.getenv("SNDJ_PHRASE_SHOT")
    if out then
      local png = emu.takeScreenshot()
      local f = io.open(out, "wb")
      f:write(png)
      f:close()
      print("info: phrase screenshot -> " .. out)
    end
    if fails == 0 then
      print("ALL PASS phrase.lua")
      emu.stop(0)
    else
      print("FAILED phrase.lua: " .. fails)
      emu.stop(1)
    end
  end
end, emu.eventType.endFrame)
