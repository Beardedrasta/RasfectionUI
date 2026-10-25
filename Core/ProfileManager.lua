
--[[
 RasfectionUI - Core/ProfileManager.lua
 Version 3.0.1
 WoW 3.3.5a / Build 12340

 FIX:
 UIPanelScrollFrameTemplate needs a globally
 named ScrollFrame in the WotLK client.

 FEATURES:
 - Named profile snapshots
 - Account-wide saved profile library
 - Export/import strings
 - Safe parser; no loadstring
 - Checksum verification
 - Backup and restore
 - Global configuration Profiles page
 - Combat protection
 - Reload after loading/importing
]]

local RUI = _G.RasfectionUI
if not RUI then return end

local Manager = {}
Manager.version = "3.0.1"
Manager.initialized = false

local MAX_RAW = 200000
local MAX_DEPTH = 32
local MAX_PROFILES = 30

local WHITE = "Interface\\Buttons\\WHITE8X8"
local FONT = "Fonts\\FRIZQT__.TTF"

local function Module(id)
    return RUI:GetModule(id)
end

local function Combat()
    return InCombatLockdown
        and InCombatLockdown()
end

local function Say(message)
    if RUI.Print then
        RUI:Print(message)
    else
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffb985ffRasfectionUI:|r " ..
            tostring(message)
        )
    end
end

local function ErrorMessage(message)
    if RUI.Error then
        RUI:Error(message)
    else
        Say(tostring(message))
    end
end

local function Finite(n)
    return type(n) == "number"
        and n == n
        and n ~= math.huge
        and n ~= -math.huge
end

-- ==========================================
-- DEEP COPY
-- ==========================================

local function DeepCopy(value, seen, depth)
    seen = seen or {}
    depth = depth or 0

    if depth > MAX_DEPTH then
        error("Profile nesting limit exceeded.")
    end

    local kind = type(value)

    if kind == "string" or kind == "boolean" then
        return value
    end

    if kind == "number" then
        if not Finite(value) then
            error("Invalid profile number.")
        end
        return value
    end

    if kind ~= "table" then
        return nil
    end

    if seen[value] then
        error("Circular reference in profile.")
    end

    seen[value] = true

    local result = {}

    for key, child in pairs(value) do
        local kt = type(key)
        local vt = type(child)

        if (kt == "string" or kt == "number")
            and (vt == "table" or vt == "string"
            or vt == "number" or vt == "boolean") then

            result[DeepCopy(key, seen, depth + 1)] =
                DeepCopy(child, seen, depth + 1)
        end
    end

    seen[value] = nil

    return result
end

-- ==========================================
-- SERIALIZATION
-- ==========================================

local function SortedKeys(tbl)
    local keys = {}

    for key in pairs(tbl) do
        if type(key) == "string"
            or type(key) == "number" then
            keys[#keys + 1] = key
        end
    end

    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)

        if ta ~= tb then
            return ta < tb
        end

        return a < b
    end)

    return keys
end

