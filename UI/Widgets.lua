-- UI/Widgets.lua
-- Reusable UI building blocks in the addon's flat design.
local _, ns = ...

local Widgets = {}
ns.Widgets = Widgets

Widgets.ACCENT = { 1, 0.62, 0.20 }

function Widgets.Backdrop(frame, bg, border)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(unpack(bg))
    frame:SetBackdropBorderColor(unpack(border))
end

function Widgets.Line(parent, alpha)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, alpha or 0.08)
    return line
end

-- ----------------------------------------------------------------------------
-- Column: stacks elements below each other automatically
-- ----------------------------------------------------------------------------
local Column = {}
Column.__index = Column

function Widgets.NewColumn(parent, x, y, width)
    return setmetatable({ parent = parent, x = x, y = y, width = width, items = {}, newKeys = {} }, Column)
end

local function CreateNewBadge(parent)
    local badge = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    badge:SetHeight(14)
    Widgets.Backdrop(badge, { 0.42, 0.24, 0.06, 1 }, { Widgets.ACCENT[1], Widgets.ACCENT[2], Widgets.ACCENT[3], 0.9 })
    badge.text = badge:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    badge.text:SetPoint("CENTER")
    badge.text:SetText(ns.L["NEW_BADGE"])
    badge.text:SetTextColor(1, 0.85, 0.35)
    badge:SetWidth(math.max(24, badge.text:GetStringWidth() + 8))
    return badge
end

function Column:Space(height)
    self.y = self.y - height
end

function Column:Header(text)
    local header = self.parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header:SetPoint("TOPLEFT", self.x, self.y)
    header:SetText(text)
    header:SetTextColor(unpack(Widgets.ACCENT))

    local line = Widgets.Line(self.parent, 0.12)
    line:SetHeight(1)
    line:SetWidth(self.width)
    line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)

    self.y = self.y - 26
    return header
end

-- Creates label + description to the right of a control of width controlWidth
function Column:Label(anchor, controlWidth, label, desc, hasBadge)
    local availWidth = self.width - controlWidth - 6
    local text = self.parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 6, -5)
    text:SetJustifyH("LEFT")
    text:SetText(label)

    local badge
    if hasBadge then
        local naturalWidth = text:GetStringWidth()
        badge = CreateNewBadge(self.parent)
        local maxLabelW = availWidth - badge:GetWidth() - 6
        text:SetWidth(maxLabelW)
        if naturalWidth <= maxLabelW then
            badge:SetPoint("TOPLEFT", text, "TOPLEFT", naturalWidth + 6, 1)
        else
            badge:SetPoint("TOPLEFT", text, "TOPRIGHT", 6, 1)
        end
    else
        text:SetWidth(availWidth)
    end

    local height = text:GetStringHeight()
    local descText
    if desc then
        descText = self.parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        descText:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -3)
        descText:SetWidth(availWidth)
        descText:SetJustifyH("LEFT")
        descText:SetText(desc)
        height = height + 3 + descText:GetStringHeight()
    end
    return text, descText, height, badge, availWidth
end

