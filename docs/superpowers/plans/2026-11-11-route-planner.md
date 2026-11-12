# Route Planner (Plan 1 of the independent Noir Guides) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate a validated level 1-60 leveling route for every race WoW Forever offers (10 races, 56 class and race combinations) from quest data, as Lua data files plus a readable report.

**Architecture:** A Node toolchain in `tools/`. `lib/` loads and normalizes QuestieDB Forever and client tables into one in-memory database. `planner/` simulates a player (level, position, quest log) and orders quest pickups, objectives and turn-ins by nearest travel, zone by zone. `planner/validate.js` replays each route independently and fails on any step a character cannot do. `build_routes.js` runs everything and writes `NoirGuides/Routes/*.lua`.

**Tech Stack:** Node 24 (built-in `node:test`, no test framework dependency), plain CommonJS, no runtime dependencies. Output is Lua 5.1 data.

**Spec:** `docs/superpowers/specs/2026-11-11-noir-guides-design.md`

**Not in this plan (later plans):** the in-game engine, flights/boats/zeppelins between zones (routes say "Travel to <zone>"), class quests, professions, talents, dungeons, Forever-only quests outside Zephras Isle, route improvement passes beyond nearest-neighbor.

## Global Constraints

- **Independence:** never open, read or copy anything under the old fork's folder (outside this repository) (the the reference addon fork's addon folder), nor any fork tool that parses the reference addon guides. The only fork files that may be read are the Noir-written, guide-independent tools named in Task 1.
- **License:** GPLv3. Every new source file starts with the line `-- Noir Guides, GPLv3. See LICENSE.` (Lua) or `// Noir Guides, GPLv3. See LICENSE.` (JS).
- **Determinism:** the same data must produce byte-identical routes. No `Math.random`, no `Date` in outputs. Ties break on the lower quest ID.
- **No guessed game facts:** quest, NPC, object, item, area and taxi IDs and coordinates come only from `tools/data/`. Constants in code (class and race IDs, XP table, instance area IDs) carry a comment naming their source.
- **Race masks exceed 32 bits** (Skyborne are bits 32 and 33). Test them with `hasBit(mask, bit)`, never with `&`.
- **Tests:** `cd tools && npm test` runs `node --test test/`. Unit tests use the fixture in `test/fixture.js`; tests that need the real data skip themselves when `tools/data/forever_db.json` is absent.
- **Repository:** `. Commit after each task with the message given. End every commit message with `Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>`. Do not push.

## File Structure

```
Noir-Guides/
  LICENSE                      GPLv3 (exists)
  README.md                    what it is, credits (QuestieDB GPLv3, client data, Barlow OFL)
  .gitignore                   tools/data/, node_modules/
  NoirGuides/Routes/           generated: one Lua file per race
  docs/routes/REPORT.md        generated: per-race summary
  tools/
    package.json               scripts: test, fetch, routes
    data_sources.json          QuestieDB release tag and wago build
    fetch_data.js              downloads QuestieDB + client CSVs into tools/data/
    questiedb_export.js        QuestieDB Lua -> forever_db.json (ported, Noir-written)
    build_routes.js            CLI: plan, validate, emit, report for all races
    lib/csv.js                 CSV parsing
    lib/db.js                  load + normalize into the Db shape
    lib/characters.js          classes, races, combos, hasBit, eligibility
    lib/geo.js                 zone of an area, map % -> world coords, distance, spawns
    lib/xp.js                  XP-to-level table and XP estimates
    lib/quests.js              which quests are leveling quests; availability
    planner/zones.js           level band per zone and faction
    planner/plan.js            the route planner
    planner/validate.js        independent replay and rule checks
    planner/emit.js            Route -> Lua text
    planner/report.js          Route -> markdown summary
    test/fixture.js            a tiny hand-made Db for unit tests
    test/*.test.js
```

## Shared Types (every task relies on these exact shapes)

```js
// Db: returned by lib/db.js loadDb(dataDir)
{
  quests:  Map<number, Quest>,
  npcs:    Map<number, { id, name, friendly: "A"|"H"|"AH"|"", spawns: { [areaId: string]: [number, number][] } }>,
  objects: Map<number, { id, name, spawns: { [areaId: string]: [number, number][] } }>,
  items:   Map<number, { id, name, npcDrops: number[], objectDrops: number[] }>,
  areas:   Map<number, { id, name, parent: number, continent: number }>,
  maps:    Map<number, { area, uiMap, minX, minY, maxX, maxY }>,   // keyed by area ID; world bounds
  taxi:    { id, name, x, y, continent }[],
  eraQuestIds: Set<number>,                                         // quest IDs that exist in vanilla_db.json
}
// Quest (normalized)
{
  id, name, level /* questLevel */, minLevel /* requiredLevel */,
  races /* mask, 0 = all */, classes /* mask, 0 = all */,
  preAny: number[],   // preQuestSingle: any one done unlocks
  preAll: number[],   // preQuestGroup: all must be done
  exclusive: number[],
  zone: number,       // zoneOrSort when > 0, else 0
  sort: number,       // zoneOrSort when < 0, else 0
  starts: { npcs: number[], objects: number[], items: number[] },
  ends:   { npcs: number[], objects: number[] },
  objectives: { npcs: number[], objects: number[], items: number[] },
  trigger: { text: string, spawns: { [areaId: string]: [number, number][] } } | null,
  repeatable: boolean, // specialFlags bit 1
  gated: boolean,      // needs a skill, reputation, spell, specialization, rank or parent quest
}
// Character
{ race: "Undead", cls: "ROGUE", faction: "Horde", raceBit: 4, classId: 4, startArea: 85 }
// Point: a place in the world
{ zone: number /* top-level area ID */, x: number, y: number /* map percent 0-100 */, wx: number, wy: number, continent: number }
// Step (the route format; also what emit.js writes)
{ action: "accept"|"objective"|"turnin"|"travel"|"grind", quest?: number, zone?: number, level?: number,
  at?: { zone, x, y }, npc?: number, object?: number, item?: number, note?: string }
// Route
{ id: "horde-undead", race: "Undead", faction: "Horde", steps: Step[],
  stats: { quests: number, distance: number /* yards */, endLevel: number, levelAt: number[] /* step index where each level is reached */ } }
