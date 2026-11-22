-- Anchors.lua: where speakers stand.
--
-- The game won't tell addons where an NPC is. But when an NPC's window opens you are
-- standing next to it, and your character turns to face it. So Earshot notes where you
-- stood, a couple of yards ahead, and treats that spot as the NPC.
local _, ns = ...
local Math, Plain = ns.Math, ns.Plain

local Anchors = { byGUID = {} }
ns.Anchors = Anchors

local AHEAD = 2.5   -- yards between you and the NPC whose window you opened
local KEEP = 600    -- seconds before a note is forgotten

local EVENTS = { "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE" }

-- `directional` says whether the spot is known well enough for "behind you" to mean much.
local function Spot(north, west, instance, directional)
    return { north = north, west = west, instance = instance, directional = directional, time = GetTime() }
end

local function TalkingTo()
    if UnitExists("questnpc") then return "questnpc" end
    if UnitExists("npc") then return "npc" end
    return nil
end

--- Note where the NPC you're talking to stands.
function Anchors:Record()
    local unit = TalkingTo()
    if not unit then return end
    local guid = Plain(UnitGUID(unit))
    -- A quest item in your bags, or another player sharing a quest, has no fixed spot to
    -- place. Nor is it "the window you just opened" for a line that comes without a GUID.
    if guid and (guid:find("^Item%-") or guid:find("^Player%-")) then
        self.last = nil
        return
    end
    local north, west, instance = ns.PlayerPosition()
    if not north then return end
    local facing = ns.PlayerFacing()
    if facing then north, west = Math.Ahead(north, west, facing, AHEAD) end
    local spot = Spot(north, west, instance, true)
    -- Kept by NPC when the game names it; the latest window is kept either way, for a line
    -- that arrives without the NPC's GUID.
    if guid then
        spot.guid = guid
        self.byGUID[guid] = spot
    end
    self.last = spot
    self:Prune()
end

--- Spoken's stand-in for a GUID it couldn't read: the NPC's ID with every other field 0
--- ("Creature-0-0-0-0-1234-0"). It names a kind of NPC, not the one standing there.
function Anchors.IsStandIn(guid)
    return type(guid) == "string" and guid:match("^%a+%-0%-0%-0%-0%-%d+%-0$") ~= nil
end

--- The NPC window opened within the last `seconds`, if any. One open right now counts even
--- before Earshot's own event handler has had its turn (Spoken's often runs first).
function Anchors:Recent(seconds)
    if TalkingTo() then self:Record() end
    local spot = self.last
    if spot and GetTime() - spot.time <= seconds then return spot end
    return nil
end

--- The spot noted for this NPC, or nil.
function Anchors:For(guid)
    guid = Plain(guid)
    local spot = guid and self.byGUID[guid]
    if spot and GetTime() - spot.time <= KEEP then return spot end
    return nil
end

--- Like For, but also catches a window that opened this very moment, before Earshot's
--- own event handler had its turn.
function Anchors:ForSpeaker(guid)
    guid = Plain(guid)
    if not guid then return nil end
    local spot = self:For(guid)
    if not spot then
        local unit = TalkingTo()
        if unit and Plain(UnitGUID(unit)) == guid then
            self:Record()
            spot = self:For(guid)
        end
    end
    return spot
end

--- A spot where you stand now, optionally `ahead` yards in front of you.
function Anchors:Here(ahead, directional)
    local north, west, instance = ns.PlayerPosition()
    if not north then return nil end
    local facing = ns.PlayerFacing()
    if ahead and ahead > 0 and facing then north, west = Math.Ahead(north, west, facing, ahead) end
    return Spot(north, west, instance, (directional and facing ~= nil) or false)
end

function Anchors:Prune()
    local now = GetTime()
    for guid, spot in pairs(self.byGUID) do
        if now - spot.time > KEEP then self.byGUID[guid] = nil end
    end
end

function Anchors:Listen()
    if self.frame then return end
    self.frame = CreateFrame("Frame")
    for _, event in ipairs(EVENTS) do self.frame:RegisterEvent(event) end
    self.frame:SetScript("OnEvent", ns.Guard(function() Anchors:Record() end))
end
