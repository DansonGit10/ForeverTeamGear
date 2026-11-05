-- Run from the addon directory: lua tests/PrivateGroup.lua
-- Three independent addon namespaces on a simulated WoW chat transport.
local active, clock = nil, 100
local clients, channels, packets, timers = {}, {}, {}, {}
local metrics = { bytes = 0, packets = 0 }
local userAction = false
local function widget()
    return setmetatable({ TitleText = { SetText = function() end } }, { __index = function(_, key)
        if key == "CreateFontString" then return widget end
        return function() end
    end })
end
CreateFrame = widget
SlashCmdList = {}
UnitFullName = function() return active.name, "Realm" end
GetRealmName = function() return "Realm" end
GetServerTime = function() return 100 end
GetTime = function() return clock end
IsInGuild = function() return active.guild ~= nil end
GetNumGuildMembers = function() return active.guild and 2 or 0 end
GetGuildRosterInfo = function(index) return ({ "Anna-Realm", "Other-Realm" })[index] end
IsInGroup = function() return false end
IsInRaid = function() return false end
GetNumSubgroupMembers = function() return 0 end
GetChannelName = function(name) return channels[name] and channels[name][active.key] and 1 or 0 end
JoinTemporaryChannel = function(name, password)
    assert(userAction, "Joining a private channel must require a user action")
    assert(password == active.ns:GroupCode())
    channels[name] = channels[name] or {}
    channels[name][active.key] = true
