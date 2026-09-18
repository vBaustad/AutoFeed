local ADDON, AF = ...

-- Forever's own bronze UI art: the "heavybronze" frame its character creation uses (and the
-- LibForever launcher wears). The atlases ship with the client. Used for AutoFeed's own windows;
-- the settings page keeps Blizzard's standard look.
local Skin = {}
AF.Skin = Skin

Skin.GOLD = { 1, 0.82, 0.40 }

local CORNER_POINT = { TL = "TOPLEFT", TR = "TOPRIGHT", BL = "BOTTOMLEFT", BR = "BOTTOMRIGHT" }

-- Stained-wood backdrop and the nine-sliced riveted border (32px slices). `corners` is an
-- optional list of bracket corners, e.g. { "BL", "BR" }; brackets are 32px plates, so keep
-- content clear of them.
function Skin.Frame(f, corners)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 10, -10)
    bg:SetPoint("BOTTOMRIGHT", -10, 10)
    bg:SetAtlas("heavybronze-frame-background")
    local border = f:CreateTexture(nil, "BORDER")
    border:SetAllPoints()
    border:SetAtlas("heavybronze-frame-basic")
    for _, c in ipairs(corners or {}) do
        local t = f:CreateTexture(nil, "BORDER", nil, 1)
        t:SetAtlas("heavybronze-horz-cornerbracket-" .. c, true)
        t:SetPoint(CORNER_POINT[c], 0, 0)
    end
    f.skinBackground, f.skinBorder = bg, border
end

