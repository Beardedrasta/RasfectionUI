
-- RasfectionUI Target-of-Target v1.9.0
local RUI = _G.RasfectionUI
if not RUI or not RUI.CompactUnitFrames then return end

local frame = RUI.CompactUnitFrames:New({
    unit = "targettarget",
    frameName = "RasfectionUITargetTargetFrame",
    moverID = "TargetTargetFrame",
    label = "Target of Target",

    width = 205,
    height = 49,
    x = 370,
    y = -265,

    portrait = false,
    mirrored = true,
    compact = true,

    auras = false
})

RUI:RegisterModule("TargetTargetFrame", frame)
