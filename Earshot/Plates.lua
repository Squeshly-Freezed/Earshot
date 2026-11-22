-- Plates.lua: follows the talking NPC by its nameplate, and keeps friendly NPC nameplates
-- down to their names (and titles).
--
-- The game won't tell addons where an NPC stands, but a nameplate gives two clues: roughly
-- how far away its NPC is (asking "is it within X yards?" for a set of distances, which
-- LibRangeCheck-3.0 does), and where on screen it sits. With those Earshot corrects its
-- guess of where the speaker is while a line plays: chatter it could only pin where you
-- were, and NPCs that walk.
--
-- A nameplate only exists while the game shows it, so following turns on Friendly NPC
-- nameplates, and Always Show Nameplates (without it, out of combat only your target has
-- one). Earshot then hides everything on friendly NPC nameplates but their names, and makes
-- them unclickable. (Once an NPC has a nameplate, the game shows its name there instead of
-- above its head.) Your own settings come back when following is switched off, and for each
-- fight: following pauses in combat anyway.
local _, ns = ...
local Math, Plain = ns.Math, ns.Plain

local Plates = { tokenByGUID = {}, guidByToken = {} }
ns.Plates = Plates

local CVARS = { "nameplateShowFriendlyNpcs", "nameplateShowAll" }
local LOOK = 0.1               -- seconds between looks at the speaker's nameplate
local STEP = 0.5               -- how far a reading moves Earshot's guess (0..1); smooths out jumps
local HALF_VIEW = math.rad(45) -- about half the camera's view across the screen
local GUESS_FAR = 5            -- yards past the last range step, for a guess beyond every step

-- What Earshot hides on a friendly NPC's nameplate: its bars, auras, level and highlights.
-- The name stays (shown or not by your NPC name settings, as names are without nameplates),
-- and so do the interact icon, a raid marker and any widgets the game puts there.
local PARTS = {
    "HealthBarsContainer", "CastBarsContainer", "AurasFrame", "ClassificationFrame", "PlayerLevelDiffFrame",
    "LevelFrame", "behindCameraIcon", "selectionHighlight", "aggroHighlightBase", "aggroHighlightAdditive",
    "aggroFlash",
}

local RangeCheck = LibStub and LibStub("LibRangeCheck-3.0", true)
local concealed = setmetatable({}, { __mode = "k" }) -- nameplate face -> how see-through its parts were
local hooked = setmetatable({}, { __mode = "k" })
local titleOf = setmetatable({}, { __mode = "k" }) -- nameplate face -> the title line Earshot added
local titles = {} -- NPC ID -> its title, or when one wasn't found (looked for again after a minute)
local TITLE_RETRY = 60

local function Following() return ns.db.enabled and ns.db.follow end
local function Hiding() return Following() and ns.db.hidePlates end
Plates.Following = Following

-- A friendly NPC: not a player, not a pet or anything else a player controls, and not
-- something you can attack. Unknown counts as no.
local function IsFriendlyNPC(unit)
    if not unit then return false end
    return Plain(UnitIsPlayer(unit)) == false
        and Plain(UnitPlayerControlled(unit)) == false
        and Plain(UnitCanAttack("player", unit)) == false
end

local function TokenOf(plate)
    return plate.unitToken or plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
end

