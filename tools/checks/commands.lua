-- commands.lua — M7 gate: the command executor, one sub-test per command:
-- P K D G H A V L R T. Song data is poked directly into the WRAM song block
-- (the pad grammar is covered by the other suites); each test plays the song
-- from the SONG screen and asserts on DSP registers / engine state.

local frames = 0
local _booted = false
local fails = 0
local pad = {}
local W = emu.memType.snesWorkRam

local function wram(a) return emu.read(a, W) end
local function poke(a, v) emu.write(a, v, W) end
local function dsp(r) return emu.read(r, emu.memType.spcDspRegisters) end
local function pitch0() return dsp(0x02) + dsp(0x03) * 256 end

local function check(cond, msg)
  if cond then
    print("PASS " .. msg)
  else
    print("FAIL " .. msg)
    fails = fails + 1
  end
end

-- command ids
local CA, CD, CG, CH, CK, CL, CP, CR, CT, CV = 1, 4, 7, 8, 11, 12, 16, 18, 20, 22

local function clear_phrase(p)
  local base = 0x4300 + p * 64
  for r = 0, 15 do
    poke(base + r * 4, 0)
    poke(base + r * 4 + 1, 0xFF)
    poke(base + r * 4 + 2, 0)
    poke(base + r * 4 + 3, 0)
  end
end

local function row(p, r, note, instr, cmd, val)
  local base = 0x4300 + p * 64 + r * 4
  poke(base, note)
  poke(base + 1, instr)
  poke(base + 2, cmd)
  poke(base + 3, val)
end

