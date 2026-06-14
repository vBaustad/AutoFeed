local ADDON, AF = ...

-- Lightweight minimap button (no external libs). Left-click opens settings,
-- right-click opens the welcome/create-macros window, drag moves it around the
-- minimap ring (position saved as an angle).

local RADIUS = 80
local btn

local function UpdatePosition()
    if not btn then return end
    local angle = math.rad((AF.db and AF.db.minimapAngle) or 200)
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", RADIUS * math.cos(angle), RADIUS * math.sin(angle))
end

local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    if not (mx and cx and scale and scale > 0) then return end
    local angle = math.atan2(cy / scale - my, cx / scale - mx)
    if AF.db then AF.db.minimapAngle = math.deg(angle) end
    UpdatePosition()
end

function AF:CreateMinimapButton()
    if btn then return end
    btn = CreateFrame("Button", "AutoFeedMinimapButton", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    btn:SetMovable(true)

    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Food_15")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetPoint("TOPLEFT", 7, -6)

    local overlay = btn:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")

    btn:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            if AF.ShowWelcome then AF:ShowWelcome() end
        else
            if AF.OpenOptions then AF:OpenOptions() end
        end
    end)
    btn:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", OnDragUpdate) end)
    btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cff66ccffAutoFeed|r")
        GameTooltip:AddLine("Left-click: settings", 1, 1, 1)
        GameTooltip:AddLine("Right-click: create macros", 1, 1, 1)
        GameTooltip:AddLine("Drag: move around the minimap", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    UpdatePosition()
end

function AF:ApplyMinimapButton()
    if AF.db and AF.db.minimapButton then
        if not btn then AF:CreateMinimapButton() end
        UpdatePosition()
        if btn then btn:Show() end
    elseif btn then
        btn:Hide()
    end
end