end
LeaveChannelByName = function(name) if channels[name] then channels[name][active.key] = nil end end
C_Timer = {
    NewTicker = function() return {} end,
    After = function(delay, fn) timers[#timers + 1] = { client = active, at = clock + delay, fn = fn } end,
}
C_ChatInfo = {
    RegisterAddonMessagePrefix = function() end,
    SendAddonMessage = function(prefix, message, channel, target)
        metrics.bytes, metrics.packets = metrics.bytes + #message, metrics.packets + 1
        metrics.last = { sender = active.key, target = target, message = message }
        assert(channel == "WHISPER" or (channel == "GUILD" and active.ns:UsesGuild()), "Private-only data must never use guild/party/channel transport")
        if channel == "GUILD" then assert(message:sub(1, 2) ~= "G|", "Private envelopes must not be sent to the guild") end
        assert(#message <= 255, "Addon packet exceeds the WoW transport limit")
        if channel == "WHISPER" then
            assert(not target:find("-", 1, true), "Same-realm whispers must omit the realm suffix")
            -- Targets already use realm-free character keys.
        end
        packets[#packets + 1] = { sender = active.key, prefix = prefix, message = message, target = target, guild = channel == "GUILD" and active.guild or nil }
    end,
    SendChatMessage = function(message, kind)
        assert(userAction, "Discovery chat must not be sent from startup events or timers")
        assert(kind == "CHANNEL" and message:match("^FTGHELLO1:"), "Discovery must contain no profile data")
        packets[#packets + 1] = { sender = active.key, message = message, channel = active.ns:PrivateChannelName() }
    end,
}
local function make(name, code)
    local client = { name = name, key = name, ns = {} }
    active = client
    local ns = client.ns
    for _, file in ipairs({ "Core", "Settings", "Comm", "PrivateGroup", "Scanner" }) do
        assert(loadfile(file .. ".lua"))("ForeverTeamGear", ns)
    end
    ns.db = { settings = { setupComplete = true, mode = "group", groupCode = code, sharing = { bags = false, bank = false, macros = false } }, players = {}, boe = {} }
    ns.Print, ns.RefreshWindow = function() end, function() end
    ns.modules[1]:Initialize()
    ns.modules[2]:Initialize()
    ns.modules[3]:Initialize()
    local profile = { key = client.key, name = name, realm = "Realm", classToken = "MAGE", level = 20,
        specID = 0, specName = "", updated = 100, gear = {}, professions = {},
        inventory = { bags = { [123] = 8 }, bank = { [456] = 10 } } }
    ns.ScanProfile = function() return profile end
    client.profile = profile
    clients[client.key] = client
    return client
end
local function run(client, fn) active = client; fn(client.ns) end
local function click(client, fn)
    userAction = true; run(client, fn); userAction = false
end
local function pump(iterations)
    for _ = 1, iterations or 100 do
        clock = clock + 0.13
        for _, client in pairs(clients) do run(client, function(ns) ns.modules[2]:FlushOne() end) end
        local pending = packets; packets = {}
        for _, packet in ipairs(pending) do
            if packet.channel then
                for key in pairs(channels[packet.channel] or {}) do
                    run(clients[key], function(ns)
                        ns:Emit("CHAT_MSG_CHANNEL", packet.message, packet.sender, nil, nil, nil, nil, nil, 1, packet.channel)
                    end)
                end
            elseif packet.guild then
                for _, client in pairs(clients) do
                    if client.guild == packet.guild then
                        run(client, function(ns) ns.modules[2]:OnMessage(packet.prefix, packet.message, "GUILD", packet.sender) end)
                    end
                end
            elseif clients[packet.target] then
                run(clients[packet.target], function(ns)
                    ns.modules[2]:OnMessage(packet.prefix, packet.message, "WHISPER", packet.sender)
                end)
            end
        end
        for i = #timers, 1, -1 do
            if timers[i].at <= clock then
                local task = table.remove(timers, i)
                run(task.client, task.fn)
            end
        end
    end
end
if ... == "harness" then return { make = make, run = run, click = click, pump = pump, clients = clients, metrics = metrics } end
local a, b, outsider = make("Anna", "FTG-FRIENDS1"), make("Bob", "FTG-FRIENDS1"), make("Other", "FTG-OTHER12")
for _, client in pairs(clients) do
    run(client, function(ns)
        ns:Emit("PLAYER_ENTERING_WORLD")
        ns:RequestSync()
        ns:DiscoverPrivateGroup()
    end)
end
assert(next(channels) == nil and #packets == 0, "Reload must not join or announce to chat automatically")
for _, client in pairs(clients) do click(client, function(ns) ns:RequestSync(true) end) end
pump()
assert(a.ns.db.players[b.key] and b.ns.db.players[a.key], "Same-code users must find and sync each other without party/guild/nick lists")
assert(not a.ns.db.players[outsider.key] and not outsider.ns.db.players[a.key])
assert(a.ns.db.players[b.key].privateGroup == "FTG-FRIENDS1")
run(a, function(ns)
    assert(ns:ProfileSourceLabel({ key = a.key }) == "Offline")
    assert(ns:ProfileSourceLabel(ns.db.players[b.key]) == "Private group")
end)
assert(next(a.ns.db.players[b.key].inventory.bags) == nil and next(a.ns.db.players[b.key].inventory.bank) == nil)
run(b, function(ns)
    ns.modules[1]:UpdateSharing("bags", true)
    ns.modules[1]:UpdateSharing("bank", true)
    assert(ns:IsPrivatePeer(a.key), "Privacy changes must preserve the existing connection")
end)
pump()
assert(a.ns.db.players[b.key].inventory.bags[123] == 8 and a.ns.db.players[b.key].inventory.bank[456] == 10, "Enabling inventory sharing must replace the previously empty snapshot")
run(b, function(ns)
    ns.modules[1]:UpdateSharing("bags", false)
    ns.modules[1]:UpdateSharing("bank", false)
end)
pump()
assert(next(a.ns.db.players[b.key].inventory.bags) == nil and not a.ns.db.players[b.key].sharing.bags, "Disabling inventory sharing must replace cached inventory with a redacted snapshot")
click(a, function(ns)
    ns.db.settings.groupCode = "FTG-CHANGED1"
    ns:ResetCommunication(); ns:UpdatePrivateChannel(true)
    assert(not ns:IsVisibleCharacter(b.key), "Changing code must hide the old group's cached profiles")
    assert(not ns:IsPrivatePeer(b.key))
end)
run(b, function(ns) ns:BroadcastProfile() end)
pump()
assert(a.ns.db.players[b.key].privateGroup == "FTG-FRIENDS1", "Old-code traffic must not replace cached data after switching")
click(a, function(ns)
    ns.db.settings.groupCode = "FTG-FRIENDS1"
    ns:ResetCommunication(); ns:UpdatePrivateChannel(true); ns:RequestSync(true)
end)
pump()
assert(a.ns:IsPrivatePeer(b.key), "Rejoining the same code must rediscover peers")
-- Add guild synchronization without leaving the private group.
a.guild, outsider.guild = "TestGuild", "TestGuild"
click(a, function(ns)
    ns.db.settings.alsoGuild = true
    ns:UpdateGuildMembers(); ns:ResetCommunication(); ns:RequestSync(true); ns:BroadcastProfile()
end)
click(outsider, function(ns)
    ns.db.settings.mode = "guild"
    ns:UpdateGuildMembers(); ns:ResetCommunication(); ns:UpdatePrivateChannel(true); ns:RequestSync(true)
end)
pump()
assert(a.ns:IsPrivatePeer(b.key), "Enabling guild sharing must preserve the private group")
assert(a.ns.db.players[outsider.key] and outsider.ns.db.players[a.key], "Combined mode must synchronize with the guild too")
assert(a.ns.db.players[outsider.key].privateGroup == nil, "A guild profile must not be tagged as private-group data")
run(a, function(ns)
    assert(ns:ProfileSourceLabel(ns.db.players[outsider.key]) == "Guild")
    assert(ns:ProfileSourceLabel({ key = "Both-Realm", privateGroup = ns:GroupCode(), guildSource = true }) == "Private group + Guild")
end)
assert(not b.ns.db.players[outsider.key], "A private member must not receive a relayed guild member profile")
run(a, function(ns)
    ns.privatePeers[b.key] = nil
    assert(ns:IsActiveTeamCharacter(b.key), "Cached private profiles must remain comparable while peers are offline")
    assert(ns:IsActiveTeamCharacter(outsider.key), "Guild comparisons must not require party/raid membership")
end)
click(a, function(ns)
    ns.db.settings.mode = "offline"
    ns:ResetCommunication(); ns:UpdatePrivateChannel(true)
    assert(not channels["FTGFTGFRIENDS1"][a.key], "Offline must leave the discovery channel")
end)
print("PASS: automatic same-code discovery, different-code isolation, whisper-only private data, packet sizes, privacy, code change/rejoin, combined private+guild synchronization without profile relaying, offline snapshot comparisons, offline cleanup")
