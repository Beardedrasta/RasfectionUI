
--[[
 RasfectionUI
 Modules/UnitFrames/Party.lua

 Version 1.8.0
 World of Warcraft 3.3.5a (12340)

 COMPACT PARTY REDESIGN

 - Includes player plus party1-party4
 - One shared metallic outer border
 - No individual unit borders
 - No portraits
 - Compact names, health and power
 - Dispellable debuff icons
 - Healing prediction via LibHealComm-4.0
 - Critical-health markers
 - Threat and range awareness
 - Secure targeting and unit menus
 - Independent shared-container movement
 - Per-character width/spacing compatibility
 - Out-of-combat automatic resizing

 Original Blizzard party frames remain enabled.
]]

local RUI = _G.RasfectionUI
if not RUI then return end

local Party = {}

Party.version = "1.8.0"
Party.initialized = false
Party.rows = {}
Party.elapsed = 0
Party.previewMode = false

local WHITE = "Interface\\Buttons\\WHITE8X8"
local FONT = "Fonts\\FRIZQT__.TTF"

local UNITS = {
    "player",
    "party1",
    "party2",
    "party3",
    "party4"
}

Party.defaults = {
    width = 234,
    rowHeight = 39,
    rowGap = 3,
    headerHeight = 25,
    padding = 8,
    x = -420,
    y = 100,
    updateInterval = 0.20
}

local DISPEL_COLORS = {
    Magic   = {0.28, 0.55, 1.00},
    Curse   = {0.72, 0.35, 0.93},
    Poison  = {0.23, 0.87, 0.35},
    Disease = {0.76, 0.62, 0.25}
}

local DISPEL_SPELLS = {
    PALADIN = {
        Magic = {4987},
        Poison = {4987, 1152},
        Disease = {4987, 1152}
    },
    PRIEST = {
        Magic = {527},
        Disease = {528, 552}
    },
    SHAMAN = {
        Curse = {51886},
        Poison = {526, 2870},
        Disease = {2870}
    },
    DRUID = {
        Curse = {2782},
        Poison = {2893, 8946}
    },
    MAGE = {
        Curse = {475}
    }
}

local function Combat()
    return InCombatLockdown
        and InCombatLockdown()
end

local function GetRaidCount()
    return GetNumRaidMembers
        and (GetNumRaidMembers() or 0)
        or 0
end

local function GetPartyCount()
    return GetNumPartyMembers
        and (GetNumPartyMembers() or 0)
        or 0
end

local function InParty()
    return GetPartyCount() > 0
        and GetRaidCount() == 0
end

local function Clamp(value, low, high)
    value = tonumber(value) or low
    return math.max(low, math.min(high, value))
end

local function Text(parent, size, align)
    local t = parent:CreateFontString(nil, "OVERLAY")
    t:SetFont(FONT, size or 10, "OUTLINE")
    t:SetJustifyH(align or "LEFT")
    t:SetTextColor(1, 1, 1, 1)
    t:SetShadowColor(0, 0, 0, 1)
    t:SetShadowOffset(1, -1)
    return t
end

local function Solid(parent, layer, r, g, b, a)
    local t = parent:CreateTexture(
        nil, layer or "ARTWORK"
    )
    t:SetTexture(WHITE)
    t:SetVertexColor(r, g, b, a or 1)
    return t
end

local function ClassColor(unit)
    local _, class = UnitClass(unit)
    local c = class and RAID_CLASS_COLORS
        and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 0.9, 0.9, 0.9
end

local function PowerColor(unit)
    local powerType, token = UnitPowerType(unit)
    local c = PowerBarColor
        and ((token and PowerBarColor[token])
          or PowerBarColor[powerType])

    if c then return c.r, c.g, c.b end
    return 0.3, 0.5, 0.9
end

local function HealthColor(percent)
    if percent <= 35 then
        return 0.82, 0.22, 0.25
    elseif percent <= 65 then
        return 0.80, 0.60, 0.22
    end
    return 0.20, 0.65, 0.36
end

-- ==========================================
-- DISPEL CAPABILITIES
-- ==========================================

