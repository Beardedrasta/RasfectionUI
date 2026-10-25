
--[[
 RasfectionUI
 Modules/UnitFrames/ClickCasting.lua

 Version 1.8.0 / WoW 3.3.5a

 Supports:
 - Five compact party buttons (player + four)
 - Secure raid group-header buttons
 - Shift / Ctrl / Alt spell click bindings
 - Per-character saved bindings
 - Combat lockdown
 - Existing /ruiclick commands
]]

local RUI = _G.RasfectionUI
if not RUI then return end

local Click = {}
Click.version = "1.8.0"
Click.initialized = false
Click.managed = {}
Click.pending = false
Click.elapsed = 0

local MODIFIERS = {
    shift = true,
    ctrl = true,
    alt = true
}

local function Combat()
    return InCombatLockdown
        and InCombatLockdown()
end

local function Trim(s)
    return tostring(s or ""):match("^%s*(.-)%s*$")
end

local function Key(mod, button)
    return mod .. ":" .. tostring(button)
end

local function ParseKey(key)
    local mod, button = tostring(key):match(
        "^(%a+):([1-5])$"
    )
    if not MODIFIERS[mod] then return nil end
    return mod, tonumber(button)
end

function Click:GetSettings()
    local db = RUI:GetModule("Database")
    if not db or not db.GetProfile then return nil end

    local profile = db:GetProfile()
    if not profile then return nil end

    profile.settings = profile.settings or {}
    local settings = profile.settings

    settings.clickCasting = settings.clickCasting or {
        enabled = true,
        bindings = {}
    }

    local s = settings.clickCasting

    if type(s.bindings) ~= "table" then
        s.bindings = {}
    end

    if s.enabled == nil then
        s.enabled = true
    end

    return s
end

function Click:KnownSpell(input)
    local wanted = Trim(input)
    if wanted == "" then return nil end

    if tonumber(wanted) then
        wanted = GetSpellInfo(tonumber(wanted))
            or wanted
    end

    if not GetSpellName then return nil end

    for i = 1, 1000 do
        local name = GetSpellName(
            i, BOOKTYPE_SPELL
        )

        if not name then break end

        if string.lower(name)
            == string.lower(wanted) then
            return name
        end
    end

    return nil
end

function Click:CollectButtons()
    local result = {}
    local seen = {}

    local function Add(button)
        if button and not seen[button]
            and button.SetAttribute
            and button.GetAttribute then

            seen[button] = true
            table.insert(result, button)
        end
    end

    local party = RUI:GetModule("PartyFrames")
    if party and party.rows then
        -- Player is row 1; party1-party4 are 2-5.
        for i = 1, 5 do
            Add(party.rows[i])
        end
    end

    local raid = RUI:GetModule("RaidFrames")
    if raid and raid.buttons then
        for _, button in ipairs(raid.buttons) do
            Add(button)
        end
    end

    return result
end

function Click:ConfigureButton(button)
    if Combat() then
        self.pending = true
        return false
    end

    local settings = self:GetSettings()
    if not settings then return false end

    local old = self.managed[button]

    if old then
        for attribute in pairs(old) do
            button:SetAttribute(attribute, nil)
        end
    end

    local managed = {}

    if settings.enabled then
        for key, spell in pairs(settings.bindings) do
            local mod, mouse = ParseKey(key)

            if mod and type(spell) == "string"
                and spell ~= "" then

                local typeAttr =
                    mod .. "-type" .. mouse

                local spellAttr =
                    mod .. "-spell" .. mouse

                button:SetAttribute(
                    typeAttr, "spell"
                )
                button:SetAttribute(
                    spellAttr, spell
                )

                managed[typeAttr] = true
                managed[spellAttr] = true
            end
        end
    end

    self.managed[button] = managed
    return true
end

function Click:ApplyAll()
    if Combat() then
        self.pending = true
        return false
    end

    for _, button in ipairs(
        self:CollectButtons()
    ) do
        self:ConfigureButton(button)
    end

    self.pending = false
    return true
end

function Click:ScanNew()
    if Combat() then
        self.pending = true
        return
    end

    for _, button in ipairs(
        self:CollectButtons()
    ) do
        if not self.managed[button] then
            self:ConfigureButton(button)
        end
    end
end

function Click:Bind(mod, mouse, input)
    mod = string.lower(Trim(mod))
    mouse = tonumber(mouse)

    if not MODIFIERS[mod] or not mouse
        or mouse < 1 or mouse > 5
        or mouse ~= math.floor(mouse) then

        RUI:Error("Use shift, ctrl or alt and mouse 1-5.")
        return
    end

    if Combat() then
        RUI:Error("Change bindings outside combat.")
        return
    end

    local spell = self:KnownSpell(input)
    if not spell then
        RUI:Error("Unknown spell: " .. tostring(input))
        return
    end

    local s = self:GetSettings()
    if not s then return end

    s.bindings[Key(mod, mouse)] = spell

    self:ApplyAll()

    RUI:Success(
        mod:upper() .. " + Mouse " .. mouse ..
        " = " .. spell
    )
