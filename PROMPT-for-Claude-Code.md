# Prompt for Claude Code, continuing QuestPaceLog

Unzip `QuestPaceLog-dev.zip` into a folder of your choice, for example `C:\Users\<you>\source\QuestPaceLog-dev`, open Claude Code in that folder, and paste everything below the line.

---

I want to keep developing my World of Warcraft addon, QuestPaceLog, here on my computer. This folder has the current version, 1.2. Read `CLAUDE.md` first. It has the standing rules for this project, and they apply to everything below. Then read `docs/SCHEMA.md` and `CHANGELOG.md`.

## Where things stand

- **1.1** records each quest's own level and quest log color, and tracks when quests in my log turn green, turn gray, or get dropped. I confirmed on September 30 that it works in the real game.
- **1.2** adds the zone at every quest accept, turn-in and rest, and tells campfire rests apart from city and inn rests by watching my own camp buffs. It passes the tests but hasn't been checked in the game yet.

## Set up first

1. **Version control.** Make this folder a git repository if it isn't one, and commit the current state as "QuestPaceLog 1.2, imported." It stays local, don't add a remote.
2. **Tests.** Check whether Lua 5.1 is available (`lua -v`, `lua5.1 -v`). If it isn't, tell me the simplest way to install it on Windows and wait for my OK before installing anything. Then run `lua tests/run_tests.lua`. All 16 tests should pass.
3. **Deploy.** Check that `F:\World of Warcraft\_classic_beta_\Interface\AddOns` exists and whether a `QuestPaceLog` folder is already there. Write a small `deploy.ps1` that copies `QuestPaceLog/` into it, and run it once I say so. Then tell me whether a directory junction would be better than copying, so edits show up after a `/reload`, and wait for my answer before creating one.

## Then check 1.2 in the game with me

Give me a short checklist, in plain language, and wait while I play. It should cover these.

- **Zone.** When I accept or turn in a quest, the chat line should end with where I am, like "in Brill, Tirisfal Glades." `/qpl` should show where each quest took me.
- **Buff names.** At a campfire, after sitting for a minute, `/qpl buffs` should list my buffs. I'll paste the names, and you tell me which `/qpl campbuff add` commands to type for the camp ones. Don't guess buff names yourself.
- **Campfire stays.** When a camp buff arrives while I'm resting, chat should say the rest counts as a campfire rest, and `/qpl report` should show my campfire stays and their average.

If anything doesn't show up, give me `/dump` commands to see what the game actually offers, for example `/dump GetSubZoneText()`, `/dump C_Map.GetBestMapForUnit("player")`, `/dump C_UnitAuras` and `/dump UnitBuff("player", 1)`. I'll paste the output, and you fix the code from that, with a test for the fix.

## After that, ideas to discuss before building

Ask me before starting any of these, one at a time. After each one, run the tests, bump the version, update the changelog and SCHEMA.md, deploy, commit, and tell me what to check in the game.

1. **Group size and how long groups last.** For an article I wrote about grouping, I'd like evidence of how long groups actually stay together. Record when I join and leave a group and the group's size, and whether I was grouped when I turned in each quest. Only counts and times. No other players' names or any other data about them, per the standing rules.
2. **Anything I find while playing.** I'll bring ideas as they come up. Push back if an idea breaks the standing rules or the data format.

## What not to do

- Don't change the meaning or names of any existing saved field. The pipeline that builds my dashboard reads them.
- Don't add anything that reads other players, automates actions, or sends data anywhere.
- Don't edit anything in my WTF folder.

## Timing

The beta ends on October 21, and I need data from real play before then. Checking 1.2 in the game comes first.
