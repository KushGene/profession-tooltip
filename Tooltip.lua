-- Tooltip.lua
-- Baut die Tooltip-Zeilen für ein Item. Bis zu drei Abschnitte:
--   1. Rezept-Item ("Recipe: ...")  – gelernt / lernbar / Skill zu niedrig   (Extras)
--   2. Hergestelltes Item            – aus welchem Rezept, mit Zutaten        (Extras)
--   3. Zutat                         – welche Rezepte sie verwenden            (Kernfunktion)
-- Fertige Zeilen werden pro Item und Shift-Zustand gecacht, da Tooltips (z. B. in Taschen)
-- sehr häufig neu aufgebaut werden.
local _, ns = ...
local L = ns.L

local TRIVIAL = 3
local DIFFICULTY_COLORS = {
    [0] = "ffff8000", -- orange
    [1] = "ffffff00", -- gelb
    [2] = "ff40c040", -- grün
    [3] = "ff808080", -- grau
}
local COLOR_UNKNOWN = "ffaaaaaa"
local COLOR_HINT = "ff888888"
local COLOR_TOO_HIGH = "ffff5050"
local COLOR_GOOD = "ff40c040"
local COLOR_GOLD = "ffffd100"
local ICON_CROP = ":0:0:64:64:5:59:5:59|t"
local SECTION_KNOWN = "  |TInterface\\Buttons\\UI-CheckBox-Check:14:14|t"
local SECTION_UNKNOWN = "  |TInterface\\Buttons\\UI-GroupLoot-Pass-Up:14:14|t"
local MAX_CRAFTED_RECIPES = 3
local VOLATILE_CACHE_SECONDS = 3 -- Vorrat und Preise ändern sich -> nur kurz cachen
local UNLIMITED = math.huge

-- ----------------------------------------------------------------------------
-- Cache
-- ----------------------------------------------------------------------------
local cache = {} -- [itemID] = { [1|2] = { lines = {...} | false, time = n } }  (2 = mit Shift)

local function ClearCache()
    wipe(cache)
end
ns.On("SETTINGS_CHANGED", ClearCache)
ns.On("DATA_CHANGED", ClearCache)

local function IsVolatile()
    return ns.db.showStockCount or ns.db.showRecipeValue
end

ns.RegisterEvent("BAG_UPDATE_DELAYED", function()
    if ns.db.showStockCount then ClearCache() end
end)

-- Nachgeladene Itemnamen (Zutatenliste bei hergestellten Items) -> gebündelt neu aufbauen
local itemInfoPending = false
ns.RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
    if not (ns.db.showCraftedBy and ns.db.showCraftedReagents) or itemInfoPending then return end
    itemInfoPending = true
    C_Timer.After(0.5, function()
        itemInfoPending = false
        ClearCache()
    end)
end)

-- ----------------------------------------------------------------------------
-- Hilfsfunktionen
-- ----------------------------------------------------------------------------
local function Icon(profession, size)
    return "|T" .. profession.icon .. ":" .. size .. ":" .. size .. ICON_CROP
end

local function Colorize(color, text)
    return "|c" .. color .. text .. "|r"
end

local function ItemName(itemID)
    local name = C_Item.GetItemNameByID(itemID)
    if not name then
        C_Item.RequestLoadItemDataByID(itemID)
    end
    return name or ("#" .. itemID)
end

local function FormatMoney(copper)
    if GetMoneyString then
        return GetMoneyString(copper, true)
    end
    return math.floor(copper / 10000) .. "g"
end

-- Auktionspreis über Auctionator (nil, wenn nicht verfügbar)
local function GetAuctionPrice(itemID)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not (api and api.GetAuctionPriceByItemID) then return nil end
    local ok, price = pcall(api.GetAuctionPriceByItemID, "ProfessionTooltip", itemID)
    return ok and price or nil
end

function ns.IsAuctionatorAvailable()
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    return api ~= nil and api.GetAuctionPriceByItemID ~= nil
end

