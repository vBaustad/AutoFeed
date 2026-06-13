-- AutoFeed options panel (Settings API with InterfaceOptions fallback).
local ADDON, AF = ...

local checks = {}
local macroBtns = {}

-- "Buy me a coffee" support link. WoW can't open a browser, so clicking pops
-- a dialog with the URL pre-selected for copying.
local BMC_URL = "buymeacoffee.com/vbaustad"
StaticPopupDialogs["AUTOFEED_BMC"] = {
    text = "Thanks for using AutoFeed!\nCopy the link below if you'd like to buy me a coffee.",
    button1 = CLOSE,
    hasEditBox = true,
    editBoxWidth = 260,
    OnShow = function(self)
        local eb = self.EditBox or self.editBox  -- field name differs across client builds
        if not eb then return end
        eb:SetText(BMC_URL)
        eb:HighlightText()
        eb:SetFocus()
    end,
    EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local function AddCoffeeButton(panel)
    local btn = CreateFrame("Button", nil, panel)
    btn:SetSize(26, 26)
    btn:SetPoint("BOTTOMLEFT", 16, 14)
    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture("Interface\\AddOns\\AutoFeed\\bmc-logo")
    tex:SetAlpha(0.65)
    local label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", btn, "RIGHT", 6, 0)
    label:SetText("|cff888888if you want to support|r")
    btn:SetScript("OnEnter", function(self)
        tex:SetAlpha(1)
        label:SetText("|cffffc840if you want to support|r")
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Buy me a coffee", 1, 0.85, 0.2)
        GameTooltip:AddLine(BMC_URL, 0.7, 0.7, 0.7)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click to copy the link.", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        tex:SetAlpha(0.65)
        label:SetText("|cff888888if you want to support|r")
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", function() StaticPopup_Show("AUTOFEED_BMC") end)
end

local function MakeCheck(parent, label, key, x, y, tooltip)
    local cb = CreateFrame("CheckButton", "AutoFeedCheck_" .. key, parent,
        "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    local fs = _G[cb:GetName() .. "Text"]
    if fs then fs:SetText(label) end

    cb.tooltipText = tooltip
    cb:SetScript("OnClick", function(self)
        if not AF.db then return end
        AF.db[key] = self:GetChecked() and true or false
        AF.lastBody = nil
        if AF.ScheduleUpdate then AF:ScheduleUpdate() end
    end)
    cb._afkey = key
    checks[#checks + 1] = cb
    return cb
end

function AF:BuildOptions()
    if AF.panel then return end

    local panel = CreateFrame("Frame")
    panel.name = "AutoFeed"
    AF.panel = panel

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("AutoFeed")

    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    sub:SetWidth(560)
    sub:SetJustifyH("LEFT")
    sub:SetText("Keeps two macros pointed at the best food/water in your bags: '"
        .. (AF.db and AF.db.macroName or "AutoFeed") .. "' (food) and '"
        .. (AF.db and AF.db.drinkMacroName or "AutoDrink")
        .. "' (water). Drag them from Esc > Macros onto your action bars once.")

    MakeCheck(panel, "Ignore food/drink that grants buffs/stats (Well Fed)",
        "filterBuffFood", 16, -80,
        "When checked, AutoFeed skips food that gives Well Fed or stat bonuses and uses plain food only.")

    MakeCheck(panel, "Prioritize conjured food/water",
        "prioritizeConjured", 16, -110,
        "Use conjured (mage) food and water before normal items.")

    MakeCheck(panel, "Manage the water macro (mana classes)",
        "includeDrink", 16, -140,
        "Keep the '" .. (AF.db and AF.db.drinkMacroName or "AutoDrink")
        .. "' macro updated with your best drink. Has no effect on rage/energy classes.")

    MakeCheck(panel, "Combine: make the food button also drink (one click does both)",
        "oneButton", 16, -170,
        "Adds the drink line to the food macro so a single click eats AND drinks. "
        .. "The separate water macro stays available too.")

    local potHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    potHeader:SetPoint("TOPLEFT", 16, -206)
    potHeader:SetText("Combat potions (usable in combat)")

    MakeCheck(panel, "Manage the healing-potion macro ('" .. (AF.db and AF.db.healMacroName or "AutoHealPot") .. "')",
        "includeHealPot", 16, -226,
        "Keeps a healing-potion macro updated with your best 3 potion tiers, strongest first. "
        .. "Works mid-fight: if your top potion runs out, it falls through to the next.")

    MakeCheck(panel, "Manage the mana-potion macro ('" .. (AF.db and AF.db.manaMacroName or "AutoManaPot") .. "')",
        "includeManaPot", 16, -256,
        "Same as healing potions, for mana. No effect on rage/energy classes.")

    MakeCheck(panel, "Use weakest potions first (save the strong ones)",
        "potionWeakestFirst", 36, -282,
        "Orders the potion macros weakest-first so small potions get drained and your "
        .. "strongest are saved for real emergencies. Unchecked = strongest first.")

    local buffHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    buffHeader:SetPoint("TOPLEFT", 16, -318)
    buffHeader:SetText("Scroll buffs")

    MakeCheck(panel, "Manage the scroll-buff cycler ('" .. (AF.db and AF.db.scrollMacroName or "AutoScroll") .. "')",
        "includeScrolls", 16, -338,
        "Cycles through your Scrolls of Stamina/Strength/Agility/Intellect/Spirit/Protection, "
        .. "showing the next one whose buff you're missing. Goes blank once you're fully buffed.")

    -- Exclude list (right column): potions and scrolls in bags, uncheck to skip.
    local exLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    exLabel:SetPoint("TOPLEFT", 330, -206)
    exLabel:SetText("Potions & scrolls in your bags:")

    local exHint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    exHint:SetPoint("TOPLEFT", 330, -224)
    exHint:SetText("Uncheck an item and the macros will never use it.")

    local exBox = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    exBox:SetPoint("TOPLEFT", 330, -242)
    exBox:SetSize(260, 150)
    exBox:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    exBox:SetBackdropColor(0, 0, 0, 0.6)
    exBox:SetBackdropBorderColor(0.4, 0.4, 0.4)

    local exScroll = CreateFrame("ScrollFrame", "AutoFeedExcludeList", exBox, "UIPanelScrollFrameTemplate")
    exScroll:SetPoint("TOPLEFT", 6, -6)
    exScroll:SetPoint("BOTTOMRIGHT", -26, 6)
    local exContent = CreateFrame("Frame", nil, exScroll)
    exContent:SetSize(220, 1)
    exScroll:SetScrollChild(exContent)

    local KIND_TAG = {
        heal = "|cffff6060heal|r", mana = "|cff6699ffmana|r", scroll = "|cffffd100scroll|r",
    }
    local exRows = {}
    local function RenderExcludes()
        if not (AF.db and AF.GetExcludables) then return end
        local items = AF:GetExcludables()
        for i, item in ipairs(items) do
            local row = exRows[i]
            if not row then
                row = CreateFrame("Frame", nil, exContent)
                row:SetSize(218, 20)
                row.cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
                row.cb:SetSize(20, 20)
                row.cb:SetPoint("LEFT", 0, 0)
                row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.text:SetPoint("LEFT", row.cb, "RIGHT", 4, 0)
                row.text:SetPoint("RIGHT", 0, 0)
                row.text:SetJustifyH("LEFT")
                exRows[i] = row
            end
            row.text:SetText(item.name .. "  " .. (KIND_TAG[item.kind] or ""))
            row.cb:SetChecked(not AF.db.blacklist[item.id])
            row.cb:SetScript("OnClick", function(self)
                AF.db.blacklist[item.id] = (not self:GetChecked()) and true or nil
                AF.lastBody = nil
                if AF.ScheduleUpdate then AF:ScheduleUpdate() end
            end)
            row:SetPoint("TOPLEFT", 0, -(i - 1) * 22)
            row:Show()
        end
        for j = #items + 1, #exRows do exRows[j]:Hide() end
        exContent:SetHeight(math.max(1, #items * 22))
        if #items == 0 then
            exHint:SetText("|cff888888(no potions or scrolls in your bags right now)|r")
        else
            exHint:SetText("Uncheck an item and the macros will never use it.")
        end
    end
    panel._renderExcludes = RenderExcludes

    -- Create-macro buttons. Macros aren't auto-created (each costs a per-character
    -- macro slot), so the player makes the ones they want here or in the welcome.
    local macroHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    macroHeader:SetPoint("TOPLEFT", 16, -366)
    macroHeader:SetText("Create macros")
    local macroHint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    macroHint:SetPoint("TOPLEFT", 16, -384)
    macroHint:SetText("Each costs one character macro slot.")

    local hasMana = (UnitPowerMax("player", 0) or 0) > 0
    local mx = 16
    for _, def in ipairs(AF.MACROS) do
        if not (def.need == "mana" and not hasMana) then
            local mb = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
            mb:SetSize(110, 22)
            mb:SetPoint("TOPLEFT", mx, -404)
            mb._def = def
            mb:SetScript("OnClick", function()
                AF:CreateMacroByKey(def.key)
                if panel._refreshMacroBtns then panel._refreshMacroBtns() end
            end)
            macroBtns[#macroBtns + 1] = mb
            mx = mx + 114
        end
    end

    local function RefreshMacroBtns()
        for _, mb in ipairs(macroBtns) do
            local name = AF.db and AF.db[mb._def.slot]
            local idx = name and GetMacroIndexByName(name)
            if idx and idx > 0 then
                mb:SetText(mb._def.short .. " (made)")
                mb:Disable()
            else
                mb:SetText("Make " .. mb._def.short)
                mb:Enable()
            end
        end
    end
    panel._refreshMacroBtns = RefreshMacroBtns

    local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btn:SetSize(140, 24)
    btn:SetPoint("TOPLEFT", 16, -436)
    btn:SetText("Refresh macro now")
    btn:SetScript("OnClick", function()
        AF.lastBody = nil
        AF:UpdateMacro()
        print("|cff66ccffAutoFeed|r: macro refreshed.")
    end)

    local function Refresh()
        if not AF.db then return end
        for _, cb in ipairs(checks) do
            cb:SetChecked(AF.db[cb._afkey] and true or false)
        end
        sub:SetText("Keeps two macros pointed at the best food/water in your bags: '"
            .. AF.db.macroName .. "' (food) and '" .. AF.db.drinkMacroName
            .. "' (water). Drag them from Esc > Macros onto your action bars once.")
        if panel._renderExcludes then panel._renderExcludes() end
        if panel._refreshMacroBtns then panel._refreshMacroBtns() end
    end
    panel:SetScript("OnShow", Refresh)
    Refresh()

    AddCoffeeButton(panel)

    -- Register with the Settings API (Classic 1.15) or legacy InterfaceOptions.
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, "AutoFeed")
        category.ID = "AutoFeed"
        Settings.RegisterAddOnCategory(category)
        AF.category = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

function AF:OpenOptions()
    if not AF.panel then return end
    if Settings and Settings.OpenToCategory and AF.category then
        Settings.OpenToCategory(AF.category.ID)
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(AF.panel)
        InterfaceOptionsFrame_OpenToCategory(AF.panel) -- twice: known Blizzard quirk
    end
end
