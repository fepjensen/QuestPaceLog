QuestPaceLog
============

What it does.
Listens for the two events WoW Forever's own client already fires for your
own actions, QUEST_ACCEPTED and QUEST_TURNED_IN, and timestamps them. It
never reads hidden information, never automates anything, and never touches
another player's data, so it sits inside a normal addon's allowed behavior,
the same category as a log uploader or a quest tracker.

Install.
1. Find your WoW Forever installation folder (the folder next to _retail_
   and _classic_ that Forever uses, check your Battle.net app if unsure).
2. Open its Interface\AddOns folder.
3. Copy this whole QuestPaceLog folder in there, so you end up with
   Interface\AddOns\QuestPaceLog\QuestPaceLog.toc and QuestPaceLog.lua.
4. If it does not show up in the in-game AddOns list, open that list and
   enable "Load out of date AddOns", since Forever's interface version
   number can change between beta builds.

Use.
1. Log in on the character you want to track. A session starts on its own,
   no command needed, you'll see "New session started" in chat.
2. Play normally. Every quest accept and turn-in prints a line to chat with
   its elapsed time from session start, and its duration once turned in.
3. Type /qpl at any point to see the full list so far.
4. Type /qpl report at the end of the session for a computed summary,
   quest count, average duration, longest and shortest quest, the
   average gap between one turn-in and the next accept, and how many
   quests you leveled up during.

/reload does not start a new session, you'll see "Reload detected,
continuing the session" instead, so long as the beta's SavedVariables bug
(next section) hasn't already wiped what was there. /qpl start still works
if you ever want to force a new session on purpose without logging out, say
after a long AFK break.

Each quest also records your character's level at accept and at turn-in,
so the log and the report both show, for example, "level 4" when a quest
didn't change your level, or "level 3 to 4" when it did.

Backlog quests. Some quests get picked up and deliberately left alone, not
actively worked toward, so their real accept-to-turn-in time is huge and
meaningless as pace. A flagged quest still shows up in /qpl and in the
report, marked backlog, but its time is left out of the average, longest,
shortest, and gap numbers.

The easy way to flag one. Untrack it from your normal quest log or the
on-screen objective tracker, the same click you'd already do to get a quest
off your screen. QuestPaceLog notices and marks it backlog on its own, no
command needed, you'll see a chat line confirming it. Track it again later
and it goes back to counting toward pace, also on its own.

This only works while the quest is still open in your log, since untracking
is something you can only do to an open quest. For one you've already
turned in, use the manual commands instead. Type /qpl skip right after
accepting one to flag it, or /qpl skip <part of its name> to flag one you
didn't catch in time, even one already turned in.

Changed your mind, or picked one back up sooner than planned? /qpl unskip
undoes the most recently flagged quest, or /qpl unskip <part of its name>
targets a specific one. It goes back to counting toward pace normally. This
works no matter which way the quest got flagged, by tracking it, by hand, or
both.

XP. Each quest's own turn-in reward now shows in the log and the report,
for example "150 xp". The report also totals up all XP earned this session
and splits it into XP from quest turn-ins against XP from everything else,
kills, first-time discovery of an area, and so on. There isn't a reliable
way to tell which specific kill's XP belongs to which specific quest, the
game doesn't expose that to an addon, so this doesn't pretend to. The
session-wide split is the honest version of that same question, roughly
how much of your leveling came from quest content against incidental
grinding.

Dungeons. Entering and leaving a dungeon is logged the same way a quest is,
with the time in between, your level at each end, and which bosses went
down or wiped, from the game's own ENCOUNTER_END event. Shows up in
/qpl report as its own section, name, difficulty, total time, boss count.

Resting. WoW Forever flags your character as resting in a city, an inn, or
near a campfire, all the same flag, this addon doesn't try to tell them
apart. Each time that flag turns on and off gets logged, with a short chat
line each way, and the report totals up how much of the session was spent
resting and how many separate rest periods there were.

