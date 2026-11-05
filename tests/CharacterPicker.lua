-- Run from the addon directory: lua tests/CharacterPicker.lua
local ns = { modules = {}, db = { settings = { alts = { alt = true } }, players = {
    own = { key = "own", name = "Zed", classToken = "MAGE" },
    alt = { key = "alt", name = "Alt", classToken = "ROGUE" },
    private = { key = "private", name = "Bob", classToken = "WARRIOR", privateGroup = "CODE12", professions = { Blacksmithing = {} } },
    guild = { key = "guild", name = "Anna", classToken = "PRIEST", guildSource = true },
    hidden = { key = "hidden", name = "Hidden", classToken = "MAGE" },
} } }
ns.IsOwnCharacter = function(_, key) return key == "own" or key == "alt" end
ns.IsVisibleCharacter = function(_, key) return key ~= "hidden" end
ns.IsGuildCharacter = function(_, key) return key == "guild" end
ns.PlayerIdentity = function() return "local-player", "Daniel" end
ns.GroupCode = function() return "CODE12" end
assert(loadfile("CharacterPicker.lua"))("ForeverTeamGear", ns)
local choices = ns:CharacterChoices("", "all", false)
assert(#choices == 4 and choices[1].key == "alt" and choices[2].key == "own" and choices[3].key == "guild")
ns:SetFavoriteCharacter("private", true)
choices = ns:CharacterChoices("", "all", false)
assert(choices[1].key == "private" and choices[2].key == "alt")
assert(#ns:CharacterChoices("", "offline", false) == 2)
assert(ns:CharacterChoices("", "private", false)[1].key == "private")
assert(ns:CharacterChoices("", "guild", false)[1].key == "guild")
assert(#ns:CharacterChoices("", "all", true) == 3)
assert(ns:CharacterChoices("BLACKSMITH", "all", false)[1].key == "private")
assert(#ns:CharacterChoices("mage", "all", false) == 1)
assert(#ns:CharacterChoices("missing", "all", false) == 0)
ns:SetFavoriteCharacter("private", false)
assert(ns.db.settings.favorites.private == nil)
for index = 1, 100 do ns.db.players["extra" .. index] = { key = "extra" .. index, name = "Friend " .. index, guildSource = true } end
assert(#ns:CharacterChoices("", "all", false) == 104)
local groups = ns:CharacterPlayerChoices(ns:CharacterChoices("", "all", false))
assert(#groups == 2 and groups[1].key == "local-player" and #groups[1].characters == 2)
ns.db.players.private.playerID, ns.db.players.private.playerName = "friend-id", "Kazu"
ns.db.players.guild.playerID, ns.db.players.guild.playerName = "friend-id", "Kazu"
groups = ns:CharacterPlayerChoices(ns:CharacterChoices("", "all", false))
local friend
for _, group in ipairs(groups) do if group.key == "friend-id" then friend = group end end
assert(friend and #friend.characters == 2 and friend.name == "Kazu")
assert(#ns:CharacterChoices("kazu", "all", false) == 2)
-- UI file only defines functions until Initialize; selection must be shared and persisted.
assert(loadfile("UI.lua"))("ForeverTeamGear", ns)
ns.RefreshWindow = function() end
ns.PlayerKey = function() return "own" end
assert(ns:SelectCharacter("private"))
assert(ns:SelectedCharacterKey() == "private" and ns.db.settings.selectedCharacter == "private")
assert(not ns:SelectCharacter("hidden") and not ns:SelectCharacter("missing"))
assert(ns:SelectedCharacterKey() == "private")
local widgets = {}
local function widget()
    local value = { shown = true, height = 400, text = "", scripts = {}, TitleText = { SetText = function() end } }
    setmetatable(value, { __index = function(_, key)
        if key == "CreateFontString" or key == "CreateTexture" then return widget end
        if key == "SetScript" then return function(self, event, callback) self.scripts[event] = callback end end
        if key == "SetText" then return function(self, text) self.text = text end end
        if key == "GetText" then return function(self) return self.text end end
        if key == "GetHeight" then return function(self) return self.height end end
        if key == "GetVerticalScroll" then return function() return 0 end end
        if key == "GetChecked" then return function() return false end end
        if key == "SetHeight" then return function(self, height) self.height = height end end
        if key == "IsShown" then return function(self) return self.shown end end
        if key == "Hide" then return function(self) self.shown = false end end
        if key == "Show" then return function(self) self.shown = true end end
        return function() end
    end })
    widgets[#widgets + 1] = value
    return value
end
CreateFrame = widget
ns.Now = function() return 100 end
ns.ProfileSourceLabel = function(_, profile) return profile.privateGroup and "Private group" or profile.guildSource and "Guild" or "Offline" end
ns:OpenCharacterPicker()
local sourceButton
for _, value in ipairs(widgets) do if value.text == "Private group" and value.scripts.OnClick then sourceButton = value; break end end
assert(sourceButton, "Source filter buttons must be created")
sourceButton.scripts.OnClick()
print("PASS: source/name/class/profession filters, favorites/own/alphabetical ordering, hidden alts, empty results, 100+ characters, shared persisted selection, audience enforcement")

C_Spell = { GetSpellName = function() return "Enchant Bracer - Stamina" end, GetSpellTexture = function() return 12345 end }
local link, icon, id = ns:RecipeSpellDisplay({ id = 7457 })
assert(link:find("spell:7457", 1, true) and link:find("Enchant Bracer", 1, true) and icon == 12345 and id == 7457)
C_Spell.GetSpellLink = function() return "native-spell-link" end
assert(ns:RecipeSpellDisplay({id = 7457}) == "native-spell-link")
assert(ns:RecipeSpellDisplay({id = 0}) == nil)
print("PASS: non-item recipes use spell links and icons, including uncached link fallback")

assert(loadfile("MacroUI.lua"))("ForeverTeamGear", ns)
ns.Mode = function() return "group" end
ns.db.sharedMacros = {
    a = {owner = "private", name = "One", at = 1},
    b = {owner = "guild", name = "Two", at = 1},
    c = {owner = "Unscanned Friend", name = "Three", at = 1, privateGroup = "CODE12", playerID = "friend-id", playerName = "Kazu"},
}
local macroChoices = ns:MacroCharacterChoices("", "all", false)
assert(#macroChoices == 3, "Only characters with visible shared macros belong in the macro picker")
local macroGroups = ns:CharacterPlayerChoices(macroChoices)
assert(#macroGroups == 1 and macroGroups[1].name == "Kazu" and #macroGroups[1].characters == 3)
assert(#ns:MacroCharacterChoices("kazu", "all", false) == 3)
assert(#ns:MacroCharacterChoices("", "private", false) == 2)
print("PASS: macro player/character grouping, character filtering, source filtering and owners without a profile")
