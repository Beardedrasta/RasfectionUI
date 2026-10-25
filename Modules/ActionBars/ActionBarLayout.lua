--[[
 RasfectionUI
 Modules/ActionBars/ActionBarLayout.lua

 Version: 1.5.0
 WoW 3.3.5a / 12340

 CUSTOM ACTION BAR LAYOUTS

 Features:
 - Five independent standard action bars
 - Separate draggable positioning overlays
 - Button size 28 through 48
 - Button spacing 0 through 16
 - Columns 1 through 12
 - Vertical / horizontal / grid arrangements
 - Saved per-character layouts
 - Opt-in activation
 - Original anchors preserved for reset
 - No changes during combat
 - No secure button reparenting
 - No modifications to action assignments

 IMPORTANT:
 Blizzard may still control action-bar visibility
 and certain positions. This is an experimental
 layout module; verify combat and paging before
 retiring Blizzard artwork.
]]

local RUI = _G.RasfectionUI
if not RUI then return end

local Layout = {}

Layout.version = "1.5.0"
Layout.initialized = false
Layout.moving = false
Layout.originals = {}
Layout.anchors = {}
Layout.pending = false

local FONT = "Fonts\\FRIZQT__.TTF"
local WHITE = "Interface\\Buttons\\WHITE8X8"

local GROUPS = {
    main = {
        prefix = "ActionButton",
        label = "MAIN BAR",
        x = 0,
        y = -220,
        columns = 12
    },
    bottomleft = {
        prefix = "MultiBarBottomLeftButton",
        label = "BOTTOM LEFT",
        x = 0,
        y = -270,
        columns = 12
    },
    bottomright = {
        prefix = "MultiBarBottomRightButton",
        label = "BOTTOM RIGHT",
        x = 0,
        y = -320,
        columns = 12
    },
    right = {
        prefix = "MultiBarRightButton",
        label = "RIGHT BAR",
        x = 400,
        y = 0,
        columns = 1
    },
    left = {
        prefix = "MultiBarLeftButton",
        label = "LEFT BAR",
        x = 350,
        y = 0,
        columns = 1
    }
}

local ORDER = {
    "main",
    "bottomleft",
    "bottomright",
    "right",
    "left"
}

local function Combat()
    return InCombatLockdown
        and InCombatLockdown()
end

local function Trim(s)
    return tostring(s or ""):match("^%s*(.-)%s*$")
end

local function ClampNumber(n, low, high)
    n = tonumber(n)
    if not n or n ~= n then return nil end
    return math.floor(math.max(low, math.min(high, n)) + 0.5)
end

local function Print(s)
    RUI:Print(s)
end

local function Error(s)
    RUI:Error(s)
end

-- =======================================
-- SETTINGS
-- =======================================

function Layout:GetSettings()
    local db = RUI:GetModule("Database")
    if not db or not db.GetProfile then
        return nil
    end

    local profile = db:GetProfile()
    if not profile then return nil end

    if type(profile.settings) ~= "table" then
        profile.settings = {}
    end

    if type(profile.settings.actionBarLayout) ~= "table" then
        profile.settings.actionBarLayout = {}
    end

    local s = profile.settings.actionBarLayout

    if type(s.enabled) ~= "boolean" then
        s.enabled = false
    end

    if type(s.bars) ~= "table" then
        s.bars = {}
    end

    for _, id in ipairs(ORDER) do
        local d = GROUPS[id]

        if type(s.bars[id]) ~= "table" then
            s.bars[id] = {}
        end

        local b = s.bars[id]

        if type(b.x) ~= "number" then b.x = d.x end
        if type(b.y) ~= "number" then b.y = d.y end

        b.size = ClampNumber(b.size, 28, 48) or 36
        b.gap = ClampNumber(b.gap, 0, 16) or 4
        b.columns = ClampNumber(
            b.columns, 1, 12
        ) or d.columns
    end

    return s
end

-- =======================================
-- ORIGINAL BUTTON GEOMETRY
-- =======================================

function Layout:SaveOriginal(button)
    if not button or self.originals[button] then
        return
    end

    local data = {
        width = button:GetWidth(),
        height = button:GetHeight(),
        points = {}
    }

    for i = 1, button:GetNumPoints() do
        local point, relative, relativePoint, x, y =
            button:GetPoint(i)

        table.insert(data.points, {
            point, relative, relativePoint, x, y
        })
    end

    self.originals[button] = data
end

function Layout:SaveAllOriginals()
    for _, id in ipairs(ORDER) do
        local prefix = GROUPS[id].prefix

        for i = 1, 12 do
            local button = _G[prefix .. i]
            if button then
                self:SaveOriginal(button)
            end
        end
    end
end

-- =======================================
-- GEOMETRY
-- =======================================

function Layout:Dimensions(b)
    local columns = b.columns
    local rows = math.ceil(12 / columns)

    local width = columns * b.size
        + (columns - 1) * b.gap

    local height = rows * b.size
        + (rows - 1) * b.gap

    return width, height
end

