local _, ns = ...
local Picker = { rows = {}, source = "all" }
local columns, cardWidth, cardHeight, gap = 3, 216, 98, 8

function ns:CharacterChoices(query, source, hideAlts)
    query = (query or ""):lower()
    local settings = self.db.settings
    local favorites, result = settings.favorites or {}, {}
    for key, profile in pairs(self.db.players) do
        local own = self:IsOwnCharacter(key)
        local private = profile.privateGroup and profile.privateGroup == self:GroupCode()
        local guild = profile.guildSource or self:IsGuildCharacter(key)
        local matches = source == nil or source == "all" or source == "offline" and own
            or source == "private" and private or source == "guild" and guild
        if self:IsVisibleCharacter(key) and matches and not (hideAlts and (settings.alts or {})[key]) then
            local text = table.concat({ profile.name or key, profile.playerName or "", self:IsOwnCharacter(key) and (self.db.settings.playerName or "") or "", profile.className or "", profile.classToken or "", self.ProfileChoiceLabel and self.ProfileChoiceLabel(profile) or "" }, " ")
            for name in pairs(profile.professions or {}) do text = text .. " " .. name end
            if query == "" or text:lower():find(query, 1, true) then result[#result + 1] = profile end
        end
    end
    table.sort(result, function(a, b)
        local af, bf = favorites[a.key] == true, favorites[b.key] == true
        if af ~= bf then return af end
        local ao, bo = self:IsOwnCharacter(a.key), self:IsOwnCharacter(b.key)
        if ao ~= bo then return ao end
        local an, bn = (a.name or a.key):lower(), (b.name or b.key):lower()
        if an ~= bn then return an < bn end
        return a.key < b.key
    end)
    return result
end

function ns:CharacterPlayerGroup(profile)
    if self:IsOwnCharacter(profile.key) then
        local id, name = self:PlayerIdentity()
        return id, name
    end
    if profile.playerID and profile.playerName then return profile.playerID, profile.playerName end
    return "unassigned", "Unassigned"
end

function ns:CharacterPlayerChoices(choices)
    local groups, result = {}, {}
    for _, profile in ipairs(choices) do
        local id, name = self:CharacterPlayerGroup(profile)
        if not groups[id] then
            groups[id] = { key = id, name = name, isPlayer = true, characters = {}, own = self:IsOwnCharacter(profile.key) }
            result[#result + 1] = groups[id]
        end
        local group = groups[id]
        group.characters[#group.characters + 1] = profile
        if (profile.updated or 0) >= (group.updated or 0) then group.name, group.updated = name, profile.updated or 0 end
    end
    table.sort(result, function(a, b)
        if a.own ~= b.own then return a.own end
        if a.name:lower() ~= b.name:lower() then return a.name:lower() < b.name:lower() end
        return a.key < b.key
    end)
    return result
end

function ns:SetFavoriteCharacter(key, favorite)
    self.db.settings.favorites = self.db.settings.favorites or {}
    self.db.settings.favorites[key] = favorite and true or nil
end

local function age(at)
    if not at or at == 0 then return "Unknown age" end
    local seconds = math.max(0, ns:Now() - at)
    if seconds < 60 then return "Just updated" end
    if seconds < 3600 then return math.floor(seconds / 60) .. "m ago" end
    if seconds < 86400 then return math.floor(seconds / 3600) .. "h ago" end
    return math.floor(seconds / 86400) .. "d ago"
end

function Picker:GetRow(index)
    if self.rows[index] then return self.rows[index] end
    local row = CreateFrame("Button", nil, self.content, "BackdropTemplate")
    row:SetSize(cardWidth, cardHeight)
    row:SetPoint("TOPLEFT", ((index - 1) % columns) * (cardWidth + gap), -math.floor((index - 1) / columns) * (cardHeight + gap))
    row:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    row:SetBackdropColor(0.08, 0.07, 0.05, 0.95)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row.selected = row:CreateTexture(nil, "BACKGROUND")
    row.selected:SetAllPoints(); row.selected:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row.selected:SetVertexColor(1, 0.82, 0.2, 0.45)
    local star = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    star:SetSize(22, 22); star:SetPoint("TOPRIGHT", -6, -6)
    star:SetScript("OnClick", function()
        local key = row.profile and row.profile.key
        if not key then return end
        ns:SetFavoriteCharacter(key, not (ns.db.settings.favorites or {})[key])
        self:Refresh()
    end)
    row.star = star
    local function label(x, y, width, font)
        local text = row:CreateFontString(nil, "OVERLAY", font)
        text:SetPoint("TOPLEFT", x, y); text:SetWidth(width); text:SetJustifyH("LEFT"); text:SetMaxLines(1)
        return text
    end
    row.name = label(12, -12, cardWidth - 44, "GameFontHighlight")
    row.name:SetMaxLines(2); row.name:SetHeight(30)
    row.details = label(12, -46, cardWidth - 24, "GameFontDisableSmall")
    row.source = label(12, -63, cardWidth - 24, "GameFontHighlightSmall")
    row.updated = label(12, -80, cardWidth - 24, "GameFontDisableSmall")
    row:SetScript("OnClick", function()
        if not row.profile then return end
        GameTooltip:Hide()
        if row.profile.isPlayer then
            if self.playersOnly then
                if self.onSelect then self.onSelect(row.profile.key, row.profile.name, self.hideAlts:GetChecked()) end
                self.frame:Hide()
            else self.player = row.profile.key; self.scroll:SetVerticalScroll(0); self:Refresh() end
        else
            if self.onSelect then self.onSelect(row.profile.key) else ns:SelectCharacter(row.profile.key) end
            self.frame:Hide()
        end
    end)
    row:SetScript("OnEnter", function()
        if not row.profile then return end
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:SetText(row.profile.name or row.profile.key)
        GameTooltip:AddLine(row.profile.isPlayer and (self.playersOnly and "Click to select player" or "Click to view characters") or ns:ProfileSourceLabel(row.profile), 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine("Updated: " .. age(row.profile.updated), 1, 1, 1)
        GameTooltip:AddLine("Click to select. Use * to pin a favorite.", 1, 0.82, 0)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.rows[index] = row
    return row
end

function Picker:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    local query = self.search:GetText()
    local choices = self.choicesProvider and self.choicesProvider(query, self.source, self.hideAlts:GetChecked()) or ns:CharacterChoices(query, self.source, self.hideAlts:GetChecked())
    local groups = ns:CharacterPlayerChoices(choices)
    if self.player then
        local filtered = {}
        for _, profile in ipairs(choices) do
            if ns:CharacterPlayerGroup(profile) == self.player then filtered[#filtered + 1] = profile end
        end
        choices = filtered
    else choices = groups end
    self.back:SetShown(self.player ~= nil)
    self.frame.TitleText:SetText(self.player and "Select character" or "Select player")
    for index = 1, math.max(#choices, #self.rows) do
        local row = self:GetRow(index)
        local profile = choices[index]
        row.profile = profile
        if profile then
            local favorite = (ns.db.settings.favorites or {})[profile.key]
            row.star:SetText(favorite and "|cffffd100*|r" or "|cff777777*|r")
            row.name:SetText(profile.name or profile.key)
            local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[profile.classToken or ""]
            row.name:SetTextColor(color and color.r or 1, color and color.g or 1, color and color.b or 1)
            local selected = not profile.isPlayer and ns:SelectedCharacterKey() == profile.key
            row:SetBackdropBorderColor(selected and 1 or (color and color.r or 0.5), selected and 0.82 or (color and color.g or 0.5), selected and 0.2 or (color and color.b or 0.5), 1)
            row.details:SetText(string.format("%s  •  Level %d%s", ns.ClassDisplayName and ns.ClassDisplayName(profile) or profile.className or profile.classToken or "Unknown", profile.level or 0, (ns.db.settings.alts or {})[profile.key] and "  •  Alt" or ""))
            if profile.isPlayer then
                row.star:Hide()
                row.details:SetText(#profile.characters .. " characters")
                row.source:SetText(self.playersOnly and "View shared macros" or (profile.own and "Your characters" or "View characters"))
                row.updated:SetText(profile.key == "unassigned" and "Awaiting updated sync" or "")
            else
                row.star:Show()
                row.source:SetText(ns:ProfileSourceLabel(profile)); row.updated:SetText(age(profile.updated))
            end
            row.selected:SetShown(selected)
            row:Show()
        else row:Hide() end
    end
    local height = math.max(1, math.ceil(#choices / columns) * (cardHeight + gap) - gap)
    self.content:SetHeight(height)
    self.scroll:SetVerticalScroll(math.min(self.scroll:GetVerticalScroll(), math.max(0, height - self.scroll:GetHeight())))
    self.count:SetText(#choices > 0 and (#choices .. (self.player and " characters  •  Favorites first" or (self.playersOnly and " players  •  Click to view shared macros" or " players  •  Click a player to view characters"))) or "No characters match these filters.")
    for source, button in pairs(self.buttons) do button:SetEnabled(source ~= self.source) end
end

function Picker:Create()
    local frame = CreateFrame("Frame", "ForeverTeamGearCharacterPicker", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(720, 560); frame:SetPoint("CENTER", 30, 10); frame:SetFrameStrata("DIALOG")
    frame.TitleText:SetText("Select character")
    frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving); frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    self.frame = frame
    local search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    search:SetSize(445, 24); search:SetPoint("TOPLEFT", 24, -40); search:SetAutoFocus(false)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    search:SetScript("OnTextChanged", function() if self.scroll then self.scroll:SetVerticalScroll(0); self:Refresh() end end)
    self.search = search
    local hide = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    hide:SetSize(24, 24); hide:SetPoint("TOPLEFT", 510, -40)
    local hideText = hide:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hideText:SetPoint("LEFT", hide, "RIGHT", 2, 0); hideText:SetText("Hide alts")
    hide:SetScript("OnClick", function() self.scroll:SetVerticalScroll(0); self:Refresh() end)
    self.hideAlts = hide
    self.buttons = {}
    for index, entry in ipairs({ { "all", "All sources" }, { "offline", "My characters" }, { "private", "Private group" }, { "guild", "Guild" } }) do
        local source = entry[1]
        local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetSize(160, 24); button:SetPoint("TOPLEFT", 20 + (index - 1) * 170, -76); button:SetText(entry[2])
        button:SetScript("OnClick", function() self.source = source; self.scroll:SetVerticalScroll(0); self:Refresh() end)
        self.buttons[source] = button
    end
    local back = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    back:SetSize(130, 22); back:SetPoint("TOPRIGHT", -22, -105); back:SetText("< Back to players")
    back:SetScript("OnClick", function() self.player = nil; self.scroll:SetVerticalScroll(0); self:Refresh() end)
    self.back = back
    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 24, -110); hint:SetText("Search by player, character, class or profession.")
    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -132); scroll:SetPoint("BOTTOMRIGHT", -32, 38)
    self.scroll = scroll
    local content = CreateFrame("Frame", nil, scroll); content:SetSize(666, 1); scroll:SetScrollChild(content); self.content = content
    self.count = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.count:SetPoint("BOTTOMLEFT", 24, 16)
    frame:Hide()
end

function ns:OpenCharacterPicker(onSelect, choicesProvider, playersOnly)
    if not Picker.frame then Picker:Create() end
    Picker.onSelect, Picker.choicesProvider, Picker.playersOnly = onSelect, choicesProvider, playersOnly
    Picker.hideAlts:SetChecked(true)
    Picker.player = nil
    Picker.frame:Show(); Picker:Refresh()
end

function ns:RefreshCharacterPicker()
    Picker:Refresh()
end

function ns:CreateCharacterChooser(parent)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(390, 26); button:SetPoint("TOPLEFT", 0, 3)
    button:SetText("Select character...")
    button:SetScript("OnClick", function() ns:OpenCharacterPicker() end)
    return button
end
