-- Run from the repository root: luajit Tools/test_review.lua
local function read(path)
    local file = assert(io.open(path))
    local text = file:read("*a")
    file:close()
    return text
end

local events, callbacks = {}, {}
local recipes = {
    [1] = { name = "Duplicate", profession = 171 },
    [2] = { name = "Duplicate", profession = 171 },
    [3] = { name = "Unique", profession = 171 },
    [4] = { name = "Other", profession = 197 },
}
local ns = {
    db = { trainerSkills = {} },
    char = { known = { [99] = 2, [4] = 1, [1] = 0 }, extra = {}, professions = {}, scanned = {} },
    Professions = { { id = 171 } },
    RegisterEvent = function(event, fn) events[event] = fn end,
    On = function(event, fn) callbacks[event] = fn end,
    Fire = function(event) if callbacks[event] then callbacks[event]() end end,
    GetRecipe = function(id) return recipes[id], recipes[id] and recipes[id].profession end,
    GetRecipeName = function(_, recipe) return recipe.name end,
    GetProfessionName = function() return "Alchemy" end,
    GetProfession = function(id) return id == 171 end,
    ForEachRecipe = function(fn)
        for id, recipe in pairs(recipes) do fn(id, recipe, recipe.profession) end
    end,
    InvalidateIndex = function() end,
}
C_Timer = { After = function(_, fn) fn() end }
Enum = {}
C_TradeSkillUI = {
    GetBaseProfessionInfo = function() return { professionID = 171 } end,
    GetChildProfessionInfo = function() end,
    GetAllRecipeIDs = function() return { 3 } end,
    GetRecipeInfo = function() return { learned = true, relativeDifficulty = 1 } end,
}
assert(loadfile("Scanner.lua"))("Test", ns)
events.TRADE_SKILL_SHOW()
assert(ns.char.known[99] == 2, "unknown profession must survive")
assert(ns.char.known[4] == 1, "other profession must survive")
assert(ns.char.known[1] == nil, "stale entry of scanned profession must be removed")
assert(ns.char.known[3] == 1, "learned recipe must be scanned")

local offerName, tooltipID = "Duplicate", nil
GetNumTrainerServices = function() return 1 end
GetTrainerServiceInfo = function() return offerName, nil, "available" end
GetTrainerServiceSkillReq = function() return "Alchemy", 50 end
C_TooltipInfo = { GetTrainerService = function() return { id = tooltipID } end }
local tradeskillTrainer, filters, filterChanges = false, { available = true, unavailable = false, used = true }, 0
IsTradeskillTrainer = function() return tradeskillTrainer end
GetTrainerServiceTypeFilter = function(kind) return filters[kind] end
SetTrainerServiceTypeFilter = function(kind, enabled) filters[kind] = enabled; filterChanges = filterChanges + 1 end
assert(loadfile("Trainer.lua"))("Test", ns)
tooltipID = 2
events.TRAINER_SHOW()
assert(next(ns.db.trainerSkills) == nil and filterChanges == 0, "class trainers must not be scanned or have their filters touched")
tradeskillTrainer, tooltipID = true, nil
events.TRAINER_SHOW()
assert(next(ns.db.trainerSkills) == nil, "ambiguous name must not pick a recipe")
tooltipID = 2
events.TRAINER_SHOW()
assert(ns.db.trainerSkills[2] == 50, "tooltip must resolve ambiguous name")
assert(filterChanges == 4 and filters.unavailable == false and filters.used == true,
    "only disabled filters may be switched, and they must be restored")
offerName, tooltipID = "Unique", 4
events.TRAINER_SHOW()
assert(ns.db.trainerSkills[4] == nil, "wrong-profession tooltip must not match")
assert(ns.db.trainerSkills[3] == 50, "unique name fallback must work")
recipes[5] = { name = "Unique", profession = 171 }
ns.Fire("DATA_CHANGED")
ns.db.trainerSkills[3] = nil
tooltipID = nil
events.TRAINER_SHOW()
assert(ns.db.trainerSkills[3] == nil and ns.db.trainerSkills[5] == nil,
    "name index must be rebuilt after recipes change")

-- Exercise the actual Extras-tab builder with lightweight UI stubs.
local controls, displayed, characters = {}, {}, {}
local function control()
    local c = {}
    for _, method in ipairs({ "SetSize", "SetPoint", "SetText", "SetShown", "SetEnabled", "SetScript" }) do
        c[method] = function(self, ...) self[method:sub(4)] = { ... } end
    end
    return c
end
CreateFrame = function()
    local c = control()
    controls[#controls + 1] = c
    return c
end
local page = { CreateFontString = function() return control() end }
local col = { x = 0, y = 0, width = 300 }
for _, method in ipairs({ "Header", "Check", "Space" }) do col[method] = function() end end
col.Add = function(_, item) col.item = item end
local Widgets = { NewColumn = function() return col end }
ns.GetCharacters = function() return characters end
local source = read("UI/ConfigWindow.lua")
local builder = assert(source:match("(local function BuildExtrasTab%(%s*page%s*%).-)\nlocal function BuildGeneralTab"))
local env = setmetatable({
    ns = ns, Widgets = Widgets, LEFT_WIDTH = 300, MAX_CHARACTER_ROWS = 6,
    L = setmetatable({}, { __index = function(_, key) return key end }),
    Option = function() return {} end,
    CreateCharacterRow = function(_, _, index)
        return { Set = function(character) displayed[index] = character end }
    end,
}, { __index = _G })
local chunk = assert(loadstring(builder .. "\nreturn BuildExtrasTab"))
setfenv(chunk, env)
chunk()(page)
for i = 1, 13 do characters[i] = { key = i } end
col.item.Refresh()
assert(displayed[1].key == 1 and displayed[6].key == 6)
assert(not controls[1].Enabled[1] and controls[2].Enabled[1])
controls[2].Script[2]()
assert(displayed[1].key == 7 and displayed[6].key == 12)
controls[2].Script[2]()
assert(displayed[1].key == 13 and displayed[2] == nil)
assert(not controls[2].Enabled[1])
table.remove(characters)
col.item.Refresh()
assert(displayed[1].key == 7, "deleting the final page must clamp to the previous page")
controls[1].Script[2]()
assert(displayed[1].key == 1)
characters = {}
col.item.Refresh()
assert(displayed[1] == nil and not controls[1].Shown[1] and not controls[2].Shown[1])
print("Review regression tests passed (scanner, trainer matching, character pagination)")
