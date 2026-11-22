-- API.lua: lets other voice addons place their sounds too.
--
--   -- When your line starts (it must play on the Ambience, Music or Dialog channel):
--   local token = Earshot:Place({ channel = "Ambience", guid = UnitGUID("npc") })
--   -- Or, for a speaker you can't identify, pinned where the player stands now:
--   local token = Earshot:Place({ channel = "Ambience", here = true })
--   -- When it ends:
--   Earshot:Done(token)
--
-- Place returns nil when Earshot can't place the sound (switched off, no position here,
-- unknown NPC). Optional fields: full, silent (yards) to override the player's settings.
local _, ns = ...

local API = { version = 1 }
Earshot = API

function API:Place(info)
    if type(info) ~= "table" then return nil end
    local spot = info.guid and ns.Anchors:ForSpeaker(info.guid)
    if not spot and info.here then spot = ns.Anchors:Here(0, false) end
    if not spot then return nil end
    local options = { kind = "api", full = tonumber(info.full), silent = tonumber(info.silent), guid = ns.Plain(info.guid) }
    if not ns.Spatial:Begin(spot, info.channel, options) then return nil end
    local token = {}
    ns.Spatial.session.token = token
    return token
end

function API:Done(token)
    local session = ns.Spatial.session
    if token and session and session.token == token then ns.Spatial:End() end
end

--- 0..1: how loud Earshot is making the placed voice now (1 when nothing is placed).
function API:GetLevel()
    return ns.Spatial.session and ns.Spatial.level or 1
end
