# Launch and publishing plan

WoW Forever's beta ends October 21, 2026 and the game launches November 4. This is the plan for both dates, in two parts. Part A is what changes in the addon for launch. Part B is how the addon gets published for other players. Decisions that are Felips' to make are marked **Decision**.

## Timeline at a glance

| When | What |
|---|---|
| Now to October 21 | Verify 2.2 in the beta, fix what the screenshots show, collect the last beta data, take screenshots for the addon page |
| October 21 to November 3 | Write the public README, set up packaging, create the addon pages as drafts so any review finishes before launch |
| November 4 | Install the launch client, run the launch-day checklist, publish 3.0.0 |
| First week after launch | Answer bug reports, fix fast, start the Brazilian Portuguese translation |

## Part A. Changes for launch

### 1. The new game folder

The launch client will most likely install next to the beta, in a new folder such as `_classic_` instead of `_classic_beta_`. Three things point at the beta folder today.

- `deploy.ps1` links `_classic_beta_\Interface\AddOns\QuestPaceLog`. It needs the launch folder, as a parameter so both can be linked.
- `tools/export_site.py` reads `_classic_beta_\WTF`. It needs to read both and label each character's data with the phase it came from.
- `CLAUDE.md` names the beta WTF folder in the "don't touch" rule. The rule covers the launch WTF folder too.

### 2. The interface number

The beta reports interface 16001. On launch day, check the live number in game with `/dump (select(4, GetBuildInfo()))` and put it in `## Interface:` in the toc. Until then, "Load out of date AddOns" in the AddOns list keeps it loading.

### 3. Beta data becomes an archive

If beta characters are wiped at launch, as they usually are, each new character starts with empty saved data, since the data is saved per character. The beta data stays where it is, in the beta WTF folder and its dated backups. Before the beta client is uninstalled, copy that folder's QuestPaceLog files somewhere safe outside the game folder.

On the site, the Lab page should show beta and launch data separately, so readers can compare them. That needs an additive change to the site's data format (schema 4), with a phase on each character, "beta" or "launch", and a phase filter on the page. **Decision** whether the Lab page shows both phases side by side, or launch data with a link to the beta archive.

### 4. Verify everything not yet checked in the real client

Run this list on launch day, with `/qpl diag` for the quest frames. Each line names the chat line or screen that confirms it.

- Quest accept and turn-in lines in chat, with zone and quest level
- Groups, "Joined a group of 2"
- Deaths, "Back on your feet after"
- Kills, a "Kills" line in `/qpl report`
- Discoveries and flight paths, in the Explorer tab
- The quest journal, `/qpl journal` and part of a quest name
- Honorable kills, if the launch has PvP
- Camp buffs, `/qpl buffs` at a campfire, since buff names can change at launch
- The welcome window on a new character, the settings window, the tracker, and the timers in the objective tracker and the map's quest log

### 5. Watch for interface errors

The quest timers change the text of the game's own objective tracker and quest log. That's normally safe, but the objective tracker also holds quest item buttons, which the game protects in combat. During the first launch sessions, watch for "Interface action failed because of an AddOn" in chat. If it appears, the fix is to turn the tracker timers off by default and keep them in the addon's own tracker.

### 6. Defaults for new players

- The welcome window opens on first login. Keep it.
- The tracker is on and starts beside the objective tracker. Check that the spot works on a common screen size, 1920 by 1080.
- Cheer messages are on. Keep them, they're part of the player tool now.
- Remove the README's notes about the beta's saved data bug if the launch client doesn't have it.

### 7. Translation

Chat lines the addon reads, like discoveries and kills, already follow the client's language. The addon's own text is English only. Brazilian Portuguese is the natural first translation, since the site is bilingual. It means moving every visible string into one table per language. About a day of work, best done after launch, once the text is stable. **Decision** whether ptBR ships at launch or in the first update.

### 8. Version 3.0.0

Launch is a good moment for 3.0.0. The interface number changes, the data starts fresh, and it's the first public release.

## Part B. Publishing the addon

### 1. Where

| Site | Why | Notes |
|---|---|---|
| CurseForge | The largest audience, and the CurseForge app installs and updates addons for players | New projects go through a review before they're public. Allow a few days |
| Wago Addons | Growing fast, with its own app | Free account, upload in the browser |
| GitHub Releases | Already where the code lives, and the source of every zip | Every release attaches the zip |
| WoWInterface | Older, smaller, still used | Optional |

What I can't confirm from here is whether CurseForge and Wago will list WoW Forever as a game version at launch. Each site's upload form lists the game versions it supports. If Forever isn't there yet, publish on GitHub Releases first and add the others when they list it.

**Decision** which sites. My recommendation is CurseForge, Wago and GitHub.

### 2. What goes in the zip

Only the `QuestPaceLog/` folder, with the toc, the Lua file and the player README. Not the tests, the site export, the launch plan, `CLAUDE.md` or the prompt file. Those stay in the repo, which is public anyway.

### 3. How a release gets built

Start simple and automate once the pages exist.

1. **First release by hand.** A small GitHub Action zips the `QuestPaceLog/` folder whenever a version tag like `v3.0.0` is pushed, and attaches it to a GitHub Release. Upload that same zip to CurseForge and Wago in their web forms.
2. **Later, fully automatic.** The BigWigs packager, the standard GitHub Action for WoW addons, builds the zip and uploads it to CurseForge, Wago, WoWInterface and GitHub from one tag push. It needs a `.pkgmeta` file, each site's project ID in the toc (`## X-Curse-Project-ID`, `## X-Wago-ID`, `## X-WoWI-ID`), and each site's API key stored as a GitHub secret. The addon sits in a subfolder of the repo, so the packager needs that set in `.pkgmeta`, or the toc moves to the repo root.

### 4. The addon page

- **A README.md at the repo root.** There's only the in-game README.txt today. It needs what the addon does, the four types and the Compass, screenshots, the commands, and a plain privacy statement. CurseForge and Wago descriptions can reuse it.
- **The privacy statement.** "QuestPaceLog records only your own character, on your own computer. It never reads other players, never automates anything and never sends data anywhere." This is a real selling point, and it's true by design.
- **Screenshots** of the welcome window, the dashboard's Overview and Compass, the tracker, and a timer in the objective tracker. Take them in the beta before October 21, with a fresh character for the welcome window.
- **The icon** is the in-game book icon, already set in the toc for the game's AddOns list. Outside the game, avoid Blizzard's logos.
- **The category** on CurseForge is "Quests & Leveling".

**Decision** the public name. "Quest Pace Log" describes the original evidence tool. A player-facing name could say more, but renaming the folder later breaks players' saved settings, so it's worth deciding before the first public release.

### 5. Rules to respect

Read Blizzard's UI Add-On Development Policy before publishing. In short, add-ons must be free, their code must be readable, and they can't advertise or ask for donations in the game. QuestPaceLog already fits, and the MIT license is fine on all three sites.

### 6. After publishing

- Bug reports go to GitHub Issues. Ask reporters for the output of `/qpl diag` and a screenshot.
- Every release gets a CHANGELOG entry, which the sites show as release notes.
- The saved data format stays additive, now for other players' saved files too, not only the site's export.
