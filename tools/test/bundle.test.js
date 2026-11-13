// Noir Guides, GPLv3. See LICENSE.
// Bundling a format 2 action list into format 3 steps (tools/planner/bundle.js, task P1 of
// docs/superpowers/plans/2026-11-11-guide-rebuild.md). Every map of the test world is 1000 yards square, so one map
// percent is 10 yards.
const test = require("node:test");
const assert = require("node:assert");
const { testWorld } = require("./world");
const { classMask } = require("../lib/characters");
const { toPoint, distance } = require("../lib/geo");
const { planRoute } = require("../planner/plan");
const { layerClasses } = require("../planner/classes");
const { checkRoute3 } = require("../planner/format3");
const { bundleSteps, flatten, hubOrder, RADIUS, BUNDLE_YARDS, OBJECTIVE_YARDS, HUB_YARDS, OWN_PLACE_YARDS } = require("../planner/bundle");

const ROGUE = classMask("ROGUE");
const M = (zone, x, y) => ({ zone, x, y });
const route2 = (steps) => ({ id: "alliance-human", format: 2, race: "Human", faction: "Alliance", steps });
const bundle = (w, steps) => bundleSteps(w.db, route2(steps), steps.map(() => 1));
const kinds = (step) => step.lines.map((l) => l.kind);

// BUNDLE_YARDS was 30 in the plan; the project lead raised it and added the hub (P3 follow-up, DATA-NOTES.md).
test("the constants are the plan's and cannot be changed", () => {
  assert.deepStrictEqual({ ...RADIUS }, { npc: 10, flightmaster: 10, dock: 15, goto: 20, area: 40, zoneOnly: 0 });
  assert.ok(Object.isFrozen(RADIUS));
  assert.strictEqual(BUNDLE_YARDS, 60);
  assert.strictEqual(HUB_YARDS, 80);
  assert.strictEqual(OWN_PLACE_YARDS, 30);
  assert.strictEqual(OBJECTIVE_YARDS, 150);
});

test("quest givers up to 80 yards from the step's first NPC share its step; farther ones do not", () => {
  const w = testWorld();
  w.npc(10, 100, 30, 50); w.npc(11, 100, 37, 50); w.npc(12, 100, 39, 50); w.npc(20, 100, 60, 30, "");
  w.kill(1, 10, 20, 100); w.kill(2, 11, 20, 100); w.kill(3, 12, 20, 100);
  const out = bundle(w, [
    { action: "accept", quest: 1, at: M(100, 30, 50), npc: 10 },
    { action: "accept", quest: 2, at: M(100, 37, 50), npc: 11 },   // 70 yards
    { action: "accept", quest: 3, at: M(100, 39, 50), npc: 12 },   // 90 yards
  ]);
  assert.deepStrictEqual(out.steps.map((s) => s.lines.map((l) => l.quest)), [[1, 2], [3]]);
  assert.deepStrictEqual(out.steps[0].lines[1].at, { zone: 100, x: 37, y: 50, r: RADIUS.npc }, "a giver over 30 yards away keeps its own place");
});

test("an objective within 60 yards of a quest giver joins its step, a farther one is a step of its own", () => {
  const w = testWorld();
  w.npc(10, 100, 30, 50); w.npc(20, 100, 35, 50, ""); w.npc(21, 100, 37, 50, "");
  w.kill(1, 10, 20, 100); w.kill(2, 10, 21, 100);
  const out = bundle(w, [
    { action: "accept", quest: 1, at: M(100, 30, 50), npc: 10 },
    { action: "objective", quest: 1, at: M(100, 35, 50), npc: 20 },   // 50 yards
    { action: "turnin", quest: 1, at: M(100, 30, 50), npc: 10 },
    { action: "accept", quest: 2, at: M(100, 30, 50), npc: 10 },
    { action: "objective", quest: 2, at: M(100, 37, 50), npc: 21 },   // 70 yards
  ]);
  assert.deepStrictEqual(out.steps.map(kinds), [["accept", "objective", "turnin", "accept"], ["objective"]]);
  assert.deepStrictEqual(out.steps[0].lines[1].at, { zone: 100, x: 35, y: 50, r: RADIUS.area });
});

