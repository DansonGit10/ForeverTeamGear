local h = assert(loadfile("tests/PrivateGroup.lua"))("harness")
local people = {h.make("Leader One", "PARTY123"), h.make("Friend Two", "PARTY123"), h.make("Friend Three", "PARTY123"), h.make("Outside Four", "PARTY123")}
local members = {people[1],people[2],people[3]}
local grouped, raid, requests = true, false, 0
IsInGroup = function() return grouped end
IsInRaid = function() return raid end
GetNumSubgroupMembers = function() return 2 end
GetNumGroupMembers = function() return 3 end
for _, client in ipairs(people) do
    client.ns.IsCurrentGroupCharacter = function(_, key)
        if not grouped or client == people[4] then return false end
        for _, member in ipairs(members) do if member.key == key then return true end end
        return false
    end
    client.ns.UnitKey = function(_, unit)
        local index = tonumber(unit:match("%d+"))
        if unit:match("^raid") then return members[index] and members[index].key end
        local other = {}
        for _, member in ipairs(members) do if member ~= client then other[#other+1] = member end end
        return other[index] and other[index].key
    end
    client.ns.privatePeers = {}
    for _, other in ipairs(people) do if client ~= other then client.ns.privatePeers[other.key] = "PARTY123" end end
end
local send = C_ChatInfo.SendAddonMessage
C_ChatInfo.SendAddonMessage = function(prefix, message, channel, target)
    if channel == "PARTY" or channel == "RAID" then
        requests = requests + 1
        assert(message == "S|PARTY123", "Group channels must carry only a sync request")
        for _, client in ipairs(people) do h.run(client, function(ns) ns.modules[2]:OnMessage(prefix,message,channel,people[1].key) end) end
        h.run(people[1], function() end)
    else send(prefix,message,channel,target) end
end
h.run(people[1], function(ns) assert(ns:RequestGroupSync()); assert(ns:IsGroupSyncing()); assert(not ns:RequestGroupSync()) end)
h.pump(150)
for index = 2,3 do
    assert(people[1].ns.db.players[people[index].key], "Requester must receive party profiles")
    assert(people[index].ns.db.players[people[1].key], "Party peers must receive requester profile")
end
assert(not people[1].ns.db.players[people[4].key] and next(people[4].ns.db.players) == nil)
assert(requests == 1)
h.run(people[1], function(ns) assert(not ns:IsGroupSyncing(), "Busy state must clear after transfers drain") end)
raid = true
h.pump(250)
h.run(people[1], function(ns) assert(ns:RequestGroupSync()) end)
h.pump(150)
assert(requests == 2)
grouped = false
h.run(people[1], function(ns) assert(not ns:RequestGroupSync()) end)
assert(requests == 2)
print("PASS: party/raid request and targeted profile exchange, outsiders excluded, cooldown and solo suppression")
