
--[[
 RasfectionUI
 Modules/UnitFrames/AuraEnhancements.lua

 Version 2.3.0
 WoW 3.3.5a / Build 12340

 ADVANCED AURA DISPLAY

 - Show All / My Debuffs / Mine Only
 - Filtered aura indices remain tooltip-correct
 - Optional countdown timers
 - Optional stack counts
 - Per-unit-frame saved settings
 - ElvUI-style global configuration integration
 - Exact numeric settings remain unchanged
 - No changes to protected unit attributes
 - No extra metallic borders

 Requires:
   CompactCore.lua v2.2
   UnitFrameOptions.lua v2.2
   GroupConfig.lua v2.1.1

 Load after UnitFrameOptions.lua.
]]

local RUI = _G.RasfectionUI
if not RUI or not RUI.CompactUnitFrames then
    return
end

local Core = RUI.CompactUnitFrames

local Auras = {
    version = "2.3.0",
    initialized = false,
    modeButtons = {},
    defaults = {
        auraFilter = "ALL",
        showAuraTimers = true,
        showAuraStacks = true
    }
}

local FONT = "Fonts\\FRIZQT__.TTF"

local FILTERS = {
    ALL = true,
    MY_DEBUFFS = true,
    MINE = true
}

local function InCombat()
    return InCombatLockdown
        and InCombatLockdown()
end

local function GetUnitOptions()
    return RUI:GetModule("UnitFrameOptions")
end

local function GetConfig()
    return RUI:GetModule("Config")
end

local function IsMine(caster)
    return caster == "player"
        or caster == "pet"
        or caster == "vehicle"
end

local function Countdown(seconds)
    if not seconds or seconds <= 0 then
        return ""
    end

    if seconds >= 3600 then
        return math.ceil(seconds / 3600) .. "h"
    elseif seconds >= 60 then
        return math.ceil(seconds / 60) .. "m"
    elseif seconds >= 10 then
        return tostring(math.ceil(seconds))
    else
        return string.format("%.1f", seconds)
    end
end

local function GetSettingsFor(id)
    local options = GetUnitOptions()

    if not options
        or not options.GetLayouts then
        return nil
    end

    local layouts = options:GetLayouts()
    if not layouts then return nil end

    local s = layouts[id]
    if not s then return nil end

    if not FILTERS[s.auraFilter] then
        s.auraFilter = "ALL"
    end

    if type(s.showAuraTimers) ~= "boolean" then
        s.showAuraTimers = true
    end

    if type(s.showAuraStacks) ~= "boolean" then
        s.showAuraStacks = true
    end

    return s
end

function Auras:GetSettings(id)
    return GetSettingsFor(id)
end

function Auras:GetSelectedSettings()
    local options = GetUnitOptions()
    if not options then return nil end

    return self:GetSettings(options.selected)
end

function Auras:RefreshSelected()
    local options = GetUnitOptions()
    if not options then return end

    local module = RUI:GetModule(options.selected)

    if module and module.UpdateAuras then
        module:UpdateAuras()
    end

    local config = GetConfig()
    if config and config.Refresh then
        config:Refresh()
    end
end

function Auras:SetOption(key, value)
    if InCombat() then
        RUI:Error(
            "Change aura settings outside combat."
        )
        self:RefreshSelected()
        return false
    end

    local settings = self:GetSelectedSettings()

    if not settings then
        return false
    end

    if key == "auraFilter" then
        if not FILTERS[value] then
            return false
        end

        settings.auraFilter = value

    elseif key == "showAuraTimers"
        or key == "showAuraStacks" then

        settings[key] = value == true

    else
        return false
    end

    self:RefreshSelected()
    return true
end

-- ==========================================
-- COUNTDOWN TEXT PER AURA ICON
-- ==========================================

local function EnsureCountdown(icon)
    if icon.RUITimer then
        return icon.RUITimer
    end

    local text = icon:CreateFontString(
        nil, "OVERLAY"
    )

    text:SetFont(
        FONT, 8, "OUTLINE"
    )

    text:SetPoint(
        "TOP", icon, "TOP", 0, -1
    )

    text:SetTextColor(1, 1, 1, 1)
    text:SetShadowColor(0, 0, 0, 1)
    text:SetShadowOffset(1, -1)
    text:SetJustifyH("CENTER")
    text:SetText("")

    icon.RUITimer = text

    return text
