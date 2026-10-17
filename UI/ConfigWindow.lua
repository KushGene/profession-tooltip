-- UI/ConfigWindow.lua
-- Einstellungsfenster: Tabs links, Live-Vorschau rechts.
local _, ns = ...
local L = ns.L
local Widgets = ns.Widgets

local WIDTH, HEIGHT = 820, 680
local HEADER_HEIGHT = 52
local LEFT_X, LEFT_WIDTH = 22, 390
local RIGHT_X = LEFT_X + LEFT_WIDTH + 36
local CONTENT_Y = -HEADER_HEIGHT - 48

local MAX_LINE_VALUES = { 5, 8, 10, 15, 20, 30, 0 }
local HEADER_STYLES = { "full", "icon", "name" }
local HEADER_STYLE_LABELS = { full = "STYLE_FULL", icon = "STYLE_ICON", name = "STYLE_NAME" }
local UNKNOWN_FILTERS = { "all", "learnable", "noGray" }
local UNKNOWN_FILTER_LABELS = { all = "FILTER_ALL", learnable = "FILTER_LEARNABLE", noGray = "FILTER_NO_GRAY" }
local MAX_CHARACTER_ROWS = 6

local window
local columns = {}
local Refresh -- forward declaration, definiert unten

local function Option(key, label, desc, enabled, indent)
    return {
        label = L[label],
        desc = L[desc],
        get = function() return ns.db[key] end,
        set = function(value) ns.SetOption(key, value) end,
        enabled = enabled,
        indent = indent,
    }
end

local function IsDetailed()
    return ns.db.detailed
end

local function IsSkillShown()
    return ns.db.detailed and ns.db.showSkill
end

local function IsOnlyOwn()
    return ns.db.onlyOwnProfessions
end

-- "Noch nicht gescannt: Alchimie, Kräuterkunde" oder nil
local function GetScanNotice()
    local names = ns.GetUnscannedProfessionNames()
    if #names > 0 then
        return string.format(L["SCAN_PENDING"], table.concat(names, ", "))
    end
end

-- ----------------------------------------------------------------------------
-- Tabs
-- ----------------------------------------------------------------------------
local function BuildTooltipTab(page)
    local col = Widgets.NewColumn(page, 0, 0, LEFT_WIDTH)
    col:Header(L["SECTION_RECIPES"])
    col:Check(Option("detailed", "OPT_DETAILED", "OPT_DETAILED_DESC"))
    col:Check(Option("showSkill", "OPT_SKILL", "OPT_SKILL_DESC", IsDetailed))
    col:Check(Option("showSkillKnown", "OPT_SKILL_KNOWN", "OPT_SKILL_KNOWN_DESC", IsSkillShown, true))
    col:Check(Option("showReagentCount", "OPT_REAGENT_COUNT", "OPT_REAGENT_COUNT_DESC", IsDetailed))
    col:Check(Option("groupByKnown", "OPT_GROUP_KNOWN", "OPT_GROUP_KNOWN_DESC", IsDetailed))
    col:Choice({
        label = L["OPT_MAX_LINES"],
        desc = L["OPT_MAX_LINES_DESC"],
        values = MAX_LINE_VALUES,
        format = function(value) return value == 0 and L["UNLIMITED"] or tostring(value) end,
        get = function() return ns.db.maxLinesPerProfession end,
        set = function(value) ns.SetOption("maxLinesPerProfession", value) end,
    })
    col:Choice({
        label = L["OPT_UNKNOWN_FILTER"],
        desc = L["OPT_UNKNOWN_FILTER_DESC"],
        values = UNKNOWN_FILTERS,
        format = function(value) return L[UNKNOWN_FILTER_LABELS[value]] end,
        get = function() return ns.db.unknownFilter end,
        set = function(value) ns.SetOption("unknownFilter", value) end,
    })
    col:Header(L["SECTION_SHIFT"])
    col:Check(Option("unknownOnlyOnShift", "OPT_UNKNOWN_SHIFT", "OPT_UNKNOWN_SHIFT_DESC", IsDetailed))
    col:Check(Option("hideTrivialKnownOnShift", "OPT_HIDE_TRIVIAL", "OPT_HIDE_TRIVIAL_DESC", IsDetailed))
    return col
