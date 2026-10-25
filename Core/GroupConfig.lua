
--[[
 RasfectionUI - Core/GroupConfig.lua
 Version 2.1.2
 WoW 3.3.5a / Build 12340

 FIX:
   WoW checkbox GetChecked() may return 1.
   Use "not not" for correct Boolean conversion.

 PRESERVES:
   Permanent sidebar and scrolling pages
   Custom clean numeric EditBoxes
   Exact values with Enter / Escape
   Persistent configuration pages
   Party, Raid and Action Bar settings
   UnitFrameOptions extension API
   AuraEnhancements extension API
   Saved per-character configuration
   Combat lockdown restrictions
]]

local RUI = _G.RasfectionUI
if not RUI then return end

local Config = {}

Config.version = "2.1.2"
Config.initialized = false
Config.currentPage = "general"
Config.selectedBar = "main"
Config.needsReload = false
Config.updating = false

Config.pages = {}
Config.navButtons = {}
Config.barButtons = {}

local WHITE = "Interface\\Buttons\\WHITE8X8"
local FONT = "Fonts\\FRIZQT__.TTF"
local BORDER =
    "Interface\\AddOns\\RasfectionUI\\Media\\RaisedBorder"

local DEFAULTS = {
    partyWidth = 234,
    partyGap = 3,
    raidGap = 4,
    raidRows = 5,
    criticalHealth = 35,
    warningHealth = 55,
    showDispels = true,
    showCritical = true,
    showThreat = true,
    showRange = true
}

local RANGES = {
    partyWidth = {190, 340},
    partyGap = {0, 15},
    raidGap = {0, 15},
    raidRows = {2, 8},
    criticalHealth = {10, 50},
    warningHealth = {35, 85}
}

local PAGE_ORDER = {
    {"general", "GENERAL"},
    {"units", "UNIT FRAMES"},
    {"party", "PARTY"},
    {"raid", "RAID"},
    {"bars", "ACTION BARS"},
    {"appearance", "APPEARANCE"}
}

local BAR_ORDER = {
    {"main", "Main Action Bar"},
    {"bottomleft", "Bottom Left"},
    {"bottomright", "Bottom Right"},
    {"right", "Right Side"},
    {"left", "Left Side"}
}

local function Combat()
    return InCombatLockdown
        and InCombatLockdown()
end

local function Module(name)
    return RUI:GetModule(name)
end

local function Clamp(value, low, high, fallback)
    value = tonumber(value)

    if not value or value ~= value
        or value == math.huge
        or value == -math.huge then
        value = fallback or low
    end

    return math.max(
        low,
        math.min(high, math.floor(value + 0.5))
    )
end

local function MakeText(parent, value, size, r, g, b)
    local text = parent:CreateFontString(nil, "OVERLAY")
    text:SetFont(FONT, size or 11, "OUTLINE")
    text:SetText(value or "")
    text:SetTextColor(r or 1, g or 1, b or 1)
    text:SetShadowColor(0, 0, 0, 0.85)
    text:SetShadowOffset(1, -1)
    return text
end

local function MakeTexture(parent, r, g, b, a, layer)
    local t = parent:CreateTexture(
        nil, layer or "BACKGROUND"
    )
    t:SetTexture(WHITE)
    t:SetVertexColor(r, g, b, a or 1)
    return t
end

local function MakePanel(parent)
    local panel = CreateFrame("Frame", nil, parent)

    panel:SetBackdrop({
        bgFile = WHITE,
        edgeFile = WHITE,
        edgeSize = 1,
        insets = {
            left = 1,
            right = 1,
            top = 1,
            bottom = 1
        }
    })

    panel:SetBackdropColor(
        0.095, 0.105, 0.14, 0.96
    )
    panel:SetBackdropBorderColor(
        0.23, 0.24, 0.30, 1
    )

    return panel
end

