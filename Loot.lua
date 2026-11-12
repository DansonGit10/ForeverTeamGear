local _, ns = ...

local Loot = { counts = {}, pending = {}, notified = {}, materialNotified = {} }
table.insert(ns.modules, Loot)

function ns:AllowsAutomaticAlert(quality)
    local settings = self.db and self.db.settings or {}
    local minimum = settings.alertMinQuality
    if minimum == nil then minimum = settings.alertsEnabled == true and 0 or -1 end
    return minimum >= 0 and tonumber(quality) ~= nil and tonumber(quality) >= minimum
end

local EQUIP_SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 },
    INVTYPE_BODY = { 4 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
    INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
    INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
    INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 },
}

function ns:LootVariantKey(reference)
    local value = tostring(reference)
    local item = value:match("(item:[^|]+)")
    if not item then return "item:" .. tostring(tonumber(reference) or 0) end
    local fields = {}
    for field in (item .. ":"):gmatch("(.-):") do fields[#fields + 1] = field end
    -- Link level and specialization describe the viewer, not the dropped item.
    for index = 1, math.max(11, #fields) do fields[index] = fields[index] ~= "" and fields[index] or "0" end
    fields[10], fields[11] = "0", "0"
    while #fields > 9 and fields[#fields] == "0" do table.remove(fields) end
    return table.concat(fields, ":")
end

local function noticeKey(record)
    local owner = ns.NormalizeSender and ns:NormalizeSender(record.looter or "?") or record.looter or "?"
    return table.concat({tostring(record.id or 0), owner, tostring(record.at or 0), ns:LootVariantKey(record.link or record.id)}, "|")
end

function ns:DismissBoeAlert(record)
    if not record or record.isTest then return end
    self.db.dismissedBoeAlerts = self.db.dismissedBoeAlerts or {}
    self.db.dismissedBoeAlerts[noticeKey(record)] = self:Now()
end

local function allBagCounts()
    local counts, links = {}, {}
    local lastBag = NUM_BAG_SLOTS or 4
    for bag = 0, lastBag do
        local slots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, slots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local link = info.hyperlink or (C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bag, slot))
                local key = ns:LootVariantKey(link or info.itemID)
                if link then links[key] = link end
                counts[key] = (counts[key] or 0) + (info.stackCount or 1)
            end
        end
    end
    return counts, links
end

local function getItemInfo(id)
    local fn = C_Item and C_Item.GetItemInfo or GetItemInfo
    if not fn then return end
    local name, link, quality, level, minLevel, _, _, _, equipLoc, icon, _, classID, subclassID, bindType = fn(id)
    return name, link, quality, level, minLevel, equipLoc, icon, classID, subclassID, bindType
end

local function detailedLevel(link, fallback)
    if C_Item and C_Item.GetDetailedItemLevelInfo then return C_Item.GetDetailedItemLevelInfo(link) or fallback or 0 end
    return fallback or 0
end

local function recipeWatchKey(profileKey, professionName, recipeID)
    return table.concat({ tostring(profileKey or ""), tostring(professionName or ""), tostring(recipeID or 0) }, "|")
end

function ns:IsRecipeWanted(profileKey, professionName, recipeID)
    local wanted = self.db and self.db.settings and self.db.settings.wantedRecipes
    return wanted and wanted[recipeWatchKey(profileKey, professionName, recipeID)] == true
end

function ns:SetRecipeWanted(profileKey, professionName, recipeID, enabled)
    if not self.db or not self.db.settings then return end
    self.db.settings.wantedRecipes = self.db.settings.wantedRecipes or {}
    local key = recipeWatchKey(profileKey, professionName, recipeID)
    self.db.settings.wantedRecipes[key] = enabled and true or nil
end

function Loot:AnnounceWantedMaterial(itemID, quantity)
    if not ns.db or not ns.db.settings or not ns:AllowsAutomaticAlert(select(3, getItemInfo(itemID))) or not ns.db.settings.wantedRecipes then return end
    local now = GetTime and GetTime() or 0
    local matches = {}
    for profileKey, profile in pairs(ns.db.players or {}) do
        local isAlt = ns.db.settings.alts and ns.db.settings.alts[profileKey]
        if not isAlt and ns:IsActiveTeamCharacter(profileKey) then
            for professionName, profession in pairs(profile.professions or {}) do
                for _, recipe in ipairs(profession.recipes or {}) do
                    if type(recipe) == "table" and ns:IsRecipeWanted(profileKey, professionName, recipe.id) then
                        for _, reagent in ipairs(recipe.reagents or {}) do
                            if reagent.id == itemID then
                                local outputName = recipe.outputItemID and getItemInfo(recipe.outputItemID)
                                matches[#matches + 1] = string.format("%s for %s (%s)", outputName or ("Recipe #" .. tostring(recipe.id)), profile.name or profileKey, professionName)
                                break
                            end
                        end
                    end
                end
            end
        end
    end
    if #matches == 0 then return end
    local dedupeKey = tostring(itemID) .. ":" .. table.concat(matches, ",")
    if self.materialNotified[dedupeKey] and now - self.materialNotified[dedupeKey] < 3 then return end
    self.materialNotified[dedupeKey] = now
    local itemName, itemLink = getItemInfo(itemID)
    local message = string.format("Keep %s x%d — needed for %s", itemLink or itemName or ("item #" .. itemID), quantity or 1, table.concat(matches, ", "))
    ns:Print(message)
    if UIErrorsFrame then UIErrorsFrame:AddMessage(message, 0.35, 1, 0.35, 1) end
end

local function scheduleUpgradeNotice(record)
    if not C_Timer or not C_Timer.After then
        if ns.AnnounceBoeUpgrades then ns:AnnounceBoeUpgrades(record) end
        return
    end
    C_Timer.After(2.5, function()
        if ns.AnnounceBoeUpgrades then ns:AnnounceBoeUpgrades(record) end
    end)
end

function Loot:Consider(reference, quantity)
    local id = tonumber(reference) or tonumber(tostring(reference):match("item:(%d+)"))
    if not id then return end
    local name, link, quality, level, minLevel, equipLoc, icon, classID, subclassID, bindType = getItemInfo(reference)
    if type(reference) == "string" and reference:find("|Hitem:", 1, true) then
        link = reference; name = reference:match("%[(.-)%]") or name
    end
    if not name or not bindType then
        self.pending[reference] = (self.pending[reference] or 0) + quantity
        if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
        return
    end
    local onEquip = Enum and Enum.ItemBind and Enum.ItemBind.OnEquip or 2
    if bindType ~= onEquip or not EQUIP_SLOTS[equipLoc] then return end
    local record = {
        id = id, link = link, name = name, quality = quality or 1,
        ilvl = detailedLevel(link, level), equipLoc = equipLoc, icon = icon,
        classID = classID, subclassID = subclassID, minLevel = minLevel or 0, quantity = quantity,
        looter = ns:PlayerKey(), at = ns:Now(),
    }
    table.insert(ns.db.boe, 1, record)
    while #ns.db.boe > 100 do table.remove(ns.db.boe) end
    ns:BroadcastBoe({ record.id, record.link, record.name, record.quality, record.ilvl, record.equipLoc, record.icon, record.quantity, record.looter, record.at, record.classID, record.subclassID, record.minLevel })
    ns:BroadcastProfile()
    ns:RequestSync()
    ns:Print("BoE: " .. (link or name) .. " — added for comparison.")
    scheduleUpgradeNotice(record)
    ns:RefreshWindow()
end

function Loot:Scan()
    local fresh, links = allBagCounts()
    for id, count in pairs(fresh) do
        local increase = count - (self.counts[id] or 0)
        if increase > 0 then
            self:AnnounceWantedMaterial(tonumber(id) or tonumber(tostring(id):match("item:(%d+)")), increase)
            if links[id] then self:Consider(links[id], increase) end
        end
    end
    self.counts = fresh
end

function ns:PruneBoe()
    local cutoff = self:Now() - 48 * 60 * 60
    local changed = false
    for _, field in ipairs({"dismissedBoeAlerts", "shownBoeAlerts"}) do
        for key, stamp in pairs(self.db[field] or {}) do if stamp < cutoff then self.db[field][key] = nil end end
    end
    for index = #(self.db.boe or {}), 1, -1 do
        local record = self.db.boe[index]
        if not record.at or record.at < cutoff then
            record.deleted = true; table.remove(self.db.boe, index); changed = true
            if ForeverTeamGearUpgradePopup and ForeverTeamGearUpgradePopup.currentRecord == record then ForeverTeamGearUpgradePopup:Hide() end
        end
    end
    return changed
end

function ns:ClearBoe()
    for _, record in ipairs(self.db.boe or {}) do record.deleted = true end
    self.db.boe = {}
    if ForeverTeamGearUpgradePopup then ForeverTeamGearUpgradePopup:Hide() end
    self:RefreshWindow()
end

function ns:DeleteBoe(record)
    for index, stored in ipairs(self.db.boe or {}) do
        if stored == record then
            record.deleted = true
            table.remove(self.db.boe, index)
            if ForeverTeamGearUpgradePopup and ForeverTeamGearUpgradePopup.currentRecord == record then
                ForeverTeamGearUpgradePopup:Hide()
            end
            self:RefreshWindow()
            return true
        end
    end
    return false
end

function ns:AcceptBoe(payload, sender, unescape, split)
    local values = split(payload, "\t")
    for index, value in ipairs(values) do values[index] = unescape(value) end
    local record = {
        id = tonumber(values[1]), link = values[2], name = values[3], quality = tonumber(values[4]) or 1,
        ilvl = tonumber(values[5]) or 0, equipLoc = values[6], icon = tonumber(values[7]),
        quantity = tonumber(values[8]) or 1, looter = values[9] or sender, at = tonumber(values[10]) or self:Now(),
        classID = tonumber(values[11]), subclassID = tonumber(values[12]), minLevel = tonumber(values[13]) or 0,
    }
    if not record.id or record.id <= 0 or not self:SameCharacter(record.looter, sender) or not EQUIP_SLOTS[record.equipLoc] then return end
    if record.at < self:Now() - 48 * 60 * 60 then return end
    self:PruneBoe()
    record.looter = self:NormalizeSender(record.looter)
    for _, old in ipairs(self.db.boe) do
        if old.id == record.id and old.looter == record.looter and old.at == record.at then return end
    end
    record.looter = self:NormalizeSender(record.looter)
    table.insert(self.db.boe, 1, record)
    while #self.db.boe > 100 do table.remove(self.db.boe) end
    self:Print("BoE looted by " .. (record.looter or "?") .. ": " .. (record.link or record.name))
    scheduleUpgradeNotice(record)
    self:RefreshWindow()
end

local ARMOR_LIMITS = {
    MAGE = 1, PRIEST = 1, WARLOCK = 1,
    ROGUE = 2, DRUID = 2,
}

local SHIELD_CLASSES = { WARRIOR = true, PALADIN = true, SHAMAN = true }
local RELIC_CLASSES = {
    [7] = { PALADIN = true }, [8] = { DRUID = true }, [9] = { SHAMAN = true },
}

local WEAPON_CLASSES = {
    WARRIOR = { [0]=true, [1]=true, [2]=true, [3]=true, [4]=true, [5]=true, [6]=true, [7]=true, [8]=true, [10]=true, [13]=true, [15]=true, [16]=true, [18]=true },
    PALADIN = { [0]=true, [1]=true, [4]=true, [5]=true, [6]=true, [7]=true, [8]=true },
    HUNTER = { [0]=true, [1]=true, [2]=true, [3]=true, [6]=true, [7]=true, [8]=true, [10]=true, [13]=true, [15]=true, [16]=true, [18]=true },
    ROGUE = { [2]=true, [3]=true, [4]=true, [7]=true, [13]=true, [15]=true, [16]=true, [18]=true },
    PRIEST = { [4]=true, [10]=true, [15]=true, [19]=true },
    SHAMAN = { [0]=true, [1]=true, [4]=true, [5]=true, [10]=true, [13]=true, [15]=true },
    MAGE = { [7]=true, [10]=true, [15]=true, [19]=true },
    WARLOCK = { [7]=true, [10]=true, [15]=true, [19]=true },
    DRUID = { [4]=true, [5]=true, [6]=true, [10]=true, [13]=true, [15]=true },
}

local function hydrateClassification(record)
    if not record or not record.id then return end
    if (record.classID == nil or record.subclassID == nil) and C_Item and C_Item.GetItemInfoInstant then
        local _, _, _, equipLoc, icon, classID, subclassID = C_Item.GetItemInfoInstant(record.id)
        record.equipLoc = record.equipLoc or equipLoc
        record.icon = record.icon or icon
        record.classID = record.classID or classID
        record.subclassID = record.subclassID or subclassID
    end
    if not record.minLevel or record.minLevel == 0 then
        local _, _, _, _, minLevel = getItemInfo(record.id)
        record.minLevel = minLevel or record.minLevel or 0
    end
end

function ns:CanProfileUseBoe(profile, record)
    hydrateClassification(record)
    local classToken = profile and profile.classToken
    local level = profile and profile.level or 0
    if not classToken then return false, "Unknown class" end
    if (record.minLevel or 0) > level then return false, string.format("Requires level %d", record.minLevel) end

    if record.classID == 4 then
        local subclassID = record.subclassID
        if record.equipLoc == "INVTYPE_CLOAK" or subclassID == 0 or subclassID == 5 then return true end
        if subclassID and subclassID >= 1 and subclassID <= 4 then
            local limit = ARMOR_LIMITS[classToken]
            if classToken == "HUNTER" or classToken == "SHAMAN" then limit = level >= 40 and 3 or 2 end
            if classToken == "WARRIOR" or classToken == "PALADIN" then limit = level >= 40 and 4 or 3 end
            if limit and subclassID <= limit then return true end
            return false, "Cannot wear this armor type"
        end
        if subclassID == 6 then
            if SHIELD_CLASSES[classToken] then return true end
            return false, "Class cannot use shields"
        end
        if RELIC_CLASSES[subclassID] then
            if RELIC_CLASSES[subclassID][classToken] then return true end
            return false, "Wrong class relic"
        end
        return true
    end

    if record.classID == 2 then
        if record.subclassID == 14 or record.subclassID == 20 then return true end
        local allowed = WEAPON_CLASSES[classToken]
        if allowed and allowed[record.subclassID] then return true end
        return false, "Class cannot use this weapon type"
    end

    return true
end

function ns:ComparisonFor(record, currentGroupOnly)
    hydrateClassification(record)
    local result = {}
    for _, profile in pairs(self.db.players) do
        if self:IsVisibleCharacter(profile.key) and (not profile.sharing or profile.sharing.gear ~= false)
            and (not currentGroupOnly or self:IsActiveTeamCharacter(profile.key)) then
            local slots = EQUIP_SLOTS[record.equipLoc] or {}
            if record.equipLoc == "INVTYPE_WEAPON" then
                -- Compare weapons against actual equipped weapons, not a vacant
                -- off-hand (which may be unavailable or occupied by a two-hander).
                slots = { 16 }
                local offhand = profile.gear and profile.gear[17]
                local class = profile.classToken
                if offhand and (class == "ROGUE" or class == "WARRIOR" or class == "HUNTER" or class == "SHAMAN") then
                    local _, _, _, _, _, location = getItemInfo(offhand.id)
                    if location == "INVTYPE_WEAPON" or location == "INVTYPE_WEAPONOFFHAND" then slots = { 16, 17 } end
                end
            end
            local weaponComparisons
            if record.classID == 2 and (record.equipLoc == "INVTYPE_WEAPON" or record.equipLoc == "INVTYPE_WEAPONMAINHAND" or record.equipLoc == "INVTYPE_2HWEAPON" or record.equipLoc == "INVTYPE_WEAPONOFFHAND") then
                weaponComparisons = {}
                for _, slot in ipairs({16, 17}) do
                    local item = profile.gear and profile.gear[slot]
                    if item or slot == 16 then
                        weaponComparisons[#weaponComparisons + 1] = { slot = slot, equipped = item, delta = (record.ilvl or 0) - (item and item.ilvl or 0) }
                    end
                end
            end
            if record.equipLoc == "INVTYPE_TRINKET" or record.equipLoc == "INVTYPE_FINGER" then
                weaponComparisons = {}
                for _, slot in ipairs(slots) do
                    local item = profile.gear and profile.gear[slot]
                    weaponComparisons[#weaponComparisons + 1] = { slot = slot, equipped = item, delta = (record.ilvl or 0) - (item and item.ilvl or 0) }
                end
            end
            local best, bestSlot
            for _, slot in ipairs(slots) do
                local equipped = profile.gear and profile.gear[slot]
                if not equipped then
                    best, bestSlot = nil, slot
                    break
                elseif not best or (equipped.ilvl or 0) < (best.ilvl or 0) then
                    best, bestSlot = equipped, slot
                end
            end
            local oldLevel = best and best.ilvl or 0
            local usable, reason = self:CanProfileUseBoe(profile, record)
            if profile.sender and not (profile.syncSections and profile.syncSections.E) and not next(profile.gear or {}) then
                usable, reason = false, "Equipment not received yet; sync this character first"
            end
            result[#result + 1] = { profile = profile, equipped = best, slot = bestSlot, weaponComparisons = weaponComparisons, delta = (record.ilvl or 0) - oldLevel, usable = usable, unusableReason = reason }
        end
    end
    table.sort(result, function(a, b)
        if a.usable ~= b.usable then return a.usable end
        return a.delta > b.delta
    end)
    return result
end

local function sameRecord(a, b)
    return a and b and a.id == b.id and a.looter == b.looter and a.at == b.at
end

local function responseText(record)
    local parts = {}
    for playerKey, choice in pairs(record and record.responses or {}) do
        parts[#parts + 1] = string.format("%s: %s", playerKey, choice)
    end
    table.sort(parts)
    return #parts > 0 and table.concat(parts, "   •   ") or "No responses yet"
end

local CLASS_NAMES = {
    WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue",
    PRIEST = "Priest", SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}

local function profileLabel(profile)
    if ns.ProfileChoiceLabel then return ns.ProfileChoiceLabel(profile) end
    local firstName = tostring(profile.name or profile.key or "Unknown"):match("^(%S+)") or "Unknown"
    local className = profile.className or CLASS_NAMES[profile.classToken or ""] or profile.classToken or "Unknown"
    return string.format("%s (%s)", firstName, className)
end

local SLOT_NAMES = {
    [1] = "Head", [2] = "Neck", [3] = "Shoulders", [4] = "Shirt", [5] = "Chest",
    [6] = "Waist", [7] = "Legs", [8] = "Feet", [9] = "Wrists", [10] = "Hands",
    [11] = "Ring 1", [12] = "Ring 2", [13] = "Trinket 1", [14] = "Trinket 2",
    [15] = "Back", [16] = "Main Hand", [17] = "Off Hand", [18] = "Ranged", [19] = "Tabard",
}

local UpgradePopup = { rows = {} }

local function itemIcon(item)
    if not item then return "Interface\\Icons\\INV_Misc_QuestionMark" end
    if item.icon then return item.icon end
    local id = item.id or (item.link and tonumber(item.link:match("item:(%d+)")))
    if id and C_Item and C_Item.GetItemIconByID then
        local icon = C_Item.GetItemIconByID(id)
        if icon then return icon end
    end
    if id and C_Item and C_Item.GetItemInfoInstant then
        return select(5, C_Item.GetItemInfoInstant(id)) or "Interface\\Icons\\INV_Misc_QuestionMark"
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function createItemButton(parent)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(42, 42)
    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
        edgeSize = 11,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    button:SetBackdropColor(0.04, 0.04, 0.04, 1)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 4, -4); icon:SetPoint("BOTTOMRIGHT", -4, 4)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.icon = icon
    button:SetScript("OnEnter", function(self)
        if not self.itemLink then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.itemLink)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnClick", function(self)
        if self.itemLink and IsShiftKeyDown() then ChatEdit_InsertLink(self.itemLink) end
    end)
    return button
end

local function createUpgradeRows(count)
    for index = #UpgradePopup.rows + 1, count do
        local row = CreateFrame("Frame", nil, UpgradePopup.content, "BackdropTemplate")
        row:SetSize(1000, 56)
        row:SetPoint("TOPLEFT", 0, -((index - 1) * 58))
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
        row:SetBackdropColor(index % 2 == 0 and 0.08 or 0.04, index % 2 == 0 and 0.055 or 0.035, 0.02, 0.68)

        local character = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        character:SetPoint("LEFT", 7, 7); character:SetWidth(140); character:SetJustifyH("LEFT")
        row.character = character
        local slot = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        slot:SetPoint("TOPLEFT", character, "BOTTOMLEFT", 0, -3); slot:SetWidth(140); slot:SetJustifyH("LEFT")
        row.slot = slot

        local oldButton = createItemButton(row)
        oldButton:SetPoint("LEFT", 150, 0)
        row.oldButton = oldButton
        local oldText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        oldText:SetPoint("LEFT", oldButton, "RIGHT", 6, 0); oldText:SetWidth(116); oldText:SetJustifyH("LEFT"); oldText:SetWordWrap(true)
        row.oldText = oldText

        row.secondButton = createItemButton(row)
        row.secondButton:SetPoint("LEFT", 330, 0)
        row.secondText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.secondText:SetPoint("LEFT", row.secondButton, "RIGHT", 6, 0)
        row.secondText:SetWidth(116); row.secondText:SetJustifyH("LEFT"); row.secondText:SetWordWrap(true)

        local arrow = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        arrow:SetPoint("LEFT", 510, 0); arrow:SetText("→")

        local newButton = createItemButton(row)
        newButton:SetPoint("LEFT", 530, 0)
        row.newButton = newButton
        local newText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        newText:SetPoint("LEFT", newButton, "RIGHT", 6, 0); newText:SetWidth(116); newText:SetJustifyH("LEFT"); newText:SetWordWrap(true)
        row.newText = newText

        local delta = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        delta:SetPoint("LEFT", 715, 0); delta:SetWidth(278); delta:SetJustifyH("LEFT"); delta:SetWordWrap(true); delta:SetTextColor(0.25, 1, 0.25)
        row.delta = delta
        UpgradePopup.rows[index] = row
    end

end

local function createUpgradePopup()
    local frame = CreateFrame("Frame", "ForeverTeamGearUpgradePopup", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(1040, 470)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame.TitleText:SetText("Potential Upgrade")
    local close = frame.CloseButton or CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetParent(frame)
    close:ClearAllPoints(); close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    close:SetFrameLevel(frame:GetFrameLevel() + 10)
    close:EnableMouse(true); close:RegisterForClicks("LeftButtonUp")
    close:SetScript("OnClick", function() ns:DismissBoeAlert(frame.currentRecord); frame:Hide() end)
    close:Show()
    frame.CloseButton = close


    local glow = frame:CreateTexture(nil, "BACKGROUND")
    glow:SetPoint("TOPLEFT", 9, -29); glow:SetPoint("BOTTOMRIGHT", -9, 9)
    glow:SetColorTexture(0.12, 0.075, 0.02, 0.34)

    local newIcon = createItemButton(frame)
    newIcon:SetPoint("TOPLEFT", 20, -42)
    frame.newIcon = newIcon
    local newTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    newTitle:SetPoint("TOPLEFT", newIcon, "TOPRIGHT", 10, -2); newTitle:SetPoint("RIGHT", -20, 0); newTitle:SetJustifyH("LEFT")
    frame.newTitle = newTitle
    local newLevel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    newLevel:SetPoint("TOPLEFT", newTitle, "BOTTOMLEFT", 0, -5); newLevel:SetJustifyH("LEFT")
    frame.newLevel = newLevel

    local headers = {
        { "Character", 20 }, { "Currently Equipped", 170 }, { "New BoE", 550 }, { "Gain", 735 },
    }
    for _, header in ipairs(headers) do
        local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", header[2], -102)
        label:SetText(header[1])
    end

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -122); scroll:SetPoint("BOTTOMRIGHT", -35, 80)
    UpgradePopup.scroll = scroll
    UpgradePopup.content = CreateFrame("Frame", nil, scroll)
    UpgradePopup.content:SetSize(1000, 1); scroll:SetScrollChild(UpgradePopup.content)

    local openList = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    openList:SetSize(130, 24); openList:SetPoint("BOTTOMRIGHT", -104, 16); openList:SetText("Open BoE List")
    openList:SetScript("OnClick", function()
        frame:Hide()
        if ns.ToggleWindow then ns:ToggleWindow("boe") end
    end)
    local dismiss = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    dismiss:SetSize(90, 24); dismiss:SetPoint("LEFT", openList, "RIGHT", 6, 0); dismiss:SetText("Dismiss")
    dismiss:SetScript("OnClick", function() ns:DismissBoeAlert(frame.currentRecord); frame:Hide() end)

    local responseStatus = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    responseStatus:SetPoint("BOTTOMLEFT", 20, 49); responseStatus:SetPoint("RIGHT", -20, 0)
    responseStatus:SetJustifyH("LEFT"); responseStatus:SetText("No responses yet")
    frame.responseStatus = responseStatus

    local need = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    need:SetSize(74, 24); need:SetPoint("BOTTOMLEFT", 20, 16); need:SetText("Need")
    need:SetScript("OnClick", function()
        if frame.currentRecord then ns:SendBoeResponse(frame.currentRecord, "Need") end
    end)
    local pass = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    pass:SetSize(74, 24); pass:SetPoint("LEFT", need, "RIGHT", 6, 0); pass:SetText("Pass")
    pass:SetScript("OnClick", function()
        if frame.currentRecord then ns:SendBoeResponse(frame.currentRecord, "Pass") end
    end)

    frame:Hide()
    UpgradePopup.frame = frame
end

local function shortItemText(item, emptyText)
    if not item then return emptyText or "Empty slot" end
    local name = item.link and item.link:match("%[(.-)%]") or item.name
    return string.format("%s\n|cffaaaaaaiLvl %d|r", name or "Item", item.ilvl or 0)
end

local function showUpgradeNotice(record, upgrades)
    local chatTargets = {}
    for _, upgrade in ipairs(upgrades) do
        local label = string.format("%s (+%d iLvl)", upgrade.label, upgrade.delta)
        chatTargets[#chatTargets + 1] = label
    end
    ns:Print(string.format("Potential upgrade: %s for %s", record.link or record.name or "BoE item", table.concat(chatTargets, ", ")))

    if not UpgradePopup.frame then createUpgradePopup() end
    local frame = UpgradePopup.frame
    local display = upgrades
    createUpgradeRows(#display)
    UpgradePopup.content:SetHeight(math.max(1, #display * 58))
    UpgradePopup.scroll:SetVerticalScroll(0)
    frame.currentRecord = record
    frame.newIcon.icon:SetTexture(itemIcon(record))
    frame.newIcon.itemLink = record.link
    frame.newTitle:SetText(record.link or record.name or "BoE item")
    frame.newLevel:SetText(string.format("Item level %d  •  Looted by %s  •  Compare before equipping", record.ilvl or 0, record.looter or "test"))
    frame.responseStatus:SetText(responseText(record))

    for index, row in ipairs(UpgradePopup.rows) do
        local upgrade = display[index]
        if upgrade then
            local color = upgrade.profile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[upgrade.profile.classToken or ""]
            row.character:SetText(upgrade.label)
            row.character:SetTextColor(color and color.r or 1, color and color.g or 0.82, color and color.b or 0)
            local pair = upgrade.weaponComparisons
            local first, second = pair and pair[1] or upgrade, pair and pair[2]
            local function fill(button, text, comparison)
                local item = comparison.equipped
                button.icon:SetTexture(itemIcon(item)); button.icon:SetDesaturated(not item)
                button.itemLink = item and item.link
                text:SetText(shortItemText(item, "Empty slot\n|cffaaaaaaiLvl 0|r"))
            end
            row.slot:SetText(second and ((SLOT_NAMES[first.slot] or "") .. " / " .. (SLOT_NAMES[second.slot] or "")) or SLOT_NAMES[first.slot] or "Matching slot")
            fill(row.oldButton, row.oldText, first)
            row.secondButton:SetShown(second ~= nil); row.secondText:SetShown(second ~= nil)
            if second then fill(row.secondButton, row.secondText, second) else row.secondButton.itemLink = nil end
            row.oldButton.icon:SetTexture(itemIcon(first.equipped))
            row.oldButton.icon:SetDesaturated(not first.equipped)
            row.oldButton.itemLink = first.equipped and first.equipped.link
            row.oldText:SetText(shortItemText(first.equipped, "Empty slot\n|cffaaaaaaiLvl 0|r"))
            row.newButton.icon:SetTexture(itemIcon(record))
            row.newButton.icon:SetDesaturated(false)
            row.newButton.itemLink = record.link
            row.newText:SetText(shortItemText(record, "New BoE"))
            local function gain(comparison)
                local labels = { [16] = "main", [17] = "off", [11] = "ring 1", [12] = "ring 2", [13] = "trinket 1", [14] = "trinket 2" }
                local color = comparison.delta > 0 and "|cff40ff40" or comparison.delta < 0 and "|cffff4040" or "|cffffff40"
                return color .. string.format("%+d iLvl", comparison.delta) .. "|r" .. (pair and (" (" .. (labels[comparison.slot] or "slot") .. ")") or "")
            end
            row.delta:SetTextColor(1, 1, 1)
            row.delta:SetText(gain(first) .. (second and (", " .. gain(second)) or ""))
            row:Show()
        else
            row:Hide()
        end
    end
    frame:Show()
    frame:Raise()
end

function ns:CanReceiveBoeAlert(record)
    if not record or not self.db then return false end
    hydrateClassification(record)
    if record.classID == nil or record.subclassID == nil then return false end
    local profile = self.db.players[self:PlayerKey()]
    -- Check the logged-in character, not another member's possible upgrade.
    if UnitClass and UnitLevel then
        local _, class = UnitClass("player")
        profile = {classToken = class, level = UnitLevel("player") or 0}
    end
    if not profile then return false end
    return self:CanProfileUseBoe(profile, record)
end

function ns:AnnounceBoeUpgrades(record, manual)
    if not record or record.deleted or not self.db or (not manual and not self:AllowsAutomaticAlert(record.quality)) then return end
    if not self:IsVisibleCharacter(record.looter) then return end
    if not manual and not self:CanReceiveBoeAlert(record) then return end
    local key = noticeKey(record)
    if not manual and (Loot.notified[key] or (self.db.dismissedBoeAlerts or {})[key] or (self.db.shownBoeAlerts or {})[key]) then return end
    local upgrades = {}
    for _, comparison in ipairs(self:ComparisonFor(record, true)) do
        local profileKey = comparison.profile and comparison.profile.key
        local isAlt = profileKey and self.db.settings and self.db.settings.alts and self.db.settings.alts[profileKey]
        if comparison.usable and comparison.delta and (manual or comparison.delta > 0) and not isAlt then
            upgrades[#upgrades + 1] = {
                label = profileLabel(comparison.profile),
                delta = comparison.delta,
                profile = comparison.profile,
                equipped = comparison.equipped,
                weaponComparisons = comparison.weaponComparisons,
                slot = comparison.slot,
            }
        end
    end
    if #upgrades == 0 then
        if manual then self:Print("No potential upgrades for the selected audience in the saved equipment data.") end
        return
    end
    if not manual then
        Loot.notified[key] = true
        self.db.shownBoeAlerts = self.db.shownBoeAlerts or {}
        self.db.shownBoeAlerts[key] = self:Now()
    end
    showUpgradeNotice(record, upgrades)
end

function ns:SendBoeResponse(record, choice)
    if not record or (choice ~= "Need" and choice ~= "Pass") then return end
    record.responses = record.responses or {}
    local playerKey = self:PlayerKey()
    record.responses[playerKey] = choice
    if not record.isTest and self.BroadcastBoeResponse then self:BroadcastBoeResponse(record, playerKey, choice) end
    if UpgradePopup.frame and sameRecord(UpgradePopup.frame.currentRecord, record) then
        UpgradePopup.frame.responseStatus:SetText(responseText(record))
    end
    self:Print(choice .. " recorded for " .. (record.link or record.name or "this BoE"))
end

function ns:AcceptBoeResponse(payload, sender, unescape, split)
    local values = split(payload, "\t")
    for index, value in ipairs(values) do values[index] = unescape(value) end
    local identity = { id = tonumber(values[1]), looter = self:NormalizeSender(values[2]), at = tonumber(values[3]) }
    local responder, choice = values[4] or sender, values[5]
    if not identity.id or not self:SameCharacter(responder, sender) or (choice ~= "Need" and choice ~= "Pass") then return end
    for _, record in ipairs(self.db.boe or {}) do
        if sameRecord(record, identity) then
            record.responses = record.responses or {}
            record.responses[self:NormalizeSender(responder)] = choice
            if UpgradePopup.frame and sameRecord(UpgradePopup.frame.currentRecord, record) then
                UpgradePopup.frame.responseStatus:SetText(responseText(record))
            end
            self:RefreshWindow()
            return
        end
    end
end

function ns:TestUpgradeNotice(profileKey)
    local profile = self.db and self.db.players and self:IsVisibleCharacter(profileKey) and self.db.players[profileKey or ""]
    if not profile and self.db and self.db.players then
        profile = self.db.players[self:PlayerKey()]
        if not profile then
            for _, candidate in pairs(self.db.players) do
                if self:IsVisibleCharacter(candidate.key) then profile = candidate; break end
            end
        end
    end
    if not profile then
        local _, classToken = UnitClass("player")
        profile = { name = UnitName("player") or "Character", classToken = classToken }
    end
    local equipped, slot
    for candidateSlot, item in pairs(profile.gear or {}) do
        if not equipped or (item.ilvl or 0) < (equipped.ilvl or 0) then equipped, slot = item, candidateSlot end
    end
    local oldLevel = equipped and equipped.ilvl or 0
    local name, link, _, _, _, _, icon = getItemInfo(19019)
    if not name and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(19019) end
    local record = {
        id = 19019,
        isTest = true,
        name = name or "Thunderfury, Blessed Blade of the Windseeker",
        link = link or "|cffff8000|Hitem:19019::::::::::::|h[Thunderfury, Blessed Blade of the Windseeker]|h|r",
        ilvl = oldLevel + 5,
        icon = icon or "Interface\\Icons\\INV_Sword_39",
    }
    showUpgradeNotice(record, {
        { label = profileLabel(profile), delta = 5, profile = profile, equipped = equipped, slot = slot or 5 },
    })
end

function Loot:Initialize()
    ns:PruneBoe()
    if C_Timer and C_Timer.NewTicker then
        self.pruneTicker = C_Timer.NewTicker(300, function() if ns:PruneBoe() then ns:RefreshWindow() end end)
    end
    self.counts = allBagCounts()
    ns:On("BAG_UPDATE_DELAYED", function() self:Scan() end)
    ns:On("ITEM_DATA_LOAD_RESULT", function(id, success)
        if not success then return end
        local ready = {}
        for reference, quantity in pairs(self.pending) do
            if (tonumber(reference) or tonumber(tostring(reference):match("item:(%d+)"))) == id then ready[#ready + 1] = { reference, quantity } end
        end
        for _, entry in ipairs(ready) do
            self.pending[entry[1]] = nil
            self:Consider(entry[1], entry[2])
        end
    end)
end
