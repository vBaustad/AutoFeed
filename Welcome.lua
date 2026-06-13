local ADDON, AF = ...

-- First-login welcome window. Explains AutoFeed and lets the player create only
-- the macros they want - each costs one per-character macro slot, so we no longer
-- auto-create them. Reopen any time with /autofeed welcome.

local function MacroExists(name)
    local idx = name and GetMacroIndexByName(name)
    return idx and idx > 0
end

function AF:ShowWelcome()
    if AF.welcomeFrame then
        if AF.welcomeFrame.Refresh then AF.welcomeFrame:Refresh() end
        AF.welcomeFrame:Show()
        return
    end

    local w = CreateFrame("Frame", "AutoFeedWelcome", UIParent, "BackdropTemplate")
    w:SetSize(440, 120)  -- height set after rows lay out
    w:SetPoint("CENTER", 0, 140)
    w:SetFrameStrata("DIALOG")
    w:SetClampedToScreen(true)
    w:EnableMouse(true)
    w:SetMovable(true)
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", function(self) self:StartMoving() end)
    w:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    w:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    w:SetBackdropColor(0, 0, 0, 0.92)
    w:SetBackdropBorderColor(0.3, 0.5, 0.85, 1)
    tinsert(UISpecialFrames, "AutoFeedWelcome")  -- Escape closes
    AF.welcomeFrame = w

    local icon = w:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28)
    icon:SetPoint("TOPLEFT", 14, -12)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Food_15")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local title = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 10, 0)
    title:SetText("|cff66ccffWelcome to AutoFeed|r")

    local close = CreateFrame("Button", nil, w, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() w:Hide() end)

    local body = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    body:SetPoint("TOPLEFT", 16, -50)
    body:SetWidth(408); body:SetJustifyH("LEFT"); body:SetSpacing(3)
    body:SetText("Self-updating macros that always point at the best consumable in your "
        .. "bags - eat, drink, pot, and buff from one button each.\n\n"
        .. "Each macro uses |cffffd100one character macro slot|r, so create only the ones "
        .. "you'll use. Click Create, then drag the macro from |cffffd100Esc > Macros|r onto "
        .. "your action bars (one time).")

    local DESC = {
        food   = "Eat the best food",
        drink  = "Drink the best water",
        heal   = "Best healing potion (combat-safe)",
        mana   = "Best mana potion (combat-safe)",
        scroll = "Next scroll buff you're missing",
    }
    local hasMana = (UnitPowerMax("player", 0) or 0) > 0

    local bodyH = body:GetStringHeight() or 80
    local y = -50 - bodyH - 14
    local rows = {}
    for _, m in ipairs(AF.MACROS) do
        if not (m.need == "mana" and not hasMana) then
            local name = AF.db[m.slot]
            local label = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            label:SetPoint("TOPLEFT", 22, y)
            label:SetWidth(300); label:SetJustifyH("LEFT")
            label:SetText("|cffffd100" .. name .. "|r  - " .. (DESC[m.key] or m.short))

            local btn = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
            btn:SetSize(96, 22)
            btn:SetPoint("TOPRIGHT", -16, y + 4)
            btn._name = name
            btn._key = m.key
            btn:SetScript("OnClick", function(self)
                AF:CreateMacroByKey(self._key)
                if w.Refresh then w:Refresh() end
            end)
            rows[#rows + 1] = btn
            y = y - 28
        end
    end

    local note = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", 18, y - 4)
    note:SetWidth(404); note:SetJustifyH("LEFT")
    note:SetText("|cff999999AutoFeed is still in active development - if anything doesn't work as "
        .. "intended, please report it on the CurseForge or GitHub page. Thanks for testing!|r")
    local noteH = note:GetStringHeight() or 28

    local settingsBtn = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    settingsBtn:SetSize(110, 22)
    settingsBtn:SetPoint("BOTTOMLEFT", 16, 14)
    settingsBtn:SetText("Open Settings")
    settingsBtn:SetScript("OnClick", function()
        w:Hide()
        if AF.OpenOptions then AF:OpenOptions() end
    end)

    local okBtn = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    okBtn:SetSize(90, 22)
    okBtn:SetPoint("BOTTOMRIGHT", -16, 14)
    okBtn:SetText("Got it")
    okBtn:SetScript("OnClick", function() w:Hide() end)

    function w:Refresh()
        for _, btn in ipairs(rows) do
            if MacroExists(btn._name) then
                btn:SetText("Created"); btn:Disable()
            else
                btn:SetText("Create"); btn:Enable()
            end
        end
    end

    w:SetHeight(-(y - 4) + noteH + 48)
    w:Refresh()
end
