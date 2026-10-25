
--[[
 RasfectionUI
 Modules/ActionBars/ActionBars.lua

 Version 1.5.0 - Border Alignment Fix
 World of Warcraft 3.3.5a / Build 12340

 FIXES:
 - Metallic border visually aligned with icon edges
 - Icon normalized to button bounds
 - Removes the unwanted dark gap
 - Border follows button resizing
 - Supports adjustable border overhang
 - Preserves original texture coordinates
 - Restores original geometry when disabled

 PRESERVED:
 - Blizzard secure action buttons
 - Main and secondary bars
 - Pet and stance bars
 - Cooldowns and action paging
 - Keybindings and hotkeys
 - Original button click handling
 - ActionBarLayout integration
 - ActionBarVisuals v2.9 integration
 - Global appearance colors
 - Per-character saved settings

 No secure button parenting or movement.
 No new action buttons are created.
]]

local RUI = _G.RasfectionUI
if not RUI then return end

local Bars = {}

Bars.version = "1.5.0"
Bars.initialized = false
Bars.buttons = {}
Bars.buttonLookup = {}
Bars.elapsed = 0

Bars.config = {
    enabled = true,

    borderSize = 11,

    -- Move decorative metallic artwork
    -- outside the button's normal bounds.
    borderOverhang = 4,

    -- Keep the icon close to the border.
    iconPadding = 1,

    borderColor = {
        0.78, 0.74, 0.88, 1
    },

    iconInset = 0.07,
    scanInterval = 2.0
}

local BORDER =
    "Interface\\AddOns\\RasfectionUI\\Media\\RaisedBorder"

local GROUPS = {
    {prefix = "ActionButton", count = 12},
    {prefix = "MultiBarBottomLeftButton", count = 12},
    {prefix = "MultiBarBottomRightButton", count = 12},
    {prefix = "MultiBarRightButton", count = 12},
    {prefix = "MultiBarLeftButton", count = 12},
    {prefix = "PetActionButton", count = 10},
    {prefix = "ShapeshiftButton", count = 10}
}

-- ==========================================
-- HELPERS
-- ==========================================

local function Combat()
    return InCombatLockdown
        and InCombatLockdown()
end

local function Clamp(value, low, high, fallback)
    value = tonumber(value)

    if not value
        or value ~= value
        or value == math.huge
        or value == -math.huge then

        value = fallback or low
    end

    return math.max(
        low,
        math.min(
            high,
            math.floor(value + 0.5)
        )
    )
end

local function GetProfile()
    local db = RUI:GetModule("Database")

    if not db or not db.GetProfile then
        return nil
    end

    return db:GetProfile()
end

local function Print(message)
    if RUI.Print then
        RUI:Print(message)
    end
end

local function ApplyTextureCoordinates(texture, inset)
    if not texture then return end

    texture:SetTexCoord(
        inset,
        1 - inset,
        inset,
        1 - inset
    )
end

-- ==========================================
-- SETTINGS
-- ==========================================

function Bars:GetSettings()
    local profile = GetProfile()

    if not profile then
        return self.config
    end

    if type(profile.settings) ~= "table" then
        profile.settings = {}
    end

    if type(profile.settings.actionBars) ~= "table" then
        profile.settings.actionBars = {}
    end

    local s = profile.settings.actionBars

    if type(s.enabled) ~= "boolean" then
        s.enabled = true
    end

    if type(s.borderOverhang) ~= "number" then
        s.borderOverhang =
            self.config.borderOverhang
    end

    if type(s.iconPadding) ~= "number" then
        s.iconPadding =
            self.config.iconPadding
    end

    s.borderOverhang = Clamp(
        s.borderOverhang, 0, 8, 4
    )

    s.iconPadding = Clamp(
        s.iconPadding, 0, 5, 1
    )

    return s
end

function Bars:IsEnabled()
    local settings = self:GetSettings()
    return settings.enabled ~= false
