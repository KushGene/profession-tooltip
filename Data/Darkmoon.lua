-- Data/Darkmoon.lua
-- Items that Darkmoon Faire quests take, with what the quest gives back.
-- Source: CMaNGOS classic-db (https://github.com/cmangos/classic-db, GPL-3.0), table quest_template
-- (ReqItemId/ReqItemCount, RewItemId/RewItemCount, MinLevel) of the quests 7881-7903, 7907,
-- 7927-7929, 7939-7946, 8222 and 8223. The repeatable "More ..." quests ask for the same item
-- and amount as the first one, so each item is listed once. The client has no quest requirements.
local _, ns = ...

ns.DARKMOON_TICKET = 19182 -- Darkmoon Faire Prize Ticket

-- [item] = { count, reward item, reward count, minimum level }
ns.DarkmoonTurnIns = {
    -- Yebb Neblegear: gathered items
    [5134] = { 5, 19182, 1, 1 },    -- Small Furry Paw
    [11407] = { 5, 19182, 4, 10 },  -- Torn Bear Pelt
    [4582] = { 5, 19182, 8, 20 },   -- Soft Bushy Tail
    [5117] = { 5, 19182, 12, 30 },  -- Vibrant Plume
    [11404] = { 10, 19182, 20, 40 }, -- Evil Bat Eye
    [19933] = { 10, 19182, 20, 40 }, -- Glowing Scorpid Blood
    -- Chronos: Leatherworking
    [2309] = { 3, 19182, 1, 1 },    -- Embossed Leather Boots
    [2314] = { 3, 19182, 4, 10 },   -- Toughened Leather Armor
    [5739] = { 3, 19182, 8, 20 },   -- Barbaric Harness
    [8185] = { 1, 19182, 12, 30 },  -- Turtle Scale Leggings
    [15564] = { 8, 19182, 20, 40 }, -- Rugged Armor Kit
    -- Kerri Hicks: Blacksmithing
    [3240] = { 10, 19182, 1, 1 },   -- Coarse Weightstone
    [3486] = { 7, 19182, 4, 10 },   -- Heavy Grinding Stone
    [3835] = { 3, 19182, 8, 20 },   -- Green Iron Bracers
    [7945] = { 1, 19182, 12, 30 },  -- Big Black Mace
    [12644] = { 8, 19182, 20, 40 }, -- Dense Grinding Stone
    -- Rinling: Engineering
    [4363] = { 5, 19182, 1, 1 },    -- Copper Modulator
    [4375] = { 7, 19182, 4, 10 },   -- Whirring Bronze Gizmo
    [9313] = { 36, 19182, 8, 20 },  -- Green Firework
    [11590] = { 6, 19182, 12, 30 }, -- Mechanical Repair Kit
    [15994] = { 6, 19182, 20, 40 }, -- Thorium Widget
    -- Darkmoon decks -> Darkmoon card trinket
    [19228] = { 1, 19288, 1, 1 },   -- Beasts Deck -> Darkmoon Card: Blue Dragon
    [19257] = { 1, 19287, 1, 1 },   -- Warlords Deck -> Darkmoon Card: Heroism
    [19267] = { 1, 19289, 1, 1 },   -- Elementals Deck -> Darkmoon Card: Maelstrom
    [19277] = { 1, 19290, 1, 1 },   -- Portals Deck -> Darkmoon Card: Twisting Nether
    -- Quest "Spawn of Jubjub"
    [11325] = { 1, 19462, 1, 1 },   -- Dark Iron Ale Mug -> Unhatched Jubling Egg
}
