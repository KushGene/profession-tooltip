-- Data/Skinning.lua
-- Automatisch erzeugt von Tools/build_data.py aus dem Client (WOW-70450patch1.60.1_ForeverBeta).
-- Nicht von Hand bearbeiten, sondern das Skript erneut ausführen.
local _, ns = ...

-- [spellID] = { benötigterSkill (0 = unbekannt), "Fallback-Name", { itemID, Menge, ... },
--               hergestelltesItem (0 = keins), gelbAb, grünAb, grauAb }
ns.RegisterRecipes(393, {
    [1229517] = { 0, "Camp Chair", { 2318, 3, 4470, 2 }, 279979, 20, 23, 25 },
    [1262985] = { 140, "Field Guide", { 2319, 3, 5784, 2, 2321, 1 }, 279969, 140, 143, 145 },
    [1262982] = { 300, "Trapper's Workbench", { 4470, 2, 4234, 4, 3575, 1 }, 279938, 300, 300, 300 },
})
