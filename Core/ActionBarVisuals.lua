
--[[
 RasfectionUI - Core/ActionBarVisuals.lua
 Version 2.9.0
 WoW WotLK 3.3.5a / Build 12340

 ACTION BAR COMBAT READABILITY

 - Out-of-range red tint
 - Insufficient-resource blue tint
 - Unusable-action dark tint
 - Custom warning opacity
 - Optional proc glow when supported
 - Cooldown placement: center/top/bottom
 - Existing hotkey, count and cooldown settings
 - Exact numeric controls in Appearance
 - Reuses one cooldown label per button
 - Safe action page updates

 No secure attributes, button positions,
 bindings, or action assignments modified.
 No raid visibility changes.
]]

local RUI = _G.RasfectionUI
if not RUI then return end

local Visuals = {}
Visuals.version = "2.9.0"
Visuals.initialized = false
Visuals.pageInstalled = false
Visuals.buttons = {}
Visuals.buttonCache = {}
Visuals.fontOriginals = setmetatable({}, {__mode="k"})
Visuals.elapsed = 0
Visuals.styleElapsed = 0

local FONT = "Fonts\\FRIZQT__.TTF"
local WHITE = "Interface\\Buttons\\WHITE8X8"

local PREFIXES = {
    {"ActionButton", 12},
    {"MultiBarBottomLeftButton", 12},
    {"MultiBarBottomRightButton", 12},
    {"MultiBarRightButton", 12},
    {"MultiBarLeftButton", 12},
    {"PetActionButton", 10},
    {"ShapeshiftButton", 10}
}

local function Module(id)
    return RUI.GetModule and RUI:GetModule(id)
end

local function Combat()
    return InCombatLockdown and InCombatLockdown()
end

local function Clamp(v, a, b, fallback)
    v = tonumber(v)
    if not v or v ~= v
        or v == math.huge or v == -math.huge then
        v = fallback or a
    end
    return math.floor(math.max(a, math.min(b, v)) + 0.5)
end

local function Bool(v)
    return not not v
end

local function IsFont(v)
    return v and v.GetObjectType
        and v:GetObjectType() == "FontString"
end

local function TimeText(t)
    if t >= 3600 then
        return math.ceil(t / 3600) .. "h"
    elseif t >= 60 then
        return math.ceil(t / 60) .. "m"
    elseif t >= 10 then
        return tostring(math.ceil(t))
    elseif t > 0 then
        return string.format("%.1f", t)
    end
    return ""
end

function Visuals:GetSettings()
    local db = Module("Database")
    local profile = db and db.GetProfile and db:GetProfile()
    if not profile then return nil end

    profile.settings = profile.settings or {}
    local s = profile.settings.actionBarVisuals

    if type(s) ~= "table" then
        s = {}
        profile.settings.actionBarVisuals = s
    end

    local defaults = {
        enabled = true,
        globalFont = true,
        showHotkeys = true,
        showCounts = true,
        accentHotkeys = false,
        cooldownText = true,
        hotkeySize = 11,
        countSize = 11,
        cooldownSize = 12,
        cooldownMinimum = 2,

        rangeWarning = true,
        resourceWarning = true,
        unusableWarning = false,
        warningOpacity = 45,
        procGlow = true,
        cooldownPlacement = "CENTER"
    }

    for k, v in pairs(defaults) do
        if type(s[k]) ~= type(v) then
            s[k] = v
        end
    end

    s.hotkeySize = Clamp(s.hotkeySize, 7, 18, 11)
    s.countSize = Clamp(s.countSize, 7, 18, 11)
    s.cooldownSize = Clamp(s.cooldownSize, 8, 20, 12)
    s.cooldownMinimum = Clamp(s.cooldownMinimum, 2, 10, 2)
    s.warningOpacity = Clamp(s.warningOpacity, 10, 85, 45)

    if s.cooldownPlacement ~= "TOP"
        and s.cooldownPlacement ~= "BOTTOM" then
        s.cooldownPlacement = "CENTER"
    end

    return s
end

function Visuals:GetAccent()
    local app = Module("GlobalAppearance")
    if app and app.GetAccent then
        return app:GetAccent()
    end
    return 0.65, 0.42, 0.91
end

function Visuals:GetFont()
    local media = Module("GlobalMedia")
    if media and media.GetFontPath then
        return media:GetFontPath()
    end
    return FONT
end

function Visuals:GetFontFlags()
    local media = Module("GlobalMedia")
    if media and media.GetSettings then
        local s = media:GetSettings()
        if s and s.outline == false then
            return ""
        end
    end
    return "OUTLINE"
end

