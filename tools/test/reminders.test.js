// Noir Guides, GPLv3. See LICENSE.
// Reminder steps (tools/planner/reminders.js, task P3 of docs/superpowers/plans/2026-11-11-guide-rebuild.md, spec
// 3.6). Every map of the test world is 1000 yards square: one map percent is 10 yards.
const test = require("node:test");
const assert = require("node:assert");
const { testWorld } = require("./world");
const { flatten } = require("../planner/bundle");
const { checkRoute3 } = require("../planner/format3");
const { addReminders, REMINDER_YARDS } = require("../planner/reminders");

const P = (x, y, r) => (r === undefined ? { zone: 100, x, y } : { zone: 100, x, y, r });
const kill = (quest, npc, extra = {}) => ({ kind: "objective", quest, index: 1, npc, ...extra });
const section = (steps) => ({ id: "human-01-05-westland", name: "1-5 Westland", group: "Alliance", subgroup: "1-20", minLevel: 1, maxLevel: 8, zone: 100,
  start: true, next: [], steps });
const clone = (o) => JSON.parse(JSON.stringify(o));
const ids = (s) => s.steps.map((x) => x.id);

// accept 1 and 2; objectives of 1 (a kill) and 2 (an object); accept 3; objective of 3; hand in 1 and 3
function hub(o1Place = P(40, 50, 40), a3Place = P(45, 50, 10)) {
  return section([
    { id: "a1.a2", at: P(30, 50, 10), lines: [{ kind: "accept", quest: 1, npc: 10 }, { kind: "accept", quest: 2, npc: 10 }] },
    { id: "o1.o2", at: o1Place, lines: [kill(1, 20), { kind: "objective", quest: 2, index: 1, object: 30 }], targets: { enemy: [20] } },
    { id: "a3", at: a3Place, lines: [{ kind: "accept", quest: 3, npc: 11 }] },
    { id: "o3", at: P(50, 50, 40), lines: [kill(3, 21)] },
    { id: "t1.t3", at: P(30, 50, 10), lines: [{ kind: "turnin", quest: 1, npc: 10 }, { kind: "turnin", quest: 3, npc: 10 }] },
  ]);
}

test("the constant is the plan's", () => {
  assert.strictEqual(REMINDER_YARDS, 200);
});

test("an objective done around the next steps becomes a reminder ending at its turn-in", () => {
  const { db } = testWorld();
  const before = hub();
  const out = addReminders(db, clone(before));
  assert.deepStrictEqual(ids(out), ["a1.a2", "r1", "o1.o2", "a3", "o3", "t1.t3"]);
  assert.deepStrictEqual(out.steps[1], { id: "r1", at: P(40, 50, 40), lines: [kill(1, 20)], targets: { enemy: [20] }, reminder: { ends: "turnin1" } });
  assert.strictEqual(out.steps[2].targets, undefined, "the moved kill takes its target button along");
  assert.deepStrictEqual(out.steps[2].lines, [{ kind: "objective", quest: 2, index: 1, object: 30 }], "the object objective stays");
  assert.strictEqual(out.steps[5].label, "turnin1");
  assert.strictEqual(out.steps[4].reminder, undefined, "quest 3 is handed in on the very next step: no reminder");
  assert.strictEqual(checkRoute3({ format: 3, race: "Human", faction: "Alliance", sections: [out] }), null);
  // an item objective counts as well, and a line's own place is the reminder's place
  const items = hub();
  items.steps[1].lines[0] = { kind: "objective", quest: 1, index: 1, item: 100, at: P(42, 52, 40) };
  const got = addReminders(db, items);
  assert.deepStrictEqual(got.steps[1], { id: "r1", at: P(42, 52, 40), lines: [{ kind: "objective", quest: 1, index: 1, item: 100 }], reminder: { ends: "turnin1" } });
  assert.deepStrictEqual(got.steps[2].targets, { enemy: [20] }, "a target that drops nothing the moved line needs stays");
  // the input is not changed
  assert.deepStrictEqual(hub(), before);
});