-- Soll ein ungelerntes Rezept laut Filter erscheinen?
local function PassesUnknownFilter(spellID, rank)
    local filter = ns.db.unknownFilter
    if filter == "all" or not rank then return true end
    local recipe = ns.GetRecipe(spellID)
    if filter == "learnable" then
        local skill = ns.GetRecipeSkill(recipe)
        return skill == 0 or skill <= rank -- unbekannte Lernstufe nicht ausfiltern
    end
    -- "noGray": Rezepte, die für mich bereits grau wären, ausblenden
    local grayAt = ns.GetGrayAt(recipe)
    return not grayAt or rank < grayAt
end

-- ----------------------------------------------------------------------------
-- Zeilen
-- ----------------------------------------------------------------------------
-- Berufszeile je nach Design-Einstellungen, z. B. "[Icon] Lederverarbeitung  70/150 · 16/82 gelernt"
local function FormatHeader(profession, rank, maxRank, knownCount, totalCount)
    local db = ns.db
    local text
    if db.headerStyle == "icon" then
        text = Icon(profession, 16)
    elseif db.headerStyle == "name" then
        text = Colorize(COLOR_GOLD, ns.GetProfessionName(profession.id))
    else
        text = Icon(profession, 14) .. " " .. Colorize(COLOR_GOLD, ns.GetProfessionName(profession.id))
    end

    local details = {}
    if db.showProfessionRank and rank then
        details[#details + 1] = rank .. "/" .. maxRank
    end
    if db.showKnownCount then
        details[#details + 1] = string.format(L["KNOWN_OF"], knownCount, totalCount)
    end
    if #details > 0 then
        text = text .. "  " .. Colorize(COLOR_HINT, table.concat(details, "  ·  "))
    end
    return text
end

local function FormatRecipeLine(spellID, itemID, difficulty, professionRank)
    local db = ns.db
    local recipe = ns.GetRecipe(spellID)
    local name = ns.GetRecipeName(spellID, recipe) or ("#" .. spellID)
    local text = "   • " .. Colorize(difficulty and DIFFICULTY_COLORS[difficulty] or COLOR_UNKNOWN, name)

    local count = ns.GetReagentCount(recipe, itemID)
    if db.showReagentCount and count > 1 then
        text = text .. " " .. Colorize("ffcccccc", "×" .. count)
    end
    if db.showStockCount and count > 0 then
        local crafts = math.floor(C_Item.GetItemCount(itemID, true) / count)
        text = text .. " " .. Colorize(crafts > 0 and "ff80c0ff" or COLOR_HINT, string.format(L["ENOUGH_FOR"], crafts))
    end

    local skill = ns.GetRecipeSkill(recipe) -- 0 = unbekannt (Lehrer-Rezept ohne Daten)
    if skill > 0 and db.showSkill and (not difficulty or db.showSkillKnown) then
        -- Rot, wenn die eigene Berufsstufe für ein ungelerntes Rezept noch nicht reicht
        local tooHigh = not difficulty and professionRank and professionRank < skill
        text = text .. " " .. Colorize(tooHigh and COLOR_TOO_HIGH or COLOR_UNKNOWN, "(" .. skill .. ")")
    end

    if db.showRecipeValue then
        local created = ns.GetCreatedItem(recipe)
        local price = created and GetAuctionPrice(created)
        if price then
            text = text .. "  " .. FormatMoney(price)
        end
    end

    if not difficulty and db.showAltKnown then
        local alts = ns.GetAltsKnowing(spellID)
        if alts then
            text = text .. " " .. Colorize(COLOR_HINT, "– " .. table.concat(alts, ", "))
        end
    end
    return text
end

-- ----------------------------------------------------------------------------
-- Abschnitt 1: Rezept-Item
-- ----------------------------------------------------------------------------
local function AddRecipeItemSection(lines, itemID)
    local spellID = ns.GetSpellTaughtBy(itemID)
    if not spellID then return end
    local recipe, professionID = ns.GetRecipe(spellID)
    if not recipe or ns.db.disabledProfessions[professionID] then return end

    local profession = ns.GetProfession(professionID)
    local skill = ns.GetRecipeSkill(recipe)
    local rank = ns.GetProfessionRank(professionID)
    local status
    if ns.GetKnownDifficulty(spellID) then
        status = Colorize(COLOR_GOOD, L["RECIPE_KNOWN"])
    elseif not rank then
        status = Colorize(COLOR_UNKNOWN, L["RECIPE_NO_PROFESSION"])
    elseif skill > 0 and rank < skill then
        status = Colorize(COLOR_TOO_HIGH, string.format(L["RECIPE_SKILL_TOO_LOW"], skill, rank))
    else
        status = Colorize(COLOR_GOOD, L["RECIPE_LEARNABLE"])
    end
    lines[#lines + 1] = Icon(profession, 14) .. " " .. Colorize(COLOR_GOLD, ns.GetProfessionName(professionID) .. ":") .. " " .. status

    if ns.db.showAltKnown then
        local knowing = ns.GetAltsKnowing(spellID)
        if knowing then
            lines[#lines + 1] = "   " .. Colorize(COLOR_HINT, L["KNOWN_BY"]) .. " " .. table.concat(knowing, ", ")
        end
        local learners = ns.GetAltsAbleToLearn(spellID)
        if learners then
            lines[#lines + 1] = "   " .. Colorize(COLOR_HINT, L["LEARNABLE_BY"]) .. " " .. table.concat(learners, ", ")
        end
    end
end

-- ----------------------------------------------------------------------------
-- Abschnitt 2: Hergestelltes Item
-- ----------------------------------------------------------------------------
local function AddCraftedSection(lines, itemID)
    local spells = ns.GetRecipesCreating(itemID)
    if not spells then return end
    local shown = 0
    for _, spellID in ipairs(spells) do
        local recipe, professionID = ns.GetRecipe(spellID)
        if shown < MAX_CRAFTED_RECIPES and not ns.db.disabledProfessions[professionID] then
            shown = shown + 1
            local difficulty = ns.GetKnownDifficulty(spellID)
            local name = ns.GetRecipeName(spellID, recipe) or ("#" .. spellID)
            local text = Colorize(COLOR_HINT, L["CRAFTED_BY"]) .. " " .. Icon(ns.GetProfession(professionID), 14) .. " "
                .. Colorize(difficulty and DIFFICULTY_COLORS[difficulty] or COLOR_UNKNOWN, name)
            local skill = ns.GetRecipeSkill(recipe)
            if skill > 0 and ns.db.showSkill then
                text = text .. " " .. Colorize(COLOR_UNKNOWN, "(" .. skill .. ")")
            end
            lines[#lines + 1] = text

            if ns.db.showCraftedReagents then
                local parts = {}
                local reagents = ns.GetRecipeReagents(recipe)
                for i = 1, #reagents, 2 do
                    parts[#parts + 1] = reagents[i + 1] .. "× " .. ItemName(reagents[i])
                end
                lines[#lines + 1] = "   " .. Colorize("ffcccccc", table.concat(parts, ", "))
            end
        end
    end
end

-- ----------------------------------------------------------------------------
-- Abschnitt 3: Zutat
-- ----------------------------------------------------------------------------
-- Fügt die Zeilen eines angezeigten Berufs an. Rückgabe: wantShiftHint, hasKnown
local function AddProfessionGroup(lines, itemID, professionID, spells, shift)
    local db = ns.db
    local profession = ns.GetProfession(professionID)
    local rank, maxRank = ns.GetProfessionRank(professionID)

    local difficulties = {} -- [spellID] = Schwierigkeit, nur für gelernte Rezepte
    local known, unknown = {}, {}
    local hasSkillupKnown = false
    for _, spellID in ipairs(spells) do
        local difficulty = ns.GetKnownDifficulty(spellID)
        if difficulty then
            difficulties[spellID] = difficulty
            known[#known + 1] = spellID
            if difficulty ~= TRIVIAL then
                hasSkillupKnown = true
            end
        elseif PassesUnknownFilter(spellID, rank) then
            unknown[#unknown + 1] = spellID
        end
    end

    lines[#lines + 1] = FormatHeader(profession, rank, maxRank, #known, #spells)
    if not db.detailed then
        return false, #known > 0
    end

    local wantHint = false
    local limit = (shift or db.maxLinesPerProfession == 0) and UNLIMITED or db.maxLinesPerProfession
    local shown, trivialHidden = 0, 0
    local hideTrivial = db.hideTrivialKnownOnShift and not shift and hasSkillupKnown
    local grouped = db.groupByKnown

    local function AddOverflow(count)
        if count > 0 then
            lines[#lines + 1] = "   " .. Colorize(COLOR_UNKNOWN, string.format(L["MORE_RECIPES"], count))
            wantHint = true
        end
    end

    -- Gelernte Rezepte: Skillups zuerst, dann höchster Skill, dann Spell-ID (stabil)
    table.sort(known, function(a, b)
        local trivialA, trivialB = difficulties[a] == TRIVIAL, difficulties[b] == TRIVIAL
        if trivialA ~= trivialB then
            return trivialB
        end
        local skillA = ns.GetRecipeSkill(ns.GetRecipe(a))
        local skillB = ns.GetRecipeSkill(ns.GetRecipe(b))
        if skillA ~= skillB then
            return skillA > skillB
        end
        return a < b
    end)

    if grouped and #known > 0 then
        lines[#lines + 1] = SECTION_KNOWN .. " " .. Colorize(COLOR_GOOD, L["SECTION_KNOWN"])
    end
    local overflowKnown = 0
    for _, spellID in ipairs(known) do
        local difficulty = difficulties[spellID]
        if hideTrivial and difficulty == TRIVIAL then
            trivialHidden = trivialHidden + 1
        elseif shown < limit then
            lines[#lines + 1] = FormatRecipeLine(spellID, itemID, difficulty, rank)
            shown = shown + 1
        else
            overflowKnown = overflowKnown + 1
        end
    end
    if trivialHidden > 0 then
        lines[#lines + 1] = "   " .. Colorize(COLOR_UNKNOWN, string.format(L["TRIVIAL_HIDDEN"], trivialHidden))
        wantHint = true
    end
    if grouped then
        AddOverflow(overflowKnown)
        overflowKnown = 0
    end

    local overflowUnknown = 0
    if #unknown > 0 then
        if grouped then
            lines[#lines + 1] = SECTION_UNKNOWN .. " " .. Colorize(COLOR_TOO_HIGH, L["SECTION_UNKNOWN"])
        end
        if db.unknownOnlyOnShift and not shift then
            lines[#lines + 1] = "   " .. Colorize(COLOR_UNKNOWN, string.format(L["UNKNOWN_COUNT"], #unknown))
            wantHint = true
        else
            for _, spellID in ipairs(unknown) do
                if shown < limit then
                    lines[#lines + 1] = FormatRecipeLine(spellID, itemID, nil, rank)
                    shown = shown + 1
                else
                    overflowUnknown = overflowUnknown + 1
                end
            end
        end
    end
    AddOverflow(overflowKnown + overflowUnknown)
    return wantHint, #known > 0
end

local function AddIngredientSection(lines, itemID, shift)
    local spells = ns.GetRecipesForItem(itemID)
    if not spells then return end
    local db = ns.db

    -- Die Liste ist nach Beruf sortiert -> in Gruppen aufteilen.
    -- Fremde Berufe (nicht erlernt, aber nicht abgewählt) erscheinen nur als Icon.
    local groups, order = {}, {}
    local others, isOther = {}, {}
    for _, spellID in ipairs(spells) do
        local _, professionID = ns.GetRecipe(spellID)
        if ns.IsProfessionShown(professionID) then
            local group = groups[professionID]
            if not group then
                group = {}
                groups[professionID] = group
                order[#order + 1] = professionID
            end
            group[#group + 1] = spellID
        elseif db.showOtherProfessionIcons and not db.disabledProfessions[professionID] and not isOther[professionID] then
            isOther[professionID] = true
            others[#others + 1] = professionID
        end
    end
    if #order == 0 and #others == 0 then return end

    local wantShiftHint, wantScanHint = false, false
    for index, professionID in ipairs(order) do
        if index > 1 and db.detailed and db.spacing then
            lines[#lines + 1] = " "
        end
        local wantHint, hasKnown = AddProfessionGroup(lines, itemID, professionID, groups[professionID], shift)
        wantShiftHint = wantShiftHint or wantHint
        -- Hinweis nur, solange für einen eigenen Beruf weder Scan noch IsPlayerSpell etwas gefunden hat
        if ns.HasProfession(professionID) and not ns.char.scanned[professionID] and not hasKnown then
            wantScanHint = true
        end
    end

    if #others > 0 then
        local icons = {}
        for i, professionID in ipairs(others) do
            icons[i] = Icon(ns.GetProfession(professionID), 16)
        end
        if #order > 0 and db.detailed and db.spacing then
            lines[#lines + 1] = " "
        end
        lines[#lines + 1] = Colorize(COLOR_HINT, L["OTHER_PROFESSIONS"]) .. "  " .. table.concat(icons, " ")
    end

    if wantScanHint and db.showHints then
        lines[#lines + 1] = Colorize(COLOR_HINT, L["HINT_SCAN"])
    end
    if wantShiftHint and not shift and db.showHints then
        lines[#lines + 1] = Colorize(COLOR_HINT, L["HINT_SHIFT"])
    end
end

-- ----------------------------------------------------------------------------
-- Zusammenbau
-- ----------------------------------------------------------------------------
local function BuildLines(itemID, shift)
    local db = ns.db
    local lines = {}
    local function Section(add, ...)
        local before = #lines
        if before > 0 and db.spacing then
            lines[#lines + 1] = " "
        end
        add(lines, ...)
        if #lines == before + 1 and lines[#lines] == " " then
            lines[#lines] = nil -- Abschnitt war leer -> Leerzeile wieder entfernen
        end
    end
    if db.showRecipeItemInfo then
        Section(AddRecipeItemSection, itemID)
    end
    if db.showCraftedBy then
        Section(AddCraftedSection, itemID)
    end
    Section(AddIngredientSection, itemID, shift)
    return #lines > 0 and lines or false
end

-- Fügt die Zeilen an einen Tooltip an. Rückgabe: true, wenn etwas angefügt wurde.
function ns.AddTooltipLines(tooltip, itemID)
    if not itemID then return false end
    local slot = IsShiftKeyDown() and 2 or 1
    local entry = cache[itemID]
    if not entry then
        entry = {}
        cache[itemID] = entry
    end
    local cached = entry[slot]
    if not cached or (IsVolatile() and GetTime() - cached.time > VOLATILE_CACHE_SECONDS) then
        cached = { lines = BuildLines(itemID, slot == 2), time = GetTime() }
        entry[slot] = cached
    end
    local lines = cached.lines
    if not lines then return false end

    tooltip:AddLine(" ")
    for i = 1, #lines do
        tooltip:AddLine(lines[i], 1, 1, 1)
    end
    return true
end

-- Shift ändert den Inhalt -> offenen Item-Tooltip sofort neu aufbauen
local canRefresh = GameTooltip.RefreshData and GameTooltip.IsTooltipType
ns.RegisterEvent("MODIFIER_STATE_CHANGED", function(_, key)
    if not canRefresh or (key ~= "LSHIFT" and key ~= "RSHIFT") then return end
    if GameTooltip:IsShown() and GameTooltip:IsTooltipType(Enum.TooltipDataType.Item) then
        GameTooltip:RefreshData()
    end
end)

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    local itemID = data and data.id
    if itemID == nil or (issecretvalue and issecretvalue(itemID)) then return end
    if ns.AddTooltipLines(tooltip, itemID) then
        tooltip:Show()
    end
end)