end

-- ==========================================
-- GLOBAL THEME BORDER COLOR
-- ==========================================

function Bars:GetBorderColor()
    local appearance =
        RUI:GetModule("GlobalAppearance")

    if appearance and appearance.GetBorderTint then
        local r, g, b, a =
            appearance:GetBorderTint()

        return r, g, b, a
    end

    local c = self.config.borderColor

    return c[1], c[2], c[3], c[4]
end

-- ==========================================
-- FIND BLIZZARD ICON
-- ==========================================

function Bars:FindIcon(button)
    if not button then return nil end

    if button.icon then
        return button.icon
    end

    if button.iconTexture then
        return button.iconTexture
    end

    if button.Icon then
        return button.Icon
    end

    local name = button:GetName()

    if not name then return nil end

    return _G[name .. "Icon"]
        or _G[name .. "IconTexture"]
        or _G[name .. "IconTextureTexture"]
end

-- ==========================================
-- CAPTURE ORIGINAL TEXTURE GEOMETRY
-- ==========================================

function Bars:CaptureIcon(entry)
    local icon = entry.icon
    if not icon then return end

    entry.texCoords = {
        icon:GetTexCoord()
    }

    entry.originalPoints = {}

    local count = icon:GetNumPoints()

    for i = 1, count do
        local point, relative,
            relativePoint, x, y =
            icon:GetPoint(i)

        entry.originalPoints[i] = {
            point = point,
            relative = relative,
            relativePoint = relativePoint,
            x = x,
            y = y
        }
    end

    entry.iconWidth = icon:GetWidth()
    entry.iconHeight = icon:GetHeight()
end

function Bars:RestoreIcon(entry)
    local icon = entry.icon
    if not icon then return end

    icon:ClearAllPoints()

    for _, point in ipairs(
        entry.originalPoints or {}
    ) do
        icon:SetPoint(
            point.point,
            point.relative,
            point.relativePoint,
            point.x,
            point.y
        )
    end

    if entry.texCoords then
        icon:SetTexCoord(
            unpack(entry.texCoords)
        )
    end
end

-- ==========================================
-- BORDER FRAME
-- ==========================================

function Bars:CreateBorder(button)
    if button.RUIBorderFrame then
        return button.RUIBorderFrame
    end

    -- Decorative frame only.
    -- Never replaces the secure button.
    local frame = CreateFrame(
        "Frame",
        nil,
        button
    )

    frame:SetFrameLevel(
        button:GetFrameLevel() + 3
    )

    frame:EnableMouse(false)

    frame:SetBackdrop({
        bgFile = nil,
        edgeFile = BORDER,
        edgeSize = self.config.borderSize,
        insets = {
            left = 0,
            right = 0,
            top = 0,
            bottom = 0
        }
    })

    local r, g, b, a =
        self:GetBorderColor()

    frame:SetBackdropBorderColor(r, g, b, a)

    button.RUIBorderFrame = frame

    return frame
end

-- ==========================================
-- FIX BORDER ALIGNMENT
-- ==========================================

function Bars:ApplyBorderGeometry(entry)
    if Combat() then return false end

    local button = entry.button
    local border = button.RUIBorderFrame

    if not button or not border then
        return false
    end

    local s = self:GetSettings()
    local overhang = s.borderOverhang

    border:ClearAllPoints()

    -- Expand the backdrop drawing surface
    -- beyond the button. This offsets the
    -- inset created by the metallic edge art.
    border:SetPoint(
        "TOPLEFT",
        button,
        "TOPLEFT",
        -overhang,
        overhang
    )

    border:SetPoint(
        "BOTTOMRIGHT",
        button,
        "BOTTOMRIGHT",
        overhang,
        -overhang
    )

    -- The border remains above the icon.
    border:SetFrameLevel(
        button:GetFrameLevel() + 3
    )

    local r, g, b, a =
        self:GetBorderColor()

    border:SetBackdropBorderColor(r, g, b, a)

    return true
