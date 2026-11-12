# Noir Guides full build: planner v2, engine, ports

> **For agentic workers:** you are given one task ID from this file. Read **Global constraints**, **Route format 2** and your task. Work test-first. Commit only your own paths.

**Goal:** fix the generated routes' known weaknesses, build the in-game engine, port the Noir-written features, and prove that all 56 class and race combinations reach level 60 when the real engine plays the generated routes in a mock client.

**Spec:** `docs/superpowers/specs/2026-11-11-noir-guides-design.md`. **Earlier plan (types, existing code):** `docs/superpowers/plans/2026-11-11-route-planner.md`.

This plan gives contracts, files and acceptance checks rather than finished code: the owner asked for the whole build in one run, and the implementers are expected to write the tests named here first.

## Global constraints

- **Independence.** The old fork lives at the old fork's folder (outside this repository). Do not open anything in it unless your task says "port". A port may use a fork file only when (a) `git log --follow --format=%an -- <file>` in the fork shows it was added after the initial import commit, by Matthew Biban, and (b) the file contains no the reference addon code, format or text. Read it, then write the new file for this addon's structure; never copy a file that hooks, skins or calls an its prefix/`addon.` the reference addon object. Never copy the fork's flight time table, map tables or guide files. `tools/test/independence.test.js` must keep passing and no shipped file may contain the strings the reference addon's name or prefix (outside `tools/data/`).
- **License.** Every source file starts on line 1 with `// Noir Guides, GPLv3. See LICENSE.` (Lua: `-- Noir Guides, GPLv3. See LICENSE.`). Third-party libraries only if GPL-compatible, with their notice, and only if truly needed.
- **Client.** WoW Forever, `## Interface: 16001`, Lua 5.1 semantics (no `goto`, no integer division, no `//`, `unpack` not `table.unpack`). Feature-detect every API that differs between Classic builds and list unverified assumptions in `docs/ENGINE-NOTES.md`.
- **Forbidden in the addon:** registering `COMBAT_LOG_EVENT_UNFILTERED` (even in pcall), writing or editing macros, restyling `StaticPopup`, calling `SetFontObject` with an EditBox or an unnamed Font, protected calls in combat. Professions are read by skill line ID (`GetProfessions`/`GetProfessionInfo`/`C_SkillInfo`), not by spell names.
- **Engine rule.** A step is never skipped silently. Every time the engine moves past a step without the game confirming it, it records the reason; `/noir why` prints the last 20.
- **Races:** Human, Dwarf, Gnome, NightElf, HighOrder (Alliance); Orc, Troll, Tauren, Undead, Windshaper (Horde). HighOrder and Windshaper are the Skyborne races and start on Zephras Isle (area 16593, continent 2991). Race masks exceed 32 bits: always use `hasBit`.
- **Data** is in `tools/data/` (gitignored; already downloaded: QuestieDB `forever_db.json`, `vanilla_db.json`, wago CSVs). New client tables may be added to `tools/fetch_data.js` and fetched with `npm run fetch` from `tools/`.
- **Tests.** Node: `npm test` in `tools/` (`node --test test/*.test.js`). Lua: `npm run test:lua` (task E1 creates it). All must pass before you commit. Never weaken a test to make it pass; never change files while a test run is in progress.
- **Git.** Author is already configured in the repo. Stage only your task's paths (`git add <paths>`, never `git add -A`). Another stream may commit at the same time: on an `index.lock` error wait a few seconds and retry. End commit messages with the Co-Authored-By line for the model you run on (the session tells you; currently `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`). Never push.
- **Honesty.** If a fact is not in the data, do not invent it: mark it `verified = false`, list it in the task's notes file, and keep the route playable without it.

## Route format 2 (the contract between planner and engine)

One file per race: `NoirGuides/Routes/<faction>-<race>.lua` (lowercase), 10 files.