-- opts: label, desc, get(), set(value), enabled() optional, indent (sub-option) optional, key/isNew() optional
function Column:Check(opts)
    local indent = opts.indent and 24 or 0
    local cb = CreateFrame("CheckButton", nil, self.parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", self.x + indent, self.y + 3)
    if opts.key and opts.isNew then
        self.newKeys[#self.newKeys + 1] = opts.key
    end
    local text, _, height, badge, availWidth = self:Label(cb, 24 + indent, opts.label, opts.desc, opts.isNew ~= nil)
    cb:SetHitRectInsets(0, -(self.width - 24 - indent), 0, 0) -- clicking the text toggles too
    cb:SetScript("OnClick", function(button)
        opts.set(button:GetChecked() and true or false)
    end)

    local item = {}
    function item.Refresh()
        cb:SetChecked(opts.get() and true or false)
        local enabled = not opts.enabled or opts.enabled()
        cb:SetEnabled(enabled)
        text:SetFontObject(enabled and "GameFontHighlight" or "GameFontDisable")
        if badge then
            local showNew = opts.isNew() and true or false
            badge:SetShown(showNew)
            text:SetWidth(showNew and (availWidth - badge:GetWidth() - 6) or availWidth)
        end
    end
    self.items[#self.items + 1] = item
    self.y = self.y - math.max(24, height) - 12
    return cb
end

-- Selection as a segmented bar: all values side by side, the selected one is highlighted.
-- opts: label, desc, values, format(value), get(), set(value), enabled() optional, key/isNew() optional
local SEGMENT_HEIGHT, SEGMENT_GAP, SEGMENT_PADDING = 22, 4, 20
local SEGMENT_BG, SEGMENT_BORDER = { 0.12, 0.12, 0.14, 1 }, { 1, 1, 1, 0.12 }
local SEGMENT_BG_SELECTED = { 0.36, 0.22, 0.07, 1 }

function Column:Choice(opts)
    if opts.key and opts.isNew then
        self.newKeys[#self.newKeys + 1] = opts.key
    end
    local label = self.parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("TOPLEFT", self.x, self.y)
    label:SetJustifyH("LEFT")
    label:SetText(opts.label)

    local badge
    if opts.isNew then
        local naturalWidth = label:GetStringWidth()
        badge = CreateNewBadge(self.parent)
        local maxLabelW = self.width - badge:GetWidth() - 6
        label:SetWidth(maxLabelW)
        if naturalWidth <= maxLabelW then
            badge:SetPoint("TOPLEFT", label, "TOPLEFT", naturalWidth + 6, 1)
        else
            badge:SetPoint("TOPLEFT", label, "TOPRIGHT", 6, 1)
        end
    else
        label:SetWidth(self.width)
    end
    local y = self.y - label:GetStringHeight() - 3

    if opts.desc then
        local desc = self.parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        desc:SetPoint("TOPLEFT", self.x, y)
        desc:SetWidth(self.width)
        desc:SetJustifyH("LEFT")
        desc:SetText(opts.desc)
        y = y - desc:GetStringHeight() - 6
    end

    local buttons, x = {}, self.x
    for i, value in ipairs(opts.values) do
        local button = CreateFrame("Button", nil, self.parent, "BackdropTemplate")
        button.text = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        button.text:SetPoint("CENTER")
        button.text:SetText(opts.format(value))
        local width = math.max(36, button.text:GetStringWidth() + SEGMENT_PADDING)
        if x + width > self.x + self.width then -- wrap if the bar gets too wide
            x = self.x
            y = y - SEGMENT_HEIGHT - SEGMENT_GAP
        end
        button:SetSize(width, SEGMENT_HEIGHT)
        button:SetPoint("TOPLEFT", self.parent, "TOPLEFT", x, y)
        Widgets.Backdrop(button, SEGMENT_BG, SEGMENT_BORDER)
        button:SetScript("OnClick", function() opts.set(value) end)
        button:SetScript("OnEnter", function(b)
            if not b.selected then b:SetBackdropBorderColor(1, 1, 1, 0.35) end
        end)
        button:SetScript("OnLeave", function(b)
            if not b.selected then b:SetBackdropBorderColor(unpack(SEGMENT_BORDER)) end
        end)
        button.value = value
        buttons[i] = button
        x = x + width + SEGMENT_GAP
    end

    local item = {}
    function item.Refresh()
        local current = opts.get()
        local enabled = not opts.enabled or opts.enabled()
        label:SetFontObject(enabled and "GameFontHighlight" or "GameFontDisable")
        if badge then
            local showNew = opts.isNew() and true or false
            badge:SetShown(showNew)
            label:SetWidth(showNew and (self.width - badge:GetWidth() - 6) or self.width)
        end
        for _, button in ipairs(buttons) do
            local selected = button.value == current
            button.selected = selected
            button:SetEnabled(enabled)
            button:SetBackdropColor(unpack(selected and SEGMENT_BG_SELECTED or SEGMENT_BG))
            if selected then
                button:SetBackdropBorderColor(Widgets.ACCENT[1], Widgets.ACCENT[2], Widgets.ACCENT[3], 0.9)
                button.text:SetTextColor(1, 0.82, 0.3)
            else
                button:SetBackdropBorderColor(unpack(SEGMENT_BORDER))
                button.text:SetTextColor(enabled and 0.9 or 0.5, enabled and 0.9 or 0.5, enabled and 0.9 or 0.5)
            end
        end
    end
    self.items[#self.items + 1] = item
    self.y = y - SEGMENT_HEIGHT - 14
end

-- Register any custom element (must have Refresh())
function Column:Add(item, height)
    self.items[#self.items + 1] = item
    self.y = self.y - height
end

function Column:Refresh()
    for _, item in ipairs(self.items) do
        item.Refresh()
    end
end