-- All button anchors are positioned relative
-- directly to UIParent, not to the movable
-- overlays. This avoids a protected unit
-- depending on an insecure drag anchor.

function Layout:ApplyBar(id)
    if Combat() then
        self.pending = true
        return false
    end

    local settings = self:GetSettings()

    if not settings or not settings.enabled then
        return false
    end

    local definition = GROUPS[id]
    local b = settings.bars[id]

    if not definition or not b then
        return false
    end

    local width, height = self:Dimensions(b)

    for i = 1, 12 do
        local button = _G[
        definition.prefix .. i
        ]

        if button then
            self:SaveOriginal(button)

            local column = (i - 1) % b.columns
            local row = math.floor(
                (i - 1) / b.columns
            )

            local x = -width / 2
                + column * (b.size + b.gap)
                + b.size / 2

            local y = height / 2
                - row * (b.size + b.gap)
                - b.size / 2

            button:ClearAllPoints()

            button:SetPoint(
                "CENTER",
                UIParent,
                "CENTER",
                b.x + x,
                b.y + y
            )

            button:SetSize(b.size, b.size)
        end
    end

    return true
end

function Layout:ApplyAll()
    if Combat() then
        self.pending = true
        return false
    end

    local s = self:GetSettings()
    if not s or not s.enabled then return false end

    for _, id in ipairs(ORDER) do
        self:ApplyBar(id)
    end

    self:UpdateAnchors()
    self.pending = false

    return true
end

-- =======================================
-- RESTORE ORIGINAL BLIZZARD POSITIONS
-- =======================================

function Layout:RestoreOriginals()
    if Combat() then
        Error("Cannot restore action bars in combat.")
        return false
    end

    for _, id in ipairs(ORDER) do
        local prefix = GROUPS[id].prefix

        for i = 1, 12 do
            local button = _G[prefix .. i]
            local saved = button and self.originals[button]

            if saved then
                button:ClearAllPoints()

                for _, p in ipairs(saved.points) do
                    button:SetPoint(
                        p[1], p[2], p[3], p[4], p[5]
                    )
                end

                button:SetSize(
                    saved.width,
                    saved.height
                )
            end
        end
    end

    return true
end

-- =======================================
-- INDEPENDENT POSITIONING OVERLAYS
-- =======================================

function Layout:CreateAnchor(id)
    if self.anchors[id] then
        return self.anchors[id]
    end

    local frame = CreateFrame(
        "Frame",
        "RasfectionUIBarAnchor_" .. id,
        UIParent
    )

    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(100)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")

    local background = frame:CreateTexture(
        nil, "BACKGROUND"
    )

    background:SetTexture(WHITE)
    background:SetAllPoints()
    background:SetVertexColor(
        0.28, 0.13, 0.44, 0.37
    )

    local label = frame:CreateFontString(
        nil, "OVERLAY"
    )

    label:SetFont(FONT, 11, "OUTLINE")
    label:SetPoint("CENTER")
    label:SetText(
        GROUPS[id].label .. "\nDRAG TO MOVE"
    )

    label:SetTextColor(
        0.94, 0.85, 1, 1
    )

    frame:SetScript("OnDragStart", function(self)
        if not Combat() then
            self:StartMoving()
        end
    end)

    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()

        if Combat() then
            return
        end

        local s = Layout:GetSettings()
        if not s then return end

        local x, y = self:GetCenter()
        local ux, uy = UIParent:GetCenter()

        if not x or not ux then return end

        -- Both centers use the same UI coordinate
        -- system because the anchor is a direct
        -- child of UIParent.
        s.bars[id].x = math.floor(x - ux + 0.5)
        s.bars[id].y = math.floor(y - uy + 0.5)

        Layout:ApplyBar(id)
        Layout:UpdateAnchors()
    end)

    frame:Hide()

    self.anchors[id] = frame

    return frame
end

function Layout:UpdateAnchors()
    local s = self:GetSettings()
    if not s then return end

    for _, id in ipairs(ORDER) do
        local frame = self.anchors[id]
        local b = s.bars[id]

        if frame and b then
            local width, height = self:Dimensions(b)

            frame:SetSize(width, height)
            frame:ClearAllPoints()

            frame:SetPoint(
                "CENTER",
                UIParent,
                "CENTER",
                b.x, b.y
            )

            if self.moving and s.enabled then
                frame:Show()
            else
                frame:Hide()
            end
        end
    end
end

function Layout:ToggleMove()
    if Combat() then
        Error("Bar movement is disabled in combat.")
        return
    end

    local s = self:GetSettings()
    if not s then return end

    if not s.enabled then
        Error("Enable layouts first: /ruilayout enable")
        return
    end

    self.moving = not self.moving
    self:UpdateAnchors()

    Print(
        self.moving
        and "Drag the purple bar overlays. Use /ruilayout move to lock."
        or "Action bar positions locked."
    )
end

-- =======================================
-- ENABLE / DISABLE
-- =======================================

