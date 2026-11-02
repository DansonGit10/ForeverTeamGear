local _, ns = ...

local TalentUI = { nodeButtons = {}, edgeTextures = {}, arrowTextures = {}, tabs = {} }

local BACKGROUND_NAMES = {
    DRUID = { balance = "DruidBalance", feralcombat = "DruidFeralCombat", restoration = "DruidRestoration" },
    HUNTER = { beastmastery = "HunterBeastMastery", marksmanship = "HunterMarksmanship", survival = "HunterSurvival" },
    MAGE = { arcane = "MageArcane", fire = "MageFire", frost = "MageFrost" },
    PALADIN = { holy = "PaladinHoly", protection = "PaladinProtection", retribution = "PaladinCombat", combat = "PaladinCombat" },
    PRIEST = { discipline = "PriestDiscipline", holy = "PriestHoly", shadow = "PriestShadow" },
    ROGUE = { assassination = "RogueAssassination", combat = "RogueCombat", subtlety = "RogueSubtlety" },
    SHAMAN = { elemental = "ShamanElementalCombat", elementalcombat = "ShamanElementalCombat", enhancement = "ShamanEnhancement", restoration = "ShamanRestoration" },
    WARLOCK = { affliction = "WarlockCurses", curses = "WarlockCurses", demonology = "WarlockSummoning", summoning = "WarlockSummoning", destruction = "WarlockDestruction" },
    WARRIOR = { arms = "WarriorArms", fury = "WarriorFury", protection = "WarriorProtection" },
}

local function normalizedName(value)
    return tostring(value or ""):lower():gsub("[^a-z]", "")
end

local function pointForGroup(profile, groupID)
    for _, group in ipairs(profile.talents and profile.talents.groups or {}) do
        if group.id == groupID then return group.points or 0 end
    end
    return 0
end

local function createBackground(panel)
    local shade = panel:CreateTexture(nil, "BACKGROUND", nil, -8)
    shade:SetAllPoints()
    shade:SetColorTexture(0.035, 0.025, 0.015, 1)

    local art = CreateFrame("Frame", nil, panel)
    art:SetSize(320, 512)
    art:SetPoint("TOP", 0, -42)
    panel.art = art

    local topLeft = art:CreateTexture(nil, "BACKGROUND", nil, -6)
    topLeft:SetSize(256, 256); topLeft:SetPoint("TOPLEFT")
    local topRight = art:CreateTexture(nil, "BACKGROUND", nil, -6)
    topRight:SetSize(64, 256); topRight:SetPoint("TOPLEFT", topLeft, "TOPRIGHT")
    local bottomLeft = art:CreateTexture(nil, "BACKGROUND", nil, -6)
    bottomLeft:SetSize(256, 256); bottomLeft:SetPoint("TOPLEFT", topLeft, "BOTTOMLEFT")
    local bottomRight = art:CreateTexture(nil, "BACKGROUND", nil, -6)
    bottomRight:SetSize(64, 256); bottomRight:SetPoint("TOPLEFT", bottomLeft, "TOPRIGHT")
    panel.backgroundPieces = { topLeft, topRight, bottomLeft, bottomRight }

    local veil = art:CreateTexture(nil, "BACKGROUND", nil, -5)
    veil:SetAllPoints()
    veil:SetColorTexture(0, 0, 0, 0.18)
end