function Visuals:CaptureFont(font)
    if not IsFont(font) then return nil end
    if self.fontOriginals[font] then
        return self.fontOriginals[font]
    end

    local path, size, flags = font:GetFont()
    local r, g, b, a = font:GetTextColor()

    local result = {
        path = path or FONT,
        size = size or 11,
        flags = flags or "",
        r = r or 1,
        g = g or 1,
        b = b or 1,
        a = a or 1,
        alpha = font:GetAlpha()
    }
    self.fontOriginals[font] = result
    return result
end

function Visuals:StyleFont(font, size, hidden, colored)
    if not IsFont(font) then return end
    local original = self:CaptureFont(font)
    if not original then return end

    local s = self:GetSettings()
    if not s then return end

    if not s.enabled then
        font:SetFont(original.path, original.size, original.flags)
        font:SetTextColor(original.r, original.g,
            original.b, original.a)
        font:SetAlpha(original.alpha)
        return
    end

    local path = s.globalFont and self:GetFont()
        or original.path
    local flags = s.globalFont and self:GetFontFlags()
        or original.flags

    if not font:SetFont(path, size, flags) then
        font:SetFont(original.path, size, original.flags)
    end

    font:SetAlpha(hidden and 0 or original.alpha)

    if colored then
        local r, g, b = self:GetAccent()
        font:SetTextColor(r, g, b, 1)
    else
        font:SetTextColor(original.r, original.g,
            original.b, original.a)
    end
end

-- ==========================================
-- BUTTON DISCOVERY AND PERSISTENT REGIONS
-- ==========================================

function Visuals:DiscoverButtons()
    local found = {}

    for _, entry in ipairs(PREFIXES) do
        local prefix, count = entry[1], entry[2]

        for i = 1, count do
            local name = prefix .. i
            local button = _G[name]

            if button then
                local info = self.buttonCache[button]

                if not info then
                    info = {
                        button = button,
                        name = name,
                        kind = prefix,
                        index = i
                    }
                    self.buttonCache[button] = info
                end

                table.insert(found, info)
            end
        end
    end

    self.buttons = found
end

function Visuals:GetIcon(info)
    local b = info.button
    local icon = _G[info.name .. "Icon"]
        or b.icon or b.iconTexture

    if icon and icon.GetObjectType
        and icon:GetObjectType() == "Texture" then
        return icon
    end

    return nil
end

function Visuals:MakeRegions(info)
    if info.regionsCreated then return end
    if Combat() then return end

    local button = info.button
    local icon = self:GetIcon(info)

    -- Create once, reuse across every refresh.
    local text = button:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER", button, "CENTER", 0, 0)
    text:SetFont(FONT, 12, "OUTLINE")
    text:SetTextColor(1, 1, 1, 1)
    text:SetShadowColor(0, 0, 0, 1)
    text:SetShadowOffset(1, -1)
    text:Hide()
    info.cooldownLabel = text

    local tint = button:CreateTexture(nil, "ARTWORK")
    tint:SetTexture(WHITE)

    if icon then
        tint:SetAllPoints(icon)
        -- Keep the overlay over the icon, not
        -- over the surrounding metallic border.
        tint:SetDrawLayer("ARTWORK", 7)
    else
        tint:SetPoint("TOPLEFT", button, "TOPLEFT", 4, -4)
        tint:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -4, 4)
    end

    tint:Hide()
    info.warningTint = tint

    local glow = {}
    for i = 1, 4 do
        local strip = button:CreateTexture(nil, "OVERLAY")
        strip:SetTexture(WHITE)
        strip:Hide()
        glow[i] = strip
    end

    glow[1]:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    glow[1]:SetPoint("TOPRIGHT", button, "TOPRIGHT", -2, -2)
    glow[1]:SetHeight(2)

    glow[2]:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 2)
    glow[2]:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    glow[2]:SetHeight(2)

    glow[3]:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    glow[3]:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 2)
    glow[3]:SetWidth(2)

    glow[4]:SetPoint("TOPRIGHT", button, "TOPRIGHT", -2, -2)
    glow[4]:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    glow[4]:SetWidth(2)

    info.procStrips = glow
    info.regionsCreated = true
end

function Visuals:GetSlot(info)
    local button = info.button

    if info.kind == "ActionButton"
        and type(ActionButton_GetPagedID) == "function" then
        local slot = ActionButton_GetPagedID(button)
        if type(slot) == "number" and slot > 0 then
            return slot
        end
    end

    if type(button.action) == "number"
        and button.action > 0 then
        return button.action
    end

    if button.GetAttribute then
        local slot = button:GetAttribute("action")
        if type(slot) == "number" and slot > 0 then
            return slot
        end
    end

    return nil
