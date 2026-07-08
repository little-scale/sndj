-- shot.lua — headless screenshot for `make shot` / goldens.
-- Waits for the splash to settle, then writes a PNG to the path in the
-- SNESDJ_SHOT env var (default build/shot.png) and exits.

local out = os.getenv("SNESDJ_SHOT") or "build/shot.png"
local target = tonumber(os.getenv("SNESDJ_SHOT_FRAME") or "60")
local frames = 0

emu.addEventCallback(function()
  frames = frames + 1
  if frames == target then
    local png = emu.takeScreenshot()
    local f = io.open(out, "wb")
    f:write(png)
    f:close()
    print("shot: " .. out .. " (" .. #png .. " bytes)")
    emu.stop(0)
  end
end, emu.eventType.endFrame)
