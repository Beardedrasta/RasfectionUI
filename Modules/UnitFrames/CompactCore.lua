
--[[
 RasfectionUI - CompactCore.lua
 Version 2.2.0 | WoW 3.3.5a / 12340

 Shared compact unit-frame engine.
 One outer border only.

 NEW:
  Health color modes: health / class / custom
  Power color modes: resource / custom
  Custom RGB color support
  Configurable name, value and level font sizes
  Configurable unit-frame scale
  Power bar visibility
  Aura placement above or below
  Aura icon gap and count
  Aura tooltip and stack counts

 PRESERVED:
  Existing unit/mover names
  Existing frame dimensions
  Existing portraits and portrait toggles
  Buff/debuff mouseover tooltips
  Secure clicks and unit watch
  Saved settings and existing controls
]]

local RUI = _G.RasfectionUI
if not RUI then return end

local Core = {}
RUI.CompactUnitFrames = Core

local WHITE = "Interface\\Buttons\\WHITE8X8"
local FONT = "Fonts\\FRIZQT__.TTF"

local function Combat()
    return InCombatLockdown
       and InCombatLockdown()
end

local function Clamp(v, lo, hi, fallback)
    v = tonumber(v)
    if not v or v ~= v
       or v == math.huge or v == -math.huge then
        v = fallback or lo
    end
    return math.max(lo, math.min(hi, v))
end

local function Integer(v, lo, hi, fallback)
    return math.floor(Clamp(v, lo, hi, fallback) + 0.5)
end

local function Text(parent, size, align)
    local t = parent:CreateFontString(nil, "OVERLAY")
    t:SetFont(FONT, size or 10, "OUTLINE")
    t:SetJustifyH(align or "LEFT")
    t:SetTextColor(1, 1, 1)
    t:SetShadowColor(0, 0, 0, 0.9)
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

local function ShortNumber(v)
    v = tonumber(v) or 0
    if v >= 1000000 then
        return string.format("%.1fM", v / 1000000)
    elseif v >= 10000 then
        return string.format("%.1fK", v / 1000)
    end
    return tostring(math.floor(v + 0.5))
end

local function Percent(v, m)
    if not m or m <= 0 then return 0 end
    return math.floor(v / m * 100 + 0.5)
end

local function UnitColor(unit)
    if UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        local c = class and RAID_CLASS_COLORS
            and RAID_CLASS_COLORS[class]
        if c then return c.r, c.g, c.b end
    end

    local reaction = UnitReaction(unit, "player")
    if reaction then
        if reaction <= 3 then
            return 0.92, 0.28, 0.28
        elseif reaction == 4 then
            return 0.96, 0.80, 0.28
        else
            return 0.32, 0.82, 0.44
        end
    end
    return 0.73, 0.59, 0.92
end

local function ResourceColor(unit)
    local kind, token = UnitPowerType(unit)
    local c = PowerBarColor
       and ((token and PowerBarColor[token])
       or PowerBarColor[kind])
    if c then return c.r, c.g, c.b end
    return 0.20, 0.50, 0.92
end

local function HealthColor(pct)
    if pct <= 35 then
        return 0.78, 0.23, 0.25
    elseif pct <= 65 then
        return 0.78, 0.61, 0.23
    end
    return 0.23, 0.67, 0.38
end

local function ColorTable(input, fallback)
    if type(input) ~= "table" then
        input = fallback
    end
    return {
        Clamp(input[1], 0, 1, fallback[1]),
        Clamp(input[2], 0, 1, fallback[2]),
        Clamp(input[3], 0, 1, fallback[3])
    }
end

local function OpenUnitMenu(unit, dropdownName)
    if not UnitExists(unit) then return end

    local dropdown = dropdownName and _G[dropdownName]
    if dropdown then
        ToggleDropDownMenu(
            1, nil, dropdown, "cursor", 0, 0
        )
        return
    end

    if not Core.fallbackMenu then
        Core.fallbackMenu = CreateFrame(
            "Frame", "RasfectionUICompactUnitMenu",
            UIParent, "UIDropDownMenuTemplate"
        )
    end

    local menu = Core.fallbackMenu
    menu.unit = unit

    UIDropDownMenu_Initialize(menu, function(self)
        if not UnitExists(self.unit) then return end

        local kind = "TARGET"
        if self.unit == "player" then
            kind = "SELF"
        elseif self.unit == "pet" then
            kind = "PET"
        end

        if UnitPopup_ShowMenu then
            UnitPopup_ShowMenu(
                self, kind, self.unit, UnitName(self.unit)
            )
        end
    end, "MENU")

    ToggleDropDownMenu(1, nil, menu, "cursor", 0, 0)
