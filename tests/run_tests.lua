-- QuestPaceLog test harness.
-- Run from the repository root with Lua 5.1:   lua tests/run_tests.lua
-- It stubs the handful of WoW API functions the addon uses, loads the real
-- addon file fresh for each test, fires simulated game events, and checks the
-- saved data. It can't prove the addon works in the real client, only that
-- the logic does what it should under the API behavior we expect.

local ADDON = "QuestPaceLog/QuestPaceLog.lua"
local passed, failed = 0, 0

-- Builds a fresh fake game world and loads the addon into it.
-- opts.api = "modern" (C_QuestLog.GetInfo) or "classic" (GetQuestLogTitle)
-- opts.db  = existing SavedVariables table to start from, or nil
local function newWorld(opts)
    opts = opts or {}
    local W = { clock = 1790000000, level = opts.level or 8, log = {}, order = {}, printed = {} }
    _G.time = function() return W.clock end
    _G.date = function(fmt, t) return os.date(fmt, t or W.clock) end
    _G.UnitLevel = function() return W.level end
    _G.UnitXP = function() return 100 end
    _G.UnitXPMax = function() return 1000 end
    _G.IsInInstance = function() return false, "none" end
    _G.GetInstanceInfo = function() return "x", "none", 0, "" end
    W.resting, W.zone, W.subZone, W.buffs = false, "Tirisfal Glades", "Brill", {}
    _G.IsResting = function() return W.resting end
    _G.GetRealZoneText = function() return W.zone end
    _G.GetSubZoneText = function() return W.subZone end
    _G.C_Map = { GetBestMapForUnit = function() return 2248 end }
    _G.UnitBuff = function(_, i) return W.buffs[i] end
    W.group = 0
    _G.GetNumGroupMembers = function() return W.group end
    _G.GetNumRaidMembers, _G.GetNumPartyMembers = nil, nil
    _G.C_UnitAuras = nil
    _G.GetQuestGreenRange = nil
    _G.SlashCmdList = {}
    _G.print = function(msg) table.insert(W.printed, (tostring(msg):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))) end
    local handler
    -- A fake frame that accepts any method. It keeps the event handler, and
    -- the window's text, so tests can check what the window shows.
    local function fakeFrame()
        local f = {}
        f.SetScript = function(self, what, fn)
            if what == "OnEvent" then handler = fn end
            if what == "OnEnter" then table.insert(W.hovers, function() fn(self) end) end
            self[what] = fn
        end
        f.SetSize = function(_, w, h) if w == 780 then W.windowHeight = h end end
        f.SetText = function(self, t) self.shownText = t; W.lastText = t; W.texts[t] = true end
        f.Show = function(self) self.shown = true end
        f.Hide = function(self) self.shown = false end
        f.IsShown = function(self) return self.shown end
        f.CreateFontString = function() return fakeFrame() end
        f.CreateTexture = function() return fakeFrame() end
        return setmetatable(f, { __index = function() return function() end end })
    end
    W.missingTemplates, W.texts, W.hovers = {}, {}, {}
    _G.CreateFrame = function(_, name, _, template)
        if template and W.missingTemplates[template] then error("Couldn't find inherited node " .. template) end
        local f = fakeFrame()
        if name then _G[name] = f end
        return f
    end
    _G.UIParent, _G.UISpecialFrames = nil, {}
    _G.C_QuestLog, _G.GetNumQuestLogEntries, _G.GetQuestLogTitle = nil, nil, nil
    if opts.api == "classic" then
        _G.GetNumQuestLogEntries = function() return #W.order end
        _G.GetQuestLogTitle = function(i)
            local id = W.order[i]
            local q = id and W.log[id]
            if not q then return nil end
            return q.title, q.level, nil, false, false, false, 0, id
        end
        _G.C_QuestLog = { GetTitleForQuestID = function(id) return W.log[id] and W.log[id].title end }
    else
        _G.C_QuestLog = {
            GetTitleForQuestID = function(id) return W.log[id] and W.log[id].title end,
            GetNumQuestLogEntries = function() return #W.order + 1 end,
            GetInfo = function(i)
                if i == 1 then return { isHeader = true, title = "Zone header" } end
                local id = W.order[i - 1]
                local q = id and W.log[id]
                if not q then return nil end
                return { questID = id, title = q.title, level = q.level, isHeader = false }
            end,
        }
    end
    _G.QuestPaceLogDB = opts.db
    dofile(ADDON)
    function W.fire(ev, ...) handler(nil, ev, ...) end
    function W.cmd(s) _G.SlashCmdList["QUESTPACELOG"](s) end
    function W.addQuest(id, title, level)
        W.log[id] = { title = title, level = level }
        table.insert(W.order, id)
    end
    function W.removeQuest(id)
        W.log[id] = nil
        for i, v in ipairs(W.order) do if v == id then table.remove(W.order, i) break end end
    end
    function W.saw(fragment)
        for _, line in ipairs(W.printed) do if line:find(fragment, 1, true) then return true end end
        return false
    end
    return W