test("a hub's accepts and turn-ins become one step when only other hub actions stand between", () => {
  const w = testWorld();
  w.npc(10, 100, 30, 50); w.npc(11, 100, 35, 50); w.npc(20, 100, 60, 30, "");
  w.kill(1, 10, 20, 100); w.kill(2, 11, 20, 100); w.kill(40, 10, 20, 100, { requiredClasses: ROGUE });
  const steps = [
    { action: "accept", quest: 1, at: M(100, 30, 50), npc: 10 },
    { action: "accept", quest: 40, at: M(100, 30, 50), npc: 10, when: { class: "ROGUE" } },
    { action: "turnin", quest: 2, at: M(100, 35, 50), npc: 11 },
  ];
  const out = bundle(w, steps);
  assert.deepStrictEqual(out.steps.map((s) => s.lines.map((l) => l.quest)), [[1, 2], [40]]);
  assert.deepStrictEqual(out.origin, [[0, 2], [1]]);
  assert.deepStrictEqual(hubOrder(w.db, steps, [1, 1, 1]), [0, 2, 1]);
});

test("the planner's order is kept where something other than a hub action stands between", () => {
  const w = testWorld();
  w.npc(10, 100, 30, 50); w.npc(20, 100, 60, 30, ""); w.npc(21, 100, 30, 51, "");
  w.kill(1, 10, 20, 100); w.kill(2, 10, 20, 100);
  const steps = [
    { action: "accept", quest: 1, at: M(100, 30, 50), npc: 10 },
    { action: "objective", quest: 1, at: M(100, 60, 30), npc: 20 },   // 360 yards away
    { action: "accept", quest: 2, at: M(100, 30, 50), npc: 10 },
    { action: "travel", at: M(100, 30, 52) },
    { action: "turnin", quest: 1, at: M(100, 30, 50), npc: 10 },
  ];
  assert.deepStrictEqual(hubOrder(w.db, steps, steps.map(() => 1)), [0, 1, 2, 3, 4]);
  assert.deepStrictEqual(bundle(w, steps).origin, [[0], [1], [2], [3], [4]]);
});

test("the objectives of one area become one step and the hand-in trip comes after; an objective never passes its own accept", () => {
  const w = testWorld();
  w.npc(10, 100, 30, 50); w.npc(11, 100, 80, 50); w.npc(20, 100, 60, 30, ""); w.npc(21, 100, 61, 31, ""); w.npc(22, 100, 62, 30, "");
  w.kill(1, 10, 20, 100); w.kill(2, 10, 21, 100); w.kill(3, 11, 22, 100); w.kill(4, 10, 22, 100);
  const steps = [
    { action: "objective", quest: 1, at: M(100, 60, 30), npc: 20 },
    { action: "turnin", quest: 1, at: M(100, 30, 50), npc: 10 },     // 360 yards back to town
    { action: "accept", quest: 3, at: M(100, 80, 50), npc: 11 },
    { action: "objective", quest: 2, at: M(100, 61, 31), npc: 21 },   // 14 yards from the first: joins it
    { action: "objective", quest: 3, at: M(100, 62, 30), npc: 22 },   // its accept is in between: stays
    { action: "objective", quest: 4, at: M(100, 62, 30), npc: 22, when: { class: "ROGUE" } }, // another condition: stays
  ];
  assert.deepStrictEqual(hubOrder(w.db, steps, steps.map(() => 1)), [0, 3, 1, 2, 4, 5]);
  assert.deepStrictEqual(bundle(w, steps).origin, [[0, 3], [1], [2], [4], [5]]);
  // a step of the way ends the area
  const travel = [steps[0], { action: "travel", at: M(100, 40, 50) }, steps[3]];
  assert.deepStrictEqual(hubOrder(w.db, travel, [1, 1, 1]), [0, 1, 2]);
});

test("a hub action is never moved before its prerequisite", () => {
  const w = testWorld();
  w.npc(10, 100, 30, 50); w.npc(20, 100, 60, 30, "");
  w.kill(1, 10, 20, 100); w.kill(41, 10, 20, 100, { requiredClasses: ROGUE }); w.kill(42, 10, 20, 100, { requiredClasses: ROGUE, preQuestGroup: [1] });
  const rogue = { class: "ROGUE" };
  const steps = [
    { action: "accept", quest: 41, at: M(100, 30, 50), npc: 10, when: rogue },
    { action: "turnin", quest: 1, at: M(100, 30, 50), npc: 10 },
    { action: "accept", quest: 42, at: M(100, 30, 50), npc: 10, when: rogue },
  ];
  assert.deepStrictEqual(hubOrder(w.db, steps, [1, 1, 1]), [0, 1, 2]);
});

