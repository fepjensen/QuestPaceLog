Adventurer's Almanac
====================

Quest timers, leveling stats and your player type, for WoW Forever.
Type /almanac to open it. Formerly QuestPaceLog, and the folder keeps that
name so saved data from earlier versions keeps loading.

Privacy.
It records only your own character, on your own computer. It never reads
other players, never automates anything and never sends data anywhere.
Group stats are counts only, never names.

Install.
The CurseForge app or the Wago app installs it and keeps it up to date.
Choose WoW Forever as the game version. To install by hand, copy this
QuestPaceLog folder into World of Warcraft\_forever_\Interface\AddOns, so
you end up with Interface\AddOns\QuestPaceLog\QuestPaceLog.toc. If it
doesn't show up after a game update, tick "Load out of date AddOns" in the
game's AddOns list.

Getting started.
The first time you log in, a welcome window explains the four kinds of
player Richard Bartle described, Achievers, Explorers, Socializers and
Competitors, and asks which sounds like you. Your pick decides what the
dashboard and the tracker show first. You can also let your play decide.
/qpl type opens the window again.

The dashboard.
/almanac, a click on the minimap button, or a click on the tracker opens it.
Five figures across the top, then cards. The Overview shows where your
experience comes from, the difficulty of the quests you turn in, your last
eight quests with their time and XP a minute, and the time each level took.
Each type has its own tab, and the Compass places your real play on Bartle's
graph. The buttons at the top switch between this session and all time.
Hover any figure to see what it counts. Export opens the full report,
selected so Ctrl+C copies it, and its Card button swaps in a short summary
you can post yourself.

The on-screen tracker.
A small panel, in combat too, with the lines you pick and your newest
tracked quests, each with its timer. Drag it where you like, click it for
the dashboard, right-click it for the settings.

Quest timers.
Each tracked quest shows how long you've worked on it, after its title in
the objective tracker and in the quest log on the map. The clock runs only
while you play with the quest tracked. Untracking a quest parks it and
pauses its clock, and logging out pauses every clock. Quests from before
version 2.4 start from an estimate, shown with a ~.

Settings.
Right-click the tracker or the minimap button, type /qpl options, or open
the game's Options and look under AddOns. Pick the tracker's lines, size and
lock, turn the quest timers and the chat lines on or off, size the
dashboard, and show or hide the minimap button.

Parked quests.
Untrack a quest and it's marked backlog, so its time stays out of your
averages. Track it again and it counts again. For a quest you already turned
in, /qpl skip and part of its name marks it, /qpl unskip undoes it. Say why
you parked one with /qpl why and a letter, then part of its name if it isn't
the latest.
  a  too hard for my level
  b  objective scarce or contested
  c  out of my route
  d  needs a group
  e  not worth it right now
  f  just untracked it, still doing it next
  g  don't remember

Campfires.
The game flags a city, an inn and a campfire the same way, as resting. The
addon tells a campfire apart by its camp buffs. Only "Boosted Rest" is
watched at first. Sit at a fire, type /qpl buffs to see your buffs' names,
then /qpl campbuff add and the name to watch another.

Commands.
  /almanac or /qpl         the dashboard, /qpl show all for every session
  /qpl log                 this session's quests in chat
  /qpl report              this session's summary in chat, /qpl report all
  /qpl export              the full report in a window to copy
  /qpl card                your share card, selected to copy
  /qpl type                pick your player type
  /qpl options             the settings
  /qpl goal 20             a level goal, /qpl goal 20 2026-12-01 with a date
  /qpl eta                 time to the next level at this session's pace
  /qpl records             your personal records
  /qpl journal and a name  the text of a quest you accepted
  /qpl hud on or off       show or hide the tracker
  /qpl cheer on or off     the record, level and goal messages
  /qpl start               start a new session without logging out
  /qpl diag                what the addon found in the game's quest frames

Your data.
Everything is saved in your SavedVariables folder, in QuestPaceLog.lua,
a plain text file the game writes when you log out or reload.

Bugs and ideas.
https://github.com/fepjensen/QuestPaceLog/issues
Include the output of /qpl diag and a screenshot.

Open source under the MIT License. Made by Felipe Jensen, fjportfolio.com.
