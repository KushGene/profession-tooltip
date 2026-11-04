-- Scanner.lua
-- Reads the learned recipes and their difficulty when a profession window opens.
local _, ns = ...

local T = C_TradeSkillUI
local BASIC_REAGENT = Enum.CraftingReagentType and Enum.CraftingReagentType.Basic

-- Determines the profession of the open window (own professions only, no linked/NPC windows)
local function GetOpenProfessionID()
    if (T.IsTradeSkillLinked and T.IsTradeSkillLinked())
        or (T.IsTradeSkillGuild and T.IsTradeSkillGuild())
        or (T.IsNPCCrafting and T.IsNPCCrafting()) then
        return nil
    end
    for _, info in ipairs({ T.GetBaseProfessionInfo(), T.GetChildProfessionInfo() }) do
        if info then
            if ns.GetProfession(info.professionID) then
                return info.professionID, info
            end
            if ns.GetProfession(info.parentProfessionID) then
                return info.parentProfessionID, info
            end
        end
    end
end

local function ReadReagents(recipeID)
    local schematic = T.GetRecipeSchematic(recipeID, false)
    if not (schematic and schematic.reagentSlotSchematics) then return nil end
    local reagents = {}
    for _, slot in ipairs(schematic.reagentSlotSchematics) do
        -- Slots without an itemID (currency reagents) are skipped so the { itemID, count } pairs don't shift
        if (BASIC_REAGENT == nil or slot.reagentType == BASIC_REAGENT) and slot.reagents and slot.reagents[1] and slot.reagents[1].itemID then
            reagents[#reagents + 1] = slot.reagents[1].itemID
            reagents[#reagents + 1] = slot.quantityRequired or 1
        end
    end
    return reagents
end

local function Scan()
    local professionID, info = GetOpenProfessionID()
    if not professionID then return end

    local getIDs = T.GetAllRecipeIDs or T.GetFilteredRecipeIDs
    if not getIDs then return end
    local recipeIDs = getIDs()
    if not recipeIDs or #recipeIDs == 0 then return end -- data not loaded yet

    local known, extra = ns.char.known, ns.char.extra

    -- Remove old entries of this profession (e.g. the difficulty has changed), kept for the diff below
    local oldKnown = {}
    for spellID, difficulty in pairs(known) do
        local _, profession = ns.GetRecipe(spellID)
        if profession == professionID then
            oldKnown[spellID] = difficulty
            known[spellID] = nil
        end
    end

    local changed, indexDirty = false, false
    for _, recipeID in ipairs(recipeIDs) do
        local recipeInfo = T.GetRecipeInfo(recipeID)
        if recipeInfo and recipeInfo.learned then
            local difficulty = recipeInfo.relativeDifficulty or 0
            known[recipeID] = difficulty
            if oldKnown[recipeID] ~= difficulty then
                changed = true
            end
            oldKnown[recipeID] = nil -- leftovers below: recipes that are no longer learned
            -- Remember recipes that aren't in the database (yet), including their reagents.
            -- The extra keeps its profession so the cleanup above doesn't wipe it during a
            -- scan of another profession.
            local stored = ns.GetRecipe(recipeID)
            if not stored or stored == extra[recipeID] then
                local reagents = ReadReagents(recipeID) or {}
                local entry = extra[recipeID]
                if not entry or #(entry[3] or {}) ~= #reagents then
                    extra[recipeID] = { nil, recipeInfo.name, reagents, profession = professionID }
                    indexDirty = true
                end
            end
        end
    end
    if next(oldKnown) then
        changed = true
    end

    if info and info.skillLevel and info.maxSkillLevel and info.maxSkillLevel > 0 then
        local old = ns.char.professions[professionID]
        if not (old and old.rank == info.skillLevel and old.max == info.maxSkillLevel) then
            ns.char.professions[professionID] = { rank = info.skillLevel, max = info.maxSkillLevel }
            changed = true
        end
    end
    if not ns.char.scanned[professionID] then
        ns.char.scanned[professionID] = true
        changed = true
    end

    if indexDirty then
        ns.InvalidateIndex()
        changed = true
    end
    -- TRADE_SKILL_LIST_UPDATE also fires after every craft -> don't rebuild unchanged data
    if changed then
        ns.Fire("DATA_CHANGED")
    end
end

-- The list events fire several times in quick succession on open -> coalesce them
local scanPending = false
local function RequestScan()
    if scanPending then return end
    scanPending = true
    C_Timer.After(0.3, function()
        scanPending = false
        Scan()
    end)
end

ns.RegisterEvent("TRADE_SKILL_SHOW", RequestScan)
ns.RegisterEvent("TRADE_SKILL_LIST_UPDATE", RequestScan)
ns.RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED", RequestScan)
