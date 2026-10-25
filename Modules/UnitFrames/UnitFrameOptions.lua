
--[[
 RasfectionUI - UnitFrameOptions.lua
 Version 2.2.0 | WotLK 3.3.5a / 12340

 Expanded ElvUI-style Unit Frames configuration.

 Six selectable unit frames.
 Exact numeric slider inputs supplied by
 GroupConfig.lua v2.1.1.

 Adds:
   Frame scale
   Health bar coloring mode
   Custom health RGB
   Power bar coloring mode
   Custom power RGB
   Power bar visibility
   Three font size controls
   Aura placement and icon spacing

 Preserves:
   Width / height
   Portrait / aura toggles
   Aura size / count
   TargetTarget / FocusTarget toggles
   Saved settings / mover locations
   Combat-safe layout changes
]]

local RUI = _G.RasfectionUI
if not RUI then return end

local Options = {}
Options.version = "2.2.0"
Options.initialized = false
Options.selected = "PlayerFrame"
Options.selectorButtons = {}
Options.modeButtons = {}

local ENTRIES = {
    {"PlayerFrame", "Player"},
    {"TargetFrame", "Target"},
    {"FocusFrame", "Focus"},
    {"PetFrame", "Pet"},
    {"TargetTargetFrame", "Target of Target"},
    {"FocusTargetFrame", "Focus Target"}
}

local DEFAULTS = {
    PlayerFrame = {
        width = 310, height = 74,
        portrait = true, auras = true,
        auraSize = 19, auraCount = 8,
        nameFont = 12
    },
    TargetFrame = {
        width = 310, height = 74,
        portrait = true, auras = true,
        auraSize = 19, auraCount = 8,
        nameFont = 12
    },
    FocusFrame = {
        width = 275, height = 70,
        portrait = true, auras = true,
        auraSize = 19, auraCount = 6,
        nameFont = 12
    },
    PetFrame = {
        width = 205, height = 49,
        portrait = false, auras = false,
        auraSize = 19, auraCount = 8,
        nameFont = 10
    },
    TargetTargetFrame = {
        width = 205, height = 49,
        portrait = false, auras = false,
        auraSize = 19, auraCount = 8,
        nameFont = 10
    },
    FocusTargetFrame = {
        width = 205, height = 49,
        portrait = false, auras = false,
        auraSize = 19, auraCount = 8,
        nameFont = 10
    }
}

local EXTRA_DEFAULTS = {
    scale = 100,
    showPower = true,
    healthMode = "health",
    powerMode = "resource",
    valueFont = 9,
    levelFont = 10,
    auraPosition = "BELOW",
    auraGap = 2
}

local VISIBILITY = {
    targettarget = "TargetTargetFrame",
    focustarget = "FocusTargetFrame"
}

local function Combat()
    return InCombatLockdown
        and InCombatLockdown()
end

local function Clamp(v, lo, hi, fallback)
    v = tonumber(v)
    if not v or v ~= v
       or v == math.huge or v == -math.huge then
        return fallback
    end

    return math.floor(
        math.max(lo, math.min(hi, v)) + 0.5
    )
end

local function UI()
    return RUI:GetModule("Config")
end

function Options:GetProfile()
    local db = RUI:GetModule("Database")
    return db and db.GetProfile
        and db:GetProfile() or nil
end

