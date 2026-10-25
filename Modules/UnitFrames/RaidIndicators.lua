--[[
    RasfectionUI
    Modules/UnitFrames/RaidIndicators.lua

    Version: 1.1.1
    Client: WoW WotLK 3.3.5a (12340)

    RAID INDICATORS - LAYERING FIX

    FIXED:
      - Debuff icons no longer render behind bars
      - Dedicated foreground indicator frame
      - Correct frame-level hierarchy
      - Debuff icons remain visible over health
      - Stack counts and timers stay visible
      - Critical health warnings remain visible

    PRESERVED:
      - Minimalist borderless raid tiles
      - Automatic dispel spell detection
      - Actual debuff spell icons
      - Debuff type coloring
      - Health priority warnings
      - Combat-safe visual updates
      - Existing slash commands
      - Existing raid secure buttons

    No changes to Raid.lua are required.
]]

local RUI = _G.RasfectionUI
if not RUI then return end

local Indicators = {}

Indicators.version = "1.1.1"
Indicators.initialized = false
Indicators.tracked = {}
Indicators.elapsed = 0

local WHITE = "Interface\\Buttons\\WHITE8X8"
local FONT = "Fonts\\FRIZQT__.TTF"

-- ==========================================
-- CONFIGURATION
-- ==========================================

Indicators.config = {
    enabled = true,

    showDispels = true,
    showCritical = true,
    showStacks = true,
    showDuration = true,

    criticalHealth = 35,
    warningHealth = 55,

    iconSize = 18,
    updateInterval = 0.15,

    foregroundOffset = 20
}

-- ==========================================
-- DISPEL COLORS
-- ==========================================

local DISPEL_COLORS = {
    Magic   = { 0.25, 0.60, 1.00 },
    Curse   = { 0.72, 0.42, 0.94 },
    Poison  = { 0.25, 0.85, 0.35 },
    Disease = { 0.73, 0.60, 0.32 }
}

-- ==========================================
-- DISPEL SPELL DETECTION
-- ==========================================

local DISPEL_SPELLS = {
    PALADIN = {
        Magic   = { 4987 },
        Poison  = { 4987, 1152 },
        Disease = { 4987, 1152 }
    },

    PRIEST = {
        Magic   = { 527 },
        Disease = { 528, 552 }
    },

    SHAMAN = {
        Curse   = { 51886 },
        Poison  = { 526, 2870 },
        Disease = { 2870 }
    },

    DRUID = {
        Curse  = { 2782 },
        Poison = { 2893, 8946 }
    },

    MAGE = {
        Curse = { 475 }
    }
}

-- ==========================================
-- HELPERS
-- ==========================================

local function InCombat()
    return InCombatLockdown
        and InCombatLockdown()
end

local function RaidModule()
    return RUI:GetModule("RaidFrames")
end

local function CreateText(parent, size)
    local text = parent:CreateFontString(
        nil,
        "OVERLAY"
    )

    text:SetFont(
        FONT,
        size,
        "OUTLINE"
    )

    text:SetTextColor(1, 1, 1, 1)
    text:SetShadowColor(0, 0, 0, 1)
    text:SetShadowOffset(1, -1)

    return text
end

-- ==========================================
-- SPELLBOOK CAPABILITIES
-- ==========================================

function Indicators:RefreshCapabilities()
    local _, class = UnitClass("player")
    local spells = DISPEL_SPELLS[class]

    self.capabilities = {}

    if not spells then
        return
    end

    local known = {}

    if GetSpellName then
        for i = 1, 600 do
            local name = GetSpellName(
                i,
                BOOKTYPE_SPELL
            )

            if not name then
                break
            end

            known[name] = true
        end
    end

    for debuffType, ids in pairs(spells) do
        for _, id in ipairs(ids) do
            local name = GetSpellInfo(id)

            if name and known[name] then
                self.capabilities[debuffType] = true
                break
            end
        end
    end
end

-- ==========================================
-- FIND DISPELLABLE DEBUFF
-- ==========================================

function Indicators:FindDebuff(unit)
    if not self.config.showDispels then
        return nil
    end

    if not self.capabilities then
        return nil
    end

    for i = 1, 40 do
        local name, rank, texture, count,
        debuffType, duration, expiration =
            UnitDebuff(unit, i)

        if not name then
            break
        end

        if debuffType
            and self.capabilities[debuffType] then
            return {
                name = name,
                texture = texture,
                count = count or 0,
                debuffType = debuffType,
                duration = duration or 0,
                expiration = expiration or 0
            }
        end
    end

    return nil