end

-- ==========================================
-- FIX ICON ALIGNMENT
-- ==========================================

function Bars:ApplyIconGeometry(entry)
    if Combat() then return false end

    local button = entry.button
    local icon = entry.icon

    if not button or not icon then
        return false
    end

    local s = self:GetSettings()
    local padding = s.iconPadding

    -- Do not use Blizzard's oversized icon
    -- geometry. Align to the actual button.
    icon:ClearAllPoints()

    icon:SetPoint(
        "TOPLEFT",
        button,
        "TOPLEFT",
        padding,
        -padding
    )

    icon:SetPoint(
        "BOTTOMRIGHT",
        button,
        "BOTTOMRIGHT",
        -padding,
        padding
    )

    ApplyTextureCoordinates(
        icon,
        self.config.iconInset
    )

    return true
end

-- ==========================================
-- REGISTER BUTTON
-- ==========================================

function Bars:SkinButton(button)
    if not button then return false end

    if self.buttonLookup[button] then
        return true
    end

    if Combat() then return false end

    local entry = {
        button = button,

        icon = self:FindIcon(button),

        normal = button.GetNormalTexture
            and button:GetNormalTexture()
            or nil
    }

    if entry.icon then
        self:CaptureIcon(entry)
    end

    if entry.normal then
        entry.normalAlpha =
            entry.normal:GetAlpha()
    end

    self:CreateBorder(button)

    self.buttonLookup[button] = entry

    table.insert(
        self.buttons,
        entry
    )

    self:UpdateButton(entry)

    return true
end

-- ==========================================
-- APPLY / REMOVE STYLING
-- ==========================================

function Bars:UpdateButton(entry)
    if not entry or not entry.button then
        return
    end

    if Combat() then return end

    local button = entry.button
    local enabled = self:IsEnabled()

    local border = button.RUIBorderFrame

    if enabled then
        self:ApplyIconGeometry(entry)
        self:ApplyBorderGeometry(entry)

        if border then
            border:Show()
        end

        if entry.normal then
            entry.normal:SetAlpha(0)
        end
    else
        if border then
            border:Hide()
        end

        self:RestoreIcon(entry)

        if entry.normal then
            entry.normal:SetAlpha(
                entry.normalAlpha or 1
            )
        end
    end
end

function Bars:Refresh()
    if Combat() then return end

    for _, entry in ipairs(self.buttons) do
        self:UpdateButton(entry)
    end
end

-- ==========================================
-- DISCOVER ALL BLIZZARD BUTTONS
-- ==========================================

function Bars:Scan()
    if Combat() then return end

    for _, group in ipairs(GROUPS) do
        for i = 1, group.count do
            local name =
                group.prefix .. tostring(i)

            local button = _G[name]

            if button then
                self:SkinButton(button)
            end
        end
    end
end

-- ==========================================
-- SETTINGS CONTROL
-- ==========================================

function Bars:Toggle()
    if Combat() then
        RUI:Error(
            "Change action-bar styling outside combat."
        )
        return
    end

    local s = self:GetSettings()

    s.enabled = not s.enabled

    self:Refresh()

    RUI:Success(
        "Action bar styling " ..
        (s.enabled and "enabled." or "disabled.")
    )
end

function Bars:SetBorderOverhang(value)
    if Combat() then
        RUI:Error(
            "Adjust borders outside combat."
        )
        return
    end

    local s = self:GetSettings()

    s.borderOverhang = Clamp(
        value, 0, 8, 4
    )

    self:Refresh()

    Print(
        "Border extension set to " ..
        s.borderOverhang .. " px."
    )
end

function Bars:SetIconPadding(value)
    if Combat() then
        RUI:Error(
            "Adjust icons outside combat."
        )
        return
    end

    local s = self:GetSettings()

    s.iconPadding = Clamp(
        value, 0, 5, 1
    )

    self:Refresh()

    Print(
        "Icon padding set to " ..
        s.iconPadding .. " px."
    )
