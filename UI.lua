local _, ns = ...

local UI = { mode = "team", rows = {}, playerButtons = {}, gearButtons = {}, professionCards = {}, inventoryButtons = {}, inventoryLocation = "bags" }
table.insert(ns.modules, UI)

local SLOT_NAMES = {
    [1] = "Head", [2] = "Neck", [3] = "Shoulders", [4] = "Shirt", [5] = "Chest",
    [6] = "Waist", [7] = "Legs", [8] = "Feet", [9] = "Wrists", [10] = "Hands",
    [11] = "Ring 1", [12] = "Ring 2", [13] = "Trinket 1", [14] = "Trinket 2",
    [15] = "Back", [16] = "Main Hand", [17] = "Off Hand", [18] = "Ranged", [19] = "Tabard",
}

local SLOT_TEXTURES = {
    [1] = "Head", [2] = "Neck", [3] = "Shoulder", [4] = "Shirt", [5] = "Chest",
    [6] = "Waist", [7] = "Legs", [8] = "Feet", [9] = "Wrist", [10] = "Hands",
    [11] = "Finger", [12] = "Finger", [13] = "Trinket", [14] = "Trinket",
    [15] = "Chest", [16] = "MainHand", [17] = "SecondaryHand", [18] = "Ranged", [19] = "Tabard",
}

local LEFT_SLOTS = { 1, 2, 3, 15, 5, 4, 19 }
local RIGHT_SLOTS = { 9, 10, 6, 7, 8, 11, 12, 13, 14 }
local BOTTOM_SLOTS = { 16, 17, 18 }

local CLASS_NAMES = {
    DEATHKNIGHT = "Death Knight", DEMONHUNTER = "Demon Hunter", DRUID = "Druid",
    EVOKER = "Evoker", HUNTER = "Hunter", MAGE = "Mage", MONK = "Monk",
    PALADIN = "Paladin", PRIEST = "Priest", ROGUE = "Rogue", SHAMAN = "Shaman",
    WARLOCK = "Warlock", WARRIOR = "Warrior",
}

local function age(timestamp)
    local seconds = math.max(0, ns:Now() - (timestamp or 0))
    if seconds < 60 then return seconds .. "s" end
    if seconds < 3600 then return math.floor(seconds / 60) .. "m" end
    return math.floor(seconds / 3600) .. "h"
end

local function displayName(profile)
    local reported = tostring(profile.name or "")
    if reported:find(" ", 1, true) then return reported end
    local fromKey = tostring(profile.key or ""):match("^(.-)%-")
    if fromKey and fromKey:find(" ", 1, true) then return fromKey end
    return reported ~= "" and reported or tostring(profile.key or "?")
end

function ns:OpenTalentStatus()
    local profile = self:ScanProfile()
    local diagnostic = self.db.talentScanDiagnostics or {}
    local talents = profile.talents or {}
    local count = 0; for _ in pairs(talents.nodes or {}) do count=count+1 end
    local lines = {"Forever Team Gear " .. self.version, "Character: " .. (profile.name or profile.key),
        "Level: " .. tostring(profile.level), "Talent scan: " .. (diagnostic.ready and "complete" or "FAILED / incomplete"),
        "Detail: " .. tostring(diagnostic.detail or "Unavailable"), "Tree: " .. tostring(talents.treeID),
        "Spec: " .. tostring(talents.specID), "Build: " .. tostring(profile.specName), "Allocated nodes: " .. count,
        "Outgoing revision: " .. tostring(self.db.syncRevision or 0)}
    if not UI.talentStatusFrame then
        local frame=CreateFrame("Frame","ForeverTeamGearTalentStatus",UIParent,"BasicFrameTemplateWithInset")
        frame:SetSize(600,320);frame:SetPoint("CENTER");frame:SetFrameStrata("FULLSCREEN_DIALOG")
        frame.TitleText:SetText("Talent synchronization status — Ctrl+C to copy")
        local edit=CreateFrame("EditBox",nil,frame,"InputBoxTemplate")
        edit:SetMultiLine(true);edit:SetAutoFocus(false);edit:SetFontObject(ChatFontNormal)
        edit:SetPoint("TOPLEFT",22,-40);edit:SetSize(552,250)
        edit:SetScript("OnEscapePressed",function() frame:Hide() end)
        frame:SetScript("OnHide",function() edit:ClearFocus() end)
        frame.edit=edit; UI.talentStatusFrame=frame
    end
    UI.talentStatusFrame:Show();UI.talentStatusFrame.edit:SetText(table.concat(lines,"\n"))
    UI.talentStatusFrame.edit:SetFocus();UI.talentStatusFrame.edit:HighlightText()
end

function ns:OpenCopyCharacterName(profile)
    if not profile then return end
    local fullName = self:WhisperTarget(displayName(profile))
    if not UI.copyNameFrame then
        local frame = CreateFrame("Frame", "ForeverTeamGearCopyName", UIParent, "BasicFrameTemplateWithInset")
        frame:SetSize(380, 120); frame:SetPoint("CENTER"); frame:SetFrameStrata("FULLSCREEN_DIALOG")
        frame.TitleText:SetText("Copy character name")
        local edit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
        edit:SetSize(330, 26); edit:SetPoint("TOPLEFT", 26, -39); edit:SetAutoFocus(false)
        edit:SetScript("OnEscapePressed", function() frame:Hide() end)
        edit:SetScript("OnEnterPressed", function() frame:Hide() end)
        frame:SetScript("OnHide", function() edit:ClearFocus() end)
        local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("TOP", edit, "BOTTOM", 0, -10); hint:SetText("Press Ctrl+C to copy, then Escape to close.")
        frame.edit = edit; UI.copyNameFrame = frame
    end
    UI.copyNameFrame:Show()
    UI.copyNameFrame.edit:SetText(fullName)
    UI.copyNameFrame.edit:SetFocus(); UI.copyNameFrame.edit:HighlightText()
end

local function firstName(profile)
    local name = displayName(profile)
    return name:match("^(%S+)") or name
end

local function classDisplayName(profile)
    return CLASS_NAMES[profile.classToken or ""] or profile.className or profile.classToken or "Unknown"
end

local function playerChoiceLabel(profile)
    local label = string.format("%s (%s)", firstName(profile), classDisplayName(profile))
    if ns.db and ns.db.settings and ns.db.settings.alts and ns.db.settings.alts[profile.key] then
        label = label .. " [Alt]"
    end
    return label
end

ns.ProfileChoiceLabel = playerChoiceLabel
ns.ClassDisplayName = classDisplayName

local function dropdownLabel(profile)
    return playerChoiceLabel(profile) .. " — " .. ns:ProfileSourceLabel(profile)
end

