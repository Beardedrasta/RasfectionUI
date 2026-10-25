
--[[
 RasfectionUI - Core/AccentIntegration.lua
 Version 2.5.0
 WotLK 3.3.5a / Build 12340

 UNIFIED THEME ACCENT SYSTEM

 Features:
 - Sidebar selected-category accent
 - Action-bar selected-tab accent
 - Unit-frame selector accent
 - Unit-frame color-mode button accent
 - Aura-filter selector accent
 - Theme preset selection accent
 - Slider thumb colors
 - Numeric input focus borders
 - Automatic recoloring after preset changes
 - Automatic recoloring after settings refresh
 - No saved-variable migration needed

 Safety:
 - Never shows or hides gameplay frames
 - Never changes protected attributes
 - Never modifies frame coordinates or scale
 - Never changes health or power-bar colors
 - Never replaces click handlers
 - Never modifies raid visibility
 - No polling loops
]]

local RUI = _G.RasfectionUI
if not RUI then return end

local Accent = {}

Accent.version = "2.5.0"
Accent.initialized = false
Accent.installed = false
Accent.applying = false

local function Module(name)
    return RUI:GetModule(name)
end

local function Clamp(v)
    v = tonumber(v) or 0
    return math.max(0, math.min(1, v))
end

local function GetAccent()
    local appearance = Module("GlobalAppearance")

    if appearance and appearance.GetAccent then
        local r, g, b = appearance:GetAccent()
        return Clamp(r), Clamp(g), Clamp(b)
    end

    return 0.65, 0.42, 0.91
end

local function SelectedColor(r, g, b)
    return
        math.max(0.12, r * 0.53),
        math.max(0.12, g * 0.53),
        math.max(0.16, b * 0.53)
end

local function ColorButton(button, selected, r, g, b)
    if not button or not button.RUIBackground then
        return
    end

    if selected then
        local sr, sg, sb = SelectedColor(r, g, b)

        button.RUIBackground:SetVertexColor(
            sr, sg, sb, 1
        )
    else
        button.RUIBackground:SetVertexColor(
            0.18, 0.18, 0.24, 1
        )
    end
end

local function SetThumbColor(slider, r, g, b)
    if not slider or not slider.GetThumbTexture then
        return
    end

    local thumb = slider:GetThumbTexture()

    if thumb then
        thumb:SetVertexColor(r, g, b, 1)
    end
end

-- ==========================================
-- SIDEBAR
-- ==========================================

function Accent:StyleNavigation(r, g, b)
    local config = Module("Config")
    if not config then return end

    for id, button in pairs(config.navButtons or {}) do
        ColorButton(
            button,
            id == config.currentPage,
            r, g, b
        )
    end
end

-- ==========================================
-- ACTION BAR SELECTION
-- ==========================================

function Accent:StyleActionBarSelectors(r, g, b)
    local config = Module("Config")
    if not config then return end

    for id, button in pairs(config.barButtons or {}) do
        ColorButton(
            button,
            id == config.selectedBar,
            r, g, b
        )
    end
end

-- ==========================================
-- UNIT FRAME SELECTION
-- ==========================================

function Accent:StyleUnitFrameSelectors(r, g, b)
    local options = Module("UnitFrameOptions")
    if not options then return end

    for id, button in pairs(
        options.selectorButtons or {}
    ) do
        ColorButton(
            button,
            id == options.selected,
            r, g, b
        )
    end

    local settings = options.GetSelectedSettings
        and options:GetSelectedSettings()

    if not settings then return end

    for _, entry in ipairs(
        options.modeButtons or {}
    ) do
        ColorButton(
            entry.button,
            settings[entry.key] == entry.value,
            r, g, b
        )
    end
end

-- ==========================================
-- AURA FILTER SELECTION
-- ==========================================

function Accent:StyleAuraFilters(r, g, b)
    local auras = Module("AuraEnhancements")
    local options = Module("UnitFrameOptions")

    if not auras or not options then return end

    local settings = auras.GetSettings
        and auras:GetSettings(options.selected)

    if not settings then return end

    for _, entry in ipairs(
        auras.modeButtons or {}
    ) do
        ColorButton(
            entry.button,
            settings.auraFilter == entry.value,
            r, g, b
        )
    end
end

-- ==========================================
-- APPEARANCE PRESETS
-- ==========================================

function Accent:StylePresets(r, g, b)
    local appearance = Module("GlobalAppearance")
    if not appearance then return end

    local settings = appearance.GetSettings
        and appearance:GetSettings()

    if not settings then return end

    for id, button in pairs(
        appearance.presetButtons or {}
    ) do
        ColorButton(
            button,
            id == settings.preset,
            r, g, b
        )
    end
end

-- ==========================================
-- SLIDER HANDLES / NUMERIC INPUTS
-- ==========================================

function Accent:StyleNumericControls(r, g, b)
    local config = Module("Config")
    if not config then return end

    -- Restyle controls on all constructed pages.
    -- Does not change their numeric values.
    for _, page in pairs(config.pages or {}) do
        for _, entry in pairs(
            page.RUIControls or {}
        ) do
            if entry.kind == "slider" then
                SetThumbColor(
                    entry.control, r, g, b
                )

                local edit = entry.input

                if edit and edit.SetBackdropBorderColor then
                    if edit:HasFocus() then
                        edit:SetBackdropBorderColor(
                            r, g, b, 1
                        )
                    else
                        edit:SetBackdropBorderColor(
                            0.27, 0.29, 0.37, 1
                        )
                    end
                end
            end
        end
    end
end

-- ==========================================
-- APPLY ALL CONTROL ACCENTS
-- ==========================================

function Accent:Apply()
    if self.applying then return end
    self.applying = true

    local r, g, b = GetAccent()

    self:StyleNavigation(r, g, b)
    self:StyleActionBarSelectors(r, g, b)
    self:StyleUnitFrameSelectors(r, g, b)
    self:StyleAuraFilters(r, g, b)
    self:StylePresets(r, g, b)
    self:StyleNumericControls(r, g, b)

    self.applying = false
end

-- ==========================================
-- SETTINGS REFRESH INTEGRATION
-- ==========================================

function Accent:InstallRefreshBridge()
    if self.installed then return true end

    local config = Module("Config")
    local appearance = Module("GlobalAppearance")

    if not config or not config.Refresh
        or not appearance or not appearance.ApplyAll then
        return false
    end

    local accent = self

    -- Other modules already wrap Config.Refresh.
    -- Preserve their complete callback chain.
    local previousRefresh = config.Refresh

    config.Refresh = function(ui, ...)
        local result = previousRefresh(ui, ...)

        accent:Apply()
        return result
    end

    -- Recolor immediately when the user changes
    -- an appearance preset or custom RGB value.
    -- Preserve the existing raid visibility fix
    -- inside GlobalAppearance.ApplyAll.
    local previousApplyAll = appearance.ApplyAll

    appearance.ApplyAll = function(selfAppearance, ...)
        local result = previousApplyAll(
            selfAppearance, ...
        )

        accent:Apply()
        return result
    end

    self.installed = true
    return true
end

-- ==========================================
-- INITIALIZATION
-- ==========================================

function Accent:Initialize()
    if self.initialized then return end

    self:InstallRefreshBridge()
    self.initialized = true

    self:Apply()

    RUI:Success(
        "Unified Theme Accents v2.5 initialized."
    )
end

RUI:RegisterModule("AccentIntegration", Accent)
