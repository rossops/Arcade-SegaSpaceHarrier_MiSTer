-- MAME autoboot script: measure a game's update cadence (M11). Each frame
-- in the window, hash the sprite list and print CHANGED/SAME - a game that
-- overruns the frame shows an irregular 1-2 frame cadence (endurord's
-- attract demo does, measured 2026-09-01). Configure with SH_FROM/SH_TO
-- (frame window) and SH_SPRBASE (0x130000 sharrier map, 0x600000 hangon).
local from = tonumber(os.getenv("SH_FROM") or "1200")
local to   = tonumber(os.getenv("SH_TO") or "1260")
local base = tonumber(os.getenv("SH_SPRBASE") or "0x130000")
local frame = 0
local mem = manager.machine.devices[":maincpu"].spaces["program"]
local last = nil
emu.register_frame_done(function()
    frame = frame + 1
    if frame >= from and frame <= to then
        local h = 0
        for a = base, base + 0x3ff, 4 do
            h = (h * 33 + mem:read_u32(a)) % 4294967291
        end
        print(string.format("f%d %s", frame, (h == last) and "SAME" or "CHANGED"))
        last = h
    end
    if frame > to then manager.machine:exit() end
end)
