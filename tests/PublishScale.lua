local h = assert(loadfile("tests/PrivateGroup.lua"))("harness")
local people, members = {}, {}
for index = 1, 150 do
    local client = h.make("Member " .. index, "SCALE150")
    client.guild = "Large guild"
    people[index], members[client.key] = client, true
end
for _, client in ipairs(people) do
    client.ns.db.settings.mode = "guild"
    client.ns.guildMembers = members
end
h.click(people[1], function(ns) ns:RequestSync(true) end)
h.pump(150)
for index = 2, #people do
    assert(people[index].ns.db.players[people[1].key], "All guild receivers must save the publisher")
    assert(#people[index].ns.modules[2].queue == 0, "Receiving must not generate reply uploads")
    assert(people[1].ns.db.players[people[index].key] == nil, "One publication must not fetch 149 profiles")
end
local bytes = h.metrics.bytes
h.run(people[2], function(ns)
    ns.modules[2]:OnMessage(ns.prefix, "Q|legacy|session|", "GUILD", people[1].key)
    ns:Emit("GROUP_ROSTER_UPDATE")
    ns:Emit("GUILD_ROSTER_UPDATE")
end)
h.pump(100)
assert(h.metrics.bytes == bytes, "Legacy requests and roster changes must not cause uploads")
h.run(people[2], function(ns)
    ns.guildMembers = members
    ns.modules[2]:OnMessage(ns.prefix, "D|P|bounded|1|2|" .. string.rep("x", 180), "GUILD", people[1].key)
    assert(ns.modules[2].incomingBytes == 180)
end)
h.pump(1000)
h.run(people[2], function(ns) ns.modules[2]:OnMessage(ns.prefix, "D|P|cleanup|1|2|x", "GUILD", people[1].key) end)
assert(people[2].ns.modules[2].incomingBytes == 1, "Expired transfers must release receive memory")
print("PASS: 150 guild clients, one publisher, 149 receivers, zero profile replies; legacy request/roster suppression and bounded receive cleanup")
