-- Data/FirstAid.lua
-- Automatisch erzeugt von Tools/build_data.py aus dem Client (WOW-70450patch1.60.1_ForeverBeta).
-- Nicht von Hand bearbeiten, sondern das Skript erneut ausführen.
local _, ns = ...

-- [spellID] = { benötigterSkill (0 = unbekannt), "Fallback-Name", { itemID, Menge, ... },
--               hergestelltesItem (0 = keins), gelbAb, grünAb, grauAb }
ns.RegisterRecipes(129, {
    [30021] = { 0, "Crystal Infused Bandage", { 23567, 1, 14047, 10 }, 23684, 300, 330, 360 },
    [1230117] = { 0, "First Aid Kit", { 1251, 3, 159, 1 }, 279968, 20, 23, 25 },
    [1244431] = { 0, "Minor Healing Potion", { 3371, 1, 2678, 1, 2447, 1 }, 118, 55, 75, 95 },
    [1244432] = { 0, "Lesser Healing Potion", { 3371, 1, 2678, 2, 2450, 1 }, 858, 85, 105, 125 },
    [1244433] = { 0, "Healing Potion", { 3372, 1, 2692, 1, 2453, 1 }, 929, 135, 155, 175 },
    [1259342] = { 0, "Simple Poultice", { 3174, 1, 2678, 1, 2723, 1 }, 255716, 90, 125, 160 },
    [1259347] = { 0, "Woolen Tourniquet", { 2592, 2, 2321, 2 }, 255720, 120, 155, 190 },
    [3275] = { 1, "Linen Bandage", { 2589, 1 }, 1251, 30, 45, 60 },
    [3276] = { 40, "Heavy Linen Bandage", { 2589, 2 }, 2581, 50, 75, 100 },
    [3277] = { 80, "Wool Bandage", { 2592, 1 }, 3530, 80, 115, 150 },
    [7934] = { 80, "Anti-Venom", { 1475, 1 }, 6452, 80, 115, 150 },
    [3278] = { 115, "Heavy Wool Bandage", { 2592, 2 }, 3531, 115, 150, 185 },
    [7935] = { 130, "Strong Anti-Venom", { 1288, 1 }, 6453, 130, 165, 200 },
    [1259343] = { 140, "Clever Poultice", { 1468, 1, 3713, 1, 2686, 1 }, 255717, 160, 190, 220 },
    [1262996] = { 140, "Toxin Study", { 6452, 1, 8544, 2, 4470, 2 }, 279940, 140, 143, 145 },
    [7928] = { 150, "Silk Bandage", { 4306, 1 }, 6450, 150, 180, 210 },
    [1244434] = { 155, "Greater Healing Potion", { 3372, 1, 2692, 3, 3357, 1 }, 1710, 175, 195, 215 },
    [7929] = { 180, "Heavy Silk Bandage", { 4306, 2 }, 6451, 180, 210, 240 },
    [1259348] = { 200, "Leather Tourniquet", { 4304, 2, 4291, 2 }, 255721, 220, 250, 280 },
    [10840] = { 210, "Mageweave Bandage", { 4338, 1 }, 8544, 210, 240, 270 },
    [1259344] = { 210, "Superior Poultice", { 7070, 1, 2692, 1, 2596, 1 }, 255718, 225, 255, 285 },
    [1244435] = { 215, "Superior Healing Potion", { 8925, 1, 3713, 1, 8838, 1 }, 3928, 230, 250, 270 },
    [1259341] = { 215, "Potent Anti-Venom", { 255645, 1 }, 255715, 230, 260, 290 },
    [10841] = { 240, "Heavy Mageweave Bandage", { 4338, 2 }, 8545, 240, 270, 300 },
    [18629] = { 260, "Runecloth Bandage", { 14047, 1 }, 14529, 260, 290, 320 },
    [1259349] = { 265, "Surgical Tourniquet", { 8170, 2, 14047, 2, 8343, 2 }, 255722, 280, 310, 340 },
    [1244436] = { 275, "Major Healing Potion", { 8925, 1, 3713, 3, 13464, 1 }, 13446, 290, 310, 330 },
    [1259345] = { 280, "Powerful Poultice", { 7080, 1, 2692, 1, 2594, 1 }, 255719, 295, 325, 355 },
    [18630] = { 290, "Heavy Runecloth Bandage", { 14047, 2 }, 14530, 290, 320, 350 },
    [23787] = { 300, "Powerful Anti-Venom", { 19441, 1 }, 19440, 300, 330, 360 },
    [470349] = { 300, "Dense Runecloth Bandage", { 14530, 2 }, 232433, 315, 328, 340 },
    [1263001] = { 300, "Plague Doctor's Laboratory", { 4470, 2, 6453, 2, 14530, 5 }, 279951, 300, 300, 300 },
})
