--[[
    RasfectionUI
    Core/Theme.lua

    Version: 0.1.0
    Client: WoW WotLK 3.3.5a (12340)

    RASFECTION UI THEME ENGINE

    Features:
      - Custom RaisedBorder.tga support
      - Consistent dark backgrounds
      - Metallic 3D borders
      - Purple accent colors
      - Reusable UI panels
      - Reusable status bars
      - Reusable icon buttons
      - Text styling
      - Runtime theme refresh
      - Movable theme preview
      - Theme preview commands

    Requires:
      Core/Core.lua
      Core/Database.lua
]]

local RUI = _G.RasfectionUI

if not RUI then
    return
end

local Theme = {}

Theme.version = "0.1.0"

-- ==========================================
-- MEDIA
-- ==========================================

Theme.media = {
    border = "Interface\\AddOns\\RasfectionUI\\Media\\RaisedBorder",
    background = "Interface\\ChatFrame\\ChatFrameBackground",
    statusbar = "Interface\\TargetingFrame\\UI-StatusBar",
    white = "Interface\\Buttons\\WHITE8X8",
    font = "Fonts\\FRIZQT__.TTF"
}

-- ==========================================
-- DEFAULT COLORS
-- ==========================================

Theme.defaults = {
    background = { 0.05, 0.06, 0.08, 0.95 },
    border = { 1.00, 1.00, 1.00, 1.00 },
    accent = { 0.61, 0.35, 1.00, 1.00 },
    text = { 1.00, 1.00, 1.00, 1.00 },

    secondaryText = { 0.65, 0.69, 0.76, 1.00 },
    highlight = { 0.76, 0.60, 1.00, 1.00 },

    health = { 0.20, 0.75, 0.36, 1.00 },
    power = { 0.26, 0.48, 0.94, 1.00 },

    button = { 0.11, 0.13, 0.17, 0.95 }
}

-- ==========================================
-- INTERNAL HELPERS
-- ==========================================

local function CopyColor(color)
    if type(color) ~= "table" then
        return { 1, 1, 1, 1 }
    end

    return {
        color[1] or 1,
        color[2] or 1,
        color[3] or 1,
        color[4] or 1
    }
end

local function Clamp(value, low, high)
    if type(value) ~= "number" then
        return low
    end

    if value < low then
        return low
    end

    if value > high then
        return high
    end

    return value
end

local function IsCombatLocked()
    return InCombatLockdown and InCombatLockdown()
end

-- ==========================================
-- SETTINGS
-- ==========================================

function Theme:GetSettings()
    local database = RUI:GetModule("Database")

    if database and database.GetTheme then
        local settings = database:GetTheme()

        if type(settings) == "table" then
            return settings
        end
    end

    return nil
end

function Theme:GetColor(name)
    local settings = self:GetSettings()

    if settings then
        local value = settings[name]

        if type(value) == "table" then
            return CopyColor(value)
        end
    end

    return CopyColor(
        self.defaults[name] or { 1, 1, 1, 1 }
    )
end

function Theme:GetBorderSize()
    local settings = self:GetSettings()

    if settings
        and type(settings.borderSize) == "number" then
        return math.floor(
            Clamp(settings.borderSize, 8, 48)
        )
    end

    return 16
end

function Theme:GetFont()
    local settings = self:GetSettings()

    if settings
        and type(settings.font) == "string"
        and settings.font ~= "" then
        return settings.font
    end

    return self.media.font
end

-- ==========================================
-- BORDER BACKDROP
-- ==========================================

function Theme:CreateBackdrop(borderSize, insets)
    borderSize = borderSize or self:GetBorderSize()

    local inset = insets

    if type(inset) ~= "number" then
        inset = math.floor(borderSize * 0.25)
    end

    return {
        bgFile = self.media.background,
        edgeFile = self.media.border,

        tile = false,
        tileSize = 0,
        edgeSize = borderSize,

        insets = {
            left = inset,
            right = inset,
            top = inset,
            bottom = inset
        }
    }
end

-- ==========================================
-- APPLY THEME TO A FRAME
-- ==========================================

