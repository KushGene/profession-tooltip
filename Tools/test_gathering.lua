-- Run from the repository root: luajit Tools/test_gathering.lua
local callbacks, scripts = {}, {}
Enum = { TooltipDataType = { Item = 0, Unit = 2, Object = 4 } }
TooltipDataProcessor = { AddTooltipPostCall = function(kind, callback) callbacks[kind] = callback end }
LOCKED_WITH_SPELL = "Benötigt %s"
UNIT_SKINNABLE_LEATHER = "Häutbar" -- the client has no SKINNABLE global
local level = 25
UnitLevel = function(unit) assert(unit == "mouseover"); return level end
strsplit = function(separator, text)
    local parts = {}
    for part in (text .. separator):gmatch("(.-)%" .. separator) do parts[#parts + 1] = part end
    return unpack(parts)
end
local clientLocale = "deDE"
GetLocale = function() return clientLocale end
issecretvalue = function(value) return value == "SECRET" end
local ns = { db = { disabledProfessions = {} } }
local owned = { [182] = true, [186] = true, [393] = true }
ns.HasProfession = function(id) return owned[id] == true end
ns.Professions = { { id = 182 }, { id = 186 }, { id = 393 }, { id = 333 } }
ns.GetProfessionName = function(id)
    return ({ [182] = "Kräuterkunde", [186] = "Bergbau", [393] = "Kürschnerei", [333] = "Verzauberkunst" })[id]
end
local lines, data, unit, shows
GameTooltip = {
    GetName = function() return "GameTooltip" end,
    GetTooltipData = function() return data end,
    GetUnit = function() return "Creature", unit end,
    NumLines = function() return #lines end,
    Show = function() shows = shows + 1 end,
    HookScript = function(_, event, callback) scripts[event] = callback end,
}
assert(loadfile("Data/Gathering.lua"))("Test", ns)
assert(loadfile("GatheringTooltip.lua"))("Test", ns)
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function setup(title, label, kind, id, token, color)
    data, unit, shows = { type = kind or 4, id = id }, token, 0
    lines = {}
    for i, text in ipairs({ title, label }) do
        local line = { text = text, color = color or { 1, 0.1, 0.1 } }
        function line:GetText() return self.text end
        function line:SetText(value) self.text = value end
        function line:GetTextColor() return unpack(self.color) end
        lines[i] = line
        _G["GameTooltipTextLeft" .. i] = line
    end
end
setup("Königsblut", "Kräuterkunde")
callbacks[4](GameTooltip, data)
check(lines[2].text == "Kräuterkunde (125)", "German herb must show required skill before clicking")
check(shows == 1, "changed tooltip must be resized")
callbacks[4](GameTooltip, data)
scripts.OnUpdate(GameTooltip, 0.2)
check(lines[2].text == "Kräuterkunde (125)" and shows == 1, "must not duplicate numbers or resize repeatedly")
lines[2].text = "Kräuterkunde"
scripts.OnUpdate(GameTooltip, 0.2)
check(lines[2].text == "Kräuterkunde (125)", "native redraw must regain requirement")
setup("Eisenvorkommen", "Bergbau")
check(ns.EnhanceGatheringTooltip(GameTooltip), "German ore must be recognized")
check(lines[2].text == "Bergbau (125)", "iron requires 125")
setup("Kingsblood", "Benötigt Kräuterkunde")
ns.EnhanceGatheringTooltip(GameTooltip)
check(lines[2].text == "Benötigt Kräuterkunde (125)", "localized Requires label must work")
setup("Localized node", "Kräuterkunde", 4, 1624)
ns.EnhanceGatheringTooltip(GameTooltip)
check(lines[2].text == "Kräuterkunde (125)", "object IDs must work regardless of node language")
setup("Localized node", "Kräuterkunde", 4, 1622)
ns.EnhanceGatheringTooltip(GameTooltip)
check(lines[2].text == "Kräuterkunde (100)", "object 1622 is Bruiseweed (100), not Kingsblood")
setup("Localized node", "Bergbau", 4, 103713)
ns.EnhanceGatheringTooltip(GameTooltip)
check(lines[2].text == "Bergbau (1)", "alternative object IDs of a node must be known")
setup("Localized node", "Bergbau", 4)
data.guid = "GameObject-0-4444-0-12-1735-00006A1B2C"
ns.EnhanceGatheringTooltip(GameTooltip)
check(lines[2].text == "Bergbau (125)", "object ID must also be read from the object GUID")
check(SKINNABLE == nil, "the test must not rely on a SKINNABLE global the client doesn't have")
data = nil
lines = { lines[1], lines[2] }
lines[2].text = "Bergbau"
scripts.OnUpdate(GameTooltip, 0.2)
check(lines[2].text == "Bergbau", "tooltips without data must be left alone")
setup("Unknown Forever Herb", "Kräuterkunde")
check(not ns.EnhanceGatheringTooltip(GameTooltip), "unknown nodes must not guess requirements")
setup("Königsblut", "Kräuterkunde", 0)
check(not ns.EnhanceGatheringTooltip(GameTooltip), "items must not be changed")
setup("Königsblut", "Kräuterkunde", 4, nil, nil, { 1, 0.5, 0 })
check(not ns.EnhanceGatheringTooltip(GameTooltip), "orange labels must remain unchanged")
setup("Königsblut", "Kräuterkunde", 4, nil, nil, { 0, 1, 0 })
check(not ns.EnhanceGatheringTooltip(GameTooltip), "green labels must remain unchanged")
ns.db.disabledProfessions[182] = true
setup("Königsblut", "Kräuterkunde")
check(not ns.EnhanceGatheringTooltip(GameTooltip), "disabled professions must be respected")
ns.db.disabledProfessions[182] = nil
setup("Wolf", "Häutbar", 2, nil, "mouseover")
callbacks[2](GameTooltip, data)
check(lines[2].text == "Häutbar (125)", "skinnable creature must use its tooltip unit level")
for _, case in ipairs({ { 1, 1 }, { 10, 1 }, { 11, 10 }, { 19, 90 }, { 20, 100 }, { 21, 105 }, { 60, 300 }, { 63, 315 } }) do
    check(ns.GetSkinningRequirement(case[1]) == case[2], "wrong skinning rank at level " .. case[1])
end
for _, unknown in ipairs({ -1, 0, "SECRET", false }) do
    check(ns.GetSkinningRequirement(unknown) == nil, "unknown/secret creature levels must be ignored")
end
level = -1
setup("Boss", "Häutbar", 2, nil, "mouseover")
check(not ns.EnhanceGatheringTooltip(GameTooltip), "boss level must not become a false requirement")
level = 25
setup("Wolf", "Häutbar", 2)
check(not ns.EnhanceGatheringTooltip(GameTooltip), "must not guess a mouseover unit for unrelated tooltip")
setup("Wolf", "Level 25", 2, nil, "mouseover")
check(not ns.EnhanceGatheringTooltip(GameTooltip), "non-skinnable creature must remain unchanged")
setup("SECRET", "SECRET", 4, "SECRET")
check(not ns.EnhanceGatheringTooltip(GameTooltip), "secret values must be ignored")
check(not ns.EnhanceGatheringTooltip({}), "other tooltips must remain unchanged")
setup("Königsblut", "Kräuterkunde", 4, nil, nil, { "SECRET", "SECRET", "SECRET" })
check(not ns.EnhanceGatheringTooltip(GameTooltip), "secret colors must not be compared")
-- The game doesn't always word the requirement with the profession's name: a single red
-- line on a known node is the requirement, in any language
setup("Eisenvorkommen", "Erzabbau erforderlich")
check(ns.EnhanceGatheringTooltip(GameTooltip) and lines[2].text == "Erzabbau erforderlich (125)",
    "a differently worded red requirement must still get its number")
check(not ns.EnhanceGatheringTooltip(GameTooltip) and lines[2].text == "Erzabbau erforderlich (125)",
    "a differently worded requirement must not get its number twice")
-- Node names of every supported client language
for locale, title in pairs({ frFR = "Filon de cuivre", esES = "Filón de cobre", esMX = "Filón de cobre",
    ruRU = "Медная жила", ptBR = "Veio de Cobre", ptPT = "Veio de Cobre", koKR = "구리 광맥",
    zhCN = "铜矿", zhTW = "銅礦", enGB = "Copper Vein", itIT = "Copper Vein" }) do
    clientLocale = locale
    assert(loadfile("Data/Gathering.lua"))("Test", ns)
    setup(title, "Bergbau")
    check(ns.EnhanceGatheringTooltip(GameTooltip) and lines[2].text == "Bergbau (1)", locale .. ": node name must be known")
    if locale ~= "enGB" and locale ~= "itIT" then
        setup("Kupfervorkommen", "Bergbau")
        check(not ns.EnhanceGatheringTooltip(GameTooltip), locale .. ": names of other languages must not be loaded")
    end
end
-- Unowned native requirements are hidden by default, without touching other red lines.
ITEM_DISENCHANT_MIN_SKILL = "Entzaubern benötigt %s [%d]"
ITEM_REQ_SKILL = "Benötigt %s (%d)"
setup("Grünes Item", "Entzaubern benötigt Verzauberkunst [1]", 0)
callbacks[0](GameTooltip, data)
check(lines[2].text == nil and shows == 1, "unowned disenchant requirement must be hidden")
callbacks[0](GameTooltip, data)
check(shows == 1, "hidden requirement must not repeatedly resize")
lines[2].text = "Entzaubern benötigt Verzauberkunst [1]"
scripts.OnUpdate(GameTooltip, 0.2)
check(lines[2].text == nil, "redraws must not restore unowned requirements")
ns.db.showUnownedRequirements = true
setup("Grünes Item", "Entzaubern benötigt Verzauberkunst [1]", 0)
callbacks[0](GameTooltip, data)
check(lines[2].text == "Entzaubern benötigt Verzauberkunst [1]", "opt-in must preserve foreign requirements")
ns.db.showUnownedRequirements = false
owned[333] = true
check(not ns.FilterProfessionRequirements(GameTooltip, data), "own profession requirements must remain visible")
owned[333] = nil
for _, text in ipairs({ "Benötigt Stufe 60", "Klassen: Magier", "Verzauberkunst ist nützlich",
    "Benötigt Verzauberkunst (100) zum Benutzen" }) do
    setup("Item", text, 0)
    check(not ns.FilterProfessionRequirements(GameTooltip, data) and lines[2].text == text,
        "unrelated requirements must not be hidden: " .. text)
end
setup("Item", "Benötigt Verzauberkunst (100)", 0)
check(ns.FilterProfessionRequirements(GameTooltip, data) and lines[2].text == nil,
    "native skill requirements must be hidden for unowned professions")
setup("Item", "Entzaubern benötigt Verzauberkunst [1]", 0, nil, nil, { 0, 1, 0 })
check(not ns.FilterProfessionRequirements(GameTooltip, data), "non-red requirements must remain unchanged")
setup("Item", "Entzaubern benötigt Verzauberkunst [1]", 0, nil, nil, { "SECRET", "SECRET", "SECRET" })
check(not ns.FilterProfessionRequirements(GameTooltip, data), "secret colors must remain untouched")
setup("Item", "SECRET", 0)
check(not ns.FilterProfessionRequirements(GameTooltip, data), "secret text must remain untouched")
setup("Item", "Entzaubern benötigt Verzauberkunst [1]", 0)
data = nil
check(not ns.FilterProfessionRequirements(GameTooltip), "plain tooltips must remain untouched")
check(not ns.FilterProfessionRequirements({}), "other tooltips must remain untouched")
for _, format in ipairs({ "Disenchanting requires %s (%d)", "Распыление: %1$s [%2$d]" }) do
    ITEM_DISENCHANT_MIN_SKILL = format
    local text = format:gsub("%%[%d%$]*s", "Verzauberkunst"):gsub("%%[%d%$]*d", "1")
    setup("Item", text, 0)
    check(ns.FilterProfessionRequirements(GameTooltip, data), "localized requirement format must match")
end
clientLocale = "deDE"
assert(loadfile("Data/Gathering.lua"))("Test", ns)
for _, case in ipairs({
    { 182, "Königsblut", "Kräuterkunde", 4 },
    { 186, "Eisenvorkommen", "Bergbau", 4 },
    { 393, "Wolf", "Häutbar", 2, "mouseover" },
}) do
    owned[case[1]] = nil
    setup(case[2], case[3], case[4], nil, case[5])
    check(ns.EnhanceGatheringTooltip(GameTooltip) and lines[2].text == nil,
        "unowned gathering requirement must be hidden")
    ns.db.showUnownedRequirements = true
    setup(case[2], case[3], case[4], nil, case[5])
    check(ns.EnhanceGatheringTooltip(GameTooltip) and lines[2].text == case[3] .. " (125)",
        "opt-in must keep enhanced foreign gathering requirements")
    ns.db.showUnownedRequirements = false
    owned[case[1]] = true
end
print("Gathering tooltip checks passed: " .. checks)