end

function Visuals:StyleButton(info)
    local s = self:GetSettings()
    if not s then return end

    local name = info.name
    local b = info.button

    local hotkey = _G[name .. "HotKey"] or b.HotKey
    local count = _G[name .. "Count"] or b.Count

    self:StyleFont(hotkey, s.hotkeySize,
        not s.showHotkeys, s.accentHotkeys)
    self:StyleFont(count, s.countSize,
        not s.showCounts, false)

    local label = info.cooldownLabel
    if label then
        local path = s.globalFont and self:GetFont() or FONT
        local flags = s.globalFont and self:GetFontFlags()
            or "OUTLINE"

        if not label:SetFont(path, s.cooldownSize, flags) then
            label:SetFont(FONT, s.cooldownSize, "OUTLINE")
        end

        label:ClearAllPoints()

        if s.cooldownPlacement == "TOP" then
            label:SetPoint("TOP", b, "TOP", 0, -5)
        elseif s.cooldownPlacement == "BOTTOM" then
            label:SetPoint("BOTTOM", b, "BOTTOM", 0, 5)
        else
            label:SetPoint("CENTER", b, "CENTER", 0, 0)
        end

        local r, g, bb = self:GetAccent()
        label:SetTextColor(r, g, bb, 1)
    end
end

-- ==========================================
-- LIVE ACTION READABILITY
-- ==========================================

function Visuals:HideProc(info)
    if not info.procStrips then return end
    for _, strip in ipairs(info.procStrips) do
        strip:Hide()
    end
end

function Visuals:UpdateProc(info, slot, s)
    if not info.procStrips then return end

    -- Not every 3.3.5a client supports the
    -- newer spell overlay API. If absent,
    -- do not invent proc indications.
    if not s.enabled or not s.procGlow
        or type(IsSpellOverlayed) ~= "function"
        or not slot or not GetActionInfo then
        self:HideProc(info)
        return
    end

    local kind, spellID = GetActionInfo(slot)

    if kind ~= "spell" or not spellID then
        self:HideProc(info)
        return
    end

    local active = IsSpellOverlayed(spellID)
    if not active then
        self:HideProc(info)
        return
    end

    local r, g, b = self:GetAccent()
    local pulse = 0.55 + math.abs(
        math.sin(GetTime() * 3)
    ) * 0.45

    for _, strip in ipairs(info.procStrips) do
        strip:SetVertexColor(r, g, b, pulse)
        strip:Show()
    end
end

function Visuals:UpdateButton(info)
    local s = self:GetSettings()
    if not s or not info.regionsCreated then return end

    local tint = info.warningTint
    local label = info.cooldownLabel

    if not s.enabled or not info.button:IsShown() then
        tint:Hide()
        label:Hide()
        self:HideProc(info)
        return
    end

    local slot = self:GetSlot(info)
    local alpha = s.warningOpacity / 100

    -- Warnings are only evaluated where the
    -- action-slot APIs are applicable.
    if not slot or not HasAction or not HasAction(slot) then
        tint:Hide()
        label:Hide()
        self:HideProc(info)
        return
    end

    local warning

    -- IsActionInRange returns:
    -- 0 = out of range, 1 = in range,
    -- nil = range not measurable.
    -- nil must NOT be treated as out of range.
    if s.rangeWarning and IsActionInRange
        and IsActionInRange(slot) == 0 then
        warning = "range"
    end

    if not warning and IsUsableAction then
        local usable, noMana = IsUsableAction(slot)

        if not usable then
            if noMana and s.resourceWarning then
                warning = "resource"
            elseif not noMana and s.unusableWarning then
                warning = "unusable"
            end
        end
    end

    if warning == "range" then
        tint:SetVertexColor(0.88, 0.10, 0.12, alpha)
        tint:Show()
    elseif warning == "resource" then
        tint:SetVertexColor(0.12, 0.30, 0.95, alpha)
        tint:Show()
    elseif warning == "unusable" then
        tint:SetVertexColor(0.04, 0.04, 0.06, alpha)
        tint:Show()
    else
        tint:Hide()
    end

    -- Only normal action slots receive our
    -- cooldown numbers. Pet/stance buttons
    -- retain their Blizzard cooldown spirals.
    if s.cooldownText
        and info.kind ~= "PetActionButton"
        and info.kind ~= "ShapeshiftButton"
        and GetActionCooldown then

        local start, duration, enabled =
            GetActionCooldown(slot)

        start = tonumber(start) or 0
        duration = tonumber(duration) or 0

        local remaining = start + duration - GetTime()

        if enabled ~= 0 and start > 0
            and duration >= s.cooldownMinimum
            and remaining > 0 then
            label:SetText(TimeText(remaining))
            label:Show()
        else
            label:Hide()
        end
    else
        label:Hide()
    end

    self:UpdateProc(info, slot, s)