local function MakeButton(parent, label, width, height)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width or 150, height or 29)

    local background = MakeTexture(
        button, 0.18, 0.18, 0.24, 1
    )
    background:SetAllPoints()

    local highlight = MakeTexture(
        button,
        0.53, 0.32, 0.75, 0.30,
        "HIGHLIGHT"
    )
    highlight:SetAllPoints()

    local caption = MakeText(
        button, label, 11,
        0.91, 0.90, 0.96
    )
    caption:SetPoint("CENTER")

    button.RUIBackground = background
    button.RUIText = caption

    return button
end

local function MakeNumberInput(parent)
    local edit = CreateFrame("EditBox", nil, parent)

    edit:SetSize(76, 23)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(7)
    edit:SetNumeric(true)
    edit:SetJustifyH("CENTER")
    edit:SetFont(FONT, 12, "OUTLINE")
    edit:SetTextColor(0.86, 0.73, 1, 1)
    edit:SetTextInsets(5, 5, 0, 0)

    edit:SetBackdrop({
        bgFile = WHITE,
        edgeFile = WHITE,
        edgeSize = 1,
        insets = {
            left = 1,
            right = 1,
            top = 1,
            bottom = 1
        }
    })

    edit:SetBackdropColor(
        0.055, 0.065, 0.09, 0.97
    )
    edit:SetBackdropBorderColor(
        0.27, 0.29, 0.37, 1
    )

    edit:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(
            0.70, 0.46, 0.96, 1
        )
        self:HighlightText()
    end)

    edit:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(
            0.27, 0.29, 0.37, 1
        )
    end)

    return edit
end

-- ==========================================
-- SETTINGS
-- ==========================================

function Config:GetSettings()
    local db = Module("Database")
    if not db or not db.GetProfile then
        return nil
    end

    local profile = db:GetProfile()
    if not profile then return nil end

    if type(profile.settings) ~= "table" then
        profile.settings = {}
    end

    if type(profile.settings.groupConfig) ~= "table" then
        profile.settings.groupConfig = {}
    end

    local s = profile.settings.groupConfig

    for key, default in pairs(DEFAULTS) do
        if type(s[key]) ~= type(default) then
            s[key] = default
        end
    end

    for key, range in pairs(RANGES) do
        s[key] = Clamp(
            s[key],
            range[1],
            range[2],
            DEFAULTS[key]
        )
    end

    if s.warningHealth <= s.criticalHealth then
        s.warningHealth = math.min(
            85, s.criticalHealth + 5
        )
    end

    return s
end

function Config:ApplySettings(initial)
    local s = self:GetSettings()
    if not s then return end

    local party = Module("PartyFrames")
    local raid = Module("RaidFrames")
    local indicators = Module("RaidIndicators")

    if initial then
        if party and party.defaults then
            party.defaults.width = s.partyWidth
            party.defaults.rowGap = s.partyGap
        end

        if raid and raid.config then
            raid.config.gap = s.raidGap
            raid.config.unitsPerColumn = s.raidRows
        end
    end

    if raid and raid.config then
        raid.config.showThreat = s.showThreat
        raid.config.showRange = s.showRange
        raid.config.showDispels = s.showDispels
    end

    if indicators and indicators.config then
        indicators.config.criticalHealth =
            s.criticalHealth
        indicators.config.warningHealth =
            s.warningHealth
        indicators.config.showDispels =
            s.showDispels
        indicators.config.showCritical =
            s.showCritical

        if indicators.initialized
            and indicators.Refresh then
            indicators:Refresh()
        end
    end

    if raid and raid.initialized and raid.UpdateAll then
        raid:UpdateAll()
    end
end

function Config:SetOption(key, value)
    if Combat() then
        RUI:Error("Configuration is locked during combat.")
        self:Refresh()
        return false
    end

    if DEFAULTS[key] == nil then
        return false
    end

    local s = self:GetSettings()
    if not s then return false end

    if RANGES[key] then
        local range = RANGES[key]
        value = Clamp(
            value,
            range[1],
            range[2],
            DEFAULTS[key]
        )
    else
        -- Explicit Boolean conversion.
        value = not not value
    end

    s[key] = value

    if s.warningHealth <= s.criticalHealth then
        if key == "criticalHealth" then
            s.warningHealth = math.min(
                85, s.criticalHealth + 5
            )
        else
            s.criticalHealth = math.max(
                10, s.warningHealth - 5
            )
        end
    end

    if key == "partyWidth"
        or key == "partyGap"
        or key == "raidGap"
        or key == "raidRows" then
        self.needsReload = true
    end

    self:ApplySettings(false)
    self:Refresh()
    return true
