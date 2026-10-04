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
                out[info.questID] = { title = info.title, level = info.level, suggestedGroup = info.suggestedGroup }
            end
        end
        return out
    end
    if GetNumQuestLogEntries and GetQuestLogTitle then
        local n = GetNumQuestLogEntries() or 0
        for i = 1, n do
            local title, level, suggestedGroup, isHeader, _, _, _, questID = GetQuestLogTitle(i)
            if title and not isHeader and questID then
                out[questID] = { title = title, level = level, suggestedGroup = tonumber(suggestedGroup) }
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

-- 2.0, something for each of Bartle's four kinds of player, all from your
-- own character. Achievers get records, goals and time to the next level.
-- Explorers get discoveries, places, flight paths, a quest journal and the
-- zones each quest sent you through. Socializers get group time and dungeon
-- runs by group size, counted, never named. Competitors get kills, deaths,
-- time spent dead and honorable kills, measured against your own past.

-- Settings. cheer turns the motivating chat lines (records, time to the next
-- level, goals) on and off. On unless you turn it off.
local function Settings()
    QuestPaceLogDB.settings = QuestPaceLogDB.settings or {}
    if QuestPaceLogDB.settings.cheer == nil then QuestPaceLogDB.settings.cheer = true end
    return QuestPaceLogDB.settings
end

local function Cheer(msg)
    if Settings().cheer then print("|cffffd200[QuestPaceLog]|r " .. msg) end
end

local function MinSec(sec)
    sec = math.floor(sec + 0.5)
    if sec >= 3600 then return string.format("%d:%02d:%02d", math.floor(sec / 3600), math.floor(sec % 3600 / 60), sec % 60) end
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

-- Turns one of the client's own message formats, like "Discovered %s: %d
-- experience gained", into a pattern that captures its values, so these work
-- in whatever language the client runs. The English text is the fallback.
local function FormatPattern(fmt)
    fmt = fmt:gsub("%%%d%$", "%%")
    local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
    return "^" .. p
end

