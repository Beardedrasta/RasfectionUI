--[[
 RasfectionUI
 Modules/UnitFrames/Raid.lua

 Version: 1.0.0
 Client: WoW WotLK 3.3.5a / 12340

 RAID HEALING UPGRADE

 - Compact dynamic raid grid
 - Single shared metallic border
 - Secure Blizzard raid assignments
 - Class colored names
 - Health and resource bars
 - Threat indicators
 - Dispellable debuff warnings
 - Optional LibHealComm-4.0 prediction
 - Resurrection detection when supported
 - Main Tank / Main Assist markers
 - Death and offline states
 - Range fading
 - Solo layout preview
 - Persistent movement
 - Combat-safe visual updates

 Existing Raid.xml remains unchanged.
]]

local RUI = _G.RasfectionUI
if not RUI then return end

local Raid = {}

Raid.version = "1.0.0"
Raid.initialized = false

Raid.buttons = {}
Raid.previewTiles = {}
Raid.preview = false
Raid.elapsed = 0
Raid.pendingLayout = false

local WHITE = "Interface\\Buttons\\WHITE8X8"
local FONT = "Fonts\\FRIZQT__.TTF"

Raid.config = {
    unitWidth = 108,
    unitHeight = 43,

    gap = 4,
    unitsPerColumn = 5,
    maxColumns = 8,

    padding = 10,
    headerHeight = 30,
    bottomPadding = 10,

    x = 0,
    y = -310,

    updateInterval = 0.20,
    previewCount = 25,

    showThreat = true,
    showDispels = true,
    showIncomingHeals = true,
    showResurrection = true,
    showRoles = true,
    showRange = true
}

-- ==========================================
-- BASIC HELPERS
-- ==========================================

local function InCombat()
    return InCombatLockdown
        and InCombatLockdown()
end

local function RaidCount()
    return GetNumRaidMembers
        and (GetNumRaidMembers() or 0)
        or 0
end

local function Clamp(value, low, high)
    value = tonumber(value) or low

    if value < low then return low end
    if value > high then return high end

    return value
end

local function Text(parent, size, justify)
    local t = parent:CreateFontString(
        nil,
        "OVERLAY"
    )

    t:SetFont(FONT, size or 10, "OUTLINE")
    t:SetTextColor(1, 1, 1, 1)
    t:SetJustifyH(justify or "LEFT")
    t:SetShadowColor(0, 0, 0, 1)
    t:SetShadowOffset(1, -1)

    return t
end

local function Solid(parent, layer, r, g, b, a)
    local t = parent:CreateTexture(
        nil,
        layer or "ARTWORK"
    )

    t:SetTexture(WHITE)
    t:SetVertexColor(
        r or 1,
        g or 1,
        b or 1,
        a or 1
    )

    return t
end

local function ClassColor(unit)
    local _, class = UnitClass(unit)

    if class and RAID_CLASS_COLORS
        and RAID_CLASS_COLORS[class] then
        local c = RAID_CLASS_COLORS[class]

        return c.r, c.g, c.b
    end

    return 0.85, 0.85, 0.88
end

local function HealthColor(percent)
    if percent > 65 then
        return 0.20, 0.65, 0.36
    elseif percent > 35 then
        return 0.82, 0.62, 0.23
    end

    return 0.86, 0.23, 0.25
end

local function PowerColor(unit)
    local power, token = UnitPowerType(unit)
    local color

    if PowerBarColor then
        color = (token and PowerBarColor[token])
            or PowerBarColor[power]
    end

    if color then
        return color.r, color.g, color.b
    end

    if power == 1 then
        return 0.85, 0.18, 0.18
    elseif power == 2 then
        return 0.92, 0.48, 0.18
    elseif power == 3 then
        return 0.95, 0.85, 0.15
    elseif power == 6 then
        return 0.00, 0.75, 0.85
    end

    return 0.20, 0.48, 0.90
end

-- ==========================================
-- LIBHEALCOMM SUPPORT
-- ==========================================

function Raid:GetHealComm()
    if self.healComm then
        return self.healComm
    end

    if not LibStub then
        return nil
    end

    local lib = LibStub(
        "LibHealComm-4.0",
        true
    )

    if lib and lib.GetHealAmount then
        self.healComm = lib
    end

    return self.healComm
