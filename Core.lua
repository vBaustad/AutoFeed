-- AutoFeed: keeps a single macro pointed at the best food/drink in your bags.
-- Classic Era 1.15.x. Shares the private table `AF` across files via the addon vararg.
local ADDON, AF = ...

AF.version = "1.0.0"

-- The dynamic "?" macro icon. With #showtooltip this auto-shows the item's icon.
local DYNAMIC_ICON = 134400

-- ---------------------------------------------------------------------------
-- Defaults / saved variables
-- ---------------------------------------------------------------------------
local defaults = {
    filterBuffFood     = true,   -- ignore food/drink that grants Well Fed / stat buffs
    prioritizeConjured = true,   -- put conjured (mage) food/water first
    includeDrink       = true,   -- manage the water macro (only matters for mana classes)
    oneButton          = false,  -- if true, the food macro also drinks (one click does both)
    includeHealPot     = true,   -- manage the healing-potion macro
    includeManaPot     = true,   -- manage the mana-potion macro (only matters for mana classes)
    includeScrolls     = true,   -- manage the scroll-buff cycler macro
    macroName          = "AutoFeed",
    drinkMacroName     = "AutoDrink",
    healMacroName      = "AutoHealPot",
    manaMacroName      = "AutoManaPot",
    scrollMacroName    = "AutoScroll",
    blacklist          = {},     -- [itemID] = true, never use these
}

local function ApplyDefaults()
    AutoFeedDB = AutoFeedDB or {}
    for k, v in pairs(defaults) do
        if AutoFeedDB[k] == nil then
            if type(v) == "table" then
                AutoFeedDB[k] = {}
            else
                AutoFeedDB[k] = v
            end
        end
    end
    AF.db = AutoFeedDB
end