-- Deaths. PLAYER_DEAD when you die, PLAYER_ALIVE when you release (as a
-- ghost) or are brought back, PLAYER_UNGHOST when the ghost reaches the body.
local function OpenDeath()
    local d = session.deaths and session.deaths[#session.deaths]
    return (d and not d.revivedAt) and d or nil
end

local function OnDeath()
    session.deaths = session.deaths or {}
    local zone, sub = CurrentZone()
    local now = time()
    table.insert(session.deaths, { at = now, atStr = date("%H:%M:%S", now), level = UnitLevel("player"), zone = zone, subZone = sub })
    print("|cff33ff99[QuestPaceLog]|r You died" .. (ZoneLabel(zone, sub) and (" in " .. ZoneLabel(zone, sub)) or "") .. ".")
end

local function OnAlive(event)
    local d = OpenDeath()
    if not d then return end
    local now = time()
    if event == "PLAYER_ALIVE" and UnitIsGhost and UnitIsGhost("player") then
        d.releasedAt = d.releasedAt or now
        return
    end
    d.revivedAt, d.downSec = now, now - d.at
    if d.releasedAt then d.ghostSec = now - d.releasedAt end
    print(string.format("|cff33ff99[QuestPaceLog]|r Back on your feet after %s%s.", MinSec(d.downSec),
        d.ghostSec and string.format(", %s of it as a ghost", MinSec(d.ghostSec)) or ""))
end

-- Gold. Every change in your own money, split into gained and spent, with
-- quest rewards counted on their own from the turn-in.
local lastMoney

local function SyncMoney(snapshotOnly)
    if not GetMoney then return end
    local ok, m = pcall(GetMoney)
    if not ok or type(m) ~= "number" then return end
    if lastMoney and not snapshotOnly then
        local delta = m - lastMoney
        if delta > 0 then session.moneyGained = (session.moneyGained or 0) + delta end
        if delta < 0 then session.moneySpent = (session.moneySpent or 0) - delta end
    end
    lastMoney = m
end

local function Gold(copper)
    copper = math.floor(copper or 0)
    local g, s, c = math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
    if g > 0 then return string.format("%dg %ds", g, s) end
    if s > 0 then return string.format("%ds %dc", s, c) end
    return c .. "c"
end

-- Kills. The game's own "X dies, you gain N experience" line about you. Only
-- the count and the XP are kept, never what was killed.
local KILL_PATTERN = FormatPattern(COMBATLOG_XPGAIN_FIRSTPERSON or "%s dies, you gain %d experience.")

local function OnXPMessage(msg)
    local _, xp = (msg or ""):match(KILL_PATTERN)
    if not xp then return end
    session.kills = (session.kills or 0) + 1
    session.killXP = (session.killXP or 0) + tonumber(xp)
end

-- Honorable kills, from your own lifetime PvP total, as the change since the session began.
local function HonorKills()
    if not GetPVPLifetimeStats then return nil end
    local ok, hk = pcall(GetPVPLifetimeStats)
    if ok and type(hk) == "number" then return hk end
    return nil
end

local function SyncHonor()
    local hk = HonorKills()
    if not hk then return end
    if session.honorKillsAtStart == nil then session.honorKillsAtStart = hk end
    session.honorKills = hk - session.honorKillsAtStart
end

-- Places. Every zone and subzone you stand in, the first time this addon saw
-- you there. Discoveries are the game's own "Discovered" lines, the real
-- first visits, with the XP they paid. Flight paths are the game's "New
-- flight path discovered" line.
local function NotePlace()
    local zone, sub = CurrentZone()
    if not zone then return end
    QuestPaceLogDB.places = QuestPaceLogDB.places or {}
    local key = zone .. " / " .. (sub or zone)
    if not QuestPaceLogDB.places[key] then
        QuestPaceLogDB.places[key] = { zone = zone, subZone = sub, firstAt = time(), level = UnitLevel("player") }
    end
end

local DISCOVERED_XP = FormatPattern(ERR_ZONE_EXPLORED_XP or "Discovered %s: %d experience gained")
local DISCOVERED = FormatPattern(ERR_ZONE_EXPLORED or "Discovered: %s")
local NEW_FLIGHT_PATH = ERR_NEWTAXIPATH or "New flight path discovered!"
local lastNotice, lastNoticeAt = nil, 0

-- The same line can arrive as a system chat message and as an on-screen
-- notice, so one seen in the last few seconds is skipped.
local function OnGameNotice(msg)
    if type(msg) ~= "string" then return end
    local now = time()
    if msg == lastNotice and now - lastNoticeAt < 5 then return end
    local zone, sub = CurrentZone()
    local name, xp = msg:match(DISCOVERED_XP)
    if not name then name = msg:match(DISCOVERED) end
    if name then
        lastNotice, lastNoticeAt = msg, now
        session.discoveries = session.discoveries or {}
        table.insert(session.discoveries, { at = now, name = name, xp = tonumber(xp), zone = zone, level = UnitLevel("player") })
        return
    end
    if msg == NEW_FLIGHT_PATH then
        lastNotice, lastNoticeAt = msg, now
        session.flightPaths = session.flightPaths or {}
        table.insert(session.flightPaths, { at = now, zone = zone, subZone = sub, level = UnitLevel("player") })
        Cheer("New flight path" .. (ZoneLabel(zone, sub) and (", " .. ZoneLabel(zone, sub)) or "") .. ".")
    end
end

-- Travel. The zones each open quest has taken you through, in order, starting
-- where you accepted it.
local function NoteTravel()
    local zone = CurrentZone()
    if not zone then return end
    for _, rec in pairs(QuestTracker()) do
        if rec.acceptedAt and not rec.turnedInAt and not rec.droppedAt then
            rec.zones = rec.zones or { rec.acceptedZone }
            local seen = false
            for _, z in ipairs(rec.zones) do if z == zone then seen = true end end
            if not seen then table.insert(rec.zones, zone) end
        end
    end
end

-- Quest journal. The quest's own text, kept when you accept it, so you have
-- the story you actually read. QUEST_DETAIL shows the text, QUEST_ACCEPTED
-- follows if you take the quest.
local pendingDetail

local function OnQuestDetail()
    if not (GetTitleText and GetQuestText) then return end
    local ok, title, text, objective = pcall(function() return GetTitleText(), GetQuestText(), GetObjectiveText and GetObjectiveText() end)
    if ok and title then pendingDetail = { title = title, text = text, objective = objective, at = time() } end
end

local function SaveJournal(questID, title)
    if not pendingDetail or pendingDetail.title ~= title or time() - pendingDetail.at > 600 then return end
    QuestPaceLogDB.journal = QuestPaceLogDB.journal or {}
    QuestPaceLogDB.journal[questID] = { title = title, text = pendingDetail.text, objective = pendingDetail.objective, savedAt = time() }
    pendingDetail = nil
end

-- Records, your own bests. Each is { value, at, label }, and beating one says
-- so in chat when cheer is on.
local function Records()
    QuestPaceLogDB.records = QuestPaceLogDB.records or {}
    return QuestPaceLogDB.records
end

local RECORD_NAMES = {
    questXPPerMin = "best XP a minute on one quest",
    sessionQuests = "most quests turned in in one session",
    sessionXPPerMin = "best XP a minute over a session",
    sessionKills = "most kills in one session",
}

local function TryRecord(key, value, label)
    if not value then return end
    local r = Records()[key]
    if r and value <= r.value then return end
    local firstThisSession = not r or r.session ~= session.startedAt
    Records()[key] = { value = value, at = time(), label = label, session = session.startedAt }
    if r and firstThisSession then
        Cheer(string.format("New record, %s, %s.", RECORD_NAMES[key], label or tostring(math.floor(value))))
    end
end

local function SessionTurnIns(s)
    local n = 0
    for _, e in ipairs(s.entries or {}) do if e.turnedInAt then n = n + 1 end end
    return n
end

local function CheckRecords(entry)
    if entry and entry.durationSec and entry.durationSec >= 60 and (entry.xpReward or 0) > 0 then
        local rate = entry.xpReward / (entry.durationSec / 60)
        TryRecord("questXPPerMin", math.floor(rate + 0.5), string.format("%d on %s", math.floor(rate + 0.5), entry.title or "?"))
    end
    local n = SessionTurnIns(session)
    if n > 0 then TryRecord("sessionQuests", n, tostring(n)) end
    if (session.kills or 0) > 0 then TryRecord("sessionKills", session.kills, tostring(session.kills)) end
    if PlayedSec(session) >= 15 * 60 then
        local rate = XPPerMinute(session)
        if rate then TryRecord("sessionXPPerMin", math.floor(rate + 0.5), tostring(math.floor(rate + 0.5))) end
    end
end

-- Time to the next level, from this session's XP a minute.
local function LevelETA()
    local rate = XPPerMinute(session)
    local xp, max = UnitXP("player"), UnitXPMax("player")
    if not rate or rate <= 0 or not max or max <= 0 then return nil end
    return (max - xp) / rate * 60
end

-- Your own levels, each against the one before. Only levels reached and left
-- inside one session count, since only those have an exact length.
local function LevelHistory()
    local out = {}
    for _, s in ipairs(QuestPaceLogDB.sessions or {}) do
        local ups = s.levelUps or {}
        for i = 2, #ups do
            table.insert(out, { level = ups[i - 1].level, sec = ups[i].at - ups[i - 1].at })
        end
    end
    return out
end

-- Goal. /qpl goal 20, or /qpl goal 20 2026-10-12 for a date. Kept in
-- QuestPaceLogDB.goal, one at a time.
local function GoalPace()
    local g = QuestPaceLogDB.goal
    if not g then return nil end
    local level = UnitLevel("player")
    if level >= g.level then return { done = true, left = 0 } end
    -- ponytail: levels left times your recent average level length. Later
    -- levels take longer, so this runs optimistic. A per-level XP table would fix it.
    local recent, total = LevelHistory(), 0
    local n = math.min(3, #recent)
    for i = #recent - n + 1, #recent do total = total + recent[i].sec end
    local perLevel = n > 0 and total / n or nil
    local eta = LevelETA()
    local playLeft = perLevel and eta and (eta + (g.level - level - 1) * perLevel) or nil
    return { done = false, left = g.level - level, playLeft = playLeft }
end

local function SetGoal(rest)
    local lvl, y, m, d = rest:match("^(%d+)%s*(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    lvl = lvl or rest:match("^(%d+)$")
    if rest == "clear" then
        QuestPaceLogDB.goal = nil
        print("|cff33ff99[QuestPaceLog]|r Goal cleared.")
        return
    end
    if not lvl then
        local g = QuestPaceLogDB.goal
        print("|cff33ff99[QuestPaceLog]|r " .. (g and string.format("Goal, level %d%s.", g.level, g.byStr and (" by " .. g.byStr) or "") or "No goal set.")
            .. " Use /qpl goal 20, /qpl goal 20 2026-10-12, or /qpl goal clear.")
        return
    end
    local by
    if y then
        local ok, t = pcall(time, { year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 23, min = 59, sec = 59 })
        if ok then by = t end
    end
    QuestPaceLogDB.goal = { level = tonumber(lvl), by = by, byStr = by and string.format("%s-%s-%s", y, m, d) or nil, setAt = time(), setLevel = UnitLevel("player") }
    print(string.format("|cff33ff99[QuestPaceLog]|r Goal set, level %s%s.", lvl, by and (" by " .. QuestPaceLogDB.goal.byStr) or ""))
end

-- What a level-up says when cheer is on. Your new level against the one
-- before, the time to the next, and the goal.
local function CheerLevelUp(newLevel)
    local hist = LevelHistory()
    local last, prev = hist[#hist], hist[#hist - 1]
    if last and last.level == newLevel - 1 then
        local compare = ""
        if prev and prev.level == newLevel - 2 and prev.sec > 0 then
            local change = (last.sec - prev.sec) / prev.sec * 100
            compare = string.format(", %d%% %s than level %d", math.abs(math.floor(change + 0.5)), change <= 0 and "faster" or "slower", prev.level)
        end
        Cheer(string.format("Level %d took %s%s.", last.level, MinSec(last.sec), compare))
    end
    local g = GoalPace()
    if g and g.done then
        Cheer(string.format("Goal reached, level %d.", QuestPaceLogDB.goal.level))
    elseif g then
        Cheer(string.format("%d %s to your goal of level %d.", g.left, g.left == 1 and "level" or "levels", QuestPaceLogDB.goal.level))
    end
end

-- A short summary you can copy and post yourself. Nothing is sent anywhere.
local function CardText(s, allTime)
    if not s then return "" end
    local turned = SessionTurnIns(s)
    local deaths = #(s.deaths or {})
    local rate = XPPerMinute(s)
    local lines = {
        string.format("QuestPaceLog, %s", allTime and ("all sessions since " .. (s.startedAtStr or "?"):sub(1, 10)) or ("session of " .. (s.startedAtStr or "?"):sub(1, 10))),
        string.format("Level %d, %d quests turned in%s, played %s", UnitLevel("player"), turned,
            rate and string.format(", %d XP a minute", math.floor(rate + 0.5)) or "", MinSec(s.playedSec or PlayedSec(s) or 0)),
    }
    local extras = {}
    if (s.kills or 0) > 0 then table.insert(extras, s.kills .. " kills") end
    if deaths > 0 then table.insert(extras, deaths .. (deaths == 1 and " death" or " deaths")) end
    if #(s.discoveries or {}) > 0 then table.insert(extras, #s.discoveries .. " places discovered") end
    if (s.moneyGained or 0) > 0 then table.insert(extras, Gold(s.moneyGained) .. " earned") end
    if #extras > 0 then table.insert(lines, table.concat(extras, ", ")) end
    return table.concat(lines, ". ") .. "."
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
frame:RegisterEvent("PLAYER_LOGOUT")
-- GROUP_ROSTER_UPDATE on newer clients, the other two on older Classic ones.
-- Registering an event a client doesn't know raises an error, hence pcall.
for _, ev in ipairs({ "GROUP_ROSTER_UPDATE", "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE",
    "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_MONEY", "CHAT_MSG_COMBAT_XP_GAIN", "PLAYER_PVP_KILLS_CHANGED",
    "CHAT_MSG_SYSTEM", "UI_INFO_MESSAGE", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "QUEST_DETAIL" }) do
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
        local od = CurrentOpenDungeon()
        if od and not od.groupSize then od.groupSize = GroupSize() end
        if isInitialLogin or isReloadingUi then SyncMoney(true) end
        SyncHonor()
        NotePlace()
        NoteTravel()
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
        local logged = ReadQuestLog()[questID]
        if logged and (logged.suggestedGroup or 0) > 1 then entry.suggestedGroup = logged.suggestedGroup end
        rec.zones = { entry.acceptedZone }
        SaveJournal(questID, title)
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
        if moneyReward and moneyReward > 0 then
            entry.moneyReward = moneyReward
            session.moneyFromQuests = (session.moneyFromQuests or 0) + moneyReward
        end
        CheckRecords(entry)
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
        if window and window:IsShown() then pcall(window.Show_, window.allTime, window.lens) end

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
        CheerLevelUp(newLevel)

    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit == "player" then SyncCampBuffs(false) end

    elseif event == "GROUP_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
        SyncGroupState(false)

    elseif event == "PLAYER_DEAD" then
        OnDeath()
    elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        OnAlive(event)
    elseif event == "PLAYER_MONEY" then
        SyncMoney(false)
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        OnXPMessage((...))
    elseif event == "PLAYER_PVP_KILLS_CHANGED" or event == "PLAYER_LOGOUT" then
        SyncHonor()
    elseif event == "CHAT_MSG_SYSTEM" then
        OnGameNotice((...))
    elseif event == "UI_INFO_MESSAGE" then
        -- Newer clients pass a message type first, older ones only the text.
        local a, b = ...
        OnGameNotice(type(b) == "string" and b or a)
    elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" or event == "ZONE_CHANGED_NEW_AREA" then
        NotePlace()
        NoteTravel()
    elseif event == "QUEST_DETAIL" then
        OnQuestDetail()
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

-- Seconds played at each level, { [level] = seconds }, and which levels are
-- estimated, { [level] = true }. Sessions from 1.8 on know their start level
-- and each level-up, so they run from the start through every level-up to
-- the last active moment. Older sessions are estimated from the levels their
-- quests and dungeons recorded, with each level-up placed halfway between
-- the last moment at the old level and the first at the new one. Time logged
-- out never counts.
local function EstimateLevelTimes(one, out, est)
    local pts = {}
    for _, e in ipairs(one.entries or {}) do
        if e.acceptedAt and e.acceptedLevel then table.insert(pts, { e.acceptedAt, e.acceptedLevel }) end
        if e.turnedInAt and e.turnedInLevel then table.insert(pts, { e.turnedInAt, e.turnedInLevel }) end
    end
    for _, d in ipairs(one.dungeons or {}) do
        if d.enteredAt and d.enteredLevel then table.insert(pts, { d.enteredAt, d.enteredLevel }) end
        if d.leftAt and d.leftLevel then table.insert(pts, { d.leftAt, d.leftLevel }) end
    end
    if #pts == 0 then return end
    table.sort(pts, function(a, b) return a[1] < b[1] end)
    local function add(level, sec)
        out[level] = (out[level] or 0) + math.max(0, sec)
        est[level] = true
    end
    add(pts[1][2], pts[1][1] - one.startedAt)
    for i = 2, #pts do
        local a, b = pts[i - 1], pts[i]
        local mid = (a[2] == b[2]) and b[1] or (a[1] + b[1]) / 2
        add(a[2], mid - a[1])
        add(b[2], b[1] - mid)
    end
    add(pts[#pts][2], one.startedAt + (PlayedSec(one) or 0) - pts[#pts][1])
end

function LevelTimes(s)
    local out, est = {}, {}
    for _, one in ipairs(s.entryRuns and (QuestPaceLogDB.sessions or {}) or { s }) do
        if not one.startLevel and one.startedAt then EstimateLevelTimes(one, out, est) end
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
    for lvl, sec in pairs(out) do out[lvl] = math.floor(sec + 0.5) end
    return out, est
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
    local all = { entries = {}, dungeons = {}, rests = {}, groups = {}, deaths = {}, discoveries = {}, flightPaths = {},
        entryRuns = {}, xpTotal = 0, xpFromQuests = 0, sessionCount = #list, playedSec = 0 }
    local sums = { "kills", "killXP", "moneyGained", "moneySpent", "moneyFromQuests", "honorKills" }
    all.startedAtStr = list[1] and list[1].startedAtStr or "?"
    for _, one in ipairs(list) do
        for _, k in ipairs({ "entries", "dungeons", "rests", "groups", "deaths", "discoveries", "flightPaths" }) do
            for _, v in ipairs(one[k] or {}) do table.insert(all[k], v) end
        end
        table.insert(all.entryRuns, one.entries or {})
        all.xpTotal = all.xpTotal + (one.xpTotal or 0)
        all.xpFromQuests = all.xpFromQuests + (one.xpFromQuests or 0)
        if (one.xpTotal or 0) > 0 then all.xpPlayedSec = (all.xpPlayedSec or 0) + (PlayedSec(one) or 0) end
        all.playedSec = all.playedSec + (PlayedSec(one) or 0)
        for _, k in ipairs(sums) do
            if one[k] then all[k] = (all[k] or 0) + one[k] end
        end
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
    if not s or (#s.entries == 0 and #s.dungeons == 0 and #s.rests == 0 and #s.groups == 0 and (s.xpTotal or 0) == 0
        and #(s.deaths or {}) == 0 and #(s.discoveries or {}) == 0 and #(s.flightPaths or {}) == 0 and (s.kills or 0) == 0) then
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
    local levels, estimated = LevelTimes(s)
    local parts = {}
    for lvl, sec in pairs(levels) do table.insert(parts, { lvl, sec }) end
    table.sort(parts, function(a, b) return a[1] < b[1] end)
    if #parts > 0 then
        local strs = {}
        for _, p in ipairs(parts) do
            table.insert(strs, string.format("level %d %d:%02d%s", p[1], math.floor(p[2] / 60), p[2] % 60, estimated[p[1]] and " (estimated)" or ""))
        end
        add("Time played at each level, " .. table.concat(strs, ", ") .. ". Estimated levels come from quest levels, before 1.8 recorded level-ups.")
    end

    -- Kills, deaths, gold, discoveries and PvP (2.0).
    if (s.kills or 0) > 0 then
        add(string.format("Kills %s, %d, worth %d XP%s.", scope, s.kills, s.killXP or 0,
            (s.xpTotal or 0) > 0 and string.format(" (%d%% of all XP)", math.floor((s.killXP or 0) / s.xpTotal * 100 + 0.5)) or ""))
    end
    if #(s.deaths or {}) > 0 then
        local down = 0
        for _, d in ipairs(s.deaths) do down = down + (d.downSec or 0) end
        add(string.format("Deaths %s, %d, %s spent dead.", scope, #s.deaths, MinSec(down)))
    end
    if (s.moneyGained or 0) > 0 or (s.moneySpent or 0) > 0 then
        add(string.format("Gold %s, %s earned, %s of it from quest rewards, %s spent.", scope, Gold(s.moneyGained), Gold(s.moneyFromQuests), Gold(s.moneySpent)))
    end
    if #(s.discoveries or {}) > 0 or #(s.flightPaths or {}) > 0 then
        local dxp = 0
        for _, d in ipairs(s.discoveries or {}) do dxp = dxp + (d.xp or 0) end
        add(string.format("Places discovered %s, %d, worth %d XP. Flight paths learned, %d.", scope, #(s.discoveries or {}), dxp, #(s.flightPaths or {})))
    end
    if (s.honorKills or 0) > 0 then add(string.format("Honorable kills %s, %d.", scope, s.honorKills)) end

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
    st.levelTimes, st.levelEstimated = LevelTimes(s)
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

-- Lenses. The same data seen the way each of Bartle's four kinds of player
-- would look at it, plus the Compass, which places your own play on Bartle's
-- graph. Each lens returns five tiles, a titled list of bars and a note.
local LENSES = {
    { "overview", "Overview" }, { "achiever", "Achiever" }, { "explorer", "Explorer" },
    { "socializer", "Socializer" }, { "competitor", "Competitor" }, { "compass", "Compass" },
}

local function InScope(s, at)
    return s.entryRuns ~= nil or (at and session and at >= session.startedAt)
end

local function GroupedSec(s)
    local sec = 0
    for _, g in ipairs(s.groups or {}) do
        sec = sec + (g.durationSec or ((s == session and g.joinedAt) and (time() - g.joinedAt) or 0))
    end
    return sec
end

-- How strongly your play leans each way, 0 to 1, from your own pace. The
-- scales are rough, a full score is 10 quests an hour, 8 discovery points an
-- hour, all your time grouped, or 60 kills an hour.
-- ponytail: fixed scales, not calibrated against other players (which the
-- addon never sees). Retune them once there's a few weeks of your own data.
local function CompassScores(s, st)
    local hours = (st.playedSec or 0) / 3600
    if hours < 1 / 6 then return nil end
    local places = 0
    for _, p in pairs(QuestPaceLogDB.places or {}) do if InScope(s, p.firstAt) then places = places + 1 end end
    local explore = #(s.discoveries or {}) + 2 * #(s.flightPaths or {}) + 0.5 * places
    local scores = {
        achiever = math.min(1, st.done / hours / 10),
        explorer = math.min(1, explore / hours / 8),
        socializer = math.min(1, GroupedSec(s) / math.max(1, st.playedSec)),
        competitor = math.min(1, (s.kills or 0) / hours / 60 + (s.honorKills or 0) / hours / 10),
    }
    local best, bestV = "achiever", -1
    for _, k in ipairs({ "achiever", "explorer", "socializer", "competitor" }) do
        if scores[k] > bestV then best, bestV = k, scores[k] end
    end
    scores.dominant = best
    scores.hours = hours
    scores.places = places
    return scores
end

local LENS_COLOR = {
    achiever = { 1, 0.82, 0 }, explorer = { 0.3, 0.78, 0.7 }, socializer = { 0.62, 0.45, 1 },
    competitor = { 0.9, 0.35, 0.3 }, compass = { 0.75, 0.75, 0.8 },
}

local function Pct(part, whole) return whole > 0 and math.floor(part / whole * 100 + 0.5) or 0 end

local function LensData(lens, s, st, allTime)
    local hours = math.max((st.playedSec or 0) / 3600, 1 / 60)
    local d = { tiles = {}, rows = {}, color = LENS_COLOR[lens] }
    local function tile(value, label) table.insert(d.tiles, { value, label }) end

    if lens == "achiever" then
        local eta = not allTime and LevelETA() or nil
        local g, goal = GoalPace(), QuestPaceLogDB.goal
        local best = Records().questXPPerMin
        tile(st.xpPerMin and tostring(math.floor(st.xpPerMin + 0.5)) or "none yet", "XP per minute played")
        tile(string.format("%.1f", st.done / hours), "quests turned in an hour")
        tile(eta and MinSec(eta) or "n/a", eta and ("to level " .. (UnitLevel("player") + 1)) or "to the next level, live only")
        tile(goal and (g and g.done and "done" or string.format("%d to go", g and g.left or 0)) or "none", goal and ("levels to " .. goal.level .. (goal.byStr and (" by " .. goal.byStr) or "")) or "goal, set with /qpl goal 20")
        tile(best and tostring(best.value) or "none yet", "best XP a minute on a quest")
        d.title = "Each level against the one before"
        local hist = LevelHistory()
        for i = math.max(1, #hist - 11), #hist do
            local h, prev = hist[i], hist[i - 1]
            local cmp = ""
            if prev and prev.level == h.level - 1 and prev.sec > 0 then
                local change = (h.sec - prev.sec) / prev.sec * 100
                cmp = string.format(", %d%% %s", math.abs(math.floor(change + 0.5)), change <= 0 and "faster" or "slower")
            end
            table.insert(d.rows, { "Level " .. h.level, h.sec, MinSec(h.sec) .. cmp })
        end
        d.note = #d.rows == 0 and "Levels show here once you finish one start to end in a session, from version 1.8 on. Records and goals cheer in chat, /qpl cheer off quiets them."
            or "Only levels started and finished in one session count, so their length is exact. /qpl records lists your bests."

    elseif lens == "explorer" then
        local dxp, zones, zoneCount = 0, {}, 0
        for _, x in ipairs(s.discoveries or {}) do dxp = dxp + (x.xp or 0) end
        for _, e in ipairs(s.entries) do
            if e.turnedInZone and not zones[e.turnedInZone] then zones[e.turnedInZone], zoneCount = true, zoneCount + 1 end
        end
        local places = 0
        for _, p in pairs(QuestPaceLogDB.places or {}) do if InScope(s, p.firstAt) then places = places + 1 end end
        tile(tostring(#(s.discoveries or {})), "places discovered")
        tile(Thousands(dxp), "XP from discovering")
        tile(tostring(#(s.flightPaths or {})), "flight paths learned")
        tile(tostring(places), "places visited, from 2.0 on")
        tile(tostring(zoneCount), "zones you turned quests in")
        d.title = "Quests that sent you farthest"
        local list = {}
        for _, rec in pairs(QuestTracker()) do
            if rec.zones and #rec.zones > 1 and (InScope(s, rec.acceptedAt) or InScope(s, rec.turnedInAt)) then table.insert(list, rec) end
        end
        table.sort(list, function(a, b) return #a.zones > #b.zones end)
        for i = 1, math.min(12, #list) do
            table.insert(d.rows, { list[i].title or "?", #list[i].zones, table.concat(list[i].zones, ", ") })
        end
        d.note = "Discoveries are the game's own Discovered messages. /qpl journal and part of a quest name shows the text of a quest you accepted."

    elseif lens == "socializer" then
        local groupedSec, closed, total = GroupedSec(s), 0, 0
        for _, g in ipairs(s.groups or {}) do if g.durationSec then closed, total = closed + 1, total + g.durationSec end end
        local groupQuests = 0
        for _, e in ipairs(s.entries) do if e.suggestedGroup and e.turnedInAt then groupQuests = groupQuests + 1 end end
        tile(Pct(groupedSec, st.playedSec or 0) .. "%", "of your time in a group")
        tile(tostring(#(s.groups or {})), "groups joined")
        tile(closed > 0 and MinSec(total / closed) or "none yet", "average time together")
        tile(Pct(st.grouped, st.grouped + st.solo) .. "%", "of turn-ins in a group")
        tile(tostring(groupQuests), "group quests turned in")
        if #(s.dungeons or {}) > 0 then
            d.title = "Dungeon runs"
            for i = math.max(1, #s.dungeons - 11), #s.dungeons do
                local dg = s.dungeons[i]
                local kills = 0
                for _, b in ipairs(dg.bosses or {}) do if b.success then kills = kills + 1 end end
                table.insert(d.rows, { dg.name or "?", dg.durationSec or 0, string.format("%s, %s, %d %s down",
                    dg.durationSec and MinSec(dg.durationSec) or "still inside", dg.groupSize and (dg.groupSize .. " players") or "group size not recorded", kills, kills == 1 and "boss" or "bosses") })
            end
        else
            d.title = "Groups"
            for i = math.max(1, #(s.groups or {}) - 11), #(s.groups or {}) do
                local g = s.groups[i]
                table.insert(d.rows, { string.format("Group of %d", g.maxSize or 2), g.durationSec or 0, g.durationSec and (MinSec(g.durationSec) .. " together") or "still together" })
            end
        end
        d.note = "Only how many people were in your group is recorded, never who they were."

    elseif lens == "competitor" then
        local down, ghost = 0, 0
        for _, x in ipairs(s.deaths or {}) do down, ghost = down + (x.downSec or 0), ghost + (x.ghostSec or 0) end
        tile(Thousands(s.kills or 0), "kills")
        tile(string.format("%.0f", (s.kills or 0) / hours), "kills an hour")
        tile(Pct(s.killXP or 0, st.xpTotal) .. "%", "of XP from kills")
        tile(tostring(#(s.deaths or {})), "deaths")
        tile(MinSec(down), "spent dead")
        d.title = "Deaths"
        for i = math.max(1, #(s.deaths or {}) - 11), #(s.deaths or {}) do
            local x = s.deaths[i]
            table.insert(d.rows, { string.format("Level %d, %s", x.level or 0, x.zone or "?"), x.downSec or 0,
                x.downSec and (MinSec(x.downSec) .. " dead" .. (x.ghostSec and (", " .. MinSec(x.ghostSec) .. " as a ghost") or "")) or "still dead" })
        end
        d.note = (#d.rows == 0 and "No deaths yet. " or "") .. "Your rival is your own past, other players are never recorded."
            .. ((s.honorKills or 0) > 0 and (" Honorable kills, " .. s.honorKills .. ".") or "")

    elseif lens == "compass" then
        local sc = CompassScores(s, st)
        d.title = "How your play leans"
        if sc then
            for _, k in ipairs({ "achiever", "explorer", "socializer", "competitor" }) do
                tile(math.floor(sc[k] * 100 + 0.5) .. "%", k)
            end
            tile(sc.dominant:sub(1, 1):upper() .. sc.dominant:sub(2), "you play most like")
            d.scores = sc
            local details = {
                achiever = string.format("%.1f quests an hour", st.done / sc.hours),
                explorer = string.format("%d discoveries, %d flight paths, %d places", #(s.discoveries or {}), #(s.flightPaths or {}), sc.places),
                socializer = Pct(GroupedSec(s), st.playedSec) .. "% of your time grouped",
                competitor = string.format("%.0f kills an hour", (s.kills or 0) / sc.hours),
            }
            for _, k in ipairs({ "achiever", "explorer", "socializer", "competitor" }) do
                table.insert(d.rows, { k:sub(1, 1):upper() .. k:sub(2), sc[k], details[k], LENS_COLOR[k] })
            end
        else
            for i = 1, 5 do tile("n/a", i == 5 and "play 10 minutes first" or "") end
        end
        d.note = "Bartle's four kinds of player on his own graph, from what you did, not who you are. Acting is up, interacting down, the world right, other players left. "
            .. "This addon only sees your own character, so the dot leans toward the world side."
    end
    return d
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

    -- Overview widgets live in ov and lens widgets in lv, so each view hides as a whole.
    local ov, lv = CreateFrame("Frame", nil, f), CreateFrame("Frame", nil, f)
    ov:SetAllPoints(); lv:SetAllPoints()
    local P = f
    local function text(x, y, template, point)
        local fs = P:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
        -- Centered text is placed from the window's top left, like everything else.
        if point == "CENTER" then fs:SetPoint("CENTER", f, "TOPLEFT", x, y) else fs:SetPoint(point or "TOPLEFT", x, y) end
        return fs
    end
    local function box(x, y, w, h, c, a)
        local t = P:CreateTexture(nil, "ARTWORK")
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

    local titleText = text(0, -6, "GameFontHighlight", "TOP")

    local function button(label, x, w, onClick)
        local b = TryCreate("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(w, 22)
        b:SetPoint("TOPLEFT", x, -32)
        b:SetText(label)
        b:SetScript("OnClick", onClick)
        return b
    end
    local scopeButton = button("All sessions", PAD, 112, function() f.Show_(not f.allTime, f.lens) end)
    local lensButtons = {}
    for i, l in ipairs(LENSES) do
        lensButtons[l[1]] = button(l[2], PAD + 116 + (i - 1) * 94, 90, function()
            Settings().lens = l[1] -- your choice beats the Compass's guess next time
            f.Show_(f.allTime, l[1])
        end)
    end
    button("Card", PAD + 116 + 6 * 94, 52, function() f.ShowCard_() end)

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
            local t = P:CreateTexture(nil, "ARTWORK")
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

    P = ov
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
        local hit = CreateFrame("Frame", nil, P)
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
    local levelNote = text(-PAD, -500, "GameFontHighlightSmall", "TOPRIGHT")

    -- Lens views, in lv. A heading, twelve rows of bars, a note, and the Compass graph.
    P = lv
    local lensTitle = text(PAD, -136, "GameFontNormal")
    box(PAD, -152, INNER, 1, GOLD, 0.25)
    local lensRows = {}
    for i = 1, 12 do
        local name = text(PAD, 0)
        name:SetJustifyH("LEFT")
        if name.SetWordWrap then name:SetWordWrap(false) end
        lensRows[i] = { name = name, bar = box(PAD, 0, 1, 12, GOLD), info = text(PAD, 0) }
    end
    local lensNote = text(PAD, -440)
    lensNote:SetWidth(INNER)
    lensNote:SetJustifyH("LEFT")
    -- Bartle's graph. Acting up, interacting down, players left, world right.
    local CX, CY, HALF = PAD + 120, -290, 110
    local compass = { box(CX - HALF, CY + HALF, 2 * HALF, 2 * HALF, { 1, 1, 1 }, 0.05), box(CX - HALF, CY + 1, 2 * HALF, 1, GOLD, 0.35), box(CX, CY + HALF, 1, 2 * HALF, GOLD, 0.35) }
    for _, q in ipairs({ { "Competitor", -HALF / 2, HALF - 12 }, { "Achiever", HALF / 2, HALF - 12 }, { "Socializer", -HALF / 2, -HALF + 12 }, { "Explorer", HALF / 2, -HALF + 12 } }) do
        local t = text(CX + q[2], CY + q[3], "GameFontNormalSmall", "CENTER")
        t:SetText(q[1])
        table.insert(compass, t)
    end
    for _, a in ipairs({ { "acting", 0, HALF + 10 }, { "interacting", 0, -HALF - 10 }, { "players", -HALF - 26, 0 }, { "world", HALF + 22, 0 } }) do
        local t = text(CX + a[2], CY + a[3], "GameFontHighlightSmall", "CENTER")
        t:SetText(a[1])
        table.insert(compass, t)
    end
    local dot = box(CX - 6, CY + 6, 12, 12, { 1, 1, 1 })
    table.insert(compass, dot)
    P = f

    local hint = text(PAD, -612 + 18)
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

    function f.UpdateLens(lens, s, st, allTime)
        local d = LensData(lens, s, st, allTime)
        for i = 1, 5 do
            local t = d.tiles[i] or { "", "" }
            tiles[i].value:SetText(t[1]); tiles[i].label:SetText(t[2])
        end
        lensTitle:SetText(d.title or "")
        lensNote:SetText(d.note or "")
        local isCompass = lens == "compass"
        for _, w in ipairs(compass) do if isCompass then w:Show() else w:Hide() end end
        -- On the Compass the list sits right of the graph, elsewhere it spans the window.
        local left = isCompass and (PAD + 2 * HALF + 70) or PAD
        local nameW = isCompass and 90 or 270
        local barMax = isCompass and 160 or 280
        local most = 0
        for _, r in ipairs(d.rows) do if r[2] > most then most = r[2] end end
        for i, row in ipairs(lensRows) do
            local r = d.rows[i]
            if r then
                local y = -164 - (i - 1) * 22
                local w = most > 0 and math.max(2, math.floor(barMax * r[2] / most)) or 2
                if isCompass then w = math.max(2, math.floor(barMax * r[2])) end
                local c = r[4] or d.color
                row.name:ClearAllPoints(); row.name:SetPoint("TOPLEFT", left, y); row.name:SetWidth(nameW - 8); row.name:SetText(r[1])
                row.bar:SetColorTexture(c[1], c[2], c[3], 0.9)
                place(row.bar, left + nameW, y - 1, w)
                row.info:ClearAllPoints(); row.info:SetPoint("TOPLEFT", left + nameW + w + 6, y); row.info:SetText(r[3])
                row.name:Show(); row.info:Show()
            else
                row.name:Hide(); row.bar:Hide(); row.info:Hide()
            end
        end
        if isCompass and d.scores then
            local sc, total = d.scores, d.scores.achiever + d.scores.explorer + d.scores.socializer + d.scores.competitor
            local x = total > 0 and ((sc.achiever + sc.explorer) - (sc.competitor + sc.socializer)) / total or 0
            local y = total > 0 and ((sc.achiever + sc.competitor) - (sc.explorer + sc.socializer)) / total or 0
            dot:ClearAllPoints()
            dot:SetPoint("CENTER", f, "TOPLEFT", CX + x * (HALF - 10), CY + y * (HALF - 10))
            dot:Show()
        elseif isCompass then
            dot:Hide()
        end
    end

    function f.ShowCard_()
        local s = f.allTime and AllSessions() or session
        report:SetText(CardText(s, f.allTime))
        report:SetFocus()
        report:HighlightText()
        hint:SetText("Your card is selected in the box below. Press Ctrl+C to copy it, then paste it wherever you like.")
    end

    function f.UpdateVisuals(st)
        local avg = st.closedCount > 0 and st.closedTotal / st.closedCount or nil
        tiles[1].value:SetText(tostring(st.done)); tiles[1].label:SetText("quests turned in")
        tiles[2].value:SetText(avg and Clock(avg) or "none yet"); tiles[2].label:SetText("average per quest")
        tiles[3].value:SetText(st.xpPerMin and Thousands(st.xpPerMin) or "none yet"); tiles[3].label:SetText("XP per minute played")
        tiles[4].value:SetText(Clock(st.playedSec)); tiles[4].label:SetText("time played")
        tiles[5].value:SetText(Clock(st.restSec)); tiles[5].label:SetText(string.format("resting, %d at campfires", st.campStays))

        fill(donuts.xp, { { st.xpFromQuests, GOLD, "from quests" }, { math.max(0, st.xpTotal - st.xpFromQuests), SLATE, "everything else" } }, "No XP gained yet.")
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
            (colored > 0 and st.done > colored) and ((st.done - colored) .. " not recorded") or nil)
        fill(donuts.group, { { st.grouped, VIOLET, "in a group" }, { st.solo, SLATE, "solo" } }, "No turn-ins since 1.3.")

        local levels = {}
        for lvl, sec in pairs(st.levelTimes) do table.insert(levels, { lvl, sec }) end
        table.sort(levels, function(a, b) return a[1] < b[1] end)
        while #levels > LEVEL_COLS do table.remove(levels, 1) end
        local most = 1
        for _, l in ipairs(levels) do if l[2] > most then most = l[2] end end
        local colW = math.min(36, math.floor(INNER / math.max(1, #levels)))
        local anyEstimated = false
        for _, l in ipairs(levels) do if st.levelEstimated[l[1]] then anyEstimated = true end end
        levelNote:SetText(#levels == 0 and "No levels recorded yet." or (anyEstimated and "Lighter columns are estimated from quest levels, before 1.8 recorded level-ups." or ""))
        for i, col in ipairs(levelCols) do
            local l = levels[i]
            if l then
                local x, h = PAD + (i - 1) * colW, math.max(2, math.floor(LEVEL_MAX_H * l[2] / most))
                col.bar:ClearAllPoints()
                col.bar:SetPoint("BOTTOMLEFT", f, "TOPLEFT", x + 3, LEVEL_BASE)
                col.bar:SetSize(colW - 6, h)
                col.bar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], st.levelEstimated[l[1]] and 0.4 or 0.9)
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

    function f.Show_(allTime, lens)
        f.allTime = allTime
        local s = allTime and AllSessions() or session
        titleText:SetText("Quest Pace Log, " .. (allTime and "all sessions" or "this session"))
        scopeButton:SetText(allTime and "This session" or "All sessions")
        local st = s and DashboardStats(s)
        local sc = st and CompassScores(s, st)
        lens = lens or f.lens or Settings().lens or (sc and sc.dominant) or "overview"
        f.lens = lens
        for _, l in ipairs(LENSES) do
            local b = lensButtons[l[1]]
            b:SetText((sc and sc.dominant == l[1]) and ("|cffffd200" .. l[2] .. " (you)|r") or l[2])
            if l[1] == lens then b:LockHighlight() else b:UnlockHighlight() end
        end
        hint:SetText(not Settings().lens and "New here? Open Compass to see which way your play leans. The window opens on that lens once you've played 10 minutes." or "")
        if lens == "overview" then ov:Show() else ov:Hide() end
        if lens == "overview" then lv:Hide() else lv:Show() end
        if s then
            local ok, err = pcall(lens == "overview" and f.UpdateVisuals or function(x) f.UpdateLens(lens, s, x, allTime) end, st)
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

local function ShowWindow(allTime, lens)
    if not window then
        local ok, f = pcall(BuildWindow)
        if not ok then
            print("|cff33ff99[QuestPaceLog]|r The window couldn't open on this client, " .. tostring(f) .. ". /qpl report still works.")
            return
        end
        window = f
    end
    window.Show_(allTime, lens)
end

local function ShowCard(allTime)
    ShowWindow(allTime)
    if window then window.ShowCard_() end
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
        local all = rest:find("all", 1, true) ~= nil
        local lens = rest:match("(%a+)$")
        if lens == "all" then lens = nil end
        ShowWindow(all, lens)
    elseif command == "" or command == "log" then
        PrintLog()
    elseif command == "skip" then
        MarkBacklog(rest)
    elseif command == "unskip" then
        Unskip(rest)
    elseif command == "why" then
        TagReason(rest)
    elseif command == "cheer" then
        if rest == "on" or rest == "off" then Settings().cheer = (rest == "on") end
        print("|cff33ff99[QuestPaceLog]|r Records, level and goal messages are " .. (Settings().cheer and "on" or "off") .. ". /qpl cheer on or /qpl cheer off.")
    elseif command == "goal" then
        SetGoal(rest)
    elseif command == "eta" then
        local eta = LevelETA()
        print("|cff33ff99[QuestPaceLog]|r " .. (eta and string.format("At this session's pace, level %d in about %s of play.", UnitLevel("player") + 1, MinSec(eta))
            or "Not enough XP this session yet to estimate the next level."))
    elseif command == "records" then
        local any = false
        for key, name in pairs(RECORD_NAMES) do
            local r = Records()[key]
            if r then any = true print(string.format("%s, %s, %s.", name, r.label or tostring(r.value), date("%Y-%m-%d", r.at))) end
        end
        if not any then print("|cff33ff99[QuestPaceLog]|r No records yet.") end
    elseif command == "journal" then
        local best
        for id, j in pairs(QuestPaceLogDB.journal or {}) do
            if (rest == "" or (j.title or ""):lower():find(rest, 1, true)) and (not best or j.savedAt > best.savedAt) then best = j end
        end
        if best then
            print("|cff33ff99[QuestPaceLog]|r " .. best.title .. ". " .. (best.text or "") .. (best.objective and (" Objective, " .. best.objective) or ""))
        else
            print("|cff33ff99[QuestPaceLog]|r No saved quest text" .. (rest ~= "" and (" matching \"" .. rest .. "\"") or "") .. ".")
        end
    elseif command == "card" then
        ShowCard(rest == "all")
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
        print("|cff33ff99[QuestPaceLog]|r Commands, /qpl start for a new session, /qpl for the log, /qpl report for a summary, /qpl report all for every session, /qpl show for a window, /qpl skip [name] to mark backlog, /qpl unskip [name] to undo, /qpl why <a-g> [name] to say why a quest was parked, /qpl buffs and /qpl campbuff for camp tracking, /qpl goal, /qpl eta, /qpl records, /qpl journal [name], /qpl card, /qpl cheer on or off.")
    end
end
