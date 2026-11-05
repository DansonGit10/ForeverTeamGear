-- Run from the addon directory: lua tests/SyncScale.lua
local h = assert(loadfile("tests/PrivateGroup.lua"))("harness")
local people = {}
for index = 1, 20 do
    local client = h.make("Friend" .. index, "SCALE123")
    people[index] = client
    client.ns.db.settings.sharing.bags = true
    client.ns.db.settings.sharing.bank = true
    client.profile.inventory.bags["item:15210:0:0:0:0:0:123:456"] = 1
    client.profile.inventory.bags["item:15210:0:0:0:0:0:124:789"] = 2
    client.profile.inventory.bank["item:15210:0:0:0:0:0:-55:456"] = 1
    client.profile.professions = { Cooking = { rank = 300, maxRank = 300, recipes = {} } }
    for recipe = 1, 160 do
        client.profile.professions.Cooking.recipes[recipe] = {
            id = 10000 + recipe, outputItemID = 20000 + recipe, category = "Food", quantityMin = 1,
            reagents = { { id = 30000 + recipe, count = 2 }, { id = 40000 + recipe, count = 3 }, { id = 50000 + recipe, count = 1 } },
        }
    end
end
for _, client in ipairs(people) do h.click(client, function(ns) ns:RequestSync(true) end) end
h.pump(2400)
local coldBytes = h.metrics.bytes
for _, client in ipairs(people) do
    for _, peer in ipairs(people) do
        if peer ~= client then
            local profile = client.ns.db.players[peer.key]
            assert(profile and profile.syncSections.R and #profile.professions.Cooking.recipes == 160, "Cold sync must deliver complete recipes to every peer")
            assert(profile.playerID == peer.ns.db.settings.playerID and profile.playerName == peer.ns.db.settings.playerName, "Sync must preserve player identity")
            assert(profile.inventory.bags["item:15210:0:0:0:0:0:123:456"] == 1)
            assert(profile.inventory.bags["item:15210:0:0:0:0:0:124:789"] == 2)
            assert(profile.inventory.bank["item:15210:0:0:0:0:0:-55:456"] == 1)
            assert(profile.inventory.bags[123] == 8 and profile.inventory.bank[456] == 10)
        end
    end
    assert(#client.ns.modules[2].queue == 0, "Cold sync queues must drain")
end
local before = h.metrics.bytes
h.click(people[1], function(ns) ns:BroadcastProfile(0, { priority = 1 }) end)
h.pump(400)
local warmBytes = h.metrics.bytes - before
assert(warmBytes < coldBytes / 20, "Unchanged sync must exchange small requests/completion messages, not full profiles")
before = h.metrics.bytes
people[1].profile.inventory.bags[123] = 9
h.run(people[1], function(ns) ns:BroadcastProfile() end)
h.pump(400)
local bagBytes = h.metrics.bytes - before
assert(bagBytes < coldBytes / 30, "A bag update must not retransmit large profession sections")
for index = 2, 20 do
    local received = people[index].ns.db.players[people[1].key]
    assert(received.inventory.bags[123] == 9 and received.inventory.bank[456] == 10)
    assert(#received.professions.Cooking.recipes == 160, "Partial updates must preserve unrelated sections")
end
-- A recipient cannot trigger peer uploads; repair requires the owner to publish.
people[2].ns.db.players[people[1].key].syncSections.R = nil
people[2].ns.db.players[people[1].key].professions = {}
h.click(people[2], function(ns) ns:RequestSync(true) end)
h.pump(500)
assert(people[2].ns.db.players[people[1].key].professions.Cooking == nil)
h.click(people[1], function(ns) ns:RequestSync(true) end)
h.pump(2400)
assert(#people[2].ns.db.players[people[1].key].professions.Cooking.recipes == 160)
-- Priority work must overtake a background profession transfer.
people[1].profile.professions.Cooking.rank = 301
h.run(people[1], function(ns)
    ns:SendProfile("WHISPER", people[2].key)
    ns:SendProfile("WHISPER", people[3].key, { priority = 1 })
    ns.modules[2]:FlushOne()
end)
assert(h.metrics.last.target == people[3].name, "Requested sync must overtake background work")
h.pump(400)
-- Change away and back before transmission; a stale queued snapshot must be discarded.
people[1].profile.inventory.bags[123] = 50
h.run(people[1], function(ns) ns:SendProfile("WHISPER", people[2].key) end)
people[1].profile.inventory.bags[123] = 9
h.run(people[1], function(ns) ns:SendProfile("WHISPER", people[2].key) end)
h.pump(100)
assert(people[2].ns.db.players[people[1].key].inventory.bags[123] == 9)
-- A newer urgent snapshot can finish before an already-started background one.
people[1].profile.professions.Cooking.rank = 302
h.run(people[1], function(ns) ns:SendProfile("WHISPER", people[2].key); ns.modules[2]:FlushOne() end)
people[1].profile.professions.Cooking.rank = 303
h.run(people[1], function(ns) ns:SendProfile("WHISPER", people[2].key, { priority = 1 }) end)
h.pump(400)
assert(people[2].ns.db.players[people[1].key].professions.Cooking.rank == 303, "Late background transfers must not overwrite newer section revisions")
people[1].profile.inventory.bags[123] = 10
h.run(people[1], function(ns) ns:BroadcastProfile(15); ns:BroadcastProfile(0, { priority = 1 }) end)
h.pump(1)
local queued = people[1].ns:SyncStatus()
assert(queued > 0, "An explicit sync must advance an already scheduled 15-second inventory update")
h.pump(300)
for recipe = 161, 1200 do
    people[1].profile.professions.Cooking.recipes[recipe] = { id = 10000 + recipe, outputItemID = 20000 + recipe, category = "Food", reagents = { { id = 30000 + recipe, count = 1 } } }
end
h.run(people[1], function(ns) ns:SendProfile("WHISPER", people[2].key, { priority = 1 }) end)
h.pump(1500)
assert(#people[2].ns.db.players[people[1].key].professions.Cooking.recipes == 1200, "A profession section exceeding the old 250-packet limit must finish")
print(string.format("PASS: 20 clients/380 peer profiles; cold %d bytes, unchanged refresh %d bytes, one bag update to 19 peers %d bytes; partial merge, manifest repair, priority scheduling, stale queue replacement", coldBytes, warmBytes, bagBytes))

local stableID = people[1].ns.db.settings.playerID
people[1].ns.db.settings.playerName = "Renamed player"
h.run(people[1], function(ns) ns:SendProfile("WHISPER", people[2].key) end)
h.pump(100)
assert(people[2].ns.db.players[people[1].key].playerID == stableID)
assert(people[2].ns.db.players[people[1].key].playerName == "Renamed player", "Identity changes must sync even when inventory is unchanged")
