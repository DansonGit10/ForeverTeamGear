local _, ns = ...

local Scanner = {}
table.insert(ns.modules, Scanner)

local function itemID(link)
    return link and tonumber(link:match("item:(%d+)"))
end

local function itemLevel(link)
    if not link then return 0 end
    if C_Item and C_Item.GetDetailedItemLevelInfo then
        return C_Item.GetDetailedItemLevelInfo(link) or 0
    end
    if GetDetailedItemLevelInfo then return GetDetailedItemLevelInfo(link) or 0 end
    return select(4, GetItemInfo(link)) or 0
end

local function foreverSpecID(classID)
    if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo then
        local ok, specID = pcall(C_SpecializationInfo.GetSpecializationInfo, 1, false, false, nil, nil, nil, classID)
        if ok and specID and specID > 0 then return specID end
    end
    if GetSpecializationInfoForClassID then
        local ok, specID = pcall(GetSpecializationInfoForClassID, classID, 1)
        if ok and specID and specID > 0 then return specID end
    end
    return 0
end

local function currentSpec(classID)
    if C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetConfigInfo then
        local configOK, configID = pcall(C_ClassTalents.GetActiveConfigID)
        if configOK and configID then
            local infoOK, configInfo = pcall(C_Traits.GetConfigInfo, configID)
            local treeID = infoOK and configInfo and configInfo.treeIDs and configInfo.treeIDs[1]
            if treeID and C_Traits.GetGroupDisplayInfoByTreeID and C_Traits.GetGroupCurrencyInfo then
                local displayOK, displays = pcall(C_Traits.GetGroupDisplayInfoByTreeID, treeID)
                if displayOK and type(displays) == "table" and #displays > 0 then
                    table.sort(displays, function(a, b) return (a.orderIndex or 0) < (b.orderIndex or 0) end)
                    local groupIDs = {}
                    for _, display in ipairs(displays) do groupIDs[#groupIDs + 1] = display.groupID end
                    local currencyOK, groupCurrencies = pcall(C_Traits.GetGroupCurrencyInfo, configID, groupIDs)
                    local pointsByGroup = {}
                    if currencyOK and type(groupCurrencies) == "table" then
                        for _, groupCurrency in ipairs(groupCurrencies or {}) do
                            local points = 0
                            for _, currency in ipairs(groupCurrency.currencyInfos or {}) do
                                points = points + (currency.spentInTree or currency.spent or 0)
                            end
                            pointsByGroup[groupCurrency.traitNodeGroupID] = points
                        end
                        local talentData = { treeID = treeID, specID = foreverSpecID(classID), groups = {}, nodes = {} }
                        local parts = {}
                        for _, display in ipairs(displays) do
                            local points = pointsByGroup[display.groupID] or 0
                            local name = tostring(display.displayName or "Tree")
                            parts[#parts + 1] = string.format("%s %d", name, points)
                            talentData.groups[#talentData.groups + 1] = {
                                id = display.groupID, name = name, icon = display.icon or 0,
                                order = display.orderIndex or #talentData.groups + 1, points = points,
                            }
                        end
                        if C_Traits.GetTreeNodes and C_Traits.GetNodeInfo then
                            local nodesOK, nodeIDs = pcall(C_Traits.GetTreeNodes, treeID)
                            if nodesOK then
                                for _, nodeID in ipairs(nodeIDs or {}) do
                                    local nodeOK, nodeInfo = pcall(C_Traits.GetNodeInfo, configID, nodeID)
                                    local rank = nodeOK and nodeInfo and (nodeInfo.currentRank or nodeInfo.activeRank or 0) or 0
                                    if rank > 0 then
                                        talentData.nodes[nodeID] = {
                                            rank = rank,
                                            entryID = nodeInfo.activeEntry and nodeInfo.activeEntry.entryID or 0,
                                        }
                                    end
                                end
                            end
                        end
                        if #parts > 0 then return talentData.specID, table.concat(parts, " / "), talentData end
                    end
                end
            end
        end
    end
    if not GetSpecialization or not GetSpecializationInfo then return 0, "" end
    local index = GetSpecialization()
    if not index then return 0, "" end
    local id, name = GetSpecializationInfo(index)
    return id or 0, name or "", nil
end

local function scanGear()
    local gear = {}
    for slot = 1, 19 do
        local link = GetInventoryItemLink("player", slot)
        if link then gear[slot] = { id = itemID(link) or 0, link = link, ilvl = itemLevel(link) } end
    end
    return gear
end

local function addContainerItems(result, bag)
    if not C_Container or not C_Container.GetContainerNumSlots then return end
    local slots = C_Container.GetContainerNumSlots(bag) or 0
    for slot = 1, slots do
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info and info.itemID then
            local link = info.hyperlink or (C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bag, slot))
            local key = link and link:match("(item:[^|]+)") or info.itemID
            result[key] = (result[key] or 0) + (info.stackCount or 1)
        end
    end
end

local function scanBags()
    local result = {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do addContainerItems(result, bag) end
    return result
end

local function scanBank()
    local result = {}
    local mainBank = Enum and Enum.BagIndex and Enum.BagIndex.Bank or -1
    addContainerItems(result, mainBank)
    local firstBankBag = (NUM_BAG_SLOTS or 4) + 1
    for bag = firstBankBag, firstBankBag + (NUM_BANKBAGSLOTS or 7) - 1 do addContainerItems(result, bag) end
    local reagentBank = Enum and Enum.BagIndex and Enum.BagIndex.Reagentbank
    if reagentBank then addContainerItems(result, reagentBank) end
    return result
end

local function scanProfessions(existing)
    local result = existing or {}
    if not GetProfessions or not GetProfessionInfo then return result end
    local found = {}
    local professionIndexes = {}
    for _, index in pairs({ GetProfessions() }) do
        if index then professionIndexes[#professionIndexes + 1] = index end
    end
    for _, index in ipairs(professionIndexes) do
        if index then
            local name, icon, rank, maxRank = GetProfessionInfo(index)
            if name then
                found[name] = true
                local old = result[name] or {}
                result[name] = { rank = rank or 0, maxRank = maxRank or 0, icon = icon or old.icon, recipes = old.recipes or {} }
            end
        end
    end
    -- The client can return an empty profession list while loading.
    -- Keep saved recipes until an authoritative nonempty list is available.
    if next(found) then
        for name in pairs(result) do if not found[name] then result[name] = nil end end
    end
    return result
end

local function apiList(callback, ...)
    if not callback then return {} end
    local values = { pcall(callback, ...) }
    local ok = table.remove(values, 1)
    if not ok then return {} end
    if #values == 1 and type(values[1]) == "table" then return values[1] end
    return values
end

local function categoryNames()
    local names, visited = {}, {}
    if not C_TradeSkillUI or not C_TradeSkillUI.GetCategories then return names end

    local function visit(categoryID)
        if not categoryID or visited[categoryID] then return end
        visited[categoryID] = true
        if C_TradeSkillUI.GetCategoryInfo then
            local ok, info = pcall(C_TradeSkillUI.GetCategoryInfo, categoryID)
            if ok and info and info.name and info.name ~= "" then names[categoryID] = info.name end
        end
        if C_TradeSkillUI.GetSubCategories then
            for _, childID in ipairs(apiList(C_TradeSkillUI.GetSubCategories, categoryID)) do visit(childID) end
        end
    end

    for _, categoryID in ipairs(apiList(C_TradeSkillUI.GetCategories)) do visit(categoryID) end
    return names
end

local function fallbackCategory(outputItemID)
    if not outputItemID or outputItemID == 0 then return "Services & Enchants" end
    local getItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
    if not getItemInfo then return "Other" end
    local _, _, _, _, _, itemType, itemSubType = getItemInfo(outputItemID)
    if itemType and itemType ~= "" then
        if (itemType == "Weapon" or itemType == "Armor") and itemSubType and itemSubType ~= "" then
            return itemType .. " - " .. itemSubType
        end
        return itemType
    end
    return "Other"
end

function ns:ScanProfile()
    local key = self:PlayerKey()
    self.db.ownCharacters[key] = true
    local profile = self.db.players[key] or {}
    local className, classToken, classID = UnitClass("player")
    local specID, specName, talents = currentSpec(classID)
    profile.key = key
    local fullName = self:UnitIdentity("player")
    profile.name = fullName or UnitName("player") or key
    profile.realm = nil
    profile.className = className or ""
    profile.classToken = classToken or ""
    profile.classID = classID or 0
    profile.level = UnitLevel("player") or 0
    profile.specID = specID
    profile.specName = specName
    profile.talents = talents or profile.talents
    profile.gear = scanGear()
    profile.inventory = profile.inventory or { bank = {} }
    profile.inventory.bags = scanBags()
    if BankFrame and BankFrame:IsShown() then
        profile.inventory.bank = scanBank()
        profile.inventory.bankUpdated = self:Now()
    end
    profile.professions = scanProfessions(profile.professions)
    profile.updated = self:Now()
    profile.addonVersion = self.version
    self.db.players[key] = profile
    return profile
end

function ns:ScanRecipes(suppressBroadcast)
    if not C_TradeSkillUI or not C_TradeSkillUI.GetAllRecipeIDs then return false end
    if C_TradeSkillUI.IsTradeSkillReady then
        local ok, ready = pcall(C_TradeSkillUI.IsTradeSkillReady)
        if not ok or not ready then return false end
    end
    local baseOK, base = pcall(function() return C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo() end)
    if not baseOK then return false end
    local professionName = base and base.professionName
    if not professionName or professionName == "" then return false end
    local profile = self:ScanProfile()
    local categories = categoryNames()
    local profession = profile.professions[professionName] or { rank = base.skillLevel or 0, maxRank = base.maxSkillLevel or 0 }
    local idsOK, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
    if not idsOK or type(ids) ~= "table" or #ids == 0 then return false end
    local recipes = {}
    for _, recipeID in ipairs(ids) do
        local infoOK, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
        if not infoOK or not info then return false end
        if info.learned or info.isLearned then
            local categoryName = info.categoryID and categories[info.categoryID]
            if not categoryName and info.categoryID and C_TradeSkillUI.GetCategoryInfo then
                local categoryOK, categoryInfo = pcall(C_TradeSkillUI.GetCategoryInfo, info.categoryID)
                if categoryOK and categoryInfo and categoryInfo.name then categoryName = categoryInfo.name end
            end
            local recipe = {
                id = recipeID,
                name = info.name,
                icon = info.icon,
                categoryID = info.categoryID or 0,
                category = categoryName or "Other",
                requiredLevel = 0,
                reagents = {},
            }
            if C_TradeSkillUI.GetRecipeSchematic then
                local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
                if ok and schematic then
                    recipe.outputItemID = schematic.outputItemID
                    recipe.quantityMin = schematic.quantityMin or 1
                    recipe.quantityMax = schematic.quantityMax or recipe.quantityMin
                    recipe.icon = schematic.icon or recipe.icon
                    if recipe.outputItemID and C_Item and C_Item.GetItemInfo then
                        recipe.requiredLevel = select(5, C_Item.GetItemInfo(recipe.outputItemID)) or 0
                        Scanner.requestedRecipeItems = Scanner.requestedRecipeItems or {}
                        if recipe.requiredLevel == 0 and C_Item.RequestLoadItemDataByID and not Scanner.requestedRecipeItems[recipe.outputItemID] then
                            Scanner.requestedRecipeItems[recipe.outputItemID] = true
                            C_Item.RequestLoadItemDataByID(recipe.outputItemID)
                        end
                    end
                    for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
                        local reagent = slot.reagents and slot.reagents[1]
                        if reagent and reagent.itemID and (slot.required == nil or slot.required) then
                            recipe.reagents[#recipe.reagents + 1] = {
                                id = reagent.itemID,
                                count = slot.quantityRequired or 1,
                            }
                        end
                    end
                end
            end
            if not categoryName or categoryName == "" then recipe.category = fallbackCategory(recipe.outputItemID) end
            recipes[#recipes + 1] = recipe
        end
    end
    if #recipes == 0 then return false end
    profession.recipes = recipes
    profession.icon = base.professionIcon or base.icon or profession.icon
    table.sort(profession.recipes, function(a, b) return (a.name or "") < (b.name or "") end)
    profile.professions[professionName] = profession
    profile.updated = self:Now()
    if not suppressBroadcast then self:BroadcastProfile() end
    self:RefreshWindow()
    return true
end

function ns:ScanAll()
    if not self.db then return end
    self:ScanProfile()
    self:RefreshWindow()
end

function ns:ScanBankInventory()
    if not self.db then return end
    local profile = self:ScanProfile()
    profile.inventory = profile.inventory or {}
    profile.inventory.bank = scanBank()
    profile.inventory.bankUpdated = self:Now()
    profile.updated = self:Now()
    self:BroadcastProfile()
    self:RefreshWindow()
end

local function serializeInventory(items)
    local encoded = {}
    for id, count in pairs(items or {}) do encoded[#encoded + 1] = tostring(id) .. ":" .. tostring(count or 1) end
    table.sort(encoded)
    return table.concat(encoded, ",")
end

local function deserializeInventory(value, split)
    local result = {}
    for _, encoded in ipairs(split(value or "", ",")) do
        local key, count = encoded:match("^(.*):(%d+)$")
        local id = tonumber(key)
        if id and id > 0 then result[id] = tonumber(count) or 1
        elseif key and key:match("^item:%d+:[%d:%-]*$") then result[key] = tonumber(count) or 1 end
    end
    return result
end

local function serializeProfile(profile)
    local gear, professions = {}, {}
    for slot, item in pairs(profile.gear or {}) do
        gear[#gear + 1] = table.concat({ slot, item.id or 0, item.ilvl or 0, item.link or "" }, "~")
    end
    table.sort(gear)
    for name, profession in pairs(profile.professions or {}) do
        local recipes = {}
        for _, stored in ipairs(profession.recipes or {}) do
            local recipe = type(stored) == "table" and stored or { id = stored }
            local reagents = {}
            for _, reagent in ipairs(recipe.reagents or {}) do
                reagents[#reagents + 1] = tostring(reagent.id or 0) .. ":" .. tostring(reagent.count or 1)
            end
            recipes[#recipes + 1] = table.concat({
                recipe.id or 0,
                recipe.outputItemID or 0,
                recipe.quantityMin or 1,
                recipe.quantityMax or recipe.quantityMin or 1,
                recipe.requiredLevel or 0,
                recipe.categoryID or 0,
                tostring(recipe.category or "Other"):gsub("[%^;~]", " "),
                table.concat(reagents, ","),
                tostring(recipe.name or ""):gsub("[%^;~\n\t]", " "),
                recipe.icon or 0,
            }, "^")
        end
        professions[#professions + 1] = table.concat({ name, profession.rank or 0, profession.maxRank or 0, profession.icon or 0, table.concat(recipes, ";") }, "~")
    end
    table.sort(professions)
    local talentGroups, talentNodes = {}, {}
    for _, group in ipairs(profile.talents and profile.talents.groups or {}) do
        talentGroups[#talentGroups + 1] = table.concat({
            group.id or 0,
            tostring(group.name or "Tree"):gsub("[%^;~]", " "),
            group.icon or 0,
            group.order or 0,
            group.points or 0,
        }, "^")
    end
    for nodeID, node in pairs(profile.talents and profile.talents.nodes or {}) do
        talentNodes[#talentNodes + 1] = table.concat({ nodeID, node.entryID or 0, node.rank or 0 }, "^")
    end
    table.sort(talentNodes)
    local talents = profile.talents and table.concat({
        profile.talents.treeID or 0,
        profile.talents.specID or profile.specID or 0,
        table.concat(talentGroups, ";"),
        table.concat(talentNodes, ";"),
    }, "~") or ""
    return {
        profile.key, profile.name, "", profile.classToken, profile.level,
        profile.specID, profile.specName, profile.updated, table.concat(gear, "\n"),
        table.concat(professions, "\n"), ns.version, talents,
        serializeInventory(profile.inventory and profile.inventory.bags),
        serializeInventory(profile.inventory and profile.inventory.bank),
        profile.inventory and profile.inventory.bankUpdated or 0,
    }
end

function ns:SendProfile(channel, target, options)
    if not channel or (channel ~= "PRIVATE" and channel ~= "ALL" and not self:CanCommunicate(channel, target)) then return end
    if channel == "ALL" and not (self:Mode() == "group" and self:UsesGuild()) then return end
    if channel == "PRIVATE" and self:Mode() ~= "group" then return end
    local profile = self:ScanProfile()
    local values = serializeProfile(profile)
    values[22], values[23] = self:PlayerIdentity()
    if not self:CanShare("gear") then values[9] = "" end
    if not self:CanShare("talents") then values[6], values[7], values[12] = 0, "", "" end
    if not self:CanShare("professions") then values[10] = "" end
    if not self:CanShare("bags") then values[13] = "" end
    if not self:CanShare("bank") then values[14], values[15] = "", 0 end
    values[16] = (self:CanShare("gear") and "1" or "0") .. (self:CanShare("bags") and "1" or "0") .. (self:CanShare("bank") and "1" or "0")
    self:SendEncoded("P", values, channel, target, options)
end

function ns:RefreshReceivedProfiles()
    if self.receivedRefreshPending then return end
    self.receivedRefreshPending = true
    C_Timer.After(0.25, function()
        self.receivedRefreshPending = false
        self:RefreshWindow()
    end)
end

function ns:AcceptProfile(payload, sender, unescape, split, privateCode)
    local raw = split(payload, "\t")
    for index, value in ipairs(raw) do raw[index] = unescape(value) end
    local key = raw[1]
    if #raw < 12 then
        self:Print(string.format("Sync rejected: incomplete profile from %s (%d fields; expected at least 12).", tostring(sender), #raw))
        return
    end
    if not key or key == "" or not self:SameCharacter(key, sender) then
        -- Compatibility with profiles produced before the surname API fix.
        local first, surname = (key or ""):match("^([^%s%-]+)%-([^%s%-]+)$")
        local legacyName = first and surname and (first .. " " .. surname)
        if legacyName and raw[2] == first and self:SameCharacter(legacyName, sender) then
            key, raw[2] = self:NormalizeSender(self:WhisperTarget(sender)), legacyName
        else
            self:Print(string.format("Sync rejected: profile key '%s', name '%s', sender '%s'.", tostring(key), tostring(raw[2]), tostring(sender)))
            return
        end
    end
    key = self:NormalizeSender(sender)
    if self:IsOwnCharacter(key) and not self:SameCharacter(sender, self:PlayerKey()) then
        self:Print("Sync rejected: another player cannot replace a locally owned character.")
        return
    end
    local section = raw[17]
    if section == "" then section = nil end
    if section and not ({ I = true, E = true, T = true, R = true, B = true, K = true, Z = true })[section] then return end
    local previous = self.db.players[key]
    if section and section ~= "Z" and previous and tonumber(raw[20]) and tonumber(raw[20]) < ((previous.syncVersions or {})[section] or 0) then return end
    local profile = {
        key = key, name = raw[2], classToken = raw[4],
        level = tonumber(raw[5]) or 0, specID = tonumber(raw[6]) or 0,
        specName = raw[7], updated = tonumber(raw[8]) or self:Now(),
        playerID = raw[22] ~= "" and raw[22] or nil, playerName = raw[23] ~= "" and raw[23] or nil,
        addonVersion = raw[11], gear = {}, professions = {}, sender = sender,
        privateGroup = privateCode or (self.db.players[key] and self.db.players[key].privateGroup),
        guildSource = not privateCode or (self.db.players[key] and self.db.players[key].guildSource) or nil,
        sharing = raw[16] and { gear = raw[16]:sub(1, 1) == "1", bags = raw[16]:sub(2, 2) == "1", bank = raw[16]:sub(3, 3) == "1" } or nil,
        inventory = {
            bags = deserializeInventory(raw[13], split),
            bank = deserializeInventory(raw[14], split),
            bankUpdated = tonumber(raw[15]) or 0,
        },
    }
    local talentValues = split(raw[12] or "", "~")
    if tonumber(talentValues[1]) and tonumber(talentValues[1]) > 0 then
        profile.talents = { treeID = tonumber(talentValues[1]), specID = tonumber(talentValues[2]) or 0, groups = {}, nodes = {} }
        for _, encodedGroup in ipairs(split(talentValues[3] or "", ";")) do
            local fields = split(encodedGroup, "^")
            if tonumber(fields[1]) then
                profile.talents.groups[#profile.talents.groups + 1] = {
                    id = tonumber(fields[1]), name = fields[2] or "Tree", icon = tonumber(fields[3]) or 0,
                    order = tonumber(fields[4]) or 0, points = tonumber(fields[5]) or 0,
                }
            end
        end
        for _, encodedNode in ipairs(split(talentValues[4] or "", ";")) do
            local fields = split(encodedNode, "^")
            local nodeID = tonumber(fields[1])
            if nodeID then profile.talents.nodes[nodeID] = { entryID = tonumber(fields[2]) or 0, rank = tonumber(fields[3]) or 0 } end
        end
    end
    for _, row in ipairs(split(raw[9] or "", "\n")) do
        local values = split(row, "~")
        local slot = tonumber(values[1])
        if slot then profile.gear[slot] = { id = tonumber(values[2]) or 0, ilvl = tonumber(values[3]) or 0, link = values[4] } end
    end
    for _, row in ipairs(split(raw[10] or "", "\n")) do
        local values = split(row, "~")
        if values[1] and values[1] ~= "" then
            local recipes = {}
            for _, encodedRecipe in ipairs(split(values[5] or "", ";")) do
                if encodedRecipe ~= "" then
                    if not encodedRecipe:find("^", 1, true) then
                        for legacyID in encodedRecipe:gmatch("%d+") do
                            recipes[#recipes + 1] = { id = tonumber(legacyID), reagents = {} }
                        end
                    else
                    local fields = split(encodedRecipe, "^")
                    local recipe = {
                        id = tonumber(fields[1]),
                        outputItemID = tonumber(fields[2]) or 0,
                        quantityMin = tonumber(fields[3]) or 1,
                        quantityMax = tonumber(fields[4]) or tonumber(fields[3]) or 1,
                        requiredLevel = tonumber(fields[5]) or 0,
                        categoryID = tonumber(fields[6]) or 0,
                        category = fields[7] ~= "" and fields[7] or "Other",
                        name = fields[9] and fields[9] ~= "" and fields[9] or nil,
                        icon = tonumber(fields[10]),
                        reagents = {},
                    }
                    for _, encodedReagent in ipairs(split(fields[8] or "", ",")) do
                        local reagentFields = split(encodedReagent, ":")
                        local reagentID = tonumber(reagentFields[1])
                        if reagentID and reagentID > 0 then
                            recipe.reagents[#recipe.reagents + 1] = { id = reagentID, count = tonumber(reagentFields[2]) or 1 }
                        end
                    end
                    if recipe.id then recipes[#recipes + 1] = recipe end
                    end
                end
            end
            profile.professions[values[1]] = {
                rank = tonumber(values[2]) or 0,
                maxRank = tonumber(values[3]) or 0,
                icon = tonumber(values[4]) or nil,
                recipes = recipes,
            }
        end
    end
    if section then
        previous = previous or {}
        if section ~= "E" then profile.gear = previous.gear or {} end
        if section ~= "T" then profile.specID, profile.specName, profile.talents = previous.specID or 0, previous.specName or "", previous.talents end
        if section ~= "R" then profile.professions = previous.professions or {} end
        local inventory = previous.inventory or {}
        if section ~= "B" then profile.inventory.bags = inventory.bags or {} end
        if section ~= "K" then profile.inventory.bank, profile.inventory.bankUpdated = inventory.bank or {}, inventory.bankUpdated or 0 end
        profile.syncSections = {}
        for id, stamp in pairs(previous.syncSections or {}) do profile.syncSections[id] = stamp end
        profile.syncVersions = {}
        for id, revision in pairs(previous.syncVersions or {}) do profile.syncVersions[id] = revision end
        if section ~= "Z" and raw[18] then profile.syncSections[section] = raw[18] end
        if section ~= "Z" and tonumber(raw[20]) then profile.syncVersions[section] = tonumber(raw[20]) end
        local identityRevision = tonumber(raw[21]) or 0
        if identityRevision < ((previous.syncVersions or {}).I or 0) then
            profile.playerID, profile.playerName = previous.playerID, previous.playerName
            profile.name, profile.realm, profile.classToken, profile.level, profile.sharing = previous.name, previous.realm, previous.classToken, previous.level, previous.sharing
        else profile.syncVersions.I = math.max(profile.syncVersions.I or 0, identityRevision) end
        profile.updated = math.max(profile.updated or 0, previous.updated or 0)
        -- Apply explicit redactions immediately, even before their section arrives.
        if profile.sharing then
            if not profile.sharing.gear then profile.gear = {} end
            if not profile.sharing.bags then profile.inventory.bags = {} end
            if not profile.sharing.bank then profile.inventory.bank, profile.inventory.bankUpdated = {}, 0 end
        end
    end
    local sharingChanged = previous and profile.sharing and (not previous.sharing or previous.sharing.bags ~= profile.sharing.bags or previous.sharing.bank ~= profile.sharing.bank)
    self.db.players[key] = profile
    self:RefreshReceivedProfiles()
    Scanner.receiptLog = Scanner.receiptLog or {}
    local now = GetTime()
    if (not section or section == "Z") and (section == "Z" or sharingChanged or not Scanner.receiptLog[key] or now - Scanner.receiptLog[key] >= 15) then
        Scanner.receiptLog[key] = now
        self:Print(string.format("Received data from %s (%s). Saved locally.", profile.name or key, privateCode and "Private group" or "Guild"))
        if profile.sharing then
            local function count(items) local total = 0; for _ in pairs(items or {}) do total = total + 1 end; return total end
            self:Print(string.format("Inventory from %s: bags %s; bank %s.", profile.name or key,
                profile.sharing.bags and (count(profile.inventory.bags) .. " item types") or "not shared",
                profile.sharing.bank and (count(profile.inventory.bank) .. " item types") or "not shared"))
        end
    end
end

function Scanner:Initialize()
    ns:On("PLAYER_ENTERING_WORLD", function()
        C_Timer.After(3, function() ns:ScanAll(); ns:RequestSync() end)
    end)
    ns:On("PLAYER_EQUIPMENT_CHANGED", function() C_Timer.After(0.5, function() ns:ScanAll(); ns:BroadcastProfile() end) end)
    ns:On("BAG_UPDATE_DELAYED", function()
        if Scanner.inventoryScanPending then return end
        Scanner.inventoryScanPending = true
        C_Timer.After(0.8, function()
            Scanner.inventoryScanPending = false
            ns:ScanAll()
            ns:BroadcastProfile(15)
        end)
    end)
    ns:On("BANKFRAME_OPENED", function() C_Timer.After(0.3, function() ns:ScanBankInventory() end) end)
    ns:On("PLAYERBANKSLOTS_CHANGED", function()
        if Scanner.bankScanPending then return end
        Scanner.bankScanPending = true
        C_Timer.After(0.8, function()
            Scanner.bankScanPending = false
            if BankFrame and BankFrame:IsShown() then ns:ScanBankInventory() end
        end)
    end)
    ns:On("SKILL_LINES_CHANGED", function() ns:ScanAll() end)
    local function queueRecipeScan(delay)
        if Scanner.recipeScanPending then return end
        Scanner.recipeScanPending = true
        local attempts = 0
        local function scan()
            attempts = attempts + 1
            if ns:ScanRecipes() or attempts >= 8 then Scanner.recipeScanPending = false; return end
            C_Timer.After(0.5, scan)
        end
        C_Timer.After(delay, scan)
    end
    ns:On("TRADE_SKILL_SHOW", function() queueRecipeScan(0.5) end)
    ns:On("TRADE_SKILL_LIST_UPDATE", function() queueRecipeScan(0.2) end)
    ns:On("ITEM_DATA_LOAD_RESULT", function()
        if C_TradeSkillUI and C_TradeSkillUI.IsTradeSkillReady and C_TradeSkillUI.IsTradeSkillReady() then queueRecipeScan(0.5) end
    end)
    local function queueTalentSync()
        if Scanner.talentSyncPending then return end
        Scanner.talentSyncPending = true
        C_Timer.After(0.5, function()
            Scanner.talentSyncPending = false
            ns:ScanAll()
            ns:BroadcastProfile()
        end)
    end
    ns:On("TRAIT_CONFIG_UPDATED", queueTalentSync)
    ns:On("TRAIT_TREE_CURRENCY_INFO_UPDATED", queueTalentSync)
end