test("an accept is never moved after an objective that needs it, nor before the level it needs", () => {
  const w = testWorld();
  w.npc(10, 100, 30, 50); w.npc(20, 100, 32, 50, "");
  w.kill(1, 10, 20, 100); w.kill(3, 10, 20, 100, { requiredLevel: 5 }); w.kill(40, 10, 20, 100, { requiredClasses: ROGUE });
  const steps = [
    { action: "accept", quest: 1, at: M(100, 30, 50), npc: 10 },
    { action: "turnin", quest: 40, at: M(100, 30, 50), npc: 10, when: { class: "ROGUE" } },
    { action: "accept", quest: 3, at: M(100, 30, 50), npc: 10 },      // level 5: the character is 4 before the turn-in
    { action: "objective", quest: 3, at: M(100, 32, 50), npc: 20 },   // 20 yards from the first NPC
  ];
  assert.deepStrictEqual(hubOrder(w.db, steps, [4, 4, 5, 5]), [0, 1, 2, 3]);
  assert.deepStrictEqual(hubOrder(w.db, steps, [5, 5, 5, 5]), [0, 2, 3, 1], "at level 5 the accept and its objective join the first step");
});

test("a getflight stays right before its fly", () => {
  const w = testWorld();
  w.npc(10, 100, 21, 50); w.npc(20, 100, 60, 30, "");
  w.kill(40, 10, 20, 100, { requiredClasses: ROGUE }); w.kill(1, 10, 20, 100);
  const steps = [
    { action: "accept", quest: 1, at: M(100, 21, 50), npc: 10 },
    { action: "accept", quest: 40, at: M(100, 21, 50), npc: 10, when: { class: "ROGUE" } },
    { action: "getflight", node: 1, at: M(100, 20, 50), npc: 901 },
    { action: "fly", from: 1, to: 3, at: M(100, 20, 50) },
  ];
  const out = bundle(w, steps);
  assert.deepStrictEqual(out.steps.map(kinds), [["accept"], ["accept"], ["getflight", "fly"]]);
});

test("two accepts and a turn-in at one NPC become one step with three lines in the planner's order", () => {
  const w = testWorld();
  w.npc(10, 100, 30, 50); w.npc(11, 100, 31, 50); w.npc(12, 100, 40, 50); w.npc(20, 100, 60, 30, "");
  w.kill(1, 10, 20, 100); w.kill(2, 10, 20, 100); w.kill(3, 10, 20, 100); w.kill(4, 11, 20, 100); w.kill(5, 12, 20, 100);
  const out = bundle(w, [
    { action: "turnin", quest: 3, at: M(100, 30, 50), npc: 10 },
    { action: "accept", quest: 1, at: M(100, 30, 50), npc: 10 },
    { action: "accept", quest: 2, at: M(100, 30, 50), npc: 10 },
    { action: "accept", quest: 4, at: M(100, 31, 50), npc: 11 },   // 10 yards away: still the same step
    { action: "accept", quest: 5, at: M(100, 40, 50), npc: 12 },   // 100 yards away: a step of its own
  ]);
  assert.strictEqual(out.steps.length, 2);
  const [first, second] = out.steps;
  assert.deepStrictEqual(first.lines, [
    { kind: "turnin", quest: 3, npc: 10 },
    { kind: "accept", quest: 1, npc: 10 },
    { kind: "accept", quest: 2, npc: 10 },
    { kind: "accept", quest: 4, npc: 11 },
  ]);
  assert.deepStrictEqual(first.at, { zone: 100, x: 30, y: 50, r: RADIUS.npc });
  assert.strictEqual(first.id, "t3.a1.a2.a4");
  assert.deepStrictEqual(first.targets, { friend: [10, 11] });
  assert.deepStrictEqual(kinds(second), ["accept"]);
  assert.deepStrictEqual(out.origin, [[0, 1, 2, 3], [4]]);
});