-- ---------------------------------------------------------------------------
-- Tooltip reading (locale: tuned for enUS health/mana strings)
-- ---------------------------------------------------------------------------
local function GetTooltipLines(bag, slot)
    local lines = {}
    if C_TooltipInfo and C_TooltipInfo.GetBagItem then
        local data = C_TooltipInfo.GetBagItem(bag, slot)
        if data and data.lines then
            for _, line in ipairs(data.lines) do
                if TooltipUtil and TooltipUtil.SurfaceArgs then
                    TooltipUtil.SurfaceArgs(line)
                end
                if line.leftText then
                    lines[#lines + 1] = line.leftText
                end
            end
        end
        if #lines > 0 then return lines end -- else fall through to scanning tooltip
    end

    -- Fallback: hidden scanning tooltip
    if not AF.scanTip then
        AF.scanTip = CreateFrame("GameTooltip", "AutoFeedScanTip", nil, "GameTooltipTemplate")
        AF.scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    AF.scanTip:ClearLines()
    AF.scanTip:SetBagItem(bag, slot)
    for i = 1, AF.scanTip:NumLines() do
        local fs = _G["AutoFeedScanTipTextLeft" .. i]
        local t = fs and fs:GetText()
        if t then lines[#lines + 1] = t end
    end
    return lines
end

-- ---------------------------------------------------------------------------
-- Classify a single bag slot -> consumable info table or nil
-- ---------------------------------------------------------------------------
local function num(s) return tonumber((s:gsub(",", ""))) end

-- Reads a "Restores N <resource>" or "Restores N to M <resource>" amount.
-- Potions use ranges (instant); food/drink use a single number (over time).
local function ParseRestore(t, resource)
    local lo, hi = t:match("restores%s+([%d,]+)%s+to%s+([%d,]+)%s+" .. resource)
    if lo and hi then return (num(lo) + num(hi)) / 2 end
    local n = t:match("restores%s+([%d,]+)%s+" .. resource)
    if n then return num(n) end
    return nil
end

-- An item's tooltip never changes for a given itemID, so parse it once and
-- cache the static classification. false = "not a consumable we care about".
-- Bounded by distinct items seen in bags - tiny.
local classifyCache = {}

local function Classify(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info or not info.itemID then return nil end

    local itemID = info.itemID
    if AF.db.blacklist[itemID] then return nil end

    local cached = classifyCache[itemID]
    if cached == false then return nil end
    if cached then
        return {
            id       = itemID,
            name     = cached.name,
            count    = info.stackCount or 1,
            reqLevel = cached.reqLevel,
            buff     = cached.buff,
            conjured = cached.conjured,
            health   = cached.health,
            mana     = cached.mana,
            kind     = cached.kind,
        }
    end

    -- Gate on Consumable (classID 0). Classic reports food as several different
    -- subclasses, so we don't trust the subclass number -- we classify food vs
    -- potion from the tooltip wording below ("restores X over N sec" = food).
    local _, _, _, _, _, classID, subClassID = GetItemInfoInstant(itemID)
    if classID ~= 0 then classifyCache[itemID] = false; return nil end

    local itemName = GetItemInfo(itemID)
    local loaded = itemName ~= nil
    if not itemName then
        -- not cached yet; ask for it and skip this pass
        if C_Item and C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(itemID)
        end
        itemName = (info.hyperlink and info.hyperlink:match("%[(.-)%]")) or ("item:" .. itemID)
    end
    local lname = itemName:lower()

    local lines = GetTooltipLines(bag, slot)
    -- Only cache verdicts based on fully-loaded data, so slow-loading items
    -- get re-examined next scan instead of being misclassified forever.
    local cacheable = loaded and #lines > 0

    local health, mana, reqLevel, buff, overTime = 0, 0, 0, false, false
    for _, raw in ipairs(lines) do
        local t = raw:lower()
        local h = ParseRestore(t, "health")
        if h then health = h; if t:find("over%s+%d") then overTime = true end end
        local m = ParseRestore(t, "mana")
        if m then mana = m; if t:find("over%s+%d") then overTime = true end end
        local rl = t:match("requires level%s+(%d+)")
        if rl then reqLevel = tonumber(rl) or reqLevel end
        if t:find("well fed") then buff = true end
    end

    if health == 0 and mana == 0 then
        if cacheable then classifyCache[itemID] = false end
        return nil
    end

    -- Food/drink restores over time; potions are instant. Use the subclass when
    -- it's the well-known value, otherwise fall back to the "over time" wording.
    local kind
    if subClassID == 5 then
        kind = "food"
    elseif subClassID == 1 then
        kind = "potion"
    elseif overTime then
        kind = "food"
    else
        kind = "potion"
    end

    -- Avoid grabbing Healthstones / mana gems as "potions": they have a separate
    -- cooldown and would double-fire in the fallback list. Real potions are
    -- subclass 1 or literally contain "Potion" in the name (enUS).
    if kind == "potion" and subClassID ~= 1 and not lname:find("potion") then
        if cacheable then classifyCache[itemID] = false end
        return nil
    end

    local conjured = (lname:find("conjured") ~= nil)
    if cacheable then
        classifyCache[itemID] = {
            name = itemName, reqLevel = reqLevel, buff = buff, conjured = conjured,
            health = health, mana = mana, kind = kind,
        }
    end

    return {
        id       = itemID,
        name     = itemName,
        count    = info.stackCount or 1,
        reqLevel = reqLevel,
        buff     = buff,
        conjured = conjured,
        health   = health,
        mana     = mana,
        kind     = kind,
    }
end

-- ---------------------------------------------------------------------------
-- Scan all bags -> filtered + unfiltered candidate lists
-- ---------------------------------------------------------------------------
local function ScanBags()
    local level = UnitLevel("player")
    local foods, foodsAll, drinks, drinksAll = {}, {}, {}, {}
    local healPots, manaPots = {}, {}

    for bag = 0, 4 do
        local slots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, slots do
            local c = Classify(bag, slot)
            if c and c.reqLevel <= level then
                if c.kind == "food" then
                    if c.health > 0 then
                        foodsAll[#foodsAll + 1] = c
                        if not (AF.db.filterBuffFood and c.buff) then
                            foods[#foods + 1] = c
                        end
                    end
                    if c.mana > 0 then
                        drinksAll[#drinksAll + 1] = c
                        if not (AF.db.filterBuffFood and c.buff) then
                            drinks[#drinks + 1] = c
                        end
                    end
                elseif c.kind == "potion" then
                    if c.health > 0 then healPots[#healPots + 1] = c end
                    if c.mana > 0 then manaPots[#manaPots + 1] = c end
                end
            end
        end
    end

    return foods, foodsAll, drinks, drinksAll, healPots, manaPots
end

-- Pick the best candidate: conjured-first (optional), then strongest restore,
-- then smallest stack (to drain partial stacks).
local function Pick(list, key)
    if not list or #list == 0 then return nil end
    local sorted = {}
    for i = 1, #list do sorted[i] = list[i] end
    table.sort(sorted, function(a, b)
        if AF.db.prioritizeConjured and a.conjured ~= b.conjured then
            return a.conjured
        end
        if a[key] ~= b[key] then
            return a[key] > b[key]
        end
        return a.count < b.count
    end)
    return sorted[1]
end

-- Returns up to n distinct items, strongest first (for combat-potion fallback
-- lists). Ignores conjured priority — potions are ranked purely by strength.
local function PickTop(list, key, n)
    if not list or #list == 0 then return {} end
    local sorted = {}
    for i = 1, #list do sorted[i] = list[i] end
    table.sort(sorted, function(a, b)
        if a[key] ~= b[key] then return a[key] > b[key] end
        return a.count < b.count
    end)
    local out, seen = {}, {}
    for _, c in ipairs(sorted) do
        if not seen[c.id] then
            seen[c.id] = true
            out[#out + 1] = c
            if #out >= n then break end
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Scroll buffs: cycle through scrolls for buffs you don't have yet
-- ---------------------------------------------------------------------------
local SCROLL_STATS = { "Stamina", "Strength", "Agility", "Intellect", "Spirit", "Protection" }
local STAT_SET = {}
for _, s in ipairs(SCROLL_STATS) do STAT_SET[s] = true end

local ROMAN = { I = 1, II = 2, III = 3, IV = 4, V = 5, VI = 6 }
local function ParseRank(name)
    local r = name:match("%s([IVX]+)$")
    return (r and ROMAN[r]) or 1
end

local function HasBuff(buffName)
    if AuraUtil and AuraUtil.FindAuraByName then
        return AuraUtil.FindAuraByName(buffName, "player", "HELPFUL") ~= nil
    end
    for i = 1, 40 do
        local n = UnitBuff("player", i)
        if not n then break end
        if n == buffName then return true end
    end
    return false
end

-- Best (highest-rank) scroll per stat that's in your bags.
local function ScanScrolls()
    local found = {}
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local name = GetItemInfo(info.itemID)
                local stat = name and name:match("^Scroll of (%a+)")
                if stat and STAT_SET[stat] then
                    local rank = ParseRank(name)
                    if not found[stat] or rank > found[stat].rank then
                        found[stat] = { id = info.itemID, rank = rank, name = name, stat = stat }
                    end
                end
            end
        end
    end
    return found
end

-- The next scroll whose buff you're missing (in stat order); nil if fully buffed.
local function PickScroll()
    local found = ScanScrolls()
    for _, stat in ipairs(SCROLL_STATS) do
        local s = found[stat]
        if s and not HasBuff(stat) then return s end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Macro writing
-- ---------------------------------------------------------------------------
-- Writes one macro by name, skipping the call if the body is unchanged.
function AF:WriteMacro(name, body)
    self.lastBody = self.lastBody or {}
    local idx = GetMacroIndexByName(name)
    -- Skip only if unchanged AND the macro still exists (the user may have
    -- deleted it manually; recreate it in that case).
    if self.lastBody[name] == body and idx and idx > 0 then return end
    self.lastBody[name] = body

    if idx and idx > 0 then
        pcall(EditMacro, idx, name, DYNAMIC_ICON, body)
    else
        local ok = pcall(CreateMacro, name, DYNAMIC_ICON, body, true) -- true = per-character
        if not ok then
            self.lastBody[name] = nil
            print("|cff66ccffAutoFeed|r: couldn't create macro '" .. name
                .. "' (per-character macro slots full?). Free a slot, then type /autofeed update.")
        end
    end
end

function AF:UpdateMacro()
    if not self.db then return end
    if InCombatLockdown() then
        self.pending = true
        return
    end
    self.pending = nil

    local foods, foodsAll, drinks, drinksAll, healPots, manaPots = ScanBags()
    local food = Pick(#foods > 0 and foods or foodsAll, "health")

    local drink
    local hasMana = (UnitPowerMax("player", 0) or 0) > 0
    if self.db.includeDrink and hasMana then
        drink = Pick(#drinks > 0 and drinks or drinksAll, "mana")
    end

    -- Food macro: food, plus the drink line too when one-button mode is on.
    local foodBody = { "#showtooltip" }
    if food then
        foodBody[#foodBody + 1] = "/use item:" .. food.id
    end
    if self.db.oneButton and drink and (not food or drink.id ~= food.id) then
        foodBody[#foodBody + 1] = "/use item:" .. drink.id
    end
    if #foodBody == 1 then
        foodBody[#foodBody + 1] = '/run print("|cff66ccffAutoFeed|r: no usable food in bags")'
    end
    self:WriteMacro(self.db.macroName, table.concat(foodBody, "\n"))

    -- Water macro: drink only. Only managed for mana classes with drink enabled.
    if self.db.includeDrink and hasMana then
        local drinkBody = { "#showtooltip" }
        if drink then
            drinkBody[#drinkBody + 1] = "/use item:" .. drink.id
        else
            drinkBody[#drinkBody + 1] = '/run print("|cff66ccffAutoFeed|r: no usable water in bags")'
        end
        self:WriteMacro(self.db.drinkMacroName, table.concat(drinkBody, "\n"))
    end

    -- Healing-potion macro: best-first fallback list (usable in combat).
    if self.db.includeHealPot then
        local top = PickTop(healPots, "health", 3)
        local body = { "#showtooltip" }
        for _, p in ipairs(top) do
            body[#body + 1] = "/use item:" .. p.id
        end
        if #body == 1 then
            body[#body + 1] = '/run print("|cff66ccffAutoFeed|r: no healing potion in bags")'
        end
        self:WriteMacro(self.db.healMacroName, table.concat(body, "\n"))
        self.lastHealPot = top[1]
    end

    -- Mana-potion macro: best-first fallback list (mana classes only).
    if self.db.includeManaPot and hasMana then
        local top = PickTop(manaPots, "mana", 3)
        local body = { "#showtooltip" }
        for _, p in ipairs(top) do
            body[#body + 1] = "/use item:" .. p.id
        end
        if #body == 1 then
            body[#body + 1] = '/run print("|cff66ccffAutoFeed|r: no mana potion in bags")'
        end
        self:WriteMacro(self.db.manaMacroName, table.concat(body, "\n"))
        self.lastManaPot = top[1]
    end

    -- Scroll-buff cycler: next scroll whose buff you lack; blank once fully buffed.
    if self.db.includeScrolls then
        local scroll = PickScroll()
        local body = { "#showtooltip" }
        if scroll then
            body[#body + 1] = "/use [@player] item:" .. scroll.id  -- always buff yourself
        else
            body[#body + 1] = '/run print("|cff66ccffAutoFeed|r: all scroll buffs active (or none in bags)")'
        end
        self:WriteMacro(self.db.scrollMacroName, table.concat(body, "\n"))
        self.lastScroll = scroll
    end

    self.lastFood, self.lastDrink = food, drink
end

-- Debounced update (bag events can fire in bursts)
function AF:ScheduleUpdate()
    if self.timer then return end
    self.timer = C_Timer.NewTimer(0.4, function()
        AF.timer = nil
        AF:UpdateMacro()
    end)
end

-- ---------------------------------------------------------------------------
-- Slash command
-- ---------------------------------------------------------------------------
SLASH_AUTOFEED1 = "/autofeed"
SLASH_AUTOFEED2 = "/af"
SlashCmdList.AUTOFEED = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "update" or msg == "refresh" then
        AF.lastBody = nil
        AF:UpdateMacro()
        print("|cff66ccffAutoFeed|r: macro refreshed.")
    elseif msg == "status" then
        local function lbl(c) return c and (c.name .. " x" .. c.count) or "none" end
        print("|cff66ccffAutoFeed|r food: " .. lbl(AF.lastFood) .. "  |  water: " .. lbl(AF.lastDrink))
        print("|cff66ccffAutoFeed|r heal pot: " .. lbl(AF.lastHealPot)
            .. "  |  mana pot: " .. lbl(AF.lastManaPot))
        print("|cff66ccffAutoFeed|r next scroll: "
            .. (AF.lastScroll and AF.lastScroll.name or "none (fully buffed or no scrolls)"))
        print("|cff66ccffAutoFeed|r: drag macros '" .. AF.db.macroName .. "' (food), '"
            .. AF.db.drinkMacroName .. "' (water), '" .. AF.db.healMacroName .. "' (heal pot), '"
            .. AF.db.manaMacroName .. "' (mana pot), '" .. AF.db.scrollMacroName
            .. "' (scrolls) from the ? Macros tab onto your action bars.")
    elseif msg == "debug" or msg == "scan" then
        print("|cff66ccffAutoFeed|r debug -- consumables in bags (class 0 only):")
        local found = 0
        for bag = 0, 4 do
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and info.itemID then
                    local name, _, _, _, _, _, _, _, _, _ = GetItemInfo(info.itemID)
                    local _, itype, isub, _, _, classID, subClassID = GetItemInfoInstant(info.itemID)
                    if classID == 0 then
                        local c = Classify(bag, slot)
                        local res = c and (c.kind .. " hp=" .. c.health .. " mp=" .. c.mana) or "ignored"
                        print(("  %s |cffaaaaaa[c%s s%s %s/%s]|r -> %s"):format(
                            name or ("item:" .. info.itemID),
                            tostring(classID), tostring(subClassID),
                            tostring(itype), tostring(isub), res))
                        found = found + 1
                    end
                end
            end
        end
        if found == 0 then print("  (no Consumable-class items found in bags)") end
    else
        AF:OpenOptions()
    end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:RegisterEvent("PLAYER_LEVEL_UP")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterUnitEvent("UNIT_AURA", "player")  -- re-pick the scroll when buffs change
f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        ApplyDefaults()
        if AF.BuildOptions then AF:BuildOptions() end
        C_Timer.After(2, function() AF:UpdateMacro() end) -- let item data cache first
        print("|cff66ccffAutoFeed|r v" .. AF.version
            .. " loaded. Type /autofeed for options. Macros: '" .. AF.db.macroName
            .. "' (food) and '" .. AF.db.drinkMacroName .. "' (water).")
    elseif event == "PLAYER_REGEN_ENABLED" then
        if AF.pending then AF:UpdateMacro() end
    elseif event == "UNIT_AURA" then
        -- Aura changes only matter for the scroll cycler, and macros can't be
        -- edited in combat anyway - skip the rescan entirely otherwise.
        if AF.db and AF.db.includeScrolls and not InCombatLockdown() then
            AF:ScheduleUpdate()
        end
    else -- BAG_UPDATE_DELAYED / PLAYER_LEVEL_UP
        if AF.db then AF:ScheduleUpdate() end
    end
end)
