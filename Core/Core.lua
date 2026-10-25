--[[
    RasfectionUI
    Core/Core.lua

    Version: 0.1.0
    Client: World of Warcraft 3.3.5a (12340)

    Core responsibilities:
      - Addon lifecycle
      - Module registration
      - Shared event dispatch
      - Protected initialization
      - Logging and debugging
      - Slash commands
      - Future subsystem integration

    This file does not modify Blizzard frames yet.
]]

local ADDON_NAME = "RasfectionUI"
local VERSION = "0.1.0"

-- ==========================================
-- GLOBAL NAMESPACE
-- ==========================================

local RUI = _G.RasfectionUI or {}
_G.RasfectionUI = RUI

RUI.name = ADDON_NAME
RUI.version = VERSION

RUI.modules = RUI.modules or {}
RUI.moduleOrder = RUI.moduleOrder or {}
RUI.events = RUI.events or {}

RUI.loaded = false
RUI.initialized = false
RUI.debugMode = false

RUI.media = {
    border = "Interface\\AddOns\\RasfectionUI\\Media\\RaisedBorder",
    logo = "Interface\\AddOns\\RasfectionUI\\Media\\Logo"
}

RUI.colors = {
    primary = "|cff9b59ff",
    white   = "|cffffffff",
    gray    = "|cffaaaaaa",
    green   = "|cff55ff88",
    red     = "|cffff5555",
    yellow  = "|cffffff55"
}

-- ==========================================
-- CHAT OUTPUT
-- ==========================================