end

local function ClearAura(icon)
    icon.auraIndex = nil
    icon.RUIExpiration = nil

    if icon.RUITimer then
        icon.RUITimer:SetText("")
    end

    if icon.countText then
        icon.countText:SetText("")
    end

    icon:Hide()
end

local function ApplyIcon(
    icon,
    index,
    texture,
    stacks,
    duration,
    expiration,
    showTimer,
    showStacks
)
    icon.auraIndex = index
    icon.icon:SetTexture(texture)

    if showStacks and stacks and stacks > 1 then
        icon.countText:SetText(tostring(stacks))
    else
        icon.countText:SetText("")
    end

    local timer = EnsureCountdown(icon)

    if showTimer
        and duration
        and duration > 0
        and expiration
        and expiration > 0 then

        icon.RUIExpiration = expiration

        timer:SetText(
            Countdown(expiration - GetTime())
        )
    else
        icon.RUIExpiration = nil
        timer:SetText("")
    end

    icon:Show()
end

-- ==========================================
-- FILTER AURA INDEXES WITHOUT REMAPPING
-- TOOLTIP CONTENT INCORRECTLY
-- ==========================================

local function UpdateCategory(
    owner,
    icons,
    harmful,
    limit,
    filter,
    showTimers,
    showStacks
)
    local shown = 0
    local unit = owner.unit

    for index = 1, 40 do
        if shown >= limit then
            break
        end

        local name, rank, texture, stacks,
            debuffType, duration,
            expiration, caster

        if harmful then
            name, rank, texture, stacks,
            debuffType, duration,
            expiration, caster =
                UnitDebuff(unit, index)
        else
            name, rank, texture, stacks,
            debuffType, duration,
            expiration, caster =
                UnitBuff(unit, index)
        end

        if not name then
            break
        end

        local allowed = true

        if filter == "MINE" then
            allowed = IsMine(caster)

        elseif filter == "MY_DEBUFFS"
            and harmful then

            allowed = IsMine(caster)
        end

        if allowed and texture then
            shown = shown + 1

            ApplyIcon(
                icons[shown],
                index,
                texture,
                stacks,
                duration,
                expiration,
                showTimers,
                showStacks
            )
        end
    end

    for i = shown + 1, #icons do
        ClearAura(icons[i])
    end
end

-- ==========================================
-- REPLACE ONLY AURA UPDATE LOGIC
-- RETAIN EXISTING COMPACT FRAME ENGINE
-- ==========================================

function Core:UpdateAuras()
    if not self.auraHolder then
        return
    end

    local layout = self:GetSettings()
    local settings = GetSettingsFor(
        self.options.moverID
    )

    if not layout.auras
        or not UnitExists(self.unit) then

        self.auraHolder:Hide()
        return
    end

    self.auraHolder:Show()

    local filter = settings
        and settings.auraFilter or "ALL"

    local showTimers = not settings
        or settings.showAuraTimers ~= false

    local showStacks = not settings
        or settings.showAuraStacks ~= false

    UpdateCategory(
        self,
        self.buffIcons,
        false,
        layout.auraCount,
        filter,
        showTimers,
        showStacks
    )

    UpdateCategory(
        self,
        self.debuffIcons,
        true,
        layout.auraCount,
        filter,
        showTimers,
        showStacks
    )
end

-- ==========================================
-- LIVE TIMER UPDATE
-- ==========================================

function Auras:RefreshTimers()
    for _, id in ipairs({
        "PlayerFrame",
        "TargetFrame",
        "FocusFrame"
    }) do
        local module = RUI:GetModule(id)

        if module and module.auraHolder
            and module.auraHolder:IsShown() then

            local settings = self:GetSettings(id)
            local showTimers = settings
                and settings.showAuraTimers ~= false

            local lists = {
                module.buffIcons,
                module.debuffIcons
            }

            for _, icons in ipairs(lists) do
                for _, icon in ipairs(icons or {}) do
                    if icon.RUITimer then
                        if showTimers
                            and icon:IsShown()
                            and icon.RUIExpiration then

                            icon.RUITimer:SetText(
                                Countdown(
                                    icon.RUIExpiration
                                    - GetTime()
                                )
                            )
                        else
                            icon.RUITimer:SetText("")
                        end
                    end
                end
            end
        end
    end
end

-- ==========================================
-- CONFIGURATION PAGE EXTENSION
-- ==========================================