local function sortedPlayers()
    local players = {}
    for _, profile in pairs(ns.db.players or {}) do
        if ns:IsVisibleCharacter(profile.key) then players[#players + 1] = profile end
    end
    table.sort(players, function(a, b) return displayName(a) < displayName(b) end)
    return players
end

local function itemIcon(item)
    if not item or not item.id or not C_Item or not C_Item.GetItemInfoInstant then return nil end
    return select(5, C_Item.GetItemInfoInstant(item.id))
end

local function itemQuality(item)
    if not item or not item.link or not C_Item or not C_Item.GetItemInfo then return nil end
    return select(3, C_Item.GetItemInfo(item.link))
end

local function createWindow()
    local frame = CreateFrame("Frame", "ForeverTeamGearFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(700, 560)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame.TitleText:SetText("Forever Team Gear")
    local settings = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    settings:SetSize(80, 20); settings:SetPoint("TOPRIGHT", -40, -3); settings:SetText("Settings")
    settings:SetScript("OnClick", function() ns:OpenSettings() end)

    local team = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    team:SetSize(86, 24); team:SetPoint("TOPLEFT", 12, -32); team:SetText("Equipment")
    team:SetScript("OnClick", function() UI.mode = "team"; UI:Refresh() end)
    local professions = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    professions:SetSize(86, 24); professions:SetPoint("LEFT", team, "RIGHT", 4, 0); professions:SetText("Professions")
    professions:SetScript("OnClick", function() UI.mode = "professions"; UI:Refresh() end)
    local boe = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    boe:SetSize(86, 24); boe:SetPoint("LEFT", professions, "RIGHT", 4, 0); boe:SetText("BoE Drops")
    boe:SetScript("OnClick", function() UI.mode = "boe"; UI:Refresh() end)
    local inventory = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    inventory:SetSize(86, 24); inventory:SetPoint("LEFT", boe, "RIGHT", 4, 0); inventory:SetText("Inventory")
    inventory:SetScript("OnClick", function() UI.mode = "inventory"; UI:Refresh() end)
    local macros = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    macros:SetSize(86, 24); macros:SetPoint("LEFT", inventory, "RIGHT", 4, 0); macros:SetText("Macros")
    macros:SetScript("OnClick", function() UI.mode = "macros"; UI:Refresh() end)
    local share = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    share:SetSize(110, 24); share:SetPoint("LEFT", macros, "RIGHT", 6, 0); share:SetText("Share my data")
    share:SetScript("OnClick", function() ns:ScanAll(); ns:RequestSync(true) end)
    share:SetScript("OnEnter", function(self)
        local queued, incoming = ns:SyncStatus()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Share my data")
        GameTooltip:AddLine("Publish your own character data to the selected audience. Does not request other players' profiles.", 1, 1, 1, true)
        GameTooltip:AddLine(string.format("Queued packets: %d\nIncoming sections: %d", queued, incoming), 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    share:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.shareButton = share
    local sync = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    sync:SetSize(100, 24); sync:SetPoint("TOPRIGHT", -12, -32); sync:SetText("Sync Party")
    sync:SetScript("OnClick", function() ns:ScanAll(); ns:RequestGroupSync() end)
    frame.syncButton = sync
    sync:SetScript("OnEnter", function(self)
        local queued, incoming = ns:SyncStatus()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Synchronization")
        GameTooltip:AddLine(string.format("Queued packets: %d\nIncoming sections: %d", queued, incoming), 1, 1, 1, true)
        GameTooltip:AddLine("Request and share data only within your current party/raid. Existing mode and sharing settings apply. 30-second cooldown.", 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    sync:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -68); scroll:SetPoint("BOTTOMRIGHT", -30, 12)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(650, 1)
    scroll:SetScrollChild(content)
    scroll.content = content
    frame.scroll = scroll
    frame.content = content

    UI.frame = frame
    ns.mainWindow = frame
    UI:CreateGearPanel(frame)
    UI:CreateInventoryPanel(frame)
    UI:CreateProfessionBrowser()
end

function UI:CreateInventoryPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", 12, -68); panel:SetPoint("BOTTOMRIGHT", -12, 12)

    panel.characterChooser = ns:CreateCharacterChooser(panel)

    local bags = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    bags:SetSize(85, 24); bags:SetPoint("TOPLEFT", 410, 5); bags:SetText("Bags")
    bags:SetScript("OnClick", function() UI.inventoryLocation = "bags"; UI:RefreshInventory() end)
    local bank = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    bank:SetSize(85, 24); bank:SetPoint("LEFT", bags, "RIGHT", 6, 0); bank:SetText("Bank")
    bank:SetScript("OnClick", function() UI.inventoryLocation = "bank"; UI:RefreshInventory() end)
    panel.bagsButton, panel.bankButton = bags, bank

    local status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", 8, -40); status:SetPoint("RIGHT", -8, 0); status:SetJustifyH("LEFT")
    panel.status = status
    self.inventoryPanel = panel
end

function UI:GetInventoryButton(index)
    if self.inventoryButtons[index] then return self.inventoryButtons[index] end
    local button = CreateFrame("Button", nil, self.inventoryPanel, "BackdropTemplate")
    button:SetSize(44, 44)
    button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border", edgeSize = 11, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    button:SetBackdropColor(0.04, 0.04, 0.04, 1)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 4, -4); icon:SetPoint("BOTTOMRIGHT", -4, 4); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.icon = icon
    local count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    count:SetPoint("BOTTOMRIGHT", -4, 4); button.count = count
    button:SetScript("OnEnter", function(self)
        if not self.itemID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local link = self.itemLink or (C_Item and C_Item.GetItemInfo and select(2, C_Item.GetItemInfo(self.itemID)))
        if link then GameTooltip:SetHyperlink(link) elseif GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.itemID) end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnClick", function(self)
        local link = self.itemLink or (self.itemID and C_Item and C_Item.GetItemInfo and select(2, C_Item.GetItemInfo(self.itemID)))
        if link and IsShiftKeyDown() then ChatEdit_InsertLink(link) end
    end)
    self.inventoryButtons[index] = button
    return button
end

function UI:RefreshInventory()
    local players = sortedPlayers()
    self.selectedKey = self.selectedKey or ns.db.settings.selectedCharacter
    if not self.selectedKey or not ns.db.players[self.selectedKey] or not ns:IsVisibleCharacter(self.selectedKey) then
        local ownKey = ns:PlayerKey()
        self.selectedKey = ns.db.players[ownKey] and ownKey or (players[1] and players[1].key)
    end
    local profile = self.selectedKey and ns.db.players[self.selectedKey]
    self.inventoryPanel.characterChooser:SetText(profile and (dropdownLabel(profile) .. "  ...") or "Select character...")
    local inventory = profile and profile.inventory or {}
    local items = inventory[self.inventoryLocation] or {}
    local sorted, total = {}, 0
    for key, count in pairs(items) do
        local id = tonumber(key) or tonumber(tostring(key):match("item:(%d+)"))
        if id then sorted[#sorted + 1] = { id = id, link = type(key) == "string" and key or nil, count = count }; total = total + count end
    end
    table.sort(sorted, function(a, b) if a.id ~= b.id then return a.id < b.id end; return (a.link or "") < (b.link or "") end)

    self.inventoryPanel.bagsButton:SetEnabled(self.inventoryLocation ~= "bags")
    self.inventoryPanel.bankButton:SetEnabled(self.inventoryLocation ~= "bank")
    if not profile then
        self.inventoryPanel.status:SetText("No synchronized character data.")
    elseif profile.sharing and profile.sharing[self.inventoryLocation] == false then
        self.inventoryPanel.status:SetText("This character does not share " .. self.inventoryLocation .. ".")
    elseif self.inventoryLocation == "bank" and (not inventory.bankUpdated or inventory.bankUpdated == 0) then
        self.inventoryPanel.status:SetText("Bank not scanned yet — this character must open the bank and synchronize.")
    else
        local location = self.inventoryLocation == "bank" and "Bank" or "Bags"
        local updated = self.inventoryLocation == "bank" and inventory.bankUpdated or profile.updated
        self.inventoryPanel.status:SetText(string.format("%s • %d item types • %d total items • updated %s ago", location, #sorted, total, age(updated)))
    end

    for index = 1, math.max(#sorted, #self.inventoryButtons) do
        local button = self:GetInventoryButton(index)
        local item = sorted[index]
        if item then
            local column, row = (index - 1) % 12, math.floor((index - 1) / 12)
            button:ClearAllPoints(); button:SetPoint("TOPLEFT", 8 + column * 54, -66 - row * 54)
            button.itemID = item.id; button.itemLink = item.link
            local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(item.id)
            if not icon and C_Item and C_Item.GetItemInfoInstant then icon = select(5, C_Item.GetItemInfoInstant(item.id)) end
            button.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            local quality = C_Item and C_Item.GetItemInfo and select(3, C_Item.GetItemInfo(item.id))
            local qualityColor = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
            if qualityColor then button:SetBackdropBorderColor(qualityColor.r, qualityColor.g, qualityColor.b, 1) else button:SetBackdropBorderColor(0.45, 0.45, 0.45, 1) end
            button.count:SetText(item.count > 1 and item.count or "")
            button:Show()
        else
            button.itemID = nil; button.itemLink = nil; button:Hide()
        end
    end
end

function UI:CreateGearPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", 12, -68)
    panel:SetPoint("BOTTOMRIGHT", -12, 12)

    local chooser = CreateFrame("Frame", nil, panel)
    chooser:SetPoint("TOPLEFT", 0, 0)
    chooser:SetPoint("TOPRIGHT", 0, 0)
    chooser:SetHeight(34)
    panel.chooser = chooser

    panel.characterChooser = ns:CreateCharacterChooser(chooser)

    local altCheck = CreateFrame("CheckButton", nil, chooser, "UICheckButtonTemplate")
    altCheck:SetSize(26, 26)
    altCheck:SetPoint("TOPLEFT", 412, 3)
    local altLabel = altCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    altLabel:SetPoint("LEFT", altCheck, "RIGHT", 2, 0)
    altLabel:SetText("Alt — exclude from alerts")
    altCheck.label = altLabel
    altCheck:SetScript("OnClick", function(self)
        local key = UI.selectedKey
        if not key then self:SetChecked(false); return end
        ns.db.settings.alts = ns.db.settings.alts or {}
        ns.db.settings.alts[key] = self:GetChecked() and true or nil
        UI:RefreshGear()
    end)
    altCheck:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Alt character", 1, 0.82, 0)
        GameTooltip:AddLine("Keeps this character visible, but excludes it from automatic BoE upgrade alerts.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    altCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel.altCheck = altCheck

    local paper = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    paper:SetPoint("TOPLEFT", 0, -40)
    paper:SetPoint("BOTTOMRIGHT", 0, 0)
    paper:SetBackdrop({
        bgFile = "Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
        tile = false, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    paper:SetBackdropColor(0.48, 0.38, 0.22, 0.96)
    panel.paper = paper

    local summary = CreateFrame("Frame", nil, paper, "BackdropTemplate")
    summary:SetPoint("TOPLEFT", 185, -66)
    summary:SetPoint("BOTTOMRIGHT", -185, 112)
    summary:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    summary:SetBackdropColor(0.12, 0.07, 0.025, 0.94)

    local name = summary:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    name:SetPoint("TOP", 0, -42)
    name:SetWidth(274); name:SetJustifyH("CENTER"); name:SetMaxLines(2)
    summary.name = name
    local copy = CreateFrame("Button", nil, summary, "UIPanelButtonTemplate")
    copy:SetSize(100, 22); copy:SetPoint("TOP", 0, -12); copy:SetText("Copy name")
    copy:SetScript("OnClick", function() if copy.profile then ns:OpenCopyCharacterName(copy.profile) end end)
    summary.copyName = copy
    local details = summary:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    details:SetPoint("TOP", name, "BOTTOM", 0, -12)
    details:SetWidth(260)
    details:SetJustifyH("CENTER")
    summary.details = details

    local talents = CreateFrame("Button", nil, summary)
    talents:SetSize(274, 34)
    talents:SetPoint("TOP", details, "BOTTOM", 0, -5)
    local talentsText = talents:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    talentsText:SetAllPoints()
    talentsText:SetJustifyH("CENTER")
    talentsText:SetTextColor(0.36, 0.78, 1)
    talents.text = talentsText
    talents:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 0.82, 0) end)
    talents:SetScript("OnLeave", function(self) self.text:SetTextColor(0.36, 0.78, 1) end)
    talents:SetScript("OnClick", function(self)
        if self.profileKey and ns.OpenTalentBrowser then ns:OpenTalentBrowser(self.profileKey) end
    end)
    summary.talents = talents

    local updated = summary:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    updated:SetPoint("TOP", talents, "BOTTOM", 0, -4)
    summary.updated = updated
    local hint = summary:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOM", 0, 26)
    hint:SetWidth(230)
    hint:SetText("Hover an item for its tooltip. Shift-click to link it in chat.")
    summary.hint = hint
    panel.summary = summary

    for index, slot in ipairs(LEFT_SLOTS) do
        self:CreateGearSlot(paper, slot, "LEFT", 20, -20 - ((index - 1) * 45))
    end
    for index, slot in ipairs(RIGHT_SLOTS) do
        self:CreateGearSlot(paper, slot, "RIGHT", -20, -20 - ((index - 1) * 45))
    end
    for index, slot in ipairs(BOTTOM_SLOTS) do
        self:CreateGearSlot(paper, slot, "BOTTOM", -76 + ((index - 1) * 76), 34)
    end

    self.gearPanel = panel
end


function UI:CreateGearSlot(parent, slot, side, x, y)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(40, 40)
    if side == "LEFT" then
        button:SetPoint("TOPLEFT", x, y)
    elseif side == "RIGHT" then
        button:SetPoint("TOPRIGHT", x, y)
    else
        button:SetPoint("BOTTOM", x, y)
    end
    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    button:SetBackdropColor(0.08, 0.08, 0.08, 1)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 4, -4); icon:SetPoint("BOTTOMRIGHT", -4, 4)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.icon = icon

    local empty = button:CreateTexture(nil, "BACKGROUND")
    empty:SetPoint("TOPLEFT", 4, -4); empty:SetPoint("BOTTOMRIGHT", -4, 4)
    empty:SetTexture("Interface\\PaperDoll\\UI-PaperDoll-Slot-" .. (SLOT_TEXTURES[slot] or "Chest"))
    button.empty = empty

    local level = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    level:SetPoint("BOTTOMRIGHT", -4, 4)
    button.level = level

    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if side == "LEFT" then
        label:SetPoint("LEFT", button, "RIGHT", 7, 0)
        label:SetJustifyH("LEFT")
    elseif side == "RIGHT" then
        label:SetPoint("RIGHT", button, "LEFT", -7, 0)
        label:SetJustifyH("RIGHT")
    else
        label:SetPoint("TOP", button, "BOTTOM", 0, -2)
        label:SetFontObject(GameFontDisableSmall)
    end
    label:SetText(SLOT_NAMES[slot] or tostring(slot))
    button.label = label
    button.slot = slot

    button:SetScript("OnEnter", function(self)
        if not self.itemLink then return end
        GameTooltip:SetOwner(self, side == "RIGHT" and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.itemLink)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnClick", function(self)
        if self.itemLink and IsShiftKeyDown() then ChatEdit_InsertLink(self.itemLink) end
    end)
    self.gearButtons[slot] = button
end

function ns:RecipeSpellDisplay(recipe)
    local id = tonumber(recipe and recipe.id)
    if not id or id <= 0 then return nil end
    local linkAPI = C_Spell and C_Spell.GetSpellLink or GetSpellLink
    local link = linkAPI and linkAPI(id)
    local textureAPI = C_Spell and C_Spell.GetSpellTexture or GetSpellTexture
    local icon = recipe.icon or (textureAPI and textureAPI(id))
    local name = recipe.name
    if not name and C_Spell and C_Spell.GetSpellName then name = C_Spell.GetSpellName(id) end
    if not name and GetSpellInfo then name = GetSpellInfo(id) end
    link = link or ("|cff71d5ff|Hspell:" .. id .. "|h[" .. (name or ("Enchant #" .. id)) .. "]|h|r")
    return link, icon or "Interface\\Icons\\Trade_Engraving", id
end

local function recipeDisplayName(recipe)
    if recipe.name and recipe.name ~= "" then return recipe.name end
    if C_Spell and C_Spell.GetSpellName and recipe.id then
        local name = C_Spell.GetSpellName(recipe.id)
        if name then return name end
    end
    return "Recipe #" .. tostring(recipe.id or "?")
end

local function itemDisplay(itemID)
    if not itemID or itemID == 0 or not C_Item then return nil, nil, nil end
    local name, link, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemID)
    UI.requestedItemData = UI.requestedItemData or {}
    if not name and C_Item.RequestLoadItemDataByID and not UI.requestedItemData[itemID] then
        UI.requestedItemData[itemID] = true
        C_Item.RequestLoadItemDataByID(itemID)
    end
    if not icon and C_Item.GetItemInfoInstant then icon = select(5, C_Item.GetItemInfoInstant(itemID)) end
    return name or ("Item #" .. itemID), link, icon, quality
end

-- Build a view without modifying the synchronized character records.
function UI:MergedProfession(name)
    local merged = { recipes = {}, owners = {} }
    local byID = {}
    for _, profile in ipairs(sortedPlayers()) do
        local profession = profile.professions and profile.professions[name]
        if profession then
            merged.icon = merged.icon or profession.icon
            merged.owners[#merged.owners + 1] = profile
            local seen = {}
            for _, stored in ipairs(profession.recipes or {}) do
                local source = type(stored) == "table" and stored or { id = stored }
                if source.id and not seen[source.id] then
                    seen[source.id] = true
                    local recipe = byID[source.id]
                    if not recipe then
                        recipe = { id = source.id, owners = {} }
                        byID[source.id] = recipe
                        merged.recipes[#merged.recipes + 1] = recipe
                    end
                    -- Prefer a complete snapshot over a legacy recipe ID.
                    if not recipe.reagents or #(source.reagents or {}) > #recipe.reagents then
                        for key, value in pairs(source) do
                            if key ~= "owners" then recipe[key] = value end
                        end
                    end
                    recipe.owners[#recipe.owners + 1] = profile
                end
            end
        end
    end
    return #merged.owners > 0 and merged or nil
end

local function recipeOwners(recipe)
    local names = {}
    for _, profile in ipairs(recipe.owners or {}) do names[#names + 1] = displayName(profile) end
    return table.concat(names, ", ")
end

function UI:CreateProfessionBrowser()
    local browser = CreateFrame("Frame", "ForeverTeamGearProfessionFrame", UIParent, "BasicFrameTemplateWithInset")
    browser:SetSize(820, 620)
    browser:SetPoint("CENTER", 80, 10)
    browser:SetMovable(true)
    browser:EnableMouse(true)
    browser:RegisterForDrag("LeftButton")
    browser:SetScript("OnDragStart", browser.StartMoving)
    browser:SetScript("OnDragStop", browser.StopMovingOrSizing)
    browser.TitleText:SetText("Profession Browser")
    browser:SetFrameStrata("DIALOG")

    local professionIcon = browser:CreateTexture(nil, "ARTWORK")
    professionIcon:SetSize(48, 48)
    professionIcon:SetPoint("TOP", 0, -34)
    professionIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    browser.professionIcon = professionIcon

    local ownerName = browser:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    ownerName:SetPoint("TOP", professionIcon, "BOTTOM", 0, -3)
    ownerName:SetTextColor(1, 0.82, 0)
    browser.ownerName = ownerName

    local subtitle = browser:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOP", ownerName, "BOTTOM", 0, -2)
    browser.subtitle = subtitle

    local filterLabel = browser:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    filterLabel:SetPoint("TOPLEFT", 36, -130)
    filterLabel:SetText("Required Level:")
    browser.filterLabel = filterLabel

    local levelInput = CreateFrame("EditBox", nil, browser, "InputBoxTemplate")
    levelInput:SetSize(52, 22)
    levelInput:SetPoint("LEFT", filterLabel, "RIGHT", 10, 0)
    levelInput:SetAutoFocus(false)
    levelInput:SetNumeric(true)
    levelInput:SetMaxLetters(3)
    levelInput:SetJustifyH("CENTER")
    levelInput:SetScript("OnEnterPressed", function(self) self:ClearFocus(); UI:RefreshProfessionBrowser() end)
    levelInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    levelInput:SetScript("OnTextChanged", function()
        if browser.settingLevelInput then return end
        browser.useCurrentLevel = false
        browser.currentLevelCheck:SetChecked(false)
        UI.selectedRecipe = nil
        UI:RefreshProfessionBrowser()
    end)
    browser.levelInput = levelInput

    local allHint = browser:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    allHint:SetPoint("LEFT", levelInput, "RIGHT", 7, 0)
    allHint:SetText("blank = all")

    local currentLevelCheck = CreateFrame("CheckButton", nil, browser, "UICheckButtonTemplate")
    currentLevelCheck:SetSize(24, 24)
    currentLevelCheck:SetPoint("LEFT", allHint, "RIGHT", 18, 0)
    browser.currentLevelCheck = currentLevelCheck
    local currentLevelText = browser:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    currentLevelText:SetPoint("LEFT", currentLevelCheck, "RIGHT", 2, 0)
    browser.currentLevelText = currentLevelText
    currentLevelCheck:SetScript("OnClick", function(self)
        browser.useCurrentLevel = self:GetChecked() and true or false
        levelInput:ClearFocus()
        UI.selectedRecipe = nil
        UI:RefreshProfessionBrowser()
    end)

    local searchLabel = browser:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    searchLabel:SetPoint("TOPLEFT", 470, -130)
    searchLabel:SetText("Search:")
    local searchInput = CreateFrame("EditBox", nil, browser, "InputBoxTemplate")
    searchInput:SetSize(145, 22)
    searchInput:SetPoint("LEFT", searchLabel, "RIGHT", 8, 0)
    searchInput:SetAutoFocus(false)
    searchInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    searchInput:SetScript("OnTextChanged", function()
        UI.selectedRecipe = nil
        UI:RefreshProfessionBrowser()
    end)
    browser.searchInput = searchInput

    local craftableCheck = CreateFrame("CheckButton", nil, browser, "UICheckButtonTemplate")
    craftableCheck:SetSize(24, 24)
    craftableCheck:SetPoint("LEFT", searchInput, "RIGHT", 10, 0)
    craftableCheck:SetScript("OnClick", function()
        UI.selectedRecipe = nil
        UI:RefreshProfessionBrowser()
    end)
    browser.craftableCheck = craftableCheck
    local craftableText = browser:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    craftableText:SetPoint("LEFT", craftableCheck, "RIGHT", 1, 0)
    craftableText:SetText("Can craft")

    local listPanel = CreateFrame("Frame", nil, browser, "BackdropTemplate")
    listPanel:SetPoint("TOPLEFT", 12, -154)
    listPanel:SetPoint("BOTTOMLEFT", 12, 12)
    listPanel:SetWidth(330)
    listPanel:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border", edgeSize = 14 })
    listPanel:SetBackdropColor(0.15, 0.12, 0.09, 1)

    local listScroll = CreateFrame("ScrollFrame", nil, listPanel, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", 8, -8)
    listScroll:SetPoint("BOTTOMRIGHT", -28, 8)
    local listContent = CreateFrame("Frame", nil, listScroll)
    listContent:SetSize(288, 1)
    listScroll:SetScrollChild(listContent)
    browser.listScroll = listScroll
    browser.listContent = listContent
    browser.recipeRows = {}

    local details = CreateFrame("Frame", nil, browser, "BackdropTemplate")
    details:SetPoint("TOPLEFT", listPanel, "TOPRIGHT", 10, 0)
    details:SetPoint("BOTTOMRIGHT", -12, 12)
    details:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border", edgeSize = 14 })
    details:SetBackdropColor(0.12, 0.07, 0.025, 0.96)

    local recipeName = details:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    recipeName:SetPoint("TOPLEFT", 18, -20)
    recipeName:SetPoint("TOPRIGHT", -165, -20)
    recipeName:SetJustifyH("LEFT")
    details.recipeName = recipeName

    local requiredLevel = details:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    requiredLevel:SetPoint("TOPLEFT", 18, -44)
    requiredLevel:SetTextColor(0.9, 0.75, 0.35)
    details.requiredLevel = requiredLevel

    local wantedCheck = CreateFrame("CheckButton", nil, details, "UICheckButtonTemplate")
    wantedCheck:SetSize(24, 24)
    wantedCheck:SetPoint("TOPRIGHT", -132, -35)
    wantedCheck:SetScript("OnClick", function(self)
        local recipe = UI.selectedRecipe
        if recipe then
            for _, owner in ipairs(recipe.owners or {}) do
                ns:SetRecipeWanted(owner.key, browser.professionName, recipe.id, self:GetChecked())
            end
        end
    end)
    details.wantedCheck = wantedCheck
    local wantedText = details:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    wantedText:SetPoint("LEFT", wantedCheck, "RIGHT", 1, 0)
    wantedText:SetText("Track materials")
    details.wantedText = wantedText

    local output = CreateFrame("Button", nil, details)
    output:SetSize(420, 54)
    output:SetPoint("TOPLEFT", 18, -66)
    local outputIcon = output:CreateTexture(nil, "ARTWORK")
    outputIcon:SetSize(44, 44); outputIcon:SetPoint("LEFT", 0, 0)
    outputIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    output.icon = outputIcon
    local outputText = output:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    outputText:SetPoint("LEFT", outputIcon, "RIGHT", 10, 0)
    outputText:SetPoint("RIGHT", 0, 0); outputText:SetJustifyH("LEFT")
    output.text = outputText
    output:SetScript("OnEnter", function(self)
        if self.itemLink then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.spellID and GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(self.spellID) else GameTooltip:SetHyperlink(self.itemLink) end
            GameTooltip:Show()
        end
    end)
    output:SetScript("OnLeave", function() GameTooltip:Hide() end)
    output:SetScript("OnClick", function(self)
        if self.itemLink and IsShiftKeyDown() then ChatEdit_InsertLink(self.itemLink) end
    end)
    details.output = output

    local materialsTitle = details:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    materialsTitle:SetPoint("TOPLEFT", 18, -134)
    materialsTitle:SetText("Required materials")
    details.materialsTitle = materialsTitle
    details.materialRows = {}
    for index = 1, 10 do
        local row = CreateFrame("Button", nil, details)
        row:SetSize(420, 28)
        row:SetPoint("TOPLEFT", 18, -154 - ((index - 1) * 28))
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(24, 24); icon:SetPoint("LEFT", 0, 0); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.icon = icon
        local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", icon, "RIGHT", 8, 0); text:SetPoint("RIGHT", -4, 0); text:SetJustifyH("LEFT")
        row.text = text
        row:SetScript("OnEnter", function(self)
            if self.itemLink then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink(self.itemLink); GameTooltip:Show() end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("OnClick", function(self)
            if self.itemLink and IsShiftKeyDown() then ChatEdit_InsertLink(self.itemLink) end
        end)
        details.materialRows[index] = row
    end

    local knownBy = details:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    knownBy:SetWidth(420)
    knownBy:SetJustifyH("LEFT")
    knownBy:SetJustifyV("TOP")
    details.knownBy = knownBy

    browser.details = details
    browser:Hide()
    self.professionBrowser = browser
end

function UI:GetRecipeRow(index)
    local browser = self.professionBrowser
    if browser.recipeRows[index] then return browser.recipeRows[index] end
    local row = CreateFrame("Button", nil, browser.listContent, "BackdropTemplate")
    row:SetSize(286, 22)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    local selected = row:CreateTexture(nil, "BACKGROUND")
    selected:SetAllPoints()
    selected:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    selected:SetVertexColor(1, 0.82, 0.2, 0.65)
    selected:Hide()
    row.selected = selected
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", 24, -3); text:SetPoint("TOPRIGHT", -8, -3); text:SetJustifyH("LEFT")
    text:SetMaxLines(1)
    row.text = text
    local toggle = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    toggle:SetPoint("RIGHT", -8, 0)
    row.toggle = toggle
    row:SetScript("OnEnter", function(self)
        if not self.recipe then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local outputItemID = tonumber(self.recipe.outputItemID)
        if outputItemID and outputItemID > 0 then
            GameTooltip:SetHyperlink("item:" .. outputItemID)
        else
            local link, _, spellID = ns:RecipeSpellDisplay(self.recipe)
            if spellID and GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(spellID)
            elseif link then GameTooltip:SetHyperlink(link)
            else GameTooltip:SetText(recipeDisplayName(self.recipe)) end
        end
        GameTooltip:AddLine("Known by: " .. recipeOwners(self.recipe), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        if self.category then
            local collapsed = browser.collapsedCategories[browser.professionName]
            collapsed[self.category] = not collapsed[self.category]
            UI:RefreshProfessionBrowser()
            return
        end
        if not self.recipe then return end
        if IsShiftKeyDown() then
            local output = tonumber(self.recipe.outputItemID)
            local link = output and output > 0 and select(2, itemDisplay(output)) or ns:RecipeSpellDisplay(self.recipe)
            if link then ChatEdit_InsertLink(link) end
            return
        end
        UI.selectedRecipe = self.recipe
        UI:RefreshProfessionBrowser()
    end)
    browser.recipeRows[index] = row
    return row
end

function UI:OpenProfession(professionName)
    local profession = self:MergedProfession(professionName)
    if not profession then return end
    self.professionBrowser.professionName = professionName
    self.professionBrowser.collapsedCategories = self.professionBrowser.collapsedCategories or {}
    self.professionBrowser.collapsedCategories[professionName] = self.professionBrowser.collapsedCategories[professionName] or {}
    self.professionBrowser.listScroll:SetVerticalScroll(0)
    self.professionBrowser.useCurrentLevel = false
    self.professionBrowser.currentLevelCheck:SetChecked(false)
    self.professionBrowser.settingLevelInput = true
    self.professionBrowser.levelInput:SetText("")
    self.professionBrowser.settingLevelInput = false
    self.professionBrowser.searchInput:SetText("")
    self.professionBrowser.craftableCheck:SetChecked(false)
    self.selectedRecipe = nil
    self.professionBrowser.TitleText:SetText(professionName)
    self.professionBrowser.professionIcon:SetTexture(profession.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    self.professionBrowser.ownerName:SetText("Shared recipes")
    self.professionBrowser:Show()
    self:RefreshProfessionBrowser()
end

function UI:RefreshProfessionBrowser()
    local browser = self.professionBrowser
    if not browser or not browser:IsShown() then return end
    local profession = self:MergedProfession(browser.professionName)
    if not profession then browser:Hide(); return end
    browser.subtitle:SetText(string.format("%d characters  •  %d unique recipes", #profession.owners, #profession.recipes))

    local recipes = {}
    local currentLevel = UnitLevel("player") or 0
    browser.currentLevelText:SetText("Current level (" .. currentLevel .. ")")
    local threshold = browser.useCurrentLevel and currentLevel or tonumber(browser.levelInput:GetText())
    local search = (browser.searchInput:GetText() or ""):lower()
    local craftableOnly = browser.craftableCheck:GetChecked()
    for _, stored in ipairs(profession.recipes or {}) do
        local recipe = type(stored) == "table" and stored or { id = stored, reagents = {} }
        local required = recipe.requiredLevel or 0
        local levelMatches = not threshold or required == 0 or required <= threshold
        local searchMatches = search == "" or recipeDisplayName(recipe):lower():find(search, 1, true) or (recipe.category or "Other"):lower():find(search, 1, true) or recipeOwners(recipe):lower():find(search, 1, true)
        local canCraft = true
        if craftableOnly then
            for _, reagent in ipairs(recipe.reagents or {}) do
                local owned = C_Item and C_Item.GetItemCount and C_Item.GetItemCount(reagent.id, true, false, true) or 0
                if (owned or 0) < (reagent.count or 1) then canCraft = false; break end
            end
        end
        if levelMatches and searchMatches and canCraft then recipes[#recipes + 1] = recipe end
    end
    table.sort(recipes, function(a, b)
        local categoryA, categoryB = a.category or "Other", b.category or "Other"
        if categoryA == categoryB then return recipeDisplayName(a) < recipeDisplayName(b) end
        return categoryA < categoryB
    end)
    local entries, lastCategory = {}, nil
    local collapsed = browser.collapsedCategories[browser.professionName]
    local filtering = search ~= "" or threshold ~= nil or craftableOnly
    for _, recipe in ipairs(recipes) do
        local category = recipe.category or "Other"
        if category ~= lastCategory then
            entries[#entries + 1] = { header = true, name = category }
            lastCategory = category
        end
        if filtering or not collapsed[category] then entries[#entries + 1] = { recipe = recipe } end
    end
    local selectedIsVisible, firstRecipe = false, recipes[1]
    for _, recipe in ipairs(recipes) do
        if self.selectedRecipe and recipe.id == self.selectedRecipe.id then
            selectedIsVisible = true
            self.selectedRecipe = recipe
        end
    end
    if not selectedIsVisible then self.selectedRecipe = firstRecipe end
    local offset = 0
    for index = 1, math.max(#entries, #browser.recipeRows) do
        local row = self:GetRecipeRow(index)
        local entry = entries[index]
        if entry then
            row.recipe = entry.recipe
            row.category = entry.header and entry.name or nil
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -offset)
            row:SetHeight(entry.header and 24 or 22)
            offset = offset + (entry.header and 27 or 23)
            row.selected:Hide()
            if entry.header then
                row:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8 })
                row:SetBackdropColor(0.32, 0.19, 0.07, 1)
                row:SetBackdropBorderColor(0.65, 0.47, 0.18, 1)
                row.text:ClearAllPoints()
                row.text:SetPoint("LEFT", 7, 0); row.text:SetPoint("RIGHT", -24, 0)
                row.text:SetFontObject("GameFontNormal")
                row.text:SetText("|cffffd36b" .. entry.name .. "|r")
                row.toggle:SetText(not filtering and collapsed[entry.name] and "+" or "−")
                row.toggle:Show()
            else
                row:SetBackdrop(nil)
                row.text:ClearAllPoints()
                row.text:SetPoint("TOPLEFT", 24, -3); row.text:SetPoint("TOPRIGHT", -8, -3)
                row.text:SetFontObject("GameFontHighlightSmall")
                local required = entry.recipe.requiredLevel or 0
                local suffix = required > 0 and ("  |cff999999Lvl " .. required .. "|r") or ""
                row.text:SetText(recipeDisplayName(entry.recipe) .. suffix)
                row.toggle:Hide()
                if self.selectedRecipe and entry.recipe.id == self.selectedRecipe.id then row.selected:Show() end
            end
            row:Show()
        else
            row.recipe = nil
            row:Hide()
        end
    end
    browser.listContent:SetHeight(math.max(1, offset))
    browser.listScroll:SetVerticalScroll(math.min(browser.listScroll:GetVerticalScroll(), math.max(0, offset - browser.listScroll:GetHeight())))
    self:RefreshRecipeDetails()
end

function UI:RefreshRecipeDetails()
    local browser = self.professionBrowser
    if not browser or not browser:IsShown() then return end
    local details, recipe = browser.details, self.selectedRecipe
    details.knownBy:Hide()
    for _, row in ipairs(details.materialRows) do row:Hide(); row.itemLink = nil end
    if not recipe then
        details.recipeName:SetText("No recipes captured")
        details.requiredLevel:Hide()
        details.output:Hide()
        details.materialsTitle:Hide()
        details.wantedCheck:Hide()
        details.wantedText:Hide()
        return
    end

    details.recipeName:SetText(recipeDisplayName(recipe))
    details.requiredLevel:Show()
    details.requiredLevel:SetText((recipe.requiredLevel or 0) > 0 and ("Requires character level " .. recipe.requiredLevel) or "No character level requirement")
    details.materialsTitle:Show()
    local allWanted = #(recipe.owners or {}) > 0
    for _, owner in ipairs(recipe.owners or {}) do
        if not ns:IsRecipeWanted(owner.key, browser.professionName, recipe.id) then allWanted = false end
    end
    details.wantedCheck:SetChecked(allWanted)
    details.wantedCheck:Show()
    details.wantedText:Show()
    local materialCount = math.max(1, math.min(#(recipe.reagents or {}), #details.materialRows))
    details.knownBy:ClearAllPoints()
    details.knownBy:SetPoint("TOPLEFT", details.materialRows[materialCount], "BOTTOMLEFT", 0, -16)
    details.knownBy:SetText("|cffffd36bKnown by:|r\n" .. recipeOwners(recipe))
    details.knownBy:Show()
    browser:SetHeight(math.max(620, 154 + 154 + materialCount * 28 + 16 + details.knownBy:GetStringHeight() + 24))
    details.output.spellID = nil
    local outputName, outputLink, outputIcon = itemDisplay(recipe.outputItemID)
    if outputName then
        local quantity = recipe.quantityMin or 1
        local quantityText = quantity > 1 and (" x" .. quantity) or ""
        if recipe.quantityMax and recipe.quantityMax ~= quantity then quantityText = string.format(" x%d–%d", quantity, recipe.quantityMax) end
        details.output.text:SetText("Creates: " .. (outputLink or outputName) .. quantityText)
        details.output.icon:SetTexture(outputIcon)
        details.output.itemLink = outputLink
        details.output:Show()
    else
        local spellLink, spellIcon, spellID = ns:RecipeSpellDisplay(recipe)
        details.output.text:SetText(spellLink or recipeDisplayName(recipe))
        details.output.icon:SetTexture(spellIcon)
        details.output.itemLink, details.output.spellID = spellLink, spellID
        details.output:Show()
    end

    if #(recipe.reagents or {}) == 0 then
        local row = details.materialRows[1]
        row.text:SetText("Material data was not captured. Ask this player to open the profession again.")
        row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        row:Show()
        return
    end

    for index, reagent in ipairs(recipe.reagents or {}) do
        local row = details.materialRows[index]
        if not row then break end
        local name, link, icon = itemDisplay(reagent.id)
        local owned = C_Item and C_Item.GetItemCount and C_Item.GetItemCount(reagent.id, true, false, true) or 0
        row.text:SetText(string.format("%s  x%d   |cffaaaaaa(you have %d incl. bank)|r", link or name or ("Item #" .. reagent.id), reagent.count or 1, owned or 0))
        row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.itemLink = link
        row:Show()
    end
end

function UI:RefreshPlayerDropdown(profile)
    if not self.gearPanel.characterChooser then return end
    self.gearPanel.characterChooser:SetText(profile and (dropdownLabel(profile) .. "  ...") or "Select character...")
end

function UI:RefreshGear()
    local players = sortedPlayers()
    self.selectedKey = self.selectedKey or ns.db.settings.selectedCharacter
    if not self.selectedKey or not ns.db.players[self.selectedKey] or not ns:IsVisibleCharacter(self.selectedKey) then
        local ownKey = ns:PlayerKey()
        self.selectedKey = ns.db.players[ownKey] and ownKey or (players[1] and players[1].key)
    end
    local profile = self.selectedKey and ns.db.players[self.selectedKey]
    self:RefreshPlayerDropdown(profile)
    self.gearPanel.summary.copyName.profile = profile
    self.gearPanel.summary.copyName:SetEnabled(profile ~= nil)
    self.gearPanel.altCheck:SetChecked(profile and ns.db.settings.alts and ns.db.settings.alts[profile.key] or false)
    self.gearPanel.altCheck:SetEnabled(profile ~= nil)
    self.gearPanel.altCheck.label:SetTextColor(profile and 1 or 0.5, profile and 1 or 0.5, profile and 1 or 0.5)

    if not profile then
        self.gearPanel.summary.name:SetText("No character data")
        self.gearPanel.summary.details:SetText("Refresh local data or choose a sharing mode in Settings")
        self.gearPanel.summary.talents:Hide()
        self.gearPanel.summary.updated:Hide()
    else
        local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[profile.classToken or ""]
        if color then
            self.gearPanel.summary.name:SetTextColor(color.r, color.g, color.b)
        else
            self.gearPanel.summary.name:SetTextColor(1, 1, 1)
        end
        self.gearPanel.summary.name:SetText(displayName(profile))
        self.gearPanel.summary.details:SetText(string.format("%s  •  Level %d", classDisplayName(profile), profile.level or 0))
        if profile.sharing and profile.sharing.gear == false then
            self.gearPanel.summary.details:SetText(string.format("%s  •  Level %d  •  Equipment not shared", classDisplayName(profile), profile.level or 0))
        end
        self.gearPanel.summary.talents.text:SetText(profile.specName and profile.specName ~= "" and profile.specName or "Talent data unavailable")
        self.gearPanel.summary.talents.profileKey = profile.key
        self.gearPanel.summary.talents:SetEnabled(profile.talents ~= nil)
        self.gearPanel.summary.talents:Show()
        self.gearPanel.summary.updated:SetText("Updated " .. age(profile.updated) .. " ago")
        self.gearPanel.summary.updated:Show()
    end

    for slot = 1, 19 do
        local button = self.gearButtons[slot]
        if button then
            local item = profile and profile.gear and profile.gear[slot]
            button.itemLink = item and item.link
            button.icon:SetTexture(itemIcon(item))
            button.icon:SetShown(item ~= nil)
            button.empty:SetShown(item == nil)
            button.level:SetText(item and item.ilvl and item.ilvl > 0 and item.ilvl or "")
            local quality = itemQuality(item)
            local qualityColor = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
            if qualityColor then
                button:SetBackdropBorderColor(qualityColor.r, qualityColor.g, qualityColor.b, 1)
            else
                button:SetBackdropBorderColor(0.45, 0.45, 0.45, 1)
            end
        end
    end
end

function UI:GetRow(index)
    if self.rows[index] then return self.rows[index] end
    local row = CreateFrame("Button", nil, self.frame.content)
    row:SetSize(640, 38)
    row:SetPoint("TOPLEFT", 4, -((index - 1) * 40))
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", 6, 0); text:SetPoint("RIGHT", -6, 0); text:SetJustifyH("LEFT")
    row.text = text
    row:SetScript("OnEnter", function(self)
        if not self.itemLink then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink(self.itemLink); GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        if self.itemLink and IsShiftKeyDown() then
            ChatEdit_InsertLink(self.itemLink)
        elseif self.action then
            self.action()
        end
    end)
    self.rows[index] = row
    return row
end

function UI:GetProfessionCard(index)
    if self.professionCards[index] then return self.professionCards[index] end
    local card = CreateFrame("Button", nil, self.frame.content, "BackdropTemplate")
    card:SetSize(204, 112)
    card:SetBackdrop({
        bgFile = "Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    card:SetBackdropColor(0.38, 0.27, 0.13, 0.96)
    local title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -9); card.title = title
    local icon = card:CreateTexture(nil, "ARTWORK")
    icon:SetSize(40, 40); icon:SetPoint("TOP", 0, -28); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92); card.icon = icon
    local owner = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    owner:SetPoint("TOP", icon, "BOTTOM", 0, -3); owner:SetWidth(190); card.owner = owner
    local stats = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    stats:SetPoint("TOP", owner, "BOTTOM", 0, -2); card.stats = stats
    card:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(1, 0.82, 0, 1)
        local profession = UI:MergedProfession(self.professionName)
        if not profession then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.professionName)
        local owners = {}
        for _, owner in ipairs(profession.owners) do owners[#owners + 1] = owner end
        table.sort(owners, function(a, b)
            local ar = a.professions[self.professionName].rank or 0
            local br = b.professions[self.professionName].rank or 0
            if ar ~= br then return ar > br end
            return displayName(a):lower() < displayName(b):lower()
        end)
        for index = 1, math.min(3, #owners) do
            local owner = owners[index]
            local skill = owner.professions[self.professionName]
            GameTooltip:AddLine(string.format("%s: %d/%d", displayName(owner), skill.rank or 0, skill.maxRank or 0), 1, 1, 1, true)
        end
        if #owners > 3 then GameTooltip:AddLine("+ " .. (#owners - 3) .. " other characters", 0.6, 0.6, 0.6) end
        GameTooltip:AddLine("Click to browse shared recipes", 1, 0.82, 0)
        GameTooltip:Show()
    end)
    card:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(1, 1, 1, 1); GameTooltip:Hide() end)
    card:SetScript("OnClick", function(self)
        if self.professionName then UI:OpenProfession(self.professionName) end
    end)
    self.professionCards[index] = card
    return card
end

function UI:ClearRows()
    for _, row in ipairs(self.rows) do
        row:Hide(); row.itemLink = nil; row.action = nil
        if row.icon then row.icon:Hide() end
        if row.delete then row.delete:Hide() end
        if row.review then row.review:Hide() end
    end
    for _, card in ipairs(self.professionCards) do card:Hide() end
end

function UI:AddRow(text, link, action)
    self.rowCount = self.rowCount + 1
    local row = self:GetRow(self.rowCount)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 4, -((self.rowCount - 1) * 40))
    row:SetHeight(38)
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", 6, 0); row.text:SetPoint("RIGHT", -6, 0)
    row.text:SetText(text); row.itemLink = link; row.action = action; row:Show()
end

function UI:ShowProfessions()
    local players = sortedPlayers()
    if #players == 0 then self:AddRow("No data. Open your profession windows and click Share my data.") end
    local cardIndex = 0
    local unique, names = {}, {}
    for _, profile in ipairs(players) do
        for name in pairs(profile.professions or {}) do
            if not unique[name] then unique[name] = true; names[#names + 1] = name end
        end
    end
    table.sort(names)
    for _, name in ipairs(names) do
            local profession = self:MergedProfession(name)
            cardIndex = cardIndex + 1
            local card = self:GetProfessionCard(cardIndex)
            local column = (cardIndex - 1) % 3
            local row = math.floor((cardIndex - 1) / 3)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", 7 + (column * 212), -(row * 120))
            card.title:SetText(name)
            card.icon:SetTexture(profession.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            card.owner:SetText(string.format("%d characters", #profession.owners))
            card.stats:SetText(string.format("%d unique recipes", #profession.recipes))
            card.professionName = name
            card:Show()
    end
    if cardIndex == 0 and #players > 0 then self:AddRow("No profession data. Open a profession window and click Share my data.") end
    self.contentHeight = math.max(self.rowCount * 40, math.ceil(cardIndex / 3) * 120)
end

function UI:ShowBoe()
    ns:PruneBoe()
    if not self.clearBoe then
        local button = CreateFrame("Button", nil, self.frame, "UIPanelButtonTemplate")
        button:SetSize(110, 24); button:SetPoint("TOPRIGHT", -38, -73); button:SetText("Clear all")
        button:SetScript("OnClick", function() ns:ClearBoe() end)
        self.clearBoe = button
    end
    self.clearBoe:Show()
    self.expandedBoe = self.expandedBoe or setmetatable({}, { __mode = "k" })
    local offset = 0
    local function add(text, link, height, action)
        self:AddRow(text, link, action)
        local row = self.rows[self.rowCount]
        height = math.max(height, row.text:GetStringHeight() + 8)
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", 4, -offset)
        row:SetHeight(height)
        offset = offset + height
        return row
    end
    add("BoE history — last 48 hours", nil, 34)
    local shown = 0
    for _, record in ipairs(ns.db.boe or {}) do
        if ns:IsVisibleCharacter(record.looter) then
        shown = shown + 1
        local expanded = self.expandedBoe[record]
        local toggle = function()
            self.expandedBoe[record] = not self.expandedBoe[record]
            self:Refresh()
        end
        local link = record.link or (record.id and ("item:" .. record.id))
        local row = add(string.format("%s  %s  |cffaaaaaaiLvl %d|r", expanded and "−" or "+", record.link or record.name or "?", record.ilvl or 0), link, 34, toggle)
        if not row.icon then
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(28, 28); row.icon:SetPoint("LEFT", 4, 0)
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        row.icon:SetTexture(itemIcon(record) or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.icon:Show()
        row.text:ClearAllPoints(); row.text:SetPoint("LEFT", 40, 0); row.text:SetPoint("RIGHT", -6, 0)
        if not row.delete then
            row.delete = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.delete:SetSize(62, 22); row.delete:SetPoint("RIGHT", -4, 0); row.delete:SetText("Delete")
        end
        row.text:ClearAllPoints(); row.text:SetPoint("LEFT", 40, 0); row.text:SetPoint("RIGHT", -74, 0)
        row.delete:SetScript("OnClick", function() ns:DeleteBoe(record) end)
        row.delete:Show()
        if not row.review then
            row.review = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.review:SetSize(74, 22); row.review:SetPoint("RIGHT", row.delete, "LEFT", -4, 0); row.review:SetText("Compare")
        end
        row.review:SetScript("OnClick", function() ns:AnnounceBoeUpgrades(record, true) end)
        row.review:Show()
        row.text:ClearAllPoints(); row.text:SetPoint("LEFT", 40, 0); row.text:SetPoint("RIGHT", -154, 0)
        local looter = ns.db.players[record.looter]
        add(string.format("    |cffaaaaaaLoot: %s  •  %s ago|r", looter and playerChoiceLabel(looter) or record.looter or "?", age(record.at)), nil, 20, toggle)
        local comparisons, upgrades = ns:ComparisonFor(record), {}
        for _, comparison in ipairs(comparisons) do
            if comparison.usable and comparison.delta > 0 and ns:IsActiveTeamCharacter(comparison.profile.key)
                and not ((ns.db.settings and ns.db.settings.alts) or {})[comparison.profile.key] then
                upgrades[#upgrades + 1] = string.format("%s (+%d)", playerChoiceLabel(comparison.profile), comparison.delta)
            end
        end
        local summary = #upgrades > 0 and ("|cff66dd88Potential upgrades: " .. table.concat(upgrades, ", ") .. "|r") or "|cff999999No potential upgrades in saved character data|r"
        add("    " .. summary, nil, 24, toggle)
        if expanded then
        local responses = {}
        for playerKey, choice in pairs(record.responses or {}) do
            local profile = ns.db.players[playerKey]
            responses[#responses + 1] = (profile and playerChoiceLabel(profile) or playerKey) .. ": " .. choice
        end
        table.sort(responses)
        if #responses > 0 then add("    |cffffd36bResponses:|r " .. table.concat(responses, "  •  "), nil, 24) end
        for _, comparison in ipairs(comparisons) do
            if comparison.usable then
                local old = comparison.equipped and comparison.equipped.link or "empty slot"
                local sign = comparison.delta >= 0 and "+" or ""
                add(string.format("    %s: %s  (%s%d iLvl)", playerChoiceLabel(comparison.profile), old, sign, comparison.delta), comparison.equipped and comparison.equipped.link, 24)
            else
                add(string.format("    |cff999999%s: cannot equip — %s|r", playerChoiceLabel(comparison.profile), comparison.unusableReason or "class restriction"), nil, 24)
            end
        end
        end
        offset = offset + 10
        end
    end
    if shown == 0 then add("No BoE items for the selected mode.", nil, 28) end
    self.contentHeight = offset
end

function UI:Refresh()
    if not self.frame or not self.frame:IsShown() or not ns.db then return end
    if self.clearBoe then self.clearBoe:Hide() end
    local mode = ns:Mode()
    self.frame.TitleText:SetText("Forever Team Gear — " .. (mode == "guild" and "Guild" or mode == "group" and (ns:UsesGuild() and "Private + Guild" or "Private group") or "Offline"))
    self:ClearRows(); self.rowCount = 0; self.contentHeight = nil
    if ns.ShowMacroPanel then ns:ShowMacroPanel(self.mode == "macros") end
    if self.mode == "macros" then
        self.frame.scroll:Hide(); self.inventoryPanel:Hide(); self.gearPanel:Hide()
        return
    end
    if self.mode == "team" then
        self.frame.scroll:Hide()
        self.inventoryPanel:Hide()
        self.gearPanel:Show()
        self:RefreshGear()
        return
    end

    if self.mode == "inventory" then
        self.frame.scroll:Hide()
        self.gearPanel:Hide()
        self.inventoryPanel:Show()
        self:RefreshInventory()
        return
    end

    self.gearPanel:Hide()
    self.inventoryPanel:Hide()
    self.frame.scroll:Show()
    if self.mode == "boe" then self:ShowBoe() else self:ShowProfessions() end
    self.frame.content:SetHeight(math.max(1, self.contentHeight or (self.rowCount * 40)))
    self.frame.scroll:SetVerticalScroll(math.min(self.frame.scroll:GetVerticalScroll(), math.max(0, self.frame.content:GetHeight() - self.frame.scroll:GetHeight())))
end

function ns:RefreshWindow()
    if ns.RefreshTalentBrowser then ns:RefreshTalentBrowser() end
    if UI.frame then UI:Refresh() end
    if UI.professionBrowser and UI.professionBrowser:IsShown() then UI:RefreshProfessionBrowser() end
    if ns.RefreshMacroWindow then ns:RefreshMacroWindow() end
    if ns.RefreshCharacterPicker then ns:RefreshCharacterPicker() end
end

function ns:SelectCharacter(key)
    if not self.db.players[key] or not self:IsVisibleCharacter(key) then return false end
    UI.selectedKey = key
    self.db.settings.selectedCharacter = key
    self:RefreshWindow()
    return true
end

function ns:UpdateSyncIndicator()
    if not UI.frame or not UI.frame.syncButton then return end
    local queued, incoming = self:SyncStatus()
    UI.frame.syncButton:SetText(self:IsGroupSyncing() and "Syncing..." or "Sync Party")
    if UI.frame.shareButton then UI.frame.shareButton:SetText(queued > 0 and ("Sending " .. queued) or "Share my data") end
end

function ns:SelectedCharacterKey()
    return UI.selectedKey or self:PlayerKey()
end

function ns:CloseSharedWindows()
    if UI.professionBrowser then UI.professionBrowser:Hide() end
    for _, name in ipairs({ "ForeverTeamGearTalentFrame", "ForeverTeamGearUpgradePopup", "ForeverTeamGearMacroFrame", "ForeverTeamGearCharacterPicker", "ForeverTeamGearCopyName" }) do
        if _G[name] then _G[name]:Hide() end
    end
end

function ns:ToggleWindow(mode)
    local requestedMode = mode or UI.mode
    if not UI.frame then createWindow() end
    if UI.frame:IsShown() and requestedMode == UI.mode then
        UI.frame:Hide()
    else
        UI.mode = requestedMode
        UI.frame:Show()
        UI:Refresh()
    end
end

function UI:Initialize()
    createWindow()
    self.frame:Hide()
    ns:On("ITEM_DATA_LOAD_RESULT", function()
        if self.itemDataRefreshPending then return end
        self.itemDataRefreshPending = true
        C_Timer.After(0.2, function()
            self.itemDataRefreshPending = false
            if self.professionBrowser and self.professionBrowser:IsShown() then self:RefreshProfessionBrowser() end
            if self.inventoryPanel and self.inventoryPanel:IsShown() then self:RefreshInventory() end
        end)
    end)
    local function refreshOpenProfession()
        if self.professionBrowser and self.professionBrowser:IsShown() then
            C_Timer.After(0, function() self:RefreshProfessionBrowser() end)
        end
    end
    ns:On("BANKFRAME_OPENED", refreshOpenProfession)
    ns:On("PLAYERBANKSLOTS_CHANGED", refreshOpenProfession)
end
