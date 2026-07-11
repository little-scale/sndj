-- transport.lua — Start is the global transport, A+B is contextual
-- play/stop, and a song-grid chain block loops back to its top row.
--
-- Song: track 0 rows 0-1 = chain 0 (a 2-row contiguous block), row 2
-- empty. Chain 0 entry 0 = phrase 0 only, so each row lasts 16 phrase
-- rows (~10 frames each at groove 6). Walk: row0 -> row1 -> back to
-- row0 (block loop, never halts).
--
-- WRAM: eng_playing $16, trk_songrow[0] $38, ui_mode $0C.

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

local row_seen = { [0] = false, [1] = false }
local tick_a = 0
local looped = false
local last_row = -1

emu.addEventCallback(function() emu.setInput(pad, 0) end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if not _booted then
    if emu.read(1, emu.memType.snesWorkRam) == 0x5D then _booted = true end
    return
  end
  frames = frames + 1
  if frames == 14 then pad = { start = true } end
  if frames == 17 then pad = {} end

  if frames == 30 then
    poke(0x2000, 0)          -- track 0 row 0 = chain 0
    poke(0x2001, 0)          -- track 0 row 1 = chain 0 (block of two)
    poke(0x3700, 0)          -- chain 0 entry 0 = phrase 0
    poke(0x4300, 49)         -- C-4
    poke(0x4301, 0)
  elseif frames == 36 then
    pad = { start = true }   -- transport from SONG
  elseif frames == 38 then
    pad = {}
  elseif frames > 40 and frames < 560 then
    -- watch the song row walk: 0 -> 1 -> 0 again = block loop
    local r = wram(0x38)
    if wram(0x16) == 1 and r <= 1 then
      if r == 1 then row_seen[1] = true end
      if r == 0 and last_row == 1 then looped = true end
      last_row = r
    end
  end

  if frames == 560 then
    check(wram(0x16) == 1, "still playing after the block end")
    check(row_seen[1], "walked into song row 1")
    check(looped, "chain block looped back to its top row")
    -- A+B while playing = stop (on SONG; per-track stops are LIVE's)
    pad = { a = true }
  elseif frames == 562 then
    pad = { a = true, b = true }
  elseif frames == 564 then
    pad = {}
  elseif frames == 570 then
    check(wram(0x16) == 0, "A+B stopped the transport")
    pad = { a = true }
  elseif frames == 572 then
    pad = { a = true, b = true }
  elseif frames == 574 then
    pad = {}
  elseif frames == 580 then
    check(wram(0x16) == 1, "A+B while stopped plays from the cursor")
    -- Start on PHRASE must be the global transport (stop), not phrase solo
    pad = { start = true }
  elseif frames == 582 then
    pad = {}
  elseif frames == 588 then
    check(wram(0x16) == 0, "Start stopped the transport")
    -- a block of chains with no phrases must halt gracefully, not hang
    poke(0x2000, 1)          -- chain 1 is factory-empty (all $FF entries)
    poke(0x2001, 0xFF)
  elseif frames == 592 then
    pad = { start = true }
  elseif frames == 594 then
    pad = {}
    tick_a = wram(0x1D1) + wram(0x1D2) * 256
  elseif frames == 650 then
    local tick_b = wram(0x1D1) + wram(0x1D2) * 256
    check(tick_b ~= tick_a, "main loop alive after an all-empty block")
    check(wram(0x28) == 0xFF, "empty-walk guard halted the track")
    if fails == 0 then
      print("ALL PASS transport.lua")
      emu.stop(0)
    else
      print("FAILED transport.lua: " .. fails)
      emu.stop(1)
    end
  end
end, emu.eventType.endFrame)
