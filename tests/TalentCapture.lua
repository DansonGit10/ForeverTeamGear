local events,timers={},{}
local rank,mode=2,"active"
local ns={modules={},db={ownCharacters={},settings={},players={}},PlayerKey=function() return "Priest" end,UnitIdentity=function() return "Priest" end,Now=function() return 100 end,
    RefreshWindow=function() end,On=function(_,event,fn) events[event]=fn end}
local broadcasts=0
ns.BroadcastProfile=function() broadcasts=broadcasts+1 end
C_Timer={After=function(_,fn) timers[#timers+1]=fn end}
UnitClass=function() return "Priest","PRIEST",5 end
UnitLevel=function() return 40 end
GetInventoryItemLink=function() return nil end
C_ClassTalents={GetActiveConfigID=function() return 1 end}
C_Traits={GetConfigInfo=function() return {treeIDs={10},specID=256} end,
    GetGroupDisplayInfoByTreeID=function() return {{groupID=1,displayName="Discipline",orderIndex=1},{groupID=2,displayName="Holy",orderIndex=2},{groupID=3,displayName="Shadow Magic",orderIndex=3}} end,
    GetTreeNodes=function() return {101,102,103} end,
    GetNodeInfo=function(_,id)
        if mode=="loading" then return nil end
        local node={groupIDs={id-100},entryIDs={id+100},activeEntry={entryID=id+100}}
        if mode=="entry" then node.activeEntry.rank=id==101 and rank or 0
        elseif mode=="current" then node.currentRank=id==101 and rank or 0
        else node.currentRank=0; node.activeRank=id==101 and rank or 0 end
        return node
    end,
    GetGroupCurrencyInfo=function() error("Currency API temporarily unavailable") end}
assert(loadfile("Scanner.lua"))("ForeverTeamGear",ns)
local profile=ns:ScanProfile()
assert(profile.talents.nodes[101].rank==2 and profile.talents.groups[1].points==2 and profile.specName:find("Discipline 2",1,true))
ns.modules[1]:Initialize()
mode="loading"
events.PLAYER_TALENT_UPDATE()
local first=table.remove(timers,1); first()
assert(profile.talents.nodes[101].rank==2 and profile.specID==256, "Incomplete scans must preserve old ranks and spec metadata")
rank,mode=4,"active"
while #timers>0 do table.remove(timers,1)() end
assert(profile.talents.nodes[101].rank==4 and broadcasts==1, "Classic update events must retry and publish changed ranks")
rank,mode=3,"current"
ns:ScanProfile()
assert(profile.talents.nodes[101].rank==3, "Current-rank API must support decreases")
rank,mode=1,"entry"
ns:ScanProfile()
assert(profile.talents.nodes[101].rank==1, "Entry-rank API must be supported")
rank=0
ns:ScanProfile()
assert(next(profile.talents.nodes)==nil and profile.talents.groups[1].points==0, "A complete respec must clear old allocated ranks")
local queued=#timers
events.TRAIT_CONFIG_UPDATED(-1)
assert(#timers==queued, "Read-only preview events must not trigger capture loops")
print("PASS: Priest talent capture, rank API variants, missing currency fallback, classic events, delayed retry, decreases, respec and preview-loop suppression")
