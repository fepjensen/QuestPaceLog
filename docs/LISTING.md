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

## Images to prepare

- **Logo**, square, at least 400 by 400. An original drawing, not Blizzard art, since the sites show it outside the game. To be made.
- **Screenshots**, taken after the design overhaul, in game, with chat hidden or cropped out so no other player's name or message appears. The welcome window, the dashboard Overview, the Compass, the on-screen tracker, a quest timer in the objective tracker, and the settings window.

## Steps

1. Create a CurseForge author account, then a new project under World of Warcraft with the fields above. Upload the zip by hand the first time. New projects go through a review before they're public.
2. Create a Wago Addons account and a new addon with the same fields and zip.
3. Once both exist, note their project IDs. To have every tagged release upload to both on its own, the IDs go in the toc (`## X-Curse-Project-ID`, `## X-Wago-ID`) and each site's API key goes in the GitHub repo's secrets, which Felips adds himself.