function Party:RefreshDispels()
    self.canDispel = {}

    local _, class = UnitClass("player")
    local spells = DISPEL_SPELLS[class]
    if not spells then return end

    local known = {}

    if GetSpellName then
        for i = 1, 600 do
            local name = GetSpellName(
                i, BOOKTYPE_SPELL
            )
            if not name then break end
            known[name] = true
        end
    end

    for auraType, ids in pairs(spells) do
        for _, id in ipairs(ids) do
            local name = GetSpellInfo(id)

            if name and (
                known[name]
                or (IsSpellKnown and IsSpellKnown(id))
            ) then
                self.canDispel[auraType] = true
                break
            end
        end
    end
end

function Party:GetDispel(unit)
    local capabilities = self.canDispel or {}

    for i = 1, 40 do
        local name, _, texture, count,
            auraType, duration, expiration =
            UnitDebuff(unit, i)

        if not name then break end

        if auraType and capabilities[auraType] then
            return texture, count or 0,
                auraType, duration or 0,
                expiration or 0
        end
    end

    return nil
end

-- ==========================================
-- HEAL PREDICTION
-- ==========================================

function Party:GetIncomingHeal(unit)
    local guid = UnitGUID(unit)
    if not guid then return 0 end

    local lib = LibStub
        and LibStub("LibHealComm-4.0", true)

    if lib and lib.GetHealAmount then
        local flags = lib.ALL_HEALS
            or lib.CASTED_HEALS

        if flags then
            local ok, amount = pcall(
                lib.GetHealAmount,
                lib,
                guid,
                flags,
                GetTime() + 5
            )

            if ok and type(amount) == "number" then
                return math.max(0, amount)
            end
        end
    end

    if type(UnitGetIncomingHeals) == "function" then
        local ok, amount = pcall(
            UnitGetIncomingHeals, unit
        )

        if ok and type(amount) == "number" then
            return math.max(0, amount)
        end
    end

    return 0
end

-- ==========================================
-- SHARED CONTAINER
-- ==========================================

function Party:CreateContainer()
    local d = self.defaults

    local frame = CreateFrame(
        "Frame",
        "RasfectionUIPartyContainer",
        UIParent
    )

    frame:SetSize(d.width, 80)

    frame:SetPoint(
        "CENTER", UIParent, "CENTER",
        d.x, d.y
    )

    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(15)
    frame:SetClampedToScreen(true)

    local theme = RUI:GetModule("Theme")

    if theme then
        theme:Apply(frame, {
            borderSize = 16,
            insets = 4,
            backgroundColor = {
                0.035, 0.045, 0.06, 0.96
            }
        })
    end

    local title = Text(frame, 11, "LEFT")
    title:SetPoint(
        "TOPLEFT", frame, "TOPLEFT",
        13, -10
    )
    title:SetText("PARTY")
    title:SetTextColor(0.77, 0.58, 1)

    local count = Text(frame, 9, "RIGHT")
    count:SetPoint(
        "TOPRIGHT", frame, "TOPRIGHT",
        -13, -12
    )

    local line = Solid(
        frame, "ARTWORK",
        0.50, 0.34, 0.72, 0.75
    )

    line:SetHeight(1)
    line:SetPoint(
        "TOPLEFT", frame, "TOPLEFT",
        10, -d.headerHeight
    )
    line:SetPoint(
        "TOPRIGHT", frame, "TOPRIGHT",
        -10, -d.headerHeight
    )

    self.container = frame
    self.countText = count
    self.titleText = title

    return frame
end

-- ==========================================
-- PARTY BUTTONS
-- ==========================================