-- the test schedule: list of {setup=fn, checks={[dt]=fn}, len=frames}
local tests = {}
local function T(name, setup, checks, len)
  tests[#tests + 1] = { name = name, setup = setup, checks = checks, len = len }
end

-- 1. P: hard-left pan
T("P", function()
  clear_phrase(0)
  row(0, 0, 49, 0, CP, 0x00)
end, {
  [14] = function()
    check(dsp(0x00) == 0x7F and dsp(0x01) == 0x00,
      "P00 pans hard left (VOLL=$" .. string.format("%02X", dsp(0x00)) ..
      " VOLR=$" .. string.format("%02X", dsp(0x01)) .. ")")
  end,
}, 24)

-- 2. K: kill after 4 ticks
T("K", function()
  clear_phrase(0)
  row(0, 0, 49, 0, CK, 12)
end, {
  [2] = function()
    check(dsp(0x08) > 0, "K: note sounds before the kill")
  end,
  [30] = function()
    check(dsp(0x08) == 0, "K12 killed the envelope (" .. dsp(0x08) .. ")")
  end,
}, 40)

-- 3. D: delayed trigger (within the row: the next row cancels a pending D)
T("D", function()
  clear_phrase(0)
  row(0, 0, 49, 0, 0, 0)        -- C-4 anchor
  row(0, 4, 61, 0xFF, CD, 4)    -- C-5 delayed 4 ticks (row 4 = tick ~24)
end, {
  [23] = function()
    check(pitch0() == 0x0800, "D: pitch still C-4 before the delay expires")
  end,
  [38] = function()
    check(pitch0() == 0x1000, "D04 triggered C-5 after the delay")
  end,
}, 50)

-- 4. G: groove select (groove 1 = 2 ticks/row)
T("G", function()
  for i = 0, 15 do poke(0x3010 + i, 2) end
  clear_phrase(0)
  row(0, 0, 49, 0, CG, 1)
end, {
  [20] = function() tests.g_row = wram(0x17) end,
  [36] = function()
    local d = (wram(0x17) - tests.g_row) % 16
    check(d >= 6 and d <= 10,
      "G01 doubled the row rate (16 frames -> " .. d .. " rows)")
  end,
}, 48)

-- 5. H: hop to the next chain entry
T("H", function()
  clear_phrase(0)
  clear_phrase(1)
  row(0, 0, 49, 0, CH, 0)
  row(1, 0, 61, 0xFF, 0, 0)
  poke(0x3702, 1)              -- chain 0 entry 1 = phrase 1
  poke(0x3703, 0)
end, {
  [20] = function()
    check(wram(0x28) == 1, "H hopped to the next chain entry (phrase 1)")
    check(pitch0() == 0x1000, "H: phrase 1's C-5 playing")
  end,
}, 32, function()
  poke(0x3702, 0xFF)           -- restore chain 0
  poke(0x3703, 0)
end)

-- 6. A: arpeggio 0/4/7
T("A", function()
  clear_phrase(0)
  row(0, 0, 49, 0, CA, 0x47)
  for r = 1, 15 do row(0, r, 0, 0xFF, CA, 0x47) end
end, {
  [20] = function()
    local seen, okset = {}, true
    tests.arp_probe = { seen = seen }
  end,
}, 44)

-- 7. V: vibrato
T("V", function()
  clear_phrase(0)
  row(0, 0, 49, 0, CV, 0x48)
  for r = 1, 15 do row(0, r, 0, 0xFF, CV, 0x48) end
end, {}, 44)

-- 8. L: slide C-4 -> C-5 (rate 16 = 64 units/tick: completes in 32 ticks,
-- well inside the 96-tick phrase loop that would otherwise restart it)
T("L", function()
  clear_phrase(0)
  row(0, 0, 49, 0, 0, 0)
  row(0, 8, 61, 0xFF, CL, 16)  -- row 8 (~tick 48): slide at 64 units/tick
end, {
  [56] = function()
    local p = pitch0()
    check(p > 0x0800 and p < 0x1000,
      "L: pitch mid-slide ($" .. string.format("%04X", p) .. ")")
    tests.l_mid = p
  end,
  [62] = function()
    local p = pitch0()
    check(p > tests.l_mid, "L: slide keeps rising")
  end,
  [88] = function()
    check(pitch0() == 0x1000, "L: slide reached C-5 exactly")
  end,
}, 92)

-- 9. R: retrigger every 3 ticks
T("R", function()
  clear_phrase(0)
  row(0, 0, 49, 0, CR, 3)
  for r = 1, 15 do row(0, r, 0, 0xFF, CR, 3) end
  tests.r_kons = wram(0x15)
end, {
  [60] = function()
    local d = (wram(0x15) - tests.r_kons) % 256
    check(d >= 12, "R03 retriggered repeatedly (" .. d .. " KON ticks)")
  end,
}, 70)

-- 10. T: tempo 240 (~96 Hz ticks) — last, since it retunes the timer
T("T", function()
  clear_phrase(0)
  row(0, 0, 49, 0, CT, 240)
end, {
  [20] = function() tests.t_row = wram(0x17) end,
  [50] = function()
    local d = (wram(0x17) - tests.t_row) % 16
    check(d >= 6 and d <= 10,
      "T240 sped the tick up (30 frames -> " .. d .. " rows, groove 6)")
  end,
}, 60)

-- A/V pitch sampling runs continuously during those tests
local arp_set = { [0x0800] = true, [0x0A14] = true, [0x0BFC] = true }
local arp_seen, arp_bad = {}, 0
local vib_lo, vib_hi = 0xFFFF, 0

-- scheduler
local cur, phase, t0 = 0, "boot", 0

emu.addEventCallback(function() emu.setInput(pad, 0) end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if not _booted then
    if emu.read(1, emu.memType.snesWorkRam) == 0x5D then _booted = true end
    return
  end
  frames = frames + 1
  if frames == 20 then pad = { start = true } end   -- splash -> SONG
  if frames == 22 then pad = {} end
  if frames == 26 then
    -- song scaffolding: V1 row0 = chain 0 -> phrase 0
    poke(0x2000, 0)
    poke(0x3700, 0)
    poke(0x3701, 0)
    cur = 1
    phase = "setup"
  end
  if cur == 0 or cur > #tests then
    if cur > #tests and phase ~= "done" then
      phase = "done"
      if fails == 0 then
        print("ALL PASS commands.lua")
        emu.stop(0)
      else
        print("FAILED commands.lua: " .. fails)
        emu.stop(1)
      end
    end
    return
  end

  local t = tests[cur]
  if phase == "setup" then
    t.setup()
    pad = { start = true }
    phase = "starting"
    t0 = frames + 2
  elseif phase == "starting" then
    if frames == t0 then
      pad = {}
      phase = "running"
    end
  elseif phase == "running" then
    local dt = frames - t0
    if t.checks[dt] then t.checks[dt]() end
    -- continuous sampling for A and V
    if t.name == "A" and dt >= 4 and dt <= 40 then
      local p = pitch0()
      if arp_set[p] then arp_seen[p] = true else arp_bad = arp_bad + 1 end
    end
    if t.name == "V" and dt >= 4 and dt <= 40 then
      local p = pitch0()
      if p < vib_lo then vib_lo = p end
      if p > vib_hi then vib_hi = p end
    end
    if dt >= t.len then
      if t.name == "A" then
        local n = 0
        for _ in pairs(arp_seen) do n = n + 1 end
        check(n >= 2 and arp_bad == 0, "A47 cycles chord pitches (" ..
          n .. " distinct, " .. arp_bad .. " strays)")
      end
      if t.name == "V" then
        check(vib_lo < 0x0800 and vib_hi > 0x0800, "V48 modulates around C-4")
        check(vib_lo >= 0x0700 and vib_hi <= 0x0900,
          "V48 depth bounded ($" .. string.format("%04X", vib_lo) .. "-$" ..
          string.format("%04X", vib_hi) .. ")")
      end
      pad = { start = true }   -- stop
      phase = "stopping"
      t0 = frames + 2
    end
  elseif phase == "stopping" then
    if frames == t0 then
      pad = {}
      phase = "gap"
      t0 = frames + 6
    end
  elseif phase == "gap" then
    if frames >= t0 then
      if tests[cur].name == "H" then
        poke(0x3702, 0xFF)     -- undo the H test's second chain entry
      end
      cur = cur + 1
      phase = "setup"
    end
  end
end, emu.eventType.endFrame)
