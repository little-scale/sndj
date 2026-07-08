-- live.lua — M13 gate: LIVE launches chains quantised to phrase
-- boundaries, mute/solo via the X modifier silences voices, ENVX
-- telemetry reaches the CPU mirror, Select round-trips LIVE.
--
-- Non-frozen addresses (from src/ram.inc): $E0 trk_pending, $E8 trk_mute,
-- $E9 envx_mirror, $20 trk_chain, $30 trk_prow.

local frames = 0
local _booted = false
local fails = 0
local pad = {}
local W = emu.memType.snesWorkRam

local function wram(a) return emu.read(a, W) end
local function poke(a, v) emu.write(a, v, W) end

local function check(cond, msg)
  if cond then
    print("PASS " .. msg)
  else
    print("FAIL " .. msg)
    fails = fails + 1
  end
end

local script = {}
local t = 30
local function gest(b, gap) script[t]=b; t=t+2; script[t]={}; t=t+(gap or 2) end

gest({ start = true }, 4)          -- SONG
gest({ select = true }, 6)         -- LIVE
local at_live = t
gest({ b = true }, 8)              -- launch chain 0 on V1 (immediate: stopped)
local launched = t
gest({ down = true }, 4)           -- cursor to row 1 (chain 1)
gest({ b = true }, 4)              -- queue chain 1 (quantised)
local queued = t
-- watch for the boundary switch during the next ~120 frames
local watch_until = t + 130
t = watch_until + 4
gest({ x = true, down = true }, 4) -- mute V1
local muted = t - 2
gest({ x = true, right = true }, 4) -- solo V1 (mute = $FE)
local soloed = t - 2
gest({ x = true, right = true }, 4) -- solo again -> clear
local cleared = t - 2
gest({ start = true }, 6)          -- stop
gest({ select = true }, 6)         -- back to SONG
local done = t + 4

local switch_frame, switch_prow = nil, nil
local mute_seq = {}
local envx_seen = false

emu.addEventCallback(function() emu.setInput(pad, 0) end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if not _booted then
    if emu.read(1, W) == 0x5D then _booted = true end
    return
  end
  frames = frames + 1
  if script[frames] then pad = script[frames] end

  if frames == 20 then
    -- song data: chain0 -> phrase0 (C-4s), chain1 -> phrase1 (C-5s)
    poke(0x2000, 0)          -- grid row 0 = chain 0
    poke(0x2001, 1)          -- grid row 1 = chain 1
    poke(0x3700, 0)
    poke(0x3720, 1)
    poke(0x4300, 49)         -- phrase0 r0
    poke(0x4301, 0)
    poke(0x4340, 61)         -- phrase1 r0
    poke(0x4341, 0)
  elseif frames == at_live then
    check(wram(0x0C) == 8, "Select opened LIVE")
  elseif frames == launched then
    check(wram(0x16) == 1, "B launched immediately from stopped")
    check(wram(0x20) == 0, "track 0 playing chain 0")
  elseif frames == queued then
    check(wram(0xE1) == 1, "chain 1 queued on track 0")
    check(wram(0x20) == 0, "still on chain 0 until the boundary")
  elseif frames > queued and frames <= watch_until then
    if wram(0x0E) ~= nil and envx_seen == false and wram(0xEA) > 0 then
      envx_seen = true
    end
    if switch_frame == nil and wram(0x20) == 1 then
      switch_frame = frames
      switch_prow = wram(0x30)
    end
  elseif frames == watch_until + 2 then
    check(switch_frame ~= nil, "queued chain launched")
    if switch_frame then
      check(switch_prow <= 1, "launch quantised to the phrase boundary " ..
        "(prow=" .. switch_prow .. " at switch)")
      check(switch_frame - queued > 30, "launch waited for the boundary (" ..
        (switch_frame - queued) .. " frames)")
      check(wram(0xE1) == 0xFF, "pending slot cleared")
    end
    -- ENVX itself reads as 0 in Mesen (emulator limitation; the same
    -- driver path verifiably round-trips FLG). Hardware-verify item.
    print("info: ENVX meters are a hardware-verify item (Mesen reads 0); " ..
      "seen=" .. tostring(envx_seen))
  elseif frames > muted - 10 and frames < done - 2 then
    local m = wram(0xE9)
    if #mute_seq == 0 or mute_seq[#mute_seq] ~= m then
      mute_seq[#mute_seq + 1] = m
    end

    local out = os.getenv("SNESDJ_LIVE_SHOT")
    if out then
      local png = emu.takeScreenshot()
      local f = io.open(out, "wb")
      f:write(png)
      f:close()
    end
  elseif frames == done then
    -- mute grammar: validate the transition sequence (timing-independent)
    local want = { 0x01, 0xFE, 0x00 }
    local wi = 1
    for _, v in ipairs(mute_seq) do
      if v == want[wi] then wi = wi + 1 end
    end
    check(wi == 4, "X mute -> solo -> clear sequence observed (" ..
      table.concat(mute_seq, ",") .. ")")
    check(wram(0x0C) == 3, "Select returned to the previous screen")
    if fails == 0 then
      print("ALL PASS live.lua")
      emu.stop(0)
    else
      print("FAILED live.lua: " .. fails)
      emu.stop(1)
    end
  end
end, emu.eventType.endFrame)