local function NpcID(guid)
    return guid and tonumber(guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
end

-- An NPC's title, such as Stable Master: the line under its name in its tooltip, unless that's
-- the level line (NPCs without a title). Nil if it has none.
local function TitleOf(token)
    local id = NpcID(token and Plain(UnitGUID(token)))
    if not id then return nil end
    local known = titles[id]
    if type(known) == "string" then return known end
    if known and GetTime() - known < TITLE_RETRY then return nil end
    local title
    local ok, data = false, nil
    if C_TooltipInfo and C_TooltipInfo.GetUnit then ok, data = pcall(C_TooltipInfo.GetUnit, token) end
    local lines = ok and type(data) == "table" and data.lines
    if type(lines) == "table" then
        local nameType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.UnitName or 2
        local at = 1
        for i, line in ipairs(lines) do
            if Plain(line.type) == nameType then
                at = i
                break
            end
        end
        local text = lines[at + 1] and Plain(lines[at + 1].leftText)
        local level = type(LEVEL) == "string" and LEVEL or "Level"
        if type(text) == "string" and text ~= "" and text:find(level, 1, true) ~= 1 then
            title = text:match("^<(.+)>$") or text
        end
    end
    titles[id] = title or GetTime()
    return title
end

-- The title line under a hidden nameplate's name, shown while the name is (it follows your
-- NPC name settings). `token` is the nameplate's unit when the game hasn't set it up yet.
local function ShowTitle(face, token)
    local line = titleOf[face]
    local name = face.name
    local title = ns.db.titles and concealed[face] and name and name:IsShown() and TitleOf(token or face.unit)
    if not title then
        if line then line:Hide() end
        return
    end
    if not line then
        if not face.CreateFontString then return end
        line = face:CreateFontString(nil, "OVERLAY")
        titleOf[face] = line
    end
    local font, size, flags = name:GetFont()
    if font then
        line:SetFont(font, math.max(6, math.floor((size or 10) * 0.9 + 0.5)), flags)
    else
        line:SetFontObject(SystemFont_NamePlate or GameFontNormalSmall)
    end
    -- The game tints a nameplate's name (green for friendly, yellow for neutral): match it.
    line:SetTextColor(name:GetTextColor())
    if name.GetVertexColor and line.SetVertexColor then line:SetVertexColor(name:GetVertexColor()) end
    line:ClearAllPoints()
    line:SetPoint("TOP", name, "BOTTOM", 0, -1)
    line:SetText("<" .. title .. ">")
    line:Show()
end

-- Take away a nameplate's clickable area. In combat the game only lets an addon do this on the
-- moment the nameplate is set up for its unit, which is when Earshot does it.
local function ClearClickArea(plate)
    if not (plate and plate.ClearAllHitTestPoints) then return end
    if plate.CanChangeHitTestPoints then
        local ok, can = pcall(plate.CanChangeHitTestPoints, plate)
        if ok and can == false then return end
    end
    pcall(plate.ClearAllHitTestPoints, plate)
end

-- Hide everything on a nameplate but its name, and take away its clickable area. The
-- nameplate itself stays, so Earshot can still ask about its NPC. Only the parts are made
-- see-through, not the whole nameplate: the game sets that back to fully visible now and then.
local function Conceal(plate, token)
    local face = plate.UnitFrame
    if not face then return end
    if not hooked[face] and type(face.UpdateHitTestArea) == "function" then
        hooked[face] = true
        -- The game redraws the clickable area whenever it sets a nameplate up. Clear it again
        -- straight after if it's still a friendly NPC's (nameplates get reused for others).
        hooksecurefunc(face, "UpdateHitTestArea", function(self)
            if Hiding() and IsFriendlyNPC(self.unit) then
                ClearClickArea(self.GetNamePlateFrame and self:GetNamePlateFrame() or plate)
            end
        end)
    end
    local before = concealed[face]
    if not before then
        before = {}
        for _, key in ipairs(PARTS) do
            local part = face[key]
            if type(part) == "table" and part.GetAlpha and part.SetAlpha then before[key] = part:GetAlpha() end
        end
        concealed[face] = before
    end
    for key in pairs(before) do face[key]:SetAlpha(0) end
    ClearClickArea(plate)
    ShowTitle(face, token)
end

-- Make a hidden nameplate visible again. `redraw` also gives back its clickable area: only
-- needed when following is switched off, since a reused nameplate gets a fresh one.
local function Reveal(plate, redraw)
    local face = plate.UnitFrame
    local before = face and concealed[face]
    if not before then return end
    concealed[face] = nil
    for key, alpha in pairs(before) do
        if face[key] then face[key]:SetAlpha(alpha) end
    end
    if titleOf[face] then titleOf[face]:Hide() end
    if redraw and face.UpdateHitTestArea and NamePlateSetupOptions then
        pcall(face.UpdateHitTestArea, face, NamePlateSetupOptions)
    end
end

local function OnAdded(token)
    local guid = Plain(UnitGUID(token))
    if guid then
        Plates.tokenByGUID[guid] = token
        Plates.guidByToken[token] = guid
    end
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return end
    local plate = C_NamePlate.GetNamePlateForUnit(token) -- nil when the game keeps it from addons
    if plate then
        if Hiding() and IsFriendlyNPC(token) then Conceal(plate, token) else Reveal(plate, false) end
    end
    ns.Markers:Update(guid) -- if it's talking, it has somewhere for its bubble now