end

-- ==========================================
-- ACTION BAR INTEGRATION
-- ==========================================

function Config:GetBarLayout()
    return Module("ActionBarLayout")
end

function Config:GetBarSettings()
    local layout = self:GetBarLayout()

    if not layout or not layout.GetSettings then
        return nil
    end

    local s = layout:GetSettings()

    return s and s.bars
        and s.bars[self.selectedBar]
        or nil
end

function Config:SetBarOption(field, value)
    if Combat() then
        RUI:Error("Cannot edit action bars during combat.")
        self:Refresh()
        return false
    end

    local layout = self:GetBarLayout()

    if layout and layout.SetBarOption then
        layout:SetBarOption(
            self.selectedBar,
            field,
            value
        )
    end

    self:Refresh()
    return true
end

-- ==========================================
-- MAIN WINDOW
-- ==========================================

function Config:CreateWindow()
    if self.window then
        return self.window
    end

    local frame = CreateFrame(
        "Frame",
        "RasfectionUIGlobalConfig",
        UIParent
    )

    frame:SetSize(830, 620)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(100)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")

    frame:SetScript("OnDragStart", function(self)
        if not Combat() then
            self:StartMoving()
        end
    end)

    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)

    local theme = Module("Theme")

    if theme and theme.Apply then
        theme:Apply(frame, {
            borderSize = 24,
            insets = 6,
            backgroundColor = {
                0.035, 0.042, 0.060, 0.99
            }
        })
    else
        frame:SetBackdrop({
            bgFile = WHITE,
            edgeFile = BORDER,
            edgeSize = 24,
            insets = {
                left = 6,
                right = 6,
                top = 6,
                bottom = 6
            }
        })
        frame:SetBackdropColor(
            0.035, 0.042, 0.060, 0.99
        )
    end

    local title = MakeText(
        frame,
        "RASFECTION UI",
        20, 0.80, 0.62, 1
    )
    title:SetPoint("TOPLEFT", 27, -23)

    local subtitle = MakeText(
        frame,
        "GLOBAL CONFIGURATION CENTER  |  v2.1.2",
        10, 0.62, 0.65, 0.75
    )
    subtitle:SetPoint(
        "TOPLEFT", title, "BOTTOMLEFT",
        0, -5
    )

    local close = CreateFrame(
        "Button", nil, frame,
        "UIPanelCloseButton"
    )
    close:SetPoint("TOPRIGHT", -12, -12)
    close:SetScript("OnClick", function()
        frame:Hide()
    end)

    local line = MakeTexture(
        frame, 0.59, 0.37, 0.84, 0.80,
        "ARTWORK"
    )
    line:SetHeight(2)
    line:SetPoint("TOPLEFT", 20, -75)
    line:SetPoint("TOPRIGHT", -20, -75)

    self.window = frame

    self:CreateNavigation()
    self:CreateContent()
    self:CreateFooter()

    frame:Hide()
    return frame
end

function Config:CreateNavigation()
    local side = MakePanel(self.window)
    side:SetPoint("TOPLEFT", 21, -87)
    side:SetPoint("BOTTOMLEFT", 21, 61)
    side:SetWidth(185)

    local title = MakeText(
        side, "MODULES",
        11, 0.67, 0.54, 0.84
    )
    title:SetPoint("TOPLEFT", 13, -15)

    for i, item in ipairs(PAGE_ORDER) do
        local id = item[1]
        local label = item[2]

        local button = MakeButton(
            side, label, 163, 34
        )

        button:SetPoint(
            "TOPLEFT", side, "TOPLEFT",
            11, -40 - (i - 1) * 39
        )

        button.RUIText:ClearAllPoints()
        button.RUIText:SetPoint(
            "LEFT", button, "LEFT", 13, 0
        )

        button:SetScript("OnClick", function()
            Config:ShowPage(id)
        end)

        self.navButtons[id] = button
    end

    local version = MakeText(
        side, "WOTLK 3.3.5a",
        9, 0.47, 0.50, 0.60
    )
    version:SetPoint("BOTTOMLEFT", 14, 15)

    self.navigation = side
