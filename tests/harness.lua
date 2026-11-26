-- A pretend WoW client: just enough of the game's API to run Earshot's real code
-- through scenarios. Run with tests/run.py (Lua 5.1, the version WoW uses).
local ADDON_DIR = ADDON_DIR
local results = { passed = 0, failed = 0, lines = {} }

local function note(line) table.insert(results.lines, line) end
local function check(ok, label, detail)
    if ok then
        results.passed = results.passed + 1
    else
        results.failed = results.failed + 1
        note("  FAIL " .. label .. (detail and ("  [" .. detail .. "]") or ""))
    end
end
local function near(a, b, tolerance) return a ~= nil and b ~= nil and math.abs(a - b) <= (tolerance or 0.002) end

local function ReadFile(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a")
    f:close()
    return text
end

local function TocFiles()
    local files = {}
    for line in ReadFile(ADDON_DIR .. "/Earshot.toc"):gmatch("[^\r\n]+") do
        -- Bundled libraries are swapped for fakes (see NewClient); they're syntax-checked separately.
        if not line:find("^##") and line:find("%S") and not line:find("^Libs") then table.insert(files, line) end
    end
    return files
end

local clients = {} -- the clients the running scenario built, for the checks after it

-- Builds a fresh client with the addon loaded. opts.spoken = channel name, or nil for no Spoken.
local function NewClient(opts)
    opts = opts or {}
    local H = {
        now = 0, frames = {}, timers = {}, chat = {}, errors = {}, sounds = {}, units = {},
        globalWrites = {}, undefinedReads = {}, cvarLog = {},
        player = { north = 0, west = 0, instance = 0, facing = 0, inInstance = false },
        cvars = {
            Sound_MasterVolume = "1", Sound_SFXVolume = "1", Sound_MusicVolume = "0.4",
            Sound_AmbienceVolume = "0.8", Sound_DialogVolume = "1",
            Sound_EnablePositionalLowPassFilter = "1", Sound_EnableReverb = "0",
            nameplateShowFriendlyNpcs = "0", nameplateShowAll = "0",
        },
        cvarDefaults = { Sound_EnablePositionalLowPassFilter = "1", Sound_EnableReverb = "0" },
        settings = { registered = {}, controls = {}, categories = {}, page = {} },
    }
    table.insert(clients, H)
    local env = {}
    for _, k in ipairs({ "math", "string", "table", "pairs", "ipairs", "type", "tostring", "tonumber", "select",
        "pcall", "error", "assert", "setmetatable", "getmetatable", "next", "rawget", "rawset", "unpack" }) do
        env[k] = _G[k]
    end
    env.format = string.format

    -- Frames, events, OnUpdate, timers
    local Frame = {}
    Frame.__index = Frame
    function Frame:RegisterEvent(e) self.events[e] = true end
    function Frame:UnregisterEvent(e) self.events[e] = nil end
    function Frame:SetScript(name, fn) self.scripts[name] = fn end
    function Frame:Show() self.shown = true end
    function Frame:Hide() self.shown = false end
    function Frame:IsShown() return self.shown end
    function Frame:SetSize(w, h) self.width, self.height = w, h end
    function Frame:SetParent(parent) self.parent = parent end
    function Frame:GetParent() return self.parent end
    function Frame:SetFrameLevel(level) self.level = level end
    function Frame:GetFrameLevel() return self.level or 1 end
    function Frame:SetPoint(...) self.points = self.points or {}; table.insert(self.points, { ... }) end
    function Frame:ClearAllPoints() self.points = {} end
    -- Textures and font strings: just enough to see what the addon drew.
    local function Region(owner)
        local r = { shown = true, owner = owner }
        function r:SetAllPoints() self.allPoints = true end
        function r:SetTexture(path) self.texture = path end
        function r:SetPoint(...) self.points = self.points or {}; table.insert(self.points, { ... }) end
        function r:ClearAllPoints() self.points = {} end
        function r:SetFont(font, size, flags) self.font, self.size, self.flags = font, size, flags end
        function r:SetFontObject(object) assert(object ~= nil, "SetFontObject(nil)"); self.fontObject = object end
        function r:SetTextColor(red, green, blue) self.color = { red, green, blue } end
        function r:SetVertexColor(red, green, blue) self.tint = { red, green, blue } end
        function r:SetText(text)
            assert(self.font or self.fontObject, "FontString:SetText(): Font not set")
            self.text = text
        end
        function r:GetText() return self.text end
        function r:Show() self.shown = true end
        function r:Hide() self.shown = false end
        function r:IsShown() return self.shown end
        return r
    end
    H.Region = Region
    function Frame:CreateTexture() local t = Region(self); self.textures = self.textures or {}; table.insert(self.textures, t); return t end
    function Frame:CreateFontString() local t = Region(self); self.fontStrings = self.fontStrings or {}; table.insert(self.fontStrings, t); return t end
    function Frame:CreateAnimationGroup()
        local group = { playing = false }
        function group:SetLooping(kind) self.looping = kind end
        function group:CreateAnimation()
            local a = {}
            function a:SetFromAlpha(v) self.from = v end
            function a:SetToAlpha(v) self.to = v end
            function a:SetDuration(v) self.duration = v end
            return a
        end
        function group:Play() self.playing = true end
        function group:Stop() self.playing = false end
        return group
    end
    env.CreateFrame = function(_, _, parent)
        local f = setmetatable({ events = {}, scripts = {}, shown = true, parent = parent }, Frame)
        table.insert(H.frames, f)
        return f
    end
    function H.Fire(event, ...)
        for _, f in ipairs(H.frames) do
            if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
        end
    end
    H.minCVar = {}
    function H.Advance(seconds)
        local target = H.now + seconds
        while H.now < target - 1e-9 do
            local dt = math.min(1 / 60, target - H.now)
            H.now = H.now + dt
            for i = #H.timers, 1, -1 do
                local t = H.timers[i]
                if t.at <= H.now then
                    table.remove(H.timers, i)
                    t.fn()
                end
            end
            for _, f in ipairs(H.frames) do
                if f.shown and f.scripts.OnUpdate then f.scripts.OnUpdate(f, dt) end
            end
        end
    end
    function H.UpdatesRunning()
        for _, f in ipairs(H.frames) do
            if f.shown and f.scripts.OnUpdate then return true end
        end
        return false
    end
    env.C_Timer = { After = function(seconds, fn) table.insert(H.timers, { at = H.now + seconds, fn = fn }) end }
    env.GetTime = function() return H.now end

    -- CVars are strings in WoW
    env.GetCVar = function(name) return H.cvars[name] end
    env.SetCVar = function(name, value)
        if H.cvars[name] == nil then error("SetCVar on unknown CVar " .. tostring(name)) end
        if H.inCombat and name:find("^nameplate") then error("nameplate options are locked in combat") end
        if type(value) == "number" then value = string.format("%.6g", value) end
        H.cvars[name] = tostring(value)
        table.insert(H.cvarLog, { name = name, value = tonumber(value) })
        return true
    end
    env.C_CVar = { GetCVarDefault = function(name) return H.cvarDefaults[name] end }
    function H.Vol(channel) return tonumber(H.cvars["Sound_" .. channel .. "Volume"]) end

    -- Where the player is
    env.UnitPosition = function(unit)
        if unit ~= "player" or H.player.inInstance then return nil end
        return H.player.north, H.player.west, 0, H.player.instance
    end
    env.GetPlayerFacing = function()
        if H.player.inInstance then return nil end
        return H.player.facing
    end
    env.IsInInstance = function() return H.player.inInstance, H.player.inInstance and "party" or "none" end
    env.UnitExists = function(unit) return H.units[unit] ~= nil end
    env.UnitGUID = function(unit) return H.units[unit] and H.units[unit].guid end
    env.UnitName = function(unit) return H.units[unit] and H.units[unit].name end
    -- A stand-in for a value the game keeps secret from addons.
    H.SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
    env.issecretvalue = function(value) return value == H.SECRET end

    -- Nameplates, the camera and range checks, all worked out from where NPCs really stand.
    -- H.npcs[guid] = { north, west, assist }; H.ShowPlate(guid, kind) gives it a nameplate.
    H.npcs, H.plates, H.mouselook, H.speed, H.inCombat, H.plateCount = {}, {}, true, 0, false, 0
    env.InCombatLockdown = function() return H.inCombat end
    env.IsMouselooking = function() return H.mouselook end
    env.GetUnitSpeed = function() return H.speed end
    env.UnitIsPlayer = function(unit) local u = H.units[unit]; return u ~= nil and u.player == true end
    env.UnitPlayerControlled = function(unit)
        local u = H.units[unit]; return u ~= nil and (u.player == true or u.controlled == true)
    end
    env.UnitCanAttack = function(_, unit) local u = H.units[unit]; return u ~= nil and u.attackable == true end
    env.NamePlateSetupOptions = {}
    env.WorldFrame = {
        GetLeft = function() return 0 end, GetWidth = function() return 1920 end,
        GetBottom = function() return 0 end, GetHeight = function() return 1000 end,
        GetEffectiveScale = function() return 1 end,
    }
    H.tooltipLines = {}
    env.GameTooltip = {
        SetOwner = function() end,
        SetText = function(_, text) H.tooltipLines = { text } end,
        AddLine = function(_, text) table.insert(H.tooltipLines, text) end,
        Show = function() H.tooltipShown = true end, Hide = function() H.tooltipShown = false end,
    }
    env.hooksecurefunc = function(tbl, name, hook)
        if type(tbl) == "string" then tbl, name, hook = env, tbl, name end -- a global function
        local original = rawget(tbl, name)
        assert(type(original) == "function", "hooksecurefunc on a missing method " .. tostring(name))
        rawset(tbl, name, function(...)
            local results = { original(...) }
            hook(...)
            return unpack(results)
        end)
    end
    -- The game's own name update for unit frames and nameplates (the addon hooks it). Like the
    -- game's in every nameplate style but Legacy, it draws names white, and a dead NPC's grey.
    env.CompactUnitFrame_UpdateName = function(frame)
        H.nameUpdates = (H.nameUpdates or 0) + 1
        local name = type(frame) == "table" and frame.name
        if name and name.SetVertexColor then
            local u = H.units[frame.unit]
            if u and u.dead and not u.player then
                name:SetVertexColor(0.5, 0.5, 0.5)
            elseif H.legacyStyle then -- the Legacy style colours names like those above heads
                local r, g, b = env.UnitSelectionColor(frame.unit, true)
                name:SetVertexColor(r, g, b)
            else
                name:SetVertexColor(1, 1, 1)
            end
        end
    end
    env.UnitIsDead = function(unit) local u = H.units[unit]; return u ~= nil and u.dead == true end
    -- The colours of names above units' heads: green friendly, yellow neutral, red hostile.
    -- H.npcs[guid].reaction as from UnitReaction (4 neutral, 5 and up friendly).
    env.UnitSelectionColor = function(unit)
        local u = H.units[unit]
        if not u then return 1, 1, 1, 1 end
        if H.selectionSecret then return H.SECRET, H.SECRET, H.SECRET, 1 end
        local npc = u.guid and H.npcs[u.guid] or {}
        local reaction = npc.reaction or (u.attackable and 2 or 5)
        if reaction >= 5 then return 0, 1, 0, 1 elseif reaction == 4 then return 1, 1, 0, 1 end
        return 1, 0, 0, 1
    end
    env.LEVEL = "Level"
    env.Enum = { TooltipDataLineType = { UnitName = 2 } }
    -- Tooltip data: the NPC's name, its title if it has one (H.npcs[guid].title), then its level.
    H.tooltipReads = 0
    env.C_TooltipInfo = {
        GetUnit = function(token)
            local u = H.units[token]
            if not u then return nil end
            H.tooltipReads = H.tooltipReads + 1
            local npc = u.guid and H.npcs[u.guid] or {}
            local lines = { { leftText = u.name or "Somebody", type = 2 } }
            if npc.title then table.insert(lines, { leftText = npc.title, type = 0 }) end
            table.insert(lines, { leftText = "Level 30 Humanoid", type = 0 })
            return { lines = lines }
        end,
    }
    -- An NPC's distance and angle from the player (+ = left). The camera faces where the player does.
    local function Relative(guid)
        local npc = H.npcs[guid]
        local dn, dw = npc.north - H.player.north, npc.west - H.player.west
        local angle = (math.atan2(dw, dn) - H.player.facing) % (2 * math.pi)
        if angle > math.pi then angle = angle - 2 * math.pi end
        return math.sqrt(dn * dn + dw * dw), angle
    end
    H.Relative = Relative
    -- The camera sits H.cameraZoom yards behind the player (0: at the player), looking the way
    -- the player faces. Where an NPC is from it: how far ahead, and the angle off its view
    -- (+ = left). An NPC between the camera and the player is ahead of the camera too.
    -- It looks down at the player at H.cameraPitch, and a nameplate sits H.plateLift yards
    -- above the height it looks at.
    H.cameraZoom, H.cameraPitch, H.plateLift = 0, math.rad(20), 1
    env.GetCameraZoom = function() return H.cameraZoom end
    local function FromCamera(guid)
        local distance, angle = Relative(guid)
        local ahead = distance * math.cos(angle) + H.cameraZoom
        return ahead, math.atan2(distance * math.sin(angle), ahead)
    end
    local function NPCOf(token) local u = H.units[token]; return u and u.guid and H.npcs[u.guid] and u.guid end
    env.C_NamePlateManager = {
        IsNamePlateUnitBehindCamera = function(token)
            local guid = NPCOf(token)
            if not guid then return false end
            return (FromCamera(guid)) <= 0
        end,
    }
    env.C_NamePlate = {
        GetNamePlateForUnit = function(token) return H.plates[token] end,
        GetNamePlates = function()
            local list = {}
            for _, plate in pairs(H.plates) do table.insert(list, plate) end
            return list
        end,
    }
    -- A fake LibRangeCheck that answers the way the real one does on Forever (its friendRC,
    -- friendNoItemsRC and miscRC lists). For an NPC you can assist: its 5 yd item check plus
    -- your class's friendly spells (H.friendSpells: none for a rogue, { 30, 40 } for a
    -- priest). Told to leave items out (the third argument), or for an NPC you can't assist:
    -- the interaction distances, 8 and 28 yd, plus those spells if you can assist it.
    H.friendSpells = {}
    local ITEM, INTERACT = { 5 }, { 8, 28 }
    local RangeCheck = {
        GetRange = function(_, token, _, noItems)
            local guid = NPCOf(token)
            if not guid then return nil end
            local assist = H.npcs[guid].assist
            local steps = {}
            for _, step in ipairs((assist and not noItems) and ITEM or INTERACT) do table.insert(steps, step) end
            if assist then
                for _, step in ipairs(H.friendSpells) do table.insert(steps, step) end
            end
            table.sort(steps)
            local distance = Relative(guid)
            local low = 0
            for _, step in ipairs(steps) do
                if distance <= step then return low, step end
                low = step
            end
            return low, nil
        end,
    }
    rawset(env, "LibStub", setmetatable({}, {
        __call = function(_, name) if name == "LibRangeCheck-3.0" then return RangeCheck end end,
    }))
    function H.ShowPlate(guid, kind)
        H.plateCount = H.plateCount + 1
        local token = "nameplate" .. H.plateCount
        kind = kind or "npc"
        H.units[token] = { guid = guid, player = kind == "player", controlled = kind == "pet", attackable = kind == "enemy" }
        -- The game reuses the visible part of an old nameplate when it can. Its parts are the
        -- ones in the game's nameplate template; the selection highlight starts a quarter
        -- visible and the aggro flash see-through.
        local face = H.freeFaces and table.remove(H.freeFaces)
        if not face then
            face = { alpha = 1 }
            for _, key in ipairs({ "name", "HealthBarsContainer", "CastBarsContainer", "AurasFrame",
                "ClassificationFrame", "RaidTargetFrame", "PlayerLevelDiffFrame", "LevelFrame", "WidgetContainer",
                "SoftTargetFrame", "behindCameraIcon", "selectionHighlight", "aggroHighlightBase",
                "aggroHighlightAdditive", "aggroFlash" }) do
                local part = { alpha = 1, shown = true }
                function part:SetAlpha(a) self.alpha = a end
                function part:GetAlpha() return self.alpha end
                function part:IsShown() return self.shown end
                face[key] = part
            end
            face.selectionHighlight.alpha, face.aggroFlash.alpha = 0.25, 0
            function face.name:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "OUTLINE" end
            function face.name:GetTextColor() return 1, 1, 1 end
            face.name.tint = { 1, 1, 1 }
            function face.name:SetVertexColor(r, g, b) self.tint = { r, g, b } end
            function face.name:GetVertexColor() return self.tint[1], self.tint[2], self.tint[3] end
            function face:CreateFontString()
                local fs = H.Region(self)
                self.fontStrings = self.fontStrings or {}
                table.insert(self.fontStrings, fs)
                return fs
            end
            function face:GetFrameLevel() return 3 end
        end
        local plate = { unitToken = token, UnitFrame = face, clickable = true }
        face.unit, face.plate = token, plate
        function face:SetAlpha(a) self.alpha = a end
        function face:GetNamePlateFrame() return self.plate end
        if not face.UpdateHitTestArea then
            function face:UpdateHitTestArea() self.plate.clickable = true end -- what the game's code does
        end
        function plate:ClearAllHitTestPoints() self.clickable = false end
        function plate:IsVisible()
            local here = NPCOf(self.unitToken)
            if not here then return true end
            local ahead, angle = FromCamera(here)
            return ahead > 0 and math.abs(angle) < math.pi / 4
        end
        function plate:GetCenter()
            local here = NPCOf(self.unitToken)
            if not here then return 960, 500 end
            local ahead, angle = FromCamera(here)
            local lift = H.plateLift + (H.npcs[here].height or 0) -- an NPC on a balcony is higher up
            local drop = math.atan2(H.cameraZoom * math.tan(H.cameraPitch) - lift, ahead)
            return 960 * (1 - math.tan(angle)), 500 + 500 * math.tan(H.cameraPitch - drop) / math.tan(math.rad(30))
        end
        function plate:GetEffectiveScale() return 1 end
        function plate:GetFrameLevel() return 2 end
        H.plates[token] = plate
        -- The game sets the nameplate up for its unit, name included, before addons hear of it.
        face:UpdateHitTestArea(env.NamePlateSetupOptions)
        env.CompactUnitFrame_UpdateName(face)
        H.Fire("NAME_PLATE_UNIT_ADDED", token)
        return token, plate
    end
    function H.RemovePlate(token)
        local plate = H.plates[token]
        H.Fire("NAME_PLATE_UNIT_REMOVED", token)
        H.plates[token], H.units[token] = nil, nil
        H.freeFaces = H.freeFaces or {}
        table.insert(H.freeFaces, plate.UnitFrame)
    end

    -- Sound, chat, errors
    env.PlaySoundFile = function(path, channel)
        H.handle = (H.handle or 0) + 1
        table.insert(H.sounds, { path = path, channel = channel, handle = H.handle })
        return true, H.handle
    end
    env.StopSound = function(handle) H.stopped = handle end
    env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) table.insert(H.chat, text) end }
    env.geterrorhandler = function() return function(err) table.insert(H.errors, tostring(err)) end end
    env.SlashCmdList = {}
    env.MinimalSliderWithSteppersMixin = { Label = { Right = 2 } }

    -- Settings: the real signatures (from the Forever UI source), checked strictly
    local Settings = { VarType = { Boolean = "boolean", String = "string", Number = "number" } }
    local Setting = {}
    Setting.__index = Setting
    function Setting:SetValueChangedCallback(fn) self.callback = fn end
    function Setting:GetValue() if self.getter then return self.getter() end return self.tbl[self.key] end
    function Setting:SetValue(v)
        if self.setter then self.setter(v) else self.tbl[self.key] = v end
        if self.callback then self.callback(self, v) end
    end
    -- The page's Defaults button: a setting without a default is left alone.
    function Setting:SetValueToDefault()
        if self.default == nil then return false end
        self:SetValue(self.default)
        return true
    end
    -- A row on the page. Like the game's, it is greyed out unless every modify predicate
    -- passes, and it is redrawn only when its parent's setting, or a setting it names,
    -- changes.
    local function NewInitializer(fields)
        local initializer = fields
        function initializer:Indent() self.indented = true end
        function initializer:SetParentInitializer(parent, predicate)
            assert(type(parent) == "table" and parent.setting, "parent must be another initializer")
            assert(predicate == nil or type(predicate) == "function", "modify predicate")
            self.parent = parent
            if predicate then self:AddModifyPredicate(predicate) end
        end
        function initializer:AddModifyPredicate(fn)
            assert(type(fn) == "function", "modify predicate")
            self.predicates = self.predicates or {}
            table.insert(self.predicates, fn)
        end
        function initializer:EvaluateModifyPredicates()
            for _, fn in ipairs(self.predicates or {}) do
                if not fn() then return false end
            end
            return true
        end
        function initializer:AddEvaluateStateCVar(variable)
            assert(type(variable) == "string", "a setting's or CVar's name")
            self.evaluateOn = self.evaluateOn or {}
            table.insert(self.evaluateOn, variable)
        end
        return initializer
    end
    local function isVarType(t) return t == "boolean" or t == "number" or t == "string" end
    function Settings.RegisterVerticalLayoutCategory(name)
        assert(type(name) == "string", "category name")
        local category = { name = name, id = #H.settings.categories + 1 }
        function category:GetID() return self.id end
        local layout = { initializers = {} }
        function layout:AddInitializer(init)
            assert(type(init) == "table", "initializer")
            table.insert(self.initializers, init)
            table.insert(H.settings.page, init)
        end
        table.insert(H.settings.categories, category)
        return category, layout
    end
    function Settings.RegisterAddOnSetting(category, variable, key, tbl, kind, name, default)
        assert(type(category) == "table", "category")
        assert(type(variable) == "string" and not H.settings.registered[variable], "unique variable " .. tostring(variable))
        assert(type(key) == "string" and type(tbl) == "table" and isVarType(kind), "key/table/type for " .. variable)
        assert(type(tbl[key]) == kind, "saved value type for " .. key)
        assert(type(default) == kind, "default type for " .. key)
        assert(type(name) == "string", "label")
        local s = setmetatable({ variable = variable, key = key, tbl = tbl, type = kind, default = default, name = name },
            Setting)
        H.settings.registered[variable] = s
        return s
    end
    function Settings.RegisterProxySetting(category, variable, kind, name, default, get, set)
        assert(type(category) == "table", "category")
        assert(type(variable) == "string" and not H.settings.registered[variable], "unique variable " .. tostring(variable))
        assert(isVarType(kind) and (default == nil or type(default) == kind), "proxy default type for " .. variable)
        assert(type(get) == "function" and type(set) == "function", "proxy get/set")
        assert(type(get()) == kind, "proxy getter type for " .. variable)
        local s = setmetatable({ variable = variable, type = kind, default = default, getter = get, setter = set,
            name = name }, Setting)
        H.settings.registered[variable] = s
        return s
    end
    function Settings.CreateCheckbox(category, setting, tooltip)
        assert(type(category) == "table" and setting and setting.type == "boolean", "checkbox needs a boolean setting")
        local initializer = NewInitializer({ setting = setting, kind = "checkbox", tooltip = tooltip })
        table.insert(H.settings.controls, { kind = "checkbox", setting = setting, initializer = initializer })
        table.insert(H.settings.page, initializer)
        return initializer
    end
    function Settings.CreateSliderOptions(low, high, step)
        local options = { low = low, high = high, step = step }
        function options:SetLabelFormatter(labelType, fn)
            assert(labelType ~= nil and type(fn) == "function", "slider label formatter")
            self.formatter = fn
        end
        return options
    end
    function Settings.CreateSlider(category, setting, options, tooltip)
        assert(setting and setting.type == "number" and options and options.formatter, "slider")
        local v = setting:GetValue()
        assert(v >= options.low and v <= options.high, "default inside slider range for " .. setting.variable)
        assert(type(options.formatter(v)) == "string", "formatter returns text")
        local initializer = NewInitializer({ setting = setting, kind = "slider", tooltip = tooltip, options = options })
        table.insert(H.settings.controls, { kind = "slider", setting = setting, initializer = initializer,
            options = options })
        table.insert(H.settings.page, initializer)
        return initializer
    end
    function Settings.CreateControlTextContainer()
        local container = { data = {} }
        function container:Add(value, label, tooltip)
            assert(value ~= nil and type(label) == "string", "dropdown entry needs a value and a label")
            table.insert(self.data, { value = value, label = label, tooltip = tooltip })
        end
        function container:GetData() return self.data end
        return container
    end
    function Settings.CreateDropdown(category, setting, getOptions, tooltip)
        assert(type(category) == "table" and setting, "dropdown category and setting")
        assert(type(getOptions) == "function", "dropdown options come from a function")
        local data = getOptions()
        assert(type(data) == "table" and #data > 0, "dropdown has entries")
        local current, found = setting:GetValue(), false
        for _, entry in ipairs(data) do
            assert(type(entry.value) == setting.type, "entry value type for " .. setting.variable)
            if entry.value == current then found = true end
        end
        assert(found, "the current value is one of the entries for " .. setting.variable)
        local initializer = NewInitializer({ setting = setting, kind = "dropdown", tooltip = tooltip, data = data })
        table.insert(H.settings.controls, { kind = "dropdown", setting = setting, data = data, initializer = initializer })
        table.insert(H.settings.page, initializer)
        return initializer
    end
    function Settings.RegisterAddOnCategory(category) H.settings.addonCategory = category end
    function Settings.OpenToCategory(id) H.settings.opened = id end
    function Settings.NotifyUpdate(variable) H.settings.notified = variable end
    env.Settings = Settings
    env.CreateSettingsListSectionHeaderInitializer = function(name)
        assert(type(name) == "string", "header name")
        return { header = name, kind = "header" }
    end
    env.CreateSettingsButtonInitializer = function(name, text, click, tooltip, addSearchTags)
        assert(addSearchTags ~= nil, "Blizzard asserts addSearchTags ~= nil")
        assert(type(click) == "function", "button click")
        local initializer = NewInitializer({ button = name, buttonText = text, tooltip = tooltip, kind = "button" })
        table.insert(H.settings.controls, { kind = "button", name = name, click = click, initializer = initializer })
        return initializer
    end

    -- Spoken, as seen through its public API
    if opts.spoken then
        H.spokenChannel = opts.spoken
        local callbacks, sources = {}, {}
        for _, key in ipairs({ "quests", "gossip", "chatter", "places", "readables", "bosses" }) do
            sources[key] = { key = key, GetChannel = function() return H.spokenChannel end }
        end
        H.sources = sources
        function H.Spoken(event, a, b)
            for _, fn in ipairs(callbacks[event] or {}) do
                local ok, err = pcall(fn, a, b) -- Spoken pcalls each subscriber
                if not ok then table.insert(H.errors, "Spoken swallowed: " .. tostring(err)) end
            end
        end
        -- Its queue: the first line plays (unless Spoken is stopped); a line that ends or is
        -- removed lets the next one start; Resume plays the first line again from the start.
        H.queue, H.paused, H.playing, H.skips, H.playNows = {}, opts.spokenPaused == true, nil, 0, 0
        H.strayTimers, H.muted, H.history = 0, opts.spokenMuted == true, {}
        local function StartFirst()
            local first = H.queue[1]
            if not first then
                H.playing = nil
                H.Spoken("QUEUE_EMPTY")
            elseif not H.paused then
                H.playing = first
                -- Muted (Spoken 3.12), a line plays as words only, marked before it's announced.
                first.silent = (first.textOnly or H.muted) and true or nil
                H.Spoken("CLIP_STARTED", first)
                -- Spoken sets a line's timer only after telling everyone it started. A line stopped
                -- in between is later ended as if it had played; one skipped in between leaves the
                -- timer running, which can sound the cue between lines at the wrong moment.
                if H.playing ~= first then H.strayTimers = H.strayTimers + 1 end
            end
        end
        -- Spoken 3.12 keeps the last ten lines that finished or were skipped, for Previous.
        local function Remember(clip)
            for i = #H.history, 1, -1 do
                if H.history[i] == clip then table.remove(H.history, i) end
            end
            table.insert(H.history, clip)
            while #H.history > 10 do table.remove(H.history, 1) end
        end
        local function RemoveAt(index, finished)
            local clip = table.remove(H.queue, index)
            if not clip then return end
            clip.rewound = nil
            if finished then Remember(clip) end
            if H.playing == clip then H.playing = nil end
            H.Spoken("CLIP_STOPPED", clip, finished == true)
            if index == 1 then StartFirst() end
        end
        function H.Queue(clip)
            table.insert(H.queue, clip)
            H.Spoken("CLIP_QUEUED", clip)
            if #H.queue == 1 and not H.paused then StartFirst() end
        end
        function H.FinishLine() RemoveAt(1, true) end
        for _, source in pairs(sources) do
            function source:Remove(clip)
                for i, c in ipairs(H.queue) do
                    if c == clip then return RemoveAt(i, false) end
                end
            end
            function source:PlayNow(clip)
                if H.playing and not H.paused then return H.Queue(clip) end
                for i, c in ipairs(H.queue) do
                    if c == clip then table.remove(H.queue, i) break end
                end
                table.insert(H.queue, 1, clip)
                H.paused = false
                H.playNows = H.playNows + 1
                StartFirst()
            end
        end
        rawset(env, "Spoken", {
            RegisterCallback = function(_, event, fn)
                callbacks[event] = callbacks[event] or {}
                table.insert(callbacks[event], fn)
                return {}
            end,
            GetSource = function(_, key) return sources[key] end,
            OpenSettings = function() H.spokenOpened = true end,
            GetCurrent = function() return H.queue[1] end,
            GetQueue = function()
                local copy = {}
                for i, c in ipairs(H.queue) do copy[i] = c end
                return copy
            end,
            IsPaused = function() return H.paused end,
            IsMuted = function() return H.muted end,
            Skip = function()
                H.skips = H.skips + 1
                H.paused = false
                if H.queue[1] then
                    Remember(H.queue[1])
                    RemoveAt(1, false)
                end
                return true
            end,
            -- Spoken 3.12: the line heard last plays ahead of the current one, which is stopped,
            -- kept, and speaks again from its start afterwards.
            Previous = function()
                local previous = table.remove(H.history)
                if not previous then return false end
                local head = H.queue[1]
                if head then head.rewound = true end
                previous.rewound = true
                table.insert(H.queue, math.min(2, #H.queue + 1), previous)
                H.Spoken("CLIP_QUEUED", previous)
                if H.queue[1] ~= previous then
                    if H.playing == head then
                        H.playing = nil
                        H.Spoken("CLIP_STOPPED", head, false)
                    end
                    table.remove(H.queue, 2)
                    table.insert(H.queue, 1, previous)
                end
                H.paused = false
                if H.playing ~= previous then StartFirst() end
                H.Spoken("AUDIO_CHANGED")
                return true
            end,
            Pause = function() H.paused, H.playing = true, nil; return true end,
            Resume = function()
                if not H.paused then return false end
                H.paused = false
                StartFirst()
                return true
            end,
        })
        -- Spoken 3.12's Mute: the voice stops mid-line ("cut") and the words run on, with no stop
        -- event; unmuted, a cut line starts again from the top.
        function H.Mute(on)
            if H.muted == on then return end
            H.muted = on
            local head = H.queue[1]
            if on and head and H.playing == head and not head.silent then
                head.silent = "cut"
            elseif not on and head and H.playing == head and head.silent == "cut" then
                H.playing = nil
                StartFirst()
            end
            H.Spoken("AUDIO_CHANGED")
        end
        function H.Clip(part, guid, extra)
            local clip = { source = sources[part], unitGUID = guid, length = 6, key = part .. ":" .. tostring(guid) }
            for k, v in pairs(extra or {}) do clip[k] = v end
            return clip
        end
    end

    -- Track globals the addon writes, and globals it reads that don't exist
    setmetatable(env, {
        __newindex = function(t, k, v) H.globalWrites[k] = true; rawset(t, k, v) end,
        __index = function(_, k) H.undefinedReads[k] = true; return nil end,
    })
    if opts.db then rawset(env, "EarshotDB", opts.db) end
    if opts.charDB then rawset(env, "EarshotCharDB", opts.charDB) end
    for name, value in pairs(opts.cvars or {}) do H.cvars[name] = value end

    H.env = env
    H.ns = {}
    for _, file in ipairs(TocFiles()) do
        local chunk, err = loadstring(ReadFile(ADDON_DIR .. "/" .. file), "@" .. file)
        if not chunk then error("syntax error: " .. err) end
        setfenv(chunk, env)
        chunk("Earshot", H.ns)
    end
    H.Fire("ADDON_LOADED", "Earshot")
    H.Fire("PLAYER_LOGIN")
    function H.Slash(text) env.SlashCmdList.EARSHOT(text) end
    function H.TalkTo(guid, name)
        H.units.npc = { guid = guid, name = name or "Eagan Peltskinner" }
        H.Fire("GOSSIP_SHOW")
    end
    function H.CloseWindow() H.units.npc = nil end
    function H.MoveTo(north, west, facing)
        H.player.north, H.player.west = north, west
        if facing then H.player.facing = facing end
    end
    function H.LastChat() return H.chat[#H.chat] or "" end
    local CHAT = { say = "CHAT_MSG_MONSTER_SAY", yell = "CHAT_MSG_MONSTER_YELL", whisper = "CHAT_MSG_MONSTER_WHISPER" }
    function H.Chat(kind, text, name, guid)
        H.Fire(CHAT[kind], text, name, "", "", "", "", 0, 0, "", 0, 0, guid)
    end
    return H
end

local function Expected(distance, full, silent, behindFactor)
    local M = { }
    if distance <= full then return 1 * (behindFactor or 1) end
    if distance >= silent then return 0 end
    local t = (distance - full) / (silent - full)
    local ss = t * t * (3 - 2 * t)
    return (full / distance) * (1 - ss) * (behindFactor or 1)
end

local NPC = "Creature-0-1-2-3-100-0000AAAA"
local pi = math.pi
local scenarios = {}
local function scenario(name, fn) table.insert(scenarios, { name = name, fn = fn }) end

scenario("loads cleanly and registers settings", function()
    local H = NewClient({ spoken = "Ambience" })
    check(#H.errors == 0, "no errors on load", H.errors[1])
    check(#H.settings.categories == 1 and H.settings.addonCategory ~= nil, "settings category registered")
    local count = { slider = 0, checkbox = 0, dropdown = 0, button = 0 }
    for _, c in ipairs(H.settings.controls) do count[c.kind] = count[c.kind] + 1 end
    check(count.slider == 6 and count.checkbox == 10 and count.dropdown == 2 and count.button == 3,
        "6 sliders, 10 checkboxes, 2 dropdowns, 3 buttons",
        count.slider .. "/" .. count.checkbox .. "/" .. count.dropdown .. "/" .. count.button)
    check(H.env.SlashCmdList.EARSHOT ~= nil, "slash command registered")
    check(H.LastChat():find("fade as you walk away") ~= nil, "welcome line printed once")
    local expected = {
        Earshot = true, EarshotDB = true, EarshotCharDB = true, SLASH_EARSHOT1 = true,
        Earshot_OnAddonCompartmentClick = true, Earshot_OnAddonCompartmentEnter = true,
        Earshot_OnAddonCompartmentLeave = true,
    }
    local extra = {}
    for k in pairs(H.globalWrites) do
        if not expected[k] then table.insert(extra, k) end
    end
    check(#extra == 0, "no stray globals", table.concat(extra, ", "))
    local reads = {}
    for k in pairs(H.undefinedReads) do
        if k ~= "EarshotDB" and k ~= "EarshotCharDB" then table.insert(reads, k) end
    end
    check(#reads == 0, "no reads of missing globals", table.concat(reads, ", "))
    H.Slash("")
    check(H.settings.opened == 1, "/earshot opens the settings page")
end)

scenario("geometry matches the game's facing convention", function()
    local H = NewClient({ spoken = "Ambience" })
    local M = H.ns.Math
    check(near(M.Bearing(0, 0, 10, 0), 0), "north is 0")
    check(near(M.Bearing(0, 0, 0, 10), pi / 2), "west is pi/2 (counterclockwise)")
    check(near(M.Bearing(0, 0, -10, 0), pi), "south is pi")
    check(near(M.Bearing(0, 0, 0, -10), 3 * pi / 2), "east is 3pi/2")
    check(near(M.RelativeAngle(pi / 2, 0), pi / 2), "facing north, west is on your left (+)")
    check(near(M.RelativeAngle(3 * pi / 2, 0), -pi / 2), "facing north, east is on your right (-)")
    check(near(math.abs(M.RelativeAngle(0, pi)), pi), "facing south, north is behind")
    local n, w = M.Ahead(0, 0, pi / 2, 3)
    check(near(n, 0) and near(w, 3), "3 yd ahead while facing west")
    check(M.DistanceGain(10, 10, 45) == 1 and M.DistanceGain(45, 10, 45) == 0, "curve ends")
    local last, smooth = 1, true
    for d = 10, 45, 0.25 do
        local g = M.DistanceGain(d, 10, 45)
        if g > last + 1e-12 then smooth = false end
        last = g
    end
    check(smooth, "curve only ever falls")
    check(near(M.DistanceGain(10.01, 10, 45), 1, 0.003), "no jump at the edge of full volume")
    check(near(M.FacingGain(0, 0.65, 1), 1) and near(M.FacingGain(pi, 0.65, 1), 0.65)
        and near(M.FacingGain(pi / 2, 0.65, 1), 0.825), "front 100%, side halfway, behind 65%")
end)

scenario("quest voice: walk away, turn around, line ends", function()
    local H = NewClient({ spoken = "Ambience" })
    H.TalkTo(NPC)
    local clip = H.Clip("gossip", NPC)
    H.Spoken("CLIP_STARTED", clip)
    H.Advance(0.5)
    check(near(H.Vol("Ambience"), 0.8), "full volume next to the NPC", H.Vol("Ambience"))
    H.CloseWindow()

    H.MoveTo(-20, 0, 0) -- 20 yd south, still facing north: the NPC is ahead, 22.5 yd away
    H.Advance(1.5)
    local ahead = 0.8 * Expected(22.5, 10, 45)
    check(near(H.Vol("Ambience"), ahead, 0.003), "quieter at 22.5 yd, NPC ahead", H.Vol("Ambience") .. " vs " .. ahead)

    H.MoveTo(-20, 0, pi) -- turn around
    H.Advance(1.5)
    local behind = ahead * 0.65
    check(near(H.Vol("Ambience"), behind, 0.003), "softer with the NPC behind", H.Vol("Ambience") .. " vs " .. behind)

    H.MoveTo(-20, 0, pi / 2) -- face west: north (the NPC) is on your right
    H.Advance(1.5)
    check(near(H.Vol("Ambience"), ahead * 0.825, 0.003), "halfway with the NPC beside you", H.Vol("Ambience"))
    H.Slash("status")
    check(H.LastChat():find("to your right") ~= nil, "status says the NPC is to your right", H.LastChat())

    H.MoveTo(-60, 0, 0)
    H.Advance(1.5)
    check(H.Vol("Ambience") > 0 and H.Vol("Ambience") <= 0.0025, "near-silent past 45 yd, never 0", H.Vol("Ambience"))
    local zero = false
    for _, entry in ipairs(H.cvarLog) do if entry.value == 0 then zero = true end end
    check(not zero, "never wrote 0 (Spoken would refuse the next line)")

    H.Spoken("CLIP_STOPPED", clip, true)
    H.Advance(1.0)
    check(H.Vol("Ambience") < 0.01, "holds for a moment after the line ends", H.Vol("Ambience"))
    H.Advance(2.0)
    check(H.Vol("Ambience") == 0.8, "back to exactly your level", H.Vol("Ambience"))
    check(H.ns.db.pending == nil and H.ns.Volume.cvar == nil, "slider handed back")
    check(not H.UpdatesRunning(), "stops updating once done")
    check(#H.errors == 0, "no errors", H.errors[1])
end)

scenario("the pause between two lines doesn't pump the volume", function()
    local H = NewClient({ spoken = "Ambience" })
    H.TalkTo(NPC)
    local first, second = H.Clip("quests", NPC, { key = "a" }), H.Clip("quests", NPC, { key = "b" })
    H.Spoken("CLIP_STARTED", first)
    H.MoveTo(-30, 0, 0)
    H.Advance(2)
    local level = H.Vol("Ambience")
    H.Spoken("CLIP_STOPPED", first, true)
    local highest = 0
    for _ = 1, 15 do H.Advance(0.1); highest = math.max(highest, H.Vol("Ambience")) end
    H.Spoken("CLIP_STARTED", second)
    H.Advance(0.5)
    check(highest <= level * 1.02, "no swell in the 1.5 s gap", highest .. " vs " .. level)
    check(near(H.Vol("Ambience"), level, 0.003), "next line carries on at the same level")
end)

scenario("a line queued behind another stays faded once you've walked away", function()
    -- Spoken queues each NPC's line as you talk to them, and plays them one after another.
    local OTHER = "Creature-0-1-2-3-101-0000BBBB"
    local H = NewClient({ spoken = "Ambience" })
    H.TalkTo(NPC)
    local first = H.Clip("quests", NPC, { key = "first" })
    H.Spoken("CLIP_QUEUED", first)
    H.Spoken("CLIP_STARTED", first)
    H.MoveTo(0, 3, 0) -- a step over to the next quest giver
    H.TalkTo(OTHER, "Next Door")
    local second = H.Clip("quests", OTHER, { key = "second" })
    H.Spoken("CLIP_QUEUED", second) -- waits behind the first line
    H.CloseWindow()
    H.MoveTo(-80, 0, 0) -- well out of earshot of both
    H.Advance(2)
    check(H.Vol("Ambience") <= 0.0025, "the first line has faded out", H.Vol("Ambience"))
    H.Spoken("CLIP_STOPPED", first, true)
    H.Spoken("CLIP_STARTED", second) -- Spoken starts the next line straight after
    H.Advance(0.5)
    check(H.Vol("Ambience") <= 0.0025, "the second line starts faded too, not at full volume", H.Vol("Ambience"))
    H.MoveTo(-10, 3, 0) -- walk back towards it
    H.Advance(1.5)
    check(H.Vol("Ambience") > 0.3, "and comes up as you walk back", H.Vol("Ambience"))
    H.Spoken("CLIP_STOPPED", second, true)
    H.Advance(3)
    check(H.Vol("Ambience") == 0.8, "your level comes back after it", H.Vol("Ambience"))
    -- Asked for from far away, so queued and started at once out of earshot: as normal.
    local J = NewClient({ spoken = "Ambience" })
    J.TalkTo(NPC)
    J.CloseWindow()
    J.MoveTo(-100, 0, 0)
    local asked = J.Clip("quests", NPC, { key = "asked" })
    J.Spoken("CLIP_QUEUED", asked)
    J.Spoken("CLIP_STARTED", asked)
    J.Advance(1)
    check(J.Vol("Ambience") == 0.8 and J.ns.Spatial.session == nil, "a line asked for from 100 yd away plays as normal")
    check(#H.errors + #J.errors == 0, "no errors", H.errors[1] or J.errors[1])
end)

scenario("you move the slider yourself mid-line", function()
    local H = NewClient({ spoken = "Ambience" })
    H.TalkTo(NPC)
    local clip = H.Clip("quests", NPC)
    H.Spoken("CLIP_STARTED", clip)
    H.MoveTo(-30, 0, 0)
    H.Advance(2)
    H.cvars.Sound_AmbienceVolume = "0.5" -- dragged in Options > Audio
    H.Advance(0.3)
    check(H.Vol("Ambience") == 0.5, "your new level stays", H.Vol("Ambience"))
    check(H.ns.Volume.cvar == nil and H.ns.db.pending == nil, "Earshot lets go")
    H.Spoken("CLIP_STOPPED", clip, true)
    H.Advance(3)
    check(H.Vol("Ambience") == 0.5, "and doesn't put its old level back", H.Vol("Ambience"))
end)

scenario("Spoken on Master volume is left alone, with one hint", function()
    local H = NewClient({ spoken = "Master" })
    check(H.LastChat():find("Volume Follows") ~= nil, "hint shown at login", H.LastChat())
    local okClient = NewClient({ spoken = "Ambience" })
    check(not table.concat(okClient.chat, " "):find("Volume Follows"), "no hint when Spoken is already on Ambience")
    H.TalkTo(NPC)
    H.Spoken("CLIP_STARTED", H.Clip("quests", NPC))
    H.MoveTo(-30, 0, 0)
    H.Advance(2)
    check(H.Vol("Master") == 1 and #H.cvarLog == 0, "no volume touched")
    local hints = 0
    for _, line in ipairs(H.chat) do if line:find("Volume Follows") then hints = hints + 1 end end
    H.Spoken("CLIP_STARTED", H.Clip("quests", NPC, { key = "again" }))
    local after = 0
    for _, line in ipairs(H.chat) do if line:find("Volume Follows") then after = after + 1 end end
    check(hints == 1 and after == 1, "hint shown once", hints .. "/" .. after)
end)

scenario("a zone story or book plays at your level straight away", function()
    local H = NewClient({ spoken = "Ambience" })
    H.TalkTo(NPC)
    local clip = H.Clip("quests", NPC)
    H.Spoken("CLIP_STARTED", clip)
    H.MoveTo(-30, 0, 0)
    H.Advance(2)
    H.Spoken("CLIP_STOPPED", clip, true)
    H.Spoken("CLIP_STARTED", H.Clip("places", nil))
    check(H.Vol("Ambience") == 0.8, "restored in the same frame", H.Vol("Ambience"))
end)

scenario("Replay from far away plays normally", function()
    local H = NewClient({ spoken = "Ambience" })
    H.TalkTo(NPC)
    H.CloseWindow()
    H.MoveTo(-100, 0, 0)
    H.Spoken("CLIP_STARTED", H.Clip("quests", NPC))
    H.Advance(1)
    check(H.Vol("Ambience") == 0.8 and H.ns.Spatial.session == nil, "not placed when started 100 yd away")
end)

scenario("a line without the NPC's GUID uses the window you just opened", function()
    local H = NewClient({ spoken = "Ambience" })
    H.TalkTo(nil, "Hidden GUID")
    H.Advance(0.4)
    H.Spoken("CLIP_STARTED", H.Clip("quests", nil))
    check(H.ns.Spatial.session ~= nil, "placed at the last window")
    H.Spoken("CLIP_STOPPED", H.ns.Spatial.session and H.Clip("quests", nil) or nil, true)
    local J = NewClient({ spoken = "Ambience" })
    J.TalkTo(nil, "Hidden GUID")
    J.CloseWindow()
    J.Advance(30)
    J.Spoken("CLIP_STARTED", J.Clip("quests", nil))
    check(J.ns.Spatial.session == nil, "not placed half a minute later (a quest log replay)")
    local K = NewClient({ spoken = "Ambience" })
    K.units.npc = { guid = "Item-0-1-2-3", name = "Torn Note" }
    K.Fire("QUEST_DETAIL")
    K.Spoken("CLIP_STARTED", K.Clip("quests", "Item-0-1-2-3", { unitIsObjectOrItem = true }))
    check(K.ns.Spatial.session == nil, "a quest item in your bags isn't placed")
    -- Spoken's handler for a window often runs before Earshot's: the open window still counts,
    -- not the one before it.
    local L = NewClient({ spoken = "Ambience" })
    L.TalkTo(NPC)
    L.CloseWindow()
    L.MoveTo(50, 0, 0)
    L.Advance(2)
    L.units.npc = { name = "Hidden GUID" } -- open, but Earshot hasn't heard yet
    L.Spoken("CLIP_STARTED", L.Clip("quests", "Creature-0-0-0-0-555-0"))
    local spot = L.ns.Spatial.session and L.ns.Spatial.session.spot
    check(spot and math.abs(spot.north - 52.5) < 0.01, "placed at the window open now",
        spot and ("north %.1f"):format(spot.north) or "not placed")
end)

scenario("logout or /reload mid-line restores your level", function()
    local H = NewClient({ spoken = "Ambience" })
    H.TalkTo(NPC)
    H.Spoken("CLIP_STARTED", H.Clip("quests", NPC))
    H.MoveTo(-30, 0, 0)
    H.Advance(2)
    H.Fire("PLAYER_LOGOUT")
    check(H.Vol("Ambience") == 0.8 and H.ns.db.pending == nil, "restored before the game saves", H.Vol("Ambience"))
end)

scenario("a leftover from a session that never logged out is put back", function()
    local H = NewClient({ spoken = "Ambience", db = { pending = { cvar = "Sound_AmbienceVolume", level = 0.9 } } })
    check(H.Vol("Ambience") == 0.9 and H.ns.db.pending == nil, "restored at load", H.Vol("Ambience"))
    local J = NewClient({ spoken = "Ambience", db = { pending = { cvar = "Sound_MasterVolume", level = 0.1 } } })
    check(J.Vol("Master") == 1, "ignores a leftover for a slider Earshot never moves")
    local K = NewClient({ spoken = "Ambience", db = { full = "ten", behind = 300 } })
    check(K.ns.db.full == 10, "bad saved setting replaced with the default")
    check(K.ns.db.behind == 100, "out-of-range saved setting pulled back into the slider's range", K.ns.db.behind)
end)

scenario("walking into a dungeon mid-line takes the voice out of earshot", function()
    local H = NewClient({ spoken = "Ambience" })
    H.TalkTo(NPC)
    H.Spoken("CLIP_STARTED", H.Clip("quests", NPC))
    H.Advance(0.5)
    H.player.inInstance = true
    H.Advance(1.5)
    check(H.Vol("Ambience") > 0 and H.Vol("Ambience") <= 0.0025, "faded out", H.Vol("Ambience"))
end)

scenario("world chatter is pinned where you heard it, with no 'behind you'", function()
    local H = NewClient({ spoken = "Ambience" })
    H.MoveTo(0, 0, 0)
    H.Spoken("CLIP_STARTED", H.Clip("chatter", "Creature-0-1-2-3-200-0000BBBB"))
    H.MoveTo(-5, 0, pi)
    H.Advance(1)
    check(H.Vol("Ambience") == 0.8, "full volume nearby, facing doesn't matter", H.Vol("Ambience"))
    H.MoveTo(-30, 0, 0)
    H.Advance(2)
    local expected = 0.8 * Expected(30, 20, 45)
    check(near(H.Vol("Ambience"), expected, 0.003), "fades from 20 yd out", H.Vol("Ambience") .. " vs " .. expected)
    H.MoveTo(-30, 0, pi)
    H.Advance(1)
    check(near(H.Vol("Ambience"), expected, 0.003), "turning around changes nothing")
end)

scenario("whispers play as normal; yells and things said aloud are placed", function()
    local H = NewClient({ spoken = "Ambience" })
    H.Fire("CHAT_MSG_MONSTER_WHISPER", "Psst, over here.", "Shady Figure")
    H.Spoken("CLIP_STARTED", H.Clip("chatter", nil, { text = "Psst, over here.", key = "w1" }))
    check(H.ns.Spatial.session == nil, "whisper not placed")
    H.Fire("CHAT_MSG_RAID_BOSS_WHISPER", "You will die.", "Dread Lord")
    H.Spoken("CLIP_STARTED", H.Clip("chatter", nil, { text = "You will die.", key = "w2" }))
    check(H.ns.Spatial.session == nil, "boss whisper not placed")
    H.Fire("CHAT_MSG_MONSTER_YELL", "The Horde attacks!", "Town Guard")
    H.Spoken("CLIP_STARTED", H.Clip("chatter", nil, { text = "The Horde attacks!", key = "y1" }))
    local session = H.ns.Spatial.session
    check(session ~= nil and session.silent == 120 and session.full == 54, "yell placed, carrying 120 yd")
    H.Fire("CHAT_MSG_MONSTER_SAY", "Fresh bread!", "Baker")
    H.Spoken("CLIP_STARTED", H.Clip("chatter", nil, { text = "Fresh bread!", key = "s1" }))
    session = H.ns.Spatial.session
    check(session ~= nil and session.silent == 45 and session.full == 20, "said aloud: placed, carrying 45 yd")
end)

scenario("a whisper Spoken starts before Earshot hears the chat goes back to normal", function()
    local H = NewClient({ spoken = "Ambience" })
    H.Spoken("CLIP_STARTED", H.Clip("chatter", nil, { text = "Come closer.", key = "w3" }))
    check(H.ns.Spatial.session ~= nil, "pinned at first, while the kind isn't known")
    H.Fire("CHAT_MSG_MONSTER_WHISPER", "Come closer.", "Shady Figure")
    check(H.ns.Spatial.session == nil and H.Vol("Ambience") == 0.8, "unplaced as soon as the whisper arrives")
end)

scenario("chatter is pinned where you were when the NPC spoke", function()
    local H = NewClient({ spoken = "Ambience" })
    H.MoveTo(0, 0, 0)
    H.Fire("CHAT_MSG_MONSTER_SAY", "Lovely weather.", "Farmer")
    H.MoveTo(-15, 0, 0) -- the line waited in Spoken's queue while you walked on
    H.Advance(5)
    H.Spoken("CLIP_STARTED", H.Clip("chatter", nil, { text = "Lovely weather.", key = "s2" }))
    H.MoveTo(-30, 0, 0)
    H.Advance(2)
    local expected = 0.8 * Expected(30, 20, 45)
    check(near(H.Vol("Ambience"), expected, 0.003), "distance counted from where it was said",
        H.Vol("Ambience") .. " vs " .. expected)
end)

scenario("a quest line with Spoken's stand-in GUID", function()
    local H = NewClient({ spoken = "Ambience" })
    H.TalkTo(nil, "Hidden GUID")
    H.Advance(0.4)
    H.Spoken("CLIP_STARTED", H.Clip("quests", "Creature-0-0-0-0-1234-0", { key = "q-standin" }))
    check(H.ns.Spatial.session ~= nil, "placed at the window you just opened")
    check(H.ns.Anchors.IsStandIn("Creature-0-0-0-0-1234-0") and not H.ns.Anchors.IsStandIn(NPC), "stand-in check")
    local J = NewClient({ spoken = "Ambience" })
    J.TalkTo(NPC)
    J.CloseWindow()
    J.units.questnpc = { guid = "Player-1-0ABCDEF", name = "Your Mate" }
    J.Fire("QUEST_DETAIL") -- a party member shares a quest
    J.Spoken("CLIP_STARTED", J.Clip("quests", "Creature-0-0-0-0-5678-0", { key = "q-shared" }))
    check(J.ns.Spatial.session == nil, "a shared quest isn't placed at the last NPC you talked to")
end)

scenario("replaying a finished line from a distance plays it as normal", function()
    local H = NewClient({ spoken = "Ambience" })
    H.TalkTo(NPC)
    local clip = H.Clip("quests", NPC, { key = "q-replay" })
    H.Spoken("CLIP_STARTED", clip)
    H.Spoken("CLIP_STOPPED", clip, true)
    H.Advance(3)
    H.CloseWindow()
    H.MoveTo(-30, 0, 0)
    H.Spoken("CLIP_STARTED", clip)
    H.Advance(1)
    check(H.ns.Spatial.session == nil and H.Vol("Ambience") == 0.8, "replay from 30 yd plays at your level")
    H.MoveTo(-5, 0, 0)
    H.Spoken("CLIP_STARTED", clip)
    check(H.ns.Spatial.session ~= nil, "replay right by the NPC is still placed")
    local J = NewClient({ spoken = "Ambience" })
    J.TalkTo(NPC)
    local line = J.Clip("quests", NPC, { key = "q-pause" })
    J.Spoken("CLIP_STARTED", line)
    J.Spoken("CLIP_STOPPED", line, false) -- paused part way
    J.CloseWindow()
    J.MoveTo(-30, 0, 0)
    J.Spoken("CLIP_STARTED", line)        -- resumed
    J.Advance(1)
    check(J.ns.Spatial.session ~= nil and J.Vol("Ambience") < 0.4, "a paused line resumed from 30 yd still fades")
    local K = NewClient({ spoken = "Ambience" })
    K.TalkTo(NPC)
    local dropped = K.Clip("quests", NPC, { key = "q-drop" })
    K.Spoken("CLIP_STARTED", dropped)
    K.Spoken("CLIP_DROPPED", dropped, "outranked")
    K.CloseWindow()
    K.MoveTo(-30, 0, 0)
    K.Spoken("CLIP_STARTED", dropped)
    check(K.ns.Spatial.session ~= nil, "a dropped line doesn't count as finished")
end)

scenario("the two distance sliders keep each other in step", function()
    local H = NewClient({ spoken = "Ambience" })
    local full, silent = H.settings.registered.EARSHOT_FULL, H.settings.registered.EARSHOT_SILENT
    full:SetValue(30)
    check(H.ns.db.silent == 45, "Silent beyond stays when it's already far enough", H.ns.db.silent)
    silent:SetValue(15)
    check(H.ns.db.full == 10, "lowering Silent beyond pulls Full volume within down", H.ns.db.full)
    full:SetValue(28)
    check(H.ns.db.silent == 35, "raising Full volume within pushes Silent beyond out", H.ns.db.silent)
end)

scenario("/earshot test", function()
    local H = NewClient({ spoken = "Ambience" })
    H.Slash("test")
    local sound = H.sounds[#H.sounds]
    check(sound and sound.path == [[Interface\AddOns\Earshot\Media\Test.mp3]] and sound.channel == "Ambience",
        "plays the test file on Spoken's slider")
    H.MoveTo(-25, 0, pi)
    H.Advance(3)
    check(H.Vol("Ambience") < 0.4, "fades as you walk off", H.Vol("Ambience"))
    H.Advance(28)
    check(H.Vol("Ambience") < 0.4 and H.UpdatesRunning(), "still placed while the 32 s tune plays")
    H.Advance(5)
    check(H.Vol("Ambience") == 0.8 and not H.UpdatesRunning(), "hands the slider back after the tune ends")
    H.MoveTo(0, 0, 0)
    H.Slash("test")
    H.MoveTo(-25, 0, 0)
    H.Advance(2)
    H.Slash("test")
    check(H.stopped ~= nil and H.Vol("Ambience") == 0.8, "running it again stops it and restores")
    check(#H.errors == 0, "no errors", H.errors[1])
end)

scenario("works without Spoken installed", function()
    local H = NewClient({})
    check(#H.errors == 0, "loads", H.errors[1])
    H.Slash("status")
    local said = table.concat(H.chat, "\n")
    check(said:find("Spoken isn't loaded") ~= nil, "status explains")
    H.Slash("test")
    check(H.sounds[1] and H.sounds[1].channel == "Ambience", "test falls back to Ambience")
end)

scenario("other addons can use the API", function()
    local H = NewClient({ spoken = "Ambience" })
    local token = H.env.Earshot:Place({ channel = "Ambience", here = true })
    check(token ~= nil, "Place returns a token")
    H.MoveTo(-30, 0, 0)
    H.Advance(2)
    check(H.env.Earshot:GetLevel() < 0.5, "fades with distance")
    H.env.Earshot:Done(token)
    H.Advance(3)
    check(H.Vol("Ambience") == 0.8, "Done hands the slider back")
    check(H.env.Earshot:Place({ channel = "Master", here = true }) == nil, "refuses Master volume")
end)

scenario("switching it off mid-line restores at once", function()
    local H = NewClient({ spoken = "Ambience" })
    H.TalkTo(NPC)
    H.Spoken("CLIP_STARTED", H.Clip("quests", NPC))
    H.MoveTo(-30, 0, 0)
    H.Advance(2)
    H.settings.registered.EARSHOT_ENABLED:SetValue(false)
    check(H.Vol("Ambience") == 0.8, "restored by the checkbox")
    H.Spoken("CLIP_STARTED", H.Clip("quests", NPC, { key = "next" }))
    H.Advance(1)
    check(H.Vol("Ambience") == 0.8, "stays off for the next line")
    H.Slash("on")
    check(H.ns.db.enabled == true, "/earshot on")
end)

scenario("game sound checkboxes write the game's own options", function()
    local H = NewClient({ spoken = "Ambience" })
    local reverb = H.settings.registered.EARSHOT_GAME_SOUND_ENABLEREVERB
    check(reverb ~= nil and reverb:GetValue() == false, "reverb reads the CVar")
    reverb:SetValue(true)
    check(H.cvars.Sound_EnableReverb == "1", "reverb writes the CVar")
end)

local FARMER = "Creature-0-1-2-3-300-0000CCCC"
local function Follow(H, on) H.settings.registered.EARSHOT_FOLLOW:SetValue(on) end

-- How a nameplate looks: "name only" (bars, auras and highlights see-through; its name and
-- interact icon showing), "as the game left it", or "something else".
local function Looks(plate)
    local face = plate.UnitFrame
    local bars = face.HealthBarsContainer.alpha + face.CastBarsContainer.alpha + face.AurasFrame.alpha
        + face.ClassificationFrame.alpha + face.LevelFrame.alpha + face.selectionHighlight.alpha
    if face.alpha == 1 and face.name.alpha == 1 and face.SoftTargetFrame.alpha == 1 and bars == 0 then
        return "name only"
    elseif face.alpha == 1 and face.name.alpha == 1 and face.HealthBarsContainer.alpha == 1
        and face.selectionHighlight.alpha == 0.25 and face.aggroFlash.alpha == 0 then
        return "as the game left it"
    end
    return "something else"
end

scenario("following is off until you switch it on", function()
    local H = NewClient({ spoken = "Ambience" })
    check(H.cvars.nameplateShowFriendlyNpcs == "0" and H.cvars.nameplateShowAll == "0", "game's nameplate options untouched")
    H.npcs[FARMER] = { north = 10, west = 0 }
    local _, plate = H.ShowPlate(FARMER)
    check(Looks(plate) == "as the game left it" and plate.clickable, "friendly NPC nameplates left as they are")
end)

scenario("switching following on turns nameplates on and hides friendly NPCs' ones", function()
    local H = NewClient({ spoken = "Ambience" })
    Follow(H, true)
    check(H.cvars.nameplateShowFriendlyNpcs == "1" and H.cvars.nameplateShowAll == "1",
        "Friendly NPC and Always Show nameplates on")
    check(H.ns.char.plateOptions.nameplateShowFriendlyNpcs == "0" and H.ns.char.plateOptions.nameplateShowAll == "0",
        "your old values kept, per character")
    H.npcs[FARMER] = { north = 10, west = 0 }
    local _, npc = H.ShowPlate(FARMER, "npc")
    local _, enemy = H.ShowPlate("Creature-0-1-2-3-400-0000DDDD", "enemy")
    local _, mate = H.ShowPlate("Player-1-0ABCDEF", "player")
    local _, pet = H.ShowPlate("Pet-0-1-2-3-500-0000EEEE", "pet")
    check(Looks(npc) == "name only" and not npc.clickable, "friendly NPC nameplate shows only its name, unclickable",
        Looks(npc))
    check(Looks(enemy) == "as the game left it" and enemy.clickable, "enemy nameplate untouched")
    check(Looks(mate) == "as the game left it" and mate.clickable, "player nameplate untouched")
    check(Looks(pet) == "as the game left it" and pet.clickable, "pet nameplate untouched")
    npc.UnitFrame:UpdateHitTestArea(H.env.NamePlateSetupOptions)
    check(not npc.clickable, "stays unclickable when the game redraws its clickable area")
    H.RemovePlate(npc.unitToken)
    local _, reused = H.ShowPlate("Creature-0-1-2-3-600-0000FFFF", "enemy")
    check(reused.UnitFrame == npc.UnitFrame, "(the game reused its visible part)")
    check(Looks(reused) == "as the game left it" and reused.clickable, "reused for an enemy: as before, and clickable")
    check(#H.errors == 0, "no errors", H.errors[1])
end)

scenario("hidden friendly NPC nameplates keep their names", function()
    -- Once an NPC has a nameplate the game shows its name there, not above its head.
    local H = NewClient({ spoken = "Ambience" })
    Follow(H, true)
    H.npcs[FARMER] = { north = 10, west = 0 }
    local _, npc = H.ShowPlate(FARMER)
    local face = npc.UnitFrame
    check(Looks(npc) == "name only", "only the name shows", Looks(npc))
    check(face.RaidTargetFrame.alpha == 1 and face.WidgetContainer.alpha == 1,
        "a raid marker or the game's widgets would still show")
    face:SetAlpha(1) -- the game sets the whole nameplate back to visible now and then
    check(Looks(npc) == "name only", "still only the name after the game resets it")
    H.Fire("NAME_PLATE_UNIT_ADDED", npc.unitToken) -- set up again for the same NPC
    H.settings.registered.EARSHOT_HIDEPLATES:SetValue(false)
    check(Looks(npc) == "as the game left it", "untick Hide: bars and highlights as they were",
        ("selection %.2f, flash %.2f"):format(face.selectionHighlight.alpha, face.aggroFlash.alpha))
    check(#H.errors == 0, "no errors", H.errors[1])
end)

scenario("switching following off puts everything back", function()
    local H = NewClient({ spoken = "Ambience" })
    Follow(H, true)
    H.npcs[FARMER] = { north = 10, west = 0 }
    local _, npc = H.ShowPlate(FARMER)
    Follow(H, false)
    check(H.cvars.nameplateShowFriendlyNpcs == "0" and H.cvars.nameplateShowAll == "0", "your nameplate options back")
    check(next(H.ns.char.plateOptions) == nil, "nothing left waiting to be restored")
    check(Looks(npc) == "as the game left it" and npc.clickable, "the hidden nameplate shows again, clickable")
    local J = NewClient({ spoken = "Ambience", cvars = { nameplateShowFriendlyNpcs = "1", nameplateShowAll = "1" } })
    Follow(J, true)
    Follow(J, false)
    check(J.cvars.nameplateShowFriendlyNpcs == "1" and J.cvars.nameplateShowAll == "1", "options you already had on stay on")
    local K = NewClient({ spoken = "Ambience" })
    Follow(K, true)
    K.settings.registered.EARSHOT_HIDEPLATES:SetValue(false)
    K.npcs[FARMER] = { north = 10, west = 0 }
    local _, shown = K.ShowPlate(FARMER)
    check(Looks(shown) == "as the game left it", "untick Hide and friendly NPC nameplates show")
    check(K.cvars.nameplateShowFriendlyNpcs == "1", "following still uses them")
    local L = NewClient({ spoken = "Ambience" })
    Follow(L, true)
    L.Slash("off")
    check(L.cvars.nameplateShowFriendlyNpcs == "0", "/earshot off also puts your nameplate options back")
end)

scenario("nameplate options wait until combat ends", function()
    local H = NewClient({ spoken = "Ambience" })
    H.inCombat = true
    Follow(H, true)
    check(H.cvars.nameplateShowFriendlyNpcs == "0" and #H.errors == 0, "nothing changed in combat, no error")
    H.inCombat = false
    H.Fire("PLAYER_REGEN_ENABLED")
    check(H.cvars.nameplateShowFriendlyNpcs == "1" and H.cvars.nameplateShowAll == "1", "applied once combat ends")
end)

scenario("in combat your own nameplate options are back", function()
    -- Following pauses in combat, so Earshot hands the options back as combat starts (the
    -- game still allows it then) and takes them again when it ends. An addon that switches
    -- enemy nameplates with combat, like Leatrix Plus's Combat plates, is left to it.
    local H = NewClient({ spoken = "Ambience", cvars = { nameplateShowEnemies = "0" } })
    Follow(H, true)
    check(H.cvars.nameplateShowFriendlyNpcs == "1" and H.cvars.nameplateShowAll == "1", "on outside combat")
    H.Fire("PLAYER_REGEN_DISABLED") -- its handlers run just before the lockdown starts
    H.inCombat = true
    H.cvars.nameplateShowEnemies = "1" -- Combat plates
    check(H.cvars.nameplateShowFriendlyNpcs == "0" and H.cvars.nameplateShowAll == "0", "yours during the fight")
    H.inCombat = false
    H.Fire("PLAYER_REGEN_ENABLED")
    H.cvars.nameplateShowEnemies = "0" -- Combat plates
    check(H.cvars.nameplateShowFriendlyNpcs == "1" and H.cvars.nameplateShowAll == "1", "on again afterwards")
    local touched = false
    for _, entry in ipairs(H.cvarLog) do
        if entry.name == "nameplateShowEnemies" then touched = true end
    end
    check(not touched, "never touches the enemy nameplate option")
    -- Already locked when Earshot hears combat start: they stay on, with no error.
    H.inCombat = true
    H.Fire("PLAYER_REGEN_DISABLED")
    H.inCombat = false
    H.Fire("PLAYER_REGEN_ENABLED")
    check(H.cvars.nameplateShowAll == "1" and #H.errors == 0, "no harm if it's too late", H.errors[1])
    -- Switched off mid-fight: nothing comes back on afterwards.
    H.Fire("PLAYER_REGEN_DISABLED")
    H.inCombat = true
    Follow(H, false)
    H.inCombat = false
    H.Fire("PLAYER_REGEN_ENABLED")
    check(H.cvars.nameplateShowFriendlyNpcs == "0" and H.cvars.nameplateShowAll == "0"
        and next(H.ns.char.plateOptions) == nil, "switched off in combat stays off")
end)

scenario("following chatter: walking past the NPC who spoke", function()
    -- The farmer is 15 yd ahead. Pinned where you stood, his voice fades as you walk past him;
    -- following finds him by his nameplate.
    local function Walk(H)
        H.MoveTo(0, 0, 0)
        H.npcs[FARMER] = { north = 15, west = 0 }
        H.ShowPlate(FARMER)
        H.Fire("CHAT_MSG_MONSTER_SAY", "Lovely day for it.", "Farmer")
        H.Spoken("CLIP_STARTED", H.Clip("chatter", FARMER, { text = "Lovely day for it.", key = "c-walk" }))
        for north = 0, 32, 2 do
            H.MoveTo(north, 0, 0)
            H.Advance(0.4)
        end
    end
    local H = NewClient({ spoken = "Ambience" })
    Follow(H, true)
    Walk(H)
    local spot = H.ns.Spatial.session.spot
    local off = math.sqrt((spot.north - 15) ^ 2 + spot.west ^ 2)
    check(off < 6, "Earshot's spot within 6 yd of the farmer", ("%.1f yd off"):format(off))
    -- 17 yd past him: inside chatter's 20 yd of full volume, so the only softening is "behind you",
    -- which applies now that following knows which way he is.
    local estimate = math.sqrt((spot.north - H.player.north) ^ 2 + (spot.west - H.player.west) ^ 2)
    local weight = math.min(1, math.max(0, (estimate - 10) / 10))
    local expected = 0.8 * (1 - weight * 0.35)
    check(spot.directional, "following knows which way he is")
    check(near(H.Vol("Ambience"), expected, 0.02), "no fade for distance, just softer behind you",
        H.Vol("Ambience") .. " vs " .. expected)
    local J = NewClient({ spoken = "Ambience" })
    Walk(J)
    check(J.Vol("Ambience") < 0.5, "without following it fades (pinned 32 yd back)", J.Vol("Ambience"))
    check(#H.errors == 0, "no errors", H.errors[1])
end)

scenario("following an NPC who walks with you", function()
    local ESCORT = "Creature-0-1-2-3-700-0000ABAB"
    local function Escort(H)
        H.MoveTo(0, 0, 0)
        H.TalkTo(ESCORT, "Escort")
        H.npcs[ESCORT] = { north = 3, west = 0 }
        H.ShowPlate(ESCORT)
        H.Spoken("CLIP_STARTED", H.Clip("quests", ESCORT, { key = "escort-1" }))
        H.CloseWindow()
        for north = 0, 40, 2 do
            H.MoveTo(north, 0, 0)
            H.npcs[ESCORT].north = north + 3
            H.Advance(0.4)
        end
    end
    local H = NewClient({ spoken = "Ambience" })
    Follow(H, true)
    Escort(H)
    check(H.Vol("Ambience") > 0.7, "40 yd on, the escort is still beside you: near full volume", H.Vol("Ambience"))
    local J = NewClient({ spoken = "Ambience" })
    Escort(J)
    check(J.Vol("Ambience") < 0.05, "without following, the voice stays where you met them", J.Vol("Ambience"))
end)

scenario("following a quest giver you walk away from, with the camera behind you", function()
    -- The camera sits behind you. Walking away from the NPC, it stays between you and the
    -- camera for a while, so its nameplate is on screen, in the middle, as if it were ahead of
    -- you. It's behind you, and its voice should fade as it does without following: also with
    -- the camera far back, and with the NPC up on a balcony, where its nameplate shows high.
    local function WalkAway(H, follow, camera, height, hidden, says)
        if follow then Follow(H, true) end
        H.cameraZoom = camera
        if hidden then H.env.GetCameraZoom = nil end -- a game that won't say how far back it is
        if says then H.env.GetCameraZoom = function() return says end end -- or says it wrong
        H.MoveTo(0, 0, 0)
        H.TalkTo(NPC)
        H.npcs[NPC] = { north = 2.5, west = 0, height = height }
        H.ShowPlate(NPC)
        H.Spoken("CLIP_STARTED", H.Clip("quests", NPC, { key = "walk-away" }))
        H.Advance(0.5)
        H.CloseWindow()
        local heard = {}
        for south = 0, 40, 2 do
            H.MoveTo(-south, 0, pi) -- facing south, away from the NPC
            H.Advance(0.4)
            heard[south] = H.Vol("Ambience")
        end
        return heard
    end
    local plain = WalkAway(NewClient({ spoken = "Ambience" }), false, 20, 0)
    for _, case in ipairs({ { 20, 0 }, { 30, 0 }, { 39, 0 }, { 20, 5 }, { 20, 0, true }, { 20, 0, false, 2 } }) do
        local camera, height, hidden, says = case[1], case[2], case[3], case[4]
        local H = NewClient({ spoken = "Ambience" })
        local followed = WalkAway(H, true, camera, height, hidden, says)
        local label = ("camera %d yd back%s%s%s: "):format(camera, height > 0 and ", NPC 5 yd up" or "",
            hidden and ", distance unknown" or "", says and (", game says %d yd"):format(says) or "")
        local spot = H.ns.Spatial.session.spot
        check(math.abs(spot.north - 2.5) < 3 and math.abs(spot.west) < 3, label .. "Earshot's spot stays by the NPC",
            ("%.1f, %.1f"):format(spot.north, spot.west))
        for _, south in ipairs({ 10, 20, 30, 40 }) do
            check(near(followed[south], plain[south], 0.03),
                label .. ("%d yd away it fades as without following"):format(south),
                ("%.3f vs %.3f"):format(followed[south], plain[south]))
        end
        H.Slash("status")
        local said = table.concat(H.chat, "\n")
        check(said:find("behind you", 1, true) ~= nil, label .. "status says the NPC is behind you",
            said:match("Placing[^\n]*") or "nothing")
        check(#H.errors == 0, label .. "no errors", H.errors[1])
    end
    -- /earshot debug: a line a second while the voice plays, on what following read.
    local H = NewClient({ spoken = "Ambience" })
    H.Slash("debug")
    check(H.LastChat():find("Debug readout on", 1, true) ~= nil, "/earshot debug switches the readout on")
    local before = #H.chat
    WalkAway(H, true, 20, 0)
    local lines = {}
    for i = before + 1, #H.chat do
        if H.chat[i]:find("Debug: voice", 1, true) then table.insert(lines, H.chat[i]) end
    end
    check(#lines >= 6 and #lines <= 10, "about one line a second", #lines)
    local last = lines[#lines] or ""
    check(last:find("Following: range over 28 yd (items over 28, interaction over 28)", 1, true) ~= nil
        and last:find("behind you", 1, true) ~= nil and last:find("off screen (behind the camera)", 1, true) ~= nil,
        "saying what the game read, and where the nameplate is", last)
    local walking
    for _, line in ipairs(lines) do
        if line:find("nameplate on screen", 1, true) and line:find("behind (by your walking)", 1, true) then
            walking = line
        end
    end
    check(walking ~= nil, "and, while the NPC was between you and the camera, why it's behind you",
        table.concat(lines, "\n"))
    H.Slash("debug")
    check(H.LastChat():find("Debug readout off", 1, true) ~= nil, "and off again")
    check(#H.errors == 0, "debug: no errors", H.errors[1])
end)

scenario("following chatter from an NPC just behind you", function()
    -- You stand still, the camera 20 yd behind you. An NPC 6 yd behind you speaks: its
    -- nameplate is on screen, in the middle, but below you, so it's between you and the camera.
    local H = NewClient({ spoken = "Ambience" })
    Follow(H, true)
    H.cameraZoom = 20
    H.MoveTo(0, 0, 0)
    H.npcs[FARMER] = { north = -6, west = 0 }
    H.ShowPlate(FARMER)
    H.Fire("CHAT_MSG_MONSTER_SAY", "Mind your step.", "Farmer")
    H.Spoken("CLIP_STARTED", H.Clip("chatter", FARMER, { text = "Mind your step.", key = "c-behind" }))
    H.Advance(1)
    local spot = H.ns.Spatial.session.spot
    check(spot.north < -2, "Earshot puts the NPC behind you", ("%.1f yd north"):format(spot.north))
    check(#H.errors == 0, "no errors", H.errors[1])
end)

scenario("following an NPC who walks with you, with the camera far back", function()
    -- With the camera 30 yd back, an escort a few yards ahead shows on screen almost where it
    -- would just behind you. It keeps up however far you go, so it's walking with you.
    local ESCORT = "Creature-0-1-2-3-700-0000ABAB"
    local H = NewClient({ spoken = "Ambience" })
    Follow(H, true)
    H.cameraZoom = 30
    H.MoveTo(0, 0, 0)
    H.TalkTo(ESCORT, "Escort")
    H.npcs[ESCORT] = { north = 3, west = 0 }
    H.ShowPlate(ESCORT)
    H.Spoken("CLIP_STARTED", H.Clip("quests", ESCORT, { key = "escort-far" }))
    H.CloseWindow()
    for north = 0, 40, 2 do
        H.MoveTo(north, 0, 0)
        H.npcs[ESCORT].north = north + 3
        H.Advance(0.4)
    end
    check(H.Vol("Ambience") > 0.7, "40 yd on, still near full volume", H.Vol("Ambience"))
    H.Slash("status")
    check(table.concat(H.chat, "\n"):find("behind you", 1, true) == nil, "status doesn't put it behind you")
    check(#H.errors == 0, "no errors", H.errors[1])
end)

scenario("following uses every range step the library has", function()
    -- For an NPC you can assist, LibRangeCheck's usual answer only has its 5 yd item check.
    -- The 8 and 28 yd steps come from asking it to leave items out, so Earshot asks both ways.
    local function Hear(H, north)
        Follow(H, true)
        H.MoveTo(0, 0, 0)
        H.npcs[FARMER] = { north = north, west = 0, assist = true }
        H.ShowPlate(FARMER)
        H.Fire("CHAT_MSG_MONSTER_SAY", "Mind the step.", "Farmer")
        H.Spoken("CLIP_STARTED", H.Clip("chatter", FARMER, { text = "Mind the step.", key = "c-steps" }))
        H.Advance(0.5)
        local seen = H.ns.Spatial.session.seen
        return seen and seen.low, seen and seen.high
    end
    local H = NewClient({ spoken = "Ambience" })
    local low, high = Hear(H, 15)
    check(low == 8 and high == 28, "a rogue 15 yd away: 8-28 yd, not just 'over 5'", tostring(low) .. "-" .. tostring(high))
    H.MoveTo(12, 0, 0)
    H.Advance(0.5)
    H.Slash("status")
    check(table.concat(H.chat, "\n"):find("Following its nameplate: within 5 yd.", 1, true) ~= nil,
        "3 yd away: within 5 yd")
    local P = NewClient({ spoken = "Ambience" })
    P.friendSpells = { 30, 40 }
    low, high = Hear(P, 35)
    check(low == 30 and high == 40, "a priest's heals and buffs add 30 and 40 yd", tostring(low) .. "-" .. tostring(high))
    local N = NewClient({ spoken = "Ambience" })
    low, high = Hear(N, 15)
    N.npcs[FARMER].assist = false
    N.MoveTo(-20, 0, 0)
    N.Advance(0.5)
    low, high = N.ns.Spatial.session.seen.low, N.ns.Spatial.session.seen.high
    check(low == 28 and high == nil, "an NPC you can't assist: past 28 yd", tostring(low) .. "-" .. tostring(high))
    check(#H.errors + #P.errors + #N.errors == 0, "no errors")
end)

scenario("in combat a voice Earshot was following keeps its volume", function()
    -- Escorts get attacked: the NPC fights beside you, but Earshot can't follow it in combat.
    local ESCORT = "Creature-0-1-2-3-700-0000ABAB"
    local H = NewClient({ spoken = "Ambience" })
    Follow(H, true)
    H.MoveTo(0, 0, 0)
    H.TalkTo(ESCORT, "Escort")
    H.npcs[ESCORT] = { north = 3, west = 0 }
    local token = H.ShowPlate(ESCORT)
    H.Spoken("CLIP_STARTED", H.Clip("quests", ESCORT, { key = "escort-fight" }))
    H.CloseWindow()
    for north = 0, 20, 2 do
        H.MoveTo(north, 0, 0)
        H.npcs[ESCORT].north = north + 3
        H.Advance(0.4)
    end
    local before = H.Vol("Ambience")
    H.Fire("PLAYER_REGEN_DISABLED")
    H.inCombat = true
    H.RemovePlate(token) -- friendly NPC nameplates go for the fight
    for north = 22, 80, 2 do -- the fight moves on, and the escort with you
        H.MoveTo(north, 0, 0)
        H.npcs[ESCORT].north = north + 3
        H.Advance(0.2)
    end
    check(before > 0.7 and near(H.Vol("Ambience"), before, 0.005), "the voice keeps playing at its volume",
        before .. " then " .. H.Vol("Ambience"))
    H.Slash("status")
    check(table.concat(H.chat, "\n"):find("stays at this volume until the fight ends", 1, true) ~= nil,
        "status says why")
    H.inCombat = false
    H.Fire("PLAYER_REGEN_ENABLED")
    H.ShowPlate(ESCORT)
    H.Advance(1)
    check(H.Vol("Ambience") > 0.7, "after the fight following picks up again", H.Vol("Ambience"))
    -- A quest giver Earshot wasn't following stays where you talked to it: still fades.
    local J = NewClient({ spoken = "Ambience" })
    J.TalkTo(NPC)
    J.Spoken("CLIP_STARTED", J.Clip("quests", NPC, { key = "giver" }))
    J.CloseWindow()
    J.Fire("PLAYER_REGEN_DISABLED")
    J.inCombat = true
    J.MoveTo(-30, 0, 0)
    J.Advance(1.5)
    check(J.Vol("Ambience") < 0.4, "a quest giver's voice still fades as you move in a fight", J.Vol("Ambience"))
    check(#H.errors + #J.errors == 0, "no errors", H.errors[1] or J.errors[1])
end)

scenario("following waits out combat, and keeps the last spot when the nameplate goes", function()
    local H = NewClient({ spoken = "Ambience" })
    Follow(H, true)
    H.MoveTo(0, 0, 0)
    H.npcs[FARMER] = { north = 15, west = 0 }
    local token = H.ShowPlate(FARMER)
    H.Fire("CHAT_MSG_MONSTER_SAY", "Mind the crops.", "Farmer")
    H.Spoken("CLIP_STARTED", H.Clip("chatter", FARMER, { text = "Mind the crops.", key = "c-combat" }))
    H.inCombat = true
    H.Advance(1)
    local spot = H.ns.Spatial.session.spot
    check(spot.north == 0 and spot.west == 0 and spot.guess, "in combat the guess stays put")
    H.inCombat = false
    H.Advance(0.5)
    check(not spot.guess and spot.north > 10, "after combat the nameplate fixes it", ("north %.1f"):format(spot.north))
    H.RemovePlate(token)
    local before = spot.north
    H.MoveTo(-20, 0, 0)
    H.Advance(1)
    check(spot.north == before, "no nameplate: Earshot keeps where it last saw the NPC")
end)

local GUARD = "Creature-0-1-2-3-600-0000FFFF"
local function Control(H, variable)
    for _, c in ipairs(H.settings.controls) do
        if c.setting and c.setting.variable == variable then return c end
    end
end

scenario("presets set the distance sliders together", function()
    local H = NewClient({ spoken = "Ambience" })
    local db, preset = H.ns.db, H.settings.registered.EARSHOT_PRESET
    check(preset:GetValue() == "natural", "starts on Natural")
    local dropdown = Control(H, "EARSHOT_PRESET")
    check(dropdown and dropdown.kind == "dropdown" and #dropdown.data == 4 and dropdown.data[4].value == "custom",
        "a dropdown of Subtle, Natural, Dramatic and Custom")
    preset:SetValue("dramatic")
    check(db.full == 6 and db.silent == 30 and db.behind == 40 and db.chatterRange == 30, "Dramatic sets the sliders",
        ("%d/%d/%d/%d"):format(db.full, db.silent, db.behind, db.chatterRange))
    check(preset:GetValue() == "dramatic", "and shows Dramatic")
    preset:SetValue("subtle")
    check(db.full == 15 and db.silent == 70 and db.behind == 80 and db.chatterRange == 70, "Subtle, straight from Dramatic",
        ("%d/%d/%d/%d"):format(db.full, db.silent, db.behind, db.chatterRange))
    H.settings.registered.EARSHOT_BEHIND:SetValue(50)
    check(preset:GetValue() == "custom", "moving a slider shows Custom")
    preset:SetValue("custom")
    check(db.behind == 50, "picking Custom changes nothing")
    preset:SetValue("natural")
    check(db.full == 10 and db.silent == 45 and db.behind == 65 and db.chatterRange == 45, "Natural is the defaults")
    check(#H.errors == 0, "no errors", H.errors[1])
end)

scenario("never quieter than", function()
    local H = NewClient({ spoken = "Ambience" })
    H.settings.registered.EARSHOT_FLOOR:SetValue(20)
    H.TalkTo(NPC)
    H.Spoken("CLIP_STARTED", H.Clip("quests", NPC, { key = "floor" }))
    H.CloseWindow()
    H.MoveTo(-200, 0, 0)
    H.Advance(3)
    check(near(H.Vol("Ambience"), 0.16, 0.002), "200 yd away it stays at 20% of your level", H.Vol("Ambience"))
    H.player.inInstance = true
    H.Advance(1)
    check(near(H.Vol("Ambience"), 0.16, 0.002), "even from inside a dungeon", H.Vol("Ambience"))
end)

scenario("chatter heard up to", function()
    local H = NewClient({ spoken = "Ambience" })
    H.settings.registered.EARSHOT_CHATTERRANGE:SetValue(30)
    H.MoveTo(0, 0, 0)
    H.Chat("say", "Mind the geese.", "Farmer", FARMER)
    H.Spoken("CLIP_STARTED", H.Clip("chatter", FARMER, { text = "Mind the geese.", key = "geese" }))
    H.MoveTo(-12, 0, 0)
    H.Advance(1.5)
    check(near(H.Vol("Ambience"), 0.8, 0.003), "full volume 12 yd from where it was said (within 14)", H.Vol("Ambience"))
    H.MoveTo(-31, 0, 0)
    H.Advance(1.5)
    check(H.Vol("Ambience") <= 0.0025, "silent past 30 yd", H.Vol("Ambience"))
end)

scenario("yells carry further, and can play as normal", function()
    local H = NewClient({ spoken = "Ambience" })
    H.MoveTo(0, 0, 0)
    H.Chat("yell", "Raiders at the gate!", "Guard", GUARD)
    H.Spoken("CLIP_STARTED", H.Clip("chatter", GUARD, { text = "Raiders at the gate!", key = "raid" }))
    check(H.ns.Spatial.session ~= nil, "a yell is placed")
    H.MoveTo(-50, 0, 0)
    H.Advance(1.5)
    check(near(H.Vol("Ambience"), 0.8, 0.003), "full volume 50 yd away", H.Vol("Ambience"))
    H.MoveTo(-100, 0, 0)
    H.Advance(1.5)
    local v = H.Vol("Ambience")
    check(v > 0.0025 and v < 0.4, "still heard, fading, 100 yd away", v)
    H.MoveTo(-125, 0, 0)
    H.Advance(1.5)
    check(H.Vol("Ambience") <= 0.0025, "gone past 120 yd", H.Vol("Ambience"))
    local J = NewClient({ spoken = "Ambience" })
    J.settings.registered.EARSHOT_YELLRANGE:SetValue(300)
    J.Chat("yell", "To arms!", "Guard", GUARD)
    J.Spoken("CLIP_STARTED", J.Clip("chatter", GUARD, { text = "To arms!", key = "arms" }))
    check(J.ns.Spatial.session == nil, "Yells heard up to Anywhere: played as normal")
    local fmt = Control(J, "EARSHOT_YELLRANGE").options.formatter
    check(fmt(300) == "Anywhere" and fmt(120) == "120 yd", "the slider reads Anywhere at the top")
    local K = NewClient({ spoken = "Ambience" })
    K.Spoken("CLIP_STARTED", K.Clip("chatter", GUARD, { text = "Hold the line!", key = "hold" }))
    K.Chat("yell", "Hold the line!", "Guard", GUARD)
    local session = K.ns.Spatial.session
    check(session and session.silent == 120 and session.full == 54, "a yell Spoken starts first still carries")
end)

scenario("out of earshot: keep playing quietly, or skip the line", function()
    local H = NewClient({ spoken = "Ambience" })
    H.TalkTo(NPC)
    local a = H.Clip("quests", NPC, { key = "quiet-a" })
    H.Queue(a)
    H.CloseWindow()
    H.MoveTo(-60, 0, 0)
    H.Advance(4)
    check(H.playing == a and H.skips == 0, "by default the line carries on, quietly")
    local J = NewClient({ spoken = "Ambience" })
    J.settings.registered.EARSHOT_AWAY:SetValue("skip")
    J.TalkTo(NPC)
    local b = J.Clip("quests", NPC, { key = "skip-b" })
    J.Queue(b)
    J.CloseWindow()
    local story = J.Clip("places", nil, { key = "skip-story" })
    J.Queue(story)
    J.MoveTo(-60, 0, 0)
    J.Advance(1)
    check(J.playing == b and J.skips == 0, "not straight away: a moment's grace")
    J.Advance(1)
    check(J.skips == 1 and J.playing == story, "then Spoken skips it and moves on")
    check(J.Vol("Ambience") == 0.8, "your level is back for the next line", J.Vol("Ambience"))
    -- Stepping just over the edge and back doesn't count.
    local K = NewClient({ spoken = "Ambience" })
    K.settings.registered.EARSHOT_AWAY:SetValue("skip")
    K.TalkTo(NPC)
    local c = K.Clip("quests", NPC, { key = "skip-c" })
    K.Queue(c)
    K.CloseWindow()
    K.MoveTo(-46, 0, 0)
    K.Advance(1)
    K.MoveTo(-40, 0, 0)
    K.Advance(1)
    K.MoveTo(-46, 0, 0)
    K.Advance(1)
    check(K.skips == 0 and K.playing == c, "a step over the edge and back: still playing")
    check(#H.errors + #J.errors + #K.errors == 0, "no errors", H.errors[1] or J.errors[1] or K.errors[1])
end)

scenario("out of earshot: skip that NPC's lines", function()
    local OTHER = "Creature-0-1-2-3-101-0000BBBB"
    local H = NewClient({ spoken = "Ambience" })
    H.settings.registered.EARSHOT_AWAY:SetValue("skipNpc")
    H.TalkTo(NPC)
    local a1, a2 = H.Clip("quests", NPC, { key = "npc-a1" }), H.Clip("gossip", NPC, { key = "npc-a2" })
    H.Queue(a1)
    H.Queue(a2)
    H.CloseWindow()
    H.MoveTo(100, 0, 0)
    H.TalkTo(OTHER, "Far Neighbour")
    local b1 = H.Clip("quests", OTHER, { key = "npc-b1" })
    H.Queue(b1)
    local a3 = H.Clip("quests", NPC, { key = "npc-a3" })
    H.Queue(a3)
    H.CloseWindow()
    check(H.playing == a1 and #H.queue == 4, "the first NPC's line plays, three more wait")
    H.Advance(2)
    check(H.playing == b1 and #H.queue == 1, "all its lines go; the other NPC's plays", #H.queue)
    H.Chat("say", "Come back!", "Eagan Peltskinner", NPC)
    local a4 = H.Clip("chatter", NPC, { text = "Come back!", key = "npc-a4" })
    H.Queue(a4)
    H.FinishLine()
    check(H.playing == a4 and H.Vol("Ambience") <= 0.0025, "something it says while you're still away is silent",
        H.Vol("Ambience"))
    H.Advance(0.05)
    check(H.playing == nil and #H.queue == 0, "and skipped a moment later")
    H.MoveTo(5, 0, 0)
    H.Chat("say", "Welcome back.", "Eagan Peltskinner", NPC)
    local a5 = H.Clip("chatter", NPC, { text = "Welcome back.", key = "npc-a5" })
    H.Queue(a5)
    H.Advance(0.5)
    check(H.playing == a5, "back in earshot, it's heard again")
    check(#H.errors == 0, "no errors", H.errors[1])
end)

scenario("Spoken's Previous and Mute (Spoken 3.12)", function()
    -- Walk away from a remark, Earshot skips it, then you go back to it with Previous.
    local H = NewClient({ spoken = "Ambience" })
    H.settings.registered.EARSHOT_AWAY:SetValue("skipAll")
    H.Chat("say", "Mind the cart.", "Farmer", FARMER)
    local c1 = H.Clip("chatter", FARMER, { text = "Mind the cart.", key = "prev-c1" })
    H.Queue(c1)
    H.MoveTo(100, 0, 0)
    H.Advance(2)
    check(H.playing == nil and H.skips == 1, "walked away: the remark is skipped")
    H.env.Spoken:Previous()
    check(H.playing == c1 and near(H.Vol("Ambience"), 0.8), "Previous from out of earshot: it plays as normal",
        H.Vol("Ambience"))
    H.Advance(3)
    check(H.playing == c1 and H.skips == 1 and near(H.Vol("Ambience"), 0.8), "and isn't skipped again", H.skips)
    H.FinishLine()
    -- Back where it was said, a line you go back to is placed as usual.
    H.MoveTo(4, 0, 0)
    H.env.Spoken:Previous()
    check(H.playing == c1 and H.ns.Spatial.session ~= nil and H.ns.Spatial.session.ended == nil,
        "Previous within full volume: placed as usual")
    H.FinishLine()
    H.Advance(3)
    -- Away from the quest giver, Previous plays the last line as normal, and the line it cut
    -- into is placed again when it speaks again.
    H.MoveTo(0, 0, 0)
    H.TalkTo(NPC)
    local a1, a2 = H.Clip("quests", NPC, { key = "prev-a1" }), H.Clip("quests", NPC, { key = "prev-a2" })
    H.Queue(a1)
    H.Queue(a2)
    H.FinishLine()
    H.CloseWindow()
    H.MoveTo(20, 0, 0)
    H.Advance(1)
    local faded = H.Vol("Ambience")
    check(H.playing == a2 and faded < 0.7, "the second line plays, faded at 20 yd", faded)
    H.env.Spoken:Previous()
    check(H.playing == a1 and near(H.Vol("Ambience"), 0.8), "Previous at 20 yd: the last line plays as normal",
        H.Vol("Ambience"))
    H.FinishLine()
    H.Advance(1)
    check(H.playing == a2 and near(H.Vol("Ambience"), faded, 0.02), "the line it cut into speaks again, placed",
        H.Vol("Ambience"))
    H.FinishLine()
    H.Advance(3)
    -- Muted, a line is words only: nothing to place.
    local J = NewClient({ spoken = "Ambience", spokenMuted = true })
    J.TalkTo(NPC)
    local m1, m2 = J.Clip("quests", NPC, { key = "mute-m1" }), J.Clip("quests", NPC, { key = "mute-m2" })
    J.Queue(m1)
    J.Queue(m2)
    J.CloseWindow()
    J.MoveTo(30, 0, 0)
    J.Advance(1)
    check(J.playing == m1 and J.ns.Spatial.session == nil and near(J.Vol("Ambience"), 0.8),
        "with Spoken muted, the slider is left alone", J.Vol("Ambience"))
    -- Unmuted, the next line is placed; muted mid-line, Earshot lets go.
    J.Mute(false)
    J.FinishLine()
    J.Advance(1)
    local level = J.Vol("Ambience")
    check(J.playing == m2 and level < 0.6, "unmuted: the next line is placed", level)
    J.Mute(true)
    check(J.ns.Spatial.session == nil or J.ns.Spatial.session.ended ~= nil, "muted mid-line: Earshot lets go")
    J.Slash("status")
    local said = false
    for _, line in ipairs(J.chat) do
        if line:find("Spoken is muted", 1, true) then said = true end
    end
    check(said, "/earshot status says Spoken is muted")
    J.Advance(3)
    check(near(J.Vol("Ambience"), 0.8), "and your level comes back", J.Vol("Ambience"))
    J.Mute(false)
    J.Advance(1)
    check(J.playing == m2 and near(J.Vol("Ambience"), level, 0.02), "unmuted mid-line: it speaks again, placed",
        J.Vol("Ambience"))
    check(#H.errors + #J.errors == 0, "no errors", H.errors[1] or J.errors[1])
end)

scenario("out of earshot: skip every NPC out of earshot", function()
    local OTHER = "Creature-0-1-2-3-101-0000BBBB"
    local COURIER = "Creature-0-1-2-3-102-0000DDDD"
    local H = NewClient({ spoken = "Ambience" })
    H.settings.registered.EARSHOT_AWAY:SetValue("skipAll")
    H.TalkTo(NPC)
    local a1, a2 = H.Clip("quests", NPC, { key = "all-a1" }), H.Clip("gossip", NPC, { key = "all-a2" })
    H.Queue(a1)
    H.Queue(a2)
    H.CloseWindow()
    H.MoveTo(100, 0, 0)
    H.TalkTo(OTHER, "Far Neighbour")
    local b1 = H.Clip("quests", OTHER, { key = "all-b1" })
    H.Queue(b1)
    H.CloseWindow()
    H.Chat("say", "Fine weather.", "Farmer", FARMER)
    local c1 = H.Clip("chatter", FARMER, { text = "Fine weather.", key = "all-c1" })
    H.Queue(c1)
    H.Chat("whisper", "Psst. Over here.", "Courier", COURIER)
    local w1 = H.Clip("chatter", COURIER, { text = "Psst. Over here.", key = "all-w1" })
    H.Queue(w1)
    -- Played from the quest log, 100 yd from the NPC: a line you asked for.
    local log = H.Clip("quests", NPC, { key = "all-log" })
    H.Queue(log)
    check(H.playing == a1 and #H.queue == 6, "the first line plays, five wait")
    H.Advance(2)
    check(H.playing == b1 and #H.queue == 4 and H.queue[2] == c1 and H.skips == 1,
        "walked away: that line goes, and everything else from back there without starting; the NPC beside you speaks",
        #H.queue .. " waiting, " .. H.skips .. " skipped")
    H.MoveTo(200, 0, 0)
    H.Advance(2)
    check(H.playing == w1 and #H.queue == 2 and H.queue[2] == log,
        "walk on: the farmer's remark goes too; the whisper and the line you asked for stay", #H.queue)
    check(H.ns.Spatial.session == nil or H.ns.Spatial.session.ended ~= nil, "the whisper plays as normal")
    -- Something said while the whisper plays, then you walk on before its turn.
    H.Chat("say", "Mind the step.", "Farmer", FARMER)
    local c2 = H.Clip("chatter", FARMER, { text = "Mind the step.", key = "all-c2" })
    H.Queue(c2)
    H.MoveTo(300, 0, 0)
    H.settings.registered.EARSHOT_FLOOR:SetValue(20)
    H.FinishLine()
    check(H.playing == log and H.ns.Spatial.session == nil, "the line you asked for plays as normal")
    H.FinishLine()
    check(H.playing == c2 and H.Vol("Ambience") <= 0.0025,
        "a line that starts out of earshot is silent at once, below Never quieter than", H.Vol("Ambience"))
    H.Advance(0.05)
    check(H.playing == nil and #H.queue == 0, "and skipped a moment later")
    H.Advance(0.4)
    check(H.Vol("Ambience") <= 0.0025, "silent while Spoken fades it out", H.Vol("Ambience"))
    H.Advance(3)
    check(H.Vol("Ambience") == 0.8, "then your level comes back", H.Vol("Ambience"))
    H.Chat("say", "Hello again.", "Farmer", FARMER)
    local c3 = H.Clip("chatter", FARMER, { text = "Hello again.", key = "all-c3" })
    H.Queue(c3)
    H.Advance(0.5)
    check(H.playing == c3 and H.ns.Spatial.session ~= nil and H.skips == 3, "in earshot, a line plays",
        tostring(H.playing == c3) .. " " .. tostring(H.ns.Spatial.session ~= nil) .. " " .. H.skips)
    -- Walk into a dungeon: the lines waiting out in the world are out of earshot.
    local J = NewClient({ spoken = "Ambience" })
    J.settings.registered.EARSHOT_AWAY:SetValue("skipAll")
    J.TalkTo(NPC)
    local d1, d2 = J.Clip("quests", NPC, { key = "all-d1" }), J.Clip("gossip", NPC, { key = "all-d2" })
    J.Queue(d1)
    J.Queue(d2)
    J.CloseWindow()
    J.player.inInstance = true
    J.Advance(2)
    check(J.playing == nil and #J.queue == 0, "inside a dungeon, the world's lines are skipped", #J.queue)
    check(#H.errors + #J.errors == 0, "no errors", H.errors[1] or J.errors[1])
end)

scenario("out of earshot: wait until you come back", function()
    local H = NewClient({ spoken = "Ambience" })
    H.settings.registered.EARSHOT_AWAY:SetValue("wait")
    H.TalkTo(NPC)
    local a = H.Clip("quests", NPC, { key = "wait-a" })
    H.Queue(a)
    H.CloseWindow()
    H.MoveTo(-60, 0, 0)
    H.Advance(2)
    check(H.paused and H.queue[1] == a and H.playing == nil, "Spoken stops on the line")
    check(H.ns.char.heldSpoken == true, "noted, in case of a reload")
    H.Advance(3)
    check(H.Vol("Ambience") == 0.8, "your level comes back while it waits", H.Vol("Ambience"))
    local story = H.Clip("places", nil, { key = "wait-story" })
    H.Queue(story)
    H.Advance(0.1)
    check(H.playing == story and H.queue[2] == a and not H.paused, "a new line plays meanwhile")
    H.FinishLine()
    check(H.playing == a and H.Vol("Ambience") <= 0.0025, "its turn comes round again: silent", H.Vol("Ambience"))
    H.Advance(0.05)
    check(H.paused and H.queue[1] == a and H.playing == nil, "then Spoken stops on it again")
    H.Slash("status")
    check(H.LastChat():find("Waiting to replay a line until you walk back", 1, true) ~= nil, "status says so",
        H.LastChat())
    H.MoveTo(-20, 0, 0)
    H.Advance(0.5)
    check(not H.paused and H.playing == a and H.ns.char.heldSpoken == nil, "walk back and it plays from the start")
    check(H.ns.Spatial.session ~= nil, "placed again")
    -- You press Play while it waits: your call, and Earshot leaves it be.
    local J = NewClient({ spoken = "Ambience" })
    J.settings.registered.EARSHOT_AWAY:SetValue("wait")
    J.TalkTo(NPC)
    local b = J.Clip("quests", NPC, { key = "wait-b" })
    J.Queue(b)
    J.CloseWindow()
    J.MoveTo(-60, 0, 0)
    J.Advance(2)
    J.env.Spoken:Resume()
    J.Advance(3)
    check(not J.paused and J.playing == b, "you pressed Play: it plays on")
    -- Changing the setting while it waits lets it play.
    local K = NewClient({ spoken = "Ambience" })
    K.settings.registered.EARSHOT_AWAY:SetValue("wait")
    K.TalkTo(NPC)
    local c = K.Clip("quests", NPC, { key = "wait-c" })
    K.Queue(c)
    K.CloseWindow()
    K.MoveTo(-60, 0, 0)
    K.Advance(2)
    K.settings.registered.EARSHOT_AWAY:SetValue("quiet")
    check(not K.paused and K.playing == c, "switched to Keep playing quietly: it plays")
    -- Chatter was a passing remark: walk away from it and it's skipped rather than kept.
    local N = NewClient({ spoken = "Ambience" })
    N.settings.registered.EARSHOT_AWAY:SetValue("wait")
    N.Chat("say", "Lovely evening.", "Farmer", FARMER)
    local remark = N.Clip("chatter", FARMER, { text = "Lovely evening.", key = "wait-remark" })
    N.Queue(remark)
    N.MoveTo(-60, 0, 0)
    N.Advance(2)
    check(not N.paused and N.skips == 1 and #N.queue == 0, "walked away from chatter: skipped, not kept")
    -- Spoken drops the line it was stopped on: it shouldn't stay stopped.
    local P = NewClient({ spoken = "Ambience" })
    P.settings.registered.EARSHOT_AWAY:SetValue("wait")
    P.TalkTo(NPC)
    local d = P.Clip("quests", NPC, { key = "wait-d" })
    P.Queue(d)
    P.CloseWindow()
    P.MoveTo(-60, 0, 0)
    P.Advance(2)
    d.source:Remove(d)
    check(not P.paused, "Spoken let go of the line it was stopped on: it plays on")
    -- The setting changes just as its turn comes round again: it plays on, placed.
    local Q = NewClient({ spoken = "Ambience" })
    Q.settings.registered.EARSHOT_AWAY:SetValue("wait")
    Q.TalkTo(NPC)
    local e = Q.Clip("quests", NPC, { key = "wait-e" })
    Q.Queue(e)
    Q.CloseWindow()
    Q.MoveTo(-60, 0, 0)
    Q.Advance(2)
    Q.Queue(Q.Clip("places", nil, { key = "wait-story-2" }))
    Q.Advance(0.1)
    Q.FinishLine()
    Q.settings.registered.EARSHOT_AWAY:SetValue("quiet")
    Q.Advance(0.05)
    check(not Q.paused and Q.playing == e, "switched to Keep playing quietly as it came round: it plays")
    Q.MoveTo(-5, 0, 0)
    Q.Advance(1)
    check(near(Q.Vol("Ambience"), 0.8, 0.01), "and it's heard when you walk back", Q.Vol("Ambience"))
    -- A reload while it waited would leave Spoken stopped with nothing to resume.
    local L = NewClient({ spoken = "Ambience", spokenPaused = true, charDB = { heldSpoken = true } })
    check(not L.paused and L.ns.char.heldSpoken == nil, "after a reload, Spoken isn't left stopped")
    local M = NewClient({ spoken = "Ambience", spokenPaused = true })
    check(M.paused, "stopped by you, it stays stopped")
    check(#H.errors + #J.errors + #K.errors + #L.errors + #N.errors + #P.errors + #Q.errors == 0, "no errors",
        H.errors[1] or J.errors[1] or K.errors[1] or L.errors[1] or N.errors[1] or P.errors[1] or Q.errors[1])
end)

scenario("who's talking: a bubble over the NPC", function()
    local H = NewClient({ spoken = "Ambience" })
    Follow(H, true)
    H.npcs[FARMER] = { north = 10, west = 0 }
    local _, plate = H.ShowPlate(FARMER)
    local M = H.ns.Markers
    local clip = H.Clip("chatter", FARMER, { text = "Nice day for it.", key = "m1" })
    H.Spoken("CLIP_STARTED", clip)
    check(M:Showing(FARMER), "a bubble while its voice plays")
    local bubble
    for _, f in ipairs(H.frames) do
        if f.parent == plate then bubble = f end
    end
    check(bubble and bubble.shown and bubble.points[1][1] == "BOTTOM" and bubble.points[1][2] == plate.UnitFrame.name,
        "on its nameplate, just above its name")
    check(bubble.textures and bubble.textures[1].texture:find("Speaking", 1, true) ~= nil, "drawn with the bubble picture")
    H.Spoken("CLIP_STOPPED", clip, true)
    check(not M:Showing(FARMER) and not bubble.shown, "gone when the line ends")
    H.Chat("say", "Hmm.", "Farmer", FARMER)
    check(M:Showing(FARMER), "an NPC talking in chat without a voice gets one too")
    H.Advance(2.5)
    check(not M:Showing(FARMER), "for about as long as the line takes to say")
    H.Chat("whisper", "Psst.", "Farmer", FARMER)
    check(not M:Showing(FARMER), "a whisper (said to you) isn't marked")
    H.settings.registered.EARSHOT_MARKSILENT:SetValue(false)
    H.Chat("say", "Hmm, again.", "Farmer", FARMER)
    check(not M:Showing(FARMER), "Also NPCs talking without a voice off: no bubble for chat")
    H.settings.registered.EARSHOT_MARKERS:SetValue(false)
    H.Spoken("CLIP_STARTED", H.Clip("chatter", FARMER, { text = "Quiet now.", key = "m2" }))
    check(not M:Showing(FARMER), "Mark who's talking off: none at all")
    H.settings.registered.EARSHOT_MARKERS:SetValue(true)
    check(M:Showing(FARMER), "back on mid-line: there it is")
    local J = NewClient({ spoken = "Ambience" })
    Follow(J, true)
    J.npcs[FARMER] = { north = 10, west = 0 }
    J.Spoken("CLIP_STARTED", J.Clip("chatter", FARMER, { text = "Over here.", key = "m3" }))
    check(not J.ns.Markers:Showing(FARMER), "no nameplate, no bubble")
    local token = J.ShowPlate(FARMER)
    check(J.ns.Markers:Showing(FARMER), "its nameplate turns up mid-line: so does the bubble")
    J.RemovePlate(token)
    check(not J.ns.Markers:Showing(FARMER), "and goes with it")
    check(#H.errors + #J.errors == 0, "no errors", H.errors[1] or J.errors[1])
end)

scenario("NPC titles under the names on hidden nameplates", function()
    local H = NewClient({ spoken = "Ambience" })
    Follow(H, true)
    H.npcs[FARMER] = { north = 10, west = 0, title = "Stable Master" }
    local _, plate = H.ShowPlate(FARMER)
    local face = plate.UnitFrame
    local title = face.fontStrings and face.fontStrings[1]
    check(title and title.shown and title.text == "<Stable Master>", "the title shows", title and title.text)
    check(title.points[1][1] == "TOP" and title.points[1][2] == face.name and title.points[1][3] == "BOTTOM",
        "just under the name")
    check(title.tint and title.tint[1] == 0 and title.tint[2] == 1 and title.tint[3] == 0,
        "green like the name", title.tint and table.concat(title.tint, ","))
    check(title.font == "Fonts\\FRIZQT__.TTF" and title.size == 12 and title.flags == "OUTLINE",
        "in the name's font, at the same size (as above NPCs' heads)", title.size)
    local reads = H.tooltipReads
    H.npcs["Creature-0-1-2-3-300-0000CCCD"] = { north = 11, west = 0, title = "Stable Master" }
    H.ShowPlate("Creature-0-1-2-3-300-0000CCCD")
    check(H.tooltipReads == reads, "looked up once for each kind of NPC")
    local PLAIN = "Creature-0-1-2-3-400-0000DDDD"
    H.npcs[PLAIN] = { north = 12, west = 0 }
    local _, other = H.ShowPlate(PLAIN)
    local otherTitle = other.UnitFrame.fontStrings and other.UnitFrame.fontStrings[1]
    check(not (otherTitle and otherTitle.shown), "an NPC with only a level line has no title")
    local BANKER = "Creature-0-1-2-3-500-0000EEEE"
    H.npcs[BANKER] = { north = 14, west = 0, title = "<Banker>" }
    local _, bank = H.ShowPlate(BANKER)
    local bankTitle = bank.UnitFrame.fontStrings and bank.UnitFrame.fontStrings[1]
    check(bankTitle and bankTitle.text == "<Banker>", "a title already in brackets isn't doubled",
        bankTitle and bankTitle.text)
    face.name.shown = false
    H.env.CompactUnitFrame_UpdateName(face)
    check(not title.shown, "the game hides the name (your name settings): the title goes too")
    face.name.shown = true
    H.env.CompactUnitFrame_UpdateName(face)
    check(title.shown, "and comes back with it")
    H.settings.registered.EARSHOT_TITLES:SetValue(false)
    check(not title.shown, "Show NPC titles off")
    H.settings.registered.EARSHOT_TITLES:SetValue(true)
    check(title.shown, "and on")
    H.settings.registered.EARSHOT_HIDEPLATES:SetValue(false)
    check(not title.shown, "nameplates shown in full: no extra line")
    check(#H.errors == 0, "no errors", H.errors[1])
end)

scenario("names on hidden nameplates coloured like names above NPCs' heads", function()
    local H = NewClient({ spoken = "Ambience" })
    Follow(H, true)
    local function Tint(face) return table.concat(face.name.tint, ",") end
    H.npcs[FARMER] = { north = 10, west = 0 }
    local token, plate = H.ShowPlate(FARMER)
    local face = plate.UnitFrame
    check(Tint(face) == "0,1,0", "a friendly NPC's name is green, not the game's nameplate white", Tint(face))
    H.env.CompactUnitFrame_UpdateName(face)
    check(Tint(face) == "0,1,0", "and stays green when the game redoes the name", Tint(face))
    local NEUTRAL = "Creature-0-1-2-3-600-0000FFFF"
    H.npcs[NEUTRAL] = { north = 12, west = 0, reaction = 4 }
    local _, neutral = H.ShowPlate(NEUTRAL)
    check(Tint(neutral.UnitFrame) == "1,1,0", "a neutral NPC you can't attack: yellow", Tint(neutral.UnitFrame))
    H.units[token].dead = true
    H.env.CompactUnitFrame_UpdateName(face)
    check(Tint(face) == "0.5,0.5,0.5", "a dead NPC keeps the game's grey", Tint(face))
    H.units[token].dead = false
    H.env.CompactUnitFrame_UpdateName(face)
    check(Tint(face) == "0,1,0", "green again", Tint(face))
    H.selectionSecret = true
    H.env.CompactUnitFrame_UpdateName(face)
    check(Tint(face) == "1,1,1" and #H.errors == 0, "when the game keeps the colour secret, its own white stays",
        Tint(face))
    H.selectionSecret = nil
    H.env.CompactUnitFrame_UpdateName(face)
    local _, enemy = H.ShowPlate("Creature-0-1-2-3-700-00001111", "enemy")
    check(Tint(enemy.UnitFrame) == "1,1,1", "an enemy's nameplate keeps the game's colour", Tint(enemy.UnitFrame))
    -- The game reuses a hidden nameplate for an enemy, setting it up before Earshot hears.
    H.RemovePlate(token)
    local _, reused = H.ShowPlate("Creature-0-1-2-3-800-00002222", "enemy")
    check(reused.UnitFrame == face, "(the game reused the farmer's nameplate)")
    check(Tint(face) == "1,1,1", "reused for an enemy: the game's colour", Tint(face))
    H.settings.registered.EARSHOT_HIDEPLATES:SetValue(false)
    check(Tint(neutral.UnitFrame) == "1,1,1", "Hide friendly NPC nameplates off: the game's colour again",
        Tint(neutral.UnitFrame))
    H.settings.registered.EARSHOT_HIDEPLATES:SetValue(true)
    check(Tint(neutral.UnitFrame) == "1,1,0", "and on: yellow again", Tint(neutral.UnitFrame))
    -- In the game's Legacy nameplate style it colours names itself: an enemy's red.
    H.legacyStyle = true
    local VENDOR = "Creature-0-1-2-3-900-00003333"
    H.npcs[VENDOR] = { north = 13, west = 0 }
    local vendorToken, vendor = H.ShowPlate(VENDOR)
    check(Tint(vendor.UnitFrame) == "0,1,0", "Legacy style: a friendly NPC's name is green as before",
        Tint(vendor.UnitFrame))
    H.RemovePlate(vendorToken)
    local _, raider = H.ShowPlate("Creature-0-1-2-3-950-00004444", "enemy")
    check(raider.UnitFrame == vendor.UnitFrame and Tint(raider.UnitFrame) == "1,0,0",
        "and that nameplate reused for an enemy keeps the red the game gave it", Tint(raider.UnitFrame))
    check(#H.errors == 0, "no errors", H.errors[1])
end)

scenario("status, the minimap addon menu and the settings layout", function()
    local H = NewClient({ spoken = "Ambience" })
    Follow(H, true)
    H.MoveTo(0, 0, 0)
    H.npcs[FARMER] = { north = 15, west = 0, assist = true }
    H.ShowPlate(FARMER)
    H.Fire("CHAT_MSG_MONSTER_SAY", "Fine weather.", "Farmer")
    H.Spoken("CLIP_STARTED", H.Clip("chatter", FARMER, { text = "Fine weather.", key = "c-status" }))
    H.Advance(0.5)
    H.Slash("status")
    local said = table.concat(H.chat, "\n")
    check(said:find("Following speakers by nameplate, with friendly NPC nameplates showing only their names", 1, true)
        ~= nil,
        "status says following is on")
    check(said:find("Following its nameplate: 8-28 yd away", 1, true) ~= nil, "status gives the nameplate's distance",
        said:match("Following its[^\n]*") or "nothing")
    H.env.Earshot_OnAddonCompartmentClick("Earshot", "LeftButton")
    check(H.settings.opened == 1, "the minimap addon menu opens Earshot's settings")
    H.env.Earshot_OnAddonCompartmentEnter("Earshot", {})
    check(H.tooltipShown == true, "hovering it shows a tooltip")
    H.env.Earshot_OnAddonCompartmentLeave("Earshot", {})
    check(H.tooltipShown == false, "and hides it again")
    local hide
    for _, c in ipairs(H.settings.controls) do
        if c.setting and c.setting.variable == "EARSHOT_HIDEPLATES" then hide = c.initializer end
    end
    check(hide and hide.indented and hide.parent and hide.parent.setting.variable == "EARSHOT_FOLLOW",
        "Hide sits indented under Follow speakers")
    local function Parent(variable)
        local c = Control(H, variable)
        return c and c.initializer and c.initializer.indented and c.initializer.parent
            and c.initializer.parent.setting.variable
    end
    check(Parent("EARSHOT_TITLES") == "EARSHOT_HIDEPLATES", "Show NPC titles sits under Hide")
    check(Parent("EARSHOT_CHATTERRANGE") == "EARSHOT_CHATTER" and Parent("EARSHOT_YELLRANGE") == "EARSHOT_CHATTER",
        "the chatter and yell ranges sit under World chatter")
    check(Parent("EARSHOT_MARKSILENT") == "EARSHOT_MARKERS", "the chat bubbles option sits under Mark who's talking")
    local away = Control(H, "EARSHOT_AWAY")
    local values = {}
    for _, choice in ipairs(away.data) do table.insert(values, choice.value) end
    check(away.kind == "dropdown" and table.concat(values, " ") == "quiet skip skipNpc skipAll wait",
        "When you walk out of earshot offers five choices", table.concat(values, " "))
    local long
    for _, c in ipairs(H.settings.controls) do
        for _, choice in ipairs(c.kind == "dropdown" and c.data or {}) do
            if #choice.label > 30 then long = choice.label end
        end
    end
    check(long == nil, "every dropdown choice fits (30 characters or fewer)", long)
    -- The settings list cuts labels off rather than wrapping them: about 30 characters fit, a few
    -- more for an indented setting (it uses a smaller font).
    long = nil
    for _, c in ipairs(H.settings.controls) do
        local name = c.setting and c.setting.name
        if name and #name > (c.initializer and c.initializer.indented and 34 or 30) then long = name end
    end
    check(long == nil, "every setting's label fits", long)
end)

-- The settings page as text, top to bottom: headers, rows (indented ones further in, greyed
-- ones marked) and buttons.
local function PageText(H)
    local lines = {}
    for _, row in ipairs(H.settings.page) do
        if row.kind == "header" then
            table.insert(lines, "")
            table.insert(lines, "== " .. row.header)
        else
            local text
            if row.kind == "button" then
                text = ("%s  [%s]"):format(row.button, row.buttonText)
            else
                local value = row.setting:GetValue()
                if row.kind == "checkbox" then
                    text = ("[%s] %s"):format(value and "x" or " ", row.setting.name)
                elseif row.kind == "slider" then
                    text = ("%s: %s"):format(row.setting.name, row.options.formatter(value))
                else
                    local label = tostring(value)
                    for _, choice in ipairs(row.data) do
                        if choice.value == value then label = choice.label end
                    end
                    text = ("%s: %s v"):format(row.setting.name, label)
                end
            end
            if not row:EvaluateModifyPredicates() then text = text .. "   (greyed out)" end
            table.insert(lines, (row.indented and "      " or "  ") .. text)
        end
    end
    return table.concat(lines, "\n")
end

scenario("the settings page", function()
    local H = NewClient({ spoken = "Ambience" })
    if DUMP_PAGE then note(PageText(H)) end
    local function Variable(row) return row.setting and row.setting.variable end
    local function Own(row)
        local variable = Variable(row)
        return variable and variable ~= "EARSHOT_ENABLED" and not variable:find("^EARSHOT_GAME_")
    end
    -- Headers in order, and the out-of-earshot choice with the distances.
    local headers, awayUnder = {}, nil
    for _, row in ipairs(H.settings.page) do
        if row.kind == "header" then table.insert(headers, row.header) end
        if Variable(row) == "EARSHOT_AWAY" then awayUnder = headers[#headers] end
    end
    check(table.concat(headers, " / ") == "Distance / Voices to place / Follow the speaker / Who's talking / "
        .. "The game's own sounds / Test and setup", "the page's sections", table.concat(headers, " / "))
    check(awayUnder == "Distance", "When you walk out of earshot sits with the distances", awayUnder)
    -- Switched off, Earshot's own rows grey out; the game's options and the buttons don't.
    local switches = { "EARSHOT_ENABLED", "EARSHOT_CHATTER", "EARSHOT_FOLLOW", "EARSHOT_HIDEPLATES", "EARSHOT_MARKERS" }
    for _, variable in ipairs(switches) do H.settings.registered[variable]:SetValue(true) end
    local grey
    for _, row in ipairs(H.settings.page) do
        if row.kind ~= "header" and not row:EvaluateModifyPredicates() then grey = Variable(row) or row.button end
    end
    check(grey == nil, "with everything switched on, nothing is greyed out", grey)
    H.settings.registered.EARSHOT_ENABLED:SetValue(false)
    local live, dead = nil, nil
    for _, row in ipairs(H.settings.page) do
        if row.kind ~= "header" then
            local usable = row:EvaluateModifyPredicates()
            if Own(row) and usable then live = Variable(row) end
            if not Own(row) and not usable then dead = Variable(row) or row.button end
        end
    end
    check(live == nil, "switched off, every Earshot setting is greyed out", live)
    check(dead == nil, "but the switch, the game's own options and the buttons still work", dead)
    H.settings.registered.EARSHOT_ENABLED:SetValue(true)
    -- The page redraws a row only when its parent's setting, or a setting it names, changes.
    -- So a row that greys out with a switch has to hear about that switch.
    local deaf
    for _, row in ipairs(H.settings.page) do
        if row.kind ~= "header" then
            for _, variable in ipairs(switches) do
                local setting = H.settings.registered[variable]
                local before = row:EvaluateModifyPredicates()
                setting:SetValue(false)
                local after = row:EvaluateModifyPredicates()
                setting:SetValue(true)
                local hears = row.parent and row.parent.setting.variable == variable
                for _, name in ipairs(row.evaluateOn or {}) do
                    if name == variable then hears = true end
                end
                if before ~= after and not hears then deaf = (Variable(row) or row.button) .. " misses " .. variable end
            end
        end
    end
    check(deaf == nil, "every row that greys out is redrawn when its switch changes", deaf)
    -- Defaults puts Earshot's settings back and leaves the game's own options alone.
    H.cvars.Sound_EnableReverb = "0"
    H.cvars.Sound_EnablePositionalLowPassFilter = "0"
    H.settings.registered.EARSHOT_FULL:SetValue(20)
    H.settings.registered.EARSHOT_AWAY:SetValue("skip")
    H.settings.registered.EARSHOT_FOLLOW:SetValue(true)
    for _, setting in pairs(H.settings.registered) do setting:SetValueToDefault() end
    check(H.cvars.Sound_EnableReverb == "0" and H.cvars.Sound_EnablePositionalLowPassFilter == "0",
        "Defaults leaves the game's own sound options alone")
    check(H.ns.db.full == H.ns.DEFAULTS.full and H.ns.db.away == "quiet" and H.ns.db.follow == false,
        "and puts Earshot's back")
    -- The minimap addon menu's tooltip says what Earshot is doing.
    H.env.Earshot_OnAddonCompartmentEnter("Earshot", {})
    check((H.tooltipLines[2] or ""):find("^On") ~= nil, "the minimap menu's tooltip says it's on", H.tooltipLines[2])
    H.Slash("off")
    H.env.Earshot_OnAddonCompartmentEnter("Earshot", {})
    check((H.tooltipLines[2] or ""):find("^Off") ~= nil and H.settings.notified == "EARSHOT_ENABLED",
        "and off, and /earshot off redraws the page", H.tooltipLines[2])
    local M = NewClient({ spoken = "Master" })
    M.env.Earshot_OnAddonCompartmentEnter("Earshot", {})
    check((M.tooltipLines[2] or ""):find("Master Volume", 1, true) ~= nil, "and when Spoken is on Master Volume",
        M.tooltipLines[2])
    H.Slash("help")
    check(H.LastChat():find("/earshot test", 1, true) ~= nil, "/earshot help lists the commands", H.LastChat())
    check(#H.errors + #M.errors == 0, "no errors", H.errors[1] or M.errors[1])
end)

scenario("the bundled libraries", function()
    for _, file in ipairs({ "Libs/LibStub/LibStub.lua", "Libs/LibRangeCheck-3.0/LibRangeCheck-3.0.lua" }) do
        local chunk, err = loadstring(ReadFile(ADDON_DIR .. "/" .. file), "@" .. file)
        check(chunk ~= nil, file .. " has no syntax errors", err)
    end
    local env = { assert = assert, tonumber = tonumber, string = string, error = error,
        setmetatable = setmetatable, pairs = pairs, type = type, tostring = tostring }
    env._G = env
    local chunk = loadstring(ReadFile(ADDON_DIR .. "/Libs/LibStub/LibStub.lua"))
    setfenv(chunk, env)
    chunk()
    local lib = env.LibStub:NewLibrary("Test-1.0", 1)
    check(type(lib) == "table" and env.LibStub("Test-1.0") == lib, "LibStub works")
    local toc = ReadFile(ADDON_DIR .. "/Earshot.toc")
    local stub, range, first = toc:find("Libs\\LibStub", 1, true), toc:find("Libs\\LibRangeCheck", 1, true),
        toc:find("Math.lua", 1, true)
    check(stub and range and first and stub < range and range < first, "the TOC loads LibStub, then LibRangeCheck, first")
end)

for _, s in ipairs(scenarios) do
    local before = results.failed
    clients = {}
    local ok, err = pcall(s.fn)
    if not ok then
        results.failed = results.failed + 1
        note("  ERROR " .. tostring(err))
    end
    -- Every scenario: Earshot never skips or stops Spoken on a line while Spoken is starting it.
    for _, H in ipairs(clients) do
        check((H.strayTimers or 0) == 0, "nothing skipped or stopped while Spoken was starting it",
            tostring(H.strayTimers))
    end
    table.insert(results.lines, (results.failed == before and "ok   " or "FAIL ") .. s.name)
end

-- Print each scenario name after its failures, in run order
local out = {}
local pending = {}
for _, line in ipairs(results.lines) do
    if line:find("^  ") then table.insert(pending, line)
    else
        table.insert(out, line)
        for _, p in ipairs(pending) do table.insert(out, p) end
        pending = {}
    end
end
table.insert(out, ("%d checks passed, %d failed"):format(results.passed, results.failed))
return table.concat(out, "\n"), results.failed
