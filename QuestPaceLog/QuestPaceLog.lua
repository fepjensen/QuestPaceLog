-- QuestPaceLog
-- Tracks the real-world moment each quest is accepted and turned in,
-- keeps one log per play session, and prints a computed pacing report.
-- Built for the "pace of questing" case study, but works on any character.
--
-- A session starts on its own the moment you log into this character, no
-- command needed. /reload doesn't start a new one, it picks the current
-- session back up, so long as the beta's SavedVariables bug hasn't already
-- wiped it (see the README).
--
-- Besides quests, this also tracks three related things, all from the same
-- kind of self-only, publicly documented event this addon already used.
-- XP. Each quest's own turn-in reward, plus a session-wide split between
--   XP that came from quest turn-ins and XP that came from everything else
--   (kills, first-time discovery, and so on). There's no reliable way to
--   attribute a specific kill's XP to a specific quest, the game doesn't
--   expose that, so this doesn't try to. The session-wide split is the
--   honest version of the same question, how much of your leveling is
--   quest content versus incidental grinding.
-- Dungeons. When you enter and leave one, how long you were inside, and
--   which bosses went down or wiped, from ENCOUNTER_END.
-- Resting. When your character enters and leaves a rested state, in a
--   city, an inn, or near a campfire, and how long each period lasted.
-- Where. The zone and subzone at every accept, turn-in and rest start, so a
--   quest that sends you to another zone shows up as one.
-- Campfires. Watches the player's own buffs for WoW Forever's camp buffs
--   ("Boosted Rest" by default, more with /qpl campbuff add). A rest period
--   in which one arrives is marked as a campfire rest, and its length is how
--   long you stayed at the fire.
-- Groups. When you join and leave a group, how long it held together, and
--   its size over time. Only the count of members, never who they are. Each
--   quest turn-in also notes the group size at that moment, 1 when solo.
-- Quest difficulty. Each quest's own level at accept, the quest log color
--   it had then (red, orange, yellow, green, gray), and, across sessions,
--   the level at which it turned green, turned gray, or was dropped from the
--   log without being turned in.
--
-- Commands.
-- /qpl start          force a new session right now, without logging out
-- /qpl                show the current session's log
-- /qpl report         show a computed summary of the current session
-- /qpl report all     the same summary across every session
-- /qpl show [all]     the summary in a window you can scroll and copy from
-- /qpl skip [name]    mark a quest as backlog, its time won't count toward
--                      pace. No name marks the most recent entry, a name
--                      matches the most recent logged quest containing it.
-- /qpl unskip [name]  undo that, back to counting toward pace. No name
--                      targets the most recently marked backlog quest.
-- /qpl why <a-g> [name] say why a quest was parked. No name tags the most
--                      recent backlog quest that has no reason yet. Letters,
--                      a too hard for my level, b objective scarce or
--                      contested, c out of my route, d needs a group, e not
--                      worth it right now, f just untracked it, g don't
--                      remember.
-- /qpl buffs           list your current buffs, to find camp buff names
-- /qpl campbuff [add|remove <name>]  show or change the camp buffs watched
--
-- Untracking a quest in your quest log (right-click, Stop Tracking, or the
-- checkbox in the tracker) does the same thing as /qpl skip automatically,
-- and tracking it again does the same as /qpl unskip. The commands above are
-- there for a quest that's already turned in, since untracking only works
-- on a quest still open in your log.

QuestPaceLogDB = QuestPaceLogDB or { sessions = {} }

local session = nil

-- On /reload, a session started less than this long ago is treated as the
-- same sitting rather than a new one. Long enough to survive a UI reload,
-- short enough not to glue together two genuinely different play sessions
-- that happen to share a character without a real logout in between.
local RESUME_WINDOW_SEC = 6 * 60 * 60

-- Running totals for XP tracking, reset each login or reload, but what they
-- feed into (session.xpTotal) is saved and survives.
local lastXP, lastXPMax, lastLevelForXP = nil, nil, nil

local function EnsureSessionShape(s)
    s.entries = s.entries or {}
    s.dungeons = s.dungeons or {}
    s.rests = s.rests or {}
    s.campBuffs = s.campBuffs or {}
    s.groups = s.groups or {}
    return s
end

local function InitXPTracking()
    lastXP, lastXPMax, lastLevelForXP = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
end

local function StartSession()
    session = EnsureSessionShape({
        startedAt = time(),
        startedAtStr = date("%Y-%m-%d %H:%M:%S"),
        startLevel = UnitLevel("player"),
        entries = {},
    })
    table.insert(QuestPaceLogDB.sessions, session)
    print("|cff33ff99[QuestPaceLog]|r New session started at " .. session.startedAtStr .. ". Use /qpl for the log, /qpl report for a summary.")
end

