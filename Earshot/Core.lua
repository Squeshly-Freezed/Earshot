-- Earshot: NPC voices fade as you walk away from whoever is talking, and soften when
-- the speaker is behind you.
--
-- How it works: WoW plays addon sounds flat, with no place in the world, and an addon
-- can't set the volume of a single sound. It can set a volume slider. So while a voice
-- plays, Earshot works out how far you are from the speaker and which way you face, and
-- moves the slider that voice plays on. When the voice ends the slider goes back to
-- where you had it.
local ADDON, ns = ...

ns.DEFAULTS = {
    enabled = true,
    full = 10,      -- yards: full volume this close to the speaker
    silent = 45,    -- yards: silent from this far away
    behind = 65,    -- percent: how loud a speaker directly behind you sounds
    floor = 0,      -- percent: a placed voice never gets quieter than this
    quests = true,  -- place quest and gossip voices
    chatter = true, -- place world chatter
    chatterRange = 45, -- yards: chatter fades out by this far from where it was said
    yellRange = 120,   -- yards: the same for yells (ns.YELLS_ANYWHERE: yells aren't faded)
    away = "quiet", -- when you walk out of earshot: quiet, skip, skipNpc, skipAll or wait (see SpokenLink)
    markers = true, -- mark the NPC that's talking (on its nameplate)
    markSilent = true, -- also NPCs talking in chat without a voice
}

-- The slider ranges on the settings page. Saved numbers outside them are pulled back in.
ns.LIMITS = {
    full = { 3, 30 },
    silent = { 15, 100 },
    behind = { 0, 100 },
    floor = { 0, 50 },
    chatterRange = { 20, 100 },
    yellRange = { 60, 300 },
}
ns.YELLS_ANYWHERE = 300 -- the top of the yell slider: yells play as normal

-- Settings with a fixed set of values. A saved value that isn't one goes back to the default.
ns.CHOICES = {
    away = { quiet = true, skip = true, skipNpc = true, skipAll = true, wait = true },
}

-- Presets set the distance sliders together. Natural is the defaults.
ns.PRESETS = {
    { key = "subtle", name = "Subtle", full = 15, silent = 70, behind = 80, chatterRange = 70,
        tooltip = "Voices fade slowly and stay fairly loud behind you." },
    { key = "natural", name = "Natural", full = 10, silent = 45, behind = 65, chatterRange = 45,
        tooltip = "Roughly how far a speaking voice carries outdoors." },
    { key = "dramatic", name = "Dramatic", full = 6, silent = 30, behind = 40, chatterRange = 30,
        tooltip = "Voices fall away quickly, and a speaker behind you is much quieter." },
}

--- Full volume within this many yards for chatter or yells heard up to `range` yards.
function ns.NearPart(range)
    return math.max(3, math.floor(range * 0.45 + 0.5))
end

-- Midnight-era clients can hand addons "secret" values that may not be compared or
-- used in maths. Nothing read here should be secret, but treat one as missing rather
-- than throw an error.
local issecretvalue = issecretvalue or function() return false end
function ns.Plain(value)
    if value == nil or issecretvalue(value) then return nil end
    return value
end
local Plain = ns.Plain

-- Where you stand: north and west in yards, and which world you're in. nil in
-- dungeons, raids, battlegrounds and arenas, where the game hides positions from addons.
function ns.PlayerPosition()
    local north, west, _, instance = UnitPosition("player")
    north, west = Plain(north), Plain(west)
    if not north or not west then return nil end
    return north, west, Plain(instance)
end

-- The way your character faces: radians, 0 = north, counterclockwise. nil where hidden.
function ns.PlayerFacing()
    return Plain(GetPlayerFacing())
end

function ns.Print(text, ...)
    if select("#", ...) > 0 then text = text:format(...) end
    DEFAULT_CHAT_FRAME:AddMessage("|cff8fd0ffEarshot:|r " .. text)
end

-- Spoken catches errors thrown inside its callbacks and files them away quietly.
-- Wrapping our handlers sends them to the normal error window instead.
function ns.Guard(fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then geterrorhandler()(err) end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name == ADDON then
            if type(EarshotDB) ~= "table" then EarshotDB = {} end
            for key, value in pairs(ns.DEFAULTS) do
                if type(EarshotDB[key]) ~= type(value) then EarshotDB[key] = value end
            end
            for key, range in pairs(ns.LIMITS) do
                EarshotDB[key] = math.min(math.max(EarshotDB[key], range[1]), range[2])
            end
            for key, allowed in pairs(ns.CHOICES) do
                if not allowed[EarshotDB[key]] then EarshotDB[key] = ns.DEFAULTS[key] end
            end
            -- Settings for following speakers by nameplate, gone since 0.4.
            EarshotDB.follow, EarshotDB.hidePlates, EarshotDB.titles = nil, nil, nil
            ns.db = EarshotDB
            -- Kept per character: a line held for you to walk back to, and the nameplate options
            -- Earshot 0.3 changed for following, to put back (see Plates.lua).
            if type(EarshotCharDB) ~= "table" then EarshotCharDB = {} end
            ns.char = EarshotCharDB
            ns.Volume:RestoreLeftover()
            ns.Options:Register()
        elseif name == "Spoken" then
            ns.SpokenLink:Attach()
        end
    elseif event == "PLAYER_LOGIN" then
        ns.Anchors:Listen()
        ns.Plates:Init()
        ns.SpokenLink:Attach()
        ns.SpokenLink:Recover()
        if not ns.db.welcomed then
            ns.db.welcomed = true
            ns.Print("NPC voices now fade as you walk away. Type /earshot test to hear it, or /earshot for settings.")
        end
        ns.SpokenLink:Check()
    elseif event == "PLAYER_LOGOUT" then
        -- Put your volume back before the game saves its settings. Fires on /reload too.
        ns.Spatial:Clear()
    end
end)
