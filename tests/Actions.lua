-- Run from the addon directory: lua tests/Actions.lua
local function widget()
    return setmetatable({ scripts = {}, shown = false, text = "" }, { __index = function(_, key)
        if key == "CreateTexture" or key == "CreateFontString" then return widget end
        if key == "SetScript" then return function(self, event, fn) self.scripts[event] = fn end end
        if key == "Show" then return function(self) self.shown = true end end
        if key == "Hide" then return function(self) self.shown = false end end
        if key == "IsShown" then return function(self) return self.shown end end
        if key == "SetText" then return function(self, text) self.text = text end end
        if key == "SetEnabled" then return function(self, value) self.enabled = value end end
        return function() end
    end })
end
CreateFrame = widget
RunMacroText = function() error("A shared macro must never run") end
MAX_ACCOUNT_MACROS = 120
local data = {
    [1] = { "First", 1, "/say first" },
    [2] = { "Second", 2, "/say second" },
    [121] = { "Character", 3, "/say character" },
}
GetNumMacros = function() return 2, 1 end
GetMacroInfo = function(index) if data[index] then return unpack(data[index]) end end
local sharing, connected, refreshes, outgoing = false, true, 0, {}
local ns = { modules = {}, db = { players = {}, boe = {}, settings = {} }, mainWindow = widget(), privatePeers = { Friend = true } }
ns.SameCharacter = function(_, a, b) return a == b end
ns.On, ns.Print = function() end, function() end
ns.PlayerKey = function() return "Me" end
ns.Now = function() return 100 end
ns.Mode = function() return "group" end
ns.CanShare = function() return sharing end
ns.IsPrivatePeer = function() return connected end
ns.IsVisibleCharacter = function(_, key) return key == "Me" or key == "Friend" end
ns.RefreshWindow = function() refreshes = refreshes + 1 end
ns.BroadcastMacro = function(_, macro) outgoing[#outgoing + 1] = macro end
assert(loadfile("Loot.lua"))("ForeverTeamGear", ns)
-- A vacant off-hand must not hide the actual weapon or produce a false +30.
ns.db.players.Me = { key = "Me", classToken = "DRUID", level = 60, gear = { [16] = { id = 1, ilvl = 25 } } }
local comparison = ns:ComparisonFor({ equipLoc = "INVTYPE_WEAPON", classID = 2, subclassID = 15, ilvl = 30 })[1]
assert(comparison.slot == 16 and comparison.equipped.id == 1 and comparison.delta == 5)
ns.db.players.Me.classToken = "ROGUE"
comparison = ns:ComparisonFor({ equipLoc = "INVTYPE_WEAPON", classID = 2, subclassID = 15, ilvl = 30 })[1]
assert(comparison.slot == 16 and comparison.delta == 5)
ns.db.players.Me.gear[17] = { id = 2, ilvl = 35 }
comparison = ns:ComparisonFor({ equipLoc = "INVTYPE_WEAPON", classID = 2, subclassID = 15, ilvl = 30 })[1]
assert(#comparison.weaponComparisons == 2)
assert(comparison.weaponComparisons[1].equipped.id == 1 and comparison.weaponComparisons[1].delta == 5)
assert(comparison.weaponComparisons[2].equipped.id == 2 and comparison.weaponComparisons[2].delta == -5)
for _, entry in ipairs({ { "INVTYPE_TRINKET", 13, 14 }, { "INVTYPE_FINGER", 11, 12 } }) do
    ns.db.players.Me.gear[entry[2]] = { id = 3, ilvl = 20 }
    ns.db.players.Me.gear[entry[3]] = { id = 4, ilvl = 40 }
    local paired = ns:ComparisonFor({ equipLoc = entry[1], ilvl = 30 })[1].weaponComparisons
    assert(#paired == 2 and paired[1].slot == entry[2] and paired[2].slot == entry[3])
    assert(paired[1].equipped.id == 3 and paired[1].delta == 10)
    assert(paired[2].equipped.id == 4 and paired[2].delta == -10)
    ns.db.players.Me.gear[entry[3]] = nil
    paired = ns:ComparisonFor({ equipLoc = entry[1], ilvl = 30 })[1].weaponComparisons
    assert(#paired == 2 and not paired[2].equipped and paired[2].delta == 30)
end
ns.db.players.Me = { key = "Me", sender = "Me", classToken = "ROGUE", level = 60, gear = {} }
comparison = ns:ComparisonFor({ equipLoc = "INVTYPE_WEAPON", classID = 2, subclassID = 15, ilvl = 30 })[1]
assert(not comparison.usable and comparison.unusableReason:find("Equipment not received"))
ns.db.players = {}
local first, second = { id = 1 }, { id = 2 }
ns.db.boe = { first, second }
ForeverTeamGearUpgradePopup = { currentRecord = second, Hide = function(self) self.hidden = true end }
assert(ns:DeleteBoe(second) and #ns.db.boe == 1 and ns.db.boe[1] == first)
assert(second.deleted and ForeverTeamGearUpgradePopup.hidden and refreshes == 1)
assert(not ns:DeleteBoe(second) and refreshes == 1)
ns:AnnounceBoeUpgrades(second) -- deleted drops must not reopen scheduled popups
ns.db.players.Me = {key="Me",classToken="ROGUE",level=60}
local comparisons = 0
ns.ComparisonFor = function() comparisons = comparisons + 1; return {} end
ns:AnnounceBoeUpgrades({ id = 10, looter = "Me", quality = 2, classID = 2, subclassID = 15, equipLoc = "INVTYPE_WEAPON", minLevel = 1 })
assert(comparisons == 0, "Automatic alerts must default to off")
ns.db.settings.alertsEnabled = true
ns:AnnounceBoeUpgrades({ id = 10, looter = "Me", quality = 2, classID = 2, subclassID = 15, equipLoc = "INVTYPE_WEAPON", minLevel = 1 })
assert(comparisons == 1, "Enabled automatic alerts must compare drops")
ns.db.settings.alertsEnabled = false
ns:AnnounceBoeUpgrades({ id = 10, looter = "Me", quality = 2, classID = 2, subclassID = 15, equipLoc = "INVTYPE_WEAPON", minLevel = 1 }, true)
assert(comparisons == 2, "Manual comparisons must work with alerts off")
ns.db.settings.alertsEnabled = true
ns.db.players.Me = {key="Me",classToken="PRIEST",level=20}
local leather = {id=20,looter="Friend",quality=2,classID=4,subclassID=2,equipLoc="INVTYPE_CHEST",minLevel=5}
assert(not ns:CanReceiveBoeAlert(leather))
ns:AnnounceBoeUpgrades(leather)
assert(comparisons == 2, "Another player's usable item must not trigger an alert for an incompatible local class")
local tooHigh = {id=21,looter="Friend",quality=2,classID=4,subclassID=1,equipLoc="INVTYPE_CHEST",minLevel=30}
assert(not ns:CanReceiveBoeAlert(tooHigh))
ns:AnnounceBoeUpgrades(tooHigh)
assert(comparisons == 2, "Level requirements must be checked before automatic comparisons")
local cloth = {id=22,looter="Friend",quality=2,classID=4,subclassID=1,equipLoc="INVTYPE_CHEST",minLevel=10}
assert(ns:CanReceiveBoeAlert(cloth))
ns:AnnounceBoeUpgrades(cloth)
assert(comparisons == 3)
assert(not ns:CanReceiveBoeAlert({id=23,looter="Friend"}), "Unknown item classification must not trigger automatic alerts")
assert(not ns:CanReceiveBoeAlert({id=24,classID=2,subclassID=7,equipLoc="INVTYPE_WEAPON",minLevel=1}), "Priests cannot use swords")
ns:AnnounceBoeUpgrades(leather, true)
assert(comparisons == 4, "Manual team comparisons must remain available")
print("PASS: local class, armor, weapon and level eligibility gate automatic alerts; unknown data is suppressed; manual comparisons preserved")


assert(loadfile("MacroUI.lua"))("ForeverTeamGear", ns)
local ui = ns.modules[2]
ui:Initialize()
local own = ns:OwnMacros()
assert(#own == 3 and own[3].index == 121 and own[3].body == "/say character")
ui.frame:Show(); ui:Refresh(); ui:Select(own[3])
assert(not ui.share.enabled)
ns:ShareMacro(121); assert(#outgoing == 0 and next(ns.db.sharedMacros) == nil)
sharing = true
ui:Refresh(); assert(ui.share.enabled and ui.selected.index == 121)
ui.share.scripts.OnClick()
assert(#outgoing == 1 and outgoing[1].name == "Character" and outgoing[1].body == "/say character")
assert(ns.db.sharedMacros["Me|Character"])
connected = false
ns:ShareMacro(1); assert(#outgoing == 1)
connected = true
ns:ShareMacro(999); assert(#outgoing == 1)
data[121] = nil
GetNumMacros = function() return 2, 0 end
ui:Refresh(); assert(ui.selected == nil and not ui.share.enabled and ui.body.text == "")
ns:AcceptSharedMacroRecord({ owner = "Friend", name = "Remote", body = "/run do_not_execute()", at = 101 })
ns:AcceptSharedMacroRecord({ owner = "Outsider", name = "Hidden", body = "secret", at = 102 })
ui.sharedButton.scripts.OnClick()
ui.macroPlayer = "Friend"; ui:Refresh()
assert(ui.view == "shared" and ui.rows[1].macro.name == "Remote")
ui.rows[1].scripts.OnClick(ui.rows[1])
assert(ui.body.text == "/run do_not_execute()" and not ui.share.enabled)
assert(rawget(ui.rows[3], "macro") == nil)
print("PASS: individual local BoE deletion, pending popup suppression, own account/character macro indexing, privacy gate, no-peer gate, selected-only sharing, removed macro selection, received text preview without execution, audience filtering")

-- Loot detection must retain the exact suffix/seed hyperlink through cache retries.
local loot = ns.modules[1]
local variant = "|cff1eff00|Hitem:15210:0:0:0:0:0:123:456|h[Blade of the Bear]|h|r"
local cached = false
C_Item = { GetItemInfo = function(reference)
    assert(reference == variant)
    if cached then return "Blade", "item:15210", 2, 30, 20, "Weapon", "Sword", 1, "INVTYPE_WEAPON", 1, 0, 2, 7, 2 end
end, RequestLoadItemDataByID = function(id) assert(id == 15210) end }
ns.BroadcastBoe, ns.BroadcastProfile, ns.RequestSync = function() end, function() end, function() end
loot:Consider(variant, 1)
assert(loot.pending[variant] == 1)
cached = true
loot.pending[variant] = nil
loot:Consider(variant, 1)
assert(ns.db.boe[1].link == variant and ns.db.boe[1].name == "Blade of the Bear")
print("PASS: exact random-stat BoE hyperlink and pending-cache identity")

ns.db.settings.alertMinQuality = 3
assert(not ns:AllowsAutomaticAlert(2) and ns:AllowsAutomaticAlert(3) and ns:AllowsAutomaticAlert(4))
assert(not ns:AllowsAutomaticAlert(nil))
ns.db.settings.alertMinQuality = -1
assert(not ns:AllowsAutomaticAlert(5))
ns.db.settings.alertMinQuality = 0
assert(ns:AllowsAutomaticAlert(0))
print("PASS: minimum rarity includes higher qualities; Off and unknown quality suppress automatic alerts")

-- The title-bar X must close the same popup as Dismiss.
local popup
CreateFrame = function(kind, name, parent, template)
    local value = widget()
    value.GetFrameLevel = function() return 1 end
    if name == "ForeverTeamGearUpgradePopup" then
        value.TitleText, value.CloseButton = widget(), widget()
        popup = value
    end
    return value
end
C_Item = {}
ns.db.players.Me = { key = "Me", name = "Me", classToken = "ROGUE", gear = {} }
ns:TestUpgradeNotice("Me")
assert(popup and popup.shown and popup.CloseButton.scripts.OnClick)
popup.CloseButton.scripts.OnClick()
assert(not popup.shown, "The X button must hide the upgrade alert")
print("PASS: alert title-bar close button")

local remote = ns.db.sharedMacros["Friend|Remote"]
assert(ns:DeleteSharedMacro(remote) and ns.db.sharedMacros["Friend|Remote"] == nil)
ns:AcceptSharedMacroRecord(remote)
assert(ns.db.sharedMacros["Friend|Remote"] == nil, "Deleted cached copies must stay removed on duplicate packets")
remote.at = remote.at + 1
ns:AcceptSharedMacroRecord(remote)
assert(ns.db.sharedMacros["Friend|Remote"], "An explicitly reshared newer macro may reappear")
local expired, recent = {at = 1}, {at = 200000}
ns.Now = function() return 200000 end
ns.db.boe = { expired, recent }
assert(ns:PruneBoe() and expired.deleted and #ns.db.boe == 1)
ns:ClearBoe()
assert(#ns.db.boe == 0 and recent.deleted)
print("PASS: local macro deletion, duplicate suppression, explicit reshare, 48-hour BoE expiry and clear all")

-- Dismissed alerts must remain suppressed across duplicate packets and reload.
ns.db.players.Me.level = 60
ns.db.settings.alertMinQuality = 0
ns.ComparisonFor = function() return {{profile=ns.db.players.Me,usable=true,delta=10,slot=16}} end
local alert = {id=15210,looter="Me",at=200000,quality=2,classID=2,subclassID=15,equipLoc="INVTYPE_WEAPON",minLevel=1,
    link="|cff1eff00|Hitem:15210:0:0:0:0:0:123:456:30:1|h[Blade of the Bear]|h|r",name="Blade of the Bear",ilvl=30}
ns:AnnounceBoeUpgrades(alert)
assert(popup.shown)
popup.CloseButton.scripts.OnClick()
assert(not popup.shown and next(ns.db.dismissedBoeAlerts))
local reloaded = {modules={}}
for key,value in pairs(ns) do if key~="modules" then reloaded[key]=value end end
assert(loadfile("Loot.lua"))("ForeverTeamGear",reloaded)
reloaded.ComparisonFor=ns.ComparisonFor
local previousPopup = popup
local duplicate = {}
for key,value in pairs(alert) do duplicate[key]=value end
duplicate.link="|cff1eff00|Hitem:15210:0:0:0:0:0:123:456:31:2|h[Blade of the Bear]|h|r"
reloaded:AnnounceBoeUpgrades(duplicate)
assert(popup==previousPopup and not popup.shown, "Dismiss must survive reload and viewer-dependent link changes")
local created = {}
local create = CreateFrame
CreateFrame = function(...)
    local value=create(...); created[#created+1]=value; return value
end
reloaded:AnnounceBoeUpgrades(alert,true)
assert(popup.shown, "Manual comparison must still open dismissed drops")
local dismiss
for _,value in ipairs(created) do if value.text=="Dismiss" then dismiss=value end end
assert(dismiss)
dismiss.scripts.OnClick()
assert(not popup.shown)
duplicate.at=200060
reloaded:AnnounceBoeUpgrades(duplicate)
assert(popup.shown, "A distinct later drop must still be eligible for an alert")
print("PASS: X and Dismiss persist suppression across reload, duplicate delivery and link-level changes; manual compare and new drops remain available")

local currentLink=alert.link
NUM_BAG_SLOTS=0
C_Container={GetContainerNumSlots=function() return 1 end,GetContainerItemInfo=function() return {itemID=15210,hyperlink=currentLink,stackCount=1} end}
local count=0
local scanner=ns.modules[1]
scanner.counts={}
scanner.Consider=function() count=count+1 end
scanner:Scan()
currentLink=duplicate.link
scanner:Scan()
scanner:Scan()
assert(count==1, "Viewer-dependent hyperlink changes must not be detected as new loot")
assert(ns:LootVariantKey(alert.link)~=ns:LootVariantKey(alert.link:gsub(":123:456",":124:456")), "Random stat suffixes must remain distinct")
print("PASS: stable bag-loot detection ignores link level/spec changes while preserving random-stat variants")