end

local function OnRemoved(token)
    local guid = Plates.guidByToken[token]
    if guid and Plates.tokenByGUID[guid] == token then Plates.tokenByGUID[guid] = nil end
    Plates.guidByToken[token] = nil
    ns.Markers:Update(guid)
end

--- Turn the game's nameplate options on for following, or put yours back. The game locks
--- nameplate options in combat, so a change waits until combat ends.
local function SetGameOptions(on)
    if InCombatLockdown() then
        Plates.waiting = true
        return
    end
    Plates.waiting = nil
    local saved = ns.char.plateOptions
    if on then
        for _, cvar in ipairs(CVARS) do
            local now = GetCVar(cvar)
            if now ~= nil and now ~= "1" then
                if saved[cvar] == nil then saved[cvar] = now end
                SetCVar(cvar, "1")
            end
        end
    else
        for cvar, old in pairs(saved) do
            -- If you changed it yourself since, leave yours.
            if GetCVar(cvar) == "1" then SetCVar(cvar, old) end
            saved[cvar] = nil
        end
    end
end

--- Bring nameplates and the game's options in line with the settings.
function Plates:Update()
    SetGameOptions(Following())
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
        local token = TokenOf(plate)
        if Hiding() and IsFriendlyNPC(token) then Conceal(plate, token) else Reveal(plate, true) end
    end
end

-- Is the camera looking where your character faces? Then the nameplate's place on screen
-- says which way the NPC is from you. Mouse-looking turns both together; moving brings the
-- camera round behind you.
local function CameraLinedUp()
    if IsMouselooking and IsMouselooking() then return true end
    local speed = Plain(GetUnitSpeed("player"))
    return speed ~= nil and speed > 0
end

local function BehindCamera(token)
    if not (C_NamePlateManager and C_NamePlateManager.IsNamePlateUnitBehindCamera) then return nil end
    local ok, behind = pcall(C_NamePlateManager.IsNamePlateUnitBehindCamera, token)
    if ok then return Plain(behind) end
    return nil
end

-- Where the NPC is across the camera's view: radians, + to the left. nil when its nameplate
-- isn't on screen, or sits pinned to the edge of it.
local function ScreenAngle(token)
    local plate = C_NamePlate.GetNamePlateForUnit(token)
    if not (plate and plate:IsVisible()) or BehindCamera(token) then return nil end
    local x = Plain((plate:GetCenter()))
    local left, width, scale = WorldFrame:GetLeft(), WorldFrame:GetWidth(), WorldFrame:GetEffectiveScale()
    if not (x and left and width and width > 0) then return nil end
    x = x * plate:GetEffectiveScale()
    local half = width * scale / 2
    local across = (x - (left * scale + half)) / half -- -1 at the left edge, 1 at the right
    if math.abs(across) > 0.98 then return nil end
    return -math.atan(across * math.tan(HALF_VIEW))
end

-- Turn a front-left angle into the matching back-left one, and so on.
local function Mirror(angle)
    return (angle >= 0 and math.pi or -math.pi) - angle
end

local function AskRange(...)
    local ok, low, high = pcall(RangeCheck.GetRange, RangeCheck, ...)
    if not ok then return nil end
    return Plain(low), Plain(high)
end

-- How far away the NPC is, as a band of yards: low to high, with no high past the last step.
-- LibRangeCheck measures a friendly NPC one of two ways: with an item that reaches 5 yards,
-- or, told to leave items out, with the game's interaction distances (8 and 28 yards). When
-- it has the item it skips the interaction distances, so ask both ways and keep where the
-- answers overlap. Both ways also use your class's healing and buff spells, if it has any.
local function RangeOf(token)
    local low, high = AskRange(token)
    local low2, high2 = AskRange(token, false, true)
    if not low then return low2, high2 end
    if not low2 then return low, high end
    local bandLow = math.max(low, low2)
    local bandHigh = (high and high2) and math.min(high, high2) or high or high2
    if bandHigh and bandLow > bandHigh then return low2, high2 end -- they disagree: go by the interaction distances
    return bandLow, bandHigh
end