```lua
Noir.Route("horde-undead", {
  format = 2, race = "Undead", faction = "Horde",
  steps = {
    { action = "accept",    quest = 364, at = { zone = 85, x = 30.84, y = 66.2 }, npc = 1569 },
    { action = "objective", quest = 364, at = { zone = 85, x = 32.63, y = 63.5 }, npc = 1501 },          -- may carry item = N or object = N
    { action = "turnin",    quest = 364, at = { zone = 85, x = 30.84, y = 66.2 }, npc = 1569 },
    { action = "getflight", node = 384, at = { zone = 85, x = 0, y = 0 }, npc = 0 },                      -- learn a flight point
    { action = "fly",       from = 384, to = 10, at = { zone = 85, x = 0, y = 0 } },                      -- taxi node IDs
    { action = "transport", kind = "zeppelin", at = { zone = 85, x = 0, y = 0 }, to = { zone = 14, x = 0, y = 0 } }, -- kind: zeppelin, boat, tram, portal
    { action = "travel",    at = { zone = 130, x = 0, y = 0 } },                                          -- on foot to a place in another zone
    { action = "sethearth", at = { zone = 85, x = 0, y = 0 }, npc = 0 },
    { action = "hearth",    to = { zone = 85, x = 0, y = 0 } },
    { action = "grind",     level = 12, at = { zone = 85, x = 0, y = 0 } },
    { action = "accept",    quest = 8, at = { zone = 85, x = 38.23, y = 56.79 }, npc = 6784, when = { class = "ROGUE" } },
  },
})
```

- `at.zone` is an AreaTable zone ID; `x`, `y` are map percent (0 to 100) on that zone's map.
- `when` is optional: `class` (one class token) and/or `level` (minimum level). A step whose `when` does not match the character is not part of that character's route and is not a skip.
- Settled 2026-11-11: the planner does not emit `when.level`. When the character must be a higher level before the next step, the planner puts a `grind` step to that level first; the engine completes it when the level is reached. `when.level` stays in the engine for hand-written routes only.
- Class tokens: WARRIOR PALADIN HUNTER ROGUE PRIEST SHAMAN MAGE WARLOCK DRUID.
- Generated data files the engine reads, all under `NoirGuides/Data/`:
  - `Names.lua`: `Noir.Data.quests[id] = "name"`, `.npcs[id]`, `.objects[id]`, `.items[id]`, only for IDs the routes use.
  - `Zones.lua`: `Noir.Data.zones[areaId] = { uiMap = N, name = "..." }`.
  - `Flights.lua`: `Noir.Data.flights[nodeId] = { name = "...", zone = areaId, x = N, y = N }`.
- The engine builds all player-facing text from the action and these names. Routes contain no sentences.

## Stream P: planner (Node, `tools/`)

### P1 Data correctness
Files: `tools/lib/db.js`, `tools/lib/quests.js`, `tools/lib/characters.js`, tests, `docs/routes/DATA-NOTES.md`, `.gitattributes`.
Find the root cause in the data for each item, write a failing test, then fix:
1. Quest 8 "A Rogue's Deal" is offered to every Undead class. Find every quest that is class-only in practice but has no class mask (quest sort, giver, prerequisite chain) and give `eligible`/`levelingQuests` a rule for them. List them in DATA-NOTES.
2. Zephras Isle quests have no race mask: restrict quests whose start is on continent 2991 to the Skyborne races.
3. Windshaper skips Zephras Isle and HighOrder jumps from Zephras to Alterac: find out why (faction inference, missing level 1 quests, positions on continent 2991, map rows) and fix so both races start with their Zephras quests. Find how a character leaves the isle (quest chain, taxi node, transport) and record it for P2.
4. `loadDb` must keep the full-map UiMapAssignment row with the lowest OrderIndex.
5. Quests that can never be completed by the planner (Night Elf ends with 8309 and 8310 in the log) must not be accepted: no end point, repeatable, reputation or event gated.
6. License header on line 1 of every test file; `.gitattributes` forcing LF for `*.lua`, `*.js`, `*.md`.
Acceptance: `npm test` passes; `npm run routes` gives 0 validator errors; DATA-NOTES lists each finding with quest IDs.

