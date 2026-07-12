-- Core checks exercise engine behavior independently of the current factory's
-- storage tuning. The emulator gets a private ROM image, so neutralizing pool
-- tune metadata here never changes the built ROM. factory.lua runs separately
-- against the untouched image and verifies the real factory path.
local R = emu.memType.snesPrgRom
local POOL = 0x8006
local count = emu.read(POOL + 9, R)

-- Mesen persists battery RAM between suites. Pin visual checks to the default
-- black scheme; palette.lua still changes and verifies persistence in-process.
emu.write(0x0007, 0, emu.memType.snesSaveRam)

for i = 0, count - 1 do
  emu.write(POOL + 16 + i * 16 + 14, 0, R)
  emu.write(POOL + 16 + i * 16 + 15, 0, R)
end

dofile(os.getenv("SNDJ_CHECK"))
