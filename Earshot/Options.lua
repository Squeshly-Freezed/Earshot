-- Options.lua: the settings page (Options > AddOns > Earshot, the addon menu on the
-- minimap, or /earshot) and the /earshot command.
local _, ns = ...

local Options = {}
ns.Options = Options

local function Yards(value) return ("%d yd"):format(math.floor(value + 0.5)) end
local function Percent(value) return ("%d%%"):format(math.floor(value + 0.5)) end

-- A checkbox for one of the game's own sound options (the CVar behind it). It has no
-- default, so the page's Defaults button resets Earshot's settings and leaves the game's alone.
local function GameCheckbox(category, cvar, label, tooltip)
    if GetCVar(cvar) == nil then return end -- not in this client
    local setting = Settings.RegisterProxySetting(category, "EARSHOT_GAME_" .. cvar:upper(),
        Settings.VarType.Boolean, label, nil,
        function() return GetCVar(cvar) == "1" end,
        function(value) SetCVar(cvar, value and "1" or "0") end)
    Settings.CreateCheckbox(category, setting, tooltip)
end

-- What happens to a placed voice once you're out of earshot (see SpokenLink).
local AWAY_CHOICES = {
    { value = "quiet", label = "Keep playing quietly",
        tooltip = "The line carries on, faded out (or at Never quieter than)." },
    { value = "skip", label = "Skip the line",
        tooltip = "Spoken moves on to its next line." },
    { value = "skipNpc", label = "Skip that NPC's lines",
        tooltip = "Skips the line, everything else that NPC has waiting, and what it says while you're still away." },
    { value = "skipAll", label = "Skip every NPC out of earshot",
        tooltip = "Skips the line and every line from an NPC you're out of earshot of, waiting or just starting. "
            .. "Whispers, and lines you play yourself, still play." },
    { value = "wait", label = "Wait until you come back",
        tooltip = "Spoken stops a quest or gossip line and replays it when you walk back; other lines play "
            .. "meanwhile. Chatter is skipped instead." },
}

-- The sliders a preset sets.
local PRESET_KEYS = { "full", "silent", "behind", "chatterRange" }

