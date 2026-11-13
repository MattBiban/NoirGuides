// Noir Guides, GPLv3. See LICENSE.
const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { normalizeQuest, loadDb, VENDOR_FLAG } = require("../lib/db");
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

// Dun Morogh is area 1, so its Lua table {[1] = ...} is exported to JSON as an array. Without this, every Dun Morogh
// position was dropped and the Dwarf and Gnome routes left their starting zone at step 1.
test("area-keyed tables exported as arrays keep their 1-based area IDs", () => {
  const { areaMap } = require("../lib/db");
  assert.deepStrictEqual(areaMap([[[29.93, 71.2]]]), { 1: [[29.93, 71.2]] });
  assert.deepStrictEqual(areaMap({ 85: [[1, 2]] }), { 85: [[1, 2]] });
  assert.deepStrictEqual(areaMap(undefined), {});
  const q = normalizeQuest(1, { triggerEnd: ["Explore", [[[10, 20]]]] });
  assert.deepStrictEqual(q.trigger.spawns, { 1: [[10, 20]] });
});
test("real data: a Dun Morogh quest giver has a Dun Morogh position", { skip: !real }, () => {
  const db = loadDb(DATA);
  assert.deepStrictEqual(Object.keys(db.npcs.get(658).spawns), ["1"]);
});
test("real data: NPCs keep their sub name, which names class and profession trainers", { skip: !real }, () => {
  const db = loadDb(DATA);
  assert.strictEqual(db.npcs.get(911).subName, "Warrior Trainer");
  assert.strictEqual(db.npcs.get(658).subName, "");
});
test("real data: merchants are told by the vendor bit of their NPC flags", { skip: !real }, () => {
  const db = loadDb(DATA);
  assert.strictEqual(VENDOR_FLAG, 4);
  assert.strictEqual(db.npcs.get(66).vendor, true, "Tharynn Bouden, Trade Supplies (flags 4)");
  assert.strictEqual(db.npcs.get(54).vendor, true, "Corina Steele, Weaponsmith (flags 16388: vendor and repair)");
  assert.strictEqual(db.npcs.get(5688).vendor, true, "Innkeeper Renee (flags 135)");
  assert.strictEqual(db.npcs.get(911).vendor, false, "Llane Beshere, Warrior Trainer (flags 19)");
  assert.strictEqual(db.npcs.get(658).vendor, false, "a quest giver (flags 3)");
});

test("reads the conditions that take a quest away again", () => {
  const q = normalizeQuest(1, { requiredMaxLevel: 30, disabledByQuest: 420, availableUntilCompleted: 5, availableStartingWith: 6 });
  assert.deepStrictEqual([q.maxLevel, q.disabledBy, q.availableUntil, q.availableAfter], [30, 420, 5, 6]);
  const plain = normalizeQuest(2, {});
  assert.deepStrictEqual([plain.maxLevel, plain.disabledBy, plain.availableUntil, plain.availableAfter], [0, 0, 0, 0]);
});

// A data folder with just enough in it for loadDb, written to a temporary place.
function tinyData(assignmentRows) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "noir-db-"));
  fs.mkdirSync(path.join(dir, "wago"));
  const empty = JSON.stringify({ Quest: {}, Npc: {}, Object: {}, Item: {} });
  fs.writeFileSync(path.join(dir, "forever_db.json"), empty);
  fs.writeFileSync(path.join(dir, "vanilla_db.json"), empty);
  const csv = (name, header, rows) => fs.writeFileSync(path.join(dir, "wago", name + ".csv"), [header, ...rows].join("\n") + "\n");
  csv("AreaTable", "ID,AreaName_lang,ParentAreaID,ContinentID", ["7,Testvale,0,0"]);
  csv("UiMapAssignment", "UiMin_0,UiMin_1,UiMax_0,UiMax_1,Region_0,Region_1,Region_3,Region_4,UiMapID,OrderIndex,AreaID", assignmentRows);
  csv("TaxiNodes", "ID,Name_lang,Pos_0,Pos_1,ContinentID", []);
  return dir;
}
test("of several full-map rows for an area, the one with the lowest OrderIndex gives the map", () => {
  const dir = tinyData([
    "0,0,1,1,500,500,600,600,92,2,7",       // a later layer of the same area, listed first
    "0,0,0.5,0.5,0,0,50,50,93,0,7",         // not a full map: only a corner of some other map
    "0,0,1,1,100,200,300,400,90,1,7",
    "0,0,1,1,-10,-20,30,40,91,0,7",         // the lowest OrderIndex: this is the zone's own map
    "0,0,1,1,1,1,2,2,94,0,0",               // no area: a continent row
    "0,0,1,1,700,700,800,800,95,0,7",       // the same OrderIndex again: the first one read stays
  ]);
  try {
    const db = loadDb(dir);
    assert.deepStrictEqual(db.maps.get(7), { area: 7, uiMap: 91, minX: -10, minY: -20, maxX: 30, maxY: 40 });
    assert.strictEqual(db.maps.size, 1);
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});
test("real data: every zone map is its area's full-map row with the lowest OrderIndex", { skip: !real }, () => {
  const { readCsv } = require("../lib/csv");
  const db = loadDb(DATA);
  const lowest = new Map();
  for (const m of readCsv(path.join(DATA, "wago", "UiMapAssignment.csv"))) {
    if (+m.AreaID === 0 || +m.UiMin_0 !== 0 || +m.UiMin_1 !== 0 || +m.UiMax_0 !== 1 || +m.UiMax_1 !== 1) continue;
    if (!lowest.has(+m.AreaID) || +m.OrderIndex < lowest.get(+m.AreaID).order) lowest.set(+m.AreaID, { order: +m.OrderIndex, uiMap: +m.UiMapID });
  }
  assert.strictEqual(db.maps.size, lowest.size);
  for (const [area, row] of lowest) assert.strictEqual(db.maps.get(area).uiMap, row.uiMap, `area ${area}`);
  assert.strictEqual(db.maps.get(16593).uiMap, 2521); // Zephras Isle
  for (const m of db.maps.values()) assert.strictEqual(m.order, undefined, "the OrderIndex is not kept on the map");
});
test("real data: items say when they can be had without a drop", { skip: !real }, () => {
  const db = loadDb(DATA);
  assert.strictEqual(db.items.get(2320).otherSources, true);   // Coarse Thread: sold by vendors
  assert.strictEqual(db.items.get(5876).otherSources, false);  // Blueleaf Tuber: only dug up in Razorfen Kraul
});
