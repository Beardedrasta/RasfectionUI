
--[[
 RasfectionUI
 Core/GlobalAppearance.lua

 Version 2.4.1
 WoW 3.3.5a / Build 12340

 FIX:
   RasfectionUIRaidContainer showing outside raids

 CHANGES:
   - Raid containers are styled only while in raid
   - Stray raid container hidden outside raid
   - Raid roster changes update appearance safely
   - Preview state respected when detectable
   - No protected visibility changes during combat
   - Periodic recovery from incorrect visibility

 PRESERVED:
   - Six global appearance presets
   - Custom accent/background RGB
   - Background opacity
   - Metallic border intensity
   - Accent tint strength
   - ElvUI-style Appearance settings page
   - Exact numeric inputs
   - Existing theme engine integration
   - Per-character saved settings
]]

local RUI = _G.RasfectionUI
if not RUI then return end

local Appearance = {}

Appearance.version = "2.4.1"
Appearance.initialized = false
Appearance.presetButtons = {}
Appearance.themeWrapped = false
Appearance.pendingApply = false

local PRESETS = {
    purple = {
        label = "Midnight Purple",
        color = {166, 106, 232},
        background = {9, 11, 17}
    },

    frost = {
        label = "Frost Blue",
        color = {87, 155, 231},
        background = {9, 14, 22}
    },

    crimson = {
        label = "Crimson",
        color = {216, 93, 103},
        background = {21, 10, 15}
    },

    emerald = {
        label = "Emerald",
        color = {70, 173, 130},
        background = {9, 19, 16}
    },

    amber = {
        label = "Amber",
        color = {212, 163, 77},
        background = {20, 16, 9}
    },

    obsidian = {
        label = "Obsidian",
        color = {154, 159, 171},
        background = {10, 12, 15}
    }
}

local PRESET_ORDER = {
    "purple",
    "frost",
    "crimson",
    "emerald",
    "amber",
    "obsidian"
}

local function Combat()
    return InCombatLockdown
        and InCombatLockdown()
end

local function InRaid()
    return (GetNumRaidMembers() or 0) > 0
end

local function Clamp(value, low, high, fallback)
    value = tonumber(value)

    if not value
        or value ~= value
        or value == math.huge
        or value == -math.huge then
        value = fallback or low
    end

    return math.max(
        low,
        math.min(
            high,
            math.floor(value + 0.5)
        )
    )
end

local function Module(name)
    return RUI:GetModule(name)
end

local function CopyRGB(rgb)
    return {
        rgb[1],
        rgb[2],
        rgb[3]
    }
end

local function IsValidFrame(frame)
    return frame
        and frame.SetBackdropColor
        and frame.SetBackdropBorderColor
end

-- ==========================================
-- RAID VISIBILITY PROTECTION
-- ==========================================

function Appearance:GetRaidModule()
    return Module("RaidFrames")
end

function Appearance:IsRaidPreviewActive()
    local raid = self:GetRaidModule()

    if not raid then
        return false
    end

    -- Respect explicit preview flags if the
    -- installed raid module uses them.
    if raid.preview == true
        or raid.previewMode == true
        or raid.previewActive == true
        or raid.isPreviewing == true
        or raid.previewEnabled == true then
        return true
    end

    return false
end

function Appearance:GetRaidContainer()
    local raid = self:GetRaidModule()

    if raid and raid.container then
        return raid.container
    end

    return _G.RasfectionUIRaidContainer
end

function Appearance:ProtectRaidVisibility()
    if Combat() then
        self.pendingRaidCheck = true
        return false
    end

    -- Never modify raid visibility while
    -- actually inside a raid.
    if InRaid() then
        self.pendingRaidCheck = false
        return true
    end

    -- Don't interfere with an intentionally
    -- activated raid preview.
    if self:IsRaidPreviewActive() then
        self.pendingRaidCheck = false
        return true
    end

    local raid = self:GetRaidModule()
    local container = self:GetRaidContainer()

    if container and container:IsShown() then
        container:Hide()
    end

    -- Some versions use an outer frame.
    -- Hide it only if it is distinct from
    -- the main container.
    if raid and raid.frame
        and raid.frame ~= container
        and raid.frame:IsShown() then
        raid.frame:Hide()
    end

    self.pendingRaidCheck = false
    return true
end

-- ==========================================
-- SAVED APPEARANCE SETTINGS
-- ==========================================

