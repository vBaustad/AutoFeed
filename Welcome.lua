local ADDON, AF = ...

-- AutoFeed's page in the shared YippYapp welcome window (LibForever). The window brings the frame,
-- heading and Done button; this file only draws the page: what AutoFeed does and a Create button per
-- macro. It opens by itself while no AutoFeed macro exists yet. Reopen with /autofeed welcome.
local LIB = LibStub("LibForever-1.0", true)

local function MacroExists(name)
    local idx = name and GetMacroIndexByName(name)
    return idx and idx > 0
end

function AF:AnyMacroExists()
    for _, m in ipairs(AF.MACROS) do
        if MacroExists(AF.db[m.slot]) then return true end
    end
    return false
end

local DESC = {
    food    = "Eat the best food",
    drink   = "Drink the best water",
    heal    = "Best healing potion (combat-safe)",
    mana    = "Best mana potion (combat-safe)",
    scroll  = "Next scroll buff you're missing",
    bandage = "Use your best bandage",
}

function AF:BuildWelcomePage(page)
    local width = page:GetWidth()

    local body = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("TOPLEFT", 0, 0)
    body:SetWidth(width)
    body:SetJustifyH("LEFT")
    body:SetSpacing(3)
    body:SetText("Self-updating macros that always point at the best consumable in your bags. "
        .. "Each one uses |cffffd100one character macro slot|r, so create only the ones you'll use, "
        .. "then drag them from |cffffd100Esc > Macros|r onto your action bars (one time).")

    local hasMana = (UnitPowerMax("player", 0) or 0) > 0
    local top = -(body:GetStringHeight() + 16)
    local colW = math.floor(width / 2)
    local rows, i = {}, 0
    for _, m in ipairs(AF.MACROS) do
        if not (m.need == "mana" and not hasMana) then
            local x, y = (i % 2) * colW, top - math.floor(i / 2) * 42
            local name = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            name:SetPoint("TOPLEFT", x, y)
            name:SetText(AF.db[m.slot])
            local desc = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            desc:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
            desc:SetText(DESC[m.key] or m.short)

            local btn = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
            btn:SetSize(84, 22)
            btn:SetPoint("TOPRIGHT", page, "TOPLEFT", x + colW - 16, y - 4)
            btn._name, btn._key = AF.db[m.slot], m.key
            btn:SetScript("OnClick", function(self)
                AF:CreateMacroByKey(self._key)
                page:Refresh()
            end)
            rows[#rows + 1] = btn
            i = i + 1
        end
    end

    local bottom = top - math.ceil(i / 2) * 42 - 6
    local allBtn = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    allBtn:SetSize(110, 22)
    allBtn:SetPoint("TOPLEFT", 0, bottom)
    allBtn:SetText("Create all")
    allBtn:SetScript("OnClick", function()
        AF:CreateAllMacros()
        page:Refresh()
    end)

    local settingsBtn = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    settingsBtn:SetSize(110, 22)
    settingsBtn:SetPoint("LEFT", allBtn, "RIGHT", 8, 0)
    settingsBtn:SetText("Open Settings")
    settingsBtn:SetScript("OnClick", function() AF:OpenOptions() end)

    function page:Refresh()
        for _, btn in ipairs(rows) do
            if MacroExists(btn._name) then
                btn:SetText("Created"); btn:Disable()
            else
                btn:SetText("Create"); btn:Enable()
            end
        end
    end
    page:Refresh()
end

function AF:ShowWelcome()
    if LIB then LIB.OpenWelcome("AutoFeed") end
end

function AF:RegisterWelcome()
    if not LIB then return end
    -- Macros are per character, so "seen" is too (AutoFeedCharDB): a fresh alt with no macros
    -- still gets the setup page.
    AutoFeedCharDB = AutoFeedCharDB or {}
    -- The old AutoFeed-only window kept an account-wide flag: count it as seen on this character
    -- only, then drop it (and the account-wide seen table from 1.4.0 test builds).
    if AF.db.welcomed then
        AutoFeedCharDB.welcomeSeen = AutoFeedCharDB.welcomeSeen or {}
        AutoFeedCharDB.welcomeSeen.AutoFeed = AutoFeedCharDB.welcomeSeen.AutoFeed or 1
        AF.db.welcomed = nil
    end
    AF.db.welcomeSeen = nil
    LIB.RegisterWelcome({
        id = "AutoFeed", title = "AutoFeed", icon = "Interface\\AddOns\\AutoFeed\\Media\\icon", version = 1,
        subtitle = "Self-updating macros for your best food, water and potions.",
        needsSetup = function() return not AF:AnyMacroExists() end,
        build = function(page) AF:BuildWelcomePage(page) end,
        onShow = function(page) if page.Refresh then page:Refresh() end end,
        launcher = "AutoFeed", order = 40,  -- same as the launcher entry, so tabs follow the bar
    }, AutoFeedCharDB)
end