test("a turn-in step that already ends a reminder lends its label to the next one", () => {
  const { db } = testWorld();
  const s = hub();
  s.steps.splice(3, 1, { id: "o3", at: P(50, 50, 40), lines: [kill(3, 21)] }, { id: "a4", at: P(48, 50, 10), lines: [{ kind: "accept", quest: 4, npc: 11 }] });
  const out = addReminders(db, s);
  assert.deepStrictEqual(ids(out), ["a1.a2", "r1", "o1.o2", "a3", "r3", "a4", "t1.t3"]);
  assert.deepStrictEqual(out.steps[4].reminder, { ends: "turnin1" });
  assert.strictEqual(out.steps[6].label, "turnin1");
  assert.strictEqual(checkRoute3({ format: 3, race: "Human", faction: "Alliance", sections: [out] }), null);
});

test("an objective far from a step in between stays where it was", () => {
  const { db } = testWorld();
  // the accept of quest 3 is 400 yards from the objective's place
  const far = hub(P(40, 50, 40), P(80, 50, 10));
  assert.deepStrictEqual(addReminders(db, clone(far)), far);
  // a step in between with no place (a hearth) breaks it too
  const hearth = hub();
  hearth.steps.splice(2, 0, { id: "h", lines: [{ kind: "hearth", to: P(22, 50) }] });
  assert.deepStrictEqual(addReminders(db, clone(hearth)), hearth);
  // a turn-in that applies to fewer characters than the objective cannot end it
  const cls = hub();
  cls.steps[4].when = { class: "ROGUE" };
  assert.deepStrictEqual(addReminders(db, clone(cls)), cls);
});

test("a step emptied by the move is removed and flatten still lists every action", () => {
  const { db } = testWorld();
  const s = hub();
  s.steps[1] = { id: "o1", at: P(40, 50, 40), lines: [kill(1, 20), { kind: "objective", quest: 1, index: 2, npc: 22, skipIfMissing: true }], targets: { enemy: [20, 22] } };
  const before = flatten(s.steps);
  const out = addReminders(db, clone(s));
  assert.deepStrictEqual(ids(out), ["a1.a2", "r1", "a3", "o3", "t1.t3"]);
  assert.deepStrictEqual(out.steps[1].lines, [kill(1, 20), { kind: "objective", quest: 1, index: 2, npc: 22, skipIfMissing: true }]);
  assert.deepStrictEqual(out.steps[1].targets, { enemy: [20, 22] }, "the target buttons of the moved lines go with them");
  assert.deepStrictEqual(flatten(out.steps), before);
  assert.strictEqual(checkRoute3({ format: 3, race: "Human", faction: "Alliance", sections: [out] }), null);
});

test("a reminder keeps the item buttons of its quest, and the step left behind keeps only the ones it still needs", () => {
  const world = testWorld();
  const { db } = world;
  db.items.set(500, { id: 500, name: "Blackjack" });
  db.items.set(501, { id: 501, name: "Torch" });
  world.quest(1, { sourceItemId: 500 });
  world.quest(2, { requiredSourceItems: [501] });
  // the kill of quest 1 leaves, the object of quest 2 stays: each keeps its own item
  const s = hub();
  s.steps[1].items = [500, 501];
  const out = addReminders(db, s);
  assert.deepStrictEqual(ids(out), ["a1.a2", "r1", "o1.o2", "a3", "o3", "t1.t3"]);
  assert.deepStrictEqual(out.steps[1].items, [500], "the reminder of quest 1 carries quest 1's item");
  assert.deepStrictEqual(out.steps[2].items, [501], "the object objective of quest 2 keeps quest 2's item");
  assert.strictEqual(checkRoute3({ format: 3, race: "Human", faction: "Alliance", sections: [out] }), null);
  // a step emptied by the move: its item is not lost
  const e = hub();
  e.steps[1] = { id: "o1", at: P(40, 50, 40), lines: [kill(1, 20)], targets: { enemy: [20] }, items: [500] };
  const got = addReminders(db, e);
  assert.deepStrictEqual(ids(got), ["a1.a2", "r1", "a3", "o3", "t1.t3"]);
  assert.deepStrictEqual(got.steps[1].items, [500]);
});
