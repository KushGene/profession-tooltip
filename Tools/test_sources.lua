-- Recipe sources: unpacking, texts, tooltip integration and the "Missing recipes" window.
-- Run from the repository root: luajit Tools/test_sources.lua
local events = {}
wipe = function(t) for key in pairs(t) do t[key] = nil end end
tinsert = table.insert
Enum = { TooltipDataType = { Item = 0 } }
TooltipDataProcessor = { AddTooltipPostCall = function() end }
IsShiftKeyDown = function() return false end
GetTime = function() return 0 end
GetLocale = function() return "enUS" end
C_Item = { GetItemNameByID = function(itemID) return "Item " .. itemID end }
UISpecialFrames = {}

-- Minimal widget mock: every method exists, the few the tests look at keep their values
local methods = {}
local function widget(kind)
    return setmetatable({ kind = kind, scripts = {}, shown = true, lines = {} }, {
        __index = function(_, name) return methods[name] or function() end end,
    })
end
function methods:SetScript(name, callback) self.scripts[name] = callback end
function methods:SetText(text) self.text = text end
function methods:GetText() return self.text end
function methods:SetShown(shown)
    local wasShown = self.shown
    self.shown = shown and true or false
    if self.shown and not wasShown and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function methods:Show() self:SetShown(true) end
function methods:Hide() self.shown = false end
function methods:IsShown() return self.shown end
function methods:SetChecked(checked) self.checked = checked end
function methods:GetChecked() return self.checked end
function methods:SetMinMaxValues(low, high) self.min, self.max = low, high end
function methods:SetValue(value)
    self.value = value
    if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
