-- Data/Herbalism.lua
-- Generated automatically by Tools/build_data.py from the client (WOW-70938patch1.60.1_Retail).
-- Do not edit by hand; run the script again instead.
local _, ns = ...

-- [spellID] = { requiredSkill (0 = unknown), "fallback name", { itemID, count, ... },
--               createdItem (0 = none), yellowAt, greenAt, grayAt }
ns.RegisterRecipes(182, {
    [1229705] = { 20, "Incense Candle", { 2447, 1, 765, 1 }, 279962, 20, 20, 20 },
    [1262980] = { 140, "Greenhouse", { 4470, 2, 8836, 1, 8831, 1 }, 279964, 140, 140, 140 },
    [1263070] = { 300, "Seed Hybridizer", { 13465, 4, 8925, 1, 14047, 2 }, 279947, 300, 300, 300 },
})
