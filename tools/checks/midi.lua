-- midi.lua — M14 gate: MIDI takeover end-to-end through the real wire
-- code. A Lua "bridge" presents framed events on DAT ($4017 bit 0),
-- clocked by the console's CLK edges (IOBit, $4201 bit 7): flag bit,
-- then 3 bytes MSB-first, next bit presented on each falling edge.
--
-- WRAM: opt_sync $036A, midi_instr $0373, midi_note $037B,
-- midi_rx $0393, trk_voll $0358.

local frames = 0
local _booted = false
local fails = 0
local pad = {}

local function wram(addr) return emu.read(addr, emu.memType.snesWorkRam) end
local function poke(a, v) emu.write(a, v, emu.memType.snesWorkRam) end
local function dsp(reg) return emu.read(reg, emu.memType.spcDspRegisters) end

local function check(cond, msg)
  if cond then
    print("PASS " .. msg)
  else
    print("FAIL " .. msg)
    fails = fails + 1
  end
end

-- the virtual ESP32-S3 bridge
local bits = {}          -- pending bit queue; empty -> DAT presents 0 (no flag)
local head = 1
local clk_prev = 0xFF

local function push_event(st, d1, d2)
  bits[#bits + 1] = 1                    -- leading flag: a frame follows
  for _, byte in ipairs({ st, d1, d2 }) do
    for b = 7, 0, -1 do
      bits[#bits + 1] = (byte >> b) & 1
    end
  end
end

emu.addMemoryCallback(function(address, value)
  local bit = 0
  if head <= #bits then bit = bits[head] end
  return bit
end, emu.callbackType.read, 0x804017, 0x804017)

emu.addMemoryCallback(function(address, value)
  if (clk_prev & 0x80) ~= 0 and (value & 0x80) == 0 then
    if head <= #bits then head = head + 1 end   -- falling edge: next bit
  end
  clk_prev = value
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
    poke(0x2401, 7)            -- instr 0 -> BD
    poke(0x2406, 0)            -- core runner already neutralizes pool tuning
    poke(0x2450, 2)            -- instr 5 -> WAV bank 0 (all slots ship SMP now)
    poke(0x2451, 0)
    poke(0x036A, 4)            -- SYNC: MIDI (midi_service applies next frame)
  elseif frames == 40 then
    check(wram(0x0373) == 0 and wram(0x0374) == 1 and wram(0x037A) == 7,
      "entry seeded ch->instrument 1:1")
    check(wram(0x037B) == 0xFF, "no note sounding after entry")
    -- note on: ch 1, MIDI 60 (C-4 after the -12 offset), velocity 100
    push_event(0x20, 60, 100)
  elseif frames == 46 then
    check(wram(0x0393) == 1, "the frame decoded (RX counter)")
    check(wram(0x037B) == 48, "note-on latched console note 48")
    check(wram(0x15) == 1, "note-on keyed the voice")
    local p = dsp(0x02) + dsp(0x03) * 256
    check(p == 0x0800, "MIDI 60 -> C-4 pitch ($" .. string.format("%04X", p) .. ")")
    check(dsp(0x00) == 100 and dsp(0x01) == 100, "velocity drives the level")
    -- bend +4096 = +1 semitone exactly (d2 96 -> value 12288)
    push_event(0x50, 0, 96)
  elseif frames == 52 then
    local p = dsp(0x02) + dsp(0x03) * 256
    check(p == 0x0879, "bend +1 semi retuned live to C#4 ($" ..
      string.format("%04X", p) .. ")")
    push_event(0x50, 0, 64)    -- bend centre
    push_event(0x10, 60, 0)    -- note off
  elseif frames == 58 then
    check(wram(0x037B) == 0xFF, "note-off released the voice")
    -- program change on ch 2 -> instrument 5 (poked to WAV bank 0),
    -- then a note through it
    push_event(0x41, 5, 0)
    push_event(0x21, 72, 127)
  elseif frames == 64 then
    check(wram(0x0374) == 5, "program change rebound ch 2 -> instr 05")
    check(dsp(0x14) == 56, "ch-2 note plays the WAV source (SRCN 56)")
    local p = dsp(0x12) + dsp(0x13) * 256
    -- WAV tuning: C-4 = $0430 (wave.lua), so C-5 = $0860 after the -1 octave
    check(p == 0x0860, "WAV pitch through the wave tuning (C-5 -> $" ..
      string.format("%04X", p) .. ")")
    -- CC 7 volume on ch 2
    push_event(0x31, 7, 32)
  elseif frames == 70 then
    check(dsp(0x10) == 32 and dsp(0x11) == 32, "CC7 set the ch-2 level")
    check(wram(0x0359) == 32, "the live level tracks it (trk_voll)")
    push_event(0x70, 0, 0)     -- panic
  elseif frames == 76 then
    check(wram(0x037C) == 0xFF, "panic released everything")
    local rx = wram(0x0393) + wram(0x0394) * 256
    check(rx == 8, "monitor counted all 8 frames (rx=" .. rx .. ")")
    -- leaving the mode restores normal input handling
    poke(0x036A, 0)
  elseif frames == 84 then
    check(wram(0x0371) == 0, "mode exit applied (shadow follows)")
    if fails == 0 then
      print("ALL PASS midi.lua")
      emu.stop(0)
    else
      print("FAILED midi.lua: " .. fails)
      emu.stop(1)
    end
  end
end, emu.eventType.endFrame)
