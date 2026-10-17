-- Scanner.lua
-- Liest beim Öffnen eines Berufsfensters die gelernten Rezepte und deren Schwierigkeit aus.
local _, ns = ...

local T = C_TradeSkillUI
local BASIC_REAGENT = Enum.CraftingReagentType and Enum.CraftingReagentType.Basic

-- Ermittelt den Beruf des offenen Fensters (nur eigene Berufe, keine verlinkten/NPC-Fenster)
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
        if (BASIC_REAGENT == nil or slot.reagentType == BASIC_REAGENT) and slot.reagents and slot.reagents[1] then
            reagents[#reagents + 1] = slot.reagents[1].itemID
            reagents[#reagents + 1] = slot.quantityRequired or 1
        end
    end
    return reagents
end

local function Scan()
    local professionID, info = GetOpenProfessionID()
    if not professionID then return end

    local recipeIDs = T.GetAllRecipeIDs()
    if not recipeIDs or #recipeIDs == 0 then return end -- Daten noch nicht geladen

    local known, extra = ns.char.known, ns.char.extra

    -- Alte Einträge dieses Berufs entfernen (z. B. Schwierigkeit hat sich geändert)
    for spellID in pairs(known) do
        local _, profession = ns.GetRecipe(spellID)
        if profession == professionID or profession == nil then
            known[spellID] = nil
        end
    end

    local indexDirty = false
    for _, recipeID in ipairs(recipeIDs) do
        local recipeInfo = T.GetRecipeInfo(recipeID)
        if recipeInfo and recipeInfo.learned then
            known[recipeID] = recipeInfo.relativeDifficulty or 0
            -- Rezepte, die (noch) nicht in der Datenbank stehen, merken wir uns samt Zutaten
            if not ns.GetRecipe(recipeID) then
                local reagents = ReadReagents(recipeID)
                if reagents and #reagents > 0 then
                    extra[recipeID] = { nil, recipeInfo.name, reagents, profession = professionID }
                    indexDirty = true
                end
            end
        end
    end

    if info and info.skillLevel and info.maxSkillLevel and info.maxSkillLevel > 0 then
        ns.char.professions[professionID] = { rank = info.skillLevel, max = info.maxSkillLevel }
    end
    ns.char.scanned[professionID] = true

    if indexDirty then
        ns.InvalidateIndex()
    end
    ns.Fire("DATA_CHANGED")
end

-- Die Listen-Events feuern beim Öffnen mehrfach kurz hintereinander -> zusammenfassen
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
