
-- RasfectionUI Focus Frame v1.9.0
local RUI = _G.RasfectionUI
if not RUI or not RUI.CompactUnitFrames then return end

local frame = RUI.CompactUnitFrames:New({
    unit = "focus",
    frameName = "RasfectionUIFocusFrame",
    moverID = "FocusFrame",
    label = "Focus Frame",

    width = 275,
    height = 70,
    x = 350,
    y = 90,

    portrait = true,
    mirrored = true,
    compact = false,

    auras = true,
    auraCount = 6,

    dropdown = "FocusFrameDropDown"
})

RUI:RegisterModule("FocusFrame", frame)
