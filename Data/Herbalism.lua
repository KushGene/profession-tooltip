-- Data/Herbalism.lua
-- Automatisch erzeugt von Tools/build_data.py aus dem Client (WOW-70450patch1.60.1_ForeverBeta).
-- Nicht von Hand bearbeiten, sondern das Skript erneut ausführen.
local _, ns = ...

-- [spellID] = { benötigterSkill (0 = unbekannt), "Fallback-Name", { itemID, Menge, ... },
--               hergestelltesItem (0 = keins), gelbAb, grünAb, grauAb }
ns.RegisterRecipes(182, {
    [1229705] = { 0, "Incense Candle", { 2447, 1, 765, 1 }, 279962, 20, 23, 25 },
    [1262980] = { 140, "Greenhouse", { 4470, 2, 8836, 1, 8831, 1 }, 279964, 140, 143, 145 },
    [1263070] = { 300, "Seed Hybridizer", { 13465, 4, 8925, 1, 14047, 2 }, 279947, 300, 300, 300 },
})
