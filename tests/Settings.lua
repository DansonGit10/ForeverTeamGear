-- Run from the addon directory with Lua 5.1: lua tests/Settings.lua
local function widget()
    return setmetatable({ scripts = {}, TitleText = { SetText = function() end } }, { __index = function(_, key)
        if key == "CreateFontString" then return widget end
        if key == "SetScript" then return function(self, event, fn) self.scripts[event] = fn end end
        if key == "SetChecked" then return function(self, value) self.checked = value end end
        if key == "GetChecked" then return function(self) return rawget(self, "checked") == true end end
        if key == "SetText" then return function(self, text) self.text = text end end
        if key == "GetText" then return function(self) return rawget(self, "text") or "" end end
        return function() end
    end })
end
CreateFrame = widget
SlashCmdList = {}
UnitFullName = function() return "Me", "Realm" end
GetRealmName = function() return "Realm" end
GetServerTime = function() return 100 end
GetTime = function() return 100 end
local guild, group = true, true
IsInGuild = function() return guild end
IsInGroup = function(category) return group and not category end
IsInRaid = function() return false end
LE_PARTY_CATEGORY_INSTANCE = 1
GetNumGuildMembers = function() return 1 end
GetGuildRosterInfo = function() return "Guildmate-Realm" end
C_Timer = { After = function(_, fn) deferred = fn end, NewTicker = function() return {} end }
local sent = 0
C_ChatInfo = { RegisterAddonMessagePrefix = function() end, SendAddonMessage = function() sent = sent + 1 end }

