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
    local W = { clock = 1790000000, level = opts.level or 8, log = {}, order = {}, printed = {}, collapsed = {}, untracked = {} }
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
    W.money, W.ghost, W.hk = 1000, false, 0
    _G.GetMoney = function() return W.money end
    _G.UnitIsGhost = function() return W.ghost end
    _G.GetPVPLifetimeStats = function() return W.hk end
    W.detail = nil
    _G.GetTitleText = function() return W.detail and W.detail.title end
    _G.GetQuestText = function() return W.detail and W.detail.text end
    _G.GetObjectiveText = function() return W.detail and W.detail.objective end
    _G.IsInInstance = function() return false, "none" end
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
        f.SetSize = function(self, w, h) self.w, self.h = w, h end
        f.GetText = function(self) return self.shownText end
        f.SetChecked = function(self, v) self.checked = v end
        f.GetChecked = function(self) return self.checked end
        f.SetText = function(self, t) self.shownText = t; W.lastText = t; W.texts[t] = true end
        f.Show = function(self) self.shown = true end
        f.Hide = function(self) self.shown = false end
        f.IsShown = function(self) return self.shown end
        f.CreateFontString = function() return fakeFrame() end
        f.CreateTexture = function() return fakeFrame() end
        -- Like a real frame, only methods (capitalized names) exist, other fields stay nil.
        return setmetatable(f, { __index = function(_, k) if type(k) == "string" and k:match("^%u") then return function() end end end })
    end
    W.missingTemplates, W.texts, W.hovers = {}, {}, {}
    _G.CreateFrame = function(_, name, _, template)
        if template and (W.missingTemplates == "all" or W.missingTemplates[template]) then error("Couldn't find inherited node " .. template) end
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
        local function visible()
            local v = {}
            for _, id in ipairs(W.order) do if not W.collapsed[id] then table.insert(v, id) end end
            return v
        end
        _G.C_QuestLog = {
            GetTitleForQuestID = function(id) return W.log[id] and W.log[id].title end,
            IsOnQuest = function(id) return W.log[id] ~= nil end,
            GetQuestWatchType = function(id) if W.untracked[id] then return nil end return 0 end,
            GetNumQuestLogEntries = function() return #visible() + 1 end,
            GetInfo = function(i)
                if i == 1 then return { isHeader = true, title = "Zone header" } end
                local id = visible()[i - 1]
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
    W.cmd("show overview")
    assert(W.lastText and W.lastText:find("Quests logged, 1.", 1, true), "this session in the window")
    assert(not W.lastText:find("|c", 1, true), "color codes stripped")
    W.cmd("show all overview")
    assert(W.lastText:find("Quests logged, 2.", 1, true), "all sessions in the window")
    eq(UISpecialFrames[1], "QuestPaceLogFrame", "Escape closes it")
end)

test("the window still opens when the client lacks the templates", function()
    local W = newWorld()
    W.missingTemplates = "all"
    twoSessions(W)
    W.cmd("show overview")
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
    W.cmd("show all overview")
    assert(not W.saw("couldn't draw"), "visuals drew without an error")
    assert(W.texts["2"], "quests turned in tile")
    assert(W.texts["3:00"], "average per quest tile")
    assert(shown(W, "2 yellow"), "quest color legend")
    assert(shown(W, "100%"), "donut center")
    QuestPaceLogDB.sessions[1].entries[1].colorAtTurnIn = nil
    W.cmd("show all overview")
    assert(shown(W, "1 yellow\n1 not recorded"), "turn-ins from before colors were recorded")
    assert(W.texts["Second Day"] and W.texts["4:00, 25 XP a minute"], "recent quest row with XP a minute")
    W.cmd("show overview")
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
    QuestPaceLogDB.settings = { lens = "overview" }
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
    W.cmd("show overview")
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
    assert(W.saw("Time played at each level, level 8 10:00, level 9 5:00. Estimated"), "level times in the report")
    W.cmd("show overview")
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
    W.cmd("show overview")
    -- OnEnter scripts in creation order. The book button comes first, then
    -- the eight quest rows, and this session's one quest sits in row 1.
    local row = _G.QuestPaceLogRow1
    row.OnEnter(row)
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
    W.cmd("show overview")
    eq(_G.QuestPaceLogFrame.h, 680, "clamped to the screen")
    _G.UIParent = nil
end)