end

function Raid:GetIncomingHealing(unit)
    if not self.config.showIncomingHeals then
        return 0
    end

    local guid = UnitGUID(unit)

    if not guid then
        return 0
    end

    -- Optional library integration.
    local lib = self:GetHealComm()

    if lib then
        local flags = lib.CASTED_HEALS
            or lib.ALL_HEALS

        if flags then
            local success, amount = pcall(
                lib.GetHealAmount,
                lib,
                guid,
                flags,
                GetTime() + 5
            )

            if success and
                type(amount) == "number" then
                return math.max(0, amount)
            end
        end
    end

    -- This is not part of native 3.3.5a,
    -- but check for custom server clients.
    if type(UnitGetIncomingHeals)
        == "function" then
        local success, amount = pcall(
            UnitGetIncomingHeals,
            unit
        )

        if success and
            type(amount) == "number" then
            return math.max(0, amount)
        end
    end

    return 0
end

-- ==========================================
-- PLAYER DISPEL CAPABILITIES
-- ==========================================

local DISPEL_SPELLS = {
    PALADIN = {
        Magic = { 4987 },
        Poison = { 4987, 1152 },
        Disease = { 4987, 1152 }
    },

    PRIEST = {
        Magic = { 527 },
        Disease = { 528, 552 }
    },

    SHAMAN = {
        Poison = { 526, 2870 },
        Disease = { 2870 },
        Curse = { 51886 }
    },

    DRUID = {
        Curse = { 2782 },
        Poison = { 2893, 8946 }
    },

    MAGE = {
        Curse = { 475 }
    }
}

function Raid:RefreshDispelCapabilities()
    local _, class = UnitClass("player")
    local mapping = DISPEL_SPELLS[class]

    self.dispelCapabilities = {}

    if not mapping then
        return
    end

    -- Build a known-spell list from the
    -- character's actual spellbook.

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

    for debuffType, spellIDs in pairs(mapping) do
        for _, spellID in ipairs(spellIDs) do
            local spellName = GetSpellInfo(spellID)

            if spellName and known[spellName] then
                self.dispelCapabilities[debuffType] = true
                break
            end
        end
    end
end

function Raid:GetDispellableDebuff(unit)
    if not self.config.showDispels then
        return nil
    end

    local capable = self.dispelCapabilities

    if not capable then
        return nil
    end

    for i = 1, 40 do
        local name, _, _, debuffType =
            UnitDebuff(unit, i)

        if not name then
            break
        end

        if debuffType and capable[debuffType] then
            return debuffType
        end
    end

    return nil
end

-- ==========================================
-- RAID ROLES
-- ==========================================

function Raid:GetRole(unit)
    if not self.config.showRoles then
        return nil
    end

    local index = tonumber(
        string.match(unit or "", "^raid(%d+)$")
    )

    if not index then
        return nil
    end

    local _, _, _, _, _, _, _, _, _, role =
        GetRaidRosterInfo(index)

    if role == "MAINTANK" then
        return "T"
    elseif role == "MAINASSIST" then
        return "A"
    end

    return nil
end

-- ==========================================
-- RESURRECTION STATUS
-- ==========================================

function Raid:HasIncomingResurrection(unit)
    if not self.config.showResurrection then
        return false
    end

    if type(UnitHasIncomingResurrection)
        ~= "function" then
        return false
    end

    local success, result = pcall(
        UnitHasIncomingResurrection,
        unit
    )

    return success and result == true
end

-- ==========================================
-- DYNAMIC LAYOUT
-- ==========================================

function Raid:GetGridDimensions(count)
    local c = self.config

    count = math.floor(
        Clamp(count or 0, 0, 40)
    )

    if count < 1 then
        return 1, 1
    end

    local columns = math.ceil(
        count / c.unitsPerColumn
    )

    columns = math.min(
        columns,
        c.maxColumns
    )

    local rows = math.min(
        count,
        c.unitsPerColumn
    )

    return columns, rows
end