end
function methods:GetStringHeight() return 12 end
function methods:GetStringWidth() return 40 end
function methods:GetWidth() return 60 end
function methods:CreateFontString() return widget("FontString") end
function methods:CreateTexture() return widget("Texture") end
function methods:GetHighlightTexture() return widget("Texture") end
function methods:GetThumbTexture() return widget("Texture") end
function methods:AddLine(text) self.lines[#self.lines + 1] = text end
function methods:SetOwner() self.lines = {} end
function methods:SetItemByID(itemID) self.item, self.spell = itemID, nil end
function methods:SetSpellByID(spellID) self.item, self.spell = nil, spellID end
local frames = {}
CreateFrame = function(kind, name)
    local frame = widget(kind)
    frame.name = name
    frames[#frames + 1] = frame
    return frame
end
UIParent = widget("Frame")
GameTooltip, ItemRefTooltip = widget("GameTooltip"), widget("GameTooltip")

local ns = {}
assert(loadfile("Core.lua"))("Test", ns)
for _, frame in ipairs(frames) do
    if frame.scripts.OnEvent then events.dispatch = frame.scripts.OnEvent end
end
events.dispatch(nil, "ADDON_LOADED", "Test")
assert(ns.db.showRecipeSource == false, "sources in tooltips must default to off")
assert(ns.db.recipeFilter == "ALL" and ns.db.recipeLearnableOnly == false)

local ranks = { [171] = { 100, 300 } }
ns.Professions = {
    { id = 171, key = "ALCHEMY", icon = "Alchemy", order = 1 },
    { id = 185, key = "COOKING", icon = "Cooking", order = 2 },
    { id = 356, key = "FISHING", icon = "Fishing", order = 3 }, -- no recipes
}
ns.GetProfession = function(id)
    for _, profession in ipairs(ns.Professions) do
        if profession.id == id then return profession end
    end
end
ns.GetProfessionRank = function(id) if ranks[id] then return ranks[id][1], ranks[id][2] end end
ns.HasProfession = function(id) return ranks[id] ~= nil end
ns.GetProfessionName = function(id) return id == 171 and "Alchemy" or "Cooking" end
ns.IsProfessionShown = function() return true end
ns.GetSpellName = function() end
local knownSpells = {}
ns.IsSpellKnown = function(spellID) return knownSpells[spellID] == true end
ns.GetAltsKnowing = function() end
ns.char.scanned[171] = true

assert(loadfile("Locales/enUS.lua"))("Test", ns)
assert(loadfile("Database.lua"))("Test", ns)
assert(loadfile("Sources.lua"))("Test", ns)
assert(loadfile("Tooltip.lua"))("Test", ns)
local L = ns.L

local alchemy = {
    [1] = { 50, "Trainer Potion", { 10, 2 }, 20, 55, 75, 95 },
    [2] = { 150, "Vendor Elixir", { 10, 1 }, 21, 160, 170, 180 },
    [3] = { 60, "Drop Draught", { 11, 1 }, 22, 90, 110, 130 },
    [4] = { 0, "Quest Tonic", { 11, 1 }, 23 },
    [5] = { 1, "Starter Brew", { 11, 1 }, 24, 10, 20, 30 },
    [6] = { 70, "Unknown Origin", { 11, 1 }, 25 },
    [7] = { 80, "Horde Trained", { 11, 1 }, 26 },
    [8] = { 90, "Uncertain Mix", { 11, 1 }, 27 },
}
for spellID = 100, 130 do
    alchemy[spellID] = { spellID, "Filler " .. spellID, { 12, 1 }, 0 }
end
ns.RegisterRecipes(171, alchemy)
ns.RegisterRecipes(185, { [200] = { 10, "Stew", { 13, 1 }, 30 } })
ns.RegisterRecipeSources({
    [1] = "t150:7:5:1",
    [2] = "i500|v900:1200:1,901:1200:0,902:800:0|r529|f45",
    [3] = "i501|dn40:2.5,o2843,w5-25,=Odd Beast:0.5,n41|n12",
    [4] = "t10:0:1:0|i502|q700,=Lost Title,701",
    [5] = "a",
    [6] = "i503",
    [7] = "t900:0:3:0",
    [8] = "i504|v|x",
})
ns.RegisterSourceNPCs({
    [900] = "Alliance Alchemist|1453|55.5|61|A|1",
    [901] = "Horde Herbalist|1454|46|45.8|H|0",
    [902] = "Neutral Trader|1434|28.2|74.5||1",
})

ns.RegisterSourceNames({
    n = { [40] = "Kobold Miner", [41] = "Rot Hide Gnoll", [900] = "Alliance Alchemist (Wowhead)" },
    o = { [2843] = "Battered Chest" },
    q = { [700] = "Wild Eyes, Wild Hearts" },
    unknownKind = { [1] = "ignored" },
})

local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function contains(text, part) return text:find(part, 1, true) ~= nil end
local function lines(spellID, maxVendors)
    local result = ns.GetSourceLines(spellID, maxVendors)
    return result and table.concat(result, "\n")
end

-- ----------------------------------------------------------------------------
-- Unpacking and kinds
-- ----------------------------------------------------------------------------
local vendorSource = ns.GetRecipeSource(2)
check(vendorSource.item == 500 and #vendorSource.vendors == 3, "vendor entry must unpack")
check(vendorSource.vendors[1].npc == 900 and vendorSource.vendors[1].price == 1200 and vendorSource.vendors[1].limited,
    "vendor fields must unpack")
check(vendorSource.faction == 529 and vendorSource.favor == 45, "reputation and favor must unpack")
check(ns.GetRecipeSource(2) == vendorSource, "unpacked source must be cached")
check(ns.GetRecipeSource(9999) == nil, "recipe without data has no source")
local trainer = ns.GetRecipeSource(4).trainer
check(trainer.cost == 10 and trainer.A == 0 and trainer.H == 1 and not trainer.seen, "trainer fields must unpack")
check(ns.GetRecipeSource(3).dropCount == 12 and ns.GetRecipeSource(8).uncertain, "drop count and uncertain flag")
local drops = ns.GetRecipeSource(3).drops
check(#drops == 5 and drops[1].kind == "n" and drops[1].id == 40 and drops[1].chance == "2.5", "drop: NPC with chance")
check(drops[2].kind == "o" and drops[2].id == 2843 and drops[2].chance == nil, "drop: object")
check(drops[3].kind == "w" and drops[4].kind == "=" and drops[4].text == "Odd Beast" and drops[4].chance == "0.5",
    "drop: world drop and English text")
local quests = ns.GetRecipeSource(4).quests
check(#quests == 3 and quests[1].id == 700 and quests[2].text == "Lost Title" and quests[3].id == 701, "quests unpack")
for spellID, kind in pairs({ "TRAINER", "VENDOR", "DROP", "QUEST", "OTHER", "OTHER", "TRAINER", "VENDOR" }) do
    check(ns.HasSourceKind(spellID, kind), "recipe " .. spellID .. " must be of kind " .. kind)
end
check(ns.HasSourceKind(4, "TRAINER") and not ns.HasSourceKind(4, "VENDOR"), "several kinds per recipe")
check(ns.HasSourceKind(9999, "OTHER") and not ns.HasSourceKind(9999, "TRAINER"), "unknown source counts as other")

-- ----------------------------------------------------------------------------
-- Texts without any client name API (fallbacks)
-- ----------------------------------------------------------------------------
check(ns.GetSourceSummary(1) == "Trainer" and ns.GetSourceSummary(2) == "Vendor", "summary of a single source")
check(ns.GetSourceSummary(4) == "Trainer, Quest", "summary of several sources")
check(ns.GetSourceSummary(5) == L["SOURCE_AUTO"] and ns.GetSourceSummary(6) == L["SOURCE_ITEM"], "summary without a place")
check(ns.GetSourceSummary(8) == "Vendor ?" and ns.GetSourceSummary(9999) == nil, "uncertain and unknown summary")
check(ns.FormatMoney(12345) == "1g 23s 45c" and ns.FormatMoney(0) == "0c", "money fallback without GetMoneyString")

local text = lines(2)
check(contains(text, "Recipe item:|r Item 500"), "recipe item must be named")
check(contains(text, "Alliance Alchemist (Wowhead) – 12s |cff888888(limited supply)|r"),
    "vendor without zone API: name from the name data, price, note")
check(contains(text, "Horde Herbalist") and contains(text, "Neutral Trader – 8s"), "all vendors without a known faction")
check(contains(text, "|cffffd100Reputation|r") and contains(text, "Merchant's Favor:|r 45"), "reputation and favor fallbacks")
check(contains(lines(1), "Trainer:|r 1s 50c"), "trainer cost")
check(contains(lines(3), "Drop:|r Kobold Miner 2.5%, Battered Chest, World drop (level 5–25 creatures), Odd Beast 0.5%, Rot Hide Gnoll"),
    "drops: names by ID, world drop, English text, chances")
check(contains(lines(3), "|cff888888(+7)|r"), "drops with the number of further sources")
check(contains(lines(4), "Quest:|r Wild Eyes, Wild Hearts, Lost Title, #701"), "quest titles by ID, English text, unknown ID")
check(contains(lines(5), L["SOURCE_AUTO"]), "automatically learned")
check(contains(lines(8), "|cffffd100Vendor|r") and contains(lines(8), L["SOURCE_UNCERTAIN"]), "vendor without details, uncertain note")
check(lines(9999) == nil, "no lines without data")

-- ----------------------------------------------------------------------------
-- With the client's APIs: faction filter, zone, money
-- ----------------------------------------------------------------------------
UnitFactionGroup = function() return "Alliance" end
FACTION_HORDE, FACTION_ALLIANCE = "Horde", "Alliance"
C_Map = { GetMapInfo = function(uiMapID) return uiMapID ~= 1434 and { name = "Zone " .. uiMapID } or nil end }
GetMoneyString = function(copper) return copper .. " copper" end
C_Reputation = { GetFactionDataByID = function(factionID) return { name = "Faction " .. factionID } end }
C_CurrencyInfo = { GetCurrencyInfo = function(currencyID) return { name = "Currency " .. currencyID } end }
-- The player's side is only known now; a fresh addon instance picks it up
local function reload()
    local fresh = setmetatable({}, { __index = ns })
    assert(loadfile("Sources.lua"))("Test", fresh)
    return fresh
end
local function register(target)
    target.RegisterRecipeSources({
        [2] = "i500|v900:1200:1,901:1200:0,902:800:0|r529|f45",
        [7] = "t900:0:3:0",
        [9] = "i505|v901:100:0",
    })
    target.RegisterSourceNPCs({
        [900] = "Alliance Alchemist|1453|55.5|61|A|1",
        [901] = "Horde Herbalist|1454|46|45.8|H|0",
        [902] = "Neutral Trader|1434|28.2|74.5||1",
    })
end
local alliance = reload()
register(alliance)
text = table.concat(alliance.GetSourceLines(2), "\n")
check(contains(text, "Alliance Alchemist – Zone 1453 (55.5, 61.0) – 1200 copper"), "vendor with zone, coordinates and price")
check(not contains(text, "Horde Herbalist"), "other faction's vendors are hidden")
check(contains(text, "Neutral Trader – 800 copper"), "unknown zone is left out")
check(contains(text, "Reputation:|r Faction 529") and contains(text, "Currency 3402:|r 45"), "client names for faction and currency")
check(contains(table.concat(alliance.GetSourceLines(2, 1), "\n"), string.format(L["SOURCE_MORE_VENDORS"], 1)), "vendor list is limited")
text = table.concat(alliance.GetSourceLines(9), "\n")
check(not contains(text, "Horde Herbalist") and not contains(text, "Zone 1454"),
    "a vendor of the other faction is never shown, even if nobody else sells the recipe")
check(contains(text, "|cffffd100Vendor|r |cff888888(Horde)|r"), "sold by the other faction only: said so, without a place")
check(contains(table.concat(alliance.GetSourceLines(7), "\n"), "|cff888888(Horde)|r"), "trainer of the other faction only")

-- Localized names override the English ones
local german = reload()
register(german)
german.RegisterSourceNames({ n = { [900] = "Allianz-Alchemist" } })
check(contains(table.concat(german.GetSourceLines(2), "\n"), "Allianz-Alchemist – Zone 1453"), "localized vendor name")

-- Map: the vendor in the current zone wins, the other faction's vendor is no destination
local name, mapID, x, y = alliance.GetSourceWaypoint(2)
check(name == "Alliance Alchemist" and mapID == 1453 and x == 55.5 and y == 61, "first usable vendor is the destination")
C_Map.GetBestMapForUnit = function() return 1434 end
name, mapID = alliance.GetSourceWaypoint(2)
check(name == "Neutral Trader" and mapID == 1434, "a vendor in the current zone is preferred")
check(alliance.GetSourceWaypoint(9) == nil and alliance.GetSourceWaypoint(7) == nil and alliance.GetSourceWaypoint(9999) == nil,
    "no destination without a usable vendor")
check(alliance.ShowSourceOnMap(9) == false, "nothing to show for the other faction's vendor")
local pin, tracked, opened, arrow
UiMapPoint = { CreateFromCoordinates = function(map, px, py) return { map, px, py } end }
C_Map.SetUserWaypoint = function(point) pin = point end
C_Map.CanSetUserWaypointOnMap = function() return true end
C_SuperTrack = { SetSuperTrackedUserWaypoint = function(value) tracked = value end }
OpenWorldMap = function(map) opened = map end
TomTom = { AddWaypoint = function(_, map, px, py, options) arrow = { map, px, py, options.title } end }
check(alliance.ShowSourceOnMap(2) == true, "vendor is shown on the map")
check(pin[1] == 1434 and math.abs(pin[2] - 0.282) < 1e-9 and math.abs(pin[3] - 0.745) < 1e-9 and tracked == true,
    "the game's map pin is set and tracked")
check(opened == 1434 and arrow[1] == 1434 and arrow[4] == "Neutral Trader", "world map opens, TomTom gets the waypoint")
pin, opened = nil, nil
C_Map.CanSetUserWaypointOnMap = function() return false end
check(alliance.ShowSourceOnMap(2) == true and pin == nil and opened == 1434, "no pin where the game doesn't allow one")
C_Map.SetUserWaypoint = function() error("blocked") end
C_Map.CanSetUserWaypointOnMap = nil
OpenWorldMap = function() error("blocked") end
check(alliance.ShowSourceOnMap(2) == true, "failing map functions don't raise errors")
UiMapPoint, C_SuperTrack, OpenWorldMap, TomTom = nil, nil, nil, nil
UnitFactionGroup, C_Map, GetMoneyString, C_Reputation, C_CurrencyInfo = nil, nil, nil, nil, nil

-- ----------------------------------------------------------------------------
-- Item tooltip
-- ----------------------------------------------------------------------------
local function tooltip(itemID)
    local result = {}
    ns.AddTooltipLines({ AddLine = function(_, line) result[#result + 1] = line end }, itemID)
    return table.concat(result, "\n")
end
check(not contains(tooltip(10), "[Trainer]"), "no source tags by default")
ns.SetOption("showRecipeSource", true)
text = tooltip(10)
check(contains(text, "Trainer Potion") and contains(text, "|cff888888[Trainer]|r"), "unlearned recipe gets its source tag")
check(contains(text, "|cff888888[Vendor]|r"), "second recipe of the reagent, too")
knownSpells[1] = true
ns.Fire("DATA_CHANGED")
check(not contains(tooltip(10), "[Trainer]"), "learned recipes get no source tag")
knownSpells[1] = nil
ns.Fire("DATA_CHANGED")
ns.SetOption("showCraftedBy", true)
text = tooltip(21)
check(contains(text, "Vendor Elixir") and contains(text, "Alliance Alchemist"), "crafted item lists where to get its recipe")
check(contains(text, string.format(L["SOURCE_MORE_VENDORS"], 1)), "crafted item limits the vendor list")
ns.SetOption("showRecipeSource", false)
check(not contains(tooltip(21), "Alliance Alchemist"), "crafted item without the option")
ns.SetOption("showCraftedBy", false)

-- ----------------------------------------------------------------------------
-- Window "Missing recipes"
-- ----------------------------------------------------------------------------
assert(loadfile("UI/Widgets.lua"))("Test", ns)
frames = {}
assert(loadfile("UI/RecipeWindow.lua"))("Test", ns)
ns.ToggleRecipeWindow()
local window, rows, slider, professionButtons, checkButtons = nil, {}, nil, {}, {}
local box
for _, frame in ipairs(frames) do
    if frame.name == "ProfessionTooltipRecipeFrame" then window = frame end
    if frame.kind == "Slider" then slider = frame end
    if frame.kind == "CheckButton" then checkButtons[#checkButtons + 1] = frame end
    if rawget(frame, "profession") then
        professionButtons[#professionButtons + 1] = frame
    elseif rawget(frame, "skill") then
        rows[#rows + 1] = frame
    end
    if frame.scripts.OnMouseWheel then box = frame end
end
check(window and window.shown, "window opens")
check(UISpecialFrames[1] == "ProfessionTooltipRecipeFrame", "ESC closes the window")
check(#professionButtons == 2, "one button per profession with recipes")
check(#rows == 17 and slider and box, "list rows and scroll bar exist")

local function visible()
    local names = {}
    for _, row in ipairs(rows) do
        if row.shown and rawget(row, "entry") then names[#names + 1] = row.entry.name end
    end
    return names
end
local function entryCount()
    local count = 0
    for _, row in ipairs(rows) do
        if row.shown then count = count + 1 end
    end
    return count
end

-- The first own profession is selected; lowest required skill first, unknown skill last
local names = visible()
check(#names == 17 and names[1] == "Starter Brew" and names[2] == "Trainer Potion", "sorted by required skill")
check(names[3] == "Drop Draught" and names[4] == "Unknown Origin", "skill order continues")
check(rows[1].source.text == L["SOURCE_AUTO"] and rows[2].source.text == "Trainer", "source column")
check(rows[4].source.text == L["SOURCE_ITEM"], "recipe item without a known origin")
check(slider.shown and slider.max == 39 - 17, "39 missing recipes scroll over 17 rows")

box.scripts.OnMouseWheel(box, -1)
check(visible()[1] == "Unknown Origin" and slider.value == 3, "mouse wheel scrolls three rows")
slider:SetValue(22)
names = visible()
check(names[17] == "Quest Tonic", "unknown skill sorts last; dragging the bar scrolls to the end")
box.scripts.OnMouseWheel(box, -1)
check(slider.value == 22, "cannot scroll past the end")
box.scripts.OnMouseWheel(box, 100)
check(slider.value == 0 and visible()[1] == "Starter Brew", "cannot scroll before the start")

-- Rank 100: "Vendor Elixir" (150) and the fillers above 100 are out of reach
ns.SetOption("recipeLearnableOnly", true)
names = visible()
check(#names == 8, "only recipes within the profession skill (and those of unknown skill): " .. #names)
for _, name in ipairs(names) do
    check(name ~= "Vendor Elixir" and name ~= "Filler 101", name .. " must be learnable")
end
ns.SetOption("recipeLearnableOnly", false)

ns.SetOption("recipeFilter", "VENDOR")
names = visible()
check(#names == 2 and names[1] == "Uncertain Mix" and names[2] == "Vendor Elixir", "vendor filter")
check(rows[1].source.text == "Vendor ?", "uncertain recipes are marked")
ns.SetOption("recipeFilter", "QUEST")
check(#visible() == 1 and visible()[1] == "Quest Tonic", "quest filter")
ns.SetOption("recipeFilter", "DROP")
check(#visible() == 1 and not slider.shown, "drop filter, no scroll bar for a short list")
ns.SetOption("recipeFilter", "OTHER")
check(#visible() == 17, "recipes without a known place are 'other'")
ns.SetOption("recipeFilter", "ALL")

-- Row tooltip
rows[2].scripts.OnEnter(rows[2])
text = table.concat(GameTooltip.lines, "\n")
check(GameTooltip.lines[1]:find("^|T.-|t Trainer Potion$") and contains(text, "Requires Alchemy (50)"), "row tooltip: icon, name and skill")
check(contains(text, "2× Item 10") and contains(text, "Trainer:|r 1s 50c"), "row tooltip: reagents and source")
-- Item preview next to it: recipe item, otherwise the crafted item, otherwise the spell
local preview
for _, frame in ipairs(frames) do
    if frame.name == "ProfessionTooltipItemPreview" then preview = frame end
end
check(preview and preview.shown and preview.item == 20, "preview shows the crafted item when there is no recipe item")
check(rows[2].icon.kind == "Texture", "rows have an icon")
rows[2].scripts.OnLeave(rows[2])
check(not preview.shown, "preview hides with the row tooltip")
check(ns.GetRecipeItem(2) == 500 and ns.GetRecipeItem(1) == nil, "recipe item from the source data")
ns.RegisterRecipeItems({ [600] = 1, [601] = 1 })
check(ns.GetRecipeItem(1) == 600, "recipe item from the client data, lowest ID first")
rows[2].scripts.OnEnter(rows[2])
check(preview.item == 600, "preview prefers the recipe item (its tooltip includes the product)")
slider:SetValue(22)
rows[17].scripts.OnEnter(rows[17])
check(not contains(table.concat(GameTooltip.lines, "\n"), "Requires"), "no skill line while the required skill is unknown")
local fillerRow
for _, row in ipairs(rows) do
    if row.entry and row.entry.spellID >= 100 then fillerRow = row end
end
fillerRow.scripts.OnEnter(fillerRow)
check(preview.spell == fillerRow.entry.spellID and rawget(preview, "item") == nil, "preview shows the spell for a recipe without any item")
slider:SetValue(0)
check(not contains(table.concat(GameTooltip.lines, "\n"), L["RECIPES_CLICK_MAP"]), "no map hint without a vendor")
local shown
OpenWorldMap = function(map) shown = map end
ns.SetOption("recipeFilter", "VENDOR")
rows[2].scripts.OnEnter(rows[2])
check(contains(table.concat(GameTooltip.lines, "\n"), L["RECIPES_CLICK_MAP"]), "map hint on a recipe with a vendor")
rows[2].scripts.OnClick(rows[2])
check(shown == 1453, "clicking a recipe opens the map on its vendor")
shown = nil
rows[1].scripts.OnClick(rows[1])
check(shown == nil, "clicking a recipe without a known vendor does nothing")
ns.SetOption("recipeFilter", "ALL")
OpenWorldMap = nil

-- Learning a recipe removes it from the list
knownSpells[5] = true
ns.Fire("DATA_CHANGED")
check(visible()[1] == "Trainer Potion", "learned recipe disappears")
knownSpells[5] = nil

-- Another profession (not learned): everything is missing, nothing is learnable
professionButtons[2].scripts.OnClick(professionButtons[2])
check(ns.char.recipeProfession == 185 and entryCount() == 1 and visible()[1] == "Stew", "profession can be switched")
ns.SetOption("recipeLearnableOnly", true)
check(entryCount() == 0, "nothing is learnable without the profession")
ns.SetOption("recipeLearnableOnly", false)
professionButtons[2].scripts.OnEnter(professionButtons[2])
check(GameTooltip.lines[1] == "Cooking" and GameTooltip.lines[2] == L["NOT_LEARNED"], "profession button tooltip")

-- Closed window: changes must not touch the list
ns.ToggleRecipeWindow()
check(not window.shown, "window closes")
ns.SetOption("recipeFilter", "TRAINER")
check(entryCount() == 1, "hidden window is not refreshed")
ns.ToggleRecipeWindow()
check(entryCount() == 0, "refreshed when shown again (Cooking has no trainer recipe)")
ns.SetOption("recipeFilter", "ALL")

-- ----------------------------------------------------------------------------
-- Shipped data: every entry must unpack, every vendor must be known
-- ----------------------------------------------------------------------------
-- The data file calls ns.RegisterRecipeSources while loading: Sources.lua must come first
local order, position = {}, 0
for line in io.lines("ProfessionTooltip.toc") do
    position = position + 1
    order[line:gsub("%s+$", "")] = position
end
check(order["Sources.lua"] and order["Data\\RecipeSources.lua"] and order["Sources.lua"] < order["Data\\RecipeSources.lua"],
    "TOC must load Sources.lua before Data\\RecipeSources.lua")
check(order["Sources.lua"] > order["Locales\\zhTW.lua"] and order["UI\\RecipeWindow.lua"] > order["UI\\Widgets.lua"],
    "TOC must load locales before Sources.lua and widgets before the recipe window")
local shipped, shippedNPCs = {}, {}
local data = {
    RegisterRecipeSources = function(list) shipped = list end,
    RegisterSourceNPCs = function(list) shippedNPCs = list end,
}
assert(loadfile("Data/RecipeSources.lua"))("Test", data)
local real = setmetatable({}, { __index = ns })
assert(loadfile("Sources.lua"))("Test", real)
real.RegisterRecipeSources(shipped)
real.RegisterSourceNPCs(shippedNPCs)
-- Names: every language file loads for its locale only and registers real names
local nameCounts = {}
for _, locale in ipairs({ "enUS", "deDE", "frFR", "esES", "ruRU", "ptBR", "koKR", "zhCN", "zhTW" }) do
    check(order["Data\\Names\\" .. locale .. ".lua"] and order["Data\\Names\\" .. locale .. ".lua"] > order["Sources.lua"],
        "TOC must load Data\\Names\\" .. locale .. ".lua after Sources.lua")
    local chunk = assert(loadfile("Data/Names/" .. locale .. ".lua"))
    local count = 0
    local target = { RegisterSourceNames = function(list)
        for _, entries in pairs(list) do
            for _ in pairs(entries) do count = count + 1 end
        end
        if locale == "enUS" or locale == "deDE" then real.RegisterSourceNames(list) end
    end }
    GetLocale = function() return locale == "enUS" and "frFR" or "enUS" end
    chunk("Test", target)
    check(count > 0 == (locale == "enUS"), locale .. ": names must only load for their own locale")
    GetLocale = function() return locale end
    count = 0
    chunk("Test", target)
    nameCounts[locale] = count
    check(count > 500, locale .. ": too few names (" .. count .. ")")
end
GetLocale = function() return "enUS" end
local total, vendors = 0, 0
for spellID, packed in pairs(shipped) do
    total = total + 1
    assert(not packed:find("||", 1, true) and packed ~= "", "empty field in recipe " .. spellID)
    local source = real.GetRecipeSource(spellID)
    assert(next(source.kinds), "recipe " .. spellID .. " has no kind")
    for _, vendor in ipairs(source.vendors or {}) do
        vendors = vendors + 1
        assert(real.GetSourceNPC(vendor.npc), "recipe " .. spellID .. ": unknown vendor " .. vendor.npc)
    end
    local text = table.concat(real.GetSourceLines(spellID), "\n")
    assert(real.GetSourceSummary(spellID) and text ~= "", "recipe " .. spellID .. " has no text")
    assert(not text:find("#%d"), "recipe " .. spellID .. ": an ID without a name: " .. text)
    for _, drop in ipairs(source.drops or {}) do
        assert(drop.kind == "w" or drop.kind == "=" or (drop.id and drop.id > 0), "recipe " .. spellID .. ": broken drop")
    end
end
check(total > 2000 and vendors > 500, "shipped data is complete: " .. total .. " recipes, " .. vendors .. " vendor entries")
for npcID in pairs(shippedNPCs) do
    local name, _, x, y = real.GetSourceNPC(npcID)
    assert(name and name ~= "" and x and y, "vendor " .. npcID .. " must unpack")
end

print("Recipe source tests passed (" .. checks .. " checks, " .. total .. " shipped recipe sources)")
