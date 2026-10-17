-- Core.lua
-- Namespace, Event-Bus, interne Nachrichten, SavedVariables und kleine Hilfsfunktionen.
local addonName, ns = ...

ns.name = addonName
ns.version = (C_AddOns and C_AddOns.GetAddOnMetadata(addonName, "Version")) or ""
if ns.version:find("@", 1, true) then
    ns.version = "dev" -- direkt aus dem Repository geladen (Packager hat die Version noch nicht eingesetzt)
end
ns.ICON = "Interface\\Icons\\INV_Scroll_03"

-- ----------------------------------------------------------------------------
-- Event-Bus (WoW-Events) und interne Nachrichten
-- ----------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local eventHandlers = {}

function ns.RegisterEvent(event, handler)
    local list = eventHandlers[event]
    if not list then
        list = {}
        eventHandlers[event] = list
        -- pcall: unbekannte Events werfen auf der Retail-Engine einen Fehler
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

-- Interne Nachrichten:
--   SETTINGS_CHANGED     eine Einstellung wurde geändert
--   DATA_CHANGED         gescannte Rezepte oder Berufsstufen haben sich geändert
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
-- Einstellungen
-- ----------------------------------------------------------------------------
-- Accountweit (ProfessionTooltipDB): Darstellungseinstellungen
-- Pro Charakter (ProfessionTooltipCharDB): gelernte Rezepte und Berufsstufen
-- Standardwerte für die Erstinstallation: nur die Kernfunktion ist aktiv, alle Extras sind aus.
local DEFAULTS = {
    -- Tab "Tooltip": Rezeptliste
    detailed = true,
    showSkill = true,
    showSkillKnown = false,
    showReagentCount = true,
    groupByKnown = false,          -- getrennte Abschnitte "Gelernt" / "Nicht gelernt"
    maxLinesPerProfession = 10,    -- 0 = unbegrenzt
    unknownFilter = "all",         -- "all", "learnable" (Skill reicht), "noGray" (für mich graue ausblenden)
    unknownOnlyOnShift = false,
    hideTrivialKnownOnShift = true,
    -- Tab "Design"
    headerStyle = "full",          -- "full" (Icon + Name), "icon", "name"
    showProfessionRank = false,    -- eigene Berufsstufe im Header, z. B. 70/150
    showKnownCount = true,         -- "16/82 gelernt" im Header
    spacing = true,                -- Leerzeilen zwischen Berufen
    showHints = true,              -- Hinweiszeilen (Shift, Berufsfenster öffnen)
    -- Tab "Berufe"
    onlyOwnProfessions = true,
    showOtherProfessionIcons = true,
    disabledProfessions = {},      -- [skillLineID] = true
    -- Tab "Extras"
    showAltKnown = false,          -- "Bekannt bei: <Twink>"
    showRecipeItemInfo = false,    -- Rezept-Items: gelernt / lernbar / Skill zu niedrig
    showCraftedBy = false,         -- hergestellte Items: Rezept anzeigen
    showCraftedReagents = true,    --   ... samt Zutaten (Unteroption)
    showStockCount = false,        -- "reicht für N" aus Taschen + Bank
    showRecipeValue = false,       -- Auktionswert des Endprodukts (Auctionator)
    -- Tab "Allgemein"
    minimap = { show = true, angle = 200 },
    legacyCheck = true,            -- beim Login auf CookingTooltip/AlchemyTooltip hinweisen
    characters = {},               -- accountweit: ["Name-Realm"] = { class, professions, known }
}

local CHAR_DEFAULTS = {
    known = {},       -- [spellID] = Schwierigkeit (0 orange, 1 gelb, 2 grün, 3 grau)
    extra = {},       -- [spellID] = { profession, name, { itemID, count, ... } } für Rezepte ohne DB-Eintrag
    professions = {}, -- [skillLineID] = { rank = n, max = n }
    scanned = {},     -- [skillLineID] = true, sobald das Berufsfenster einmal gescannt wurde
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
-- Hilfsfunktionen
-- ----------------------------------------------------------------------------
-- Spellnamen ändern sich nie -> einmal auflösen und merken
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