function Raid:GetContainerDimensions(count)
    local c = self.config
    local columns, rows =
        self:GetGridDimensions(count)

    local width = c.padding * 2
        + columns * c.unitWidth
        + (columns - 1) * c.gap

    local height = c.headerHeight
        + c.padding
        + rows * c.unitHeight
        + (rows - 1) * c.gap
        + c.bottomPadding

    return width, height, columns, rows
end

-- ==========================================
-- UNIT DROPDOWN
-- ==========================================

function Raid:CreateDropdown()
    local dropdown = CreateFrame(
        "Frame",
        "RasfectionUIRaidDropDown",
        UIParent,
        "UIDropDownMenuTemplate"
    )

    UIDropDownMenu_Initialize(
        dropdown,
        function(menu)
            local unit = menu.unit

            if not unit or not UnitExists(unit) then
                return
            end

            local menuType = "RAID_PLAYER"

            if UnitIsUnit(unit, "player") then
                menuType = "SELF"
            end

            if UnitPopup_ShowMenu then
                UnitPopup_ShowMenu(
                    menu,
                    menuType,
                    unit,
                    UnitName(unit)
                )
            end
        end,
        "MENU"
    )

    self.dropdown = dropdown
end

function Raid:OpenMenu(button)
    if not button or not self.dropdown then
        return
    end

    local unit = button:GetAttribute("unit")

    if not unit or not UnitExists(unit) then
        return
    end

    self.dropdown.unit = unit

    ToggleDropDownMenu(
        1,
        nil,
        self.dropdown,
        "cursor",
        0,
        0
    )
end

-- ==========================================
-- THREAT OUTLINE
-- ==========================================

function Raid:CreateThreatOutline(button)
    local edges = {}

    local function Edge(horizontal)
        local t = Solid(
            button,
            "OVERLAY",
            0.95, 0.20, 0.20, 1
        )

        if horizontal then
            t:SetHeight(2)
        else
            t:SetWidth(2)
        end

        t:Hide()

        table.insert(edges, t)

        return t
    end

    local top = Edge(true)
    top:SetPoint("TOPLEFT", button)
    top:SetPoint("TOPRIGHT", button)

    local bottom = Edge(true)
    bottom:SetPoint("BOTTOMLEFT", button)
    bottom:SetPoint("BOTTOMRIGHT", button)

    local left = Edge(false)
    left:SetPoint("TOPLEFT", button)
    left:SetPoint("BOTTOMLEFT", button)

    local right = Edge(false)
    right:SetPoint("TOPRIGHT", button)
    right:SetPoint("BOTTOMRIGHT", button)

    button.RUIThreatEdges = edges
end

function Raid:SetThreat(button, active)
    if not button.RUIThreatEdges then
        return
    end

    for _, texture in ipairs(
        button.RUIThreatEdges
    ) do
        if active then
            texture:Show()
        else
            texture:Hide()
        end
    end
end

-- ==========================================
-- SECURE RAID TILE CREATION
-- ==========================================