local function SafePrint(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(message)
    end
end

function RUI:Print(message)
    SafePrint(
        self.colors.primary ..
        "RasfectionUI|r " ..
        tostring(message or "")
    )
end

function RUI:Success(message)
    self:Print(
        self.colors.green ..
        tostring(message or "") ..
        "|r"
    )
end

function RUI:Error(message)
    self:Print(
        self.colors.red ..
        tostring(message or "") ..
        "|r"
    )
end

function RUI:Debug(message)
    if not self.debugMode then
        return
    end

    self:Print(
        self.colors.gray ..
        "[DEBUG] " ..
        tostring(message or "") ..
        "|r"
    )
end

-- ==========================================
-- SAFE FUNCTION EXECUTION
-- ==========================================

function RUI:SafeCall(callback, context, ...)
    if type(callback) ~= "function" then
        return false
    end

    local success, result = pcall(callback, context, ...)

    if not success then
        self:Error(tostring(result))
        return false
    end

    return true, result
end

-- ==========================================
-- MODULE SYSTEM
-- ==========================================

function RUI:RegisterModule(name, module)
    if type(name) ~= "string" or name == "" then
        self:Error("Invalid module name.")
        return false
    end

    if self.modules[name] then
        self:Error("Duplicate module: " .. name)
        return false
    end

    if type(module) ~= "table" then
        module = {}
    end

    module.name = name
    module.core = self
    module.enabled = true
    module.initialized = false

    self.modules[name] = module
    table.insert(self.moduleOrder, name)

    self:Debug("Registered module: " .. name)

    return true
end

function RUI:GetModule(name)
    return self.modules[name]
end

function RUI:InitializeModule(name)
    local module = self.modules[name]

    if not module then
        return false
    end

    if module.initialized then
        return true
    end

    if module.enabled == false then
        return false
    end

    if type(module.Initialize) == "function" then
        local success = self:SafeCall(
            module.Initialize,
            module
        )

        if not success then
            self:Error(
                "Failed to initialize module: " .. name
            )
            return false
        end
    end

    module.initialized = true

    self:Debug("Initialized module: " .. name)

    return true
end

function RUI:InitializeModules()
    for _, name in ipairs(self.moduleOrder) do
        self:InitializeModule(name)
    end
end

-- ==========================================
-- SHARED EVENT SYSTEM
-- ==========================================

local eventFrame = CreateFrame("Frame", "RasfectionUIEventFrame")

RUI.eventFrame = eventFrame

function RUI:RegisterEvent(eventName, callback)
    if type(eventName) ~= "string" then
        return false
    end

    if type(callback) ~= "function" then
        return false
    end

    if not self.events[eventName] then
        self.events[eventName] = {}
        eventFrame:RegisterEvent(eventName)
    end

    table.insert(self.events[eventName], callback)

    return true
end

function RUI:DispatchEvent(eventName, ...)
    local callbacks = self.events[eventName]

    if not callbacks then
        return
    end

    for _, callback in ipairs(callbacks) do
        self:SafeCall(callback, self, eventName, ...)
    end
end

-- ==========================================
-- CORE INITIALIZATION
-- ==========================================

function RUI:OnAddonLoaded()
    if self.loaded then
        return
    end

    self.loaded = true

    -- SavedVariables become available when our
    -- own ADDON_LOADED event fires.
    if type(RasfectionUIDB) ~= "table" then
        RasfectionUIDB = {}
    end

    self.db = RasfectionUIDB

    if self.db.debug == nil then
        self.db.debug = false
    end

    self.debugMode = self.db.debug == true

    self:Debug("SavedVariables initialized.")

    eventFrame:UnregisterEvent("ADDON_LOADED")
end

function RUI:OnPlayerLogin()
    if self.initialized then
        return
    end

    if not self.loaded then
        return
    end

    self.initialized = true

    self:InitializeModules()

    self:Success(
        "v" .. self.version ..
        " loaded successfully. Type /rui for commands."
    )

    eventFrame:UnregisterEvent("PLAYER_LOGIN")
end

-- ==========================================
-- FUTURE UI INTEGRATION
-- ==========================================

function RUI:OpenConfig()
    local module = self:GetModule("Config")

    if module and type(module.Open) == "function" then
        self:SafeCall(module.Open, module)
        return
    end

    self:Print(
        "Configuration panel will be added in a future phase."
    )
end

function RUI:ToggleMovers()
    local module = self:GetModule("Movers")

    if module and type(module.Toggle) == "function" then
        self:SafeCall(module.Toggle, module)
        return
    end

    self:Print(
        "Movable frame system is not installed yet."
    )
end

function RUI:ResetLayout()
    if InCombatLockdown and InCombatLockdown() then
        self:Error("Cannot reset layout during combat.")
        return
    end

    local module = self:GetModule("Movers")

    if module and type(module.ResetAll) == "function" then
        self:SafeCall(module.ResetAll, module)
        return
    end

    self:Print("Layout reset is not available yet.")
end

-- ==========================================
-- STATUS INFORMATION
-- ==========================================

function RUI:ShowStatus()
    local total = 0
    local active = 0

    for _, module in pairs(self.modules) do
        total = total + 1

        if module.initialized then
            active = active + 1
        end
    end

    self:Print("Version: " .. self.version)
    self:Print(
        "Modules initialized: " ..
        active .. "/" .. total
    )

    self:Print(
        "Debug mode: " ..
        (self.debugMode and "Enabled" or "Disabled")
    )

    self:Print(
        "Database: " ..
        (self.db and "Ready" or "Not ready")
    )
end

-- ==========================================
-- SLASH COMMANDS
-- ==========================================

local function Trim(text)
    text = tostring(text or "")
    return string.match(text, "^%s*(.-)%s*$")
end

function RUI:HandleSlashCommand(message)
    local command = string.lower(Trim(message))

    if command == "" or command == "help" then
        self:Print("Available commands:")
        self:Print("/rui help - Show commands")
        self:Print("/rui status - Show addon status")
        self:Print("/rui config - Open settings")
        self:Print("/rui move - Toggle frame movers")
        self:Print("/rui reset - Reset frame layout")
        self:Print("/rui debug - Toggle debugging")
        return
    end

    if command == "status" then
        self:ShowStatus()
    elseif command == "config" then
        self:OpenConfig()
    elseif command == "move" then
        self:ToggleMovers()
    elseif command == "reset" then
        self:ResetLayout()
    elseif command == "debug" then
        self.debugMode = not self.debugMode

        if self.db then
            self.db.debug = self.debugMode
        end

        self:Print(
            "Debug mode " ..
            (self.debugMode and "enabled." or "disabled.")
        )
    else
        self:Error(
            "Unknown command. Type /rui help."
        )
    end
end

SLASH_RASFECTIONUI1 = "/rui"
SLASH_RASFECTIONUI2 = "/rasfectionui"

SlashCmdList["RASFECTIONUI"] = function(message)
    RUI:HandleSlashCommand(message)
end

-- ==========================================
-- BLIZZARD EVENT HANDLER
-- ==========================================

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...

        if addonName == ADDON_NAME then
            RUI:OnAddonLoaded()
        end
    elseif event == "PLAYER_LOGIN" then
        RUI:OnPlayerLogin()
    end

    RUI:DispatchEvent(event, ...)
end)

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
