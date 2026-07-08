-- voice.lua — M3 gate: sample + directory uploaded to ARAM via the bulk
-- mailbox, DSP configured for voice 0, and auditioned notes land the right
-- KON + pitch register values (C-4 then E-4 from the cursor grid).

local frames = 0
local fails = 0
local pad = {}

local function wram(addr)
  return emu.read(addr, emu.memType.snesWorkRam)
end

local function dsp(reg)
  return emu.read(reg, emu.memType.spcDspRegisters)
end

local function aram(addr)
  return emu.read(addr, emu.memType.spcRam)
end

local function check(cond, msg)
  if cond then
    print("PASS " .. msg)
  else
    print("FAIL " .. msg)
    fails = fails + 1
  end
end

-- frame-scripted input: {frame, buttons}
local script = {
  [30] = { start = true },
  [32] = {},
  -- audition row 0 = C-4
  [40] = { b = true },
  [42] = {},
  -- two taps down -> row 2 (E-4)
  [50] = { down = true },
  [52] = {},
  [54] = { down = true },
  [56] = {},
  [60] = { b = true },
  [62] = {},
}

local function onPoll()
  emu.setInput(pad, 0)
end

local function onFrame()
  frames = frames + 1
  if script[frames] then
    pad = script[frames]
  end

  if frames == 25 then
    -- audio init landed via bulk upload + SCB writes
    check(dsp(0x5D) == 0x10, "DSP DIR points at ARAM directory page")
    check(dsp(0x6C) == 0x20, "DSP FLG unmuted, echo writes disabled")
    check(dsp(0x0C) == 0x60 and dsp(0x1C) == 0x60, "master volume set")
    check(dsp(0x05) == 0xAF and dsp(0x06) == 0xCA, "voice 0 ADSR configured")
    check(aram(0x1000) == 0x00 and aram(0x1001) == 0x12 and
          aram(0x1002) == 0x00 and aram(0x1003) == 0x12,
          "sample directory uploaded to ARAM $1000")
    -- BRR block 0: filter 0 forced, loop sample -> header nibble check +
    -- END+LOOP flags on the last of 8 blocks
    check(aram(0x1200 + 63 * 1) ~= nil and (aram(0x1200 + 7 * 9) & 0x03) == 0x03,
          "BRR sample in ARAM with END+LOOP flags")
    check(wram(0x0015) == 0, "no KONs yet")
  elseif frames == 48 then
    check(wram(0x0015) == 1, "first audition sent one KON")
    check(wram(0x0013) == 0x00 and wram(0x0014) == 0x08,
          "C-4 pitch $0800 recorded")
    check(dsp(0x02) == 0x00 and dsp(0x03) == 0x08, "DSP V0 pitch = C-4")
    check(dsp(0x4C) == 0x01, "KON hit voice 0")
  elseif frames == 70 then
    check(wram(0x000E) == 0 and wram(0x000F) == 2, "cursor moved to row 2")
    check(wram(0x0015) == 2, "second audition sent")
    -- E-4: round(16384 * 2^(4/12)) >> 3 = 20643 >> 3 = 2580 = $0A14
    check(wram(0x0013) == 0x14 and wram(0x0014) == 0x0A,
          "E-4 pitch $0A14 recorded")
    check(dsp(0x02) == 0x14 and dsp(0x03) == 0x0A, "DSP V0 pitch = E-4")
    -- envelope must actually be running (voice audibly alive)
    check(dsp(0x08) > 0, "V0 ENVX shows a live envelope (" .. dsp(0x08) .. ")")
    if fails == 0 then
      print("ALL PASS voice.lua")
      emu.stop(0)
    else
      print("FAILED voice.lua: " .. fails)
      emu.stop(1)
    end
  end
end

emu.addEventCallback(onFrame, emu.eventType.endFrame)
emu.addEventCallback(onPoll, emu.eventType.inputPolled)
