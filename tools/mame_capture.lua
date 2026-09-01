-- MAME autoboot script: at frame SH_FRAME dump the segahang video RAMs and
-- take a screenshot, then exit. Configure through environment variables
-- SH_FRAME (frame number) and SH_OUT (output directory). The RAM addresses
-- are the hangon map; the sharrier map arrives with M7 (SH_MAP=sharrier).
local frame_target = tonumber(os.getenv("SH_FRAME") or "300")
local outdir = os.getenv("SH_OUT") or "."
local sharrier_map = os.getenv("SH_MAP") == "sharrier"
local frame = 0
local done = false

local function dump(space, base, words, path)
    local f = io.open(path, "wb")
    for i = 0, words - 1 do
        local w = space:read_u16(base + i * 2)
        f:write(string.char(w & 0xff, (w >> 8) & 0xff))
    end
    f:close()
end

local test_mode = os.getenv("SH_TEST") == "1"
local test_from = tonumber(os.getenv("SH_TEST_FRAME") or "1")   -- the game wants an edge during the attract
local test_field = nil
-- optional presses, for captures of the game in play (verif/board +coin/+start)
local coin_frame = tonumber(os.getenv("SH_COIN") or "-1")
local start_frame = tonumber(os.getenv("SH_START") or "-1")
local coin_field, start_field = nil, nil

emu.register_frame_done(function()
    frame = frame + 1
    if coin_field == nil then
        local port = manager.machine.ioport.ports[":SERVICE"]
        coin_field = port and port.fields["Coin 1"] or false
        start_field = port and port.fields["1 Player Start"] or false
    end
    if coin_field and coin_frame >= 0 then
        if frame >= coin_frame and frame < coin_frame + 4 then coin_field:set_value(1) end
        if frame == coin_frame + 4 then coin_field:set_value(0) end
    end
    if start_field and start_frame >= 0 then
        if frame >= start_frame and frame < start_frame + 4 then start_field:set_value(1) end
        if frame == start_frame + 4 then start_field:set_value(0) end
    end
    if test_mode then
        if test_field == nil then
            local port = manager.machine.ioport.ports[":SERVICE"]
            test_field = port and port.fields["Service Mode"] or false
        end
        if test_field and frame >= test_from then test_field:set_value(tonumber(os.getenv("SH_TEST_VAL") or "1")) end
    end
    if done or frame < frame_target then return end
    done = true
    local main = manager.machine.devices[":maincpu"].spaces["program"]
    if sharrier_map then
        dump(main, 0x100000, 0x4000, outdir .. "/tileram.bin")   -- 32 KB mapped; pages 0-3 in the first half
        dump(main, 0x108000, 0x800,  outdir .. "/textram.bin")
        dump(main, 0x110000, 0x800,  outdir .. "/paletteram.bin")
        dump(main, 0x130000, 0x800,  outdir .. "/spriteram.bin")
    else
        dump(main, 0x20C000, 0x2000, outdir .. "/workram.bin")
        dump(main, 0x400000, 0x2000, outdir .. "/tileram.bin")
        dump(main, 0x410000, 0x800,  outdir .. "/textram.bin")
        dump(main, 0xA00000, 0x800,  outdir .. "/paletteram.bin")
        dump(main, 0x600000, 0x400,  outdir .. "/spriteram.bin")
    end
    dump(main, 0xC68000, 0x800, outdir .. "/roadram.bin")
    -- PPI0 port B/C drive the video path (flip, shade, display enable,
    -- tilemap row/column scroll enables); read the latches back
    local f = io.open(outdir .. "/ppi.txt", "w")
    f:write(string.format("%d\n%d\n", main:read_u8(0xE00003), main:read_u8(0xE00005)))
    f:close()
    f = io.open(outdir .. "/frame.txt", "w"); f:write(tostring(frame) .. "\n"); f:close()
    manager.machine.video:snapshot()
    manager.machine:exit()
end)
