-- UI/RecipeWindow.lua
-- Window "Missing recipes": the recipes of a profession the character hasn't learned yet,
-- with the required skill and where to get them (Sources.lua).
local _, ns = ...
local L = ns.L
local Widgets = ns.Widgets

local WIDTH, HEIGHT = 640, 660
local HEADER_HEIGHT = 52
local MARGIN = 22
local CONTENT_WIDTH = WIDTH - 2 * MARGIN
local PROFESSION_BUTTON, PROFESSION_GAP = 30, 5
local ROW_HEIGHT, ROW_COUNT = 20, 17
local LIST_HEIGHT = ROW_HEIGHT * ROW_COUNT + 8
local SCROLL_STEP = 3
local MAX_TOOLTIP_VENDORS = 6
local ICON_SIZE = 16

local FILTERS = { "ALL" }
for _, kind in ipairs(ns.SOURCE_KINDS) do
    FILTERS[#FILTERS + 1] = kind
end
local FILTER_LABELS = {
    ALL = "FILTER_ALL", TRAINER = "SOURCE_TRAINER", VENDOR = "SOURCE_VENDOR",
    DROP = "SOURCE_DROP", QUEST = "SOURCE_QUEST", OTHER = "SOURCE_OTHER",
}
local DIFFICULTY_COLORS = {
    [0] = { 1, 0.5, 0 }, [1] = { 1, 1, 0 }, [2] = { 0.25, 0.75, 0.25 }, [3] = { 0.5, 0.5, 0.5 },
}
local COLOR_TOO_HIGH = { 1, 0.31, 0.31 }
local COLOR_NORMAL = { 1, 1, 1 }
local COLOR_DIM = { 0.6, 0.6, 0.6 }
-- "Requires %s (%d)" in the client's language
local REQUIRES_SKILL = ITEM_MIN_SKILL or "Requires %s (%d)"

local window
local columns = {}
local professionButtons = {}
local rows = {}
local entries = {}   -- recipes shown in the list: { spellID, name, skill, tooHigh, summary }
local offset = 0     -- index of the first visible entry - 1
local missingCount, totalCount = 0, 0
local slider, summaryText, emptyText, scanText
local updatingSlider = false

-- ----------------------------------------------------------------------------
-- Data
-- ----------------------------------------------------------------------------
local recipeProfessions -- [skillLineID] = true for professions that have recipes

local function HasRecipes(professionID)
    if not recipeProfessions then
        recipeProfessions = {}
        ns.ForEachRecipe(function(_, _, id)
            recipeProfessions[id] = true
        end)
    end
    return recipeProfessions[professionID]
end

-- Remembered profession, otherwise the first own one, otherwise the first with recipes
local function GetSelectedProfession()
    local selected = ns.char.recipeProfession
    if selected and ns.GetProfession(selected) and HasRecipes(selected) then
        return selected
    end
    local fallback
    for _, profession in ipairs(ns.Professions) do
        if HasRecipes(profession.id) then
            if ns.HasProfession(profession.id) then
                return profession.id
            end
            fallback = fallback or profession.id
        end
    end
    return fallback
end

-- Item to preview for a recipe: the recipe item (its tooltip includes the product),
-- otherwise the crafted item. nil for recipes without an item (e.g. enchants).
local function GetPreviewItem(spellID, recipe)
    return ns.GetRecipeItem(spellID) or (recipe and ns.GetCreatedItem(recipe))
end

local function GetRecipeIcon(spellID, recipe)
    local itemID = recipe and ns.GetCreatedItem(recipe) or ns.GetRecipeItem(spellID)
    local icon = itemID and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)
    if not icon and C_Spell and C_Spell.GetSpellTexture then
        icon = C_Spell.GetSpellTexture(spellID)
    end
    return icon or ns.ICON
end

-- Required skill ascending (unknown last), then by name
local function CompareEntries(a, b)
    if a.skill ~= b.skill then
        if a.skill == 0 or b.skill == 0 then
            return b.skill == 0
        end
        return a.skill < b.skill
    end
    if a.name ~= b.name then
        return a.name < b.name
    end
    return a.spellID < b.spellID
end

