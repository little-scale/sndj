-- phrase.lua — M4 gate: PHRASE screen B-grammar editing writes the song
-- block, nudge/clear work, and groove-driven playback advances rows and
-- keys notes with the right pitches.
--
-- WRAM: song block at $7E2000 (phrase 0 row r note byte = $2000 + r*4);
-- frozen vars: $15 kon_count, $16 eng_playing, $17 eng_row, $18 eng_phrase,
-- $0E..: cur handled via $0F? cursor row = cur_y ($0F), ed_col ($19).

local frames = 0
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
  [30] = { start = true }, [32] = {},
  -- B tap on row 0 note column -> insert C-4
  [40] = { b = true }, [42] = {},
  -- B held + Right tap -> nudge to C#4
  [46] = { b = true },
  [50] = { b = true, right = true },
  [52] = { b = true },
  [56] = {},
  -- down twice -> row 2, B tap -> insert C#4 (last note propagates)
  [60] = { down = true }, [62] = {},
  [64] = { down = true }, [66] = {},
  [68] = { b = true }, [70] = {},
  -- row 3: insert then Y+B clear
  [74] = { down = true }, [76] = {},
  [80] = { b = true }, [82] = {},
  [86] = { y = true },
  [88] = { y = true, b = true },
  [90] = {},
  -- play
  [100] = { start = true }, [102] = {},
  -- stop
  [170] = { start = true }, [172] = {},
}

emu.addEventCallback(function() emu.setInput(pad, 0) end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  frames = frames + 1
  if script[frames] then pad = script[frames] end

  if frames == 36 then
    check(wram(0x000C) == 1, "Start opened the PHRASE screen")
    check(wram(0x5782) == 0xD7, "song block initialised (magic)")
  elseif frames == 45 then
    check(wram(0x2000) == 49, "B tap inserted C-4 (note 49) at row 0")
    check(wram(0x0015) == 1, "insert auditioned (1 KON)")
  elseif frames == 58 then
    check(wram(0x2000) == 50, "B+Right nudged row 0 to C#4 (50)")
    check(wram(0x0015) == 2, "nudge auditioned (2 KONs)")
  elseif frames == 72 then
    check(wram(0x000F) == 2, "cursor on row 2")
    check(wram(0x2008) == 50, "B tap inserted last note (C#4) at row 2")
  elseif frames == 96 then
    check(wram(0x200C) == 0, "Y+B cleared row 3")
    check(wram(0x0016) == 0, "not playing yet")
  elseif frames == 112 then
    check(wram(0x0016) == 1, "Start began playback")
  elseif frames == 160 then
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
  elseif frames == 178 then
    check(wram(0x0016) == 0, "Start stopped playback")
  elseif frames == 185 then
    local out = os.getenv("SNESDJ_PHRASE_SHOT")
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
