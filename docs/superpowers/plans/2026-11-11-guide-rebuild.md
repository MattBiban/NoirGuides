# Noir Guides guide rebuild: route format 3, engine v3, interface v2 (0.2.0)

> **For agentic workers:** you get one task ID from this file. Read **Global constraints**, **Route format 3** and your task, and nothing else in this file needs to be followed for your task. Work test-first: write the failing tests your task names, see them fail, then write the code. Commit only your own paths.

**Goal:** rebuild Noir Guides so it plays exactly like the behavior the owner approved: routes in sections of bundled steps, an engine that follows the game on its own (no command needed), a window with a card stack and a scrolling step list, map pins and an arrow that behave as specified, windows that never leave the screen, and characters that join the route at any level.

**Spec (the only source for reference behavior):** `docs/superpowers/specs/2026-11-11-guide-behavior.md`, called "the spec" below; "spec 4.5" means its section 4.5, "gap #14" a row of its section 8 table. **Earlier plan (format and tools the implementers know):** `docs/superpowers/plans/2026-11-11-full-build.md`. **Look:** `DESIGN.md`.

This plan gives contracts, files, names, numbers and acceptance checks, not finished code. Every number taken from the spec is written here; do not change one without the owner.

## Global constraints

- **Clean room (hard rule).** Nobody working on this plan opens the old fork folder the old fork's folder (outside this repository), any code of the reference addon, or any of its guides, not even to compare. The spec is the only source for how the reference behaves. The "port rule" of earlier plans no longer applies: nothing is ported. `tools/compare_fork.js` is not run (task X2 removes it). No file under `NoirGuides/` or `tools/` (outside `tools/data/`) may contain the strings the reference addon's name or prefix; `tools/test/independence.test.js` keeps checking this.
- **License.** Every source file starts on line 1 with `-- Noir Guides, GPLv3. See LICENSE.` (Lua, XML as `<!-- Noir Guides, GPLv3. See LICENSE. -->`) or `// Noir Guides, GPLv3. See LICENSE.` (JavaScript). No third-party library (no LibStub, LibDBIcon, Ace): everything is written here.
- **Client.** WoW Forever, `## Interface: 16001`, Lua 5.1 (no `goto`, no `//`, no integer division, `unpack` not `table.unpack`). Feature-detect every API that differs between Classic builds; list each assumption you could not verify in `docs/ENGINE-NOTES.md` with the next free number.
- **Forbidden in the addon:**
  - registering `COMBAT_LOG_EVENT_UNFILTERED` or `COMBAT_LOG_EVENT` (the Forever client shows its blocked popup even inside `pcall`);
  - `CreateMacro`, `EditMacro`, `DeleteMacro`, `SetBinding`, `SetBindingClick`, `SetBindingMacro`, `SetOverrideBinding*` (key bindings come only from `Bindings.xml`);
  - writing to `StaticPopupDialogs` or changing `StaticPopup1`..`StaticPopup4` (confirmations use the addon's own dialog, `Panel.Confirm`);
  - `SetFontObject` with an EditBox or with any font object that is not one of the client's own named ones (it crashes the client; fonts are set by file with `SetFont`);
  - any protected call in combat (`InCombatLockdown()` true): secure buttons are created, changed, shown, hidden and moved only out of combat;
  - calling a method that changes the world map, the minimap, the talent frame or the quest log frame, or hooking them. Own frames may be parented or anchored to them.
  - Professions are read by skill line ID (`GetProfessions`/`GetProfessionInfo`/`C_SkillInfo`/skill list), never by spell names.
- **Never skip silently.** Every time the engine moves past a step, or completes a line, without the game confirming it in front of the player, it records a reason in the why-log (`Why.Add`), shown in the step's tooltip in the step list and by `/noir why`.
- **Nothing needs a command.** Every behavior in spec 6.2 happens by itself, and every command has a mouse path (spec 6.3). A test that drives the addon by `client:slash` counts as covering a command only; behavior tests use clicks and game events.
- **Never off-screen.** Every frame the addon creates and shows is kept fully inside `UIParent` when it opens, is dragged, grows, or when the UI scale or resolution changes (`Noir.Screen`, task E1). Every UI test ends with `eq(client:offScreen(), {})`.
- **Races:** Human, Dwarf, Gnome, NightElf, HighOrder (Alliance); Orc, Troll, Tauren, Undead, Windshaper (Horde). HighOrder and Windshaper are the Skyborne races (Zephras Isle, area 16593, continent 2991). Race masks exceed 32 bits: use `hasBit` in JavaScript. Class tokens: WARRIOR PALADIN HUNTER ROGUE PRIEST SHAMAN MAGE WARLOCK DRUID.
- **Data** is in `tools/data/` (gitignored; QuestieDB `forever_db.json`, `vanilla_db.json`, wago CSVs). New client tables are added to `tools/fetch_data.js` and fetched with `npm run fetch` in `tools/`.
- **Tests.** In `tools/`: Node `npm test`; Lua `npm run test:lua` (one file: `node harness/run.js <part of name>`); routes `npm run routes`; simulator `npm run sim` (about 45 minutes for everything; `-- --race Undead` for one race). All of `npm test` and `npm run test:lua` must pass before every commit. Never weaken or delete a test to make it pass, except where your task names a test file to replace. Never change files while a test run is in progress.
- **Git.** Task C1 creates the branch `rebuild-0.2` from `main`; every task commits there. The author is configured. Stage only your task's paths (`git add <paths>`, never `git add -A`). Streams commit in parallel: on an `index.lock` error wait a few seconds and retry. End every commit message with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` (or the line for the model you run on, as your session tells you). Never push, never merge to `main`, never make a release.
- **Honesty.** A fact that is not in the data is not invented: mark it `verified = false`, list it in the task's notes file (`docs/routes/DATA-NOTES.md` for the planner, `docs/ENGINE-NOTES.md` for the addon), and keep the route playable without it.
- **The look.** Colors, type, sizes and textures come from `DESIGN.md` and `UI/Theme.lua` only. Task E5 rewrites the layout sections of `DESIGN.md`; `tools/test-lua/theme.lua` keeps the two in step.

## Task graph

```
C1 ──┬── P1 → P2 → P3 ─────────────────────────────┐
     │                                              ├── X1 → X2
     └── E1 → E2 → E3 → E4 ─┬─ E5 ─┐                │
                            ├─ E6 ─┤                │
                            ├─ E7 ─┼── E8 ──────────┘
                            ├─ E9 ─┤
                            └─ E10 ┘
```

- **C1** comes first and alone.
- **Stream P** (`tools/` planner and emitter, `NoirGuides/Routes/`, `NoirGuides/Data/`) and **stream E** (`NoirGuides/` without `Routes/` and `Data/`, `tools/harness/`, `tools/test-lua/`) run in parallel after C1. Stream E never edits `Routes/` or `Data/`; stream P never edits anything else under `NoirGuides/`.
- Inside stream E, **E5, E6, E7, E9 and E10 run in parallel** after E4 (each edits only its own files; the toc is final after E1). **E8** runs after all five.
- **X1** needs P3 and E8. **X2** needs X1.

Between C1 and X1 the addon does not play (C1 retires the format 2 engine). That is expected on the branch; `npm run sim` is not part of any acceptance before X1.

## Route format 3 (the contract between planner and engine)

One file per race, `NoirGuides/Routes/<faction>-<race>.lua` (lowercase), 10 files, same names as today. Each file is a list of sections; each section a list of steps; each step a list of lines.

```lua
-- Noir Guides, GPLv3. See LICENSE.
-- Generated by tools/build_routes.js from QuestieDB Forever <release>. Do not edit.
Noir.Route("horde-undead", {
  format = 3, race = "Undead", faction = "Horde",
  sections = {
    {
      id = "undead-01-06-deathknell",            -- unique in the file; levels padded to two digits
      name = "1-6 Deathknell",                    -- level range and main zone
      names = { WARRIOR = "1-5 Deathknell" },     -- optional: the name for a class whose range differs
      group = "Horde", subgroup = "1-20",         -- group: the faction's main route; subgroup: level band
      minLevel = 1, maxLevel = 9,                 -- maxLevel optional: above it the section is outleveled
      zone = 85,                                  -- main zone (AreaTable ID)
      start = true,                               -- the default start for this file's race; exactly one per file
      when = nil,                                 -- optional condition (see Conditions)
      loop = nil,                                 -- optional: true wraps to the first step once at the end
      noAuto = nil,                               -- optional: { questId, ... } automation never touches here
      next = {                                    -- candidates in order; the first that exists and applies wins
        { section = "undead-06-11-tirisfal-glades" },
        { section = "undead-06-10-the-barrens", when = { class = { "HUNTER", "SHAMAN" } } },
      },
      steps = {
        {
          id = "t364.a365",                       -- stable step identity, unique in the section
          at = { zone = 85, x = 30.84, y = 66.2, r = 10 },
          text = "Shadow Priest Sarvis stands by the crypt doors, north of the graveyard.",
          lines = {
            { kind = "turnin", quest = 364, npc = 1569 },
            { kind = "accept", quest = 365, npc = 1569, requires = { 364 } },
          },
          targets = { friend = { 1569 } },
        },
        {
          id = "o365", at = { zone = 85, x = 32.63, y = 63.5, r = 40 },
          lines = { { kind = "objective", quest = 365, index = 1, npc = 1501 } },
          targets = { enemy = { 1501 } }, items = { 2856 },
          reminder = { ends = "turnin365" },
        },
        { id = "l7@85", at = { zone = 85, x = 31.0, y = 64.0 }, lines = { { kind = "grind", level = 7 } } },
        { id = "t365", label = "turnin365", at = { zone = 85, x = 30.84, y = 66.2, r = 10 },
          lines = { { kind = "turnin", quest = 365, npc = 1569 } } },
      },
    },
  },
})
```

### Places

`{ zone = areaId, x = 0..100, y = 0..100, r = yards or nil, nearest = true or nil }`. `x`, `y` are percent of that zone's map. `r` is the arrival radius in yards: a positive `r` completes a `goto` line and marks the place reached for the arrow; `r = 0` draws a pin and no arrow; `r = nil` gives arrow and pin and never completes on arrival. `x = 0, y = 0` means "this zone, place unknown" (arrival = being in the zone). `nearest = true` on several places of one step: only the closest is the arrow's target.

### Section fields

| Field | Type | Rule |
|---|---|---|
| `id` | string | `^[a-z0-9%-]+$`, unique in the file |
| `name` | string | `^%d+%-%d+ .+$` or `^%d+ .+$` |
| `names` | table | optional; keys class tokens, values as `name` |
| `group` | string | `"Alliance"` or `"Horde"` for the main route; other groups (dungeons, side content) are later |
| `subgroup` | string | `"1-20"`, `"20-30"`, `"30-40"`, `"40-50"`, `"50-60"` from `minLevel` (below 20 → `"1-20"`, else `floor(min/10)*10` to `+10`) |
| `minLevel`, `maxLevel` | 1..60 | `minLevel <= maxLevel` |
| `zone` | number | positive AreaTable ID |
| `start` | true | exactly one section per file |
| `when` | condition | optional |
| `loop` | true | optional |
| `noAuto` | array of quest IDs | optional |
| `next` | array of `{ section, when }` | each `section` exists in the same file; may be empty only on the last section of the chain |
| `steps` | array | 1 to 400 steps |

### Step fields

| Field | Type | Rule |
|---|---|---|
| `id` | string | `^[%w%.%-%+@#:]+$`, unique in the section |
| `at` | place | optional; the step's place (pin and arrow) |
| `text` | string | optional, at most 160 characters; the planner's instruction note in Noir's own words |
| `title` | string | optional, at most 24 characters; shown on the card's badge instead of the number |
| `lines` | array | 1 or more lines |
| `when` | condition | optional; a step that does not apply does not exist for the character |
| `minLevel`, `maxLevel` | 1..60 | optional |
| `label` | string | optional, `^[%w_]+$`, unique in the section |
| `requires` | string | optional; a label in the same section |
| `reminder` | `{ ends = "next" or label }` | optional; the label must be on a later step |
| `skip` | array of skip conditions | optional |
| `load` | string | optional; a section ID of the same file loaded when this step becomes current |
| `items` | array of item IDs | optional; for item buttons |
| `targets` | `{ enemy = {npcIds}, friend = {npcIds} }` | optional; for target buttons |
| `path` | `{ points = { {x=,y=}, ... }, loop = true or nil }` | optional; needs `at` (its zone); drawn on the world map, `loop` makes the arrow follow it |

### Lines

`*` marks a required field. Every line may also carry `at` (a place; the line's own place, else the step's), `when` (condition), and `npc`, `object` or `item` where the table says so.

| `kind` | Fields | Active? | Done when (engine, task E3) |
|---|---|---|---|
| `accept` | `quest*`, `npc`/`object`/`item`, `manual`, `ifDone` (quest ID), `requires` (quest IDs) | yes | the quest is in the log or handed in, or an accept event for it arrived during the step or at most 2 s before the step became current; with `ifDone`, passed at once (state `skip`, a why entry of kind `condition`) when that quest is not handed in, except while an earlier line of the same step still hands that quest in or accepts it (state `todo`, or `missing` waiting on a detour): then it waits for that line (same-step rule, approved in X1 review 2); a later accept line of the same quest on the step is hidden while an earlier one is not passed (one line per any-of prerequisite) |
| `turnin` | `quest*`, `npc`/`object`, `reward` (1..6), `manual`, `skipIfMissing`, `skipIfIncomplete` | yes | the quest is handed in, or a hand-in event for it arrived during the step or at most 5 s before the step became current; `skipIfMissing`/`skipIfIncomplete` complete it (with a why entry) when the quest is not in the log / not ready |
| `objective` | `quest*`, `index*` (1..n), `cap`, `skipIfMissing`, `npc`/`object`/`item` | yes | that objective is finished, or its count reaches `cap`, or the quest is complete or handed in; a quest with no objectives reads as one 0/1 objective that is done when the quest is complete |
| `collect` | `item*`, `count*` (0..1000), `quest` | yes | the bags hold `count`; done and shown full when `quest` is complete or handed in; `count = 0` hides the line |
| `goto` | `at*` | yes when `at.r` is a number > 0, else passive | the player is within `at.r` yards (in the zone when `x = y = 0`) |
| `getflight` | `node*`, `npc` | yes | the node is known, or was just flown from or to, or the discovery message arrived |
| `fly` | `from*`, `to*` (taxi node IDs) | yes | the player is on a flight that started during the step, or lost control within 1.5 s after picking a destination, or stands within 60 yards of the destination's flight master |
| `transport` | `mode*` (`zeppelin`, `boat`, `tram`, `portal`), `at*` (dock), `to*` (place) | yes | the player is in `to`'s zone (and within `to.r` when both ends share a zone) |
| `sethearth` | `npc` | yes | the bind is confirmed at this step's inn, or the hearthstone is already bound there |
| `hearth` | `to*` (place) | yes | a successful Hearthstone (item 6948) or Astral Recall (spell 556) cast during the step, or the player is at `to` |
| `grind` | `level*` (2..60), `percent` (0..99) | yes | the level is above `level`, or at `level` with at least `percent`% of the level's XP (no `percent`: reaching `level`) |
| `train` | `spell`, or (`skill` and `rank` 1..4), or (`class` and `level` 2..60, a class trainer visit), `npc` | yes | the spell is known; for a profession rank, the skill's cap covers the rank (75, 150, 225, 300); for a class trainer visit, the character is at least `level` and has opened and closed that trainer's window since reaching it (or since the step became current) |
| `vendor` | `npc*`, `buy` = `{ item*, count* }` | yes | a merchant window opened (at `npc` when the client gives the NPC) and closed during the step |
| `use` | `item*` | passive | puts the item on an item button while the step is on screen |
| `target` | `npc*`, `enemy` (bool) | passive | adds the NPC to the target buttons |
| `note` | `text*` (at most 160) | passive | never blocks |
| `manual` | `text*` (at most 160) | yes | only when the player ticks it |

### Conditions (`when`, on sections, steps and lines)

`{ class = token or {tokens}, notClass = ..., race = name or {names}, notRace = ..., profession = skillLineId }`. Every key given must hold (and); a list means any of them (or); `notClass`/`notRace` exclude. `profession` holds when the character has learned that skill line or planned it in settings (`Professions.IsPlanned`).

### Skip conditions (`skip`, on steps)

Each entry `{ kind = ..., ..., jump = label or nil }`; when one holds while the step is current, the step is passed (or the place jumps to `jump`) and the why-log says which. Kinds: `onquest {quest}`, `notonquest {quest}`, `complete {quest}`, `notcomplete {quest}`, `turnedin {quest}`, `notturnedin {quest}`, `level {level, percent}` (reached), `below {level}` (not reached), `maxlevel {level}` (player above it), `skill {skill, value}` (at or above), `item {item, count}` (have at least), `zone {zone}` (player in it), `bound {zone}` (hearthstone bound in it).

### Validation rules (both validators, identical wording)

`Routes.Check(data)` in Lua (task C1) and `checkRoute3(route)` in `tools/planner/format3.js` (task C1) return `nil`/`null` for a valid file, else one sentence naming the first three problems as `section <id> step <id> <problem>` and "and N more". The rules, each with its own test case:

- R1 `format` is 3; `race` and `faction` known and matching.
- R2 `sections` is a non-empty array; section `id`s unique and well formed; exactly one `start`.
- R3 section `name`, `group`, `subgroup`, `minLevel`, `maxLevel`, `zone` as in the table.
- R4 every `next.section` exists in the file; no cycle through `next` unless a section on it has `loop`.
- R5 `steps` has 1 to 400 entries; step `id`s unique in the section and well formed.
- R6 every place is valid (zone positive whole number, `x`, `y` in 0..100, `r` nil or a number in 0..500).
- R7 every line has a known `kind` and its required fields with the right types; unknown keys on a line or step are refused.
- R8 `text` and `note`/`manual` texts at most 160 characters; `title` at most 24.
- R9 conditions use only the known keys with known class tokens and race names; skip conditions use known kinds with their fields.
- R10 `label`s unique in the section; `requires`, `reminder.ends` and `jump` name an existing label (`ends` on a later step); `load` names a section in the file.
- R11 `path` only with `at`; points in 0..100.
- R12 `items` and `targets` hold positive whole numbers.

A file that fails is refused whole and reported in `/noir problems` (and by the bug report): showing part of a broken route would hide steps without saying so.

### Generated data files

Unchanged names under `NoirGuides/Data/`: `Names.lua` (`Noir.Data.quests/npcs/objects/items[id] = "name"`, every ID the routes use, including `items` and `targets`), `Zones.lua` (`Noir.Data.zones[areaId] = { uiMap, name, continent }`), `Flights.lua` (`Noir.Data.flights[node] = { name, zone, x, y, factions }`). Line texts are built by the engine (`UI/Text.lua`) from the line and these names; only step `text` and `note`/`manual` lines carry sentences.

## Saved variables (schema 2)

Task E1 raises the schema from 1 to 2 and migrates instead of resetting:

```lua
NoirGuidesDB = {
  schema = 2,
  profiles = { Default = { <option key> = value, positions = { [windowKey] = { point, relPoint, x, y, w, h } } } },
  defaultProfile = "Default",
}
NoirGuidesCharDB = {
  schema = 2,
  profile = "Default",
  owner = "<UnitGUID('player')>",
  guide = {
    section = "<section id>" or nil,
    how = "auto" | "hand" | "wizard" | "next" | "step",
    places = { ["<section id>"] = { step = "<step id>", n = <index>, sig = "<signature>", reminders = { ["<step id>"] = true }, ticks = { ["<step id>"] = { [lineIndex] = true } } } },
    wizard = true or nil,           -- the setup wizard has been shown or closed for this character
    setup = { groupQuests = false, auctionHouse = true },
  },
  why = { ... },                    -- as today
  professions = { ... }, talents = { ... },  -- as today
}
```

Migration from schema 1: `NoirGuidesDB.options` becomes `profiles.Default` (automation keys `accept`/`turnin` → `autoQuests`, `flight` → `flights`, `hearth` → `hearth`, `gossip` → `dialogue`; `window`/`arrow` places → `positions`); `NoirGuidesCharDB.progress` (format 2 places) is dropped with one why-log entry of kind `route` saying the route changed to sections and the place will be found again.

---

## C1 Format 3 contract, validators, samples and cutover

**Files.** Create `tools/planner/format3.js`, `tools/test/format3.test.js`, `tools/test-lua/sample/v3/horde-undead.lua`, `tools/test-lua/sample/v3/alliance-human.lua`, `tools/test-lua/sample/v3/data.lua`, `tools/test-lua/sample/format3-cases.lua`. Rewrite `NoirGuides/Routes.lua`, `tools/test-lua/routes.lua`, `tools/test-lua/sample/helper.lua`. Reduce to skeletons `NoirGuides/Progress.lua`, `NoirGuides/Automation.lua`, `NoirGuides/UI/Text.lua`, `NoirGuides/UI/Window.lua`, `NoirGuides/UI/Arrow.lua`, `NoirGuides/UI/Map.lua`, `NoirGuides/Menu.lua`. Delete `tools/test-lua/progress.lua`, `placement.lua`, `window.lua`, `text.lua`, `arrow.lua`, `map.lua`, `automation.lua`, `menu.lua`, `sim.lua` and the format 2 samples `tools/test-lua/sample/horde-undead.lua`, `alliance-human.lua`, `data.lua` (their behavior is rewritten and retested by E3 to E9 and X1). Guard `NoirGuides/Cleanup.lua` and `NoirGuides/Diagnostics.lua` so they run without the old Progress. Mark the whole-character test in `tools/test/sim.test.js` with `{ skip: "format 3 rebuild: task X1 restores this test" }` and nothing else in that file.

**Steps.**
1. `git switch -c rebuild-0.2` from `main`.
2. Write the failing tests, then the code.

**Interfaces produced.**
- `checkRoute3(route) -> null | string` and `RULES` (array of `{ id: "R1".."R12", text }`) from `tools/planner/format3.js`; `route` is the JavaScript object with the same shape as the Lua table.
- `Noir.Route(id, data) -> boolean` (registers a format 3 file; never raises), `Routes.Check(data) -> nil | string`, `Routes.Get(id)`, `Routes.Ids()`, `Routes.ForRace(race, faction) -> id or nil`, `Routes.rejected[id]`. Format 2 is refused with "it is in format 2 and this version of the addon reads format 3".
- On registration each step gets `n` (its 1-based position in the section) and each section gets `file` (the route ID); nothing else is added.
- Skeleton modules: line 1 license, a header comment with the contract of the task that rewrites it (copied from this plan), `Noir.<Module> = Noir.<Module> or {}`, and nothing that registers events.
- `sample3(opts)` in the helper: a client whose toc swaps `Data/` for `tools/test-lua/sample/v3/data.lua` and `Routes/` for the two v3 sample files.
- The samples: `horde-undead.lua` has three sections (`undead-01-03-deathknell` start, `undead-03-05-tirisfal-glades`, `undead-05-06-silverpine-forest`) chained by `next`, with one conditional `next` (`class = "HUNTER"` to the third), together at least 30 steps using every line kind and every step field at least once: a step bundling two accepts and a turn-in, a step bundling objectives of two quests, a reminder ending at a label, a step with `requires`, a skip condition with `jump`, a rogue-only step, a step with `minLevel` above the route's estimate, a step with `maxLevel`, a `path` with `loop`, `nearest` places, `items` and `targets`. `alliance-human.lua` has one section of four steps. `data.lua` names everything they use.

**Failing tests first.**
- `tools/test/format3.test.js`: "every case in format3-cases.lua gets the expected verdict from checkRoute3" (cases read through `tools/harness/vm.js`); "both v3 samples are valid"; "each rule R1 to R12 has at least one failing case"; "the message names at most three problems and counts the rest".
- `tools/test-lua/routes.lua`: "every case in format3-cases.lua gets the same verdict from Routes.Check as from checkRoute3" (the expected strings are in the case file, so both sides compare against the same text); "a format 2 file is refused with the format sentence and listed in /noir problems"; "a refused file does not stop the next file from registering"; "steps get n, sections get file, and nothing else is added"; "ForRace finds the file for the character's race and faction".
- `tools/test-lua/addon.lua` keeps passing (every toc file exists; engine reads no missing global).

**Acceptance.** In `tools/`: `npm test` and `npm run test:lua` pass; `node -e "require('./planner/format3')"` loads; `git grep -n "action =" -- NoirGuides/*.lua NoirGuides/UI` finds nothing outside `Routes/`.

---

## Stream P: planner and emitter (`tools/`, `NoirGuides/Routes/`, `NoirGuides/Data/`)

The planner (`planRoute`, `layerClasses`, `validateRoute` of format 2 actions) is kept as it is. A new emitter stage turns each race's layered action list into format 3.

### P1 Bundling actions into steps

**Files.** Create `tools/planner/bundle.js`, `tools/test/bundle.test.js`. Modify `tools/lib/quests.js` only to export what bundling needs (objective count and kinds, quest-starter and usable items, prerequisites).

**Interfaces consumed.** `planRoute`, `layerClasses` (route `{ id, race, faction, steps }` with format 2 actions, some with `when = { class }`), `validateRoute(...).levels`, `loadDb`, `lib/geo.js distance`.

**Interfaces produced.**
- `bundleSteps(db, route, levels) -> { steps: Step3[], origin: number[][] }`: `steps` in format 3 step shape (no `text` yet); `origin[i]` lists the indices of the format 2 actions that step `i` came from, in order.
- `flatten(steps) -> action[]`: the format 2 action sequence a format 3 step list stands for (one action per active line, grind steps included); used by P2, P3 and the validators.
- `RADIUS` (frozen): `{ npc: 10, flightmaster: 10, dock: 15, goto: 20, area: 40, zoneOnly: 0 }` yards; `BUNDLE_YARDS = 30`, `OBJECTIVE_YARDS = 150`.

**Rules.**
- Consecutive accept, turn-in, getflight and sethearth actions at the same NPC or object, or within `BUNDLE_YARDS` of the first action's place in the same zone, form one step; their lines keep the planner's order.
- Consecutive objective actions within `OBJECTIVE_YARDS` of the first form one step. Each quest gives one `objective` line per objective index (from QuestieDB's objectives; a quest without objectives gives `index = 1`). A line whose place is more than `BUNDLE_YARDS` from the step's `at` carries its own `at` with `r = RADIUS.area`.
- A getflight followed by a fly at the same flight master is one step. Every other fly, transport, travel and hearth action is its own step (`goto` for travel with `r = RADIUS.goto`; transport with `at.r = RADIUS.dock`).
- Actions with different `when` never share a step; the step carries the shared `when`.
- Step `at`: the first action's place with `r` from `RADIUS` by kind (`npc` for quest NPCs and inns, `flightmaster`, `dock`, `area` for objective areas, `zoneOnly` when the planner wrote `x = y = 0`).
- `minLevel`: the highest required level of the step's accepted quests when above 1.
- `accept` lines get `requires` from QuestieDB prerequisites (single and group) when present.
- `items`: quest-starter items of accepted quests and usable source items of the step's quests (QuestieDB source item / required source items). `targets.enemy`: creatures of kill objectives and drop sources of item objectives on the step (at most 6, nearest spawns first); `targets.friend`: the NPCs the step's quest lines talk to. Only IDs with a name in QuestieDB.
- Step `id`: the lines in order as `<letter><id>` joined by `.` (`a` accept, `t` turnin, `o` objective with quest, `f` getflight with node, `y` fly as `y<from>-<to>`, `x` transport as `x<zone>`, `g` goto as `g<zone>`, `h` hearth, `b` sethearth, `l` grind as `l<level>`), then `@<zone>` for goto, grind and sethearth; a repeat in the section gets `#2`, `#3`.

**Failing tests first** (`tools/test/bundle.test.js`, on the fixture world of `tools/test/world.js`): "two accepts and a turn-in at one NPC become one step with three lines in the planner's order"; "objectives of two quests within 150 yards become one step, one line per objective index"; "an objective farther than 30 yards from the step's place carries its own place with r 40"; "getflight then fly at one flight master is one step"; "travel, transport and hearth are steps of their own with the radius of their kind"; "a class step never shares a step with a shared one"; "minLevel is the highest required level of the step's accepts"; "items and targets come from the quest data and only carry named IDs"; "step ids are stable across two runs and unique in a list"; "flatten(bundleSteps(route).steps) gives back the route's actions exactly"; "every bundled step passes checkRoute3's step rules".

**Acceptance.** `npm test` passes. A one-off check printed in the commit message: for each race, actions before and steps after bundling (`node -e` over `planRoute` for Undead and Human is enough).

### P2 Sections, level ranges, grind targets and chaining

**Files.** Create `tools/planner/sections.js`, `tools/test/sections.test.js`.

**Interfaces consumed.** `bundleSteps`, `flatten`, `validateRoute(...).levels` per character (the shared route's and each class's), `lib/xp.js` (`XP_TO_LEVEL`, the grey level rule), `db.areas` names.

**Interfaces produced.**
- `splitSections(db, race, faction, bundled, levelsByStep, classLevels) -> Section3[]` (no `text` yet), where `levelsByStep[i] = { start, end }` is the estimated level at the start and end of step `i` for the shared route, and `classLevels[CLASS]` the same for each class's own step list.
- `insertGrinds(steps, levelsByStep) -> steps` and constants `MIN_SECTION_WORK = 12`, `MAX_SECTION_STEPS = 250`, `OUTLEVEL_MARGIN = 3`, `BANDS = [20, 30, 40, 50]`.

**Rules.**
- A step's work zone is the zone of its accept, turn-in, objective, sethearth or grind lines; movement steps (only goto, fly, transport, hearth lines) belong to the section of the next work step, so a section starts with the way into its zone.
- A new section starts where the work zone changes and the new zone keeps at least `MIN_SECTION_WORK` work lines before the next change; a shorter run stays in the current section. A section is also split where the estimated level crosses one of `BANDS`, and wherever it reaches `MAX_SECTION_STEPS`, but only where both parts keep at least `MIN_SECTION_WORK` work lines.
- `minLevel` = floor of the estimated level at the section's first step; the end level = the estimated level after its last step; `name` = `"<min>-<end> <zone name>"`, or `"<min> <zone name>"` when they are equal; `maxLevel` = end level + `OUTLEVEL_MARGIN` (at most 60). `names[CLASS]` is written only where that class's own range gives a different name.
- `id` = `<race lowercase>-<min two digits>-<end two digits>-<zone name slug>`, `-2`, `-3` for repeats. `group` = faction; `subgroup` from `minLevel` as in the section table. The race's first section has `start = true`; each section's `next` = `{ { section = <following id> } }`; the last has `next = {}`.
- Grind targets: before every step whose `minLevel` is above the estimated level at its start, insert a step `{ id = "l<level>@<zone>", at = <previous work step's place, r nil>, lines = { { kind = "grind", level = <minLevel> } } }`. The planner's own grind actions are already grind steps. No section may end with a grind of more than one level.
- Step `maxLevel` on steps whose lines are all accepts: the highest player level at which every accepted quest still gives XP (the last level before the quest turns grey by `lib/xp.js`'s grey rule). The later `objective` and `turnin` lines of those quests get `skipIfMissing = true`.

**Failing tests first** (`tools/test/sections.test.js`): "a zone change with 12 or more work lines starts a section; a shorter detour stays in the section"; "movement steps open the section of the zone they lead to"; "a long stay is split at level 20, 30, 40 or 50 only when both parts keep 12 work lines"; "no section has more than 250 steps"; "names read 'min-end Zone' from the estimated levels, single level when equal, and a class gets its own name only when its range differs"; "ids are padded, slugged, unique and stable"; "maxLevel is the end level plus 3, at most 60"; "exactly one start section and every section but the last links the next"; "a step above the estimated level gets a grind step before it, at the last work place"; "accept-only steps get the last level their quests give XP, and the quests' later lines skip if missing"; "flatten over all sections gives the route's actions plus the inserted grinds, in order"; "the sections pass checkRoute3".

**Acceptance.** `npm test` passes.

### P3 Step texts, reminders, profession steps, emitting and the build

**Files.** Create `tools/planner/texts.js`, `tools/planner/reminders.js`, `tools/planner/professions.js`, `tools/planner/training.js` (test `tools/test/training.test.js`), `tools/planner/emit3.js`, `tools/planner/validate3.js`, tests `tools/test/texts.test.js`, `reminders.test.js`, `professions.test.js`, `emit3.test.js`, `validate3.test.js`. Modify `tools/build_routes.js`, `tools/planner/report.js`, `tools/planner/emit.js` (data files read format 3), `tools/test/emit.test.js`, `docs/routes/DATA-NOTES.md`. Regenerate `NoirGuides/Routes/*.lua`, `NoirGuides/Data/Names.lua`, `Zones.lua`, `Flights.lua`, `docs/routes/REPORT.md`. Create `docs/routes/PROFESSION-NOTES.md`.

**Interfaces produced.**
- `stepText(db, step, context) -> string | undefined` with `context = { previous: Step3, section: Section3, faction }`. Texts are written here, in Noir's own words, from templates in `texts.js`: a goto into another zone ("Head <compass direction> into <zone>."), a transport ("Take the <mode> from <dock zone> to <destination zone>."), a fly ("Fly from <node> to <node>."), a hearth ("Use your hearthstone to return to <bind place>."), a grind ("Kill creatures around <zone> until you reach level <L>."), an objective step whose area lies more than 200 yards from the previous step ("The <first target name> are <compass direction> of <previous NPC or place>."). Every text is at most 160 characters; other steps get none. Compass direction from the two places' world coordinates, eight directions.
- `addReminders(db, section) -> section`: an `objective` line whose quest's turn-in is at least two steps later in the same section, and whose place lies within `REMINDER_YARDS = 200` of the place of every step in between, is moved out of its step into a new step `{ id = "r" .. <quest>, at = <its place>, lines = { that line }, reminder = { ends = "turnin<quest>" } }` placed where it was; the turn-in step gets `label = "turnin<quest>"`. A step left without lines is removed. Kill and item objectives only.
- `addProfessionSteps(db, sections, faction) -> sections`: for each primary profession in `NoirGuides/Data/Professions.lua`'s skill lines and each rank 2 to 4 (Journeyman, Expert, Artisan; gates 50, 125, 200; caps 150, 225, 300; levels 10, 20, 35 marked `verified = false`), one step `{ id = "p<skill>-<rank>", when = { profession = <skill> }, at = <trainer>, lines = { { kind = "train", skill = <skill>, rank = <rank>, npc = <trainer> } } }` at the first step at or after the level where a friendly trainer of that profession (QuestieDB NPC whose sub name is "<Profession> Trainer", usable by the faction) stands in the same zone as the route. Where none is reached within three sections, the profession rank is listed in `PROFESSION-NOTES.md` and no step is written (the profession plan in chat still covers it).
- `addClassTraining(db, sections, faction) -> sections` (owner requirement 2026-11-11: regular class training as the reference does): for each class, a step `{ id = "t<CLASS>-<level>", when = { class = <CLASS> }, at = <trainer place>, lines = { { kind = "train", class = <CLASS>, level = <level>, npc = <trainer> } } }`. A class trainer is a QuestieDB NPC whose sub name is "<Class> Trainer" (for example "Warrior Trainer"), friendly to the faction. A visit is written at the first step where the character's estimated level has reached an even level at least 2 above the last visit, and a friendly trainer of that class stands within 300 yards of the step's place. It is also written when 6 levels have passed with no visit and the route passes through a zone with such a trainer. Visits never add a detour longer than the planner's own `travelPlan` estimate of 120 seconds. Each class's visit levels go in `docs/routes/REPORT.md`. The rotation of a spell list is not needed: the trainer window shows what can be learned, and the automation (E9) buys it when `train` is on.
- `emitRoute3(route3) -> string`: deterministic Lua text (fixed key order per table, one step per line block, lists sorted where order has no meaning); throws when `checkRoute3` fails.
- `validate3(db, route3, character, options) -> { errors, warnings, endLevel }`: `flatten` of the character's applying steps through `validateRoute`, plus: every section reachable from the start through `next`; section `minLevel` never decreases along the chain by more than 1; every `reminder.ends` and `requires` resolves; every step with `minLevel` above the estimate has a grind before it.

**Build.** `build_routes.js`: plan → layer classes → validate format 2 (as today) → `bundleSteps` → `splitSections` → `addReminders` → `addProfessionSteps` → `addClassTraining` → `stepText` for every step → `validate3` for all 56 characters → `emitRoute3` → write. `REPORT.md` gains per race: actions before and steps after bundling, the section table (id, name, steps, levels) and the profession steps written.

**Failing tests first.**
- `texts.test.js`: "each template gives the text for its step kind"; "compass directions come from world coordinates in eight directions"; "no text is longer than 160 characters"; "a step without a template gets no text".
- `reminders.test.js`: "an objective done around the next steps becomes a reminder ending at its turn-in"; "an objective far from a step in between stays where it was"; "a step emptied by the move is removed and flatten still lists every action".
- `training.test.js`: "a warrior's route visits a warrior trainer at even levels when one stands near the route"; "a visit is forced after 6 levels without one when the route passes a trainer's zone"; "a visit never adds a detour over 120 seconds"; "other classes do not see the step"; "no visit uses a trainer of the other faction".
- `professions.test.js`: "a trainer step is written at the first step at or after the rank's level in a zone with that trainer"; "the step exists only for characters with the profession"; "a rank with no trainer within three sections is listed in the notes and not written".
- `emit3.test.js`: "the same route gives the same bytes"; "the text reads back through the Lua VM as the same table"; "a route that fails checkRoute3 is refused".
- `validate3.test.js`: "a valid route has no errors"; "an unreachable section, a broken reminder label and a missing grind are each reported".
- `emit.test.js` (replace the format 2 cases): "Names.lua lists every quest, NPC, object and item the format 3 routes name, including items and targets".

**Acceptance.** In `tools/`: `npm run routes` exits 0 and prints for every race 0 errors and all classes at level 60; for each race the steps after bundling are at most 65% of the actions; each race has between 6 and 45 sections and none over 250 steps; every route file passes `checkRoute3`; `npm test` passes; `node harness/run.js addon` passes (the shipped routes register in the mock client without a problem).

---

## Stream E: engine and interface (`NoirGuides/` without `Routes/` and `Data/`)

Every task here tests against the v3 samples (`sample3`). Each new or rewritten module file starts with a header listing its public functions exactly as this plan names them. Every window an E task creates is placed with `Screen.Place`, kept with `Screen.Keep` and registered with `Screen.Register` under its `Screen.DEFAULTS` key (menus use `Screen.AtCursor` instead).

### E1 Mock client v3, options and profiles, screen keeping, final toc

**Files.** Modify `tools/harness/wow.lua`, `tools/harness/lint.js`, `NoirGuides/Core.lua`, `NoirGuides/NoirGuides.toc`. Create `NoirGuides/Options.lua`, `NoirGuides/UI/Screen.lua`, skeletons (as in C1) for `NoirGuides/Guide.lua`, `Lines.lua`, `UI/Buttons.lua`, `UI/SettingsPanel.lua`, `UI/MinimapButton.lua`, `UI/Wizard.lua`, and `NoirGuides/Bindings.xml`. Tests `tools/test-lua/options.lua`, `screen.lua`, additions to `harness.lua`, `widgets.lua`, `core.lua`.

**Mock client additions** (each changes the fake state and fires the real events in the real order):
- screen: `Client.new{ screen = { w, h, scale } }`, `client:setScreen(w, h, scale)` (fires `DISPLAY_SIZE_CHANGED`, `UI_SCALE_CHANGED`); `client:rectOf(frame) -> left, bottom, right, top` in UIParent units resolving every anchor, size and scale; `client:offScreen() -> { name or debug label, ... }` for every shown frame the addon created whose rect leaves UIParent;
- mouse and keys: `client:setCursor(x, y)` (`GetCursorPosition`), `client:click(frame, button)`, `client:doubleClick(frame, gapSeconds)`, `client:wheel(frame, delta)`, `client:hover(frame)` (existing) with `GameTooltip` recording lines (`client:tooltip() -> { lines }`), `client:hold("CTRL"|"SHIFT"|"ALT", down)` (`IsControlKeyDown` etc.), `client:pressKey(key)` (`OnKeyDown` on frames with keyboard enabled);
- options window: `Client.new{ settingsApi = "modern" | "legacy" | "none" }`: modern `Settings.RegisterCanvasLayoutCategory`, `Settings.RegisterAddOnCategory`, `Settings.OpenToCategory`; legacy `InterfaceOptions_AddCategory`, `InterfaceOptionsFrame_OpenToCategory`; `client:optionsOpenedTo() -> name or nil`;
- secure frames: `CreateFrame(type, name, parent, "SecureActionButtonTemplate")` records attributes; `SetAttribute`, `Show`, `Hide`, `SetPoint`, `SetSize` on a protected frame while in combat record an `ADDON_ACTION_BLOCKED` violation; `client:secureClick(frame)` performs `type = "item"` (uses the item), `type = "spell"`, and `type = "macro"` with `macrotext` `"/targetexact <name>"` (targets that unit if near);
- merchants and trainers: `client:openMerchant(npc, items)` (`MERCHANT_SHOW`, `GetMerchantNumItems`, `GetMerchantItemInfo`, `GetMerchantItemLink`, `GetMerchantItemMaxStack`, `BuyMerchantItem`, `CloseMerchant`, `MERCHANT_CLOSED`); `client:openTrainer(npc, services)` (`TRAINER_SHOW`, `GetNumTrainerServices`, `GetTrainerServiceInfo`, `BuyTrainerService`, `CloseTrainer`, `IsTradeskillTrainer`);
- quest pages: `client:showReward(quest, choices)` with `GetNumQuestChoices`, `GetQuestItemInfo("choice", i)`, `GetQuestItemLink`, `GetQuestReward(i)`; `QUEST_ACCEPT_CONFIRM` with `ConfirmAcceptQuest`; `AddQuestWatch`, `RemoveQuestWatch`, `IsQuestWatched`; `client:events(name)` lists the times an event fired;
- character: bags `client:giveItem(id, count)`, `client:takeItem`, `GetItemCount`, `GetContainerNumSlots`/`GetContainerItemID` (and `C_Container` under `api = "modern"`), `GetItemCooldown`; `IsSpellKnown`, `client:learnSpell(id)`; `client:castSpell(spellId)` firing `UNIT_SPELLCAST_START/SUCCEEDED`; `client:die()`, `client:releaseSpirit()`, `client:resurrect()` with `UnitIsDeadOrGhost`, `UnitIsGhost`, `C_DeathInfo.GetCorpseMapPosition`; `IsInInstance`, `IsInRaid`, `client:joinRaid(on)`; `UnitGUID("player")`; `SetRaidTarget`, `GetRaidTargetIndex`; `GetCVar`, `SetCVar`; `ReloadUI` recorded; `client:openTalentFrame()` (loads `Blizzard_TalentUI`, `TalentFrame` shown); `QuestLogFrame` frame; `GetActiveTalentGroup` under `api = "modern"`;
- frames: `SetMouseClickEnabled`, `SetMouseMotionEnabled`, `SetClampedToScreen`, `SetPropagateKeyboardInput` (refused in combat), `CreateFrame("Cooldown")`;
- `client:slashCount() -> number` of slash commands the test typed.

**Lint additions.** Refuse the forbidden calls of the Global constraints that `lint.js` does not yet refuse: `SetBinding`, `SetBindingClick`, `SetBindingMacro`, `SetOverrideBinding`, `SetOverrideBindingClick`, any assignment to `StaticPopupDialogs` fields, any method call on `StaticPopup1`..`StaticPopup4`.

**Options (`NoirGuides/Options.lua`).**
- `Options.Get(key)`, `Options.Set(key, value) -> true | false, reason` (checks type and range; fires `NOIR_OPTION` with key, value), `Options.DEFAULTS`, `Options.RANGES`, `Options.Profile() -> name`, `Options.Profiles() -> sorted names`, `Options.NewProfile(name, copyFrom)`, `Options.UseProfile(name)` (fires `NOIR_PROFILE`), `Options.DeleteProfile(name)` (never the one in use or the last), `Options.ResetProfile()`, `Options.SetDefaultProfile(name)`, `Options.Position(key) -> table or nil`, `Options.SavePosition(key, pos)`.
- `DEFAULTS` (spec 6.1), keys and defaults: `shown = true`, `locked = false`, `hideInRaid = false`, `minimap = true`, `minimapAngle = 225` (0..360), `windowHidden = false`, `cardsBelow = false`, `windowScale = 1` (0.2..2), `fontSize = "standard"` (`"standard"`, `"large"`), `stepList = true`, `hideFinished = false`, `otherSections = false`, `highlight = true`, `itemButtons = true`, `buttonBackground = true`, `buttonScale = 1` (0.8..3), `arrow = true`, `arrowScale = 1` (0.2..2), `arrowText = 12` (8..20), `minimapPins = true`, `pinRing = false`, `worldPins = 7` (0..20), `pinSize = 1` (0.5..2), `pinMerge = 1` (0.05..2), `pinAlpha = 0.6` (0..1), `autoQuests = true`, `guideRewards = false`, `rewardMarker = true`, `bestReward = false`, `train = false`, `flights = true`, `hearth = true`, `dialogue = true`, `buy = true`, `targetButtons = true`, `nameplates = true`, `markers = true`, `outlevel = true`, `groupQuests = false`, `talents = true`, `neverSkip = false`, `offerCleanup = true`, `conflicts = true`, `debug = false`.
- Core: schema 2 and the migration of "Saved variables (schema 2)"; `Noir.char.owner` set at login when missing.

**Screen keeping (`NoirGuides/UI/Screen.lua`).**
- `Screen.DEFAULTS` (frame point, UIParent point, x, y): `window = { "LEFT", "LEFT", 20, 80 }`, `arrow = { "TOP", "TOP", 0, -100 }`, `arrowReset = { "CENTER", "CENTER", 0, 150 }`, `items = { "CENTER", "CENTER", 0, -100 }`, `targets = { "CENTER", "CENTER", 0, -170 }`, `wizard = { "CENTER", "CENTER", 220, 120 }`, `dialog = { "CENTER", "CENTER", 0, 60 }`.
- `Screen.Place(frame, key)`: the saved position of `key` from `Options.Position`, else `DEFAULTS[key]`, then `Screen.Keep(frame)`.
- `Screen.Keep(frame)`: moves the frame inside UIParent now, sets `SetClampedToScreen(true)`, and again after `OnSizeChanged`, `OnShow`, `DISPLAY_SIZE_CHANGED`, `UI_SCALE_CHANGED` for every kept frame.
- `Screen.Save(frame, key)` (top-left corner in screen units, so scale changes keep the corner), `Screen.Reset(key)`, `Screen.Fit(frame, contentHeight) -> height` (caps at `MAX_SHARE = 0.9` of the screen height; the caller scrolls the rest), `Screen.AtCursor(frame, side)` (`side` "right" or "left"; flips when there is no room; then `Keep`).
- `Screen.Movable(frame, key, opts)`: left-drag moves and saves; refused while `Options.Get("locked")` unless `opts.altWhenLocked` and Alt is held; `opts.resizable` adds a corner grip and Alt-drag resize saving `w`, `h`.
- `Screen.Register(key, frame, preview)`: every addon window registers here (`preview(on)` fills it with sample content, may be nil). `Screen.SetShown(on)` sets `shown` and hides or shows every registered window (the engine keeps following the game); `Screen.Preview(on)` calls every `preview` so the player can place the windows, then returns to the real content; with `hideInRaid` on, every registered window hides while `IsInRaid()` and comes back after (`GROUP_ROSTER_UPDATE`).

**Toc.** Final list in this order: `Core.lua`, `Options.lua`, `State.lua`, `Routes.lua`, `Guide.lua`, `Why.lua`, `Lines.lua`, `Progress.lua`, `Automation.lua`, `UI\Theme.lua`, `UI\Screen.lua`, `UI\Text.lua`, `UI\Panel.lua`, `UI\Window.lua`, `UI\Arrow.lua`, `UI\Map.lua`, `UI\Buttons.lua`, `UI\Wizard.lua`, `UI\SettingsPanel.lua`, `UI\MinimapButton.lua`, `Talents.lua`, `Professions.lua`, `Cleanup.lua`, `Diagnostics.lua`, `Menu.lua`, then the data files and route files as today. `Bindings.xml` is not listed (the client reads it by itself).

**Failing tests first.**
- `harness.lua`/`widgets.lua`: "rectOf resolves chains of anchors with scale"; "offScreen lists a shown frame that leaves the screen and ignores hidden ones"; "changing the resolution fires the display events"; "a protected frame changed in combat records a blocked action"; "the modern and legacy options APIs record the category and what was opened"; "merchant, trainer, reward, corpse and bag functions answer from the fake state"; "lint refuses SetBinding and writing StaticPopupDialogs".
- `options.lua`: "defaults come from DEFAULTS"; "Set refuses a value out of range and fires NOIR_OPTION for a good one"; "schema 1 options become the Default profile with the renamed automation keys"; "schema 1 progress is dropped with one why entry"; "profiles: new, copy, use, delete, reset, default for new characters"; "positions are kept per profile".
- `screen.lua`: "each window key has a default place on the screen"; "a saved place outside the screen is pulled back at login"; "a frame that grows past the bottom is moved up"; "after a resolution or UI scale change every kept frame is on screen again"; "Fit caps a tall frame to 90% of the screen"; "AtCursor opens to the right and flips left at the right edge"; "locked frames do not move; Alt-drag moves a frame that allows it"; "SetShown hides every registered window and shows them again"; "Preview calls every window's preview and turns it off again"; "hide in raid hides everything in a raid and shows it after"; at resolutions 1024x768 scale 1, 1920x1080 scale 0.64 and 3840x1080 scale 1.
- `core.lua`: "saved variables get schema 2 on first login"; "a character's owner GUID is saved".
- `addon.lua`: "the toc lists exactly the files of the final list, each once, and every one exists".

**Acceptance.** `npm run test:lua` and `npm test` pass.

### E2 Guide: section registry, automatic choice, next section, saved state

**Files.** Rewrite `NoirGuides/Guide.lua` (from its skeleton); test `tools/test-lua/guide.lua`.

**Interfaces consumed.** `Routes.Get/Ids/ForRace`, `State` (level, class, race, faction, zone, ready, `NOIR_READY`), `Options.Get("otherSections")`, `Options.Get("outlevel")`, `Professions.IsPlanned` (looked up when called).

**Interfaces produced.**
- `Guide.When(cond) -> boolean`: the one evaluator of `when` tables (every key given must hold; a list means any of them; `notClass`/`notRace` exclude; `profession` holds when learned per `State.Profession` or planned per `Noir.Professions.IsPlanned`, looked up when called). `Lines.Applies` (E3) is this function.
- `Guide.Section(id) -> section or nil` (also accepts an ID written with unpadded levels, spec 2.1); `Guide.Current() -> id or nil`; `Guide.Steps(id) -> steps` (the section's steps whose `when` holds for this character; each step keeps `n`).
- `Guide.Applies(section) -> boolean` (file race and faction, section `when`); `Guide.Offered(section) -> boolean` (`Applies`, and not above `maxLevel` while `outlevel` is on); `Guide.IsDefault(section)` (the start section of the character's race file, and the sections reached from it through `next` for this character); `Guide.Name(section) -> names[class] or name`.
- `Guide.List(all) -> { { group, subgroups = { { name, sections = { section, ... } } } } }` of offered sections, sorted by group order weight (main route first), subgroups and sections in level order; `all = true` adds sections of other races' files and non-default sections under the heading "Other races and classes".
- `Guide.Recommend() -> id`: the first of (1) the section loaded, (2) a section applying to the character whose name contains the current zone or subzone name, default ones first, (3) the default section whose range contains the level, (4) the race's start section. Only sections whose `minLevel..maxLevel` contains the level count for (2) and (3).
- `Guide.ForLevel(level) -> id`: along the character's chain from the start section, the first whose range contains `level`.
- `Guide.Select(id, how)`, `how` ∈ `"auto"`, `"hand"`, `"wizard"`, `"next"`, `"step"`: saves `guide.section` and `guide.how`, fires `NOIR_SECTION` with id, how, previous id. Returns false for an unknown or non-applying id (`"hand"` may pick any registered section).
- `Guide.Next() -> id or nil`: spec 2.4: walk `next` in order, take the first that exists and applies; if none applies take the last listed; if the chosen one is not offered because of `outlevel`, follow its own `next` the same way; `Select(..., "next")`. Without a next section fires `NOIR_ROUTE_DONE`. `Recommend` and `ForLevel` use `Offered`; a saved section is kept while it exists and `Applies` (outleveling never switches it in the background, spec 2.3).
- `Guide.Chain(fromId) -> { section ids in order }` for this character, used by Progress's placement.
- Automatic choice at `NOIR_READY` (spec 2.3, 2.5): with `guide.section` saved and applying, keep it. With nothing saved: at level 1 the wizard (E7) opens 2 s after entering the world and `Guide.Select(Guide.Recommend(), "auto")` is done at once so a closed wizard leaves the recommendation loaded; above level 1, `Progress.Locate(Guide.Chain(start))` (E4) decides the section and step when it finds evidence, else `Guide.ForLevel(level)` refined by `Recommend`'s zone rule. A saved section that no longer exists or applies is replaced the same way, with a why entry of kind `section`.
- Recreated character (spec 2.6, gap #48): at login at level 1, when `Noir.char.owner` differs from `UnitGUID("player")`, `Panel.Confirm` asks "This character's saved guide belongs to an earlier character of the same name. Start fresh?"; yes clears `guide` and `why`; no keeps them and saves the new owner.

**Failing tests first** (`tools/test-lua/guide.lua`): "When: and across keys, or inside lists, not keys exclude, profession learned or planned"; "a section is found by its padded and unpadded ID"; "a saved section the character has outleveled is kept at login"; "a level 1 Undead gets the start section without any command"; "a level 4 Undead with nothing saved gets the section whose range contains 4"; "the recommendation prefers a section named after the current zone"; "a saved section is kept at the next login"; "Next follows the conditional link for a hunter and the plain link for a mage"; "Next skips an outleveled section through its own next list when outlevel is on, and not when it is off"; "the last section ends with NOIR_ROUTE_DONE"; "List groups and orders sections and marks other races' sections only when the setting is on"; "a section that no longer exists is replaced and the why-log says so"; "a recreated character at level 1 is asked, and yes starts fresh"; "Select fires NOIR_SECTION with how and the previous section".

**Acceptance.** `node harness/run.js guide` and `npm run test:lua` pass.

### E3 Lines: line states, conditions, step text

**Interfaces consumed.** `Guide.When` (E2), `State`, `Noir.Data`.

**Files.** Rewrite `NoirGuides/Lines.lua` and `NoirGuides/UI/Text.lua`; extend `NoirGuides/State.lua` where a line needs a fact State does not read yet (bags, known spells, spell casts, ghost, merchant/trainer windows, recent accept and hand-in times); tests `tools/test-lua/lines.lua`, `text.lua`, additions to `state.lua`.

**Interfaces produced.**
- `Lines.ACCEPT_GRACE = 2`, `Lines.TURNIN_GRACE = 5`, `Lines.FLY_GRACE = 1.5`, `Lines.FLY_ARRIVE_YARDS = 60`.
- `Lines.Active(line) -> boolean` (per the Lines table: `use`, `target`, `note` and `goto` without a positive radius are passive).
- `Lines.Check(line, step, ctx) -> state, evidence, counter`: `state` ∈ `"done"`, `"todo"`, `"skip"` (a `skipIf...` option completed it; `evidence` says why), `"missing"` (a quest line whose quest is neither in the log nor handed in, without `skipIfMissing`), `"hidden"` (a `collect` with count 0, or a line whose `when` does not hold); `counter = { have, need }` for objective, collect and grind lines. `ctx = { since = time the step became current, flights taken, bound name, vendor seen, trainer seen }` kept by Progress.
- `Lines.Applies = Noir.Guide.When` (E2), so steps, lines and sections share one evaluator.
- `Lines.RANK_CAP = { 75, 150, 225, 300 }`, `Lines.RANK_GATE = { 0, 50, 125, 200 }` (Forever trainer gates, spec 3.8). A `train` line with `skill` and `rank` is `"done"` when the skill's cap is at least `RANK_CAP[rank]`, and `"skip"` (reason "your <profession> skill is below <gate>") while the skill is below `RANK_GATE[rank]`.
- `Lines.Condition(step) -> nil | reason, jump` (the first skip condition that holds, with its reason sentence).
- `Lines.Places(step, reached) -> { { at, line = index or 0, nearest } }`: the step's `at` first (as line 0) while any line without its own `at` is undone, then each undone line's own `at`, minus places in `reached`; of `nearest` places only the closest stays.
- `Lines.Arrived(place) -> true | false | nil` (nil: the client gives no position), using yards from `Arrow`-independent math in this file (`State.Position` plus `C_Map` world size; zone-only places by zone).
- `Text.Line(line, step) -> { text, icon, quest, spans }`: `icon` ∈ `"accept"`, `"turnin"`, `"objective"`, `"kill"`, `"item"`, `"vendor"`, `"trainer"`, `"gossip"`, `"flight"`, `"flightpoint"`, `"hearth"`, `"bind"`, `"goto"`, `"xp"`, `"error"`, `"note"`; `spans` mark named things by meaning (`"friend"`, `"enemy"`, `"loot"`, `"warning"`, `"object"`, `"buy"`) for highlighting. Words: "Accept <quest>", "Turn in <quest>", the quest log's objective text with "have/need" (kill icon for kill objectives, item icon for items), "Collect <item> have/need", "Go to <zone> <x>, <y>", "Get the <node> flight point", "Fly to <node>", "Take the <mode> to <zone>", "Set your hearthstone at <inn or zone>", "Hearth to <place>", "Grind to level <L>" or "Grind until <P>% into level <L>" with "<xp>/<needed>" while at that level, "Learn <spell or rank>", "Visit <npc>" plus "buy <count> <item>", "Use <item>", "Kill <npc>"/"Talk to <npc>", the text of note and manual lines. Missing prerequisites on an accept line (`requires` not all handed in) give icon `"error"` and a tooltip listing them; the line is not skipped.
- `Text.StepTitle(step) -> title or tostring(step.n)`, `Text.QuestName(id)`, `Text.ZoneName(area)`, `Text.FlightName(node)`, `Text.NpcName(id)`, `Text.ItemName(id)`, `Text.Place(point)`, `Text.Distance(yards) -> "120 yd"`.
- State additions: `State.ItemCount(id)`, `State.KnowsSpell(id)`, `State.RecentAccept(quest) -> seconds ago or nil`, `State.RecentTurnIn(quest)`, `State.IsGhost()`, `State.Corpse() -> zone, x, y or nil`, `State.InInstance()`, `State.InRaid()`, `State.lastCast = { spell, time }`, `State.merchant = { npc, opened, closed }`, `State.trainer = { npc, opened, closed }`.

**Failing tests first.**
- `lines.lua`, one test per row of the Lines table: "accept is done when the quest is in the log, handed in, or accepted up to 2 s before the step became current, and not 3 s before"; "accept with ifDone is done at once when that quest is not handed in"; "turnin is done on a hand-in up to 5 s before the step became current, and not 6 s before"; "turnin with skipIfMissing completes with a reason when the quest is not in the log"; "objective follows its own counter and cap, and a quest with no objectives reads 0/1"; "collect counts bags and is full when its quest is complete; count 0 hides it"; "goto completes inside its radius, is passive without one, and in the zone when x and y are 0"; "getflight completes on a known node or the discovery message"; "fly completes when control is lost within 1.5 s of choosing, or at the destination"; "transport completes in the destination zone"; "sethearth completes on the bind at the step's inn"; "hearth completes on a hearthstone or Astral Recall cast"; "grind completes at the level and percent"; "train completes when the spell is known and when a profession cap covers the rank, and skips below the rank's gate of 50, 125 or 200"; "a class trainer visit completes when that trainer's window opens and closes at or above its level, and not below it"; "vendor completes when the merchant window closes after opening"; "use, target and note are passive"; "manual is done only when ticked"; "every skip condition kind holds and fails as written"; "a line whose when does not hold is hidden"; "Places lists the step place, then undone lines' own places, keeps the nearest of a nearest group and drops reached ones".
- `text.lua`: "each line kind has its words and icon"; "names come from Noir.Data, then the client, then 'Quest 364'"; "missing prerequisites show the error icon and list the quests"; "named things are marked by meaning".

**Acceptance.** `node harness/run.js lines`, `node harness/run.js text`, `npm run test:lua` pass.

### E4 Progress v3 and the why-log v2

**Files.** Rewrite `NoirGuides/Progress.lua`; modify `NoirGuides/Why.lua`; tests `tools/test-lua/progress.lua`, `reminders.lua`, `placement.lua`, `why.lua` (extend).

**Interfaces consumed.** `Guide.*` (E2), `Lines.*` and `Text.*` (E3), `State`, `Options.Get("neverSkip")`, `Options.Get("outlevel")`.

**Constants.** `PASS_SECONDS = 0.1` (one update pass; the place moves at most one step per pass), `ARRIVAL_SECONDS = 0.33` (position checks while a place with a radius is on screen), `SIGNAL_QUIET = 1` (seconds), `LOOKAHEAD_TEXT = 8`, `BEHIND_STEPS = 3`.

**Interfaces produced.**
- `Progress.Load(sectionId)` (on `NOIR_SECTION`): the saved place by step `id` (falling back to `n`); a signature mismatch or no saved place runs placement inside the section (`Progress.Locate({ sectionId })`).
- `Progress.Cards() -> { { step, index, kind, lines = { { line, state, ticked, text, icon, counter, why } } } }` with `kind` ∈ `"reminder"`, `"detour"`, `"current"`; reminders and detours first, in step order, then the current step. A current step whose `minLevel` is above the character's level gets a synthetic first line `{ kind = "grind", level = minLevel, synthetic = true }` and cannot complete before it is reached (spec 3.7: never stall silently).
- `Progress.Place() -> sectionId, index, count, step`; `Progress.Steps() -> the section's steps for this character`; `Progress.StepState(index) -> "done" | "current" | "reminder" | "ahead" | "behind" | "hidden"` (for dimming: steps before the place and finished reminders are `"done"` or `"behind"`).
- `Progress.Tick(index, lineIndex, on)`: a manual tick or untick of a line on screen; saved in `places[section].ticks`; ticking the last open line completes the step (why kind `tick`).
- `Progress.Jump(index, how)` (`how` ∈ `"list"`, `"skip"`, `"back"`): goes to any step at once, forward or back, without confirmation; why kind `jump`. `Progress.Skip()` = tick every active line of the current step. `Progress.Back()` = jump to the nearest earlier step that is not done.
- `Progress.Lookahead() -> step or nil` (the step after the current one, for automation).
- `Progress.Locate(chain) -> sectionId, index, score, left` (placement from quest history across the given sections in order; the 0.1.1 scoring kept: a quest in the log +4, handed in +2, missing −1, flight points not counted as missing; a quest counts once at its first line; the place is just after the highest score, latest on ties). Score 0 means no evidence.
- `Progress.Refresh()`, and `Progress.Reached(index, lineIndex) -> boolean`, `Progress.MarkReached(index, lineIndex)` (arrival of places with a radius; kept while the step is on screen).
- Events: `NOIR_STEP` with the cards whenever they change; `NOIR_PLACE` with section, index; `NOIR_LINE` with section, step id, line index, state; `NOIR_STEP_DONE` and `NOIR_OBJECTIVE_DONE` only when more than `SIGNAL_QUIET` seconds passed since the last place change.

**Rules (spec 3.3 to 3.7, 2.4, 2.5).**
- A step is complete when every active line is done, ticked or passive, when a skip condition holds, or when its `reminder.ends` step is reached. Skip conditions are checked only while the step is current, never while the addon is hidden (`shown` false; lines still complete then, conditions wait), and while `neverSkip` is on only a gate is: a `notturnedin` condition on a quest that an accept line of the step `requires` (the game will not offer that accept, so the step would wait for ever; X1 review 2). A line that became done while its step was on screen stays done (latch) until the step is entered again; only unticking clears a tick.
- Each pass: evaluate the cards; if the current step is complete, move the place one step forward. A step whose lines are all hidden is passed (no why). A step with `requires` waits while the labelled step is on screen or ahead; a reminder required by a normal step without `ends` ends at that step. A reminder step never becomes the place: when the place reaches it, it opens as a reminder card (if its `minLevel` and `when` allow) and the place moves on; it ends when the place passes its `ends` step (`"next"`: the step after it) or when all its lines are done (saved in `places[section].reminders`).
- A step with `maxLevel` below the character's level is passed with why kind `outleveled` while `outlevel` is on.
- Missing quests: a `"missing"` objective or turn-in line shows the accept step of its quest as a detour card when that accept is in an earlier applying step of the section; otherwise the line is passed with why kind `cannot` and one chat line.
- Movement steps (every active line is goto, fly, transport or hearth) whose next work step is already done are passed with why kind `moot`, unless the work left lies that way (the 0.1.1 `stillLeads` rule, kept) or the player jumped to that step.
- When the place changes, lines of steps no longer on screen lose their done state and ticks.
- At the end of a section: a `loop` section wraps to its first step once; open reminders hold the place; else `Guide.Next()` with no cleanup prompt; without a next section the window says the route is complete.
- A step with `load` calls `Guide.Select(load, "step")` when it becomes current.
- The game's quest tracker follows the quests of the current card (`AddQuestWatch` when not watched; never more than the client allows).
- Catch-up at login: the saved step is made current and passes forward through done steps on its own (one per pass); steps before it are not checked again except reminders.
- Behind: at login, when `Progress.Locate(Guide.Chain(current))` lands at least `BEHIND_STEPS` quest steps after the saved place, move there and print one chat line ("Moved ahead to <section> step <n>: your quest log shows the work before it done."); never move backward on its own.
- Why kinds (Why.lua): `done` (already done when reached), `moot`, `cannot`, `condition`, `outleveled`, `tick`, `jump`, `place`, `section`, `route`. `Why.Add(entry)` with `entry = { section, step = id, n, kind, text }`; `Why.ForStep(sectionId, stepId) -> latest entry or nil`; `Why.Lines(count)`; the log keeps 100 entries.

**Failing tests first.**
- `progress.lua`: "a bundled step completes only when all its lines are done"; "a line ticked by hand counts and untick reopens it"; "a line done once stays done while its step is on screen"; "an accept event 1 s before the step became current completes the accept line; 3 s before does not"; "a hand-in 4 s before the step became current completes the turn-in line"; "a run of done steps passes one per pass and is logged as already done"; "a skip condition passes the step with its reason, and never when 'never auto-skip' is on"; "a jump condition goes to its label"; "a step under its minimum level shows a grind line first and waits"; "an outleveled step is passed with the reason"; "a missing quest shows its accept step as a detour card"; "a move whose next task is done is passed as moot"; "Jump goes back and forward without confirmation and logs it"; "the end of a section loads the next section with no cleanup prompt"; "open reminders hold the place at the end of a section"; "the last section says the route is complete"; "signals are not raised within 1 s of a place change"; "the quest tracker follows the current quest"; "the place is saved by step id and survives a relog; an edited section finds the step by id".
- `reminders.lua`: "a reminder opens above the current step and the place moves on"; "it ends when the place passes its ends step"; "one finished early is remembered for the section"; "a reminder under its minimum level does not show".
- `placement.lua` (rewrite of the 0.1.1/0.1.2 tests on v3 samples): "a level 1 character with nothing done starts at the first step"; "a level 4 character with the second section's quests in the log is placed in the second section, after those quests"; "a character joining at the third section's level with its first quest handed in lands after it"; "early quests left undone do not hold the place back"; "a saved place behind the quest log moves forward at login with one chat line"; "a saved place ahead of the quest log is never moved back"; "placement runs with no command and the result is the current step".
- `why.lua` additions: "ForStep returns the newest entry for a step"; "every kind has its words".

**Acceptance.** `node harness/run.js progress`, `reminders`, `placement`, `why` and `npm run test:lua` pass.

### E5 Window v2: card stack and step list

**Files.** Rewrite `NoirGuides/UI/Window.lua`; modify `NoirGuides/UI/Theme.lua`, `NoirGuides/UI/Panel.lua` (add `Panel.Confirm`, `Panel.ScrollList`), `tools/gen_textures.js` and `NoirGuides/Textures/` (the 16 kind icons, tick box, grip, menu button), `DESIGN.md` (rewrite "The idea", "Layout", "States", "The words of a step" for the card stack and step list; keep the color and type tokens); tests `tools/test-lua/window.lua`, `theme.lua`, `textures.test.js` additions.

**Interfaces consumed.** `Progress.Cards/Place/Steps/StepState/Tick/Jump`, `Guide.Current/Section/Name`, `Text.*`, `Why.ForStep`, `Screen.Place/Keep/Movable/Save`, `Options`, `Noir.Menu.OpenMain()` and `Noir.Menu.OpenStep(index)` (looked up at click time).

**Interfaces produced.**
- `Window.frame`; `Window.Refresh()`; `Window.Read() -> { shown, title, subtitle, range, cards = { { badge, kind, lines = { { text, icon, ticked, done, counter } } } }, list = { { n, text, dim, current, lit } }, footer = { version, level, share } }`.
- Click targets for tests and the simulator: `Window.Tick(cardIndex, lineIndex) -> frame`, `Window.Row(listIndex) -> frame`, `Window.Header() -> frame`, `Window.MenuButton() -> frame`, `Window.Grip() -> frame`.
- `Window.Preview(on)`: fills the window with sample content for placing; registered with `Screen.Register("window", Window.frame, Window.Preview)`.
- `Panel.Confirm(text, onYes, onNo)`: the addon's own centred dialog (`Screen.DEFAULTS.dialog`).

**Behavior (spec 4.1 to 4.3, gap #13, #14).**
- Default place `Screen.DEFAULTS.window`; moved by the header or body, resized by the grip or Alt-drag (list height saved), locked by `locked`, scaled by `windowScale` keeping the top-left corner, kept on screen at all times.
- Header: section name (`Guide.Name`), subgroup on a second line, the range of step numbers in view, a menu button; right-click on header or footer opens the main menu. Without a section: the header says "Choose a section" and the window collapses to the header.
- Cards: one per entry of `Progress.Cards()`, stacked above the header (`cardsBelow` puts them below the window); when that side would leave the screen they flip to the other side. Badge: `Text.StepTitle`. Each visible line: tick box, kind icon, text with counter. Hovering a line shows its tooltip (missing prerequisites, the why entry, the condition that will skip it); hovering the tick box says "Tick to treat this line as done". Accept and turn-in quest names are links: hovering shows the quest tooltip (`GameTooltip:SetHyperlink("quest:<id>")`).
- A new current card's side bar shows the step's kind for 3 seconds (hand in, accept, train, objectives, travel, in that order of prominence) and the card slides in; no sound.
- Step list (`stepList` on): every step of `Progress.Steps()` with its lines' icons and texts indented and its number at the corner; `"done"`/`"behind"` steps and finished reminders at half alpha; hover brightens; right-click or a double-click within 0.5 s opens the step menu for that row; mouse wheel and scrollbar; on every place change the list scrolls so the current step is the top row; `hideFinished` stops scrolling above the current step; rows keep the text of the next 8 steps current. Hovering a row shows the why entry of that step when it has one.
- Footer: version, the character's level and the share of the section done, the resize grip; the level rail with a tick per level when the section's range is 20 levels or fewer.
- Named things in line texts are colored by meaning (`highlight` on) from Theme tokens `friend`, `enemy`, `loot`, `warning`, `object`, `buy` (added to `DESIGN.md` and `Theme.lua`); `highlight` off gives one plain color.
- `windowHidden` hides the window while the arrow, pins and engine keep running; `shown = false` hides every addon window (`Screen.SetShown`); the window keeps updating in combat.
- The card slide and the talent ring (E10) are the only motion in the interface; `DESIGN.md` says so.

**Failing tests first** (`tools/test-lua/window.lua`): "the window opens at its default place on the left, a little above the middle"; "a bundled step shows as one card with a tick box per line"; "ticking a line by mouse completes it and the next step slides in"; "reminders show as their own cards above the current card"; "cards flip below when there is no room above"; "the step list dims finished steps and highlights the current one"; "a double-click within 0.5 s opens the step menu; two clicks 0.6 s apart do not"; "a right-click on a row opens the step menu"; "the list scrolls so the current step is the top row after a place change"; "hide finished steps stops the list above the current step"; "hovering a passed step shows why it was passed"; "hovering an accept line shows the quest tooltip"; "the header shows the section name and subgroup, and right-click opens the main menu"; "without a section the window collapses to its header"; "resizing saves the list height; locking stops moving and resizing"; "scaling keeps the top-left corner"; "nothing is off-screen at 1024x768 with 12 cards"; "no sound is played on a step change"; "no font object is set".

**Acceptance.** `node harness/run.js window`, `theme`, and `npm run test:lua`, `npm test` pass.

### E6 Arrow v2 and map pins v2

**Files.** Rewrite `NoirGuides/UI/Arrow.lua` and `NoirGuides/UI/Map.lua`; tests `tools/test-lua/arrow.lua`, `map.lua`.

**Interfaces consumed.** `Progress.Cards/Reached/MarkReached/Steps/Place`, `Lines.Places`, `Text.Line/StepTitle`, `State.Position/IsGhost/Corpse/InInstance/Continent`, `Screen.*`, `Options`.

**Arrow (spec 4.4, gap #23).**
- `Arrow.Target() -> { at, title, index, line } or nil`: while a ghost, the corpse (`State.Corpse`); else the first place of `Lines.Places` over the cards in card order then line order; places in other continents are skipped for choosing but reported.
- `Arrow.Solve(point) -> bearing, yards, method` (kept from 0.1.x: world position first, map projection second); `Arrow.Project(point, uiMap)`; `Arrow.Read() -> { shown, angle, yards, text, frozen }`; `Arrow.Reset()` (re-enables and places at `Screen.DEFAULTS.arrowReset`).
- Redraws when the angle moved more than 0.5 degrees or the whole-yard distance changed; label = target title (step title or number) and distance in whole yards; scale `arrowScale`, label size `arrowText`.
- Loops: a `path` with `loop`: the arrow follows the points in order, each reached within the step's `at.r` (20 yards when nil); when all are reached they reset; off the loop by more than 1.3 times the current leg's length (at least 1000 yards) it restarts from the nearest point.
- Other continent: frozen pointing straight up with "On another continent", one chat line per target.
- Hidden when `arrow` is off, there is no target, in an instance, or without a position. Default place `Screen.DEFAULTS.arrow`; draggable, saved, locked by `locked`.

**Pins (spec 4.5, gap #24).**
- `Map.Pins(kind) -> { { x, y, steps = { { index, line, text, title } }, current, alpha, size, merged } }` for `kind` ∈ `"world"`, `"minimap"`; `Map.Refresh()`; `Map.Read()`.
- World map: places of the cards first, then the following steps in order, up to `worldPins` (default 7, 0 to 20) counted in steps; raised so every place of the cards fits. Pins also on sub-zone and continent maps that contain the place (via `Arrow.Project`); none in instances.
- Minimap: places of the cards only, when `minimapPins` is on.
- Merging: places closer than `60 * pinMerge` yards on the world map and `25 * pinMerge` yards on the minimap share one pin, labelled "+" with the step icon or number of the first.
- Look: current-card pins larger and fully opaque; each later step's pins 0.1 more transparent, never below 0.4; ring around the current pin when `pinRing`; size `pinSize`, background `pinAlpha`.
- Tooltip on hover: one line per merged place, "<step title or number>: <line text>". Pins take mouse motion only (`SetMouseMotionEnabled(true)`, `SetMouseClickEnabled(false)`, feature-detected; without them, no tooltip and no mouse), so clicks reach the map.
- Lines: a step's `path` is drawn on the world map as segments between its points (dashed: segments of 8 yards drawn, 6 skipped) while the step is on a card and its zone's map is shown.
- Reached places, ticked lines and done lines have no pin. Pins rebuild at most every 0.33 s, on `NOIR_STEP`, and when the shown map changes. The world map and minimap frames themselves are never changed.

**Failing tests first.**
- `arrow.lua`: "points to the first undone place of the current card and shows whole yards"; "a reached place moves the arrow to the next one"; "of a nearest group only the closest is the target"; "a ghost gets the corpse"; "a loop resets after the last point and restarts when far off"; "another continent freezes the arrow and says so once in chat"; "hidden in an instance, without a position, or when switched off"; "small turns under half a degree do not redraw"; "reset re-enables and recentres it slightly above the middle".
- `map.lua`: "the world map shows the cards' places and the next steps up to 7"; "the setting changes the limit from 0 to 20, raised to fit every place on the cards"; "the minimap shows only the cards' places and can be switched off"; "places within 60 yards share a pin with '+' on the world map, 25 yards on the minimap, scaled by the merge setting"; "the current pins are larger and opaque, later ones fade by step down to 0.4"; "hovering a merged pin lists each step and line"; "a click on a pin reaches the map"; "a path is drawn while its step is on a card"; "done, ticked and reached places have no pin"; "pins rebuild at most three times a second"; "sub-zone maps show pins that fall on them; instances show none"; "the map frames are never changed".

**Acceptance.** `node harness/run.js arrow`, `map` and `npm run test:lua` pass.

### E7 Menus at the cursor, the section picker, the setup wizard

**Files.** Rewrite `NoirGuides/Menu.lua`; rewrite `NoirGuides/UI/Wizard.lua`; tests `tools/test-lua/menu.lua`, `wizard.lua`.

**Interfaces consumed.** `Guide.List/Select/Recommend/Current/Section/Name/Chain`, `Progress.Jump/Skip/Back/Place/Locate`, `Screen.AtCursor/Fit/Keep/Place/Register/SetShown/Preview`, `Options`, `Panel.*`, and by name at click time: `Noir.SettingsPanel.Open`, `Noir.Cleanup.Open`, `Noir.Cleanup.Offer`, `Noir.Talents.Print`, `Noir.Diagnostics.Open`. Menu entries that call another parallel task's function are tested with a spy on that function.

**Menu (spec 2.2, 4.1 menus, gap #1, #5, #7, #49).**
- `Menu.Open(items, opts)` (`opts = { title, current }`), `Menu.OpenMain()`, `Menu.OpenStep(index)`, `Menu.OpenPicker()`, `Menu.Close()`, `Menu.IsOpen()`, `Menu.Read() -> { levels = { { rows = { { text, right, checked, sub, current, marker, heading, lit } }, scroll } } }`, `Menu.Row(level, i) -> frame`.
- Item: `{ text, right, checked = fn, on = fn, sub = fn -> items, keep, current, marker = "level" | "passed", heading }`.
- Opens at the cursor; submenus open on hover to the right, to the left when there is no room; each level capped by `Screen.Fit` and scrolled with the mouse wheel; a picker level opens scrolled to the current section; Escape or a click outside (a full-screen catcher frame under the menu) closes the whole menu; works in combat (own frames only).
- Main menu: "Choose a section" ▸ (picker), "Reload section", "Find my place again" (`Progress.Locate` over the current chain, with confirmation), "Step" ▸ ("Skip this step", "Back to the last open step"), "Show the arrow" (tick), "Show map pins" (tick), "Lock windows" (tick), "Options", "Setup wizard", "Quest cleanup", "Talents", "Report a problem", "Preview window positions" (`Screen.Preview`), "Hide Noir Guides" (`Screen.SetShown(false)`; the minimap button shows it again).
- Step menu (spec 4.3): "Go to this step", "Skip this step" (on the current step), "Back to the last open step", "Choose another section" ▸, "Reload section", "Options", "Report a problem with this step", "Close".
- Picker (spec 2.2): `Guide.List(Options.Get("otherSections"))` as groups → subgroups → sections; each row the section's name with its level range on the right; the section played highlighted; marker `"level"` on rows whose range contains the character's level and `"passed"` on ranges already passed (a colored tab, Theme tokens `lamp` and `dim`). Picking calls `Guide.Select(id, "hand")`; when the section changed and `offerCleanup` is on, `Noir.Cleanup.Offer()` 3 s later (Cleanup decides whether anything starts ticked).

**Wizard (spec 2.3, 6.1).**
- `Wizard.Open()`, `Wizard.Close()`, `Wizard.Finish()`, `Wizard.Read() -> { shown, page, questions = { { key, text, on, recommended } }, sections = { { id, name, recommended } } }`, `Wizard.Button(name) -> frame` (`"back"`, `"reset"`, `"finish"`, `"close"`), `Wizard.Toggle(key) -> frame`.
- Opens by itself 2 s after entering the world for a level 1 character with no `guide.wizard`; reachable from the menu and settings any time. Default place `Screen.DEFAULTS.wizard`.
- Page 1 "Open world route" card (the only route family until dungeons exist). Page 2 questions with "recommended" tags: "Use the auction house" (`setup.auctionHouse`, recommended on), "Do group quests" (`groupQuests`, off), "Skip content you outlevel" (`outlevel`, on), "Level a profession" (opens the profession choice, `Professions.SetPlanned`), "Show sections for other races and classes" (`otherSections`, off). Page 3 the section list: only sections whose range contains the level, the recommended one first and marked. Back, Reset (defaults), Finish (loads the chosen section with `Guide.Select(id, "wizard")`).
- Closing without Finish keeps the automatically loaded recommendation and sets `guide.wizard = true`.

**Failing tests first.**
- `menu.lua`: "the main menu opens at the cursor from the header and from the menu button"; "a submenu opens to the right, and to the left at the screen's right edge"; "a long picker is capped to the screen, scrolls with the wheel and opens at the current section"; "the picker lists groups, subgroups and sections in level order with ranges on the right"; "the current section is highlighted; 'your level' and 'passed' markers are set"; "picking a section loads it and offers the cleanup 3 s later when the setting is on"; "Escape closes the whole menu; so does a click outside"; "every step menu entry does what it says"; "the menu works in combat"; "no menu is off-screen at 1024x768 with the cursor in each corner".
- `wizard.lua`: "a new level 1 character sees the wizard 2 s after entering the world, without a command"; "a level 5 character does not"; "Finish loads the chosen section"; "closing keeps the recommended section loaded"; "the section list holds only sections for the character's level, the recommended first"; "each question changes its setting"; "the wizard opens from the menu any time".

**Acceptance.** `node harness/run.js menu`, `wizard` and `npm run test:lua` pass.

### E8 Settings panel, minimap button, commands, preview and hide-in-raid

Runs after E5, E6, E7, E9 and E10.

**Files.** Rewrite `NoirGuides/UI/SettingsPanel.lua`, `NoirGuides/UI/MinimapButton.lua`; modify `NoirGuides/Core.lua` (`/noir` without argument opens settings), the command registrations in each module (remove commands not in the list below); tests `tools/test-lua/settings.lua`, `minimap.lua`, `commands.lua`.

**Settings panel (spec 4.1 entry points, 6.1, gap #3).**
- `SettingsPanel.Open(tab)`, `SettingsPanel.Read() -> { shown, tab, controls = { { key, kind, value } } }`, `SettingsPanel.Control(key) -> frame`, `SettingsPanel.TABS = { "General", "Guide window", "Navigation", "Automation", "Route", "Advanced", "Profiles" }`.
- Registered in the game's options window as "Noir Guides": modern `Settings.RegisterCanvasLayoutCategory` + `Settings.RegisterAddOnCategory` when present, else `InterfaceOptions_AddCategory`; without either, `Open` shows the same panel as a free window at `Screen.DEFAULTS.dialog`. In combat `Open` is remembered and done at `PLAYER_REGEN_ENABLED`.
- Controls are the addon's own (tick box, slider with value, choice list through `Menu.Open`, button), one per `Options.DEFAULTS` key in its tab per spec 6.1, plus buttons: General "Open setup wizard", "Open quest cleanup", "Report a problem"; Guide window "Reset item buttons", "Preview window positions"; Navigation "Reset arrow"; Advanced "Find my place again"; Profiles new, copy, delete, reset, "Use as default for new characters", "Reset guide progress for this character" (with `Panel.Confirm`). Changing `fontSize` or `outlevel` asks with `Panel.Confirm`: `fontSize` then calls `ReloadUI()`, `outlevel` reloads the section.
- Conflict warning (spec 6.1 Advanced): 20 s after login, when `conflicts` is on and another arrow addon is loaded (`C_AddOns.IsAddOnLoaded` or `IsAddOnLoaded` for `"TomTom"`), one chat line.

**Minimap button (gap #4).** `MinimapButton.frame`, `MinimapButton.SetAngle(degrees)`, `MinimapButton.Read() -> { shown, angle }`. On the minimap's rim at `minimapAngle`; drag moves it along the rim and saves the angle; left click toggles `shown` for every addon window (the guide keeps following); right click `Menu.OpenMain()` at the cursor; tooltip names both clicks; hidden when `minimap` is off.

**Preview and raids.** The settings controls and buttons for `shown`, `hideInRaid` and "Preview window positions" call `Screen.SetShown`, `Options.Set("hideInRaid", ...)` and `Screen.Preview` (E1); E8 checks end to end that every window registered with `Screen.Register` (window, arrow, item buttons, target buttons, wizard, cleanup, bug report) takes part.

**Commands (spec 6.3).** One command word `/noir`: no argument opens settings; `show`, `hide`, `toggle`, `wizard`, `cleanup`, `talents`, `professions`, `bug`, `preview`, `help`, and the extras `why`, `state`, `problems`, `step`, `skip`, `back`, `sync`, `version`. Every one is also a menu entry or button; `Menu.MOUSE_PATHS[command] = { "main", "<entry text>", ... }` names the path.

**Failing tests first.**
- `settings.lua`: "the panel is registered in the modern options window"; "and in the legacy one"; "and opens as a window when neither exists"; "opening in combat waits for combat to end"; "every option key has one control in its tab, and changing it changes the option"; "font size asks and reloads the UI; outlevel asks and reloads the section"; "reset buttons put the arrow and item buttons back at their defaults"; "profiles can be made, copied, used, deleted and reset, and window places follow the profile"; "the conflict warning comes once, 20 s after login".
- `minimap.lua`: "the button sits on the rim at 225 degrees by default"; "dragging moves it along the rim and the angle is saved"; "left click hides and shows every window while the guide keeps following"; "right click opens the main menu at the cursor"; "the setting hides it".
- `commands.lua`: "/noir alone opens settings"; "every registered command is in MOUSE_PATHS and following that path by clicks does the same thing"; "the preview button fills every registered window and returns to the section"; "with hide in raid on, joining a raid hides every registered window".

**Acceptance.** `node harness/run.js settings`, `minimap`, `commands`, `npm run test:lua` and `npm test` pass.

### E9 Automation v2 and secure buttons

**Files.** Rewrite `NoirGuides/Automation.lua` and `NoirGuides/UI/Buttons.lua`; write `NoirGuides/Bindings.xml`; tests `tools/test-lua/automation.lua`, `buttons.lua`.

**Interfaces consumed.** `Progress.Cards/Lookahead`, `Guide.Section(...).noAuto`, `Lines.*`, `State`, `Options`, `Screen.*`.

**Automation (spec 5, gap #27 to #32, #35).**
- `Automation.Enabled(key)` reads `Options` (`autoQuests`, `guideRewards`, `rewardMarker`, `bestReward`, `flights`, `hearth`, `dialogue`, `buy`, `train`). Holding Ctrl when an NPC window opens skips accept, hand-in and reward automation for that interaction; holding Shift skips flight, bind and dialogue automation.
- Accept: only quests of `accept` lines on the cards or on `Progress.Lookahead()`, without `manual` and not in the section's `noAuto`; matched by ID, by title only where the client gives only titles and the title matches exactly one. Dialogue order: a complete quest the guide hands in, then a quest it accepts, then an incomplete quest whose only objective is talking to this NPC. On the detail page: accept and close; if a hand-in happened less than 0.5 s before and the offered follow-up is not a guide quest, close it. Shared quests (`QUEST_ACCEPT_CONFIRM`) and escort starts are accepted under the same rule.
- Hand-in: quests of `turnin` lines on the cards (a hand-in line once on a card keeps its quest eligible for the session), not `manual`; progress page: continue when completable. Reward page: no or one choice → take it; the line names `reward` and `guideRewards` is on → take it; else mark the choice with the best sell price with a coin icon (`rewardMarker`) and leave the page, or take it when `bestReward` is on. The coin marker also shows in the quest log's detail pane when a quest with choices is selected (own texture anchored to the pane).
- Flights: at a flight master with a `fly` line on a card, the flight option is picked once per step; on `TAXIMAP_OPENED`, the node is matched by node ID first, by name only as fallback. A `getflight` line re-picks the flight master option at most once every 10 s. Every taxi map opening records all known nodes (State, kept).
- Hearthstone: on a `sethearth` line, the innkeeper's bind option is picked and the confirmation answered on the next frame (only that popup).
- Dialogue: options recognised by type (flight, bind, trainer) before any text; nothing while a modifier is held.
- Vendor: a merchant opened while a `vendor` line with `buy` is on a card buys up to the count still needed (bags counted), capped by stock, in full stacks, then closes the merchant after the bags update; skipped when the linked quest is done.
- Trainer (`train` off by default): for 15 s after `TRAINER_SHOW`, every 0.2 s, buy the available class and race services (lowest level first) plus any service named by a `train` line on a card; pet trainers and profession trainers without a `train` line are skipped; no gold check.

**Buttons (spec 4.6, gap #25, #26, #31).**
- `Buttons.Items() -> { { kind = "item" | "spell", id } }`, `Buttons.Targets() -> { enemy = { name }, friend = { name } }`, `Buttons.Read()`, `Buttons.Preview(on)`, `Buttons.Reset()`.
- Item buttons: from the cards: `use` lines, `items` of the steps, `item` fields of accept, turn-in and objective lines, quest-starter items until the quest is in the log, the Hearthstone (6948) on `hearth` lines and Astral Recall (556) for shamans when known. Order: spells, equipped items, bag items in bag order. One row at `Screen.DEFAULTS.items`; `SecureActionButtonTemplate` with `type = "item"` / `type = "spell"`; cooldown shown; tooltip on hover; shown only with at least one button; scale `buttonScale`; background `buttonBackground`; moved with Alt-drag even when locked.
- Target buttons: enemies (top group) and friendly NPCs (bottom group), four per row, at `Screen.DEFAULTS.targets`, from `targets` and `target` lines of the cards, names from `Noir.Data.npcs`. `type = "macro"` with the attribute `macrotext = "/targetexact <name>"` (an attribute of the button, not a macro: no macro is created). With `markers` on, `PostClick` puts a raid marker by position (friendly: star 1, circle 2, diamond 3, triangle 4; enemies: skull 8, cross 7, square 6). Portrait once the unit was seen as target, else a placeholder. A friendly target the player talks to is removed. Hidden on a flight, while casting the hearthstone, in raids and with no targets. `nameplates` on sets the nameplate distance CVar to the client's maximum (feature-detected; the old value restored when switched off).
- All secure buttons are built, changed, shown and hidden only out of combat; changes asked for in combat wait for `PLAYER_REGEN_ENABLED`.
- Key bindings: the first four item buttons and the first four of each target group are named (`NoirGuidesItem1`..`4`, `NoirGuidesFriend1`..`4`, `NoirGuidesEnemy1`..`4`, the only named frames of the addon) and bound through `Bindings.xml` `CLICK` entries with `BINDING_HEADER_NOIRGUIDES` and `BINDING_NAME_*` globals.

**Failing tests first.**
- `automation.lua`: "a quest of the next step is accepted at its NPC"; "a quest of no step on screen or next is left alone"; "Ctrl skips quest automation, Shift skips the flight, bind and dialogue"; "the dialogue picks a guide hand-in before an accept"; "a non-guide follow-up offered right after a hand-in is closed"; "a shared quest of a guide step is confirmed"; "a reward page with one choice is taken; with several it is marked with a coin and left open"; "guide rewards and best reward take the choice when switched on"; "the flight is matched by node ID before name"; "the flight master option is re-picked at most every 10 s for a flight point line"; "the bind confirmation is answered on the next frame"; "a vendor line buys what is missing in full stacks, capped by stock, and closes the merchant"; "the trainer buys class spells for 15 s every 0.2 s when switched on, and nothing when off"; "nothing is done for a quest in the section's noAuto list".
- `buttons.lua`: "a use line puts its item on a button and clicking uses it"; "a hearth line puts the hearthstone on a button, and Astral Recall for a shaman"; "buttons appear only with something to show"; "nothing secure changes in combat; the change happens after combat"; "target buttons target the exact name and set markers by position"; "a friendly target talked to is removed"; "target buttons hide on a flight and in raids"; "no macro function is called"; "the first four buttons of each kind are named and bound in Bindings.xml"; "buttons open at their defaults and stay on screen".

**Acceptance.** `node harness/run.js automation`, `buttons` and `npm run test:lua` pass.

### E10 Talents, professions, quest cleanup and the bug report on v3

**Files.** Modify `NoirGuides/Talents.lua`, `Professions.lua`, `Cleanup.lua`, `Diagnostics.lua`; tests `tools/test-lua/talents.lua`, `professions.lua`, `cleanup.lua`, `diagnostics.lua` (extend; replace cases that used format 2 routes).

**Talents (spec 5.11, gap #37).** Chat reminders 5 s after login and 1.5 s after a level-up or talent group change: asked once at level 10 to choose a build; told how many points are ready and the next pick; warned once about points off the build. `Talents.Builds() -> { { id, name } }` for the class (today one per class; more are owner data, later), `Talents.Choose(id)` per character and per talent group (`GetActiveTalentGroup` when present). In the talent window (`Blizzard_TalentUI` loaded, `TalentFrame` shown): the addon's own frames anchored above it: a build picker (through `Menu.Open`), an info line with the next point, and a pulsing ring on the next talent's button position (alpha between 0.4 and 1 over 1.2 s). The game's frames are not changed; points are never spent by the addon.

**Professions (spec 3.8, gap #36).** `Professions.IsPlanned(skill)` is what `when.profession` reads (with learned skills, through `Guide.When`). The chat plan uses `Lines.RANK_GATE` and `Lines.RANK_CAP` instead of its own copies, so the route's training steps (P3, judged by E3) and the plan agree. The Route tab's "profession to level with the route" (E8) calls `Professions.SetPlanned`.

**Cleanup (spec 5.9, 6.1, gap #38).** `Cleanup.RouteQuests()` reads the rest of the chain from the current step (current section to the end of `Guide.Chain`). Pre-ticked: failed quests and quests off the route; listed unticked: grey quests still on the route, quests ready to hand in, event quests, quests started by an item; never listed: class, profession, dungeon and raid quests and anything under the class or a profession header. `Cleanup.Offer()` opens the window only if at least one row starts ticked. Opened from the menu, the settings, a button the addon anchors beside the quest log frame, and by `Offer` after a hand-picked section change. The window opens at `Screen.DEFAULTS.dialog`, is kept on screen and capped by `Screen.Fit`. Nothing is abandoned before the player presses the button; bottom first, one every 0.2 s, stopped by combat.

**Diagnostics (gap #39).** The report adds: section ID and name, how it was chosen, the place (index, step ID), every card with each line's state and evidence, the reminders open, the options that differ from the defaults, the profile name and the screen size and UI scale.

**Failing tests first.**
- `talents.lua`: "the reminder comes 5 s after login and 1.5 s after a level-up"; "the build picker and next-point line appear above the talent window"; "the ring sits on the next talent and the game's frames are not changed"; "the choice is kept per talent group".
- `professions.lua`: "a training step exists only with the profession learned or planned"; "the chat plan and the route's training steps read the same gates and caps".
- `cleanup.lua`: "failed and off-route quests start ticked; grey on-route, ready, event and item-started quests are listed unticked"; "class and profession quests are never listed"; "Offer opens nothing when no row would start ticked"; "the window is on screen at 1024x768 with 25 rows"; "the quest log button opens it".
- `diagnostics.lua`: "the report names the section, the place and each line's state on the cards".

**Acceptance.** `node harness/run.js talents`, `professions`, `cleanup`, `diagnostics` and `npm run test:lua` pass.

---

## Integration

### X1 Simulator v3 with mid-route joiners

**Files.** Rewrite `tools/harness/sim.lua`; modify `tools/sim_all.js`, `tools/test/sim.test.js` (restore the whole-character test, now on format 3), create `tools/test-lua/sim.lua`; regenerate `docs/routes/SIM.md`.

**Interfaces.**
- `parseRoute(text)` in `sim_all.js` reads format 3 (sections, steps, lines); `buildFacts` builds the world from `flatten` of the character's steps.
- `Sim.play(facts, opts)` with `opts.join = level or nil`, returns `{ race, class, join, stuck, cannot, unexplained, errors, slash, offScreen, placement = { expectedFrom, landed }, level }`.
- `Sim.prepareJoin(facts, level)`: a player without the addon plays the route's flattened actions in the simulated world until the level is at least `level`, leaving out every 7th accept whose quest is no prerequisite of a later route quest (so the log differs from a perfect run). For `level = 1` the player accepts the first quest only. The prepared quest log, handed-in quests, level, known flight points, hearthstone and position are put into the mock client before `client:login()`, with empty saved variables.
- Constants: `JOIN_LEVELS = { 1, 12, 25, 40, 55 }`, `JOIN_BACK = 40` (flattened actions), `TRIES = 2`, `SETTLE = 1.5` s.

**The scripted player** reads `Progress.Cards()` only and does every open active line of every card: accept/turn-in (walk, talk; automation does the rest), objective (walk, finish the objective), collect (loot the item), goto (walk), getflight, fly, transport, sethearth, hearth (click the item button with the hearthstone), grind (fight to the level or percent), train (open the trainer), vendor (open the merchant), manual (click the tick box through `Window.Tick`). It never types a command. When a card is unchanged after `TRIES` attempts, the player ticks its lines with the mouse and the step counts as stuck. A level 1 character closes the wizard with its close button when it appears.

**Fails a run:** any stuck step, a step shown that the character cannot do, a why entry of a kind other than `done`, `moot`, `condition`, `outleveled`, `place`, `section` or `route` (the kinds that carry the game's evidence or describe placement), a Lua error or forbidden call, `slash > 0`, a non-empty `client:offScreen()` at the end, an end level below 60, and for joiners a placement outside `[expectedFrom - JOIN_BACK, first undone action after expectedFrom]` (indices of the flattened actions; `expectedFrom` = the last action the prepared player did).

**Runs.** `npm run sim` plays the 56 fresh characters (level 1, nothing done) and 50 joiners: for each of the 10 races, each of `JOIN_LEVELS`, with the class `classes[(k mod #classes) + 1]` of that race (k = 0 for level 1 up to 4 for level 55; classes in `combos()` order, 1-based). `npm run sim -- --joiners all` plays all 280 joiner combinations; `--race`, `--class`, `--join <level>` narrow a run. `SIM.md` gets one table for fresh runs and one for joiners (placement landed vs expected, steps passed by placement).

Fix failures at their root cause in the engine or the emitter (in their own files, with a test there); never special-case the simulator.

**Failing tests first.**
- `tools/test-lua/sim.lua`: "a fresh character plays the v3 sample to its end without a command"; "a joiner at the second sample section's level is placed there and plays on"; "a stuck card is ticked with the mouse and reported"; "a slash command fails the run".
- `tools/test/sim.test.js`: "a format 3 route file reads back as its sections, steps and lines"; "the world is built from the flattened steps"; "prepareJoin leaves out every 7th optional accept"; the restored "a whole character played by the real addon in the simulated world".

**Acceptance.** In `tools/`: `npm run sim` reports 56 of 56 fresh and 50 of 50 joiners at level 60 with 0 stuck, 0 unexplained, 0 slash, 0 off-screen and every joiner placed inside its window; `npm test` and `npm run test:lua` pass.

### X2 Packaging 0.2.0, independence check, docs

**Files.** `NoirGuides/NoirGuides.toc` (`## Version: 0.2.0`), `tools/test/package.test.js` (expects 0.2.0), `CHANGELOG.md`, `README.md`, `docs/ENGINE-NOTES.md`, `docs/INGAME-CHECKLIST.md`, `docs/INDEPENDENCE-REVIEW.md`, `tools/test/docs.test.js` (adapt the section heading it reads), delete `tools/compare_fork.js` and `tools/test/compare_fork.test.js`, create `tools/test/cleanroom.test.js`.

**Work.**
- `cleanroom.test.js`: "no file under NoirGuides/ or tools/ (outside tools/data/) names the old fork's folder"; "no tool reads a path outside the repository" (scan for absolute Windows paths in `tools/*.js`); "every Lua file under NoirGuides/ starts with the license line"; "Bindings.xml starts with the license comment".
- `INDEPENDENCE-REVIEW.md`: a new section "0.2.0: every shipped file" with one row per file under `NoirGuides/` and its verdict (the verdict words `docs.test.js` defines), stating it was written from the spec in a clean room, and the result of `independence.test.js` and `cleanroom.test.js`.
- `README.md`: install, first login (window, arrow, minimap button, wizard), that no command is needed, where the settings are, build/test/package commands.
- `CHANGELOG.md`: 0.2.0 entry: sections, bundled steps, card stack and step list, settings panel, minimap button, menus at the cursor, pins and arrow per spec, joiners placed by themselves, item and target buttons.
- `ENGINE-NOTES.md` and `INGAME-CHECKLIST.md`: every new assumption (options window API, secure button `macrotext`, mouse motion on pins, corpse position API, nameplate CVar, `Bindings.xml`, talent window anchoring, profession rank levels) numbered and carried into the checklist, so `docs.test.js` passes.
- `npm run package` → `dist/NoirGuides-0.2.0.zip`. No push, no release: the owner's release routine follows.

**Acceptance.** In `tools/`: `npm test`, `npm run test:lua`, `npm run routes` (0 errors), `npm run package` pass from a clean checkout after `npm run fetch`; `npm run sim` result of X1 still holds (rerun when anything under `NoirGuides/` changed in X2); the zip holds the one folder `NoirGuides/`; `git grep -n -i "its prefix\|restedxp" -- NoirGuides tools ':!tools/data'` finds nothing.

---

## Spec coverage

| Spec section | Tasks |
|---|---|
| Owner's requirement 1 (windows on screen) | E1 (Screen), E5, E6, E7, E8, E9, E10; checked in every UI test and by X1 |
| Owner's requirement 2 (no command needed) | E2, E4, E7, E8 (`MOUSE_PATHS`), X1 (`slash = 0`) |
| Owner's requirement 3 (parity, own name) | Global constraints (clean room), X2 |
| 1 Overview | E2, E4, E5, E6, E8, E9 |
| 2.1 Sections | C1 (format), P2 (emitted), E2 (registry) |
| 2.2 Section picker | E7; cleanup offer E7 + E10 |
| 2.3 Automatic selection, wizard | E2 (logic), E7 (wizard) |
| 2.4 Next section | E2 (`Next`), E4 (end of section, reminders hold) |
| 2.5 Joining mid-way | E4 (`Locate`, behind rule), E2 (first choice), X1 (joiners) |
| 2.6 Saved state | E1 (schema 2), E2 (owner check), E4 (places by step id, reminders, ticks) |
| 3.1 Step contents | C1, P1, P3 |
| 3.2 Line kinds | C1 (contract), E3 (states), E5 (display); kinds outside the Lines table are deferred (below) |
| 3.3 Current step choice | E4 |
| 3.4 Catch-up | E4 |
| 3.5 Skipping, why | E3 (conditions), E4 (why kinds), E5 (tooltip) |
| 3.6 Reminders | C1, P3 (emitted), E4 |
| 3.7 Outleveling, grind targets | P2 (grinds, maxLevel), E3 (grind line), E4 (synthetic grind, outleveled), E2/E8 (setting) |
| 3.8 Optional and conditional steps | C1 (`when`), E3, P3 + E10 (professions); dungeon, group, AH steps deferred |
| 4.1 Windows | E1, E5, E8 |
| 4.2 Guide window | E5 |
| 4.3 Step list | E5, E7 (step menu) |
| 4.4 Arrow | E6 |
| 4.5 Pins and lines | E6 |
| 4.6 Item and target buttons | E9 |
| 4.7 Notifications | E5 (quiet: no sound); the rest deferred |
| 5 general (modifiers, scope) | E9 |
| 5.1 to 5.5 | E9 |
| 5.6 Vendors | E9 (buy lines); junk deferred |
| 5.7 Trainers | E9, E10 (profession ranks) |
| 5.8 Dialogue | E9 |
| 5.9 Quest log | E10 (cleanup, quest log button) |
| 5.10 Party | deferred |
| 5.11 Talents | E10 |
| 5.12 Leveling tracker | deferred |
| 6.1 Settings | E1 (options), E8 (panel), E7 (wizard), E10 (cleanup window) |
| 6.2 Automatic behaviors 1 to 13 | 1 E2/E7; 2 E4; 3 E4; 4 E2/E4; 5 E4/E2; 6 E6; 7 E9; 8 E9; 9 E9; 10 E1; 11 E10; 12 E7/E10; 13 E2 (recreated character), E8 (conflict warning); version notices deferred with party |
| 6.3 Commands | E8 |
| 7 Data | P1 (quest facts, items, targets, prerequisites), P2 (levels, sections, grinds), P3 (texts, reminders, trainers, data files) |

| Gap # | Task | Gap # | Task | Gap # | Task |
|---|---|---|---|---|---|
| 1 | E1, E7 | 18 | C1, E3 | 35 | E9 |
| 2 | E1, E8 | 19 | E3, E4 | 36 | P3, E10 |
| 3 | E8 | 20 | E3, E4 | 37 | E10 |
| 4 | E8 | 21 | P2, E2, E4 | 38 | E10 |
| 5 | E7 | 22 | P2, E4 | 39 | E10 |
| 6 | C1, P2, E2 | 23 | E6 | 40 | E4, E5 |
| 7 | E2, E7 | 24 | E6 | 41 | deferred |
| 8 | E2, E7 | 25 | E9 | 42 | deferred |
| 9 | E2, E4 | 26 | E9 | 43 | deferred |
| 10 | E4, X1 | 27 | E9 | 44 | deferred |
| 11 | P1, E3, E5 | 28 | E9 | 45 | deferred |
| 12 | E4 | 29 | E9 | 46 | deferred |
| 13 | E4, E5 | 30 | E9 | 47 | deferred |
| 14 | E5 | 31 | E9 | 48 | E2, E4 |
| 15 | E4 | 32 | E9 | 49 | E7, E8 |
| 16 | E3 | 33 | deferred | | |
| 17 | E3 | 34 | deferred | | |

## Deferred on purpose

- **Spec "later" rows** (gaps #33 junk, #34 repair, #41 drowning and low-health warnings, #42 flight timer bar and flight times, #43 party sharing, announcements and version notices, #44 leveling tracker, #45 dungeon route family and dungeon settings, #46 side sections, #47 dangerous mobs) and the items the spec marks "should, later" (XP rate, hearthstone batching, the party step window, repair lines). The owner graded them later; none is needed for the route to play.
- **Line kinds the planner never emits** (abandon, explore, subzone arrival, die and respawn as a line, dialogue pages and options, tame, cast, emote, vehicle, bank, mail, reputation, money, equipped, buff, cooldown, bag slots, countdown, timer bars, web links, clickable text that loads a named section). The engine reads none of them yet (a step's `load` field covers forks in a route); format 3 refuses them (R7) so nothing silently ignores a step. The corpse arrow, which the spec asks of the arrow itself, is in E6.
- **Spell-by-spell training lists.** Class trainer visits are in the routes (P3 `addClassTraining`, owner requirement); naming each spell to learn would need the client's spell level tables, which are not fetched yet. The trainer window lists what can be learned, and E9 buys it when `train` is on.
- **More talent builds.** The talent window and picker are built for several builds per class (E10); the spec's three builds per class are owner data, and today there is one per class.
- **Tip card, quest log "which sections use this quest" button, item tooltips listing sections, wizard cards for dungeons, import and endgame, per-user raid markers in groups.** No section carries tips yet; the others belong with the dungeon route and party work above.
