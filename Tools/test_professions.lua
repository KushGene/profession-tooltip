-- Run from the repository root: luajit Tools/test_professions.lua
-- Unlearning a profession must drop its scan data, but a login without profession data must not.
local events, fired = {}, 0
local recipes = { [10] = 171, [11] = 171, [20] = 197 } -- spellID -> profession
local owned = { 171, 197 }
GetProfessions = function() return unpack(owned) end
GetProfessionInfo = function(id) return "Name", nil, 50, 75, nil, nil, id end
C_TradeSkillUI = {}
local invalidated = 0
local ns = {
    L = {},
    char = {
        known = { [10] = 1, [11] = 2, [20] = 0 },
        extra = { [30] = { nil, "Extra", {}, profession = 171 }, [31] = { nil, "Other", {}, profession = 197 } },
        scanned = { [171] = true, [197] = true },
        professions = { [171] = { rank = 50, max = 75 }, [197] = { rank = 50, max = 75 } },
    },
    db = { disabledProfessions = {} },
    RegisterEvent = function(event, fn) events[event] = events[event] or {}; table.insert(events[event], fn) end,
    Fire = function() fired = fired + 1 end,
    InvalidateIndex = function() invalidated = invalidated + 1 end,
}
ns.GetRecipe = function(spellID)
    if recipes[spellID] then return {}, recipes[spellID] end
    local extra = ns.char.extra[spellID]
    if extra then return extra, extra.profession end
end
assert(loadfile("Professions.lua"))("Test", ns)
local function fire(event) for _, fn in ipairs(events[event]) do fn(event) end end

-- Login while the client doesn't report professions yet: nothing may be deleted
owned = {}
fire("PLAYER_LOGIN")
assert(ns.char.known[10] and ns.char.scanned[171] and ns.char.extra[30], "login without data must keep scan data")

owned = { 171, 197 }
fire("SKILL_LINES_CHANGED")
assert(ns.HasProfession(171) and ns.HasProfession(197), "professions must be detected again")

-- Alchemy unlearned while playing
owned = { 197 }
fire("SKILL_LINES_CHANGED")
assert(not ns.HasProfession(171), "unlearned profession must be gone")
assert(ns.char.known[10] == nil and ns.char.known[11] == nil, "its scanned recipes must be dropped")
assert(ns.char.extra[30] == nil and ns.char.scanned[171] == nil, "its extras and scan flag must be dropped")
assert(ns.char.known[20] == 0 and ns.char.extra[31] and ns.char.scanned[197], "other professions must stay")
assert(invalidated == 1, "dropping extras must rebuild the index")
print("Profession tests passed (unlearning drops scan data, login keeps it)")
