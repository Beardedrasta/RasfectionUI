--[[
    RasfectionUI
    Core/Database.lua

    Version: 0.1.0
    Client: World of Warcraft 3.3.5a

    Persistent settings and layout management.

    Features:
      - Global theme settings
      - Per-character settings
      - Frame position storage
      - Frame size storage
      - Module preferences
      - Named layout profiles
      - Default restoration
      - Safe data validation

    Requires Core.lua to load first.
]]

local RUI = _G.RasfectionUI

if not RUI then
    return
end

local Database = {}

-- ==========================================
-- DEFAULT SETTINGS
-- ==========================================

local DEFAULTS = {

    global = {

        version = 1,

        theme = {
            name = "Rasfection",
            border = "RaisedBorder",

            borderSize = 16,

            background = {
                0.05, 0.06, 0.08, 0.95
            },

            borderColor = {
                1.0, 1.0, 1.0, 1.0
            },

            accent = {
                0.61, 0.35, 1.0, 1.0
            },

            textColor = {
                1.0, 1.0, 1.0, 1.0
            },

            font = "Fonts\\FRIZQT__.TTF",

            fontSize = 12,

            shadows = true,
            animations = true
        },

        config = {
            scale = 1.0,
            rememberPosition = true
        }
    },

    character = {

        activeProfile = "Default",

        profiles = {

            Default = {

                frames = {},

                modules = {

                    UnitFrames = {
                        enabled = true
                    },

                    ActionBars = {
                        enabled = true
                    },

                    Chat = {
                        enabled = true
                    },

                    Bags = {
                        enabled = true
                    },

                    Minimap = {
                        enabled = true
                    },

                    Panels = {
                        enabled = true
                    },

                    Misc = {
                        enabled = true
                    }
                },

                settings = {
                    locked = true,
                    snapToGrid = false,
                    gridSize = 8,
                    showAnchors = false
                }
            }
        }
    }
}

-- ==========================================
-- DEEP COPY
-- ==========================================

local function DeepCopy(source)
    if type(source) ~= "table" then
        return source
    end

    local result = {}

    for key, value in pairs(source) do
        if type(value) == "table" then
            result[key] = DeepCopy(value)
        else
            result[key] = value
        end
    end

    return result
end

-- ==========================================
-- DEFAULT MERGING
-- ==========================================

local function MergeDefaults(target, defaults)
    if type(target) ~= "table" then
        target = {}
    end

    for key, value in pairs(defaults) do
        if target[key] == nil then
            target[key] = DeepCopy(value)
        elseif type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = DeepCopy(value)
            else
                MergeDefaults(target[key], value)
            end
        end
    end

    return target
end

-- ==========================================
-- VALIDATION HELPERS
-- ==========================================

local function ValidNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function ValidName(value)
    return type(value) == "string"
        and value ~= ""
end

local function CleanNumber(value, fallback)
    if ValidNumber(value) then
        return value
    end

    return fallback
end

-- ==========================================
-- CHARACTER IDENTIFICATION
-- ==========================================

function Database:GetCharacterKey()
    local player = UnitName("player")
    local realm = GetRealmName()

    if not ValidName(player) then
        return nil
    end

    if not ValidName(realm) then
        return nil
    end

    return realm .. "-" .. player
end

-- ==========================================
-- DATABASE INITIALIZATION
-- ==========================================

function Database:Initialize()
    if type(RasfectionUIDB) ~= "table" then
        RasfectionUIDB = {}
    end

    self.root = RasfectionUIDB

    -- The root table is shared with Core.lua.
    RUI.db = self.root

    if type(self.root.global) ~= "table" then
        self.root.global = {}
    end

    self.root.global = MergeDefaults(
        self.root.global,
        DEFAULTS.global
    )

    if type(self.root.characters) ~= "table" then
        self.root.characters = {}
    end

    self.characterKey = self:GetCharacterKey()

    if not self.characterKey then
        RUI:Error(
            "Database could not identify the character."
        )
        return
    end

    local characters = self.root.characters

    if type(characters[self.characterKey]) ~= "table" then
        characters[self.characterKey] = {}
    end

    self.character = MergeDefaults(
        characters[self.characterKey],
        DEFAULTS.character
    )

    self:ValidateProfile()

    RUI:Debug(
        "Database loaded for " ..
        self.characterKey
    )

    RUI:Debug(
        "Active profile: " ..
        self.character.activeProfile
    )
