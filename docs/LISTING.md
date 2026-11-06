# Store listings

Ready-to-paste text and settings for the CurseForge and Wago projects. Felips creates the accounts and projects himself, since they need his sign-in.

## Both sites

| Field | Value |
|---|---|
| Name | Adventurer's Almanac |
| Summary | Quest timers, leveling stats and your player type. A dashboard for Achievers, Explorers, Socializers and Competitors. |
| Game version | WoW Forever (1.60.1, interface 16001) |
| Main category | Quests & Leveling |
| Other categories | Achievements, Map & Minimap |
| License | MIT |
| Source | https://github.com/fepjensen/QuestPaceLog |
| Issues | https://github.com/fepjensen/QuestPaceLog/issues |
| Description | The README.md at the repo root, from the first line down to Privacy, plus the Commands table |
| File | The zip from the GitHub release, `AdventurersAlmanac-vX.Y.Z.zip` |
| Release type | Beta for the first week, then Release |
| Changelog | That version's section of CHANGELOG.md, which the GitHub release already shows |

## Images

- **Logo**, `media/logo.png`, 512 by 512, drawn for the addon (no Blizzard art). `media/logo.svg` is its source, render it again with any browser after an edit.
- **Screenshots**, `media/store/`, cropped from launch play on 2026-11-05 to the addon's own windows. Upload them in this order, with these captions.

| File | Caption |
|---|---|
| 01-dashboard.jpg | The dashboard. Where your experience comes from, how hard your quests were, your last quests and the time each level took. |
| 02-compass.jpg | The Compass places your real play on Bartle's graph of player types. |
| 03-explorer.jpg | A tab for each type. The Explorer's discoveries and the quests that sent you farthest. |
| 04-quest-timers-map.jpg | Quest timers in the map's quest log, counting only time played with the quest tracked. |
| 05-quest-timers-tracker.jpg | The on-screen tracker, and the timers in the game's objective tracker. |
| 06-export.jpg | The full report, selected to copy. |

The Explorer and Export shots predate two small wording changes in 4.0's final build, a shorter tile label and "Timed quests" in the report. Retake them in a later version if they should match exactly. Still missing, the welcome window and the settings window.

## Steps

1. Create a CurseForge author account, then a new project under World of Warcraft with the fields above. Upload the zip by hand the first time. New projects go through a review before they're public.
2. Create a Wago Addons account and a new addon with the same fields and zip.
3. Once both exist, note their project IDs. To have every tagged release upload to both on its own, the IDs go in the toc (`## X-Curse-Project-ID`, `## X-Wago-ID`) and each site's API key goes in the GitHub repo's secrets, which Felips adds himself.
