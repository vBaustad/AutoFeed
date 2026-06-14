-- AutoFeed: keeps a single macro pointed at the best food/drink in your bags.
-- Classic Era 1.15.x. Shares the private table `AF` across files via the addon vararg.
local ADDON, AF = ...

AF.version = "1.1.0"

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
    potionWeakestFirst = false,  -- false = strongest potion first; true = drain weak ones, save the big
    includeScrolls     = true,   -- manage the scroll-buff cycler macro
    includeBandage     = true,   -- manage the bandage macro
    macroName          = "AutoFeed",
    drinkMacroName     = "AutoDrink",
    healMacroName      = "AutoHealPot",
    manaMacroName      = "AutoManaPot",
    scrollMacroName    = "AutoScroll",
    bandageMacroName   = "AutoBandage",
    blacklist          = {},     -- [itemID] = true, never use these
    welcomed           = false,  -- first-login welcome window shown yet?
    minimapButton      = true,   -- show a minimap button
    minimapAngle       = 200,    -- minimap button position around the ring (degrees)
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

local function Classify(bag, slot, ignoreBlacklist)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info or not info.itemID then return nil end

    local itemID = info.itemID
    if not ignoreBlacklist and AF.db.blacklist[itemID] then return nil end

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
        -- Not cached yet: ask for it, flag the scan incomplete (so UpdateMacro
        -- retries once data arrives), and skip caching this pass.
        if C_Item and C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(itemID)
        end
        AF.scanPending = true
        itemName = (info.hyperlink and info.hyperlink:match("%[(.-)%]")) or ("item:" .. itemID)
    end
    local lname = itemName:lower()

    local lines = GetTooltipLines(bag, slot)
    -- Only ever cache POSITIVE verdicts, and only from fully-loaded data. A
    -- not-yet-loaded item can momentarily look like "nothing"; caching that
    -- negative would wrongly hide a real food/potion until /reload.
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

    -- Bandages say "Heals X damage over N sec" (not "Restores") and are named
    -- "... Bandage". Detect them before the food/potion logic.
    if lname:find("bandage") then
        local heal = 0
        for _, raw in ipairs(lines) do
            local n = raw:lower():match("heals%s+([%d,]+)")
            if n then heal = num(n); break end
        end
        if heal > 0 then
            local rec = { name = itemName, reqLevel = reqLevel, buff = false,
                conjured = false, health = heal, mana = 0, kind = "bandage" }
            if cacheable then classifyCache[itemID] = rec end
            return {
                id = itemID, name = itemName, count = info.stackCount or 1,
                reqLevel = reqLevel, buff = false, conjured = false,
                health = heal, mana = 0, kind = "bandage",
            }
        end
    end

    if health == 0 and mana == 0 then
        -- A Potion (subclass 1) or Food & Drink (subclass 5) with no restore line
        -- almost certainly hasn't finished loading its use effect - retry rather
        -- than write it off (and never cache the negative).
        if subClassID == 1 or subClassID == 5 then AF.scanPending = true end
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
    AF.scanPending = false   -- Classify() sets this true if any item wasn't loaded yet
    local level = UnitLevel("player")
    local foods, foodsAll, drinks, drinksAll = {}, {}, {}, {}
    local healPots, manaPots, bandages = {}, {}, {}

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
                elseif c.kind == "bandage" then
                    bandages[#bandages + 1] = c
                end
            end
        end
    end

    return foods, foodsAll, drinks, drinksAll, healPots, manaPots, bandages
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

-- Returns up to n distinct items for the combat-potion fallback lists, ranked
-- purely by strength. Strongest first by default; weakest first if the user
-- prefers to drain small potions and save the big ones.
local function PickTop(list, key, n)
    if not list or #list == 0 then return {} end
    local sorted = {}
    for i = 1, #list do sorted[i] = list[i] end
    local weakFirst = AF.db.potionWeakestFirst
    table.sort(sorted, function(a, b)
        if a[key] ~= b[key] then
            if weakFirst then return a[key] < b[key] end
            return a[key] > b[key]
        end
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
    if not buffName then return false end
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
            if info and info.itemID and not AF.db.blacklist[info.itemID] then
                local name = GetItemInfo(info.itemID)
                local stat = name and name:match("^Scroll of (%a+)")
                if stat and STAT_SET[stat] then
                    local rank = ParseRank(name)
                    if not found[stat] or rank > found[stat].rank then
                        -- The aura a scroll grants isn't always named after the stat
                        -- (Scroll of Protection -> "Armor"), so capture the actual
                        -- on-use buff name and check that.
                        local buffName = GetItemSpell(info.itemID)
                        found[stat] = { id = info.itemID, rank = rank, name = name,
                            stat = stat, buffName = buffName }
                    end
                end
            end
        end
    end
    return found
end

-- Potions and scrolls currently in bags, for the settings exclude list.
-- Ignores the blacklist so excluded items remain visible (and re-includable).
function AF:GetExcludables()
    local out, seen = {}, {}
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local id = info and info.itemID
            if id and not seen[id] then
                seen[id] = true
                local name = GetItemInfo(id)
                if name then
                    local stat = name:match("^Scroll of (%a+)")
                    if stat and STAT_SET[stat] then
                        out[#out + 1] = { id = id, name = name, kind = "scroll" }
                    else
                        local c = Classify(bag, slot, true)
                        if c and c.kind == "potion" then
                            out[#out + 1] = { id = id, name = name,
                                kind = (c.health > 0) and "heal" or "mana" }
                        end
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- The next scroll whose buff you're missing (in stat order); nil if fully buffed.
local function PickScroll()
    local found = ScanScrolls()
    for _, stat in ipairs(SCROLL_STATS) do
        local s = found[stat]
        -- Buffed if the scroll's real buff is up (or, as a fallback, an aura named
        -- after the stat). Either match means "don't suggest it again".
        if s and not (HasBuff(s.buffName) or HasBuff(stat)) then return s end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Macro writing
-- ---------------------------------------------------------------------------
-- Updates an EXISTING macro's body (skips the call if unchanged). It never
-- creates a macro - macros cost a per-character slot, so the player makes the
-- ones they want from the welcome window or settings. Missing macros are skipped.
function AF:WriteMacro(name, body)
    self.lastBody = self.lastBody or {}
    local idx = GetMacroIndexByName(name)
    if not (idx and idx > 0) then
        self.lastBody[name] = nil   -- doesn't exist; nothing to keep in sync
        return
    end
    if self.lastBody[name] == body then return end
    self.lastBody[name] = body
    pcall(EditMacro, idx, name, DYNAMIC_ICON, body)
end

-- The macros AutoFeed manages, in display order. need="mana" entries only matter
-- for mana users; toggle = the "manage this" setting to switch on when created.
AF.MACROS = {
    { key = "food",   slot = "macroName",       short = "Food",     need = "always" },
    { key = "drink",  slot = "drinkMacroName",  short = "Water",    need = "mana",   toggle = "includeDrink" },
    { key = "heal",   slot = "healMacroName",   short = "Heal pot", need = "always", toggle = "includeHealPot" },
    { key = "mana",   slot = "manaMacroName",   short = "Mana pot", need = "mana",   toggle = "includeManaPot" },
    { key = "scroll", slot = "scrollMacroName", short = "Scroll",   need = "always", toggle = "includeScrolls" },
    { key = "bandage", slot = "bandageMacroName", short = "Bandage", need = "always", toggle = "includeBandage" },
}

-- Create every macro that applies to this class, in one go (for a "Create all" button).
function AF:CreateAllMacros()
    local hasMana = (UnitPowerMax("player", 0) or 0) > 0
    for _, m in ipairs(AF.MACROS) do
        if not (m.need == "mana" and not hasMana) then AF:CreateMacroByKey(m.key) end
    end
end

-- Create one managed macro on demand (per-character). Enables its "manage" toggle
-- so UpdateMacro keeps it current, then fills the body immediately. Returns false
-- (with a chat note) if the character's macro slots are full.
function AF:CreateMacroByKey(key)
    if not self.db then return false end
    local def
    for _, m in ipairs(AF.MACROS) do if m.key == key then def = m; break end end
    if not def then return false end

    local name = self.db[def.slot]
    if def.toggle then self.db[def.toggle] = true end

    local idx = GetMacroIndexByName(name)
    if not (idx and idx > 0) then
        local ok = pcall(CreateMacro, name, DYNAMIC_ICON, "#showtooltip", true) -- per-character
        if not ok then
            print("|cff66ccffAutoFeed|r: couldn't create '" .. name
                .. "' - your character macro slots are full. Free one (Esc > Macros) and try again.")
            return false
        end
        print("|cff66ccffAutoFeed|r: created '" .. name
            .. "'. Drag it from Esc > Macros onto your action bars.")
    end

    self.lastBody = self.lastBody or {}
    self.lastBody[name] = nil   -- force a fresh body on the next write
    self:UpdateMacro()
    return true
end

function AF:UpdateMacro()
    if not self.db then return end
    if InCombatLockdown() then
        self.pending = true
        return
    end
    self.pending = nil

    local foods, foodsAll, drinks, drinksAll, healPots, manaPots, bandages = ScanBags()
    -- Use the FILTERED lists: when "filter buff food" is on, Well Fed / stat food is
    -- intentionally never auto-suggested (saved for raids) - even if it's all you
    -- have. foodsAll/drinksAll are only used to word the "nothing usable" message.
    local food = Pick(foods, "health")

    local drink
    local hasMana = (UnitPowerMax("player", 0) or 0) > 0
    if self.db.includeDrink and hasMana then
        drink = Pick(drinks, "mana")
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
        local msg = (#foodsAll > 0) and "only buff food in bags - saved for raids (/autofeed to change)"
            or "no usable food in bags"
        foodBody[#foodBody + 1] = '/run print("|cff66ccffAutoFeed|r: ' .. msg .. '")'
    end
    self:WriteMacro(self.db.macroName, table.concat(foodBody, "\n"))

    -- Water macro: drink only. Only managed for mana classes with drink enabled.
    if self.db.includeDrink and hasMana then
        local drinkBody = { "#showtooltip" }
        if drink then
            drinkBody[#drinkBody + 1] = "/use item:" .. drink.id
        else
            local msg = (#drinksAll > 0) and "only buff drink in bags - saved for raids (/autofeed to change)"
                or "no usable water in bags"
            drinkBody[#drinkBody + 1] = '/run print("|cff66ccffAutoFeed|r: ' .. msg .. '")'
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

    -- Bandage macro: best bandage, with the next tier as a fallback.
    if self.db.includeBandage then
        local top = PickTop(bandages, "health", 2)
        local body = { "#showtooltip" }
        for _, b in ipairs(top) do
            body[#body + 1] = "/use item:" .. b.id
        end
        if #body == 1 then
            body[#body + 1] = '/run print("|cff66ccffAutoFeed|r: no bandage in bags")'
        end
        self:WriteMacro(self.db.bandageMacroName, table.concat(body, "\n"))
        self.lastBandage = top[1]
    end

    self.lastFood, self.lastDrink = food, drink

    -- Right after login (and sometimes after big bag changes) item data isn't
    -- cached yet, so the scan can miss food/potions that really are in the bags.
    -- When ScanBags flagged that, retry shortly - bounded - until it settles.
    if self.scanPending and (self.loadRetries or 0) < 8 then
        self.loadRetries = (self.loadRetries or 0) + 1
        C_Timer.After(1.5, function() AF:UpdateMacro() end)
    elseif not self.scanPending then
        self.loadRetries = 0
    end
end

-- Debounced update (bag events can fire in bursts)
function AF:ScheduleUpdate()
    self.loadRetries = 0   -- a fresh event gets a fresh retry budget
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
        wipe(classifyCache)   -- drop any stale verdicts so everything is re-read
        AF.loadRetries = 0
        AF:UpdateMacro()
        print("|cff66ccffAutoFeed|r: macro refreshed.")
    elseif msg == "status" then
        local function lbl(c) return c and (c.name .. " x" .. c.count) or "none" end
        print("|cff66ccffAutoFeed|r food: " .. lbl(AF.lastFood) .. "  |  water: " .. lbl(AF.lastDrink))
        print("|cff66ccffAutoFeed|r heal pot: " .. lbl(AF.lastHealPot)
            .. "  |  mana pot: " .. lbl(AF.lastManaPot))
        print("|cff66ccffAutoFeed|r next scroll: "
            .. (AF.lastScroll and AF.lastScroll.name or "none (fully buffed or no scrolls)")
            .. "  |  bandage: " .. (AF.lastBandage and AF.lastBandage.name or "none"))
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
    elseif msg == "welcome" or msg == "macros" then
        if AF.ShowWelcome then AF:ShowWelcome() end
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
        if AF.ApplyMinimapButton then AF:ApplyMinimapButton() end
        C_Timer.After(2, function() AF:UpdateMacro() end) -- let item data cache first
        print("|cff66ccffAutoFeed|r v" .. AF.version
            .. " loaded. Type /autofeed to create macros and change options.")
        if not AF.db.welcomed then
            AF.db.welcomed = true
            C_Timer.After(3, function() if AF.ShowWelcome then AF:ShowWelcome() end end)
        end
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
