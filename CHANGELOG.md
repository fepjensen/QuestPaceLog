# Changelog

## 1.6, 2026-10-01

- A book button by the minimap opens and closes the dashboard. Drag it to move it. The game remembers where you put it in its own layout file, so nothing new is saved by the addon.
- The dashboard's report text uses the same smaller font as the rest of the window, without blank lines between rows, so more of it fits.
- The quest color note counts turn-ins without a recorded color, those from before 1.1.
- No change to the saved data format. 1.5's window confirmed working in the real Forever client on 2026-10-01. The button isn't verified yet.

## 1.5, 2026-10-01

- The /qpl show window is now visual. Four tiles at the top show quests turned in, average time per quest, the share of XP from quests, and time resting with campfire stays. Below them are a bar for XP from quests against everything else, a bar of quest colors at turn-in in the quest log's own colors, and the last 8 finished quests as bars, so a slow one stands out. The full text report is still underneath and can be copied.
- The window refreshes on its own when you turn in a quest while it's open.
- No change to the saved data format. Not yet verified in the real Forever client. If the tiles and bars can't draw, chat says so once and the text report still shows.

## 1.4, 2026-10-01

- /qpl show opens a dashboard window with the report, and buttons for This session and All sessions. It can be moved, scrolled, and closed with Escape, and its text can be selected and copied. /qpl show all opens straight on All sessions.
- /qpl report all prints the report across every session. The wait between one session's last turn-in and the next session's first accept doesn't count as a gap.
- No change to the saved data format.
- The window uses the client's standard frame templates when they exist and falls back to a plain window when they don't. Not yet verified in the real Forever client.

## 1.3, 2026-10-01

- Groups. Each session has a new `groups` list. A group record opens when you join, notes every change in size, and closes when you leave, with how long it lasted. Only member counts are kept, never names or anything else about other players.
- Each quest turn-in records `turnedInGroupSize`, on the entry and on the quest record, 1 when solo.
- The turn-in chat line ends with "in a group of N" when grouped. /qpl shows it, and /qpl report shows the session's groups, their average length, the largest size, and how many turn-ins happened in a group.
- Reads GetNumGroupMembers, or the older GetNumPartyMembers and GetNumRaidMembers. Not yet verified in the real Forever client.

## 1.2, 2026-09-30

- Zone, subzone and map ID at every accept and turn-in, on the entry and on the quest record. Zone and subzone at the start of every rest period. The /qpl log shows where a quest took you.
- Campfire stays. Watches the player's own buffs (UNIT_AURA on "player") for camp buffs, "Boosted Rest" by default. A rest period in which one arrives is tagged campfire, and its length is the stay. Camp buffs gained are also logged per session. /qpl report shows campfire stays and their average.
- /qpl buffs lists current buffs. /qpl campbuff add, remove, or on its own to show the watched list, stored in QuestPaceLogDB.campBuffNames.
- Supports both aura APIs, C_UnitAuras.GetAuraDataByIndex and UnitBuff. Confirmed working in the real Forever client on 2026-10-01.

## 1.1, 2026-09-30

- Records each quest's own level at accept (`questLevel`) and its quest log color at accept and turn-in (`colorAtAccept`, `colorAtTurnIn`).
- New `QuestPaceLogDB.quests` table, one record per questID across sessions. Notes the level at which each quest in the log turns green, turns gray, or is dropped without a turn-in. Scans on login, reload and every level-up (`PLAYER_LEVEL_UP`).
- New `/qpl why <a-g> [name]` command, an optional note on why a quest was parked. Stored as `reason`. Not used as evidence.
- `/qpl report` ends with counts of quests that went gray while in the log and quests dropped.
- `/qpl` log lines show the quest level and the why note.
- Supports both quest log APIs, `C_QuestLog.GetInfo` and the older `GetQuestLogTitle`. Confirmed working in the real Forever client on 2026-09-30.

## 1.0, 2026-09-24

- Sessions, quest accept and turn-in times, durations, player level at each end.
- Backlog flag from untracking a quest, `/qpl skip` and `/qpl unskip`.
- Per-quest XP reward and session XP split.
- Dungeon visits with boss kills and wipes.
- Rested-state periods.
