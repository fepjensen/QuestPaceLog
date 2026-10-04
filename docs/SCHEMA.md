# QuestPaceLog saved data format

Everything the addon records lives in one per-character SavedVariables table, `QuestPaceLogDB`, written to
`WTF\Account\<account>\<realm>\<character>\SavedVariables\QuestPaceLog.lua` when the player logs out or reloads.

A Python pipeline outside this repo reads that file to build a private dashboard and a public data file for the site's Lab page. It reads the field names below directly. **Changes to this format must be additive.** Never rename or remove a field, and never change a field's meaning or type. Old saved files, written by earlier versions, must keep loading and must keep producing the same values. When you add a field, add it to this document and to CHANGELOG.md, so the pipeline can be updated to use it.

## Top level

```
QuestPaceLogDB = {
  sessions = { <session>, ... },     -- array, oldest first
  quests   = { [questID] = <quest record>, ... },   -- added in 1.1
  campBuffNames = { "boosted rest", ... },         -- added in 1.2, lowercase buff names watched as camp buffs
  places   = { ["Zone / Subzone"] = { zone, subZone, firstAt, level }, ... },  -- 2.0, first time the addon saw you there
  journal  = { [questID] = { title, text, objective, savedAt }, ... },          -- 2.0, quest text kept at accept
  records  = { [key] = { value, at, label, session }, ... },                    -- 2.0, keys below
  goal     = { level, by, byStr, setAt, setLevel } or nil,                     -- 2.0, from /qpl goal
  settings = { cheer = true or false, lens = "achiever" or nil, hud = false or nil },  -- 2.0, hud from 2.1
}
```

## Session

One per login. A /reload within six hours continues the same session.

| Field | Type | Meaning |
|---|---|---|
| startedAt | number | epoch seconds at login |
| startedAtStr | string | "YYYY-MM-DD HH:MM:SS", local time |
| entries | array of entry | quests accepted or turned in during this session |
| xpTotal | number or nil | all XP gained this session, from PLAYER_XP_UPDATE deltas |
| xpFromQuests | number or nil | XP from quest turn-ins this session, sum of xpReward |
| dungeons | array of dungeon | dungeon visits this session |
| rests | array of rest | rested-state periods this session |
| campBuffs | array of camp buff | camp buffs gained this session (1.2) |
| groups | array of group | groups joined this session (1.3) |
| startLevel | number or nil | player level when the session started. nil before 1.8 (1.8) |
| levelUps | array of { level, at } or nil | each level reached this session and when, from PLAYER_LEVEL_UP. Absent until the first level-up, and before 1.8 (1.8) |
| deaths | array of death or nil | each death this session (2.0) |
| moneyGained, moneySpent | number (copper) or nil | positive and negative changes in your money this session (2.0) |
| moneyFromQuests | number (copper) or nil | money from quest rewards this session, from QUEST_TURNED_IN (2.0) |
| kills, killXP | number or nil | kills this session and their XP, from your own "X dies, you gain N experience" lines. What was killed isn't kept (2.0) |
| honorKillsAtStart, honorKills | number or nil | lifetime honorable kills when the session began, and the gain since (2.0) |
| discoveries | array of { at, name, xp, zone, level } or nil | the game's own "Discovered" messages, real first visits (2.0) |
| flightPaths | array of { at, zone, subZone, level } or nil | the game's "New flight path discovered" message (2.0) |
| lastActiveAt | number or nil | epoch seconds of the last event the addon saw this session, including logout. lastActiveAt minus startedAt is the time played. nil on sessions before 1.7, where the latest timestamp in the session is the best estimate (1.7) |

## Entry (one quest, within one session)

A quest accepted in one session and turned in during a later one appears as two entries, an accept-only entry in the first session and a turn-in-only entry in the later one. The pipeline stitches them together by questID.

