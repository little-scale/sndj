-- sync.lua — M12 gate: SYNC IN / IN24 lock row advance to injected clock
-- edges (2-bit counter presented on the real $4017 read path), WAIT holds
-- row 0 silent until the first clock, and PULSE drives IOBit ($4201) at
-- 2 PPQN. OUT stays a selectable dummy (nothing to assert).
--
-- WRAM: opt_sync $036A, sync_wait $036C, sync_gctr $036D, sync_act $036F.

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

-- the virtual master: a 2-bit counter presented on port 2's data lines
local counter = 0
local pulses = 0
local wrio_prev = 0xFF

emu.addMemoryCallback(function(address, value)
  return counter & 3
end, emu.callbackType.read, 0x804017, 0x804017)

emu.addMemoryCallback(function(address, value)
  if (wrio_prev & 0x80) == 0 and (value & 0x80) ~= 0 then
    pulses = pulses + 1        -- IOBit rising edge = one pulse
  end
  wrio_prev = value
end, emu.callbackType.write, 0x804201, 0x804201)

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
    poke(0x2000, 0)            -- track 0 row 0 = chain 0
    poke(0x3700, 0)            -- chain 0 entry 0 = phrase 0
    poke(0x2401, 23)           -- instr 0 -> SW ORCH (tune 0)
    for r = 0, 15 do           -- a note on every row marks each advance
      poke(0x4300 + r * 4, 49)
      poke(0x4301 + r * 4, 0)
    end
    poke(0x036A, 3)            -- SYNC: IN
  elseif frames == 44 then
    pad = { start = true }
  elseif frames == 46 then
    pad = {}
  elseif frames == 70 then
    check(wram(0x16) == 1, "transport armed (playing)")
    check(wram(0x036C) == 1, "IN: WAIT holds for the first clock")
    check(wram(0x15) == 0, "WAIT is silent (no KON before a clock)")
    counter = counter + 1      -- the first external clock
  elseif frames == 76 then
    check(wram(0x036C) == 0, "first clock disarmed WAIT")
    check(wram(0x17) == 0 and wram(0x15) == 1, "first clock played row 0")
    counter = counter + 1
  elseif frames == 82 then
    check(wram(0x17) == 1, "IN advances one row per clock")
    counter = counter + 2      -- a multi-clock burst (2-bit catch-up)
  elseif frames == 92 then
    check(wram(0x17) == 3, "burst of 2 caught up losslessly (row 3)")
    check(wram(0x15) == 4, "each row keyed its note")
  elseif frames == 100 then
    check(wram(0x17) == 3, "no clock, no advance (master owns the tempo)")
    pad = { start = true }     -- stop
  elseif frames == 102 then
    pad = {}
  elseif frames == 110 then
    poke(0x036A, 5)            -- SYNC: IN24
    pad = { start = true }
  elseif frames == 112 then
    pad = {}
  elseif frames == 126 then
    check(wram(0x036C) == 1, "IN24: WAIT re-armed")
    check(wram(0x036D) == 5, "IN24 head-start seeded (divisor-1)")
    counter = counter + 1      -- first clock completes the head-start
  elseif frames == 132 then
    check(wram(0x036C) == 0 and wram(0x17) == 0,
      "IN24: the FIRST clock plays row 0")
    counter = counter + 3
  elseif frames == 138 then
    counter = counter + 3      -- 6 clocks total = one row
  elseif frames == 146 then
    check(wram(0x17) == 1, "IN24 divides by 6 (24 PPQN -> one row)")
    pad = { start = true }     -- stop
  elseif frames == 148 then
    pad = {}
  elseif frames == 156 then
    poke(0x036A, 2)            -- SYNC: PULSE
    pulses = 0
    pad = { start = true }
  elseif frames == 158 then
    pad = {}
  elseif frames == 278 then
    -- ~120 frames of ticks at 12 ticks/pulse ~= 10 pulses
    check(pulses >= 7 and pulses <= 13,
      "PULSE drives IOBit at 2 PPQN (" .. pulses .. " pulses/2s)")
    local act = wram(0x036F) + wram(0x0370) * 256
    check(act == pulses, "activity counter matches the wire (" .. act .. ")")
    if fails == 0 then
      print("ALL PASS sync.lua")
      emu.stop(0)
    else
      print("FAILED sync.lua: " .. fails)
      emu.stop(1)
    end
  end
end, emu.eventType.endFrame)
