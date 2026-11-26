-- Plates.lua: keeps track of which nameplate belongs to which NPC, so the speech bubble over
-- whoever's talking (Markers.lua) has somewhere to sit. A friendly NPC only has a nameplate
-- while the game shows one: with Friendly NPC nameplates on in the game's options.
--
-- Earshot 0.3 could also follow the talking NPC by its nameplate. It turned those options
-- on for that, and kept each character's own settings to put back. Following is gone (it
-- guessed wrong too often), so anyone who had it on gets their own settings back.
local _, ns = ...
local Plain = ns.Plain

local Plates = { tokenByGUID = {}, guidByToken = {} }
ns.Plates = Plates

local function OnAdded(token)
    local guid = Plain(UnitGUID(token))
    if guid then
        Plates.tokenByGUID[guid] = token
        Plates.guidByToken[token] = guid
    end
    ns.Markers:Update(guid) -- if it's talking, it has somewhere for its bubble now
end

local function OnRemoved(token)
    local guid = Plates.guidByToken[token]
    if guid and Plates.tokenByGUID[guid] == token then Plates.tokenByGUID[guid] = nil end
    Plates.guidByToken[token] = nil
    ns.Markers:Update(guid)
end

--- Put back the nameplate options Earshot 0.3 turned on for following (Friendly NPC
--- nameplates, Always Show Nameplates) as they were. One you've changed yourself since stays
--- as you have it. The game locks nameplate options in combat: then it waits. True when done.
function Plates:GiveBackOptions()
    local saved = ns.char and ns.char.plateOptions
    if type(saved) ~= "table" or next(saved) == nil then
        if ns.char then ns.char.plateOptions = nil end
        return true
    end
    if InCombatLockdown() then return false end
    for cvar, old in pairs(saved) do
        if GetCVar(cvar) == "1" then SetCVar(cvar, old) end
    end
    ns.char.plateOptions = nil
    return true
end

function Plates:Init()
    if self.frame then return end
    self.frame = CreateFrame("Frame")
    self.frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    self.frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    self.frame:SetScript("OnEvent", ns.Guard(function(frame, event, token)
        if event == "NAME_PLATE_UNIT_ADDED" then
            OnAdded(token)
        elseif event == "NAME_PLATE_UNIT_REMOVED" then
            OnRemoved(token)
        elseif event == "PLAYER_REGEN_ENABLED" then
            if self:GiveBackOptions() then frame:UnregisterEvent("PLAYER_REGEN_ENABLED") end
        end
    end))
    if not self:GiveBackOptions() then self.frame:RegisterEvent("PLAYER_REGEN_ENABLED") end
    -- Nameplates already showing (after a /reload).
    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
            local token = plate.unitToken or plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
            if token then OnAdded(token) end
        end
    end
end
