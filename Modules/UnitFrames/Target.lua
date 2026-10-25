
-- RasfectionUI Target Frame v1.9.0
local RUI = _G.RasfectionUI
if not RUI or not RUI.CompactUnitFrames then return end

local frame = RUI.CompactUnitFrames:New({
    unit = "target",
    frameName = "RasfectionUITargetFrame",
    moverID = "TargetFrame",
    label = "Target Frame",

    width = 310,
    height = 74,
    x = 310,
    y = -160,

    portrait = true,
    mirrored = true,
    compact = false,

    auras = true,
    auraCount = 8,

    dropdown = "TargetFrameDropDown"
})

RUI:RegisterModule("TargetFrame", frame)