end

function Core:New(options)
    local module = {
        options = options,
        unit = options.unit,
        initialized = false,
        elapsed = 0
    }

    setmetatable(module, {__index = Core})
    return module
end

function Core:GetSettings()
    local o = self.options

    local s = {
        width = o.width,
        height = o.height,
        portrait = o.portrait == true,
        auras = o.auras == true,
        auraCount = o.auraCount or 8,
        auraSize = 19,
        scale = 100,
        showPower = true,
        healthMode = "health",
        powerMode = "resource",
        healthColor = {35, 165, 90},
        powerColor = {45, 110, 235},
        nameFont = o.compact and 10 or 12,
        valueFont = 9,
        levelFont = 10,
        auraPosition = "BELOW",
        auraGap = 2
    }

    local db = RUI:GetModule("Database")
    local profile = db and db.GetProfile
        and db:GetProfile()
    local saved = profile
        and type(profile.settings) == "table"
        and type(profile.settings.unitFrameLayout) == "table"
        and profile.settings.unitFrameLayout[o.moverID]

    if type(saved) == "table" then
        for k, v in pairs(saved) do
            if s[k] ~= nil then
                s[k] = v
            end
        end
    end

    s.width = Integer(s.width, 130, 500, o.width)
    s.height = Integer(s.height, 42, 150, o.height)
    s.auraCount = Integer(s.auraCount, 1, 12, 8)
    s.auraSize = Integer(s.auraSize, 14, 30, 19)
    s.auraGap = Integer(s.auraGap, 0, 12, 2)
    s.scale = Integer(s.scale, 50, 150, 100)
    s.nameFont = Integer(s.nameFont, 8, 20, 12)
    s.valueFont = Integer(s.valueFont, 7, 18, 9)
    s.levelFont = Integer(s.levelFont, 7, 18, 10)

    if s.healthMode ~= "class"
       and s.healthMode ~= "custom" then
        s.healthMode = "health"
    end
    if s.powerMode ~= "custom" then
        s.powerMode = "resource"
    end
    if s.auraPosition ~= "ABOVE" then
        s.auraPosition = "BELOW"
    end

    s.portrait = s.portrait == true and o.portrait == true
    s.auras = s.auras == true and o.auras == true
    s.showPower = s.showPower ~= false

    local hc = type(s.healthColor) == "table"
        and s.healthColor or {35, 165, 90}
    local pc = type(s.powerColor) == "table"
        and s.powerColor or {45, 110, 235}

    s.healthColor = {
        Integer(hc[1], 0, 255, 35),
        Integer(hc[2], 0, 255, 165),
        Integer(hc[3], 0, 255, 90)
    }

    s.powerColor = {
        Integer(pc[1], 0, 255, 45),
        Integer(pc[2], 0, 255, 110),
        Integer(pc[3], 0, 255, 235)
    }

    return s
end

function Core:CreateBar(parent, height)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(WHITE)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    bar:SetHeight(height)

    local background = Solid(
        parent, "BACKGROUND", 0.045, 0.055, 0.075, 1
    )
    background:SetAllPoints(bar)

    return bar
end

