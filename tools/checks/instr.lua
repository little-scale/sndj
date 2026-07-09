-- instr.lua — M6 gate: INSTR screen edits the instrument record, and a GRP
-- span renders a 3-voice chord (root+4+7 semitones) from ONE phrase column.
--
-- Path: SONG -> chain 00 -> phrase 00 (note C-4, instr 00) -> INSTR:
-- GRP=2, OFS1=4, OFS2=7 -> play phrase -> voices 0/1/2 = C-4/E-4/G-4.

local frames = 0
local _booted = false
local fails = 0
local pad = {}
local env_peak = { 0, 0, 0 }

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

-- build the input script with a tiny sequencer
local script = {}
local t = 30
local function gest(buttons, hold)
  script[t] = buttons
  t = t + (hold or 2)
  script[t] = {}
  t = t + 2
end
local function chord(buttons)  -- keep B held across a d-pad tap
  script[t] = { b = true }
  t = t + 2
  for k, v in pairs(buttons) do script[t] = { b = true, [k] = v } end
  t = t + 2
  script[t] = { b = true }
  t = t + 2
  script[t] = {}
  t = t + 2
end

gest({ start = true })                    -- SONG
gest({ b = true })                        -- chain 00
gest({ a = true, right = true })          -- CHAIN
gest({ b = true })                        -- phrase 00
gest({ a = true, right = true })          -- PHRASE
gest({ b = true })                        -- note C-4 at row 0
gest({ right = true })                    -- instr column
gest({ b = true })                        -- instr 00 at row 0
gest({ a = true, right = true })          -- INSTR
local at_instr = t
for _ = 1, 8 do gest({ down = true }) end -- field 8 = GRP
chord({ right = true })                   -- GRP 0 -> 1
chord({ right = true })                   -- GRP 1 -> 2
gest({ down = true })                     -- OFS1
chord({ up = true })                      -- +4
gest({ down = true })                     -- OFS2
chord({ up = true })                      -- +4
chord({ right = true })                   -- +1
chord({ right = true })                   -- +1
chord({ right = true })                   -- +1 -> 7
local shot_at = t - 2
local after_edit = t + 4
gest({ a = true, left = true })           -- back to PHRASE
local at_phrase = t + 2
gest({ start = true })                    -- play (phrase mode)
local playing = t + 12
t = playing + 4
gest({ start = true })                    -- stop
local done = t + 6

emu.addEventCallback(function() emu.setInput(pad, 0) end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if not _booted then
    if emu.read(1, emu.memType.snesWorkRam) == 0x5D then _booted = true end
    return
  end
  frames = frames + 1
  if script[frames] then pad = script[frames] end
  if frames > at_phrase then
    for i, r in ipairs({ 0x08, 0x18, 0x28 }) do
      if dsp(r) > env_peak[i] then env_peak[i] = dsp(r) end
    end
  end

  if frames == at_instr then
    check(wram(0x000C) == 4, "A+Right opened INSTR from the phrase row")
    check(wram(0x4301) == 0, "phrase row 0 instrument = 00")
    check(wram(0x2402) == 0x2F and wram(0x2403) == 0xCA,
      "factory instrument ADSR present")
    -- exact-pitch asserts below need a zero-tune sample (factory melodics
    -- carry loop-quantise tune corrections now)
    emu.write(0x2401, 23, emu.memType.snesWorkRam)
  elseif frames == shot_at then
    local out = os.getenv("SNDJ_INSTR_SHOT")
    if out then
      local png = emu.takeScreenshot()
      local f = io.open(out, "wb")
      f:write(png)
      f:close()
      print("info: instr screenshot -> " .. out)
    end
  elseif frames == after_edit then
    check(wram(0x2408) == 2, "GRP span = 2")
    check(wram(0x2409) == 4, "OFS1 = 4 semitones")
    check(wram(0x240A) == 7, "OFS2 = 7 semitones")
  elseif frames == at_phrase + 2 then
    check(wram(0x000C) == 1, "back on PHRASE")
  elseif frames == playing - 8 then
    -- 8 kHz one-shots at chord pitches are short: peaks tracked per frame
    check(env_peak[1] > 0 and env_peak[2] > 0 and env_peak[3] > 0,
      "three envelopes alive (peaks " .. env_peak[1] .. "/" ..
      env_peak[2] .. "/" .. env_peak[3] .. ")")
  elseif frames == playing then
    check(wram(0x0016) == 1, "playing")
    check(dsp(0x4C) & 0x07 == 0x07, "KON hit voices 0+1+2 ($" ..
      string.format("%02X", dsp(0x4C)) .. ")")
    local p0 = dsp(0x02) + dsp(0x03) * 256
    local p1 = dsp(0x12) + dsp(0x13) * 256
    local p2 = dsp(0x22) + dsp(0x23) * 256
    check(p0 == 0x0800, "voice 0 = C-4 ($" .. string.format("%04X", p0) .. ")")
    check(p1 == 0x0A14, "voice 1 = E-4 ($" .. string.format("%04X", p1) .. ")")
    check(p2 == 0x0BFC, "voice 2 = G-4 ($" .. string.format("%04X", p2) .. ")")
    -- sample 23 is boot-resident via kit 0; its SRCN comes from the
    -- residency map, not a fixed order
    local srcn = wram(0x0097 + 23)
    check(srcn > 0 and dsp(0x04) == srcn and dsp(0x14) == srcn and
      dsp(0x24) == srcn,
      "GRP members use the resident sample (SRCN " .. srcn .. ")")
  elseif frames == done then
    if fails == 0 then
      print("ALL PASS instr.lua")
      emu.stop(0)
    else
      print("FAILED instr.lua: " .. fails)
      emu.stop(1)
    end
  end
end, emu.eventType.endFrame)