end

function Config:CreateContent()
    local panel = MakePanel(self.window)
    panel:SetPoint("TOPLEFT", 215, -87)
    panel:SetPoint("BOTTOMRIGHT", -21, 61)

    local scroll = CreateFrame(
        "ScrollFrame",
        "RasfectionUIConfigScroll",
        panel,
        "UIPanelScrollFrameTemplate"
    )

    scroll:SetPoint(
        "TOPLEFT", panel, "TOPLEFT", 8, -9
    )
    scroll:SetPoint(
        "BOTTOMRIGHT", panel,
        "BOTTOMRIGHT", -28, 9
    )

    scroll:EnableMouseWheel(true)

    scroll:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local maximum = self:GetVerticalScrollRange()

        self:SetVerticalScroll(
            math.max(
                0,
                math.min(maximum, current - delta * 35)
            )
        )
    end)

    self.contentPanel = panel
    self.scroll = scroll
end

-- ==========================================
-- PERSISTENT PAGE HELPERS
-- ==========================================

function Config:CreatePage(id, height)
    if self.pages[id] then
        return self.pages[id]
    end

    local page = CreateFrame(
        "Frame", nil, self.scroll
    )

    page:SetSize(548, height or 700)
    page.RUIControls = {}

    self.pages[id] = page
    return page
end

function Config:Heading(page, label, y)
    local text = MakeText(
        page, label, 17,
        0.81, 0.65, 1
    )
    text:SetPoint("TOPLEFT", 16, -y)
    return text
end

function Config:Description(page, label, y)
    local text = MakeText(
        page, label, 11,
        0.68, 0.72, 0.80
    )
    text:SetWidth(495)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(true)
    text:SetPoint("TOPLEFT", 16, -y)
    return text
end

function Config:Section(page, label, y)
    local text = MakeText(
        page, label, 12,
        0.76, 0.55, 1
    )
    text:SetPoint("TOPLEFT", 17, -y)

    local line = MakeTexture(
        page, 0.32, 0.27, 0.43, 0.80,
        "ARTWORK"
    )
    line:SetPoint("TOPLEFT", 17, -(y + 22))
    line:SetSize(500, 1)

    return text
end

-- ==========================================
-- SLIDER WITH EXACT NUMBER INPUT
-- ==========================================

