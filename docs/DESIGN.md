# Design

How Adventurer's Almanac looks, and the checklist every window is reviewed against before a release. The goal is that it reads like part of the game, made by someone who does this for a living.

## Principles

1. **Looks like the game.** The game's own frames, tabs, buttons, checkboxes, tooltips and fonts. The dashboard is a quest log page, parchment with brown ink. The on-screen tracker is the game's dark tooltip look, like the objective tracker beside it.
2. **One idea per card.** Each card answers one question, named in its title ("Where your experience comes from"). Numbers sit in KPI tiles, comparisons in bars and donuts.
3. **Every number explains itself.** Hovering a figure shows what it counts and how. Text in `UI.TIPS`.
4. **Never empty, never broken.** Before there's data a card says what fills it ("Finish a quest and it shows up here"). Nothing ever shows nil, NaN, a negative time or a raw field name.
5. **Words for players.** No version numbers, field names or slash commands in the windows, except where a command is the answer. No em dashes and no colons in prose.

## Grid

| Token | Value | Where |
|---|---|---|
| Window | 800 by 664, scale 70 to 150% | `WIN_W`, `WIN_H`, `windowScale` |
| Outer margin | 16 | `PAD` |
| Gap between cards | 8 | `UI.GAP` |
| Card inner padding | 12 | titles and rows start at x 12 |
| KPI row | 5 tiles of 147 by 58, at y -68 | `UI.KPI_W`, `UI.KPI_H`, `UI.TOP` |
| Card rows | Overview at -138, -298, -506, tabs at -138 and -480 | `BuildWindow` |
| Tracker | 260 wide, scale 70 to 150% | `UI.HUD_W`, `hudScale` |
| Settings | 620 by 690 | `UI.BuildOptions` |

Cards line up on both edges of the KPI row. Two cards side by side split the width with one gap between them.

## Type

The game's fonts, recolored as ink without a shadow on parchment (`UI.Fonts`).

| Role | Font | Color |
|---|---|---|
| Value in a tile | GameFontHighlightLarge | ink |
| Card title | GameFontNormal | heading brown |
| Body and rows | GameFontHighlight | ink |
| Labels and notes | GameFontHighlightSmall | ink, or soft brown |
| Tracker | GameFontHighlight, GameFontNormal for quest titles | the game's white and gold |

## Color

| Token | Use |
|---|---|
| `UI.INK`, `UI.INK_HEAD`, `UI.INK_SOFT` | body, headings, soft labels |
| `UI.EDGE` | card borders and dividers |
| `GOLD` | quests, the default accent |
| `LENS_COLOR` | one color per player type, achiever gold, explorer teal, socializer violet, competitor red, Compass brown |
| Quest difficulty | the game's own quest colors, gray, green, yellow, orange, red |

A type's color marks it everywhere, its tab's KPI accents, its bars and its corner of the Compass.

## Components

| Component | Code | Notes |
|---|---|---|
| Window | `UI.Window` | the game's portrait frame, falls back to plainer templates |
| Card | `UI.Card` | parchment patch with a brown border and an optional title |
| KPI tile | `UI.KPI` | value, label, 3px accent, hover tip |
| Bar | `UI.Bar` | status bar with a soft track |
| Donut | `UI.Donut`, `UI.FillDonut` | ring with a legend of colored swatches |
| Tabs | `PanelTabButtonTemplate` | under the window, the player's own type marked "(you)" |
| Button, check, stepper | `UI.Button`, `UI.Check`, `UI.Stepper` | the game's templates |
| Tooltip | `UI.ShowTip` | the game's tooltip, gold title, white text |

## Empty states

| Where | Text when there's nothing yet |
|---|---|
| Recent quests | Finish a quest and it shows up here, with its time and XP a minute. |
| Time at each level | a line saying levels appear once one is played start to end |
| KPI tiles | "none yet" |
| Compass | the scores wait for 10 minutes of play |

## Review checklist

Run before every release. The automatic part runs with the tests.

**Automatic, `luajit tests/run_tests.lua`**

- [ ] No text overflows its width, spills out of its card, or overlaps other text, on every tab, both scopes, a busy character and a new one
- [ ] Nothing sticks out of its window, in the dashboard, welcome, settings, export and the tracker with every line on
- [ ] Each window opens with every template missing, falling back without an error

**By eye, from in-game screenshots at 100% and 70% scale**

- [ ] Every card's edges line up with the KPI row above it
- [ ] Titles are the same size and color everywhere, values stand out from labels
- [ ] Text is readable on the parchment, no light text on light paper
- [ ] Each tab's color matches its type, and the "(you)" tab is the chosen type
- [ ] Every figure has a hover tip that says what it counts
- [ ] A new character sees empty states, never zeros pretending to be data or blank cards
- [ ] The tracker reads at a glance in combat, labels left, values right
- [ ] The minimap button sits on the ring and drags around it
- [ ] Quest timers sit after the title in the objective tracker and the map's quest log, and only for tracked quests
- [ ] No developer words, version numbers or field names in any window
