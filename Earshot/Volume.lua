-- Volume.lua: borrowing one volume slider, and always giving it back.
local _, ns = ...

local Volume = {}
ns.Volume = Volume

-- Sliders Earshot may move. Master and Effects carry nearly every game sound, so a voice
-- on either is left alone rather than fading your whole game.
local MOVABLE = { Ambience = true, Music = true, Dialog = true }

ns.CHANNEL_NAMES = {
    Master = "Master Volume", SFX = "Effects Volume", Music = "Music Volume",
    Ambience = "Ambience Volume", Dialog = "Dialog Volume",
}

-- Never write 0: Spoken treats a slider at 0 as switched off and won't queue lines on it.
local FLOOR = 0.002
-- A slider further than this from what we last wrote was moved by you or another addon.
local MOVED = 0.005

local function CVar(channel) return "Sound_" .. channel .. "Volume" end
local function Read(cvar) return tonumber(GetCVar(cvar)) end

function Volume:IsMovable(channel)
    return channel ~= nil and MOVABLE[channel] == true
end

--- Start controlling `channel`'s slider, remembering your level so it can go back.
function Volume:Take(channel)
    if self.cvar and self.channel == channel then return true end
    self:Release()
    if not self:IsMovable(channel) then return false end
    local cvar = CVar(channel)
    local level = Read(cvar)
    if not level or level <= 0 then return false end -- at 0 there is nothing to fade
    self.channel, self.cvar, self.base, self.written = channel, cvar, level, level
    -- Written down in case the session ends without a logout (see RestoreLeftover).
    ns.db.pending = { cvar = cvar, level = level }
    return true
end

--- Set the slider to your level times `gain` (0..1). Returns false, and lets go, if
--- you moved the slider yourself since Earshot last set it: your new level stands.
function Volume:Set(gain)
    if not self.cvar then return false end
    local now = Read(self.cvar)
    if now and math.abs(now - self.written) > MOVED then
        self:Forget()
        return false
    end
    local value = self.base * math.max(gain, FLOOR)
    value = math.floor(value * 10000 + 0.5) / 10000
    if math.abs(value - self.written) >= 0.0005 then -- smaller steps can't be heard
        SetCVar(self.cvar, value)
        self.written = Read(self.cvar) or value
    end
    return true
end

--- Put your level back and stop controlling the slider.
function Volume:Release()
    if not self.cvar then return end
    local now = Read(self.cvar)
    -- If you moved it meanwhile, that's your level now and it stays.
    if not now or math.abs(now - self.written) <= MOVED then
        SetCVar(self.cvar, self.base)
    end
    self:Forget()
end

--- Stop controlling the slider without touching it.
function Volume:Forget()
    self.channel, self.cvar, self.base, self.written = nil, nil, nil, nil
    if ns.db then ns.db.pending = nil end
end

--- A level lowered in a session that ended without a proper logout: put it back.
function Volume:RestoreLeftover()
    local pending = ns.db.pending
    ns.db.pending = nil
    if type(pending) ~= "table" or not tonumber(pending.level) then return end
    for channel in pairs(MOVABLE) do
        if pending.cvar == CVar(channel) then
            SetCVar(pending.cvar, tonumber(pending.level))
            return
        end
    end
end
