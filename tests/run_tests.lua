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
    _G.C_UnitAuras = nil
    _G.GetQuestGreenRange = nil
    _G.SlashCmdList = {}
    _G.print = function(msg) table.insert(W.printed, (tostring(msg):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))) end
    local handler
    _G.CreateFrame = function()
        return { RegisterEvent = function() end, SetScript = function(_, _, f) handler = f end }
    end
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

io.write(string.format("\n%d passed, %d failed\n", passed, failed))
os.exit(failed == 0 and 0 or 1)