| Field | Type | Meaning |
|---|---|---|
| questID | number | |
| title | string | |
| acceptedAt, acceptedStr, acceptedElapsed | number, "HH:MM:SS", "M:SS since session start" | nil on a turn-in-only entry |
| acceptedLevel | number | player level at accept |
| questLevel | number or nil | the quest's own level, read from the quest log at accept (1.1) |
| colorAtAccept | string or nil | "red", "orange", "yellow", "green" or "gray" at accept (1.1) |
| turnedInAt, turnedInStr, turnedInElapsed | as above | nil while the quest is still open |
| acceptedZone, acceptedSubZone, acceptedMapID | string, string, number, each or nil | where the player was at accept (1.2) |
| turnedInLevel | number | player level at turn-in |
| turnedInZone, turnedInSubZone, turnedInMapID | as above | where the player was at turn-in (1.2) |
| colorAtTurnIn | string or nil | quest color at turn-in (1.1) |
| xpReward | number | XP paid at turn-in, from QUEST_TURNED_IN |
| turnedInGroupSize | number or nil | people in your group at turn-in, you included, 1 when solo. nil on turn-ins before 1.3 (1.3) |
| durationSec | number or nil | turn-in minus accept, only when both are in this session |
| backlog | true or nil | set by untracking the quest or by /qpl skip, cleared by tracking again or /qpl unskip |
| reason | letter a to g or nil | optional note from /qpl why (1.1). Not used as evidence |
| moneyReward | number (copper) or nil | money paid at turn-in (2.0) |
| suggestedGroup | number or nil | the group size the quest log suggested, when more than 1 (2.0) |

## Quest record (1.1), one per questID, across sessions

| Field | Meaning |
|---|---|
| title, questLevel | |
| firstSeenAt, firstSeenLevel | when the addon first saw the quest |
| predatesTracking | true if the quest was already in the log when 1.1 first ran |
| acceptedAt, acceptedLevel | latest accept |
| acceptedZone, acceptedSubZone, acceptedMapID | where, at the latest accept (1.2) |
| greenAt, greenAtLevel | first moment it turned green (or gray) for the player |
| grayAt, grayAtLevel | first moment it turned gray |
| droppedAt, droppedLevel | left the log without a turn-in. Cleared if later turned in |
| turnedInAt, turnedInLevel, xpReward, colorAtTurnIn | turn-in |
| turnedInZone, turnedInSubZone, turnedInMapID | where, at turn-in (1.2) |
| turnedInGroupSize | group size at turn-in, as on the entry (1.3) |
| reason | copy of the entry's /qpl why letter |
| zones | the zones the quest took you through while open, in order, starting where you accepted it (2.0) |

Picking a quest back up after turning it in or dropping it starts a fresh record for that questID.

## Dungeon

name, instanceType, difficultyName, enteredAt, enteredAtStr, enteredLevel, leftAt, leftAtStr, leftLevel, durationSec, bosses (array of { name, success (boolean), at }). From 2.0 also groupSize, your group's size when you entered.

## Death (2.0)

at, atStr, level, zone, subZone, releasedAt when you released as a ghost, revivedAt when you were alive again, downSec (at to revivedAt), and ghostSec (releasedAt to revivedAt) when you released.

## Records (2.0)

questXPPerMin (best XP a minute on one quest, at least a minute long), sessionQuests (most turn-ins in one session), sessionXPPerMin (best XP a minute over a session of 15 minutes or more), sessionKills (most kills in one session). Each holds value, at, label and session (the session's startedAt).

## Rest

startedAt, startedAtStr, endedAt, endedAtStr, durationSec. From 1.2 also zone and subZone where it started, and campfire (true) plus campBuff (the buff's name) when a watched camp buff arrived during the rest. Cities, inns and campfires all set the same resting flag, so the campfire tag is what separates them. A rest without the tag isn't proof it wasn't a campfire, since a buff still running from an earlier stop won't arrive again.

## Camp buff (1.2)

name, gainedAt, gainedAtStr, zone, subZone, and endedAt, endedAtStr when the buff went away. Camp buffs last about an hour after leaving the fire, so gainedAt to endedAt is the buff's life, not the stay. The stay is the length of the rest period the buff tagged.

## Group (1.3)

joinedAt, joinedAtStr, joinedLevel, zone, subZone (where you joined), leftAt, leftAtStr, durationSec, maxSize, and sizes, an array of { at, size } with one item for each change in size, the first being the size at joining. Sizes count you. alreadyGrouped is true when you were already in the group at login or reload, so joinedAt is that moment rather than the real join. A group still open when you log out keeps no leftAt, and the next login opens a fresh record flagged alreadyGrouped. No names or other data about the members are kept.

## Colors

Computed from the quest's level against the player's. Red at 5 or more levels above, orange at 3 or 4 above, yellow from 2 below to 2 above, gray at or below the gray level, green between. The gray level comes from the client's GetQuestGreenRange() when it exists, otherwise from the Classic table (0 up to level 5, level minus floor(level / 10) minus 5 up to 39, level minus floor(level / 5) minus 1 up to 59, level minus 9 at 60).
