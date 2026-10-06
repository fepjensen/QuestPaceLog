# Changelog

## 2.4.1, 2026-10-05

- Time played at each level sits a little lower, so the tallest column's time no longer touches the heading's line.

## 2.4, 2026-10-05

- Quest timers now count only the time you played with the quest tracked. Untracking a quest pauses its clock and tracking it again resumes it. Logging out or reloading pauses every clock, so time away doesn't count, and a session that ends without a logout, after a crash or a lost connection, stops its clocks at its last activity. Each quest record keeps its clock (`activeSec`, `activeSince`), and each turn-in keeps the final count (`activeSec` on the entry). `durationSec` is unchanged, still clock time from accept to turn-in.
- Quests accepted before 2.4 start their clock from an estimate, the time you played since accepting them, shown with a ~ (`activeEstimated`). When they were untracked wasn't recorded before.
- Easier to read on parchment. Darker ink, body text one size larger, cream cards that lift the paper under tiles and the report, and a light cream wash that calms the parchment's texture.
- The game's parchment art is cropped to its clean middle, so its worn, burnt edges no longer cut through the tiles and the report box.

## 2.3, 2026-10-05

- Fixed quests wrongly recorded as dropped. The game's quest list leaves out quests under a collapsed zone header, and the addon read that as the quest leaving the log. On 2026-10-05 at 21:57, a level-up marked three open quests dropped this way. The addon now asks the game whether you're still on a quest (C_QuestLog.IsOnQuest), and clears a wrong `droppedAt` and `droppedLevel` when the game confirms the quest is still in your log. Real drops are still recorded.
- Quests under a collapsed header now count in the tracker's "+N more in your log", and keep their green and gray tracking.
- Quest timers only on tracked quests, in the map's quest log, the objective tracker and the addon's tracker. Untracking a quest parks it as backlog, so its timer is hidden, and tracking it again brings the timer back.
- The dashboard, welcome and settings windows are parchment, like the game's quest log, with brown ink text, card-style tiles and chart colors deep enough to read on it. The game's own parchment art is used when the client has it, otherwise a warm parchment color, with darker edges like old paper.
- The Compass graph's labels and lines were dimmed by its own background. Fixed.
- /qpl diag now lists, for each of the game's quest frames, how many lines it looked at and the quest titles it saw, whether each got a timer, the last timer error, and which parchment the client had.

## 2.2, 2026-10-05

- A welcome window explains Bartle's four types of player and lets you pick the one that sounds like you, or let your play decide. It opens by itself the first time, and /qpl type opens it again (`settings.archetype`, `settings.welcomed`). Your type sets the dashboard's first tab and the tracker's lines.
- The Compass still measures how you play. After an hour of play, if your play leans clearly toward another type (25 points or more), the Compass tab shows it with Switch and Keep buttons, and a chat line says so at login, at most once a day (`settings.keptType`, `settings.suggestedAt`).
- A settings window, from right-clicking the tracker or the minimap button, the Settings button on the dashboard, /qpl options, or the game's Options under AddOns. Pick which of 15 lines the tracker shows (`settings.hudStats`), turn quest timers and cheer messages on or off, and change your type.
- Quest timers in the game's own objective tracker and in the quest log on the map, after each quest's title, in gray (`settings.timersInTracker`, `settings.timersInLog`). Long titles are shortened with "..." so the timer stays on the same line. /qpl diag reports which of the game's quest frames were found.
- New look, closer to the game's own windows. Portrait frames, tabs along the bottom edge, the game's status bars and tooltip borders, a round minimap button, and a tracker styled like the objective tracker, with a minus to collapse it (`settings.hudCollapsed`). The game's open, close and tab sounds.
- WoW Forever runs the modern interface (the objective tracker and Edit Mode are in its logs), so the timers target those frames, with the older Classic frames as a fallback.
- Not yet verified in the real Forever client.

## 2.1, 2026-10-04

- On-screen tracker, a small panel that stays up while you play, in combat too. The top follows your lens, for example an XP bar, time to the next level and your goal for an Achiever, or kills and deaths for a Competitor. The bottom lists your 3 newest open quests with a live timer, real clock time since you accepted them, and how many more are in your log. Drag to move it, click to open the dashboard, /qpl hud off hides it (`settings.hud`).
- Fixed the dashboard's X, which handed off to the game's panel manager and did nothing. It now closes the window directly.
- Not yet verified in the real Forever client.

