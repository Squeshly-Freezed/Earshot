-- Test.lua: /earshot test plays a short tune as if someone stood just in front of you.
local _, ns = ...

local FILE = [[Interface\AddOns\Earshot\Media\Test.mp3]]
local LENGTH = 32 -- seconds
local handle, session

local function Finish()
    -- Only end the placement if it's still the test's: a Spoken line may have taken over.
    if session and ns.Spatial.session == session then ns.Spatial:End() end
    handle, session = nil, nil
end

function ns.Test()
    if handle then
        StopSound(handle)
        if session and ns.Spatial.session == session then ns.Spatial:Clear() end
        handle, session = nil, nil
        ns.Print("Test stopped.")
        return
    end
    if not ns.db.enabled then
        ns.Print("Earshot is switched off. Type /earshot on first.")
        return
    end
    local spot = ns.Anchors:Here(3, true)
    if not spot then
        ns.Print("The game hides your position here (dungeons, raids, battlegrounds and arenas). Try it outdoors.")
        return
    end
    -- Use the slider Spoken plays on, so the test sounds the way your voices will.
    local channel = ns.SpokenLink:Channel()
    if not ns.Volume:IsMovable(channel) then channel = "Ambience" end
    local willPlay, newHandle = PlaySoundFile(FILE, channel)
    if not willPlay then
        ns.Print("Couldn't play the test on %s. Is that sound switched off in the game's Sound settings?",
            ns.CHANNEL_NAMES[channel])
        return
    end
    handle = newHandle
    if ns.Spatial:Begin(spot, channel, { kind = "test" }) then
        session = ns.Spatial.session
        ns.Print("A tune is playing a few steps in front of you, on %s. Walk away and turn around: it fades, "
            .. "and goes softer behind you. Type /earshot test again to stop.", ns.CHANNEL_NAMES[channel])
    else
        ns.Print("Playing, but Earshot can't move %s (is it at 0?).", ns.CHANNEL_NAMES[channel])
    end
    local this = handle
    C_Timer.After(LENGTH, function()
        if handle == this then Finish() end
    end)
end
