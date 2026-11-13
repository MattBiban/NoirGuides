// Noir Guides, GPLv3. See LICENSE.
const test = require("node:test");
const assert = require("node:assert");
const { testWorld, at } = require("./world");
const { leftBehind, MAX_LEFT_BEHIND } = require("../planner/leftbehind");
const { CHOICES } = require("../planner/tuning");

// Westland's map is 1000 yards square: one percent is 10 yards
const db = testWorld().db;
const route = (steps) => ({ steps });

test("the thresholds are the planner's", () => {
  assert.strictEqual(CHOICES.READY_YARDS, 300);
  assert.strictEqual(CHOICES.LEAVE_YARDS, 500);
  assert.ok(MAX_LEFT_BEHIND >= 0 && MAX_LEFT_BEHIND <= 2);
});
test("a step that moves far while a ready hand-in waits close by leaves it behind", () => {
  const steps = [
    { action: "accept", quest: 1, at: at(100, 30, 50) },
    { action: "objective", quest: 1, at: at(100, 30, 60) }, // ready, 100 yards from its turn-in
    { action: "accept", quest: 2, at: at(100, 90, 60) },    // 600 yards on
    { action: "turnin", quest: 1, at: at(100, 30, 50) },
  ];
  assert.deepStrictEqual(leftBehind(db, route(steps)), [{ step: 2, quests: [1], yards: 600 }]);
});
test("nothing is left behind when the hand-in comes first, the move is short, or the hand-in is far", () => {
  const first = [
    { action: "accept", quest: 1, at: at(100, 30, 50) }, { action: "objective", quest: 1, at: at(100, 30, 60) },
    { action: "turnin", quest: 1, at: at(100, 30, 50) }, { action: "accept", quest: 2, at: at(100, 90, 60) },
  ];
  assert.deepStrictEqual(leftBehind(db, route(first)), []);
  const short = [
    { action: "accept", quest: 1, at: at(100, 30, 50) }, { action: "objective", quest: 1, at: at(100, 30, 60) },
    { action: "objective", quest: 2, at: at(100, 70, 60) }, { action: "turnin", quest: 1, at: at(100, 30, 50) },
  ];
  assert.deepStrictEqual(leftBehind(db, route(short)), []);
  const far = [
    { action: "accept", quest: 1, at: at(100, 10, 10) }, { action: "objective", quest: 1, at: at(100, 50, 50) }, // 566 yards from its turn-in
    { action: "accept", quest: 2, at: at(100, 95, 95) }, { action: "turnin", quest: 1, at: at(100, 10, 10) },
  ];
  assert.deepStrictEqual(leftBehind(db, route(far)), []);
});
test("a quest without an objective step is ready once taken; a quest whose objective is still to come is not", () => {
  const steps = [
    { action: "accept", quest: 1, at: at(100, 30, 50) }, { action: "accept", quest: 2, at: at(100, 32, 50) },
    { action: "objective", quest: 3, at: at(100, 90, 90) }, { action: "objective", quest: 2, at: at(100, 90, 91) },
    { action: "turnin", quest: 1, at: at(100, 31, 50) }, { action: "turnin", quest: 2, at: at(100, 32, 50) },
  ];
  assert.deepStrictEqual(leftBehind(db, route(steps)), [{ step: 2, quests: [1], yards: 705 }]);
});
test("a flight or a hearth always leaves; each quest is counted once", () => {
  const steps = [
    { action: "accept", quest: 1, at: at(100, 30, 50) }, { action: "objective", quest: 1, at: at(100, 30, 52) },
    { action: "hearth", to: at(100, 22, 50) },              // 80 yards, but a hearth: counted
    { action: "fly", from: 1, to: 3, at: at(100, 20, 50) }, // quest 1 again: not counted twice
    { action: "accept", quest: 2, at: at(200, 30, 50) }, { action: "turnin", quest: 1, at: at(100, 30, 50) },
  ];
  assert.deepStrictEqual(leftBehind(db, route(steps)), [{ step: 2, quests: [1], yards: Infinity }]);
});