local function EncodeValue(value, parts, seen, depth)
    if depth > MAX_DEPTH then
        error("Serialization too deep.")
    end

    local kind = type(value)

    if kind == "string" then
        parts[#parts + 1] =
            "s" .. #value .. ":" .. value

    elseif kind == "number" then
        if not Finite(value) then
            error("Invalid number.")
        end

        local repr = string.format("%.17g", value)

        parts[#parts + 1] =
            "n" .. #repr .. ":" .. repr

    elseif kind == "boolean" then
        parts[#parts + 1] =
            value and "b1" or "b0"

    elseif kind == "table" then
        if seen[value] then
            error("Circular table.")
        end

        seen[value] = true
        parts[#parts + 1] = "{"

        for _, key in ipairs(SortedKeys(value)) do
            local child = value[key]
            local t = type(child)

            if t == "table" or t == "string"
                or t == "number" or t == "boolean" then

                EncodeValue(
                    key, parts, seen, depth + 1
                )

                EncodeValue(
                    child, parts, seen, depth + 1
                )
            end
        end

        parts[#parts + 1] = "}"
        seen[value] = nil

    else
        error("Unsupported value.")
    end
end

local function Serialize(value)
    local parts = {}

    EncodeValue(value, parts, {}, 0)

    local result = table.concat(parts)

    if #result > MAX_RAW then
        error("Profile exceeds export size limit.")
    end

    return result
end

local function Deserialize(source)
    if type(source) ~= "string"
        or #source > MAX_RAW then
        error("Invalid profile length.")
    end

    local position = 1
    local nodes = 0

    local function Read(depth)
        nodes = nodes + 1

        if depth > MAX_DEPTH or nodes > 50000 then
            error("Import structure limit exceeded.")
        end

        local token =
            string.sub(source, position, position)

        position = position + 1

        if token == "b" then
            local bit =
                string.sub(source, position, position)

            position = position + 1

            if bit == "1" then return true end
            if bit == "0" then return false end

            error("Invalid Boolean token.")

        elseif token == "s" or token == "n" then
            local colon = string.find(
                source, ":", position, true
            )

            if not colon or colon - position > 8 then
                error("Invalid token length.")
            end

            local length = tonumber(
                string.sub(
                    source, position, colon - 1
                )
            )

            if not length or length < 0
                or length > MAX_RAW
                or length ~= math.floor(length) then
                error("Invalid value size.")
            end

            position = colon + 1

            local last = position + length - 1

            if last > #source then
                error("Truncated import.")
            end

            local content =
                string.sub(source, position, last)

            position = last + 1

            if token == "s" then
                return content
            end

            local number = tonumber(content)

            if not Finite(number) then
                error("Invalid number.")
            end

            return number

        elseif token == "{" then
            local result = {}

            while true do
                if position > #source then
                    error("Unclosed profile table.")
                end

                if string.sub(
                    source, position, position
                ) == "}" then

                    position = position + 1
                    return result
                end

                local key = Read(depth + 1)

                if type(key) ~= "string"
                    and type(key) ~= "number" then
                    error("Invalid table key.")
                end

                result[key] = Read(depth + 1)
            end
        end

        error("Invalid import token.")
    end

    local result = Read(0)

    if position ~= #source + 1 then
        error("Trailing import data.")
    end

    if type(result) ~= "table" then
        error("Imported profile must be a table.")
    end

    return result
end

-- ==========================================
-- BASE64
-- ==========================================

local ALPHABET =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ" ..
    "abcdefghijklmnopqrstuvwxyz0123456789+/"

local REVERSE = {}

for i = 1, #ALPHABET do
    REVERSE[string.sub(ALPHABET, i, i)] = i - 1
end

local function Base64Encode(source)
    local out = {}

    for i = 1, #source, 3 do
        local a = string.byte(source, i) or 0
        local b = string.byte(source, i + 1) or 0
        local c = string.byte(source, i + 2) or 0

        local n = a * 65536 + b * 256 + c

        local v1 = math.floor(n / 262144) % 64
        local v2 = math.floor(n / 4096) % 64
        local v3 = math.floor(n / 64) % 64
        local v4 = n % 64

        out[#out + 1] =
            string.sub(ALPHABET, v1 + 1, v1 + 1)

        out[#out + 1] =
            string.sub(ALPHABET, v2 + 1, v2 + 1)

        out[#out + 1] = i + 1 <= #source
            and string.sub(ALPHABET, v3 + 1, v3 + 1)
            or "="

        out[#out + 1] = i + 2 <= #source
            and string.sub(ALPHABET, v4 + 1, v4 + 1)
            or "="
    end

    return table.concat(out)
end

local function Base64Decode(source)
    if #source % 4 ~= 0 then
        error("Malformed Base64 length.")
    end

    local out = {}

    for i = 1, #source, 4 do
        local a = string.sub(source, i, i)
        local b = string.sub(source, i + 1, i + 1)
        local c = string.sub(source, i + 2, i + 2)
        local d = string.sub(source, i + 3, i + 3)

        local va = REVERSE[a]
        local vb = REVERSE[b]
        local vc = c == "=" and 0 or REVERSE[c]
        local vd = d == "=" and 0 or REVERSE[d]

        if va == nil or vb == nil
            or vc == nil or vd == nil then
            error("Invalid Base64 character.")
        end

        if c == "=" and d ~= "=" then
            error("Invalid Base64 padding.")
        end

        if (c == "=" or d == "=")
            and i ~= #source - 3 then
            error("Unexpected Base64 padding.")
        end

        local n =
            va * 262144 + vb * 4096
            + vc * 64 + vd

        out[#out + 1] = string.char(
            math.floor(n / 65536) % 256
        )

        if c ~= "=" then
            out[#out + 1] = string.char(
                math.floor(n / 256) % 256
            )
        end

        if d ~= "=" then
            out[#out + 1] =
                string.char(n % 256)
        end
    end

    return table.concat(out)
end

local function Checksum(source)
    local hash = 7

    for i = 1, #source do
        hash = (
            hash * 33 + string.byte(source, i)
        ) % 65521
    end

    return hash
end

local function Pack(profile)
    local raw = Serialize(profile)

    return "RUI3:" ..
        #raw .. ":" ..
        Checksum(raw) .. ":" ..
        Base64Encode(raw)
end

local function Unpack(code)
    if type(code) ~= "string" then
        error("Import must be text.")
    end

    code = string.gsub(code, "%s+", "")

    if #code > MAX_RAW * 2 then
        error("Import exceeds size limit.")
    end

    local length, checksum, data =
        string.match(
            code,
            "^RUI3:(%d+):(%d+):([A-Za-z0-9+/=]+)$"
        )

    if not length then
        error("Invalid RasfectionUI export code.")
    end

    length = tonumber(length)
    checksum = tonumber(checksum)

    if not length or length > MAX_RAW then
        error("Invalid import length.")
    end

    local raw = Base64Decode(data)

    if #raw ~= length then
        error("Import length mismatch.")
    end

    if Checksum(raw) ~= checksum then
        error("Import checksum mismatch.")
    end

    return Deserialize(raw)
end

-- ==========================================
-- DATABASE
-- ==========================================

function Manager:GetCurrentProfile()
    local db = Module("Database")

    if db and db.GetProfile then
        return db:GetProfile()
    end

    return nil
end

function Manager:GetLibrary()
    if type(RasfectionUIDB) ~= "table" then
        return nil
    end

    if type(RasfectionUIDB.RUIProfileLibrary)
        ~= "table" then

        RasfectionUIDB.RUIProfileLibrary = {}
    end

    local library = RasfectionUIDB.RUIProfileLibrary

    if type(library.profiles) ~= "table" then
        library.profiles = {}
    end

    return library
end

function Manager:CleanName(name)
    name = tostring(name or "")
    name = string.gsub(name, "^%s+", "")
    name = string.gsub(name, "%s+$", "")

    if #name < 1 or #name > 32 then
        return nil
    end

    if string.find(name, "[%c]") then
        return nil
    end

    return name
end

function Manager:Snapshot()
    local current = self:GetCurrentProfile()

    if type(current) ~= "table" then
        error("Current profile unavailable.")
    end

    local snapshot = DeepCopy(current)

    snapshot.RUIProfileLibrary = nil

    if type(snapshot.settings) == "table" then
        snapshot.settings.RUIProfileLibrary = nil
    end

    return snapshot
end

function Manager:SaveProfile(name)
    if Combat() then
        return false, "Cannot save during combat."
    end

    name = self:CleanName(name)

    if not name then
        return false, "Enter a name of 1-32 characters."
    end

    local library = self:GetLibrary()

    if not library then
        return false, "Profile library unavailable."
    end

    if not library.profiles[name] then
        local count = 0

        for _ in pairs(library.profiles) do
            count = count + 1
        end

        if count >= MAX_PROFILES then
            return false, "Maximum 30 profiles reached."
        end
    end

    local ok, snapshot = pcall(function()
        return self:Snapshot()
    end)

    if not ok then
        return false, tostring(snapshot)
    end

    library.profiles[name] = snapshot

    return true
end

function Manager:BackupCurrent()
    local library = self:GetLibrary()

    if not library then
        return false, "Profile library unavailable."
    end

    local ok, snapshot = pcall(function()
        return self:Snapshot()
    end)

    if not ok then
        return false, tostring(snapshot)
    end

    library.backup = snapshot

    return true
end

function Manager:ReplaceCurrent(snapshot)
    if Combat() then
        return false, "Cannot load during combat."
    end

    if type(snapshot) ~= "table"
        or type(snapshot.settings) ~= "table" then

        return false, "Invalid profile structure."
    end

    local current = self:GetCurrentProfile()

    if type(current) ~= "table" then
        return false, "Current profile unavailable."
    end

    local ok, replacement = pcall(function()
        return DeepCopy(snapshot)
    end)

    if not ok then
        return false, tostring(replacement)
    end

    local backupOK, backupError = self:BackupCurrent()

    if not backupOK then
        return false, backupError
    end

    -- Preserve active profile table identity.
    for key in pairs(current) do
        if key ~= "RUIProfileLibrary" then
            current[key] = nil
        end
    end

    for key, value in pairs(replacement) do
        if key ~= "RUIProfileLibrary" then
            current[key] = value
        end
    end

    return true
end

function Manager:LoadProfile(name)
    if Combat() then
        return false, "Cannot load during combat."
    end

    local library = self:GetLibrary()

    if not library then
        return false, "Profile library unavailable."
    end

    local profile = library.profiles[name]

    if type(profile) ~= "table" then
        return false, "Profile not found."
    end

    return self:ReplaceCurrent(profile)
end

function Manager:RestoreBackup()
    local library = self:GetLibrary()

    if not library
        or type(library.backup) ~= "table" then

        return false, "No backup is available."
    end

    return self:ReplaceCurrent(library.backup)
end

function Manager:DeleteProfile(name)
    if Combat() then
        return false, "Cannot delete in combat."
    end

    local library = self:GetLibrary()

    if not library
        or not library.profiles[name] then

        return false, "Profile not found."
    end

    library.profiles[name] = nil

    return true
end

function Manager:ExportCurrent()
    return Pack(self:Snapshot())
end

function Manager:ImportCode(code)
    if Combat() then
        return false, "Cannot import during combat."
    end

    local ok, result = pcall(function()
        return Unpack(code)
    end)

    if not ok then
        return false, tostring(result)
    end

    return self:ReplaceCurrent(result)
end

-- ==========================================
-- UI HELPERS
-- ==========================================

local function Label(parent, text, size)
    local f = parent:CreateFontString(
        nil, "OVERLAY"
    )

    f:SetFont(
        FONT, size or 11, "OUTLINE"
    )

    f:SetText(text or "")
    f:SetTextColor(0.89, 0.86, 0.98)
    f:SetJustifyH("LEFT")

    return f
end

local function Button(parent, text, width)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 120, 29)

    b:SetBackdrop({
        bgFile = WHITE,
        edgeFile = WHITE,
        edgeSize = 1
    })

    b:SetBackdropColor(
        0.16, 0.16, 0.23, 1
    )

    b:SetBackdropBorderColor(
        0.40, 0.30, 0.55, 1
    )

    local title = Label(b, text, 11)
    title:SetPoint("CENTER")

    b.label = title

    b:SetScript("OnEnter", function(self)
        self:SetBackdropColor(
            0.29, 0.22, 0.40, 1
        )
    end)

    b:SetScript("OnLeave", function(self)
        self:SetBackdropColor(
            0.16, 0.16, 0.23, 1
        )
    end)

    return b
end

local function Input(parent, width, height, multiline)
    local edit = CreateFrame(
        "EditBox", nil, parent
    )

    edit:SetSize(width, height)
    edit:SetFont(FONT, 11, "")
    edit:SetTextColor(0.95, 0.92, 1)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(0)
    edit:SetMultiLine(multiline == true)
    edit:SetJustifyH("LEFT")
    edit:SetTextInsets(6, 6, 4, 4)

    edit:SetBackdrop({
        bgFile = WHITE,
        edgeFile = WHITE,
        edgeSize = 1
    })

    edit:SetBackdropColor(
        0.05, 0.06, 0.09, 1
    )

    edit:SetBackdropBorderColor(
        0.27, 0.28, 0.36, 1
    )

    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    return edit
end

-- ==========================================
-- PROFILE WINDOW
-- ==========================================

function Manager:CreateWindow()
    if self.window then
        return self.window
    end

    local window = CreateFrame(
        "Frame",
        "RasfectionUIProfileManagerWindow",
        UIParent
    )

    window:SetSize(570, 480)
    window:SetPoint("CENTER")
    window:SetFrameStrata("FULLSCREEN_DIALOG")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")

    window:SetScript("OnDragStart", function(self)
        if not Combat() then
            self:StartMoving()
        end
    end)

    window:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)

    window:SetBackdrop({
        bgFile = WHITE,
        edgeFile = WHITE,
        edgeSize = 2,
        insets = {
            left = 2,
            right = 2,
            top = 2,
            bottom = 2
        }
    })

    window:SetBackdropColor(
        0.04, 0.05, 0.075, 0.98
    )

    window:SetBackdropBorderColor(
        0.53, 0.40, 0.70, 1
    )

    local title = Label(
        window, "PROFILE MANAGER", 17
    )
    title:SetPoint("TOPLEFT", 18, -17)

    local close = CreateFrame(
        "Button", nil, window,
        "UIPanelCloseButton"
    )
    close:SetPoint("TOPRIGHT", -6, -5)

    local description = Label(
        window,
        "Save a layout, share it, or load it on another character.",
        10
    )
    description:SetTextColor(
        0.65, 0.68, 0.78
    )
    description:SetPoint("TOPLEFT", 18, -47)

    local nameLabel = Label(
        window, "Profile name", 11
    )
    nameLabel:SetPoint("TOPLEFT", 18, -81)

    local name = Input(window, 318, 25, false)
    name:SetPoint("TOPLEFT", 18, -102)
    name:SetMaxLetters(32)

    local savedLabel = Label(
        window, "Saved profiles:", 10
    )
    savedLabel:SetPoint("TOPLEFT", 18, -139)

    local savedList = Label(
        window, "(none)", 10
    )
    savedList:SetWidth(525)
    savedList:SetHeight(32)
    savedList:SetPoint("TOPLEFT", 18, -157)
    savedList:SetTextColor(
        0.73, 0.72, 0.84
    )

    local save = Button(window, "Save", 96)
    save:SetPoint("TOPLEFT", 18, -202)

    local load = Button(window, "Load", 96)
    load:SetPoint(
        "LEFT", save, "RIGHT", 8, 0
    )

    local backup = Button(
        window, "Undo Load", 105
    )
    backup:SetPoint(
        "LEFT", load, "RIGHT", 8, 0
    )

    local remove = Button(
        window, "Delete", 96
    )
    remove:SetPoint(
        "LEFT", backup, "RIGHT", 8, 0
    )

    local transferLabel = Label(
        window,
        "Export / Import code (Ctrl+C or Ctrl+V)",
        11
    )
    transferLabel:SetPoint(
        "TOPLEFT", 18, -255
    )

    -- ======================================
    -- FIXED SCROLLFRAME
    --
    -- WoW 3.3.5a UIPanelScrollFrameTemplate
    -- requires a non-nil global frame name.
    -- ======================================

    local scroll = CreateFrame(
        "ScrollFrame",
        "RasfectionUIProfileExportScroll",
        window,
        "UIPanelScrollFrameTemplate"
    )

    scroll:SetPoint(
        "TOPLEFT", window, "TOPLEFT",
        18, -280
    )

    scroll:SetSize(511, 119)

    local codeEdit = Input(
        scroll, 475, 118, true
    )

    scroll:SetScrollChild(codeEdit)

    codeEdit:SetScript(
        "OnTextChanged",
        function(self)
            local chars = self:GetNumLetters()
            local rows = math.ceil(
                chars / 70
            )

            self:SetHeight(
                math.max(
                    118,
                    rows * 15 + 30
                )
            )
        end
    )

    local export = Button(
        window, "Export Current", 145
    )
    export:SetPoint("TOPLEFT", 18, -417)

    local import = Button(
        window, "Import & Load", 145
    )
    import:SetPoint(
        "LEFT", export, "RIGHT", 9, 0
    )

    local status = Label(window, "", 10)
    status:SetPoint(
        "BOTTOMLEFT", 18, 13
    )
    status:SetWidth(520)

    self.window = window
    self.nameInput = name
    self.codeInput = codeEdit
    self.savedList = savedList
    self.statusText = status

    local function Message(message, success)
        status:SetText(tostring(message))

        if success then
            status:SetTextColor(
                0.50, 0.90, 0.63
            )
        else
            status:SetTextColor(
                1, 0.49, 0.45
            )
        end
    end

    local function Run(operation)
        local ok, success, reason =
            pcall(operation)

        if not ok then
            Message(success, false)
            return false
        end

        if not success then
            Message(reason, false)
            return false
        end

        return true
    end

    save:SetScript("OnClick", function()
        if Run(function()
            return Manager:SaveProfile(
                name:GetText()
            )
        end) then
            Message("Profile saved.", true)
            Manager:RefreshWindow()
        end
    end)

    load:SetScript("OnClick", function()
        if Run(function()
            return Manager:LoadProfile(
                name:GetText()
            )
        end) then
            ReloadUI()
        end
    end)

    backup:SetScript("OnClick", function()
        if Run(function()
            return Manager:RestoreBackup()
        end) then
            ReloadUI()
        end
    end)

    remove:SetScript("OnClick", function()
        if Run(function()
            return Manager:DeleteProfile(
                name:GetText()
            )
        end) then
            Message(
                "Saved profile deleted.", true
            )
            Manager:RefreshWindow()
        end
    end)

    export:SetScript("OnClick", function()
        local ok, result = pcall(function()
            return Manager:ExportCurrent()
        end)

        if not ok then
            Message(result, false)
            return
        end

        codeEdit:SetText(result)
        codeEdit:SetFocus()
        codeEdit:HighlightText()

        Message(
            "Export ready. Press Ctrl+C.",
            true
        )
    end)

    import:SetScript("OnClick", function()
        if Run(function()
            return Manager:ImportCode(
                codeEdit:GetText()
            )
        end) then
            ReloadUI()
        end
    end)

    window:Hide()

    return window
end

-- ==========================================
-- UPDATE PROFILE LIST
-- ==========================================

function Manager:RefreshWindow()
    local library = self:GetLibrary()

    if not library or not self.savedList then
        return
    end

    local names = {}

    for name in pairs(library.profiles) do
        names[#names + 1] = name
    end

    table.sort(names)

    if #names == 0 then
        self.savedList:SetText("(none)")
    else
        self.savedList:SetText(
            table.concat(names, "   |   ")
        )
    end
end

function Manager:Open()
    if Combat() then
        ErrorMessage(
            "Open Profile Manager outside combat."
        )
        return
    end

    self:CreateWindow()
    self:RefreshWindow()

    self.window:Show()
    self.window:Raise()
end

-- ==========================================
-- GLOBAL CONFIGURATION INTEGRATION
-- ==========================================

function Manager:InstallConfigIntegration()
    local config = Module("Config")
    if not config then return false end

    if config.RUIProfilesInstalled then
        return true
    end

    local previousNavigation = config.CreateNavigation

    config.CreateNavigation = function(ui, ...)
        local result =
            previousNavigation(ui, ...)

        if ui.navigation
            and not ui.navButtons.profiles then

            local button = Button(
                ui.navigation,
                "PROFILES",
                163
            )

            button:SetHeight(34)

            button:SetPoint(
                "TOPLEFT",
                ui.navigation,
                "TOPLEFT",
                11, -274
            )

            button:SetScript(
                "OnClick",
                function()
                    ui:ShowPage("profiles")
                end
            )

            -- Use a colorable background
            -- matching the other sidebar tabs.
            local background =
                button:CreateTexture(
                    nil, "BACKGROUND"
                )

            background:SetTexture(WHITE)
            background:SetAllPoints()
            background:SetVertexColor(
                0.18, 0.18, 0.24, 1
            )

            button.RUIBackground = background
            button.label:SetDrawLayer(
                "OVERLAY"
            )

            ui.navButtons.profiles = button
        end

        return result
    end

    local previousBuildPage = config.BuildPage

    config.BuildPage = function(ui, id, ...)
        if id ~= "profiles" then
            return previousBuildPage(
                ui, id, ...
            )
        end

        if ui.pages.profiles then
            return ui.pages.profiles
        end

        local page = ui:CreatePage(
            "profiles", 640
        )

        ui:Heading(page, "Profiles", 17)

        ui:Description(
            page,
            "Save layouts, share configurations, and load your settings on another character.",
            54
        )

        ui:Section(
            page, "PROFILE MANAGEMENT", 120
        )

        ui:Action(
            page,
            "Open Profile Manager",
            170,
            function()
                Manager:Open()
            end,
            260
        )

        ui:Section(
            page, "HOW PROFILES WORK", 250
        )

        ui:Description(
            page,
            "Save captures your current RasfectionUI database profile. Loading replaces the current profile and reloads the interface.",
            298
        )

        ui:Description(
            page,
            "Named profiles can be used across characters on the same installation. Export codes can transfer settings to another installation.",
            370
        )

        ui:Description(
            page,
            "A backup is created before loading or importing. Undo Load restores the preceding settings.",
            445
        )

        return page
    end

    config.RUIProfilesInstalled = true

    return true
end

-- ==========================================
-- SLASH COMMANDS
-- ==========================================

SLASH_RUIPROFILE1 = "/ruiprofile"

SlashCmdList["RUIPROFILE"] = function(message)
    local command, name = string.match(
        tostring(message or ""),
        "^%s*(%S*)%s*(.-)%s*$"
    )

    command = string.lower(
        command or ""
    )

    if command == "save" then
        local ok, reason =
            Manager:SaveProfile(name)

        if ok then
            Say("Profile saved: " .. name)
        else
            ErrorMessage(reason)
        end

    elseif command == "load" then
        local ok, reason =
            Manager:LoadProfile(name)

        if ok then
            ReloadUI()
        else
            ErrorMessage(reason)
        end

    else
        Manager:Open()
    end
end

-- ==========================================
-- INITIALIZATION
-- ==========================================

function Manager:Initialize()
    if self.initialized then
        return
    end

    self:GetLibrary()
    self:InstallConfigIntegration()

    self.initialized = true

    if RUI.Success then
        RUI:Success(
            "Profile Manager v3.0.1 ready."
        )
    end
end

RUI:RegisterModule(
    "ProfileManager",
    Manager
)
