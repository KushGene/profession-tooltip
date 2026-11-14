-- Run from the repository root: luajit Tools/test_unlearned_difficulty.lua
local events = {}
CreateFrame = function()
    return {
        RegisterEvent = function() end,
        SetScript = function(_, _, callback) events.dispatch = callback end,
    }
end
wipe = function(t) for key in pairs(t) do t[key] = nil end end
Enum = { TooltipDataType = { Item = 0 } }
GameTooltip, ItemRefTooltip = {}, {}
TooltipDataProcessor = { AddTooltipPostCall = function() end }
IsShiftKeyDown = function() return false end
GetTime = function() return 0 end
C_Item = { GetItemNameByID = function() return "Ingredient" end }

local ns = {}
assert(loadfile("Core.lua"))("Test", ns)
events.dispatch(nil, "ADDON_LOADED", "Test")
assert(ns.db.showUnlearnedDifficulty == false, "new option must default to off")
assert(ns.db.showSkillDifficulty == true, "skill difficulty must default to on")
assert(ns.db.showUnownedRequirements == false, "requirements for unlearned professions must default to hidden")
local rank = 120
ns.GetProfessionRank = function() return rank, 300 end
ns.GetProfession = function() return { id = 185, icon = "Cooking", order = 1 } end
ns.GetProfessionName = function() return "Cooking" end
ns.IsProfessionShown = function() return true end
ns.HasProfession = function() return true end
ns.GetSpellName = function() end
ns.IsSpellKnown = function() return false end
ns.GetAltsKnowing = function() return { "TestAlt" } end
ns.char.scanned[185] = true
assert(loadfile("Locales/enUS.lua"))("Test", ns)
assert(loadfile("Database.lua"))("Test", ns)
ns.RegisterRecipes(185, {
    [1] = { 100, "Catfish", { 10, 2 }, 20, 140, 160, 180 },
    [2] = { 100, "Missing thresholds", { 11, 1 }, 21 },
    [3] = { 100, "Partial thresholds", { 12, 1 }, 22, 140 },
})
assert(loadfile("Tooltip.lua"))("Test", ns)
ns.db.hideTrivialKnownOnShift = false
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function tooltip(itemID)
    local lines = {}
    ns.AddTooltipLines({ AddLine = function(_, line) lines[#lines + 1] = line end }, itemID or 10)
    return table.concat(lines, "\n")
end
local function contains(text, part) return text:find(part, 1, true) ~= nil end
local function setRank(value)
    rank = value
    ns.Fire("DATA_CHANGED")
end

check(contains(tooltip(), "|cffaaaaaaCatfish|r"), "default unlearned name must stay gray")
check(contains(tooltip(), "|cffff8000(100)|r"), "default unlearned skill label must use difficulty")
ns.SetOption("showSkillDifficulty", false)
check(contains(tooltip(), "|cffaaaaaa(100)|r"), "skill color can be disabled independently")
ns.SetOption("showSkillDifficulty", true)
ns.SetOption("showUnlearnedDifficulty", true)
for _, case in ipairs({
    { 99, 0, "ffff8000" }, { 120, 0, "ffff8000" }, { 139, 0, "ffff8000" },
    { 140, 1, "ffffff00" }, { 159, 1, "ffffff00" },
    { 160, 2, "ff40c040" }, { 179, 2, "ff40c040" }, { 180, 3, "ff808080" },
}) do
    setRank(case[1])
    local text = tooltip()
    check(ns.GetRecipeDifficulty(1) == case[2], "wrong threshold at " .. case[1])
    check(contains(text, "|c" .. case[3] .. "Catfish|r"), "wrong tooltip color at " .. case[1])
    check(contains(text, "(Not known)"), "ungrouped unlearned recipe must be marked")
    check(ns.GetKnownDifficulty(1) == nil, "color must not mark recipe learned")
    check(contains(text, "0/1 known"), "known count must not change")
    if case[1] >= 100 then
        check(contains(text, "|c" .. case[3] .. "(100)|r"), "skill label must use difficulty at " .. case[1])
    end
end
setRank(99)
ns.SetOption("showAltKnown", true)
check(contains(tooltip(), "|cffff5050(100)|r"), "too-low required skill must stay red")
check(contains(tooltip(), "TestAlt"), "unlearned alt information must remain")
ns.SetOption("groupByKnown", true)
check(contains(tooltip(), "Not known"), "grouped status must remain")
check(not contains(tooltip(), "(Not known)"), "group header already marks unlearned recipes")
ns.SetOption("groupByKnown", false)
ns.SetOption("unknownFilter", "learnable")
check(tooltip() == "" or not contains(tooltip(), "Catfish"), "learnable filter must still apply")
ns.SetOption("unknownFilter", "noGray")
setRank(180)
check(not contains(tooltip(), "Catfish"), "gray filter must still apply")
ns.SetOption("unknownFilter", "all")

setRank(nil)
check(ns.GetRecipeDifficulty(1) == nil, "no profession rank must yield unknown difficulty")
check(contains(tooltip(), "|cffaaaaaaCatfish|r"), "no rank must keep name gray")
setRank(120)
for _, id in ipairs({ 2, 3 }) do
    check(ns.GetRecipeDifficulty(id) == nil, "missing thresholds must not invent difficulty")
end
check(contains(tooltip(11), "|cffaaaaaaMissing thresholds|r"), "missing thresholds must stay gray")
check(contains(tooltip(12), "|cffaaaaaaPartial thresholds|r"), "partial thresholds must stay gray")

ns.SetOption("showCraftedBy", true)
check(contains(tooltip(20), "|cffff8000Catfish|r"), "crafted section must use unlearned difficulty")
check(contains(tooltip(20), "(Not known)"), "crafted section must preserve unlearned status")
check(contains(tooltip(20), "|cffff8000(100)|r"), "crafted skill label must use difficulty")
ns.SetOption("showSkillDifficulty", false)
check(contains(tooltip(), "|cffff8000Catfish|r"), "disabling skill colors must preserve enabled name colors")
check(contains(tooltip(), "|cffaaaaaa(100)|r"), "disabled skill color must stay neutral")
ns.SetOption("showSkillDifficulty", true)
ns.char.known[1] = 2
ns.Fire("DATA_CHANGED")
check(ns.GetKnownDifficulty(1) == 0, "learned recipe must use current rank")
check(not contains(tooltip(), "(Not known)"), "known recipe must not get unlearned label")
check(not contains(tooltip(), "(100)"), "showSkillKnown=false must still hide learned skill")
ns.SetOption("showSkillKnown", true)
check(contains(tooltip(), "|cffff8000(100)|r"), "known skill label must use difficulty too")
ns.SetOption("showSkillDifficulty", false)
check(contains(tooltip(), "|cffaaaaaa(100)|r"), "known skill label color can be disabled")
ns.SetOption("showSkillDifficulty", true)
ns.SetOption("showUnlearnedDifficulty", false)
check(contains(tooltip(), "|cffff8000Catfish|r"), "option must not change learned colors")
ns.char.known[1] = nil
ns.Fire("DATA_CHANGED")
check(contains(tooltip(), "|cffaaaaaaCatfish|r"), "disabling must restore old appearance")
check(not contains(tooltip(), "(Not known)"), "disabled option must preserve old labels")
ns.char.known[3] = 2
check(ns.GetKnownDifficulty(3) == 2, "incomplete thresholds must fall back to scanned difficulty")
-- Header details must use a ruRU-font-safe separator, and only between two details.
GetLocale = function() return "ruRU" end
assert(loadfile("Locales/ruRU.lua"))("Test", ns)
for _, style in ipairs({ "icon", "name", "both" }) do
    ns.SetOption("headerStyle", style)
    for _, options in ipairs({
        { true, true, "120/300  •  " .. string.format(ns.L.KNOWN_OF, 0, 1) },
        { true, false, "120/300" },
        { false, true, string.format(ns.L.KNOWN_OF, 0, 1) },
        { false, false },
    }) do
        ns.SetOption("showProfessionRank", options[1])
        ns.SetOption("showKnownCount", options[2])
        local text = tooltip()
        local header = text:match("^%s*([^\n]+)") or ""
        check(not contains(header, "·"), "header must not use the unsupported middle dot")
        if options[3] then
            check(contains(header, "|cff888888" .. options[3] .. "|r"), "wrong header details for " .. style)
        else
            check(not contains(header, "|cff888888"), "disabled details must not appear")
        end
        check(contains(header, "•") == (options[1] and options[2]), "separator requires both header details")
    end
end
print("Unlearned difficulty tests passed (" .. checks .. " checks)")