test("objectives of two quests within 150 yards become one step, one line per objective index", () => {
  const w = testWorld();
  w.npc(10, 100, 30, 50); w.npc(20, 100, 60, 30, ""); w.npc(21, 100, 61, 30, ""); w.npc(22, 100, 90, 90, "");
  w.db.items.set(300, { id: 300, name: "Pelt", npcDrops: [21], objectDrops: [] });
  w.quest(5, { startedBy: [[10]], finishedBy: [[10]], zoneOrSort: 100, objectives: [[[20, null, 0], [21, null, 0]]] });
  w.quest(6, { startedBy: [[10]], finishedBy: [[10]], zoneOrSort: 100, objectives: { "3": [[300, null, 0]] } });
  w.quest(7, { startedBy: [[10]], finishedBy: [[10]], zoneOrSort: 100, objectives: [[[22, null, 0]]] });
  const out = bundle(w, [
    { action: "objective", quest: 5, at: M(100, 60, 30), npc: 20 },
    { action: "objective", quest: 6, at: M(100, 61, 40), npc: 21, item: 300 },  // 100 yards from the first
    { action: "objective", quest: 7, at: M(100, 90, 90), npc: 22 },             // 670 yards: a step of its own
  ]);
  assert.strictEqual(out.steps.length, 2);
  const step = out.steps[0];
  assert.deepStrictEqual(step.lines.map((l) => [l.quest, l.index]), [[5, 1], [5, 2], [6, 1]]);
  assert.strictEqual(step.lines[0].npc, 20);
  assert.strictEqual(step.lines[1].npc, 21);
  assert.strictEqual(step.lines[2].item, 300);
  assert.deepStrictEqual(step.at, { zone: 100, x: 60, y: 30, r: RADIUS.area });
  assert.strictEqual(step.id, "o5.o6");
  assert.deepStrictEqual(out.steps[1].lines, [{ kind: "objective", quest: 7, index: 1, npc: 22 }]);
  assert.deepStrictEqual(out.origin, [[0, 1], [2]]);
});

test("a quest without objectives gives one objective line with index 1", () => {
  const w = testWorld();
  w.npc(10, 100, 30, 50);
  w.errand(8, 10, 10, 100, { triggerEnd: ["Explore the hill", { 100: [[50, 50]] }] });
  const out = bundle(w, [{ action: "objective", quest: 8, at: M(100, 50, 50) }]);
  assert.deepStrictEqual(out.steps[0].lines, [{ kind: "objective", quest: 8, index: 1 }]);
});

test("an objective farther than 30 yards from the step's place carries its own place with r 40", () => {
  const w = testWorld();
  w.npc(10, 100, 30, 50); w.npc(20, 100, 60, 30, ""); w.npc(21, 100, 62, 30, ""); w.npc(22, 100, 66, 30, "");
  w.kill(5, 10, 20, 100); w.kill(6, 10, 21, 100); w.kill(7, 10, 22, 100);
  const out = bundle(w, [
    { action: "objective", quest: 5, at: M(100, 60, 30), npc: 20 },
    { action: "objective", quest: 6, at: M(100, 62, 30), npc: 21 },  // 20 yards: no place of its own
    { action: "objective", quest: 7, at: M(100, 66, 30), npc: 22 },  // 60 yards
  ]);
  assert.strictEqual(out.steps.length, 1);
  const [l5, l6, l7] = out.steps[0].lines;
  assert.strictEqual(l5.at, undefined);
  assert.strictEqual(l6.at, undefined);
  assert.deepStrictEqual(l7.at, { zone: 100, x: 66, y: 30, r: RADIUS.area });
});

test("getflight then fly at one flight master is one step", () => {
  const w = testWorld();
  const out = bundle(w, [
    { action: "getflight", node: 1, at: M(100, 20, 50), npc: 901 },
    { action: "fly", from: 1, to: 3, at: M(100, 20, 50) },
    { action: "fly", from: 3, to: 2, at: M(200, 30, 50) },
  ]);
  assert.strictEqual(out.steps.length, 2);
  assert.deepStrictEqual(out.steps[0].lines, [{ kind: "getflight", node: 1, npc: 901 }, { kind: "fly", from: 1, to: 3 }]);
  assert.deepStrictEqual(out.steps[0].at, { zone: 100, x: 20, y: 50, r: RADIUS.flightmaster });
  assert.strictEqual(out.steps[0].id, "f1.y1-3");
  assert.deepStrictEqual(out.steps[1].lines, [{ kind: "fly", from: 3, to: 2 }]);
  assert.deepStrictEqual(out.steps[1].at, { zone: 200, x: 30, y: 50, r: RADIUS.flightmaster });
});

