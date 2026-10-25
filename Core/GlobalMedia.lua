
--[[
 RasfectionUI - Core/GlobalMedia.lua
 Version 2.6.0
 World of Warcraft 3.3.5a / 12340

 GLOBAL FONT & STATUS BAR STYLING

 Features:
  - Three client font selections
  - Flat and Blizzard status-bar textures
  - Shared text outline preference
  - Optional aura font synchronization
  - Per-character persistence
  - Live out-of-combat application
  - Reapplies styling after CompactCore layout
  - Appearance page integration
  - Existing exact-number settings unaffected

 This module does not:
  - Change raid/party visibility
  - Change unit-frame dimensions or positions
  - Change health/power colors
  - Replace secure unit buttons
  - Alter action bar icons
]]

local RUI = _G.RasfectionUI
if not RUI then return end

local Media = {}

Media.version = "2.6.0"
Media.initialized = false
Media.pageInstalled = false
Media.layoutWrapped = false
Media.refreshWrapped = false

local FONTS = {
    standard = {
        label = "Standard",
        path = "Fonts\\FRIZQT__.TTF"
    },
    narrow = {
        label = "Arial Narrow",
        path = "Fonts\\ARIALN.TTF"
    },
    morpheus = {
        label = "Morpheus",
        path = "Fonts\\MORPHEUS.TTF"
    }
}

local TEXTURES = {
    flat = {
        label = "Flat",
        path = "Interface\\Buttons\\WHITE8X8"
    },
    blizzard = {
        label = "Blizzard",
        path = "Interface\\TargetingFrame\\UI-StatusBar"
    }
}

local FONT_ORDER = {
    "standard", "narrow", "morpheus"
}

local TEXTURE_ORDER = {
    "flat", "blizzard"
}

local FRAME_MODULES = {
    "PlayerFrame",
    "TargetFrame",
    "FocusFrame",
    "PetFrame",
    "TargetTargetFrame",
    "FocusTargetFrame"
}

local function Module(name)
    return RUI:GetModule(name)
end

local function Combat()
    return InCombatLockdown
        and InCombatLockdown()
end

local function Notify(message)
    if RUI.Print then
        RUI:Print(message)
    end
end

-- ==========================================
-- SAVED SETTINGS
-- ==========================================

function Media:GetSettings()
    local database = Module("Database")

    if not database or not database.GetProfile then
        return nil
    end

    local profile = database:GetProfile()

    if not profile then return nil end

    if type(profile.settings) ~= "table" then
        profile.settings = {}
    end

    if type(profile.settings.globalMedia) ~= "table" then
        profile.settings.globalMedia = {}
    end

    local s = profile.settings.globalMedia

    if not FONTS[s.font] then
        s.font = "standard"
    end

    if not TEXTURES[s.barTexture] then
        s.barTexture = "flat"
    end

    if type(s.outline) ~= "boolean" then
        s.outline = true
    end

    if type(s.auraFont) ~= "boolean" then
        s.auraFont = true
    end

    return s
end

function Media:GetFontPath()
    local settings = self:GetSettings()

    if not settings then
        return FONTS.standard.path
    end

    return FONTS[settings.font].path
end

function Media:GetTexturePath()
    local settings = self:GetSettings()

    if not settings then
        return TEXTURES.flat.path
    end

    return TEXTURES[settings.barTexture].path
end

-- ==========================================
-- APPLY TO FONTSTRINGS
-- ==========================================

function Media:ApplyFont(fontString, size)
    if not fontString or not fontString.SetFont then
        return
    end

    local settings = self:GetSettings()
    if not settings then return end

    local path = self:GetFontPath()
    local flags = settings.outline
        and "OUTLINE" or ""

    -- Fall back to the client's original font
    -- if a particular font path is unavailable.
    local ok = fontString:SetFont(
        path, size, flags
    )

    if not ok then
        fontString:SetFont(
            FONTS.standard.path,
            size,
            flags
        )
    end
end

-- ==========================================
-- APPLY TO A COMPACT UNIT FRAME
-- ==========================================

