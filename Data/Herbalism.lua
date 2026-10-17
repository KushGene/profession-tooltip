-- Data/Herbalism.lua
-- Generated automatically by Tools/build_data.py from the client (WOW-70450patch1.60.1_ForeverBeta).
-- Do not edit by hand; run the script again instead.
local _, ns = ...

-- [spellID] = { requiredSkill (0 = unknown), "fallback name", { itemID, count, ... },
--               createdItem (0 = none), yellowAt, greenAt, grayAt }
ns.RegisterRecipes(182, {
    [1229705] = { 0, "Incense Candle", { 2447, 1, 765, 1 }, 279962, 20, 23, 25 },
    [1262980] = { 140, "Greenhouse", { 4470, 2, 8836, 1, 8831, 1 }, 279964, 140, 143, 145 },
    [1263070] = { 300, "Seed Hybridizer", { 13465, 4, 8925, 1, 14047, 2 }, 279947, 300, 300, 300 },
})
