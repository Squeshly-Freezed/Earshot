-- Spatial.lua: follows you while a voice plays and moves the slider to match.
local _, ns = ...
local Math = ns.Math

local Spatial = { level = 1 }
ns.Spatial = Spatial

local TICK = 0.05    -- seconds between updates (20 a second)
local FOLLOW = 0.15  -- seconds for the volume to catch up with a change; smooths out steps
local SETTLE = 2.0   -- seconds to hold after a line ends, so the pause before the next line doesn't pump the volume
local RETURN = 0.6   -- seconds to fade back to your own level afterwards
local AWAY = 1.5     -- seconds out of earshot before that counts (see options.onAway)

local frame = CreateFrame("Frame")
frame:Hide() -- runs only while a voice is placed
local waited = 0
frame:SetScript("OnUpdate", function(_, elapsed)
    waited = waited + elapsed
    if waited < TICK then return end
    local dt = waited
    waited = 0
    local ok, err = pcall(Spatial.Update, Spatial, dt)
    if not ok then
        Spatial:Clear() -- stop rather than repeat the error 20 times a second
        geterrorhandler()(err)
    end
end)

--- How far you are from `spot` in yards; math.huge in another world, nil if unknown.
function Spatial:DistanceTo(spot)
    local north, west, instance = ns.PlayerPosition()
    if not (north and spot) then return nil end
    if instance ~= spot.instance then return math.huge end
    return Math.Distance(north, west, spot.north, spot.west)
end

--- The distances a session fades over: full volume within `full`, silent beyond `silent`.
function Spatial:Range(session)
    local full = session.full or ns.db.full
    return full, math.max(session.silent or ns.db.silent, full + 5)
end

--- How loud the voice should be right now (0..1), or nil when it can't be told. Never
--- below the Never quieter than setting.
function Spatial:Gain(session)
    if session.hushed then return 0 end -- about to be skipped (see Hush)
    local db = ns.db
    local least = db.floor / 100
    local north, west, instance = ns.PlayerPosition()
    if not north then
        -- Inside a dungeon or battleground the speaker is out in the world: out of earshot.
        -- Anywhere else it's a passing gap, like a loading screen, so hold.
        if IsInInstance() then
            self.info = { away = true, elsewhere = true }
            return least
        end
        return nil
    end
    local spot = session.spot
    if instance ~= spot.instance then -- another continent
        self.info = { away = true, elsewhere = true }
        return least
    end
    local full, silent = self:Range(session)
    local distance = Math.Distance(north, west, spot.north, spot.west)
    local gain = Math.DistanceGain(distance, full, silent)
    local angle
    local facing = spot.directional and ns.PlayerFacing()
    if facing then
        angle = Math.RelativeAngle(Math.Bearing(north, west, spot.north, spot.west), facing)
        local weight = Math.Clamp((distance - full * 0.5) / (full * 0.5), 0, 1)
        gain = gain * Math.FacingGain(angle, db.behind / 100, weight)
    end
    gain = math.max(gain, least)
    self.info = { distance = distance, angle = angle, gain = gain, away = distance > silent }
    return gain
end

-- Whether you're further than `yards` from `spot`, as Gain sees it: from inside an instance,
-- or another continent, a voice out in the world is out of reach.
local function FurtherThan(spot, yards)
    local north, west, instance = ns.PlayerPosition()
    if not north then return IsInInstance() and true or false end
    if instance ~= spot.instance then return true end
    return Math.Distance(north, west, spot.north, spot.west) > yards
end

--- Whether you're out of earshot of a voice at `spot`. options: full / silent, as for Begin.
function Spatial:OutOfEarshot(spot, options)
    local _, silent = self:Range(options or {})
    return FurtherThan(spot, silent)
end

--- Whether you're further from a voice at `spot` than full volume reaches.
function Spatial:BeyondFull(spot, options)
    return FurtherThan(spot, (self:Range(options or {})))
end

--- Place a voice at `spot`, playing on `channel`. Returns true if Earshot took it on.
--- options: full / silent (yards) to override the settings, guid (the speaker), kind (for
--- debugging), onAway (called once, with the session, after you've been out of earshot a moment).
function Spatial:Begin(spot, channel, options)
    if not (ns.db.enabled and spot) then return false end
    if not ns.Volume:Take(channel) then return false end
    options = options or {}
    self.session = {
        spot = spot, channel = channel, full = options.full, silent = options.silent, kind = options.kind,
        guid = options.guid, -- the speaker, so its nameplate can be followed
        onAway = options.onAway,
    }
    self.returning = false
    self.info = nil -- the last voice's, until Gain says otherwise
    -- Start at the right level at once rather than fading in from the last one.
    local gain = self:Gain(self.session)
    if gain then
        self.level = gain
        if not ns.Volume:Set(gain) then
            self:Reset()
            return false
        end
    end
    waited = 0
    frame:Show()
    return true
end

--- Silence the voice at once, below Never quieter than, and keep it silent: it's about to
--- be skipped.
function Spatial:Hush()
    local session = self.session
    if not session then return end
    session.hushed = true
    self.level = 0
    if not ns.Volume:Set(0) then self:Reset() end
end

--- The voice stopped. Hold a moment in case the next line follows, then let go.
function Spatial:End()
    if self.session and not self.session.ended then
        self.session.ended = GetTime()
    end
end

--- Back to your level at once: a line that should play as normal is starting, or logout.
function Spatial:Clear()
    ns.Volume:Release()
    self:Reset()
end

function Spatial:Reset()
    self.session, self.info, self.returning, self.level = nil, nil, false, 1
    frame:Hide()
end

function Spatial:Update(dt)
    local session = self.session
    if not session then
        self:Clear()
        return
    end
    if session.ended and not self.returning and GetTime() - session.ended >= SETTLE then
        self.returning = true
    end
    if self.returning then
        self.level = math.min(1, self.level + dt / RETURN)
        if self.level >= 1 then
            self:Clear()
        elseif not ns.Volume:Set(self.level) then
            self:Reset()
        end
        return
    end
    ns.Plates:Refine(session) -- move the speaker's spot if its nameplate says otherwise
    if ns.Plates:Holds(session) then return end -- in combat, a followed voice keeps its volume
    local target = self:Gain(session)
    if target == nil then return end -- hold where we are
    self.level = self.level + (target - self.level) * (1 - math.exp(-dt / FOLLOW))
    if not ns.Volume:Set(self.level) then
        -- You moved the slider yourself: hands off until the next line.
        self:Reset()
        return
    end
    self:CheckAway(session)
    if ns.debug then ns.DebugTick(session) end
end

-- Out of earshot for a moment (not just stepping over the edge): tell whoever placed the voice.
function Spatial:CheckAway(session)
    if not (self.info and self.info.away) then
        session.awaySince = nil
        return
    end
    local now = GetTime()
    session.awaySince = session.awaySince or now
    if session.onAway and not (session.wentAway or session.ended) and now - session.awaySince >= AWAY then
        session.wentAway = true
        session.onAway(session)
    end
end