end

-- ==========================================
-- GLOBAL SETTINGS
-- ==========================================

function Database:GetGlobal()
    return self.root and self.root.global
end

function Database:GetTheme()
    local global = self:GetGlobal()

    return global and global.theme
end

function Database:SetThemeValue(key, value)
    local theme = self:GetTheme()

    if not theme or not ValidName(key) then
        return false
    end

    if theme[key] == nil then
        return false
    end

    theme[key] = DeepCopy(value)

    return true
end

-- ==========================================
-- CHARACTER SETTINGS
-- ==========================================

function Database:GetCharacter()
    return self.character
end

function Database:GetProfile()
    if not self.character then
        return nil
    end

    local name = self.character.activeProfile

    if not ValidName(name) then
        return nil
    end

    local profiles = self.character.profiles

    if type(profiles) ~= "table" then
        return nil
    end

    return profiles[name]
end

-- ==========================================
-- PROFILE VALIDATION
-- ==========================================

function Database:ValidateProfile()
    if not self.character then
        return
    end

    if type(self.character.profiles) ~= "table" then
        self.character.profiles = {}
    end

    local profiles = self.character.profiles

    if type(profiles.Default) ~= "table" then
        profiles.Default = DeepCopy(
            DEFAULTS.character.profiles.Default
        )
    end

    MergeDefaults(
        profiles.Default,
        DEFAULTS.character.profiles.Default
    )

    local active = self.character.activeProfile

    if not ValidName(active)
        or type(profiles[active]) ~= "table" then
        active = "Default"
        self.character.activeProfile = active
    end

    MergeDefaults(
        profiles[active],
        DEFAULTS.character.profiles.Default
    )
end

-- ==========================================
-- NAMED PROFILES
-- ==========================================

function Database:CreateProfile(name)
    if not self.character then
        return false
    end

    if not ValidName(name) then
        return false
    end

    local profiles = self.character.profiles

    if profiles[name] ~= nil then
        return false
    end

    local current = self:GetProfile()

    profiles[name] = DeepCopy(
        current or DEFAULTS.character.profiles.Default
    )

    return true
end

function Database:SetProfile(name)
    if not self.character then
        return false
    end

    if not ValidName(name) then
        return false
    end

    if type(self.character.profiles[name]) ~= "table" then
        return false
    end

    self.character.activeProfile = name

    return true
end

function Database:DeleteProfile(name)
    if not self.character then
        return false
    end

    if name == "Default" then
        return false
    end

    if not ValidName(name) then
        return false
    end

    local profiles = self.character.profiles

    if not profiles[name] then
        return false
    end

    if self.character.activeProfile == name then
        self.character.activeProfile = "Default"
    end

    profiles[name] = nil

    return true
end

function Database:ListProfiles()
    local result = {}

    if not self.character then
        return result
    end

    for name in pairs(self.character.profiles) do
        table.insert(result, name)
    end

    table.sort(result)

    return result
end

-- ==========================================
-- MODULE SETTINGS
-- ==========================================

function Database:GetModuleSettings(name)
    local profile = self:GetProfile()

    if not profile or not ValidName(name) then
        return nil
    end

    if type(profile.modules) ~= "table" then
        profile.modules = {}
    end

    if type(profile.modules[name]) ~= "table" then
        profile.modules[name] = {
            enabled = true
        }
    end

    return profile.modules[name]
end

function Database:IsModuleEnabled(name)
    local settings = self:GetModuleSettings(name)

    if not settings then
        return false
    end

    return settings.enabled ~= false
end

function Database:SetModuleEnabled(name, enabled)
    local settings = self:GetModuleSettings(name)

    if not settings then
        return false
    end

    settings.enabled = enabled == true

    return true
end

-- ==========================================
-- FRAME LAYOUT STORAGE
-- ==========================================

function Database:GetFrameSettings(frameID)
    if not ValidName(frameID) then
        return nil
    end

    local profile = self:GetProfile()

    if not profile then
        return nil
    end

    if type(profile.frames) ~= "table" then
        profile.frames = {}
    end

    return profile.frames[frameID]
end

