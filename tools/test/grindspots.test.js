// Noir Guides, GPLv3. See LICENSE.
// Places to grind at (tools/planner/grindspots.js). Every map of the test world is 1000 yards square, so one map
// percent is 10 yards.
const test = require("node:test");
const assert = require("node:assert");
const { testWorld } = require("./world");
const { grindSpots, grindSpotAt, grindTargets } = require("../planner/grindspots");
const { CHOICES: C } = require("../planner/tuning");

// Westland as open country with quests of its own (lib/xp.js zoneLevels): a herd without levels, which no grind counts
function world() {
  const w = testWorld();
  w.npc(10, 100, 30, 50); w.herd(40, 100, 5, 5);
  w.kill(1, 10, 40, 100);
  return w;
}
const places = (db, level) => grindSpots(db, level).map((s) => [s.at.zone, s.at.x, s.at.y, s.count, s.npcs]);

test("the constants are the plan's: creatures from two levels under the player to one above, twelve within 150 yards", () => {
  assert.deepStrictEqual([C.GRIND_BELOW, C.GRIND_ABOVE, C.GRIND_RADIUS, C.GRIND_MIN_SPAWNS], [2, 1, 150, 12]);
});

test("a place to grind at is where enough creatures of the level stand together", () => {
  const w = world();
  w.pack(50, 100, 60, 70, 10, 20);
  w.pack(51, 100, 62, 70, 11, 5);   // 20 yards on: the same place
  w.pack(52, 100, 20, 20, 10, C.GRIND_MIN_SPAWNS - 1); // too few to be a place
  assert.deepStrictEqual(places(w.db, 10), [[100, 60.4, 70, 25, [50, 51]]]);
  // level 9 to 12 fight the level 10 wolves; the level 11 ones are too high for level 9 and stay with level 13
  assert.deepStrictEqual(places(w.db, 9), [[100, 60, 70, 20, [50]]]);
  assert.deepStrictEqual(places(w.db, 12), [[100, 60.4, 70, 25, [50, 51]]]);
  assert.deepStrictEqual(places(w.db, 13), []);
  assert.deepStrictEqual(places(w.db, 8), []);
  // the same answer for the same world
  assert.strictEqual(grindSpots(w.db, 10), grindSpots(w.db, 10));
});

test("never an elite, a friendly creature, a city or a creature without a level", () => {
  const w = world();
  w.pack(50, 100, 60, 70, 10, 20, { rank: 1 });           // elite
  w.pack(51, 100, 60, 30, 10, 20, { friendly: "A" });      // the other faction's guards are no place to grind either
  w.pack(52, 100, 20, 70, 10, 20, { minLevel: 0, maxLevel: 0 });
  w.pack(53, 100, 80, 50, 9, 20, { maxLevel: 12 });        // some of them two levels above the player
  w.pack(54, 200, 50, 50, 10, 20);                         // Eastland has no quests and too few creatures: not open country
  assert.deepStrictEqual(places(w.db, 10), []);
  assert.deepStrictEqual(grindSpotAt(w.db, { zone: 100, x: 60, y: 70 }, 10), { count: 0, npcs: [] });
  // Forever's own creatures are left out where the data says which are classic
  const era = world();
  era.pack(50, 100, 60, 70, 10, 20); era.pack(51, 100, 20, 20, 10, 20);
  era.db.eraNpcIds = new Set([51]);
  assert.deepStrictEqual(places(era.db, 10), [[100, 20, 20, 20, [51]]]);
});

test("what stands at a place: the count, the levels and the creatures to name, most spawns first", () => {
  const w = world();
  w.pack(50, 100, 60, 70, 10, 6); w.pack(51, 100, 61, 70, 11, 14); w.pack(52, 100, 60, 71, 9, 2);
  // the two wolves of 52 are under GRIND_NAMED_SHARE of the 22 and are not named
  assert.deepStrictEqual(grindSpotAt(w.db, { zone: 100, x: 60.5, y: 70 }, 10), { count: 22, npcs: [51, 50], min: 9, max: 11 });
  assert.deepStrictEqual(grindTargets(w.db, { zone: 100, x: 60.5, y: 70 }, 10), [51, 50]);
  assert.deepStrictEqual(grindTargets(w.db, { zone: 100, x: 60.5, y: 70 }, 9), [], "only eight of them fit level 9: not a place");
  assert.deepStrictEqual(grindTargets(w.db, { zone: 100, x: 20, y: 20 }, 10), [], "200 yards and more away");
  assert.deepStrictEqual(grindTargets(w.db, { zone: 999, x: 20, y: 20 }, 10), []);
});