function Config:Slider(
    page, key, label, y,
    minimum, maximum,
    getter, setter
)
    local title = MakeText(
        page, label, 11,
        0.89, 0.90, 0.95
    )
    title:SetPoint("TOPLEFT", 21, -y)

    local slider = CreateFrame(
        "Slider", nil, page
    )
    slider:SetSize(386, 18)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(minimum, maximum)
    slider:SetValueStep(1)
    slider:SetPoint(
        "TOPLEFT", page, "TOPLEFT",
        21, -(y + 29)
    )

    local track = MakeTexture(
        slider, 0.16, 0.18, 0.24, 1
    )
    track:SetPoint("LEFT", slider, "LEFT")
    track:SetPoint("RIGHT", slider, "RIGHT")
    track:SetHeight(5)

    slider:SetThumbTexture(
        "Interface\\Buttons\\UI-SliderBar-Button-Horizontal"
    )

    local thumb = slider:GetThumbTexture()
    if thumb then
        thumb:SetSize(20, 20)
        thumb:SetVertexColor(0.77, 0.54, 1, 1)
    end

    local edit = MakeNumberInput(page)
    edit:SetPoint(
        "LEFT", slider, "RIGHT", 17, 0
    )

    local function ReadValue()
        return Clamp(
            getter and getter(),
            minimum,
            maximum,
            minimum
        )
    end

    local lastValue = ReadValue()

    local function Display(value)
        value = Clamp(
            value, minimum, maximum, minimum
        )

        lastValue = value

        local previous = Config.updating
        Config.updating = true

        slider:SetValue(value)

        if not edit:HasFocus() then
            edit:SetText(tostring(value))
        end

        Config.updating = previous
    end

    slider:SetScript("OnValueChanged", function(_, value)
        if Config.updating then return end

        if Combat() then
            Display(ReadValue())
            return
        end

        local rounded = Clamp(
            value, minimum, maximum, lastValue
        )

        if rounded == lastValue then
            return
        end

        setter(rounded)
        Display(ReadValue())
    end)

    slider:EnableMouseWheel(true)

    slider:SetScript("OnMouseWheel", function(self, delta)
        if Combat() then return end

        self:SetValue(
            self:GetValue() + delta
        )
    end)

    edit:SetScript("OnEnterPressed", function(self)
        if Combat() then
            RUI:Error("Change numeric settings outside combat.")
            self:ClearFocus()
            Display(ReadValue())
            return
        end

        local number = tonumber(self:GetText())

        if not number or number ~= number
            or number == math.huge
            or number == -math.huge then

            RUI:Error(
                "Enter a valid number for " .. label .. "."
            )

            self:ClearFocus()
            Display(ReadValue())
            return
        end

        setter(Clamp(
            number, minimum, maximum, lastValue
        ))

        self:ClearFocus()
        Display(ReadValue())
    end)

    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        Display(ReadValue())
    end)

    edit:HookScript("OnEditFocusLost", function()
        Display(ReadValue())
    end)

    page.RUIControls[key] = {
        kind = "slider",
        control = slider,
        input = edit,
        getter = getter,
        display = Display
    }

    Display(ReadValue())
    return slider
end

-- ==========================================
-- CHECKBOX — GLOBAL FIX
-- ==========================================

function Config:Check(
    page, key, label, y,
    getter, setter
)
    local check = CreateFrame(
        "CheckButton", nil, page,
        "UICheckButtonTemplate"
    )

    check:SetSize(26, 26)
    check:SetPoint("TOPLEFT", 13, -y)

    local text = MakeText(
        page, label, 11,
        0.90, 0.91, 0.96
    )
    text:SetPoint(
        "LEFT", check, "RIGHT", 5, 0
    )

    check:SetScript("OnClick", function(self)
        if Config.updating then return end

        if Combat() then
            RUI:Error(
                "Change settings outside combat."
            )
            Config:Refresh()
            return
        end

        -- WoW 3.3.5a may return:
        --   checked   = 1
        --   unchecked = nil
        --
        -- Never use:
        --   self:GetChecked() == true
        --
        -- That incorrectly treats 1 as false.
        --
        -- Correct:
        local enabled = not not self:GetChecked()

        setter(enabled)

        -- Refresh from the saved setting.
        -- This keeps the checkbox correct even
        -- when a module refuses or adjusts it.
        Config:Refresh()
    end)

    page.RUIControls[key] = {
        kind = "check",
        control = check,
        getter = getter
    }

    return check
end

function Config:Action(page, label, y, callback, width)
    local button = MakeButton(
        page, label, width or 200, 30
    )
    button:SetPoint("TOPLEFT", 20, -y)
    button:SetScript("OnClick", callback)
    return button
end

-- ==========================================
-- GENERAL PAGE
-- ==========================================

function Config:BuildGeneral()
    local page = self:CreatePage("general", 660)

    self:Heading(page, "General", 17)

    self:Description(
        page,
        "Manage RasfectionUI layout and interface tools.",
        51
    )

    self:Section(page, "LAYOUT MANAGEMENT", 100)

    self:Action(
        page, "Unlock Unit Frames", 145,
        function()
            if Combat() then return end

            local movers = Module("Movers")
            if movers then movers:Toggle() end
        end, 230
    )

    self:Action(
        page, "Unlock Action Bars", 190,
        function()
            local layout = Module("ActionBarLayout")
            if layout then layout:ToggleMove() end
        end, 230
    )

    self:Section(page, "INTERFACE MANAGEMENT", 255)

    self:Action(
        page, "Reload Interface", 300,
        function()
            if Combat() then
                RUI:Error("Cannot reload in combat.")
                return
            end
            ReloadUI()
        end, 230
    )

    self:Description(
        page,
        "Numeric fields accept exact values. Enter applies, Escape cancels.",
        365
    )

    return page
