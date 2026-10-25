
-- RasfectionUI Player Frame v1.9.0
local RUI = _G.RasfectionUI
if not RUI or not RUI.CompactUnitFrames then return end

local frame = RUI.CompactUnitFrames:New({
    unit = "player",
    frameName = "RasfectionUIPlayerFrame",
    moverID = "PlayerFrame",
    label = "Player Frame",

    width = 310,
    height = 74,
    x = -310,
    y = -160,

    portrait = true,
    mirrored = false,
    compact = false,

    auras = true,
    auraCount = 8,

    dropdown = "PlayerFrameDropDown"
})

RUI:RegisterModule("PlayerFrame", frame)