function Options:Register()
    if self.category or not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
    local db = ns.db
    local category, layout = Settings.RegisterVerticalLayoutCategory("Earshot")
    self.category = category

    local function Setting(key, kind, label)
        return Settings.RegisterAddOnSetting(category, "EARSHOT_" .. key:upper(), key, db, kind, label, ns.DEFAULTS[key])
    end
    local function Checkbox(key, label, tooltip)
        local setting = Setting(key, Settings.VarType.Boolean, label)
        local initializer = Settings.CreateCheckbox(category, setting, tooltip)
        return setting, initializer
    end
    local function Slider(key, label, tooltip, step, formatter)
        local setting = Setting(key, Settings.VarType.Number, label)
        local options = Settings.CreateSliderOptions(ns.LIMITS[key][1], ns.LIMITS[key][2], step)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, formatter)
        local initializer = Settings.CreateSlider(category, setting, options, tooltip)
        return setting, initializer
    end
    -- A dropdown, built the way the game's own settings build theirs.
    local function Dropdown(setting, choices, tooltip)
        local function Choices()
            local container = Settings.CreateControlTextContainer()
            for _, choice in ipairs(choices) do container:Add(choice.value, choice.label, choice.tooltip) end
            return container:GetData()
        end
        return Settings.CreateDropdown(category, setting, Choices, tooltip)
    end
    -- Indent a setting under another, usable while `active()` says so. The list greys a row
    -- out again when its parent setting changes.
    local function Under(initializer, parent, active)
        if initializer and initializer.SetParentInitializer then initializer:SetParentInitializer(parent, active) end
        if initializer and initializer.Indent then initializer:Indent() end
    end
    -- Redraw a row when another setting changes too (the game's function takes any setting's
    -- name, though it says CVar).
    local function Hears(initializer, key)
        if initializer and initializer.AddEvaluateStateCVar then
            initializer:AddEvaluateStateCVar("EARSHOT_" .. key:upper())
        end
    end
    -- Earshot's own rows, greyed out while it's switched off (not the game's options or the
    -- buttons, which work either way).
    local rows = {}
    local function Row(initializer)
        table.insert(rows, initializer)
        return initializer
    end
    local function Header(text)
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
    end
    local function Button(label, buttonText, onClick, tooltip)
        layout:AddInitializer(CreateSettingsButtonInitializer(label, buttonText, onClick, tooltip, true))
    end
    local function PresetChanged()
        if Settings.NotifyUpdate then Settings.NotifyUpdate("EARSHOT_PRESET") end
    end

    Header("Distance")
    local enabled = Checkbox("enabled", "Fade voices with distance",
        "While an NPC's voice plays, it gets quieter as you walk away and softer when the NPC is behind you. "
        .. "Works outdoors. In dungeons, raids and battlegrounds the game hides positions, so voices play as normal.")
    enabled:SetValueChangedCallback(function(_, value)
        if not value then
            ns.Spatial:Clear()
            ns.SpokenLink:LetGo()
        end
        ns.Plates:Update()
    end)

    -- Presets: the sliders they set match one of them, or it's your own mix.
    local sliders = {}
    local function PresetNow()
        for _, choice in ipairs(ns.PRESETS) do
            local same = true
            for _, key in ipairs(PRESET_KEYS) do
                if db[key] ~= choice[key] then same = false end
            end
            if same then return choice.key end
        end
        return "custom"
    end
    local preset = Settings.RegisterProxySetting(category, "EARSHOT_PRESET", Settings.VarType.String, "Preset",
        "natural", PresetNow, function(value)
            for _, choice in ipairs(ns.PRESETS) do
                if choice.key == value then
                    for _, key in ipairs(PRESET_KEYS) do sliders[key]:SetValue(choice[key]) end
                end
            end
        end)
    local presetChoices = {}
    for _, choice in ipairs(ns.PRESETS) do
        table.insert(presetChoices, { value = choice.key, label = choice.name, tooltip = choice.tooltip })
    end
    table.insert(presetChoices, { value = "custom", label = "Custom", tooltip = "Your own mix of the sliders." })
    Row(Dropdown(preset, presetChoices,
        "Sets the distance sliders together, and how far chatter carries. Move any of them and this shows Custom."))

    local full, fullInit = Slider("full", "Full volume within", "How close to the speaker a voice stays at full volume.",
        1, Yards)
    local silent, silentInit = Slider("silent", "Silent beyond",
        "How far from the speaker a voice fades out completely. Always at least 5 yards past Full volume within.",
        5, Yards)
    Row(fullInit)
    Row(silentInit)
    -- Keep the two sliders showing what's used: Silent beyond stays 5+ yards past Full volume within.
    full:SetValueChangedCallback(function(_, value)
        if db.silent < value + 5 then
            silent:SetValue(math.min(ns.LIMITS.silent[2], math.ceil((value + 5) / 5) * 5))
        end
        PresetChanged()
    end)
    silent:SetValueChangedCallback(function(_, value)
        if value < db.full + 5 then full:SetValue(math.max(ns.LIMITS.full[1], value - 5)) end
        PresetChanged()
    end)
    local behind, behindInit = Slider("behind", "Volume behind you",
        "How loud a speaker directly behind you sounds. Beside you it's halfway. 100% switches this off.",
        5, Percent)
    Row(behindInit)
    behind:SetValueChangedCallback(PresetChanged)
    sliders.full, sliders.silent, sliders.behind = full, silent, behind
    Row(select(2, Slider("floor", "Never quieter than",
        "A placed voice never gets quieter than this, however far you walk. At 0% voices fade out completely.",
        5, Percent)))
    local away = Setting("away", Settings.VarType.String, "When you walk out of earshot")
    Row(Dropdown(away, AWAY_CHOICES,
        "What happens to a placed voice a moment after you're out of earshot of it: past Silent beyond, or past "
        .. "how far chatter or yells are heard."))
    away:SetValueChangedCallback(function()
        if db.away ~= "wait" then ns.SpokenLink:LetGo() end
    end)

    Header("Voices to place")
    Row(select(2, Checkbox("quests", "Quest and gossip voices",
        "Lines read from an NPC's window. Placed where the NPC stood when you talked to it.")))
    local _, chatterInit = Checkbox("chatter", "World chatter",
        "NPCs talking around you. The game doesn't say where they stand, so the voice stays where you were "
        .. "when the NPC spoke, unless Follow speakers by nameplate finds the NPC. Whispers are said to you, so "
        .. "they play as normal.")
    Row(chatterInit)
    local chatterRange, chatterRangeInit = Slider("chatterRange", "Chatter heard up to",
        "How far from where an NPC spoke its chatter fades out. Full volume within about half of that.", 5, Yards)
    chatterRange:SetValueChangedCallback(PresetChanged)
    sliders.chatterRange = chatterRange
    Under(Row(chatterRangeInit), chatterInit, function() return db.chatter end)
    local _, yellsInit = Slider("yellRange", "Yells heard up to",
        "Yells carry further than talk. Full volume within about half of this. At the top of the slider "
        .. "(Anywhere) yells aren't faded at all.", 10, function(value)
            if value >= ns.YELLS_ANYWHERE then return "Anywhere" end
            return Yards(value)
        end)
    Under(Row(yellsInit), chatterInit, function() return db.chatter end)

    Header("Follow the speaker")
    local follow, followInit = Checkbox("follow", "Follow speakers by nameplate",
        "Keeps track of the talking NPC while it speaks, from its nameplate: how far away it is, and which way. "
        .. "Chatter then comes from the NPC rather than from where you heard it, and an NPC who walks with you "
        .. "stays in earshot.\n\n"
        .. "Out of combat it turns on the game's Friendly NPC nameplates and Always Show Nameplates (which also "
        .. "shows enemy nameplates, unless something like Leatrix Plus's Combat plates hides them). Your own "
        .. "settings come back in combat and when you switch this off.\n\n"
        .. "Outdoors only. In combat a voice it's following keeps its volume until the fight ends.")
    Row(followInit)
    local hide, hideInit = Checkbox("hidePlates", "Hide friendly NPC nameplates",
        "Friendly NPC nameplates show only the NPC's name, and can't be clicked, so following doesn't fill the "
        .. "screen with health bars. Names follow your NPC name settings: once an NPC has a nameplate, its name "
        .. "shows there instead of above its head.\n\n"
        .. "Enemy and player nameplates aren't touched. With a nameplate addon such as Plater, hide friendly NPCs "
        .. "in its settings instead.")
    Under(Row(hideInit), followInit, function() return db.follow end)
    local titles, titlesInit = Checkbox("titles", "Show NPC titles",
        "Puts titles such as <Stable Master> under the names, as the game shows them without nameplates. "
        .. "Read from the NPC's tooltip.")
    Under(Row(titlesInit), hideInit, function() return db.follow and db.hidePlates end)
    Hears(titlesInit, "follow") -- its parent is Hide, but it also depends on Follow
    follow:SetValueChangedCallback(function() ns.Plates:Update() end)
    hide:SetValueChangedCallback(function() ns.Plates:Update() end)
    titles:SetValueChangedCallback(function() ns.Plates:Update() end)

    Header("Who's talking")
    local markers, markersInit = Checkbox("markers", "Mark who's talking",
        "A small speech bubble over the NPC whose voice is playing. It sits on the NPC's nameplate, so it shows "
        .. "with Follow speakers by nameplate on, or with friendly NPC nameplates switched on yourself.")
    Row(markersInit)
    local unvoiced, unvoicedInit = Checkbox("markSilent", "Also NPCs talking without a voice",
        "NPC lines that only show in chat, such as the game's own lines Spoken has no voice for. The bubble stays "
        .. "for about as long as the line takes to say.")
    Under(Row(unvoicedInit), markersInit, function() return db.markers end)
    markers:SetValueChangedCallback(function() ns.Markers:Refresh() end)
    unvoiced:SetValueChangedCallback(function() ns.Markers:Refresh() end)

    -- The game already places its own world sounds. These are two of its own switches.
    Header("The game's own sounds")
    GameCheckbox(category, "Sound_EnablePositionalLowPassFilter", "Distance filtering",
        "The game's own option, also in Options > Audio: muffles world sounds the further away they are.")
    GameCheckbox(category, "Sound_EnableReverb", "Reverb",
        "The game's own option, also in Options > Audio: adds the echo of the place you're in.")

    Header("Test and setup")
    Button("Test sound", "Play", function() ns.Test() end,
        "Plays a short tune a few steps in front of you. Walk away and turn around to hear Earshot at work.")
    Button("Check your setup", "Check", function() ns.Status() end,
        "Says in chat whether Spoken's voices are on a slider Earshot can fade, and what Earshot is doing now. "
        .. "Also /earshot status.")
    if type(Spoken) == "table" and Spoken.OpenSettings then
        Button("Spoken's settings", "Open", function() Spoken:OpenSettings() end,
            "Volume Follows picks the slider Spoken's voices play on: Ambience Volume suits Earshot best. Also "
            .. "/earshot spoken.")
    end

    for _, row in ipairs(rows) do
        if row.AddModifyPredicate then row:AddModifyPredicate(function() return db.enabled end) end
        Hears(row, "enabled")
    end

    Settings.RegisterAddOnCategory(category)
