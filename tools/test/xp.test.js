// Noir Guides, GPLv3. See LICENSE.
const test = require("node:test");
const assert = require("node:assert");
const { fixtureDb } = require("./fixture");
const { PACE, XP_TO_LEVEL, yieldAt, gain, grindSeconds, mobXp, questXp, objectiveXp, objectiveSeconds, walkXp, zoneLevels } = require("../lib/xp");

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
  assert.deepStrictEqual(levels.get(1000), { min: 1, max: 2, wild: false });
  for (let i = 0; i < PACE.WILD_SPAWNS; i++) db.npcs.get(3).spawns[1000].push([60, 60]);
  levels = zoneLevels(db);
  assert.strictEqual(levels.get(1000).wild, true);
  assert.strictEqual(levels.get(2000).wild, false);
  assert.strictEqual(levels.has(999), false);
});
test("the share of the estimate that is counted on rises from YIELD at level 30 to YIELD_LATE at level 50", () => {
  assert.deepStrictEqual([PACE.YIELD, PACE.YIELD_LATE, PACE.YIELD_FROM, PACE.YIELD_TO], [0.6, 0.68, 30, 50]);
  assert.deepStrictEqual([1, 30, 50, 60].map(yieldAt), [0.6, 0.6, 0.68, 0.68]);
  assert.ok(Math.abs(yieldAt(40) - 0.64) < 1e-12, "halfway between at level 40");
  for (let level = 2; level <= 60; level++) assert.ok(yieldAt(level) >= yieldAt(level - 1), `never less at level ${level}`);
  // gain counts every XP at the share of the level it is earned at
  const low = { level: 10, xp: 0 }, high = { level: 55, xp: 0 }, between = { level: 35, xp: 0 };
  gain(low, 1000); gain(high, 1000); gain(between, 1000);
  assert.deepStrictEqual([low.xp, between.xp, high.xp], [600, 620, 680]);
  // ... and a level gained on the way is counted from what was earned, not earned again at the new share
  const up = { level: 1, xp: 390 };
  gain(up, 100);
  assert.deepStrictEqual(up, { level: 2, xp: 50 });
});
test("a grind step takes the fights of the rest of the level, each counted at the share of its XP every gain is", () => {
  // level 10: 7,600 XP to the next, 95 a kill, 57 of them counted
  assert.strictEqual(grindSeconds(10, 0), Math.ceil(7600 / 57) * PACE.KILL_SECONDS);
  assert.strictEqual(grindSeconds(10, 0), 134 * 30);
  assert.strictEqual(grindSeconds(10, 7600 - 57), PACE.KILL_SECONDS, "one fight short of the level");
  assert.strictEqual(grindSeconds(10, 7600 - 58), 2 * PACE.KILL_SECONDS);
  assert.strictEqual(grindSeconds(10, 7600), 0);
  assert.strictEqual(grindSeconds(10, 9000), 0, "never less than nothing");
  // from level 50 a fight counts for more of its XP, so the same share of a level is fewer fights than the low share would make it
  assert.strictEqual(grindSeconds(59, 0), Math.ceil(XP_TO_LEVEL[59] / Math.round(mobXp(59, 59) * PACE.YIELD_LATE)) * PACE.KILL_SECONDS);
  assert.ok(grindSeconds(59, 0) < Math.ceil(XP_TO_LEVEL[59] / Math.round(mobXp(59, 59) * PACE.YIELD)) * PACE.KILL_SECONDS);
  // the fights of a grind step are the fights gain needs for the level: that many reach it, one less does not
  for (const level of [1, 10, 35, 59]) {
    const fights = grindSeconds(level, 0) / PACE.KILL_SECONDS;
    const state = { level, xp: 0 };
    for (let n = 1; n < fights; n++) gain(state, mobXp(level, level));
    assert.strictEqual(state.level, level, `level ${level}: one fight short`);
    gain(state, mobXp(level, level));
    assert.strictEqual(state.level, level + 1, `level ${level}: ${fights} fights`);
  }
});
test("the estimates are in one place and each is a positive number", () => {
  assert.ok(Object.isFrozen(PACE));
  for (const [name, value] of Object.entries(PACE)) assert.ok(typeof value === "number" && value > 0, name);
  assert.strictEqual(XP_TO_LEVEL.length, 60);
  assert.strictEqual(questXp(2, 20), 0);
});