test("sessions before 1.8 estimate time per level from quest levels", function()
    local W = newWorld({ db = { sessions = { { startedAt = 1000, startedAtStr = "old", xpTotal = 900,
        entries = {
            { questID = 1, title = "A", acceptedAt = 1100, acceptedLevel = 5, turnedInAt = 1300, turnedInLevel = 5 },
            { questID = 2, title = "B", acceptedAt = 1500, acceptedLevel = 6, turnedInAt = 1600, turnedInLevel = 6 },
        } } } } })
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.cmd("report all")
    -- Level 5 from the start through 1300 and on to the midpoint 1400, level 6 from there to 1600.
    assert(W.saw("level 5 6:40 (estimated), level 6 3:20 (estimated)"), "estimated level times")
end)

-- 2.0, something for each kind of player.

test("deaths record time dead and time as a ghost", function()
    local W = newWorld()
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.fire("PLAYER_DEAD")
    W.clock = W.clock + 30
    W.ghost = true
    W.fire("PLAYER_ALIVE")
    W.clock = W.clock + 90
    W.ghost = false
    W.fire("PLAYER_UNGHOST")
    local d = QuestPaceLogDB.sessions[1].deaths[1]
    eq(d.zone, "Tirisfal Glades", "where you died")
    eq(d.downSec, 120, "time dead")
    eq(d.ghostSec, 90, "time as a ghost")
    assert(W.saw("Back on your feet after 2:00, 1:30 of it as a ghost."), "chat line")
end)

test("gold gained, spent and from quests", function()
    local W = newWorld()
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.money = 1500
    W.fire("PLAYER_MONEY")
    W.money = 1200
    W.fire("PLAYER_MONEY")
    W.addQuest(950, "Paid Quest", 8)
    W.fire("QUEST_ACCEPTED", 950)
    W.removeQuest(950)
    W.fire("QUEST_TURNED_IN", 950, 100, 250)
    local s = QuestPaceLogDB.sessions[1]
    eq(s.moneyGained, 500, "gained")
    eq(s.moneySpent, 300, "spent")
    eq(s.moneyFromQuests, 250, "from quest rewards")
    eq(s.entries[1].moneyReward, 250, "on the entry")
end)

test("kills counted from your own XP lines, nothing about the target kept", function()
    local W = newWorld()
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.fire("CHAT_MSG_COMBAT_XP_GAIN", "Rattlecage Skeleton dies, you gain 120 experience. (+60 exp Rested bonus)")
    W.fire("CHAT_MSG_COMBAT_XP_GAIN", "You gain 50 experience.")
    local s = QuestPaceLogDB.sessions[1]
    eq(s.kills, 1, "one kill, the plain XP line isn't one")
    eq(s.killXP, 120, "kill XP")
    for k, v in pairs(s) do assert(v ~= "Rattlecage Skeleton", "target name not saved") end
end)

