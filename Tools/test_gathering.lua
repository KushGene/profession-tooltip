-- Run from the repository root: luajit Tools/test_gathering.lua
local callbacks, scripts = {}, {}
Enum = { TooltipDataType = { Item = 0, Unit = 2, Object = 4 } }
TooltipDataProcessor = { AddTooltipPostCall = function(kind, callback) callbacks[kind] = callback end }
LOCKED_WITH_SPELL = "Benötigt %s"
SKINNABLE = "Häutbar"
local level = 25
UnitLevel = function(unit) assert(unit == "mouseover"); return level end
issecretvalue = function(value) return value == "SECRET" end
local ns = { db = { disabledProfessions = {} } }
ns.GetProfessionName = function(id)
    return ({ [182] = "Kräuterkunde", [186] = "Bergbau", [393] = "Kürschnerei" })[id]
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
setup("Localized node", "Kräuterkunde", 4, 1622)
ns.EnhanceGatheringTooltip(GameTooltip)
check(lines[2].text == "Kräuterkunde (125)", "object IDs must work regardless of node language")
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
print("Gathering tooltip checks passed: " .. checks)
