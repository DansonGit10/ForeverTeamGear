local _, ns = ...

local MacroUI = { rows = {}, view = "own" }
table.insert(ns.modules, MacroUI)

local function sortedMacros(includeHidden)
    local result = {}
    for _, macro in pairs(ns.db.sharedMacros or {}) do
        local private = ns:Mode() == "group" and macro.privateGroup and macro.privateGroup == ns:GroupCode()
        local guild = macro.guildSource and ns.UsesGuild and ns:UsesGuild() and ns:IsGuildCharacter(macro.owner)
        if includeHidden or ns:IsVisibleCharacter(macro.owner) or private or guild then result[#result + 1] = macro end
    end
    table.sort(result, function(a, b) return (a.at or 0) > (b.at or 0) end)
    return result
end

function ns:MacroCharacterChoices(query, source, hideAlts)
    local choices, seen = {}, {}
    for _, profile in ipairs(self:CharacterChoices(query, source, hideAlts)) do
        for _, macro in ipairs(sortedMacros()) do
            if macro.owner == profile.key then choices[#choices + 1], seen[profile.key] = profile, true; break end
        end
    end
    for _, macro in ipairs(sortedMacros()) do
        if not seen[macro.owner] and not self.db.players[macro.owner] then
            local own = self:IsOwnCharacter(macro.owner)
            local matches = source == "all" or source == nil or source == "offline" and own or source == "private" and macro.privateGroup == self:GroupCode() or source == "guild" and macro.guildSource
            if matches and not (hideAlts and (self.db.settings.alts or {})[macro.owner]) and (query == "" or (macro.owner .. " " .. (macro.playerName or "")):lower():find(query:lower(), 1, true)) then
                choices[#choices + 1] = { key = macro.owner, name = macro.owner, playerID = macro.playerID, playerName = macro.playerName, classToken = macro.classToken, level = macro.level, privateGroup = macro.privateGroup, guildSource = macro.guildSource }
                seen[macro.owner] = true
            end
        end
    end
    return choices
end

function ns:MacroPlayer(macro)
    local profile = self.db.players[macro.owner] or { key = macro.owner, playerID = macro.playerID, playerName = macro.playerName }
    if self.CharacterPlayerGroup then return self:CharacterPlayerGroup(profile) end
    return macro.playerID or macro.owner, macro.playerName or macro.owner
end

function ns:DeleteSharedMacro(macro)
    if not macro then return false end
    local key = macro.owner .. "|" .. macro.name
    local stored = (self.db.sharedMacros or {})[key]
    if not stored then return false end
    self.db.hiddenMacros = self.db.hiddenMacros or {}
    self.db.hiddenMacros[key] = stored.at or 0
    self.db.sharedMacros[key] = nil
    if MacroUI.frame and MacroUI.frame:IsShown() then MacroUI:Select(nil); MacroUI:Refresh() end
    return true
end

function ns:UnshareMacro(macro)
    if not macro or macro.owner ~= self:PlayerKey() then return false end
    local key = macro.owner .. "|" .. macro.name
    local stored = (self.db.sharedMacros or {})[key]
    if not stored then return false end
    local stamp = math.max(self:Now(), (stored.at or 0) + 1)
    self.db.hiddenMacros = self.db.hiddenMacros or {}
    self.db.hiddenMacros[key] = stamp
    self.db.sharedMacros[key] = nil
    if self.BroadcastMacroRemoval then self:BroadcastMacroRemoval(macro.name, stamp) end
    if MacroUI.frame and MacroUI.frame:IsShown() then MacroUI:Select(nil); MacroUI:Refresh() end
    return true
end

function ns:AcceptMacroRemoval(payload, sender, unescape, split)
    local values = split(payload, "\t")
    for index, value in ipairs(values) do values[index] = unescape(value) end
    local name, owner, stamp = values[1], values[2], tonumber(values[3])
    if not name or name == "" or #name > 128 or not stamp or not self:SameCharacter(owner, sender) then return end
    local key = sender .. "|" .. name
    local stored = (self.db.sharedMacros or {})[key]
    self.db.hiddenMacros = self.db.hiddenMacros or {}
    self.db.hiddenMacros[key] = math.max(self.db.hiddenMacros[key] or 0, stamp)
    if stored and (stored.at or 0) <= stamp then self.db.sharedMacros[key] = nil end
    if MacroUI.frame and MacroUI.frame:IsShown() then MacroUI:Refresh() end
end

function ns:ShareMacro(index)
    local function fail(message)
        self:Print(message)
        if MacroUI.status then MacroUI.status:SetText(message) end
    end
    if not self:CanShare("macros") then
        fail("Enable macro sharing and select Group or Guild mode in /ftg settings first.")
        return
    end
    index = tonumber(index)
    if not index then
        fail("Use /ftg sharemacro <number>. The macro is shared as text and is never installed or run automatically.")
        return
    end
    local name, icon, body = GetMacroInfo(index)
    if not name then fail("Macro #" .. index .. " does not exist."); return end
    if self:Mode() == "group" and not (self.UsesGuild and self:UsesGuild() and IsInGuild and IsInGuild()) then
        local connected = false
        for peer in pairs(self.privatePeers or {}) do if self:IsPrivatePeer(peer) then connected = true; break end end
        if not connected then fail("No connected friends. Click Share my data first."); return end
    elseif self:Mode() == "guild" and not (IsInGuild and IsInGuild()) then
        fail("You are not in a guild."); return
    end
    local owner = self:PlayerKey()
    local key = owner .. "|" .. name
    local stamp = math.max(self:Now(), ((self.db.hiddenMacros or {})[key] or 0) + 1)
    local macro = { name = name, icon = icon, body = body or "", owner = owner, at = stamp }
    if self.PlayerIdentity then macro.playerID, macro.playerName = self:PlayerIdentity() end
    self:AcceptSharedMacroRecord(macro)
    if self.BroadcastMacro then self:BroadcastMacro(macro) end
    self:Print("Shared macro: " .. name)
    if MacroUI.status then MacroUI.status:SetText("Queued for sharing: " .. name .. ". Recipients need the same addon version.") end
    return true
end

function ns:OwnMacros()
    local result = {}
    local account, character = GetNumMacros()
    local function add(index)
        local name, icon, body = GetMacroInfo(index)
        if name then result[#result + 1] = { name = name, icon = icon, body = body or "", index = index, owner = self:PlayerKey(), localMacro = true } end
    end
    for index = 1, account or 0 do add(index) end
    for index = 1, character or 0 do add((MAX_ACCOUNT_MACROS or 120) + index) end
    return result
end

function MacroUI:Select(macro)
    self.selected = macro
    self.name:SetText(macro and macro.name or "Select a macro")
    self.owner:SetText(macro and (macro.localMacro and "Your macro — " or "Shared by ") .. macro.owner or "")
    self.body:SetText(macro and macro.body or "")
    self.body:HighlightText(0, 0)
    self.share:SetEnabled(macro ~= nil and macro.localMacro == true and ns:CanShare("macros"))
    if self.remove then
        local stored = macro and (ns.db.sharedMacros or {})[macro.owner .. "|" .. macro.name]
        self.remove:SetText(macro and macro.owner == ns:PlayerKey() and "Unshare" or "Delete locally")
        self.remove:SetEnabled(stored ~= nil)
    end
end

function ns:AcceptSharedMacroRecord(macro)
    if not macro or not macro.name or not macro.owner then return end
    local key = macro.owner .. "|" .. macro.name
    if (self.db.hiddenMacros or {})[key] and (macro.at or 0) <= self.db.hiddenMacros[key] then return end
    if self.db.hiddenMacros then self.db.hiddenMacros[key] = nil end
    self.db.sharedMacros = self.db.sharedMacros or {}
    self.db.sharedMacros[macro.owner .. "|" .. macro.name] = macro
    local macros = sortedMacros(true)
    for index = 51, #macros do
        self.db.sharedMacros[macros[index].owner .. "|" .. macros[index].name] = nil
    end
    if MacroUI.frame and MacroUI.frame:IsShown() then MacroUI:Refresh() end
end

function ns:AcceptMacro(payload, sender, unescape, split, privateCode)
    local values = split(payload, "\t")
    for index, value in ipairs(values) do values[index] = unescape(value) end
    if #values < 5 or not self:SameCharacter(values[4], sender) or values[1] == "" or #values[1] > 128 or #values[3] > 4096 then return end
    self:AcceptSharedMacroRecord({
        name = values[1], icon = tonumber(values[2]) or values[2], body = values[3] or "",
        owner = sender, at = tonumber(values[5]) or self:Now(),
        privateGroup = privateCode, guildSource = not privateCode or nil,
        playerID = values[6] ~= "" and values[6] or nil, playerName = values[7] ~= "" and values[7] or nil,
    })
    if MacroUI.status then MacroUI.status:SetText("Received macro: " .. values[1] .. " — open Shared macros.") end
    self:Print("Received shared macro " .. (values[1] or "?") .. " from " .. (values[4] or sender or "?"))
end

function MacroUI:GetRow(index)
    if self.rows[index] then return self.rows[index] end
    local row = CreateFrame("Button", nil, self.content)
    row:SetSize(246, 38)
    row:SetPoint("TOPLEFT", 0, -((index - 1) * 40))
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(32, 32); icon:SetPoint("LEFT", 3, 0); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon = icon
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", icon, "RIGHT", 7, 0); text:SetPoint("RIGHT", -5, 0); text:SetJustifyH("LEFT")
    row.text = text
    row:SetScript("OnClick", function(self)
        if not self.macro then return end
        MacroUI:Select(self.macro)
    end)
    self.rows[index] = row
    return row
end

function MacroUI:Refresh()
    local macros = self.view == "own" and ns:OwnMacros() or sortedMacros()
    if self.view == "shared" then
        local filtered = {}
        for _, macro in ipairs(macros) do if ns:MacroPlayer(macro) == self.macroPlayer and not (self.hideAlts ~= false and (ns.db.settings.alts or {})[macro.owner]) then
                filtered[#filtered + 1] = macro
            end end
        macros = filtered
    end
    if self.chooser then
        self.chooser:SetShown(self.view == "shared")
        self.chooser:SetText(self.macroPlayerName or "Select player...")
    end
    local selected
    for _, macro in ipairs(macros) do
        if self.selected and macro.localMacro == self.selected.localMacro and macro.owner == self.selected.owner
            and (macro.localMacro and macro.index == self.selected.index or not macro.localMacro and macro.name == self.selected.name) then selected = macro end
    end
    self:Select(selected)
    self.ownButton:SetEnabled(self.view ~= "own"); self.sharedButton:SetEnabled(self.view ~= "shared")
    self.status:SetText(ns:CanShare("macros") and "Select one of your macros, then click Share selected." or "Sharing is off. Enable macros in Settings and choose an online mode.")
    for index = 1, math.max(#macros, #self.rows) do
        local row = self:GetRow(index)
        local macro = macros[index]
        if macro then
            row.macro = macro
            row.icon:SetTexture(macro.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.text:SetText(macro.name .. "\n|cff999999" .. macro.owner .. "|r")
            row:Show()
        else
            row.macro = nil
            row:Hide()
        end
    end
    self.content:SetHeight(math.max(1, #macros * 40))
    if #macros == 0 then
        self.name:SetText(self.view == "own" and "No macros found" or "No shared macros")
        self.owner:SetText(self.view == "own" and "Create a macro in WoW's macro window first." or "Macros shared by your selected group appear here.")
        self.body:SetText("")
    end
end

function MacroUI:Toggle()
    ns:ToggleWindow("macros")
end

function ns:ShowMacroPanel(show)
    if not MacroUI.frame then return end
    if show then MacroUI.frame:Show(); MacroUI:Refresh() else MacroUI.frame:Hide() end
end

function ns:RefreshMacroWindow()
    if MacroUI.frame and MacroUI.frame:IsShown() then MacroUI:Refresh() end
end

function MacroUI:Initialize()
    ns.db.sharedMacros = ns.db.sharedMacros or {}
    local frame = CreateFrame("Frame", "ForeverTeamGearMacroFrame", ns.mainWindow)
    frame:SetPoint("TOPLEFT", 12, -68); frame:SetPoint("BOTTOMRIGHT", -12, 12)
    local own = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    own:SetSize(110, 24); own:SetPoint("TOPLEFT", 0, 0); own:SetText("My macros")
    own:SetScript("OnClick", function() self.view = "own"; self:Select(nil); self:Refresh() end)
    self.ownButton = own
    local shared = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    shared:SetSize(110, 24); shared:SetPoint("LEFT", own, "RIGHT", 6, 0); shared:SetText("Shared macros")
    shared:SetScript("OnClick", function() self.view = "shared"; self:Select(nil); self:Refresh()
        if ns.OpenCharacterPicker then self.chooser:Click() end end)
    self.sharedButton = shared
    local share = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    share:SetSize(140, 24); share:SetPoint("TOPRIGHT", -4, 0); share:SetText("Share selected")
    share:SetScript("OnClick", function()
        if self.selected and self.selected.localMacro then ns:ShareMacro(self.selected.index) end
    end)
    self.share = share
    local remove = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    remove:SetSize(130, 24); remove:SetPoint("RIGHT", share, "LEFT", -6, 0)
    remove:SetScript("OnClick", function()
        if not self.selected then return end
        if self.selected.owner == ns:PlayerKey() then ns:UnshareMacro(self.selected) else ns:DeleteSharedMacro(self.selected) end
    end)
    self.remove = remove
    local chooser = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    chooser:SetSize(390, 24); chooser:SetPoint("TOPLEFT", 4, -33)
    chooser:SetScript("OnClick", function()
        ns:OpenCharacterPicker(function(key, name, hideAlts)
            self.macroPlayer, self.macroPlayerName, self.hideAlts = key, name, hideAlts
            self:Select(nil); self:Refresh()
        end, function(query, source, hideAlts) return ns:MacroCharacterChoices(query, source, hideAlts) end, true)
    end)
    self.chooser = chooser

    local status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", 4, -64); status:SetPoint("TOPRIGHT", -4, -64); status:SetJustifyH("LEFT")
    self.status = status

    local list = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    list:SetPoint("TOPLEFT", 4, -95); list:SetPoint("BOTTOMLEFT", 4, 12); list:SetWidth(272)
    local content = CreateFrame("Frame", nil, list); content:SetSize(246, 1); list:SetScrollChild(content); self.content = content

    local name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    name:SetPoint("TOPLEFT", 300, -95); name:SetPoint("RIGHT", -10, 0); name:SetJustifyH("LEFT"); self.name = name
    local owner = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    owner:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -5); self.owner = owner
    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", 300, -142); hint:SetPoint("RIGHT", -10, 0); hint:SetJustifyH("LEFT")
    hint:SetText("Macro text only — the addon never installs or runs it. Click the box, press Ctrl+A, then Ctrl+C.")

    local bodyScroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate,BackdropTemplate")
    bodyScroll:SetPoint("TOPLEFT", 294, -188); bodyScroll:SetPoint("BOTTOMRIGHT", -28, 12)
    bodyScroll:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
    local body = CreateFrame("EditBox", nil, bodyScroll)
    body:SetMultiLine(true); body:SetAutoFocus(false); body:SetFontObject(ChatFontNormal); body:SetTextInsets(8, 8, 8, 8)
    body:SetSize(340, 250); bodyScroll:SetScrollChild(body)
    body:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    self.body = body
    ns:On("UPDATE_MACROS", function() if self.frame:IsShown() then self:Refresh() end end)

    frame:Hide(); self.frame = frame
    ns.ToggleMacroWindow = function() MacroUI:Toggle() end
end