function Party:CreateRow(index)
    local d = self.defaults
    local unit = UNITS[index]

    local button = CreateFrame(
        "Button",
        "RasfectionUIPartyCompact" .. index,
        self.container,
        "SecureUnitButtonTemplate"
    )

    button:SetSize(
        d.width - d.padding * 2,
        d.rowHeight
    )

    button:SetPoint(
        "TOPLEFT",
        self.container,
        "TOPLEFT",
        d.padding,
        -(d.headerHeight + d.padding
            + (index - 1) *
            (d.rowHeight + d.rowGap))
    )

    button:SetFrameLevel(
        self.container:GetFrameLevel() + 2
    )

    button:RegisterForClicks("AnyUp")
    button:EnableMouse(true)

    local dropdown = CreateFrame(
        "Frame",
        "RasfectionUIPartyCompactDropdown" .. index,
        UIParent,
        "UIDropDownMenuTemplate"
    )

    UIDropDownMenu_Initialize(
        dropdown,
        function(menu)
            if not UnitExists(unit) then return end

            local menuType = "PARTY"
            if unit == "player" then
                menuType = "SELF"
            end

            if UnitPopup_ShowMenu then
                UnitPopup_ShowMenu(
                    menu, menuType,
                    unit, UnitName(unit)
                )
            end
        end,
        "MENU"
    )

    local function OpenMenu()
        if not UnitExists(unit) then return end

        ToggleDropDownMenu(
            1, nil, dropdown,
            "cursor", 0, 0
        )
    end

    if SecureUnitButton_OnLoad then
        SecureUnitButton_OnLoad(
            button, unit, OpenMenu
        )
    end

    button:SetAttribute("unit", unit)
    button:SetAttribute("*type1", "target")
    button:SetAttribute("*type2", "menu")
    button.menu = OpenMenu

    local background = Solid(
        button, "BACKGROUND",
        0.075, 0.09, 0.12, 0.85
    )
    background:SetAllPoints()

    local highlight = Solid(
        button, "HIGHLIGHT",
        0.57, 0.36, 0.78, 0.20
    )
    highlight:SetAllPoints()

    local name = Text(button, 10, "LEFT")
    name:SetPoint(
        "TOPLEFT", button, "TOPLEFT",
        5, -4
    )
    name:SetPoint(
        "TOPRIGHT", button, "TOPRIGHT",
        -53, -4
    )
    name:SetHeight(12)
    name:SetWordWrap(false)

    local percentage = Text(button, 9, "RIGHT")
    percentage:SetPoint(
        "TOPRIGHT", button, "TOPRIGHT",
        -5, -4
    )

    local healthBackground = Solid(
        button, "BACKGROUND",
        0.02, 0.03, 0.04, 1
    )
    healthBackground:SetPoint(
        "TOPLEFT", button, "TOPLEFT",
        4, -18
    )
    healthBackground:SetPoint(
        "TOPRIGHT", button, "TOPRIGHT",
        -4, -18
    )
    healthBackground:SetHeight(12)

    local health = CreateFrame(
        "StatusBar", nil, button
    )
    health:SetAllPoints(healthBackground)
    health:SetStatusBarTexture(WHITE)
    health:SetMinMaxValues(0, 1)
    health:SetValue(1)

    local powerBackground = Solid(
        button, "BACKGROUND",
        0.02, 0.03, 0.04, 1
    )
    powerBackground:SetPoint(
        "BOTTOMLEFT", button, "BOTTOMLEFT",
        4, 3
    )
    powerBackground:SetPoint(
        "BOTTOMRIGHT", button, "BOTTOMRIGHT",
        -4, 3
    )
    powerBackground:SetHeight(3)

    local power = CreateFrame(
        "StatusBar", nil, button
    )
    power:SetAllPoints(powerBackground)
    power:SetStatusBarTexture(WHITE)
    power:SetMinMaxValues(0, 1)
    power:SetValue(1)

    -- Foreground frame is above StatusBars.
    local foreground = CreateFrame(
        "Frame", nil, button
    )
    foreground:SetAllPoints(button)
    foreground:SetFrameLevel(
        button:GetFrameLevel() + 12
    )
    foreground:EnableMouse(false)

    local debuff = foreground:CreateTexture(
        nil, "ARTWORK"
    )
    debuff:SetSize(17, 17)
    debuff:SetPoint(
        "TOPRIGHT", foreground, "TOPRIGHT",
        -3, -2
    )
    debuff:SetTexCoord(
        0.08, 0.92, 0.08, 0.92
    )
    debuff:Hide()

    local debuffEdge = foreground:CreateTexture(
        nil, "OVERLAY"
    )
    debuffEdge:SetTexture(WHITE)
    debuffEdge:SetHeight(2)
    debuffEdge:SetPoint(
        "BOTTOMLEFT", debuff, "BOTTOMLEFT"
    )
    debuffEdge:SetPoint(
        "BOTTOMRIGHT", debuff, "BOTTOMRIGHT"
    )
    debuffEdge:Hide()

    local debuffCount = Text(
        foreground, 9, "RIGHT"
    )
    debuffCount:SetPoint(
        "BOTTOMRIGHT", debuff, "BOTTOMRIGHT",
        2, -2
    )

    local status = Text(
        foreground, 9, "CENTER"
    )
    status:SetPoint(
        "CENTER", health, "CENTER"
    )

    local priority = Solid(
        foreground, "OVERLAY",
        1, 0.20, 0.20, 1
    )
    priority:SetWidth(3)
    priority:SetPoint(
        "TOPLEFT", foreground, "TOPLEFT"
    )
    priority:SetPoint(
        "BOTTOMLEFT", foreground, "BOTTOMLEFT"
    )
    priority:Hide()

    local threat = Solid(
        foreground, "OVERLAY",
        0.95, 0.20, 0.20, 1
    )
    threat:SetSize(5, 5)
    threat:SetPoint(
        "BOTTOMRIGHT", foreground, "BOTTOMRIGHT",
        -3, 4
    )
    threat:Hide()

    local incoming = health:CreateTexture(
        nil, "OVERLAY"
    )
    incoming:SetTexture(WHITE)
    incoming:SetVertexColor(
        0.33, 0.93, 0.78, 0.80
    )
    incoming:SetHeight(12)
    incoming:SetWidth(1)
    incoming:SetPoint(
        "LEFT",
        health:GetStatusBarTexture(),
        "RIGHT"
    )
    incoming:Hide()

    button:SetScript("OnEnter", function(self)
        if not UnitExists(unit) then return end

        GameTooltip_SetDefaultAnchor(
            GameTooltip, self
        )
        GameTooltip:SetUnit(unit)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    button.unit = unit
    button.nameText = name
    button.percentText = percentage
    button.healthBar = health
    button.powerBar = power
    button.incoming = incoming
    button.statusText = status
    button.debuffIcon = debuff
    button.debuffEdge = debuffEdge
    button.debuffCount = debuffCount
    button.priority = priority
    button.threat = threat

    self.rows[index] = button

    -- Keep player separate because self always
    -- exists, but the container itself hides solo.
    if index == 1 then
        self.playerRow = button
    else
        RegisterUnitWatch(button)
    end

    return button
end

-- ==========================================
-- INDICATOR UPDATES
-- ==========================================

function Party:UpdateDebuff(row, unit)
    local settings =
        RUI:GetModule("Config")

    if settings and settings.GetSettings then
        local s = settings:GetSettings()

        if s and s.showDispels == false then
            row.debuffIcon:Hide()
            row.debuffEdge:Hide()
            row.debuffCount:SetText("")
            return
        end
    end

    local texture, count, kind =
        self:GetDispel(unit)

    if not texture then
        row.debuffIcon:Hide()
        row.debuffEdge:Hide()
        row.debuffCount:SetText("")
        return
    end

    row.debuffIcon:SetTexture(texture)
    row.debuffIcon:Show()

    local c = DISPEL_COLORS[kind]
        or {1, 1, 1}

    row.debuffEdge:SetVertexColor(
        c[1], c[2], c[3], 1
    )
    row.debuffEdge:Show()

    if count > 1 then
        row.debuffCount:SetText(
            tostring(count)
        )
    else
        row.debuffCount:SetText("")
    end
end

function Party:UpdateIncoming(row, unit, hp, maximum)
    if maximum <= 0 or hp >= maximum then
        row.incoming:Hide()
        return
    end

    local amount = self:GetIncomingHeal(unit)

    if amount <= 0 then
        row.incoming:Hide()
        return
    end

    amount = math.min(
        amount, maximum - hp
    )

    local width = row.healthBar:GetWidth()

    if not width or width <= 0 then
        row.incoming:Hide()
        return
    end

    row.incoming:SetWidth(
        math.max(1, width * amount / maximum)
    )
    row.incoming:Show()
end

-- ==========================================
-- UPDATE ONE PARTY UNIT
-- ==========================================

function Party:UpdateRow(index)
    local row = self.rows[index]
    if not row then return end

    local unit = row.unit

    if not UnitExists(unit) then
        row.incoming:Hide()
        row.debuffIcon:Hide()
        row.debuffEdge:Hide()
        row.debuffCount:SetText("")
        row.priority:Hide()
        row.threat:Hide()
        return
    end

    local name = UnitName(unit) or "Unknown"

    if unit == "player" then
        name = name .. " (You)"
    end

    row.nameText:SetText(name)

    local r, g, b = ClassColor(unit)
    row.nameText:SetTextColor(r, g, b)

    local hp = UnitHealth(unit) or 0
    local maximum = UnitHealthMax(unit) or 0
    local safeMaximum = math.max(1, maximum)

    hp = Clamp(hp, 0, safeMaximum)

    local percent = maximum > 0
        and math.floor(hp / maximum * 100 + 0.5)
        or 0

    row.healthBar:SetMinMaxValues(
        0, safeMaximum
    )
    row.healthBar:SetValue(hp)

    local hr, hg, hb = HealthColor(percent)
    row.healthBar:SetStatusBarColor(hr, hg, hb)

    row.percentText:SetText(percent .. "%")

    local powerType = UnitPowerType(unit) or 0
    local power = UnitPower(unit, powerType) or 0
    local maxPower = UnitPowerMax(
        unit, powerType
    ) or 0
    local safePower = math.max(1, maxPower)

    row.powerBar:SetMinMaxValues(
        0, safePower
    )
    row.powerBar:SetValue(
        Clamp(power, 0, safePower)
    )

    local pr, pg, pb = PowerColor(unit)
    row.powerBar:SetStatusBarColor(pr, pg, pb)

    local status = ""

    if not UnitIsConnected(unit) then
        status = "OFFLINE"
    elseif UnitIsDead(unit) then
        status = "DEAD"
    elseif UnitIsGhost(unit) then
        status = "GHOST"
    end

    row.statusText:SetText(status)

    if status ~= "" then
        row.percentText:SetText("")
        row.incoming:Hide()
    else
        self:UpdateIncoming(
            row, unit, hp, maximum
        )
    end

    self:UpdateDebuff(row, unit)

    local critical = 35
    local warning = 55
    local showWarnings = true
    local showThreat = true
    local showRange = true

    local config = RUI:GetModule("Config")

    if config and config.GetSettings then
        local s = config:GetSettings()

        if s then
            critical = s.criticalHealth or critical
            warning = s.warningHealth or warning
            showWarnings = s.showCritical ~= false
            showThreat = s.showThreat ~= false
            showRange = s.showRange ~= false
        end
    end

    if status == "" and showWarnings
        and percent <= warning then

        if percent <= critical then
            row.priority:SetVertexColor(
                1, 0.20, 0.20, 1
            )
        else
            row.priority:SetVertexColor(
                1, 0.68, 0.20, 1
            )
        end

        row.priority:Show()
    else
        row.priority:Hide()
    end

    local threat = showThreat
        and UnitThreatSituation
        and UnitThreatSituation(unit)

    if threat and threat >= 2 then
        row.threat:Show()
    else
        row.threat:Hide()
    end

    local inRange = true

    if showRange and unit ~= "player"
        and UnitInRange then

        if UnitInRange(unit) == false then
            inRange = false
        end
    end

    row:SetAlpha(
        inRange and 1 or 0.43
    )
end

function Party:UpdateAll()
    if not self.initialized then return end

    if self.countText then
        local count = InParty()
            and (GetPartyCount() + 1)
            or 0

        self.countText:SetText(
            count .. " MEMBERS"
        )
    end

    for i = 1, 5 do
        self:UpdateRow(i)
    end
end

-- ==========================================
-- RESIZE / VISIBILITY
-- ==========================================

function Party:RefreshLayout()
    if not self.container then return end

    if Combat() then
        self.pendingLayout = true
        return
    end

    local d = self.defaults
    local count = InParty()
        and (GetPartyCount() + 1)
        or 0

    local visualCount = count

    if visualCount == 0
        and self.previewMode then
        visualCount = 5
    end

    local height =
        d.headerHeight
        + d.padding * 2
        + visualCount * d.rowHeight
        + math.max(0, visualCount - 1)
          * d.rowGap

    self.container:SetSize(
        d.width,
        math.max(55, height)
    )

    -- These are protected secure buttons.
    -- Their visibility is managed through
    -- parent visibility and UnitWatch.
    -- Do not change the layout in combat.

    if count > 0 or self.previewMode then
        self.container:Show()
    else
        self.container:Hide()
    end

    self.pendingLayout = false
end

function Party:TogglePreview()
    if Combat() then
        RUI:Error(
            "Cannot toggle party preview in combat."
        )
        return
    end

    self.previewMode = not self.previewMode
    self:RefreshLayout()

    RUI:Print(
        "Party preview " ..
        (self.previewMode and "enabled." or "disabled.")
    )
end

-- ==========================================
-- EVENTS
-- ==========================================

function Party:OnEvent(event)
    if event == "PLAYER_ENTERING_WORLD"
        or event == "PARTY_MEMBERS_CHANGED"
        or event == "RAID_ROSTER_UPDATE"
        or event == "PLAYER_REGEN_ENABLED" then

        self:RefreshLayout()
    end

    if event == "SPELLS_CHANGED"
        or event == "LEARNED_SPELL_IN_TAB"
        or event == "PLAYER_ENTERING_WORLD" then

        self:RefreshDispels()
    end

    self:UpdateAll()
end

function Party:CreateController()
    local controller = CreateFrame(
        "Frame",
        "RasfectionUIPartyController",
        UIParent
    )

    local events = {
        "PLAYER_ENTERING_WORLD",
        "PARTY_MEMBERS_CHANGED",
        "RAID_ROSTER_UPDATE",
        "PLAYER_REGEN_ENABLED",
        "UNIT_HEALTH",
        "UNIT_MAXHEALTH",
        "UNIT_POWER",
        "UNIT_MAXPOWER",
        "UNIT_DISPLAYPOWER",
        "UNIT_AURA",
        "UNIT_FLAGS",
        "UNIT_THREAT_SITUATION_UPDATE",
        "SPELLS_CHANGED",
        "LEARNED_SPELL_IN_TAB"
    }

    for _, event in ipairs(events) do
        controller:RegisterEvent(event)
    end

    controller:SetScript("OnEvent", function(_, event)
        Party:OnEvent(event)
    end)

    controller:SetScript("OnUpdate", function(_, elapsed)
        Party.elapsed = Party.elapsed + elapsed

        if Party.elapsed >=
            Party.defaults.updateInterval then

            Party.elapsed = 0
            Party:UpdateAll()
        end
    end)

    self.controller = controller
end

-- ==========================================
-- MOVERS
-- ==========================================

function Party:RegisterMover()
    local movers = RUI:GetModule("Movers")

    if not movers then return false end

    return movers:RegisterFrame(
        "PartyContainer",
        self.container,
        {label = "Party Frames"}
    )
end

-- ==========================================
-- COMMANDS
-- ==========================================

SLASH_RUIPARTY1 = "/ruiparty"

SlashCmdList["RUIPARTY"] = function(message)
    message = string.lower(
        tostring(message or "")
    )

    if message == "preview" then
        Party:TogglePreview()

    elseif message == "status" then
        RUI:Print(
            "Party members including you: " ..
            (InParty()
                and GetPartyCount() + 1
                or 0)
        )

        RUI:Print(
            "HealComm: " ..
            ((LibStub and
              LibStub("LibHealComm-4.0", true))
                and "Available"
                or "Not available")
        )

    else
        RUI:Print("/ruiparty preview")
        RUI:Print("/ruiparty status")
    end
end

-- ==========================================
-- INITIALIZATION
-- ==========================================

function Party:Initialize()
    if self.initialized then return end

    if Combat() then
        RUI:Error(
            "Party initialization blocked in combat."
        )
        return
    end

    self:RefreshDispels()
    self:CreateContainer()

    for i = 1, 5 do
        self:CreateRow(i)
    end

    self:CreateController()
    self:RegisterMover()

    self.initialized = true

    self:RefreshLayout()
    self:UpdateAll()

    RUI:Success(
        "Compact Party Frames v1.8 initialized."
    )
end

RUI:RegisterModule("PartyFrames", Party)