end

local function BuildDesignTab(page)
    local col = Widgets.NewColumn(page, 0, 0, LEFT_WIDTH)
    col:Header(L["SECTION_HEADER"])
    col:Choice({
        label = L["OPT_HEADER_STYLE"],
        desc = L["OPT_HEADER_STYLE_DESC"],
        values = HEADER_STYLES,
        format = function(value) return L[HEADER_STYLE_LABELS[value]] end,
        get = function() return ns.db.headerStyle end,
        set = function(value) ns.SetOption("headerStyle", value) end,
    })
    col:Check(Option("showProfessionRank", "OPT_SHOW_RANK", "OPT_SHOW_RANK_DESC"))
    col:Check(Option("showKnownCount", "OPT_SHOW_KNOWN_COUNT", "OPT_SHOW_KNOWN_COUNT_DESC"))
    col:Space(6)
    col:Header(L["SECTION_LAYOUT"])
    col:Check(Option("spacing", "OPT_SPACING", "OPT_SPACING_DESC", IsDetailed))
    col:Check(Option("showHints", "OPT_HINTS", "OPT_HINTS_DESC"))
    return col
end

local function CreateProfessionRow(page, col, profession)
    local row = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    row:SetSize(22, 22)
    row:SetPoint("TOPLEFT", col.x, col.y + 2)
    row:SetHitRectInsets(0, -(col.width - 22), 0, 0)

    local icon = page:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", row, "RIGHT", 4, 0)
    icon:SetTexture(profession.icon)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local name = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    name:SetText(ns.GetProfessionName(profession.id))

    local rankText = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    rankText:SetPoint("RIGHT", page, "TOPLEFT", col.x + col.width, col.y - 9)

    row:SetScript("OnClick", function(button)
        ns.SetProfessionEnabled(profession.id, button:GetChecked() and true or false)
    end)

    local item = {}
    function item.Refresh()
        local enabled = not ns.db.disabledProfessions[profession.id]
        local owned = ns.HasProfession(profession.id)
        row:SetChecked(enabled)
        -- Nicht erlernte Berufe sind bei "Nur meine Berufe" ohnehin ausgeblendet -> abgedimmt
        local active = enabled and (owned or not ns.db.onlyOwnProfessions)
        name:SetFontObject(active and "GameFontHighlight" or "GameFontDisable")
        icon:SetDesaturated(not active)
        local rank, maxRank = ns.GetProfessionRank(profession.id)
        rankText:SetText(rank and ("|cffffd100" .. rank .. "|r / " .. maxRank) or ("|cff808080" .. L["NOT_LEARNED"] .. "|r"))
    end
    col:Add(item, 25)
end

local function BuildProfessionsTab(page)
    local col = Widgets.NewColumn(page, 0, 0, LEFT_WIDTH)
    col:Header(L["SECTION_FILTER"])
    col:Check(Option("onlyOwnProfessions", "OPT_ONLY_OWN", "OPT_ONLY_OWN_DESC"))
    col:Check(Option("showOtherProfessionIcons", "OPT_OTHER_ICONS", "OPT_OTHER_ICONS_DESC", IsOnlyOwn, true))
    col:Header(L["SECTION_PROFESSION_LIST"])
    for _, profession in ipairs(ns.Professions) do
        CreateProfessionRow(page, col, profession)
    end
    return col
end

local function IsCraftedShown()
    return ns.db.showCraftedBy
end