function Raid:BuildButton(button)
    if button.RUIBuilt then
        return
    end

    button.RUIBuilt = true

    local c = self.config

    button:SetSize(
        c.unitWidth,
        c.unitHeight
    )

    button:RegisterForClicks("AnyUp")
    button:EnableMouse(true)

    button:SetAttribute("*type1", "target")
    button:SetAttribute("*type2", "menu")

    button.menu = function(self)
        Raid:OpenMenu(self)
    end

    -- No individual metallic border.

    local background = Solid(
        button,
        "BACKGROUND",
        0.075, 0.09, 0.12, 0.96
    )

    background:SetAllPoints()

    local highlight = Solid(
        button,
        "HIGHLIGHT",
        0.60, 0.38, 0.90, 0.22
    )

    highlight:SetAllPoints()

    -- Name

    local name = Text(button, 10, "LEFT")

    name:SetPoint(
        "TOPLEFT",
        button,
        "TOPLEFT",
        5, -4
    )

    name:SetPoint(
        "TOPRIGHT",
        button,
        "TOPRIGHT",
        -21, -4
    )

    name:SetHeight(13)
    name:SetWordWrap(false)

    -- Health

    local healthBG = Solid(
        button,
        "BACKGROUND",
        0.02, 0.025, 0.035, 1
    )

    healthBG:SetPoint(
        "TOPLEFT",
        button,
        "TOPLEFT",
        4, -20
    )

    healthBG:SetPoint(
        "TOPRIGHT",
        button,
        "TOPRIGHT",
        -4, -20
    )

    healthBG:SetHeight(13)

    local health = CreateFrame(
        "StatusBar",
        nil,
        button
    )

    health:SetAllPoints(healthBG)
    health:SetStatusBarTexture(WHITE)
    health:SetMinMaxValues(0, 100)
    health:SetValue(100)

    -- Incoming healing overlay.
    -- The overlay begins at the end of
    -- the current health fill.

    local incoming = Solid(
        health,
        "OVERLAY",
        0.40, 0.95, 0.85, 0.72
    )

    incoming:SetHeight(13)
    incoming:SetWidth(1)

    incoming:SetPoint(
        "LEFT",
        health:GetStatusBarTexture(),
        "RIGHT",
        0, 0
    )

    incoming:Hide()

    -- Health percentage

    local percent = Text(
        button,
        9,
        "CENTER"
    )

    percent:SetPoint(
        "CENTER",
        health,
        "CENTER"
    )

    percent:SetWidth(70)

    -- Power

    local powerBG = Solid(
        button,
        "BACKGROUND",
        0.02, 0.025, 0.035, 1
    )

    powerBG:SetPoint(
        "BOTTOMLEFT",
        button,
        "BOTTOMLEFT",
        4, 4
    )

    powerBG:SetPoint(
        "BOTTOMRIGHT",
        button,
        "BOTTOMRIGHT",
        -4, 4
    )

    powerBG:SetHeight(3)

    local power = CreateFrame(
        "StatusBar",
        nil,
        button
    )

    power:SetAllPoints(powerBG)
    power:SetStatusBarTexture(WHITE)
    power:SetMinMaxValues(0, 100)
    power:SetValue(100)

    -- Status

    local status = Text(
        button,
        9,
        "CENTER"
    )

    status:SetPoint(
        "CENTER",
        health,
        "CENTER"
    )

    status:SetWidth(96)
    status:SetTextColor(1, 0.85, 0.85)

    -- Main Tank / Assist marker

    local role = Text(
        button,
        10,
        "RIGHT"
    )

    role:SetPoint(
        "TOPRIGHT",
        button,
        "TOPRIGHT",
        -4, -3
    )

    role:SetTextColor(1, 0.80, 0.25)

    -- Dispel indicator

    local dispel = Text(
        button,
        8,
        "RIGHT"
    )

    dispel:SetPoint(
        "BOTTOMRIGHT",
        button,
        "BOTTOMRIGHT",
        -5, 8
    )

    dispel:SetWidth(52)

    -- Threat

    self:CreateThreatOutline(button)

    button.RUIName = name
    button.RUIHealth = health
    button.RUIPercent = percent
    button.RUIPower = power
    button.RUIStatus = status
    button.RUIRole = role
    button.RUIDispel = dispel
    button.RUIIncoming = incoming

    button:SetScript(
        "OnEnter",
        function(self)
            local unit = self:GetAttribute("unit")

            if unit and UnitExists(unit) then
                GameTooltip_SetDefaultAnchor(
                    GameTooltip,
                    self
                )

                GameTooltip:SetUnit(unit)
                GameTooltip:Show()
            end
        end
    )

    button:SetScript(
        "OnLeave",
        function()
            GameTooltip:Hide()
        end
    )

    table.insert(self.buttons, button)
end

-- Raid.xml calls this for each unit button.
function RasfectionUI_RaidButton_OnLoad(button)
    Raid:BuildButton(button)
end

-- ==========================================
-- INCOMING HEAL DISPLAY
-- ==========================================

function Raid:UpdateIncomingHealing(
    button,
    unit,
    current,
    maximum
)
    local overlay = button.RUIIncoming

    if not overlay then
        return
    end

    local missing = math.max(
        0,
        maximum - current
    )

    if missing <= 0 or maximum <= 0 then
        overlay:Hide()
        return
    end

    local incoming = self:GetIncomingHealing(unit)

    incoming = math.min(
        missing,
        math.max(0, incoming)
    )

    if incoming <= 0 then
        overlay:Hide()
        return
    end

    local barWidth = button.RUIHealth:GetWidth()

    if not barWidth or barWidth <= 0 then
        overlay:Hide()
        return
    end

    local width = barWidth * incoming / maximum

    if width < 1 then
        overlay:Hide()
        return
    end

    overlay:SetWidth(width)
    overlay:Show()
