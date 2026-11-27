-- Crafting cost tooltip, vendor reagent prices, multi-output yields, and "NEW" option badges.
-- Run from the repository root: luajit Tools/test_craft_cost.lua
wipe = function(t) for key in pairs(t) do t[key] = nil end end
tinsert = table.insert
Enum = { TooltipDataType = { Item = 0 } }
local postCall
TooltipDataProcessor = { AddTooltipPostCall = function(_, callback) postCall = callback end }
IsShiftKeyDown = function() return false end
local now = 100
GetTime = function() return now end
GetLocale = function() return "enUS" end
GetMoneyString = function(copper) return copper .. "c" end
C_Item = {
    GetItemNameByID = function(itemID) return "Item " .. itemID end,
    GetItemIconByID = function() return 133784 end,
    GetItemInfoInstant = function() return nil end,
    RequestLoadItemDataByID = function() end,
}
C_Spell = { GetSpellName = function(spellID) return "Spell " .. spellID end }
C_Timer = { After = function(_, callback) callback() end }
UISpecialFrames = {}
StaticPopupDialogs = {}
SlashCmdList = {}

local methods = {}
local function widget(kind, name)
    return setmetatable({ kind = kind, name = name, scripts = {}, shown = true, enabled = true, lines = {}, value = 0 }, {
        __index = function(_, method) return methods[method] or function() end end,
    })
end
function methods:SetScript(name, callback) self.scripts[name] = callback end
function methods:SetText(text) self.text = text end
function methods:GetText() return self.text end
function methods:SetShown(shown)
    local wasShown = self.shown
    self.shown = shown and true or false
    if self.shown and not wasShown and self.scripts.OnShow then self.scripts.OnShow(self) end
    if not self.shown and wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:Show() self:SetShown(true) end