function Auras:RefreshModeButtons()
    local options = GetUnitOptions()
    if not options then return end

    local settings = self:GetSettings(
        options.selected
    )

    if not settings then return end

    for _, entry in ipairs(
        self.modeButtons
    ) do
        local active =
            settings.auraFilter == entry.value

        if entry.button
            and entry.button.RUIBackground then

            if active then
                entry.button.RUIBackground:
                    SetVertexColor(
                        0.39, 0.26, 0.54, 1
                    )
            else
                entry.button.RUIBackground:
                    SetVertexColor(
                        0.18, 0.18, 0.24, 1
                    )
            end
        end
    end
end

function Auras:InstallConfig()
    local config = GetConfig()

    if not config or not config.BuildUnits then
        return false
    end

    if config.RUIAuraConfigInstalled then
        return true
    end

    local previousBuild = config.BuildUnits

    config.BuildUnits = function(ui)
        -- Build all existing v2.2 controls first.
        local page = previousBuild(ui)

        if not page then
            return nil
        end

        -- The previous page ended at 2650.
        -- Add this section below it.
        page:SetHeight(3020)

        ui:Section(
            page,
            "ADVANCED AURA SETTINGS",
            2630
        )

        ui:Description(
            page,
            "Aura filtering is configured separately for each selected unit frame.",
            2672
        )

        local choices = {
            {"Show All", "ALL", 17},
            {"My Debuffs", "MY_DEBUFFS", 190},
            {"Mine Only", "MINE", 363}
        }

        Auras.modeButtons = {}

        for _, choice in ipairs(choices) do
            local label = choice[1]
            local mode = choice[2]
            local x = choice[3]

            local button = ui:Action(
                page,
                label,
                2725,
                function()
                    Auras:SetOption(
                        "auraFilter", mode
                    )
                end,
                158
            )

            button:ClearAllPoints()

            button:SetPoint(
                "TOPLEFT",
                page,
                "TOPLEFT",
                x, -2725
            )

            table.insert(
                Auras.modeButtons,
                {
                    button = button,
                    value = mode
                }
            )
        end

        ui:Check(
            page,
            "ruiAuraTimers",
            "Show remaining duration on auras",
            2795,
            function()
                local s =
                    Auras:GetSelectedSettings()

                return s
                    and s.showAuraTimers == true
                    or false
            end,
            function(value)
                Auras:SetOption(
                    "showAuraTimers", value
                )
            end
        )

        ui:Check(
            page,
            "ruiAuraStacks",
            "Show aura stack counts",
            2840,
            function()
                local s =
                    Auras:GetSelectedSettings()

                return s
                    and s.showAuraStacks == true
                    or false
            end,
            function(value)
                Auras:SetOption(
                    "showAuraStacks", value
                )
            end
        )

        ui:Description(
            page,
            "My Debuffs keeps all buffs visible and filters debuffs to those applied by you or your pet. Mine Only filters both rows.",
            2900
        )

        Auras:RefreshModeButtons()

        return page
    end

    -- Preserve the existing configuration
    -- refresh chain and selected-frame buttons.
    local previousRefresh = config.Refresh

    config.Refresh = function(ui, ...)
        if previousRefresh then
            previousRefresh(ui, ...)
        end

        Auras:RefreshModeButtons()
    end

    config.RUIAuraConfigInstalled = true

    return true
end

-- ==========================================
-- INITIALIZATION
-- ==========================================

function Auras:Initialize()
    if self.initialized then
        return
    end

    self:InstallConfig()

    local controller = CreateFrame(
        "Frame",
        "RasfectionUIAuraEnhancementsController",
        UIParent
    )

    local elapsed = 0

    controller:SetScript(
        "OnUpdate",
        function(_, delta)
            elapsed = elapsed + delta

            if elapsed >= 0.2 then
                elapsed = 0

                Auras:RefreshTimers()
            end
        end
    )

    self.controller = controller
    self.initialized = true

    for _, id in ipairs({
        "PlayerFrame",
        "TargetFrame",
        "FocusFrame"
    }) do
        local module = RUI:GetModule(id)

        if module and module.UpdateAuras then
            module:UpdateAuras()
        end
    end

    RUI:Success(
        "Advanced Aura System v2.3 initialized."
    )
end

RUI:RegisterModule(
    "AuraEnhancements",
    Auras
)