end

-- ==========================================
-- DISPEL INDICATOR
-- ==========================================

function Raid:UpdateDispel(button, unit)
    local debuffType =
        self:GetDispellableDebuff(unit)

    local marker = button.RUIDispel

    if not debuffType then
        marker:SetText("")
        return
    end

    if debuffType == "Magic" then
        marker:SetText("MAG")
        marker:SetTextColor(
            0.35, 0.65, 1.00
        )
    elseif debuffType == "Curse" then
        marker:SetText("CUR")
        marker:SetTextColor(
            0.75, 0.45, 0.95
        )
    elseif debuffType == "Poison" then
        marker:SetText("PSN")
        marker:SetTextColor(
            0.35, 0.95, 0.40
        )
    elseif debuffType == "Disease" then
        marker:SetText("DIS")
        marker:SetTextColor(
            0.70, 0.60, 0.35
        )
    end
end

-- ==========================================
-- UPDATE INDIVIDUAL RAID MEMBER
-- ==========================================

function Raid:UpdateButton(button)
    if not button or not button.RUIBuilt then
        return
    end

    local unit = button:GetAttribute("unit")

    if not unit or not UnitExists(unit) then
        button.RUIIncoming:Hide()
        button.RUIDispel:SetText("")
        self:SetThreat(button, false)
        return
    end

    -- NAME

    local name = UnitName(unit) or "Unknown"

    button.RUIName:SetText(name)

    local r, g, b = ClassColor(unit)

    button.RUIName:SetTextColor(r, g, b)

    -- HEALTH

    local hp = UnitHealth(unit) or 0
    local maxHP = UnitHealthMax(unit) or 0

    local safeHP = math.max(1, maxHP)

    hp = Clamp(hp, 0, safeHP)

    local percent = 0

    if maxHP > 0 then
        percent = math.floor(
            hp / maxHP * 100 + 0.5
        )
    end

    button.RUIHealth:SetMinMaxValues(
        0,
        safeHP
    )

    button.RUIHealth:SetValue(hp)

    local hr, hg, hb =
        HealthColor(percent)

    button.RUIHealth:SetStatusBarColor(
        hr, hg, hb
    )

    button.RUIPercent:SetText(
        percent .. "%"
    )

    -- POWER

    local powerType = UnitPowerType(unit) or 0

    local power = UnitPower(
        unit,
        powerType
    ) or 0

    local maxPower = UnitPowerMax(
        unit,
        powerType
    ) or 0

    local safePower = math.max(1, maxPower)

    button.RUIPower:SetMinMaxValues(
        0,
        safePower
    )

    button.RUIPower:SetValue(
        Clamp(power, 0, safePower)
    )

    local pr, pg, pb =
        PowerColor(unit)

    button.RUIPower:SetStatusBarColor(
        pr, pg, pb
    )

    -- DEATH / RESURRECTION

    local status = ""

    if not UnitIsConnected(unit) then
        status = "OFFLINE"
    elseif UnitIsDead(unit)
        or UnitIsGhost(unit) then
        if self:HasIncomingResurrection(unit) then
            status = "RES"
        elseif UnitIsGhost(unit) then
            status = "GHOST"
        else
            status = "DEAD"
        end
    end

    button.RUIStatus:SetText(status)

    if status ~= "" then
        button.RUIPercent:SetText("")
    end

    -- RAID ROLE

    local role = self:GetRole(unit)

    button.RUIRole:SetText(
        role or ""
    )

    -- THREAT

    local threatActive = false

    if self.config.showThreat
        and UnitThreatSituation then
        local situation =
            UnitThreatSituation(unit)

        -- 2: insecurely tanking
        -- 3: securely tanking
        if situation and situation >= 2 then
            threatActive = true
        end
    end

    self:SetThreat(
        button,
        threatActive
    )

    -- DEBUFFS

    self:UpdateDispel(
        button,
        unit
    )

    -- INCOMING HEALING

    if status == "" then
        self:UpdateIncomingHealing(
            button,
            unit,
            hp,
            maxHP
        )
    else
        button.RUIIncoming:Hide()
    end

    -- RANGE

    local inRange = true

    if self.config.showRange
        and UnitInRange then
        local result = UnitInRange(unit)

        if result == false then
            inRange = false
        end
    end

    if inRange then
        button:SetAlpha(1)
    else
        button:SetAlpha(0.42)
    end
