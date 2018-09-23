--[[
Author: Ayantir
Filename: fr.lua
Version: 7
]]--

local strings = {
    ROOMBA_GBANK            = "Activer Roomba à la banque de Guilde",
    ROOMBA_GBANK_TOOLTIP    = "L'option activée, Roomba sera activé à la banque de guilde",

    ROOMBA_POSITION         = "Position du bouton",
    ROOMBA_POSITION_TOOLTIP = "Définir la position horizontale du bouton de restack",

    ROOMBA_POSITION_CHOICE1 = "A gauche",
    ROOMBA_POSITION_CHOICE2 = "Au milieu",
    ROOMBA_POSITION_CHOICE3 = "A droite"
}

for stringId, stringValue in pairs(strings) do
    SafeAddString(stringId, stringValue, 1)
end