## 2.0, 2026-10-04

QuestPaceLog becomes a tracker for players, not only an evidence logger, with something for each of Bartle's four kinds of player. All of it is about your own character only.

- Achievers. Personal records with a chat line when you beat one (`QuestPaceLogDB.records`, /qpl records). Goals, /qpl goal 20 or /qpl goal 20 2026-10-12 (`QuestPaceLogDB.goal`). Time to the next level at this session's pace, /qpl eta. Each level-up compares the level just finished with the one before.
- Explorers. The game's own Discovered messages with their XP (`discoveries`), flight paths learned (`flightPaths`), every place you stand in (`QuestPaceLogDB.places`), the zones each open quest takes you through (`zones` on the quest record), and a quest journal with the text of quests you accept (`QuestPaceLogDB.journal`, /qpl journal [name]).
- Socializers. Group quests (`suggestedGroup` on the entry), your group's size in each dungeon (`groupSize`), and time spent grouped. Only counts, never who.
- Competitors. Kills and their XP from your own XP lines (`kills`, `killXP`), deaths with time dead and time as a ghost (`deaths`), and honorable kills (`honorKills`). The rival is your own past.
- Gold gained, spent and from quest rewards (`moneyGained`, `moneySpent`, `moneyFromQuests`, `moneyReward` on the entry).
- The dashboard has lenses, Overview, Achiever, Explorer, Socializer, Competitor and Compass. The Compass places your play on Bartle's own graph from what you did. Once you've played 10 minutes, the window opens on the lens your play leans to, marked "(you)". A lens you pick yourself is remembered instead (`settings.lens`). The scope button switches between this session and all sessions.
- Card button and /qpl card, a short summary selected for you to copy and post yourself. Nothing is sent anywhere.
- Records, level and goal messages can be turned off with /qpl cheer off (`settings.cheer`).
- Duel results are left out on purpose, since the game only reports them in a line naming your opponent.
- Not yet verified in the real Forever client. The message-based parts (discoveries, flight paths, kills) use the client's own message text, so they follow its language.

## 1.9, 2026-10-03

- Fixed the donut titles and percentages, which were placed from the middle of the window instead of its top left, so they showed up near the bottom or off screen.
- Time at each level now covers sessions before 1.8 too, estimated from the levels quests and dungeons recorded, with each level-up placed halfway between the last moment at the old level and the first at the new one. Estimated levels are marked in /qpl report and drawn lighter in the dashboard.
- Shorter donut legends, so they don't run into the next donut.
- No change to the saved data format. 1.7's donuts confirmed drawing in the real Forever client on 2026-10-03.

## 1.8, 2026-10-03

- Sessions record `startLevel` and `levelUps`, a list of each level reached and when. Time played at each level is worked out from those, within sessions only, so time logged out never counts. Shown in /qpl report and as columns in the dashboard. Sessions before 1.8 have neither, so they aren't counted.
- Hovering a quest in the dashboard's recent quests shows its quest level and color, your level, where it took you, its time, XP and XP a minute, and its group size.
- The dashboard can be made taller or shorter by dragging its bottom right corner, and it never opens taller than the screen.
- Not yet verified in the real Forever client.

## 1.7, 2026-10-03

- Sessions record `lastActiveAt`, the last moment anything happened, including logout. Time played is lastActiveAt minus startedAt. Older sessions estimate it from their latest timestamp.
- XP per minute played, in /qpl report and in the dashboard. Counts only sessions that tracked XP. Each recent quest in the dashboard also shows its own XP a minute.
- A session with XP but no quests now gets a report instead of "Nothing to report yet."
- Bigger dashboard, 780 by 740. Five tiles (quests turned in, average per quest, XP per minute, time played, resting). Three donut charts replace the bars, for XP from quests against everything else, quest colors at turn-in, and solo against grouped turn-ins. Recent quest bars take the quest's own color. Section headings, gold accents, thousands separators, and the active view's button stays highlighted.
- The donuts are drawn from plain color textures, rotated when the client allows it. Not yet verified in the real Forever client.

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
