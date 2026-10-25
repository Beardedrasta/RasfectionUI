--[[
    RasfectionUI
    Core/Movers.lua

    Version: 0.1.0
    Client: WoW WotLK 3.3.5a

    MOVEMENT ENGINE

    Features:
      - Register independently movable frames
      - Purple unlock overlays
      - Drag and drop positioning
      - Persistent frame positions
      - Optional grid snapping
      - Individual frame resets
      - Full layout reset
      - Combat lockdown protection
      - Frame position restoration
      - Mover command interface

    Requires:
      Core.lua
      Database.lua
      Theme.lua
]]

local RUI = _G.RasfectionUI

if not RUI then
    return
end

local Movers = {}

Movers.version = "0.1.0"

Movers.registered = {}
Movers.order = {}
Movers.unlocked = false
Movers.initialized = false

local floor = math.floor
local abs = math.abs

-- ==========================================
-- INTERNAL HELPERS
-- ==========================================

local function GetDatabase()
    return RUI:GetModule("Database")
end

local function InCombat()
    return InCombatLockdown
        and InCombatLockdown()
end

local function IsProtected(frame)
    return frame
        and frame.IsProtected
        and frame:IsProtected()
end

local function IsValidFrame(frame)
    return frame
        and frame.SetPoint
        and frame.ClearAllPoints
        and frame.GetCenter
end

local function SafeNumber(value, fallback)
    if type(value) ~= "number"
        or value ~= value
        or value == math.huge
        or value == -math.huge then
        return fallback
    end

    return value
end

local function Round(value, step)
    if not step or step <= 0 then
        return value
    end

    if value >= 0 then
        return floor(value / step + 0.5) * step
    end

    return -floor(abs(value) / step + 0.5) * step
end

-- ==========================================
-- LAYOUT SETTINGS
-- ==========================================

function Movers:GetSettings()
    local database = GetDatabase()

    if database and database.GetLayoutSettings then
        return database:GetLayoutSettings()
    end

    return nil
end

function Movers:GetGridSize()
    local settings = self:GetSettings()

    if not settings then
        return 8
    end

    local size = SafeNumber(settings.gridSize, 8)

    return math.max(1, math.min(100, floor(size)))
end

function Movers:IsSnapEnabled()
    local settings = self:GetSettings()

    return settings and settings.snapToGrid == true
end

function Movers:SetSnap(enabled)
    local settings = self:GetSettings()

    if not settings then
        return false
    end

    settings.snapToGrid = enabled == true

    RUI:Success(
        "Snap-to-grid " ..
        (settings.snapToGrid and "enabled." or "disabled.")
    )

    return true
end

-- ==========================================
-- FRAME POSITION CALCULATION
-- ==========================================

function Movers:GetFramePosition(frame)
    if not IsValidFrame(frame) then
        return nil
    end

    local centerX, centerY = frame:GetCenter()
    local parentX, parentY = UIParent:GetCenter()

    if not centerX or not centerY
        or not parentX or not parentY then
        return nil
    end

    local parentScale = UIParent:GetEffectiveScale()
    local frameScale = frame:GetEffectiveScale()

    if not parentScale or parentScale <= 0
        or not frameScale or frameScale <= 0 then
        return nil
    end

    -- Convert frame center into UIParent's
    -- coordinate system.
    local x = centerX * frameScale / parentScale - parentX
    local y = centerY * frameScale / parentScale - parentY

    return x, y
end

-- ==========================================
-- SAVE FRAME POSITION
-- ==========================================

function Movers:SavePosition(id)
    local entry = self.registered[id]

    if not entry then
        return false
    end

    local database = GetDatabase()

    if not database then
        return false
    end

    local frame = entry.frame

    local x, y = self:GetFramePosition(frame)

    if not x or not y then
        return false
    end

    if self:IsSnapEnabled() then
        local grid = self:GetGridSize()

        x = Round(x, grid)
        y = Round(y, grid)

        frame:ClearAllPoints()
        frame:SetPoint(
            "CENTER",
            UIParent,
            "CENTER",
            x,
            y
        )
    end

    local scale = frame:GetScale()

    local success = database:SaveFrame(
        id,
        "CENTER",
        "CENTER",
        x,
        y,
        frame:GetWidth(),
        frame:GetHeight(),
        scale
    )

    if success then
        RUI:Debug(
            "Saved mover position: " ..
            id .. " (" ..
            floor(x) .. ", " ..
            floor(y) .. ")"
        )
    end

    return success
end

-- ==========================================
-- RESTORE SAVED POSITION
-- ==========================================

function Movers:RestorePosition(id)
    local entry = self.registered[id]

    if not entry then
        return false
    end

    local database = GetDatabase()

    if not database then
        return false
    end

    return database:ApplyFrame(
        id,
        entry.frame
    )
end

-- ==========================================
-- VISUAL OVERLAY CREATION
-- ==========================================