end

-- ==========================================
-- CREATE FOREGROUND INDICATOR LAYER
-- ==========================================

function Indicators:CreateForeground(button)
    -- Important:
    --
    -- A texture's OVERLAY draw layer only
    -- controls ordering within its frame.
    --
    -- Our Health and Power StatusBars are
    -- child frames, so an OVERLAY texture
    -- placed directly on the raid button
    -- may still render underneath them.
    --
    -- This dedicated frame sits at a higher
    -- frame level than the StatusBars.

    local layer = CreateFrame(
        "Frame",
        nil,
        button
    )

    layer:SetAllPoints(button)

    layer:SetFrameStrata(
        button:GetFrameStrata()
    )

    layer:SetFrameLevel(
        button:GetFrameLevel() +
        self.config.foregroundOffset
    )

    -- Indicators must never intercept
    -- unit targeting or healing clicks.
    layer:EnableMouse(false)

    return layer
end

-- ==========================================
-- ATTACH INDICATORS
-- ==========================================

function Indicators:Attach(button)
    if not button or not button.RUIBuilt then
        return false
    end

    if self.tracked[button] then
        return true
    end

    -- All new regions are created outside
    -- combat to avoid protected UI issues.
    if InCombat() then
        return false
    end

    local visual = {}

    local layer = self:CreateForeground(button)

    visual.layer = layer

    -- ======================================
    -- CRITICAL HEALTH STRIP
    -- ======================================

    local urgent = layer:CreateTexture(
        nil,
        "ARTWORK"
    )

    urgent:SetTexture(WHITE)
    urgent:SetWidth(3)

    urgent:SetPoint(
        "TOPLEFT",
        layer,
        "TOPLEFT",
        0,
        0
    )

    urgent:SetPoint(
        "BOTTOMLEFT",
        layer,
        "BOTTOMLEFT",
        0,
        0
    )

    urgent:SetVertexColor(
        1, 0.18, 0.18, 1
    )

    urgent:Hide()

    visual.urgent = urgent

    -- ======================================
    -- CRITICAL HEALTH EXCLAMATION
    -- ======================================

    local warning = CreateText(
        layer,
        11
    )

    warning:SetPoint(
        "TOPRIGHT",
        layer,
        "TOPRIGHT",
        -5,
        -3
    )

    warning:SetText("!")

    warning:SetTextColor(
        1, 0.30, 0.30, 1
    )

    warning:Hide()

    visual.warning = warning

    -- ======================================
    -- DEBUFF ICON BACKGROUND
    -- ======================================

    local iconHolder = CreateFrame(
        "Frame",
        nil,
        layer
    )

    iconHolder:SetSize(
        self.config.iconSize,
        self.config.iconSize
    )

    -- Upper-right area of the unit tile.
    -- The icon sits ABOVE the health/power
    -- bars in the frame hierarchy.
    iconHolder:SetPoint(
        "TOPRIGHT",
        layer,
        "TOPRIGHT",
        -5,
        -4
    )

    iconHolder:EnableMouse(false)

    local iconBackground = iconHolder:CreateTexture(
        nil,
        "BACKGROUND"
    )

    iconBackground:SetTexture(WHITE)
    iconBackground:SetAllPoints(iconHolder)

    iconBackground:SetVertexColor(
        0.015, 0.020, 0.030, 1
    )

    -- ======================================
    -- ACTUAL DEBUFF ICON
    -- ======================================

    local icon = iconHolder:CreateTexture(
        nil,
        "ARTWORK"
    )

    icon:SetAllPoints(iconHolder)

    icon:SetTexCoord(
        0.08, 0.92,
        0.08, 0.92
    )

    -- ======================================
    -- DISPEL TYPE INDICATOR
    -- ======================================

    local typeMarker = iconHolder:CreateTexture(
        nil,
        "OVERLAY"
    )

    typeMarker:SetTexture(WHITE)
    typeMarker:SetHeight(2)

    typeMarker:SetPoint(
        "BOTTOMLEFT",
        iconHolder,
        "BOTTOMLEFT"
    )

    typeMarker:SetPoint(
        "BOTTOMRIGHT",
        iconHolder,
        "BOTTOMRIGHT"
    )

    typeMarker:SetVertexColor(
        1, 1, 1, 1
    )

    -- ======================================
    -- STACK COUNT
    -- ======================================

    local stacks = CreateText(
        iconHolder,
        9
    )

    stacks:SetPoint(
        "BOTTOMRIGHT",
        iconHolder,
        "BOTTOMRIGHT",
        -1,
        1
    )

    stacks:SetJustifyH("RIGHT")

    -- ======================================
    -- REMAINING DURATION
    -- ======================================

    local duration = CreateText(
        iconHolder,
        8
    )

    duration:SetPoint(
        "TOP",
        iconHolder,
        "BOTTOM",
        0,
        -1
    )

    duration:SetJustifyH("CENTER")

    duration:SetTextColor(
        1, 1, 1, 1
    )

    -- ======================================
    -- STORE VISUALS
    -- ======================================

    visual.iconHolder = iconHolder
    visual.icon = icon
    visual.typeMarker = typeMarker
    visual.stacks = stacks
    visual.duration = duration

    iconHolder:Hide()
    duration:Hide()
    stacks:Hide()

    self.tracked[button] = visual

    -- Prevent the previous text-based
    -- dispel marker from duplicating the
    -- new spell icon.
    if button.RUIDispel then
        button.RUIDispel:SetAlpha(0)
    end

    return true
