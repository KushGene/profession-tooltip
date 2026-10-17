-- Data/Mining.lua
-- Automatisch erzeugt von Tools/build_data.py aus dem Client (WOW-70450patch1.60.1_ForeverBeta).
-- Nicht von Hand bearbeiten, sondern das Skript erneut ausführen.
local _, ns = ...

-- [spellID] = { benötigterSkill (0 = unbekannt), "Fallback-Name", { itemID, Menge, ... },
--               hergestelltesItem (0 = keins), gelbAb, grünAb, grauAb }
ns.RegisterRecipes(186, {
    [14891] = { 0, "Smelt Dark Iron", { 11370, 8 }, 11371, 230, 230, 230 },
    [22967] = { 0, "Smelt Elementium", { 18562, 1, 12360, 10, 17010, 1, 18567, 3 }, 17771, 310, 315, 320 },
    [1230161] = { 0, "Lodestone", { 2835, 1, 2840, 1 }, 279960, 20, 23, 25 },
    [1249637] = { 0, "Smelt Azerothium", { 249426, 2, 3857, 1 }, 249726, 275, 275, 275 },
    [1306126] = { 0, "Smelt Heavy Thorium", { 248815, 1 }, 251291, 300, 308, 315 },
    [2657] = { 1, "Smelt Copper", { 2770, 1 }, 2840, 25, 48, 70 },
    [2659] = { 65, "Smelt Bronze", { 2840, 1, 3576, 1 }, 2841, 65, 90, 115 },
    [3304] = { 65, "Smelt Tin", { 2771, 1 }, 3576, 50, 63, 75 },
    [2658] = { 75, "Smelt Silver", { 2775, 1 }, 2842, 100, 113, 125 },
    [3307] = { 125, "Smelt Iron", { 2772, 1 }, 3575, 130, 135, 140 },
    [1262975] = { 140, "Rock Garden", { 2838, 2, 2772, 1, 2842, 1 }, 279948, 140, 143, 145 },
    [3308] = { 155, "Smelt Gold", { 2776, 1 }, 3577, 170, 178, 185 },
    [3569] = { 165, "Smelt Steel", { 3575, 1, 3857, 1 }, 3859, 165, 165, 165 },
    [10097] = { 175, "Smelt Mithril", { 3858, 1 }, 3860, 175, 175, 175 },
    [10098] = { 230, "Smelt Truesilver", { 7911, 1 }, 6037, 230, 230, 230 },
    [16153] = { 250, "Smelt Thorium", { 10620, 1 }, 12359, 250, 250, 250 },
    [1263071] = { 300, "Molten Foundry", { 12359, 5, 12365, 2, 6037, 1 }, 279952, 300, 300, 300 },
})
