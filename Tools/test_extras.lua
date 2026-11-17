-- Extras: Darkmoon Faire turn-ins in item tooltips and WoW Forever surnames of characters.
-- Run from the repository root: luajit Tools/test_extras.lua
wipe = function(t) for key in pairs(t) do t[key] = nil end end
Enum = { TooltipDataType = { Item = 0 } }
local postCall
TooltipDataProcessor = { AddTooltipPostCall = function(_, callback) postCall = callback end }
IsShiftKeyDown = function() return false end
GetTime = function() return 0 end
GetLocale = function() return "enUS" end
C_Item = {
    GetItemNameByID = function(itemID) return "Item " .. itemID end,
    GetItemIconByID = function() return 133784 end,
}
C_Timer = { After = function(_, callback) callback() end }
local level = 15
UnitLevel = function() return level end
local firstName, surname, realm = "Leo", "Brightvale", "Soulseeker"
UnitName = function() return firstName, surname end
GetRealmName = function() return realm end
UnitClass = function() return "Mage", "MAGE" end
C_ClassColor = { GetClassColor = function() return { WrapTextInColorCode = function(_, text) return "<" .. text .. ">" end } end }

local frames = {}
CreateFrame = function()
    local frame = { scripts = {} }
    function frame:RegisterEvent() end
    function frame:SetScript(name, callback) self.scripts[name] = callback end
    frames[#frames + 1] = frame
    return frame
end
local function tooltip()
    local t = { lines = {} }
    function t:AddLine(text) self.lines[#self.lines + 1] = text end
    function t:Show() end
    return t
end
GameTooltip, ItemRefTooltip = tooltip(), tooltip()

local ns = {}
assert(loadfile("Core.lua"))("Test", ns)
local dispatch
for _, frame in ipairs(frames) do
    if frame.scripts.OnEvent then dispatch = frame.scripts.OnEvent end
end
dispatch(nil, "ADDON_LOADED", "Test")

ns.Professions = {}
ns.GetProfession = function() end
ns.HasProfession = function() return false end
ns.GetProfessionRank = function() end
ns.IsProfessionShown = function() return true end
assert(loadfile("Locales/enUS.lua"))("Test", ns)
assert(loadfile("Database.lua"))("Test", ns)
assert(loadfile("Data/Darkmoon.lua"))("Test", ns)
assert(loadfile("Tooltip.lua"))("Test", ns)
assert(loadfile("Characters.lua"))("Test", ns)
local L = ns.L

local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function contains(text, part) return text:find(part, 1, true) ~= nil end
local function tooltipText(itemID)
    GameTooltip.lines = {}
    postCall(GameTooltip, { id = itemID })
    return table.concat(GameTooltip.lines, "\n")
end

-- ----------------------------------------------------------------------------
-- Darkmoon Faire
-- ----------------------------------------------------------------------------
check(ns.db.showDarkmoon == true and ns.db.showSurname == true, "both extras default to on")
ns.SetOption("showDarkmoon", false)
check(tooltipText(5134) == "", "no Darkmoon line while the option is off")
ns.SetOption("showDarkmoon", true)
ns.SetOption("showSurname", false)
local text = tooltipText(5134) -- Small Furry Paw: 5 for 1 ticket, any level
check(contains(text, L["DARKMOON_FAIRE"] .. ":") and contains(text, "5× for 1 ticket"), "amount and reward: " .. text)
check(not contains(text, "→") and not contains(text, "Item 19182"), "no arrow (missing in the game fonts), no ticket item name")
check(not contains(text, "level"), "no level note for quests without a level requirement")
check(contains(text, "|T133784:14:14"), "ticket icon")

text = tooltipText(11407) -- Torn Bear Pelt: 5 for 4 tickets, level 10
check(contains(text, "5× for 4 tickets"), "reward count above one")
check(contains(text, "|cff888888(level 10+)|r"), "level requirement met: grey note")
text = tooltipText(11404) -- Evil Bat Eye: level 40
check(contains(text, "10× for 20 tickets"), "20 tickets")
check(contains(text, "|cffff5050(level 40+)|r"), "level too low: red note")
level = 40
dispatch(nil, "PLAYER_LEVEL_UP", 40)
check(contains(tooltipText(11404), "|cff888888(level 40+)|r"), "level up rebuilds the cached lines")
check(contains(tooltipText(19228), "1× for Item 19288"), "deck turns into its card")
check(tooltipText(2589) == "", "no line for other items")

-- Every entry: { count, reward, reward count, minimum level } with sane values
local entries = 0
for itemID, turnIn in pairs(ns.DarkmoonTurnIns) do
    entries = entries + 1
    check(type(itemID) == "number" and turnIn[1] >= 1 and turnIn[2] > 0 and turnIn[3] >= 1
        and (turnIn[4] == 1 or turnIn[4] % 10 == 0), "data entry " .. itemID)
end
check(entries == 26, "26 turn-in items: " .. entries)

-- ----------------------------------------------------------------------------
-- Surnames
-- ----------------------------------------------------------------------------
-- An entry from before surnames ("Leo-Soulseeker") is replaced by the full key
ns.db.characters["Leo-Soulseeker"] = { name = "Leo", class = "MAGE", professions = {}, known = {} }
ns.db.characters["Leo-OtherRealm"] = { name = "Leo", class = "MAGE", professions = {}, known = {} }
dispatch(nil, "PLAYER_LOGIN")
local me = ns.db.characters["Leo Brightvale-Soulseeker"]
check(me and me.name == "Leo" and me.surname == "Brightvale", "keyed and stored with the surname")
check(ns.db.characters["Leo-Soulseeker"] == nil, "legacy entry of this character is removed")
check(ns.db.characters["Leo-OtherRealm"] ~= nil, "same name on another realm stays")

-- A namesake (same first name, other surname) of the same realm gets its own entry
ns.db.characters["Leo Stormwind-Soulseeker"] = {
    name = "Leo", surname = "Stormwind", class = "PRIEST", professions = {}, known = { [77] = true },
}
local function names()
    local list = {}
    for _, character in ipairs(ns.GetCharacters()) do list[#list + 1] = character.colored end
    return table.concat(list, ",")
end
check(names() == "<Leo>,<Leo>,<Leo>", "surnames hidden when the option is off: " .. names())
check(ns.GetAltsKnowing(77)[1] == "<Leo>", "known-by without surname")
ns.SetOption("showSurname", true)
check(contains(names(), "<Leo Brightvale>") and contains(names(), "<Leo Stormwind>"), "surnames shown: " .. names())
check(ns.GetAltsKnowing(77)[1] == "<Leo Stormwind>", "known-by index is rebuilt with surnames")

-- Without a surname (other clients: the second value is the realm or nil) nothing changes
surname = realm
dispatch(nil, "PLAYER_LOGIN")
check(ns.db.characters["Leo-Soulseeker"] and ns.db.characters["Leo-Soulseeker"].surname == nil, "no surname: classic key")
Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = "_" } }
check(contains(names(), "<Leo_Stormwind>"), "client separator is used")

print(string.format("Extras tests passed (%d checks)", checks))
