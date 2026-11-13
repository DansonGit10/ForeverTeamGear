local h=assert(loadfile("tests/PrivateGroup.lua"))("harness")
local a,b=h.make("Priest Sender","PRIEST12"),h.make("Receiver Friend","PRIEST12")
a.guild,b.guild="Guild","Guild"
a.ns.db.settings.mode,b.ns.db.settings.mode="guild","guild"
a.profile.classToken,a.profile.level,a.profile.specID="PRIEST",40,1487
a.profile.specName="Discipline 0 / Holy 31 / Shadow Magic 0"
a.profile.talents={treeID=1114,specID=1487,groups={{id=11608,name="Discipline",points=0},{id=11615,name="Holy",points=31},{id=11622,name="Shadow Magic",points=0}},nodes={[1001]={rank=5,entryID=2001}}}
b.ns.db.players[a.key]={key=a.key,name=a.name,classToken="PRIEST",level=30,specID=1487,specName="Discipline 20 / Holy 0 / Shadow Magic 0",updated=99,sender=a.key,
    talents={treeID=1114,specID=1487,groups={{id=11608,name="Discipline",points=20}},nodes={[1000]={rank=5,entryID=2000}}},
    syncVersions={I=2335,T=2294,R=2352,E=2391,B=2390,K=2266},syncSections={},gear={},professions={},inventory={bags={},bank={}}}
a.ns.db.syncRevision=0
h.run(a,function(ns) ns:SendProfile("GUILD",nil,{force=true}) end)
h.pump(150)
local received=b.ns.db.players[a.key]
assert(received.level==40,"A lower reset counter must not freeze the receiver at level 30")
assert(received.specName==a.profile.specName and received.talents.nodes[1001] and not received.talents.nodes[1000],"New Priest talents must replace the frozen build")
h.run(a,function(ns) ns:ResetCommunication(); ns.db.syncRevision=0; ns.Now=function() return 101 end end)
a.profile.level,a.profile.updated=41,101
h.run(a,function(ns) ns:SendProfile("GUILD",nil,{force=true}) end)
h.pump(150)
assert(b.ns.db.players[a.key].level==41,"A later sender reset must also recover without deleting receiver data")
print("PASS: frozen level-30 Priest snapshot with real historical section counters updates to level 40 and a new talent build; later saved-counter resets also recover")
