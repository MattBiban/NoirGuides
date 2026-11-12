# Noir Guides

**An automatic leveling guide for WoW Forever, from level 1 to 60, for every race and class.**

Noir Guides shows you what to do next and where to go, and moves on by itself when the game confirms you did it. Log in and follow the arrow. No commands, no setup.

[Download on CurseForge](https://www.curseforge.com/wow/addons/noir-guides) · [Releases](../../releases) · [Report a bug](../../issues)

---

## Features

- **Every race and class.** All 10 races: Human, Dwarf, Gnome, Night Elf and High Order for the Alliance; Orc, Troll, Tauren, Undead and Windshaper for the Horde. That's 56 class and race combinations, each with its own class quests.
- **Sections that load by themselves.** The route is split into sections such as *12-17 The Barrens*. The right one is chosen for your race, level and zone, and the next loads when you finish.
- **Steps grouped by place.** Everything at one spot is one step, with a tick box per line that ticks itself when the game confirms it.
- **Clickable step list.** Scroll the whole section; double-click any step to jump to it.
- **Smooth arrow and map pins.** The arrow shows the distance in yards. Pins mark the current and next steps on the world map and the minimap.
- **Starts wherever you are.** An existing character is placed from its quest log and the quests it has handed in. Chat tells you where it landed.
- **Automation you control.** It accepts and hands in guide quests, takes flights, binds the hearthstone and buys what a step needs. It can also choose rewards and train spells. Each part has its own switch; hold Ctrl or Shift at an NPC to do it yourself.
- **Item and target buttons.** Quest items and quest mobs get their own buttons.
- **Trainer visits.** You're sent to your class trainer every few levels, and to profession trainers at WoW Forever's skill gates (50, 125, 200).
- **Talents, professions and quest cleanup.** A talent build per class, a profession plan, and a quest log cleanup that abandons nothing unless you tick it.
- **Movable, resizable windows** that can never open off screen, with settings kept per profile.

## Install

1. Download the latest `NoirGuides-<version>.zip` from [CurseForge](https://www.curseforge.com/wow/addons/noir-guides) or the [releases](../../releases).
2. Unpack it into your game's `Interface\AddOns\` folder. You should end up with `Interface\AddOns\NoirGuides\NoirGuides.toc`.
3. On the character select screen, open **AddOns** and make sure **Noir Guides** is ticked.

## The first login

Log in and Noir Guides starts by itself:

- **The guide window** opens on the left. On top is a stack of cards, one per step on screen, each line with its own tick box. Below it is a scrolling step list of the whole section, with the current step highlighted and finished steps dimmed. Drag the bottom-right corner to resize the window.
- **The arrow** appears near the top of the screen and points to the current step's place.
- **The minimap button** sits on the minimap's rim. Left-click it to hide or show every Noir window; right-click it for the menu.
- **A new level 1 character** gets the **setup wizard** a few seconds after login: a few questions and the recommended starting section for your race.
- **An existing character** gets the section that fits its level and is placed inside it automatically.

**No command is needed.** Everything you might want to do by hand is a click away:

- **The window's menu** (its menu button, or right-click the header): choose another section, find your place again, skip a step or go back, options, setup wizard, quest cleanup, talents, professions, report a problem.
- **The step list:** double-click or right-click a step to go to it, skip it or report it.
- **A line on a card:** tick it to mark it done, untick it to open it again.

`/noir` is an optional extra: `/noir` opens the settings and `/noir help` lists the rest.

## Settings

Press **Escape → Options → AddOns → Noir Guides**, or choose **Options** in the window's menu. The tabs are General, Guide window, Navigation, Automation, Route, Advanced and Profiles. Windows can be moved, locked, scaled and reset.

## Reporting a problem

Open the window's menu and choose **Report a problem**. It builds a report with your step, position and any errors, ready to copy into an [issue](../../issues).

---

## For developers

The routes are generated from open quest and world data by the tools in `tools/`, checked by an independent validator, and played through by the real addon in a simulator before every release.

Everything runs from `tools/` with Node 22 or later:

```
cd tools
npm install          # once: the Lua VM and parser the tests use (nothing of them ships)
npm run fetch        # once: QuestieDB and the client tables into tools/data/ (not committed)
npm test             # Node tests: data, planner, validator, packaging, clean room
npm run test:lua     # lint and the addon's Lua tests against a mock client
npm run routes       # generate NoirGuides/Routes/ and NoirGuides/Data/
npm run sim          # the real addon plays all 56 characters to 60, plus mid-route joiners (~45 min)
npm run package      # dist/NoirGuides-<version>.zip, version from NoirGuides.toc
```

`npm run fetch` needs 7-Zip or the Windows `tar.exe`. `npm run sim -- --race Undead` plays one race.

### Releasing

Releases are automatic. Bump `## Version:` in `NoirGuides/NoirGuides.toc`, add the matching entry at the top of `CHANGELOG.md`, commit, then tag and push:

```
git tag v0.2.2
git push origin main --tags
```

The `Release` workflow (`.github/workflows/release.yml`) runs the tests, builds the zip, publishes a GitHub release and uploads the file to CurseForge. One-time setup is in [docs/RELEASING.md](docs/RELEASING.md).

### Documents

- `CHANGELOG.md`: what each version brings.
- `docs/INGAME-CHECKLIST.md`: what only the real game can confirm.
- `docs/ENGINE-NOTES.md`: how the engine works and every assumption about the client.
- `docs/INDEPENDENCE-REVIEW.md`: every shipped file and where it comes from.
- `docs/routes/`: the route report, the simulator report and notes on the data.
- `DESIGN.md`: colors, type and measures of the interface.

## Credits

- [QuestieDB](https://github.com/Questie/QuestieDB) (GPLv3): quest, NPC, object and item data.
- Client tables (zones, maps, flight paths, skills, talents) via [wago.tools](https://wago.tools).

## License

Noir Guides is free software under the [GNU General Public License v3](LICENSE).