```

---

### Task 1: Foundation and data

**Files:**
- Create: `README.md`, `.gitignore`, `tools/package.json`, `tools/data_sources.json`, `tools/fetch_data.js`, `tools/questiedb_export.js`, `tools/lib/csv.js`, `tools/test/csv.test.js`

**Interfaces:**
- Produces: `parseCsv(text) -> { header: string[], rows: string[][] }` and `readCsv(file) -> object[]` (one object per row keyed by header) from `lib/csv.js`. `tools/data/forever_db.json`, `tools/data/vanilla_db.json`, `tools/data/wago/*.csv` on disk.

Fork files that MAY be read for this task, all Noir-written and unrelated to the reference addon guides: `the old fork's folder/tools/questiedb_export.js`, `.../tools/pipeline.js` (only the QuestieDB download and export part, lines that mention `questiedb`), `.../tools/check_updates.js` (only the `--fetch-wago` part), `.../tools/data_sources.json`.

- [ ] **Step 1: Write the failing CSV test**

```js
// tools/test/csv.test.js
// Noir Guides, GPLv3. See LICENSE.
const test = require("node:test");
const assert = require("node:assert");
const { parseCsv } = require("../lib/csv");

test("parses quoted fields with commas and doubled quotes", () => {
  const { header, rows } = parseCsv('Name,ID\n"Ironforge, Dun Morogh",6\n"Say ""hi""",7\n');
  assert.deepStrictEqual(header, ["Name", "ID"]);
  assert.deepStrictEqual(rows, [["Ironforge, Dun Morogh", "6"], ['Say "hi"', "7"]]);
});
test("handles CRLF and a missing final newline", () => {
  assert.deepStrictEqual(parseCsv("a,b\r\n1,2").rows, [["1", "2"]]);
});
```

- [ ] **Step 2: Run it, expect failure** — `cd tools && node --test test/` fails with `Cannot find module '../lib/csv'`.

- [ ] **Step 3: Implement `lib/csv.js`**

```js
// Noir Guides, GPLv3. See LICENSE.
const fs = require("fs");
function parseCsv(text) {
  const out = [];
  let row = [], cell = "", quoted = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (quoted) {
      if (ch === '"' && text[i + 1] === '"') { cell += '"'; i++; }
      else if (ch === '"') quoted = false;
      else cell += ch;
    } else if (ch === '"') quoted = true;
    else if (ch === ",") { row.push(cell); cell = ""; }
    else if (ch === "\n" || ch === "\r") {
      if (ch === "\r" && text[i + 1] === "\n") i++;
      row.push(cell); cell = "";
      if (row.length > 1 || row[0] !== "") out.push(row);
      row = [];
    } else cell += ch;
  }
  if (cell !== "" || row.length) { row.push(cell); out.push(row); }
  return { header: out[0] || [], rows: out.slice(1) };
}
function readCsv(file) {
  const { header, rows } = parseCsv(fs.readFileSync(file, "utf8"));
  return rows.map((r) => Object.fromEntries(header.map((h, i) => [h, r[i]])));
}
module.exports = { parseCsv, readCsv };
```

- [ ] **Step 4: Run tests, expect pass.**

- [ ] **Step 5: Scaffolding.** `tools/package.json`:

```json
{
  "name": "noir-guides-tools",
  "private": true,
  "license": "GPL-3.0-only",
  "scripts": { "test": "node --test test/", "fetch": "node fetch_data.js", "routes": "node build_routes.js" }
}
```

`.gitignore`: `tools/data/` and `node_modules/`. `tools/data_sources.json`: `{ "questiedb": { "release": "v1.0.14" }, "wago": { "build": "1.60.1.70888" } }`. `README.md`: one paragraph on what Noir Guides is, that it is GPLv3, and a Credits list: QuestieDB (GPLv3, quest and world data), client tables via wago.tools, Barlow Semi Condensed (SIL OFL, used later).

- [ ] **Step 6: Port the exporter and write `fetch_data.js`.** Copy `questiedb_export.js` from the fork tools unchanged except for the license header line. Write `fetch_data.js` so that `node fetch_data.js` (a) downloads the QuestieDB release named in `data_sources.json` and runs the exporter for the Forever and Vanilla flavors into `tools/data/forever_db.json` and `tools/data/vanilla_db.json`, exactly as the fork's `pipeline.js` does, and (b) downloads these client tables as CSV for the build in `data_sources.json` into `tools/data/wago/`, exactly as the fork's `check_updates.js --fetch-wago` does: `AreaTable`, `CharBaseInfo`, `ChrRaces`, `TaxiNodes`, `TaxiPath`, `UiMap`, `UiMapAssignment`. If a download fails, print the URL and exit 1.

- [ ] **Step 7: Run `npm run fetch`** and confirm: `forever_db.json` has more than 5,000 quests; `vanilla_db.json` more than 4,000; `wago/UiMapAssignment.csv` has a row with `AreaID` 17. If the network is unavailable, copy those same files from `the old fork's folder/tools/data/` (they are downloads, not fork content) and say so in the task report.

- [ ] **Step 8: Commit** — `git add -A && git commit -m "Foundation: license, data fetch, CSV reader"`

---

### Task 2: The database (`lib/db.js`) and the test fixture

**Files:**
- Create: `tools/lib/db.js`, `tools/test/fixture.js`, `tools/test/db.test.js`

**Interfaces:**
- Consumes: `readCsv` from Task 1.
- Produces: `loadDb(dataDir) -> Db` and `normalizeQuest(id, raw) -> Quest` from `lib/db.js`; `fixtureDb() -> Db` from `test/fixture.js`.

Raw QuestieDB facts the normalizer must handle (verified on v1.0.14):
- `startedBy` / `finishedBy` are `[npcs, objects, items]` arrays, or an object keyed `"1"`,`"2"`,`"3"` (1-based) when sparse, e.g. `{"3":[16790]}`. Missing means none.
- `objectives` is either an array `[creatures, objects, items, ...]` or an object keyed `"1"`,`"2"`,`"3"`; each entry is a list of `[id, text, icon]`.
- `triggerEnd` is `[text, { areaId: [[x, y], ...] }]`.
- `zoneOrSort` > 0 is an area ID (often a subzone, e.g. 154 Deathknell whose parent is 85); < 0 is a quest sort.
- `specialFlags` bit 1 = repeatable.
- NPC `friendlyToFaction` is `"A"`, `"H"`, `"AH"` or absent.

- [ ] **Step 1: Write the failing tests**

```js
// tools/test/db.test.js
// Noir Guides, GPLv3. See LICENSE.
const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const path = require("path");
const { normalizeQuest, loadDb } = require("../lib/db");
const DATA = path.join(__dirname, "..", "data");
const real = fs.existsSync(path.join(DATA, "forever_db.json"));

test("normalizes array-form starts and objectives", () => {
  const q = normalizeQuest(364, { name: "The Mindless Ones", startedBy: [[1569]], finishedBy: [[1569]], requiredLevel: 1, questLevel: 2,
    requiredRaces: 8589934770, objectives: [[[1501, null, 0], [1502, null, 0]]], zoneOrSort: 154 });
  assert.deepStrictEqual(q.starts, { npcs: [1569], objects: [], items: [] });
  assert.deepStrictEqual(q.objectives, { npcs: [1501, 1502], objects: [], items: [] });
  assert.strictEqual(q.zone, 154); assert.strictEqual(q.sort, 0);
  assert.strictEqual(q.level, 2); assert.strictEqual(q.minLevel, 1);
});
test("normalizes keyed-form starts and objectives", () => {
  const q = normalizeQuest(6564, { name: "x", startedBy: { "3": [16790] }, finishedBy: [[12736]], objectives: { "3": [[16790, null, 0]] }, zoneOrSort: -81 });
  assert.deepStrictEqual(q.starts, { npcs: [], objects: [], items: [16790] });
  assert.deepStrictEqual(q.objectives.items, [16790]);
  assert.strictEqual(q.zone, 0); assert.strictEqual(q.sort, -81);
});
test("flags repeatable and gated quests, and reads prerequisites", () => {
  const q = normalizeQuest(1, { name: "x", specialFlags: 1, requiredSkill: [185, 1], preQuestSingle: [5], preQuestGroup: [6, 7], exclusiveTo: [9] });
  assert.strictEqual(q.repeatable, true); assert.strictEqual(q.gated, true);
  assert.deepStrictEqual([q.preAny, q.preAll, q.exclusive], [[5], [6, 7], [9]]);
});
test("reads trigger objectives", () => {
  const q = normalizeQuest(870, { name: "x", triggerEnd: ["Explore", { "17": [[45.06, 22.53]] }] });
  assert.deepStrictEqual(q.trigger, { text: "Explore", spawns: { "17": [[45.06, 22.53]] } });
});
test("loads the real database", { skip: !real }, () => {
  const db = loadDb(DATA);
  assert.ok(db.quests.size > 5000);
  assert.strictEqual(db.quests.get(364).name, "The Mindless Ones");
  assert.strictEqual(db.areas.get(154).parent, 85);
  assert.strictEqual(db.areas.get(85).name, "Tirisfal Glades");
  assert.ok(db.maps.get(17).maxX > db.maps.get(17).minX);
  assert.ok(db.eraQuestIds.has(364));
  assert.ok(db.taxi.some((t) => t.name.startsWith("Crossroads")));
});
```

- [ ] **Step 2: Run, expect failure** (`Cannot find module '../lib/db'`).

- [ ] **Step 3: Implement `lib/db.js`**

```js
// Noir Guides, GPLv3. See LICENSE.
const fs = require("fs");
const path = require("path");
const { readCsv } = require("./csv");

// QuestieDB lists are arrays, or objects keyed "1".."n" (1-based) when sparse.
const slot = (v, i) => (!v ? [] : Array.isArray(v) ? v[i] || [] : v[String(i + 1)] || []);
const ids = (list) => (list || []).map((e) => (Array.isArray(e) ? e[0] : e)).filter((n) => typeof n === "number");

function normalizeQuest(id, raw) {
  const z = raw.zoneOrSort || 0;
  return {
    id: +id, name: raw.name || "", level: raw.questLevel || 0, minLevel: raw.requiredLevel || 0,
    races: raw.requiredRaces || 0, classes: raw.requiredClasses || 0,
    preAny: raw.preQuestSingle || [], preAll: raw.preQuestGroup || [], exclusive: raw.exclusiveTo || [],
    zone: z > 0 ? z : 0, sort: z < 0 ? z : 0,
    starts: { npcs: ids(slot(raw.startedBy, 0)), objects: ids(slot(raw.startedBy, 1)), items: ids(slot(raw.startedBy, 2)) },
    ends: { npcs: ids(slot(raw.finishedBy, 0)), objects: ids(slot(raw.finishedBy, 1)) },
    objectives: { npcs: ids(slot(raw.objectives, 0)), objects: ids(slot(raw.objectives, 1)), items: ids(slot(raw.objectives, 2)) },
    trigger: raw.triggerEnd ? { text: raw.triggerEnd[0], spawns: raw.triggerEnd[1] || {} } : null,
    repeatable: ((raw.specialFlags || 0) & 1) === 1,
    gated: !!(raw.requiredSkill || raw.requiredMinRep || raw.requiredMaxRep || raw.requiredSpell || raw.requiredSpecialization || raw.requiredRanks || raw.parentQuest),
  };
}

function loadDb(dataDir) {
  const raw = JSON.parse(fs.readFileSync(path.join(dataDir, "forever_db.json"), "utf8"));
  const era = JSON.parse(fs.readFileSync(path.join(dataDir, "vanilla_db.json"), "utf8"));
  const db = { quests: new Map(), npcs: new Map(), objects: new Map(), items: new Map(), areas: new Map(), maps: new Map(), taxi: [], eraQuestIds: new Set() };
  for (const [id, q] of Object.entries(raw.Quest)) db.quests.set(+id, normalizeQuest(id, q));
  for (const [id, n] of Object.entries(raw.Npc)) db.npcs.set(+id, { id: +id, name: n.name || "", friendly: n.friendlyToFaction || "", spawns: n.spawns || {} });
  for (const [id, o] of Object.entries(raw.Object)) db.objects.set(+id, { id: +id, name: o.name || "", spawns: o.spawns || {} });
  for (const [id, i] of Object.entries(raw.Item)) db.items.set(+id, { id: +id, name: i.name || "", npcDrops: i.npcDrops || [], objectDrops: i.objectDrops || [] });
  for (const id of Object.keys(era.Quest)) db.eraQuestIds.add(+id);
  const wago = (name) => readCsv(path.join(dataDir, "wago", name + ".csv"));
  for (const a of wago("AreaTable")) db.areas.set(+a.ID, { id: +a.ID, name: a.AreaName_lang, parent: +a.ParentAreaID, continent: +a.ContinentID });
  // world bounds of each zone map: the full-map assignment row (UiMin 0,0 to UiMax 1,1) with the lowest OrderIndex
  for (const m of wago("UiMapAssignment")) {
    if (+m.UiMin_0 !== 0 || +m.UiMin_1 !== 0 || +m.UiMax_0 !== 1 || +m.UiMax_1 !== 1 || +m.AreaID === 0) continue;
    if (db.maps.has(+m.AreaID)) continue;
    db.maps.set(+m.AreaID, { area: +m.AreaID, uiMap: +m.UiMapID, minX: +m.Region_0, minY: +m.Region_1, maxX: +m.Region_3, maxY: +m.Region_4 });
  }
  for (const t of wago("TaxiNodes")) db.taxi.push({ id: +t.ID, name: t.Name_lang, x: +t.Pos_0, y: +t.Pos_1, continent: +t.ContinentID });
  return db;
}
module.exports = { loadDb, normalizeQuest };
```

- [ ] **Step 4: Run tests, expect pass** (the real-data test runs if Task 1 fetched data).

- [ ] **Step 5: Write `test/fixture.js`**, the small world every later unit test uses. Zone 1000 "Testvale" (levels 1-5, continent 0, world bounds x 0..1000, y 0..1000) and zone 2000 "Farlands" (levels 5-10, same continent, bounds x 0..1000, y 2000..3000). Map percent to world is defined in Task 4; with these bounds a point at (50, 50) in zone 1000 is world (500, 500).

```js
// Noir Guides, GPLv3. See LICENSE.
const { normalizeQuest } = require("../lib/db");
function fixtureDb() {
  const db = { quests: new Map(), npcs: new Map(), objects: new Map(), items: new Map(), areas: new Map(), maps: new Map(), taxi: [], eraQuestIds: new Set() };
  const area = (id, name, parent) => db.areas.set(id, { id, name, parent, continent: 0 });
  area(1000, "Testvale", 0); area(1001, "Testvale Camp", 1000); area(2000, "Farlands", 0);
  db.maps.set(1000, { area: 1000, uiMap: 1, minX: 0, minY: 0, maxX: 1000, maxY: 1000 });
  db.maps.set(2000, { area: 2000, uiMap: 2, minX: 0, minY: 2000, maxX: 1000, maxY: 3000 });
  const npc = (id, name, zone, x, y, friendly = "AH") => db.npcs.set(id, { id, name, friendly, spawns: { [zone]: [[x, y]] } });
  npc(1, "Giver Ann", 1000, 50, 50); npc(2, "Giver Bob", 1000, 52, 50); npc(3, "Wolf", 1000, 60, 60, "");
  npc(4, "Boar", 1000, 40, 40, ""); npc(5, "Far Giver", 2000, 50, 50); npc(6, "Far Beast", 2000, 55, 55, "");
  npc(7, "Horde Only Giver", 1000, 50, 52, "H");
  db.items.set(100, { id: 100, name: "Boar Tusk", npcDrops: [4], objectDrops: [] });
  const quest = (id, raw) => { db.quests.set(id, normalizeQuest(id, raw)); db.eraQuestIds.add(id); };
  quest(10, { name: "Wolves", startedBy: [[1]], finishedBy: [[1]], requiredLevel: 1, questLevel: 2, objectives: [[[3, null, 0]]], zoneOrSort: 1001 });
  quest(11, { name: "Tusks", startedBy: [[2]], finishedBy: [[2]], requiredLevel: 1, questLevel: 3, objectives: { "3": [[100, null, 0]] }, zoneOrSort: 1000 });
  quest(12, { name: "More Wolves", startedBy: [[1]], finishedBy: [[2]], requiredLevel: 2, questLevel: 4, objectives: [[[3, null, 0]]], preQuestSingle: [10], zoneOrSort: 1000 });
  quest(13, { name: "Horde Errand", startedBy: [[7]], finishedBy: [[7]], requiredLevel: 1, questLevel: 2, requiredRaces: 178, zoneOrSort: 1000 });
  quest(14, { name: "Too High", startedBy: [[1]], finishedBy: [[1]], requiredLevel: 40, questLevel: 45, zoneOrSort: 1000 });
  quest(15, { name: "Daily", startedBy: [[1]], finishedBy: [[1]], requiredLevel: 1, questLevel: 2, specialFlags: 1, zoneOrSort: 1000 });
  quest(20, { name: "Far Beasts", startedBy: [[5]], finishedBy: [[5]], requiredLevel: 4, questLevel: 6, objectives: [[[6, null, 0]]], zoneOrSort: 2000 });
  quest(21, { name: "Far Report", startedBy: [[5]], finishedBy: [[5]], requiredLevel: 5, questLevel: 7, preQuestSingle: [20], zoneOrSort: 2000 });
  return db;
}
module.exports = { fixtureDb };
```

- [ ] **Step 6: Commit** — `git add -A && git commit -m "Database loader, quest normalizer, test fixture"`

---

### Task 3: Characters and eligibility (`lib/characters.js`)

**Files:**
- Create: `tools/lib/characters.js`, `tools/test/characters.test.js`

**Interfaces:**
- Consumes: `readCsv`; `Db`, `Quest`.
- Produces: `CLASSES`, `RACES`, `hasBit(mask, bit) -> boolean`, `combos(dataDir) -> Character[]`, `character(race, cls) -> Character`, `eligible(quest, character) -> boolean`.

- [ ] **Step 1: Write the failing tests**

```js
// tools/test/characters.test.js
// Noir Guides, GPLv3. See LICENSE.
const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const path = require("path");
const { hasBit, character, eligible, combos, RACES } = require("../lib/characters");
const { normalizeQuest } = require("../lib/db");
const DATA = path.join(__dirname, "..", "data");
const real = fs.existsSync(path.join(DATA, "wago", "CharBaseInfo.csv"));

test("hasBit works above 32 bits", () => {
  assert.strictEqual(hasBit(8589934770, 33), true);   // Horde mask includes Windshaper (bit 33)
  assert.strictEqual(hasBit(8589934770, 32), false);
  assert.strictEqual(hasBit(4294967373, 32), true);   // Alliance mask includes High Order (bit 32)
  assert.strictEqual(hasBit(178, 4), true);           // Undead
  assert.strictEqual(hasBit(178, 0), false);          // not Human
});
test("eligibility by race and class", () => {
  const rogue = character("Undead", "ROGUE");
  assert.strictEqual(eligible(normalizeQuest(1, { requiredRaces: 8589934770 }), rogue), true);
  assert.strictEqual(eligible(normalizeQuest(1, { requiredRaces: 4294967373 }), rogue), false);
  assert.strictEqual(eligible(normalizeQuest(1, {}), rogue), true);
  assert.strictEqual(eligible(normalizeQuest(1, { requiredClasses: 1 }), rogue), false); // Warrior only
  assert.strictEqual(eligible(normalizeQuest(1, { requiredClasses: 8 }), rogue), true);  // Rogue = class ID 4, bit 3
});
test("start areas are real areas", () => {
  assert.strictEqual(RACES.Undead.startArea, 85);
  assert.strictEqual(RACES.HighOrder.startArea, 16593);
});
test("the client offers 56 combinations", { skip: !real }, () => {
  const all = combos(DATA);
  assert.strictEqual(all.length, 56);
  assert.ok(all.some((c) => c.race === "Undead" && c.cls === "PALADIN"));
});
```

- [ ] **Step 2: Run, expect failure.**

- [ ] **Step 3: Implement**

```js
// Noir Guides, GPLv3. See LICENSE.
const path = require("path");
const { readCsv } = require("./csv");

// Class IDs: the client's ChrClasses. The class mask bit is id - 1.
const CLASSES = { WARRIOR: 1, PALADIN: 2, HUNTER: 3, ROGUE: 4, PRIEST: 5, SHAMAN: 7, MAGE: 8, WARLOCK: 9, DRUID: 11 };
// Race IDs and PlayableRaceBit: the client's ChrRaces. Start areas: AreaTable (1 Dun Morogh, 12 Elwynn Forest, 14 Durotar,
// 85 Tirisfal Glades, 141 Teldrassil, 215 Mulgore, 16593 Zephras Isle). Skyborne are two client races, one per faction.
const RACES = {
  Human: { id: 1, bit: 0, faction: "Alliance", startArea: 12 },
  Orc: { id: 2, bit: 1, faction: "Horde", startArea: 14 },
  Dwarf: { id: 3, bit: 2, faction: "Alliance", startArea: 1 },
  NightElf: { id: 4, bit: 3, faction: "Alliance", startArea: 141 },
  Undead: { id: 5, bit: 4, faction: "Horde", startArea: 85 },
  Tauren: { id: 6, bit: 5, faction: "Horde", startArea: 215 },
  Gnome: { id: 7, bit: 6, faction: "Alliance", startArea: 1 },
  Troll: { id: 8, bit: 7, faction: "Horde", startArea: 14 },
  HighOrder: { id: 95, bit: 32, faction: "Alliance", startArea: 16593 },
  Windshaper: { id: 96, bit: 33, faction: "Horde", startArea: 16593 },
};
// Masks reach bit 33, past what JS bitwise operators keep. A negative mask is two's complement (-1 = everyone).
const hasBit = (mask, bit) => ((Math.floor(mask / 2 ** bit) % 2) + 2) % 2 === 1;

function character(race, cls) {
  const r = RACES[race];
  if (!r || !CLASSES[cls]) throw new Error(`unknown character ${race} ${cls}`);
  return { race, cls, faction: r.faction, raceBit: r.bit, classId: CLASSES[cls], startArea: r.startArea };
}
function combos(dataDir) {
  const out = [];
  for (const row of readCsv(path.join(dataDir, "wago", "CharBaseInfo.csv"))) {
    const race = Object.keys(RACES).find((k) => RACES[k].id === +row.RaceID);
    const cls = Object.keys(CLASSES).find((k) => CLASSES[k] === +row.ClassID);
    if (race && cls) out.push(character(race, cls));
  }
  return out.sort((a, b) => (a.race + a.cls).localeCompare(b.race + b.cls));
}
const eligible = (quest, ch) =>
  (!quest.races || hasBit(quest.races, ch.raceBit)) && (!quest.classes || hasBit(quest.classes, ch.classId - 1));

module.exports = { CLASSES, RACES, hasBit, character, combos, eligible };
```

- [ ] **Step 4: Run tests, expect pass.**
- [ ] **Step 5: Commit** — `git commit -am "Characters, race and class eligibility"` (after `git add -A`).

---

### Task 4: Geography (`lib/geo.js`)

**Files:**
- Create: `tools/lib/geo.js`, `tools/test/geo.test.js`

**Interfaces:**
- Consumes: `Db`.
- Produces: `zoneOf(db, areaId) -> number` (the top-level zone that has a map; follows `parent`), `toPoint(db, areaId, x, y) -> Point|null`, `distance(a: Point, b: Point) -> number` (yards; `Infinity` across continents), `spawnPoints(db, kind: "npc"|"object", id) -> Point[]`, `centroid(points: Point[]) -> Point|null`.

Map percent to world (verified: Devrak at 51.5, 30.34 in The Barrens lands within 10 yards of the Crossroads taxi node at world -441.8, -2596.1): map x runs along world Y descending, map y along world X descending.

```
wx = maxX - (y / 100) * (maxX - minX)
wy = maxY - (x / 100) * (maxY - minY)
```

- [ ] **Step 1: Write the failing tests**

```js
// tools/test/geo.test.js
// Noir Guides, GPLv3. See LICENSE.
const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const path = require("path");
const { fixtureDb } = require("./fixture");
const { zoneOf, toPoint, distance, spawnPoints, centroid } = require("../lib/geo");
const { loadDb } = require("../lib/db");
const DATA = path.join(__dirname, "..", "data");
const real = fs.existsSync(path.join(DATA, "forever_db.json"));

test("zoneOf climbs to the zone that has a map", () => {
  const db = fixtureDb();
  assert.strictEqual(zoneOf(db, 1001), 1000);
  assert.strictEqual(zoneOf(db, 1000), 1000);
  assert.strictEqual(zoneOf(db, 999999), 0);
});
test("toPoint converts percent to world and distance is in yards", () => {
  const db = fixtureDb();
  const a = toPoint(db, 1000, 50, 50), b = toPoint(db, 1000, 60, 50);
  assert.deepStrictEqual([a.wx, a.wy, a.zone], [500, 500, 1000]);
  assert.strictEqual(Math.round(distance(a, b)), 100);
  assert.strictEqual(toPoint(db, 999999, 1, 1), null);
});
test("spawnPoints uses the zone map even when the spawn is keyed by a subzone", () => {
  const db = fixtureDb();
  db.npcs.get(1).spawns = { 1001: [[50, 50]] };
  assert.strictEqual(spawnPoints(db, "npc", 1)[0].zone, 1000);
});
test("centroid averages world positions and keeps the commonest zone", () => {
  const db = fixtureDb();
  const c = centroid([toPoint(db, 1000, 40, 40), toPoint(db, 1000, 60, 60)]);
  assert.deepStrictEqual([Math.round(c.x), Math.round(c.y)], [50, 50]);
  assert.strictEqual(centroid([]), null);
});
test("real data: Devrak stands at the Crossroads taxi node", { skip: !real }, () => {
  const db = loadDb(DATA);
  const p = spawnPoints(db, "npc", 3615)[0];
  const node = db.taxi.find((t) => t.name.startsWith("Crossroads"));
  assert.ok(Math.hypot(p.wx - node.x, p.wy - node.y) < 15);
});
```

- [ ] **Step 2: Run, expect failure.**

- [ ] **Step 3: Implement**

```js
// Noir Guides, GPLv3. See LICENSE.
function zoneOf(db, areaId) {
  let id = +areaId;
  for (let i = 0; i < 6 && id; i++) {
    if (db.maps.has(id)) return id;
    const a = db.areas.get(id);
    id = a ? a.parent : 0;
  }
  return 0;
}
function toPoint(db, areaId, x, y) {
  const zone = zoneOf(db, areaId);
  const m = db.maps.get(zone);
  if (!m || x < 0 || y < 0) return null;
  const area = db.areas.get(zone);
  return { zone, x, y, wx: m.maxX - (y / 100) * (m.maxX - m.minX), wy: m.maxY - (x / 100) * (m.maxY - m.minY), continent: area ? area.continent : -1 };
}
const distance = (a, b) => (a.continent !== b.continent ? Infinity : Math.hypot(a.wx - b.wx, a.wy - b.wy));
function spawnPoints(db, kind, id) {
  const e = (kind === "npc" ? db.npcs : db.objects).get(id);
  const out = [];
  for (const [area, list] of Object.entries((e && e.spawns) || {})) for (const [x, y] of list) {
    const p = toPoint(db, +area, x, y);
    if (p) out.push(p);
  }
  return out;
}
// The middle of a set of spawns, in the zone most of them are in. Percent coordinates are recomputed from the average.
function centroid(points) {
  if (!points.length) return null;
  const count = new Map();
  for (const p of points) count.set(p.zone, (count.get(p.zone) || 0) + 1);
  const zone = [...count].sort((a, b) => b[1] - a[1] || a[0] - b[0])[0][0];
  const inZone = points.filter((p) => p.zone === zone);
  const avg = (k) => inZone.reduce((s, p) => s + p[k], 0) / inZone.length;
  return { zone, x: avg("x"), y: avg("y"), wx: avg("wx"), wy: avg("wy"), continent: inZone[0].continent };
}
module.exports = { zoneOf, toPoint, distance, spawnPoints, centroid };
```

- [ ] **Step 4: Run tests, expect pass.**
- [ ] **Step 5: Commit** — `git add -A && git commit -m "Geography: zones, world coordinates, distances"`

---

### Task 5: XP model and leveling quests (`lib/xp.js`, `lib/quests.js`)

**Files:**
- Create: `tools/lib/xp.js`, `tools/lib/quests.js`, `tools/test/quests.test.js`

**Interfaces:**
- Consumes: `Db`, `Quest`, `Character`, `eligible`, `zoneOf`, `spawnPoints`, `centroid`.
- Produces from `lib/xp.js`: `XP_TO_LEVEL: number[]` (index = level, value = XP needed to finish that level), `questXp(questLevel, playerLevel) -> number`, `objectiveXp(quest, playerLevel) -> number`.
- Produces from `lib/quests.js`: `INSTANCE_AREAS: Set<number>`, `levelingQuests(db, character) -> Quest[]`, `startPoint(db, quest) -> { point: Point, npc?: number, object?: number } | null`, `endPoint(db, quest) -> same | null`, `objectivePoint(db, quest) -> { point: Point, npc?, object?, item? } | null` (null when the quest has no objective to go to), `canAccept(quest, state: { level: number, done: Set<number>, log: Set<number> }) -> boolean`.

The XP numbers are estimates, and the code must say so: quest XP is not in the data. They exist only to pace the route; the engine will read real XP in the game.

- [ ] **Step 1: Write the failing tests**

```js
// tools/test/quests.test.js
// Noir Guides, GPLv3. See LICENSE.
const test = require("node:test");
const assert = require("node:assert");
const { fixtureDb } = require("./fixture");
const { character } = require("../lib/characters");
const { XP_TO_LEVEL, questXp } = require("../lib/xp");
const { levelingQuests, startPoint, endPoint, objectivePoint, canAccept } = require("../lib/quests");

test("xp table and estimates", () => {
  assert.strictEqual(XP_TO_LEVEL[1], 400);
  assert.strictEqual(XP_TO_LEVEL[59], 209800);
  assert.ok(questXp(10, 10) > questXp(5, 5));
  assert.strictEqual(questXp(2, 20), 0);                       // grey: more than 8 levels under the player
  assert.strictEqual(questXp(10, 14), questXp(10, 10));        // full XP up to 5 levels over the quest
  assert.ok(questXp(10, 16) < questXp(10, 10));                // lower-level quests give less
});
test("leveling quests exclude other factions, repeatables and unplaceable quests", () => {
  const db = fixtureDb();
  const ids = (ch) => levelingQuests(db, ch).map((q) => q.id).sort((a, b) => a - b);
  assert.deepStrictEqual(ids(character("Human", "WARRIOR")), [10, 11, 12, 14, 20, 21]); // no 13 (Horde), no 15 (repeatable)
  assert.deepStrictEqual(ids(character("Undead", "ROGUE")), [10, 11, 12, 13, 14, 20, 21]);
});
test("a quest giver friendly only to the other faction rules the quest out", () => {
  const db = fixtureDb();
  db.quests.get(13).races = 0;                                  // no race mask, but the giver is Horde-only
  assert.ok(!levelingQuests(db, character("Human", "WARRIOR")).some((q) => q.id === 13));
});
test("points for start, objective and end", () => {
  const db = fixtureDb();
  assert.strictEqual(startPoint(db, db.quests.get(10)).npc, 1);
  assert.strictEqual(endPoint(db, db.quests.get(12)).npc, 2);
  assert.strictEqual(objectivePoint(db, db.quests.get(10)).npc, 3);
  const tusks = objectivePoint(db, db.quests.get(11));          // item objective: go where its dropper is
  assert.deepStrictEqual([tusks.item, tusks.npc], [100, 4]);
  assert.strictEqual(objectivePoint(db, db.quests.get(21)), null); // a talk-to quest
});
test("canAccept checks level, prerequisites and the log", () => {
  const db = fixtureDb();
  const s = { level: 2, done: new Set(), log: new Set() };
  assert.strictEqual(canAccept(db.quests.get(10), s), true);
  assert.strictEqual(canAccept(db.quests.get(12), s), false);   // needs quest 10
  s.done.add(10);
  assert.strictEqual(canAccept(db.quests.get(12), s), true);
  assert.strictEqual(canAccept(db.quests.get(14), s), false);   // level 40
  assert.strictEqual(canAccept(db.quests.get(10), s), false);   // already done
});
```

- [ ] **Step 2: Run, expect failure.**

- [ ] **Step 3: Implement `lib/xp.js`**

```js
// Noir Guides, GPLv3. See LICENSE.
// XP needed to finish each level 1-59: the classic client's level table (what UnitXPMax reports).
const XP_TO_LEVEL = [0, 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900, 14400, 16000, 17700, 19400,
  21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400, 50800, 54500, 58600, 62800, 67100, 71600,
  76100, 80800, 85700, 90700, 95800, 101000, 106300, 111800, 117500, 123200, 129100, 135100, 141200, 147500, 153900, 160400,
  167100, 173900, 180800, 187900, 195000, 202300, 209800];
// ESTIMATES. Quest XP is not in the data. These only pace the route (which zone comes when); the engine reads real XP
// in the game. A quest is worth roughly a fixed share of its own level, less when it is below the player, nothing when grey.
function questXp(questLevel, playerLevel) {
  const diff = playerLevel - questLevel;
  if (diff > 8) return 0;
  const base = questLevel <= 10 ? 60 * questLevel + 50 : 110 * questLevel - 500;
  const scale = diff <= 5 ? 1 : diff === 6 ? 0.8 : diff === 7 ? 0.6 : 0.4;
  return Math.round(base * scale);
}
// Killing and gathering for an objective: about 8 kills of a same-level mob per kill or item objective.
function objectiveXp(quest, playerLevel) {
  const n = quest.objectives.npcs.length + quest.objectives.items.length;
  if (playerLevel - quest.level > 8) return 0;
  return n * 8 * (45 + 5 * quest.level);
}
module.exports = { XP_TO_LEVEL, questXp, objectiveXp };
```

- [ ] **Step 4: Implement `lib/quests.js`**

```js
// Noir Guides, GPLv3. See LICENSE.
const { eligible } = require("./characters");
const { zoneOf, spawnPoints, centroid } = require("./geo");

// AreaTable IDs of the classic dungeons and raids (names checked in AreaTable.csv): Ragefire Chasm, Deadmines, Wailing
// Caverns, Shadowfang Keep, Blackfathom Deeps, Stockade, Gnomeregan, Razorfen Kraul, Scarlet Monastery, Razorfen Downs,
// Uldaman, Maraudon, Zul'Farrak, Sunken Temple, Blackrock Depths, Blackrock Spire, Dire Maul, Scholomance, Stratholme,
// Molten Core, Blackwing Lair, Onyxia's Lair, Zul'Gurub, Ruins of Ahn'Qiraj, Ahn'Qiraj, Naxxramas.
const INSTANCE_AREAS = new Set([2437, 1581, 718, 209, 719, 717, 721, 491, 796, 722, 1337, 2100, 1176, 1477, 1584, 1583, 2557, 2057,
  2017, 2717, 2677, 2159, 1977, 3429, 3428, 3456]);
const ZEPHRAS_ISLE = 16593; // the Skyborne starting zone (name checked in AreaTable.csv); its quests are Forever-only and still needed

const friendlyTo = (npc, faction) => !npc.friendly || npc.friendly.includes(faction[0]);
// the first giver or ender of a kind that has a known position and is usable by this faction (faction null = any)
function place(db, npcs, objects, faction) {
  for (const id of npcs) {
    const n = db.npcs.get(id);
    if (!n || (faction && !friendlyTo(n, faction))) continue;
    const c = centroid(spawnPoints(db, "npc", id));
    if (c) return { point: c, npc: id };
  }
  for (const id of objects) {
    const c = centroid(spawnPoints(db, "object", id));
    if (c) return { point: c, object: id };
  }
  return null;
}
const startPoint = (db, q, faction) => place(db, q.starts.npcs, q.starts.objects, faction || null);
const endPoint = (db, q, faction) => place(db, q.ends.npcs, q.ends.objects, faction || null);

// Where to go for the quest's work: its first creature, object, item source or explore point. null = nothing to do
// between accept and turn-in (a delivery or talk-to quest).
function objectivePoint(db, q) {
  for (const id of q.objectives.npcs) { const c = centroid(spawnPoints(db, "npc", id)); if (c) return { point: c, npc: id }; }
  for (const id of q.objectives.objects) { const c = centroid(spawnPoints(db, "object", id)); if (c) return { point: c, object: id }; }
  for (const id of q.objectives.items) {
    const item = db.items.get(id);
    for (const n of (item && item.npcDrops) || []) { const c = centroid(spawnPoints(db, "npc", n)); if (c) return { point: c, item: id, npc: n }; }
    for (const o of (item && item.objectDrops) || []) { const c = centroid(spawnPoints(db, "object", o)); if (c) return { point: c, item: id, object: o }; }
  }
  if (q.trigger) for (const [area, list] of Object.entries(q.trigger.spawns)) {
    const { toPoint } = require("./geo");
    const p = list[0] && toPoint(db, +area, list[0][0], list[0][1]);
    if (p) return { point: p };
  }
  return null;
}
// true when the quest has objectives but none can be placed on the map: the route could not say where to go
function unplaceable(db, q) {
  const has = q.objectives.npcs.length + q.objectives.objects.length + q.objectives.items.length > 0 || q.trigger;
  return has && !objectivePoint(db, q);
}

// The quests a route may use for this character: takeable by race, class and faction; ordinary one-time world quests;
// classic quests (or the Skyborne start); with a giver and a turn-in we can point at.
function levelingQuests(db, ch) {
  const out = [];
  for (const q of db.quests.values()) {
    if (!eligible(q, ch) || q.repeatable || q.gated || q.classes) continue;
    if (q.sort < 0 || !q.zone || INSTANCE_AREAS.has(zoneOf(db, q.zone)) || INSTANCE_AREAS.has(q.zone)) continue;
    if (!db.eraQuestIds.has(q.id) && zoneOf(db, q.zone) !== ZEPHRAS_ISLE) continue;
    if (q.starts.items.length && !q.starts.npcs.length && !q.starts.objects.length) continue; // started by a drop
    if (!startPoint(db, q, ch.faction) || !endPoint(db, q, ch.faction) || unplaceable(db, q)) continue;
    out.push(q);
  }
  return out.sort((a, b) => a.id - b.id);
}
function canAccept(q, state) {
  if (state.done.has(q.id) || state.log.has(q.id) || state.level < q.minLevel) return false;
  if (q.preAny.length && !q.preAny.some((p) => state.done.has(p))) return false;
  if (q.preAll.some((p) => !state.done.has(p))) return false;
  if (q.exclusive.some((p) => state.done.has(p) || state.log.has(p))) return false;
  return true;
}
module.exports = { INSTANCE_AREAS, levelingQuests, startPoint, endPoint, objectivePoint, canAccept };
```

Move the `require("./geo")` for `toPoint` to the top import line; it is written inline above only to keep the snippet short.

- [ ] **Step 5: Run tests, expect pass.**
- [ ] **Step 6: Commit** — `git add -A && git commit -m "XP estimates, leveling quest filter, quest places"`

---

### Task 6: The planner (`planner/zones.js`, `planner/plan.js`)

**Files:**
- Create: `tools/planner/zones.js`, `tools/planner/plan.js`, `tools/test/plan.test.js`

**Interfaces:**
- Consumes: everything from Tasks 2-5.
- Produces: `zoneBands(db, quests: Quest[]) -> { zone, name, min, max, count }[]` (one per top-level zone, `min`/`max` = 20th and 80th percentile of the zone's quest `minLevel`, sorted by `min` then zone ID) from `planner/zones.js`; `planRoute(db, character, options?: { maxLevel?: number }) -> Route` from `planner/plan.js`.

How the planner works. It keeps a state `{ level, xp, pos: Point, zone, log: Map<questId, { needsObjective: boolean }>, done: Set, steps: Step[], distance }` and repeats:

1. **Tasks here.** In the current zone, list every possible next action: accept a quest the character can accept (`canAccept`, quest level not grey, log under 20, the quest's start point in this zone); do an objective for a quest in the log (its objective point, any zone on this continent within 1,500 yards of the current zone's tasks, or in this zone); turn in a quest in the log whose objective is done or absent.
2. **Pick the nearest** by `distance(pos, task.point)`; ties go to turn-in, then objective, then accept, then the lower quest ID. Append its step, move `pos`, add the distance, apply its effect (log, done, XP via `questXp` on turn-in and `objectiveXp` when an objective is done, level-ups by `XP_TO_LEVEL`).
3. **Nothing to do here.** If any log quest's objective or turn-in is in another zone, travel to the nearest such zone. Otherwise pick the zone with the most acceptable quests at the current level (ties: nearer zone band `min`, then lower zone ID) and append a `travel` step. If no zone has any, but some zone has quests acceptable within 2 levels, append a `grind` step to that level in the current zone (set level, no distance). If nothing remains at all, stop.
4. Stop when `level >= maxLevel` (default 60).

The first zone is the top-level zone of the character's `startArea`; the starting position is the start point of the lowest-`minLevel`, lowest-ID quest in that zone.

- [ ] **Step 1: Write the failing tests**

```js
// tools/test/plan.test.js
// Noir Guides, GPLv3. See LICENSE.
const test = require("node:test");
const assert = require("node:assert");
const { fixtureDb } = require("./fixture");
const { character, RACES } = require("../lib/characters");
const { levelingQuests } = require("../lib/quests");
const { zoneBands } = require("../planner/zones");
const { planRoute } = require("../planner/plan");

const human = () => { RACES.Human.startArea = 1000; return character("Human", "WARRIOR"); };

test("zone bands come from quest levels", () => {
  const db = fixtureDb();
  const bands = zoneBands(db, levelingQuests(db, human()));
  assert.deepStrictEqual(bands.map((b) => b.zone), [1000, 2000]);
  assert.strictEqual(bands[0].name, "Testvale");
  assert.ok(bands[1].min >= 4);
});
test("a route accepts before it does objectives and turns in after", () => {
  const db = fixtureDb();
  const route = planRoute(db, human(), { maxLevel: 10 });
  const at = (action, quest) => route.steps.findIndex((s) => s.action === action && s.quest === quest);
  for (const q of [10, 11, 12, 20]) {
    assert.ok(at("accept", q) >= 0, `accepts ${q}`);
    assert.ok(at("accept", q) < at("objective", q), `objective after accept for ${q}`);
    assert.ok(at("objective", q) < at("turnin", q), `turn-in after objective for ${q}`);
  }
  assert.ok(at("turnin", 10) < at("accept", 12), "a follow-up waits for its prerequisite");
  assert.ok(at("accept", 21) > at("turnin", 20));
  assert.strictEqual(at("accept", 13), -1, "never the other faction's quest");
  assert.strictEqual(at("accept", 14), -1, "never a quest far above the level cap");
});
test("it travels between zones and records it", () => {
  const db = fixtureDb();
  const route = planRoute(db, human(), { maxLevel: 10 });
  const travel = route.steps.findIndex((s) => s.action === "travel" && s.zone === 2000);
  assert.ok(travel > 0);
  assert.ok(travel < route.steps.findIndex((s) => s.action === "accept" && s.quest === 20));
  assert.ok(route.stats.distance > 0);
  assert.strictEqual(route.id, "alliance-human");
});
test("planning is deterministic", () => {
  const a = JSON.stringify(planRoute(fixtureDb(), human(), { maxLevel: 10 }));
  const b = JSON.stringify(planRoute(fixtureDb(), human(), { maxLevel: 10 }));
  assert.strictEqual(a, b);
});
test("every step with a place carries percent coordinates in its zone", () => {
  const route = planRoute(fixtureDb(), human(), { maxLevel: 10 });
  for (const s of route.steps) if (s.at) {
    assert.ok(s.at.zone === 1000 || s.at.zone === 2000);
    assert.ok(s.at.x >= 0 && s.at.x <= 100 && s.at.y >= 0 && s.at.y <= 100);
  }
});
```

Note: the fixture's quest 20 needs level 4 and the fixture gives little XP, so the planner must reach it through a `grind` step; the tests above pass either way and do not assert the grind.

- [ ] **Step 2: Run, expect failure.**

- [ ] **Step 3: Implement `planner/zones.js`**

```js
// Noir Guides, GPLv3. See LICENSE.
const { zoneOf } = require("../lib/geo");
function zoneBands(db, quests) {
  const byZone = new Map();
  for (const q of quests) {
    const z = zoneOf(db, q.zone);
    if (!z) continue;
    if (!byZone.has(z)) byZone.set(z, []);
    byZone.get(z).push(q.minLevel);
  }
  const out = [];
  for (const [zone, levels] of byZone) {
    levels.sort((a, b) => a - b);
    const pick = (f) => levels[Math.min(levels.length - 1, Math.floor(f * levels.length))];
    out.push({ zone, name: (db.areas.get(zone) || {}).name || String(zone), min: pick(0.2), max: pick(0.8), count: levels.length });
  }
  return out.sort((a, b) => a.min - b.min || a.zone - b.zone);
}
module.exports = { zoneBands };
```

- [ ] **Step 4: Implement `planner/plan.js`** following the four numbered rules above exactly. Required structure:

```js
// Noir Guides, GPLv3. See LICENSE.
const { zoneOf, distance } = require("../lib/geo");
const { XP_TO_LEVEL, questXp, objectiveXp } = require("../lib/xp");
const { levelingQuests, startPoint, endPoint, objectivePoint, canAccept } = require("../lib/quests");
const { zoneBands } = require("./zones");

const LOG_LIMIT = 20;          // the classic quest log holds 20 quests
const GREY = 8;                // a quest more than 8 levels under the player gives no XP
const ORDER = { turnin: 0, objective: 1, accept: 2 };

function planRoute(db, ch, options = {}) {
  const maxLevel = options.maxLevel || 60;
  const quests = levelingQuests(db, ch);
  const bands = zoneBands(db, quests);
  // precompute each quest's three places once
  const info = new Map(quests.map((q) => [q.id, { q, start: startPoint(db, q, ch.faction), end: endPoint(db, q, ch.faction), obj: objectivePoint(db, q) }]));
  const state = { level: 1, xp: 0, pos: null, zone: zoneOf(db, ch.startArea), log: new Map(), done: new Set(), steps: [], distance: 0, levelAt: [0, 0] };
  // ... starting position, the main loop (rules 1-4), helpers gain(xp), move(point), tasksIn(zone), nextZone()
  return { id: `${ch.faction.toLowerCase()}-${ch.race.toLowerCase()}`, race: ch.race, faction: ch.faction, steps: state.steps,
    stats: { quests: state.done.size, distance: Math.round(state.distance), endLevel: state.level, levelAt: state.levelAt } };
}
module.exports = { planRoute };
```

Details that must hold:
- `gain(xp)`: add to `state.xp`; while `state.level < 60 && state.xp >= XP_TO_LEVEL[state.level]`, subtract, increment the level and set `state.levelAt[state.level] = state.steps.length`.
- Step shapes: accept `{ action: "accept", quest, at: { zone, x, y }, npc | object }`; objective `{ action: "objective", quest, at, npc | object, item? }`; turn-in `{ action: "turnin", quest, at, npc | object }`; travel `{ action: "travel", zone }` (set `state.pos` to the nearest task point in the new zone, or keep the position if there is none, and add the distance when finite); grind `{ action: "grind", level, zone }`.
- Round `x` and `y` to 2 decimals in steps.
- An accept is skipped while `state.level - q.level > GREY`.
- Guard the main loop with a hard cap of 200,000 iterations and throw `new Error("planner did not finish for " + route id)` if hit.
- A travel step is never appended twice in a row to the same zone; if rule 3 picks the current zone and nothing is doable, fall through to grind or stop.

- [ ] **Step 5: Run tests, expect pass.** Then run the planner on real data for one race and print the stats:

```bash
node -e 'const {loadDb}=require("./lib/db");const {character}=require("./lib/characters");const {planRoute}=require("./planner/plan");const r=planRoute(loadDb("data"),character("Undead","ROGUE"));console.log(r.stats, r.steps.length, r.steps.slice(0,8))'
```

Expected: no exception; the first steps are accepts and objectives in Tirisfal Glades (zone 85); `endLevel` is reported. Put the printed stats in the task report. A low `endLevel` is information for Task 8, not a failure of this task.

- [ ] **Step 6: Commit** — `git add -A && git commit -m "Route planner: nearest-task ordering, zone travel, level pacing"`

---

### Task 7: The validator (`planner/validate.js`)

**Files:**
- Create: `tools/planner/validate.js`, `tools/test/validate.test.js`

**Interfaces:**
- Consumes: `Db`, `Route`, `Step`, `Character`, `eligible`, `XP_TO_LEVEL`, `questXp`, `objectiveXp`. It must NOT import `planner/plan.js` or `lib/quests.js`'s `canAccept`: it re-checks the rules from the data on its own, so a planner bug cannot hide behind shared code.
- Produces: `validateRoute(db, route, character) -> { errors: string[], warnings: string[], endLevel: number }`.

Errors (each message starts with `step N:`):
1. accept of a quest the character cannot take by race or class;
2. accept below the quest's `minLevel` at that point of the replay;
3. accept with a prerequisite not turned in (`preAny`: none done; `preAll`: any missing) or with an `exclusive` quest done or in the log;
4. accept of a quest already in the log or done; accept that would make the log exceed 20;
5. objective or turn-in for a quest not in the log;
6. turn-in before its objective step when the quest has an objective step anywhere in the route;
7. a step whose `at.zone` is not a zone with a map, or whose `x`/`y` are outside 0-100;
8. an accept, objective or turn-in whose `at.zone` differs from the zone the replay is in (the zone changes only on `travel` steps and starts at the character's start zone) and is on a different continent.

Warnings: quests still in the log at the end (`route ends with N quests in the log: ids`); `endLevel` below 60 (`route ends at level N`).

- [ ] **Step 1: Write the failing tests**

```js
// tools/test/validate.test.js
// Noir Guides, GPLv3. See LICENSE.
const test = require("node:test");
const assert = require("node:assert");
const { fixtureDb } = require("./fixture");
const { character, RACES } = require("../lib/characters");
const { validateRoute } = require("../planner/validate");

RACES.Human.startArea = 1000;
const human = character("Human", "WARRIOR");
const at = { zone: 1000, x: 50, y: 50 };
const route = (steps) => ({ id: "t", race: "Human", faction: "Alliance", steps, stats: {} });

test("a correct route has no errors", () => {
  const r = route([{ action: "accept", quest: 10, at, npc: 1 }, { action: "objective", quest: 10, at, npc: 3 }, { action: "turnin", quest: 10, at, npc: 1 }]);
  assert.deepStrictEqual(validateRoute(fixtureDb(), r, human).errors, []);
});
test("catches a quest of the other faction", () => {
  const e = validateRoute(fixtureDb(), route([{ action: "accept", quest: 13, at, npc: 7 }]), human).errors;
  assert.match(e[0], /^step 1: .*race/);
});
test("catches an accept below the required level", () => {
  const e = validateRoute(fixtureDb(), route([{ action: "accept", quest: 14, at, npc: 1 }]), human).errors;
  assert.match(e[0], /^step 1: .*level 40/);
});
test("catches a missing prerequisite", () => {
  const e = validateRoute(fixtureDb(), route([{ action: "accept", quest: 12, at, npc: 1 }]), human).errors;
  assert.match(e[0], /^step 1: .*prerequisite/);
});
test("catches a turn-in for a quest never accepted, and a turn-in before its objective", () => {
  const db = fixtureDb();
  assert.match(validateRoute(db, route([{ action: "turnin", quest: 10, at, npc: 1 }]), human).errors[0], /not in the log/);
  const r = route([{ action: "accept", quest: 10, at, npc: 1 }, { action: "turnin", quest: 10, at, npc: 1 }, { action: "objective", quest: 10, at, npc: 3 }]);
  assert.ok(validateRoute(db, r, human).errors.some((m) => /before its objective/.test(m)));
});
test("catches bad coordinates and an unannounced zone change", () => {
  const db = fixtureDb();
  assert.ok(validateRoute(db, route([{ action: "accept", quest: 10, at: { zone: 1000, x: 150, y: 5 }, npc: 1 }]), human).errors.some((m) => /coordinates/.test(m)));
});
test("warns about quests left in the log and a low end level", () => {
  const w = validateRoute(fixtureDb(), route([{ action: "accept", quest: 10, at, npc: 1 }]), human).warnings;
  assert.ok(w.some((m) => /1 quests? in the log/.test(m)));
  assert.ok(w.some((m) => /ends at level/.test(m)));
});
```

- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement `planner/validate.js`** as one replay loop over `route.steps` with its own state `{ level, xp, zone, log: Set, done: Set, objectiveDone: Set }`, pushing a message for each rule above. XP and level-ups follow the same arithmetic as the planner (`questXp` on turn-in, `objectiveXp` on objective, `XP_TO_LEVEL`); a `grind` step sets the level to `step.level` when higher. Rule 6 needs one pass first to collect which quests have an objective step.
- [ ] **Step 4: Run tests, expect pass.**
- [ ] **Step 5: Commit** — `git add -A && git commit -m "Route validator: independent replay of every rule"`

---

### Task 8: Emit, report, build all routes

**Files:**
- Create: `tools/planner/emit.js`, `tools/planner/report.js`, `tools/build_routes.js`, `tools/test/emit.test.js`
- Generated and committed: `NoirGuides/Routes/*.lua` (10 files), `docs/routes/REPORT.md`

**Interfaces:**
- Consumes: `planRoute`, `validateRoute`, `combos`, `loadDb`, `Route`.
- Produces: `emitLua(route) -> string`; `reportMarkdown(db, results: { route, validations: { character, result }[] }[]) -> string`; the CLI `node build_routes.js [--race Undead]`.

Lua format (one step per line, keys in this fixed order: `action, quest, zone, level, at, npc, object, item`; `do` is a Lua keyword, which is why the key is `action`):

```lua
-- Noir Guides, GPLv3. See LICENSE. Generated by tools/build_routes.js from QuestieDB Forever v1.0.14. Do not edit.
Noir.Route("horde-undead", {
  race = "Undead", faction = "Horde",
  steps = {
    { action = "accept", quest = 363, at = { zone = 85, x = 30.21, y = 71.65 }, npc = 1568 },
    { action = "travel", zone = 130 },
    { action = "grind", zone = 85, level = 6 },
  },
})
```

- [ ] **Step 1: Write the failing test**

```js
// tools/test/emit.test.js
// Noir Guides, GPLv3. See LICENSE.
const test = require("node:test");
const assert = require("node:assert");
const { emitLua } = require("../planner/emit");

test("emits one step per line in a fixed key order", () => {
  const lua = emitLua({ id: "horde-undead", race: "Undead", faction: "Horde", stats: {}, steps: [
    { npc: 1568, at: { zone: 85, x: 30.21, y: 71.65 }, quest: 363, action: "accept" },
    { action: "travel", zone: 130 },
    { action: "grind", level: 6, zone: 85 },
  ] });
  assert.ok(lua.includes('Noir.Route("horde-undead", {'));
  assert.ok(lua.includes('    { action = "accept", quest = 363, at = { zone = 85, x = 30.21, y = 71.65 }, npc = 1568 },'));
  assert.ok(lua.includes('    { action = "travel", zone = 130 },'));
  assert.ok(lua.includes('    { action = "grind", zone = 85, level = 6 },'));
  assert.ok(lua.trimEnd().endsWith("})"));
  assert.ok(!/\bdo\s*=/.test(lua));
});
```

- [ ] **Step 2: Run, expect failure. Step 3: Implement `emit.js`** (header line takes the QuestieDB release from `tools/data_sources.json`). **Step 4: Run, expect pass.**

- [ ] **Step 5: Implement `report.js`.** For each race: a heading, then a table row per fact: steps, quests, end level, travel distance in yards, grind steps (count and the levels), zones in order (names), errors (count), warnings (text). Then a section "Level curve" listing the step index at which levels 10, 20, 30, 40, 50 and 60 are reached, or "not reached".

- [ ] **Step 6: Implement `build_routes.js`.** For each race (or the one given by `--race`): take every class of that race from `combos`; plan once with the race's first class (class does not change a route in this plan, because class quests are excluded); validate against every class of the race; write `NoirGuides/Routes/<route id>.lua` and collect results. After each race, write `tools/data/build_status.json` as `{ "phase": "Routes", "total": <races>, "done": <n>, "current": [<race being planned>], "started": <ms> }` (this one file may use `Date.now()`; route files may not). At the end write `docs/routes/REPORT.md`, print one line per race (`Undead: 3,412 steps, 890 quests, level 58, 0 errors`), and exit 1 if any validation has errors.

- [ ] **Step 7: Run `npm run routes`.** Expected: 10 route files, 0 errors. If the validator reports errors, they are planner bugs: fix `planner/plan.js` (add a unit test reproducing each one in `test/plan.test.js` first), never weaken the validator. End levels below 60 and grind steps are reported, not hidden.

- [ ] **Step 8: Run `npm test`**, expect all pass. Run `npm run routes` a second time and confirm `git status` shows no change in `NoirGuides/Routes/` (determinism).

- [ ] **Step 9: Commit** — `git add -A && git commit -m "Emit Lua routes, build and report for all races"`

---

## Self-Review Notes

- Spec coverage for this plan's scope: data sources and license (Task 1), route planner input, model, method, pace, output and determinism (Tasks 5, 6, 8), guide format as Lua data with one action per step (Task 8), simulator-style checks that fail the build (Task 7). The engine, the in-game simulator, flights, class and profession layers and ports are later plans, as the header says.
- The validator shares only data helpers and the XP arithmetic with the planner, by design.
- Known honest limits written into the code and report: XP is estimated; travel between zones is a plain "travel" step; Skyborne starting routes depend on how complete Zephras Isle is in QuestieDB.
