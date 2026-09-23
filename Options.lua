-- AutoFeed's settings panel, hosted in the YippYapp window (LibForever). Same layout as every
-- YippYapp addon: title + version and one line on top, sections with headings, footer at the bottom.
-- The shared settings (minimap and launcher buttons) are on the YippYapp page in the same window.
local ADDON, AF = ...
local LIB = LibStub("LibForever-1.0", true)

local checks = {}
local macroBtns = {}

-- Two columns sized for the YippYapp window (572 px, less the scrollbar); everything flows down from TOP.
local LEFT_X, RIGHT_X, COL_W = 16, 282, 250
local PAGE_HEIGHT = 560  -- taller than the room in the window, so the lib scrolls it
local TOP = -62
local SECTION_GAP = 14

-- ---------------------------------------------------------------------------
-- Layout: a column is a cursor that moves down as things are placed
-- ---------------------------------------------------------------------------
local function Column(panel, x)
    return { panel = panel, x = x, y = TOP }
end

local function Header(col, text)
    local fs = col.panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetPoint("TOPLEFT", col.x, col.y)
    fs:SetText(text)
    col.y = col.y - 20
end

local function Hint(col, text, lines)
    local fs = col.panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    fs:SetPoint("TOPLEFT", col.x, col.y)
    fs:SetWidth(COL_W)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    col.y = col.y - (lines or 1) * 13 - 6
    return fs
end

local function Gap(col) col.y = col.y - SECTION_GAP end