test("discoveries and flight paths from the game's own lines, counted once", function()
    local W = newWorld()
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.fire("CHAT_MSG_SYSTEM", "Discovered Agamand Mills: 70 experience gained")
    W.fire("UI_INFO_MESSAGE", 0, "Discovered Agamand Mills: 70 experience gained")
    W.fire("UI_INFO_MESSAGE", "New flight path discovered!")
    local s = QuestPaceLogDB.sessions[1]
    eq(#s.discoveries, 1, "same line twice counts once")
    eq(s.discoveries[1].name, "Agamand Mills", "place name")
    eq(s.discoveries[1].xp, 70, "discovery XP")
    eq(#s.flightPaths, 1, "flight path")
    W.cmd("report")
    assert(W.saw("Places discovered this session, 1, worth 70 XP. Flight paths learned, 1."), "report line")
end)

test("places and the zones each open quest takes you through", function()
    local W = newWorld()
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.addQuest(960, "Long Walk", 8)
    W.fire("QUEST_ACCEPTED", 960)
    W.zone, W.subZone = "Undercity", "Trade Quarter"
    W.fire("ZONE_CHANGED_NEW_AREA")
    W.zone, W.subZone = "Silverpine Forest", "The Sepulcher"
    W.fire("ZONE_CHANGED_NEW_AREA")
    W.fire("ZONE_CHANGED_NEW_AREA")
    eq(table.concat(QuestPaceLogDB.quests[960].zones, ", "), "Tirisfal Glades, Undercity, Silverpine Forest", "travel")
    assert(QuestPaceLogDB.places["Undercity / Trade Quarter"], "place noted")
end)

test("the quest journal keeps the text of quests you accept", function()
    local W = newWorld()
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.detail = { title = "Story Quest", text = "The dead walk again.", objective = "Kill 8 zombies." }
    W.fire("QUEST_DETAIL")
    W.addQuest(970, "Story Quest", 8)
    W.fire("QUEST_ACCEPTED", 970)
    eq(QuestPaceLogDB.journal[970].text, "The dead walk again.", "text saved")
    W.cmd("journal story")
    assert(W.saw("Story Quest. The dead walk again. Objective, Kill 8 zombies."), "journal command")
end)

test("records cheer when beaten in a later session, and cheer can be turned off", function()
    local W = newWorld()
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.addQuest(980, "Quick", 8)
    W.fire("QUEST_ACCEPTED", 980)
    W.clock = W.clock + 120
    W.removeQuest(980)
    W.fire("QUEST_TURNED_IN", 980, 200, 0)
    eq(QuestPaceLogDB.records.questXPPerMin.value, 100, "first record kept quietly")
    assert(not W.saw("New record"), "no cheer for the very first record")
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.addQuest(981, "Quicker", 8)
    W.fire("QUEST_ACCEPTED", 981)
    W.clock = W.clock + 60
    W.removeQuest(981)
    W.fire("QUEST_TURNED_IN", 981, 300, 0)
    assert(W.saw("New record, best XP a minute on one quest, 300 on Quicker."), "cheer on a beaten record")
    W.cmd("cheer off")
    eq(QuestPaceLogDB.settings.cheer, false, "cheer off saved")
end)

test("level-ups compare against the level before, and goals count down", function()
    local W = newWorld({ level = 8 })
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.cmd("goal 12")
    eq(QuestPaceLogDB.goal.level, 12, "goal saved")
    W.clock = W.clock + 60
    W.level = 9; W.fire("PLAYER_LEVEL_UP", 9)
    W.clock = W.clock + 600
    W.level = 10; W.fire("PLAYER_LEVEL_UP", 10)
    W.clock = W.clock + 300
    W.level = 11; W.fire("PLAYER_LEVEL_UP", 11)
    assert(W.saw("Level 9 took 10:00."), "first full level")
    assert(W.saw("Level 10 took 5:00, 50% faster than level 9."), "against the level before")
    assert(W.saw("1 level to your goal of level 12."), "goal countdown")
    W.cmd("goal 20 2026-10-12")
    eq(QuestPaceLogDB.goal.byStr, "2026-10-12", "goal date")
end)

test("time to the next level from this session's pace", function()
    local W = newWorld()
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.clock = W.clock + 600
    QuestPaceLogDB.sessions[1].xpTotal = 900 -- 90 XP a minute, 900 of 1000 left at 100 XP
    W.cmd("eta")
    assert(W.saw("At this session's pace, level 9 in about 10:00 of play."), "ETA")
end)

test("group quests and dungeon group size are noted", function()
    local W = newWorld()
    _G.C_QuestLog.GetInfo = function(i)
        if i == 1 then return { isHeader = true } end
        local id = W.order[i - 1]
        return id and { questID = id, title = W.log[id].title, level = W.log[id].level, suggestedGroup = 3 }
    end
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.addQuest(990, "Elite Quest", 8)
    W.fire("QUEST_ACCEPTED", 990)
    eq(QuestPaceLogDB.sessions[1].entries[1].suggestedGroup, 3, "suggested group size")
    W.group = 4
    _G.IsInInstance = function() return true, "party" end
    _G.GetInstanceInfo = function() return "Scarlet Monastery", "party", 1, "Normal" end
    W.fire("PLAYER_ENTERING_WORLD", false, false)
    eq(QuestPaceLogDB.sessions[1].dungeons[1].groupSize, 4, "group size in the dungeon")
end)

test("honorable kills since the session began", function()
    local W = newWorld()
    W.hk = 10
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.hk = 13
    W.fire("PLAYER_PVP_KILLS_CHANGED")
    eq(QuestPaceLogDB.sessions[1].honorKills, 3, "three this session")
end)

test("the card is a short summary to copy, nothing is sent", function()
    local W = newWorld()
    twoSessions(W)
    W.cmd("card")
    assert(shown(W, "QuestPaceLog, session of") and shown(W, "1 quests turned in"), "card text in the window")
end)

test("every lens draws, and the window opens on the lens your play leans to", function()
    local W = newWorld()
    twoSessions(W)
    W.fire("CHAT_MSG_COMBAT_XP_GAIN", "Wolf dies, you gain 10 experience.")
    W.clock = W.clock + 900 -- the Compass needs 10 minutes of play
    for _, lens in ipairs({ "achiever", "explorer", "socializer", "competitor", "compass" }) do
        W.cmd("show all " .. lens)
        W.cmd("show " .. lens)
    end
    assert(not W.saw("couldn't draw"), "every lens drew without an error")
    assert(shown(W, "you play most like"), "compass tile")
    assert(shown(W, "Achiever (you)"), "dominant lens marked")
    eq(QuestPaceLogDB.settings.lens, nil, "no choice saved from commands")
    -- A fresh window with no saved choice opens on the Compass's pick.
    local W2 = newWorld({ db = QuestPaceLogDB })
    W2.fire("PLAYER_ENTERING_WORLD", false, true)
    W2.clock = W.clock
    W2.cmd("show")
    eq(_G.QuestPaceLogFrame.lens, "achiever", "opens on the dominant lens")
end)

test("the on-screen tracker shows your lens and the 3 newest open quests with timers", function()
    local W = newWorld()
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    for i, title in ipairs({ "Old", "Middle", "Newer", "Newest" }) do
        W.addQuest(1000 + i, title, 8)
        W.fire("QUEST_ACCEPTED", 1000 + i)
        W.clock = W.clock + 60
    end
    local hud = _G.QuestPaceLogHUD
    hud.OnUpdate(hud, 1.5)
    assert(not W.saw("couldn't update"), "tracker updated without an error")
    assert(W.texts["Quest Pace Log"], "tracker header")
    assert(W.texts["Newest"] and W.texts["1:00"] and W.texts["Middle"] and W.texts["3:00"], "newest three with live timers")
    assert(not W.texts["Old"], "only three quests")
    assert(W.texts["+1 more in your log"], "the rest counted")
    assert(W.texts["Set a goal with /qpl goal 20"], "achiever lines")
    QuestPaceLogDB.settings.hudStats = { kills = true, deaths = true, timers = true }
    hud.OnUpdate(hud, 1.5)
    assert(W.texts["Kills 0, 0 an hour"], "competitor lines")
    W.cmd("hud off")
    eq(hud.shown, false, "hidden")
    W.cmd("hud on")
    eq(hud.shown, true, "shown again")
end)

test("the X closes the dashboard", function()
    local W = newWorld()
    twoSessions(W)
    W.cmd("show overview")
    eq(_G.QuestPaceLogFrame.shown, true, "open")
    _G.QuestPaceLogFrameClose.OnClick()
    eq(_G.QuestPaceLogFrame.shown, false, "closed by the X")
end)

-- 2.2, the welcome window, the Compass suggestion, tracker stats and quest log timers.

-- Runs the once-a-second ticker that handles quest timers and the welcome check.
local function tick(W, n)
    local t = _G.QuestPaceLogTimers
    for _ = 1, n or 1 do t.OnUpdate(t, 1.5) end
end

test("the welcome window opens on first login and choosing a type sets the dashboard's lens", function()
    local W = newWorld()
    twoSessions(W)
    tick(W)
    eq(_G.QuestPaceLogWelcome.shown, true, "welcome opens by itself")
    assert(shown(W, "What kind of player are you?"), "welcome heading")
    assert(shown(W, "Bartle called this type the Killer"), "the four types explained")
    local card = _G.QuestPaceLogWelcomeCard2
    card.OnClick(card)
    assert(shown(W, "Choose Explorer"), "the choose button names the pick")
    _G.QuestPaceLogWelcomeChoose.OnClick()
    eq(QuestPaceLogDB.settings.archetype, "explorer", "type saved")
    eq(QuestPaceLogDB.settings.welcomed, true, "welcome done")
    eq(_G.QuestPaceLogWelcome.shown, false, "welcome closed")
    assert(W.saw("You chose Explorer."), "chat confirms")
    W.cmd("show")
    eq(_G.QuestPaceLogFrame.lens, "explorer", "dashboard opens on the chosen type")
    assert(shown(W, "Explorer (you)"), "chosen type marked on its tab")
    -- Already welcomed, so the next login doesn't open it again.
    _G.QuestPaceLogWelcome = nil
    local W2 = newWorld({ db = QuestPaceLogDB })
    W2.fire("PLAYER_ENTERING_WORLD", false, true)
    tick(W2)
    eq(_G.QuestPaceLogWelcome, nil, "no welcome the second time")
end)

test("letting your play decide, and /qpl type with a name", function()
    local W = newWorld()
    twoSessions(W)
    tick(W)
    _G.QuestPaceLogWelcomeAuto.OnClick()
    eq(QuestPaceLogDB.settings.archetype, "auto", "auto saved")
    W.cmd("type competitor")
    eq(QuestPaceLogDB.settings.archetype, "competitor", "type from the command")
    W.cmd("type wizard")
    assert(W.saw("/qpl type opens the welcome window"), "help for an unknown type")
end)

-- A long session with many quests and nothing else, so the play leans Achiever.
local function achieverDay(W)
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    for i = 1, 20 do
        W.addQuest(2000 + i, "Errand " .. i, 8)
        W.fire("QUEST_ACCEPTED", 2000 + i)
        W.clock = W.clock + 200
        W.removeQuest(2000 + i)
        W.fire("QUEST_TURNED_IN", 2000 + i, 100, 0)
    end
end

test("the Compass suggests switching when your play leans clearly another way, and stays quiet once kept", function()
    local W = newWorld()
    QuestPaceLogDB = { sessions = {}, settings = { archetype = "explorer", welcomed = true } }
    achieverDay(W)
    tick(W)
    assert(W.saw("your play leans Achiever more than Explorer, the type you chose"), "a login hint in chat")
    W.cmd("show compass")
    assert(shown(W, "You chose Explorer, but across all your sessions your play leans Achiever"), "banner on the Compass")
    assert(shown(W, "Keep Explorer"), "keep button")
    _G.QuestPaceLogKeepType.OnClick()
    eq(QuestPaceLogDB.settings.keptType, "explorer>achiever", "choice kept")
    W.texts = {}
    W.cmd("show compass")
    assert(not shown(W, "You chose Explorer, but"), "no banner after keeping")
    QuestPaceLogDB.settings.keptType = nil
    W.cmd("show compass")
    _G.QuestPaceLogSwitchType.OnClick()
    eq(QuestPaceLogDB.settings.archetype, "achiever", "switched")
end)

test("no suggestion before an hour of play", function()
    local W = newWorld()
    QuestPaceLogDB = { sessions = {}, settings = { archetype = "explorer", welcomed = true } }
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    for i = 1, 5 do
        W.addQuest(3000 + i, "Short " .. i, 8)
        W.fire("QUEST_ACCEPTED", 3000 + i)
        W.clock = W.clock + 120
        W.removeQuest(3000 + i)
        W.fire("QUEST_TURNED_IN", 3000 + i, 100, 0)
    end
    tick(W)
    assert(not W.saw("your play leans"), "too early to tell")
end)

test("you pick what the tracker shows in the settings window", function()
    local W = newWorld()
    QuestPaceLogDB = { sessions = {}, settings = { archetype = "achiever", welcomed = true } }
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    local hud = _G.QuestPaceLogHUD
    hud.OnUpdate(hud, 1.5)
    assert(W.texts["Set a goal with /qpl goal 20"], "achiever default shows the goal")
    W.cmd("options")
    eq(_G.QuestPaceLogOptions.shown, true, "settings open")
    local kills = _G.QuestPaceLogOptionsStat_kills
    kills:SetChecked(true)
    kills.OnClick(kills)
    local goal = _G.QuestPaceLogOptionsStat_goal
    goal:SetChecked(false)
    goal.OnClick(goal)
    eq(QuestPaceLogDB.settings.hudStats.kills, true, "kills picked")
    eq(QuestPaceLogDB.settings.hudStats.goal, nil, "goal unpicked")
    eq(QuestPaceLogDB.settings.hudStats.xpbar, true, "the rest of the type's choices kept")
    W.texts = {}
    hud.OnUpdate(hud, 1.5)
    assert(W.texts["Kills 0, 0 an hour"], "kills on the tracker")
    assert(not W.texts["Set a goal with /qpl goal 20"], "goal gone from the tracker")
    _G.QuestPaceLogOptionsReset.OnClick()
    eq(QuestPaceLogDB.settings.hudStats, nil, "back to the type's choices")
    local cheer = _G.QuestPaceLogOptionsCheer
    cheer:SetChecked(false)
    cheer.OnClick(cheer)
    eq(QuestPaceLogDB.settings.cheer, false, "cheer off from settings")
end)

test("the tracker's minus collapses it to its header", function()
    local W = newWorld()
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    local hud = _G.QuestPaceLogHUD
    _G.QuestPaceLogHUDToggle.OnClick()
    eq(QuestPaceLogDB.settings.hudCollapsed, true, "collapsed saved")
    W.texts = {}
    hud.OnUpdate(hud, 1.5)
    assert(W.texts["+"], "plus to expand again")
    assert(not W.texts["Set a goal with /qpl goal 20"], "stats hidden while collapsed")
    _G.QuestPaceLogHUDToggle.OnClick()
    hud.OnUpdate(hud, 1.5)
    assert(W.texts["Set a goal with /qpl goal 20"], "stats back after expanding")
end)

-- A fake piece of the game's UI. Frames have regions and children, font strings have text.
local function fakeFontString(text)
    return { text = text, GetObjectType = function() return "FontString" end,
        GetText = function(self) return self.text end, SetText = function(self, t) self.text = t end }
end
local function fakeUIFrame(fields, regions, children)
    local f = fields or {}
    f.IsVisible = function() return true end
    f.GetRegions = function() return unpack(regions or {}) end
    f.GetChildren = function() return unpack(children or {}) end
    return f
end

test("quest timers in the game's objective tracker and map quest log", function()
    local W = newWorld()
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.addQuest(4001, "A Recipe For Death", 15)
    W.fire("QUEST_ACCEPTED", 4001)
    W.addQuest(4002, "Story Quest", 8)
    W.fire("QUEST_ACCEPTED", 4002)
    W.clock = W.clock + 130
    -- The tracker block carries the quest's ID, the map list only its title.
    local header = fakeFontString("[15] A Recipe For Death")
    local objective = fakeFontString("- 0/1 Berard's Journal")
    local block = fakeUIFrame({ questID = 4001, HeaderText = header }, { header, objective })
    _G.ObjectiveTrackerFrame = fakeUIFrame({}, {}, { block })
    local title = fakeFontString("Story Quest")
    _G.QuestScrollFrame = fakeUIFrame({}, {}, { fakeUIFrame({}, { title }) })
    tick(W)
    eq(header.text, "[15] A Recipe For Death  |cffb4b4b42:10|r", "timer after the tracker title")
    eq(title.text, "Story Quest  |cffb4b4b42:10|r", "timer after the map log title")
    eq(objective.text, "- 0/1 Berard's Journal", "objective lines untouched")
    W.clock = W.clock + 60
    tick(W)
    eq(header.text, "[15] A Recipe For Death  |cffb4b4b43:10|r", "the timer ticks, never doubled")
    -- The game redraws the title, the timer comes back once.
    header.text = "[15] A Recipe For Death"
    tick(W, 5)
    eq(header.text, "[15] A Recipe For Death  |cffb4b4b43:10|r", "restamped after a redraw")
    -- Turned off in settings, the title goes back to the game's own text.
    QuestPaceLogDB.settings.timersInTracker = false
    tick(W, 5)
    eq(header.text, "[15] A Recipe For Death", "tracker timer removed")
    eq(title.text, "Story Quest  |cffb4b4b43:10|r", "map log timer stays")
    _G.ObjectiveTrackerFrame, _G.QuestScrollFrame = nil, nil
end)

test("the game's quest log updates are hooked, and /qpl diag reports what was found", function()
    local W = newWorld()
    _G.hooksecurefunc = function(a, b, c)
        if type(a) == "string" then
            local orig = _G[a]
            _G[a] = function(...) orig(...) b(...) end
        else
            local orig = a[b]
            a[b] = function(...) orig(...) c(...) end
        end
    end
    local title = fakeFontString("Story Quest")
    _G.QuestScrollFrame = fakeUIFrame({}, {}, { fakeUIFrame({}, { title }) })
    _G.QuestLogQuests_Update = function() title.text = "Story Quest" end
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.addQuest(4100, "Story Quest", 8)
    W.fire("QUEST_ACCEPTED", 4100)
    tick(W)
    W.clock = W.clock + 65
    QuestLogQuests_Update()
    eq(title.text, "Story Quest  |cffb4b4b41:05|r", "stamped right after the game's update")
    W.cmd("diag")
    assert(W.saw("Quest frames found, QuestScrollFrame (shown)."), "frames reported")
    assert(W.saw("Hooks attached, QuestLogQuests_Update."), "hooks reported")
    _G.hooksecurefunc, _G.QuestScrollFrame, _G.QuestLogQuests_Update = nil, nil, nil
end)


-- 2.3, quests under a collapsed header, and timers only on tracked quests.

test("a quest under a collapsed zone header isn't dropped, and an old false drop is cleared", function()
    local W = newWorld({ level = 14 })
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.addQuest(600, "Hidden Away", 14)
    W.fire("QUEST_ACCEPTED", 600)
    W.addQuest(601, "In Plain Sight", 14)
    W.fire("QUEST_ACCEPTED", 601)
    W.collapsed[600] = true
    W.level = 15; W.fire("PLAYER_LEVEL_UP", 15)
    eq(QuestPaceLogDB.quests[600].droppedAt, nil, "still in the log, under a collapsed header")
    -- A record wrongly marked dropped before 2.3 gets cleared while the quest is still there.
    QuestPaceLogDB.quests[600].droppedAt, QuestPaceLogDB.quests[600].droppedLevel = 123, 15
    W.level = 16; W.fire("PLAYER_LEVEL_UP", 16)
    eq(QuestPaceLogDB.quests[600].droppedAt, nil, "false drop cleared")
    eq(QuestPaceLogDB.quests[600].droppedLevel, nil, "its level cleared too")
    -- A quest really abandoned is still marked dropped.
    W.removeQuest(601)
    W.level = 17; W.fire("PLAYER_LEVEL_UP", 17)
    eq(QuestPaceLogDB.quests[601].droppedLevel, 17, "a real drop")
end)

test("untracked quests get no timer, in the game's quest log or the addon's tracker", function()
    local W = newWorld()
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.addQuest(610, "Tracked Errand", 8)
    W.fire("QUEST_ACCEPTED", 610)
    W.addQuest(611, "Parked Errand", 8)
    W.fire("QUEST_ACCEPTED", 611)
    W.untracked[611] = true
    W.clock = W.clock + 70
    local tracked, parked = fakeFontString("Tracked Errand"), fakeFontString("[8] Parked Errand")
    _G.QuestScrollFrame = fakeUIFrame({}, {}, { fakeUIFrame({}, { tracked, parked }) })
    tick(W)
    eq(tracked.text, "Tracked Errand  |cffb4b4b41:10|r", "tracked quest ticks")
    eq(parked.text, "[8] Parked Errand", "untracked quest left alone")
    local hud = _G.QuestPaceLogHUD
    hud.OnUpdate(hud, 1.5)
    assert(W.texts["Tracked Errand"] and not W.texts["Parked Errand"], "addon tracker lists only the tracked quest")
    assert(W.texts["+1 more in your log"], "the parked quest still counts as in the log")
    -- Tracking it again brings its timer back.
    W.untracked[611] = nil
    tick(W, 5)
    eq(parked.text, "[8] Parked Errand  |cffb4b4b41:10|r", "timer back once tracked")
    _G.QuestScrollFrame = nil
end)

test("/qpl diag shows the titles it saw under each quest frame", function()
    local W = newWorld()
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.addQuest(620, "Seen Quest", 8)
    W.fire("QUEST_ACCEPTED", 620)
    local title = fakeFontString("[8] Seen Quest")
    _G.ObjectiveTrackerFrame = fakeUIFrame({}, {}, { fakeUIFrame({}, { title, fakeFontString("[9] Someone Else's Quest") }) })
    tick(W)
    W.cmd("diag")
    assert(W.saw("Tracked open quests that get a timer, 1, Seen Quest."), "open quests named")
    assert(W.saw("ObjectiveTrackerFrame, 2 frames, 2 lines of text. With a timer, \"[8] Seen Quest\". Other lines, \"[9] Someone Else's Quest\"."), "lines reported")
    _G.ObjectiveTrackerFrame = nil
end)


test("the dashboard is parchment, from the game's own art when the client has it", function()
    local W = newWorld()
    local fonts = {}
    _G.CreateFont = function(name)
        local f = setmetatable({}, { __index = function() return function() end end })
        f.SetTextColor = function(self, r, g, b) self.color = { r, g, b } end
        fonts[name] = f
        return f
    end
    _G.C_Texture = { GetAtlasInfo = function(name) if name == "questlog-parchment" then return {} end end }
    -- The game fonts the ink fonts copy.
    for _, base in ipairs({ "GameFontHighlightSmall", "GameFontHighlight", "GameFontNormal", "GameFontNormalLarge", "GameFontHighlightLarge" }) do _G[base] = {} end
    twoSessions(W)
    W.cmd("show overview")
    W.cmd("diag")
    assert(W.saw("Parchment, questlog-parchment."), "the game's own parchment art, the first one this client has")
    assert(fonts.QuestPaceLogFont_body and fonts.QuestPaceLogFont_body.color[1] == 0.16, "dark brown ink for body text")
    assert(fonts.QuestPaceLogFont_heading and fonts.QuestPaceLogFont_heading.color[1] == 0.36, "deeper ink for headings")
    _G.CreateFont, _G.C_Texture = nil, nil
    for _, base in ipairs({ "GameFontHighlightSmall", "GameFontHighlight", "GameFontNormal", "GameFontNormalLarge", "GameFontHighlightLarge" }) do _G[base] = nil end
    -- Without any of the game's parchment art, a warm parchment color.
    local W2 = newWorld()
    twoSessions(W2)
    W2.cmd("show overview")
    W2.cmd("diag")
    assert(W2.saw("Parchment, color."), "color fallback")
end)


-- 2.4, quest clocks count only time played with the quest tracked.

local function hudTick()
    local hud = _G.QuestPaceLogHUD
    hud.OnUpdate(hud, 1.5)
end

test("a quest's clock counts only the time it was tracked", function()
    local W = newWorld()
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.addQuest(700, "Clocked", 8)
    W.fire("QUEST_ACCEPTED", 700)
    W.clock = W.clock + 60
    W.untracked[700] = true
    W.fire("QUEST_WATCH_LIST_CHANGED", 700, false)
    W.clock = W.clock + 600
    W.untracked[700] = nil
    W.fire("QUEST_WATCH_LIST_CHANGED", 700, true)
    W.clock = W.clock + 30
    hudTick()
    assert(W.texts["1:30"], "60 seconds before untracking plus 30 after")
    W.removeQuest(700)
    W.fire("QUEST_TURNED_IN", 700, 100, 0)
    local e = QuestPaceLogDB.sessions[1].entries[1]
    eq(e.activeSec, 90, "the clock is kept on the turn-in")
    eq(e.durationSec, 690, "clock time since accepting is unchanged")
end)

test("logging out pauses the clocks, and the time away doesn't count", function()
    local W = newWorld()
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.addQuest(710, "Overnight", 8)
    W.fire("QUEST_ACCEPTED", 710)
    W.clock = W.clock + 100
    W.fire("PLAYER_LOGOUT")
    W.clock = W.clock + 8 * 3600
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.clock = W.clock + 20
    hudTick()
    assert(W.texts["2:00"], "100 seconds before logging out plus 20 after")
end)

test("a session that never logged out stops its clocks at its last activity", function()
    local W = newWorld()
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.addQuest(720, "Crashed", 8)
    W.fire("QUEST_ACCEPTED", 720)
    W.clock = W.clock + 300
    W.fire("PLAYER_XP_UPDATE") -- the last thing that happened before the crash
    W.clock = W.clock + 5 * 3600
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.clock = W.clock + 10
    hudTick()
    assert(W.texts["5:10"], "300 seconds before the crash plus 10 after")
end)

test("quests from before 2.4 start from the time you played since accepting them", function()
    local W = newWorld({ db = { sessions = { { startedAt = 1000, startedAtStr = "old", lastActiveAt = 1600, entries = {} } },
        quests = { [730] = { title = "Border Crossings", acceptedAt = 1100 } } } })
    W.addQuest(730, "Border Crossings", 8)
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    eq(QuestPaceLogDB.quests[730].activeEstimated, true, "marked as an estimate")
    hudTick()
    -- 500 seconds played after accepting in the old session, nothing yet in this one.
    assert(W.texts["~8:20"], "the estimate, marked with ~")
    W.clock = W.clock + 40
    hudTick()
    assert(W.texts["~9:00"], "and it runs from there")
end)


test("tracker titles wrapped in the game's color codes still get their timer", function()
    local W = newWorld()
    W.fire("PLAYER_ENTERING_WORLD", true, false)
    W.addQuest(640, "Arugal's Folly", 15)
    W.fire("QUEST_ACCEPTED", 640)
    W.clock = W.clock + 75
    local header = fakeFontString("|cffffff00[15] Arugal's Folly|r")
    local block = fakeUIFrame({}, { header, fakeFontString("- 0/1 Head of Grimson") })
    -- The quest section is found both inside the tracker and by its own name.
    _G.QuestObjectiveTracker = fakeUIFrame({}, {}, { block })
    _G.ObjectiveTrackerFrame = fakeUIFrame({}, {}, { _G.QuestObjectiveTracker })
    tick(W)
    eq(header.text, "|cffffff00[15] Arugal's Folly|r  |cffb4b4b41:15|r", "timer after the colored title, added once")
    W.cmd("diag")
    assert(W.saw("With a timer, \"[15] Arugal's Folly\""), "diag shows the title as it reads")
    _G.QuestObjectiveTracker, _G.ObjectiveTrackerFrame = nil, nil
end)

io.write(string.format("\n%d passed, %d failed\n", passed, failed))
os.exit(failed == 0 and 0 or 1)
