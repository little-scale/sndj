-- livecue.lua — LIVE cue/stop lifecycle + the boot-pending regression.
--
-- Regression (2026-07-12): trk_pending is boot-zeroed WRAM and 0 is a
-- valid chain id, so the FIRST launch after power-on read "chain 0
-- queued" on every track and started all eight. live_pending_reset now
-- seeds $FF at boot and on engine_stop.
--
-- Also gates the new semantics: a chain queued on a HALTED track fires
-- at the next bar boundary (16 rows); B on an EMPTY cell of a playing
-- track — or on the cell the track is PLAYING (don't re-trigger the
-- chain you're hearing) — queues a STOP ($FE) that drains at the
-- phrase boundary.
--
-- Non-frozen addresses (src/ram.inc): $E8 trk_pending, $C00 trk_live_row,
-- $C08 trk_pend_row, $20 trk_chain, $28 trk_phrase.

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

gest({ start = true }, 4)            -- splash -> SONG
gest({ select = true }, 6)           -- LIVE
gest({ b = true }, 8)                -- launch chain 0 on V1 (cursor 0,0)
local launched = t
gest({ down = true }, 2)             -- cursor -> row 2
gest({ down = true }, 2)
for _ = 1, 7 do gest({ right = true }, 2) end  -- cursor -> track 8
gest({ b = true }, 4)                -- cue chain 2 on HALTED V8
local cued = t
local fire_until = cued + 220        -- a bar is 16 rows (~2 phrase lengths)
t = fire_until + 4
script[t] = { down = true } ; t = t + 2 ; script[t] = {} ; t = t + 2
script[t] = { b = true } ; t = t + 2 ; script[t] = {} ; t = t + 4
local stopped_q = t
local drain_until = stopped_q + 220
t = drain_until + 4
script[t] = { start = true } ; t = t + 2 ; script[t] = {} ; t = t + 6
local stopped_chk = t + 4
t = stopped_chk + 2
for _ = 1, 3 do gest({ up = true }, 2) end     -- cursor back to (0,0)
for _ = 1, 7 do gest({ left = true }, 2) end
gest({ b = true }, 8)                -- relaunch chain 0 on V1
local relaunched = t
gest({ b = true }, 4)                -- B on the PLAYING cell = stop it
local selfstop = t
local drain2_until = selfstop + 220
t = drain2_until + 4
local done = t

local fired_frame, fired_pending = nil, nil
local drained_frame = nil
local selfdrain_frame = nil

emu.addEventCallback(function() emu.setInput(pad, 0) end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if not _booted then
    if emu.read(1, W) == 0x5D then _booted = true end
    return
  end
  frames = frames + 1
  if script[frames] then pad = script[frames] end

  if frames == 20 then
    -- t1 r0 = chain 0 (phrase 0); t8 r0 = chain 1, r2 = chain 2
    poke(0x2000, 0)
    poke(0x2380, 1)
    poke(0x2382, 2)
    poke(0x3700, 0)
    poke(0x3720, 1)
    poke(0x3740, 2)
    poke(0x4300, 49) poke(0x4301, 0)   -- phrase 0: C-4
    poke(0x4340, 52) poke(0x4341, 0)   -- phrase 1: D#4
    poke(0x4380, 56) poke(0x4381, 0)   -- phrase 2: G-4
  elseif frames == launched then
    check(wram(0x16) == 1, "first-boot B launched the transport")
    check(wram(0x28) == 0, "track 1 playing phrase 0")
    local others_halted = true
    for tr = 1, 7 do
      if wram(0x28 + tr) ~= 0xFF then others_halted = false end
    end
    check(others_halted,
      "REGRESSION: only the queued track launched (boot pendings = $FF)")
  elseif frames == cued then
    check(wram(0xE8 + 7) == 2, "chain 2 queued on halted track 8")
    check(wram(0xC08 + 7) == 2, "cue row recorded for the flash marker")
    check(wram(0x2F) == 0xFF, "track 8 still halted until the bar")
  elseif frames > cued and frames <= fire_until then
    if fired_frame == nil and wram(0x2F) ~= 0xFF then
      fired_frame = frames
      fired_pending = wram(0xE8 + 7)
    end
  elseif frames == fire_until + 2 then
    check(fired_frame ~= nil, "halted-track cue fired at a bar boundary")
    if fired_frame then
      check(wram(0x27) == 2, "track 8 adopted chain 2")
      check(wram(0xC00 + 7) == 2, "playhead moved to the launched cell")
      check(fired_pending == 0xFF, "pending slot cleared on fire")
    end
  elseif frames == stopped_q then
    check(wram(0xE8 + 7) == 0xFE, "B on an empty cell queued a STOP")
  elseif frames > stopped_q and frames <= drain_until then
    if drained_frame == nil and wram(0x2F) == 0xFF then
      drained_frame = frames
    end
  elseif frames == drain_until + 2 then
    check(drained_frame ~= nil, "queued stop drained at the boundary")
    check(wram(0xE8 + 7) == 0xFF, "stop consumed the pending slot")
    check(wram(0x28) == 0, "track 1 kept playing through it all")
    poke(0xE8 + 2, 5)          -- stale cue: engine_stop must clear it
  elseif frames == stopped_chk then
    check(wram(0x16) == 0, "Start stopped the transport")
    check(wram(0xE8 + 2) == 0xFF, "engine_stop cleared stale pendings")
  elseif frames == relaunched then
    check(wram(0x16) == 1 and wram(0x28) == 0,
      "relaunched chain 0 on track 1")
  elseif frames == selfstop then
    check(wram(0xE8) == 0xFE, "B on the playing cell queued its stop")
  elseif frames > selfstop and frames <= drain2_until then
    if selfdrain_frame == nil and wram(0x28) == 0xFF then
      selfdrain_frame = frames
    end
  elseif frames == done then
    check(selfdrain_frame ~= nil, "playing-cell stop drained the track")
    check(wram(0x16) == 1, "transport kept running (track-level stop)")
    if fails == 0 then
      print("ALL PASS livecue.lua")
      emu.stop(0)
    else
      print("FAILED livecue.lua: " .. fails)
      emu.stop(1)
    end
  end
end, emu.eventType.endFrame)