function Appearance:GetSettings()
    local db = Module("Database")

    if not db or not db.GetProfile then
        return nil
    end

    local profile = db:GetProfile()
    if not profile then return nil end

    if type(profile.settings) ~= "table" then
        profile.settings = {}
    end

    if type(profile.settings.globalAppearance)
        ~= "table" then
        profile.settings.globalAppearance = {}
    end

    local s = profile.settings.globalAppearance

    if type(s.preset) ~= "string"
        or (not PRESETS[s.preset]
            and s.preset ~= "custom") then
        s.preset = "purple"
    end

    if type(s.accentColor) ~= "table" then
        s.accentColor =
            CopyRGB(PRESETS.purple.color)
    end

    if type(s.backgroundColor) ~= "table" then
        s.backgroundColor =
            CopyRGB(PRESETS.purple.background)
    end

    for i = 1, 3 do
        s.accentColor[i] = Clamp(
            s.accentColor[i],
            0, 255,
            PRESETS.purple.color[i]
        )

        s.backgroundColor[i] = Clamp(
            s.backgroundColor[i],
            0, 255,
            PRESETS.purple.background[i]
        )
    end

    s.backgroundOpacity = Clamp(
        s.backgroundOpacity,
        25, 100, 96
    )

    s.borderIntensity = Clamp(
        s.borderIntensity,
        0, 100, 100
    )

    s.accentStrength = Clamp(
        s.accentStrength,
        0, 100, 35
    )

    return s
end

-- ==========================================
-- THEME COLORS
-- ==========================================

function Appearance:GetAccent()
    local s = self:GetSettings()

    if not s then
        return 0.65, 0.42, 0.91
    end

    return
        s.accentColor[1] / 255,
        s.accentColor[2] / 255,
        s.accentColor[3] / 255
end

function Appearance:GetBackground()
    local s = self:GetSettings()

    if not s then
        return 0.035, 0.043, 0.067, 0.96
    end

    return
        s.backgroundColor[1] / 255,
        s.backgroundColor[2] / 255,
        s.backgroundColor[3] / 255,
        s.backgroundOpacity / 100
end

function Appearance:GetBorderTint()
    local s = self:GetSettings()

    if not s then
        return 1, 1, 1, 1
    end

    local r, g, b = self:GetAccent()

    local strength = s.accentStrength / 100
    local neutral = 0.83

    return
        neutral * (1 - strength) + r * strength,
        neutral * (1 - strength) + g * strength,
        neutral * (1 - strength) + b * strength,
        s.borderIntensity / 100
end

-- ==========================================
-- FRAME STYLING
-- ==========================================

function Appearance:StyleFrame(frame)
    if Combat() then
        return false
    end

    if not IsValidFrame(frame) then
        return false
    end

    -- Styling only.
    -- No Show(), Enable(), or frame creation.
    local r, g, b, a = self:GetBackground()
    local br, bg, bb, ba = self:GetBorderTint()

    frame:SetBackdropColor(r, g, b, a)
    frame:SetBackdropBorderColor(br, bg, bb, ba)

    return true
end

function Appearance:IsRaidOwnedFrame(frame)
    if not frame then return false end

    local raid = self:GetRaidModule()

    if frame == _G.RasfectionUIRaidContainer then
        return true
    end

    if raid then
        return frame == raid.container
            or frame == raid.frame
            or frame == raid.border
    end

    return false
end

function Appearance:GetKnownFrames()
    local frames = {}
    local seen = {}

    local function Add(frame)
        if frame
            and IsValidFrame(frame)
            and not seen[frame] then

            seen[frame] = true
            table.insert(frames, frame)
        end
    end

    -- Compact unit frames.
    for _, name in ipairs({
        "PlayerFrame",
        "TargetFrame",
        "FocusFrame",
        "PetFrame",
        "TargetTargetFrame",
        "FocusTargetFrame"
    }) do
        local module = Module(name)

        if module then
            Add(module.frame)
        end
    end

    -- Party container.
    local party = Module("PartyFrames")

    if party then
        Add(party.container)
    end

    -- Raid visuals are only styled while
    -- the raid UI is legitimately active.
    if InRaid() then
        local raid = self:GetRaidModule()

        if raid then
            Add(raid.container)
            Add(raid.frame)
            Add(raid.border)
        end
    end

    -- Global configuration window.
    local config = Module("Config")

    if config then
        Add(config.window)
    end

    return frames
end

function Appearance:ApplyExistingFrames()
    if Combat() then
        self.pendingApply = true
        return false
    end

    local frames = self:GetKnownFrames()

    for _, frame in ipairs(frames) do
        self:StyleFrame(frame)
    end

    self.pendingApply = false

    -- Recover raid container if it was
    -- erroneously visible after earlier
    -- theme changes or reloads.
    self:ProtectRaidVisibility()

    return true
end

