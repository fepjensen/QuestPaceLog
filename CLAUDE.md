# QuestPaceLog, notes for Claude Code

## What this is

A small World of Warcraft addon for WoW Forever (Blizzard's 2026 Classic-style game, beta until October 21, 2026, launch November 4). It records Felips' own play on his own characters, when he accepts and turns in quests, the quest's level and color, experience earned, rest periods and dungeon visits. He uses the data as evidence in design criticism he publishes on his site, fjportfolio.com, and shows a trimmed summary of it in the site's Lab section.

Felips is a lawyer building a career in game design criticism, not a programmer. Explain changes in plain language, say what to test in the game, and keep each change small.

## Standing rules

- **Own character only.** Use only events and functions about the player's own character and quest log. Never read, log or inspect other players, never automate any action, never send data anywhere. The code is open source, public at https://github.com/fepjensen/QuestPaceLog. The play data never leaves Felips' computer. Never commit anything from the WTF folder or any saved data.
- **The saved data format is a contract.** A Python pipeline outside this repo reads `QuestPaceLogDB` by field name. Changes are additive only. Never rename or remove a field or change its meaning or type, and keep old saved files loading. Every new field goes into `docs/SCHEMA.md` and `CHANGELOG.md`.
- **Tests for every change.** `luajit tests/run_tests.lua` from the repo root (LuaJIT runs Lua 5.1 code, installed with winget). Add a test for each new behavior. The tests stub the WoW API, so they prove the logic, not the client. Say so when reporting.
- **Unknown API, check in game.** The Forever client reports interface version 16001 and its exact API isn't documented. Write new code defensively (check a function exists, use pcall where a call might fail) and tell Felips which chat line or `/dump` command confirms it works.
- **Version and changelog.** Bump `## Version` in `QuestPaceLog/QuestPaceLog.toc` for each release and add a CHANGELOG entry.
- **Don't touch the WTF folder.** Never edit or delete anything under `F:\World of Warcraft\_classic_beta_\WTF`. The game writes the saved files, and Felips keeps dated backups there.
- **Ask before** installing software, creating links or files outside this repo, or pushing anywhere.
- **Writing style for anything Felips will read** (chat lines, README, commit messages, your replies). No em dashes and no colons in prose. Use periods and commas instead. Existing chat lines follow this already, for example "Resting ends, 1:05."

## Layout

- `QuestPaceLog/` the addon itself, `QuestPaceLog.toc`, `QuestPaceLog.lua`, `README.txt` (player-facing instructions)
- `tests/run_tests.lua` the test harness
- `docs/SCHEMA.md` the saved data format
- `CHANGELOG.md`
- `tools/export_site.py` builds the site Lab page data file (schemaVersion 3) from every saved file and dated backup, read only. `python tools/test_export_site.py` checks it
- `update-site.ps1` runs the export into `F:\Claude Code\portfolio`, checks the site builds, and commits and pushes (deploys) only after Felips types y

## Deploying

The game loads the addon from `F:\World of Warcraft\_classic_beta_\Interface\AddOns\QuestPaceLog`. That folder is a directory junction to this repo's `QuestPaceLog/` folder, made by `deploy.ps1`, so edits show up after `/reload` with no copy step. Never delete the junction's contents. To remove it, delete only the link, as the comment in `deploy.ps1` shows.