function Options:GetLayouts()
    local profile = self:GetProfile()
    if not profile then return nil end

    if type(profile.settings) ~= "table" then
        profile.settings = {}
    end

    if type(profile.settings.unitFrameLayout)
       ~= "table" then
        profile.settings.unitFrameLayout = {}
    end

    local layouts = profile.settings.unitFrameLayout

    for id, defaults in pairs(DEFAULTS) do
        if type(layouts[id]) ~= "table" then
            layouts[id] = {}
        end

        local s = layouts[id]

        for k, value in pairs(defaults) do
            if type(s[k]) ~= type(value) then
                s[k] = value
            end
        end

        for k, value in pairs(EXTRA_DEFAULTS) do
            if type(s[k]) ~= type(value) then
                s[k] = value
            end
        end

        if type(s.healthColor) ~= "table" then
            s.healthColor = {35, 165, 90}
        end

        if type(s.powerColor) ~= "table" then
            s.powerColor = {45, 110, 235}
        end

        s.width = Clamp(
            s.width, 130, 500, defaults.width
        )
        s.height = Clamp(
            s.height, 42, 150, defaults.height
        )
        s.scale = Clamp(s.scale, 50, 150, 100)
        s.auraSize = Clamp(s.auraSize, 14, 30, 19)
        s.auraCount = Clamp(
            s.auraCount, 1, 12, defaults.auraCount
        )
        s.auraGap = Clamp(s.auraGap, 0, 12, 2)
        s.nameFont = Clamp(
            s.nameFont, 8, 20, defaults.nameFont
        )
        s.valueFont = Clamp(s.valueFont, 7, 18, 9)
        s.levelFont = Clamp(s.levelFont, 7, 18, 10)

        for i = 1, 3 do
            s.healthColor[i] = Clamp(
                s.healthColor[i], 0, 255,
                ({35, 165, 90})[i]
            )
            s.powerColor[i] = Clamp(
                s.powerColor[i], 0, 255,
                ({45, 110, 235})[i]
            )
        end

        if s.healthMode ~= "health"
           and s.healthMode ~= "class"
           and s.healthMode ~= "custom" then
            s.healthMode = "health"
        end

        if s.powerMode ~= "resource"
           and s.powerMode ~= "custom" then
            s.powerMode = "resource"
        end

        if s.auraPosition ~= "ABOVE" then
            s.auraPosition = "BELOW"
        end

        if not defaults.portrait then
            s.portrait = false
        end

        if not defaults.auras then
            s.auras = false
        end
    end

    return layouts
end

-- Compatibility with older integrations.
function Options:GetLayoutSettings()
    return self:GetLayouts()
end

function Options:GetSelectedSettings()
    local layouts = self:GetLayouts()
    return layouts and layouts[self.selected]
end

function Options:GetFrameValue(key)
    local s = self:GetSelectedSettings()
    if not s then return 0 end
    if s[key] == nil then return 0 end
    return s[key]
end

function Options:GetFrameBoolean(key)
    local s = self:GetSelectedSettings()
    return s and s[key] == true or false
end

function Options:GetVisibilitySettings()
    local profile = self:GetProfile()
    if not profile then return nil end

    profile.settings = profile.settings or {}

    if type(profile.settings.unitFrameVisibility)
       ~= "table" then
        profile.settings.unitFrameVisibility = {}
    end

    local s = profile.settings.unitFrameVisibility

    if type(s.targettarget) ~= "boolean" then
        s.targettarget = true
    end
    if type(s.focustarget) ~= "boolean" then
        s.focustarget = true
    end

    return s
end

function Options:IsEnabled(id)
    local s = self:GetVisibilitySettings()
    return s and s[id] == true or false
end

function Options:GetFrame(id)
    local module = RUI:GetModule(
        VISIBILITY[id] or id
    )
    return module and module.frame
end

function Options:ApplyVisibility(id)
    if Combat() then return false end
    local s = self:GetVisibilitySettings()
    local frame = self:GetFrame(id)
    if not s or not frame then return false end

    if s[id] then
        RegisterUnitWatch(frame)
    else
        UnregisterUnitWatch(frame)
        frame:Hide()
    end
    return true
end

function Options:ApplyAllVisibility()
    if Combat() then return false end
    for id in pairs(VISIBILITY) do
        self:ApplyVisibility(id)
    end
    return true
end

function Options:SetEnabled(id, enabled)
    if not VISIBILITY[id] or Combat() then
        if Combat() then
            RUI:Error("Change visibility outside combat.")
        end
        self:RefreshConfig()
        return false
    end

    local s = self:GetVisibilitySettings()
    if not s then return false end

    s[id] = enabled == true
    self:ApplyVisibility(id)
    self:RefreshConfig()
    return true
end