-- ==========================================
-- THEME BRIDGE
-- ==========================================

function Appearance:InstallThemeBridge()
    if self.themeWrapped then
        return true
    end

    local theme = Module("Theme")

    if not theme or not theme.Apply then
        return false
    end

    local original = theme.Apply
    self.originalThemeApply = original

    local appearance = self

    theme.Apply = function(themeSelf, frame, options)
        local result = original(
            themeSelf, frame, options
        )

        if not Combat() then
            -- Never interfere with inactive
            -- raid headers/containers.
            if not appearance:IsRaidOwnedFrame(frame)
                or InRaid() then

                appearance:StyleFrame(frame)
            end
        end

        return result
    end

    self.themeWrapped = true
    return true
end

-- ==========================================
-- SETTINGS ACTIONS
-- ==========================================

function Appearance:SetPreset(id)
    if Combat() then
        RUI:Error("Change themes outside combat.")
        return false
    end

    local preset = PRESETS[id]
    if not preset then return false end

    local s = self:GetSettings()
    if not s then return false end

    s.preset = id
    s.accentColor = CopyRGB(preset.color)
    s.backgroundColor = CopyRGB(preset.background)

    self:ApplyAll()
    return true
end

function Appearance:SetOption(key, value)
    if Combat() then
        RUI:Error(
            "Appearance settings are locked in combat."
        )
        return false
    end

    local s = self:GetSettings()
    if not s then return false end

    local limits = {
        backgroundOpacity = {25, 100},
        borderIntensity = {0, 100},
        accentStrength = {0, 100}
    }

    local limitsForKey = limits[key]
    if not limitsForKey then return false end

    s[key] = Clamp(
        value,
        limitsForKey[1],
        limitsForKey[2],
        s[key]
    )

    self:ApplyAll()
    return true
end

function Appearance:SetColorChannel(group, index, value)
    if Combat() then
        RUI:Error("Change colors outside combat.")
        return false
    end

    if index < 1 or index > 3 then
        return false
    end

    local s = self:GetSettings()
    if not s then return false end

    local key

    if group == "accent" then
        key = "accentColor"
    elseif group == "background" then
        key = "backgroundColor"
    else
        return false
    end

    s[key][index] = Clamp(
        value, 0, 255, s[key][index]
    )

    s.preset = "custom"

    self:ApplyAll()
    return true
end

-- ==========================================
-- CONFIGURATION HIGHLIGHTS
-- ==========================================

function Appearance:RefreshPresetButtons()
    local s = self:GetSettings()
    if not s then return end

    for id, button in pairs(self.presetButtons) do
        if button and button.RUIBackground then
            if id == s.preset then
                button.RUIBackground:SetVertexColor(
                    0.38, 0.29, 0.48, 1
                )
            else
                button.RUIBackground:SetVertexColor(
                    0.18, 0.18, 0.24, 1
                )
            end
        end
    end
end

function Appearance:RefreshConfigAccent()
    local config = Module("Config")
    if not config then return end

    local r, g, b = self:GetAccent()

    for id, button in pairs(
        config.navButtons or {}
    ) do
        if button.RUIBackground
            and id == config.currentPage then

            button.RUIBackground:SetVertexColor(
                r * 0.48,
                g * 0.48,
                b * 0.48,
                1
            )
        end
    end

    for id, button in pairs(
        config.barButtons or {}
    ) do
        if button.RUIBackground
            and id == config.selectedBar then

            button.RUIBackground:SetVertexColor(
                r * 0.48,
                g * 0.48,
                b * 0.48,
                1
            )
        end
    end

    self:RefreshPresetButtons()
end

function Appearance:ApplyAll()
    if Combat() then
        self.pendingApply = true
        return false
    end

    self:ApplyExistingFrames()

    local config = Module("Config")

    if config and config.Refresh then
        config:Refresh()
    end

    self:RefreshConfigAccent()
    self:ProtectRaidVisibility()

    return true
end

-- ==========================================
-- APPEARANCE SETTINGS PAGE
-- ==========================================

