-- Trainer.lua
-- Liest beim Öffnen eines Berufslehrers die benötigte Stufe der angebotenen Rezepte aus.
-- Lehrer-Daten stehen nicht in den Spieldateien, sondern kommen vom Server. Gespeichert wird
-- accountweit in ns.db.trainerSkills; Tools/build_data.py übernimmt die Werte in die Addon-Daten.
local _, ns = ...

local SERVICE_TYPES = { "available", "unavailable", "used" }

local nameIndex -- [professionID] = { [Rezeptname] = spellID }

local function BuildNameIndex()
    nameIndex = {}
    ns.ForEachRecipe(function(spellID, recipe, professionID)
        local names = nameIndex[professionID]
        if not names then
            names = {}
            nameIndex[professionID] = names
        end
        names[ns.GetRecipeName(spellID, recipe)] = spellID
    end)
end

local function FindProfessionByName(name)
    for _, profession in ipairs(ns.Professions) do
        if ns.GetProfessionName(profession.id) == name then
            return profession.id
        end
    end
end

-- Spell-ID eines Lehrer-Angebots: bevorzugt über die Tooltip-Daten, sonst über den Namen
local function GetServiceSpellID(index, name, professionID)
    if C_TooltipInfo and C_TooltipInfo.GetTrainerService then
        local data = C_TooltipInfo.GetTrainerService(index)
        if data and data.id and ns.GetRecipe(data.id) then
            return data.id
        end
    end
    if not nameIndex then BuildNameIndex() end
    return nameIndex[professionID] and nameIndex[professionID][name]
end

-- Alle Angebote sichtbar machen (auch nicht verfügbare/gelernte); Rückgabe: vorherige Filter
local function ShowAllServices()
    if not (GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter) then return nil end
    local previous = {}
    for _, serviceType in ipairs(SERVICE_TYPES) do
        previous[serviceType] = GetTrainerServiceTypeFilter(serviceType)
        SetTrainerServiceTypeFilter(serviceType, 1)
    end
    return previous
end

local function RestoreFilters(previous)
    if not previous then return end
    for serviceType, enabled in pairs(previous) do
        SetTrainerServiceTypeFilter(serviceType, enabled and 1 or 0)
    end
end

local function Scan()
    if not GetNumTrainerServices then return end
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

-- Einmal pro Lehrer-Besuch, kurz verzögert, bis die Angebotsliste geladen ist.
-- (Nicht auf TRAINER_UPDATE reagieren: das Umschalten der Filter löst es selbst aus.)
ns.RegisterEvent("TRAINER_SHOW", function()
    C_Timer.After(0.3, Scan)
end)
