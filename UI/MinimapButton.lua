-- UI/MinimapButton.lua
-- One broker launcher, displayed on the minimap by the bundled LibDBIcon.
local _, ns = ...
local L = ns.L
local NAME = "ProfessionTooltip"
local broker = LibStub("LibDataBroker-1.1")
local icon = LibStub("LibDBIcon-1.0")

local function Update()
    local db = ns.db.minimap
    -- Migrate once: LibDBIcon writes minimapPos directly when the icon is dragged.
    -- Keep show as the public setting used by our configuration window.
    if db.minimapPos == nil then
        db.minimapPos = db.angle or 200
    end
    db.hide = not db.show

    local launcher = broker:GetDataObjectByName(NAME) or broker:NewDataObject(NAME, {
        type = "launcher",
        text = "Profession Tooltip",
        icon = ns.ICON,
        OnClick = function(_, button)
            if button == "RightButton" then
                ns.ToggleRecipeWindow()
            else
                ns.ToggleConfigWindow()
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("Profession Tooltip", 1, 1, 1)
            tooltip:AddLine(L["MINIMAP_TOOLTIP"], 0.9, 0.9, 0.9)
            tooltip:AddLine(L["MINIMAP_TOOLTIP_RIGHT"], 0.9, 0.9, 0.9)
        end,
    })

    if not icon:IsRegistered(NAME) then
        icon:Register(NAME, launcher, db)
    else
        icon:Refresh(NAME, db)
    end
end

-- Keep the existing TOC entry; do not also register a LibDBIcon compartment entry.
function ProfessionTooltip_OnAddonCompartmentClick()
    ns.ToggleConfigWindow()
end

ns.RegisterEvent("PLAYER_LOGIN", Update)
ns.On("SETTINGS_CHANGED", function(_, key)
    if key == "minimap" then Update() end
end)