function Appearance:InstallConfigPage()
    local config = Module("Config")

    if not config or not config.BuildAppearance then
        return false
    end

    if config.RUIGlobalAppearanceInstalled then
        return true
    end

    local appearance = self

    config.BuildAppearance = function(ui)
        local page = ui:CreatePage(
            "appearance", 1350
        )

        ui:Heading(page, "Global Appearance", 17)

        ui:Description(
            page,
            "Choose a shared visual theme for RasfectionUI.",
            52
        )

        ui:Section(page, "THEME PRESETS", 105)

        appearance.presetButtons = {}

        for i, id in ipairs(PRESET_ORDER) do
            local preset = PRESETS[id]

            local column = (i - 1) % 2
            local row = math.floor((i - 1) / 2)

            local x = 17 + column * 246
            local y = 150 + row * 43

            local button = ui:Action(
                page,
                preset.label,
                y,
                function()
                    appearance:SetPreset(id)
                end,
                231
            )

            button:ClearAllPoints()

            button:SetPoint(
                "TOPLEFT", page, "TOPLEFT",
                x, -y
            )

            appearance.presetButtons[id] = button
        end

        ui:Section(
            page, "ACCENT COLOR (RGB)", 310
        )

        ui:Description(
            page,
            "Set exact RGB values for the interface accent.",
            353
        )

        local function Channel(
            group, index, label, y
        )
            local key = group == "accent"
                and "accentColor"
                or "backgroundColor"

            ui:Slider(
                page,
                group .. index,
                label,
                y,
                0, 255,
                function()
                    local s =
                        appearance:GetSettings()

                    if not s then return 0 end
                    return s[key][index]
                end,
                function(value)
                    appearance:SetColorChannel(
                        group, index, value
                    )
                end
            )
        end

        Channel("accent", 1, "Red", 390)
        Channel("accent", 2, "Green", 465)
        Channel("accent", 3, "Blue", 540)

        ui:Section(
            page, "BACKGROUND COLOR (RGB)", 630
        )

        Channel("background", 1, "Red", 675)
        Channel("background", 2, "Green", 750)
        Channel("background", 3, "Blue", 825)

        ui:Section(
            page, "TRANSPARENCY AND BORDERS", 910
        )

        local function Number(
            key, label, y, low, high
        )
            ui:Slider(
                page, key, label, y,
                low, high,
                function()
                    local s =
                        appearance:GetSettings()

                    return s and s[key] or low
                end,
                function(value)
                    appearance:SetOption(key, value)
                end
            )
        end

        Number(
            "backgroundOpacity",
            "Background opacity (%)",
            960, 25, 100
        )

        Number(
            "borderIntensity",
            "Metallic border visibility (%)",
            1040, 0, 100
        )

        Number(
            "accentStrength",
            "Metallic border accent (%)",
            1120, 0, 100
        )

        ui:Section(
            page, "THEME INFORMATION", 1210
        )

        ui:Description(
            page,
            "Global colors apply to supported frame backgrounds and outer borders. Raid frame visibility remains controlled by the Raid module.",
            1255
        )

        appearance:RefreshPresetButtons()

        return page
    end

    local oldRefresh = config.Refresh

    config.Refresh = function(ui, ...)
        if oldRefresh then
            oldRefresh(ui, ...)
        end

        appearance:RefreshConfigAccent()
    end

    config.RUIGlobalAppearanceInstalled = true

    return true
end

-- ==========================================
-- INITIALIZATION AND EVENTS
-- ==========================================

function Appearance:Initialize()
    if self.initialized then return end

    self:GetSettings()
    self:InstallThemeBridge()
    self:InstallConfigPage()

    local controller = CreateFrame(
        "Frame",
        "RasfectionUIAppearanceController",
        UIParent
    )

    controller:RegisterEvent("PLAYER_ENTERING_WORLD")
    controller:RegisterEvent("PLAYER_REGEN_ENABLED")
    controller:RegisterEvent("RAID_ROSTER_UPDATE")
    controller:RegisterEvent("PARTY_MEMBERS_CHANGED")

    controller:SetScript("OnEvent", function(
        self, event
    )
        if Combat() then
            Appearance.pendingApply = true
            Appearance.pendingRaidCheck = true
            return
        end

        if event == "PLAYER_ENTERING_WORLD"
            or event == "PLAYER_REGEN_ENABLED" then

            Appearance:ApplyAll()
        else
            Appearance:ProtectRaidVisibility()
        end
    end)

    -- Recovery for an older Raid module that
    -- can re-show its container after startup.
    -- This checks visibility only; it does
    -- not repeatedly restyle any frames.
    local elapsed = 0

    controller:SetScript("OnUpdate", function(
        self, delta
    )
        elapsed = elapsed + delta
        if elapsed < 1 then return end
        elapsed = 0

        if Combat() then return end

        if Appearance.pendingApply then
            Appearance:ApplyAll()
            return
        end

        if not InRaid() then
            Appearance:ProtectRaidVisibility()
        end
    end)

    self.controller = controller
    self.initialized = true

    self:ApplyAll()

    RUI:Success(
        "Global Appearance v2.4.1 initialized."
    )
end

RUI:RegisterModule(
    "GlobalAppearance",
    Appearance
)