end

-- ==========================================
-- MAIN RAID CONTAINER
-- ==========================================

function Raid:CreateContainer()
    local c = self.config

    local width, height =
        self:GetContainerDimensions(1)

    local frame = CreateFrame(
        "Frame",
        "RasfectionUIRaidContainer",
        UIParent
    )

    frame:SetSize(width, height)

    frame:SetPoint(
        "CENTER",
        UIParent,
        "CENTER",
        c.x,
        c.y
    )

    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(15)
    frame:SetClampedToScreen(true)

    local theme =
        RUI:GetModule("Theme")

    if theme then
        theme:Apply(frame, {
            borderSize = 16,
            insets = 4,

            backgroundColor = {
                0.035,
                0.045,
                0.06,
                0.96
            }
        })
    end

    local title = Text(frame, 12, "LEFT")

    title:SetPoint(
        "TOPLEFT",
        frame,
        "TOPLEFT",
        15, -13
    )

    title:SetText("RASFECTION RAID")

    title:SetTextColor(
        0.76, 0.56, 1
    )

    local count = Text(
        frame,
        10,
        "RIGHT"
    )

    count:SetPoint(
        "TOPRIGHT",
        frame,
        "TOPRIGHT",
        -15, -14
    )

    local line = Solid(
        frame,
        "ARTWORK",
        0.55, 0.39, 0.78, 0.75
    )

    line:SetHeight(1)

    line:SetPoint(
        "TOPLEFT",
        frame,
        "TOPLEFT",
        12,
        -c.headerHeight
    )

    line:SetPoint(
        "TOPRIGHT",
        frame,
        "TOPRIGHT",
        -12,
        -c.headerHeight
    )

    self.container = frame
    self.titleText = title
    self.countText = count
    self.headerLine = line
end

-- ==========================================
-- SECURE RAID HEADER
-- ==========================================

function Raid:CreateHeader()
    local c = self.config

    local header = CreateFrame(
        "Frame",
        "RasfectionUIRaidHeader",
        self.container,
        "SecureGroupHeaderTemplate"
    )

    header:SetPoint(
        "TOPLEFT",
        self.container,
        "TOPLEFT",
        c.padding,
        -(c.headerHeight + c.padding)
    )

    header:SetAttribute(
        "template",
        "RasfectionUIRaidUnitTemplate"
    )

    header:SetAttribute(
        "templateType",
        "Button"
    )

    header:SetAttribute("showRaid", true)
    header:SetAttribute("showParty", false)
    header:SetAttribute("showSolo", false)
    header:SetAttribute("showPlayer", false)

    header:SetAttribute(
        "groupFilter",
        "1,2,3,4,5,6,7,8"
    )

    header:SetAttribute(
        "groupBy",
        "GROUP"
    )

    header:SetAttribute(
        "groupingOrder",
        "1,2,3,4,5,6,7,8"
    )

    header:SetAttribute(
        "sortMethod",
        "INDEX"
    )

    header:SetAttribute(
        "sortDir",
        "ASC"
    )

    -- Vertical members, horizontal columns.
    header:SetAttribute("point", "TOP")
    header:SetAttribute("xOffset", 0)
    header:SetAttribute("yOffset", -c.gap)

    header:SetAttribute(
        "unitsPerColumn",
        c.unitsPerColumn
    )

    header:SetAttribute(
        "maxColumns",
        c.maxColumns
    )

    header:SetAttribute(
        "columnAnchorPoint",
        "LEFT"
    )

    header:SetAttribute(
        "columnSpacing",
        c.gap
    )

    header:SetAttribute(
        "minWidth",
        c.unitWidth
    )

    header:SetAttribute(
        "minHeight",
        c.unitHeight
    )

    self.header = header

    header:Show()
end

-- ==========================================
-- DECORATION VISIBILITY
-- ==========================================