Quest difficulty and reasons. Each quest now records its own level when
you accept it, and the color the quest log gave it then, red, orange,
yellow, green, or gray. Every time you level up, the addon checks your whole
quest log and notes the level at which each quest turned green and the level
at which it turned gray, with a short chat line when one goes gray. A quest
that leaves your log without being turned in is noted as dropped. This works
across sessions, so a quest parked on Monday and finished on Thursday still
has one clean record. Quests that were already in your log when you
installed this version get tracked from that moment on.

When you park a quest, say why with /qpl why and a letter.
  a  too hard for my level
  b  objective scarce or contested
  c  out of my route
  d  needs a group
  e  not worth it right now
  f  just untracked it, still doing it next
  g  don't remember
/qpl why a tags the most recent backlog quest that has no reason yet.
/qpl why b elixir tags the most recent quest with "elixir" in its name,
even from an earlier session. /qpl report now ends with how many quests went
gray while still in your log, how many of those you turned in anyway, and
how many you dropped.

Where. Every accept and turn-in now notes the zone and the named spot
inside it, for example "Brill, Tirisfal Glades," and so does the start of
every rest period. The /qpl log shows where a quest took you, like "Brill,
Tirisfal Glades to Magic Quarter, Undercity."

Campfires. The game uses the same resting flag for a city, an inn and a
campfire, so a rest period on its own can't tell them apart. Sitting at a
WoW Forever campfire for a minute gives camp buffs, and the addon watches
your own buffs for them. When one arrives during a rest period, that rest
counts as a campfire rest, and its length is how long you stayed at the
fire. /qpl report shows how many campfire stays you had and their average.
Only "Boosted Rest" is watched at first. To add the others, sit at a fire,
type /qpl buffs to see your buffs' exact names, then /qpl campbuff add
followed by the name. /qpl campbuff on its own shows the list, and
/qpl campbuff remove takes a name off it.

Groups. Joining and leaving a group is logged with how long the group held
together and how many people were in it, counting you. Only the count is
kept, never who was in it. Each turn-in also notes the group size at that
moment, so the turn-in line says "in a group of 3" when you weren't solo.
/qpl report shows the session's groups, their average length, and how many
turn-ins happened while grouped.

Dashboard. /qpl show, or a click on the book button by the minimap, opens
a window you can move, scroll, and close with Escape. Drag the book button
to put it wherever you like, the game remembers the spot. At the top, tiles show quests turned in, average time per quest,
XP per minute played, time played, and time resting. Below them, three
donut charts show where your XP came from, the colors your quests had at
turn-in, and how many turn-ins were solo or in a group. Your last 8
finished quests appear as bars in their quest color, with their XP a
minute, so a slow one stands out. The full report is underneath. The
window updates by itself when you turn in a quest while it's open. Its two buttons switch between this
session and all sessions together. You can select the text in it and copy
it with Ctrl+C. /qpl report all prints the all-sessions report in chat.

Getting the report out.
The report prints to your chat window, so you can select and copy it from
there. The raw data is also written to your SavedVariables file,
WTF\Account\<your account>\<realm>\<character>\SavedVariables\QuestPaceLog.lua,
a plain text Lua file, written the moment you reload the UI or log out.
Paste either the chat report or that file's contents back into the project
chat, and it turns into the written half of the case study, the average
active and idle read, the framework tie-in, the counterargument. That part
stays a human judgment call on purpose, the addon only removes the clock-
watching.

Known limitation.
This uses QUEST_ACCEPTED, QUEST_TURNED_IN, QUEST_WATCH_LIST_CHANGED,
PLAYER_XP_UPDATE, ENCOUNTER_END, PLAYER_UPDATE_RESTING, PLAYER_LEVEL_UP, UNIT_AURA (your own buffs only), and GROUP_ROSTER_UPDATE (group size only), plus the game's own quest log functions to read each quest's level. All of these
are long-standing, widely used events, the same ones dungeon and XP addons
have relied on for years, but Forever is still in beta, so if any of them
stops firing or fires with different data, the affected part will just go
quiet, nothing will error loudly. If a session's data looks incomplete, say
so and the event names can be checked against whatever's changed.