end

local function Where(angle)
    if not angle then return "" end
    local a = math.abs(angle)
    if a <= math.pi / 4 then return ", in front of you" end
    if a >= math.pi * 3 / 4 then return ", behind you" end
    return angle > 0 and ", to your left" or ", to your right"
end

-- /earshot debug: while a voice is placed, a line a second on where Earshot has the speaker,
-- and what following read from the game. Lasts until /reload.
local debugAt = 0
function ns.DebugTick(session)
    if not ns.debug then return end
    local now = GetTime()
    if now - debugAt < 1 then return end
    debugAt = now
    local info = ns.Spatial.info
    local where = info and info.distance and ("%d yd away%s"):format(math.floor(info.distance + 0.5), Where(info.angle))
        or "somewhere Earshot can't tell"
    ns.Print("Debug: voice %s, at %d%%. %s", where, math.floor(ns.Spatial.level * 100 + 0.5), ns.Plates:Trace(session))
end

function ns.Status()
    local db = ns.db
    ns.Print(db.enabled and "On." or "Off. Type /earshot on to switch it on.")
    local channel = ns.SpokenLink:Channel()
    if not ns.SpokenLink.attached then
        ns.Print("Spoken isn't loaded. The test sound and addons that use Earshot's API still work.")
    elseif not channel then
        ns.Print("Spoken is loaded, but none of its voice parts are.")
    elseif ns.Volume:IsMovable(channel) then
        ns.Print("Spoken's voices follow %s, which Earshot can fade. You're set.", ns.CHANNEL_NAMES[channel])
    else
        ns.Print("Spoken's voices follow %s, which also carries other game sounds, so Earshot leaves it alone. "
            .. "Set Volume Follows to Ambience Volume in Spoken's settings (/earshot spoken).",
            ns.CHANNEL_NAMES[channel] or channel)
    end
    if ns.SpokenLink.attached and Spoken.IsMuted and Spoken:IsMuted() then
        ns.Print("Spoken is muted, so its lines are words only and there's nothing to fade.")
    end
    if not ns.PlayerPosition() then
        ns.Print("The game hides positions here, so voices play as normal.")
    end
    if ns.Plates.Following() then
        ns.Print("Following speakers by nameplate%s.",
            db.hidePlates and ", with friendly NPC nameplates showing only their names" or "")
    end
    local session = ns.Spatial.session
    local info = session and ns.Spatial.info
    if info and info.elsewhere then
        ns.Print("The speaker is out of earshot (another continent, or you're in an instance).")
    elseif info and info.distance then
        ns.Print("Placing a voice %d yd away%s, at %d%% volume.", math.floor(info.distance + 0.5),
            Where(info.angle), math.floor(ns.Spatial.level * 100 + 0.5))
        local following = ns.Plates:Describe(session)
        if following then ns.Print(following) end
    end
    local waiting = ns.SpokenLink:Describe()
    if waiting then ns.Print(waiting) end
