local h = assert(loadfile("tests/PrivateGroup.lua"))("harness")
local a, b = h.make("Cook Sender", "COOK1234"), h.make("Cook Receiver", "COOK1234")
local ready, empty, missing = false, false, false
C_TradeSkillUI = {
    IsTradeSkillReady = function() return ready end,
    GetBaseProfessionInfo = function() return {professionName="Cooking",skillLevel=75,maxSkillLevel=150,professionIcon=42} end,
    GetAllRecipeIDs = function() return empty and {} or {1001,1002} end,
    GetRecipeInfo = function(id)
        if missing then return nil end
        return {learned=id==1001,name="Spiced Wolf Meat",icon=99,categoryID=1}
    end,
    GetRecipeSchematic = function() return {outputItemID=2001,quantityMin=1,quantityMax=1,reagentSlotSchematics={{required=true,quantityRequired=2,reagents={{itemID=3001}}}}} end,
}
a.profile.professions = {Cooking={rank=75,maxRank=150,recipes={{id=77,name="Previously captured"}}}}
h.run(a, function(ns)
    assert(not ns:ScanRecipes() and ns.db.players[a.key] == nil)
    assert(a.profile.professions.Cooking.recipes[1].id == 77)
    ready, empty = true, true
    assert(not ns:ScanRecipes() and a.profile.professions.Cooking.recipes[1].id == 77)
    empty, missing = false, true
    assert(not ns:ScanRecipes() and a.profile.professions.Cooking.recipes[1].id == 77)
    missing = false
end)
ready = false
h.run(a, function(ns) ns.modules[4]:Initialize(); ns:Emit("TRADE_SKILL_SHOW") end)
h.pump(5)
ready = true
h.pump(20)
assert(a.profile.professions.Cooking.recipes[1].id == 1001, "Recipe scans must retry while the profession window is loading")
for _, client in ipairs({a,b}) do h.click(client, function(ns) ns:RequestSync(true) end) end
h.pump(180)
local received = b.ns.db.players[a.key].professions.Cooking.recipes
assert(#received == 1 and received[1].id == 1001 and received[1].name == "Spiced Wolf Meat" and received[1].icon == 99)
assert(received[1].reagents[1].id == 3001 and received[1].reagents[1].count == 2)
assert(received[1].outputItemID == 2001)
print("PASS: unready/empty/incomplete recipe scans preserve saved data; delayed capture retries; profession recipes, names, icons, output and reagents sync end-to-end")