--- Correct where Earshot thinks the speaker of `session` is, from its nameplate.
function Plates:Refine(session)
    if not (Following() and session.guid and RangeCheck) then return end
    local now = GetTime()
    if (session.lookedAt or 0) + LOOK > now then return end
    session.lookedAt = now
    if InCombatLockdown() then return end -- the game blocks range checks on friendly units in combat
    local token = self.tokenByGUID[session.guid]
    if not token or Plain(UnitGUID(token)) ~= session.guid then return end
    local north, west, instance = ns.PlayerPosition()
    local facing = ns.PlayerFacing()
    local spot = session.spot
    if not (north and facing) or instance ~= spot.instance then return end
    local low, high = RangeOf(token)
    if not low then return end
    session.seen = { low = low, high = high, time = now }

    -- How far: keep the guess unless the reading rules it out. A first reading for a spot
    -- that was only ever a guess goes to the middle of the range.
    local distance = Math.Distance(north, west, spot.north, spot.west)
    local yards
    if spot.guess then
        yards = high and (low + high) / 2 or low + GUESS_FAR
    else
        yards = Math.Clamp(distance, low, high or math.huge)
    end

    -- Which way: from the nameplate if the camera faces where you do, otherwise keep ours.
    local ours = distance > 0.5 and Math.RelativeAngle(Math.Bearing(north, west, spot.north, spot.west), facing) or nil
    local angle, linedUp = nil, CameraLinedUp()
    if linedUp then
        angle = ScreenAngle(token)
        if not angle then
            local behind = BehindCamera(token)
            angle = ours or (behind and math.pi or 0)
            if behind ~= nil and (math.abs(angle) < math.pi / 2) == behind then angle = Mirror(angle) end
        end
    else
        angle = ours or 0
    end

    local toNorth, toWest = Math.Ahead(north, west, facing + angle, yards)
    local step = spot.guess and 1 or STEP
    spot.north = spot.north + (toNorth - spot.north) * step
    spot.west = spot.west + (toWest - spot.west) * step
    spot.guess = nil
    if linedUp then spot.directional = true end
end

--- In combat Earshot can't follow the speaker. If it was following this one (it may be an
--- escort fighting beside you), its voice keeps the volume it had as the fight started. A
--- speaker it wasn't following stays where Earshot placed it, so that voice still fades.
function Plates:Holds(session)
    return Following() and session ~= nil and session.seen ~= nil and InCombatLockdown() and true or false
end

--- What following knows about the current speaker, for /earshot status.
function Plates:Describe(session)
    if not Following() then return nil end
    if not RangeCheck then return "Following needs LibRangeCheck-3.0, which didn't load." end
    if not (session and session.guid) then return nil end
    if self:Holds(session) then
        return "In combat Earshot can't follow it, so its voice stays at this volume until the fight ends."
    end
    local seen = session.seen
    if seen and GetTime() - seen.time < 2 then
        if seen.high and seen.low <= 0 then
            return ("Following its nameplate: within %d yd."):format(seen.high)
        elseif seen.high then
            return ("Following its nameplate: %d-%d yd away."):format(seen.low, seen.high)
        end
        return ("Following its nameplate: over %d yd away."):format(seen.low)
    end
    if InCombatLockdown() then return "Following pauses in combat (the game blocks range checks)." end
    return "Its nameplate isn't showing, so Earshot goes by where it last saw the NPC."
end

function Plates:Init()
    if self.frame then return end
    self.frame = CreateFrame("Frame")
    self.frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    self.frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    self.frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    self.frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    self.frame:SetScript("OnEvent", ns.Guard(function(_, event, token)
        if event == "NAME_PLATE_UNIT_ADDED" then
            OnAdded(token)
        elseif event == "NAME_PLATE_UNIT_REMOVED" then
            OnRemoved(token)
        elseif event == "PLAYER_REGEN_DISABLED" then
            -- Following pauses in combat, so your own nameplate options come back for the
            -- fight. The game still allows the change at this moment, as combat starts.
            SetGameOptions(false)
        elseif event == "PLAYER_REGEN_ENABLED" then
            SetGameOptions(Following())
        end
    end))
    -- The game redoes a nameplate's name when its unit or your name settings change: redo the
    -- title under it too.
    if type(CompactUnitFrame_UpdateName) == "function" then
        hooksecurefunc("CompactUnitFrame_UpdateName", ns.Guard(function(face)
            if type(face) == "table" and (titleOf[face] or concealed[face]) then ShowTitle(face) end
        end))
    end
    self:Update()
end