function Raid:ShowDecorations(show)
    if not self.container then return end

    if show then
        self.container:SetBackdropColor(
            0.035, 0.045, 0.06, 0.96
        )

        self.container:SetBackdropBorderColor(
            1, 1, 1, 1
        )

        self.titleText:Show()
        self.countText:Show()
        self.headerLine:Show()
    else
        self.container:SetBackdropColor(
            0, 0, 0, 0
        )

        self.container:SetBackdropBorderColor(
            0, 0, 0, 0
        )

        self.titleText:Hide()
        self.countText:Hide()
        self.headerLine:Hide()
    end
end

-- ==========================================
-- DYNAMIC CONTAINER RESIZING
-- ==========================================

function Raid:ResizeContainer()
    if not self.container then
        return false
    end

    if InCombat() then
        self.pendingLayout = true
        return false
    end

    local count = RaidCount()

    if count == 0 and self.preview then
        count = self.config.previewCount
    end

    local width, height, columns, rows =
        self:GetContainerDimensions(count)

    self.container:SetSize(width, height)

    self.columns = columns
    self.rows = rows

    self.pendingLayout = false

    return true
end

function Raid:RefreshPresentation()
    if InCombat() then
        self.pendingLayout = true
        return
    end

    local count = RaidCount()

    if count > 0 then
        self.preview = false
    end

    self:ResizeContainer()

    self:ShowDecorations(
        count > 0 or self.preview
    )

    self:RefreshPreview()
end

-- ==========================================
-- SOLO RAID PREVIEW
-- ==========================================

function Raid:CreatePreview()
    local c = self.config

    for i = 1, c.previewCount do
        local tile = CreateFrame(
            "Frame",
            nil,
            self.container
        )

        tile:SetSize(
            c.unitWidth,
            c.unitHeight
        )

        local col = math.floor(
            (i - 1) / c.unitsPerColumn
        )

        local row =
            (i - 1) % c.unitsPerColumn

        tile:SetPoint(
            "TOPLEFT",
            self.container,
            "TOPLEFT",
            c.padding
            + col *
            (c.unitWidth + c.gap),
            -(c.headerHeight + c.padding
                + row *
                (c.unitHeight + c.gap))
        )

        local bg = Solid(
            tile,
            "BACKGROUND",
            0.075, 0.09, 0.12, 0.95
        )

        bg:SetAllPoints()

        local name = Text(
            tile,
            10,
            "LEFT"
        )

        name:SetPoint(
            "TOPLEFT",
            tile,
            "TOPLEFT",
            5, -4
        )

        name:SetText(
            "Member " .. i
        )

        local hp = Solid(
            tile,
            "ARTWORK",
            0.20, 0.60, 0.35, 1
        )

        hp:SetPoint(
            "TOPLEFT",
            tile,
            "TOPLEFT",
            4, -20
        )

        hp:SetSize(
            c.unitWidth - 8,
            13
        )

        local power = Solid(
            tile,
            "ARTWORK",
            0.24, 0.48, 0.84, 1
        )

        power:SetPoint(
            "BOTTOMLEFT",
            tile,
            "BOTTOMLEFT",
            4, 4
        )

        power:SetSize(
            c.unitWidth - 8,
            3
        )

        tile:Hide()

        table.insert(
            self.previewTiles,
            tile
        )
    end
end

function Raid:RefreshPreview()
    local show =
        self.preview and RaidCount() == 0

    for _, tile in ipairs(self.previewTiles) do
        if show then
            tile:Show()
        else
            tile:Hide()
        end
    end
end

function Raid:TogglePreview()
    if InCombat() then
        RUI:Error(
            "Cannot toggle raid preview in combat."
        )
        return
    end

    if RaidCount() > 0 then
        RUI:Print(
            "Leave your raid to preview."
        )
        return
    end

    self.preview = not self.preview

    self:RefreshPresentation()

    RUI:Success(
        "Raid preview " ..
        (self.preview and "enabled." or "disabled.")
    )
end

-- ==========================================
-- UPDATE ALL
-- ==========================================

function Raid:UpdateAll()
    if not self.initialized then
        return
    end

    for _, button in ipairs(self.buttons) do
        self:UpdateButton(button)
    end

    if self.countText then
        self.countText:SetText(
            RaidCount() .. " / 40"
        )
    end
