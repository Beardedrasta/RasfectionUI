
--[[
 RasfectionUI - Core/GroupVisuals.lua
 Version 2.7.0
 WoW 3.3.5a / Build 12340

 PARTY AND RAID VISUAL INTEGRATION

 Features:
  - Uses GlobalMedia font selection
  - Uses GlobalMedia bar texture selection
  - Independent group text scaling
  - Optional font synchronization
  - Optional bar texture synchronization
  - Optional font outline
  - Live out-of-combat updates
  - Per-character saved preferences
  - ElvUI-style Appearance page integration

 SAFETY:
  - Does not show or hide any group frames
  - Does not change secure attributes
  - Does not change group positions or sizes
  - Does not overwrite health/power colors
  - Does not replace group-frame events
  - Does not modify click-casting
  - Does not modify aura, heal, or threat logic
]]

local RUI = _G.RasfectionUI
if not RUI then return end

local Visuals = {}

Visuals.version = "2.7.0"
Visuals.initialized = false
Visuals.pageInstalled = false
Visuals.pending = false
Visuals.applying = false

local DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"
local DEFAULT_TEXTURE =
    "Interface\\Buttons\\WHITE8X8"

local GROUP_MODULES = {
    "PartyFrames",
    "RaidFrames"
}

local function Module(name)
    if not RUI.GetModule then return nil end
    return RUI:GetModule(name)
end

local function Combat()
    return InCombatLockdown
        and InCombatLockdown()
end

local function Clamp(value, lo, hi, fallback)
    value = tonumber(value)

    if not value
        or value ~= value
        or value == math.huge
        or value == -math.huge then
        value = fallback or lo
    end

    return math.max(
        lo,
        math.min(
            hi, math.floor(value + 0.5)
        )
    )
end

local function IsFrame(value)
    return value
        and type(value.GetObjectType) == "function"
        and type(value.GetChildren) == "function"
end

local function IsFontString(value)
    return value
        and type(value.GetObjectType) == "function"
        and value:GetObjectType() == "FontString"
end

local function IsStatusBar(value)
    return value
        and type(value.GetObjectType) == "function"
        and value:GetObjectType() == "StatusBar"
end

local function SafeFontPath()
    local media = Module("GlobalMedia")

    if media and media.GetFontPath then
        return media:GetFontPath()
    end

    return DEFAULT_FONT
end

local function SafeBarTexture()
    local media = Module("GlobalMedia")

    if media and media.GetTexturePath then
        return media:GetTexturePath()
    end

    return DEFAULT_TEXTURE
end

-- ==========================================
-- SETTINGS
-- ==========================================

function Visuals:GetSettings()
    local db = Module("Database")

    if not db or not db.GetProfile then
        return nil
    end

    local profile = db:GetProfile()
    if not profile then return nil end

    if type(profile.settings) ~= "table" then
        profile.settings = {}
    end

    local all = profile.settings

    if type(all.groupVisuals) ~= "table" then
        all.groupVisuals = {}
    end

    local s = all.groupVisuals

    if type(s.partyFonts) ~= "boolean" then
        s.partyFonts = true
    end

    if type(s.raidFonts) ~= "boolean" then
        s.raidFonts = true
    end

    if type(s.partyTextures) ~= "boolean" then
        s.partyTextures = true
    end

    if type(s.raidTextures) ~= "boolean" then
        s.raidTextures = true
    end

    if type(s.groupOutline) ~= "boolean" then
        s.groupOutline = true
    end

    s.partyTextScale = Clamp(
        s.partyTextScale, 70, 150, 100
    )

    s.raidTextScale = Clamp(
        s.raidTextScale, 70, 150, 100
    )

    return s
end

-- ==========================================
-- FRAME DISCOVERY
-- ==========================================

function Visuals:GetRoots(id)
    local module = Module(id)
    local roots = {}
    local seen = {}

    local function Add(frame)
        if IsFrame(frame)
            and not seen[frame] then
            seen[frame] = true
            table.insert(roots, frame)
        end
    end

    if module then
        Add(module.container)
        Add(module.frame)
        Add(module.header)
        Add(module.raidHeader)
        Add(module.partyHeader)

        -- Some versions store rows/buttons.
        -- They may already be descendants of
        -- the main container. Repeated frames
        -- are protected by the traversal cache.
        for _, collection in ipairs({
            module.rows or {},
            module.buttons or {},
            module.frames or {}
        }) do
            if type(collection) == "table" then
                for _, child in pairs(collection) do
                    Add(child)
                end
            end
        end
    end

    -- Fall back to the named raid container.
    -- This is a reference only: no Show/Hide.
    if id == "RaidFrames" then
        Add(_G.RasfectionUIRaidContainer)
    end

    return roots
end