local function createBrowser()
    local frame = CreateFrame("Frame", "ForeverTeamGearTalentFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(430, 684)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame.TitleText:SetText("Talents")

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOP", 0, -34)
    subtitle:SetText("Read-only synchronized build")
    frame.subtitle = subtitle

    local panel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    panel:SetPoint("TOPLEFT", 22, -52)
    panel:SetSize(386, 556)
    panel:SetBackdrop({
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
        edgeSize = 18,
        insets = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    panel:SetBackdropBorderColor(0.8, 0.62, 0.15, 1)
    createBackground(panel)

    local treeIcon = panel:CreateTexture(nil, "ARTWORK")
    treeIcon:SetSize(34, 34); treeIcon:SetPoint("TOPLEFT", 18, -11); treeIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    panel.icon = treeIcon
    local treeTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    treeTitle:SetPoint("LEFT", treeIcon, "RIGHT", 8, 1); treeTitle:SetPoint("RIGHT", -16, 0); treeTitle:SetJustifyH("LEFT")
    panel.title = treeTitle
    TalentUI.panel = panel

    local status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    status:SetPoint("CENTER")
    status:SetWidth(320)
    panel.status = status

    for index = 1, 3 do
        local tab = CreateFrame("Button", nil, frame, "BackdropTemplate")
        tab:SetSize(122, 48)
        tab:SetPoint("BOTTOMLEFT", 25 + ((index - 1) * 127), 20)
        tab:SetBackdrop({
            bgFile = "Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
            edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        tab:SetBackdropColor(0.34, 0.22, 0.08, 1)
        local icon = tab:CreateTexture(nil, "ARTWORK")
        icon:SetSize(30, 30); icon:SetPoint("LEFT", 7, 0); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        tab.icon = icon
        local label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", icon, "RIGHT", 5, 0); label:SetPoint("RIGHT", -4, 0); label:SetJustifyH("LEFT"); label:SetWordWrap(true)
        tab.label = label
        tab:SetScript("OnClick", function(self) TalentUI:ShowGroup(self.groupIndex) end)
        tab:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(1, 0.82, 0, 1) end)
        tab:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(self.groupIndex == TalentUI.activeGroup and 1 or 0.55, self.groupIndex == TalentUI.activeGroup and 0.82 or 0.45, self.groupIndex == TalentUI.activeGroup and 0 or 0.25, 1)
        end)
        TalentUI.tabs[index] = tab
    end

    frame:Hide()
    TalentUI.frame = frame
end

local function getNodeButton(index)
    local button = TalentUI.nodeButtons[index]
    if not button then
        button = CreateFrame("Button", nil, TalentUI.panel)
        button:SetSize(44, 44)
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 4, -4); icon:SetPoint("BOTTOMRIGHT", -4, 4)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        button.icon = icon
        local slot = button:CreateTexture(nil, "OVERLAY")
        slot:SetAllPoints(); slot:SetTexture("Interface\\Buttons\\UI-Quickslot2")
        button.slot = slot
        local rankBorder = button:CreateTexture(nil, "OVERLAY")
        rankBorder:SetTexture("Interface\\TalentFrame\\UI-TalentRank-Border")
        rankBorder:SetSize(28, 14); rankBorder:SetPoint("BOTTOMRIGHT", 5, -1)
        button.rankBorder = rankBorder
        local rank = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        rank:SetPoint("CENTER", rankBorder, "CENTER", 0, 0)
        button.rank = rank
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.spellID and GameTooltip.SetSpellByID then
                GameTooltip:SetSpellByID(self.spellID)
            else
                GameTooltip:SetText(self.talentName or "Talent")
                if self.description and self.description ~= "" then GameTooltip:AddLine(self.description, 1, 1, 1, true) end
            end
            GameTooltip:AddLine(string.format("Rank %d/%d", self.currentRank or 0, self.maxRank or 0), 0.35, 0.8, 1)
            GameTooltip:AddLine("Synchronized view — read only", 0.55, 0.55, 0.55)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        TalentUI.nodeButtons[index] = button
    end
    button:ClearAllPoints()
    return button
end

local function getEdge(index)
    local edge = TalentUI.edgeTextures[index]
    if not edge then
        edge = TalentUI.panel:CreateTexture(nil, "BORDER")
        edge:SetTexture("Interface\\Buttons\\WHITE8X8")
        TalentUI.edgeTextures[index] = edge
    end
    edge:ClearAllPoints()
    return edge
end

local function getArrow(index)
    local arrow = TalentUI.arrowTextures[index]
    if not arrow then
        arrow = TalentUI.panel:CreateTexture(nil, "BORDER")
        arrow:SetTexture("Interface\\TalentFrame\\UI-TalentArrows")
        arrow:SetTexCoord(0, 0.5, 0, 0.5)
        TalentUI.arrowTextures[index] = arrow
    end
    arrow:ClearAllPoints()
    return arrow
end

local function hideTree()
    for _, button in ipairs(TalentUI.nodeButtons) do button:Hide() end
    for _, edge in ipairs(TalentUI.edgeTextures) do edge:Hide() end
    for _, arrow in ipairs(TalentUI.arrowTextures) do arrow:Hide() end
end

local function talentDefinition(configID, nodeInfo, selected)
    local entryID = selected and selected.entryID and selected.entryID > 0 and selected.entryID
        or (nodeInfo.activeEntry and nodeInfo.activeEntry.entryID)
        or (nodeInfo.entryIDs and nodeInfo.entryIDs[1])
    if not entryID then return nil end
    local entryOK, entryInfo = pcall(C_Traits.GetEntryInfo, configID, entryID)
    if not entryOK or not entryInfo then return nil end
    local definitionOK, definition = pcall(C_Traits.GetDefinitionInfo, entryInfo.definitionID)
    if not definitionOK or not definition then return entryID, entryInfo end
    local spellID = definition.spellID
    local name = definition.overrideName or (spellID and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)) or "Talent"
    local icon = definition.overrideIcon or (spellID and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID))
    return entryID, entryInfo, spellID, name, icon
