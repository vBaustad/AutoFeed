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
    -- InterfaceOptionsCheckButtonTemplate is gone on the modern client; label and tooltip by hand.
    local cb = CreateFrame("CheckButton", "AutoFeedCheck_" .. key, parent, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", x, y)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    fs:SetWidth(x < 330 and (300 - x) or 300)  -- keep the left column clear of the right one
    fs:SetText(label)

    if tooltip then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tooltip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    cb:SetScript("OnClick", function(self)
        if not AF.db then return end
        AF.db[key] = self:GetChecked() and true or false
        if key == "minimapButton" then
            if AF.ApplyMinimapButton then AF:ApplyMinimapButton() end
        else
            AF.lastBody = nil
            if AF.ScheduleUpdate then AF:ScheduleUpdate() end
        end
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

    MakeCheck(panel, "Save buff food (Well Fed / stats)",
        "filterBuffFood", 16, -80,
        "When checked, AutoFeed skips food that gives Well Fed or stat bonuses and uses plain food, "
        .. "so buff food is saved for raids and dungeons. See the option below for leveling.")

    MakeCheck(panel, "...except while leveling (+5% XP)",
        "wellFedXP", 36, -106,
        "On Forever, Well Fed also increases experience from kills by 5%. While you're below max level "
        .. "and not Well Fed, the food macro picks buff food (or buff drink if you have no buff food) "
        .. "until the buff is up, then goes back to plain food.")

    MakeCheck(panel, "Prioritize conjured food/water",
        "prioritizeConjured", 16, -136,
        "Use conjured (mage) food and water before normal items.")

    MakeCheck(panel, "Manage the water macro (mana classes)",
        "includeDrink", 16, -166,
        "Keep the '" .. (AF.db and AF.db.drinkMacroName or "AutoDrink")
        .. "' macro updated with your best drink. Has no effect on rage/energy classes.")

    MakeCheck(panel, "Food button also drinks (one click)",
        "oneButton", 16, -196,
        "Adds the drink line to the food macro so a single click eats AND drinks. "
        .. "The separate water macro stays available too.")

    local potHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    potHeader:SetPoint("TOPLEFT", 16, -232)
    potHeader:SetText("Combat potions (usable in combat)")

    MakeCheck(panel, "Healing-potion macro (" .. (AF.db and AF.db.healMacroName or "AutoHealPot") .. ")",
        "includeHealPot", 16, -252,
        "Keeps a healing-potion macro updated with your best 3 potion tiers, strongest first. "
        .. "Works mid-fight: if your top potion runs out, it falls through to the next.")

    MakeCheck(panel, "Mana-potion macro (" .. (AF.db and AF.db.manaMacroName or "AutoManaPot") .. ")",
        "includeManaPot", 16, -282,
        "Same as healing potions, for mana. No effect on rage/energy classes.")

    MakeCheck(panel, "Weakest potions first (save the strong)",
        "potionWeakestFirst", 36, -308,
        "Orders the potion macros weakest-first so small potions get drained and your "
        .. "strongest are saved for real emergencies. Unchecked = strongest first.")

    local buffHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    buffHeader:SetPoint("TOPLEFT", 16, -344)
    buffHeader:SetText("Scroll buffs")

    MakeCheck(panel, "Scroll-buff cycler (" .. (AF.db and AF.db.scrollMacroName or "AutoScroll") .. ")",
        "includeScrolls", 16, -364,
        "Cycles through your Scrolls of Stamina/Strength/Agility/Intellect/Spirit/Protection, "
        .. "showing the next one whose buff you're missing. Goes blank once you're fully buffed.")

    -- Right-column extras: bandage macro + minimap button.
    MakeCheck(panel, "Bandage macro (" .. (AF.db and AF.db.bandageMacroName or "AutoBandage") .. ")",
        "includeBandage", 330, -84,
        "Keeps a bandage macro pointed at your best bandage (with the next tier as a fallback). "
        .. "Bandages heal out of combat - great for hardcore.")
    MakeCheck(panel, "Show a minimap button",
        "minimapButton", 330, -114,
        "A button on the minimap: left-click for settings, right-click to create macros, drag to move.")

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

    -- The shared Forever launcher bar (LibForever): show AutoFeed's icon on it, and the bar's style.
    local LIB = LibStub and LibStub("LibForever-1.0", true)
    if LIB and LIB.LauncherOptions then
        local launcherHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        launcherHeader:SetPoint("TOPLEFT", 330, -404)
        launcherHeader:SetText("Launcher")
        LIB.LauncherOptions(panel, "AutoFeed"):SetPoint("TOPLEFT", 326, -422)
    end

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
    macroHeader:SetPoint("TOPLEFT", 16, -404)
    macroHeader:SetText("Create macros")
    local macroHint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    macroHint:SetPoint("TOPLEFT", 16, -422)
    macroHint:SetText("Each costs one character macro slot.")

    local hasMana = (UnitPowerMax("player", 0) or 0) > 0
    local defs = {}
    for _, def in ipairs(AF.MACROS) do
        if not (def.need == "mana" and not hasMana) then defs[#defs + 1] = def end
    end
    for i, def in ipairs(defs) do
        local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
        local mb = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        mb:SetSize(108, 22)
        mb:SetPoint("TOPLEFT", 16 + col * 112, -442 - row * 26)
        mb._def = def
        mb:SetScript("OnClick", function()
            AF:CreateMacroByKey(def.key)
            if panel._refreshMacroBtns then panel._refreshMacroBtns() end
        end)
        macroBtns[#macroBtns + 1] = mb
    end
    local afterGrid = -442 - math.ceil(#defs / 4) * 26

    local allBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    allBtn:SetSize(108, 22)
    allBtn:SetPoint("TOPLEFT", 16, afterGrid)
    allBtn:SetText("Create all")
    allBtn:SetScript("OnClick", function()
        AF:CreateAllMacros()
        if panel._refreshMacroBtns then panel._refreshMacroBtns() end
    end)

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
    btn:SetSize(140, 22)
    btn:SetPoint("TOPLEFT", 132, afterGrid)
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
        -- Do NOT overwrite category.ID with our addon name. As of 1.15.9 / 2.5.6,
        -- Settings.OpenToCategory forwards the ID straight to the C function
        -- C_SettingsUtil.OpenSettingsPanel(), which only accepts a number - a
        -- string ID throws "bad argument #1 ... outside of expected range".
        Settings.RegisterAddOnCategory(category)
        AF.category = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

function AF:OpenOptions()
    if not AF.panel then return end
    -- C_SettingsUtil.OpenSettingsPanel() (what Settings.OpenToCategory calls since
    -- 1.15.9) is protected, so opening the panel from addon code during combat is
    -- blocked. Bail out with a note instead of throwing ADDON_ACTION_BLOCKED.
    if InCombatLockdown() then
        print("|cff66ccffAutoFeed|r: settings can't be opened during combat.")
        return
    end
    if Settings and Settings.OpenToCategory and AF.category then
        local id = AF.category.GetID and AF.category:GetID() or AF.category.ID
        Settings.OpenToCategory(id)
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(AF.panel)
        InterfaceOptionsFrame_OpenToCategory(AF.panel) -- twice: known Blizzard quirk
    end
end
