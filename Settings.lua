local _, ns = ...
local Settings = {}
table.insert(ns.modules, Settings)

local defaults = { gear = true, talents = true, professions = true, bags = true, bank = true, boe = true, macros = true }

local alertOptions = {
    { -1, "Off" }, { 0, "All" }, { 1, "Common+" },
    { 2, "|cff1eff00Uncommon+|r" }, { 3, "|cff0070ddRare+|r" },
    { 4, "|cffa335eeEpic+|r" }, { 5, "|cffff8000Legendary+|r" }, { 6, "|cffe6cc80Artifact+|r" },
}
local function alertLabel(quality)
    for _, option in ipairs(alertOptions) do if option[1] == quality then return option[2] end end
    return "Off"
end

function ns:PlayerIdentity()
    local settings = self.db.settings
    if not settings.playerID then
        settings.playerID = string.format("FTGP-%x-%04x%04x", self:Now(), math.random(0, 65535), math.random(0, 65535))
    end
    if not settings.playerName or settings.playerName == "" then settings.playerName = self:WhisperTarget(self:PlayerKey()) end
    return settings.playerID, settings.playerName
end

function ns:IsOwnCharacter(key)
    return key == self:PlayerKey() or (self.db.ownCharacters and self.db.ownCharacters[key]) == true
end

function ns:Mode()
    return self.db.settings.setupComplete and self.db.settings.mode or "offline"
end

function ns:CanShare(kind)
    return self:Mode() ~= "offline" and self.db.settings.sharing[kind] == true
end

function ns:IsGuildCharacter(key)
    if not (IsInGuild and IsInGuild() and self.guildMembers) then return false end
    if self.guildMembers[key] then return true end
    for member in pairs(self.guildMembers) do
        if self:SameCharacter(key, member) then return true end
    end
    return false
end

function ns:UsesGuild()
    return self:Mode() == "guild" or (self:Mode() == "group" and self.db.settings.alsoGuild == true)
end

function ns:IsVisibleCharacter(key)
    if self:IsOwnCharacter(key) then return true end
    local mode = self:Mode()
    local profile = self.db.players[key]
    return (self:UsesGuild() and self:IsGuildCharacter(key)) or
        (mode == "group" and self:GroupCode() ~= "" and profile and profile.privateGroup == self:GroupCode()) or false
end

function ns:GroupCode()
    return self.db.settings.groupCode or ""
end

