
-- RasfectionUI Pet Frame v1.9.0
local RUI = _G.RasfectionUI
if not RUI or not RUI.CompactUnitFrames then return end

local frame = RUI.CompactUnitFrames:New({
    unit = "pet",
    frameName = "RasfectionUIPetFrame",
    moverID = "PetFrame",
    label = "Pet Frame",

    width = 205,
    height = 49,
    x = -340,
    y = -265,

    portrait = false,
    mirrored = false,
    compact = true,

    auras = false,

    dropdown = "PetFrameDropDown"
})

RUI:RegisterModule("PetFrame", frame)
