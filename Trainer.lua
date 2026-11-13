-- Trainer.lua
-- Reads the required rank of the offered recipes when a profession trainer opens.
-- Trainer data isn't in the game files but comes from the server. It is stored
-- account-wide in ns.db.trainerSkills; Tools/build_data.py merges the values into the addon data.
local _, ns = ...

local SERVICE_TYPES = { "available", "unavailable", "used" }

local nameIndex -- [professionID] = { [recipe name] = spellID or false (ambiguous) }

local function BuildNameIndex()
    nameIndex = {}
    ns.ForEachRecipe(function(spellID, recipe, professionID)
        local names = nameIndex[professionID]
        if not names then
            names = {}
            nameIndex[professionID] = names
        end
        local name = ns.GetRecipeName(spellID, recipe)
        if names[name] == nil then
            names[name] = spellID
        elseif names[name] ~= spellID then
            names[name] = false
        end
    end)
end

local function FindProfessionByName(name)
    for _, profession in ipairs(ns.Professions) do
        if ns.GetProfessionName(profession.id) == name then
            return profession.id
        end
    end
end

-- Spell ID of a trainer offer: preferably via the tooltip data, otherwise via the name
local function GetServiceSpellID(index, name, professionID)
    if C_TooltipInfo and C_TooltipInfo.GetTrainerService then
        local data = C_TooltipInfo.GetTrainerService(index)
        if data and data.id then
            local recipe, profession = ns.GetRecipe(data.id)
            if recipe and profession == professionID then return data.id end
        end
    end
    if not nameIndex then BuildNameIndex() end
    return nameIndex[professionID] and nameIndex[professionID][name]
end

ns.On("DATA_CHANGED", function() nameIndex = nil end)

-- Make all offers visible (including unavailable/learned ones); returns the filters that
-- were switched on for it. Every filter change makes the client rebuild the whole offer
-- list, so only filters that are actually off are touched.
local function ShowAllServices()
    if not (GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter) then return nil end
    local changed = {}
    for _, serviceType in ipairs(SERVICE_TYPES) do
        if not GetTrainerServiceTypeFilter(serviceType) then
            SetTrainerServiceTypeFilter(serviceType, true)
            changed[#changed + 1] = serviceType
        end
    end
    return changed
end

local function RestoreFilters(changed)
    if not changed then return end
    for _, serviceType in ipairs(changed) do
        SetTrainerServiceTypeFilter(serviceType, false)
    end
end

local function Scan()
    if not GetNumTrainerServices then return end
    -- Profession trainers only. Class trainers offer hundreds of spells; unfolding their
    -- list through the filters froze the game for a moment, for nothing to record.
    if IsTradeskillTrainer and not IsTradeskillTrainer() then return end
    local previous = ShowAllServices()

    local changed = false
    for index = 1, GetNumTrainerServices() do
        local name, _, category = GetTrainerServiceInfo(index)
        if name and category ~= "header" then
            local skillName, skillRank = GetTrainerServiceSkillReq(index)
            local professionID = skillName and FindProfessionByName(skillName)
            if professionID and skillRank and skillRank > 0 then
                local spellID = GetServiceSpellID(index, name, professionID)
                if spellID and ns.db.trainerSkills[spellID] ~= skillRank then
                    ns.db.trainerSkills[spellID] = skillRank
                    changed = true
                end
            end
        end
    end

    RestoreFilters(previous)
    if changed then
        ns.Fire("DATA_CHANGED")
    end
end

function ns.GetTrainerSkillCount()
    local count = 0
    for _ in pairs(ns.db.trainerSkills) do count = count + 1 end
    return count
end

-- Once per trainer visit, slightly delayed until the offer list has loaded.
-- (Don't react to TRAINER_UPDATE: toggling the filters triggers it itself.)
ns.RegisterEvent("TRAINER_SHOW", function()
    C_Timer.After(0.3, Scan)
end)
