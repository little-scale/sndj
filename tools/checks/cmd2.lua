-- cmd2.lua — the second command batch: F fine tune, M master volume,
-- N noise clock, Z pitch-mod, Q GAIN override/restore, U surround,
-- S sweep. One track, one command per even row, DSP-level asserts.
--
-- Command ids: F=6 M=13 N=14 Q=17 S=19 U=21 Z=26.

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

local function row(r, note, instr, cmd, val)
  local base = 0x4300 + r * 4
  poke(base, note); poke(base + 1, instr)
  poke(base + 2, cmd); poke(base + 3, val)
end

local sweep_a, sweep_b = -1, -1

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
    poke(0x2000, 0)          -- grid: track 0 row 0 = chain 0
    poke(0x3700, 0)          -- chain 0 entry 0 = phrase 0
    poke(0x2401, 12)         -- instr 0 -> BONGO 2 (tune 0)
    row(0, 49, 0, 6, 0x40)   -- C-4 + F40: fine +64 at trigger
    row(2, 0, 0xFF, 13, 0x20) -- M20: master volume
    row(4, 0, 0xFF, 14, 0x05) -- N05: noise clock
    row(6, 0, 0xFF, 26, 0x01) -- Z01: pitch-mod on
    row(8, 0, 0xFF, 17, 0x35) -- Q35: GAIN exp-dec rate 5
    row(10, 0, 0xFF, 17, 0x00) -- Q00: back to ADSR
    row(12, 0, 0xFF, 21, 0x11) -- U11: invert both phases
    row(14, 0, 0xFF, 19, 0x0F) -- S0F: sweep down
    -- second phrase pass never happens: chain has only entry 0 and the
    -- block loops, so extend the test into phrase rows via a C command
    -- on its own row 15 with a fresh note
    row(15, 49, 0, 3, 0x47)  -- C-4 + C47: fan a major chord
  elseif frames == 44 then
    pad = { start = true }
  elseif frames == 46 then
    pad = {}
  elseif frames == 54 then
    local p = dsp(0x02) + dsp(0x03) * 256
    check(p == 0x081E, "F40 tuned the trigger +64/256 semi ($" ..
      string.format("%04X", p) .. ")")
  elseif frames == 66 then
    check(dsp(0x0C) == 0x20 and dsp(0x1C) == 0x20, "M20 set master volume")
  elseif frames == 78 then
    check(dsp(0x6C) == 0x05, "N05 set the global noise clock")
  elseif frames == 90 then
    check(dsp(0x2D) == 0x01, "Z01 raised the PMON bit")
  elseif frames == 102 then
    check(dsp(0x07) == 0xA5, "Q35 wrote GAIN exp-dec rate 5")
    check(dsp(0x05) < 0x80, "Q35 dropped ADSR1 bit 7 (GAIN active)")
  elseif frames == 114 then
    check(dsp(0x05) >= 0x80, "Q00 restored the ADSR")
  elseif frames == 126 then
    check(dsp(0x00) == 0xB0 and dsp(0x01) == 0xB0,
      "U11 inverted both volume phases ($50 -> $B0)")
  elseif frames == 133 then
    sweep_a = dsp(0x02) + dsp(0x03) * 256
  elseif frames == 136 then
    sweep_b = dsp(0x02) + dsp(0x03) * 256
    check(sweep_b < sweep_a, "S0F sweeps the pitch down (" ..
      string.format("%04X -> %04X", sweep_a, sweep_b) .. ")")
  elseif frames == 148 then
    -- row 15: C47 chord (offsets +4/+7 on the next two voices)
    local p0 = dsp(0x02) + dsp(0x03) * 256
    local p1 = dsp(0x12) + dsp(0x13) * 256
    local p2 = dsp(0x22) + dsp(0x23) * 256
    -- the root keeps row 0's F fine (+64); members play pure offsets
    check(p0 == 0x081E and p1 == 0x0A14 and p2 == 0x0BFC,
      "C47 fanned a major chord (" ..
      string.format("%04X/%04X/%04X", p0, p1, p2) .. ")")
    if fails == 0 then
      print("ALL PASS cmd2.lua")
      emu.stop(0)
    else
      print("FAILED cmd2.lua: " .. fails)
      emu.stop(1)
    end
  end
end, emu.eventType.endFrame)