local function BuildEntries(professionID)
    wipe(entries)
    missingCount, totalCount = 0, 0
    if not professionID then return end
    local rank = ns.GetProfessionRank(professionID)
    local filter = ns.db.recipeFilter
    local learnableOnly = ns.db.recipeLearnableOnly
    ns.ForEachRecipe(function(spellID, recipe, id)
        if id ~= professionID then return end
        totalCount = totalCount + 1
        if ns.GetKnownDifficulty(spellID) then return end
        missingCount = missingCount + 1
        local skill = ns.GetRequiredSkill(spellID, recipe)
        local tooHigh = rank ~= nil and skill > rank
        if (filter == "ALL" or ns.HasSourceKind(spellID, filter)) and not (learnableOnly and (tooHigh or not rank)) then
            entries[#entries + 1] = {
                spellID = spellID,
                name = ns.GetRecipeName(spellID, recipe) or ("#" .. spellID),
                skill = skill,
                tooHigh = tooHigh,
                summary = ns.GetSourceSummary(spellID),
                icon = GetRecipeIcon(spellID, recipe),
            }
        end
    end)
    table.sort(entries, CompareEntries)
end

-- ----------------------------------------------------------------------------
-- Item preview: second tooltip next to the info tooltip with the real item (icon, stats)
-- ----------------------------------------------------------------------------
local itemTooltip

local function GetItemTooltip()
    if not itemTooltip then
        -- Own tooltip: the item hook in Tooltip.lua only touches GameTooltip/ItemRefTooltip,
        -- so the preview stays the plain Blizzard tooltip
        itemTooltip = CreateFrame("GameTooltip", "ProfessionTooltipItemPreview", UIParent, "GameTooltipTemplate")
        itemTooltip.icon = itemTooltip:CreateTexture(nil, "ARTWORK")
        itemTooltip.icon:SetSize(36, 36)
        itemTooltip.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    return itemTooltip
end

local function HideItemPreview()
    if itemTooltip then itemTooltip:Hide() end
end

local function ShowItemPreview(spellID, recipe)
    local tooltip = GetItemTooltip()
    tooltip:SetOwner(GameTooltip, "ANCHOR_NONE")
    local itemID = GetPreviewItem(spellID, recipe)
    if itemID then
        tooltip:SetItemByID(itemID)
    elseif tooltip.SetSpellByID then
        tooltip:SetSpellByID(spellID) -- enchants: the spell describes the effect
    else
        return
    end
    tooltip:Show()

    -- Right of the info tooltip, or left of it if there is no room on the screen
    local right, screenRight = GameTooltip:GetRight(), UIParent:GetRight()
    local roomRight = true
    if right and screenRight then
        local scale = tooltip:GetEffectiveScale() / UIParent:GetEffectiveScale()
        roomRight = right + (tooltip:GetWidth() + 40) * scale <= screenRight
    end
    tooltip:ClearAllPoints()
    tooltip.icon:ClearAllPoints()
    if roomRight then
        tooltip:SetPoint("TOPLEFT", GameTooltip, "TOPRIGHT", 40, 0)
        tooltip.icon:SetPoint("TOPRIGHT", tooltip, "TOPLEFT", -2, -2)
    else
        tooltip:SetPoint("TOPRIGHT", GameTooltip, "TOPLEFT", -40, 0)
        tooltip.icon:SetPoint("TOPLEFT", tooltip, "TOPRIGHT", 2, -2)
    end
    tooltip.icon:SetTexture(GetRecipeIcon(spellID, recipe))
end

-- ----------------------------------------------------------------------------
-- List
-- ----------------------------------------------------------------------------
local function ShowRowTooltip(row)
    local entry = row.entry
    if not entry then return end
    local recipe, professionID = ns.GetRecipe(entry.spellID)
    if not recipe then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine("|T" .. GetRecipeIcon(entry.spellID, recipe) .. ":18:18:0:0:64:64:5:59:5:59|t " .. entry.name, 1, 0.82, 0)
    if entry.skill > 0 then
        local color = entry.tooHigh and COLOR_TOO_HIGH or COLOR_NORMAL
        GameTooltip:AddLine(string.format(REQUIRES_SKILL, ns.GetProfessionName(professionID), entry.skill),
            color[1], color[2], color[3])
    end

    local parts = {}
    local reagents = ns.GetRecipeReagents(recipe)
    for i = 1, #reagents, 2 do
        parts[#parts + 1] = reagents[i + 1] .. "× " .. ns.ItemName(reagents[i])
    end
    if #parts > 0 then
        GameTooltip:AddLine(table.concat(parts, ", "), 0.8, 0.8, 0.8, true)
    end

    GameTooltip:AddLine(" ")
    local lines = ns.GetSourceLines(entry.spellID, MAX_TOOLTIP_VENDORS)
    if lines then
        for _, line in ipairs(lines) do
            GameTooltip:AddLine(line, 1, 1, 1, true)
        end
    else
        GameTooltip:AddLine(L["SOURCE_UNKNOWN"], 0.6, 0.6, 0.6)
    end
    if ns.GetSourceWaypoint(entry.spellID) then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["RECIPES_CLICK_MAP"], 0.5, 0.75, 1)
    end
    GameTooltip:Show()
    ShowItemPreview(entry.spellID, recipe)