function ns:ProfileSourceLabel(profile)
    if self:IsOwnCharacter(profile.key) then return "Offline" end
    local sources = {}
    if profile.privateGroup then sources[#sources + 1] = "Private group" end
    if profile.guildSource or (not profile.privateGroup and self:IsGuildCharacter(profile.key)) then
        sources[#sources + 1] = "Guild"
    end
    return #sources > 0 and table.concat(sources, " + ") or "Saved"
end

function ns:IsPrivateContact(key)
    return self:GroupCode() ~= "" and self.privatePeers and self.privatePeers[key] == self:GroupCode()
end

function ns:IsPrivatePeer(key)
    return self:IsPrivateContact(key) and self.privatePeers and self.privatePeers[key] == self:GroupCode()
end

function ns:IsActiveTeamCharacter(key)
    return self:IsVisibleCharacter(key)
end

function ns:RefreshPrivateStatus()
    if not Settings.frame or not Settings.frame.privateStatus then return end
    local count = 0
    for peer in pairs(self.privatePeers or {}) do
        if self:IsPrivatePeer(peer) then count = count + 1 end
    end
    Settings.frame.privateStatus:SetText("Connected friends: " .. count)
end

function ns:ParsePrivateGroup(code)
    code = (code or ""):upper():match("^%s*(.-)%s*$")
    if #code < 6 or #code > 20 or code:find("[^A-Z0-9%-]") or #code:gsub("%-", "") < 6 then
        return nil, "Use a group code of 6–20 letters, digits or hyphens."
    end
    return code
end

function ns:CanCommunicate(channel, target)
    local mode = self:Mode()
    if mode == "offline" then return false end
    if channel == "WHISPER" then
        return self:UsesGuild() and self:IsGuildCharacter(target) or mode == "group" and self:IsPrivatePeer(target)
    end
    if self:UsesGuild() then return channel == "GUILD" and IsInGuild and IsInGuild() end
    return false
end

function ns:UpdateGuildMembers()
    self.guildMembers = {}
    if IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
        for index = 1, GetNumGuildMembers() do
            local name = GetGuildRosterInfo(index)
            local key = self:NormalizeSender(name)
            if key then self.guildMembers[key] = true end
        end
    end
end

function ns:RequestGuildRoster()
    if not IsInGuild or not IsInGuild() then return end
    local request = C_GuildInfo and C_GuildInfo.GuildRoster or GuildRoster
    if request then request() end
end

function ns:OpenSettings()
    Settings:Show()
end

function Settings:Show()
    local frame = self.frame
    local settings = ns.db.settings
    frame.TitleText:SetText(settings.setupComplete and "Forever Team Gear — Settings" or "Forever Team Gear — Welcome")
    self.mode = settings.mode or "offline"
    for mode, button in pairs(frame.modes) do button:SetChecked(mode == self.mode) end
    for key, check in pairs(frame.sharing) do check:SetChecked(settings.sharing[key]) end
    frame.code:SetText(settings.groupCode or "")
    local _, playerName = ns:PlayerIdentity()
    frame.playerName:SetText(playerName)
    frame.alsoGuild:SetChecked(settings.alsoGuild == true)
    frame.alerts:SetText(alertLabel(settings.alertMinQuality))
    frame.alertMenu:Hide()
    frame.error:SetText("")
    ns:RefreshPrivateStatus()
    frame.save:SetText(settings.setupComplete and "Save settings" or "Start")
    frame:Show()
end

function Settings:Save()
    local settings = ns.db.settings
    local code, err = ns:ParsePrivateGroup(self.frame.code:GetText())
    if not code and self.mode == "group" then self.frame.error:SetText(err); return end
    local alsoGuild = self.frame.alsoGuild:GetChecked() and true or false
    local audienceChanged = settings.mode ~= self.mode or (settings.groupCode or "") ~= (code or "") or (settings.alsoGuild == true) ~= alsoGuild
    local playerName = self.frame.playerName:GetText():match("^%s*(.-)%s*$")
    if playerName == "" then self.frame.error:SetText("Enter your player display name."); return end
    settings.playerName = playerName
    ns:PlayerIdentity()
    settings.groupCode = code or ""
    settings.alsoGuild = alsoGuild
    settings.mode = self.mode
    settings.setupComplete = true
    for key, check in pairs(self.frame.sharing) do settings.sharing[key] = check:GetChecked() and true or false end
    -- Discard even partially sent snapshots when privacy or audience changes.
    if audienceChanged then
        if ns.ResetCommunication then ns:ResetCommunication() end
    elseif ns.DiscardQueuedSharing then ns:DiscardQueuedSharing() end
    if ns.UpdatePrivateChannel then ns:UpdatePrivateChannel(true) end
    ns:UpdateGuildMembers()
    if ns:UsesGuild() then ns:RequestGuildRoster() end
    if ns.CloseSharedWindows then ns:CloseSharedWindows() end
    ns:ScanAll()
    ns:RequestSync(true)
    self.frame:Hide()
    if ns.RefreshWindow then ns:RefreshWindow() end
end

function Settings:UpdateSharing(key, enabled)
    if not ns.db.settings.setupComplete then return end
    ns.db.settings.sharing[key] = enabled and true or false
    if ns.DiscardQueuedSharing then ns:DiscardQueuedSharing() end
    ns:BroadcastProfile()
    ns:Print("Sharing preference saved: " .. key .. " " .. (enabled and "ON" or "OFF") .. ".")
    if ns.RefreshWindow then ns:RefreshWindow() end
end

function ns:MigrateRealmKeys()
    local settings, players, aliases = self.db.settings, {}, {}
    for old, profile in pairs(self.db.players) do
        local key = self:NormalizeSender(old)
        aliases[old] = key
        profile.key, profile.realm = key, nil
        if profile.sender then profile.sender = self:NormalizeSender(profile.sender) end
        local previous = players[key]
        if not previous or (profile.updated or 0) > (previous.updated or 0) then
            if previous then
                profile.privateGroup = profile.privateGroup or previous.privateGroup
                profile.guildSource = profile.guildSource or previous.guildSource
            end
            players[key] = profile
        else
            previous.privateGroup = previous.privateGroup or profile.privateGroup
            previous.guildSource = previous.guildSource or profile.guildSource
        end
    end
    self.db.players = players
    local function rekey(values)
        local result = {}
        for key, value in pairs(values or {}) do result[aliases[key] or self:NormalizeSender(key)] = value end
        return result
    end
    self.db.ownCharacters = rekey(self.db.ownCharacters)
    settings.alts, settings.favorites = rekey(settings.alts), rekey(settings.favorites)
    if settings.selectedCharacter then settings.selectedCharacter = aliases[settings.selectedCharacter] or self:NormalizeSender(settings.selectedCharacter) end
    local wanted = {}
    for key, value in pairs(settings.wantedRecipes or {}) do
        local owner, rest = key:match("^([^|]+)(|.*)$")
        wanted[owner and ((aliases[owner] or self:NormalizeSender(owner)) .. rest) or key] = value
    end
    settings.wantedRecipes = wanted
    local hidden = {}
    for key, stamp in pairs(self.db.hiddenMacros or {}) do
        local owner, name = key:match("^([^|]+)|(.+)$")
        if owner then hidden[(aliases[owner] or self:NormalizeSender(owner)) .. "|" .. name] = stamp end
    end
    self.db.hiddenMacros = hidden
    for _, record in ipairs(self.db.boe or {}) do
        if record.looter then record.looter = aliases[record.looter] or self:NormalizeSender(record.looter) end
        if record.responses then record.responses = rekey(record.responses) end
    end
    local macros = {}
    for _, macro in pairs(self.db.sharedMacros or {}) do
        macro.owner = aliases[macro.owner] or self:NormalizeSender(macro.owner)
        local key = macro.owner .. "|" .. macro.name
        if not macros[key] or (macro.at or 0) > (macros[key].at or 0) then macros[key] = macro end
    end
    self.db.sharedMacros = macros
end

function Settings:Initialize()
    local settings = ns.db.settings
    if settings.alertMinQuality == nil then settings.alertMinQuality = settings.alertsEnabled == true and 0 or -1 end
    if not alertLabel(settings.alertMinQuality) or settings.alertMinQuality < -1 or settings.alertMinQuality > 6 then settings.alertMinQuality = -1 end
    settings.mode = ({ offline = true, group = true, guild = true })[settings.mode] and settings.mode or "offline"
    -- Old Group mode used party broadcasts. Require choosing a private group.
    if settings.mode == "group" and not settings.groupCode then
        settings.mode, settings.setupComplete = "offline", false
    end
    settings.sharing = settings.sharing or {}
    for key, value in pairs(defaults) do
        if settings.sharing[key] == nil then settings.sharing[key] = value end
    end
    ns.db.ownCharacters = ns.db.ownCharacters or {}
    local migrations = {}
    for key, profile in pairs(ns.db.players) do
        local first, surname = key:match("^([^%s%-]+)%-([^%s%-]+)$")
        local realm = (profile.realm or ""):gsub("%s+", "")
        if not profile.sender and first and surname and profile.name == first and realm ~= "" and surname ~= realm and not surname:match("^ClassicBeta") then
            migrations[#migrations + 1] = { old = key, key = first .. " " .. surname .. "-" .. realm, name = first .. " " .. surname, profile = profile }
        end
    end
    for _, entry in ipairs(migrations) do
        local previous = ns.db.players[entry.key]
        if not previous or (entry.profile.updated or 0) > (previous.updated or 0) then
            entry.profile.key, entry.profile.name = entry.key, entry.name
            ns.db.players[entry.key] = entry.profile
        end
        ns.db.players[entry.old] = nil
        ns.db.ownCharacters[entry.old], ns.db.ownCharacters[entry.key] = nil, true
        if settings.alts[entry.old] then settings.alts[entry.key], settings.alts[entry.old] = true, nil end
        if settings.favorites and settings.favorites[entry.old] then settings.favorites[entry.key], settings.favorites[entry.old] = true, nil end
        if settings.selectedCharacter == entry.old then settings.selectedCharacter = entry.key end
        for _, macro in pairs(ns.db.sharedMacros or {}) do if macro.owner == entry.old then macro.owner = entry.key end end
        local changed = {}
        for key, value in pairs(settings.wantedRecipes or {}) do
            if key:sub(1, #entry.old + 1) == entry.old .. "|" then changed[#changed + 1] = { key, entry.key .. key:sub(#entry.old + 1), value } end
        end
        for _, value in ipairs(changed) do settings.wantedRecipes[value[1]], settings.wantedRecipes[value[2]] = nil, value[3] end
        for _, record in ipairs(ns.db.boe or {}) do if record.looter == entry.old then record.looter = entry.key end end
    end
    for key, profile in pairs(ns.db.players) do
        if not profile.sender then ns.db.ownCharacters[key] = true end
    end
    ns:MigrateRealmKeys()
    ns.db.ownCharacters[ns:PlayerKey()] = true
    ns:UpdateGuildMembers()
    ns:On("GUILD_ROSTER_UPDATE", function()
        ns:UpdateGuildMembers()
        if ns.RefreshWindow then ns:RefreshWindow() end
    end)
    ns:On("PLAYER_GUILD_UPDATE", function()
        ns:UpdateGuildMembers()
        if ns.ResetCommunication then ns:ResetCommunication() end
        ns:RequestGuildRoster()
        if ns.CloseSharedWindows then ns:CloseSharedWindows() end
        if ns.RefreshWindow then ns:RefreshWindow() end
    end)
    ns:On("PLAYER_ENTERING_WORLD", function()
        ns:UpdateGuildMembers()
        if ns:UsesGuild() then ns:RequestGuildRoster() end
        if not settings.setupComplete then C_Timer.After(1, function() self:Show() end) end
    end)

    local frame = CreateFrame("Frame", "ForeverTeamGearSettingsFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(620, 700); frame:SetPoint("CENTER"); frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving); frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    local function label(text, x, y, font, width)
        local result = frame:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
        result:SetPoint("TOPLEFT", x, y); result:SetWidth(width or 500); result:SetJustifyH("LEFT"); result:SetText(text)
        return result
    end
    label("Choose who you use the addon with", 22, -40, "GameFontNormalLarge")
    label("Your characters are stored locally. Settings apply to all your characters on this WoW account.", 22, -65)
    frame.modes, frame.sharing = {}, {}
    local modes = {
        { "offline", "Offline", "Only your characters. No data is sent or received." },
        { "group", "Private group", "Only people with the same code; works outside party/raid." },
        { "guild", "Guild", "Your characters and members of your current guild." },
    }
    for index, entry in ipairs(modes) do
        local mode = entry[1]
        local check = CreateFrame("CheckButton", nil, frame, "UIRadioButtonTemplate")
        check:SetSize(22, 22); check:SetPoint("TOPLEFT", 22, -96 - (index - 1) * 42)
        label(entry[2], 50, -98 - (index - 1) * 42, "GameFontNormal")
        label(entry[3], 50, -114 - (index - 1) * 42)
        check:SetScript("OnClick", function()
            self.mode = mode
            for value, button in pairs(frame.modes) do button:SetChecked(value == mode) end
        end)
        frame.modes[mode] = check
    end
    local alsoGuild = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    alsoGuild:SetSize(24, 24); alsoGuild:SetPoint("TOPLEFT", 22, -213)
    label("Also sync with my guild in Private group mode", 50, -218, "GameFontHighlightSmall", 540)
    frame.alsoGuild = alsoGuild
    label("Private group code", 22, -240, "GameFontNormal")
    local code = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    code:SetSize(200, 22); code:SetPoint("TOPLEFT", 26, -255); code:SetAutoFocus(false); code:SetMaxLetters(20)
    code:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    frame.code = code
    frame.privateStatus = label("", 360, -260, "GameFontHighlightSmall", 230)
    local generate = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    generate:SetSize(100, 22); generate:SetPoint("LEFT", code, "RIGHT", 10, 0); generate:SetText("Generate")
    generate:SetScript("OnClick", function()
        code:SetText(string.format("FTG-%04X%04X%04X", math.random(0, 65535), math.random(0, 65535), math.random(0, 65535)))
    end)
    label("Share this code with your friends. Everyone selects Private group, enters the same code and clicks Save / Share my data. No character list needed.", 22, -289, nil, 570)
    label("A dedicated WoW chat channel discovers group members; character data travels by addon whispers. Requires compatible realm/faction chat. Codes are not encryption.", 22, -334, nil, 570)
    label("What do you want to share?", 22, -389, "GameFontNormalLarge")
    label("Sharing changes save immediately after setup. Local data stays available.", 22, -412, nil, 570)
    local options = {
        { "gear", "Equipment" }, { "talents", "Specialization and talents" },
        { "professions", "Professions and recipes" }, { "bags", "Bag contents" },
        { "bank", "Bank contents" }, { "boe", "BoE drops and Need/Pass" },
        { "macros", "Manually selected macros" },
    }
    for index, entry in ipairs(options) do
        local key = entry[1]
        local x, y = 22 + ((index - 1) % 2) * 295, -435 - math.floor((index - 1) / 2) * 30
        local check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        check:SetSize(24, 24); check:SetPoint("TOPLEFT", x, y)
        check:SetScript("OnClick", function(self) Settings:UpdateSharing(key, self:GetChecked()) end)
        label(entry[2], x + 28, y - 5, "GameFontHighlightSmall", 225)
        frame.sharing[key] = check
    end
    label("Online modes share name, class and level. Changing the code hides old group snapshots. Previously shared data may remain on other computers.", 22, -563, nil, 570)
    label("Player name (shared across your characters)", 22, -599, "GameFontNormal")
    local playerName = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    playerName:SetSize(290, 22); playerName:SetPoint("TOPLEFT", 26, -620); playerName:SetAutoFocus(false); playerName:SetMaxLetters(40)
    playerName:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    frame.playerName = playerName
    label("Automatic alerts — minimum rarity", 22, -657, "GameFontHighlightSmall", 290)
    local alerts = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    alerts:SetSize(230, 24); alerts:SetPoint("TOPLEFT", 332, -651)
    local menu = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    menu:SetSize(230, #alertOptions * 24 + 8); menu:SetPoint("BOTTOMLEFT", alerts, "TOPLEFT", 0, 2)
    menu:SetFrameStrata("TOOLTIP"); menu:EnableMouse(true)
    menu:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
    menu:SetBackdropColor(0.05, 0.05, 0.05, 1)
    for index, option in ipairs(alertOptions) do
        local quality, text = option[1], option[2]
        local choice = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
        choice:SetSize(222, 24); choice:SetPoint("TOPLEFT", 4, -4 - (index - 1) * 24); choice:SetText(text)
        choice:SetScript("OnClick", function()
            ns.db.settings.alertMinQuality = quality
            alerts:SetText(text); menu:Hide()
            if ForeverTeamGearUpgradePopup then ForeverTeamGearUpgradePopup:Hide() end
        end)
    end
    alerts:SetScript("OnClick", function() menu:SetShown(not menu:IsShown()) end)
    frame:SetScript("OnHide", function() menu:Hide() end)
    menu:Hide()
    frame.alerts, frame.alertMenu = alerts, menu
    frame.error = label("", 22, -687, "GameFontNormal", 570)
    frame.error:SetTextColor(1, 0.2, 0.2)
    local save = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    save:SetSize(150, 26); save:SetPoint("BOTTOM", 0, 18)
    save:SetScript("OnClick", function() self:Save() end); frame.save = save
    local test = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    test:SetSize(120, 26); test:SetPoint("BOTTOMLEFT", 22, 18); test:SetText("Test Alert")
    test:SetScript("OnClick", function()
        if ns.TestUpgradeNotice then ns:TestUpgradeNotice(ns.SelectedCharacterKey and ns:SelectedCharacterKey() or ns:PlayerKey()) end
    end)
    frame:SetHeight(756)
    self.frame = frame; frame:Hide()
end
