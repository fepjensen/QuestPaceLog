# Adventurer's Almanac

**Quest timers, leveling stats and your player type, for WoW Forever.**

Adventurer's Almanac keeps a record of how you actually play. It times every quest you track, counts the experience each one pays, notes where quests send you, how long each level takes, when you rest, group up, explore or die. Then it shows all of it in a dashboard built around the four kinds of player the game designer Richard Bartle described, Achievers, Explorers, Socializers and Competitors.

*Formerly QuestPaceLog.*

## Features

- **Quest timers** after each tracked quest's title, in the objective tracker and the quest log on the map. The clock only runs while you play with the quest tracked, so parked quests and time away don't count.
- **A dashboard** (`/almanac`) with an Overview and a tab for each player type. Experience from quests against everything else, quest difficulty at turn-in, your last quests as bars, and the time each level took.
- **Pick your type** in a welcome window, or let your play decide. The Compass places your real play on Bartle's own graph, and tells you if you lean another way.
- **An on-screen tracker** with the lines you choose, time to the next level, XP a minute, your goal, kills, discoveries, time grouped and more.
- **Records and goals.** Your best XP a minute on a quest, your best session, a level goal with a countdown, and each level compared with the one before.
- **For explorers,** discoveries and their XP, flight paths, places visited, the quests that sent you farthest, and a journal of the quest text you read.
- **A share card,** a short summary of your session you can copy and post yourself.

## Privacy

Adventurer's Almanac records only your own character, on your own computer. It never reads other players, never automates anything and never sends data anywhere. Group stats are counts only, never names.

## Install

Install it with the CurseForge app or the Wago app, choosing WoW Forever as the game version, and it stays up to date by itself.

To install by hand, download the zip from [Releases](https://github.com/fepjensen/QuestPaceLog/releases), and copy its `QuestPaceLog` folder into `World of Warcraft\_forever_\Interface\AddOns`. The folder keeps its original name so saved data from earlier versions keeps loading.

## Commands

| Command | What it does |
|---|---|
| `/almanac` or `/qpl show` | Opens the dashboard |
| `/qpl report` | Prints this session's summary in chat, `/qpl report all` for every session |
| `/qpl type` | Opens the welcome window to pick your player type |
| `/qpl options` | Opens the settings |
| `/qpl goal 20` | Sets a level goal, with an optional date like `/qpl goal 20 2026-12-01` |
| `/qpl eta` | Time to the next level at this session's pace |
| `/qpl records` | Your personal records |
| `/qpl journal` and part of a name | The text of a quest you accepted |
| `/qpl card` | Your share card, selected to copy |
| `/qpl cheer off` | Turns off the record, level and goal messages |
| `/qpl diag` | What the addon found in the game's quest frames, for bug reports |

## Bugs and ideas

Open an issue on [GitHub](https://github.com/fepjensen/QuestPaceLog/issues). For a bug, include the output of `/qpl diag` and a screenshot.

## License

Open source under the [MIT License](LICENSE). Made by Felipe Jensen, who writes about game design at [fjportfolio.com](https://fjportfolio.com).
