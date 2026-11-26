-- SpokenLink.lua: places Spoken's voices.
--
-- Spoken announces every line it queues, starts and stops (Spoken:RegisterCallback). Each
-- line says which part of Spoken it came from, which slider it plays on, and which NPC is
-- talking (clip.unitGUID).
--
--   quests, gossip   the NPC whose window you opened: placed where it stood
--   chatter          an NPC talking nearby. The game doesn't say where it stands, so the
--                    voice is pinned where you were when the NPC spoke. Yells carry further
--                    (Yells heard up to). Whispers are said to you, so they play as normal
--   anything else    zone stories, books and dungeon voices play as normal
--
-- A line you replay or start from a distance plays as normal: Earshot fades a voice you
-- walk away from, but doesn't start one silent. A line that waits in Spoken's queue behind
-- others is different: if you were in earshot when Spoken queued it, you walked away from
-- it, so it starts faded, or silent.
--
-- Walk out of earshot of a placed line and, after a moment, the "When you walk out of
-- earshot" setting decides what happens: it keeps playing quietly, Spoken skips it, Spoken
-- skips everything that NPC has to say, Spoken skips every line from anywhere you're out of
-- earshot of, or Spoken stops it until you come back (a quest or gossip line; chatter was
-- only a passing remark, so that's skipped).
local _, ns = ...
local Spatial, Anchors, Volume, Plain = ns.Spatial, ns.Anchors, ns.Volume, ns.Plain

local Link = {}
ns.SpokenLink = Link

-- A quest or gossip line without the NPC's own GUID belongs to the window you just
-- opened, if it starts this soon after.
local JUST_OPENED = 10

-- Spoken voices all of these as chatter without saying which it was, so Earshot listens
-- to the same chat and matches it by the words.
local CHAT_KIND = {
    CHAT_MSG_MONSTER_SAY = "say",
    CHAT_MSG_MONSTER_YELL = "yell",
    CHAT_MSG_MONSTER_WHISPER = "whisper",
    CHAT_MSG_RAID_BOSS_WHISPER = "whisper",
}
local HEARD_KEEP = 120   -- seconds a chat line is remembered
local SKIPPED_KEEP = 600 -- seconds an NPC you walked away from stays skipped

local placing    -- the line Earshot is placing now
local warned = {}
local heard = {} -- chat text -> { kind, spot, time }
local finished, finishedCount = {}, 0 -- lines that have played to the end, by Spoken's key
local queuedNear = setmetatable({}, { __mode = "k" }) -- line -> its spot, for lines queued while in earshot
local letPlay = setmetatable({}, { __mode = "k" }) -- lines you restarted yourself while away: left alone
local asked = setmetatable({}, { __mode = "k" }) -- lines you went back to with Spoken's Previous
local skipped = {} -- speaker GUID -> { spot, silent, time }: NPCs you walked away from mid-line
-- A line stopped until you come back: { clip, spot, back (yards), paused }. While `paused`,
-- Spoken is stopped on it; otherwise it waits in the queue behind lines that went ahead.
local held

local function KeyOf(clip) return clip.key or clip.fileName or clip.path end

-- The NPC's own GUID (its nameplate has it too, for the speech bubble). Spoken's stand-ins
-- don't match one.
local function Speaker(clip)
    local guid = Plain(clip.unitGUID)
    return guid and not Anchors.IsStandIn(guid) and guid or nil
end

local function Remember(key)
    if not key or finished[key] then return end
    finishedCount = finishedCount + 1
    if finishedCount > 500 then finished, finishedCount = {}, 1 end -- keep it small
    finished[key] = true
end

local function ChannelOf(clip)
    local ok, channel = pcall(function() return clip.source:GetChannel() end)
    if ok and type(channel) == "string" then return channel end
    return nil
end

local function Warn(channel)
    if warned[channel] then return end
    warned[channel] = true
    ns.Print("Spoken plays on %s, which also carries other game sounds, so Earshot leaves it alone. "
        .. "To let voices fade, set Volume Follows to Ambience Volume in Spoken's settings (/earshot spoken).",
        ns.CHANNEL_NAMES[channel] or tostring(channel))
end

local function SpotFor(clip, part, replay)
    local db = ns.db
    local guid = clip.unitGUID
    local speaker = Speaker(clip)
    local queued = queuedNear[clip] -- where it would have gone when Spoken queued it
    if (part == "quests" or part == "gossip") and db.quests then
        local spot = Anchors:ForSpeaker(guid) or queued
        if not spot and not speaker and not clip.unitIsObjectOrItem then
            -- Spoken couldn't read this NPC's own GUID: the window you just opened is the speaker.
            spot = Anchors:Recent(JUST_OPENED)
        end
        -- Out of earshot as it starts (or a replay from a distance): play as normal. Not if you
        -- were in earshot when it was queued, though: then you walked away from it.
        if spot and not queued then
            local distance = Spatial:DistanceTo(spot)
            if distance and (distance > db.silent or (replay and distance > db.full)) then return nil end
        end
        return spot, { guid = speaker }
    elseif part == "chatter" and db.chatter then
        local said = clip.text and heard[clip.text]
        local kind = said and said.kind or "say"
        if kind == "whisper" then return nil end -- said to you
        local range = db.chatterRange
        if kind == "yell" then
            if db.yellRange >= ns.YELLS_ANYWHERE then return nil end -- heard anywhere: as normal
            range = db.yellRange
        end
        local spot = Anchors:ForSpeaker(guid) -- an NPC you talked to
        if spot then
            if kind == "yell" then return spot, { guid = speaker, full = ns.NearPart(range), silent = range } end
            return spot, { guid = speaker }
        end
        local pin = (said and said.spot) or queued or Anchors:Here(0, false) -- where you were
        return pin, { full = ns.NearPart(range), silent = range, guid = speaker }
    end
    return nil
end

--------------------------------------------------------------------------------
-- Out of earshot
--------------------------------------------------------------------------------

local function Head()
    return Spoken.GetCurrent and Spoken:GetCurrent() or nil
end

local function Queue()
    local ok, queue = pcall(function() return Spoken:GetQueue() end)
    return ok and type(queue) == "table" and queue or {}
end

local function Skip(clip)
    if Head() == clip and Spoken.Skip then Spoken:Skip() end
end

-- Skip a line that's only just starting. Spoken tells Earshot a line has started before it
-- has finished starting it (it sets the line's timer straight after), and a line skipped in
-- between leaves that timer running. So it's silenced now and skipped a moment later.
local function SkipSoon(clip)
    Spatial:Hush()
    C_Timer.After(0, ns.Guard(function()
        if not (Spoken.IsPaused and Spoken:IsPaused()) then Skip(clip) end -- stopped meanwhile by you: left be
    end))
end

-- Skip the line, and everything else that NPC has waiting. Lines it says while you're still
-- away are skipped as they start (see OnStarted).
local function SkipSpeaker(clip, session)
    local who = Plain(clip.unitGUID) -- a stand-in counts too: the same kind of NPC
    if who then
        local now = GetTime()
        for guid, entry in pairs(skipped) do
            if now - entry.time > SKIPPED_KEEP then skipped[guid] = nil end
        end
        local _, silent = Spatial:Range(session)
        skipped[who] = { spot = session.spot, silent = silent, time = now }
        for _, queued in ipairs(Queue()) do
            if queued ~= clip and queued.unitGUID == who and queued.source and queued.source.Remove then
                queued.source:Remove(queued)
            end
        end
    end
    Skip(clip)
end

-- Skip the line, and every line waiting from somewhere you're out of earshot of. Lines that
-- start while you're out of earshot of them are skipped as they start (see OnStarted). Lines
-- that would play as normal (whispers, lines you start yourself from a distance) stay.
local function SkipEverythingAway(clip)
    for _, queued in ipairs(Queue()) do
        if queued ~= clip and not queued.textOnly and queued.source and queued.source.Remove then
            local spot, options = SpotFor(queued, queued.source.key, finished[KeyOf(queued)] == true)
            if spot and Spatial:OutOfEarshot(spot, options) then queued.source:Remove(queued) end
        end
    end
    Skip(clip)
end

local watcher = CreateFrame("Frame")
watcher:Hide()

local function Release()
    held = nil
    if ns.char then ns.char.heldSpoken = nil end
    watcher:Hide()
end

-- While Spoken is stopped on the held line, the lines waiting behind it go ahead.
local function LetOthersPass()
    if not (held and held.paused and Head() == held.clip) then return end
    local nextClip = Queue()[2]
    if nextClip and nextClip.source and nextClip.source.PlayNow then
        held.paused = false -- Spoken plays again; the held line waits behind
        nextClip.source:PlayNow(nextClip)
    end
end

-- Stop Spoken on `clip` until you're back within `back` yards of `spot`.
local function Stop(clip, spot, back)
    if not Spoken.Pause or Head() ~= clip then return false end
    held = held or {}
    held.clip, held.spot, held.back = clip, spot, back
    ns.char.heldSpoken = true -- in case of a reload before it's resumed (see Recover)
    Spoken:Pause()
    if Head() ~= clip then
        -- It had already spoken to its end: Spoken let it go and stopped on the next line.
        Release()
        if Spoken:IsPaused() then Spoken:Resume() end
        return false
    end
    held.paused = true
    if placing == clip then
        placing = nil
        Spatial:End() -- the slider comes back once Spoken has faded the line out
    end
    ns.Markers:Quiet(Speaker(clip), "voice")
    watcher:Show()
    LetOthersPass()
    return true
end

local function Hold(clip, session)
    local full, silent = Spatial:Range(session)
    Stop(clip, session.spot, (full + silent) / 2)
end

local function OnAway(clip, session)
    if placing ~= clip or letPlay[clip] then return end
    local away = ns.db.away
    if away == "skip" then
        Skip(clip)
    elseif away == "skipNpc" then
        SkipSpeaker(clip, session)
    elseif away == "skipAll" then
        SkipEverythingAway(clip)
    elseif away == "wait" then
        local part = clip.source and clip.source.key
        if part == "quests" or part == "gossip" then Hold(clip, session) else Skip(clip) end
    end
end

local CHECK = 0.25
local checked = 0
watcher:SetScript("OnUpdate", ns.Guard(function(_, elapsed)
    checked = checked + elapsed
    if checked < CHECK then return end
    checked = 0
    if not held then
        watcher:Hide()
        return
    end
    if not held.paused then return end -- waiting behind other lines: its turn decides
    if Head() ~= held.clip or not Spoken:IsPaused() then
        Release() -- you played, skipped or cleared it yourself
        return
    end
    local distance = Spatial:DistanceTo(held.spot)
    if distance and distance <= held.back then
        Release()
        Spoken:Resume() -- from the start: the game can't carry on mid-line
    end
end))

--- Give up a held line (the setting changed, or Earshot was switched off): Spoken plays on.
function Link:LetGo()
    if not held then return end
    local paused = held.paused
    Release()
    if paused and self.attached and Spoken:IsPaused() then Spoken:Resume() end
end

--- At login: a reload while a line was held leaves Spoken stopped, with nothing to resume.
function Link:Recover()
    if not (ns.char and ns.char.heldSpoken) then return end
    ns.char.heldSpoken = nil
    if self.attached and Spoken.IsPaused and Spoken:IsPaused() then Spoken:Resume() end
end

--- For /earshot status: the line Earshot is waiting to play, if any.
function Link:Describe()
    if not held then return nil end
    local distance = Spatial:DistanceTo(held.spot)
    if distance and distance < math.huge then
        return ("Waiting to replay a line until you walk back (%d yd away, back within %d)."):format(
            math.floor(distance + 0.5), math.floor(held.back + 0.5))
    end
    return "Waiting to replay a line until you walk back."
end

--------------------------------------------------------------------------------
-- Spoken's events
--------------------------------------------------------------------------------

-- Spoken queues a line when the NPC says it, and starts it once the lines ahead of it are
-- done. Note now where it would go, so it still fades if you walk away before it starts.
local function OnQueued(clip)
    if type(clip) ~= "table" or clip.textOnly then return end
    -- Spoken's Previous queues a line heard before again, marked `rewound` (Spoken 3.12).
    asked[clip] = clip.rewound == true or nil
    queuedNear[clip] = nil -- SpotFor reads it, so forget any earlier note first
    queuedNear[clip] = SpotFor(clip, clip.source and clip.source.key, finished[KeyOf(clip)] == true)
    -- Spoken is stopped on a line you walked away from: let this one go ahead. Not in the
    -- middle of Spoken queuing it, though.
    if held and held.paused then C_Timer.After(0, LetOthersPass) end
end

-- A line from an NPC you walked away from (Skip that NPC's lines): still away?
local function StillSkipped(clip)
    local who = Plain(clip.unitGUID)
    local entry = who and skipped[who]
    if not entry then return false end
    local distance = Spatial:DistanceTo(entry.spot)
    if GetTime() - entry.time > SKIPPED_KEEP or not distance or distance <= entry.silent then
        skipped[who] = nil -- you came back, or it's been a while
        return false
    end
    return true
end

-- Skipped as soon as it starts: a line from an NPC you walked away from (Skip that NPC's
-- lines), or any line you're out of earshot of (Skip every NPC out of earshot).
local function SkipsAsItStarts(clip, spot, options)
    if letPlay[clip] then return false end
    local away = ns.db.away
    if away == "skipAll" then return Spatial:OutOfEarshot(spot, options) end
    return away == "skipNpc" and StillSkipped(clip)
end

-- The held line's turn came round again while you're still away: stop Spoken on it again, a
-- moment after it starts (as with SkipSoon: Spoken sets its timer straight after). If that
-- can't be done now, it plays on, placed.
local function StopAgain(clip)
    if held and held.clip == clip and not held.paused and Stop(clip, held.spot, held.back) then return end
    if placing == clip and Spatial.session then Spatial.session.hushed = nil end
end

local function OnStarted(clip)
    -- Words only, or Spoken is muted (it marks the line `silent`, Spoken 3.12): nothing to hear.
    if type(clip) ~= "table" or clip.textOnly or clip.silent then return end
    local part = clip.source and clip.source.key
    local channel = ChannelOf(clip)
    local spot, options = SpotFor(clip, part, finished[KeyOf(clip)] == true)
    if spot and asked[clip] and Spatial:BeyondFull(spot, options) then
        spot = nil -- you went back to it with Previous: like a replay, from a distance it plays as normal
    end
    local stopAgain = false
    if held and held.clip == clip then
        if held.paused then
            -- Spoken was stopped on it and it plays: you pressed Play. Your call.
            letPlay[clip] = true
            Release()
        elseif spot and (Spatial:DistanceTo(held.spot) or 0) > held.back then
            stopAgain = true -- its turn came round again after the lines that went ahead
        else
            Release() -- you're back
        end
    end
    if spot and not Volume:IsMovable(channel) then
        Warn(channel)
        spot = nil
    end
    if spot then
        options = options or {}
        options.onAway = function(session) OnAway(clip, session) end
    end
    if spot and Spatial:Begin(spot, channel, options) then
        placing = clip
        if stopAgain then
            Spatial:Hush()
            C_Timer.After(0, ns.Guard(function() StopAgain(clip) end))
            return
        end
        if SkipsAsItStarts(clip, spot, options) then
            SkipSoon(clip)
            return
        end
    else
        -- This line plays as normal. If the slider is still lowered from the last one, put it back.
        placing = nil
        Spatial:Clear()
    end
    ns.Markers:Speak(Speaker(clip), "voice")
end

local function OnStopped(clip, finishedPlaying)
    if type(clip) == "table" then
        if finishedPlaying == true then Remember(KeyOf(clip)) end
        if held and held.clip == clip then
            -- Skipped or cleared while held. If Spoken let go of it while still stopped on it,
            -- it has nothing to stop for now.
            local paused = held.paused
            Release()
            if paused and Spoken:IsPaused() then Spoken:Resume() end
        end
        ns.Markers:Quiet(Speaker(clip), "voice")
    end
    if clip ~= nil and clip == placing then
        placing = nil
        Spatial:End()
    end
end

local function OnDropped(clip)
    OnStopped(clip, false) -- the second value is Spoken's reason, not "finished"
end

local function OnEmpty()
    ns.Markers:QuietAll("voice")
    if placing then
        placing = nil
        Spatial:End()
    end
end

-- Muted mid-line (Spoken 3.12), Spoken cuts the voice and lets the words run on, with no stop
-- event. Unmuted, it starts the line again from the top (CLIP_STARTED).
local function OnAudioChanged()
    if placing and placing.silent then
        ns.Markers:Quiet(Speaker(placing), "voice")
        placing = nil
        Spatial:End()
    end
end

-- About how long a line takes to say, for marking an NPC whose words only show in chat.
local function SpeakingTime(text)
    return math.min(12, 2 + #text * 0.06)
end

local function OnChat(event, text, guid)
    text = Plain(text)
    if not text then return end
    local now = GetTime()
    local entry = { kind = CHAT_KIND[event], spot = Anchors:Here(0, false), time = now }
    heard[text] = entry
    -- Spoken hears this event before Earshot does and may already be playing the line,
    -- pinned as if said aloud. A yell carries further; a whisper goes back to normal.
    if entry.kind ~= "say" and placing and placing.text == text
        and placing.source and placing.source.key == "chatter" then
        local session = Spatial.session
        local range = ns.db.yellRange
        if entry.kind == "yell" and range < ns.YELLS_ANYWHERE and session then
            session.full, session.silent = ns.NearPart(range), range
        else
            placing = nil
            Spatial:Clear()
        end
    end
    if entry.kind ~= "whisper" and ns.db.markSilent then
        ns.Markers:Speak(Plain(guid), "chat", SpeakingTime(text))
    end
    for line, old in pairs(heard) do
        if now - old.time > HEARD_KEEP then heard[line] = nil end
    end
end

--- The slider Spoken's voices follow, or nil without Spoken.
function Link:Channel()
    if not self.attached then return nil end
    local ok, channel = pcall(function()
        for _, key in ipairs({ "quests", "gossip", "places", "readables" }) do
            local source = Spoken:GetSource(key)
            if source then return source:GetChannel() end
        end
    end)
    if ok and type(channel) == "string" then return channel end
    return nil
end

--- At login: if Spoken's slider is one Earshot won't move, say how to fix it now rather
--- than at the first voiced NPC. (Spoken's own default is Master Volume.)
function Link:Check()
    local channel = self:Channel()
    if channel and ns.db.enabled and not Volume:IsMovable(channel) then Warn(channel) end
end

function Link:Attach()
    if self.attached then return true end
    if type(Spoken) ~= "table" or type(Spoken.RegisterCallback) ~= "function" then return false end
    Spoken:RegisterCallback("CLIP_QUEUED", ns.Guard(OnQueued))
    Spoken:RegisterCallback("CLIP_STARTED", ns.Guard(OnStarted))
    Spoken:RegisterCallback("CLIP_STOPPED", ns.Guard(OnStopped))
    Spoken:RegisterCallback("CLIP_DROPPED", ns.Guard(OnDropped))
    Spoken:RegisterCallback("QUEUE_EMPTY", ns.Guard(OnEmpty))
    Spoken:RegisterCallback("AUDIO_CHANGED", ns.Guard(OnAudioChanged))
    local chat = CreateFrame("Frame")
    for event in pairs(CHAT_KIND) do chat:RegisterEvent(event) end
    -- The twelfth value is the speaker's GUID.
    chat:SetScript("OnEvent", ns.Guard(function(_, event, text, ...)
        OnChat(event, text, (select(11, ...)))
    end))
    self.attached = true
    return true
end
