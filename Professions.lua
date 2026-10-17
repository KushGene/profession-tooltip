-- Professions.lua
-- Profession definitions and detection of which professions the character has.
local _, ns = ...
local L = ns.L

-- Order = display order in the tooltip and in the settings.
-- previewItem: typical reagent of the profession for the preview in the settings window
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

-- Maps a profession from GetProfessionInfo to a skill line (by ID if possible, otherwise by name)
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
            changed = true -- profession unlearned
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

-- Should the profession appear in the tooltip?
function ns.IsProfessionShown(id)
    if ns.db.disabledProfessions[id] then return false end
    if ns.db.onlyOwnProfessions and not ns.HasProfession(id) then return false end
    return true
end

-- Names of own professions whose window has never been scanned
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

-- Newly learned recipe -> rebuild tooltips (IsPlayerSpell reports it right away)
local function OnRecipeLearned()
    ns.Fire("DATA_CHANGED")
end
ns.RegisterEvent("NEW_RECIPE_LEARNED", OnRecipeLearned)
ns.RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE", OnRecipeLearned)
