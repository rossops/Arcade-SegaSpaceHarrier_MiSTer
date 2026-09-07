-- Press Coin 1 for four frames starting at frame SH_COIN (for audio captures),
-- and 1P Start for four frames at SH_START if set. The coin lives in port
-- GENERAL on the Hang-On map and in SERVICE on the Space Harrier map.
local coin_frame = tonumber(os.getenv("SH_COIN") or "120")
local start_frame = tonumber(os.getenv("SH_START") or "-1")
local frame = 0
local field, sfield = nil, nil
local function find(name, mask)
    for _, pn in ipairs({":GENERAL", ":SERVICE"}) do
        local port = manager.machine.ioport.ports[pn]
        if port then
            if port.fields[name] then return port.fields[name] end
            for _, f in pairs(port.fields) do if f.mask == mask and pn == ":SERVICE" then return f end end
        end
    end
    return false
end
emu.register_frame_done(function()
    frame = frame + 1
    if field == nil then field = find("Coin 1", 0x01); sfield = find("1 Player Start", 0x10) end
    if field and frame >= coin_frame and frame < coin_frame + 4 then field:set_value(1) end
    if field and frame == coin_frame + 4 then field:set_value(0) end
    if sfield and start_frame > 0 and frame >= start_frame and frame < start_frame + 4 then sfield:set_value(1) end
    if sfield and start_frame > 0 and frame == start_frame + 4 then sfield:set_value(0) end
end)
