-- boot.lua — M1 gate: ROM boots, init completes, frames advance,
-- splash text lands in the BG3 shadow map, pad input echoes into WRAM,
-- DAS auto-repeat moves the cursor.
--
-- WRAM addresses here are the FROZEN block from src/ram.inc.

local frames = 0
local fails = 0
local fc_sample = -1
local pad = {}   -- table of buttons to hold, applied at every input poll

local function wram(addr)
  return emu.read(addr, emu.memType.snesWorkRam)
end

local function wram16(addr)
  return wram(addr) + wram(addr + 1) * 256
end

local function check(cond, msg)
  if cond then
    print("PASS " .. msg)
  else
    print("FAIL " .. msg)
    fails = fails + 1
  end
end

-- shadow tilemap word for text cell (x, y)
local function cell(x, y)
  return wram16(0x0400 + (y * 32 + x) * 2)
end

local function word(ch, attr)
  return (string.byte(ch) - 32) | attr
end

local ATTR_ACCENT = 0x2400

local function onPoll()
  emu.setInput(pad, 0)
end

local function onFrame()
  frames = frames + 1

  if frames == 20 then
    check(wram(0x0001) == 0x5D, "magic_boot set (init completed)")
    fc_sample = wram16(0x0002)
    local s = "SNESDJ"
    local ok = true
    for i = 1, #s do
      if cell(13 + i - 1, 7) ~= word(s:sub(i, i), ATTR_ACCENT) then
        ok = false
      end
    end
    check(ok, "splash title rendered in shadow map")
    check(wram(0x000C) == 0, "ui_mode is splash")
    pad = { start = true }
  elseif frames == 26 then
    local fc = wram16(0x0002)
    check(fc > fc_sample and fc <= fc_sample + 7,
      "frame counter advancing (" .. fc_sample .. " -> " .. fc .. ")")
    check(wram16(0x0006) & 0x1000 == 0x1000, "pad_held echoes Start bit")
    check(wram(0x000C) == 1, "Start entered the PHRASE screen")
    pad = { down = true }   -- hold Down: DAS delay 14 + repeats every 3
  elseif frames == 55 then
    local cy = wram(0x000F)
    check(cy >= 3 and cy <= 12, "DAS auto-repeat moved cursor (cur_y=" .. cy .. ")")
    if fails == 0 then
      print("ALL PASS boot.lua")
      emu.stop(0)
    else
      print("FAILED boot.lua: " .. fails)
      emu.stop(1)
    end
  end
end

emu.addEventCallback(onFrame, emu.eventType.endFrame)
emu.addEventCallback(onPoll, emu.eventType.inputPolled)