end

local function CreateRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 4, -4 - (index - 1) * ROW_HEIGHT)
    row:SetPoint("TOPRIGHT", -18, -4 - (index - 1) * ROW_HEIGHT)
    row:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
    row:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.07)

    row.skill = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.skill:SetPoint("LEFT", 2, 0)
    row.skill:SetWidth(30)
    row.skill:SetJustifyH("RIGHT")

    row.source = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    row.source:SetPoint("RIGHT", -4, 0)
    row.source:SetWidth(190)
    row.source:SetJustifyH("RIGHT")
    row.source:SetWordWrap(false)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.icon:SetPoint("LEFT", row.skill, "RIGHT", 8, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row.source, "LEFT", -8, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row:SetScript("OnEnter", ShowRowTooltip)
    -- Click: world map and map pin on the vendor
    row:SetScript("OnClick", function(self)
        if self.entry then
            ns.ShowSourceOnMap(self.entry.spellID)
        end
    end)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
        HideItemPreview()
    end)
    return row
end

local function UpdateRows()
    local professionID = GetSelectedProfession()
    for index, row in ipairs(rows) do
        local entry = entries[offset + index]
        row.entry = entry
        row:SetShown(entry ~= nil)
        if entry then
            local color = COLOR_DIM
            if entry.tooHigh then
                color = COLOR_TOO_HIGH
            elseif professionID and ns.HasProfession(professionID) then
                color = DIFFICULTY_COLORS[ns.GetRecipeDifficulty(entry.spellID)] or COLOR_NORMAL
            end
            row.skill:SetText(entry.skill > 0 and entry.skill or "–")
            row.skill:SetTextColor(color[1], color[2], color[3])
            local nameColor = entry.tooHigh and COLOR_DIM or COLOR_NORMAL
            row.icon:SetTexture(entry.icon)
            row.icon:SetDesaturated(entry.tooHigh)
            row.name:SetText(entry.name)
            row.name:SetTextColor(nameColor[1], nameColor[2], nameColor[3])
            row.source:SetText(entry.summary or L["SOURCE_UNKNOWN"])
        end
    end
end

