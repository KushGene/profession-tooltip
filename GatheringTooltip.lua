-- Add required ranks to red gathering labels without clicking a world object.
local _, ns = ...

local function Public(value)
    return not (issecretvalue and issecretvalue(value))
end

local function Plain(text)
    if not Public(text) or type(text) ~= "string" then return nil end
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function IsRed(line)
    local r, g, b = line:GetTextColor()
    return Public(r) and Public(g) and Public(b)
        and r and g and b and r > 0.8 and g < 0.3 and b < 0.3
end

local function IsProfessionLabel(text, profession)
    local name = ns.GetProfessionName(profession)
    return text == name or (LOCKED_WITH_SPELL and text == string.format(LOCKED_WITH_SPELL, name))
end

-- Classic skinning: levels 1–10 require 1, 11–20 require (level−10)*10,
-- then level*5. Unknown/boss levels must not be treated as level 1.
function ns.GetSkinningRequirement(level)
    if not Public(level) or type(level) ~= "number" or level < 1 then return nil end
    if level <= 10 then return 1 end
    if level <= 20 then return (level - 10) * 10 end
    return level * 5
end

function ns.EnhanceGatheringTooltip(tooltip, data)
    if tooltip ~= GameTooltip or not ns.db then return false end
    data = data or (tooltip.GetTooltipData and tooltip:GetTooltipData())
    local kind = data and data.type
    if not Public(kind) then return false end
    if kind ~= nil and kind ~= Enum.TooltipDataType.Object and kind ~= Enum.TooltipDataType.Unit then
        return false
    end

    local title = _G[tooltip:GetName() .. "TextLeft1"]
    local name = title and Plain(title:GetText())
    local id = data and data.id
    local node = (Public(id) and ns.GatheringNodes[id]) or ns.GatheringNodes[name]
    local _, unit = tooltip:GetUnit()
    if not Public(unit) then return false end
    local changed = false
    for i = 2, tooltip:NumLines() do
        local line = _G[tooltip:GetName() .. "TextLeft" .. i]
        local text = line and Plain(line:GetText())
        if text and IsRed(line) then
            local profession, required
            if unit and text == SKINNABLE then
                profession = 393
                required = ns.GetSkinningRequirement(UnitLevel(unit))
            elseif not unit and node and IsProfessionLabel(text, node.profession) then
                profession, required = node.profession, node.skill
            end
            if required and not ns.db.disabledProfessions[profession] then
                -- Preserve Blizzard's color and wording. Exact label matching also
                -- makes repeated calls idempotent after the number was appended.
                line:SetText(text .. " (" .. required .. ")")
                changed = true
            end
        end
    end
    return changed
end

local function Update(tooltip, data)
    if ns.EnhanceGatheringTooltip(tooltip, data) then tooltip:Show() end
end

for _, kind in ipairs({ Enum.TooltipDataType.Object, Enum.TooltipDataType.Unit }) do
    TooltipDataProcessor.AddTooltipPostCall(kind, Update)
end

-- World cursor tooltips can be redrawn while already shown (e.g. after looting
-- a corpse). Recheck the rendered lines, not a cache keyed only by object name.
local elapsedSinceUpdate = 0
GameTooltip:HookScript("OnUpdate", function(tooltip, elapsed)
    elapsedSinceUpdate = elapsedSinceUpdate + elapsed
    if elapsedSinceUpdate < 0.1 then return end
    elapsedSinceUpdate = 0
    Update(tooltip)
end)