test("travel, transport and hearth are steps of their own with the radius of their kind", () => {
  const w = testWorld();
  w.npc(10, 100, 22, 51); w.kill(1, 10, 10, 100);
  const out = bundle(w, [
    { action: "accept", quest: 1, at: M(100, 22, 51), npc: 10 },
    { action: "sethearth", at: M(100, 22, 50), npc: 800 },
    { action: "travel", at: M(100, 50, 89) },
    { action: "travel", at: M(100, 50, 89) },
    { action: "transport", kind: "boat", at: M(100, 50, 90), to: M(400, 50, 10) },
    { action: "hearth", to: M(100, 22, 50) },
    { action: "grind", level: 5, at: M(100, 30, 30) },
    { action: "travel", at: M(200, 0, 0) },
  ]);
  assert.deepStrictEqual(out.steps.map(kinds), [["accept", "sethearth"], ["goto"], ["goto"], ["transport"], ["hearth"], ["grind"], ["goto"]]);
  const [inn, go, again, boat, hearth, grind, zoneOnly] = out.steps;
  assert.deepStrictEqual(inn.lines[1], { kind: "sethearth", npc: 800 });
  assert.strictEqual(inn.id, "a1.b@100");
  assert.deepStrictEqual(go.at, { zone: 100, x: 50, y: 89, r: RADIUS.goto });
  assert.deepStrictEqual(go.lines, [{ kind: "goto", at: { zone: 100, x: 50, y: 89, r: RADIUS.goto } }]);
  assert.strictEqual(go.id, "g100@100");
  assert.strictEqual(again.id, "g100@100#2");
  assert.deepStrictEqual(boat.at, { zone: 100, x: 50, y: 90, r: RADIUS.dock });
  assert.deepStrictEqual(boat.lines, [{ kind: "transport", mode: "boat", at: { zone: 100, x: 50, y: 90, r: RADIUS.dock }, to: { zone: 400, x: 50, y: 10 } }]);
  assert.strictEqual(boat.id, "x400");
  assert.deepStrictEqual(hearth.lines, [{ kind: "hearth", to: { zone: 100, x: 22, y: 50 } }]);
  assert.strictEqual(hearth.at, undefined, "a hearth is cast where the player stands");
  assert.strictEqual(hearth.id, "h");
  assert.deepStrictEqual(grind.lines, [{ kind: "grind", level: 5 }]);
  assert.deepStrictEqual(grind.at, { zone: 100, x: 30, y: 30 }, "a grind place never completes on arrival");
  assert.strictEqual(grind.id, "l5@100");
  assert.deepStrictEqual(zoneOnly.at, { zone: 200, x: 0, y: 0, r: RADIUS.zoneOnly });
  assert.strictEqual(zoneOnly.lines[0].at.r, RADIUS.zoneOnly);
});

test("an unknown transport kind is refused", () => {
  const w = testWorld();
  assert.throws(() => bundle(w, [{ action: "transport", kind: "balloon", at: M(100, 50, 90), to: M(400, 50, 10) }]), /balloon/);
});

test("a class step never shares a step with a shared one", () => {
  const w = testWorld();
  w.npc(10, 100, 30, 50); w.npc(20, 100, 60, 30, "");
  w.kill(1, 10, 20, 100); w.kill(40, 10, 20, 100, { requiredClasses: ROGUE }); w.kill(41, 10, 20, 100, { requiredClasses: ROGUE });
  const rogue = { class: "ROGUE" };
  const out = bundle(w, [
    { action: "accept", quest: 1, at: M(100, 30, 50), npc: 10 },
    { action: "accept", quest: 40, at: M(100, 30, 50), npc: 10, when: rogue },
    { action: "accept", quest: 41, at: M(100, 30, 50), npc: 10, when: rogue },
    { action: "turnin", quest: 1, at: M(100, 30, 50), npc: 10 },
  ]);
  // the shared turn-in at the same NPC joins the shared step (hub order); the class lines keep their own step
  assert.deepStrictEqual(out.steps.map((s) => s.lines.map((l) => l.quest)), [[1, 1], [40, 41]]);
  assert.strictEqual(out.steps[0].when, undefined);
  assert.deepStrictEqual(out.steps[1].when, { class: "ROGUE" });
  for (const s of out.steps) for (const l of s.lines) assert.strictEqual(l.when, undefined, "the step carries the condition, not its lines");
});