function Layout:SetEnabled(enabled)
    if Combat() then
        Error("Change action bar layout outside combat.")
        return
    end

    local s = self:GetSettings()
    if not s then return end

    if s.enabled == enabled then
        Print(
            enabled and "Layouts already enabled."
            or "Layouts already disabled."
        )
        return
    end

    if enabled then
        self:SaveAllOriginals()
        s.enabled = true
        self:ApplyAll()

        Print("Custom layouts enabled.")
    else
        self.moving = false
        self:RestoreOriginals()
        s.enabled = false
        self:UpdateAnchors()

        Print("Original action bar positions restored.")
    end
end

-- =======================================
-- BAR SETTINGS
-- =======================================

function Layout:SetBarOption(id, field, value)
    if Combat() then
        Error("Change layout settings outside combat.")
        return
    end

    if not GROUPS[id] then
        Error("Unknown bar name.")
        return
    end

    local limits = {
        size = { 28, 48 },
        gap = { 0, 16 },
        columns = { 1, 12 }
    }

    local range = limits[field]

    if not range then
        Error("Use size, gap or columns.")
        return
    end

    value = ClampNumber(value, range[1], range[2])

    if not value then
        Error("Please enter a number.")
        return
    end

    local s = self:GetSettings()
    if not s then return end

    s.bars[id][field] = value

    if s.enabled then
        self:ApplyBar(id)
    end

    self:UpdateAnchors()

    Print(
        GROUPS[id].label .. " " ..
        field .. " set to " .. value .. "."
    )
end

-- =======================================
-- RESET
-- =======================================

function Layout:Reset()
    if Combat() then
        Error("Reset action bars outside combat.")
        return
    end

    local s = self:GetSettings()
    if not s then return end

    self.moving = false
    self:RestoreOriginals()

    local profile = RUI:GetModule("Database"):GetProfile()

    profile.settings.actionBarLayout = nil

    self:UpdateAnchors()

    Print(
        "Custom action bar layouts reset. " ..
        "Original Blizzard positions restored."
    )
end

-- =======================================
-- DIAGNOSTICS
-- =======================================

function Layout:Status()
    local s = self:GetSettings()
    if not s then return end

    Print("Action Bar Layout v" .. self.version)

    Print(
        "Custom positioning: " ..
        (s.enabled and "Enabled" or "Disabled")
    )

    for _, id in ipairs(ORDER) do
        local b = s.bars[id]

        Print(
            id .. ": " ..
            b.columns .. " columns, " ..
            b.size .. "px, " ..
            b.gap .. "px gap"
        )
    end
end

-- =======================================
-- SLASH COMMANDS
-- =======================================

SLASH_RUILAYOUT1 = "/ruilayout"

SlashCmdList["RUILAYOUT"] = function(message)
    local a, b, c, d = string.match(
        Trim(message),
        "^(%S*)%s*(%S*)%s*(%S*)%s*(%S*)"
    )

    a = string.lower(a or "")
    b = string.lower(b or "")
    c = string.lower(c or "")

    if a == "enable" then
        Layout:SetEnabled(true)
    elseif a == "disable" then
        Layout:SetEnabled(false)
    elseif a == "move" then
        Layout:ToggleMove()
    elseif a == "set" then
        Layout:SetBarOption(b, c, d)
    elseif a == "reset" then
        Layout:Reset()
    elseif a == "status" then
        Layout:Status()
    else
        Print("/ruilayout enable")
        Print("/ruilayout disable")
        Print("/ruilayout move")
        Print("/ruilayout set main size 40")
        Print("/ruilayout set main gap 5")
        Print("/ruilayout set main columns 6")
        Print("/ruilayout set right columns 1")
        Print("/ruilayout reset")
        Print("/ruilayout status")

        Print(
            "Bar IDs: main, bottomleft, " ..
            "bottomright, right, left"
        )
    end
end

-- =======================================
-- EVENTS
-- =======================================

function Layout:CreateController()
    local controller = CreateFrame(
        "Frame",
        "RasfectionUIActionBarLayoutController",
        UIParent
    )

    controller:RegisterEvent("PLAYER_ENTERING_WORLD")
    controller:RegisterEvent("PLAYER_REGEN_ENABLED")

    controller:SetScript("OnEvent", function()
        if Combat() then
            Layout.pending = true
            return
        end

        local s = Layout:GetSettings()

        if s and s.enabled then
            Layout:ApplyAll()
        end
    end)

    self.controller = controller
end

-- =======================================
-- INITIALIZATION
-- =======================================

function Layout:Initialize()
    if self.initialized then return end

    self:GetSettings()

    for _, id in ipairs(ORDER) do
        self:CreateAnchor(id)
    end

    self:SaveAllOriginals()
    self:CreateController()

    self.initialized = true

    if not Combat() then
        local s = self:GetSettings()
        if s and s.enabled then
            self:ApplyAll()
        end
    end

    RUI:Success(
        "Action Bar Layout v1.5 initialized."
    )

    Print(
        "Use /ruilayout enable to begin custom positioning."
    )
end

RUI:RegisterModule("ActionBarLayout", Layout)
