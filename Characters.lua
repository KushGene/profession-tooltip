-- Characters.lua
-- Accountweite Übersicht der Charaktere (für "Bekannt bei: <Twink>").
-- Jeder Charakter legt beim Login und nach Scans eine Momentaufnahme ab:
--   ns.db.characters["Name-Realm"] = { name, class, professions = {...}, known = { [spellID] = true } }
local _, ns = ...

local playerKey
local altIndex -- [spellID] = { "farbiger Name", ... } – nur andere Charaktere, bei Bedarf aufgebaut

local function ColoredName(entry)
    local color = entry.class and C_ClassColor and C_ClassColor.GetClassColor(entry.class)
    return color and color:WrapTextInColorCode(entry.name) or entry.name
end

local function Snapshot()
    local known = {}
    for spellID in pairs(ns.char.known) do
        known[spellID] = true
    end
    -- Rezepte eigener Berufe, die ohne Scan per IsPlayerSpell erkannt werden
    ns.ForEachRecipe(function(spellID, _, professionID)
        if not known[spellID] and ns.HasProfession(professionID) and IsPlayerSpell(spellID) then
            known[spellID] = true
        end
    end)
    local professions = {}
    for id, info in pairs(ns.char.professions) do
        professions[id] = { rank = info.rank, max = info.max }
    end
    ns.db.characters[playerKey] = {
        name = UnitName("player"),
        class = select(2, UnitClass("player")),
        professions = professions,
        known = known,
    }
end

-- Momentaufnahmen zusammenfassen (Scan-Events kommen oft gehäuft)
local snapshotPending = false
local function RequestSnapshot()
    if snapshotPending or not playerKey then return end
    snapshotPending = true
    C_Timer.After(2, function()
        snapshotPending = false
        Snapshot()
    end)
end

local function BuildAltIndex()
    altIndex = {}
    for key, entry in pairs(ns.db.characters) do
        if key ~= playerKey and entry.known then
            local name = ColoredName(entry)
            for spellID in pairs(entry.known) do
                local list = altIndex[spellID]
                if not list then
                    list = {}
                    altIndex[spellID] = list
                end
                list[#list + 1] = name
            end
        end
    end
end

-- Farbige Namen der Twinks, die dieses Rezept kennen (oder nil)
function ns.GetAltsKnowing(spellID)
    if not altIndex then BuildAltIndex() end
    return altIndex[spellID]
end

-- Twinks, die das Rezept lernen könnten (Beruf vorhanden, Skill reicht, noch nicht gelernt)
function ns.GetAltsAbleToLearn(spellID)
    local recipe, professionID = ns.GetRecipe(spellID)
    if not recipe then return nil end
    local skill = ns.GetRecipeSkill(recipe)
    local names
    for key, entry in pairs(ns.db.characters) do
        local info = entry.professions and entry.professions[professionID]
        if key ~= playerKey and info and info.rank >= skill and not (entry.known and entry.known[spellID]) then
            names = names or {}
            names[#names + 1] = ColoredName(entry)
        end
    end
    return names
end

-- Für die Einstellungen: sortierte Liste { key, entry }
function ns.GetCharacters()
    local list = {}
    for key, entry in pairs(ns.db.characters) do
        list[#list + 1] = { key = key, entry = entry, colored = ColoredName(entry), isPlayer = key == playerKey }
    end
    table.sort(list, function(a, b) return a.key < b.key end)
    return list
end

function ns.DeleteCharacter(key)
    ns.db.characters[key] = nil
    altIndex = nil
    ns.Fire("DATA_CHANGED")
end

ns.RegisterEvent("PLAYER_LOGIN", function()
    playerKey = UnitName("player") .. "-" .. GetRealmName()
    Snapshot()
end)
ns.On("DATA_CHANGED", RequestSnapshot)
