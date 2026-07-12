-- shot.lua — headless screenshot for `make shot` / goldens.
-- Waits for boot (magic_boot) plus a settle delay deep inside the
-- PRESS-START blink window, then writes a PNG and exits.

local out = os.getenv("SNDJ_SHOT") or "build/shot.png"
local settle = tonumber(os.getenv("SNDJ_SHOT_FRAME") or "48")
local booted = false
local frames = 0

-- Screenshot runs share Mesen's battery file with the emulator suites.
-- Always render the canonical scheme 0 rather than the last tested option.
emu.write(0x0007, 0, emu.memType.snesSaveRam)

emu.addEventCallback(function()
  if not booted then
    if emu.read(1, emu.memType.snesWorkRam) == 0x5D then booted = true end
    return
  end
  frames = frames + 1
  if frames == settle then
    local png = emu.takeScreenshot()
    local f = io.open(out, "wb")
    f:write(png)
    f:close()
    print("shot: " .. out .. " (" .. #png .. " bytes)")
    emu.stop(0)
  end
end, emu.eventType.endFrame)
