// Noir Guides, GPLv3. See LICENSE.
const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const path = require("path");
const { fixtureDb } = require("./fixture");
const { normalizeQuest, loadDb } = require("../lib/db");
const { character, RACES, SKYBORNE_CONTINENT } = require("../lib/characters");
const { XP_TO_LEVEL, questXp } = require("../lib/xp");
const { levelingQuests, startPoint, endPoint, objectivePoint, canAccept, instanced } = require("../lib/quests");

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
test("an objective with several sources is done at the one nearest the quest giver", () => {
  const db = fixtureDb();
  const herd = (x, y) => [[x, y], [x + 1, y], [x, y + 1], [x + 1, y + 1], [x + 2, y], [x, y + 2], [x + 2, y + 2], [x + 1, y + 2]]; // 8 spawns
  // Boar Tusk also drops from a far herd that the data lists first
  db.npcs.set(8, { id: 8, name: "Far Boar", friendly: "", spawns: { 2000: herd(50, 50) } });
  db.npcs.get(4).spawns = { 1000: herd(40, 40) };
  db.items.get(100).npcDrops = [8, 6, 4];
  const tusks = objectivePoint(db, db.quests.get(11));
  assert.deepStrictEqual([tusks.item, tusks.npc, tusks.point.zone], [100, 4, 1000]);
  // one named boar right beside the giver is no place to collect tusks while a herd is in reach
  db.npcs.set(9, { id: 9, name: "Old Tusker", friendly: "", spawns: { 1000: [[52, 51]] } });
  db.items.get(100).npcDrops = [9, 8, 6, 4];
  assert.strictEqual(objectivePoint(db, db.quests.get(11)).npc, 4);
  // but when it is the only source, that is where to go
  db.items.get(100).npcDrops = [9];
  assert.strictEqual(objectivePoint(db, db.quests.get(11)).npc, 9);
  // a creature found in two zones: the spawns in the giver's zone are the place
  db.npcs.get(3).spawns = { 2000: herd(10, 10), 1000: herd(60, 60) };
  const wolves = objectivePoint(db, db.quests.get(10));
  assert.deepStrictEqual([wolves.npc, wolves.point.zone, Math.round(wolves.point.x), Math.round(wolves.point.y)], [3, 1000, 61, 61]);
  // the first objective that can be placed still decides which objective it is
  db.quests.get(10).objectives.npcs = [999, 3, 4];
  assert.strictEqual(objectivePoint(db, db.quests.get(10)).npc, 3);
  // a quest handed out in the far zone sends the player to the far boars
  db.items.get(100).npcDrops = [4, 8];
  db.quests.get(20).objectives = { npcs: [], objects: [], items: [100] };
  assert.strictEqual(objectivePoint(db, db.quests.get(20)).npc, 8);
  // nothing to measure from: the first source in the data, as before
  db.quests.get(20).starts.npcs = []; db.quests.get(20).ends.npcs = [];
  assert.strictEqual(objectivePoint(db, db.quests.get(20)).npc, 4);
});
test("real data: a Zephras Isle quest for a common drop is done on the isle", { skip: !fs.existsSync(path.join(__dirname, "..", "data", "forever_db.json")) }, () => {
  const db = loadDb(path.join(__dirname, "..", "data"));
  // Restocking the Larders wants Small Eggs, which also drop in Westfall, Teldrassil and Mulgore (listed first in the data)
  const eggs = objectivePoint(db, db.quests.get(92553), "Horde");
  assert.deepStrictEqual([eggs.item, eggs.point.zone], [6889, 16593]);
  for (const q of db.quests.values()) {
    if (q.zone !== 16593) continue;
    const start = startPoint(db, q), objective = objectivePoint(db, q);
    if (start && objective && start.point.zone === 16593) assert.strictEqual(objective.point.zone, 16593, `quest ${q.id} is done on the isle`);
  }
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
test("canAccept honours the conditions that take a quest away again", () => {
  const state = (over) => ({ level: 10, done: new Set(), log: new Set(), ...over });
  const quest = (raw) => normalizeQuest(900, { name: "x", requiredLevel: 1, ...raw });
  const capped = quest({ requiredMaxLevel: 10 });
  assert.strictEqual(canAccept(capped, state()), true);
  assert.strictEqual(canAccept(capped, state({ level: 11 })), false);            // too high a level
  const disabled = quest({ disabledByQuest: 420 });
  assert.strictEqual(canAccept(disabled, state()), true);
  assert.strictEqual(canAccept(disabled, state({ log: new Set([420]) })), false); // off while the other quest is in the log
  assert.strictEqual(canAccept(disabled, state({ done: new Set([420]) })), true);
  const until = quest({ availableUntilCompleted: 5 });
  assert.strictEqual(canAccept(until, state({ log: new Set([5]) })), true);
  assert.strictEqual(canAccept(until, state({ done: new Set([5]) })), false);     // gone once the other quest is turned in
  const after = quest({ availableStartingWith: 6 });
  assert.strictEqual(canAccept(after, state()), false);                           // not before the other quest is taken
  assert.strictEqual(canAccept(after, state({ log: new Set([6]) })), true);
  assert.strictEqual(canAccept(after, state({ done: new Set([6]) })), true);
});

// An instance in the fixture: area 4000 on its own map (a dungeon), and area 4100 that the hand-written list names.
function instanceDb() {
  const db = fixtureDb();
  db.areas.set(4000, { id: 4000, name: "Test Depths", parent: 0, continent: 777 });
  db.areas.set(4500, { id: 4500, name: "Test Battleground", parent: 0, continent: 778 });
  db.maps.set(4500, { area: 4500, uiMap: 9, minX: 0, minY: 9000, maxX: 1000, maxY: 10000 });
  db.npcs.set(40, { id: 40, name: "Depths Boss", friendly: "", spawns: { 4000: [[-1, -1]] } });
  db.npcs.set(41, { id: 41, name: "Boss With a Double Outside", friendly: "", spawns: { 4000: [[-1, -1]], 1000: [[70, 70]] } });
  db.npcs.set(42, { id: 42, name: "Cave Dweller", friendly: "", spawns: { 10073: [[44, 86]] } }); // an area the client tables do not have
  db.npcs.set(43, { id: 43, name: "Battlemaster", friendly: "AH", spawns: { 4500: [[50, 50]] } });
  db.items.set(101, { id: 101, name: "Depths Root", npcDrops: [40], objectDrops: [] });
  db.items.set(102, { id: 102, name: "Thread", npcDrops: [40], objectDrops: [], otherSources: true });
  const quest = (id, raw) => { db.quests.set(id, normalizeQuest(id, { name: "q" + id, startedBy: [[1]], finishedBy: [[1]], requiredLevel: 1, questLevel: 2, zoneOrSort: 1000, ...raw })); db.eraQuestIds.add(id); };
  quest(30, { objectives: [[[3, null, 0], [40, null, 0]]] });      // a wolf outside and the boss inside
  quest(31, { objectives: { "3": [[101, null, 0]] } });           // an item only the boss drops
  quest(32, { objectives: [[[41, null, 0]]] });                   // also found outside
  quest(33, { objectives: [[[3, null, 0], [42, null, 0]]] });      // a place we cannot name is not an instance
  quest(34, { objectives: { "3": [[100, null, 0], [102, null, 0]] } }); // the boss drops it, but a vendor sells it too
  quest(35, { startedBy: [[43]], finishedBy: [[43]], zoneOrSort: 4500 }); // a battleground's own quest
  quest(36, { zoneOrSort: 4000 });                                // zoned in the dungeon, given outside
  return db;
}
test("instanced tells an open-world area from a dungeon, raid or battleground", () => {
  const db = instanceDb();
  assert.strictEqual(instanced(db, 1000), false);
  assert.strictEqual(instanced(db, 1001), false);
  assert.strictEqual(instanced(db, 4000), true);
  assert.strictEqual(instanced(db, 4500), true);    // it has a map, but it is not the open world
  assert.strictEqual(instanced(db, 10073), false);  // unknown is not the same as instanced
  db.areas.set(1584, { id: 1584, name: "A Dungeon Filed Under the Continent", parent: 0, continent: 0 });
  assert.strictEqual(instanced(db, 1584), true);    // Blackrock Depths: on the hand-written list
});
test("leveling quests leave out what cannot be finished in the open world", () => {
  const db = instanceDb();
  const ids = levelingQuests(db, character("Human", "WARRIOR")).map((q) => q.id);
  for (const id of [30, 31, 35, 36]) assert.ok(!ids.includes(id), `quest ${id} needs an instance`);
  for (const id of [32, 33, 34]) assert.ok(ids.includes(id), `quest ${id} can be done outside`);
});

const DATA = path.join(__dirname, "..", "data");
const real = fs.existsSync(path.join(DATA, "forever_db.json"));
// every quest of a character's list that can be reached from nothing, levels aside
function reachable(db, ch) {
  const state = { level: 60, done: new Set(), log: new Set() };
  const list = levelingQuests(db, ch);
  for (let again = true; again;) {
    again = false;
    for (const q of list) if (canAccept(q, state)) { state.done.add(q.id); again = true; }
  }
  return state.done;
}
test("real data: only the Skyborne get Zephras Isle quests, and both get the whole way off the isle", { skip: !real }, () => {
  const db = loadDb(DATA);
  const onIsle = (q, ch) => startPoint(db, q, ch.faction).point.continent === SKYBORNE_CONTINENT;
  for (const race of Object.keys(RACES)) {
    const ch = character(race, "WARRIOR");
    const isle = levelingQuests(db, ch).filter((q) => onIsle(q, ch));
    if (race === "HighOrder" || race === "Windshaper") assert.ok(isle.length >= 60, `${race} has ${isle.length} isle quests`);
    else assert.deepStrictEqual(isle.map((q) => q.id), [], `${race} has no business on the isle`);
  }
  const horde = reachable(db, character("Windshaper", "WARRIOR")), alliance = reachable(db, character("HighOrder", "WARRIOR"));
  // Windshaper: the first quest, the Horde welcome, the main chain to Valanaar and the ship to Mulgore
  for (const id of [92460, 92461, 92514, 92595, 92550, 93927, 92579, 92700, 92646, 93836, 93090, 95349]) assert.ok(horde.has(id), `Windshaper reaches ${id}`);
  // High Order: the same on the Alliance side, ending with the ship to Dalaran
  for (const id of [92460, 92461, 93461, 92596, 92550, 93927, 92701, 92699, 93835, 94369, 93089, 94946]) assert.ok(alliance.has(id), `High Order reaches ${id}`);
  for (const id of [93461, 92596, 92701, 92699, 92709, 94946]) assert.ok(!horde.has(id), `Windshaper never gets the Alliance quest ${id}`);
  for (const id of [92514, 92595, 92579, 92708, 95349]) assert.ok(!alliance.has(id), `High Order never gets the Horde quest ${id}`);
  const first = (ch) => levelingQuests(db, ch).filter((q) => q.minLevel === 1 && onIsle(q, ch)).map((q) => q.id);
  assert.ok(first(character("Windshaper", "WARRIOR")).includes(92460), "Windshaper has a level 1 quest on the isle");
});
test("real data: the way off Zephras Isle is a quest that ends on the mainland", { skip: !real }, () => {
  const db = loadDb(DATA);
  const ends = (id, faction) => { const p = endPoint(db, db.quests.get(id), faction); return [p.point.zone, p.npc]; };
  assert.strictEqual(startPoint(db, db.quests.get(94946), "Alliance").point.zone, 16593);
  assert.deepStrictEqual(ends(94946, "Alliance"), [36, 259084]);  // Denaaris Stargale, placed in Alterac Mountains (Dalaran)
  assert.strictEqual(startPoint(db, db.quests.get(95349), "Horde").point.zone, 16593);
  assert.deepStrictEqual(ends(95349, "Horde"), [215, 259119]);    // Alaana Stormwalker, Mulgore
  assert.deepStrictEqual(db.taxi.filter((t) => t.continent === SKYBORNE_CONTINENT).map((t) => t.id), [3361]); // a quest path, not a flight point
});
test("real data: no leveling quest needs a dungeon, raid or battleground, or is repeatable or gated", { skip: !real }, () => {
  const db = loadDb(DATA);
  const all = new Map();
  for (const race of Object.keys(RACES)) for (const q of levelingQuests(db, character(race, "WARRIOR"))) all.set(q.id, q);
  for (const q of all.values()) {
    assert.ok(!q.repeatable && !q.gated, `quest ${q.id} is repeatable or gated`);
    assert.ok(!instanced(db, q.zone), `quest ${q.id} is zoned in an instance`);
  }
  for (const id of [7141, 7142, 7081, 8271, 8272]) assert.ok(!all.has(id), `Alterac Valley quest ${id}`);
  for (const id of [1475, 1445, 3380]) assert.ok(!all.has(id), `Sunken Temple quest ${id}`);
  for (const id of [1221, 5166, 5167]) assert.ok(!all.has(id), `quest ${id} needs a drop from inside a dungeon`);
  // Glyph Chasing and Breaking the Code are ordinary Silithus quests: an earlier route only ended before their turn-in
  for (const id of [8309, 8310, 5527, 3627]) assert.ok(all.has(id), `quest ${id} can be finished`);
});
test("a quest whose only objective is a kill credit is done where its creatures are", () => {
  // Found by the simulator (task X1): Kodo Roundup (a kill credit objective, nothing else) was planned as accept and
  // hand in with no objective step, so the hand-in waited forever.
  const { testWorld } = require("./world");
  const w = testWorld();
  w.npc(10, 100, 30, 30, "AH", "Giver");
  w.npc(12, 100, 80, 80, "", "Far Kodo"); w.npc(13, 100, 35, 35, "", "Near Kodo");
  w.quest(5, { startedBy: [[10]], finishedBy: [[10]], objectives: [null, null, null, null, [[[12, 13], 99, "Kodo tamed"]]], zoneOrSort: 100 });
  const q = w.db.quests.get(5);
  const at = objectivePoint(w.db, q);
  assert.ok(at, "the objective has a place");
  assert.strictEqual(at.npc, 13, "the credited creatures nearest the giver");
  w.db.npcs.delete(12); w.db.npcs.delete(13);
  assert.strictEqual(objectivePoint(w.db, w.db.quests.get(5)), null, "creatures with no spawn: no place");
  assert.ok(!levelingQuests(w.db, character("Orc", "WARRIOR")).some((x) => x.id === 5), "and the quest cannot be placed, so it is left out");
});