function Theme:Apply(frame, options)
    if not frame then
        return false
    end

    if not frame.SetBackdrop then
        return false
    end

    if IsCombatLocked()
        and frame.IsProtected
        and frame:IsProtected() then
        return false
    end

    options = options or {}

    local borderSize = options.borderSize
        or self:GetBorderSize()

    frame:SetBackdrop(
        self:CreateBackdrop(
            borderSize,
            options.insets
        )
    )

    local backgroundColor = options.backgroundColor
        or self:GetColor("background")

    local borderColor = options.borderColor
        or self:GetColor("border")

    frame:SetBackdropColor(
        unpack(backgroundColor)
    )

    frame:SetBackdropBorderColor(
        unpack(borderColor)
    )

    frame.RUIThemed = true
    frame.RUIThemeOptions = options

    self.frames = self.frames or
        setmetatable({}, { __mode = "k" })

    self.frames[frame] = true

    return true
end

-- ==========================================
-- REFRESH THEMED FRAMES
-- ==========================================

function Theme:Refresh()
    if not self.frames then
        return
    end

    for frame in pairs(self.frames) do
        if frame and frame.RUIThemed then
            self:Apply(
                frame,
                frame.RUIThemeOptions
            )
        end
    end

    RUI:Debug("Theme refresh completed.")
end

-- ==========================================
-- PANEL FACTORY
-- ==========================================

function Theme:CreatePanel(
    name,
    parent,
    width,
    height,
    options
)
    parent = parent or UIParent

    local frame = CreateFrame(
        "Frame",
        name,
        parent
    )

    frame:SetWidth(width or 250)
    frame:SetHeight(height or 150)

    frame:SetFrameStrata("MEDIUM")

    self:Apply(frame, options)

    return frame
end

-- ==========================================
-- TEXT FACTORY
-- ==========================================

function Theme:CreateText(
    parent,
    text,
    size,
    color,
    justify
)
    local label = parent:CreateFontString(
        nil,
        "OVERLAY"
    )

    label:SetFont(
        self:GetFont(),
        size or 12,
        "OUTLINE"
    )

    label:SetText(text or "")

    label:SetTextColor(
        unpack(color or self:GetColor("text"))
    )

    label:SetJustifyH(justify or "LEFT")

    return label
end

-- ==========================================
-- STATUS BAR FACTORY
-- ==========================================

function Theme:CreateStatusBar(
    name,
    parent,
    width,
    height,
    color
)
    local holder = CreateFrame(
        "Frame",
        name,
        parent
    )

    holder:SetWidth(width or 200)
    holder:SetHeight(height or 20)

    self:Apply(holder, {
        borderSize = 12,
        insets = 3,
        backgroundColor = {
            0.03, 0.04, 0.06, 0.95
        }
    })

    local bar = CreateFrame(
        "StatusBar",
        nil,
        holder
    )

    bar:SetPoint("TOPLEFT", 6, -6)
    bar:SetPoint("BOTTOMRIGHT", -6, 6)

    bar:SetStatusBarTexture(
        self.media.statusbar
    )

    bar:SetMinMaxValues(0, 100)
    bar:SetValue(100)

    local barColor = color
        or self:GetColor("health")

    bar:SetStatusBarColor(
        unpack(barColor)
    )

    local text = self:CreateText(
        holder,
        "100%",
        11,
        self:GetColor("text"),
        "CENTER"
    )

    text:SetPoint("CENTER", holder, "CENTER")

    holder.bar = bar
    holder.text = text

    function holder:SetProgress(value, maximum)
        maximum = maximum or 100

        if maximum <= 0 then
            maximum = 100
        end

        value = Clamp(value, 0, maximum)

        self.bar:SetMinMaxValues(0, maximum)
        self.bar:SetValue(value)

        local percent = math.floor(
            (value / maximum) * 100 + 0.5
        )

        self.text:SetText(
            tostring(percent) .. "%"
        )
    end

    return holder
end

-- ==========================================
-- ICON BUTTON FACTORY
-- ==========================================

