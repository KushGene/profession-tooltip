-- Professions.lua
-- Berufsdefinitionen und Erkennung, welche Berufe der Charakter hat.
local _, ns = ...
local L = ns.L

-- Reihenfolge = Anzeigereihenfolge im Tooltip und in den Einstellungen.
-- previewItem: typische Zutat des Berufs für die Vorschau im Einstellungsfenster
ns.Professions = {
    { id = 171, key = "ALCHEMY",        icon = "Interface\\Icons\\Trade_Alchemy",          previewItem = 2447 },  -- Peacebloom
    { id = 164, key = "BLACKSMITHING",  icon = "Interface\\Icons\\Trade_BlackSmithing",    previewItem = 2840 },  -- Copper Bar
    { id = 333, key = "ENCHANTING",     icon = "Interface\\Icons\\Trade_Engraving",        previewItem = 10940 }, -- Strange Dust
    { id = 202, key = "ENGINEERING",    icon = "Interface\\Icons\\Trade_Engineering",      previewItem = 2835 },  -- Rough Stone
    { id = 165, key = "LEATHERWORKING", icon = "Interface\\Icons\\Trade_LeatherWorking",   previewItem = 2318 },  -- Light Leather
    { id = 197, key = "TAILORING",      icon = "Interface\\Icons\\Trade_Tailoring",        previewItem = 2589 },  -- Linen Cloth
    { id = 186, key = "MINING",         icon = "Interface\\Icons\\Trade_Mining",           previewItem = 2770 },  -- Copper Ore
    { id = 182, key = "HERBALISM",      icon = "Interface\\Icons\\Trade_Herbalism",        previewItem = 765 },   -- Silverleaf
    { id = 393, key = "SKINNING",       icon = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",  previewItem = 2318 },  -- Light Leather
    { id = 185, key = "COOKING",        icon = "Interface\\Icons\\INV_Misc_Food_15",       previewItem = 2678 },  -- Mild Spices
    { id = 129, key = "FIRST_AID",      icon = "Interface\\Icons\\Spell_Holy_SealOfSacrifice", previewItem = 2589 }, -- Linen Cloth
    { id = 356, key = "FISHING",        icon = "Interface\\Icons\\Trade_Fishing",          previewItem = 6291 },  -- Raw Brilliant Smallfish
}

local byID = {}
for order, profession in ipairs(ns.Professions) do
    profession.order = order
    byID[profession.id] = profession
end

function ns.GetProfession(id)
    return byID[id]
end

local nameCache = {}

function ns.GetProfessionName(id)
    local name = nameCache[id]
    if not name then
        name = C_TradeSkillUI.GetTradeSkillDisplayName and C_TradeSkillUI.GetTradeSkillDisplayName(id)
        if not name or name == "" then
            name = L["PROFESSION_" .. byID[id].key]
        end
        nameCache[id] = name
    end
    return name
end

-- Ordnet einen Beruf aus GetProfessionInfo einer Skill-Line zu (bevorzugt per ID, sonst per Name)
local function ResolveProfessionID(name, skillLine)
    if skillLine and byID[skillLine] then
        return skillLine
    end
    for _, profession in ipairs(ns.Professions) do
        if ns.GetProfessionName(profession.id) == name then
            return profession.id
        end
    end
end

function ns.DetectProfessions()
    if not (GetProfessions and GetProfessionInfo) then return end
    local detected = {}
    local indices = { GetProfessions() }
    for i = 1, 6 do
        local index = indices[i]
        if index then
            local name, _, rank, maxRank, _, _, skillLine = GetProfessionInfo(index)
            local id = ResolveProfessionID(name, skillLine)
            if id then
                detected[id] = { rank = rank, max = maxRank }
            end
        end
    end

    local professions = ns.char.professions
    local changed = false
    for id, info in pairs(detected) do
        local old = professions[id]
        if not old or old.rank ~= info.rank or old.max ~= info.max then
            changed = true
        end
    end
    for id in pairs(professions) do
        if not detected[id] then
            changed = true -- Beruf verlernt
        end
    end
    if changed then
        ns.char.professions = detected
        ns.Fire("DATA_CHANGED")
    end
end

function ns.GetProfessionRank(id)
    local info = ns.char.professions[id]
    if info then
        return info.rank, info.max
    end
end

function ns.HasProfession(id)
    return ns.char.professions[id] ~= nil
end

-- Soll der Beruf im Tooltip erscheinen?
function ns.IsProfessionShown(id)
    if ns.db.disabledProfessions[id] then return false end
    if ns.db.onlyOwnProfessions and not ns.HasProfession(id) then return false end
    return true
end

-- Namen der eigenen Berufe, deren Fenster noch nie gescannt wurde
function ns.GetUnscannedProfessionNames()
    local names = {}
    for _, profession in ipairs(ns.Professions) do
        if ns.HasProfession(profession.id) and not ns.char.scanned[profession.id] then
            names[#names + 1] = ns.GetProfessionName(profession.id)
        end
    end
    return names
end

function ns.SetProfessionEnabled(id, enabled)
    ns.db.disabledProfessions[id] = (not enabled) or nil
    ns.Fire("SETTINGS_CHANGED", "disabledProfessions")
end

ns.RegisterEvent("PLAYER_LOGIN", ns.DetectProfessions)
ns.RegisterEvent("SKILL_LINES_CHANGED", ns.DetectProfessions)

-- Neu gelerntes Rezept -> Tooltips neu aufbauen (IsPlayerSpell liefert es sofort)
local function OnRecipeLearned()
    ns.Fire("DATA_CHANGED")
end
ns.RegisterEvent("NEW_RECIPE_LEARNED", OnRecipeLearned)
ns.RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE", OnRecipeLearned)
