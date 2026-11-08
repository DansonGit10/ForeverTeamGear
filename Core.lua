local ADDON_NAME, ns = ...

ns.name = ADDON_NAME
ns.version = "0.30.7"
ns.prefix = "FTG11"
ns.events = {}
ns.modules = {}

local frame = CreateFrame("Frame")
ns.frame = frame

function ns:Print(message)
    -- Distribution copy: chat logging is disabled.
end

function ns:UnitIdentity(unit)
    local first, second = UnitFullName(unit)
    if not first then return nil end
    local realm = GetRealmName() or ""
    local name = first
    if GetUnitName then
        local ok, display = pcall(GetUnitName, unit, true)
        if ok and type(display) == "string" and display:find(" ", 1, true) then
            local full, backend = display:match("^(.*)%-([^%-]+)$")
            if full and (backend:match("^ClassicBeta") or backend:gsub("%s+", "") == realm:gsub("%s+", "")) then
                name, realm = full, backend
            else name = display end
        end
    end
    if second and second ~= "" then
        if second:match("^ClassicBeta") or second:gsub("%s+", "") == realm:gsub("%s+", "") then
            realm = second
        elseif not name:find(" ", 1, true) then
            name = first .. " " .. second
        end
    end
    return name, realm:gsub("%s+", "")
end

function ns:PlayerKey()
    local name = self:UnitIdentity("player")
    return self:NormalizeSender(name) or "?"
end

function ns:UnitKey(unit)
    local name = self:UnitIdentity(unit)
    return self:NormalizeSender(name)
end

function ns:IsCurrentGroupCharacter(key)
    if not key then return false end
    if key == self:PlayerKey() then return true end
    local prefix = IsInRaid() and "raid" or "party"
    local count = IsInRaid() and (GetNumGroupMembers() or 0) or (GetNumSubgroupMembers() or 0)
    for index = 1, count do
        if self:UnitKey(prefix .. index) == key then return true end
    end
    return false
end

function ns:NormalizeSender(sender)
    if type(sender) ~= "string" or sender == "" then return nil end
    return sender:match("^(.*)%-[^%-]+$") or sender
end

function ns:Now()
    return GetServerTime and GetServerTime() or time()
end

function ns:WhisperTarget(key)
    if type(key) ~= "string" then return key end
    return self:NormalizeSender(key)
end

function ns:On(event, callback)
    self.events[event] = self.events[event] or {}
    table.insert(self.events[event], callback)
    frame:RegisterEvent(event)
end

function ns:SameCharacter(left, right)
    if left == right then return left ~= nil end
    if type(left) ~= "string" or type(right) ~= "string" then return false end
    local first, second = self:WhisperTarget(left), self:WhisperTarget(right)
    -- Backend realm aliases do not identify a different Forever character.
    return first:lower() == second:lower()
end

function ns:Emit(event, ...)
    local handlers = self.events[event]
    if not handlers then return end
    for _, callback in ipairs(handlers) do
        local ok, err = pcall(callback, ...)
        if not ok then self:Print("Error in " .. event .. ": " .. tostring(err)) end
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    ns:Emit(event, ...)
end)

local function initialize()
    ForeverTeamGearDB = ForeverTeamGearDB or {}
    local db = ForeverTeamGearDB
    db.version = 1
    db.players = db.players or {}
    db.boe = db.boe or {}
    db.settings = db.settings or {}
    db.settings.alts = db.settings.alts or {}
    db.settings.wantedRecipes = db.settings.wantedRecipes or {}
    ns.db = db

    for _, module in ipairs(ns.modules) do
        if module.Initialize then module:Initialize() end
    end

    ns:Print("ready. /ftg opens the window; /ftg sync synchronizes your party/raid.")
end

ns:On("ADDON_LOADED", function(addon)
    if addon == ADDON_NAME then initialize() end
end)

SLASH_FOREVERTEAMGEAR1 = "/ftg"
local function blockedAction(addon, action)
    if addon == ADDON_NAME then ns:Print("Client blocked addon action: " .. tostring(action)) end
end
ns:On("ADDON_ACTION_BLOCKED", blockedAction)
ns:On("ADDON_ACTION_FORBIDDEN", blockedAction)
SLASH_FOREVERTEAMGEAR2 = "/foreverteamgear"
SlashCmdList.FOREVERTEAMGEAR = function(input)
    local rawInput = input or ""
    input = (input or ""):lower():match("^%s*(.-)%s*$")
    if input:match("^sync%s+.+") then
        if ns:Mode() ~= "group" or ns:GroupCode() == "" then
            ns:Print("Direct sync requires Private group mode and a saved group code.")
            return
        end
        local target = rawInput:match("^%s*%S+%s+(.+)"):match("^(.-)%s*$")
        target = ns:NormalizeSender(target)
        ns:SendPrivateHello(target)
        C_Timer.After(3, function()
            if ns:IsPrivatePeer(target) then ns:SendProfile("WHISPER", target, { priority = 1, force = true }) end
        end)
        ns:Print("Direct sync: sending a code-checked addon handshake to " .. ns:WhisperTarget(target) .. ".")
    elseif input == "settings" or input == "setup" then
        ns:OpenSettings()
    elseif input == "sync" then
        ns:ScanAll()
        ns:RequestGroupSync()
    elseif input == "share" then
        ns:ScanAll(); ns:RequestSync(true)
    elseif input == "boe" then
        ns:ToggleWindow("boe")
    elseif input == "macros" then
        ns:ToggleWindow("macros")
    elseif input == "inventory" or input == "bags" or input == "bank" then
        ns:ToggleWindow("inventory")
    elseif input:match("^sharemacro%s+%d+$") then
        ns:ShareMacro(tonumber(input:match("(%d+)$")))
    elseif input == "debug" then
        ns.debug = not ns.debug
        ns:Print("debug: " .. (ns.debug and "ON" or "OFF"))
    elseif input == "help" then
        ns:Print("/ftg — equipment, /ftg settings — mode and privacy, /ftg inventory — bags and bank, /ftg boe — detected BoEs, /ftg macros — shared macros, /ftg sharemacro <number> — share one macro, /ftg sync — sync party/raid, /ftg share — publish your own data")
    else
        ns:ToggleWindow("team")
    end
end
