local _, ns = ...
local Private = { sessions = {} }
table.insert(ns.modules, Private)

function ns:SetPrivateDiscoveryStatus(message)
    self.privateDiscoveryStatus = message
    if self.RefreshPrivateStatus then self:RefreshPrivateStatus() end
end

function ns:IsPrivateChannelEvent(...)
    local expected = self:PrivateChannelName()
    if not expected then return false end
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        if type(value) == "string" then
            local name = value:gsub("^%s*%d+%.%s*", ""):match("^%s*(.-)%s*$")
            if name:lower() == expected:lower() then return true end
        end
    end
    return false
end

function ns:ResetPrivateDiscovery()
    Private.sessions, Private.lastHello = {}, nil
    self:SetPrivateDiscoveryStatus("Not connected yet")
    Private.session = tostring(self:Now()) .. ":" .. tostring(math.random(100000, 999999))
end

function ns:PrivateChannelName()
    if self:Mode() ~= "group" or self:GroupCode() == "" then return nil end
    return "FTG" .. self:GroupCode():gsub("%-", "")
end

function ns:UpdatePrivateChannel(userInitiated)
    local name = self:PrivateChannelName()
    if Private.channel and Private.channel ~= name then
        if not userInitiated then return end
        if LeaveChannelByName then LeaveChannelByName(Private.channel) end
        Private.channel, Private.lastHello = nil, nil
        self.db.settings.privateChannel = nil
        Private.sessions, self.privatePeers = {}, {}
    end
    if not name then return end
    local id = GetChannelName and GetChannelName(name)
    if not id or id == 0 then
        if userInitiated then
            local join = JoinTemporaryChannel or JoinChannelByName
            if not join then self:SetPrivateDiscoveryStatus("Channel join API unavailable"); return end
            local ok, result = pcall(join, name, self:GroupCode())
            if not ok or result == false then self:SetPrivateDiscoveryStatus("Channel join failed"); return end
            self:SetPrivateDiscoveryStatus("Joining private channel...")
            Private.channel = name
            self.db.settings.privateChannel = name
        end
    else
        Private.channel = name
        self.db.settings.privateChannel = name
    end
end

function ns:DiscoverPrivateGroup(userInitiated)
    if self:Mode() ~= "group" then return end
    if not userInitiated then return end
    self:UpdatePrivateChannel(true)
    local name = self:PrivateChannelName()
    local id = name and GetChannelName and GetChannelName(name)
    if not id or id == 0 then
        self:Print("Private sync: channel not joined yet. Wait for the channel-ready message, then click Share my data again.")
        return
    end
    local now = GetTime()
    if Private.lastHello and now - Private.lastHello < 5 then
        self:Print("Private sync: discovery was sent recently; waiting for friends.")
        return
    end
    local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
    if not send then return end
    local ok, result = pcall(send, "FTGHELLO1:" .. Private.session, "CHANNEL", nil, id)
    if not ok or result == false then self:SetPrivateDiscoveryStatus("Discovery blocked; click Share again"); return end
    Private.lastHello = now
    self:SetPrivateDiscoveryStatus("Discovery sent; waiting for peers")
    self:Print("Private sync: discovery sent. Waiting for another addon with the same group code.")
end

function Private:OnPresence(message, sender, ...)
    if not ns:IsPrivateChannelEvent(...) then return end
    local session = type(message) == "string" and message:match("^FTGHELLO1:([%w:%.%-]+)$")
    sender = ns:NormalizeSender(sender)
    if not session or #session > 80 or not sender or sender == ns:PlayerKey() then return end
    if self.sessions[sender] == session and ns:IsPrivatePeer(sender) then return end
    self.sessions[sender] = session
    ns:SetPrivateDiscoveryStatus("Peer found; connecting...")
    ns:Print("Private sync: found " .. ns:WhisperTarget(sender) .. "; sending addon handshake.")
    -- Presence only initiates a code-checked handshake. No profile is sent yet.
    if ns.SendPrivateHello then ns:SendPrivateHello(sender) end
end

function Private:Initialize()
    ns:ResetPrivateDiscovery()
    self.channel = ns.db.settings.privateChannel
    ns.privatePeers = {}
    ns:On("PLAYER_ENTERING_WORLD", function()
        ns:UpdatePrivateChannel()
    end)
    ns:On("CHAT_MSG_CHANNEL", function(...) self:OnPresence(...) end)
    ns:On("CHAT_MSG_CHANNEL_NOTICE", function(notice, ...)
        if not ns:IsPrivateChannelEvent(...) then return end
        if notice == "WRONG_PASSWORD" or notice == "BANNED" or notice == "CHANNEL_LIMIT" or notice == "INVALID_NAME" then
            ns:SetPrivateDiscoveryStatus("Channel error: " .. notice)
        elseif notice == "YOU_JOINED" then
            ns:SetPrivateDiscoveryStatus("Channel joined; ready for peers")
        elseif notice == "YOU_LEFT" then ns:SetPrivateDiscoveryStatus("Private channel disconnected") end
    end)
    -- Joining is asynchronous. Existing members receive this event even when
    -- the joining player could not announce presence on their first click.
    ns:On("CHAT_MSG_CHANNEL_JOIN", function(_, sender, ...)
        if not ns:IsPrivateChannelEvent(...) then return end
        local key = ns:NormalizeSender(sender)
        if key and key ~= ns:PlayerKey() then ns:SendPrivateHello(key) end
    end)
    ns:On("CHAT_MSG_CHANNEL_LEAVE", function(_, sender, ...)
        if ns:IsPrivateChannelEvent(...) then
            local key = ns:NormalizeSender(sender)
            if key then ns.privatePeers[key], self.sessions[key] = nil, nil end
            if ns.RefreshPrivateStatus then ns:RefreshPrivateStatus() end
        end
    end)
    if ChatFrame_AddMessageEventFilter then
        ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", function(_, _, _, _, ...)
            return ns:IsPrivateChannelEvent(...)
        end)
    end
end