local function MostRecentSession()
    local sessions = QuestPaceLogDB.sessions
    if not sessions or #sessions == 0 then return nil end
    return sessions[#sessions]
end

local function ResumeOrStartSession()
    local recent = MostRecentSession()
    if recent and recent.startedAt and (time() - recent.startedAt) < RESUME_WINDOW_SEC then
        session = EnsureSessionShape(recent)
        print("|cff33ff99[QuestPaceLog]|r Reload detected, continuing the session started at " .. (recent.startedAtStr or "?") .. ".")
    else
        -- Either this is the very first reload ever for this character, or the
        -- beta's SavedVariables bug meant nothing came back to resume. Either
        -- way, a fresh session is the only honest option here.
        StartSession()
    end
end

local function GetQuestTitle(questID)
    if C_QuestLog and C_QuestLog.GetTitleForQuestID and questID then
        local title = C_QuestLog.GetTitleForQuestID(questID)
        if title and title ~= "" then
            return title
        end
    end
    return "Unknown quest (" .. tostring(questID) .. ")"
end

local function Elapsed(epoch)
    if not session then return "?" end
    local diff = epoch - session.startedAt
    local m = math.floor(diff / 60)
    local s = diff % 60
    return string.format("%d:%02d", m, s)
end

local function FindEntryToMark(query)
    if not session or #session.entries == 0 then return nil end
    if query and query ~= "" then
        for i = #session.entries, 1, -1 do
            local e = session.entries[i]
            if e.title and e.title:lower():find(query, 1, true) then
                return e
            end
        end
        return nil
    end
    return session.entries[#session.entries]
end

local function MarkBacklog(query)
    local target = FindEntryToMark(query)
    if not target then
        if query and query ~= "" then
            print("|cff33ff99[QuestPaceLog]|r No logged quest matches \"" .. query .. "\".")
        else
            print("|cff33ff99[QuestPaceLog]|r Nothing logged yet to mark.")
        end
        return
    end
    target.backlog = true
    print("|cff33ff99[QuestPaceLog]|r Marked \"" .. target.title .. "\" as backlog, its time won't count toward pace.")
end

local function FindBacklogEntry(query)
    if not session or #session.entries == 0 then return nil end
    for i = #session.entries, 1, -1 do
        local e = session.entries[i]
        if e.backlog and (not query or query == "" or (e.title and e.title:lower():find(query, 1, true))) then
            return e
        end
    end
    return nil
end

local function Unskip(query)
    local target = FindBacklogEntry(query)
    if not target then
        if query and query ~= "" then
            print("|cff33ff99[QuestPaceLog]|r No backlog quest matches \"" .. query .. "\".")
        else
            print("|cff33ff99[QuestPaceLog]|r Nothing is currently marked backlog.")
        end
        return
    end
    target.backlog = nil
    print("|cff33ff99[QuestPaceLog]|r Unmarked \"" .. target.title .. "\", back to counting toward pace.")
end

-- Quest difficulty. The same colors the quest log uses, computed from the
-- quest's own level against yours. Tracked per quest, across sessions, so a
-- quest parked in one session and finished three sessions later still has
-- one record of when it turned green, when it turned gray, and whether it
-- was dropped instead.
local REASONS = {
    a = "too hard for my level",
    b = "objective scarce or contested",
    c = "out of my route",
    d = "needs a group",
    e = "not worth it right now",
    f = "just untracked it",
    g = "don't remember",
}

-- Highest player level at which a quest still isn't gray, per the Classic
-- rules the quest log colors follow. GetQuestGreenRange() is the game's own
-- answer when the client has it, the fallback reproduces the Classic table.
local function GrayLevelFor(playerLevel)
    if playerLevel <= 5 then return 0 end
    if playerLevel <= 39 then return playerLevel - math.floor(playerLevel / 10) - 5 end
    if playerLevel <= 59 then return playerLevel - math.floor(playerLevel / 5) - 1 end
    return playerLevel - 9
end

local function DifficultyOf(questLevel, playerLevel)
    if not questLevel or not playerLevel or questLevel <= 0 then return nil end
    local diff = questLevel - playerLevel
    if diff >= 5 then return "red" end
    if diff >= 3 then return "orange" end
    if diff >= -2 then return "yellow" end
    local grayAtOrBelow
    if GetQuestGreenRange then
        local ok, range = pcall(GetQuestGreenRange)
        if ok and type(range) == "number" then grayAtOrBelow = playerLevel - range - 1 end
    end
    grayAtOrBelow = grayAtOrBelow or GrayLevelFor(playerLevel)
    if questLevel <= grayAtOrBelow then return "gray" end
    return "green"
end

-- Every quest currently in the log, as { [questID] = { title, level } },
-- through whichever quest log API this client exposes.
local function ReadQuestLog()
    local out = {}
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        local n = C_QuestLog.GetNumQuestLogEntries() or 0
        for i = 1, n do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.questID then
                out[info.questID] = { title = info.title, level = info.level }
            end
        end
        return out
    end
    if GetNumQuestLogEntries and GetQuestLogTitle then
        local n = GetNumQuestLogEntries() or 0
        for i = 1, n do
            local title, level, _, isHeader, _, _, _, questID = GetQuestLogTitle(i)
            if title and not isHeader and questID then
                out[questID] = { title = title, level = level }
            end
        end
    end
    return out
end

local function QuestTracker()
    QuestPaceLogDB.quests = QuestPaceLogDB.quests or {}
    return QuestPaceLogDB.quests
end

-- Walk the log and note, for every quest in it, the first moment it turned
-- green and the first moment it turned gray. A quest the tracker knew about
-- that's no longer in the log and was never turned in gets marked dropped.
local function ScanQuestDifficulty(playerLevel)
    playerLevel = playerLevel or UnitLevel("player")
    local tracker = QuestTracker()
    local inLog = ReadQuestLog()
    local now = time()
    for questID, q in pairs(inLog) do
        local rec = tracker[questID]
        if not rec then
            -- Already in the log before this version of the addon saw it.
            rec = { title = q.title, questLevel = q.level, firstSeenAt = now, firstSeenLevel = playerLevel, predatesTracking = true }
            tracker[questID] = rec
        end
        rec.questLevel = rec.questLevel or q.level
        local color = DifficultyOf(rec.questLevel, playerLevel)
        if (color == "green" or color == "gray") and not rec.greenAt then
            rec.greenAt, rec.greenAtLevel = now, playerLevel
        end
        if color == "gray" and not rec.grayAt then
            rec.grayAt, rec.grayAtLevel = now, playerLevel
            print(string.format("|cff33ff99[QuestPaceLog]|r \"%s\" is now gray for you (quest level %d, you're %d).", rec.title or "?", rec.questLevel or 0, playerLevel))
        end
    end
    for questID, rec in pairs(tracker) do
        if not inLog[questID] and not rec.turnedInAt and not rec.droppedAt then
            rec.droppedAt, rec.droppedLevel = now, playerLevel
        end
    end
end

local function QuestLevelFor(questID)
    local q = ReadQuestLog()[questID]
    return q and q.level or nil
end

local function FindEntryAnySession(query)
    local sessions = QuestPaceLogDB.sessions or {}
    for si = #sessions, 1, -1 do
        local entries = sessions[si].entries or {}
        for i = #entries, 1, -1 do
            local e = entries[i]
            if (not query or query == "") and e.backlog and not e.reason then
                return e
            end
            if query and query ~= "" and e.title and e.title:lower():find(query, 1, true) then
                return e
            end
        end
    end
    return nil
end

local function TagReason(rest)
    local letter, query = (rest or ""):match("^(%a)%s*(.-)$")
    letter = letter and letter:lower()
    if not letter or not REASONS[letter] then
        print("|cff33ff99[QuestPaceLog]|r Use /qpl why <letter> [part of the quest name]. Letters, a too hard, b scarce or contested, c out of route, d needs a group, e not worth it now, f just untracked, g don't remember.")
        return
    end
    local target = FindEntryAnySession(query)
    if not target then
        print("|cff33ff99[QuestPaceLog]|r No quest found to tag" .. ((query and query ~= "") and (" matching \"" .. query .. "\".") or ", no untagged backlog quest left."))
        return
    end
    target.reason = letter
    local rec = target.questID and QuestTracker()[target.questID]
    if rec then rec.reason = letter end
    print(string.format("|cff33ff99[QuestPaceLog]|r \"%s\" tagged, %s.", target.title or "?", REASONS[letter]))
end

local function FindOpenEntry(questID)
    for i = #session.entries, 1, -1 do
        if session.entries[i].questID == questID and not session.entries[i].turnedInAt then
            return session.entries[i]
        end
    end
    return nil
end

-- Dungeons. A dungeon entry is "open" from the moment we detect you inside
-- it until we detect you're not, across possibly several PLAYER_ENTERING_WORLD
-- firings (trash pulls and zone-in loading screens inside the same dungeon
-- don't close it, only actually leaving does).
local function CurrentOpenDungeon()
    local list = session.dungeons
    if not list or #list == 0 then return nil end
    local last = list[#list]
    if not last.leftAt then return last end
    return nil
end

local function IsDungeonInstanceType(t)
    return t == "party" or t == "raid"
end

local function CloseDungeon(d)
    local now = time()
    d.leftAt = now
    d.leftAtStr = date("%H:%M:%S", now)
    d.leftLevel = UnitLevel("player")
    d.durationSec = now - d.enteredAt
    print(string.format("|cff33ff99[QuestPaceLog]|r Left %s after %d:%02d", d.name, math.floor(d.durationSec / 60), d.durationSec % 60))
end

local function SyncDungeonState()
    if not session then return end
    local inInstance, instanceType = IsInInstance()
    local openDungeon = CurrentOpenDungeon()

    if inInstance and IsDungeonInstanceType(instanceType) then
        local name, _, _, difficultyName = GetInstanceInfo()
        if not openDungeon or openDungeon.name ~= name then
            if openDungeon then
                CloseDungeon(openDungeon) -- switched dungeons without a clear "outside" moment in between
            end
            local now = time()
            local d = {
                name = name,
                instanceType = instanceType,
                difficultyName = difficultyName,
                enteredAt = now,
                enteredAtStr = date("%H:%M:%S", now),
                enteredLevel = UnitLevel("player"),
                bosses = {},
            }
            table.insert(session.dungeons, d)
            print(string.format("|cff33ff99[QuestPaceLog]|r Entered %s (%s) at level %d", name, difficultyName or instanceType, d.enteredLevel))
        end
    elseif openDungeon then
        CloseDungeon(openDungeon)
    end
end

-- Where the player is, as the game names it. Zone is the big area (Tirisfal
-- Glades), subzone the named spot inside it (Brill, Agamand Mills), mapID
-- the game's own number for the map, when this client exposes it.
local function CurrentZone()
    local zone = GetRealZoneText and GetRealZoneText() or nil
    local sub = GetSubZoneText and GetSubZoneText() or nil
    if zone == "" then zone = nil end
    if sub == "" then sub = nil end
    local mapID
    if C_Map and C_Map.GetBestMapForUnit then
        local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
        if ok then mapID = id end
    end
    return zone, sub, mapID
end

local function ZoneLabel(zone, sub)
    if sub and zone and sub ~= zone then return sub .. ", " .. zone end
    return sub or zone
end

-- Camp buffs. The resting flag below can't tell a campfire from a city or an
-- inn, but sitting at a WoW Forever campfire for a minute grants camp buffs.
-- The names to watch live in QuestPaceLogDB.campBuffNames, lowercase, so
-- they can be added in game with /qpl campbuff add <name> rather than
-- guessed here. A camp buff lasts an hour after you leave the fire, so its
-- own duration says nothing about how long you stayed. What it does is mark
-- the rest period it arrived in as a campfire rest, and that rest period's
-- length is the stay.
local DEFAULT_CAMP_BUFFS = { "boosted rest" }
local activeCampBuffs = {}

local function CampBuffNames()
    if not QuestPaceLogDB.campBuffNames then
        QuestPaceLogDB.campBuffNames = {}
        for _, n in ipairs(DEFAULT_CAMP_BUFFS) do table.insert(QuestPaceLogDB.campBuffNames, n) end
    end
    return QuestPaceLogDB.campBuffNames
end

local function PlayerBuffNames()
    local names = {}
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 40 do
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok or not a then break end
            if a.name then table.insert(names, a.name) end
        end
        return names
    end
    if UnitBuff then
        for i = 1, 40 do
            local name = UnitBuff("player", i)
            if not name then break end
            table.insert(names, name)
        end
    end
    return names
end

local function ActiveCampBuffs()
    local watched = {}
    for _, n in ipairs(CampBuffNames()) do watched[n] = true end
    local active = {}
    for _, name in ipairs(PlayerBuffNames()) do
        if watched[name:lower()] then active[name:lower()] = name end
    end
    return active
end

-- Resting. Cities, inns, sanctuaries, and campfires all set this same flag,
-- IsResting() doesn't distinguish which one. The zone at the start of each
-- rest and the camp buff tag above are what tell them apart.
local function CurrentOpenRest()
    local list = session.rests
    if not list or #list == 0 then return nil end
    local last = list[#list]
    if not last.endedAt then return last end
    return nil
end

local function CloseRest(r)
    local now = time()
    r.endedAt = now
    r.endedAtStr = date("%H:%M:%S", now)
    r.durationSec = now - r.startedAt
    print(string.format("|cff33ff99[QuestPaceLog]|r Resting ends, %d:%02d.", math.floor(r.durationSec / 60), r.durationSec % 60))
end

local function SyncRestState()
    if not session then return end
    local resting = IsResting and IsResting()
    local openRest = CurrentOpenRest()
    if resting and not openRest then
        local now = time()
        local zone, sub = CurrentZone()
        table.insert(session.rests, { startedAt = now, startedAtStr = date("%H:%M:%S", now), zone = zone, subZone = sub })
        print("|cff33ff99[QuestPaceLog]|r Resting begins" .. (ZoneLabel(zone, sub) and (", " .. ZoneLabel(zone, sub)) or "") .. ".")
    elseif not resting and openRest then
        CloseRest(openRest)
    end
end

-- Compares the watched camp buffs now against the last check. A newly gained
-- one is logged, and tags the open rest period as a campfire rest. On login
-- and reload it only takes a snapshot, since a buff already present then was
-- gained at a moment this addon didn't see.
local function SyncCampBuffs(snapshotOnly)
    if not session then return end
    local active = ActiveCampBuffs()
    if not snapshotOnly then
        local now = time()
        for key, name in pairs(active) do
            if not activeCampBuffs[key] then
                local zone, sub = CurrentZone()
                table.insert(session.campBuffs, { name = name, gainedAt = now, gainedAtStr = date("%H:%M:%S", now), zone = zone, subZone = sub })
                local r = CurrentOpenRest()
                if r then
                    r.campfire = true
                    r.campBuff = name
                end
                print("|cff33ff99[QuestPaceLog]|r Camp buff gained, " .. name .. (r and ", this rest counts as a campfire rest." or "."))
            end
        end
        for key in pairs(activeCampBuffs) do
            if not active[key] then
                for i = #session.campBuffs, 1, -1 do
                    local c = session.campBuffs[i]
                    if c.name:lower() == key and not c.endedAt then
                        c.endedAt, c.endedAtStr = now, date("%H:%M:%S", now)
                        break
                    end
                end
            end
        end
    end
    activeCampBuffs = active
end

-- Groups. How many people are in your group, you included, 1 when solo. A
-- count only, the addon never looks at who the other members are.
local function GroupSize()
    if GetNumGroupMembers then
        local ok, n = pcall(GetNumGroupMembers)
        if ok and type(n) == "number" and n > 0 then return n end
        return 1
    end
    -- Older Classic API. The raid count includes you, the party count doesn't.
    local raid = GetNumRaidMembers and GetNumRaidMembers() or 0
    if raid > 0 then return raid end
    return (GetNumPartyMembers and GetNumPartyMembers() or 0) + 1
end

-- Opens a group record on joining, notes each size change, closes it on
-- leaving. atLoad marks a group you were already in at login or reload, so
-- its joinedAt is that moment, not the real join.
local function SyncGroupState(atLoad)
    if not session then return end
    local size = GroupSize()
    local last = session.groups[#session.groups]
    local open = last and not last.leftAt and last or nil
    local now = time()
    if size > 1 and not open then
        local zone, sub = CurrentZone()
        open = { joinedAt = now, joinedAtStr = date("%H:%M:%S", now), joinedLevel = UnitLevel("player"),
            zone = zone, subZone = sub, sizes = {}, maxSize = size, alreadyGrouped = atLoad or nil }
        table.insert(session.groups, open)
        print(string.format("|cff33ff99[QuestPaceLog]|r %s a group of %d.", atLoad and "Already in" or "Joined", size))
    elseif size <= 1 and open then
        open.leftAt, open.leftAtStr, open.durationSec = now, date("%H:%M:%S", now), now - open.joinedAt
        print(string.format("|cff33ff99[QuestPaceLog]|r Left the group after %d:%02d.", math.floor(open.durationSec / 60), open.durationSec % 60))
        return
    end
    if open then
        local lastSize = open.sizes[#open.sizes]
        if not lastSize or lastSize.size ~= size then
            table.insert(open.sizes, { at = now, size = size })
            if size > open.maxSize then open.maxSize = size end
        end
    end
end

local window -- the /qpl show dashboard, built on first use
local PlayedSec, XPPerMinute, LevelTimes

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("QUEST_ACCEPTED")
frame:RegisterEvent("QUEST_TURNED_IN")
frame:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
frame:RegisterEvent("PLAYER_XP_UPDATE")
frame:RegisterEvent("ENCOUNTER_END")
frame:RegisterEvent("PLAYER_UPDATE_RESTING")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("UNIT_AURA")
frame:RegisterEvent("PLAYER_LOGOUT")
-- GROUP_ROSTER_UPDATE on newer clients, the other two on older Classic ones.
-- Registering an event a client doesn't know raises an error, hence pcall.
for _, ev in ipairs({ "GROUP_ROSTER_UPDATE", "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE" }) do
    pcall(frame.RegisterEvent, frame, ev)
end

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        -- Blizzard passes these two flags specifically so an addon can tell
        -- a real login apart from a /reload, and both apart from an ordinary
        -- zone transition, which also fires this event with both false.
        local isInitialLogin, isReloadingUi = ...
        if isInitialLogin then
            StartSession()
            InitXPTracking()
        elseif isReloadingUi then
            ResumeOrStartSession()
            InitXPTracking()
        end
        -- Runs on every firing, including a plain zone change, since that's
        -- exactly when a dungeon is entered or left, or a rest state carries
        -- over from before the reload.
        SyncDungeonState()
        SyncRestState()
        if isInitialLogin or isReloadingUi then
            ScanQuestDifficulty()
            SyncCampBuffs(true)
        end
        SyncGroupState(isInitialLogin or isReloadingUi)
        return
    end

    if not session then
        return -- a quest event landed before PLAYER_ENTERING_WORLD resolved, safety net only
    end
    -- The last moment anything happened, so a session's play time is known
    -- after logout. PLAYER_LOGOUT needs nothing else.
    session.lastActiveAt = time()

    if event == "QUEST_ACCEPTED" then
        local questID = ...
        local title = GetQuestTitle(questID)
        local now = time()
        local level = UnitLevel("player")
        local entry = {
            questID = questID,
            title = title,
            acceptedAt = now,
            acceptedStr = date("%H:%M:%S", now),
            acceptedElapsed = Elapsed(now),
            acceptedLevel = level,
            questLevel = QuestLevelFor(questID),
            turnedInAt = nil,
        }
        table.insert(session.entries, entry)
        local tracker = QuestTracker()
        local rec = tracker[questID]
        if not rec or rec.turnedInAt or rec.droppedAt then
            -- A fresh pick-up, or picking a dropped quest back up, starts a new record.
            rec = { title = title, firstSeenAt = now, firstSeenLevel = level }
            tracker[questID] = rec
        end
        rec.questLevel = rec.questLevel or entry.questLevel
        rec.acceptedAt, rec.acceptedLevel = now, level
        entry.acceptedZone, entry.acceptedSubZone, entry.acceptedMapID = CurrentZone()
        rec.acceptedZone, rec.acceptedSubZone, rec.acceptedMapID = entry.acceptedZone, entry.acceptedSubZone, entry.acceptedMapID
        entry.colorAtAccept = DifficultyOf(entry.questLevel, level)
        local where = ZoneLabel(entry.acceptedZone, entry.acceptedSubZone)
        print(string.format("|cff33ff99[QuestPaceLog]|r %s accepted \"%s\" at level %d%s%s", entry.acceptedElapsed, title, level,
            where and (" in " .. where) or "",
            entry.questLevel and string.format(", quest level %d (%s)", entry.questLevel, entry.colorAtAccept or "?") or ""))

    elseif event == "QUEST_TURNED_IN" then
        local questID, xpReward, moneyReward = ...
        local now = time()
        local level = UnitLevel("player")
        local entry = FindOpenEntry(questID)
        if not entry then
            entry = {
                questID = questID,
                title = GetQuestTitle(questID),
                acceptedAt = nil,
                acceptedStr = nil,
                acceptedElapsed = nil,
                acceptedLevel = nil,
            }
            table.insert(session.entries, entry)
        end
        entry.turnedInAt = now
        entry.turnedInStr = date("%H:%M:%S", now)
        entry.turnedInElapsed = Elapsed(now)
        entry.turnedInLevel = level
        entry.turnedInZone, entry.turnedInSubZone, entry.turnedInMapID = CurrentZone()
        entry.xpReward = xpReward
        entry.turnedInGroupSize = GroupSize()
        local rec = QuestTracker()[questID]
        if rec then
            entry.questLevel = entry.questLevel or rec.questLevel
            rec.turnedInAt, rec.turnedInLevel, rec.xpReward = now, level, xpReward
            rec.turnedInZone, rec.turnedInSubZone, rec.turnedInMapID = entry.turnedInZone, entry.turnedInSubZone, entry.turnedInMapID
            rec.droppedAt, rec.droppedLevel = nil, nil
            rec.turnedInGroupSize = entry.turnedInGroupSize
        end
        entry.colorAtTurnIn = DifficultyOf(entry.questLevel, level)
        if rec then rec.colorAtTurnIn = entry.colorAtTurnIn end
        if entry.acceptedAt then
            entry.durationSec = now - entry.acceptedAt
        end
        if xpReward and xpReward > 0 then
            session.xpFromQuests = (session.xpFromQuests or 0) + xpReward
        end
        local suffix = ""
        if entry.durationSec then
            suffix = string.format(" (took %d:%02d)", math.floor(entry.durationSec / 60), entry.durationSec % 60)
        end
        local xpNote = (xpReward and xpReward > 0) and string.format(", %d xp", xpReward) or ""
        local levelNote
        if entry.acceptedLevel and entry.acceptedLevel ~= level then
            levelNote = string.format(", level %d to %d", entry.acceptedLevel, level)
        else
            levelNote = string.format(" at level %d", level)
        end
        local turnWhere = ZoneLabel(entry.turnedInZone, entry.turnedInSubZone)
        print(string.format("|cff33ff99[QuestPaceLog]|r %s turned in \"%s\"%s%s%s%s%s", entry.turnedInElapsed, entry.title, suffix, xpNote, levelNote,
            turnWhere and (" in " .. turnWhere) or "",
            entry.turnedInGroupSize > 1 and string.format(", in a group of %d", entry.turnedInGroupSize) or ""))
        if window and window:IsShown() then pcall(window.Show_, window.allTime) end

    elseif event == "QUEST_WATCH_LIST_CHANGED" then
        -- Fires whenever a quest is added to or removed from your on-screen
        -- tracker, whether you did it on purpose or the game did it for you
        -- on accept. Only acts on a quest this session actually has open,
        -- and only when tracking state disagrees with the backlog flag, so
        -- this never overrides /qpl skip or /qpl unskip with a no-op.
        local questID, added = ...
        local entry = questID and FindOpenEntry(questID)
        if not entry then return end
        if added == false and not entry.backlog then
            entry.backlog = true
            print("|cff33ff99[QuestPaceLog]|r \"" .. entry.title .. "\" untracked, marked backlog. Say why with /qpl why a-g.")
        elseif added == true and entry.backlog then
            entry.backlog = nil
            print("|cff33ff99[QuestPaceLog]|r \"" .. entry.title .. "\" tracked again, back to counting toward pace.")
        end

    elseif event == "PLAYER_XP_UPDATE" then
        if not lastXP then
            InitXPTracking()
            return
        end
        local newXP, newXPMax, newLevel = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
        if newXPMax and newXPMax > 0 and lastXPMax and lastXPMax > 0 then
            local delta
            if newLevel > lastLevelForXP then
                delta = (lastXPMax - lastXP) + newXP -- one level-up between updates, the common case
            else
                delta = newXP - lastXP
            end
            if delta and delta > 0 then
                session.xpTotal = (session.xpTotal or 0) + delta
            end
        end
        lastXP, lastXPMax, lastLevelForXP = newXP, newXPMax, newLevel

    elseif event == "ENCOUNTER_END" then
        local encounterID, encounterName, difficultyID, groupSize, success = ...
        local openDungeon = CurrentOpenDungeon()
        if openDungeon then
            table.insert(openDungeon.bosses, {
                name = encounterName,
                success = (success == 1),
                at = time(),
            })
            print(string.format("|cff33ff99[QuestPaceLog]|r %s, %s", encounterName, (success == 1) and "down" or "wipe"))
        end

    elseif event == "PLAYER_UPDATE_RESTING" then
        SyncRestState()

    elseif event == "PLAYER_LEVEL_UP" then
        -- The new level arrives as the event's argument, UnitLevel can still
        -- report the old one at this exact moment.
        local newLevel = ...
        session.levelUps = session.levelUps or {}
        table.insert(session.levelUps, { level = newLevel, at = time() })
        ScanQuestDifficulty(newLevel)

    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit == "player" then SyncCampBuffs(false) end

    elseif event == "GROUP_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
        SyncGroupState(false)
    end
end)

local function PrintLog()
    if not session or #session.entries == 0 then
        print("|cff33ff99[QuestPaceLog]|r No quests logged in the current session yet.")
        return
    end
    print(string.format("|cff33ff99[QuestPaceLog]|r Session started %s, %d entries.", session.startedAtStr, #session.entries))
    for i, e in ipairs(session.entries) do
        local levelStr
        if e.acceptedLevel and e.turnedInLevel and e.acceptedLevel ~= e.turnedInLevel then
            levelStr = string.format("level %d to %d", e.acceptedLevel, e.turnedInLevel)
        else
            levelStr = string.format("level %s", tostring(e.turnedInLevel or e.acceptedLevel or "?"))
        end
        local xpStr = (e.xpReward and e.xpReward > 0) and string.format(", %d xp", e.xpReward) or ""
        local turnStr = e.turnedInElapsed and (e.turnedInElapsed .. " turned in" .. ((e.turnedInGroupSize or 1) > 1 and string.format(" in a group of %d", e.turnedInGroupSize) or "")) or "still open"
        local qlvlStr = e.questLevel and string.format(", quest level %d", e.questLevel) or ""
        local reasonStr = e.reason and (", " .. REASONS[e.reason]) or ""
        local fromWhere = ZoneLabel(e.acceptedZone, e.acceptedSubZone)
        local toWhere = ZoneLabel(e.turnedInZone, e.turnedInSubZone)
        local whereStr = ""
        if fromWhere and toWhere and fromWhere ~= toWhere then whereStr = ", " .. fromWhere .. " to " .. toWhere
        elseif fromWhere or toWhere then whereStr = ", " .. (fromWhere or toWhere) end
        reasonStr = reasonStr .. whereStr
        print(string.format("%d) %s accepted, %s, %s%s%s, \"%s\"%s%s", i, e.acceptedElapsed or "?", turnStr, levelStr, qlvlStr, xpStr, e.title, e.backlog and " (backlog)" or "", reasonStr))
    end
end

-- How long a session was played, start to its last recorded moment. Sessions
-- from before 1.7 have no lastActiveAt, so their latest timestamp stands in.
-- The live session runs to now.
function PlayedSec(s)
    local last = s.lastActiveAt or s.startedAt
    if s == session then last = time() end
    if not s.lastActiveAt then
        for _, e in ipairs(s.entries or {}) do last = math.max(last, e.acceptedAt or 0, e.turnedInAt or 0) end
        for _, r in ipairs(s.rests or {}) do last = math.max(last, r.endedAt or r.startedAt or 0) end
        for _, d in ipairs(s.dungeons or {}) do last = math.max(last, d.leftAt or d.enteredAt or 0) end
        for _, g in ipairs(s.groups or {}) do last = math.max(last, g.leftAt or g.joinedAt or 0) end
    end
    return s.startedAt and math.max(0, last - s.startedAt) or nil
end

-- Seconds played at each level, { [level] = seconds }, from sessions that
-- know their starting level (1.8 on). Each session runs from its start
-- through every level-up to its last active moment, so time logged out
-- never counts.
function LevelTimes(s)
    local out = {}
    for _, one in ipairs(s.entryRuns and (QuestPaceLogDB.sessions or {}) or { s }) do
        if one.startLevel and one.startedAt then
            local t0, lvl = one.startedAt, one.startLevel
            for _, lu in ipairs(one.levelUps or {}) do
                out[lvl] = (out[lvl] or 0) + math.max(0, lu.at - t0)
                t0, lvl = lu.at, lu.level
            end
            local last = (one == session) and time() or (one.lastActiveAt or t0)
            out[lvl] = (out[lvl] or 0) + math.max(0, last - t0)
        end
    end
    return out
end

-- XP per minute played, counting only sessions that tracked XP.
function XPPerMinute(s)
    local xp = s.xpTotal or 0
    local played = s.entryRuns and s.xpPlayedSec or (xp > 0 and PlayedSec(s))
    if xp <= 0 or not played or played < 60 then return nil end
    return xp / (played / 60)
end

-- Every session merged into one, for /qpl report all and the window's All
-- sessions view. entryRuns keeps each session's entries apart, so the gap
-- between one session's last turn-in and the next session's first accept,
-- often overnight, never counts as a gap.
local function AllSessions()
    local list = QuestPaceLogDB.sessions or {}
    local all = { entries = {}, dungeons = {}, rests = {}, groups = {}, entryRuns = {}, xpTotal = 0, xpFromQuests = 0, sessionCount = #list }
    all.startedAtStr = list[1] and list[1].startedAtStr or "?"
    for _, one in ipairs(list) do
        for _, k in ipairs({ "entries", "dungeons", "rests", "groups" }) do
            for _, v in ipairs(one[k] or {}) do table.insert(all[k], v) end
        end
        table.insert(all.entryRuns, one.entries or {})
        all.xpTotal = all.xpTotal + (one.xpTotal or 0)
        all.xpFromQuests = all.xpFromQuests + (one.xpFromQuests or 0)
        if (one.xpTotal or 0) > 0 then all.xpPlayedSec = (all.xpPlayedSec or 0) + (PlayedSec(one) or 0) end
    end
    return all
end

-- The report as a list of lines, for chat and for the window. s is the
-- current session, or AllSessions() when allTime is true.
local function ReportLines(s, allTime)
    local out = {}
    local function add(line) table.insert(out, line) end
    local scope = allTime and "across all sessions" or "this session"
    -- Notes like "still resting" only make sense live. A record left open by
    -- an old session's logout isn't still going.
    local live = not allTime
    if not s or (#s.entries == 0 and #s.dungeons == 0 and #s.rests == 0 and #s.groups == 0 and (s.xpTotal or 0) == 0) then
        add("|cff33ff99[QuestPaceLog]|r Nothing to report yet.")
        return out
    end

    local closed, backlogCount = {}, 0
    for _, e in ipairs(s.entries) do
        if e.backlog then
            backlogCount = backlogCount + 1
        elseif e.durationSec then
            table.insert(closed, e)
        end
    end

    if allTime then
        add(string.format("|cff33ff99[QuestPaceLog] Report|r, all %d sessions since %s", s.sessionCount, s.startedAtStr))
    else
        add(string.format("|cff33ff99[QuestPaceLog] Report|r, session started %s", s.startedAtStr))
    end
    add(string.format("Quests logged, %d. Quests with both a start and end time, %d%s.", #s.entries, #closed,
        backlogCount > 0 and string.format(" (%d more marked backlog, not counted here)", backlogCount) or ""))

    if #closed > 0 then
        local total, longest, shortest = 0, closed[1], closed[1]
        for _, e in ipairs(closed) do
            total = total + e.durationSec
            if e.durationSec > longest.durationSec then longest = e end
            if e.durationSec < shortest.durationSec then shortest = e end
        end
        local avg = total / #closed
        add(string.format("Average time per quest, %d:%02d.", math.floor(avg / 60), avg % 60))
        add(string.format("Longest, \"%s\" at %d:%02d. Shortest, \"%s\" at %d:%02d.",
            longest.title, math.floor(longest.durationSec / 60), longest.durationSec % 60,
            shortest.title, math.floor(shortest.durationSec / 60), shortest.durationSec % 60))
    end

    -- Gap between one quest's turn-in and the next quest's accept, a rough proxy
    -- for travel or idle time. It is not a felt-pacing judgment, keep tagging that by hand.
    local gaps = {}
    for _, entries in ipairs(s.entryRuns or { s.entries }) do
        for i = 2, #entries do
            local prev, cur = entries[i - 1], entries[i]
            if not prev.backlog and not cur.backlog and prev.turnedInAt and cur.acceptedAt and cur.acceptedAt > prev.turnedInAt then
                table.insert(gaps, cur.acceptedAt - prev.turnedInAt)
            end
        end
    end
    if #gaps > 0 then
        local gapTotal = 0
        for _, g in ipairs(gaps) do gapTotal = gapTotal + g end
        local gapAvg = gapTotal / #gaps
        add(string.format("Gaps measured between a turn-in and the next accept, %d, average %d:%02d.", #gaps, math.floor(gapAvg / 60), gapAvg % 60))
    end

    local levelUps = 0
    for _, e in ipairs(s.entries) do
        if e.acceptedLevel and e.turnedInLevel and e.turnedInLevel > e.acceptedLevel then
            levelUps = levelUps + 1
        end
    end
    if levelUps > 0 then
        add(string.format("Quests during which you leveled up, %d.", levelUps))
    end

    -- XP. The per-quest reward is exact, straight off the turn-in event. The
    -- split below is the honest version of "how much came from monsters,"
    -- since nothing tells this addon which kill fed which quest.
    local xpTotal = s.xpTotal or 0
    if xpTotal > 0 then
        local xpFromQuests = s.xpFromQuests or 0
        local xpOther = xpTotal - xpFromQuests
        local pctQuest = (xpFromQuests / xpTotal) * 100
        add(string.format("XP earned %s, %d total, %d from quest turn-ins (%d%%), %d from everything else, kills, first-time discovery, and so on.",
            scope, xpTotal, xpFromQuests, math.floor(pctQuest + 0.5), xpOther))
        local perMin = XPPerMinute(s)
        if perMin then add(string.format("XP per minute played, %d.", math.floor(perMin + 0.5))) end
    end

    -- Dungeons.
    if s.dungeons and #s.dungeons > 0 then
        add(string.format("Dungeons %s, %d.", scope, #s.dungeons))
        for _, d in ipairs(s.dungeons) do
            local kills, wipes = 0, 0
            for _, b in ipairs(d.bosses or {}) do
                if b.success then kills = kills + 1 else wipes = wipes + 1 end
            end
            if d.leftAt then
                local levelNote = (d.enteredLevel ~= d.leftLevel) and string.format(", level %d to %d", d.enteredLevel, d.leftLevel) or ""
                add(string.format("  %s (%s), %d:%02d, %d boss(es) down, %d wipe(s)%s",
                    d.name, d.difficultyName or d.instanceType, math.floor(d.durationSec / 60), d.durationSec % 60, kills, wipes, levelNote))
            elseif live then
                add(string.format("  %s (%s), still inside, entered at %s", d.name, d.difficultyName or d.instanceType, d.enteredAtStr))
            end
        end
    end

    -- Resting.
    if s.rests and #s.rests > 0 then
        local totalRest, closedRests = 0, 0
        for _, r in ipairs(s.rests) do
            if r.durationSec then
                totalRest = totalRest + r.durationSec
                closedRests = closedRests + 1
            end
        end
        if closedRests > 0 then
            add(string.format("Rest periods %s, %d, totaling %d:%02d%s.", scope, #s.rests,
                math.floor(totalRest / 60), totalRest % 60, (live and #s.rests > closedRests) and " (still resting)" or ""))
        elseif live then
            add(string.format("Rest periods this session, %d, still resting.", #s.rests))
        end
        local campCount, campTotal = 0, 0
        for _, r in ipairs(s.rests) do
            if r.campfire and r.durationSec then
                campCount = campCount + 1
                campTotal = campTotal + r.durationSec
            end
        end
        if campCount > 0 then
            local avg = campTotal / campCount
            add(string.format("Of those, at a campfire, %d, averaging %d:%02d per stay.", campCount, math.floor(avg / 60), avg % 60))
        end
    end

    -- Groups.
    if #s.groups > 0 then
        local closedGroups, groupTotal, largest = 0, 0, 0
        for _, g in ipairs(s.groups) do
            if g.durationSec then closedGroups, groupTotal = closedGroups + 1, groupTotal + g.durationSec end
            if g.maxSize > largest then largest = g.maxSize end
        end
        local avg = closedGroups > 0 and groupTotal / closedGroups or 0
        add(string.format("Groups %s, %d, largest %d%s%s.", scope, #s.groups, largest,
            closedGroups > 0 and string.format(", average %d:%02d together", math.floor(avg / 60), avg % 60) or "",
            (live and #s.groups > closedGroups) and ", still grouped" or ""))
    end
    local turnedIn, grouped = 0, 0
    for _, e in ipairs(s.entries) do
        if e.turnedInGroupSize then
            turnedIn = turnedIn + 1
            if e.turnedInGroupSize > 1 then grouped = grouped + 1 end
        end
    end
    if grouped > 0 then
        add(string.format("Quests turned in while grouped, %d of %d.", grouped, turnedIn))
    end

    -- Time at each level.
    local levels, parts = LevelTimes(s), {}
    for lvl, sec in pairs(levels) do table.insert(parts, { lvl, sec }) end
    table.sort(parts, function(a, b) return a[1] < b[1] end)
    if #parts > 0 then
        local strs = {}
        for _, p in ipairs(parts) do table.insert(strs, string.format("level %d %d:%02d", p[1], math.floor(p[2] / 60), p[2] % 60)) end
        add("Time played at each level, " .. table.concat(strs, ", ") .. ".")
    end

    -- Quest difficulty, across every session, not only this one.
    local tracked, wentGray, grayThenDone, dropped = 0, 0, 0, 0
    for _, rec in pairs(QuestTracker()) do
        tracked = tracked + 1
        if rec.grayAt then
            wentGray = wentGray + 1
            if rec.turnedInAt and rec.turnedInAt >= rec.grayAt then grayThenDone = grayThenDone + 1 end
        end
        if rec.droppedAt then dropped = dropped + 1 end
    end
    if tracked > 0 then
        add(string.format("Quests tracked for difficulty, %d. Went gray while still in your log, %d (%d of those turned in anyway). Dropped without turning in, %d.",
            tracked, wentGray, grayThenDone, dropped))
    end

    add("|cff33ff99[QuestPaceLog]|r Raw data is also saved in your SavedVariables file. Paste this report, or that file's contents, back into the project and it becomes a written case study.")
    return out
end

local function PrintReport(allTime)
    for _, line in ipairs(ReportLines(allTime and AllSessions() or session, allTime)) do print(line) end
end

-- The dashboard window, /qpl show. Tiles, donuts and bars for a quick look
-- while playing, and below them the full report, which you can scroll,
-- select and copy from. Built on first use, with every template call
-- wrapped in pcall, so a client missing a template gets a plainer window
-- instead of an error, and logging is never affected.
local function TryCreate(kind, name, parent, template)
    local ok, f = pcall(CreateFrame, kind, name, parent, template)
    if ok and f then return f, true end
    return CreateFrame(kind, nil, parent), false
end

-- The numbers the tiles, donuts and bars show, for a session or AllSessions().
local function DashboardStats(s)
    local st = { done = 0, closedCount = 0, closedTotal = 0, xpTotal = s.xpTotal or 0, xpFromQuests = s.xpFromQuests or 0,
        restSec = 0, campStays = 0, colors = {}, recent = {}, solo = 0, grouped = 0, playedSec = 0 }
    for _, e in ipairs(s.entries) do
        if e.turnedInAt then st.done = st.done + 1 end
        if e.colorAtTurnIn then st.colors[e.colorAtTurnIn] = (st.colors[e.colorAtTurnIn] or 0) + 1 end
        if e.turnedInGroupSize then
            if e.turnedInGroupSize > 1 then st.grouped = st.grouped + 1 else st.solo = st.solo + 1 end
        end
        if e.durationSec and not e.backlog then
            st.closedCount, st.closedTotal = st.closedCount + 1, st.closedTotal + e.durationSec
            table.insert(st.recent, e)
        end
    end
    while #st.recent > 8 do table.remove(st.recent, 1) end
    for _, r in ipairs(s.rests) do
        if r.durationSec then
            st.restSec = st.restSec + r.durationSec
            if r.campfire then st.campStays = st.campStays + 1 end
        end
    end
    if s.entryRuns then
        for _, one in ipairs(QuestPaceLogDB.sessions or {}) do st.playedSec = st.playedSec + (PlayedSec(one) or 0) end
    else
        st.playedSec = PlayedSec(s) or 0
    end
    st.xpPerMin = XPPerMinute(s)
    st.levelTimes = LevelTimes(s)
    return st
end

local function Clock(sec)
    sec = math.floor(sec)
    if sec >= 3600 then return string.format("%d:%02d:%02d", math.floor(sec / 3600), math.floor(sec % 3600 / 60), sec % 60) end
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

-- 25090 becomes 25,090.
local function Thousands(n)
    local s = tostring(math.floor(n + 0.5))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

local QUEST_COLORS = {
    { "red", 1, 0.1, 0.1 }, { "orange", 1, 0.5, 0.25 }, { "yellow", 1, 1, 0 }, { "green", 0.25, 0.75, 0.25 }, { "gray", 0.5, 0.5, 0.5 },
}
local GOLD, SLATE, VIOLET = { 1, 0.82, 0 }, { 0.42, 0.45, 0.52 }, { 0.62, 0.45, 1 }
local WIN_W, WIN_H, PAD = 780, 820, 16
local INNER = WIN_W - PAD * 2
local BAR_LEFT, BAR_MAX = 300, 300
local DONUT_DOTS, DONUT_R, DONUT_THICK = 96, 40, 13

-- 1h05 or 42m, for the narrow level columns.
local function Short(sec)
    if sec >= 3600 then return string.format("%dh%02d", math.floor(sec / 3600), math.floor(sec % 3600 / 60)) end
    return string.format("%dm", math.floor(sec / 60))
end

local function BuildWindow()
    local f, styled = TryCreate("Frame", "QuestPaceLogFrame", UIParent, "BasicFrameTemplateWithInset")
    -- No taller than the screen. The corner grip makes it taller or shorter.
    local height, screenH = WIN_H, UIParent and UIParent.GetHeight and UIParent:GetHeight()
    if type(screenH) == "number" and screenH > 0 then height = math.min(WIN_H, screenH - 20) end
    f:SetSize(WIN_W, height)
    f:SetResizable(true)
    if not (f.SetResizeBounds and pcall(f.SetResizeBounds, f, WIN_W, 560, WIN_W, 2000)) then
        if f.SetMinResize then pcall(f.SetMinResize, f, WIN_W, 560) end
        if f.SetMaxResize then pcall(f.SetMaxResize, f, WIN_W, 2000) end
    end
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if not styled then
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.85)
        local close = TryCreate("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT")
        close:SetScript("OnClick", function() f:Hide() end)
    end
    if UISpecialFrames then table.insert(UISpecialFrames, "QuestPaceLogFrame") end -- Escape closes it

    local function text(x, y, template, point)
        local fs = f:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
        fs:SetPoint(point or "TOPLEFT", x, y)
        return fs
    end
    local function box(x, y, w, h, c, a)
        local t = f:CreateTexture(nil, "ARTWORK")
        t:SetPoint("TOPLEFT", x, y)
        t:SetSize(w, h)
        t:SetColorTexture(c[1], c[2], c[3], a or 1)
        return t
    end
    -- Moves a bar to its spot and width, hidden when it has nothing to show.
    local function place(t, x, y, w)
        if w < 1 then t:Hide() return end
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", x, y)
        t:SetWidth(w)
        t:Show()
    end
    local function heading(y, label)
        text(PAD, y, "GameFontNormal"):SetText(label)
        box(PAD, y - 16, INNER, 1, GOLD, 0.25)
    end

    text(0, -6, "GameFontHighlight", "TOP"):SetText("Quest Pace Log")

    local tabs = {}
    local function tab(label, x, allTime)
        local b = TryCreate("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(130, 22)
        b:SetPoint("TOPLEFT", x, -32)
        b:SetText(label)
        b:SetScript("OnClick", function() f.Show_(allTime) end)
        tabs[allTime] = b
    end
    tab("This session", PAD, false)
    tab("All sessions", PAD + 138, true)
    local scopeText = text(-PAD - 4, -38, "GameFontNormalSmall", "TOPRIGHT")

    -- Five tiles, each with a gold line on top.
    local tiles, tileW = {}, (INNER - 4 * 8) / 5
    for i = 1, 5 do
        local x = PAD + (i - 1) * (tileW + 8)
        box(x, -64, tileW, 58, { 1, 1, 1 }, 0.06)
        box(x, -64, tileW, 2, GOLD, 0.8)
        tiles[i] = { value = text(x + 10, -74, "GameFontNormalLarge"), label = text(x + 10, -100) }
    end

    -- Donuts. A ring of short bars around a circle, each colored by the
    -- share of the whole it falls in. Plain color textures only, rotated
    -- to follow the ring when the client can rotate them.
    local function donut(cx, cy, title)
        local d = { dots = {} }
        text(cx, cy + DONUT_R + 26, "GameFontNormalSmall", "CENTER"):SetText(title)
        local seg = 2 * math.pi * DONUT_R / DONUT_DOTS + 1.5
        for i = 1, DONUT_DOTS do
            local angle = math.pi / 2 - (i - 0.5) / DONUT_DOTS * 2 * math.pi
            local t = f:CreateTexture(nil, "ARTWORK")
            t:SetSize(seg, DONUT_THICK)
            t:SetPoint("CENTER", f, "TOPLEFT", cx + DONUT_R * math.cos(angle), cy + DONUT_R * math.sin(angle))
            if t.SetRotation then pcall(t.SetRotation, t, angle - math.pi / 2) end
            d.dots[i] = t
        end
        d.center = text(cx, cy, "GameFontNormalLarge", "CENTER")
        d.legend = text(cx + DONUT_R + 22, cy + 20)
        d.legend:SetJustifyH("LEFT")
        return d
    end
    -- parts is a list of { count, color, label }. The center shows the first part's share.
    local function fill(d, parts, emptyNote, extra)
        local total = 0
        for _, p in ipairs(parts) do total = total + p[1] end
        for i, t in ipairs(d.dots) do
            local c, a = SLATE, 0.25
            if total > 0 then
                local at, sum = (i - 0.5) / DONUT_DOTS * total, 0
                for _, p in ipairs(parts) do
                    sum = sum + p[1]
                    if at <= sum then c, a = p[2], 1 break end
                end
            end
            t:SetColorTexture(c[1], c[2], c[3], a)
        end
        d.center:SetText(total > 0 and (math.floor(parts[1][1] / total * 100 + 0.5) .. "%") or "")
        local lines = {}
        for _, p in ipairs(parts) do
            if p[1] > 0 then
                table.insert(lines, string.format("|cff%02x%02x%02x%s|r %s", math.floor(p[2][1] * 255), math.floor(p[2][2] * 255), math.floor(p[2][3] * 255), Thousands(p[1]), p[3]))
            end
        end
        if #lines > 0 and extra then table.insert(lines, extra) end
        d.legend:SetText(#lines > 0 and table.concat(lines, "\n") or emptyNote)
    end

    heading(-136, "Where your XP, quest colors and turn-ins come from")
    local colW = INNER / 3
    local donuts = {
        xp = donut(PAD + 60, -222, "XP"),
        colors = donut(PAD + colW + 60, -222, "Quest color at turn-in"),
        group = donut(PAD + 2 * colW + 60, -222, "Solo or grouped"),
    }

    -- Recent quests, newest at the bottom, bar length against the longest,
    -- colored the way the quest log colored the quest at turn-in.
    heading(-300, "Last finished quests")
    local rows = {}
    for i = 1, 8 do
        local y = -324 - (i - 1) * 20
        local name = text(PAD, y)
        name:SetWidth(BAR_LEFT - PAD - 10)
        name:SetJustifyH("LEFT")
        if name.SetWordWrap then name:SetWordWrap(false) end
        -- An invisible strip over the row, so hovering shows the quest's details.
        local hit = CreateFrame("Frame", nil, f)
        hit:SetPoint("TOPLEFT", PAD, y + 3)
        hit:SetSize(INNER, 18)
        hit:EnableMouse(true)
        local row = { name = name, bar = box(BAR_LEFT, y - 1, 1, 12, { 0.3, 0.6, 1 }), time = text(BAR_LEFT, y), hit = hit }
        hit:SetScript("OnEnter", function(self)
            local e = row.e
            if not e or not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            GameTooltip:SetText(e.title or "?")
            if e.questLevel then GameTooltip:AddLine(string.format("Quest level %d, %s at turn-in", e.questLevel, e.colorAtTurnIn or "no color recorded"), 1, 1, 1) end
            if e.acceptedLevel and e.turnedInLevel and e.acceptedLevel ~= e.turnedInLevel then
                GameTooltip:AddLine(string.format("You went from level %d to %d", e.acceptedLevel, e.turnedInLevel), 1, 1, 1)
            elseif e.turnedInLevel then
                GameTooltip:AddLine(string.format("You were level %d", e.turnedInLevel), 1, 1, 1)
            end
            local from, to = ZoneLabel(e.acceptedZone, e.acceptedSubZone), ZoneLabel(e.turnedInZone, e.turnedInSubZone)
            if from and to and from ~= to then GameTooltip:AddLine("From " .. from .. " to " .. to, 1, 1, 1)
            elseif from or to then GameTooltip:AddLine("In " .. (from or to), 1, 1, 1) end
            local xp = (e.xpReward and e.xpReward > 0) and e.xpReward or nil
            GameTooltip:AddLine(Clock(e.durationSec) .. (xp and string.format(", %s XP, %s XP a minute", Thousands(xp), Thousands(xp / math.max(1, e.durationSec / 60))) or ""), 1, 1, 1)
            if (e.turnedInGroupSize or 1) > 1 then GameTooltip:AddLine(string.format("In a group of %d", e.turnedInGroupSize), 1, 1, 1) end
            GameTooltip:Show()
        end)
        hit:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        rows[i] = row
    end

    -- Time at each level, one column per level, newest levels on the right.
    heading(-494, "Time played at each level")
    local LEVEL_BASE, LEVEL_MAX_H, LEVEL_COLS = -580, 50, 20
    local levelCols = {}
    for i = 1, LEVEL_COLS do
        levelCols[i] = { bar = box(PAD, LEVEL_BASE, 1, 1, GOLD, 0.85), time = text(0, 0, "GameFontHighlightSmall", "CENTER"), level = text(0, 0, "GameFontNormalSmall", "CENTER") }
    end
    local levelNote = text(PAD, -520)

    heading(-612, "Full report")
    local scroll = TryCreate("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", PAD, -636)
    scroll:SetPoint("BOTTOMRIGHT", -PAD - 22, 14)
    local report = CreateFrame("EditBox", nil, scroll)
    report:SetMultiLine(true)
    report:SetAutoFocus(false)
    report:SetFontObject("GameFontHighlightSmall")
    report:SetWidth(INNER - 30)
    report:SetScript("OnEscapePressed", function() f:Hide() end)
    scroll:SetScrollChild(report)

    function f.UpdateVisuals(st)
        local avg = st.closedCount > 0 and st.closedTotal / st.closedCount or nil
        tiles[1].value:SetText(tostring(st.done)); tiles[1].label:SetText("quests turned in")
        tiles[2].value:SetText(avg and Clock(avg) or "none yet"); tiles[2].label:SetText("average per quest")
        tiles[3].value:SetText(st.xpPerMin and Thousands(st.xpPerMin) or "none yet"); tiles[3].label:SetText("XP per minute played")
        tiles[4].value:SetText(Clock(st.playedSec)); tiles[4].label:SetText("time played")
        tiles[5].value:SetText(Clock(st.restSec)); tiles[5].label:SetText(string.format("resting, %d at campfires", st.campStays))

        fill(donuts.xp, { { st.xpFromQuests, GOLD, "from quests" }, { math.max(0, st.xpTotal - st.xpFromQuests), SLATE, "from everything else" } }, "No XP gained yet.")
        local colorParts, colored = {}, 0
        for _, c in ipairs(QUEST_COLORS) do
            local n = st.colors[c[1]] or 0
            colored = colored + n
            table.insert(colorParts, { n, { c[2], c[3], c[4] }, c[1] })
        end
        -- Sort so the center shows the most common color.
        table.sort(colorParts, function(a, b) return a[1] > b[1] end)
        -- Colors are recorded from 1.1 on, so older turn-ins have none.
        fill(donuts.colors, colorParts, "No quests turned in yet.",
            (colored > 0 and st.done > colored) and ((st.done - colored) .. " without a recorded color") or nil)
        fill(donuts.group, { { st.grouped, VIOLET, "in a group" }, { st.solo, SLATE, "solo" } }, "No turn-ins since 1.3.")

        local levels = {}
        for lvl, sec in pairs(st.levelTimes) do table.insert(levels, { lvl, sec }) end
        table.sort(levels, function(a, b) return a[1] < b[1] end)
        while #levels > LEVEL_COLS do table.remove(levels, 1) end
        local most = 1
        for _, l in ipairs(levels) do if l[2] > most then most = l[2] end end
        local colW = math.min(36, math.floor(INNER / math.max(1, #levels)))
        levelNote:SetText(#levels == 0 and "Recording starts with version 1.8. Sessions before it don't know when you leveled." or "")
        for i, col in ipairs(levelCols) do
            local l = levels[i]
            if l then
                local x, h = PAD + (i - 1) * colW, math.max(2, math.floor(LEVEL_MAX_H * l[2] / most))
                col.bar:ClearAllPoints()
                col.bar:SetPoint("BOTTOMLEFT", f, "TOPLEFT", x + 3, LEVEL_BASE)
                col.bar:SetSize(colW - 6, h)
                col.time:ClearAllPoints()
                col.time:SetPoint("CENTER", f, "TOPLEFT", x + colW / 2, LEVEL_BASE + h + 8)
                col.time:SetText(Short(l[2]))
                col.level:ClearAllPoints()
                col.level:SetPoint("CENTER", f, "TOPLEFT", x + colW / 2, LEVEL_BASE - 10)
                col.level:SetText(tostring(l[1]))
                col.bar:Show(); col.time:Show(); col.level:Show()
            else
                col.bar:Hide(); col.time:Hide(); col.level:Hide()
            end
        end

        local longest = 1
        for _, e in ipairs(st.recent) do if e.durationSec > longest then longest = e.durationSec end end
        for i, row in ipairs(rows) do
            local e = st.recent[i]
            if e then
                local y = -324 - (i - 1) * 20
                local w = math.max(2, math.floor(BAR_MAX * e.durationSec / longest))
                local color = { 0.3, 0.6, 1 }
                for _, c in ipairs(QUEST_COLORS) do if c[1] == e.colorAtTurnIn then color = { c[2], c[3], c[4] } end end
                row.name:SetText(e.title or "?")
                row.bar:SetColorTexture(color[1], color[2], color[3], 1)
                place(row.bar, BAR_LEFT, y - 1, w)
                row.time:ClearAllPoints()
                row.time:SetPoint("TOPLEFT", BAR_LEFT + w + 6, y)
                local perMin = (e.xpReward and e.xpReward > 0 and e.durationSec >= 60) and string.format(", %s XP a minute", Thousands(e.xpReward / (e.durationSec / 60))) or ""
                row.time:SetText(Clock(e.durationSec) .. perMin)
                row.e = e
                row.name:Show(); row.time:Show(); row.hit:Show()
            else
                row.e = nil
                row.name:Hide(); row.bar:Hide(); row.time:Hide(); row.hit:Hide()
            end
        end
    end

    function f.Show_(allTime)
        f.allTime = allTime
        local s = allTime and AllSessions() or session
        scopeText:SetText(allTime and "Showing all sessions" or "Showing this session")
        for which, b in pairs(tabs) do
            if which == allTime then b:LockHighlight() else b:UnlockHighlight() end
        end
        if s then
            local ok, err = pcall(f.UpdateVisuals, DashboardStats(s))
            if not ok and not f.warned then
                f.warned = true
                print("|cff33ff99[QuestPaceLog]|r The tiles and charts couldn't draw, " .. tostring(err) .. ". The report below them still works.")
            end
        end
        local plain = table.concat(ReportLines(s, allTime), "\n"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        report:SetText(plain)
        f:Show()
    end
    return f
end

local function ShowWindow(allTime)
    if not window then
        local ok, f = pcall(BuildWindow)
        if not ok then
            print("|cff33ff99[QuestPaceLog]|r The window couldn't open on this client, " .. tostring(f) .. ". /qpl report still works.")
            return
        end
        window = f
    end
    window.Show_(allTime)
end

-- A small book button by the minimap. Left-click opens or closes the
-- dashboard, drag moves it. The client keeps its spot in its own layout
-- cache (SetUserPlaced), so no saved field is needed for it.
local buttonOk, buttonErr = pcall(function()
    local b = CreateFrame("Button", "QuestPaceLogButton", UIParent)
    b:SetSize(28, 28)
    b:SetFrameStrata("MEDIUM")
    if Minimap then b:SetPoint("TOPRIGHT", Minimap, "BOTTOMLEFT", 8, 8) else b:SetPoint("RIGHT", -40, 0) end
    b:SetNormalTexture("Interface\\Icons\\INV_Misc_Book_09")
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    b:SetMovable(true)
    b:SetClampedToScreen(true)
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", b.StartMoving)
    b:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); self:SetUserPlaced(true) end)
    b:SetScript("OnClick", function()
        if window and window:IsShown() then window:Hide() else ShowWindow(false) end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Quest Pace Log")
        GameTooltip:AddLine("Click to open or close the dashboard. Drag to move.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end)
if not buttonOk then
    print("|cff33ff99[QuestPaceLog]|r The dashboard button couldn't be made on this client, " .. tostring(buttonErr) .. ". /qpl show still works.")
end

SLASH_QUESTPACELOG1 = "/qpl"
SlashCmdList["QUESTPACELOG"] = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    local command, rest = msg:match("^(%S*)%s*(.-)$")

    if command == "start" then
        StartSession()
    elseif command == "report" then
        PrintReport(rest == "all")
    elseif command == "show" then
        ShowWindow(rest == "all")
    elseif command == "" or command == "log" then
        PrintLog()
    elseif command == "skip" then
        MarkBacklog(rest)
    elseif command == "unskip" then
        Unskip(rest)
    elseif command == "why" then
        TagReason(rest)
    elseif command == "buffs" then
        local names = PlayerBuffNames()
        print("|cff33ff99[QuestPaceLog]|r Your buffs right now, " .. (#names > 0 and table.concat(names, ", ") or "none") .. ".")
    elseif command == "campbuff" then
        local action, name = rest:match("^(%S*)%s*(.-)$")
        local list = CampBuffNames()
        if action == "add" and name ~= "" then
            for _, n in ipairs(list) do if n == name then print("|cff33ff99[QuestPaceLog]|r Already watching " .. name .. ".") return end end
            table.insert(list, name)
            print("|cff33ff99[QuestPaceLog]|r Now watching " .. name .. " as a camp buff.")
        elseif action == "remove" and name ~= "" then
            for i, n in ipairs(list) do
                if n == name then table.remove(list, i) print("|cff33ff99[QuestPaceLog]|r Stopped watching " .. name .. ".") return end
            end
            print("|cff33ff99[QuestPaceLog]|r Not watching " .. name .. ".")
        else
            print("|cff33ff99[QuestPaceLog]|r Watching as camp buffs, " .. table.concat(list, ", ") .. ". Use /qpl campbuff add <name> or /qpl campbuff remove <name>, and /qpl buffs to see your current buffs.")
        end
    else
        print("|cff33ff99[QuestPaceLog]|r Commands, /qpl start for a new session, /qpl for the log, /qpl report for a summary, /qpl report all for every session, /qpl show for a window, /qpl skip [name] to mark backlog, /qpl unskip [name] to undo, /qpl why <a-g> [name] to say why a quest was parked, /qpl buffs and /qpl campbuff for camp tracking.")
    end
end