function Movers:CreateOverlay(entry)
    local target = entry.frame

    local overlay = CreateFrame(
        "Frame",
        nil,
        target
    )

    overlay:SetAllPoints(target)
    overlay:SetFrameLevel(target:GetFrameLevel() + 20)

    overlay:SetMovable(false)
    overlay:EnableMouse(true)
    overlay:RegisterForDrag("LeftButton")

    overlay:SetClampedToScreen(true)

    -- Purple translucent background.
    local background = overlay:CreateTexture(
        nil,
        "BACKGROUND"
    )

    background:SetAllPoints(overlay)
    background:SetTexture(
        "Interface\\Buttons\\WHITE8X8"
    )

    background:SetVertexColor(
        0.35, 0.16, 0.65, 0.42
    )

    -- Thin outline using native WoW textures.
    local function CreateEdge(point1, point2, horizontal)
        local edge = overlay:CreateTexture(
            nil,
            "BORDER"
        )

        edge:SetTexture(
            "Interface\\Buttons\\WHITE8X8"
        )

        edge:SetVertexColor(
            0.76, 0.53, 1.00, 0.95
        )

        if horizontal then
            edge:SetHeight(2)
        else
            edge:SetWidth(2)
        end

        edge:SetPoint(point1, overlay, point1)
        edge:SetPoint(point2, overlay, point2)

        return edge
    end

    CreateEdge("TOPLEFT", "TOPRIGHT", true)
    CreateEdge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    CreateEdge("TOPLEFT", "BOTTOMLEFT", false)
    CreateEdge("TOPRIGHT", "BOTTOMRIGHT", false)

    -- Mover title.
    local title = overlay:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontNormal"
    )

    title:SetPoint(
        "CENTER",
        overlay,
        "CENTER",
        0,
        0
    )

    title:SetJustifyH("CENTER")
    title:SetText(entry.label or entry.id)

    title:SetTextColor(1, 1, 1, 1)
    title:SetShadowColor(0, 0, 0, 1)
    title:SetShadowOffset(1, -1)

    overlay.title = title

    -- Mouse interaction.
    overlay:SetScript("OnDragStart", function()
        if InCombat() then
            return
        end

        if IsProtected(target) and InCombat() then
            return
        end

        target:SetMovable(true)
        target:StartMoving()

        entry.dragging = true
    end)

    overlay:SetScript("OnDragStop", function()
        if not entry.dragging then
            return
        end

        entry.dragging = false

        target:StopMovingOrSizing()

        if not InCombat() then
            Movers:SavePosition(entry.id)
        end
    end)

    overlay:SetScript("OnEnter", function(self)
        background:SetVertexColor(
            0.55, 0.28, 0.88, 0.55
        )
    end)

    overlay:SetScript("OnLeave", function(self)
        background:SetVertexColor(
            0.35, 0.16, 0.65, 0.42
        )
    end)

    overlay:Hide()

    entry.overlay = overlay

    return overlay
end

-- ==========================================
-- REGISTER MOVABLE FRAME
-- ==========================================

function Movers:RegisterFrame(id, frame, options)
    if type(id) ~= "string" or id == "" then
        return false
    end

    if not IsValidFrame(frame) then
        RUI:Error(
            "Invalid frame registered: " .. id
        )

        return false
    end

    if self.registered[id] then
        return false
    end

    options = options or {}

    local entry = {
        id = id,
        label = options.label or id,
        frame = frame,
        options = options,
        dragging = false
    }

    -- Record initial layout so reset can
    -- return to the original location.
    local point, relativeFrame, relativePoint, x, y =
        frame:GetPoint(1)

    entry.default = {
        point = point or "CENTER",
        relativeFrame = relativeFrame or UIParent,
        relativePoint = relativePoint or "CENTER",
        x = SafeNumber(x, 0),
        y = SafeNumber(y, 0),
        width = frame:GetWidth(),
        height = frame:GetHeight(),
        scale = frame:GetScale()
    }

    self.registered[id] = entry
    table.insert(self.order, id)

    frame:SetMovable(true)
    frame:SetClampedToScreen(true)

    self:CreateOverlay(entry)
    self:RestorePosition(id)

    if self.unlocked then
        entry.overlay:Show()
    end

    RUI:Debug(
        "Registered movable frame: " .. id
    )

    return true
end

-- ==========================================
-- UNLOCK MOVERS
-- ==========================================

function Movers:Unlock()
    if InCombat() then
        RUI:Error(
            "Cannot unlock frames during combat."
        )

        return false
    end

    self.unlocked = true

    for _, id in ipairs(self.order) do
        local entry = self.registered[id]

        if entry and entry.overlay then
            entry.overlay:Show()
        end
    end

    local settings = self:GetSettings()

    if settings then
        settings.locked = false
    end

    RUI:Success(
        "Movers unlocked. Drag purple overlays to reposition frames."
    )

    return true
end

-- ==========================================
-- LOCK MOVERS
-- ==========================================