local ns = {}
local function load(name) assert(loadfile(name .. ".lua"))("ForeverTeamGear", ns) end
load("Core")
local chatLog = {}
ns.Print = function(_, message) chatLog[#chatLog + 1] = message end
assert(ns:WhisperTarget("Kazu Zephyrus-Realm") == "Kazu Zephyrus")
assert(ns:WhisperTarget("Kazu Zephyrus-OtherRealm") == "Kazu Zephyrus")
assert(ns:WhisperTarget("Kazu Zephyrus-ClassicBetaPvP") == "Kazu Zephyrus")
assert(ns:WhisperTarget("Kazu Zephyrus-ClassicBetaPvP2") == "Kazu Zephyrus")
assert(ns:WhisperTarget("Kazu Zephyrus") == "Kazu Zephyrus")
assert(ns:SameCharacter("Kazu Zephyrus-ClassicBetaPvP", "Kazu Zephyrus-ClassicBetaPvP2"))
assert(not ns:SameCharacter("Kazu Other-Realm", "Kazu Zephyrus-Realm"))
assert(ns:SameCharacter("Kazu-Realm", "Kazu-OtherRealm"))
local originalFullName = UnitFullName
UnitFullName = function() return "Kazu", "Zephyrus" end
assert(ns:PlayerKey() == "Kazu Zephyrus", "Forever's second name component must not be treated as a realm")
GetUnitName = function() return "Kazu Zephyrus" end
assert(ns:PlayerKey() == "Kazu Zephyrus")
UnitFullName = function() return "Kazu Zephyrus", "Realm" end
assert(ns:PlayerKey() == "Kazu Zephyrus", "Older full-name/realm API shape must remain supported")
UnitFullName, GetUnitName = originalFullName, nil
ns.IsCurrentGroupCharacter = function(_, key) return key == "Friend" or key == "Me" end
ns.db = { settings = { alts = {} }, players = {
    ["Alt"] = { key = "Alt" },
    ["Friend"] = { key = "Friend", sender = "Friend" },
    ["Kazu-Zephyrus"] = { key = "Kazu-Zephyrus", name = "Kazu", realm = "ClassicBetaPvP", gear = { [1] = { id = 123 } } },
}, boe = {} }
load("Settings")
local settings = ns.modules[1]
settings:Initialize()
assert(ns.db.players["Kazu Zephyrus"].gear[1].id == 123 and ns.db.players["Kazu-Zephyrus"] == nil)
assert(ns:Mode() == "offline" and not ns:CanCommunicate("PARTY"))
assert(ns:IsOwnCharacter("Alt") and not ns:IsOwnCharacter("Friend"))
assert(ns:IsVisibleCharacter("Alt") and not ns:IsVisibleCharacter("Friend"))
for _, option in ipairs({ "gear", "talents", "professions", "bags", "bank", "boe", "macros" }) do
    assert(ns.db.settings.sharing[option] == true, "New setups must enable every sharing category by default")
end
ns.db.settings.sharing.bags, ns.db.settings.sharing.bank, ns.db.settings.sharing.macros = false, false, false
assert(not ns:CanShare("gear")) -- onboarding has not been completed
ns.db.settings.setupComplete = true
ns.db.settings.mode = "group"
ns.db.settings.groupCode = "FRIENDS1"
ns.privatePeers = { ["Friend"] = "FRIENDS1" }
ns.db.players["Friend"].privateGroup = "FRIENDS1"
assert(not ns:CanCommunicate("PARTY") and ns:CanCommunicate("WHISPER", "Friend"))
assert(not ns:CanCommunicate("GUILD") and not ns:CanCommunicate("WHISPER", "Guildmate"))
assert(ns:IsVisibleCharacter("Friend") and not ns:IsVisibleCharacter("Guildmate"))
assert(ns:CanShare("gear") and not ns:CanShare("bags"))
ns.db.settings.mode = "guild"
assert(ns:CanCommunicate("GUILD") and ns:CanCommunicate("WHISPER", "Guildmate"))
assert(not ns:CanCommunicate("PARTY") and not ns:CanCommunicate("WHISPER", "Friend"))
assert(ns:IsVisibleCharacter("Guildmate") and not ns:IsVisibleCharacter("Friend"))
guild = false; ns:UpdateGuildMembers()
assert(not ns:CanCommunicate("GUILD") and not ns:IsVisibleCharacter("Guildmate"))
guild = true; ns:UpdateGuildMembers()

load("Comm")
local comm = ns.modules[2]
ns.db.settings.mode = "group"
ns:SendEncoded("P", { "test" }, "WHISPER", "Friend")
assert(#comm.queue == 1)
ns.db.settings.mode = "offline"
comm:FlushOne(); assert(sent == 0)
ns.db.settings.mode = "group"
ns:SendEncoded("B", { "test" }, "WHISPER", "Friend")
assert(#comm.queue == 1)
ns.db.settings.sharing.boe = false
comm:FlushOne(); assert(sent == 0)
ns:SendEncoded("B", { "test" }, "WHISPER", "Friend"); assert(#comm.queue == 0)
ns:SendEncoded("M", { "test" }, "WHISPER", "Friend"); assert(#comm.queue == 0)
ns:SendEncoded("P", { "test" }, "WHISPER", "Friend")
ns:ResetCommunication(); assert(#comm.queue == 0 and next(comm.incoming) == nil)
local accepted = 0
ns.AcceptProfile = function() accepted = accepted + 1 end
ns.privatePeers["Friend"] = "FRIENDS1"
comm:OnMessage(ns.prefix, "G|FRIENDS1|D|P|x|1|1|test", "WHISPER", "Friend")
assert(accepted == 1)
comm:OnMessage(ns.prefix, "G|WRONG1|D|P|x|1|1|test", "WHISPER", "Friend")
comm:OnMessage(ns.prefix, "D|P|x|1|1|test", "WHISPER", "Friend")
comm:OnMessage(ns.prefix, "G|FRIENDS1|D|P|x|1|1|test", "GUILD", "Friend")
assert(accepted == 1)
ns.db.settings.mode = "guild"
comm:OnMessage(ns.prefix, "D|P|x|1|1|test", "PARTY", "Friend")
comm:OnMessage(ns.prefix, "D|P|x|1|1|test", "GUILD", "Friend")
assert(accepted == 2, "Authenticated guild traffic must work before the roster is loaded")
comm:OnMessage(ns.prefix, "D|P|x|1|1|test", "GUILD", "Guildmate")
assert(accepted == 3)
ns.db.settings.mode = "offline"
comm:OnMessage(ns.prefix, "D|P|x|1|1|test", "GUILD", "Guildmate")
assert(accepted == 3)

load("Scanner")
local profile = { key = "Me", name = "Me", realm = "Realm", classToken = "MAGE", level = 20,
    specID = 1, specName = "Fire", updated = 100, gear = { [1] = { id = 123, ilvl = 10, link = "item:123" } },
    professions = { Cooking = { rank = 30, recipes = { { id = 1 } } } },
    talents = { treeID = 1 }, inventory = { bags = { [10] = 5 }, bank = { [20] = 7 }, bankUpdated = 100 } }
ns.ScanProfile = function() return profile end
local wire
ns.SendEncoded = function(_, kind, values) wire = values end
ns.db.settings.mode = "group"
ns:SendProfile("PRIVATE")
assert(wire[9] ~= "" and wire[10] ~= "" and wire[12] ~= "")
assert(wire[13] == "" and wire[14] == "" and wire[15] == 0 and wire[16] == "100")
assert(profile.inventory.bags[10] == 5 and profile.inventory.bank[20] == 7)
for key in pairs(ns.db.settings.sharing) do ns.db.settings.sharing[key] = false end
ns:SendProfile("PRIVATE")
assert(wire[6] == 0 and wire[7] == "" and wire[9] == "" and wire[10] == "" and wire[12] == "")
assert(profile.gear[1].id == 123 and profile.talents.treeID == 1 and profile.professions.Cooking.rank == 30)
ns.db.settings.sharing.bags, ns.db.settings.sharing.bank = true, true
ns:SendProfile("PRIVATE")
assert(wire[13] == "10:5" and wire[14] == "20:7" and wire[16] == "011")
wire = nil; ns.db.settings.mode = "offline"; ns:SendProfile("PARTY"); assert(wire == nil)

-- A new profile replaces cached private fields, including older clients' snapshots.
local function split(value, separator)
    local result, start = {}, 1
    while true do
        local pos = value:find(separator, start, true)
        if not pos then result[#result + 1] = value:sub(start); return result end
        result[#result + 1] = value:sub(start, pos - 1); start = pos + #separator
    end
end
ns.RefreshWindow = function() end
local raw = { "Friend", "Friend", "Realm", "MAGE", "20", "0", "", "100", "", "", "test", "", "", "", "0", "000" }
ns:AcceptProfile(table.concat(raw, "\t"), "Friend", function(v) return v end, split)
assert(chatLog[#chatLog - 1]:find("Received data from Friend %(Guild%)%. Saved locally%."))
assert(chatLog[#chatLog]:find("bags not shared; bank not shared"))
local receiptCount = #chatLog
ns:AcceptProfile(table.concat(raw, "\t"), "Friend", function(v) return v end, split)
assert(#chatLog == receiptCount, "Repeated profile packets must not spam receipt messages")
local received = ns.db.players["Friend"]
assert(not received.sharing.gear and not received.sharing.bags and not received.sharing.bank)
assert(next(received.inventory.bags) == nil and next(received.inventory.bank) == nil)
raw[1], raw[2] = "Kazu Zephyrus-ClassicBetaPvP2", "Kazu Zephyrus"
ns:AcceptProfile(table.concat(raw, "\t"), "Kazu Zephyrus-ClassicBetaPvP", function(v) return v end, split)
assert(ns.db.players["Kazu Zephyrus"] and ns.db.players["Kazu Zephyrus"].name == "Kazu Zephyrus")
raw[1], raw[2] = "Newfriend-Surname", "Newfriend"
ns:AcceptProfile(table.concat(raw, "\t"), "Newfriend Surname-ClassicBetaPvP", function(v) return v end, split)
assert(ns.db.players["Newfriend Surname"], "Legacy first-name/surname keys must match the complete authenticated sender")
ns.db.settings.mode = "group"
local directTarget
ns.SendPrivateHello = function(_, target) directTarget = target end
SlashCmdList.FOREVERTEAMGEAR("sync Kazu Zephyrus")
assert(directTarget == "Kazu Zephyrus", "Direct sync must preserve the complete character name and capitalization")
ns:OpenSettings()
settings.mode = "offline"
settings.frame.sharing.bank:SetChecked(false)
settings:Save()
assert(ns:Mode() == "offline" and ns.db.settings.setupComplete and not ns.db.settings.sharing.bank)
assert(#comm.queue == 0)
ns.db.settings.mode, ns.db.settings.groupCode = "group", "FRIENDS1"
ns.privatePeers["Friend"] = "FRIENDS1"
settings:Show()
comm.queue = { { "stale profile" } }
settings.frame.sharing.bags:SetChecked(true)
settings.frame.sharing.bags.scripts.OnClick(settings.frame.sharing.bags)
assert(ns:CanShare("bags") and #comm.queue == 0 and ns:IsPrivatePeer("Friend"), "Sharing clicks must save immediately, clear old packets, and preserve peers")
settings:Save()
assert(ns:IsPrivatePeer("Friend"), "Saving sharing preferences without changing audiences must not disconnect friends")
print("PASS: setup defaults, local ownership, Offline/Group/Guild audiences, guild loss, send/receive gates, queued privacy changes, disabled BoE/macros, profile redaction, local data preservation, cached snapshot replacement")

ns.db = { settings = { alts = { ["Alt Name-OldBackend"] = true }, favorites = { ["Alt Name-OldBackend"] = true },
    selectedCharacter = "Alt Name-OldBackend", wantedRecipes = { ["Alt Name-OldBackend|Cooking|123"] = true } },
    ownCharacters = { ["Alt Name-OldBackend"] = true }, players = {
        ["Alt Name-OldBackend"] = { key = "Alt Name-OldBackend", name = "Alt Name", realm = "OldBackend", updated = 1, privateGroup = "CODE12", gear = {} },
        ["Alt Name-NewBackend"] = { key = "Alt Name-NewBackend", name = "Alt Name", realm = "NewBackend", updated = 2, guildSource = true, gear = { [1] = {id = 99} } },
    }, boe = { { looter = "Alt Name-OldBackend", responses = { ["Friend Name-OldBackend"] = "Need" } } },
    sharedMacros = { old = {owner = "Alt Name-OldBackend", name = "Test", body = "/cast Test"} } }
ns:MigrateRealmKeys()
assert(ns.db.players["Alt Name"].gear[1].id == 99 and not ns.db.players["Alt Name"].realm)
assert(ns.db.players["Alt Name"].privateGroup == "CODE12" and ns.db.players["Alt Name"].guildSource)
assert(ns.db.players["Alt Name-OldBackend"] == nil and ns.db.players["Alt Name-NewBackend"] == nil)
assert(ns:IsOwnCharacter("Alt Name") and ns.db.settings.alts["Alt Name"] and ns.db.settings.favorites["Alt Name"])
assert(ns.db.settings.selectedCharacter == "Alt Name" and ns.db.settings.wantedRecipes["Alt Name|Cooking|123"])
assert(ns.db.boe[1].looter == "Alt Name" and ns.db.boe[1].responses["Friend Name"] == "Need")
assert(ns.db.sharedMacros["Alt Name|Test"].owner == "Alt Name")
ns:MigrateRealmKeys()
assert(ns.db.players["Alt Name"].gear[1].id == 99)
print("PASS: realm-free migration, backend deduplication, latest gear, sources, ownership, alts, favorites, recipe tracking, BoE responses, macros and repeat migration")