end

-- ==========================================
-- HIDE INDICATORS
-- ==========================================

function Indicators:HideIndicators(visual)
    visual.urgent:Hide()
    visual.warning:Hide()
    visual.iconHolder:Hide()
    visual.duration:Hide()
    visual.stacks:Hide()
end

-- ==========================================
-- HEALTH PRIORITY
-- ==========================================

function Indicators:UpdatePriority(
    button,
    visual,
    unit
)
    if not self.config.showCritical then
        visual.urgent:Hide()
        visual.warning:Hide()
        return
    end

    if UnitIsDeadOrGhost(unit)
        or not UnitIsConnected(unit) then
        visual.urgent:Hide()
        visual.warning:Hide()
        return
    end

    local current = UnitHealth(unit) or 0
    local maximum = UnitHealthMax(unit) or 0

    local percent = 100

    if maximum > 0 then
        percent = current / maximum * 100
    end

    if percent <= self.config.criticalHealth then
        visual.urgent:SetVertexColor(
            1, 0.18, 0.18, 1
        )

        visual.urgent:Show()

        visual.warning:Show()
    elseif percent <= self.config.warningHealth then
        visual.urgent:SetVertexColor(
            1, 0.68, 0.20, 0.95
        )

        visual.urgent:Show()

        visual.warning:Hide()
    else
        visual.urgent:Hide()
        visual.warning:Hide()
    end
end

-- ==========================================
-- DEBUFF ICON UPDATE
-- ==========================================

function Indicators:UpdateDebuff(
    button,
    visual,
    unit
)
    local debuff = self:FindDebuff(unit)

    if not debuff or not debuff.texture then
        visual.iconHolder:Hide()
        visual.stacks:Hide()
        visual.duration:Hide()
        return
    end

    local color =
        DISPEL_COLORS[debuff.debuffType]
        or { 1, 1, 1 }

    visual.icon:SetTexture(
        debuff.texture
    )

    visual.typeMarker:SetVertexColor(
        color[1],
        color[2],
        color[3],
        1
    )

    visual.iconHolder:Show()

    -- Stack count.
    if self.config.showStacks
        and debuff.count > 1 then
        visual.stacks:SetText(
            tostring(debuff.count)
        )

        visual.stacks:Show()
    else
        visual.stacks:Hide()
    end

    -- Remaining time.
    if self.config.showDuration
        and debuff.expiration > 0 then
        local remaining = math.max(
            0,
            debuff.expiration - GetTime()
        )

        if remaining > 0 then
            local text

            if remaining >= 60 then
                text = math.floor(
                    remaining / 60
                ) .. "m"
            else
                text = tostring(
                    math.ceil(remaining)
                )
            end

            visual.duration:SetText(text)
            visual.duration:Show()
        else
            visual.duration:Hide()
        end
    else
        visual.duration:Hide()
    end
end

-- ==========================================
-- UPDATE INDIVIDUAL UNIT
-- ==========================================

