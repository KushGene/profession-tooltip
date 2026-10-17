-- Core.lua
-- Namespace, event bus, internal messages, SavedVariables and small helpers.
local addonName, ns = ...

ns.name = addonName
ns.version = (C_AddOns and C_AddOns.GetAddOnMetadata(addonName, "Version")) or ""
if ns.version:find("@", 1, true) then
    ns.version = "dev" -- loaded straight from the repository (the packager hasn't filled in the version yet)
else
    ns.version = ns.version:gsub("^v", "") -- the packager fills in the tag, e.g. "v1.0.0"
end
ns.ICON = "Interface\\Icons\\INV_Scroll_03"

-- ----------------------------------------------------------------------------
-- Event bus (WoW events) and internal messages
-- ----------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local eventHandlers = {}

function ns.RegisterEvent(event, handler)
    local list = eventHandlers[event]
    if not list then
        list = {}
        eventHandlers[event] = list
        -- pcall: unknown events throw an error on the retail engine
        pcall(eventFrame.RegisterEvent, eventFrame, event)
    end
    list[#list + 1] = handler
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = eventHandlers[event]
    for i = 1, #list do
        list[i](event, ...)
    end
end)

local messageHandlers = {}

-- Internal messages:
--   SETTINGS_CHANGED     a setting was changed
--   DATA_CHANGED         scanned recipes or profession ranks have changed
function ns.On(message, handler)
    local list = messageHandlers[message]
    if not list then
        list = {}
        messageHandlers[message] = list
    end
    list[#list + 1] = handler
end

function ns.Fire(message, ...)
    local list = messageHandlers[message]
    if not list then return end
    for i = 1, #list do
        list[i](message, ...)
    end
end

-- ----------------------------------------------------------------------------
-- Settings
-- ----------------------------------------------------------------------------
-- Account-wide (ProfessionTooltipDB): display settings
-- Per character (ProfessionTooltipCharDB): learned recipes and profession ranks
-- Defaults for a fresh install: only the core feature is enabled, all extras are off.
local DEFAULTS = {
    -- Tab "Tooltip": recipe list
    detailed = true,
    showSkill = true,
    showSkillKnown = false,
    showReagentCount = true,
    groupByKnown = false,          -- separate "Learned" / "Not learned" sections
    maxLinesPerProfession = 10,    -- 0 = unlimited
    unknownFilter = "all",         -- "all", "learnable" (enough skill), "noGray" (hide recipes that are gray for me)
    unknownOnlyOnShift = false,
    hideTrivialKnownOnShift = true,
    -- Tab "Design"
    headerStyle = "full",          -- "full" (icon + name), "icon", "name"
    showProfessionRank = false,    -- own profession rank in the header, e.g. 70/150
    showKnownCount = true,         -- "16/82 learned" in the header
    spacing = true,                -- blank lines between professions
    showHints = true,              -- hint lines (Shift, open profession window)
    -- Tab "Professions"
    onlyOwnProfessions = true,
    showOtherProfessionIcons = true,
    disabledProfessions = {},      -- [skillLineID] = true
    -- Tab "Extras"
    showAltKnown = false,          -- "Known by: <alt>"
    showRecipeItemInfo = false,    -- recipe items: learned / learnable / skill too low
    showCraftedBy = false,         -- crafted items: show the recipe
    showCraftedReagents = true,    --   ... including reagents (sub-option)
    showStockCount = false,        -- "enough for N" from bags + bank
    showRecipeValue = false,       -- auction value of the product (Auctionator)
    -- Tab "General"
    minimap = { show = true, angle = 200 },
    legacyCheck = true,            -- point out CookingTooltip/AlchemyTooltip on login
    characters = {},               -- account-wide: ["Name-Realm"] = { class, professions, known }
    trainerSkills = {},            -- account-wide, from the trainer scan: [spellID] = required rank
}

local CHAR_DEFAULTS = {
    known = {},       -- [spellID] = difficulty (0 orange, 1 yellow, 2 green, 3 gray)
    extra = {},       -- [spellID] = { profession, name, { itemID, count, ... } } for recipes without a DB entry
    professions = {}, -- [skillLineID] = { rank = n, max = n }
    scanned = {},     -- [skillLineID] = true once the profession window has been scanned
}

local function ApplyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if target[key] == nil then
            if type(value) == "table" then
                target[key] = ApplyDefaults({}, value)
            else
                target[key] = value
            end
        elseif type(value) == "table" and type(target[key]) == "table" then
            ApplyDefaults(target[key], value)
        end
    end
    return target
end

function ns.SetOption(key, value)
    ns.db[key] = value
    ns.Fire("SETTINGS_CHANGED", key)
end

function ns.ResetCharacterData()
    wipe(ns.char.known)
    wipe(ns.char.extra)
    wipe(ns.char.scanned)
    ns.Fire("DATA_CHANGED")
end

ns.RegisterEvent("ADDON_LOADED", function(_, loadedName)
    if loadedName ~= addonName then return end
    ProfessionTooltipDB = ApplyDefaults(type(ProfessionTooltipDB) == "table" and ProfessionTooltipDB or {}, DEFAULTS)
    ProfessionTooltipCharDB = ApplyDefaults(type(ProfessionTooltipCharDB) == "table" and ProfessionTooltipCharDB or {}, CHAR_DEFAULTS)
    ns.db = ProfessionTooltipDB
    ns.char = ProfessionTooltipCharDB
end)

-- ----------------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------------
-- Spell names never change -> resolve once and remember
local spellNameCache = {}

function ns.GetSpellName(spellID)
    local name = spellNameCache[spellID]
    if name == nil then
        name = C_Spell.GetSpellName(spellID)
        if name then
            spellNameCache[spellID] = name
        end
    end
    return name
end