function Media:ApplyUnitFrame(unitModule)
    if Combat() then
        self.pendingApply = true
        return false
    end

    if not unitModule or not unitModule.frame
        or not unitModule.GetSettings then
        return false
    end

    local layout = unitModule:GetSettings()

    self:ApplyFont(
        unitModule.nameText,
        layout.nameFont or 12
    )

    self:ApplyFont(
        unitModule.levelText,
        layout.levelFont or 10
    )

    self:ApplyFont(
        unitModule.healthText,
        layout.valueFont or 9
    )

    self:ApplyFont(
        unitModule.powerText,
        layout.valueFont or 9
    )

    self:ApplyFont(
        unitModule.statusText,
        layout.valueFont or 9
    )

    local texture = self:GetTexturePath()

    if unitModule.healthBar then
        unitModule.healthBar:SetStatusBarTexture(
            texture
        )
    end

    if unitModule.powerBar then
        unitModule.powerBar:SetStatusBarTexture(
            texture
        )
    end

    local settings = self:GetSettings()

    -- Aura enhancements creates RUITimer
    -- dynamically. Existing icons are
    -- restyled when the module is applied.
    for _, list in ipairs({
        unitModule.buffIcons or {},
        unitModule.debuffIcons or {}
    }) do
        for _, icon in ipairs(list) do
            if icon.countText then
                if settings.auraFont then
                    self:ApplyFont(
                        icon.countText, 9
                    )
                else
                    icon.countText:SetFont(
                        FONTS.standard.path,
                        9, "OUTLINE"
                    )
                end
            end

            if icon.RUITimer then
                if settings.auraFont then
                    self:ApplyFont(
                        icon.RUITimer, 8
                    )
                else
                    icon.RUITimer:SetFont(
                        FONTS.standard.path,
                        8, "OUTLINE"
                    )
                end
            end
        end
    end

    -- Reapply dynamic class/resource colors
    -- after changing status-bar textures.
    if unitModule.Update then
        unitModule:Update()
    end

    return true
end

function Media:ApplyAll()
    if Combat() then
        self.pendingApply = true
        return false
    end

    for _, id in ipairs(FRAME_MODULES) do
        local module = Module(id)
        if module then
            self:ApplyUnitFrame(module)
        end
    end

    self.pendingApply = false
    self:RefreshSelection()
    return true
end

-- ==========================================
-- COMPACT CORE INTEGRATION
-- ==========================================

function Media:InstallLayoutBridge()
    if self.layoutWrapped then return true end

    local core = RUI.CompactUnitFrames

    if not core or not core.ApplyLayout then
        return false
    end

    local previousLayout = core.ApplyLayout
    local media = self

    core.ApplyLayout = function(unitModule, ...)
        local result = previousLayout(
            unitModule, ...
        )

        -- Do not apply cosmetics if layout
        -- was denied by combat lockdown.
        if result ~= false and not Combat()
            and unitModule.initialized then

            media:ApplyUnitFrame(unitModule)
        end

        return result
    end

    self.layoutWrapped = true

    return true
end

-- ==========================================
-- SETTINGS CALLBACKS
-- ==========================================

function Media:SetOption(key, value)
    if Combat() then
        Notify(
            "Global media cannot change during combat."
        )
        return false
    end

    local s = self:GetSettings()
    if not s then return false end

    if key == "font" then
        if not FONTS[value] then return false end
        s.font = value

    elseif key == "barTexture" then
        if not TEXTURES[value] then return false end
        s.barTexture = value

    elseif key == "outline" then
        s.outline = value == true

    elseif key == "auraFont" then
        s.auraFont = value == true

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
-- SELECTED BUTTON COLORS
-- ==========================================

function Media:RefreshSelection()
    local s = self:GetSettings()

    if not s then return end

    local appearance = Module("GlobalAppearance")

    local r, g, b = 0.65, 0.42, 0.91

    if appearance and appearance.GetAccent then
        r, g, b = appearance:GetAccent()
    end

    for _, entry in ipairs(
        self.mediaButtons or {}
    ) do
        local button = entry.button

        if button and button.RUIBackground then
            if s[entry.key] == entry.value then
                button.RUIBackground:SetVertexColor(
                    math.max(0.12, r * 0.53),
                    math.max(0.12, g * 0.53),
                    math.max(0.16, b * 0.53),
                    1
                )
            else
                button.RUIBackground:SetVertexColor(
                    0.18, 0.18, 0.24, 1
                )
            end
        end
    end
