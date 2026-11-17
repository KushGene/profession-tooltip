-- Characters.lua
-- Account-wide overview of characters (for "Known by: <alt>").
-- Each character stores a snapshot on login and after scans:
--   ns.db.characters["Name-Realm"] = { name, surname, class, professions = {...}, known = { [spellID] = true } }
-- WoW Forever: characters have a first name and a surname, and several characters can share the
-- first name. UnitName returns (name, surname) there instead of (name, realm), so such characters
-- are keyed "Name Surname-Realm".
local _, ns = ...

local playerKey
local altIndex -- [spellID] = { "colored name", ... } – other characters only, built on demand

local function SurnameSeparator()
    local consts = Constants and Constants.CharacterNameSeparatorConsts
    return consts and consts.CHARACTERNAME_SURNAME_SEPARATOR or " "
end

-- First name and surname of the player (surname nil where the game has none)
local function GetPlayerNames()
    local name, surname = UnitName("player")
    if type(surname) ~= "string" or surname == "" or surname == GetRealmName() then
        surname = nil
    end
    return name, surname
end

local function DisplayName(entry)
    if ns.db.showSurname and entry.surname then
        return entry.name .. SurnameSeparator() .. entry.surname
    end
    return entry.name
end

local function ColoredName(entry)
    local name = DisplayName(entry)
    local color = entry.class and C_ClassColor and C_ClassColor.GetClassColor(entry.class)
    return color and color:WrapTextInColorCode(name) or name
end

local function Snapshot()
    local known = {}
    for spellID in pairs(ns.char.known) do
        local _, professionID = ns.GetRecipe(spellID)
        if professionID and ns.HasProfession(professionID) then -- not of an unlearned profession
            known[spellID] = true
        end
    end
    -- Recipes of own professions that IsSpellKnown detects without a scan
    ns.ForEachRecipe(function(spellID, _, professionID)
        if not known[spellID] and ns.HasProfession(professionID) and ns.IsSpellKnown(spellID) then
            known[spellID] = true
        end
    end)
    local professions = {}
    for id, info in pairs(ns.char.professions) do
        professions[id] = { rank = info.rank, max = info.max }
    end
    local name, surname = GetPlayerNames()
    ns.db.characters[playerKey] = {
        name = name,
        surname = surname,
        class = select(2, UnitClass("player")),
        professions = professions,
        known = known,
    }
end

-- Coalesce snapshots (scan events often arrive in bursts)
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

-- Colored names of the alts that know this recipe (or nil)
function ns.GetAltsKnowing(spellID)
    if not altIndex then BuildAltIndex() end
    return altIndex[spellID]
end

-- Alts that could learn the recipe (have the profession, enough skill, not learned yet)
function ns.GetAltsAbleToLearn(spellID)
    local recipe, professionID = ns.GetRecipe(spellID)
    if not recipe then return nil end
    local skill = ns.GetRequiredSkill(spellID, recipe)
    if skill == 0 then return nil end -- required skill unknown: don't claim anyone can learn it
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

-- For the settings: sorted list { key, entry }
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

-- "Name-Realm", with surname "Name Surname-Realm"
local function GetPlayerKey()
    local name, surname = GetPlayerNames()
    return (surname and (name .. " " .. surname) or name) .. "-" .. GetRealmName()
end

ns.RegisterEvent("PLAYER_LOGIN", function()
    playerKey = GetPlayerKey()
    -- Before surnames the key was "Name-Realm": drop that entry once the character has one
    -- (the snapshot below rebuilds everything; a namesake re-adds its own entry on its next login)
    local name, surname = GetPlayerNames()
    local legacyKey = name .. "-" .. GetRealmName()
    local legacy = ns.db.characters[legacyKey]
    if surname and legacy and not legacy.surname and legacy.class == select(2, UnitClass("player")) then
        ns.db.characters[legacyKey] = nil
    end
    Snapshot()
end)
ns.On("DATA_CHANGED", RequestSnapshot)
ns.On("SETTINGS_CHANGED", function(_, key)
    if key == "showSurname" then
        altIndex = nil -- colored names are cached in the index
    end
end)
