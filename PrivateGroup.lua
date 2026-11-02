local _, ns = ...
local Private = { sessions = {} }
table.insert(ns.modules, Private)

function ns:ResetPrivateDiscovery()
    Private.sessions, Private.lastHello = {}, nil
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
        if userInitiated and JoinTemporaryChannel then
            JoinTemporaryChannel(name, self:GroupCode())
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
    Private.lastHello = now
    send("FTGHELLO1:" .. Private.session, "CHANNEL", nil, id)
    self:Print("Private sync: discovery sent. Waiting for another addon with the same group code.")
end

function Private:OnPresence(message, sender, _, _, _, _, _, _, channelName)
    local name = ns:PrivateChannelName()
    if not name or type(channelName) ~= "string" or channelName:lower() ~= name:lower() then return end
    local session = type(message) == "string" and message:match("^FTGHELLO1:([%w:%.%-]+)$")
    sender = ns:NormalizeSender(sender)
    if not session or #session > 80 or not sender or sender == ns:PlayerKey() then return end
    if self.sessions[sender] == session and ns:IsPrivatePeer(sender) then return end
    self.sessions[sender] = session
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
    ns:On("CHAT_MSG_CHANNEL_NOTICE", function(notice, _, _, _, _, _, _, _, name)
        if name and ns:PrivateChannelName() and name:lower() == ns:PrivateChannelName():lower() then
            if notice == "WRONG_PASSWORD" or notice == "BANNED" or notice == "CHANNEL_LIMIT" then
                ns:Print("Cannot join the private group channel (" .. notice .. "). Check the code or available chat channel slots.")
                return
            end
            if notice == "YOU_JOINED" then ns:Print("Private channel ready. Click Share my data to discover friends.") end
        end
    end)
    ns:On("CHAT_MSG_CHANNEL_LEAVE", function(_, sender, _, _, _, _, _, _, name)
        if name and ns:PrivateChannelName() and name:lower() == ns:PrivateChannelName():lower() then
            local key = ns:NormalizeSender(sender)
            if key then ns.privatePeers[key], self.sessions[key] = nil, nil end
            if ns.RefreshPrivateStatus then ns:RefreshPrivateStatus() end
        end
    end)
    if ChatFrame_AddMessageEventFilter then
        ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", function(_, _, _, _, _, _, _, _, _, _, name)
            local active = ns:PrivateChannelName()
            return active and type(name) == "string" and name:lower() == active:lower() or false
        end)
    end
end
