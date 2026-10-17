-- UI/SettingsPanel.lua
-- Entry under Options -> AddOns. Points to the actual settings window.
local _, ns = ...
local L = ns.L

local function CreatePanel()
    local panel = CreateFrame("Frame")

    local icon = panel:CreateTexture(nil, "ARTWORK")
    icon:SetSize(32, 32)
    icon:SetPoint("TOPLEFT", 16, -16)
    icon:SetTexture(ns.ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -1)
    title:SetText("Profession Tooltip")

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    subtitle:SetText(L["SUBTITLE"])

    local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    open:SetSize(220, 26)
    open:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -20)
    open:SetText(L["OPEN_SETTINGS"])
    open:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel:IsShown() then
            SettingsPanel:Close(true)
        end
        ns.OpenConfigWindow()
    end)

    local slashHint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    slashHint:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -10)
    slashHint:SetText(L["SLASH_HINT"])

    local category = Settings.RegisterCanvasLayoutCategory(panel, "Profession Tooltip")
    Settings.RegisterAddOnCategory(category)
end

ns.RegisterEvent("PLAYER_LOGIN", CreatePanel)