-- Eine Zeile der Twink-Liste: Name, Berufs-Icons, Löschen-Button
local function CreateCharacterRow(page, col, index)
    local y = col.y - (index - 1) * 22
    local name = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    name:SetPoint("TOPLEFT", col.x, y)

    local icons = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    icons:SetPoint("LEFT", name, "RIGHT", 8, 0)

    local delete = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    delete:SetSize(22, 18)
    delete:SetText("×")
    delete:SetPoint("TOPRIGHT", page, "TOPLEFT", col.x + col.width, y + 3)

    local row = {}
    function row.Set(character)
        name:SetShown(character ~= nil)
        icons:SetShown(character ~= nil)
        delete:SetShown(character ~= nil and not character.isPlayer)
        if not character then return end
        name:SetText(character.colored .. (character.isPlayer and (" |cff888888" .. L["CURRENT_CHARACTER"] .. "|r") or ""))
        local parts = {}
        for _, profession in ipairs(ns.Professions) do
            local info = character.entry.professions and character.entry.professions[profession.id]
            if info then
                parts[#parts + 1] = "|T" .. profession.icon .. ":14:14:0:0:64:64:5:59:5:59|t" .. info.rank
            end
        end
        icons:SetText(table.concat(parts, "  "))
        delete:SetScript("OnClick", function() ns.DeleteCharacter(character.key) end)
    end
    return row
end

local function BuildExtrasTab(page)
    local col = Widgets.NewColumn(page, 0, 0, LEFT_WIDTH)
    col:Header(L["SECTION_EXTRAS"])
    col:Check(Option("showAltKnown", "OPT_ALT_KNOWN", "OPT_ALT_KNOWN_DESC"))
    col:Check(Option("showRecipeItemInfo", "OPT_RECIPE_ITEMS", "OPT_RECIPE_ITEMS_DESC"))
    col:Check(Option("showCraftedBy", "OPT_CRAFTED_BY", "OPT_CRAFTED_BY_DESC"))
    col:Check(Option("showCraftedReagents", "OPT_CRAFTED_REAGENTS", "OPT_CRAFTED_REAGENTS_DESC", IsCraftedShown, true))
    col:Check(Option("showStockCount", "OPT_STOCK", "OPT_STOCK_DESC", IsDetailed))
    col:Check(Option("showRecipeValue", "OPT_VALUE", "OPT_VALUE_DESC", ns.IsAuctionatorAvailable))
    col:Space(6)
    col:Header(L["SECTION_CHARACTERS"])

    local rows = {}
    for i = 1, MAX_CHARACTER_ROWS do
        rows[i] = CreateCharacterRow(page, col, i)
    end
    local more = page:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    more:SetPoint("TOPLEFT", col.x, col.y - MAX_CHARACTER_ROWS * 22)

    local item = {}
    function item.Refresh()
        local characters = ns.GetCharacters()
        for i, row in ipairs(rows) do
            row.Set(characters[i])
        end
        local hidden = #characters - MAX_CHARACTER_ROWS
        more:SetText(hidden > 0 and string.format(L["MORE_CHARACTERS"], hidden) or "")
    end
    col:Add(item, MAX_CHARACTER_ROWS * 22 + 16)
    return col
end

local function BuildGeneralTab(page)
    local col = Widgets.NewColumn(page, 0, 0, LEFT_WIDTH)
    col:Header(L["SECTION_GENERAL"])
    col:Check({
        label = L["OPT_MINIMAP"],
        desc = L["OPT_MINIMAP_DESC"],
        get = function() return ns.db.minimap.show end,
        set = function(value)
            ns.db.minimap.show = value
            ns.Fire("SETTINGS_CHANGED", "minimap")
        end,
    })
    col:Space(6)
    col:Header(L["SECTION_DATA"])

    local stats = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    stats:SetPoint("TOPLEFT", col.x, col.y)
    stats:SetWidth(col.width)
    stats:SetJustifyH("LEFT")

    local scanNotice = page:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    scanNotice:SetPoint("TOPLEFT", stats, "BOTTOMLEFT", 0, -6)
    scanNotice:SetWidth(col.width)
    scanNotice:SetJustifyH("LEFT")

    local dbInfo = page:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    dbInfo:SetPoint("TOPLEFT", scanNotice, "BOTTOMLEFT", 0, -6)

    local reset = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    reset:SetSize(200, 24)
    reset:SetPoint("TOPLEFT", dbInfo, "BOTTOMLEFT", 0, -12)
    reset:SetText(L["RESET_SCAN"])
    reset:SetScript("OnClick", function()
        StaticPopup_Show("PROFESSIONTOOLTIP_RESET_SCAN")
    end)

    local slashHint = page:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    slashHint:SetPoint("TOPLEFT", reset, "BOTTOMLEFT", 0, -18)
    slashHint:SetText(L["SLASH_HINT"])

    local item = {}
    function item.Refresh()
        local recipes, professions = 0, {}
        for spellID in pairs(ns.char.known) do
            local _, professionID = ns.GetRecipe(spellID)
            if professionID then
                recipes = recipes + 1
                professions[professionID] = true
            end
        end
        local professionCount = 0
        for _ in pairs(professions) do professionCount = professionCount + 1 end
        stats:SetText(recipes > 0 and string.format(L["SCAN_STATS"], recipes, professionCount) or L["SCAN_NONE"])
        scanNotice:SetText(GetScanNotice() or "")
        dbInfo:SetText(string.format(L["DATA_INFO"], ns.GetDatabaseStats()) .. "\n" .. string.format(L["TRAINER_INFO"], ns.GetTrainerSkillCount()))
    end
    col:Add(item, 150)

    -- Übergang von CookingTooltip/AlchemyTooltip
    col:Header(L["SECTION_LEGACY"])
    col:Check(Option("legacyCheck", "OPT_LEGACY_CHECK", "OPT_LEGACY_CHECK_DESC"))

    local legacyStatus = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    legacyStatus:SetPoint("TOPLEFT", col.x, col.y)
    legacyStatus:SetWidth(col.width)
    legacyStatus:SetJustifyH("LEFT")

    local import = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    import:SetSize(185, 24)
    import:SetPoint("TOPLEFT", legacyStatus, "BOTTOMLEFT", 0, -8)
    import:SetText(L["LEGACY_IMPORT"])
    import:SetScript("OnClick", ns.ImportLegacySettings)

    local disable = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    disable:SetSize(185, 24)
    disable:SetPoint("LEFT", import, "RIGHT", 8, 0)
    disable:SetText(L["LEGACY_DISABLE"])
    disable:SetScript("OnClick", ns.DisableLegacyAddons)

    local legacy = {}
    function legacy.Refresh()
        local loaded = ns.GetLoadedLegacyAddons()
        legacyStatus:SetText(#loaded > 0 and string.format(L["LEGACY_ACTIVE"], table.concat(loaded, ", ")) or L["LEGACY_NONE"])
        import:SetEnabled(#loaded > 0)
        disable:SetEnabled(#loaded > 0)
    end
    col:Add(legacy, 60)
    return col
end

local TABS = {
    { label = "TAB_TOOLTIP", build = BuildTooltipTab },
    { label = "TAB_DESIGN", build = BuildDesignTab },
    { label = "TAB_PROFESSIONS", build = BuildProfessionsTab },
    { label = "TAB_EXTRAS", build = BuildExtrasTab },
    { label = "TAB_GENERAL", build = BuildGeneralTab },
}

-- ----------------------------------------------------------------------------
-- Vorschau
-- ----------------------------------------------------------------------------
-- Beispiel-Zutaten der Berufe, die im Tooltip angezeigt werden (sonst aller Berufe)
local function GetPreviewItems()
    local items, seen = {}, {}
    local function Collect(onlyShown)
        for _, profession in ipairs(ns.Professions) do
            local itemID = profession.previewItem
            if not seen[itemID] and (not onlyShown or ns.IsProfessionShown(profession.id)) then
                seen[itemID] = true
                items[#items + 1] = itemID
            end
        end
    end
    Collect(true)
    if #items == 0 then
        Collect(false)
    end
    return items
end

local function IndexOf(list, value)
    for i, v in ipairs(list) do
        if v == value then return i end
    end
end

local function CreatePreview(parent)
    local preview = {}

    local header = Widgets.NewColumn(parent, RIGHT_X, -HEADER_HEIGHT - 20, WIDTH - RIGHT_X - 22)
    header:Header(L["PREVIEW"])

    local nextButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    nextButton:SetSize(24, 20)
    nextButton:SetText(">")
    nextButton:SetPoint("TOPRIGHT", -22, -HEADER_HEIGHT - 14)

    local prevButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    prevButton:SetSize(24, 20)
    prevButton:SetText("<")
    prevButton:SetPoint("RIGHT", nextButton, "LEFT", -4, 0)

    local counter = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    counter:SetPoint("RIGHT", prevButton, "LEFT", -6, 0)

    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetPoint("TOPLEFT", RIGHT_X, CONTENT_Y)
    box:SetPoint("BOTTOMRIGHT", -22, 46)
    Widgets.Backdrop(box, { 0, 0, 0, 0.35 }, { 1, 1, 1, 0.08 })

    local emptyText = box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    emptyText:SetPoint("BOTTOMLEFT", 10, 10)
    emptyText:SetPoint("BOTTOMRIGHT", -10, 10)
    emptyText:SetJustifyH("LEFT")
    emptyText:SetText(L["PREVIEW_EMPTY"])

    local hint = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 2, -8)
    hint:SetText(L["PREVIEW_HINT"])

    -- Hinweis, solange eigene Berufsfenster noch nicht gescannt wurden
    local scanNotice = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    scanNotice:SetPoint("BOTTOMLEFT", emptyText, "TOPLEFT", 0, 8)
    scanNotice:SetPoint("BOTTOMRIGHT", emptyText, "TOPRIGHT", 0, 8)
    scanNotice:SetJustifyH("LEFT")

    local tooltip = CreateFrame("GameTooltip", "ProfessionTooltipPreview", box, "GameTooltipTemplate")
    tooltip:SetScale(0.9)

    function preview.Render()
        -- Liste neu bestimmen (Filter/Berufe können sich geändert haben), aktuelles Item möglichst behalten
        local items = GetPreviewItems()
        local index = IndexOf(items, preview.itemID) or 1
        local itemID = items[index]
        preview.itemID = itemID
        counter:SetText(index .. " / " .. #items)
        prevButton:SetEnabled(#items > 1)
        nextButton:SetEnabled(#items > 1)
        tooltip:SetOwner(box, "ANCHOR_NONE")
        tooltip:ClearAllPoints()
        tooltip:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -8)
        tooltip:SetItemByID(itemID)
        local hasLines = ns.AddTooltipLines(tooltip, itemID)
        emptyText:SetText(hasLines and "" or L["PREVIEW_EMPTY"])
        scanNotice:SetText(GetScanNotice() or "")
        tooltip:Show()
    end

    local function Step(delta)
        local items = GetPreviewItems()
        local index = IndexOf(items, preview.itemID) or 1
        preview.itemID = items[(index - 1 + delta) % #items + 1]
        preview.Render()
    end
    prevButton:SetScript("OnClick", function() Step(-1) end)
    nextButton:SetScript("OnClick", function() Step(1) end)

    return preview
end

-- ----------------------------------------------------------------------------
-- Fenster
-- ----------------------------------------------------------------------------
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
    title:SetText("Profession Tooltip")

    local version = header:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    version:SetPoint("LEFT", title, "RIGHT", 8, -1)
    version:SetText(ns.version ~= "" and ("v" .. ns.version) or "")

    local subtitle = header:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    subtitle:SetText(L["SUBTITLE"])

    local close = CreateFrame("Button", nil, header, "UIPanelCloseButton")
    close:SetPoint("RIGHT", -6, 0)
    close:SetScript("OnClick", function() frame:Hide() end)
end

local function CreateTabs(frame)
    local buttons, pages = {}, {}

    local function Select(index)
        ns.db.lastTab = index
        for i, button in ipairs(buttons) do
            local selected = (i == index)
            pages[i]:SetShown(selected)
            button.underline:SetShown(selected)
            button.text:SetFontObject(selected and "GameFontHighlight" or "GameFontNormal")
        end
    end

    local x = LEFT_X
    for i, tab in ipairs(TABS) do
        local button = CreateFrame("Button", nil, frame)
        button.text = button:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        button.text:SetPoint("CENTER")
        button.text:SetText(L[tab.label])
        button:SetSize(button.text:GetStringWidth() + 18, 26)
        button:SetPoint("TOPLEFT", x, -HEADER_HEIGHT - 12)
        button:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
        button:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.06)
        button.underline = button:CreateTexture(nil, "ARTWORK")
        button.underline:SetColorTexture(unpack(Widgets.ACCENT))
        button.underline:SetHeight(2)
        button.underline:SetPoint("BOTTOMLEFT")
        button.underline:SetPoint("BOTTOMRIGHT")
        button:SetScript("OnClick", function() Select(i) end)
        x = x + button:GetWidth() + 2
        buttons[i] = button

        local page = CreateFrame("Frame", nil, frame)
        page:SetPoint("TOPLEFT", LEFT_X, CONTENT_Y)
        page:SetSize(LEFT_WIDTH, HEIGHT + CONTENT_Y - 20)
        pages[i] = page
        columns[#columns + 1] = tab.build(page)
    end

    local tabLine = Widgets.Line(frame, 0.08)
    tabLine:SetHeight(1)
    tabLine:SetPoint("TOPLEFT", LEFT_X, -HEADER_HEIGHT - 38)
    tabLine:SetWidth(LEFT_WIDTH)

    Select(ns.db.lastTab or 1)
end

local function CreateWindow()
    local frame = CreateFrame("Frame", "ProfessionTooltipConfigFrame", UIParent, "BackdropTemplate")
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
    tinsert(UISpecialFrames, "ProfessionTooltipConfigFrame") -- ESC schließt das Fenster

    CreateHeader(frame)
    CreateTabs(frame)

    local divider = Widgets.Line(frame, 0.08)
    divider:SetWidth(1)
    divider:SetPoint("TOPLEFT", RIGHT_X - 18, -HEADER_HEIGHT - 12)
    divider:SetPoint("BOTTOMLEFT", RIGHT_X - 18, 20)

    frame.preview = CreatePreview(frame)
    frame:SetScript("OnShow", function() Refresh() end)
    frame:Hide()
    return frame
end

Refresh = function()
    if not (window and window:IsShown()) then return end
    for _, col in ipairs(columns) do
        col:Refresh()
    end
    window.preview.Render()
end

function ns.ToggleConfigWindow()
    if not window then
        window = CreateWindow()
    end
    window:SetShown(not window:IsShown())
end

function ns.OpenConfigWindow()
    if not (window and window:IsShown()) then
        ns.ToggleConfigWindow()
    end
end

ns.On("SETTINGS_CHANGED", Refresh)
ns.On("DATA_CHANGED", Refresh)
-- Vorschau live aktualisieren: Shift-Taste und nachgeladene Item-Daten
local function RenderPreview()
    if window and window:IsShown() then
        window.preview.Render()
    end
end
ns.RegisterEvent("MODIFIER_STATE_CHANGED", RenderPreview)
ns.RegisterEvent("GET_ITEM_INFO_RECEIVED", RenderPreview)

StaticPopupDialogs["PROFESSIONTOOLTIP_RESET_SCAN"] = {
    text = L["RESET_SCAN_CONFIRM"],
    button1 = YES,
    button2 = NO,
    OnAccept = ns.ResetCharacterData,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

SLASH_PROFESSIONTOOLTIP1 = "/pt"
SLASH_PROFESSIONTOOLTIP2 = "/proftip"
SlashCmdList["PROFESSIONTOOLTIP"] = ns.ToggleConfigWindow
