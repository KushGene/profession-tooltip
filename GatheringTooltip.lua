-- Filter native red profession requirements and enhance gathering labels with ranks.
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

local function HideRequirement(profession)
    return not ns.db.showUnownedRequirements and not ns.HasProfession(profession)
end

local function EscapePattern(text)
    return (text:gsub("(%W)", "%%%1"))
end

-- Match the client's localized format, not arbitrary mentions of a profession.
-- Both ordinary and positional printf placeholders are used by client locales.
local function MatchesRequirement(text, format, name)
    if type(format) ~= "string" then return false end
    local parts, start = { "^" }, 1
    for first, token, after in format:gmatch("()(%%[%d%$]*[sd])()") do
        parts[#parts + 1] = EscapePattern(format:sub(start, first - 1))
        parts[#parts + 1] = token:sub(-1) == "s" and EscapePattern(name) or "%d+"
        start = after
    end
    parts[#parts + 1] = EscapePattern(format:sub(start)) .. "$"
    return text:match(table.concat(parts)) ~= nil
end

function ns.FilterProfessionRequirements(tooltip, data)
    if tooltip ~= GameTooltip or not ns.db or ns.db.showUnownedRequirements then return false end
    data = data or (tooltip.GetTooltipData and tooltip:GetTooltipData())
    local kind = data and data.type
    if not Public(kind) or (kind ~= Enum.TooltipDataType.Item
        and kind ~= Enum.TooltipDataType.Object and kind ~= Enum.TooltipDataType.Unit) then
        return false
    end
    local changed = false
    for i = 2, tooltip:NumLines() do
        local line = _G[tooltip:GetName() .. "TextLeft" .. i]
        local text = line and Plain(line:GetText())
        if text and text ~= "" and IsRed(line) then
            for _, profession in ipairs(ns.Professions) do
                if HideRequirement(profession.id) then
                    local name = ns.GetProfessionName(profession.id)
                    if MatchesRequirement(text, ITEM_REQ_SKILL, name)
                        or (profession.id == 333 and MatchesRequirement(text, ITEM_DISENCHANT_MIN_SKILL, name)) then
                        line:SetText(nil)
                        changed = true
                        break
                    end
                end
            end
        end
    end
    return changed
end

-- "Skinnable" on a creature tooltip. The client's global is UNIT_SKINNABLE_LEATHER;
-- there is no SKINNABLE global.
local SKINNABLE_LABEL = UNIT_SKINNABLE_LEATHER

local function IsProfessionLabel(text, profession)
    local name = ns.GetProfessionName(profession)
    return text == name or (LOCKED_WITH_SPELL and text == string.format(LOCKED_WITH_SPELL, name))
end

local function EndsWith(text, suffix)
    return text:sub(-#suffix) == suffix
end

-- The red requirement line of a known node. The game words it differently per language
-- (and not always with the profession's name), so the wording only decides if several
-- lines are red; a single red line on a gathering node is the requirement.
local function FindNodeLabel(tooltip, node)
    local suffix = " (" .. node.skill .. ")"
    local only, count
    for i = 2, tooltip:NumLines() do
        local line = _G[tooltip:GetName() .. "TextLeft" .. i]
        local text = line and Plain(line:GetText())
        if text and text ~= "" and IsRed(line) then
            if EndsWith(text, suffix) then return nil end -- already added
            if IsProfessionLabel(text, node.profession) then return line, text end
            only, count = line, (count or 0) + 1
        end
    end
    if count == 1 then
        return only, Plain(only:GetText())
    end
end

-- Entry ID of a world object from its GUID ("GameObject-0-<server>-<map>-<instance>-<id>-<spawn>")
local function ObjectIDFromGUID(guid)
    if not Public(guid) or type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    return kind == "GameObject" and tonumber(id) or nil
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
    -- Only world objects and units; tooltips without data (plain text) are none of ours
    local kind = data and data.type
    if kind == nil or not Public(kind) then return false end
    if kind ~= Enum.TooltipDataType.Object and kind ~= Enum.TooltipDataType.Unit then
        return false
    end

    local title = _G[tooltip:GetName() .. "TextLeft1"]
    local name = title and Plain(title:GetText())
    local id = data.id
    -- Object ID first, then the node's name in the client language (or in English)
    local node = (Public(id) and id ~= nil and ns.GatheringNodes[id])
        or ns.GatheringNodes[ObjectIDFromGUID(data.guid) or false]
        or (name and ns.GatheringNodes[name])
    local _, unit = tooltip:GetUnit()
    if not Public(unit) then return false end
    if not unit then
        if not node then return false end
        local line, text = FindNodeLabel(tooltip, node)
        if not line then return false end
        if HideRequirement(node.profession) then
            line:SetText(nil)
            return true
        end
        if ns.db.disabledProfessions[node.profession] then return false end
        -- Preserve Blizzard's color and wording
        line:SetText(text .. " (" .. node.skill .. ")")
        return true
    end

    if not SKINNABLE_LABEL then return false end
    for i = 2, tooltip:NumLines() do
        local line = _G[tooltip:GetName() .. "TextLeft" .. i]
        local text = line and Plain(line:GetText())
        -- Exact label matching makes repeated calls idempotent after the number was appended
        if text == SKINNABLE_LABEL and IsRed(line) then
            if HideRequirement(393) then
                line:SetText(nil)
                return true
            end
            if ns.db.disabledProfessions[393] then return false end
            local required = ns.GetSkinningRequirement(UnitLevel(unit))
            if required then
                line:SetText(text .. " (" .. required .. ")")
                return true
            end
        end
    end
    return false
end

local function Update(tooltip, data)
    local changed = ns.FilterProfessionRequirements(tooltip, data)
    if ns.EnhanceGatheringTooltip(tooltip, data) then changed = true end
    if changed then tooltip:Show() end
end

for _, kind in ipairs({ Enum.TooltipDataType.Item, Enum.TooltipDataType.Object, Enum.TooltipDataType.Unit }) do
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