end

-- ==========================================
-- UNIT FRAMES FALLBACK
-- Replaced by UnitFrameOptions v2.2
-- and extended by AuraEnhancements v2.3.
-- ==========================================

function Config:BuildUnits()
    local page = self:CreatePage("units", 660)

    self:Heading(page, "Unit Frames", 17)
    self:Description(
        page,
        "Manage compact unit frames and their positions.",
        52
    )

    self:Section(page, "POSITIONING", 100)

    self:Action(
        page, "Unlock Unit Frame Positions", 145,
        function()
            if Combat() then return end

            local movers = Module("Movers")
            if movers then movers:Toggle() end
        end, 260
    )

    self:Description(
        page,
        "Individual settings load through the UnitFrameOptions module.",
        205
    )

    return page
end

-- ==========================================
-- PARTY
-- ==========================================

function Config:BuildParty()
    local page = self:CreatePage("party", 680)

    self:Heading(page, "Party Frames", 17)

    self:Description(
        page,
        "Compact party frames with one shared border.",
        52
    )

    self:Section(page, "FRAME DIMENSIONS", 100)

    self:Slider(
        page, "partyWidth", "Container width",
        150, 190, 340,
        function()
            return Config:GetSettings().partyWidth
        end,
        function(value)
            Config:SetOption("partyWidth", value)
        end
    )

    self:Slider(
        page, "partyGap", "Spacing between members",
        230, 0, 15,
        function()
            return Config:GetSettings().partyGap
        end,
        function(value)
            Config:SetOption("partyGap", value)
        end
    )

    self:Section(page, "POSITIONING", 330)

    self:Action(
        page, "Unlock Party Position", 380,
        function()
            if Combat() then return end

            local movers = Module("Movers")
            if movers then movers:Toggle() end
        end, 240
    )

    self:Description(
        page,
        "Party dimension changes require /reload.",
        440
    )

    return page
end

-- ==========================================
-- RAID
-- ==========================================

function Config:BuildRaid()
    local page = self:CreatePage("raid", 920)

    self:Heading(page, "Raid Frames", 17)

    self:Description(
        page,
        "Compact raid layout and healing indicators.",
        52
    )

    self:Section(page, "GRID LAYOUT", 100)

    self:Slider(
        page, "raidGap", "Spacing between tiles",
        150, 0, 15,
        function()
            return Config:GetSettings().raidGap
        end,
        function(value)
            Config:SetOption("raidGap", value)
        end
    )

    self:Slider(
        page, "raidRows", "Members per column",
        230, 2, 8,
        function()
            return Config:GetSettings().raidRows
        end,
        function(value)
            Config:SetOption("raidRows", value)
        end
    )

    self:Section(page, "HEALING PRIORITY", 320)

    self:Slider(
        page, "criticalHealth",
        "Critical health threshold (%)",
        370, 10, 50,
        function()
            return Config:GetSettings().criticalHealth
        end,
        function(value)
            Config:SetOption("criticalHealth", value)
        end
    )

    self:Slider(
        page, "warningHealth",
        "Warning health threshold (%)",
        450, 35, 85,
        function()
            return Config:GetSettings().warningHealth
        end,
        function(value)
            Config:SetOption("warningHealth", value)
        end
    )

    self:Section(page, "INDICATORS", 540)

    local function AddCheck(key, label, y)
        Config:Check(
            page, key, label, y,
            function()
                return Config:GetSettings()[key] == true
            end,
            function(value)
                Config:SetOption(key, value)
            end
        )
    end

    AddCheck(
        "showDispels",
        "Display dispellable debuff icons", 585
    )

    AddCheck(
        "showCritical",
        "Display health warnings", 625
    )

    AddCheck(
        "showThreat",
        "Highlight dangerous threat", 665
    )

    AddCheck(
        "showRange",
        "Fade out-of-range members", 705
    )

    self:Section(page, "TOOLS", 770)

    self:Action(
        page, "Toggle Raid Preview", 820,
        function()
            local raid = Module("RaidFrames")
            if raid and raid.TogglePreview then
                raid:TogglePreview()
            end
        end, 240
    )

    return page