test("minLevel is the highest required level of the step's accepts", () => {
  const w = testWorld();
  w.npc(10, 100, 30, 50); w.npc(11, 100, 50, 50); w.npc(20, 100, 60, 30, "");
  w.kill(1, 10, 20, 100, { requiredLevel: 3 }); w.kill(2, 10, 20, 100, { requiredLevel: 5 }); w.kill(3, 10, 20, 100, { requiredLevel: 1 });
  w.kill(4, 11, 20, 100, { requiredLevel: 1 });
  const out = bundle(w, [
    { action: "accept", quest: 1, at: M(100, 30, 50), npc: 10 },
    { action: "accept", quest: 2, at: M(100, 30, 50), npc: 10 },
    { action: "accept", quest: 3, at: M(100, 30, 50), npc: 10 },
    { action: "accept", quest: 4, at: M(100, 50, 50), npc: 11 },
  ]);
  assert.strictEqual(out.steps[0].minLevel, 5);
  assert.strictEqual(out.steps[1].minLevel, undefined, "a level 1 quest sets no minimum");
});

test("accept lines require the quest's prerequisites that the route hands in before them", () => {
  const w = testWorld();
  w.npc(10, 100, 30, 50); w.npc(11, 100, 50, 50); w.npc(20, 100, 60, 30, "");
  w.kill(1, 10, 20, 100); w.kill(2, 10, 20, 100);
  w.kill(3, 11, 20, 100, { preQuestGroup: [1, 2] });
  w.kill(4, 11, 20, 100, { preQuestSingle: [1, 99] });   // either one: 99 is another race's version the route never takes
  w.kill(5, 11, 20, 100);
  const out = bundle(w, [
    { action: "turnin", quest: 1, at: M(100, 30, 50), npc: 10 },
    { action: "turnin", quest: 2, at: M(100, 30, 50), npc: 10 },
    { action: "accept", quest: 3, at: M(100, 50, 50), npc: 11 },
    { action: "accept", quest: 4, at: M(100, 50, 50), npc: 11 },
    { action: "accept", quest: 5, at: M(100, 50, 50), npc: 11 },
  ]);
  const [a3, a4, a5] = out.steps[1].lines;
  assert.deepStrictEqual(a3.requires, [1, 2]);
  assert.deepStrictEqual(a4.requires, [1]);
  assert.strictEqual(a5.requires, undefined);
});

test("an accept line requires an 'any one of' prerequisite handed in earlier in its own step", () => {
  const w = testWorld();
  w.npc(10, 100, 30, 50); w.npc(20, 100, 60, 30, "");
  w.kill(1, 10, 20, 100);
  w.kill(2, 10, 20, 100, { preQuestSingle: [1, 99] });
  w.kill(3, 10, 20, 100, { preQuestSingle: [4] });          // 4 is handed in after the accept: not before it
  w.kill(4, 10, 20, 100);
  const out = bundle(w, [
    { action: "turnin", quest: 1, at: M(100, 30, 50), npc: 10 },
    { action: "accept", quest: 2, at: M(100, 30, 50), npc: 10 },
    { action: "accept", quest: 3, at: M(100, 30, 50), npc: 10 },
    { action: "turnin", quest: 4, at: M(100, 30, 50), npc: 10 },
  ]);
  assert.strictEqual(out.steps.length, 1);
  assert.strictEqual(out.steps[0].id, "t1.a2.a3.t4");
  const [, a2, a3] = out.steps[0].lines;
  assert.deepStrictEqual(a2.requires, [1]);
  assert.strictEqual(a3.requires, undefined);
});

