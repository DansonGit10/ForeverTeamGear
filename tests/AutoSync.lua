local h = assert(loadfile("tests/PrivateGroup.lua"))("harness")
local people = {}
for index = 1, 5 do
    local client = h.make("Auto Friend " .. index, "AUTO1234")
    client.guild = "Auto Guild"; client.ns.db.settings.mode = "guild"
    client.profile.professions = {Cooking={rank=75,maxRank=150,recipes={{id=123,name="Food",reagents={}}}}}
    people[index] = client
end
for _, client in ipairs(people) do h.run(client, function(ns) ns:AutoSyncTick() end) end
local function pump(count)
    for index = 1, count do
        if index % 8 == 0 then
            for _, client in ipairs(people) do h.run(client, function(ns)
                ns:ProcessAutoSyncRequests()
                local active = 0
                for _ in pairs(ns.modules[2].autoActive or {}) do active = active + 1 end
                assert(active <= 2, "Automatic pulls must have at most two active senders")
            end) end
        end
        h.pump(1)
    end
end
pump(600)
for _, receiver in ipairs(people) do
    for _, sender in ipairs(people) do
        if receiver ~= sender then assert(receiver.ns.db.players[sender.key].professions.Cooking.recipes[1].id == 123) end
    end
end
local before = h.metrics.bytes
for _, client in ipairs(people) do h.run(client, function(ns) ns:AutoSyncTick() end) end
pump(100)
assert(h.metrics.bytes-before < 1000, "Unchanged automatic refresh must exchange only small manifests")
people[2].ns.db.players[people[1].key].professions = {}
people[2].ns.db.players[people[1].key].syncSections.R = nil
h.run(people[1], function(ns) ns:AutoSyncTick() end)
pump(150)
assert(people[2].ns.db.players[people[1].key].professions.Cooking.recipes[1].id == 123, "Automatic manifests must repair a missing recipe section")
people[1].ns.db.settings.mode = "offline"
local unchanged = h.metrics.bytes
h.run(people[1], function(ns) ns:AutoSyncTick(); ns:ProcessAutoSyncRequests() end)
h.pump(20)
assert(h.metrics.bytes == unchanged, "Offline clients must not automatically communicate")
print("PASS: automatic guild synchronization without clicks, missing recipe repair, unchanged manifest-only refresh, two-sender concurrency and Offline isolation")

local p, q = h.make("Private Auto One", "PRIVAUTO"), h.make("Private Auto Two", "PRIVAUTO")
people[#people+1], people[#people+2] = p, q
GetNumChannelMembers = function() return 2 end
GetChannelRosterInfo = function(_, index) return index == 1 and p.key or q.key end
for _, client in ipairs({p,q}) do
    h.click(client, function(ns) ns:UpdatePrivateChannel(true) end)
end
for _, client in ipairs({p,q}) do h.run(client, function(ns) ns:AutoSyncTick() end) end
pump(200)
assert(p.ns.db.players[q.key] and q.ns.db.players[p.key], "Joined private channels must discover and sync without Share my data")
assert(p.ns.db.players[q.key].privateGroup == "PRIVAUTO")
print("PASS: automatic private-channel roster discovery, code-checked handshake and profile pulls without manual publication")
