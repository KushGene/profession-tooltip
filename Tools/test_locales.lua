-- Run from the repository root: luajit Tools/test_locales.lua
local keys = {
    "SECTION_RECIPE_COLORS", "OPT_SKILL_DIFFICULTY", "OPT_SKILL_DIFFICULTY_DESC",
    "OPT_UNLEARNED_DIFFICULTY", "OPT_UNLEARNED_DIFFICULTY_DESC",
    "OPT_UNOWNED_REQUIREMENTS", "OPT_UNOWNED_REQUIREMENTS_DESC",
    "MINIMAP_TOOLTIP_RIGHT", "RECIPES_TITLE", "RECIPES_FILTER", "RECIPES_LEARNABLE", "RECIPES_LEARNABLE_DESC",
    "RECIPES_SUMMARY", "RECIPES_SHOWN", "RECIPES_EMPTY", "OPT_RECIPE_SOURCE", "OPT_RECIPE_SOURCE_DESC",
    "SOURCE_TRAINER", "SOURCE_VENDOR", "SOURCE_OTHER", "SOURCE_AUTO", "SOURCE_ITEM", "SOURCE_LIMITED",
    "SOURCE_MORE_VENDORS", "SOURCE_UNKNOWN", "SOURCE_UNCERTAIN", "SOURCE_CREDIT",
    "SOURCE_WORLD_DROP", "RECIPES_CLICK_MAP",
    "OPT_DARKMOON", "OPT_DARKMOON_DESC", "DARKMOON_FAIRE", "DARKMOON_MIN_LEVEL", "OPT_SURNAME", "OPT_SURNAME_DESC",
    "DARKMOON_TURNIN", "DARKMOON_TICKET", "DARKMOON_TICKETS",
    "OPT_CRAFT_COST", "OPT_CRAFT_COST_DESC", "CRAFT_COST", "CRAFT_COST_MISSING", "NEW_BADGE",
}
local files = { "deDE", "frFR", "esES", "ruRU", "ptBR", "koKR", "zhCN", "zhTW" }
-- Translations that are the same word as in English
local sameAsEnglish = { frFR = { DARKMOON_TICKET = true, DARKMOON_TICKETS = true } }
local checks = 0
for _, locale in ipairs({ "enUS", "enGB", "deDE", "frFR", "esES", "esMX", "ruRU", "ptBR", "ptPT", "koKR", "zhCN", "zhTW" }) do
    GetLocale = function() return locale end
    local ns = {}
    assert(loadfile("Locales/enUS.lua"))("Test", ns)
    local english = {}
    for _, key in ipairs(keys) do english[key] = ns.L[key] end
    for _, file in ipairs(files) do assert(loadfile("Locales/" .. file .. ".lua"))("Test", ns) end
    for _, key in ipairs(keys) do
        assert(type(ns.L[key]) == "string" and ns.L[key] ~= "" and ns.L[key] ~= key, locale .. ": missing " .. key)
        if locale ~= "enUS" and locale ~= "enGB" and not (sameAsEnglish[locale] and sameAsEnglish[locale][key]) then
            assert(ns.L[key] ~= english[key], locale .. ": English fallback for " .. key)
        end
        checks = checks + 1
    end
    -- Texts the code fills in must keep their placeholders in every language
    for key, count in pairs({ RECIPES_SUMMARY = 2, RECIPES_SHOWN = 1, SOURCE_MORE_VENDORS = 1, DARKMOON_MIN_LEVEL = 1, DARKMOON_TICKETS = 1, DARKMOON_TURNIN = 1, CRAFT_COST_MISSING = 1 }) do
        local _, found = ns.L[key]:gsub("%%d", "")
        assert(found == count and not ns.L[key]:find("%%%d%$"), locale .. ": placeholders of " .. key)
    end
    assert(select(2, ns.L.SOURCE_WORLD_DROP:gsub("%%s", "")) == 1, locale .. ": placeholder of SOURCE_WORLD_DROP")
    assert(select(2, ns.L.DARKMOON_TURNIN:gsub("%%s", "")) == 1 and ns.L.DARKMOON_TURNIN:find("%%d.*%%s"),
        locale .. ": placeholders of DARKMOON_TURNIN (count before reward)")
    -- "→" (U+2192) is missing in the game fonts and shows as a box
    for key, text in pairs(ns.L) do
        assert(type(text) ~= "string" or not text:find("\226\134\146", 1, true), locale .. ": arrow in " .. tostring(key))
    end
    assert(ns.L.SOURCE_CREDIT:find("ForeverDB.net (https://foreverdb.net)", 1, true), locale .. ": source credit")
    assert(ns.L.SOURCE_DROP ~= "SOURCE_DROP" and ns.L.SOURCE_QUEST ~= "SOURCE_QUEST"
        and ns.L.SOURCE_REPUTATION ~= "SOURCE_REPUTATION" and ns.L.SOURCE_FAVOR ~= "SOURCE_FAVOR", locale .. ": source labels")
    assert(ns.L.SECTION_UNKNOWN ~= "SECTION_UNKNOWN", locale .. ": missing unlearned status")
    for _, key in ipairs({ "ALCHEMY", "BLACKSMITHING", "ENCHANTING", "ENGINEERING", "LEATHERWORKING", "TAILORING",
        "MINING", "HERBALISM", "SKINNING", "COOKING", "FIRST_AID", "FISHING" }) do
        local name = ns.L["PROFESSION_" .. key]
        assert(name ~= "PROFESSION_" .. key and name ~= "", locale .. ": missing profession name " .. key)
    end
    if locale ~= "enUS" and locale ~= "enGB" then
        assert(ns.L.PROFESSION_MINING ~= "Mining", locale .. ": profession names must be translated")
    end
end
print("Locale tests passed (12 locales, " .. checks .. " translated settings checked)")
