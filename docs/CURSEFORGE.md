# CurseForge listing: Noir Guides

Everything needed to create the project and upload the first file. Each block below is ready to paste into the field it names.

---

## 1. Project settings

| Field | Value |
|---|---|
| Project name | Noir Guides |
| Summary (one line) | Automatic leveling guide for WoW Forever: every race and class, 1 to 60, with an arrow, map pins and a clickable step list. |
| Primary category | Quests & Leveling |
| Other categories | Map & Minimap |
| Game version | WoW Forever (Interface 16001) |
| License | GNU General Public License v3.0 (GPL-3.0-only) |
| Source | https://github.com/MattBiban/NoirGuides |
| Icon | `docs/images/icon-400.png` (400 × 400 PNG) |

---

## 2. Description (paste into the description editor, Markdown)

```markdown
# Noir Guides

**A leveling guide that plays along with you, from level 1 to 60, for every race and class on WoW Forever.**

Noir Guides shows you what to do next, where to go, and moves on by itself when the game confirms you did it. No commands, no setup: log in and follow the arrow.

## What you get

- **Routes for all 10 races and every class.** That covers Human, Dwarf, Gnome, Night Elf and High Order for the Alliance, and Orc, Troll, Tauren, Undead and Windshaper for the Horde: 56 class and race combinations, each with its own class quests and trainer visits.
- **Sections that load by themselves.** Each route is split into sections such as *12-17 The Barrens*. The right one is picked for your race, level and zone, and the next one loads when you finish.
- **Steps grouped by place.** Everything you do at one spot is one step: accept these quests, kill these, hand in those. Each line has its own tick box and ticks itself when the game confirms it.
- **A clickable step list.** Scroll through the whole section, see what's done, and double-click any step to jump to it.
- **Arrow and map pins.** A smooth arrow with the distance in yards, plus pins for the current and next steps on the world map and the minimap.
- **Joins you wherever you are.** Already level 25? Noir Guides reads your quest log and the quests you've handed in, and puts you at the right step. It tells you where it placed you and why.
- **Automation you control.** It accepts and hands in guide quests, marks the best quest reward, takes flights, binds the hearthstone and buys what a step needs. It can also choose rewards and train your spells if you switch those on. Every part has its own switch. Hold Ctrl or Shift at an NPC to do it yourself.
- **Item and target buttons.** Quest items and quest mobs get their own buttons beside the guide window.
- **Trainer visits.** Class trainer visits every few levels, and profession trainers at the ranks WoW Forever gates at skill 50, 125 and 200.
- **Talents, professions, quest cleanup.** A talent build per class with reminders, a profession plan, and a quest log cleanup that never abandons anything unless you tick it.
- **Clean, movable windows.** Resize, move, lock and scale every window. Windows can never open off screen, and settings are kept per profile.

## Getting started

1. Install, then make sure **Noir Guides** is ticked in the AddOns list on the character screen.
2. Log in. A new character gets a short setup wizard. An existing character is placed automatically.
3. Follow the arrow and the step cards. That's it.

Settings: **Escape → Options → AddOns → Noir Guides**, or the menu button on the guide window, or right-click the minimap button.

## How the routes are made

The routes are generated from open quest and world data, then checked by a validator and played through in a simulator. In that simulator the addon plays all 56 characters from level 1 to 60, plus characters joining mid-route at levels 1, 12, 25, 40 and 55, before every release.

## Not included yet

- Dungeon routes and WoW Forever's own new quests are planned for later versions.
- Party features (sharing steps with your group) are planned.

## Feedback and bugs

Open the guide window's menu and choose **Report a problem**. It builds a report you can copy, with your step, position and any errors. Paste it in a comment or an issue.

## Credits

- Quest, NPC, object and item data: [QuestieDB](https://github.com/Questie/QuestieDB) (GPLv3).
- Client tables (zones, maps, flight paths, skills, talents) via [wago.tools](https://wago.tools).

Noir Guides is free software under the GNU General Public License v3.
```

---

## 3. First file upload

| Field | Value |
|---|---|
| File | `dist/NoirGuides-0.2.1.zip` (build with `npm run package` in `tools/`) |
| Display name | Noir Guides 0.2.1 |
| Release type | Beta |
| Game version | WoW Forever (16001) |

**Changelog (paste into the file's changelog field):**

```markdown
## 0.2.1

- Smoother arrow: it now updates every frame and glides when you turn.
- The guide window can be resized from its bottom-right corner.
- The main menu opens beside the guide window instead of over it.
- Easier to read: lighter window, the current step highlighted in the step list, and icons colored by kind (gold for quests, red to kill, purple for items, blue for travel, green for trainers).

## 0.2.0

- First public version: sectioned routes for every race and class from 1 to 60, steps grouped by place with tick boxes, a clickable step list, arrow and map pins, automatic placement for characters of any level, automation with per-part switches, item and target buttons, class and profession trainer visits, settings in the game's options window and a minimap button.
```

---

## 4. Screenshots to take (in game)

CurseForge shows these on the project page. Use 16:9 and hide other UI clutter.

1. The guide window in a starting zone: a step card with several lines, and the step list with the current step lit.
2. The arrow on screen, with the distance, pointing at a quest giver.
3. The world map with the step pins, including a merged pin's tooltip.
4. The minimap with pins and the Noir minimap button.
5. The section picker menu open beside the window.
6. The settings page in the game's options window.
7. The setup wizard on a new level 1 character.
8. Item and target buttons next to the window during a quest.

---

## 5. Notes for the CurseForge review (only if they ask)

- **Original work:** Noir Guides was written from scratch in a clean room. No code, guide text or art from any other guide addon was used. The routes are generated by the project's own tools from QuestieDB and client data. `docs/INDEPENDENCE-REVIEW.md` lists every shipped file and its origin.
- **No third-party libraries:** everything in the zip is the project's own code and generated data.
- **Safe for the client:** the addon writes no macros or key bindings, does not hook or change the world map, minimap, talent or quest log frames, and makes no protected changes in combat.
- **License:** GPL-3.0-only, with the full text in `LICENSE` inside the zip.

---

## Before publishing: checklist

- [ ] Play 0.2.1 in game for a session or two. The simulator passes, but `docs/INGAME-CHECKLIST.md` lists what only the real game can confirm.
- [x] The 400 × 400 icon: `docs/images/icon-400.png`.
- [ ] Take the screenshots above.
- [ ] Create the project, then connect it to GitHub for automatic uploads (`docs/RELEASING.md`). From then on every version tag uploads itself.
- [ ] If CurseForge gives the project a different address than `noir-guides`, update the CurseForge link at the top of `README.md`.
