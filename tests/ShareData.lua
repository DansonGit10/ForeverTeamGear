local h = assert(loadfile("tests/PrivateGroup.lua"))("harness")
local a, b = h.make("Guild Sender", "SHARE123"), h.make("Guild Receiver", "SHARE123")
a.guild, b.guild = "Guild", "Guild"
for _, client in ipairs({a,b}) do
    client.ns.db.settings.mode = "guild"
    client.ns.guildMembers = {}
end
h.click(a, function(ns) ns:RequestSync(true) end)
h.pump(120)
assert(b.ns.db.players[a.key], "Guild publication must work without preloaded roster")
assert(a.ns.db.players[b.key] == nil, "Share my data must not request a profile reply")
b.ns.db.players[a.key] = nil
h.click(a, function(ns)
    ns:RequestSync(true)
    ns:BroadcastProfile(0.5)
    ns:BroadcastProfile(15)
end)
h.pump(120)
assert(b.ns.db.players[a.key] and b.ns.db.players[a.key].syncSections.E, "A background scan must not erase forced manual sharing")
local c, d = h.make("Private Sender", "LATE1234"), h.make("Private Receiver", "LATE1234")
h.click(c, function(ns)
    ns.DiscoverPrivateGroup = function() end -- Simulate slow channel/presence delivery.
    ns:RequestSync(true)
end)
h.pump(40)
assert(d.ns.db.players[c.key] == nil)
h.run(d, function(ns) ns:SendPrivateHello(c.key) end)
h.pump(120)
assert(d.ns.db.players[c.key], "A late private handshake must complete the pending own-data publication")
assert(c.ns.db.players[d.key] == nil, "A receiving private peer must not upload its own profile automatically")
print("PASS: Share my data via guild with unloaded roster, forced publication survives background scans, late private discovery and zero profile replies")
