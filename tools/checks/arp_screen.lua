-- arp_screen.lua — screen redraw cost must not alias tick effects.
-- The same A47 arrangement is measured on PHRASE and INSTR; each consumed
-- audio tick should leave an observable pitch step on both screens.

local frames = 0
local booted = false
local fails = 0
local pad = {}
local W = emu.memType.snesWorkRam
local result = {}
local run, last_pitch, changes, tick0

local function wram(a) return emu.read(a, W) end
local function poke(a, v) emu.write(a, v, W) end
local function pitch()
  return emu.read(2, emu.memType.spcDspRegisters) +
    256 * emu.read(3, emu.memType.spcDspRegisters)
end
local function word(a) return wram(a) + 256 * wram(a + 1) end
local function check(cond, msg)
  if cond then print("PASS " .. msg)
  else print("FAIL " .. msg); fails = fails + 1 end
end

local script = {
  [20] = { start = true }, [22] = {},
  [34] = { a = true }, [36] = { a = true, right = true }, [38] = {},
  [42] = { a = true }, [44] = { a = true, right = true }, [46] = {},
  [56] = { start = true }, [58] = {},
  [182] = { start = true }, [184] = {},
  [192] = { a = true }, [194] = { a = true, right = true }, [196] = {},
  [206] = { start = true }, [208] = {},
  [332] = { start = true }, [334] = {},
  [338] = { down = true }, [340] = {},
  [344] = { up = true }, [346] = {},
}

emu.addEventCallback(function() emu.setInput(pad, 0) end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if not booted then
    if wram(1) == 0x5D then booted = true end
    return
  end
  frames = frames + 1
  if script[frames] then pad = script[frames] end

  if frames == 26 then
    poke(0x2000, 0)
    poke(0x3700, 0); poke(0x3701, 0)
    poke(0x4300, 49); poke(0x4301, 0)
    poke(0x4302, 1); poke(0x4303, 0x47)
    poke(0x2401, 7); poke(0x2406, 0)
  elseif frames == 52 then
    check(wram(0x0C) == 1, "reached PHRASE for the first timing pass")
  elseif frames == 62 then
    run = "phrase"; last_pitch = pitch(); changes = 0; tick0 = wram(0x11)
  elseif frames == 178 then
    result.phrase = { changes, (wram(0x11) - tick0) % 256 }
    run = nil
  elseif frames == 202 then
    check(wram(0x0C) == 4, "reached INSTR for the second timing pass")
  elseif frames == 212 then
    run = "instr"; last_pitch = pitch(); changes = 0; tick0 = wram(0x11)
  elseif frames == 328 then
    result.instr = { changes, (wram(0x11) - tick0) % 256 }
    run = nil
  elseif frames == 342 then
    check(wram(0x91) == 1, "one Down press selected the next INSTR field")
    check((word(0x400 + 4 * 64 + 11 * 2) & 0xFC00) == 0x2400,
      "Down repainted the new INSTR cursor row")
  elseif frames == 348 then
    check(wram(0x91) == 0, "one Up press selected the previous INSTR field")
    check((word(0x400 + 3 * 64 + 11 * 2) & 0xFC00) == 0x2400,
      "Up repainted the new INSTR cursor row")
  elseif frames == 352 then
    local pc, pt = result.phrase[1], result.phrase[2]
    local ic, it = result.instr[1], result.instr[2]
    check(pc >= pt - 2,
      "PHRASE exposes each A47 tick (" .. pc .. " changes / " .. pt .. " ticks)")
    check(ic >= it - 2,
      "INSTR exposes each A47 tick (" .. ic .. " changes / " .. it .. " ticks)")
    check(math.abs(pc - ic) <= 2,
      "A47 runs at the same rate on PHRASE and INSTR")
    if fails == 0 then
      print("ALL PASS arp_screen.lua")
      emu.stop(0)
    else
      print("FAILED arp_screen.lua: " .. fails)
      emu.stop(1)
    end
  end

  if run then
    local q = pitch()
    if q ~= last_pitch then changes = changes + 1; last_pitch = q end
  end
end, emu.eventType.endFrame)