end

-- ==========================================
-- APPEARANCE PAGE EXTENSION
-- ==========================================

function Media:InstallConfigPage()
    if self.pageInstalled then return true end

    local config = Module("Config")

    if not config or not config.BuildAppearance then
        return false
    end

    local previousBuild = config.BuildAppearance

    config.BuildAppearance = function(ui)
        local page = previousBuild(ui)

        if not page then return nil end

        -- Global Appearance v2.4 uses
        -- approximately the first 1350 pixels.
        -- Continue below existing settings.
        page:SetHeight(1950)

        ui:Section(
            page, "GLOBAL FONT FAMILY", 1390
        )

        ui:Description(
            page,
            "Change the typeface used by compact unit frames while keeping each frame's individual font sizes.",
            1435
        )

        Media.mediaButtons = {}

        local function Choice(
            label, key, value, x, y, width
        )
            local button = ui:Action(
                page, label, y,
                function()
                    Media:SetOption(key, value)
                end,
                width
            )

            button:ClearAllPoints()
            button:SetPoint(
                "TOPLEFT",
                page, "TOPLEFT",
                x, -y
            )

            table.insert(Media.mediaButtons, {
                button = button,
                key = key,
                value = value
            })
        end

        local fontPositions = {
            {17, 150},
            {190, 150},
            {363, 150}
        }

        for i, id in ipairs(FONT_ORDER) do
            Choice(
                FONTS[id].label,
                "font", id,
                fontPositions[i][1],
                1490,
                fontPositions[i][2]
            )
        end

        ui:Section(
            page, "STATUS BAR TEXTURE", 1570
        )

        ui:Description(
            page,
            "The texture changes the bar surface, not the health or resource colors.",
            1610
        )

        for i, id in ipairs(TEXTURE_ORDER) do
            Choice(
                TEXTURES[id].label,
                "barTexture", id,
                17 + (i - 1) * 246,
                1660,
                230
            )
        end

        ui:Section(
            page, "TYPOGRAPHY OPTIONS", 1735
        )

        ui:Check(
            page,
            "globalFontOutline",
            "Outline text for readability",
            1780,
            function()
                local s = Media:GetSettings()
                return s and s.outline == true
                    or false
            end,
            function(value)
                Media:SetOption("outline", value)
            end
        )

        ui:Check(
            page,
            "globalAuraFont",
            "Use selected font on aura timers and stacks",
            1825,
            function()
                local s = Media:GetSettings()
                return s and s.auraFont == true
                    or false
            end,
            function(value)
                Media:SetOption("auraFont", value)
            end
        )

        Media:RefreshSelection()

        return page
    end

    local previousRefresh = config.Refresh

    config.Refresh = function(ui, ...)
        local result = previousRefresh(
            ui, ...
        )
        Media:RefreshSelection()
        return result
    end

    self.pageInstalled = true
    return true
end

-- ==========================================
-- INITIALIZATION
-- ==========================================

function Media:Initialize()
    if self.initialized then return end

    self:GetSettings()
    self:InstallLayoutBridge()
    self:InstallConfigPage()

    local controller = CreateFrame(
        "Frame",
        "RasfectionUIGlobalMediaController",
        UIParent
    )

    controller:RegisterEvent(
        "PLAYER_ENTERING_WORLD"
    )
    controller:RegisterEvent(
        "PLAYER_REGEN_ENABLED"
    )

    controller:SetScript("OnEvent", function()
        if not Combat() then
            Media:ApplyAll()
        else
            Media.pendingApply = true
        end
    end)

    self.controller = controller
    self.initialized = true

    self:ApplyAll()

    if RUI.Success then
        RUI:Success(
            "Global Fonts & Textures v2.6 initialized."
        )
    end
end

RUI:RegisterModule("GlobalMedia", Media)