end

function Click:Unbind(mod, mouse)
    if Combat() then
        RUI:Error("Change bindings outside combat.")
        return
    end

    mod = string.lower(Trim(mod))
    mouse = tonumber(mouse)

    if not MODIFIERS[mod]
        or not mouse or mouse < 1
        or mouse > 5 then
        RUI:Error("Invalid binding.")
        return
    end

    local s = self:GetSettings()
    if not s then return end

    s.bindings[Key(mod, mouse)] = nil
    self:ApplyAll()

    RUI:Success("Binding removed.")
end

function Click:Toggle()
    if Combat() then
        RUI:Error("Change bindings outside combat.")
        return
    end

    local s = self:GetSettings()
    if not s then return end

    s.enabled = not s.enabled
    self:ApplyAll()

    RUI:Success(
        "Click-casting " ..
        (s.enabled and "enabled." or "disabled.")
    )
end

function Click:List()
    local s = self:GetSettings()
    if not s then return end

    RUI:Print(
        "ClickCasting: " ..
        (s.enabled and "Enabled" or "Disabled")
    )

    local keys = {}
    for key in pairs(s.bindings) do
        table.insert(keys, key)
    end

    table.sort(keys)

    if #keys == 0 then
        RUI:Print("No bindings configured.")
    end

    for _, key in ipairs(keys) do
        RUI:Print(key .. " = " .. s.bindings[key])
    end
end

function Click:Status()
    local buttons = self:CollectButtons()
    RUI:Print("ClickCasting v" .. self.version)
    RUI:Print("Secure unit buttons: " .. #buttons)
    RUI:Print(
        "Pending changes: " ..
        (self.pending and "Yes" or "No")
    )
end

function Click:HandleCommand(message)
    local command, rest = Trim(message):match(
        "^(%S+)%s*(.-)$"
    )

    command = string.lower(command or "")

    if command == "bind" then
        local mod, mouse, spell = (rest or ""):match(
            "^(%S+)%s+(%d+)%s+(.+)$"
        )

        if not spell then
            RUI:Print(
                "/ruiclick bind shift 1 Flash of Light"
            )
            return
        end

        self:Bind(mod, mouse, spell)

    elseif command == "unbind" then
        local mod, mouse = (rest or ""):match(
            "^(%S+)%s+(%d+)$"
        )

        self:Unbind(mod or "", mouse)

    elseif command == "toggle" then
        self:Toggle()

    elseif command == "list" then
        self:List()

    elseif command == "status" then
        self:Status()

    elseif command == "refresh" then
        self:ApplyAll()
        RUI:Print("Click bindings refreshed.")

    else
        RUI:Print("/ruiclick bind shift 1 Spell Name")
        RUI:Print("/ruiclick unbind shift 1")
        RUI:Print("/ruiclick toggle")
        RUI:Print("/ruiclick list")
        RUI:Print("/ruiclick status")
        RUI:Print("/ruiclick refresh")
    end
end

SLASH_RUICLICK1 = "/ruiclick"

SlashCmdList["RUICLICK"] = function(message)
    Click:HandleCommand(message)
end

function Click:Initialize()
    if self.initialized then return end

    self:GetSettings()

    local controller = CreateFrame(
        "Frame",
        "RasfectionUIClickCastingController",
        UIParent
    )

    controller:RegisterEvent("PLAYER_ENTERING_WORLD")
    controller:RegisterEvent("PARTY_MEMBERS_CHANGED")
    controller:RegisterEvent("RAID_ROSTER_UPDATE")
    controller:RegisterEvent("PLAYER_REGEN_ENABLED")

    controller:SetScript("OnEvent", function()
        if Combat() then
            Click.pending = true
            return
        end

        Click:ApplyAll()
    end)

    controller:SetScript("OnUpdate", function(_, elapsed)
        Click.elapsed = Click.elapsed + elapsed

        if Click.elapsed < 0.5 then return end
        Click.elapsed = 0

        if not Combat() then
            if Click.pending then
                Click:ApplyAll()
            else
                Click:ScanNew()
            end
        end
    end)

    self.controller = controller
    self.initialized = true

    self:ApplyAll()

    RUI:Success(
        "ClickCasting v1.8 initialized."
    )
end

RUI:RegisterModule("ClickCasting", Click)
