-- Integration checks using the actual bundled libraries and a minimal WoW UI mock.
-- Run from the repository root: luajit Tools/test_minimap.lua
local frames = {}
strmatch = string.match
local methods = {}
local function noop() end
for name in ([[SetFrameStrata SetFixedFrameStrata SetFrameLevel SetFixedFrameLevel
    RegisterForClicks RegisterForDrag SetHighlightTexture SetSize SetTexture
    SetTexCoord SetVertexColor ClearAllPoints SetOrder SetDuration SetFromAlpha
    SetToAlpha SetStartDelay SetToFinalAlpha LockHighlight UnlockHighlight
    SetAlpha Stop Play SetOwner]]):gmatch("%S+") do
    methods[name] = noop
end
local function widget(parent)
    return setmetatable({ parent = parent, scripts = {}, lines = {} }, { __index = methods })
end
function methods:SetScript(event, callback) self.scripts[event] = callback end
function methods:HookScript(event, callback) self.scripts[event] = callback end
function methods:RegisterEvent(event) self.event = event end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:GetParent() return self.parent end
function methods:GetVertexColor() return 1, 1, 1 end
function methods:GetWidth() return 140 end
function methods:GetHeight() return 140 end
function methods:GetCenter() return 70, 70 end
function methods:GetEffectiveScale() return 1 end
function methods:SetPoint(...) self.point = { ... } end
function methods:CreateTexture() return widget(self) end
function methods:CreateAnimationGroup() return widget(self) end
function methods:CreateAnimation() return widget(self) end
function methods:AddLine(text) self.lines[#self.lines + 1] = text end
function CreateFrame(kind, name, parent)
    local frame = widget(parent)
    frame.name = name
    frames[#frames + 1] = frame
    return frame
end
function GetCursorPosition() return 70, 140 end

local libraries = {}
for line in io.lines("ProfessionTooltip.toc") do
    if line:match("^Libs\\") then
        libraries[#libraries + 1] = line:gsub("\\", "/")
    end
end
assert(#libraries == 4, "TOC must load all four bundled libraries")

local function scenario(db, expectedPos, libraryLoginFirst)
    frames = {}
    LibStub = nil
    UIParent, Minimap = widget(), widget()
    AddonCompartmentFrame = nil -- No compartment API required for the TOC entry.
    for _, path in ipairs(libraries) do dofile(path) end
    local icon = LibStub("LibDBIcon-1.0")
    local broker = LibStub("LibDataBroker-1.1")
    local function libraryLogin()
        for _, frame in ipairs(frames) do
            if frame.event == "PLAYER_LOGIN" and frame.scripts.OnEvent then
                frame.scripts.OnEvent(frame, "PLAYER_LOGIN")
            end
        end
    end
    if libraryLoginFirst then libraryLogin() end
    local events, messages = {}, {}
    local clicks, recipeClicks = 0, 0
    local ns = {
        db = { minimap = db }, ICON = "test-icon",
        L = { MINIMAP_TOOLTIP = "Open settings", MINIMAP_TOOLTIP_RIGHT = "Missing recipes" },
        ToggleConfigWindow = function() clicks = clicks + 1 end,
        ToggleRecipeWindow = function() recipeClicks = recipeClicks + 1 end,
        RegisterEvent = function(event, callback) events[event] = callback end,
        On = function(event, callback) messages[event] = callback end,
    }
    assert(loadfile("UI/MinimapButton.lua"))("ProfessionTooltip", ns)
    events.PLAYER_LOGIN()
    if not libraryLoginFirst then libraryLogin() end

    local button = assert(icon:GetMinimapButton("ProfessionTooltip"))
    local launcher = assert(broker:GetDataObjectByName("ProfessionTooltip"))
    assert(button.name == "LibDBIcon10_ProfessionTooltip", "collector-compatible name")
    assert(button.db == db and button.dataObject == launcher)
    assert(db.minimapPos == expectedPos, "legacy position migrated only once")
    assert(db.hide == not db.show and button.shown == db.show, "visibility preserved")
    assert(not db.showInCompartment, "no duplicate compartment entry")
    assert(#icon:GetButtonList() == 1, "exactly one minimap button")
    assert(button.point[2] == Minimap, "positioned at minimap")

    -- Left clicks from the minimap, broker display and TOC compartment open settings;
    -- a right click opens the missing recipes.
    button.scripts.OnClick(button, "LeftButton")
    launcher.OnClick(nil, "LeftButton")
    ProfessionTooltip_OnAddonCompartmentClick()
    assert(clicks == 3 and recipeClicks == 0)
    button.scripts.OnClick(button, "RightButton")
    launcher.OnClick(nil, "RightButton")
    assert(clicks == 3 and recipeClicks == 2, "right click must open the missing recipes")
    button.scripts.OnEnter(button)
    assert(icon.tooltip.lines[1] == "Profession Tooltip")
    assert(icon.tooltip.lines[2] == "Open settings")
    assert(icon.tooltip.lines[3] == "Missing recipes")

    -- A real library drag writes to the same SavedVariables table.
    button.scripts.OnDragStart(button)
    button.scripts.OnUpdate(button)
    button.scripts.OnDragStop(button)
    assert(db.minimapPos == 90, "dragged position persisted")
    db.show = not db.show
    messages.SETTINGS_CHANGED(nil, "minimap")
    assert(db.hide == not db.show and button.shown == db.show)
    assert(db.minimapPos == 90, "settings change must not restore stale angle")
    events.PLAYER_LOGIN()
    assert(icon:GetMinimapButton("ProfessionTooltip") == button)
    assert(broker:GetDataObjectByName("ProfessionTooltip") == launcher)
    assert(db.minimapPos == 90, "repeat initialization must preserve new position")

    -- Existing same-version libraries are reused rather than replacing objects.
    for _, path in ipairs(libraries) do dofile(path) end
    assert(LibStub("LibDBIcon-1.0") == icon)
    assert(icon:GetMinimapButton("ProfessionTooltip") == button)
end

scenario({ show = true, angle = 200 }, 200, true)
scenario({ show = false, angle = 315 }, 315, true)
scenario({ show = true, angle = 0 }, 0, false)
scenario({ show = false, angle = 200, minimapPos = 42 }, 42, false)
scenario({ show = true }, 200, true)
print("Minimap: bundled libraries, migration, visibility, drag, launcher and reuse OK")