function Theme:CreateIconButton(
    name,
    parent,
    size,
    texture
)
    local button = CreateFrame(
        "Button",
        name,
        parent
    )

    button:SetWidth(size or 40)
    button:SetHeight(size or 40)

    self:Apply(button, {
        borderSize = 12,
        insets = 2,
        backgroundColor =
            self:GetColor("button")
    })

    local icon = button:CreateTexture(
        nil,
        "ARTWORK"
    )

    icon:SetPoint("TOPLEFT", 5, -5)
    icon:SetPoint("BOTTOMRIGHT", -5, 5)

    icon:SetTexture(
        texture or
        "Interface\\Icons\\INV_Misc_QuestionMark"
    )

    icon:SetTexCoord(
        0.08, 0.92,
        0.08, 0.92
    )

    button.icon = icon

    local highlight = button:CreateTexture(
        nil,
        "HIGHLIGHT"
    )

    highlight:SetTexture(self.media.white)

    highlight:SetPoint(
        "TOPLEFT",
        button,
        "TOPLEFT",
        5,
        -5
    )

    highlight:SetPoint(
        "BOTTOMRIGHT",
        button,
        "BOTTOMRIGHT",
        -5,
        5
    )

    highlight:SetVertexColor(
        0.61, 0.35, 1.0, 0.2
    )

    button.highlight = highlight

    return button
end

-- ==========================================
-- PANEL HEADER FACTORY
-- ==========================================

function Theme:CreateHeader(
    parent,
    title,
    height
)
    local header = CreateFrame(
        "Frame",
        nil,
        parent
    )

    header:SetHeight(height or 32)

    header:SetPoint(
        "TOPLEFT",
        parent,
        "TOPLEFT",
        9,
        -9
    )

    header:SetPoint(
        "TOPRIGHT",
        parent,
        "TOPRIGHT",
        -9,
        -9
    )

    local background = header:CreateTexture(
        nil,
        "BACKGROUND"
    )

    background:SetAllPoints(header)
    background:SetTexture(self.media.white)
    background:SetVertexColor(
        0.08, 0.09, 0.13, 0.98
    )

    local titleText = self:CreateText(
        header,
        title or "RasfectionUI",
        13,
        self:GetColor("text"),
        "LEFT"
    )

    titleText:SetPoint(
        "LEFT",
        header,
        "LEFT",
        12,
        0
    )

    local accent = header:CreateTexture(
        nil,
        "ARTWORK"
    )

    accent:SetTexture(self.media.white)

    accent:SetHeight(2)

    accent:SetPoint(
        "BOTTOMLEFT",
        header,
        "BOTTOMLEFT"
    )

    accent:SetPoint(
        "BOTTOMRIGHT",
        header,
        "BOTTOMRIGHT"
    )

    accent:SetVertexColor(
        unpack(self:GetColor("accent"))
    )

    header.title = titleText

    return header
end

-- ==========================================
-- DEMONSTRATION WINDOW
-- ==========================================

