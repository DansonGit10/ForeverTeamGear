local _, ns = ...

local Comm = { incoming = {}, queue = {}, serial = 0 }
table.insert(ns.modules, Comm)

local sections = {
    { id = "I", fields = { 1, 2, 3, 4, 5, 11, 16, 22, 23 }, priority = 2 },
    { id = "E", fields = { 9 }, priority = 2 },
    { id = "T", fields = { 6, 7, 12 }, priority = 3 },
    { id = "R", fields = { 10 }, priority = 5 },
    { id = "B", fields = { 13 }, priority = 4 },
    { id = "K", fields = { 14, 15 }, priority = 5 },
}

local function checksum(value)
    local a, b = 1, 0
    for index = 1, #value do a = (a + value:byte(index)) % 65521; b = (b + a) % 65521 end
    return string.format("%08x", b * 65536 + a)
end

local function route(channel, target)
    return (channel == "GUILD" and "guild" or ns:GroupCode()) .. ":" .. channel .. ":" .. (target or "")
end

local function escape(value)
    return tostring(value or ""):gsub("%%", "%%25"):gsub("\t", "%%09"):gsub("\n", "%%0A")
end

local function unescape(value)
    return (value or ""):gsub("%%0A", "\n"):gsub("%%09", "\t"):gsub("%%25", "%%")
end

local function split(value, separator)
    local result, from = {}, 1
    while true do
        local at = value:find(separator, from, true)
        if not at then
            table.insert(result, value:sub(from))
            return result
        end
        table.insert(result, value:sub(from, at - 1))
        from = at + #separator
    end
end