-- ==========================================
-- STYLE TRACKING
-- ==========================================

Visuals.fontOriginals = setmetatable(
    {}, {__mode = "k"}
)

Visuals.barOriginals = setmetatable(
    {}, {__mode = "k"}
)

function Visuals:CaptureFont(font)
    local original = self.fontOriginals[font]

    if original then
        return original
    end

    local path, size, flags = font:GetFont()

    if not size or size <= 0 then
        return nil
    end

    original = {
        path = path or DEFAULT_FONT,
        size = size,
        flags = flags or ""
    }

    self.fontOriginals[font] = original

    return original
end

function Visuals:CaptureBar(bar)
    local original = self.barOriginals[bar]

    if original then
        return original
    end

    local texture = bar:GetStatusBarTexture()
    local path

    if texture and texture.GetTexture then
        path = texture:GetTexture()
    end

    local r, g, b, a = bar:GetStatusBarColor()

    original = {
        texture = path or DEFAULT_TEXTURE,
        r = r or 1,
        g = g or 1,
        b = b or 1,
        a = a or 1
    }

    self.barOriginals[bar] = original

    return original
end

-- ==========================================
-- APPLY TEXT STYLE
-- ==========================================

function Visuals:StyleFont(
    font, useGlobal, scale, outline
)
    if not IsFontString(font) then
        return
    end

    local original = self:CaptureFont(font)
    if not original then return end

    local path

    if useGlobal then
        path = SafeFontPath()
    else
        path = original.path
    end

    local size = math.max(
        6,
        math.min(
            32,
            original.size * (scale / 100)
        )
    )

    local flags = outline
        and "OUTLINE"
        or original.flags

    local ok = font:SetFont(path, size, flags)

    if not ok then
        font:SetFont(
            original.path, size, original.flags
        )
    end

    -- Deliberately preserve:
    -- font:GetTextColor()
    -- font:GetShadowColor()
    -- font:GetJustifyH()
    -- font:GetJustifyV()
end

-- ==========================================
-- APPLY STATUS BAR TEXTURE
-- ==========================================

function Visuals:StyleBar(bar, useGlobal)
    if not IsStatusBar(bar) then return end

    local original = self:CaptureBar(bar)
    if not original then return end

    local path = useGlobal
        and SafeBarTexture()
        or original.texture

    -- Keep the colors the existing group
    -- module calculated for this bar.
    local r, g, b, a = bar:GetStatusBarColor()

    bar:SetStatusBarTexture(path)

    bar:SetStatusBarColor(
        r or original.r,
        g or original.g,
        b or original.b,
        a or original.a
    )
end

-- ==========================================
-- WALK GROUP CONTENT
-- ==========================================

function Visuals:WalkFrame(
    frame, settings, isParty, visited
)
    if not IsFrame(frame) then return end
    if visited[frame] then return end

    visited[frame] = true

    local fonts = isParty
        and settings.partyFonts
        or settings.raidFonts

    local bars = isParty
        and settings.partyTextures
        or settings.raidTextures

    local scale = isParty
        and settings.partyTextScale
        or settings.raidTextScale

    if IsStatusBar(frame) then
        self:StyleBar(frame, bars)
    end

    -- GetRegions returns all region values.
    -- Only FontStrings are modified.
    local regions = {frame:GetRegions()}

    for _, region in ipairs(regions) do
        if IsFontString(region) then
            self:StyleFont(
                region,
                fonts,
                scale,
                settings.groupOutline
            )
        end
    end

    local children = {frame:GetChildren()}

    for _, child in ipairs(children) do
        if IsFrame(child) then
            self:WalkFrame(
                child, settings, isParty, visited
            )
        end
    end
end

-- ==========================================
-- APPLY GROUP STYLES
-- ==========================================

function Visuals:ApplyGroup(id)
    if Combat() then
        self.pending = true
        return false
    end

    local s = self:GetSettings()
    if not s then return false end

    local isParty = id == "PartyFrames"
    local roots = self:GetRoots(id)
    local visited = {}

    for _, root in ipairs(roots) do
        self:WalkFrame(
            root, s, isParty, visited
        )
    end

    return true
end

function Visuals:ApplyAll()
    if Combat() then
        self.pending = true
        return false
    end

    if self.applying then return false end

    self.applying = true

    for _, id in ipairs(GROUP_MODULES) do
        self:ApplyGroup(id)
    end

    self.pending = false
    self.applying = false

    return true
end

-- ==========================================
-- OPTION UPDATES
-- ==========================================