### P2 Travel
Files: `tools/lib/travel.js`, `tools/planner/transports.json` (hand-written facts, each with `verified`), tests, `tools/fetch_data.js` if more tables are needed.
- Flight graph from TaxiNodes and TaxiPath: which faction can use each node (from the client data or the flight master NPC's faction in QuestieDB), its zone and map position, edges, and a time estimate from distance.
- Transport links (zeppelins, boats, Deeprun Tram, the way off Zephras Isle) written from the game's public facts into `transports.json`, never from the fork. Each has both ends as zone and percent, the factions that can use it, and `verified`.
- `travelPlan(db, graph, state, from, to)` returns `{ legs: [...], seconds }` using walking, known flight points, flight points picked up on the way (`getflight`), transports and hearthstone, never a flight the character has not learned. `state` = `{ faction, level, flights: Set, hearth: point|null }`.
Acceptance: unit tests for same zone, same continent with and without a known flight, cross-continent for each faction, and off Zephras Isle; a test that no leg uses an unlearned flight.

### P3 Planner v2
Files: `tools/planner/plan.js` (split into focused files under `tools/planner/` if it grows past ~300 lines), `tools/lib/xp.js`, `tools/planner/validate.js`, `tools/planner/emit.js`, `tools/planner/report.js`, tests.
- **Zone commitment:** stay in a zone while it has enough worthwhile quests for the level; leave only when the zone is spent or a log quest's last step is elsewhere and cheap. Batch by hub: accept everything at a hub, do objectives in a loop, return once.
- **Cost-based choice:** pick the next task by travel seconds from `travelPlan`, not straight-line yards, with look-ahead to avoid ping-pong between hubs.
- **Next zone:** by level fit, quest count and travel cost from where the player is; emit the legs from `travelPlan` as format 2 steps; set hearth at each new main hub when it saves time.
- **Pacing:** add kill XP for objective kills and for walking through level-appropriate areas so that grind steps are rare and short; no route may end with a grind of more than one level. Keep the estimate constants in one place with a comment on how each was derived.
- Emit format 2 and the three `NoirGuides/Data/*.lua` files.
- The validator replays independently of the planner and additionally fails on: a flight not learned, a transport the faction cannot use, a step outside the continent the player is on without a leg that got them there, quests left in the log at the end, a `when` step for the wrong class.
Acceptance, measured by `docs/routes/REPORT.md` against the baseline in git (`37a4f8c`): zone changes per route down by at least 60% for every race; total travel time not worse for any race; 0 validator errors; every race reaches 60; report shows before and after.

### P4 Classes: 56 characters
Files: `tools/planner/classes.js`, `tools/build_routes.js`, validator, tests, report.
- Layer each class's quests into its race route with `when = { class = ... }` at the cheapest detour that keeps level and prerequisites.
- Trainer visits are out of scope here; only quests are layered.
- The build validates all 56 characters from `combos()` against their race file and writes per-character results into `tools/data/build_status.json` and the report.
Acceptance: 56 of 56 valid and at level 60; no class quest reaches a wrong class; `npm test` and `npm run routes` pass.

## Stream E: engine (Lua, `NoirGuides/`)

### E1 Harness, Core, Routes, State
Files: `NoirGuides/NoirGuides.toc`, `NoirGuides/Core.lua`, `Routes.lua`, `State.lua`, `tools/harness/` (mock client and runner), `tools/test-lua/*.lua`, `tools/package.json` (`test:lua`).
- Mock client: runs the addon's files in toc order in a Lua VM from npm (Lua 5.1 behavior as far as the library allows), with a fake API (frames, events, quest log, taxi, map, saved variables) driven by test scripts. Port from the fork's `tools/harness/wow.lua` only under the port rule.
- `Core`: namespace `Noir`, saved variables `NoirGuidesDB` (account) and `NoirGuidesCharDB`, event bus, slash `/noir`.
- `Routes`: `Noir.Route(id, data)` registers; picks the file for the player's race; filters steps by `when`.
- `State`: level, class, race, quest log, completed quests, known flight points, hearth bind, professions, position, each refreshed from events.
Acceptance: Lua tests for registration, `when` filtering, state updates from mock events; a hand-written 12-step sample route in the tests.

### E2 Progress, Automation, why-log
Files: `NoirGuides/Progress.lua`, `Automation.lua`, `Why.lua`, tests.
- `Progress`: current step; completion from game state only (quest in log, objectives complete, quest turned in, flight learned, zone and distance reached, level reached, bind changed). On login or route change it fast-forwards past steps the character has demonstrably done and logs why. Steps the character can no longer do (quest greyed out is fine; quest unavailable is not) are reported, not hidden.
- `Automation` (each switchable): accept and turn in quests at the step's NPC, choose the gossip option that leads to the quest or flight, take the step's flight, confirm hearth bind. Never choose a quest reward for the player.
- `/noir why`, `/noir skip` (manual, logged), `/noir back`, `/noir reset`.
Acceptance: Lua tests replaying the sample route through mock events, including out-of-order play, relog mid-route and a manual skip.

### E3 Window, Arrow, Map
Files: `NoirGuides/UI/Window.lua`, `UI/Arrow.lua`, `UI/Map.lua`, `UI/Text.lua` (step to text), `UI/Theme.lua`, `NoirGuides/Textures/`, `tools/gen_textures.js`, `DESIGN.md`, tests.
- Port `DESIGN.md` (Strip Bay) and the textures generator from the fork under the port rule; the design is the authority for colors, type and layout. Game default fonts for now (the font file is added later by the owner).
- Window: one lit strip for the current step, a rack of the next steps, a level rail; movable, lockable, scalable, position saved. Text from `UI/Text.lua` using `Noir.Data` names with a client API fallback.
- Arrow: direction and distance to the current step from player map position, across zones on the same continent; hidden when unknown.
- Map: pins for the current and next steps on the world map and minimap without touching protected frames.
Acceptance: Lua tests that the window shows the right text for each action, the arrow math is right for known points, and nothing errors when map data is missing.

## Integration

### X1 Simulator: the real engine plays every route
Files: `tools/harness/sim.lua`, `tools/sim_all.js`, `tools/package.json` (`sim`), report.
Load the full addon in the mock client for each of the 56 characters and let a scripted player do exactly what each step says. Fail when the engine is stuck, shows a step the character cannot do, or the character does not reach 60. Fix the engine or the planner at the root cause; never special-case the simulator.
Acceptance: `npm run sim` reports 56 of 56 at level 60 with 0 stuck steps and 0 unexplained skips.

### X2 Ports
Files: `NoirGuides/Menu.lua`, `Cleanup.lua`, `Talents.lua` plus `Data/Talents.lua`, `Professions.lua`, `Diagnostics.lua`, their tests, generators under `tools/`.
Each under the port rule, rewritten for this engine: the options and route menu, quest log cleanup with a review list (never abandons without the player ticking the quest), talent builds with legality checks, the profession plan (trainer gates 50/125/200), `/noir bug` diagnostics.
Acceptance: Lua tests per module; `npm run sim` still 56 of 56.

### X3 Independence review, packaging, docs
Files: `tools/package_addon.js` (`npm run package` → `dist/NoirGuides-<version>.zip` with `NoirGuides/` at the top), `README.md`, `CHANGELOG.md`, `docs/INDEPENDENCE-REVIEW.md`, `docs/INGAME-CHECKLIST.md`.
Compare every shipped Lua file against the fork for copied structure or text and rewrite anything found; record the result per file. Write the checklist of everything only the owner can confirm in game (unverified transports, API assumptions, Skyborne start).
Acceptance: all test suites and the simulator pass from a clean checkout after `npm run fetch`; the zip installs as one folder; version `0.1.0`.