local function SetOffset(value)
    local maxOffset = math.max(0, #entries - ROW_COUNT)
    offset = math.max(0, math.min(maxOffset, value))
    updatingSlider = true
    slider:SetMinMaxValues(0, maxOffset)
    slider:SetValue(offset)
    slider:SetShown(maxOffset > 0)
    updatingSlider = false
    UpdateRows()
end

local function CreateList(frame, y)
    local box = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    box:SetPoint("TOPLEFT", MARGIN, y)
    box:SetSize(CONTENT_WIDTH, LIST_HEIGHT)
    Widgets.Backdrop(box, { 0, 0, 0, 0.35 }, { 1, 1, 1, 0.08 })
    box:EnableMouseWheel(true)
    box:SetScript("OnMouseWheel", function(_, delta)
        SetOffset(offset - delta * SCROLL_STEP)
    end)

    for index = 1, ROW_COUNT do
        rows[index] = CreateRow(box, index)
    end

    emptyText = box:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    emptyText:SetPoint("CENTER")
    emptyText:SetWidth(CONTENT_WIDTH - 60)

    slider = CreateFrame("Slider", nil, box)
    slider:SetOrientation("VERTICAL")
    slider:SetWidth(8)
    slider:SetPoint("TOPRIGHT", -5, -5)
    slider:SetPoint("BOTTOMRIGHT", -5, 5)
    slider:SetThumbTexture("Interface\\Buttons\\WHITE8x8")
    local thumb = slider:GetThumbTexture()
    thumb:SetSize(8, 36)
    thumb:SetVertexColor(Widgets.ACCENT[1], Widgets.ACCENT[2], Widgets.ACCENT[3], 0.7)
    slider:SetMinMaxValues(0, 0)
    slider:SetValueStep(1)
    slider:SetValue(0)
    slider:SetScript("OnValueChanged", function(_, value)
        if updatingSlider then return end
        local rounded = math.floor(value + 0.5)
        if rounded ~= offset then
            offset = rounded
            UpdateRows()
        end
    end)
end

-- ----------------------------------------------------------------------------
-- Profession buttons
-- ----------------------------------------------------------------------------
local Refresh -- forward declaration, defined below

local function CreateProfessionButton(frame, profession, x, y)
    local button = CreateFrame("Button", nil, frame, "BackdropTemplate")
    button:SetSize(PROFESSION_BUTTON, PROFESSION_BUTTON)
    button:SetPoint("TOPLEFT", x, y)
    Widgets.Backdrop(button, { 0, 0, 0, 0.5 }, { 1, 1, 1, 0.12 })

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 2, -2)
    button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    button.icon:SetTexture(profession.icon)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    button:SetScript("OnClick", function()
        ns.char.recipeProfession = profession.id
        offset = 0
        Refresh()
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(ns.GetProfessionName(profession.id), 1, 0.82, 0)
        local rank, maxRank = ns.GetProfessionRank(profession.id)
        if rank then
            GameTooltip:AddLine(rank .. " / " .. maxRank, 1, 1, 1)
        else
            GameTooltip:AddLine(L["NOT_LEARNED"], 0.5, 0.5, 0.5)
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button.profession = profession
    return button
end

local function UpdateProfessionButtons(selected)
    for _, button in ipairs(professionButtons) do
        local id = button.profession.id
        local owned = ns.HasProfession(id)
        button.icon:SetDesaturated(not owned)
        button.icon:SetAlpha(owned and 1 or 0.6)
        if id == selected then
            button:SetBackdropBorderColor(Widgets.ACCENT[1], Widgets.ACCENT[2], Widgets.ACCENT[3], 1)
        else
            button:SetBackdropBorderColor(1, 1, 1, 0.12)
        end
    end
end

-- ----------------------------------------------------------------------------
-- Window
-- ----------------------------------------------------------------------------
local function UpdateSummary(professionID)
    if not professionID then
        summaryText:SetText("")
        return
    end
    local text = "|cffffd100" .. ns.GetProfessionName(professionID) .. "|r"
    local rank, maxRank = ns.GetProfessionRank(professionID)
    text = text .. "  " .. (rank and (rank .. "/" .. maxRank) or ("|cff808080" .. L["NOT_LEARNED"] .. "|r"))
    text = text .. "  •  " .. string.format(L["RECIPES_SUMMARY"], missingCount, totalCount)
    if #entries ~= missingCount then
        text = text .. "  •  " .. string.format(L["RECIPES_SHOWN"], #entries)
    end
    summaryText:SetText(text)
end

Refresh = function()
    if not (window and window:IsShown()) then return end
    for _, col in ipairs(columns) do
        col:Refresh()
    end
    local professionID = GetSelectedProfession()
    BuildEntries(professionID)
    UpdateProfessionButtons(professionID)
    UpdateSummary(professionID)
    emptyText:SetText(#entries == 0 and L["RECIPES_EMPTY"] or "")
    -- Without a scan only IsSpellKnown tells what is learned: point to the profession window
    local unscanned = professionID and ns.HasProfession(professionID) and not ns.char.scanned[professionID]
    scanText:SetText(unscanned and L["HINT_SCAN"] or "")
    SetOffset(offset)
end

local function CreateHeader(frame)
    local header = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(HEADER_HEIGHT)
    Widgets.Backdrop(header, { 0.12, 0.09, 0.06, 1 }, { 0, 0, 0, 0 })

    local accent = header:CreateTexture(nil, "ARTWORK")
    accent:SetColorTexture(Widgets.ACCENT[1], Widgets.ACCENT[2], Widgets.ACCENT[3], 0.7)
    accent:SetHeight(2)
    accent:SetPoint("BOTTOMLEFT")
    accent:SetPoint("BOTTOMRIGHT")

    local icon = header:CreateTexture(nil, "ARTWORK")
    icon:SetSize(34, 34)
    icon:SetPoint("LEFT", 14, 0)
    icon:SetTexture(ns.ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local title = header:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
    title:SetText(L["RECIPES_TITLE"])

    local subtitle = header:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    subtitle:SetText("Profession Tooltip")

    local close = CreateFrame("Button", nil, header, "UIPanelCloseButton")
    close:SetPoint("RIGHT", -6, 0)
    close:SetScript("OnClick", function() frame:Hide() end)
end

local function CreateWindow()
    local frame = CreateFrame("Frame", "ProfessionTooltipRecipeFrame", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    Widgets.Backdrop(frame, { 0.05, 0.05, 0.06, 0.96 }, { 0.30, 0.30, 0.33, 1 })
    tinsert(UISpecialFrames, "ProfessionTooltipRecipeFrame") -- ESC closes the window

    CreateHeader(frame)

    -- Professions: one icon each, own professions in color
    local y = -HEADER_HEIGHT - 14
    local x = MARGIN
    for _, profession in ipairs(ns.Professions) do
        if HasRecipes(profession.id) then
            professionButtons[#professionButtons + 1] = CreateProfessionButton(frame, profession, x, y)
            x = x + PROFESSION_BUTTON + PROFESSION_GAP
        end
    end
    y = y - PROFESSION_BUTTON - 14

    -- Filter by source
    local filterColumn = Widgets.NewColumn(frame, MARGIN, y, CONTENT_WIDTH)
    filterColumn:Choice({
        label = L["RECIPES_FILTER"],
        values = FILTERS,
        format = function(value) return L[FILTER_LABELS[value]] end,
        get = function() return ns.db.recipeFilter end,
        set = function(value)
            offset = 0
            ns.SetOption("recipeFilter", value)
        end,
    })
    columns[#columns + 1] = filterColumn
    y = filterColumn.y

    -- Two options side by side
    local half = (CONTENT_WIDTH - 16) / 2
    local left = Widgets.NewColumn(frame, MARGIN, y, half)
    left:Check({
        label = L["RECIPES_LEARNABLE"],
        desc = L["RECIPES_LEARNABLE_DESC"],
        get = function() return ns.db.recipeLearnableOnly end,
        set = function(value)
            offset = 0
            ns.SetOption("recipeLearnableOnly", value)
        end,
    })
    local right = Widgets.NewColumn(frame, MARGIN + half + 16, y, half)
    right:Check({
        label = L["OPT_RECIPE_SOURCE"],
        desc = L["OPT_RECIPE_SOURCE_DESC"],
        get = function() return ns.db.showRecipeSource end,
        set = function(value) ns.SetOption("showRecipeSource", value) end,
    })
    columns[#columns + 1] = left
    columns[#columns + 1] = right
    y = math.min(left.y, right.y)

    summaryText = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    summaryText:SetPoint("TOPLEFT", MARGIN, y)
    summaryText:SetWidth(CONTENT_WIDTH)
    summaryText:SetJustifyH("LEFT")
    summaryText:SetWordWrap(false)
    y = y - 20

    CreateList(frame, y)
    y = y - LIST_HEIGHT - 6

    scanText = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    scanText:SetPoint("TOPLEFT", MARGIN, y)
    scanText:SetWidth(CONTENT_WIDTH)
    scanText:SetJustifyH("LEFT")

    -- Required credit for the source data
    local credit = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    credit:SetPoint("BOTTOMLEFT", MARGIN, 12)
    credit:SetWidth(CONTENT_WIDTH)
    credit:SetJustifyH("LEFT")
    credit:SetText(L["SOURCE_CREDIT"])

    frame:SetScript("OnShow", function() Refresh() end)
    frame:Hide()
    return frame
end

function ns.ToggleRecipeWindow()
    if not window then
        window = CreateWindow()
    end
    window:SetShown(not window:IsShown())
end

ns.On("SETTINGS_CHANGED", Refresh)
ns.On("DATA_CHANGED", Refresh)
ns.On("TOOLTIP_REFRESH", Refresh) -- names of recipe items loaded later
