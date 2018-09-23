--[[
Author: Ayantir
Filename: en.lua
Version: 7
]]--

local strings = {
    ROOMBA_GBANK            = "Enable Roomba at Guild Bank",
    ROOMBA_GBANK_TOOLTIP    = "If enabled, Roomba will be activated at Guild Bank",

    ROOMBA_POSITION         = "Horizontal positioning",
    ROOMBA_POSITION_TOOLTIP = "Set the horizontal positioning of the Roomba button",

    ROOMBA_POSITION_CHOICE1 = "Left Side",
    ROOMBA_POSITION_CHOICE2 = "Center",
    ROOMBA_POSITION_CHOICE3 = "Right Side",
    
    ROOMBA_RESCAN_BANK      = "Rescan"
}

for stringId, stringValue in pairs(strings) do
    ZO_CreateStringId(stringId, stringValue)
    SafeAddVersion(stringId, 1)
end