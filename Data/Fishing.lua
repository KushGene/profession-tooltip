-- Data/Fishing.lua
-- Generated automatically by Tools/build_data.py from the client (WOW-70450patch1.60.1_ForeverBeta).
-- Do not edit by hand; run the script again instead.
local _, ns = ...

-- [spellID] = { requiredSkill (0 = unknown), "fallback name", { itemID, count, ... },
--               createdItem (0 = none), yellowAt, greenAt, grayAt }
ns.RegisterRecipes(356, {
    [1229745] = { 0, "Fish Bowl", { 6291, 1, 3371, 1 }, 279967, 20, 20, 20 },
    [1262990] = { 140, "Fishing Rack", { 4470, 2, 8925, 1, 8365, 2 }, 279965, 140, 143, 145 },
    [1262998] = { 300, "Fishing Hut", { 4470, 5, 14048, 2, 273295, 1 }, 279966, 300, 300, 300 },
})