end

function Visuals:ApplyAll()
    if Combat() then
        self.pending = true
        return false
    end

    self:DiscoverButtons()

    for _, info in ipairs(self.buttons) do
        self:MakeRegions(info)
        self:StyleButton(info)
        self:UpdateButton(info)
    end

    self.pending = false
    return true
end

function Visuals:RefreshConfig()
    local config = Module("Config")
    if config and config.Refresh then
        config:Refresh()
    end
end

function Visuals:SetOption(key, value)
    if Combat() then
        if RUI.Error then
            RUI:Error("Change action-bar options outside combat.")
        end
        self:RefreshConfig()
        return false
    end

    local s = self:GetSettings()
    if not s then return false end

    local ranges = {
        hotkeySize = {7, 18},
        countSize = {7, 18},
        cooldownSize = {8, 20},
        cooldownMinimum = {2, 10},
        warningOpacity = {10, 85}
    }

    local booleans = {
        enabled = true,
        globalFont = true,
        showHotkeys = true,
        showCounts = true,
        accentHotkeys = true,
        cooldownText = true,
        rangeWarning = true,
        resourceWarning = true,
        unusableWarning = true,
        procGlow = true
    }

    if ranges[key] then
        local r = ranges[key]
        s[key] = Clamp(value, r[1], r[2], s[key])
    elseif booleans[key] then
        s[key] = Bool(value)
    elseif key == "cooldownPlacement" then
        if value ~= "CENTER" and value ~= "TOP"
            and value ~= "BOTTOM" then
            return false
        end
        s[key] = value
    else
        return false
    end

    self:ApplyAll()
    self:RefreshConfig()
    return true
end

-- ==========================================
-- EXTEND GLOBAL APPEARANCE PAGE
-- ==========================================

function Visuals:InstallConfigPage()
    if self.pageInstalled then return true end

    local config = Module("Config")
    if not config or not config.BuildAppearance then
        return false
    end

    local previousBuild = config.BuildAppearance
    local visuals = self

    config.BuildAppearance = function(ui)
        local page = previousBuild(ui)
        if not page then return nil end

        page:SetHeight(4300)

        local function Check(key, label, y)
            ui:Check(page, "abv_" .. key, label, y,
                function()
                    local s = visuals:GetSettings()
                    return s and s[key] == true or false
                end,
                function(v)
                    visuals:SetOption(key, v)
                end)
        end

        local function Number(key, label, y, lo, hi)
            ui:Slider(page, "abv_" .. key, label,
                y, lo, hi,
                function()
                    local s = visuals:GetSettings()
                    return s and s[key] or lo
                end,
                function(v)
                    visuals:SetOption(key, v)
                end)
        end

        -- Preserve the existing v2.8 controls.
        ui:Section(page, "ACTION BAR VISUALS", 2730)

        ui:Description(page,
            "Customize text and readability without changing button assignments or layouts.",
            2770)

        Check("enabled", "Enable action-bar visual styling", 2820)
        Check("globalFont", "Use the selected global font", 2860)
        Check("showHotkeys", "Show hotkeys", 2900)
        Check("showCounts", "Show stack counts", 2940)
        Check("accentHotkeys", "Use theme color for hotkeys", 2980)
        Check("cooldownText", "Show cooldown countdowns", 3020)

        ui:Section(page, "ACTION BAR FONT SIZES", 3080)
        Number("hotkeySize", "Hotkey font size", 3125, 7, 18)
        Number("countSize", "Stack-count font size", 3205, 7, 18)
        Number("cooldownSize", "Cooldown font size", 3285, 8, 20)
        Number("cooldownMinimum",
            "Minimum cooldown duration (seconds)",
            3365, 2, 10)

        -- New v2.9 options.
        ui:Section(page, "COMBAT READABILITY", 3460)

        Check("rangeWarning",
            "Red overlay when out of range", 3500)
        Check("resourceWarning",
            "Blue overlay when resources are insufficient", 3540)
        Check("unusableWarning",
            "Dim actions that cannot be used", 3580)
        Check("procGlow",
            "Show proc highlights when supported", 3620)

        Number("warningOpacity",
            "Warning overlay opacity (%)",
            3690, 10, 85)

        ui:Section(page, "COOLDOWN TEXT POSITION", 3790)

        visuals.positionButtons = {}
        local positions = {
            {"CENTER", "Center", 17},
            {"TOP", "Top", 190},
            {"BOTTOM", "Bottom", 363}
        }

        for _, entry in ipairs(positions) do
            local value, label, x =
                entry[1], entry[2], entry[3]

            local button = ui:Action(
                page, label, 3840,
                function()
                    visuals:SetOption(
                        "cooldownPlacement", value
                    )
                end, 158
            )

            button:ClearAllPoints()
            button:SetPoint(
                "TOPLEFT", page,
                "TOPLEFT", x, -3840
            )

            visuals.positionButtons[value] = button
        end

        ui:Description(page,
            "Range checks only tint actions whose range can be measured. Proc highlights depend on the client supporting spell overlay detection.",
            3910)

        page:SetHeight(4020)
        visuals:RefreshPositionButtons()
        return page
    end

    local previousRefresh = config.Refresh

    config.Refresh = function(ui, ...)
        local result = previousRefresh(ui, ...)
        visuals:RefreshPositionButtons()
        return result
    end

    self.pageInstalled = true
    return true