function Movers:Lock()
    if InCombat() then
        RUI:Error(
            "Cannot change mover state during combat."
        )

        return false
    end

    for _, id in ipairs(self.order) do
        local entry = self.registered[id]

        if entry then
            if entry.dragging then
                entry.dragging = false
                entry.frame:StopMovingOrSizing()
                self:SavePosition(id)
            end

            if entry.overlay then
                entry.overlay:Hide()
            end
        end
    end

    self.unlocked = false

    local settings = self:GetSettings()

    if settings then
        settings.locked = true
    end

    RUI:Success("Movers locked.")

    return true
end

-- ==========================================
-- TOGGLE
-- ==========================================

function Movers:Toggle()
    if self.unlocked then
        return self:Lock()
    end

    return self:Unlock()
end

-- ==========================================
-- RESET SINGLE FRAME
-- ==========================================

function Movers:ResetFrame(id)
    if InCombat() then
        RUI:Error(
            "Cannot reset frames during combat."
        )

        return false
    end

    local entry = self.registered[id]

    if not entry then
        RUI:Error("Unknown mover: " .. tostring(id))
        return false
    end

    local frame = entry.frame
    local defaults = entry.default

    local database = GetDatabase()

    if database then
        database:ResetFrame(id)
    end

    frame:ClearAllPoints()

    frame:SetScale(defaults.scale or 1)

    frame:SetPoint(
        defaults.point,
        defaults.relativeFrame,
        defaults.relativePoint,
        defaults.x,
        defaults.y
    )

    if defaults.width and defaults.width > 0 then
        frame:SetWidth(defaults.width)
    end

    if defaults.height and defaults.height > 0 then
        frame:SetHeight(defaults.height)
    end

    RUI:Success(
        "Reset frame: " .. id
    )

    return true
end

-- ==========================================
-- RESET ALL FRAMES
-- ==========================================

function Movers:ResetAll()
    if InCombat() then
        RUI:Error(
            "Cannot reset layout during combat."
        )

        return false
    end

    local database = GetDatabase()

    if database then
        database:ResetAllFrames()
    end

    for _, id in ipairs(self.order) do
        local entry = self.registered[id]

        if entry then
            local frame = entry.frame
            local defaults = entry.default

            frame:ClearAllPoints()

            frame:SetScale(defaults.scale or 1)

            frame:SetPoint(
                defaults.point,
                defaults.relativeFrame,
                defaults.relativePoint,
                defaults.x,
                defaults.y
            )

            if defaults.width and defaults.width > 0 then
                frame:SetWidth(defaults.width)
            end

            if defaults.height and defaults.height > 0 then
                frame:SetHeight(defaults.height)
            end
        end
    end

    RUI:Success(
        "All registered frame positions reset."
    )

    return true
end

-- ==========================================
-- LIST MOVABLE FRAMES
-- ==========================================

function Movers:ListFrames()
    RUI:Print(
        "Registered movable frames: " ..
        tostring(#self.order)
    )

    for _, id in ipairs(self.order) do
        local entry = self.registered[id]

        if entry then
            RUI:Print(
                " - " .. id ..
                " (" .. entry.label .. ")"
            )
        end
    end
end

-- ==========================================
-- ADDITIONAL SLASH COMMANDS
-- ==========================================

SLASH_RUIMOVERS1 = "/ruimovers"

SlashCmdList["RUIMOVERS"] = function(message)
    message = string.lower(message or "")

    if message == "list" then
        Movers:ListFrames()
    elseif message == "unlock" then
        Movers:Unlock()
    elseif message == "lock" then
        Movers:Lock()
    elseif message == "snap" then
        Movers:SetSnap(not Movers:IsSnapEnabled())
    elseif message == "reset" then
        Movers:ResetAll()
    else
        Movers:Toggle()
    end
end

-- ==========================================
-- COMBAT PROTECTION
-- ==========================================

function Movers:HandleCombatStart()
    -- Lock overlays before protected combat
    -- interactions can interfere.
    --
    -- Visibility changes to secure frames
    -- are intentionally avoided here.

    if self.unlocked then
        for _, id in ipairs(self.order) do
            local entry = self.registered[id]

            if entry and entry.overlay
                and not IsProtected(entry.overlay) then
                entry.overlay:Hide()
            end
        end

        self.unlocked = false

        local settings = self:GetSettings()

        if settings then
            settings.locked = true
        end

        RUI:Print(
            "Movers automatically locked for combat."
        )
    end
end

-- ==========================================
-- INITIALIZATION
-- ==========================================

function Movers:Initialize()
    if self.initialized then
        return
    end

    self.initialized = true

    -- Register the theme preview as our
    -- first movable interface element.
    local theme = RUI:GetModule("Theme")

    if theme and theme.preview then
        self:RegisterFrame(
            "ThemePreview",
            theme.preview,
            {
                label = "Theme Preview"
            }
        )
    end

    RUI:RegisterEvent(
        "PLAYER_REGEN_DISABLED",
        function()
            Movers:HandleCombatStart()
        end
    )

    RUI:Debug(
        "Movement engine initialized."
    )

    RUI:Success(
        "Movement engine ready. Type /rui move."
    )
end

-- ==========================================
-- REGISTER MODULE
-- ==========================================

RUI:RegisterModule("Movers", Movers)
