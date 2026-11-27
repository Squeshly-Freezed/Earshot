-- Markers.lua: a small speech bubble over the NPC who's talking.
--
-- It sits on the NPC's nameplate, so it shows when the NPC has one: with Friendly NPC
-- nameplates on in the game's options, and out of combat only for your target unless Always
-- Show Nameplates is on too. Earshot doesn't change those options; it says what's missing (once
-- when a voice first plays without them, when you tick Mark who's talking, and in
-- /earshot status). An NPC is talking while Spoken plays its voice, and (with Also NPCs talking
-- without a voice) for a while after it says something in chat, which covers the game's own
-- lines that Spoken has no voice for.
local _, ns = ...
local Plain = ns.Plain

local Markers = { talking = {} } -- speaker GUID -> { voice = true, chatUntil = time }
ns.Markers = Markers

--- Which friendly NPCs have a nameplate for the bubble: "all", "target" (out of combat only
--- your target, without Always Show Nameplates), "none", or nil if this client lacks the option.
function Markers.Nameplates()
    local friendly = GetCVar("nameplateShowFriendlyNpcs")
    if friendly == nil then return nil end
    if friendly ~= "1" then return "none" end
    return GetCVar("nameplateShowAll") == "1" and "all" or "target"
end

--- Why the bubble can't show over every NPC, or nil if it can (or Mark who's talking is off).
function Markers:Problem()
    if not (ns.db and ns.db.markers) then return nil end
    local plates = self.Nameplates()
    if plates == "none" then
        return "Mark who's talking puts its bubble on nameplates, and the game's Friendly NPC nameplates "
            .. "are off. To see it, switch them on in the game's options under Nameplates, with Always "
            .. "Show Nameplates for NPCs you haven't targeted."
    elseif plates == "target" then
        return "Mark who's talking: Always Show Nameplates is off in the game's options, so out of combat "
            .. "only your target has a nameplate, and only your target gets the bubble."
    end
end

-- Mark who's talking is on by default, and does nothing without nameplates. The first time a
-- voice plays with no friendly NPC nameplates, say why there's no bubble. Once, ever.
local function HintOnce()
    local db = ns.db
    if db.markerHint or Markers.Nameplates() ~= "none" then return end
    db.markerHint = true
    ns.Print("To see a speech bubble over whoever's talking, switch on Friendly NPC nameplates in the "
        .. "game's options (under Nameplates). Don't want it? Untick Mark who's talking in /earshot.")
end

local ICON = "Interface\\AddOns\\Earshot\\Media\\Speaking"
local SIZE = 22
local pool, shown = {}, {} -- spare bubbles; GUID -> the bubble on its nameplate

local function Bubble()
    local bubble = table.remove(pool)
    if bubble then return bubble end
    bubble = CreateFrame("Frame")
    bubble:SetSize(SIZE, SIZE)
    local icon = bubble:CreateTexture(nil, "OVERLAY")
    icon:SetAllPoints()
    icon:SetTexture(ICON)
    if bubble.CreateAnimationGroup then -- a slow pulse, like someone mid-sentence
        local pulse = bubble:CreateAnimationGroup()
        pulse:SetLooping("BOUNCE")
        local fade = pulse:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0.5)
        fade:SetDuration(0.6)
        bubble.pulse = pulse
    end
    return bubble
end

local function Detach(guid)
    local bubble = shown[guid]
    if not bubble then return end
    shown[guid] = nil
    if bubble.pulse then bubble.pulse:Stop() end
    bubble:Hide()
    bubble:ClearAllPoints()
    bubble:SetParent(nil)
    bubble.plate = nil
    table.insert(pool, bubble)
end

local function Attach(guid)
    local token = ns.Plates.tokenByGUID[guid]
    local plate = token and C_NamePlate and C_NamePlate.GetNamePlateForUnit
        and C_NamePlate.GetNamePlateForUnit(token)
    if not plate then
        Detach(guid)
        return
    end
    if shown[guid] and shown[guid].plate == plate then return end
    Detach(guid)
    local bubble = Bubble()
    bubble.plate = plate
    bubble:SetParent(plate)
    local face = plate.UnitFrame
    if face and face.GetFrameLevel then bubble:SetFrameLevel(face:GetFrameLevel() + 5) end
    -- Just above the name. A hidden name still has its place, so this works either way.
    local anchor = face and face.name or plate
    bubble:SetPoint("BOTTOM", anchor, "TOP", 0, 2)
    bubble:Show()
    if bubble.pulse then bubble.pulse:Play() end
    shown[guid] = bubble
end

--- Show or take down the bubble for `guid`, by whether it's talking and has a nameplate.
function Markers:Update(guid)
    if not guid then return end
    local talk = self.talking[guid]
    if talk and talk.chatUntil and talk.chatUntil <= GetTime() then talk.chatUntil = nil end
    if talk and not (talk.voice or talk.chatUntil) then
        self.talking[guid] = nil
        talk = nil
    end
    if talk and ns.db and ns.db.markers then Attach(guid) else Detach(guid) end
end

--- `guid` is talking: "voice" until Quiet, or "chat" for `seconds`.
function Markers:Speak(guid, how, seconds)
    guid = Plain(guid)
    if not guid then return end
    local talk = self.talking[guid] or {}
    self.talking[guid] = talk
    if how == "voice" then
        talk.voice = true
        if ns.db and ns.db.markers then HintOnce() end
    else
        talk.chatUntil = math.max(talk.chatUntil or 0, GetTime() + seconds)
        C_Timer.After(seconds + 0.05, function() Markers:Update(guid) end)
    end
    self:Update(guid)
end

--- `guid` stopped talking (its "voice" ended).
function Markers:Quiet(guid, how)
    guid = Plain(guid)
    local talk = guid and self.talking[guid]
    if not talk then return end
    if how == "voice" then talk.voice = nil end
    self:Update(guid)
end

function Markers:QuietAll(how)
    for guid in pairs(self.talking) do self:Quiet(guid, how) end
end

--- After a setting changed, or a nameplate came or went.
function Markers:Refresh()
    local guids = {}
    for guid in pairs(shown) do guids[guid] = true end
    for guid in pairs(self.talking) do guids[guid] = true end
    for guid in pairs(guids) do self:Update(guid) end
end

--- Which NPC has a bubble now (for tests and /earshot status).
function Markers:Showing(guid)
    return shown[guid] ~= nil
end