function Core:CreateAuraButton(holder, index, kind)
    local button = CreateFrame("Button", nil, holder)
    button:EnableMouse(true)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(button)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local count = Text(button, 9, "RIGHT")
    count:SetPoint(
        "BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1
    )

    button.icon = icon
    button.countText = count
    button.auraIndex = index
    button.auraKind = kind
    button.owner = self

    button:SetScript("OnEnter", function(b)
        local owner = b.owner
        local unit = owner.unit
        if not UnitExists(unit) then return end

        GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
        if b.auraKind == "buff" then
            GameTooltip:SetUnitBuff(unit, b.auraIndex)
        else
            GameTooltip:SetUnitDebuff(unit, b.auraIndex)
        end
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    button:Hide()
    return button
end

function Core:CreateAuras()
    if not self.options.auras then return end

    local holder = CreateFrame(
        "Frame", nil, self.frame
    )
    holder:SetFrameLevel(self.frame:GetFrameLevel() + 12)
    holder:EnableMouse(false)

    self.auraHolder = holder
    self.buffIcons = {}
    self.debuffIcons = {}

    for i = 1, 12 do
        self.buffIcons[i] =
            self:CreateAuraButton(holder, i, "buff")
        self.debuffIcons[i] =
            self:CreateAuraButton(holder, i, "debuff")
    end

    self:ApplyAuraLayout()
end

function Core:ApplyAuraLayout()
    if not self.auraHolder then return end

    local s = self:GetSettings()
    local size = s.auraSize
    local gap = s.auraGap
    local count = s.auraCount

    self.auraHolder:SetSize(
        count * size + (count - 1) * gap,
        size * 2 + 4
    )
    self.auraHolder:ClearAllPoints()

    local above = s.auraPosition == "ABOVE"
    local right = self.options.mirrored == true

    if above then
        if right then
            self.auraHolder:SetPoint(
                "BOTTOMRIGHT", self.frame,
                "TOPRIGHT", -2, 3
            )
        else
            self.auraHolder:SetPoint(
                "BOTTOMLEFT", self.frame,
                "TOPLEFT", 2, 3
            )
        end
    else
        if right then
            self.auraHolder:SetPoint(
                "TOPRIGHT", self.frame,
                "BOTTOMRIGHT", -2, -3
            )
        else
            self.auraHolder:SetPoint(
                "TOPLEFT", self.frame,
                "BOTTOMLEFT", 2, -3
            )
        end
    end

    for i = 1, 12 do
        local buff = self.buffIcons[i]
        local debuff = self.debuffIcons[i]

        buff:SetSize(size, size)
        debuff:SetSize(size, size)
        buff:ClearAllPoints()
        debuff:ClearAllPoints()

        local dx = (i - 1) * (size + gap)
        if right then
            buff:SetPoint(
                "TOPRIGHT", self.auraHolder,
                "TOPRIGHT", -dx, 0
            )
            debuff:SetPoint(
                "TOPRIGHT", self.auraHolder,
                "TOPRIGHT", -dx, -(size + 4)
            )
        else
            buff:SetPoint(
                "TOPLEFT", self.auraHolder,
                "TOPLEFT", dx, 0
            )
            debuff:SetPoint(
                "TOPLEFT", self.auraHolder,
                "TOPLEFT", dx, -(size + 4)
            )
        end
    end

    self:UpdateAuras()
end

function Core:UpdateAuras()
    if not self.auraHolder then return end

    local s = self:GetSettings()
    if not s.auras or not UnitExists(self.unit) then
        self.auraHolder:Hide()
        GameTooltip:Hide()
        return
    end

    self.auraHolder:Show()

    for i = 1, 12 do
        local buff = self.buffIcons[i]
        local debuff = self.debuffIcons[i]

        if i <= s.auraCount then
            local name, _, icon, stacks =
                UnitBuff(self.unit, i)

            if name and icon then
                buff.icon:SetTexture(icon)
                buff.countText:SetText(
                    stacks and stacks > 1
                    and tostring(stacks) or ""
                )
                buff:Show()
            else
                buff:Hide()
            end

            local dname, _, dicon, dstacks =
                UnitDebuff(self.unit, i)

            if dname and dicon then
                debuff.icon:SetTexture(dicon)
                debuff.countText:SetText(
                    dstacks and dstacks > 1
                    and tostring(dstacks) or ""
                )
                debuff:Show()
            else
                debuff:Hide()
            end
        else
            buff:Hide()
            debuff:Hide()
        end
    end
end

function Core:CreateFrame()
    local o = self.options
    local s = self:GetSettings()

    local frame = CreateFrame(
        "Button", o.frameName, UIParent,
        "SecureUnitButtonTemplate"
    )

    frame:SetSize(s.width, s.height)
    frame:SetScale(s.scale / 100)
    frame:SetPoint(
        "CENTER", UIParent, "CENTER",
        o.x or 0, o.y or 0
    )
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(10)
    frame:EnableMouse(true)
    frame:RegisterForClicks("AnyUp")

    local function Menu()
        OpenUnitMenu(o.unit, o.dropdown)
    end

    if SecureUnitButton_OnLoad then
        SecureUnitButton_OnLoad(frame, o.unit, Menu)
    end

    frame:SetAttribute("unit", o.unit)
    frame:SetAttribute("*type1", "target")
    frame:SetAttribute("*type2", "menu")
    frame.menu = Menu

    local theme = RUI:GetModule("Theme")
    if theme and theme.Apply then
        theme:Apply(frame, {
            borderSize = 13,
            insets = 3,
            backgroundColor = {
                0.035, 0.045, 0.061, 0.98
            }
        })
    end

    self.frame = frame

    if o.portrait then
        local portrait = frame:CreateTexture(
            nil, "ARTWORK"
        )
        portrait:SetTexCoord(
            0.08, 0.92, 0.08, 0.92
        )
        self.portrait = portrait
    end

    local content = CreateFrame("Frame", nil, frame)
    self.content = content

    local name = Text(content, o.compact and 10 or 12)
    name:SetPoint("TOPLEFT")
    name:SetPoint("TOPRIGHT", -35, 0)
    name:SetHeight(o.compact and 12 or 15)
    name:SetWordWrap(false)
    self.nameText = name

    local level = Text(content, 10, "RIGHT")
    level:SetPoint("TOPRIGHT")
    self.levelText = level

    local health = self:CreateBar(
        content, o.compact and 12 or 17
    )
    health:SetPoint(
        "TOPLEFT", content, "TOPLEFT",
        0, o.compact and -17 or -22
    )
    health:SetPoint(
        "TOPRIGHT", content, "TOPRIGHT",
        0, o.compact and -17 or -22
    )
    self.healthBar = health

    local power = self:CreateBar(
        content, o.compact and 3 or 6
    )
    power:SetPoint(
        "TOPLEFT", health, "BOTTOMLEFT", 0, -3
    )
    power:SetPoint(
        "TOPRIGHT", health, "BOTTOMRIGHT", 0, -3
    )
    self.powerBar = power

    local overlay = CreateFrame("Frame", nil, frame)
    overlay:SetAllPoints(frame)
    overlay:SetFrameLevel(frame:GetFrameLevel() + 8)
    overlay:EnableMouse(false)

    local hpText = Text(overlay, 9, "RIGHT")
    hpText:SetPoint(
        "RIGHT", health, "RIGHT", -3, 0
    )
    self.healthText = hpText

    local status = Text(overlay, 9, "CENTER")
    status:SetPoint("CENTER", health, "CENTER")
    self.statusText = status

    if not o.compact then
        local powerText = Text(overlay, 9, "RIGHT")
        powerText:SetPoint(
            "RIGHT", power, "RIGHT", -3, 0
        )
        self.powerText = powerText
    end

    self:ApplyLayout()
    self:CreateAuras()

    frame:SetScript("OnEnter", function(button)
        if UnitExists(o.unit) then
            GameTooltip_SetDefaultAnchor(
                GameTooltip, button
            )
            GameTooltip:SetUnit(o.unit)
            GameTooltip:Show()
        end
    end)

    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    if o.unit ~= "player" then
        RegisterUnitWatch(frame)
    end

    return frame
end

function Core:ApplyLayout()
    if not self.frame or Combat() then
        return false
    end

    local s = self:GetSettings()
    local o = self.options

    self.frame:SetSize(s.width, s.height)
    self.frame:SetScale(s.scale / 100)

    local portraitWidth = 0

    if self.portrait then
        if s.portrait then
            portraitWidth = math.max(
                20, s.height - 8
            )
            self.portrait:SetSize(
                portraitWidth, portraitWidth
            )
            self.portrait:ClearAllPoints()

            if o.mirrored then
                self.portrait:SetPoint(
                    "RIGHT", self.frame,
                    "RIGHT", -4, 0
                )
            else
                self.portrait:SetPoint(
                    "LEFT", self.frame,
                    "LEFT", 4, 0
                )
            end
            self.portrait:Show()
        else
            self.portrait:Hide()
        end
    end

    local inset = portraitWidth > 0
        and portraitWidth + 10 or 9

    self.content:ClearAllPoints()

    if o.mirrored and portraitWidth > 0 then
        self.content:SetPoint(
            "TOPLEFT", self.frame,
            "TOPLEFT", 9, -7
        )
        self.content:SetPoint(
            "BOTTOMRIGHT", self.frame,
            "BOTTOMRIGHT", -inset, 7
        )
    else
        self.content:SetPoint(
            "TOPLEFT", self.frame,
            "TOPLEFT", inset, -7
        )
        self.content:SetPoint(
            "BOTTOMRIGHT", self.frame,
            "BOTTOMRIGHT", -9, 7
        )
    end

    self.nameText:SetFont(
        FONT, s.nameFont, "OUTLINE"
    )
    self.levelText:SetFont(
        FONT, s.levelFont, "OUTLINE"
    )
    self.healthText:SetFont(
        FONT, s.valueFont, "OUTLINE"
    )

    if self.powerText then
        self.powerText:SetFont(
            FONT, s.valueFont, "OUTLINE"
        )
    end

    if s.showPower then
        self.powerBar:Show()
        if self.powerText then
            self.powerText:Show()
        end
    else
        self.powerBar:Hide()
        if self.powerText then
            self.powerText:Hide()
        end
    end

    if self.auraHolder then
        self:ApplyAuraLayout()
    end

    self:Update()
    return true
end

function Core:Update()
    if not self.frame then return end

    local unit = self.unit

    if not UnitExists(unit) then
        self.lastGUID = nil
        self:UpdateAuras()
        return
    end

    local guid = UnitGUID(unit)
    if guid ~= self.lastGUID then
        self.lastGUID = guid
        if self.portrait then
            SetPortraitTexture(self.portrait, unit)
        end
    end

    local s = self:GetSettings()
    local r, g, b = UnitColor(unit)

    self.nameText:SetText(
        UnitName(unit) or "Unknown"
    )
    self.nameText:SetTextColor(r, g, b)

    local level = UnitLevel(unit) or 0
    self.levelText:SetText(
        level == -1 and "??" or tostring(level)
    )

    local health = UnitHealth(unit) or 0
    local maxHealth = UnitHealthMax(unit) or 0
    local pct = Percent(health, maxHealth)

    self.healthBar:SetMinMaxValues(
        0, math.max(1, maxHealth)
    )
    self.healthBar:SetValue(health)

    local hr, hg, hb

    if s.healthMode == "class" then
        hr, hg, hb = UnitColor(unit)
    elseif s.healthMode == "custom" then
        hr = s.healthColor[1] / 255
        hg = s.healthColor[2] / 255
        hb = s.healthColor[3] / 255
    else
        hr, hg, hb = HealthColor(pct)
    end

    self.healthBar:SetStatusBarColor(hr, hg, hb)

    self.healthText:SetText(
        self.options.compact
        and (pct .. "%")
        or (ShortNumber(health) .. "/" ..
            ShortNumber(maxHealth))
    )

    local kind = UnitPowerType(unit) or 0
    local power = UnitPower(unit, kind) or 0
    local maxPower = UnitPowerMax(unit, kind) or 0

    self.powerBar:SetMinMaxValues(
        0, math.max(1, maxPower)
    )
    self.powerBar:SetValue(power)

    local pr, pg, pb
    if s.powerMode == "custom" then
        pr = s.powerColor[1] / 255
        pg = s.powerColor[2] / 255
        pb = s.powerColor[3] / 255
    else
        pr, pg, pb = ResourceColor(unit)
    end

    self.powerBar:SetStatusBarColor(pr, pg, pb)

    if self.powerText then
        self.powerText:SetText(
            ShortNumber(power) .. "/" ..
            ShortNumber(maxPower)
        )
    end

    local status = ""
    if not UnitIsConnected(unit) then
        status = "OFFLINE"
    elseif UnitIsDead(unit) then
        status = "DEAD"
    elseif UnitIsGhost(unit) then
        status = "GHOST"
    end

    self.statusText:SetText(status)
    if status ~= "" then
        self.healthText:SetText("")
    end

    self:UpdateAuras()
end

function Core:Initialize()
    if self.initialized or Combat() then return end

    self:CreateFrame()

    local movers = RUI:GetModule("Movers")
    if movers then
        movers:RegisterFrame(
            self.options.moverID,
            self.frame,
            {label = self.options.label}
        )
    end

    -- Reapply design dimensions after Movers
    -- restores positions from previous versions.
    self:ApplyLayout()

    local controller = CreateFrame(
        "Frame", nil, UIParent
    )

    local events = {
        "PLAYER_ENTERING_WORLD",
        "PLAYER_TARGET_CHANGED",
        "PLAYER_FOCUS_CHANGED",
        "UNIT_TARGET",
        "UNIT_PET",
        "UNIT_HEALTH",
        "UNIT_MAXHEALTH",
        "UNIT_POWER",
        "UNIT_MAXPOWER",
        "UNIT_DISPLAYPOWER",
        "UNIT_AURA",
        "UNIT_NAME_UPDATE",
        "UNIT_PORTRAIT_UPDATE",
        "UNIT_FLAGS"
    }

    for _, event in ipairs(events) do
        controller:RegisterEvent(event)
    end

    controller:SetScript("OnEvent", function()
        self:Update()
    end)

    controller:SetScript("OnUpdate", function(_, elapsed)
        self.elapsed = self.elapsed + elapsed

        if self.elapsed >= 0.20 then
            self.elapsed = 0
            self:Update()
        end
    end)

    self.controller = controller
    self.initialized = true
    self:Update()

    RUI:Print(
        self.options.label ..
        " appearance engine v2.2 ready."
    )
end