end

function Options:Open()
    if self.category then Settings.OpenToCategory(self.category:GetID()) end
end

-- The addon menu on the minimap (the TOC names these).
function Earshot_OnAddonCompartmentClick()
    Options:Open()
end

-- One line on what Earshot is doing, and its colour: for the minimap addon menu's tooltip.
function Options:Summary()
    if not ns.db.enabled then return "Off: voices play as normal.", 0.62, 0.62, 0.62 end
    local channel = ns.SpokenLink.attached and ns.SpokenLink:Channel()
    if channel and not ns.Volume:IsMovable(channel) then
        return ("Spoken's voices follow %s, so Earshot can't fade them. Click, then Spoken's settings."):format(
            ns.CHANNEL_NAMES[channel] or channel), 1, 0.5, 0.25
    end
    if not ns.SpokenLink.attached then return "On. Spoken isn't loaded.", 1, 0.82, 0 end
    return "On: NPC voices fade as you walk away.", 0.25, 1, 0.25
end

function Earshot_OnAddonCompartmentEnter(_, button)
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:SetText("Earshot")
    local line, r, g, b = Options:Summary()
    GameTooltip:AddLine(line, r, g, b, true)
    GameTooltip:AddLine("Click to open the settings.", 1, 1, 1)
    GameTooltip:Show()
end

function Earshot_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end

SLASH_EARSHOT1 = "/earshot"
SlashCmdList.EARSHOT = function(input)
    local command = (input or ""):lower():match("^%s*(%S*)")
    if command == "test" then
        ns.Test()
    elseif command == "status" then
        ns.Status()
    elseif command == "spoken" then
        if type(Spoken) == "table" and Spoken.OpenSettings then Spoken:OpenSettings() else ns.Print("Spoken isn't loaded.") end
    elseif command == "on" or command == "off" then
        ns.db.enabled = command == "on"
        if not ns.db.enabled then
            ns.Spatial:Clear()
            ns.SpokenLink:LetGo()
        end
        ns.Plates:Update()
        if Settings and Settings.NotifyUpdate then Settings.NotifyUpdate("EARSHOT_ENABLED") end
        ns.Print(ns.db.enabled and "On." or "Off.")
    elseif command == "debug" then
        ns.debug = not ns.debug
        ns.Print(ns.debug and "Debug readout on: a line a second while a voice is placed. /earshot debug again turns it off."
            or "Debug readout off.")
    elseif command == "help" or not Options.category then
        ns.Print("/earshot opens the settings. Also: /earshot test, status, spoken, on, off, debug.")
    else
        Options:Open()
    end
end