-- A checkbox with its label; the tooltip says what it does in a sentence or two.
local function Check(col, label, key, tooltip, indent)
    indent = indent or 0
    local cb = CreateFrame("CheckButton", "AutoFeedCheck_" .. key, col.panel, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", col.x + indent - 4, col.y + 3)
    local fs = col.panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    fs:SetWidth(COL_W - 24 - indent)
    fs:SetText(label)

    cb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(label, 1, 1, 1)
        GameTooltip:AddLine(tooltip, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cb:SetScript("OnClick", function(self)
        if not AF.db then return end
        AF.db[key] = self:GetChecked() and true or false
        AF.lastBody, AF.bagSig = nil, nil   -- the lists depend on the settings
        AF:ScheduleUpdate()
    end)
    cb._afkey = key
    checks[#checks + 1] = cb
    col.y = col.y - 26
    return cb
end

local function Button(parent, text, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    return b
end

-- ---------------------------------------------------------------------------
-- Sections
-- ---------------------------------------------------------------------------
-- Create-macro buttons. Macros aren't auto-created (each costs a per-character macro slot),
-- so the player makes the ones they want here or on the welcome page.
local function MacrosSection(col)
    local panel = col.panel
    Header(col, "Macros")
    Hint(col, "Each one costs a character macro slot. Create the ones you want, then drag them "
        .. "from Esc > Macros onto your action bars once.", 2)

    local hasMana = (UnitPowerMax("player", 0) or 0) > 0
    local defs = {}
    for _, def in ipairs(AF.MACROS) do
        if not (def.need == "mana" and not hasMana) then defs[#defs + 1] = def end
    end
    for i, def in ipairs(defs) do
        local c, r = (i - 1) % 2, math.floor((i - 1) / 2)
        local mb = Button(panel, def.short, 123)
        mb:SetPoint("TOPLEFT", col.x + c * 127, col.y - r * 26)
        mb._def = def
        mb:SetScript("OnClick", function()
            AF:CreateMacroByKey(def.key)
            panel._refreshMacroBtns()
        end)
        macroBtns[#macroBtns + 1] = mb
    end
    col.y = col.y - math.ceil(#defs / 2) * 26

    local allBtn = Button(panel, "Create all", 123)
    allBtn:SetPoint("TOPLEFT", col.x, col.y)
    allBtn:SetScript("OnClick", function()
        AF:CreateAllMacros()
        panel._refreshMacroBtns()
    end)
    local refresh = Button(panel, "Refresh macros now", 123)
    refresh:SetPoint("LEFT", allBtn, "RIGHT", 4, 0)
    refresh:SetScript("OnClick", function() AF:RefreshNow() end)
    col.y = col.y - 26

    function panel._refreshMacroBtns()
        for _, mb in ipairs(macroBtns) do
            local name = AF.db and AF.db[mb._def.slot]
            local idx = name and GetMacroIndexByName(name)
            if idx and idx > 0 then
                mb:SetText("|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t " .. mb._def.short)
                mb:Disable()
            else
                mb:SetText(mb._def.short)
                mb:Enable()
            end
        end
    end
end

local function FoodSection(col)
    Header(col, "Food & water")
    Check(col, "Save buff food for raids", "filterBuffFood",
        "Skips food that gives Well Fed or stat bonuses and uses plain food, so buff food is saved "
        .. "for raids and dungeons. See the option below for leveling.")
    Check(col, "...except while leveling (+5% XP)", "wellFedXP",
        "On Forever, Well Fed also increases experience from kills by 5%. While you're below max level "
        .. "and not Well Fed, the food macro picks buff food (or buff drink if you have no buff food) "
        .. "until the buff is up, then goes back to plain food.", 20)
    Check(col, "Prioritize conjured food/water", "prioritizeConjured",
        "Use conjured (mage) food and water before normal items.")
    Check(col, "Water macro (mana classes)", "includeDrink",
        "Keep the '" .. AF.db.drinkMacroName .. "' macro updated with your best drink. "
        .. "Has no effect on rage/energy classes.")
    Check(col, "Food button also drinks", "oneButton",
        "Adds the drink line to the food macro so a single click eats AND drinks. "
        .. "The separate water macro stays available too.")
end

local function PotionsSection(col)
    Header(col, "Potions (usable in combat)")
    Check(col, "Healing-potion macro (" .. AF.db.healMacroName .. ")", "includeHealPot",
        "Keeps a healing-potion macro updated with your best 3 potion tiers, strongest first. "
        .. "Works mid-fight: if your top potion runs out, it falls through to the next.")
    Check(col, "Mana-potion macro (" .. AF.db.manaMacroName .. ")", "includeManaPot",
        "Same as healing potions, for mana. No effect on rage/energy classes.")
    Check(col, "Weakest potions first", "potionWeakestFirst",
        "Orders the potion macros weakest-first so small potions get drained and your "
        .. "strongest are saved for real emergencies. Unchecked = strongest first.", 20)
end

local function ScrollsSection(col)
    Header(col, "Scrolls & bandages")
    Check(col, "Scroll-buff cycler (" .. AF.db.scrollMacroName .. ")", "includeScrolls",
        "Cycles through your Scrolls of Stamina/Strength/Agility/Intellect/Spirit/Protection, "
        .. "showing the next one whose buff you're missing. Goes blank once you're fully buffed.")
    Check(col, "Bandage macro (" .. AF.db.bandageMacroName .. ")", "includeBandage",
        "Keeps a bandage macro pointed at your best bandage (with the next tier as a fallback). "
        .. "Bandages heal out of combat.")
end

-- Potions and scrolls in the bags; uncheck one and the macros never use it.
local function ExclusionsSection(col)
    local panel = col.panel
    Header(col, "Exclusions")
    local hint = Hint(col, "Uncheck an item and the macros will never use it.")

    local box = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    box:SetPoint("TOPLEFT", col.x, col.y)
    box:SetSize(COL_W, 140)
    box:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    box:SetBackdropColor(0, 0, 0, 0.6)
    box:SetBackdropBorderColor(0.4, 0.4, 0.4)
    col.y = col.y - 140

    local scroll = CreateFrame("ScrollFrame", "AutoFeedExcludeList", box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(COL_W - 40, 1)
    scroll:SetScrollChild(content)

    local KIND_TAG = {
        heal = "|cffff6060heal|r", mana = "|cff6699ffmana|r", scroll = "|cffffd100scroll|r",
    }
    local rows = {}
    function panel._renderExcludes()
        local items = AF:GetExcludables()
        for i, item in ipairs(items) do
            local row = rows[i]
            if not row then
                row = CreateFrame("Frame", nil, content)
                row:SetSize(COL_W - 42, 20)
                row.cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
                row.cb:SetSize(20, 20)
                row.cb:SetPoint("LEFT", 0, 0)
                row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.text:SetPoint("LEFT", row.cb, "RIGHT", 4, 0)
                row.text:SetPoint("RIGHT", 0, 0)
                row.text:SetJustifyH("LEFT")
                rows[i] = row
            end
            row.text:SetText(item.name .. "  " .. (KIND_TAG[item.kind] or ""))
            row.cb:SetChecked(not AF.db.blacklist[item.id])
            row.cb:SetScript("OnClick", function(self)
                AF.db.blacklist[item.id] = (not self:GetChecked()) and time() or nil
                AF.lastBody, AF.bagSig = nil, nil
                AF:ScheduleUpdate()
            end)
            row:SetPoint("TOPLEFT", 0, -(i - 1) * 22)
            row:Show()
        end
        for j = #items + 1, #rows do rows[j]:Hide() end
        content:SetHeight(math.max(1, #items * 22))
        if #items == 0 then
            hint:SetText("No potions or scrolls in your bags right now.")
        else
            hint:SetText("Uncheck an item and the macros will never use it.")
        end
    end
end

local function Footer(panel)
    local footer = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    footer:SetPoint("BOTTOMLEFT", 16, 10)
    footer:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    footer:SetJustifyH("LEFT")
    footer:SetText("|cffffd100/af|r opens these settings.  |cffffd100/af status|r shows what each macro uses.\n"
        .. "Part of YippYapp - addons for WoW: Forever that work even better together.")
end

-- ---------------------------------------------------------------------------
-- The page
-- ---------------------------------------------------------------------------
function AF:BuildOptions()
    if AF.panel then return end

    local panel = CreateFrame("Frame")
    panel.name = "AutoFeed"
    AF.panel = panel

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(("AutoFeed |cff888888v%s|r"):format(AF.version))
    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    sub:SetJustifyH("LEFT")
    sub:SetText("Self-updating macros that always point at the best food, water, potions, scrolls "
        .. "and bandages in your bags.")

    local left, right = Column(panel, LEFT_X), Column(panel, RIGHT_X)
    MacrosSection(left);  Gap(left)
    FoodSection(left);    Gap(left)
    PotionsSection(left)

    ScrollsSection(right); Gap(right)
    ExclusionsSection(right)

    Footer(panel)

    -- Fill in the values. The panel's own OnShow may never fire on a Settings canvas (it's already
    -- "shown" when Settings adopts it), so also refresh at build, from Settings' OnRefresh, and from
    -- a child's OnShow. The exclusion list walks the bags, so it waits until the page is shown.
    local function Refresh(atBuild)
        for _, cb in ipairs(checks) do
            cb:SetChecked(AF.db[cb._afkey] and true or false)
        end
        panel._refreshMacroBtns()
        if atBuild ~= true then panel._renderExcludes() end
    end
    panel.OnRefresh = Refresh
    panel:SetScript("OnShow", Refresh)
    checks[1]:HookScript("OnShow", Refresh)
    Refresh(true)   -- values now, bags later (the handlers above pass their frame, not true)

    -- Hosted in the YippYapp window: the lib gives the panel the window's width and scrolls it,
    -- since PAGE_HEIGHT is taller than the room. Without the lib, fall back to Blizzard's Options.
    local category
    if LIB and LIB.RegisterOptionsPage then
        category = LIB.RegisterOptionsPage("AutoFeed", panel, "AutoFeed", PAGE_HEIGHT)
    else
        category = Settings.RegisterCanvasLayoutCategory(panel, "AutoFeed")
        Settings.RegisterAddOnCategory(category)
    end
    AF.category = category
end

function AF:OpenOptions()
    if not (AF.panel and AF.category) then return end
    -- C_SettingsUtil.OpenSettingsPanel() (what Settings.OpenToCategory calls) is protected, so
    -- opening the panel from addon code during combat is blocked. Bail out with a note instead of
    -- throwing ADDON_ACTION_BLOCKED.
    -- Our own window (the lib hosts the page there); Settings.OpenToCategory must not be used for it.
    if LIB and LIB.OpenAddonSettings then
        LIB.OpenAddonSettings("AutoFeed")
        return
    end
    if InCombatLockdown() then
        print("|cff66ccffAutoFeed|r: settings can't be opened during combat.")
        return
    end
    Settings.OpenToCategory(AF.category:GetID())
end
