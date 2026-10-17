-- Legacy.lua
-- Übergang von CookingTooltip/AlchemyTooltip: Einstellungen übernehmen, alte Addons deaktivieren.
local _, ns = ...
local L = ns.L

-- Addon-Name -> globale Einstellungstabelle
local LEGACY_ADDONS = {
    { name = "CookingTooltip", settings = "CookingTooltipSettings" },
    { name = "AlchemyTooltip", settings = "AlchemyTooltipSettings" },
}

-- Alte Einstellung -> neue Einstellung
local SETTING_MAP = {
    detailed = "detailed",
    showSkillUnknown = "showSkill",
    showSkillKnown = "showSkillKnown",
    unknownOnlyOnShift = "unknownOnlyOnShift",
    hideTrivialKnownOnShift = "hideTrivialKnownOnShift",
}

-- Namen der alten Addons, die gerade geladen sind
function ns.GetLoadedLegacyAddons()
    local loaded = {}
    for _, legacy in ipairs(LEGACY_ADDONS) do
        if C_AddOns.IsAddOnLoaded(legacy.name) then
            loaded[#loaded + 1] = legacy.name
        end
    end
    return loaded
end

-- Übernimmt die Einstellungen des ersten geladenen alten Addons. Rückgabe: true bei Erfolg
function ns.ImportLegacySettings()
    for _, legacy in ipairs(LEGACY_ADDONS) do
        local old = _G[legacy.settings]
        if C_AddOns.IsAddOnLoaded(legacy.name) and type(old) == "table" then
            for oldKey, newKey in pairs(SETTING_MAP) do
                if old[oldKey] ~= nil then
                    ns.db[newKey] = old[oldKey] and true or false
                end
            end
            ns.Fire("SETTINGS_CHANGED")
            return true
        end
    end
    return false
end

function ns.DisableLegacyAddons()
    for _, name in ipairs(ns.GetLoadedLegacyAddons()) do
        C_AddOns.DisableAddOn(name)
    end
    ReloadUI()
end

StaticPopupDialogs["PROFESSIONTOOLTIP_LEGACY"] = {
    text = L["LEGACY_FOUND"],
    button1 = L["LEGACY_IMPORT_AND_DISABLE"],
    button2 = L["LEGACY_LATER"],
    OnAccept = function()
        ns.ImportLegacySettings()
        ns.DisableLegacyAddons()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

ns.RegisterEvent("PLAYER_LOGIN", function()
    if not ns.db.legacyCheck then return end
    local loaded = ns.GetLoadedLegacyAddons()
    if #loaded > 0 then
        StaticPopup_Show("PROFESSIONTOOLTIP_LEGACY", table.concat(loaded, ", "))
    end
end)