local function encodeList(values)
    local out = {}
    for _, value in ipairs(values or {}) do out[#out + 1] = escape(value) end
    return table.concat(out, "\t")
end

local function groupChannel()
    if ns:Mode() == "offline" then return end
    if ns:Mode() == "group" and ns:UsesGuild() then return "ALL" end
    if ns:Mode() == "guild" then
        if IsInGuild and IsInGuild() then return "GUILD" end
        return
    end
    if ns:GroupCode() ~= "" then return "PRIVATE" end
end

local function permitted(kind)
    local option = ({ B = "boe", R = "boe", M = "macros" })[kind]
    return not option or ns:CanShare(option)
end

function ns:ResetCommunication()
    Comm.queue, Comm.incoming, Comm.requests = {}, {}, {}
    Comm.incomingBytes = 0
    Comm.groupSyncUntil = nil
    Comm.publishIntent = nil
    Comm.profilePending, Comm.profileOptions = false, nil
    Comm.profileGeneration = (Comm.profileGeneration or 0) + 1
    Comm.profileCache = {}
    Comm.lastRequest = nil
    Comm.lastPrivateRequest = nil
    Comm.hellos = {}
    Comm.helloSent = {}
    ns.privatePeers = {}
    if ns.ResetPrivateDiscovery then ns:ResetPrivateDiscovery() end
    if ns.RefreshPrivateStatus then ns:RefreshPrivateStatus() end
end

function ns:DiscardQueuedSharing()
    -- Privacy changes invalidate prepared packets, but not connected peers.
    Comm.queue = {}
end

function ns:SendPrivateHello(target)
    if self:Mode() ~= "group" or self:GroupCode() == "" or target == self:PlayerKey() then return end
    Comm.helloSent = Comm.helloSent or {}
    if Comm.helloSent[target] and GetTime() - Comm.helloSent[target] < 3 then return end
    Comm.helloSent[target] = GetTime()
    Comm.queue[#Comm.queue + 1] = { "G|" .. self:GroupCode() .. "|H", "WHISPER", target, nil, self:GroupCode(), true }
end

function Comm:Initialize()
    C_ChatInfo.RegisterAddonMessagePrefix(ns.prefix)
    ns:On("CHAT_MSG_ADDON", function(...) self:OnMessage(...) end)
    ns:On("GROUP_ROSTER_UPDATE", function()
        if ns.RefreshWindow then ns:RefreshWindow() end
    end)
    self.ticker = C_Timer.NewTicker(0.12, function() self:FlushOne() end)
    self.statusTicker = C_Timer.NewTicker(1, function() if ns.UpdateSyncIndicator then ns:UpdateSyncIndicator() end end)
    self.cleanupTicker = C_Timer.NewTicker(10, function()
        for key, pending in pairs(self.incoming) do
            if GetTime() - pending.at > 120 then
                self.incomingBytes = math.max(0, (self.incomingBytes or 0) - (pending.bytes or 0))
                self.incoming[key] = nil
            end
        end
    end)
end

function Comm:Send(message, channel, target, batch)
    if not ns:CanCommunicate(channel, target) then return end
    local private = channel == "WHISPER" and ns:Mode() == "group" and ns:IsPrivatePeer(target)
    local context = private and ns:GroupCode() or "guild"
    if private then message = "G|" .. context .. "|" .. message end
    self.queue[#self.queue + 1] = { message, channel, target, batch, context }
end

function Comm:FlushOne()
    local best, priority
    for index, message in ipairs(self.queue) do
        local rank = message[4] and message[4].priority or 0
        if not priority or rank < priority then best, priority = index, rank end
    end
    local nextMessage = best and table.remove(self.queue, best)
    if not nextMessage then return end
    if nextMessage[5] == "guild" then
        if not ns:UsesGuild() then return end
    elseif ns:Mode() ~= "group" or nextMessage[5] ~= ns:GroupCode() then return end
    local hello = nextMessage[6] and ns:Mode() == "group" and ns:GroupCode() ~= ""
    if (not hello and not ns:CanCommunicate(nextMessage[2], nextMessage[3])) or (nextMessage[4] and not permitted(nextMessage[4].kind)) then return end
    if nextMessage[4] then nextMessage[4].started = true end
    local target = nextMessage[3]
    if nextMessage[2] == "WHISPER" then target = ns:WhisperTarget(target) end
    C_ChatInfo.SendAddonMessage(ns.prefix, nextMessage[1], nextMessage[2], target)
    local batch = nextMessage[4]
    if batch and batch.cacheKey then
        batch.remaining = batch.remaining - 1
        if batch.remaining == 0 and self.sectionState and self.sectionState[batch.section] and self.sectionState[batch.section].signature == batch.signature then
            self.profileCache = self.profileCache or {}
            self.profileCache[batch.cacheKey] = batch.signature
        end
    end
end

function Comm:SendPayload(kind, payload, channel, target, options)
    channel = channel or groupChannel()
    if not channel or not ns:CanCommunicate(channel, target) or not permitted(kind) then return end
    options = options or {}
    -- Replace only profiles whose transmission has not begun. Once started,
    -- every chunk must be delivered so the receiver can assemble the profile.
    if kind == "P" then
        for index = #self.queue, 1, -1 do
            local queued = self.queue[index]
            local batch = queued[4]
            if batch and batch.kind == "P" and batch.section == options.section and not batch.started and queued[2] == channel and queued[3] == target then
                table.remove(self.queue, index)
            end
        end
    end
    local batch = { kind = kind, section = options.section, cacheKey = options.cacheKey, signature = options.signature,
        priority = options.priority or (kind == "R" and 0 or kind == "B" and 1 or 3) }
    self.serial = self.serial + 1
    local transfer = tostring(ns:Now()) .. ":" .. tostring(self.serial)
    local chunkSize = 180
    local total = math.max(1, math.ceil(#payload / chunkSize))
    if total > 2048 then ns:Print("Sync section is too large to send."); return end
    batch.remaining = total
    for index = 1, total do
        local chunk = payload:sub((index - 1) * chunkSize + 1, index * chunkSize)
        self:Send(table.concat({ "D", kind, transfer, index, total, chunk }, "|"), channel, target, batch)
    end
end

function Comm:QueueProfile(values, channel, target, options)
    options = options or {}
    self.profileCache = self.profileCache or {}
    self.sectionState = self.sectionState or {}
    local changed = {}
    for _, section in ipairs(sections) do
        local content = {}
        for _, field in ipairs(section.fields) do content[#content + 1] = tostring(values[field] or "") end
        local signature = checksum(table.concat(content, "\t"))
        if not self.sectionState[section.id] or self.sectionState[section.id].signature ~= signature then
            ns.db.syncRevision = (ns.db.syncRevision or 0) + 1
            self.sectionState[section.id] = { signature = signature, revision = ns.db.syncRevision }
        end
        local cacheKey = route(channel, target) .. ":" .. section.id
        local obsoleteActive = false
        for index = #self.queue, 1, -1 do
            local batch = self.queue[index][4]
            if batch and batch.cacheKey == cacheKey and batch.signature ~= signature then
                if batch.started then obsoleteActive = true else table.remove(self.queue, index) end
            end
        end
        local known = options.known and options.known[section.id] or self.profileCache[cacheKey]
        if obsoleteActive or options.force or (options.known and options.known[section.id] ~= signature) or (not options.known and known ~= signature) then
            local pending
            for _, message in ipairs(self.queue) do
                local batch = message[4]
                if batch and batch.cacheKey == cacheKey and batch.signature == signature then
                    pending = batch
                    if options.priority then batch.priority = math.min(batch.priority, options.priority) end
                end
            end
            if not pending then changed[#changed + 1] = { definition = section, signature = signature, cacheKey = cacheKey, revision = self.sectionState[section.id].revision } end
        end
    end
    if #changed == 0 and not options.priority then return end
    for index, section in ipairs(changed) do
        local partial = {}
        for field = 1, 23 do partial[field] = "" end
        for _, field in ipairs({ 1, 2, 3, 4, 5, 8, 11, 16, 22, 23 }) do partial[field] = values[field] end
        for _, field in ipairs(section.definition.fields) do partial[field] = values[field] end
        partial[17], partial[18], partial[19] = section.definition.id, section.signature, index .. "/" .. #changed
        partial[20], partial[21] = section.revision, self.sectionState.I.revision
        self:SendPayload("P", encodeList(partial), channel, target, { section = partial[17], signature = section.signature,
            cacheKey = section.cacheKey, priority = options.priority or section.definition.priority })
    end
    local done = {}
    for index = 1, 23 do done[index] = "" end
    for _, index in ipairs({ 1, 2, 3, 4, 5, 8, 11, 16, 22, 23 }) do done[index] = values[index] end
    done[17] = "Z"
    done[21] = self.sectionState.I.revision
    self:SendPayload("P", encodeList(done), channel, target, { section = "Z", priority = options.priority or 6 })
end

function Comm:OnMessage(prefix, message, channel, sender)
    if prefix ~= ns.prefix or type(message) ~= "string" or #message > 255 then return end
    sender = ns:NormalizeSender(sender)
    if not sender or sender == ns:PlayerKey() then return end
    if channel == "PARTY" or channel == "RAID" then
        if ns:Mode() == "offline" or not ns:IsCurrentGroupCharacter(sender) then return end
        local code = message:match("^S|([^|]*)$")
        if code == nil then return end
        local private = ns:Mode() == "group" and code ~= "" and code == ns:GroupCode()
        local guild = ns:UsesGuild() and ns:IsGuildCharacter(sender)
        if not private and not guild then return end
        self.groupRequests = self.groupRequests or {}
        if self.groupRequests[sender] and GetTime() - self.groupRequests[sender] < 30 then return end
        -- Also cap aggregate responses when multiple raid members click together.
        if self.lastGroupReply and GetTime() - self.lastGroupReply < 5 then return end
        self.groupRequests[sender], self.lastGroupReply = GetTime(), GetTime()
        if private then
            ns.privatePeers = ns.privatePeers or {}; ns.privatePeers[sender] = code
            ns:SendPrivateHello(sender)
        end
        C_Timer.After(1 + math.random() * 4, function()
            if ns:IsCurrentGroupCharacter(sender) and ns:CanCommunicate("WHISPER", sender) then
                ns:SendProfile("WHISPER", sender, { priority = 1, force = true })
            end
        end)
        return
    end
    local privateCode
    if message:sub(1, 2) == "G|" then
        if ns:Mode() ~= "group" then return end
        if channel ~= "WHISPER" or ns:GroupCode() == "" then return end
        local code, inner = message:match("^G|([^|]+)|(.*)$")
        if code ~= ns:GroupCode() then return end
        privateCode = code
        message = inner
        if message == "H" then
            self.hellos = self.hellos or {}
            if self.hellos[sender] and GetTime() - self.hellos[sender] < 5 then return end
            self.hellos[sender] = GetTime()
            local known = ns:IsPrivatePeer(sender)
            ns.privatePeers = ns.privatePeers or {}
            ns.privatePeers[sender] = code
            if not known then ns:Print("Private sync: connected to " .. ns:WhisperTarget(sender) .. ". Requesting character data.") end
            if ns.RefreshPrivateStatus then ns:RefreshPrivateStatus() end
            if not known then ns:SendPrivateHello(sender) end
            local intent = self.publishIntent
            if intent and intent.code == code and GetTime() <= intent.untilTime then
                -- Complete only this user's pending share when discovery was slow.
                -- The peer is not asked to upload a profile in return.
                ns:SendProfile("WHISPER", sender, { priority = 1, force = true })
            end
            -- Handshake establishes a route only; it never requests profiles.
            return
        end
    end
    if not sender or sender == ns:PlayerKey() or not ns:CanCommunicate(channel, sender) then return end
    if privateCode then
        if not ns:IsPrivatePeer(sender) then return end
    elseif channel == "GUILD" then
        if not ns:UsesGuild() or not (IsInGuild and IsInGuild()) then return end
        -- GUILD is an authenticated guild transport; roster data may not be loaded yet.
        ns.guildMembers = ns.guildMembers or {}; ns.guildMembers[sender] = true
    elseif not ns:UsesGuild() or not ns:IsGuildCharacter(sender) then return end
    -- Legacy requests are deliberately ignored: one user's click must not
    -- make every online client upload its profile.
    if message:sub(1, 2) == "Q|" then return end
    local kind, transferID, indexText, totalText, chunk = message:match("^D|([^|]*)|([^|]*)|(%d+)|(%d+)|(.*)$")
    if not kind or not ({ P = true, B = true, R = true, M = true, U = true })[kind] then return end
    if kind == "P" and self.groupSyncUntil and ns:IsCurrentGroupCharacter(sender) then
        self.groupSyncUntil = GetTime() + 3
    end
    local transfer = sender .. ":" .. (privateCode or "guild") .. ":" .. transferID
    local index, total = tonumber(indexText), tonumber(totalText)
    if not index or not total or total < 1 or total > 2048 or index < 1 or index > total or #chunk > 180 then return end
    local bucket = self.incoming[transfer]
    if bucket and (bucket.total ~= total or bucket.kind ~= kind) then return end
    if not bucket then
        local active = 0
        for _ in pairs(self.incoming) do active = active + 1 end
        if active >= 80 then return end
        bucket = { chunks = {}, total = total, kind = kind, at = GetTime(), count = 0 }
        if kind == "P" and total > 10 then ns:Print(string.format("Receiving character data from %s (%d packets).", ns:WhisperTarget(sender), total)) end
    end
    self.incoming[transfer] = bucket
    if bucket.chunks[index] ~= nil then return end
    if (self.incomingBytes or 0) + #chunk > 2 * 1024 * 1024 then return end
    bucket.bytes = (bucket.bytes or 0) + #chunk
    self.incomingBytes = (self.incomingBytes or 0) + #chunk
    bucket.chunks[index] = chunk or ""
    bucket.at = GetTime()
    bucket.count = bucket.count + 1
    if kind == "P" and total > 10 then
        local percent = math.floor(bucket.count * 100 / total)
        local step = math.floor(percent / 25)
        if step > (bucket.progress or 0) then
            bucket.progress = step
            ns:Print(string.format("Sync from %s: %d%% (%d/%d packets).", ns:WhisperTarget(sender), percent, bucket.count, total))
        end
    end
    if bucket.count == total then
        local payload = table.concat(bucket.chunks)
        self.incoming[transfer] = nil
        self.incomingBytes = math.max(0, (self.incomingBytes or 0) - (bucket.bytes or 0))
        if kind == "P" then ns:AcceptProfile(payload, sender, unescape, split, privateCode) end
        if kind == "B" then ns:AcceptBoe(payload, sender, unescape, split) end
        if kind == "R" then ns:AcceptBoeResponse(payload, sender, unescape, split) end
        if kind == "M" then ns:AcceptMacro(payload, sender, unescape, split, privateCode) end
        if kind == "U" then ns:AcceptMacroRemoval(payload, sender, unescape, split) end
    end

    for key, pending in pairs(self.incoming) do
        if GetTime() - pending.at > 120 then
                self.incomingBytes = math.max(0, (self.incomingBytes or 0) - (pending.bytes or 0))
                self.incoming[key] = nil
            end
    end
end

function ns:RequestGroupSync()
    if self:Mode() == "offline" then self:Print("Offline mode: local data refreshed."); return false end
    local raid = IsInRaid and IsInRaid()
    if not raid and not (IsInGroup and IsInGroup()) then
        self:Print("Sync Now requires a party or raid."); return false
    end
    local now = GetTime()
    if Comm.lastGroupRequest and now - Comm.lastGroupRequest < 30 then
        self:Print("Group sync is on cooldown (30 seconds)."); return false
    end
    Comm.lastGroupRequest = now
    Comm.groupSyncUntil = now + 7
    if self.UpdateSyncIndicator then self:UpdateSyncIndicator() end
    local channel = raid and "RAID" or "PARTY"
    -- Group channels carry only this request; profiles remain audience-checked whispers.
    C_ChatInfo.SendAddonMessage(self.prefix, "S|" .. (self:Mode() == "group" and self:GroupCode() or ""), channel)
    local prefix = raid and "raid" or "party"
    local count = raid and (GetNumGroupMembers() or 0) or (GetNumSubgroupMembers() or 0)
    for index = 1, count do
        local target = self:UnitKey(prefix .. index)
        if target and target ~= self:PlayerKey() then
            if self:Mode() == "group" then self:SendPrivateHello(target) end
            C_Timer.After(3 + math.random() * 2, function()
                if self:IsCurrentGroupCharacter(target) and self:CanCommunicate("WHISPER", target) then
                    self:SendProfile("WHISPER", target, { priority = 1, force = true })
                end
            end)
        end
    end
    self:Print("Sync requested from your party/raid; existing sharing permissions apply.")
    return true
end

function ns:RequestSync(userInitiated)
    if not groupChannel() then return end
    if userInitiated and self:Mode() == "group" then
        Comm.publishIntent = { code = self:GroupCode(), untilTime = GetTime() + 30 }
    end
    if userInitiated and self.DiscoverPrivateGroup then self:DiscoverPrivateGroup(true) end
    -- Only publish this client's own snapshot. A short delay lets private
    -- discovery finish; login announcements are spread across thirty seconds.
    self:BroadcastProfile(userInitiated and 3 or (10 + math.random() * 30),
        userInitiated and { priority = 1, force = true } or nil)
end

function ns:SendEncoded(kind, values, channel, target, options)
    channel = channel or groupChannel()
    if channel == "ALL" then
        self:SendEncoded(kind, values, "PRIVATE", nil, options)
        if IsInGuild and IsInGuild() then self:SendEncoded(kind, values, "GUILD", nil, options) end
        return
    end
    if channel == "PRIVATE" then
        for peer in pairs(self.privatePeers or {}) do
            if self:IsPrivatePeer(peer) and not (self:UsesGuild() and self:IsGuildCharacter(peer)) then
                self:SendEncoded(kind, values, "WHISPER", peer, options)
            end
        end
        return
    end
    if kind == "P" and #values >= 16 then
        Comm:QueueProfile(values, channel, target, options)
    else Comm:SendPayload(kind, encodeList(values), channel, target, options) end
end

function ns:BroadcastProfile(delay, options)
    if not groupChannel() then return end
    local due = GetTime() + (delay or 2)
    local pending = Comm.profilePending and Comm.profileOptions or {}
    local merged = {}
    for key, value in pairs(pending) do merged[key] = value end
    for key, value in pairs(options or {}) do merged[key] = value end
    if pending.force then merged.force = true end
    if pending.priority and options and options.priority then merged.priority = math.min(pending.priority, options.priority) end
    Comm.profileOptions = merged
    if Comm.profilePending and Comm.profileDue <= due then return end
    Comm.profilePending = true
    Comm.profileDue = due
    Comm.profileGeneration = (Comm.profileGeneration or 0) + 1
    local generation = Comm.profileGeneration
    C_Timer.After(delay or 2, function()
        if Comm.profileGeneration ~= generation then return end
        local sendOptions = Comm.profileOptions
        Comm.profilePending, Comm.profileOptions = false, nil
        ns:SendProfile(groupChannel(), nil, sendOptions)
    end)
end

function ns:IsGroupSyncing()
    if not Comm.groupSyncUntil then return false end
    local queued, incoming = self:SyncStatus()
    if GetTime() < Comm.groupSyncUntil or queued > 0 or incoming > 0 then return true end
    Comm.groupSyncUntil = nil
    return false
end

function ns:SyncStatus()
    local incoming = 0
    for _ in pairs(Comm.incoming) do incoming = incoming + 1 end
    return #Comm.queue, incoming
end

function ns:BroadcastBoe(values)
    local channel = groupChannel()
    if channel then ns:SendEncoded("B", values, channel) end
end

function ns:BroadcastBoeResponse(record, responder, choice)
    local channel = groupChannel()
    if not channel then return end
    ns:SendEncoded("R", { record.id or 0, record.looter or "", record.at or 0, responder or ns:PlayerKey(), choice or "" }, channel)
end

function ns:BroadcastMacro(macro)
    local channel = groupChannel()
    if channel then ns:SendEncoded("M", { macro.name, macro.icon or "Interface\\Icons\\INV_Misc_QuestionMark", macro.body, macro.owner, macro.at, macro.playerID or "", macro.playerName or "" }, channel, nil, { priority = 1 }) end
end

function ns:BroadcastMacroRemoval(name, stamp)
    local channel = groupChannel()
    if channel then self:SendEncoded("U", { name, self:PlayerKey(), stamp }, channel, nil, { priority = 0 }) end
end