function methods:Hide() self:SetShown(false) end
function methods:IsShown() return self.shown end
function methods:SetChecked(checked) self.checked = checked and true or false end
function methods:GetChecked() return self.checked end
function methods:SetEnabled(enabled) self.enabled = enabled and true or false end
function methods:IsEnabled() return self.enabled end
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:SetWidth(w) self.width = w end
function methods:GetWidth() return rawget(self, "width") or 80 end
function methods:GetStringWidth()
    local t = rawget(self, "text")
    return (t and #t * 6) or 40
end
function methods:GetStringHeight() return 12 end
function methods:SetMinMaxValues(low, high) self.min, self.max = low, high end
function methods:SetValue(value)
    self.value = value
    if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
end
function methods:GetValue() return self.value end
function methods:CreateFontString() return widget("FontString") end
function methods:CreateTexture() return widget("Texture") end
function methods:GetHighlightTexture() return widget("Texture") end
function methods:GetThumbTexture() return widget("Texture") end
function methods:AddLine(text) self.lines[#self.lines + 1] = text end
function methods:SetOwner() self.lines = {} end
function methods:SetItemByID(itemID) self.item = itemID end

local frames = {}
CreateFrame = function(kind, name)
    local frame = widget(kind, name)
    frames[#frames + 1] = frame
    return frame
end
UIParent = widget("Frame")
GameTooltip, ItemRefTooltip = widget("GameTooltip"), widget("GameTooltip")

local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function contains(text, part) return text:find(part, 1, true) ~= nil end

local function fireEvent(event, ...)
    for _, frame in ipairs(frames) do
        if frame.scripts.OnEvent then
            frame.scripts.OnEvent(frame, event, ...)
        end
    end
end

-- 1. Fresh install: all NEW_OPTIONS start marked as seen
ProfessionTooltipDB = nil
ProfessionTooltipCharDB = nil
local freshNs = {}
assert(loadfile("Core.lua"))("Test", freshNs)
fireEvent("ADDON_LOADED", "Test")
check(freshNs.db.showCraftCost == false, "showCraftCost defaults to false")
check(freshNs.IsOptionNew("showCraftCost") == false, "fresh install does not show NEW badge")

-- 2. Existing user upgrade: showCraftCost is new, stale keys are pruned
frames = {}
ProfessionTooltipDB = { detailed = true, seenNewOptions = { oldGoneOption = true } }
ProfessionTooltipCharDB = nil
local ns = {}
assert(loadfile("Core.lua"))("Test", ns)
fireEvent("ADDON_LOADED", "Test")
check(ns.db.showCraftCost == false, "showCraftCost defaults to false on upgrade")
check(ns.IsOptionNew("showCraftCost") == true, "existing user sees NEW badge for showCraftCost")
check(ns.db.seenNewOptions.oldGoneOption == nil, "stale seenNewOptions keys are pruned")

-- Stub Professions minimally and load Database, real Data files, Tooltip
ns.Professions = {
    { id = 171, key = "ALCHEMY", icon = "icon_alc", previewItem = 2447, order = 1 },
    { id = 164, key = "BLACKSMITHING", icon = "icon_bs", previewItem = 2840, order = 2 },
}
local profById = { [171] = ns.Professions[1], [164] = ns.Professions[2] }
ns.GetProfession = function(id) return profById[id] end
ns.GetProfessionName = function(id) return profById[id].key end
ns.HasProfession = function() return false end
ns.GetProfessionRank = function() return nil end
ns.IsProfessionShown = function() return false end
ns.GetUnscannedProfessionNames = function() return {} end
ns.GetCharacters = function() return {} end
ns.GetDatabaseStats = function() return 0, 0 end
ns.GetTrainerSkillCount = function() return 0 end
ns.GetLoadedLegacyAddons = function() return {} end
ns.ToggleRecipeWindow = function() end
ns.ImportLegacySettings = function() end
ns.DisableLegacyAddons = function() end

assert(loadfile("Locales/enUS.lua"))("Test", ns)
assert(loadfile("Database.lua"))("Test", ns)
assert(loadfile("Data/CreatedCounts.lua"))("Test", ns)
assert(loadfile("Data/VendorPrices.lua"))("Test", ns)
assert(loadfile("Tooltip.lua"))("Test", ns)

local L = ns.L

-- Sanity checks on generated data files
check(ns.GetCreatedCount(2659) == 2, "Smelt Bronze creates 2")
check(ns.GetCreatedCount(3920) == 200, "Crafted Light Shot creates 200")
check(ns.GetCreatedCount(9999999) == 1, "unknown spell defaults to yield 1")
check(ns.GetVendorPrice(3371) == 4, "Empty Vial vendor price is 4c")
check(ns.GetVendorPrice(2678) == 2, "Mild Spices vendor price is 2c")
check(ns.GetVendorPrice(13468) == nil, "Black Lotus is not a general vendor reagent")
check(ns.GetVendorPrice(2447) == nil, "Peacebloom is not a general vendor reagent")

-- Register synthetic test recipes
ns.RegisterRecipes(171, {
    [90001] = { 1, "Test Potion", { 9001, 2, 3371, 1 }, 9101 },          -- 2x 9001 + 1x Empty Vial (4c)
    [90002] = { 1, "Batch Vial", { 9001, 1 }, 9102 },                     -- yield 2 -> half cost
    [90003] = { 1, "Cheap Ammo", { 2678, 1 }, 9103 },                     -- 2c / 200 -> 0c unit, shows batch cost
    [90004] = { 1, "Partial Elixir", { 9001, 1, 9002, 1 }, 9104 },        -- 9002 missing price
    [90005] = { 1, "Unknown Cost", { 9002, 1, 9003, 1 }, 9105 },          -- 0 reagents priced
    [90006] = { 1, "Alt Recipe Expensive", { 9001, 5 }, 9106 },           -- 500c complete
    [90007] = { 1, "Alt Recipe Cheap", { 9001, 2 }, 9106 },               -- 200c complete
    [90008] = { 1, "Alt Recipe Partial", { 9001, 1, 9002, 1 }, 9106 },    -- 100c partial (must lose to complete)
})
ns.RegisterRecipes(164, {
    [90009] = { 1, "Disabled Prof Cheap", { 9001, 1 }, 9106 },            -- disabled profession -> ignored
})
ns.RegisterCreatedCounts({
    [90002] = 2,
    [90003] = 200,
})

local ahPrices = { [9001] = 100 }
local function tooltipText(itemID)
    GameTooltip.lines = {}
    postCall(GameTooltip, { id = itemID })
    return table.concat(GameTooltip.lines, "\n")
end

-- Without Auctionator, showCraftCost does nothing
ns.SetOption("showCraftCost", true)
check(tooltipText(9101) == "", "no craft cost when Auctionator is missing")

-- Enable Auctionator mock
Auctionator = {
    API = {
        v1 = {
            GetAuctionPriceByItemID = function(_, itemID) return ahPrices[itemID] end,
        },
    },
}
ns.SetOption("showCraftCost", false)
check(tooltipText(9101) == "", "no craft cost when option is disabled")

local expectedPrefix = " \n|cff888888" .. L["CRAFT_COST"] .. "|r "
ns.SetOption("showCraftCost", true)
check(tooltipText(9101) == expectedPrefix .. "204c", "uses AH + vendor fallback (2*100 + 4): " .. tooltipText(9101))

-- min(ah, vendor): inflated AH price on Empty Vial still uses 4c vendor price
ahPrices[3371] = 500
now = now + 4
check(tooltipText(9101) == expectedPrefix .. "204c", "uses min(ah, vendor) when AH is higher")

-- cheaper AH price on Empty Vial beats vendor price
ahPrices[3371] = 2
now = now + 4
check(tooltipText(9101) == expectedPrefix .. "202c", "uses AH when cheaper than vendor")
ahPrices[3371] = nil

-- Multi-output yield (100c / 2 = 50c)
check(tooltipText(9102) == expectedPrefix .. "50c", "divides cost by createdCount: " .. tooltipText(9102))

-- Batch fallback when unitCost < 1c (2c / 200 -> 2c (×200))
local ammoText = tooltipText(9103)
check(contains(ammoText, expectedPrefix .. "2c") and contains(ammoText, "(×200)"),
    "sub-1c unit cost shows batch cost: " .. ammoText)

-- Partial missing price
local partialText = tooltipText(9104)
check(contains(partialText, expectedPrefix .. "~100c") and contains(partialText, "(+1 without price)"),
    "partial price marks missing count: " .. partialText)

-- No priced reagents -> no line
check(tooltipText(9105) == "", "omits craft cost when no reagent has a price")

-- Multiple recipes creating 9106: disabled BS ignored, complete 200c beats partial 100c and complete 500c
ns.db.disabledProfessions[164] = true
now = now + 4
check(tooltipText(9106) == expectedPrefix .. "200c", "prefers complete & cheapest active recipe: " .. tooltipText(9106))

-- Integrated with showCraftedBy (no duplicate standalone section)
ns.SetOption("showCraftedBy", true)
local craftedText = tooltipText(9101)
check(contains(craftedText, L["CRAFTED_BY"]) and contains(craftedText, "\n   |cff888888" .. L["CRAFT_COST"] .. "|r 204c"),
    "integrated into Crafted with section: " .. craftedText)
local _, costOccurrences = craftedText:gsub(L["CRAFT_COST"], "")
check(costOccurrences == 1, "no duplicate crafting cost line when showCraftedBy is enabled")

-- Volatile cache expires after > 3s
ahPrices[9001] = 150
check(tooltipText(9101) == craftedText, "cached within volatile window")
now = now + 4
check(contains(tooltipText(9101), "304c"), "refreshes after volatile cache expires")

-- 3. UI NEW badge + tab dots + dismissal on tab switch and window hide
assert(loadfile("UI/Widgets.lua"))("Test", ns)
assert(loadfile("UI/ConfigWindow.lua"))("Test", ns)

ns.db.lastTab = 1
ns.OpenConfigWindow()
local configFrame
for _, f in ipairs(frames) do
    if f.name == "ProfessionTooltipConfigFrame" then configFrame = f end
end
check(configFrame ~= nil and configFrame:IsShown(), "config window opens")

-- Find tab buttons (they have newDot and underline textures)
local tabButtons = {}
for _, f in ipairs(frames) do
    if rawget(f, "newDot") and rawget(f, "underline") then
        tabButtons[#tabButtons + 1] = f
    end
end
check(#tabButtons == 5, "all 5 tab buttons created")
check(not tabButtons[1].newDot:IsShown() and tabButtons[4].newDot:IsShown(), "only Extras tab shows NEW dot")

-- Find the NEW badge frame
local newBadges = {}
for _, f in ipairs(frames) do
    local ft = rawget(f, "text")
    if type(ft) == "table" and rawget(ft, "text") == L["NEW_BADGE"] then
        newBadges[#newBadges + 1] = f
    end
end
check(#newBadges == 1 and newBadges[1]:IsShown(), "one NEW badge created and visible while unseen")

-- Switch to Extras (tab 4), then switch back to Tab 1 -> marks Extras seen
tabButtons[4].scripts.OnClick(tabButtons[4])
check(ns.IsOptionNew("showCraftCost") == true, "still marked new while viewing Extras tab")
tabButtons[1].scripts.OnClick(tabButtons[1])
check(ns.IsOptionNew("showCraftCost") == false, "marked seen after leaving Extras tab")
check(not tabButtons[4].newDot:IsShown() and not newBadges[1]:IsShown(), "tab dot and badge hidden after leaving Extras")

-- Also verify hiding while Extras is active marks it seen
ns.db.seenNewOptions = {}
tabButtons[4].scripts.OnClick(tabButtons[4])
configFrame:Hide()
check(ns.IsOptionNew("showCraftCost") == false, "marked seen when window hides while tab is active")

print(string.format("Crafting cost & badge tests passed (%d checks)", checks))