test("a kill credit objective names the credited creature when it is one that counts, else the first", () => {
  const w = testWorld();
  w.npc(10, 100, 30, 50);
  w.npc(51, 100, 60, 30, "", "Webbed Captive"); w.npc(52, 100, 61, 30, "", "Adventurer"); w.npc(53, 100, 62, 30, "", "Credit Dummy");
  // QuestieDB objectives slot 5: [[creatures that count], credited creature, text, icon]
  w.quest(1, { startedBy: [[10]], finishedBy: [[10]], zoneOrSort: 100, objectives: [[], [], [], [], [[[51, 52], 52, null, 0]]] });
  w.quest(2, { startedBy: [[10]], finishedBy: [[10]], zoneOrSort: 100, objectives: [[], [], [], [], [[[51, 52], 53, null, 0]]] });
  const out = bundle(w, [
    { action: "objective", quest: 1, at: M(100, 60, 30) },
    { action: "objective", quest: 2, at: M(100, 60, 30) },
  ]);
  const [o1, o2] = out.steps[0].lines;
  assert.strictEqual(o1.npc, 52, "the credited creature is in the list: the quest log names it");
  assert.strictEqual(o2.npc, 51, "the credited creature is a stand-in outside the list: the first that counts");
  assert.deepStrictEqual(out.steps[0].targets.enemy.slice().sort(), [51, 52], "only the creatures that count are targets");
});

test("items and targets come from the quest data and only carry named IDs", () => {
  const w = testWorld();
  w.npc(10, 100, 30, 50);
  w.db.npcs.set(19, { id: 19, name: "", friendly: "", spawns: { 100: [[60, 30]] } }); // no name in the data
  w.npc(20, 100, 60, 30, "");
  w.db.items.set(300, { id: 300, name: "Strange Letter", npcDrops: [], objectDrops: [] });
  w.db.items.set(301, { id: 301, name: "Torch", npcDrops: [], objectDrops: [] });
  w.db.items.set(303, { id: 303, name: "Ward", npcDrops: [], objectDrops: [] });
  w.db.items.set(304, { id: 304, name: "", npcDrops: [], objectDrops: [] });
  w.quest(1, { startedBy: [[10], [], [300]], finishedBy: [[10]], zoneOrSort: 100, sourceItemId: 301, requiredSourceItems: [302, 303, 304],
    objectives: [[[19, null, 0], [20, null, 0]]] });
  // eight creatures drop the item of quest 2, at 10, 20, ... 80 yards from the step's place, listed farthest first
  const droppers = [];
  for (let k = 8; k >= 1; k--) { w.npc(30 + k, 100, 60 + k, 30, ""); droppers.push(30 + k); }
  w.db.items.set(310, { id: 310, name: "Fang", npcDrops: droppers, objectDrops: [] });
  w.quest(2, { startedBy: [[10]], finishedBy: [[10]], zoneOrSort: 100, objectives: { "3": [[310, null, 0]] } });
  const out = bundle(w, [
    { action: "accept", quest: 1, at: M(100, 30, 50), npc: 10 },
    { action: "objective", quest: 1, at: M(100, 60, 30), npc: 20 },
    { action: "objective", quest: 2, at: M(100, 61, 30), npc: 31, item: 310 },
  ]);
  const [accept, objectives] = out.steps;
  assert.deepStrictEqual(accept.items, [300, 301, 303], "starter item, source item, required source items; unknown and unnamed left out");
  assert.deepStrictEqual(accept.targets, { friend: [10] });
  assert.deepStrictEqual(objectives.items, [301, 303], "the step's quests' usable items, not the objective's own item");
  // the kill creature (20; 19 has no name) and the six nearest droppers
  assert.deepStrictEqual(objectives.targets, { enemy: [20, 31, 32, 33, 34, 35] });
  assert.strictEqual(objectives.lines[0].npc, undefined, "an unnamed creature is not named on its line");
});

// A town with three quests, a rogue quest layered in, and a trip to Eastland: a real planner route.
function plannedRoute() {
  const w = testWorld();
  w.npc(10, 100, 30, 50); w.npc(11, 100, 31, 50); w.npc(12, 100, 30, 51); w.npc(13, 100, 32, 50);
  w.npc(20, 100, 60, 30, ""); w.npc(21, 100, 70, 50, ""); w.npc(22, 100, 60, 70, ""); w.npc(23, 100, 62, 32, "");
  w.kill(1, 10, 20, 100); w.kill(2, 11, 21, 100); w.kill(3, 12, 22, 100);
  w.kill(40, 13, 23, 100, { requiredClasses: ROGUE });
  w.npc(14, 200, 50, 50); w.npc(24, 200, 55, 55, "");
  w.kill(60, 14, 24, 200, { requiredLevel: 2 });
  const graph = w.graph();
  const shared = planRoute(w.db, w.human(), { graph, inns: w.inns, maxLevel: 4 });
  const route = layerClasses(w.db, shared, [w.human("WARRIOR"), w.human("ROGUE")], { graph }).route;
  return { w, route };
}

