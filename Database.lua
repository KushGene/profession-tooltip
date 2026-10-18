-- Database.lua
-- Recipe registry (filled by Data/*.lua) and indexes reagent -> recipes, item -> recipes.
--
-- Recipe format (compact, so the data files stay small):
--   [spellID] = { requiredSkill, "fallback name", { itemID, count, ... }, createdItem, yellowAt, greenAt, grayAt }
-- requiredSkill 0 = unknown, createdItem 0 = no item (e.g. enchants).
-- The color thresholds are optional; if missing, the difficulty reported by the scan applies.
local _, ns = ...

local SKILL, NAME, REAGENTS, CREATED, YELLOW, GREEN, GRAY = 1, 2, 3, 4, 5, 6, 7
local DIFFICULTY_OPTIMAL, DIFFICULTY_MEDIUM, DIFFICULTY_EASY, DIFFICULTY_TRIVIAL = 0, 1, 2, 3

local recipes = {}          -- [spellID] = recipe
local recipeProfession = {} -- [spellID] = skillLineID
local recipeItems = {}      -- [recipe item] = taught spell
local reagentIndex          -- [itemID] = { spellID, ... }, sorted; built on demand
local createdIndex          -- [itemID] = { spellID, ... } for crafted items

function ns.RegisterRecipes(professionID, list)
    for spellID, recipe in pairs(list) do
        recipes[spellID] = recipe
        recipeProfession[spellID] = professionID
    end
end

function ns.RegisterRecipeItems(list)
    for itemID, spellID in pairs(list) do
        recipeItems[itemID] = spellID
    end
end

-- Returns recipe and profession; also covers scanned recipes without a DB entry
function ns.GetRecipe(spellID)
    local recipe = recipes[spellID]
    if recipe then
        return recipe, recipeProfession[spellID]
    end
    local extra = ns.char.extra[spellID]
    if extra then
        return extra, extra.profession
    end
end

function ns.ForEachRecipe(callback)
    for spellID, recipe in pairs(recipes) do
        callback(spellID, recipe, recipeProfession[spellID])
    end
end

function ns.GetRecipeSkill(recipe)
    return recipe[SKILL] or 0
end

-- Rank required to learn: from the data or – if lower or unknown there – from the
-- trainer scan (trainer data isn't in the game files). 0 = unknown.
function ns.GetRequiredSkill(spellID, recipe)
    local skill = recipe[SKILL] or 0
    local trainer = ns.db.trainerSkills[spellID]
    if trainer and (skill == 0 or trainer < skill) then
        return trainer
    end
    return skill
end

function ns.GetRecipeName(spellID, recipe)
    return ns.GetSpellName(spellID) or recipe[NAME]
end

function ns.GetRecipeReagents(recipe)
    return recipe[REAGENTS]
end

function ns.GetCreatedItem(recipe)
    local itemID = recipe[CREATED]
    return itemID and itemID ~= 0 and itemID or nil
end

function ns.GetGrayAt(recipe)
    return recipe[GRAY]
end

function ns.GetReagentCount(recipe, itemID)
    local reagents = recipe[REAGENTS]
    for i = 1, #reagents, 2 do
        if reagents[i] == itemID then
            return reagents[i + 1]
        end
    end
    return 0
end

-- Recipe item subclass -> profession (item class 9 = Recipe)
local ITEM_CLASS_RECIPE = 9
local RECIPE_SUBCLASS_PROFESSION = {
    [1] = 165, [2] = 197, [3] = 202, [4] = 164, [5] = 185, [6] = 171, [7] = 129, [8] = 333, [9] = 356,
}
local matchedByName = {}    -- [recipe item] = taught spell, or false if no recipe matches

-- Fallback for recipe items missing from the data (e.g. new content after a patch):
-- "Pattern: Linen Cloak" -> recipe "Linen Cloak" of the same profession
local function FindSpellByItemName(itemID)
    local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
    if not classID then return nil end -- unknown to the client so far, try again next time
    local professionID = classID == ITEM_CLASS_RECIPE and RECIPE_SUBCLASS_PROFESSION[subclassID]
    if not professionID then return false end
    local itemName = C_Item.GetItemNameByID(itemID)
    if not itemName then return nil end -- item data not loaded yet, try again next time
    local recipeName = itemName:match("^.-:%s*(.+)$") or itemName:match("^.-：%s*(.+)$")
    if not recipeName then return false end
    for spellID, recipe in pairs(recipes) do
        if recipeProfession[spellID] == professionID and ns.GetRecipeName(spellID, recipe) == recipeName then
            return spellID
        end
    end
    for spellID, extra in pairs(ns.char.extra) do
        if extra.profession == professionID and ns.GetRecipeName(spellID, extra) == recipeName then
            return spellID
        end
    end
    return false
end

-- Spell taught by a recipe item (or nil)
function ns.GetSpellTaughtBy(itemID)
    local spellID = recipeItems[itemID]
    if spellID then return spellID end
    local matched = matchedByName[itemID]
    if matched == nil then
        matched = FindSpellByItemName(itemID)
        matchedByName[itemID] = matched
    end
    return matched or nil
end

local function AddToIndex(index, itemID, spellID)
    local list = index[itemID]
    if not list then
        list = {}
        index[itemID] = list
    end
    list[#list + 1] = spellID
end

-- Sort order: profession (display order), then required skill, then spell ID (stable)
local function CompareSpells(a, b)
    local recipeA, profA = ns.GetRecipe(a)
    local recipeB, profB = ns.GetRecipe(b)
    if profA ~= profB then
        return ns.GetProfession(profA).order < ns.GetProfession(profB).order
    end
    local skillA, skillB = recipeA[SKILL] or 0, recipeB[SKILL] or 0
    if skillA ~= skillB then
        return skillA < skillB
    end
    return a < b
end

local function BuildIndexes()
    reagentIndex, createdIndex = {}, {}
    local function Add(spellID, recipe)
        local reagents = recipe[REAGENTS]
        for i = 1, #reagents, 2 do
            AddToIndex(reagentIndex, reagents[i], spellID)
        end
        if recipe[CREATED] and recipe[CREATED] ~= 0 then
            AddToIndex(createdIndex, recipe[CREATED], spellID)
        end
    end
    for spellID, recipe in pairs(recipes) do
        Add(spellID, recipe)
    end
    for spellID, extra in pairs(ns.char.extra) do
        if not recipes[spellID] and ns.GetProfession(extra.profession) then
            Add(spellID, extra)
        end
    end
    for _, list in pairs(reagentIndex) do
        table.sort(list, CompareSpells)
    end
    for _, list in pairs(createdIndex) do
        table.sort(list, CompareSpells)
    end
end

-- Spell IDs of all recipes that use this reagent (or nil)
function ns.GetRecipesForItem(itemID)
    if not reagentIndex then BuildIndexes() end
    return reagentIndex[itemID]
end

-- Spell IDs of all recipes that create this item (or nil)
function ns.GetRecipesCreating(itemID)
    if not createdIndex then BuildIndexes() end
    return createdIndex[itemID]
end

-- Difficulty (0 orange .. 3 gray) of a learned recipe, nil if not learned.
-- Learned: per scan or per IsPlayerSpell (works without the profession window open, too).
-- The color is computed from the current profession rank so it stays current while leveling.
function ns.GetKnownDifficulty(spellID)
    local scanned = ns.char.known[spellID]
    if scanned == nil and not IsPlayerSpell(spellID) then
        return nil
    end
    local recipe, professionID = ns.GetRecipe(spellID)
    local rank = professionID and ns.GetProfessionRank(professionID)
    if recipe and rank and recipe[YELLOW] then
        if rank >= recipe[GRAY] then return DIFFICULTY_TRIVIAL end
        if rank >= recipe[GREEN] then return DIFFICULTY_EASY end
        if rank >= recipe[YELLOW] then return DIFFICULTY_MEDIUM end
        return DIFFICULTY_OPTIMAL
    end
    return scanned or DIFFICULTY_OPTIMAL
end

-- Number of recipes and reagents (for the statistics in the settings)
function ns.GetDatabaseStats()
    if not reagentIndex then BuildIndexes() end
    local recipeCount, itemCount = 0, 0
    for _ in pairs(recipes) do recipeCount = recipeCount + 1 end
    for _ in pairs(reagentIndex) do itemCount = itemCount + 1 end
    return recipeCount, itemCount
end

-- New scanned recipes without a DB entry require a rebuild
function ns.InvalidateIndex()
    reagentIndex, createdIndex = nil, nil
end
