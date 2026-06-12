-- AutoFeed options panel (Settings API with InterfaceOptions fallback).
local ADDON, AF = ...

local checks = {}

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

    local buffHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    buffHeader:SetPoint("TOPLEFT", 16, -292)
    buffHeader:SetText("Scroll buffs")

    MakeCheck(panel, "Manage the scroll-buff cycler ('" .. (AF.db and AF.db.scrollMacroName or "AutoScroll") .. "')",
        "includeScrolls", 16, -312,
        "Cycles through your Scrolls of Stamina/Strength/Agility/Intellect/Spirit/Protection, "
        .. "showing the next one whose buff you're missing. Goes blank once you're fully buffed.")

    local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btn:SetSize(140, 24)
    btn:SetPoint("TOPLEFT", 16, -352)
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
    end
    panel:SetScript("OnShow", Refresh)
    Refresh()

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