end

-- ==========================================
-- STATUS
-- ==========================================

function Bars:Status()
    local s = self:GetSettings()

    Print(
        "Action Bars v" .. self.version
    )

    Print(
        "Styled buttons: " .. #self.buttons
    )

    Print(
        "Metallic styling: " ..
        (self:IsEnabled() and "Enabled" or "Disabled")
    )

    Print(
        "Border extension: " ..
        s.borderOverhang .. " px"
    )

    Print(
        "Icon padding: " ..
        s.iconPadding .. " px"
    )

    Print(
        "Action casting/paging: Blizzard secure buttons"
    )
end

-- ==========================================
-- SLASH COMMANDS
-- ==========================================

SLASH_RUIBARS1 = "/ruibars"

SlashCmdList["RUIBARS"] = function(message)
    message = string.lower(
        tostring(message or ""):match(
            "^%s*(.-)%s*$"
        )
    )

    local command, value =
        string.match(
            message,
            "^(%S+)%s*(%S*)"
        )

    if command == "toggle" then
        Bars:Toggle()

    elseif command == "refresh" then
        if Combat() then
            RUI:Error(
                "Refresh after combat."
            )
            return
        end

        Bars:Scan()
        Bars:Refresh()

        RUI:Success(
            "Action-bar borders refreshed."
        )

    elseif command == "edge" then
        if tonumber(value) then
            Bars:SetBorderOverhang(
                tonumber(value)
            )
        else
            Print(
                "Usage: /ruibars edge 0-8"
            )
        end

    elseif command == "padding" then
        if tonumber(value) then
            Bars:SetIconPadding(
                tonumber(value)
            )
        else
            Print(
                "Usage: /ruibars padding 0-5"
            )
        end

    elseif command == "status" then
        Bars:Status()

    else
        Print(
            "/ruibars status - Diagnostics"
        )
        Print(
            "/ruibars toggle - Toggle metallic styling"
        )
        Print(
            "/ruibars refresh - Reapply borders"
        )
        Print(
            "/ruibars edge 0-8 - Adjust border alignment"
        )
        Print(
            "/ruibars padding 0-5 - Adjust icon spacing"
        )
    end
end

-- ==========================================
-- EVENTS
-- ==========================================

function Bars:CreateController()
    local controller = CreateFrame(
        "Frame",
        "RasfectionUIActionBarsController",
        UIParent
    )

    local events = {
        "PLAYER_ENTERING_WORLD",
        "PLAYER_REGEN_ENABLED",
        "UPDATE_SHAPESHIFT_FORMS",
        "PET_BAR_UPDATE",
        "ACTIONBAR_PAGE_CHANGED"
    }

    for _, event in ipairs(events) do
        controller:RegisterEvent(event)
    end

    controller:SetScript(
        "OnEvent",
        function()
            if Combat() then return end

            Bars:Scan()
            Bars:Refresh()
        end
    )

    -- Catch Blizzard buttons created after
    -- the initial login or pet/stance updates.
    controller:SetScript(
        "OnUpdate",
        function(_, elapsed)
            Bars.elapsed =
                Bars.elapsed + elapsed

            if Bars.elapsed <
                Bars.config.scanInterval then
                return
            end

            Bars.elapsed = 0

            if not Combat() then
                Bars:Scan()
            end
        end
    )

    self.controller = controller
end

-- ==========================================
-- INITIALIZATION
-- ==========================================

function Bars:Initialize()
    if self.initialized then return end

    self:GetSettings()
    self:CreateController()

    self.initialized = true

    if not Combat() then
        self:Scan()
        self:Refresh()
    end

    RUI:Success(
        "Action Bars v1.5 initialized."
    )
end

-- ==========================================
-- REGISTER MODULE
-- ==========================================

RUI:RegisterModule(
    "ActionBars",
    Bars
)
