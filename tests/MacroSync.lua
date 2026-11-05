local h = assert(loadfile("tests/PrivateGroup.lua"))("harness")
local a, b = h.make("Kazu Zephyrus", "MACRO123"), h.make("Friend Player", "MACRO123")
for _, client in ipairs({a, b}) do
    h.run(client, function(ns)
        assert(loadfile("MacroUI.lua"))("ForeverTeamGear", ns)
        ns.db.settings.sharing.macros = true
    end)
    h.click(client, function(ns) ns:RequestSync(true) end)
end
h.pump(150)
b.ns.db.players[a.key] = nil
local body = "/cast Spell\n/say 100% | test\tvalue"
GetMacroInfo = function() return "Shared test", nil, body end
h.run(a, function(ns) assert(ns:ShareMacro(1)) end)
h.pump(50)
local received = b.ns.db.sharedMacros[a.key .. "|Shared test"]
assert(received and received.body == body and received.privateGroup == "MACRO123")
assert(received.icon and received.owner == a.key)
h.run(a, function(ns)
    ns:SendEncoded("M", { "Alias", 1, body, "Kazu Zephyrus-OtherBackend", 100 }, "WHISPER", b.key)
end)
h.pump(50)
assert(b.ns.db.sharedMacros[a.key .. "|Alias"], "Equivalent full character names must accept backend aliases")
h.run(a, function(ns)
    ns:SendEncoded("M", { "Forged", 1, body, "Somebody Else-Realm", 100 }, "WHISPER", b.key)
end)
h.pump(50)
assert(not b.ns.db.sharedMacros[a.key .. "|Forged"])
print("PASS: macro transport, missing icon, escaped multiline body, pre-profile receive, sender alias and forged-owner rejection")

h.run(a, function(ns) assert(ns:UnshareMacro({owner = a.key, name = "Shared test"})) end)
h.pump(50)
assert(b.ns.db.sharedMacros[a.key .. "|Shared test"] == nil, "Unshare must remove the connected receiver's copy")
h.run(b, function(ns)
    ns:AcceptSharedMacroRecord(received)
    assert(ns.db.sharedMacros[a.key .. "|Shared test"] == nil, "Delayed share packets must not undo revocation")
end)
h.run(a, function(ns) assert(ns:ShareMacro(1)) end)
h.pump(50)
assert(b.ns.db.sharedMacros[a.key .. "|Shared test"], "Explicit reshare after revocation must work")
print("PASS: remote unshare, stale share suppression and explicit reshare")