end

-- ==========================================
-- ACTION BARS
-- ==========================================

function Config:BuildBars()
    local page = self:CreatePage("bars", 940)

    self:Heading(page, "Action Bars", 17)

    self:Description(
        page,
        "Configure action bars and their individual layouts.",
        52
    )

    self:Section(page, "GENERAL SETTINGS", 100)

    self:Check(
        page, "barEnabled",
        "Enable custom action bar positioning",
        145,
        function()
            local layout = Module("ActionBarLayout")
            local s = layout and layout:GetSettings()
            return s and s.enabled == true or false
        end,
        function(enabled)
            local layout = Module("ActionBarLayout")

            if layout then
                layout:SetEnabled(enabled)
            end

            Config:Refresh()
        end
    )

    self:Section(page, "SELECT ACTION BAR", 206)

    for i, info in ipairs(BAR_ORDER) do
        local id = info[1]
        local label = info[2]

        local button = MakeButton(
            page, label, 158, 32
        )

        local column = (i - 1) % 3
        local row = math.floor((i - 1) / 3)

        button:SetPoint(
            "TOPLEFT", page, "TOPLEFT",
            17 + column * 168,
            -(249 + row * 40)
        )

        button:SetScript("OnClick", function()
            Config.selectedBar = id
            Config:Refresh()
        end)

        self.barButtons[id] = button
    end

    self:Section(
        page, "SELECTED BAR OPTIONS", 357
    )

    self:Slider(
        page, "barSize", "Button size",
        407, 28, 48,
        function()
            local s = Config:GetBarSettings()
            return s and s.size or 36
        end,
        function(value)
            Config:SetBarOption("size", value)
        end
    )

    self:Slider(
        page, "barGap", "Button spacing",
        487, 0, 16,
        function()
            local s = Config:GetBarSettings()
            return s and s.gap or 4
        end,
        function(value)
            Config:SetBarOption("gap", value)
        end
    )

    self:Slider(
        page, "barColumns", "Buttons per row",
        567, 1, 12,
        function()
            local s = Config:GetBarSettings()
            return s and s.columns or 12
        end,
        function(value)
            Config:SetBarOption("columns", value)
        end
    )

    self:Section(page, "MOVEMENT AND RESET", 665)

    self:Action(
        page, "Unlock / Lock Action Bars", 710,
        function()
            local layout = Module("ActionBarLayout")
            if layout then layout:ToggleMove() end
        end, 250
    )

    self:Action(
        page, "Reset Action Bar Layout", 754,
        function()
            local layout = Module("ActionBarLayout")

            if layout then layout:Reset() end
            Config:Refresh()
        end, 250
    )

    self:Description(
        page,
        "Protected action bar changes are restricted during combat.",
        815
    )

    return page
end

-- ==========================================
-- APPEARANCE
-- ==========================================

function Config:BuildAppearance()
    local page = self:CreatePage(
        "appearance", 660
    )

    self:Heading(page, "Appearance", 17)

    self:Description(
        page,
        "Global RasfectionUI visual styling.",
        52
    )

    self:Section(page, "ACTIVE THEME", 105)

    self:Description(
        page,
        "Rasfection Metallic - Charcoal / Purple",
        155
    )

    self:Description(
        page,
        "Global colors, fonts and theme presets will be integrated here.",
        205
    )

    return page
end

-- ==========================================
-- PAGE MANAGEMENT
-- ==========================================

function Config:BuildPage(id)
    if self.pages[id] then
        return self.pages[id]
    end

    if id == "general" then
        return self:BuildGeneral()
    elseif id == "units" then
        return self:BuildUnits()
    elseif id == "party" then
        return self:BuildParty()
    elseif id == "raid" then
        return self:BuildRaid()
    elseif id == "bars" then
        return self:BuildBars()
    elseif id == "appearance" then
        return self:BuildAppearance()
    end

    return nil