function Theme:CreatePreview()
    if self.preview then
        return self.preview
    end

    local preview = self:CreatePanel(
        "RasfectionUIThemePreview",
        UIParent,
        430,
        315,
        {
            borderSize = 24,
            insets = 6
        }
    )

    preview:SetPoint("CENTER")
    preview:SetFrameStrata("DIALOG")

    preview:SetMovable(true)
    preview:EnableMouse(true)
    preview:RegisterForDrag("LeftButton")

    preview:SetClampedToScreen(true)

    preview:SetScript("OnDragStart", function(self)
        if not IsCombatLocked() then
            self:StartMoving()
        end
    end)

    preview:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)

    self:CreateHeader(
        preview,
        "RASFECTION UI - THEME PREVIEW",
        35
    )

    -- ======================================
    -- CLOSE BUTTON
    -- ======================================

    local close = CreateFrame(
        "Button",
        nil,
        preview
    )

    close:SetWidth(25)
    close:SetHeight(25)

    close:SetPoint(
        "TOPRIGHT",
        preview,
        "TOPRIGHT",
        -18,
        -14
    )

    local closeText = self:CreateText(
        close,
        "X",
        13,
        self:GetColor("accent"),
        "CENTER"
    )

    closeText:SetPoint("CENTER")

    close:SetScript("OnClick", function()
        preview:Hide()
    end)

    -- ======================================
    -- DESCRIPTION
    -- ======================================

    local description = self:CreateText(
        preview,
        "Custom raised metallic borders",
        11,
        self:GetColor("secondaryText"),
        "LEFT"
    )

    description:SetPoint(
        "TOPLEFT",
        preview,
        "TOPLEFT",
        24,
        -62
    )

    -- ======================================
    -- SAMPLE PLAYER FRAME
    -- ======================================

    local playerFrame = self:CreatePanel(
        nil,
        preview,
        382,
        85,
        {
            borderSize = 16,
            insets = 4
        }
    )

    playerFrame:SetPoint(
        "TOP",
        preview,
        "TOP",
        0,
        -88
    )

    local playerName = self:CreateText(
        playerFrame,
        UnitName("player") or "Player",
        12
    )

    playerName:SetPoint(
        "TOPLEFT",
        playerFrame,
        "TOPLEFT",
        15,
        -12
    )

    local level = UnitLevel("player") or 80

    local levelText = self:CreateText(
        playerFrame,
        "LEVEL " .. tostring(level),
        10,
        self:GetColor("secondaryText"),
        "RIGHT"
    )

    levelText:SetPoint(
        "TOPRIGHT",
        playerFrame,
        "TOPRIGHT",
        -15,
        -14
    )

    local healthBar = self:CreateStatusBar(
        nil,
        playerFrame,
        348,
        29,
        self:GetColor("health")
    )

    healthBar:SetPoint(
        "TOP",
        playerFrame,
        "TOP",
        0,
        -37
    )

    healthBar:SetProgress(82, 100)

    -- ======================================
    -- SAMPLE ACTION BUTTONS
    -- ======================================

    local actionTitle = self:CreateText(
        preview,
        "ACTION BUTTON STYLE",
        11,
        self:GetColor("secondaryText")
    )

    actionTitle:SetPoint(
        "TOPLEFT",
        preview,
        "TOPLEFT",
        24,
        -188
    )

    local icons = {
        "Interface\\Icons\\Spell_Holy_SealOfRighteousness",
        "Interface\\Icons\\Ability_Warrior_BattleShout",
        "Interface\\Icons\\Spell_DeathKnight_DeathStrike",
        "Interface\\Icons\\Spell_Nature_Lightning",
        "Interface\\Icons\\Spell_Arcane_Arcane01",
        "Interface\\Icons\\INV_Misc_QuestionMark"
    }

    for i = 1, 6 do
        local button = self:CreateIconButton(
            nil,
            preview,
            45,
            icons[i]
        )

        button:SetPoint(
            "TOPLEFT",
            preview,
            "TOPLEFT",
            25 + ((i - 1) * 64),
            -212
        )
    end

    -- ======================================
    -- FOOTER
    -- ======================================

    local footer = self:CreateText(
        preview,
        "RasfectionUI v" .. RUI.version ..
        "   |   Drag to move",
        10,
        self:GetColor("secondaryText"),
        "CENTER"
    )

    footer:SetPoint(
        "BOTTOM",
        preview,
        "BOTTOM",
        0,
        16
    )

    self.preview = preview

    return preview
end

-- ==========================================
-- PREVIEW CONTROL
-- ==========================================

function Theme:ShowPreview()
    local preview = self:CreatePreview()

    if preview then
        preview:Show()
        preview:Raise()
    end
end

function Theme:HidePreview()
    if self.preview then
        self.preview:Hide()
    end
end

function Theme:TogglePreview()
    if self.preview and self.preview:IsShown() then
        self:HidePreview()
    else
        self:ShowPreview()
    end
end

-- ==========================================
-- THEME SLASH COMMAND
-- ==========================================

SLASH_RUITHEME1 = "/ruitheme"

SlashCmdList["RUITHEME"] = function(message)
    message = string.lower(message or "")

    if message == "hide" then
        Theme:HidePreview()
    elseif message == "refresh" then
        Theme:Refresh()
        RUI:Success("Theme refreshed.")
    elseif message == "show" then
        Theme:ShowPreview()
    else
        Theme:TogglePreview()
    end
end

-- ==========================================
-- INITIALIZATION
-- ==========================================

function Theme:Initialize()
    self.frames = setmetatable(
        {},
        { __mode = "k" }
    )

    RUI:Debug("Theme engine initialized.")

    -- Display the first visual milestone.
    -- self:ShowPreview()

    RUI:Success(
        "Theme engine ready. Type /ruitheme."
    )
end

-- ==========================================
-- REGISTER MODULE
-- ==========================================

RUI:RegisterModule("Theme", Theme)
