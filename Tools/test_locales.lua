-- Run from the repository root: luajit Tools/test_locales.lua
local keys = {
    "SECTION_RECIPE_COLORS", "OPT_SKILL_DIFFICULTY", "OPT_SKILL_DIFFICULTY_DESC",
    "OPT_UNLEARNED_DIFFICULTY", "OPT_UNLEARNED_DIFFICULTY_DESC",
}
local files = { "deDE", "frFR", "esES", "ruRU", "ptBR", "koKR", "zhCN", "zhTW" }
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
        if locale ~= "enUS" and locale ~= "enGB" then
            assert(ns.L[key] ~= english[key], locale .. ": English fallback for " .. key)
        end
        checks = checks + 1
    end
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