test("step ids are stable across two runs and unique in a list", () => {
  const ids = () => { const { w, route } = plannedRoute(); return bundleSteps(w.db, route).steps.map((s) => s.id); };
  const a = ids(), b = ids();
  assert.deepStrictEqual(a, b);
  assert.strictEqual(new Set(a).size, a.length, a.join(" "));
  for (const id of a) assert.match(id, /^[A-Za-z0-9.\-+@#:]+$/);
});

// The name is the plan's. "Exactly" is each action's identity, order, origin and the first place of each step; the other
// places of a step are only checked to be within OWN_PLACE_YARDS (a line that close carries no place of its own), and an
// objective's npc/object/item is the quest's own objective rather than the planner's pick.
test("flatten(bundleSteps(route).steps) gives back the route's actions exactly", () => {
  const { w, route } = plannedRoute();
  assert.ok(route.steps.length >= 10, `${route.steps.length} actions`);
  assert.ok(route.steps.some((s) => s.when), "the route has class steps");
  const { steps, origin } = bundleSteps(w.db, route);
  assert.ok(steps.length < route.steps.length, "bundling makes fewer steps than actions");
  // every action is in exactly one step; the hub order may move talk actions within a hub, nothing else
  const order = origin.flat();
  assert.deepStrictEqual([...order].sort((x, y) => x - y), route.steps.map((_, i) => i), "every action is in exactly one step");
  assert.deepStrictEqual(order, hubOrder(w.db, route.steps), "the steps follow the hub order");
  const back = [];
  flatten(steps).forEach((a, j) => { back[order[j]] = a; });
  // What an action is: everything but its place, and for an objective the creature, object or item the planner
  // pointed at (a step lists every objective of the quest instead).
  const what = (a) => {
    const { at, npc, object, item, ...rest } = a;
    return a.action === "objective" ? rest : { ...rest, npc, object, item };
  };
  const clean = (o) => JSON.parse(JSON.stringify(o));
  assert.deepStrictEqual(clean(back.map(what)), clean(route.steps.map(what)));
  // the places: the first action of each step stands exactly where it did, every other within OWN_PLACE_YARDS
  const P = (p) => toPoint(w.db, p.zone, p.x, p.y);
  origin.forEach((list, i) => list.forEach((k, j) => {
    const want = route.steps[k], got = back[k];
    if (!want.at) { assert.strictEqual(got.at, undefined); return; }
    if (j === 0) assert.deepStrictEqual(got.at, want.at, `step ${steps[i].id}`);
    else assert.ok(distance(P(got.at), P(want.at)) <= OWN_PLACE_YARDS, `step ${steps[i].id} action ${k}`);
  }));
  // an objective names one of its quest's objectives
  back.forEach((a, k) => {
    if (a.action !== "objective") return;
    const q = w.db.quests.get(a.quest);
    const named = [...q.objectives.npcs, ...q.objectives.objects, ...q.objectives.items];
    if (named.length) assert.ok(named.includes(a.npc) || named.includes(a.object) || named.includes(a.item), `action ${k}`);
  });
});

test("every bundled step passes checkRoute3's step rules", () => {
  const { w, route } = plannedRoute();
  const { steps } = bundleSteps(w.db, route);
  const sections = [];
  for (let i = 0; i < steps.length; i += 400) {
    sections.push({ id: `s${sections.length + 1}`, name: "1-4 Westland", group: "Alliance", subgroup: "1-20", minLevel: 1, zone: 100, steps: steps.slice(i, i + 400), next: [] });
  }
  sections[0].start = true;
  sections.forEach((s, i) => { if (i + 1 < sections.length) s.next = [{ section: sections[i + 1].id }]; });
  assert.strictEqual(checkRoute3({ format: 3, race: "Human", faction: "Alliance", sections }), null);
});
