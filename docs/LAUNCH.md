# Launch and publishing plan

WoW Forever launches November 4, 2026. Part A is the addon working in the launch client. Part B is publishing it for other players. Decisions that are Felips' to make are marked **Decision**. Updated 2026-11-01.

## Where things stand on November 1

- The launch client is installed at `F:\World of Warcraft\_forever_`, version 1.60.1.70707. That's interface 16001, the same number the beta reported, so the toc needs no change.
- QuestPaceLog 3.0.0 is linked into `_forever_\Interface\AddOns` with `deploy.ps1`, so the game loads it straight from the repo.
- The beta client's `WTF` folder is gone, and with it all raw beta play data and its dated backups. No copy exists on drives C, E or F, or in the Recycle Bin. The only surviving record is the summary the site export made on October 3, in the portfolio repo (`src/data/lab/questpacelog.json`) and live on the Lab page. It covers 20 sessions for Zeembie and 1 for Ziza. Play from October 3 to the end of the beta is lost unless a copy exists somewhere else.
- `update-site.ps1` refuses to replace that beta summary, so the first launch update can't erase it by accident.

## Part A. The addon at launch

### Done

- Interface number checked against the client, 16001.
- `deploy.ps1` links into `_forever_` by default.
- `tools/export_site.py` reads `_forever_\WTF` and labels the data "WoW Forever".
- The player README and code comments no longer mention the beta.
- Version 3.0.0.

### Launch day checklist

Run it on November 4, on the character you'll play. Each line names what confirms it.

1. The welcome window opens on first login. Pick a type.
2. Accept a quest. The chat line ends with the zone and the quest level.
3. The objective tracker and the map's quest log show a gray timer after tracked quests. If not, `/qpl diag` and send the lines.
4. Untrack a quest for a minute and track it again. Its timer picks up where it stopped.
5. Join a group. "Joined a group of 2."
6. Kill something, then `/qpl report`. A "Kills" line.
7. Enter a new subzone. It shows in the Explorer tab.
8. Die, if it happens. "Back on your feet after" with the time.
9. `/qpl journal` and part of a quest name shows its text.
10. At a campfire, `/qpl buffs`. Camp buff names can change at launch.
11. The dashboard, settings window and tracker look right. A screenshot of each.
12. Watch chat for "Interface action failed because of an AddOn" during combat. If it appears, the objective tracker timers get turned off by default.

### Still open

- **Decision** how the Lab page shows beta and launch data. My recommendation is a phase switch on the page, launch data first and the October 3 beta summary as its own tab. It needs the beta JSON kept as its own file in the portfolio repo and a small page change. Until then, `update-site.ps1` stops before replacing the beta data.
- **Decision** whether to remove the old link in `_classic_beta_\Interface\AddOns`. It still points at the repo. If the beta folder is ever deleted, a careless delete could follow the link into the repo. The repo is safe on GitHub either way, but removing only the link is the tidy fix.
- **Question for Felips** whether a copy of the beta `WTF` folder exists anywhere else, a cloud drive, another computer or an external disk. If it does, the October 3 to 21 data can still be recovered.

## Part B. Publishing

### Where

| Site | Why |
|---|---|
| CurseForge | The largest audience. Guides for WoW Forever say the CurseForge app lists Forever as its own game version |
| Wago Addons | Growing fast. Guides say the Wago app also lists WoW Forever |
| GitHub Releases | Where the code already lives, and the home of every zip |

Those listings come from third-party guides. The sites' own upload forms are the proof, so check them when creating each project.

**Decision** which sites. My recommendation is all three.

### When

Publish after the launch day checklist passes, not at launch hour. Many features have only been verified in the beta, and a first version that breaks on day one costs more trust than a two-day wait. Mark the first upload as a beta release on CurseForge and Wago for the first week, then switch to a normal release.

| Date | Step |
|---|---|
| November 1 to 3 | Decisions below, the public README, packaging, accounts and draft projects |
| November 4 | Launch day checklist in game, fixes |
| November 5 or 6 | First public release, 3.0.x, as a beta release |
| About November 12 | Normal release, once the first players' reports are in |

### Steps

1. **Pick the public name.** "Quest Pace Log" describes the original evidence tool. A player-facing name could say more. Renaming later resets players' settings, because the saved data is named after the addon, so decide before the first release. **Decision**
2. **Write a public README.md** at the repo root. What the addon does, the four types and the Compass, screenshots, the commands, and a plain privacy statement. "QuestPaceLog records only your own character, on your own computer. It never reads other players, never automates anything and never sends data anywhere." The CurseForge and Wago descriptions reuse it.
3. **Screenshots.** The beta screenshots survived in `_classic_beta_\Screenshots`, including the dashboard, the Compass and the timers in the map's quest log. Take launch ones for the welcome window and the settings window.
4. **Packaging.** Only the `QuestPaceLog/` folder goes in the zip, not the tests, the site tools or the notes. A small GitHub Action zips it whenever a version tag like `v3.0.1` is pushed, and attaches the zip to a GitHub Release.
5. **Accounts and projects.** Create the CurseForge and Wago projects with the README text, the category "Quests & Leveling", the in-game book icon and the screenshots. Upload the zip by hand the first time. New CurseForge projects go through a review before they're public, so allow a few days.
6. **Automate later.** Once both projects exist, the BigWigs packager (the standard GitHub Action for WoW addons) can upload each tagged release to CurseForge, Wago and GitHub at once. It needs each site's project ID in the toc and each site's API key stored as a GitHub secret, which Felips adds himself.
7. **Policy check.** Blizzard's UI Add-On Development Policy asks that add-ons be free, readable and free of in-game ads or donation requests. QuestPaceLog fits, and its MIT license is fine on all three sites.
8. **After release.** Bug reports go to GitHub Issues, with `/qpl diag` output and a screenshot. Every release gets a CHANGELOG entry, which the sites show as release notes. The saved data format stays additive, now for other players' saved files too.

### Decisions to make before November 5

1. The sites, recommended CurseForge, Wago and GitHub.
2. The public name.
3. Brazilian Portuguese at release or in the first update. Recommended the first update, once the text settles.
4. How the Lab page shows beta and launch data.
