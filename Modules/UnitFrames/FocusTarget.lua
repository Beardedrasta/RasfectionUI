
-- RasfectionUI Focus Target v1.9.0
local RUI = _G.RasfectionUI
if not RUI or not RUI.CompactUnitFrames then return end

local frame = RUI.CompactUnitFrames:New({
    -- Native WotLK 3.3.5a unit identifier.
    unit = "focus-target",

    frameName = "RasfectionUIFocusTargetFrame",
    moverID = "FocusTargetFrame",
    label = "Focus Target",

    width = 205,
    height = 49,
    x = 370,
    y = 20,

    portrait = false,
    mirrored = true,
    compact = true,

    auras = false
})

RUI:RegisterModule("FocusTargetFrame", frame)