function Indicators:UpdateButton(button)
    local visual = self.tracked[button]

    if not visual then
        return
    end

    local unit = button:GetAttribute("unit")

    if not self.config.enabled
        or not unit
        or not UnitExists(unit) then
        self:HideIndicators(visual)
        return
    end

    self:UpdatePriority(
        button,
        visual,
        unit
    )

    self:UpdateDebuff(
        button,
        visual,
        unit
    )
end

-- ==========================================
-- REFRESH ALL RAID INDICATORS
-- ==========================================

function Indicators:Refresh()
    local raid = RaidModule()

    if not raid or not raid.buttons then
        return
    end

    for _, button in ipairs(raid.buttons) do
        if button and button.RUIBuilt then
            if not self.tracked[button] then
                self:Attach(button)
            end

            self:UpdateButton(button)
        end
    end
end

-- ==========================================
-- STATUS
-- ==========================================

function Indicators:Status()
    local count = 0

    for _ in pairs(self.tracked) do
        count = count + 1
    end

    RUI:Print(
        "Raid Indicators v" ..
        self.version
    )

    RUI:Print(
        "Attached raid units: " ..
        count
    )

    RUI:Print(
        "Foreground layer: Enabled"
    )

    RUI:Print(
        "Indicators: " ..
        (self.config.enabled
            and "Enabled"
            or "Disabled")
    )

    local available = {}

    for typeName, enabled in pairs(
        self.capabilities or {}
    ) do
        if enabled then
            table.insert(
                available,
                typeName
            )
        end
    end

    table.sort(available)

    RUI:Print(
        "Dispels: " ..
        (#available > 0
            and table.concat(
                available,
                ", "
            )
            or "None detected")
    )
end

-- ==========================================
-- COMMANDS
-- ==========================================

SLASH_RUIALERTS1 = "/ruialerts"

SlashCmdList["RUIALERTS"] = function(message)
    message = string.lower(
        tostring(message or ""):match(
            "^%s*(.-)%s*$"
        )
    )

    if message == "status" then
        Indicators:Status()
    elseif message == "toggle" then
        Indicators.config.enabled =
            not Indicators.config.enabled

        Indicators:Refresh()

        RUI:Print(
            "Raid indicators " ..
            (Indicators.config.enabled
                and "enabled."
                or "disabled.")
        )
    elseif message == "refresh" then
        Indicators:RefreshCapabilities()
        Indicators:Refresh()

        RUI:Success(
            "Raid indicators refreshed."
        )
    else
        RUI:Print(
            "/ruialerts status - Diagnostics"
        )

        RUI:Print(
            "/ruialerts toggle - Toggle alerts"
        )

        RUI:Print(
            "/ruialerts refresh - Refresh detection"
        )
    end
end

-- ==========================================
-- INITIALIZATION
-- ==========================================

function Indicators:Initialize()
    if self.initialized then
        return
    end

    self.initialized = true

    self:RefreshCapabilities()

    local controller = CreateFrame(
        "Frame",
        "RasfectionUIRaidIndicatorsController",
        UIParent
    )

    local events = {
        "PLAYER_ENTERING_WORLD",
        "SPELLS_CHANGED",
        "LEARNED_SPELL_IN_TAB",
        "PLAYER_REGEN_ENABLED",
        "RAID_ROSTER_UPDATE",
        "UNIT_AURA"
    }

    for _, event in ipairs(events) do
        controller:RegisterEvent(event)
    end

    controller:SetScript(
        "OnEvent",
        function(_, event)
            if event == "SPELLS_CHANGED"
                or event == "LEARNED_SPELL_IN_TAB"
                or event == "PLAYER_ENTERING_WORLD" then
                Indicators:RefreshCapabilities()
            end

            Indicators:Refresh()
        end
    )

    controller:SetScript(
        "OnUpdate",
        function(_, elapsed)
            Indicators.elapsed =
                Indicators.elapsed + elapsed

            if Indicators.elapsed >=
                Indicators.config.updateInterval then
                Indicators.elapsed = 0

                Indicators:Refresh()
            end
        end
    )

    self.controller = controller

    self:Refresh()

    RUI:Success(
        "Raid Indicators v1.1.1 loaded."
    )
end

-- ==========================================
-- MODULE REGISTRATION
-- ==========================================

RUI:RegisterModule(
    "RaidIndicators",
    Indicators
)