end

local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; io.write("PASS  ", name, "\n")
    else failed = failed + 1; io.write("FAIL  ", name, "\n      ", tostring(err), "\n") end
end

local function eq(actual, expected, what)
    if actual ~= expected then
        error(string.format("%s, expected %s, got %s", what or "value", tostring(expected), tostring(actual)), 2)
    end
end

test("login starts a session", function()
    local W = newWorld()
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    eq(#QuestPaceLogDB.sessions, 1, "session count")
end)

test("reload resumes instead of starting a new session", function()
    local W = newWorld()
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.fire("PLAYER_ENTERING_WORLD", false, true)
    eq(#QuestPaceLogDB.sessions, 1, "session count after reload")
end)

test("accept and turn-in record duration, levels, quest level and colors", function()
    local W = newWorld({ level = 8 })
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.addQuest(100, "Hard Quest", 11)
    W.fire("QUEST_ACCEPTED", 100)
    W.clock = W.clock + 600; W.level = 11
    W.removeQuest(100)
    W.fire("QUEST_TURNED_IN", 100, 900, 0)
    local e = QuestPaceLogDB.sessions[1].entries[1]
    eq(e.durationSec, 600, "duration")
    eq(e.acceptedLevel, 8, "accepted level")
    eq(e.turnedInLevel, 11, "turned in level")
    eq(e.questLevel, 11, "quest level")
    eq(e.colorAtAccept, "orange", "color at accept")
    eq(e.colorAtTurnIn, "yellow", "color at turn-in")
    eq(e.xpReward, 900, "xp reward")
end)

test("untracking marks backlog, tracking again clears it", function()
    local W = newWorld()
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.addQuest(200, "Some Quest", 8)
    W.fire("QUEST_ACCEPTED", 200)
    W.fire("QUEST_WATCH_LIST_CHANGED", 200, false)
    eq(QuestPaceLogDB.sessions[1].entries[1].backlog, true, "backlog after untrack")
    W.fire("QUEST_WATCH_LIST_CHANGED", 200, true)
    eq(QuestPaceLogDB.sessions[1].entries[1].backlog, nil, "backlog after retrack")
end)

test("/qpl why tags the latest untagged backlog quest, rejects bad letters", function()
    local W = newWorld()
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.addQuest(300, "Parked Quest", 8)
    W.fire("QUEST_ACCEPTED", 300)
    W.fire("QUEST_WATCH_LIST_CHANGED", 300, false)
    W.cmd("why a")
    eq(QuestPaceLogDB.sessions[1].entries[1].reason, "a", "reason")
    eq(QuestPaceLogDB.quests[300].reason, "a", "reason on tracker record")
    W.cmd("why z")
    assert(W.saw("Use /qpl why"), "usage message for a bad letter")
end)

test("level-ups record green and gray, with the classic fallback formula", function()
    local W = newWorld({ level = 8 })
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.addQuest(400, "Easy Quest", 7)
    W.fire("QUEST_ACCEPTED", 400)
    W.level = 11; W.fire("PLAYER_LEVEL_UP", 11)
    eq(QuestPaceLogDB.quests[400].greenAtLevel, 11, "green at level")
    eq(QuestPaceLogDB.quests[400].grayAt, nil, "not gray yet at 11")
    W.level = 13; W.fire("PLAYER_LEVEL_UP", 13)
    eq(QuestPaceLogDB.quests[400].grayAtLevel, 13, "gray at level")
    assert(W.saw("is now gray"), "gray chat line")
end)

test("GetQuestGreenRange from the client is used when present", function()
    local W = newWorld({ level = 8 })
    _G.GetQuestGreenRange = function() return 3 end
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.addQuest(450, "Quest", 8)
    W.fire("QUEST_ACCEPTED", 450)
    W.level = 12; W.fire("PLAYER_LEVEL_UP", 12)
    -- green range 3 at level 12 means gray at quest level 8 or below
    eq(QuestPaceLogDB.quests[450].grayAtLevel, 12, "gray at level with range 3")
end)

test("a quest leaving the log without a turn-in is marked dropped", function()
    local W = newWorld()
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.addQuest(500, "Drop Me", 8)
    W.fire("QUEST_ACCEPTED", 500)
    W.removeQuest(500)
    W.level = 9; W.fire("PLAYER_LEVEL_UP", 9)
    assert(QuestPaceLogDB.quests[500].droppedAt, "dropped timestamp")
    eq(QuestPaceLogDB.quests[500].droppedLevel, 9, "dropped level")
end)

test("classic-style quest log API works and old saved data loads", function()
    local oldDb = { sessions = { { startedAt = 1, startedAtStr = "old", entries = {
        { questID = 370, title = "At War With The Scarlet Crusade", acceptedAt = 1, acceptedLevel = 6, backlog = true } } } } }
    local W = newWorld({ api = "classic", level = 10, db = oldDb })
    W.addQuest(370, "At War With The Scarlet Crusade", 10)
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    eq(QuestPaceLogDB.quests[370].predatesTracking, true, "pre-existing quest picked up at login")
    W.cmd("why a scarlet")
    eq(QuestPaceLogDB.sessions[1].entries[1].reason, "a", "tag on an old-session entry")
    W.level = 17; W.fire("PLAYER_LEVEL_UP", 17)
    eq(QuestPaceLogDB.quests[370].grayAtLevel, 17, "gray via classic API")
end)

test("report runs without errors and mentions quest difficulty", function()
    local W = newWorld()
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.addQuest(600, "Quest", 8)
    W.fire("QUEST_ACCEPTED", 600)
    W.cmd("report")
    W.cmd("")
    assert(W.saw("Quests tracked for difficulty"), "difficulty line in report")
end)

test("accept and turn-in record the zone, subzone and map", function()
    local W = newWorld()
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.addQuest(700, "The Prodigal Lich", 8)
    W.fire("QUEST_ACCEPTED", 700)
    W.zone, W.subZone = "Undercity", "Magic Quarter"
    W.removeQuest(700)
    W.fire("QUEST_TURNED_IN", 700, 300, 0)
    local e = QuestPaceLogDB.sessions[1].entries[1]
    eq(e.acceptedZone, "Tirisfal Glades", "accepted zone")
    eq(e.acceptedSubZone, "Brill", "accepted subzone")
    eq(e.acceptedMapID, 2248, "accepted map")
    eq(e.turnedInZone, "Undercity", "turned in zone")
    eq(QuestPaceLogDB.quests[700].turnedInSubZone, "Magic Quarter", "zone on the quest record")
    W.cmd("")
    assert(W.saw("Brill, Tirisfal Glades to Magic Quarter, Undercity"), "zones in the log line")
end)

test("rest periods record the zone where they started", function()
    local W = newWorld()
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.resting = true
    W.fire("PLAYER_UPDATE_RESTING")
    eq(QuestPaceLogDB.sessions[1].rests[1].subZone, "Brill", "rest subzone")
end)

test("a camp buff gained while resting marks the rest as a campfire rest", function()
    local W = newWorld()
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.zone, W.subZone = "Tirisfal Glades", "Balnir Farmstead"
    W.resting = true
    W.fire("PLAYER_UPDATE_RESTING")
    W.clock = W.clock + 60
    W.buffs = { "Boosted Rest" }
    W.fire("UNIT_AURA", "player")
    W.clock = W.clock + 30
    W.resting = false
    W.fire("PLAYER_UPDATE_RESTING")
    local r = QuestPaceLogDB.sessions[1].rests[1]
    eq(r.campfire, true, "campfire tag")
    eq(r.campBuff, "Boosted Rest", "camp buff name")
    eq(r.durationSec, 90, "stay length")
    eq(#QuestPaceLogDB.sessions[1].campBuffs, 1, "camp buff logged")
    W.cmd("report")
    assert(W.saw("at a campfire, 1, averaging 1:30"), "campfire line in the report")
end)

test("camp buff already present at login is not logged as a new gain", function()
    local W = newWorld()
    W.buffs = { "Boosted Rest" }
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.fire("UNIT_AURA", "player")
    eq(#QuestPaceLogDB.sessions[1].campBuffs, 0, "no gain from a login snapshot")
    W.buffs = {}
    W.fire("UNIT_AURA", "player")
    W.buffs = { "Boosted Rest" }
    W.fire("UNIT_AURA", "player")
    eq(#QuestPaceLogDB.sessions[1].campBuffs, 1, "a real later gain is logged")
end)

test("/qpl campbuff add and remove change the watched names", function()
    local W = newWorld()
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.cmd("campbuff add cozy fire")
    W.buffs = { "Cozy Fire" }
    W.fire("UNIT_AURA", "player")
    eq(#QuestPaceLogDB.sessions[1].campBuffs, 1, "watched after add")
    W.cmd("campbuff remove cozy fire")
    local found = false
    for _, n in ipairs(QuestPaceLogDB.campBuffNames) do if n == "cozy fire" then found = true end end
    eq(found, false, "removed from the list")
    W.cmd("buffs")
    assert(W.saw("Your buffs right now, Cozy Fire"), "buff listing")
end)

test("modern aura API (C_UnitAuras) is used when present", function()
    local W = newWorld()
    _G.UnitBuff = nil
    local modern = {}
    _G.C_UnitAuras = { GetAuraDataByIndex = function(_, i) return modern[i] end }
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    modern[1] = { name = "Boosted Rest", spellId = 1 }
    W.fire("UNIT_AURA", "player")
    eq(#QuestPaceLogDB.sessions[1].campBuffs, 1, "gain seen through C_UnitAuras")
end)

test("joining and leaving a group records times and sizes, never names", function()
    local W = newWorld()
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.group = 2
    W.fire("GROUP_ROSTER_UPDATE")
    W.clock = W.clock + 60
    W.group = 3
    W.fire("GROUP_ROSTER_UPDATE")
    W.fire("GROUP_ROSTER_UPDATE")
    W.clock = W.clock + 60
    W.group = 0
    W.fire("GROUP_ROSTER_UPDATE")
    local g = QuestPaceLogDB.sessions[1].groups[1]
    eq(#QuestPaceLogDB.sessions[1].groups, 1, "one group")
    eq(g.durationSec, 120, "group length")
    eq(g.maxSize, 3, "largest size")
    eq(#g.sizes, 2, "size changes, repeats ignored")
    eq(g.sizes[1].size, 2, "first size")
    eq(g.zone, "Tirisfal Glades", "zone where joined")
    eq(g.alreadyGrouped, nil, "a real join")
    W.cmd("report")
    assert(W.saw("Groups this session, 1, largest 3, average 2:00 together"), "group line in the report")
end)

test("turn-ins note the group size, 1 when solo", function()
    local W = newWorld()
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.addQuest(800, "Solo Quest", 8)
    W.fire("QUEST_ACCEPTED", 800)
    W.removeQuest(800)
    W.fire("QUEST_TURNED_IN", 800, 100, 0)
    W.group = 4
    W.fire("GROUP_ROSTER_UPDATE")
    W.addQuest(801, "Group Quest", 8)
    W.fire("QUEST_ACCEPTED", 801)
    W.removeQuest(801)
    W.fire("QUEST_TURNED_IN", 801, 100, 0)
    local entries = QuestPaceLogDB.sessions[1].entries
    eq(entries[1].turnedInGroupSize, 1, "solo turn-in")
    eq(entries[2].turnedInGroupSize, 4, "grouped turn-in")
    eq(QuestPaceLogDB.quests[801].turnedInGroupSize, 4, "size on the quest record")
    assert(W.saw("in a group of 4"), "group size in the turn-in line")
    W.cmd("report")
    assert(W.saw("Quests turned in while grouped, 1 of 2."), "grouped count in the report")
end)

test("a group already joined at login is flagged, reload continues it", function()
    local W = newWorld()
    W.group = 5
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.fire("PLAYER_ENTERING_WORLD", false, true)
    eq(#QuestPaceLogDB.sessions[1].groups, 1, "reload doesn't open a second group")
    eq(QuestPaceLogDB.sessions[1].groups[1].alreadyGrouped, true, "flagged as already grouped")
end)

test("older Classic party and raid counts work", function()
    local W = newWorld()
    _G.GetNumGroupMembers = nil
    local party, raid = 2, 0
    _G.GetNumPartyMembers = function() return party end
    _G.GetNumRaidMembers = function() return raid end
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    eq(QuestPaceLogDB.sessions[1].groups[1].maxSize, 3, "party count plus you")
    raid = 12
    W.fire("RAID_ROSTER_UPDATE")
    eq(QuestPaceLogDB.sessions[1].groups[1].maxSize, 12, "raid count includes you")
end)

-- Two sessions, each with one quest, and a long overnight wait in between.
local function twoSessions(W)
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.addQuest(900, "First Day", 8)
    W.fire("QUEST_ACCEPTED", 900)
    W.clock = W.clock + 120
    W.removeQuest(900)
    W.fire("QUEST_TURNED_IN", 900, 100, 0)
    W.clock = W.clock + 12 * 3600
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.addQuest(901, "Second Day", 8)
    W.fire("QUEST_ACCEPTED", 901)
    W.clock = W.clock + 240
    W.removeQuest(901)
    W.fire("QUEST_TURNED_IN", 901, 100, 0)
end

test("/qpl report all covers every session, without overnight gaps", function()
    local W = newWorld()
    twoSessions(W)
    W.cmd("report all")
    assert(W.saw("all 2 sessions since"), "all-sessions header")
    assert(W.saw("Quests logged, 2."), "quests from both sessions")
    assert(W.saw("Average time per quest, 3:00."), "average across both")
    assert(not W.saw("Gaps measured"), "the overnight wait isn't a gap")
    W.printed = {}
    W.cmd("report")
    assert(W.saw("Quests logged, 1."), "plain report is still this session only")
end)

test("/qpl show opens a window with the report, both views", function()
    local W = newWorld()
    twoSessions(W)
    W.cmd("show")
    assert(W.lastText and W.lastText:find("Quests logged, 1.", 1, true), "this session in the window")
    assert(not W.lastText:find("|c", 1, true), "color codes stripped")
    W.cmd("show all")
    assert(W.lastText:find("Quests logged, 2.", 1, true), "all sessions in the window")
    eq(UISpecialFrames[1], "QuestPaceLogFrame", "Escape closes it")
end)

test("the window still opens when the client lacks the templates", function()
    local W = newWorld()
    W.missingTemplates = { BasicFrameTemplateWithInset = true, UIPanelScrollFrameTemplate = true, UIPanelButtonTemplate = true, UIPanelCloseButton = true }
    twoSessions(W)
    W.cmd("show")
    assert(W.lastText and W.lastText:find("Quests logged, 1.", 1, true), "plain window shows the report")
    assert(not W.saw("couldn't open"), "no failure message")
end)

-- True when any text the window set contains the fragment, color codes removed.
local function shown(W, fragment)
    for t in pairs(W.texts) do
        if t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):find(fragment, 1, true) then return true end
    end
    return false
end

test("dashboard tiles and bars show the right numbers, and refresh on turn-in", function()
    local W = newWorld()
    twoSessions(W)
    W.cmd("show all")
    assert(not W.saw("couldn't draw"), "visuals drew without an error")
    assert(W.texts["2"], "quests turned in tile")
    assert(W.texts["3:00"], "average per quest tile")
    assert(shown(W, "2 yellow"), "quest color legend")
    assert(shown(W, "100%"), "donut center")
    QuestPaceLogDB.sessions[1].entries[1].colorAtTurnIn = nil
    W.cmd("show all")
    assert(shown(W, "1 yellow\n1 without a recorded color"), "turn-ins from before colors were recorded")
    assert(W.texts["Second Day"] and W.texts["4:00, 25 XP a minute"], "recent quest row with XP a minute")
    W.cmd("show")
    W.texts = {}
    W.addQuest(902, "Third Quest", 8)
    W.fire("QUEST_ACCEPTED", 902)
    W.clock = W.clock + 60
    W.removeQuest(902)
    W.fire("QUEST_TURNED_IN", 902, 100, 0)
    assert(W.texts["Third Quest"], "open window refreshed after a turn-in")
end)

test("the book button opens and closes the dashboard", function()
    local W = newWorld()
    twoSessions(W)
    local b = _G.QuestPaceLogButton
    assert(b and b.OnClick, "button exists")
    b.OnClick()
    assert(W.texts["Second Day"], "click opens the dashboard")
    b.OnClick()
    eq(_G.QuestPaceLogFrame.shown, false, "second click closes it")
end)

test("XP per minute and time played, live and after logout", function()
    local W = newWorld()
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.clock = W.clock + 600
    QuestPaceLogDB.sessions[1].xpTotal = 3000
    W.fire("PLAYER_LOGOUT")
    eq(QuestPaceLogDB.sessions[1].lastActiveAt, W.clock, "last active saved at logout")
    W.cmd("report")
    assert(W.saw("XP per minute played, 300."), "300 XP a minute over 10 minutes")
    W.cmd("show")
    assert(W.texts["300"] and W.texts["10:00"], "XP a minute and time played tiles")
end)

test("old sessions without lastActiveAt use their latest timestamp for play time", function()
    local W = newWorld({ db = { sessions = { { startedAt = 1000, startedAtStr = "old", xpTotal = 1200, xpFromQuests = 0,
        entries = { { questID = 1, title = "Old", acceptedAt = 1100, turnedInAt = 1600, durationSec = 500 } } } } } })
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.cmd("report all")
    assert(W.saw("XP per minute played, 120."), "1200 XP over the 10 minutes the old session's data spans")
end)

test("time played at each level, from the start level through level-ups", function()
    local W = newWorld({ level = 8 })
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.clock = W.clock + 600
    W.level = 9
    W.fire("PLAYER_LEVEL_UP", 9)
    W.clock = W.clock + 300
    QuestPaceLogDB.sessions[1].xpTotal = 900 -- leveling always comes with XP
    W.fire("PLAYER_LOGOUT")
    eq(QuestPaceLogDB.sessions[1].startLevel, 8, "start level saved")
    eq(QuestPaceLogDB.sessions[1].levelUps[1].level, 9, "level-up saved")
    W.cmd("report")
    assert(W.saw("Time played at each level, level 8 10:00, level 9 5:00."), "level times in the report")
    W.cmd("show")
    assert(W.texts["10m"] and W.texts["5m"], "level columns in the window")
end)

test("hovering a recent quest shows its details", function()
    local W = newWorld()
    local lines = {}
    _G.GameTooltip = setmetatable({
        SetText = function(_, t) table.insert(lines, t) end,
        AddLine = function(_, t) table.insert(lines, t) end,
    }, { __index = function() return function() end end })
    twoSessions(W)
    W.cmd("show")
    -- OnEnter scripts in creation order. The book button comes first, then
    -- the eight quest rows, and this session's one quest sits in row 1.
    eq(#W.hovers, 9, "button plus eight hover strips")
    W.hovers[2]()
    local all = table.concat(lines, " | ")
    assert(all:find("Second Day", 1, true), "title in the tooltip, got " .. all)
    assert(all:find("In Brill, Tirisfal Glades", 1, true), "zone in the tooltip")
    assert(all:find("4:00, 100 XP, 25 XP a minute", 1, true), "time and XP in the tooltip")
    _G.GameTooltip = nil
end)

test("the window is never taller than the screen", function()
    local W = newWorld()
    _G.UIParent = { GetHeight = function() return 700 end }
    twoSessions(W)
    W.cmd("show")
    eq(W.windowHeight, 680, "clamped to the screen")
    _G.UIParent = nil
end)

io.write(string.format("\n%d passed, %d failed\n", passed, failed))
os.exit(failed == 0 and 0 or 1)