end

function Config:ShowPage(id)
    if not self.window then return end

    local page = self:BuildPage(id)
    if not page then return end

    self.currentPage = id

    for otherID, otherPage in pairs(self.pages) do
        if otherID ~= id then
            otherPage:Hide()
        end
    end

    if self.scroll:GetScrollChild() ~= page then
        self.scroll:SetScrollChild(page)
    end

    page:Show()
    self.scroll:SetVerticalScroll(0)
    self:Refresh()
end

-- ==========================================
-- CONTROL REFRESH
-- ==========================================

function Config:Refresh()
    if not self.window then return end

    self.updating = true

    local page = self.pages[self.currentPage]

    if page and page.RUIControls then
        for _, entry in pairs(page.RUIControls) do
            local value

            if entry.getter then
                value = entry.getter()
            end

            if entry.kind == "slider" then
                if entry.input
                    and entry.input:HasFocus() then

                    entry.control:SetValue(
                        tonumber(value) or 0
                    )
                else
                    entry.display(value)
                end

            elseif entry.kind == "check" then
                -- Saved booleans, not numeric
                -- GetChecked() return values.
                entry.control:SetChecked(
                    value == true
                )
            end
        end
    end

    for id, button in pairs(self.navButtons) do
        if id == self.currentPage then
            button.RUIBackground:SetVertexColor(
                0.37, 0.24, 0.51, 1
            )
        else
            button.RUIBackground:SetVertexColor(
                0.18, 0.18, 0.24, 1
            )
        end
    end

    for id, button in pairs(self.barButtons) do
        if id == self.selectedBar then
            button.RUIBackground:SetVertexColor(
                0.39, 0.26, 0.54, 1
            )
        else
            button.RUIBackground:SetVertexColor(
                0.18, 0.18, 0.24, 1
            )
        end
    end

    if self.statusText then
        if Combat() then
            self.statusText:SetText(
                "Combat lockdown"
            )
            self.statusText:SetTextColor(
                1, 0.47, 0.40
            )

        elseif self.needsReload then
            self.statusText:SetText(
                "Layout settings saved - Reload to apply"
            )
            self.statusText:SetTextColor(
                1, 0.76, 0.36
            )

        else
            self.statusText:SetText(
                "Settings saved per character"
            )
            self.statusText:SetTextColor(
                0.64, 0.83, 0.68
            )
        end
    end

    self.updating = false
end

-- ==========================================
-- FOOTER
-- ==========================================

function Config:CreateFooter()
    local status = MakeText(
        self.window,
        "Settings saved per character",
        10, 0.64, 0.83, 0.68
    )

    status:SetPoint("BOTTOMLEFT", 28, 31)
    self.statusText = status

    local reload = MakeButton(
        self.window, "Apply / Reload",
        140, 28
    )

    reload:SetPoint("BOTTOMRIGHT", -28, 23)

    reload:SetScript("OnClick", function()
        if Combat() then
            RUI:Error("Cannot reload during combat.")
            return
        end
        ReloadUI()
    end)
end

-- ==========================================
-- OPEN / CLOSE / INITIALIZE
-- ==========================================

function Config:Open()
    if Combat() then
        RUI:Error("Open configuration outside combat.")
        return
    end

    local window = self:CreateWindow()
    self:ShowPage(self.currentPage)

    window:Show()
    window:Raise()
end

function Config:Close()
    if self.window then
        self.window:Hide()
    end
end

function Config:Toggle()
    if self.window and self.window:IsShown() then
        self:Close()
    else
        self:Open()
    end
end

function Config:Initialize()
    if self.initialized then return end

    self:GetSettings()
    self:ApplySettings(true)

    self.initialized = true

    RUI:Debug(
        "Global Configuration v2.1.2 initialized."
    )
end

SLASH_RUIGROUP1 = "/ruigroup"
SLASH_RUICONFIG1 = "/ruiconfig"

SlashCmdList["RUIGROUP"] = function()
    Config:Toggle()
end

SlashCmdList["RUICONFIG"] = function()
    Config:Toggle()
end

RUI:RegisterModule("Config", Config)