function Options:RefreshConfig()
    local ui = UI()
    if ui and ui.Refresh then ui:Refresh() end
end

function Options:ApplySelectedLayout()
    if Combat() then return false end

    local module = RUI:GetModule(self.selected)
    if not module or not module.initialized then
        return false
    end

    if module.ApplyLayout then
        module:ApplyLayout()
    end
    if module.ApplyAuraLayout and module.auraHolder then
        module:ApplyAuraLayout()
    end
    if module.Update then
        module:Update()
    end

    return true
end

function Options:SetFrameOption(key, value)
    if Combat() then
        RUI:Error(
            "Appearance changes are locked in combat."
        )
        self:RefreshConfig()
        return false
    end

    local s = self:GetSelectedSettings()
    local d = DEFAULTS[self.selected]
    if not s or not d then return false end

    local ranges = {
        width = {130, 500},
        height = {42, 150},
        scale = {50, 150},
        auraSize = {14, 30},
        auraCount = {1, 12},
        auraGap = {0, 12},
        nameFont = {8, 20},
        valueFont = {7, 18},
        levelFont = {7, 18}
    }

    if ranges[key] then
        local r = ranges[key]
        s[key] = Clamp(value, r[1], r[2], s[key])

    elseif key == "portrait" then
        s.portrait = d.portrait and value == true or false

    elseif key == "auras" then
        s.auras = d.auras and value == true or false

    elseif key == "showPower" then
        s.showPower = value == true

    elseif key == "healthMode" then
        if value == "health"
           or value == "class"
           or value == "custom" then
            s.healthMode = value
        end

    elseif key == "powerMode" then
        if value == "resource"
           or value == "custom" then
            s.powerMode = value
        end

    elseif key == "auraPosition" then
        if value == "ABOVE"
           or value == "BELOW" then
            s.auraPosition = value
        end

    else
        return false
    end

    self:ApplySelectedLayout()
    self:RefreshConfig()
    return true
end

function Options:SetColorOption(group, index, value)
    if Combat() then
        RUI:Error("Edit colors outside combat.")
        self:RefreshConfig()
        return false
    end

    local s = self:GetSelectedSettings()
    if not s or index < 1 or index > 3 then
        return false
    end

    local key = group == "health"
        and "healthColor"
        or "powerColor"

    s[key][index] = Clamp(
        value, 0, 255, s[key][index]
    )

    self:ApplySelectedLayout()
    self:RefreshConfig()
    return true
end

function Options:SelectFrame(id)
    if not DEFAULTS[id] then return end
    self.selected = id
    self:RefreshConfig()
end

function Options:RefreshSelection()
    for id, button in pairs(
        self.selectorButtons or {}
    ) do
        if button.RUIBackground then
            if id == self.selected then
                button.RUIBackground:SetVertexColor(
                    0.39, 0.26, 0.54, 1
                )
            else
                button.RUIBackground:SetVertexColor(
                    0.18, 0.18, 0.24, 1
                )
            end
        end
    end

    local s = self:GetSelectedSettings()
    if not s then return end

    for _, entry in pairs(self.modeButtons or {}) do
        local active =
            s[entry.key] == entry.value

        entry.button.RUIBackground:SetVertexColor(
            active and 0.39 or 0.18,
            active and 0.26 or 0.18,
            active and 0.54 or 0.24,
            1
        )
    end
end

-- ==========================================
-- CONFIGURATION PAGE
-- ==========================================

