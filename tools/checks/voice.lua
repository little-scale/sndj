-- voice.lua — M3 gate: sample + directory uploaded to ARAM via the bulk
-- mailbox, DSP configured for voice 0, and auditioned notes land the right
-- KON + pitch register values (C-4 then E-4 from the cursor grid).

local frames = 0
local envx_peak = 0
local _booted = false
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

-- frame-scripted input: B tap inserts C-4 (auditions), then four B+Right
-- nudges walk the note up to E-4, auditioning each step
local script = {
  [30] = { start = true }, [32] = {},          -- SONG
  [36] = { b = true }, [38] = {},              -- insert chain 00
  [42] = { a = true }, [44] = { a = true, right = true }, [46] = {},  -- CHAIN
  [50] = { b = true }, [52] = {},              -- insert phrase 00
  [56] = { a = true }, [58] = { a = true, right = true }, [60] = {},  -- PHRASE
  [64] = { b = true }, [66] = {},              -- insert C-4 (audition)
  [70] = { b = true },
  [72] = { b = true, right = true },
  [74] = { b = true },
  [76] = { b = true, right = true },
  [78] = { b = true },
  [80] = { b = true, right = true },
  [82] = { b = true },
  [84] = { b = true, right = true },
  [86] = { b = true },
  [88] = {},
}

local function onPoll()
  emu.setInput(pad, 0)
end

local function onFrame()
  if not _booted then
    if emu.read(1, emu.memType.snesWorkRam) == 0x5D then _booted = true end
    return
  end
  frames = frames + 1
  local e = dsp(0x08)
  if e > envx_peak then envx_peak = e end
  if script[frames] then
    pad = script[frames]
  end

  if frames == 25 then
    -- audio init landed via bulk upload + SCB writes
    check(dsp(0x5D) == 0x10, "DSP DIR points at ARAM directory page")
    check(dsp(0x0C) == 0x60 and dsp(0x1C) == 0x60, "master volume set")
    check(dsp(0x05) == 0xAF and dsp(0x06) == 0xCA, "voice 0 ADSR configured")
    check(aram(0x1000) == 0x00 and aram(0x1001) == 0x12 and
          aram(0x1002) == 0x00 and aram(0x1003) == 0x12,
          "sample directory uploaded to ARAM $1000")
    -- resident sample 1 (SF2 00 at $1209): END+LOOP on its last block
    -- (block count read from the ROM pool table so retunes don't break this)
    local rom = function(a) return emu.read(a, emu.memType.snesPrgRom) end
    local blocks = rom(0x8006 + 16 + 10) + rom(0x8006 + 16 + 11) * 256
    check((aram(0x1209 + (blocks - 1) * 9) & 0x03) == 0x03,
          "BRR sample in ARAM with END+LOOP flags (" .. blocks .. " blocks)")
    check(wram(0x0015) == 0, "no KONs yet")
    -- zero-tune sample (SW ORCH) so the pitch asserts stay table-exact
    emu.write(0x2401, 12, emu.memType.snesWorkRam)
  elseif frames == 68 then
    check(wram(0x000C) == 1, "navigated SONG -> CHAIN -> PHRASE")
    check(dsp(0x6C) == 0x20, "DSP FLG unmuted, echo idle at EDL 0")
    check(wram(0x0015) == 1, "first audition sent one KON")
    check(wram(0x0013) == 0x00 and wram(0x0014) == 0x08,
          "C-4 pitch $0800 recorded")
    check(dsp(0x02) == 0x00 and dsp(0x03) == 0x08, "DSP V0 pitch = C-4")
    check(dsp(0x4C) == 0x01, "KON hit voice 0")
  elseif frames == 95 then
    check(wram(0x4300) == 53, "four nudges wrote E-4 (note 53) to row 0")
    check(wram(0x0015) == 5, "each nudge auditioned (5 KONs)")
    -- E-4: round(16384 * 2^(4/12)) >> 3 = 20643 >> 3 = 2580 = $0A14
    check(wram(0x0013) == 0x14 and wram(0x0014) == 0x0A,
          "E-4 pitch $0A14 recorded")
    check(dsp(0x02) == 0x14 and dsp(0x03) == 0x0A, "DSP V0 pitch = E-4")
    -- envelope must have run (peak tracked per frame; 16 kHz drums decay
    -- fast at melodic pitches, so a point sample can miss it)
    check(envx_peak > 0, "V0 ENVX showed a live envelope (peak " .. envx_peak .. ")")
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
