// Noir Guides, GPLv3. See LICENSE.
const test = require("node:test");
const assert = require("node:assert");
const { fixtureDb } = require("./fixture");
const { PACE, XP_TO_LEVEL, mobXp, questXp, objectiveXp, objectiveSeconds, walkXp, zoneLevels } = require("../lib/xp");

test("a kill gives the original game's XP: full at the player's level, more above, less below, none when grey", () => {
  assert.strictEqual(mobXp(10, 10), 95);
  assert.strictEqual(mobXp(30, 30), 195);
  assert.strictEqual(mobXp(12, 10), Math.round(95 * 1.1));
  assert.strictEqual(mobXp(20, 10), Math.round(95 * 1.2), "the bonus stops at four levels above");
  assert.strictEqual(mobXp(8, 10), Math.round(95 * (1 - 2 / 7)));
  assert.strictEqual(mobXp(4, 10), 0, "grey at level 10 is 4 and below");
  assert.strictEqual(mobXp(5, 10), Math.round(95 * (1 - 5 / 7)));
  assert.strictEqual(mobXp(47, 60), 0);
  assert.ok(mobXp(52, 60) > 0);
  assert.strictEqual(mobXp(1, 1), 50);
  for (let level = 1; level <= 60; level++) for (let mob = 1; mob <= 63; mob++) {
    assert.ok(mobXp(mob, level) >= 0 && (mob < 2 || mobXp(mob, level) >= mobXp(mob - 1, level)), `mob ${mob} at ${level}`);
  }
});
test("an objective is worth its kills: creature objectives, and item objectives at twice the kills", () => {
  const quest = { level: 20, objectives: { npcs: [1, 2], items: [3], objects: [4] } };
  // two creature objectives, and one item objective that takes twice the kills
  assert.strictEqual(objectiveXp(quest, 20), (2 + PACE.ITEM_KILL_FACTOR) * PACE.OBJECTIVE_KILLS * mobXp(20, 20));
  assert.strictEqual(objectiveSeconds(quest), (2 + PACE.ITEM_KILL_FACTOR) * PACE.OBJECTIVE_KILLS * PACE.KILL_SECONDS);
  assert.strictEqual(objectiveSeconds({ level: 20, objectives: { npcs: [], items: [], objects: [4] } }), PACE.TALK_SECONDS);
  assert.strictEqual(objectiveXp(quest, 40), 0);
  assert.strictEqual(objectiveXp({ level: 20, objectives: { npcs: [], items: [], objects: [4] } }, 20), 0);
});
test("walking gives kill XP only in a zone with creatures of a level worth fighting", () => {
  const wild = { min: 10, max: 20, wild: true };
  assert.strictEqual(walkXp(PACE.INCIDENTAL_YARDS * 4, wild, 15), 4 * mobXp(15, 15));
  assert.strictEqual(walkXp(PACE.INCIDENTAL_YARDS, wild, 8), mobXp(10, 8), "below the band the creatures are the band's lowest");
  assert.strictEqual(walkXp(PACE.INCIDENTAL_YARDS, wild, 40), 0, "everything is grey");
  assert.strictEqual(walkXp(PACE.INCIDENTAL_YARDS * 4, { min: 10, max: 20, wild: false }, 15), 0, "a city");
  assert.strictEqual(walkXp(1000, null, 15), 0);
  assert.strictEqual(walkXp(0, wild, 15), 0);
  assert.strictEqual(walkXp(Infinity, wild, 15), 0);
});
test("zone levels come from the quests filed under the zone, and wild from its hostile creatures", () => {
  const db = fixtureDb();
  let levels = zoneLevels(db);
  assert.deepStrictEqual(levels.get(1000), { min: 2, max: 4, wild: false });
  for (let i = 0; i < PACE.WILD_SPAWNS; i++) db.npcs.get(3).spawns[1000].push([60, 60]);
  levels = zoneLevels(db);
  assert.strictEqual(levels.get(1000).wild, true);
  assert.strictEqual(levels.get(2000).wild, false);
  assert.strictEqual(levels.has(999), false);
});
test("the estimates are in one place and each is a positive number", () => {
  assert.ok(Object.isFrozen(PACE));
  for (const [name, value] of Object.entries(PACE)) assert.ok(typeof value === "number" && value > 0, name);
  assert.strictEqual(XP_TO_LEVEL.length, 60);
  assert.strictEqual(questXp(2, 20), 0);
});