end

-- ==========================================
-- EVENTS
-- ==========================================

function Raid:OnEvent(event)
    if event == "PLAYER_REGEN_ENABLED" then
        if self.pendingLayout then
            self:RefreshPresentation()
        end
    elseif event == "PLAYER_ENTERING_WORLD"
        or event == "RAID_ROSTER_UPDATE"
        or event == "PARTY_MEMBERS_CHANGED" then
        self:RefreshPresentation()
    elseif event == "SPELLS_CHANGED"
        or event == "LEARNED_SPELL_IN_TAB" then
        self:RefreshDispelCapabilities()
    end

    self:UpdateAll()
end

function Raid:CreateController()
    local controller = CreateFrame(
        "Frame",
        "RasfectionUIRaidController",
        UIParent
    )

    local events = {
        "PLAYER_ENTERING_WORLD",
        "RAID_ROSTER_UPDATE",
        "PARTY_MEMBERS_CHANGED",
        "PLAYER_REGEN_ENABLED",

        "UNIT_HEALTH",
        "UNIT_MAXHEALTH",
        "UNIT_POWER",
        "UNIT_MAXPOWER",
        "UNIT_DISPLAYPOWER",
        "UNIT_NAME_UPDATE",
        "UNIT_FLAGS",
        "UNIT_AURA",

        "UNIT_THREAT_SITUATION_UPDATE",
        "UNIT_THREAT_LIST_UPDATE",

        "INCOMING_RESURRECT_CHANGED",

        "SPELLS_CHANGED",
        "LEARNED_SPELL_IN_TAB"
    }

    for _, event in ipairs(events) do
        controller:RegisterEvent(event)
    end

    controller:SetScript(
        "OnEvent",
        function(_, event)
            Raid:OnEvent(event)
        end
    )

    controller:SetScript(
        "OnUpdate",
        function(_, elapsed)
            Raid.elapsed =
                Raid.elapsed + elapsed

            if Raid.elapsed >=
                Raid.config.updateInterval then
                Raid.elapsed = 0
                Raid:UpdateAll()
            end
        end
    )

    self.controller = controller
end

-- ==========================================
-- MOVERS
-- ==========================================

function Raid:RegisterMover()
    local movers = RUI:GetModule("Movers")

    if not movers then
        return false
    end

    return movers:RegisterFrame(
        "RaidContainer",
        self.container,
        {
            label = "Raid Frames"
        }
    )
end

-- ==========================================
-- COMMANDS
-- ==========================================

SLASH_RUIRAID1 = "/ruiraid"

SlashCmdList["RUIRAID"] = function(message)
    message = string.lower(
        tostring(message or "")
    )

    if message == "preview" then
        Raid:TogglePreview()
    elseif message == "status" then
        local count = RaidCount()

        local columns, rows =
            Raid:GetGridDimensions(count)

        RUI:Print(
            "Raid members: " .. count
        )

        RUI:Print(
            "Grid: " ..
            columns .. " columns, " ..
            rows .. " rows"
        )

        RUI:Print(
            "Secure buttons: " ..
            #Raid.buttons
        )

        RUI:Print(
            "HealComm: " ..
            (Raid:GetHealComm()
                and "Available"
                or "Not available")
        )
    else
        RUI:Print(
            "/ruiraid preview - Solo preview"
        )

        RUI:Print(
            "/ruiraid status - Raid diagnostics"
        )
    end
end

-- ==========================================
-- INITIALIZATION
-- ==========================================

function Raid:Initialize()
    if self.initialized then
        return
    end

    if InCombat() then
        RUI:Error(
            "Raid initialization blocked by combat."
        )
        return
    end

    self:CreateDropdown()
    self:CreateContainer()
    self:CreateHeader()
    self:CreatePreview()
    self:CreateController()
    self:RegisterMover()

    self:RefreshDispelCapabilities()

    self.initialized = true

    self:RefreshPresentation()
    self:UpdateAll()

    RUI:Success(
        "Raid Healing UI v1.0 initialized."
    )
end

RUI:RegisterModule(
    "RaidFrames",
    Raid
)
