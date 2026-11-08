-- Gathering requirements for Classic world objects (not recipe skill ranks).
-- Object IDs are locale-independent. Names also cover tooltips without an ID.
local _, ns = ...
ns.GatheringNodes = {}

local function Node(profession, skill, objectID, english, german)
    local node = { profession = profession, skill = skill }
    ns.GatheringNodes[objectID] = node
    ns.GatheringNodes[english] = node
    ns.GatheringNodes[german] = node
end

Node(182, 1,   1618, "Peacebloom", "Friedensblume")
Node(182, 1,   1617, "Silverleaf", "Silberblatt")
Node(182, 15,  1619, "Earthroot", "Erdwurzel")
Node(182, 50,  1620, "Mageroyal", "Maguskönigskraut")
Node(182, 70,  1621, "Briarthorn", "Wilddornrose")
Node(182, 85,  2045, "Stranglekelp", "Würgetang")
Node(182, 100, 1623, "Bruiseweed", "Beulengras")
Node(182, 115, 1624, "Wild Steelbloom", "Wildstahlblume")
Node(182, 120, 1628, "Grave Moss", "Grabmoos")
Node(182, 125, 1622, "Kingsblood", "Königsblut")
Node(182, 150, 2041, "Liferoot", "Lebenswurz")
Node(182, 160, 2042, "Fadeleaf", "Blassblatt")
Node(182, 170, 2046, "Goldthorn", "Golddorn")
Node(182, 185, 2043, "Khadgar's Whisker", "Khadgars Schnurrbart")
Node(182, 195, 2044, "Wintersbite", "Winterbiss")
Node(182, 205, 2866, "Firebloom", "Feuerblüte")
Node(182, 210, 142140, "Purple Lotus", "Lila Lotus")
Node(182, 220, 142141, "Arthas' Tears", "Arthas' Tränen")
Node(182, 230, 142142, "Sungrass", "Sonnengras")
Node(182, 235, 142143, "Blindweed", "Blindkraut")
Node(182, 245, 142144, "Ghost Mushroom", "Geisterpilz")
Node(182, 250, 142145, "Gromsblood", "Gromsblut")
Node(182, 260, 176583, "Golden Sansam", "Goldener Sansam")
Node(182, 270, 176584, "Dreamfoil", "Traumblatt")
Node(182, 280, 176586, "Mountain Silversage", "Bergsilbersalbei")
Node(182, 285, 176587, "Plaguebloom", "Pestblüte")
Node(182, 290, 176588, "Icecap", "Eiskappe")
Node(182, 300, 176589, "Black Lotus", "Schwarzer Lotus")

Node(186, 1,   1731, "Copper Vein", "Kupfervorkommen")
Node(186, 65,  1732, "Tin Vein", "Zinnvorkommen")
Node(186, 75,  1733, "Silver Vein", "Silbervorkommen")
Node(186, 125, 1735, "Iron Deposit", "Eisenvorkommen")
Node(186, 155, 1734, "Gold Vein", "Goldvorkommen")
Node(186, 175, 2040, "Mithril Deposit", "Mithrilvorkommen")
Node(186, 230, 2047, "Truesilver Deposit", "Echtsilbervorkommen")
Node(186, 230, 165658, "Dark Iron Deposit", "Dunkeleisenvorkommen")
Node(186, 245, 324, "Small Thorium Vein", "Kleines Thoriumvorkommen")
Node(186, 275, 175404, "Rich Thorium Vein", "Reiches Thoriumvorkommen")
Node(186, 175, 123310, "Ooze Covered Mithril Deposit", "Brühschlammbedecktes Mithrilvorkommen")
Node(186, 230, 123309, "Ooze Covered Truesilver Deposit", "Brühschlammbedecktes Echtsilbervorkommen")
Node(186, 245, 123848, "Ooze Covered Thorium Vein", "Brühschlammbedecktes Thoriumvorkommen")
Node(186, 275, 177388, "Ooze Covered Rich Thorium Vein", "Brühschlammbedecktes reiches Thoriumvorkommen")