end

local function prepareView(profile)
    local talents = profile.talents
    if not talents or not talents.specID or talents.specID == 0 then return nil end
    if not C_ClassTalents or not C_ClassTalents.InitializeViewLoadout or not C_Traits then return nil end
    local ok = pcall(C_ClassTalents.InitializeViewLoadout, talents.specID, profile.level or 60)
    if not ok then return nil end
    local configID = Constants and Constants.TraitConsts and Constants.TraitConsts.VIEW_TRAIT_CONFIG_ID or -1
    local treeID = talents.treeID
    if C_ClassTalents.GetTraitTreeForSpec then
        local treeOK, viewTreeID = pcall(C_ClassTalents.GetTraitTreeForSpec, talents.specID)
        if treeOK and viewTreeID then treeID = viewTreeID end
    end
    return configID, treeID
end

local function angleFor(dx, dy)
    if dx == 0 then return dy >= 0 and (math.pi / 2) or (-math.pi / 2) end
    local angle = math.atan(dy / dx)
    if dx < 0 then angle = angle + math.pi end
    return angle
end

local function setTreeBackground(profile, group)
    local classBackgrounds = BACKGROUND_NAMES[profile.classToken or ""] or {}
    local fileName = classBackgrounds[normalizedName(group.displayName)]
    if not fileName then
        local className = (profile.classToken or "Mage"):lower():gsub("^%l", string.upper)
        fileName = className .. tostring(group.displayName or "Fire"):gsub("[^%a]", "")
    end
    local base = "Interface\\TalentFrame\\" .. fileName .. "-"
    local pieces = TalentUI.panel.backgroundPieces
    pieces[1]:SetTexture(base .. "TopLeft")
    pieces[2]:SetTexture(base .. "TopRight")
    pieces[3]:SetTexture(base .. "BottomLeft")
    pieces[4]:SetTexture(base .. "BottomRight")
end