function Database:SaveFrame(
    frameID,
    point,
    relativePoint,
    x,
    y,
    width,
    height,
    scale
)
    if not ValidName(frameID) then
        return false
    end

    local profile = self:GetProfile()

    if not profile then
        return false
    end

    if type(profile.frames) ~= "table" then
        profile.frames = {}
    end

    local old = profile.frames[frameID]

    if type(old) ~= "table" then
        old = {}
    end

    local allowedPoints = {
        CENTER = true,
        TOP = true,
        BOTTOM = true,
        LEFT = true,
        RIGHT = true,
        TOPLEFT = true,
        TOPRIGHT = true,
        BOTTOMLEFT = true,
        BOTTOMRIGHT = true
    }

    if not allowedPoints[point] then
        point = "CENTER"
    end

    if not allowedPoints[relativePoint] then
        relativePoint = "CENTER"
    end

    local result = {
        point = point,
        relativePoint = relativePoint,

        x = CleanNumber(x, 0),
        y = CleanNumber(y, 0),

        width = CleanNumber(width, old.width),
        height = CleanNumber(height, old.height),

        scale = CleanNumber(scale, old.scale or 1)
    }

    if result.width and result.width <= 0 then
        result.width = nil
    end

    if result.height and result.height <= 0 then
        result.height = nil
    end

    if result.scale <= 0 then
        result.scale = 1
    end

    profile.frames[frameID] = result

    RUI:Debug(
        "Saved frame layout: " .. frameID
    )

    return true
end

-- ==========================================
-- APPLY SAVED FRAME LAYOUT
-- ==========================================

function Database:ApplyFrame(frameID, frame)
    if not frame or not frame.SetPoint then
        return false
    end

    local settings = self:GetFrameSettings(frameID)

    if not settings then
        return false
    end

    -- Protected frames must not be moved
    -- during combat lockdown.
    if InCombatLockdown
        and InCombatLockdown()
        and frame.IsProtected
        and frame:IsProtected() then
        return false
    end

    local point = settings.point or "CENTER"

    local relativePoint =
        settings.relativePoint or "CENTER"

    local x = CleanNumber(settings.x, 0)
    local y = CleanNumber(settings.y, 0)

    frame:ClearAllPoints()

    frame:SetPoint(
        point,
        UIParent,
        relativePoint,
        x,
        y
    )

    if ValidNumber(settings.scale)
        and settings.scale > 0 then
        frame:SetScale(settings.scale)
    end

    if ValidNumber(settings.width)
        and settings.width > 0 then
        frame:SetWidth(settings.width)
    end

    if ValidNumber(settings.height)
        and settings.height > 0 then
        frame:SetHeight(settings.height)
    end

    return true
end

-- ==========================================
-- RESET FRAME LAYOUT
-- ==========================================

function Database:ResetFrame(frameID)
    if not ValidName(frameID) then
        return false
    end

    local profile = self:GetProfile()

    if not profile or type(profile.frames) ~= "table" then
        return false
    end

    profile.frames[frameID] = nil

    return true
end

function Database:ResetAllFrames()
    local profile = self:GetProfile()

    if not profile then
        return false
    end

    profile.frames = {}

    return true
end

-- ==========================================
-- PROFILE OPTIONS
-- ==========================================

function Database:GetLayoutSettings()
    local profile = self:GetProfile()

    if not profile then
        return nil
    end

    return profile.settings
end

function Database:SetLayoutLocked(locked)
    local settings = self:GetLayoutSettings()

    if not settings then
        return false
    end

    settings.locked = locked == true

    return true
end

function Database:IsLayoutLocked()
    local settings = self:GetLayoutSettings()

    if not settings then
        return true
    end

    return settings.locked ~= false
end

-- ==========================================
-- FACTORY RESET
-- ==========================================

function Database:ResetCurrentProfile()
    if not self.character then
        return false
    end

    local name = self.character.activeProfile

    if not ValidName(name) then
        return false
    end

    self.character.profiles[name] = DeepCopy(
        DEFAULTS.character.profiles.Default
    )

    RUI:Debug(
        "Reset profile settings: " .. name
    )

    return true
end

function Database:ResetGlobalTheme()
    if not self.root then
        return false
    end

    self.root.global.theme = DeepCopy(
        DEFAULTS.global.theme
    )

    return true
end

-- ==========================================
-- DEFAULT ACCESS
-- ==========================================

function Database:GetDefaults()
    return DeepCopy(DEFAULTS)
end

-- ==========================================
-- MODULE REGISTRATION
-- ==========================================

RUI:RegisterModule("Database", Database)
