local _, ns = ...

local MinimapButton = {}
table.insert(ns.modules, MinimapButton)

local function angleForPoint(y, x)
    if math.atan2 then return math.atan2(y, x) end
    if x == 0 then return y >= 0 and (math.pi / 2) or (-math.pi / 2) end
    local angle = math.atan(y / x)
    if x < 0 then angle = angle + math.pi end
    return angle
end

function MinimapButton:UpdatePosition()
    if not self.button or not ns.db then return end
    ns.db.settings.minimapAngle = tonumber(ns.db.settings.minimapAngle) or 220
    local angle = math.rad(ns.db.settings.minimapAngle)
    local radius = 80
    self.button:ClearAllPoints()
    self.button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

function MinimapButton:UpdateDragPosition()
    local scale = Minimap:GetEffectiveScale()
    local cursorX, cursorY = GetCursorPosition()
    local centerX, centerY = Minimap:GetCenter()
    if not centerX or not centerY then return end
    cursorX, cursorY = cursorX / scale, cursorY / scale
    ns.db.settings.minimapAngle = math.deg(angleForPoint(cursorY - centerY, cursorX - centerX))
    self:UpdatePosition()
end

function MinimapButton:Initialize()
    ns.db.settings.minimapAngle = ns.db.settings.minimapAngle or 220

    local button = CreateFrame("Button", "ForeverTeamGearMinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20); background:SetPoint("CENTER")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18); icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\Icons\\INV_Misc_GroupNeedMore")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.icon = icon

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54); border:SetPoint("TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetSize(32, 32); highlight:SetPoint("CENTER")
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    highlight:SetBlendMode("ADD")

    button:SetScript("OnClick", function(_, mouseButton)
        if button.ignoreClickUntil and GetTime() < button.ignoreClickUntil then return end
        if mouseButton == "RightButton" then
            ns:ScanAll()
            ns:RequestGroupSync()
        else
            ns:ToggleWindow()
        end
    end)
    button:SetScript("OnDragStart", function(self)
        self.dragging = true
        self:SetScript("OnUpdate", function() MinimapButton:UpdateDragPosition() end)
    end)
    button:SetScript("OnDragStop", function(self)
        self.dragging = false
        self.ignoreClickUntil = GetTime() + 0.2
        self:SetScript("OnUpdate", nil)
        MinimapButton:UpdateDragPosition()
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Forever Team Gear", 0.36, 0.78, 1)
        GameTooltip:AddLine("Left-click: Open or close", 1, 1, 1)
        GameTooltip:AddLine("Right-click: Synchronize group", 1, 1, 1)
        GameTooltip:AddLine("Drag: Move around the minimap", 0.65, 0.65, 0.65)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self.button = button
    self:UpdatePosition()
end
