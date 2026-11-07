local _, ns = ...

local TalentUI = { nodeButtons = {}, edgeTextures = {}, arrowTextures = {}, panels = {} }

local BACKGROUND_NAMES = {
    DRUID = { balance = "DruidBalance", feralcombat = "DruidFeralCombat", restoration = "DruidRestoration" },
    HUNTER = { beastmastery = "HunterBeastMastery", marksmanship = "HunterMarksmanship", survival = "HunterSurvival" },
    MAGE = { arcane = "MageArcane", fire = "MageFire", frost = "MageFrost" },
    PALADIN = { holy = "PaladinHoly", protection = "PaladinProtection", retribution = "PaladinCombat", combat = "PaladinCombat" },
    PRIEST = { discipline = "PriestDiscipline", holy = "PriestHoly", shadow = "PriestShadow", shadowmagic = "PriestShadow" },
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

local function createBrowser()
    local frame = CreateFrame("Frame", "ForeverTeamGearTalentFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(1040, 650)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame.TitleText:SetText("Synchronized Talents")

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    subtitle:SetPoint("TOP", 0, -34)
    frame.subtitle = subtitle

    local status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    status:SetPoint("CENTER")
    status:SetWidth(700)
    frame.status = status

    local footer = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    footer:SetPoint("BOTTOM", 0, 18)
    footer:SetText("Read-only synchronized talent build")

    for index = 1, 3 do
        local panel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        panel:SetPoint("TOPLEFT", 14 + ((index - 1) * 339), -62)
        panel:SetSize(332, 552)
        panel:SetBackdrop({
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
            edgeSize = 14,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        local shade = panel:CreateTexture(nil, "BACKGROUND", nil, -8)
        shade:SetAllPoints(); shade:SetColorTexture(0.025, 0.018, 0.01, 1)
        local art = CreateFrame("Frame", nil, panel)
        art:SetSize(320, 512); art:SetPoint("TOP", 0, -38)
        local topLeft = art:CreateTexture(nil, "BACKGROUND", nil, -7)
        topLeft:SetSize(256, 256); topLeft:SetPoint("TOPLEFT")
        local topRight = art:CreateTexture(nil, "BACKGROUND", nil, -7)
        topRight:SetSize(64, 256); topRight:SetPoint("TOPLEFT", topLeft, "TOPRIGHT")
        local bottomLeft = art:CreateTexture(nil, "BACKGROUND", nil, -7)
        bottomLeft:SetSize(256, 256); bottomLeft:SetPoint("TOPLEFT", topLeft, "BOTTOMLEFT")
        local bottomRight = art:CreateTexture(nil, "BACKGROUND", nil, -7)
        bottomRight:SetSize(64, 256); bottomRight:SetPoint("TOPLEFT", bottomLeft, "TOPRIGHT")
        panel.backgroundPieces = { topLeft, topRight, bottomLeft, bottomRight }
        local veil = art:CreateTexture(nil, "BACKGROUND", nil, -6)
        veil:SetAllPoints(); veil:SetColorTexture(0, 0, 0, 0.16)
        local icon = panel:CreateTexture(nil, "ARTWORK")
        icon:SetSize(30, 30); icon:SetPoint("TOPLEFT", 14, -12); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        panel.icon = icon
        local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("LEFT", icon, "RIGHT", 8, 0); title:SetPoint("RIGHT", -12, 0); title:SetJustifyH("LEFT")
        panel.title = title
        TalentUI.panels[index] = panel
    end

    frame:Hide()
    TalentUI.frame = frame
end

local function getNodeButton(index, parent)
    local button = TalentUI.nodeButtons[index]
    if not button then
        button = CreateFrame("Button", nil, parent, "BackdropTemplate")
        button:SetSize(38, 38)
        button:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
            edgeSize = 12,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 4, -4); icon:SetPoint("BOTTOMRIGHT", -4, 4)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        button.icon = icon
        local rank = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        rank:SetPoint("BOTTOMRIGHT", -3, 3)
        button.rank = rank
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.talentName or "Talent", 1, 0.82, 0)
            local appended = false
            if self.entryID and GameTooltip.AppendInfo then
                appended = pcall(GameTooltip.AppendInfo, GameTooltip, "GetTraitEntry", self.entryID, math.max(1, self.currentRank or 0))
            end
            if not appended and self.description and self.description ~= "" then GameTooltip:AddLine(self.description, 1, 1, 1, true) end
            GameTooltip:AddLine(string.format("Rank %d/%d", self.currentRank or 0, self.maxRank or 0), 0.35, 0.8, 1)
            GameTooltip:AddLine("Synchronized view — read only", 0.55, 0.55, 0.55)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        TalentUI.nodeButtons[index] = button
    end
    button:SetParent(parent)
    button:ClearAllPoints()
    return button
end

local function getEdge(index)
    local edge = TalentUI.edgeTextures[index]
    if not edge then
        edge = TalentUI.frame:CreateTexture(nil, "BACKGROUND")
        edge:SetTexture("Interface\\Buttons\\WHITE8X8")
        TalentUI.edgeTextures[index] = edge
    end
    edge:ClearAllPoints()
    return edge
end

local function getArrow(index)
    local arrow = TalentUI.arrowTextures[index]
    if not arrow then
        arrow = TalentUI.frame:CreateTexture(nil, "BACKGROUND", nil, 2)
        arrow:SetTexture("Interface\\TalentFrame\\UI-TalentArrows")
        arrow:SetTexCoord(0, 0.5, 0, 0.5)
        TalentUI.arrowTextures[index] = arrow
    end
    arrow:ClearAllPoints()
    return arrow
end

local function hideDynamic()
    for _, button in ipairs(TalentUI.nodeButtons) do button:Hide() end
    for _, edge in ipairs(TalentUI.edgeTextures) do edge:Hide() end
    for _, arrow in ipairs(TalentUI.arrowTextures) do arrow:Hide() end
    for _, panel in ipairs(TalentUI.panels) do panel:Hide() end
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
    local description = definition.overrideDescription or (spellID and C_Spell and C_Spell.GetSpellDescription and C_Spell.GetSpellDescription(spellID))
    return entryID, entryInfo, spellID, name, icon, description
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

local function setTreeBackground(panel, profile, group)
    local classBackgrounds = BACKGROUND_NAMES[profile.classToken or ""] or {}
    local fileName = classBackgrounds[normalizedName(group.displayName)]
    if not fileName then
        local className = (profile.classToken or "Mage"):lower():gsub("^%l", string.upper)
        fileName = className .. tostring(group.displayName or "Fire"):gsub("[^%a]", "")
    end
    local base = "Interface\\TalentFrame\\" .. fileName .. "-"
    panel.backgroundPieces[1]:SetTexture(base .. "TopLeft")
    panel.backgroundPieces[2]:SetTexture(base .. "TopRight")
    panel.backgroundPieces[3]:SetTexture(base .. "BottomLeft")
    panel.backgroundPieces[4]:SetTexture(base .. "BottomRight")
end

function TalentUI:ShowProfile(profile)
    if not self.frame then createBrowser() end
    hideDynamic()
    self.frame.status:Hide()
    self.frame.TitleText:SetText("Talents — " .. (ns.ProfileChoiceLabel and ns.ProfileChoiceLabel(profile) or profile.name or "Character"))
    self.frame.subtitle:SetText(profile.specName or "")
    self.frame:Show()

    local configID, treeID = prepareView(profile)
    if not configID or not treeID then
        self.frame.status:SetText("Talent layout is not available yet. Ask this player to update and synchronize again.")
        self.frame.status:Show()
        return
    end

    local groupsOK, groups = pcall(C_Traits.GetGroupDisplayInfoByTreeID, treeID)
    local nodesOK, nodeIDs = pcall(C_Traits.GetTreeNodes, treeID)
    if not groupsOK or not nodesOK or type(groups) ~= "table" or type(nodeIDs) ~= "table" then
        self.frame.status:SetText("The Forever client did not return the talent-tree layout.")
        self.frame.status:Show()
        return
    end
    table.sort(groups, function(a, b) return (a.orderIndex or 0) < (b.orderIndex or 0) end)

    local layouts, nodeByID = {}, {}
    for index, group in ipairs(groups) do
        if index <= 3 then
            local panel = self.panels[index]
            setTreeBackground(panel, profile, group)
            panel.icon:SetTexture(group.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            panel.title:SetText(string.format("%s  —  %d", tostring(group.displayName or "Tree"), pointForGroup(profile, group.groupID)))
            panel:Show()
            layouts[group.groupID] = { panel = panel, nodes = {}, minX = math.huge, maxX = -math.huge, minY = math.huge, maxY = -math.huge }
        end
    end

    for _, nodeID in ipairs(nodeIDs) do
        local nodeOK, nodeInfo = pcall(C_Traits.GetNodeInfo, configID, nodeID)
        if nodeOK and nodeInfo and nodeInfo.isVisible ~= false and nodeInfo.entryIDs and #nodeInfo.entryIDs > 0
            and type(nodeInfo.posX) == "number" and type(nodeInfo.posY) == "number" then
            for _, groupID in ipairs(nodeInfo.groupIDs or {}) do
                local layout = layouts[groupID]
                if layout then
                    layout.nodes[#layout.nodes + 1] = nodeInfo
                    layout.minX = math.min(layout.minX, nodeInfo.posX or 0); layout.maxX = math.max(layout.maxX, nodeInfo.posX or 0)
                    layout.minY = math.min(layout.minY, nodeInfo.posY or 0); layout.maxY = math.max(layout.maxY, nodeInfo.posY or 0)
                    nodeByID[nodeID] = { info = nodeInfo, layout = layout }
                    break
                end
            end
        end
    end

    -- Hidden/alternate trait nodes may occupy the same grid cell. Render one
    -- talent per cell, preferring the selected node over an inactive alternate.
    for _, layout in pairs(layouts) do
        local cells, visible = {}, {}
        for _, node in ipairs(layout.nodes) do
            local key = tostring(node.posX) .. ":" .. tostring(node.posY)
            local previous = cells[key]
            local selected = profile.talents.nodes and profile.talents.nodes[node.ID]
            if not previous or selected and (selected.rank or 0) > 0 then cells[key] = node end
        end
        layout.minX, layout.maxX, layout.minY, layout.maxY = math.huge, -math.huge, math.huge, -math.huge
        for _, node in pairs(cells) do
            visible[#visible + 1] = node
            layout.minX = math.min(layout.minX, node.posX); layout.maxX = math.max(layout.maxX, node.posX)
            layout.minY = math.min(layout.minY, node.posY); layout.maxY = math.max(layout.maxY, node.posY)
        end
        layout.nodes = visible
    end
    local buttonIndex, positions = 0, {}
    for _, layout in pairs(layouts) do
        local width = math.max(1, layout.maxX - layout.minX)
        local height = math.max(1, layout.maxY - layout.minY)
        for _, nodeInfo in ipairs(layout.nodes) do
            buttonIndex = buttonIndex + 1
            local x = 28 + (((nodeInfo.posX or 0) - layout.minX) / width) * 238
            local y = -66 - (((nodeInfo.posY or 0) - layout.minY) / height) * 420
            positions[nodeInfo.ID] = { x = x + 19, y = y - 19, panel = layout.panel }
            local selected = profile.talents.nodes and profile.talents.nodes[nodeInfo.ID]
            local entryID, entryInfo, spellID, name, icon, description = talentDefinition(configID, nodeInfo, selected)
            local learned = selected and (selected.rank or 0) > 0
            local button = getNodeButton(buttonIndex, layout.panel)
            button:SetPoint("TOPLEFT", x, y)
            button.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            button.icon:SetDesaturated(not learned)
            button:SetBackdropColor(learned and 0.28 or 0.05, learned and 0.2 or 0.05, 0.02, 1)
            button:SetBackdropBorderColor(learned and 1 or 0.35, learned and 0.82 or 0.35, learned and 0 or 0.35, 1)
            local rank = selected and selected.rank or 0
            local maxRank = entryInfo and entryInfo.maxRanks or nodeInfo.maxRanks or 1
            button.rank:SetText(string.format("%d/%d", rank, maxRank))
            button.rank:SetTextColor(learned and 0.2 or 0.65, learned and 1 or 0.65, learned and 0.2 or 0.65)
            button.entryID = entryID; button.spellID = spellID; button.talentName = name
            button.currentRank = rank; button.maxRank = maxRank; button.description = description
            button:Show()
        end
    end

    local edgeIndex = 0
    for nodeID, data in pairs(nodeByID) do
        local from = positions[nodeID]
        for _, edgeInfo in ipairs(data.info.visibleEdges or {}) do
            local to = positions[edgeInfo.targetNode]
            if from and to and from.panel == to.panel then
                edgeIndex = edgeIndex + 1
                local dx, dy = to.x - from.x, to.y - from.y
                local length = math.max(1, math.sqrt((dx * dx) + (dy * dy)))
                local edge = getEdge(edgeIndex)
                edge:SetParent(from.panel)
                edge:SetSize(math.max(1, length - 32), 3)
                edge:SetPoint("CENTER", from.panel, "TOPLEFT", (from.x + to.x) / 2, (from.y + to.y) / 2)
                if edge.SetRotation then edge:SetRotation(angleFor(dx, dy)) end
                local active = profile.talents.nodes[nodeID] and profile.talents.nodes[edgeInfo.targetNode]
                edge:SetVertexColor(active and 0.1 or 0.32, active and 1 or 0.32, active and 0.1 or 0.32, active and 0.95 or 0.7)
                edge:Show()

                local arrow = getArrow(edgeIndex)
                arrow:SetParent(from.panel)
                arrow:SetSize(18, 18)
                arrow:SetPoint("CENTER", from.panel, "TOPLEFT", to.x - (dx / length) * 23, to.y - (dy / length) * 23)
                if arrow.SetRotation then arrow:SetRotation(angleFor(dx, dy) - (math.pi / 2)) end
                arrow:SetVertexColor(active and 0.1 or 0.42, active and 1 or 0.42, active and 0.1 or 0.42, 1)
                arrow:Show()
            end
        end
    end
end

function ns:OpenTalentBrowser(profileKey)
    local profile = self.db and self.db.players and self.db.players[profileKey]
    if profile and self:IsVisibleCharacter(profileKey) then TalentUI:ShowProfile(profile) end
end