function TalentUI:ShowGroup(groupIndex)
    local profile, group = self.profile, self.groups and self.groups[groupIndex]
    if not profile or not group then return end
    self.activeGroup = groupIndex
    hideTree()
    self.panel.status:Hide()
    setTreeBackground(profile, group)
    self.panel.icon:SetTexture(group.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    self.panel.title:SetText(string.format("%s  —  %d points", tostring(group.displayName or "Tree"), pointForGroup(profile, group.groupID)))

    for index, tab in ipairs(self.tabs) do
        local tabGroup = self.groups[index]
        if tabGroup then
            tab.groupIndex = index
            tab.icon:SetTexture(tabGroup.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            tab.label:SetText(string.format("%s\n%d", tostring(tabGroup.displayName or "Tree"), pointForGroup(profile, tabGroup.groupID)))
            tab:SetBackdropColor(index == groupIndex and 0.58 or 0.28, index == groupIndex and 0.38 or 0.18, 0.07, 1)
            tab:SetBackdropBorderColor(index == groupIndex and 1 or 0.55, index == groupIndex and 0.82 or 0.45, index == groupIndex and 0 or 0.25, 1)
            tab:Show()
        else
            tab:Hide()
        end
    end

    local nodes, nodeByID = {}, {}
    local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
    for _, nodeID in ipairs(self.nodeIDs or {}) do
        local ok, nodeInfo = pcall(C_Traits.GetNodeInfo, self.configID, nodeID)
        if ok and nodeInfo and nodeInfo.entryIDs and #nodeInfo.entryIDs > 0 then
            for _, memberGroupID in ipairs(nodeInfo.groupIDs or {}) do
                if memberGroupID == group.groupID then
                    nodes[#nodes + 1] = nodeInfo
                    nodeByID[nodeInfo.ID] = nodeInfo
                    minX = math.min(minX, nodeInfo.posX or 0); maxX = math.max(maxX, nodeInfo.posX or 0)
                    minY = math.min(minY, nodeInfo.posY or 0); maxY = math.max(maxY, nodeInfo.posY or 0)
                    break
                end
            end
        end
    end
    if #nodes == 0 then
        self.panel.status:SetText("The Forever client did not return this talent-tree layout.")
        self.panel.status:Show()
        return
    end

    local width, height = math.max(1, maxX - minX), math.max(1, maxY - minY)
    local positions = {}
    for index, nodeInfo in ipairs(nodes) do
        local x = 58 + (((nodeInfo.posX or 0) - minX) / width) * 226
        local y = -74 - (((nodeInfo.posY or 0) - minY) / height) * 414
        positions[nodeInfo.ID] = { x = x + 22, y = y - 22 }
        local selected = profile.talents.nodes and profile.talents.nodes[nodeInfo.ID]
        local entryID, entryInfo, spellID, name, icon = talentDefinition(self.configID, nodeInfo, selected)
        local button = getNodeButton(index)
        button:SetPoint("TOPLEFT", self.panel, "TOPLEFT", x, y)
        button.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        button.icon:SetDesaturated(not selected)
        local rank = selected and selected.rank or 0
        local maxRank = entryInfo and entryInfo.maxRanks or nodeInfo.maxRanks or 1
        button.slot:SetVertexColor(selected and (rank >= maxRank and 1 or 0.1) or 0.45, selected and (rank >= maxRank and 0.82 or 1) or 0.45, selected and 0.1 or 0.45, 1)
        button.rank:SetText(rank > 0 and tostring(rank) or "")
        button.rank:SetTextColor(rank >= maxRank and 1 or 0.1, rank >= maxRank and 0.82 or 1, rank >= maxRank and 0 or 0.1)
        button.rankBorder:SetShown(rank > 0)
        button.spellID = spellID; button.talentName = name; button.currentRank = rank; button.maxRank = maxRank
        button.description = nil
        if entryID and C_Traits.GetTraitDescription then
            local descOK, description = pcall(C_Traits.GetTraitDescription, entryID, math.max(1, rank))
            if descOK then button.description = description end
        end
        button:Show()
    end

    local edgeIndex = 0
    for nodeID, nodeInfo in pairs(nodeByID) do
        local from = positions[nodeID]
        for _, edgeInfo in ipairs(nodeInfo.visibleEdges or {}) do
            local to = positions[edgeInfo.targetNode]
            if from and to then
                edgeIndex = edgeIndex + 1
                local dx, dy = to.x - from.x, to.y - from.y
                local length = math.max(1, math.sqrt((dx * dx) + (dy * dy)))
                local active = profile.talents.nodes[nodeID] and profile.talents.nodes[edgeInfo.targetNode]
                local edge = getEdge(edgeIndex)
                edge:SetSize(math.max(1, length - 34), 4)
                edge:SetPoint("CENTER", self.panel, "TOPLEFT", (from.x + to.x) / 2, (from.y + to.y) / 2)
                if edge.SetRotation then edge:SetRotation(angleFor(dx, dy)) end
                edge:SetVertexColor(active and 0.1 or 0.38, active and 1 or 0.38, active and 0.1 or 0.38, active and 0.95 or 0.72)
                edge:Show()

                local arrow = getArrow(edgeIndex)
                arrow:SetSize(16, 16)
                arrow:SetPoint("CENTER", self.panel, "TOPLEFT", to.x - (dx / length) * 25, to.y - (dy / length) * 25)
                if arrow.SetRotation then arrow:SetRotation(angleFor(dx, dy) - (math.pi / 2)) end
                arrow:SetVertexColor(active and 0.1 or 0.45, active and 1 or 0.45, active and 0.1 or 0.45, 1)
                arrow:Show()
            end
        end
    end
end

function TalentUI:ShowProfile(profile)
    if not self.frame then createBrowser() end
    hideTree()
    self.profile = profile
    self.frame.TitleText:SetText("Talents — " .. (ns.ProfileChoiceLabel and ns.ProfileChoiceLabel(profile) or profile.name or "Character"))
    self.frame:Show()

    local configID, treeID = prepareView(profile)
    if not configID or not treeID then
        self.panel.status:SetText("Talent layout is not available yet. Ask this player to update and synchronize again.")
        self.panel.status:Show()
        for _, tab in ipairs(self.tabs) do tab:Hide() end
        return
    end

    local groupsOK, groups = pcall(C_Traits.GetGroupDisplayInfoByTreeID, treeID)
    local nodesOK, nodeIDs = pcall(C_Traits.GetTreeNodes, treeID)
    if not groupsOK or not nodesOK or type(groups) ~= "table" or type(nodeIDs) ~= "table" then
        self.panel.status:SetText("The Forever client did not return the talent-tree layout.")
        self.panel.status:Show()
        for _, tab in ipairs(self.tabs) do tab:Hide() end
        return
    end
    table.sort(groups, function(a, b) return (a.orderIndex or 0) < (b.orderIndex or 0) end)
    self.groups, self.nodeIDs, self.configID = groups, nodeIDs, configID
    self:ShowGroup(1)
end

function ns:OpenTalentBrowser(profileKey)
    local profile = self.db and self.db.players and self.db.players[profileKey]
    if profile then TalentUI:ShowProfile(profile) end
end