function Options:InstallConfigPage()
    local config = UI()
    if not config then return false end

    config.BuildUnits = function(ui)
        local page = ui:CreatePage("units", 2010)

        ui:Heading(page, "Unit Frames", 17)
        ui:Description(
            page,
            "Customize each compact unit frame independently.",
            52
        )

        ui:Section(page, "SELECT FRAME", 100)

        local positions = {
            {17,145}, {190,145}, {363,145},
            {17,187}, {190,187}, {363,187}
        }

        Options.selectorButtons = {}
        Options.modeButtons = {}

        for i, entry in ipairs(ENTRIES) do
            local id, label = entry[1], entry[2]
            local p = positions[i]

            local button = ui:Action(
                page, label, p[2],
                function()
                    Options:SelectFrame(id)
                end, 160
            )

            button:ClearAllPoints()
            button:SetPoint(
                "TOPLEFT", page, "TOPLEFT",
                p[1], -p[2]
            )
            Options.selectorButtons[id] = button
        end

        local function Numeric(key)
            return function()
                local s = Options:GetSelectedSettings()
                return s and s[key] or 0
            end
        end

        local function Bool(key)
            return function()
                return Options:GetFrameBoolean(key)
            end
        end

        local function Set(key)
            return function(value)
                Options:SetFrameOption(key, value)
            end
        end

        local function Number(
            key, label, y, low, high
        )
            ui:Slider(
                page, key, label, y, low, high,
                Numeric(key), Set(key)
            )
        end

        local function Check(
            key, label, y
        )
            ui:Check(
                page, key, label, y,
                Bool(key), Set(key)
            )
        end

        local function ModeButton(
            label, key, value, x, y, width
        )
            local button = ui:Action(
                page, label, y,
                function()
                    Options:SetFrameOption(
                        key, value
                    )
                end,
                width or 150
            )
            button:ClearAllPoints()
            button:SetPoint(
                "TOPLEFT", page, "TOPLEFT",
                x, -y
            )

            table.insert(Options.modeButtons, {
                button = button,
                key = key,
                value = value
            })
        end

        local function ColorControl(
            group, label, y
        )
            ui:Section(page, label, y)

            local key = group .. "Color"
            local channels = {"Red", "Green", "Blue"}

            for i = 1, 3 do
                local index = i
                local yy = y + 46 + (i - 1) * 75

                ui:Slider(
                    page,
                    key .. index,
                    channels[i] .. " (0-255)",
                    yy, 0, 255,
                    function()
                        local s =
                            Options:GetSelectedSettings()

                        return s and s[key]
                            and s[key][index] or 0
                    end,
                    function(value)
                        Options:SetColorOption(
                            group, index, value
                        )
                    end
                )
            end
        end

        -- DIMENSIONS
        ui:Section(page, "FRAME DIMENSIONS", 250)
        Number("width", "Frame width", 300, 130, 500)
        Number("height", "Frame height", 380, 42, 150)
        Number("scale", "Frame scale (%)", 460, 50, 150)

        -- PORTRAIT / RESOURCES
        ui:Section(
            page, "PORTRAIT AND RESOURCE BAR", 545
        )
        Check("portrait", "Show portrait", 590)
        Check("showPower", "Show power bar", 630)

        -- HEALTH MODE
        ui:Section(page, "HEALTH BAR COLOR", 700)

        ModeButton(
            "Health Based", "healthMode",
            "health", 17, 745, 155
        )
        ModeButton(
            "Class / Reaction", "healthMode",
            "class", 190, 745, 155
        )
        ModeButton(
            "Custom RGB", "healthMode",
            "custom", 363, 745, 155
        )

        ui:Description(
            page,
            "Custom RGB values apply when Custom RGB is selected.",
            787
        )

        ColorControl("health", "CUSTOM HEALTH COLOR", 835)

        -- POWER MODE
        ui:Section(page, "POWER BAR COLOR", 1150)

        ModeButton(
            "Resource Color", "powerMode",
            "resource", 17, 1195, 230
        )
        ModeButton(
            "Custom RGB", "powerMode",
            "custom", 263, 1195, 230
        )

        ColorControl("power", "CUSTOM POWER COLOR", 1270)

        -- FONT SIZES
        ui:Section(page, "TEXT AND FONTS", 1580)
        Number(
            "nameFont", "Name font size",
            1625, 8, 20
        )
        Number(
            "valueFont", "Health / power text size",
            1705, 7, 18
        )
        Number(
            "levelFont", "Level text size",
            1785, 7, 18
        )

        -- AURA SETTINGS
        -- Separate long section after fonts.
        ui:Section(page, "AURAS", 1885)

        -- The page grows to accommodate
        -- these controls and remains scrollable.
        page:SetHeight(2550)

        Check(
            "auras", "Show buffs and debuffs", 1930
        )
        Number(
            "auraSize", "Aura icon size",
            1985, 14, 30
        )
        Number(
            "auraCount", "Auras per row",
            2065, 1, 12
        )
        Number(
            "auraGap", "Aura icon spacing",
            2145, 0, 12
        )

        ui:Section(
            page, "AURA POSITION", 2235
        )

        ModeButton(
            "Above Frame", "auraPosition",
            "ABOVE", 17, 2280, 230
        )
        ModeButton(
            "Below Frame", "auraPosition",
            "BELOW", 263, 2280, 230
        )

        -- SECONDARY FRAME TOGGLES
        ui:Section(
            page, "SECONDARY FRAME VISIBILITY", 2350
        )

        ui:Check(
            page, "ufTargetTarget",
            "Enable Target-of-Target",
            2395,
            function()
                return Options:IsEnabled(
                    "targettarget"
                )
            end,
            function(value)
                Options:SetEnabled(
                    "targettarget", value
                )
            end
        )

        ui:Check(
            page, "ufFocusTarget",
            "Enable Focus Target",
            2435,
            function()
                return Options:IsEnabled(
                    "focustarget"
                )
            end,
            function(value)
                Options:SetEnabled(
                    "focustarget", value
                )
            end
        )

        page:SetHeight(2650)

        ui:Section(page, "POSITIONING", 2510)
        ui:Action(
            page,
            "Unlock Unit Frame Positions",
            2550,
            function()
                if Combat() then
                    RUI:Error(
                        "Cannot unlock frames in combat."
                    )
                    return
                end

                local movers =
                    RUI:GetModule("Movers")
                if movers then
                    movers:Toggle()
                end
            end,
            260
        )

        Options:RefreshSelection()
        return page
    end

    if not config.RUIUnitRefreshWrapped then
        local oldRefresh = config.Refresh

        config.Refresh = function(ui, ...)
            if oldRefresh then
                oldRefresh(ui, ...)
            end
            Options:RefreshSelection()
        end

        config.RUIUnitRefreshWrapped = true
    end

    return true
