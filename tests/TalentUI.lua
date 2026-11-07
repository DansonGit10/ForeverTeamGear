local widgets = {}
local function widget(kind, parent)
    local obj = {kind = kind, parent = parent, shown = false, TitleText = {SetText = function() end}}
    setmetatable(obj, {__index = function(_, key)
        if key == "CreateTexture" or key == "CreateFontString" then return function(self) return widget(key, self) end end
        if key == "SetPoint" then return function(self, ...) self.point = {...} end end
        if key == "SetParent" then return function(self, p) self.parent = p end end
        if key == "SetText" then return function(self, text) self.text = text end end
        if key == "SetTexture" then return function(self, texture) self.texture = texture end end
        if key == "SetDesaturated" then return function(self, value) self.desaturated = value end end
        if key == "Show" then return function(self) self.shown = true end end
        if key == "Hide" then return function(self) self.shown = false end end
        return function() end
    end})
    widgets[#widgets+1] = obj
    return obj
end
CreateFrame = function(kind, name, parent) return widget(kind, parent) end
local nodes = {
    [1] = {ID=1,posX=0,posY=0,groupIDs={1},entryIDs={1}},
    [2] = {ID=2,posX=100,posY=100,groupIDs={1},entryIDs={2}},
    [3] = {ID=3,posX=0,posY=0,groupIDs={2},entryIDs={3}},
    [4] = {ID=4,posX=100,posY=0,groupIDs={2},entryIDs={4}},
    [5] = {ID=5,posX=10000,posY=10000,isVisible=false,groupIDs={2},entryIDs={5}},
    [6] = {ID=6,posX=0,posY=0,groupIDs={2},entryIDs={6}},
    [7] = {ID=7,posX=0,posY=0,groupIDs={3},entryIDs={7}},
}
C_ClassTalents = {InitializeViewLoadout=function() end}
C_Traits = {
    GetGroupDisplayInfoByTreeID=function() return {{groupID=1,displayName="Discipline",orderIndex=1},{groupID=2,displayName="Holy",orderIndex=2},{groupID=3,displayName="Shadow Magic",orderIndex=3}} end,
    GetTreeNodes=function() return {1,2,3,4,5,6,7} end,
    GetNodeInfo=function(_, id) return nodes[id] end,
    GetEntryInfo=function(_, id) return {definitionID=id,maxRanks=5} end,
    GetDefinitionInfo=function(id) return {spellID=id} end,
}
C_Spell = {GetSpellName=function(id) return "Talent " .. id end, GetSpellTexture=function(id) return id end}
local ns = {db={players={Priest={key="Priest",classToken="PRIEST",level=30,talents={specID=1,treeID=1,groups={},nodes={[6]={rank=2,entryID=6},[7]={rank=0,entryID=7}}}}}},IsVisibleCharacter=function() return true end}
assert(loadfile("TalentUI.lua"))("ForeverTeamGear", ns)
ns:OpenTalentBrowser("Priest")
local buttons, shadow, holyRight = 0, false, false
for _, value in ipairs(widgets) do
    if value.kind == "Button" and value.shown then
        buttons = buttons + 1
        assert(value.talentName ~= "Talent 3" and value.talentName ~= "Talent 5")
        if value.talentName == "Talent 4" then holyRight = value.point[2] == 266 end
        if value.talentName == "Talent 7" then assert(value.icon.desaturated, "Zero-rank records must stay inactive") end
    end
    if type(value.texture) == "string" and value.texture:find("PriestShadow-TopLeft",1,true) then shadow = true end
end
assert(buttons == 5 and shadow and holyRight)
print("PASS: Shadow Magic background, hidden-node filtering, selected alternate deduplication, layout bounds and zero-rank styling")
