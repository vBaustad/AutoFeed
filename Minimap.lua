local ADDON, AF = ...

-- Minimap button through LibDataBroker + LibDBIcon (via LibForever's helper), so it sits in the ring
-- with the client's own geometry and drags like every other addon's. Left-click opens the addon's
-- main window; AutoFeed has none, so both clicks open its settings in the YippYapp window (the
-- Create-macro buttons are there too). The what's-new page is reached from inside that window.
local LIB = LibStub("LibForever-1.0", true)

local function OnClick()
    AF:OpenOptions()  -- AutoFeed's settings in the YippYapp window
end

local function OnTooltipShow(tooltip)
    tooltip:AddLine("|cff66ccffAutoFeed|r")
    tooltip:AddLine("Click: settings and macros", 1, 1, 1)
    tooltip:AddLine("Drag: move around the minimap", 0.6, 0.6, 0.6)
end

local registered = false

-- Registers the button once. Whether it shows is set on the shared YippYapp settings page.
function AF:ApplyMinimapButton()
    if not (AF.db and LIB and LIB.RegisterMinimapButton) then return end
    if not registered then
        -- The old hand-made button saved its spot as AF.db.minimapAngle (same degrees LibDBIcon uses);
        -- LibDBIcon's own db (AF.db.minimap) starts there, then the old key is dropped.
        registered = LIB.RegisterMinimapButton("AutoFeed", {
            icon = "Interface\\AddOns\\AutoFeed\\Media\\minimap",
            label = "AutoFeed",
            OnClick = OnClick,
            OnTooltipShow = OnTooltipShow,
            migrateAngle = AF.db.minimapAngle,
        }, AF.db)
        if registered then AF.db.minimapAngle = nil end
    end
    -- AutoFeed's own "Show a minimap button" setting moved to the YippYapp page: carry a switched-off
    -- button over once, then drop the old key.
    if registered and AF.db.minimapButton ~= nil then
        if AF.db.minimapButton == false then LIB.SetMinimapButtonShown("AutoFeed", false) end
        AF.db.minimapButton = nil
    end
end

-- Addon compartment (the modern client's addon menu by the minimap): same clicks as the button.
function AutoFeed_OnAddonCompartmentClick(frame, button)
    OnClick(frame, button)
end

function AutoFeed_OnAddonCompartmentEnter(_, menuButton)
    GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cff66ccffAutoFeed|r")
    GameTooltip:AddLine("Click: settings and macros", 1, 1, 1)
    GameTooltip:Show()
end

function AutoFeed_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end

-- The shared launcher notch (LibForever): one bronze bar on the screen edge for all our addons.
function AF:RegisterLauncher()
    if not (LIB and LIB.RegisterLauncher) then return end
    LIB.RegisterLauncher({
        id = "AutoFeed", label = "AutoFeed", order = 40,
        icon = "Interface\\AddOns\\AutoFeed\\Media\\notch",
        onClick = function(button) AutoFeed_OnAddonCompartmentClick(nil, button) end,
        status = function()
            return AF.lastFood and ("Eating: " .. AF.lastFood.name .. " x" .. AF.lastFood.count) or nil
        end,
        tooltip = { "Click: settings and macros" },
    }, AF.db)
end