function Visuals:SetOption(key, value)
    if Combat() then
        if RUI.Error then
            RUI:Error(
                "Group visual settings cannot change in combat."
            )
        end
        return false
    end

    local s = self:GetSettings()
    if not s then return false end

    if key == "partyTextScale"
        or key == "raidTextScale" then

        s[key] = Clamp(value, 70, 150, 100)

    elseif key == "partyFonts"
        or key == "raidFonts"
        or key == "partyTextures"
        or key == "raidTextures"
        or key == "groupOutline" then

        s[key] = value == true

    else
        return false
    end

    self:ApplyAll()

    local config = Module("Config")
    if config and config.Refresh then
        config:Refresh()
    end

    return true
end

-- ==========================================
-- GLOBAL MEDIA INTEGRATION
-- ==========================================

function Visuals:InstallMediaBridge()
    if self.mediaWrapped then
        return true
    end

    local media = Module("GlobalMedia")
    if not media or not media.ApplyAll then
        return false
    end

    local oldApply = media.ApplyAll
    local visuals = self

    media.ApplyAll = function(mediaSelf, ...)
        local result = oldApply(mediaSelf, ...)

        if not Combat() then
            visuals:ApplyAll()
        end

        return result
    end

    self.mediaWrapped = true

    return true
end

-- ==========================================
-- CONFIG PAGE EXTENSION
-- ==========================================

function Visuals:InstallConfigPage()
    if self.pageInstalled then
        return true
    end

    local config = Module("Config")

    if not config or not config.BuildAppearance then
        return false
    end

    local oldBuild = config.BuildAppearance

    config.BuildAppearance = function(ui)
        local page = oldBuild(ui)
        if not page then return nil end

        page:SetHeight(2560)

        ui:Section(
            page, "PARTY & RAID VISUALS", 1970
        )

        ui:Description(
            page,
            "Synchronize group frames with the global font and bar texture, without changing their individual colors or layouts.",
            2015
        )

        local function Boolean(key, label, y)
            ui:Check(
                page, key, label, y,
                function()
                    local s = Visuals:GetSettings()
                    return s and s[key] == true
                        or false
                end,
                function(value)
                    Visuals:SetOption(key, value)
                end
            )
        end

        local function Numeric(
            key, label, y, lo, hi
        )
            ui:Slider(
                page, key, label, y, lo, hi,
                function()
                    local s = Visuals:GetSettings()
                    return s and s[key] or 100
                end,
                function(value)
                    Visuals:SetOption(key, value)
                end
            )
        end

        ui:Section(page, "PARTY FRAMES", 2090)

        Boolean(
            "partyFonts",
            "Use global font in Party frames",
            2130
        )

        Boolean(
            "partyTextures",
            "Use global status-bar texture in Party",
            2175
        )

        Numeric(
            "partyTextScale",
            "Party text size (%)",
            2220, 70, 150
        )

        ui:Section(page, "RAID FRAMES", 2310)

        Boolean(
            "raidFonts",
            "Use global font in Raid frames",
            2350
        )

        Boolean(
            "raidTextures",
            "Use global status-bar texture in Raid",
            2395
        )

        Numeric(
            "raidTextScale",
            "Raid text size (%)",
            2440, 70, 150
        )

        page:SetHeight(2700)

        ui:Check(
            page,
            "groupOutline",
            "Outline group-frame text",
            2550,
            function()
                local s = Visuals:GetSettings()
                return s and s.groupOutline == true
                    or false
            end,
            function(value)
                Visuals:SetOption(
                    "groupOutline", value
                )
            end
        )

        ui:Description(
            page,
            "Fonts and bar surfaces update immediately outside combat. Group frame visibility and healing indicators remain controlled by the Party and Raid modules.",
            2610
        )

        return page
    end

    self.pageInstalled = true
    return true
end

-- ==========================================
-- INITIALIZATION
-- ==========================================

function Visuals:Initialize()
    if self.initialized then
        return
    end

    self:GetSettings()
    self:InstallMediaBridge()
    self:InstallConfigPage()

    local controller = CreateFrame(
        "Frame",
        "RasfectionUIGroupVisualsController",
        UIParent
    )

    controller:RegisterEvent(
        "PLAYER_ENTERING_WORLD"
    )
    controller:RegisterEvent(
        "PLAYER_REGEN_ENABLED"
    )
    controller:RegisterEvent(
        "PARTY_MEMBERS_CHANGED"
    )
    controller:RegisterEvent(
        "RAID_ROSTER_UPDATE"
    )

    controller:SetScript(
        "OnEvent",
        function()
            if Combat() then
                Visuals.pending = true
                return
            end

            Visuals:ApplyAll()
        end
    )

    self.controller = controller
    self.initialized = true

    self:ApplyAll()

    if RUI.Success then
        RUI:Success(
            "Party & Raid Visuals v2.7 initialized."
        )
    end
end

RUI:RegisterModule(
    "GroupVisuals",
    Visuals
)