end

-- ==========================================
-- SLASH COMMANDS
-- ==========================================

SLASH_RUIUNITS1 = "/ruiunits"

SlashCmdList["RUIUNITS"] = function(message)
    local command, value = string.match(
        string.lower(tostring(message or "")),
        "^%s*(%S*)%s*(%S*)"
    )

    local id
    if command == "tot"
       or command == "targettarget" then
        id = "targettarget"
    elseif command == "ft"
       or command == "focustarget" then
        id = "focustarget"
    end

    if id then
        if value == "on" then
            Options:SetEnabled(id, true)
        elseif value == "off" then
            Options:SetEnabled(id, false)
        else
            Options:SetEnabled(
                id, not Options:IsEnabled(id)
            )
        end
        return
    end

    RUI:Print("/ruiunits tot on/off")
    RUI:Print("/ruiunits ft on/off")
    RUI:Print("Use /rui config for appearance settings.")
end

-- ==========================================
-- INITIALIZATION
-- ==========================================

function Options:Initialize()
    if self.initialized then return end

    self:GetLayouts()
    self:GetVisibilitySettings()
    self:InstallConfigPage()

    local controller = CreateFrame(
        "Frame",
        "RasfectionUIUnitFrameOptionsController",
        UIParent
    )

    controller:RegisterEvent("PLAYER_ENTERING_WORLD")
    controller:RegisterEvent("PLAYER_REGEN_ENABLED")

    controller:SetScript("OnEvent", function()
        if not Combat() then
            Options:ApplyAllVisibility()
        end
    end)

    self.controller = controller
    self.initialized = true
    self:ApplyAllVisibility()

    RUI:Success(
        "Unit Frame Appearance v2.2 initialized."
    )
end

RUI:RegisterModule("UnitFrameOptions", Options)
