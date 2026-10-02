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

local function PrintReport()
    if not session or (#session.entries == 0 and #session.dungeons == 0 and #session.rests == 0 and #session.groups == 0) then
        print("|cff33ff99[QuestPaceLog]|r Nothing to report yet.")
        return
    end

    local closed, backlogCount = {}, 0
    for _, e in ipairs(session.entries) do
        if e.backlog then
            backlogCount = backlogCount + 1
        elseif e.durationSec then
            table.insert(closed, e)
        end
    end

    print(string.format("|cff33ff99[QuestPaceLog] Report|r, session started %s", session.startedAtStr))
    print(string.format("Quests logged, %d. Quests with both a start and end time, %d%s.", #session.entries, #closed,
        backlogCount > 0 and string.format(" (%d more marked backlog, not counted here)", backlogCount) or ""))

    if #closed > 0 then
        local total, longest, shortest = 0, closed[1], closed[1]
        for _, e in ipairs(closed) do
            total = total + e.durationSec
            if e.durationSec > longest.durationSec then longest = e end
            if e.durationSec < shortest.durationSec then shortest = e end
        end
        local avg = total / #closed
        print(string.format("Average time per quest, %d:%02d.", math.floor(avg / 60), avg % 60))
        print(string.format("Longest, \"%s\" at %d:%02d. Shortest, \"%s\" at %d:%02d.",
            longest.title, math.floor(longest.durationSec / 60), longest.durationSec % 60,
            shortest.title, math.floor(shortest.durationSec / 60), shortest.durationSec % 60))
    end

    -- Gap between one quest's turn-in and the next quest's accept, a rough proxy
    -- for travel or idle time. It is not a felt-pacing judgment, keep tagging that by hand.
    local gaps = {}
    for i = 2, #session.entries do
        local prev, cur = session.entries[i - 1], session.entries[i]
        if not prev.backlog and not cur.backlog and prev.turnedInAt and cur.acceptedAt and cur.acceptedAt > prev.turnedInAt then
            table.insert(gaps, cur.acceptedAt - prev.turnedInAt)
        end
    end
    if #gaps > 0 then
        local gapTotal = 0
        for _, g in ipairs(gaps) do gapTotal = gapTotal + g end
        local gapAvg = gapTotal / #gaps
        print(string.format("Gaps measured between a turn-in and the next accept, %d, average %d:%02d.", #gaps, math.floor(gapAvg / 60), gapAvg % 60))
    end

    local levelUps = 0
    for _, e in ipairs(session.entries) do
        if e.acceptedLevel and e.turnedInLevel and e.turnedInLevel > e.acceptedLevel then
            levelUps = levelUps + 1
        end
    end
    if levelUps > 0 then
        print(string.format("Quests during which you leveled up, %d.", levelUps))
    end

    -- XP. The per-quest reward is exact, straight off the turn-in event. The
    -- split below is the honest version of "how much came from monsters,"
    -- since nothing tells this addon which kill fed which quest.
    local xpTotal = session.xpTotal or 0
    if xpTotal > 0 then
        local xpFromQuests = session.xpFromQuests or 0
        local xpOther = xpTotal - xpFromQuests
        local pctQuest = (xpFromQuests / xpTotal) * 100
        print(string.format("XP earned this session, %d total, %d from quest turn-ins (%d%%), %d from everything else, kills, first-time discovery, and so on.",
            xpTotal, xpFromQuests, math.floor(pctQuest + 0.5), xpOther))
    end

    -- Dungeons.
    if session.dungeons and #session.dungeons > 0 then
        print(string.format("Dungeons this session, %d.", #session.dungeons))
        for _, d in ipairs(session.dungeons) do
            local kills, wipes = 0, 0
            for _, b in ipairs(d.bosses or {}) do
                if b.success then kills = kills + 1 else wipes = wipes + 1 end
            end
            if d.leftAt then
                local levelNote = (d.enteredLevel ~= d.leftLevel) and string.format(", level %d to %d", d.enteredLevel, d.leftLevel) or ""
                print(string.format("  %s (%s), %d:%02d, %d boss(es) down, %d wipe(s)%s",
                    d.name, d.difficultyName or d.instanceType, math.floor(d.durationSec / 60), d.durationSec % 60, kills, wipes, levelNote))
            else
                print(string.format("  %s (%s), still inside, entered at %s", d.name, d.difficultyName or d.instanceType, d.enteredAtStr))
            end
        end
    end

    -- Resting.
    if session.rests and #session.rests > 0 then
        local totalRest, closedRests = 0, 0
        for _, r in ipairs(session.rests) do
            if r.durationSec then
                totalRest = totalRest + r.durationSec
                closedRests = closedRests + 1
            end
        end
        if closedRests > 0 then
            print(string.format("Rest periods this session, %d, totaling %d:%02d%s.", #session.rests,
                math.floor(totalRest / 60), totalRest % 60, (#session.rests > closedRests) and " (still resting)" or ""))
        else
            print(string.format("Rest periods this session, %d, still resting.", #session.rests))
        end
        local campCount, campTotal = 0, 0
        for _, r in ipairs(session.rests) do
            if r.campfire and r.durationSec then
                campCount = campCount + 1
                campTotal = campTotal + r.durationSec
            end
        end
        if campCount > 0 then
            local avg = campTotal / campCount
            print(string.format("Of those, at a campfire, %d, averaging %d:%02d per stay.", campCount, math.floor(avg / 60), avg % 60))
        end
    end

    -- Groups.
    if #session.groups > 0 then
        local closedGroups, groupTotal, largest = 0, 0, 0
        for _, g in ipairs(session.groups) do
            if g.durationSec then closedGroups, groupTotal = closedGroups + 1, groupTotal + g.durationSec end
            if g.maxSize > largest then largest = g.maxSize end
        end
        local avg = closedGroups > 0 and groupTotal / closedGroups or 0
        print(string.format("Groups this session, %d, largest %d%s%s.", #session.groups, largest,
            closedGroups > 0 and string.format(", average %d:%02d together", math.floor(avg / 60), avg % 60) or "",
            (#session.groups > closedGroups) and ", still grouped" or ""))
    end
    local turnedIn, grouped = 0, 0
    for _, e in ipairs(session.entries) do
        if e.turnedInGroupSize then
            turnedIn = turnedIn + 1
            if e.turnedInGroupSize > 1 then grouped = grouped + 1 end
        end
    end
    if grouped > 0 then
        print(string.format("Quests turned in while grouped, %d of %d.", grouped, turnedIn))
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
        print(string.format("Quests tracked for difficulty, %d. Went gray while still in your log, %d (%d of those turned in anyway). Dropped without turning in, %d.",
            tracked, wentGray, grayThenDone, dropped))
    end

    print("|cff33ff99[QuestPaceLog]|r Raw data is also saved in your SavedVariables file. Paste this report, or that file's contents, back into the project and it becomes a written case study.")
end

SLASH_QUESTPACELOG1 = "/qpl"
SlashCmdList["QUESTPACELOG"] = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    local command, rest = msg:match("^(%S*)%s*(.-)$")

    if command == "start" then
        StartSession()
    elseif command == "report" then
        PrintReport()
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
        print("|cff33ff99[QuestPaceLog]|r Commands, /qpl start for a new session, /qpl for the log, /qpl report for a summary, /qpl skip [name] to mark backlog, /qpl unskip [name] to undo, /qpl why <a-g> [name] to say why a quest was parked, /qpl buffs and /qpl campbuff for camp tracking.")
    end
end
