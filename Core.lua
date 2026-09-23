-- AutoFeed: keeps a single macro pointed at the best food/drink in your bags.
-- WoW: Forever (modern 12.x client API). Shares the private table `AF` across files via the addon vararg.
local ADDON, AF = ...

AF.version = C_AddOns.GetAddOnMetadata(ADDON, "Version") or "?"

-- The modern client dropped the global item functions; only the C_Item versions exist.
local GetItemInfo = C_Item.GetItemInfo
local GetItemInfoInstant = C_Item.GetItemInfoInstant
local GetItemSpell = C_Item.GetItemSpell

-- Backpack + equipped bags (the modern client adds a reagent bag slot after bag 4).
local LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4

-- The dynamic "?" macro icon. With #showtooltip this auto-shows the item's icon.
local DYNAMIC_ICON = 134400

local MAX_BLACKLIST = 250   -- excluded items kept in SavedVariables
local MAX_CACHE = 400       -- classified items kept in memory

-- ---------------------------------------------------------------------------
-- Defaults / saved variables
-- ---------------------------------------------------------------------------
local defaults = {
    filterBuffFood     = true,   -- ignore food/drink that grants Well Fed / stat buffs
    wellFedXP          = true,   -- ...except while leveling without Well Fed: its +5% XP makes buff food worth it
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
    blacklist          = {},     -- [itemID] = time() it was excluded, never use these
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

    -- Per character: which macros AutoFeed made (never touch anyone else's).
    AutoFeedCharDB = AutoFeedCharDB or {}
    if type(AutoFeedCharDB.owned) ~= "table" then AutoFeedCharDB.owned = {} end
    AF.char = AutoFeedCharDB

    -- The exclusion list is the only saved table that grows with use. Each entry is the time it was
    -- excluded; keep the newest MAX_BLACKLIST and drop the rest, so it can't grow without bound.
    local ids = {}
    for id, v in pairs(AutoFeedDB.blacklist) do
        ids[#ids + 1] = { id = id, t = tonumber(v) or 0 }
    end
    if #ids > MAX_BLACKLIST then
        table.sort(ids, function(a, b) return a.t > b.t end)
        for i = MAX_BLACKLIST + 1, #ids do AutoFeedDB.blacklist[ids[i].id] = nil end
    end
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
local classifyCount = 0

local function CacheVerdict(itemID, verdict)
    if classifyCount >= MAX_CACHE then   -- rebuilt on demand; bounded by items actually seen
        classifyCache, classifyCount = {}, 0
    end
    if classifyCache[itemID] == nil then classifyCount = classifyCount + 1 end
    classifyCache[itemID] = verdict
end

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

    -- Gate on Consumable (classID 0). Food shows up under several different
    -- subclasses, so we don't trust the subclass number -- we classify food vs
    -- potion from the tooltip wording below ("restores X over N sec" = food).
    local _, _, _, _, _, classID, subClassID = GetItemInfoInstant(itemID)
    if classID ~= 0 then CacheVerdict(itemID, false); return nil end

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
    -- Only cache verdicts from fully-loaded data. A not-yet-loaded item can
    -- momentarily look like "nothing"; caching that would wrongly hide a real
    -- food/potion until /reload (see the "Use:" check below for negatives).
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
            if cacheable then CacheVerdict(itemID, rec) end
            return {
                id = itemID, name = itemName, count = info.stackCount or 1,
                reqLevel = reqLevel, buff = false, conjured = false,
                health = heal, mana = 0, kind = "bandage",
            }
        end
    end

    if health == 0 and mana == 0 then
        -- Nothing we use (Swiftness, Free Action, Rage, alcohol...). Once the item and its
        -- "Use:" text have loaded, cache that for good; without the use text, a Potion (1) or
        -- Food & Drink (5) probably hasn't loaded its effect yet, so retry.
        local hasUseText = false
        for _, raw in ipairs(lines) do
            if raw:lower():match("^use:%s*%S") then hasUseText = true; break end
        end
        if cacheable and hasUseText then
            CacheVerdict(itemID, false)
        elseif subClassID == 1 or subClassID == 5 then
            AF.scanPending = true
        end
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
        if cacheable then CacheVerdict(itemID, false) end
        return nil
    end

    local conjured = (lname:find("conjured") ~= nil)
    if cacheable then
        CacheVerdict(itemID, {
            name = itemName, reqLevel = reqLevel, buff = buff, conjured = conjured,
            health = health, mana = mana, kind = kind,
        })
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
-- What the bags hold right now, as a cheap string. Item data isn't read, only IDs and counts.
local function BagSignature()
    local parts = {}
    for bag = 0, LAST_BAG do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                parts[#parts + 1] = info.itemID .. "x" .. (info.stackCount or 1)
            end
        end
    end
    parts[#parts + 1] = "L" .. UnitLevel("player")
    return table.concat(parts, ",")
end

local function ScanBags()
    AF.scanPending = false   -- Classify() sets this true if any item wasn't loaded yet
    local level = UnitLevel("player")
    local foods, foodsAll, drinks, drinksAll = {}, {}, {}, {}
    local healPots, manaPots, bandages = {}, {}, {}

    for bag = 0, LAST_BAG do
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

-- Class buffs that raise the SAME stat and so don't stack with the scroll - if
-- one is up, using the scroll just fails ("a more powerful spell is already
-- active"), so we don't suggest it. enUS buff names.
local STAT_BUFFS = {
    Stamina   = { "Power Word: Fortitude", "Prayer of Fortitude" },
    Intellect = { "Arcane Intellect", "Arcane Brilliance" },
    Spirit    = { "Divine Spirit", "Prayer of Spirit" },
}

local ROMAN = { I = 1, II = 2, III = 3, IV = 4, V = 5, VI = 6 }
local function ParseRank(name)
    local r = name:match("%s([IVX]+)$")
    return (r and ROMAN[r]) or 1
end

-- The player's helpful auras: names and spell IDs we can read, plus whether any aura was secret.
-- Walks the list by index: C_UnitAuras.GetAuraDataBySpellName needs a non-secret aura and just
-- returns nil otherwise, which looked like "buff missing" (Well Fed was re-suggested).
-- GetAuraDataByIndex throws a Lua error for a secret aura (combat, encounters, PvP), so every index
-- is asked about first; a secret one is skipped and marks the result unreadable.
local function ReadPlayerAuras()
    local names, ids, unreadable = {}, {}, false
    for i = 1, 255 do
        if C_Secrets.ShouldUnitAuraIndexBeSecret("player", i, "HELPFUL") then
            unreadable = true
        else
            local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not a then break end
            local name, id = a.name, a.spellId
            if issecretvalue(name) or issecretvalue(id) then
                unreadable = true
            else
                if name then names[name] = true end
                if id then ids[id] = true end
            end
        end
    end
    return names, ids, unreadable
end

-- Best (highest-rank) scroll per stat that's in your bags.
local function ScanScrolls()
    local found = {}
    for bag = 0, LAST_BAG do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and not AF.db.blacklist[info.itemID] then
                local name = GetItemInfo(info.itemID)
                if not name then
                    -- Not loaded yet (right after login): ask for it and let UpdateMacro retry,
                    -- as Classify does, instead of reporting "all scroll buffs active".
                    C_Item.RequestLoadItemDataByID(info.itemID)
                    AF.scanPending = true
                end
                local stat = name and name:match("^Scroll of (%a+)")
                if stat and STAT_SET[stat] then
                    local rank = ParseRank(name)
                    if not found[stat] or rank > found[stat].rank then
                        -- The aura a scroll grants isn't always named after the stat
                        -- (Scroll of Protection -> "Armor"), so capture the actual
                        -- on-use buff name and check that.
                        local buffName = GetItemSpell(info.itemID)
                        if not buffName then AF.scanPending = true end
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
    for bag = 0, LAST_BAG do
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

-- A stat is "covered" if the scroll's own buff is up, an aura named after the
-- stat is up, or a non-stacking class buff for that stat is up (using the scroll
-- then would only fail with "a more powerful spell is already active").
local function StatCovered(s, auras)
    if (s.buffName and auras[s.buffName]) or auras[s.stat] then return true end
    local conflicts = STAT_BUFFS[s.stat]
    if conflicts then
        for _, b in ipairs(conflicts) do
            if auras[b] then return true end
        end
    end
    return false
end

-- The next scroll whose stat isn't already covered (in stat order); nil if done.
-- Second return: true when some buffs couldn't be read, so the answer can't be trusted.
local function PickScroll()
    local found = ScanScrolls()
    local auras, _, unreadable = ReadPlayerAuras()  -- once, not per stat
    if unreadable then return nil, true end
    for _, stat in ipairs(SCROLL_STATS) do
        local s = found[stat]
        if s and not StatCovered(s, auras) then return s end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Well Fed XP: on Forever every Well Fed buff also carries "Well Fed XP Boost"
-- (+5% experience from kills), so buff food is worth eating while leveling.
-- ---------------------------------------------------------------------------
local WELL_FED_XP_SPELL = 1243969  -- the hidden "Well Fed XP Boost" aura every Well Fed carries

-- "yes", "no", or "unknown" (an aura was secret, so we can't be sure it's missing).
function AF:WellFedState()
    local names, ids, unreadable = ReadPlayerAuras()
    if names["Well Fed"] or ids[WELL_FED_XP_SPELL] then return "yes" end  -- aura name is enUS
    return unreadable and "unknown" or "no"
end

-- true/false, or the previous answer when buffs can't be read (keep the macro as it was).
local function WantsWellFed()
    if not AF.db.wellFedXP then return false end
    if IsXPUserDisabled() then return false end
    if UnitLevel("player") >= GetMaxLevelForPlayerExpansion() then return false end
    local state = AF:WellFedState()
    if state == "unknown" then return AF.lastWantBuff or false end
    AF.lastWantBuff = (state == "no")
    return AF.lastWantBuff
end

-- Macro lines are built from our own text plus an item ID as a number, never from an item name,
-- link or tooltip text, so nothing a weird item name contains can end up as macro commands.
local function UseLine(id, self_)
    id = tonumber(id)
    if not id then return nil end
    return self_ and ("/use [@player] item:%d"):format(id) or ("/use item:%d"):format(id)
end

local function BuffOnly(list)
    local out = {}
    for _, c in ipairs(list) do
        if c.buff then out[#out + 1] = c end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Macro writing
-- ---------------------------------------------------------------------------
-- Updates an EXISTING macro's body (skips the call if unchanged). It never
-- creates a macro - macros cost a per-character slot, so the player makes the
-- ones they want from the welcome window or settings. Missing macros are skipped.
-- A body only AutoFeed writes: "#showtooltip", then /use lines with a plain item ID, or one of
-- our own /run print notes. Used to recognise our macros from before we recorded them.
local function LooksLikeOurs(body)
    if not body or body == "" then return false end
    local lines, first = 0, true
    for line in body:gmatch("[^\n]+") do
        lines = lines + 1
        if first then
            if line ~= "#showtooltip" then return false end
            first = false
        elseif not (line:match("^/use item:%d+$")
            or line:match("^/use %[@player%] item:%d+$")
            or line:match('^/run print%("|cff66ccffAutoFeed|r: [^"]*"%)$')) then
            return false
        end
    end
    return lines > 0
end

-- Only ever edit a macro AutoFeed made. Installs from before we recorded that adopt a macro whose
-- body is one we would have written; anything else with the same name is somebody's own macro and
-- is left alone (said once per name).
local function OwnedMacro(name)
    local owned = AF.char and AF.char.owned
    if not owned then return false end
    if owned[name] then return true end
    if LooksLikeOurs(GetMacroBody(name)) then
        owned[name] = true
        return true
    end
    AF.warnedForeign = AF.warnedForeign or {}
    if not AF.warnedForeign[name] then
        AF.warnedForeign[name] = true
        print("|cff66ccffAutoFeed|r: '" .. tostring(name)
            .. "' is a macro AutoFeed didn't create, so it is left untouched. "
            .. "Rename or delete it, then create the AutoFeed macro again.")
    end
    return false
end

function AF:WriteMacro(name, body)
    self.lastBody = self.lastBody or {}
    local idx = GetMacroIndexByName(name)
    if not (idx and idx > 0) then
        self.lastBody[name] = nil   -- doesn't exist; nothing to keep in sync
        return
    end
    if not OwnedMacro(name) then return end
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
local function CombatBlocked()
    if not InCombatLockdown() then return false end
    print("|cff66ccffAutoFeed|r: can't create macros in combat - try again after the fight.")
    return true
end

function AF:CreateAllMacros()
    if CombatBlocked() then return end
    local hasMana = (UnitPowerMax("player", 0) or 0) > 0
    for _, m in ipairs(AF.MACROS) do
        if not (m.need == "mana" and not hasMana) then AF:CreateMacroByKey(m.key) end
    end
end

-- Create one managed macro on demand (per-character). Enables its "manage" toggle
-- so UpdateMacro keeps it current, then fills the body immediately. Returns false
-- (with a chat note) if the character's macro slots are full.
function AF:CreateMacroByKey(key)
    if not self.db or CombatBlocked() then return false end
    local def
    for _, m in ipairs(AF.MACROS) do if m.key == key then def = m; break end end
    if not def then return false end

    local name = self.db[def.slot]
    if def.toggle then self.db[def.toggle] = true end

    local idx = GetMacroIndexByName(name)
    if idx and idx > 0 then
        if not OwnedMacro(name) then return false end   -- somebody else's macro with that name
    else
        local ok = pcall(CreateMacro, name, DYNAMIC_ICON, "#showtooltip", true) -- per-character
        if not ok then
            print("|cff66ccffAutoFeed|r: couldn't create '" .. name
                .. "' - your character macro slots are full. Free one (Esc > Macros) and try again.")
            return false
        end
        self.char.owned[name] = true   -- ours from now on
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

    -- Bag events fire for all sorts of reasons (moving things around, a stack merging). When the
    -- bags and the level are what they were at the last scan, reuse that scan's lists instead of
    -- classifying everything again; a settings change clears bagSig to force a fresh scan.
    local sig = BagSignature()
    if sig ~= self.bagSig or not self.lists then
        self.lists = { ScanBags() }
        self.bagSig = sig
    end
    local foods, foodsAll, drinks, drinksAll, healPots, manaPots, bandages = unpack(self.lists, 1, 7)
    -- Use the FILTERED lists: when "filter buff food" is on, Well Fed / stat food is
    -- intentionally never auto-suggested (saved for raids) - even if it's all you
    -- have. foodsAll/drinksAll are only used to word the "nothing usable" message.
    -- Exception: while leveling without Well Fed, buff food wins (it's +5% XP). One buff
    -- item is enough, so buff drink is only picked when there's no buff food.
    local wantBuff = WantsWellFed()
    local food = wantBuff and Pick(BuffOnly(foodsAll), "health") or nil
    food = food or Pick(foods, "health")

    local drink
    local hasMana = (UnitPowerMax("player", 0) or 0) > 0
    if self.db.includeDrink and hasMana then
        if wantBuff and not (food and food.buff) then
            drink = Pick(BuffOnly(drinksAll), "mana")
        end
        drink = drink or Pick(drinks, "mana")
    end
    self.forWellFed = wantBuff and ((food and food.buff) or (drink and drink.buff)) or false

    -- Food macro: food, plus the drink line too when one-button mode is on.
    local foodBody = { "#showtooltip" }
    if food then
        foodBody[#foodBody + 1] = UseLine(food.id)
    end
    if self.db.oneButton and drink and (not food or drink.id ~= food.id) then
        foodBody[#foodBody + 1] = UseLine(drink.id)
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
            drinkBody[#drinkBody + 1] = UseLine(drink.id)
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
            body[#body + 1] = UseLine(p.id)
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
            body[#body + 1] = UseLine(p.id)
        end
        if #body == 1 then
            body[#body + 1] = '/run print("|cff66ccffAutoFeed|r: no mana potion in bags")'
        end
        self:WriteMacro(self.db.manaMacroName, table.concat(body, "\n"))
        self.lastManaPot = top[1]
    end

    -- Scroll-buff cycler: next scroll whose buff you lack; blank once fully buffed.
    -- Buffs that can't be read (secret) leave the macro as it was: neither "covered" nor "missing".
    local scroll, aurasUnreadable
    if self.db.includeScrolls then scroll, aurasUnreadable = PickScroll() end
    if self.db.includeScrolls and not aurasUnreadable then
        local body = { "#showtooltip" }
        if scroll then
            body[#body + 1] = UseLine(scroll.id, true)  -- always buff yourself
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
            body[#body + 1] = UseLine(b.id)
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
    -- One retry timer at a time, however many updates run meanwhile.
    if self.scanPending and (self.loadRetries or 0) < 8 then
        self.loadRetries = (self.loadRetries or 0) + 1
        if not self.retryTimer then
            self.retryTimer = C_Timer.NewTimer(1.5, function()
                AF.retryTimer = nil
                AF:UpdateMacro()
            end)
        end
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

-- "Refresh now" (settings button and /af update): re-read everything and rewrite the macros.
-- Macros can't be edited in combat, so then it's queued for the end of the fight - and says so.
function AF:RefreshNow()
    AF.lastBody = nil
    wipe(classifyCache)   -- drop any stale verdicts so everything is re-read
    classifyCount = 0
    AF.bagSig = nil       -- and rescan the bags even if nothing in them changed
    AF.loadRetries = 0
    AF:UpdateMacro()
    if AF.pending then
        print("|cff66ccffAutoFeed|r: macros can't change in combat - they'll refresh when the fight ends.")
    else
        print("|cff66ccffAutoFeed|r: macros refreshed.")
    end
end

SlashCmdList.AUTOFEED = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "update" or msg == "refresh" then
        AF:RefreshNow()
    elseif msg == "status" then
        local function lbl(c) return c and (c.name .. " x" .. c.count) or "none" end
        print("|cff66ccffAutoFeed|r food: " .. lbl(AF.lastFood) .. "  |  water: " .. lbl(AF.lastDrink)
            .. (AF.forWellFed and "  |cffffd100(buff food: you're missing Well Fed, +5% XP)|r" or ""))
        local _, _, unreadable = ReadPlayerAuras()
        print("|cff66ccffAutoFeed|r Well Fed: " .. AF:WellFedState()
            .. (unreadable and "  |cff999999(some of your buffs are hidden from addons)|r" or ""))
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
        for bag = 0, LAST_BAG do
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
        if AF.RegisterLauncher then AF:RegisterLauncher() end
        C_Timer.After(2, function() AF:UpdateMacro() end) -- let item data cache first
        AF:RegisterWelcome()  -- the shared YippYapp window opens itself while no macro exists
    elseif event == "PLAYER_REGEN_ENABLED" then
        if AF.pending then AF:ScheduleUpdate() end
    elseif event == "UNIT_AURA" then
        -- Aura changes only matter for the scroll cycler and the Well Fed check. Macros can't be
        -- edited in combat, so a change during combat is caught up on when it ends.
        if AF.db and (AF.db.includeScrolls or AF.db.wellFedXP) then
            if InCombatLockdown() then AF.pending = true else AF:ScheduleUpdate() end
        end
    else -- BAG_UPDATE_DELAYED / PLAYER_LEVEL_UP
        if AF.db then AF:ScheduleUpdate() end
    end
end)