end

function Visuals:RefreshPositionButtons()
    local s = self:GetSettings()
    if not s then return end

    local r, g, b = self:GetAccent()

    for value, button in pairs(self.positionButtons or {}) do
        if button and button.RUIBackground then
            if value == s.cooldownPlacement then
                button.RUIBackground:SetVertexColor(
                    math.max(0.12, r * 0.53),
                    math.max(0.12, g * 0.53),
                    math.max(0.16, b * 0.53), 1
                )
            else
                button.RUIBackground:SetVertexColor(
                    0.18, 0.18, 0.24, 1
                )
            end
        end
    end
end

function Visuals:InstallMediaBridge()
    if self.mediaWrapped then return end
    local media = Module("GlobalMedia")
    if not media or not media.ApplyAll then return end

    local previous = media.ApplyAll
    local visuals = self

    media.ApplyAll = function(selfMedia, ...)
        local result = previous(selfMedia, ...)
        if not Combat() then visuals:ApplyAll() end
        return result
    end

    self.mediaWrapped = true
end

function Visuals:InstallAppearanceBridge()
    if self.appearanceWrapped then return end
    local appearance = Module("GlobalAppearance")
    if not appearance or not appearance.ApplyAll then return end

    local previous = appearance.ApplyAll
    local visuals = self

    appearance.ApplyAll = function(selfAppearance, ...)
        local result = previous(selfAppearance, ...)
        if not Combat() then visuals:ApplyAll() end
        return result
    end

    self.appearanceWrapped = true
end

function Visuals:Initialize()
    if self.initialized then return end

    self:GetSettings()
    self:InstallConfigPage()
    self:InstallMediaBridge()
    self:InstallAppearanceBridge()

    local controller = CreateFrame(
        "Frame",
        "RasfectionUIActionBarVisualsController",
        UIParent
    )

    local events = {
        "PLAYER_ENTERING_WORLD",
        "PLAYER_REGEN_ENABLED",
        "ACTIONBAR_PAGE_CHANGED",
        "UPDATE_BONUS_ACTIONBAR",
        "ACTIONBAR_SLOT_CHANGED",
        "ACTIONBAR_UPDATE_COOLDOWN",
        "ACTIONBAR_UPDATE_USABLE",
        "ACTIONBAR_UPDATE_STATE",
        "PLAYER_TARGET_CHANGED",
        "UNIT_POWER",
        "UNIT_MANA"
    }

    for _, event in ipairs(events) do
        controller:RegisterEvent(event)
    end

    controller:SetScript("OnEvent", function()
        if not Combat() then
            Visuals:ApplyAll()
        else
            Visuals.pending = true
        end
    end)

    controller:SetScript("OnUpdate", function(_, dt)
        Visuals.elapsed = Visuals.elapsed + dt
        Visuals.styleElapsed = Visuals.styleElapsed + dt

        if Visuals.elapsed >= 0.20 then
            Visuals.elapsed = 0

            for _, info in ipairs(Visuals.buttons) do
                Visuals:UpdateButton(info)
            end
        end

        if Visuals.styleElapsed >= 2 then
            Visuals.styleElapsed = 0

            if not Combat() then
                if Visuals.pending then
                    Visuals:ApplyAll()
                else
                    for _, info in ipairs(Visuals.buttons) do
                        Visuals:StyleButton(info)
                    end
                end
            end
        end
    end)

    self.controller = controller
    self.initialized = true
    self:ApplyAll()

    if RUI.Success then
        RUI:Success(
            "Action Bar Usability v2.9 initialized."
        )
    end
end

RUI:RegisterModule("ActionBarVisuals", Visuals)
