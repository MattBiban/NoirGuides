// Noir Guides, GPLv3. See LICENSE.
const test = require("node:test");
const assert = require("node:assert");
const { testWorld, at } = require("./world");
const { safeLevels, havens, dangerousWalks, MAX_DANGEROUS_WALKS, STILL_YARDS } = require("../planner/danger");
const { plannerGraph } = require("../planner/context");
const { travelPlan } = require("../lib/travel");
const { CHOICES } = require("../planner/tuning");

// Westland (100) is a quiet zone of level 1 quests; Eastland (200), next door, is open country of level 20 to 24.
// Every map is 1000 yards square: one percent is 10 yards.
function wildEast() {
  const w = testWorld();
  w.npc(10, 100, 30, 50); w.npc(11, 100, 30, 60, ""); w.kill(1, 10, 11, 100);
  w.npc(20, 200, 50, 50); w.herd(21, 200, 60, 50);
  [20, 20, 22, 24, 24].forEach((level, k) => w.kill(50 + k, 20, 21, 200, { questLevel: level, requiredLevel: level - 2 }));
  return w;
}
const human = { faction: "Alliance", cls: "WARRIOR" };
const levels = (steps, level) => steps.map(() => level);

test("the thresholds are the planner's, and no dangerous walk is let through", () => {
  assert.strictEqual(CHOICES.DANGER_LEVELS, 5);
  assert.strictEqual(CHOICES.ARRIVAL_YARDS, 150);
  assert.strictEqual(MAX_DANGEROUS_WALKS, 0);
  assert.ok(STILL_YARDS > 0 && STILL_YARDS <= 10);
});
test("an open zone is safe from DANGER_LEVELS under the low end of its creatures; a quiet zone always", () => {
  const w = wildEast();
  const safe = safeLevels(w.db);
  assert.strictEqual(safe.get(200), 20 - CHOICES.DANGER_LEVELS);
  assert.strictEqual(safe.has(100), false, "no herd: not open country");
  assert.strictEqual(safe.has(400), false, "no quests filed there: no levels to go by");
});
test("the planner's graph keeps the rule: no way on foot into the zone below its level, the same way from it on", () => {
  const w = wildEast();
  const raw = w.graph(), graph = plannerGraph(w.db, raw);
  const from = w.P(100, 50, 50), to = w.P(200, 50, 50);
  const traveller = (level) => ({ faction: "Alliance", level, flights: new Set(), hearth: null });
  assert.strictEqual(travelPlan(w.db, graph, traveller(14), from, to).seconds, Infinity);
  assert.ok(travelPlan(w.db, graph, traveller(15), from, to).seconds < Infinity);
  assert.ok(travelPlan(w.db, raw, traveller(14), from, to).seconds < Infinity, "the validator's graph has no such rule");
});
test("a walk into, inside or out of a dangerous zone is counted, with the zone and the level", () => {
  const w = wildEast();
  const graph = w.graph();
  const steps = [
    { action: "accept", quest: 1, at: at(100, 30, 50) },
    { action: "travel", at: at(200, 10, 50) },            // over the border
    { action: "accept", quest: 50, at: at(200, 50, 50) }, // on inside the zone
    { action: "travel", at: at(100, 90, 50) },            // and out again
    { action: "objective", quest: 1, at: at(100, 30, 60) },
  ];
  const found = dangerousWalks(w.db, graph, { steps }, human, levels(steps, 14));
  assert.deepStrictEqual(found, [1, 2, 3].map((step) => ({ step, level: 14, from: step === 1 ? 100 : 200, to: step === 3 ? 100 : 200, zone: 200, min: 20 })));
  assert.deepStrictEqual(dangerousWalks(w.db, graph, { steps }, human, levels(steps, 15)), [], "five levels under is close enough");
  // the level is the one at each step: the walk out at 15 is fine
  assert.deepStrictEqual(dangerousWalks(w.db, graph, { steps }, human, [14, 14, 14, 15, 15]).map((d) => d.step), [1, 2]);
});
test("flying in and standing where the flight lands is no walk; walking on from there is", () => {
  const w = wildEast();
  const graph = w.graph();
  const steps = [
    { action: "getflight", node: 1, at: at(100, 20, 50), npc: 901 },
    { action: "fly", from: 1, to: 2, at: at(100, 20, 50) },        // lands at East Camp, Eastland (80, 50)
    { action: "getflight", node: 2, at: at(200, 80.1, 50), npc: 902 }, // a yard off: the place is rounded
    { action: "fly", from: 2, to: 1, at: at(200, 80, 50) },
    { action: "accept", quest: 1, at: at(100, 30, 50) },
  ];
  assert.deepStrictEqual(dangerousWalks(w.db, graph, { steps }, human, levels(steps, 10)), []);
  const on = [...steps.slice(0, 3), { action: "accept", quest: 50, at: at(200, 50, 50) }];
  assert.deepStrictEqual(dangerousWalks(w.db, graph, { steps: on }, human, levels(on, 10)).map((d) => [d.step, d.from, d.to]), [[3, 200, 200]]);
});
test("the steps of another class are not this character's walks", () => {
  const w = wildEast();
  const graph = w.graph();
  const steps = [
    { action: "accept", quest: 1, at: at(100, 30, 50) },
    { action: "travel", at: at(200, 10, 50), when: { class: "ROGUE" } },
    { action: "travel", at: at(100, 90, 50), when: { class: "ROGUE" } },
    { action: "objective", quest: 1, at: at(100, 30, 60) },
  ];
  assert.deepStrictEqual(dangerousWalks(w.db, graph, { steps }, human, levels(steps, 10)), []);
  assert.deepStrictEqual(dangerousWalks(w.db, graph, { steps }, { faction: "Alliance", cls: "ROGUE" }, levels(steps, 10)).map((d) => d.step), [1, 2]);
});
test("a haven: around the end of a transport that asks for a quest a walk is safe, a step past it is not", () => {
  // the boat off the Sky Isle asks for quest 77; here it lands in the middle of Eastland
  const w = testWorld((src) => { src.transports.links.find((l) => l.id === "sky").b = { zone: 200, x: 50, y: 50 }; });
  w.npc(20, 200, 55, 50); w.herd(21, 200, 60, 50);
  [20, 20, 22, 24, 24].forEach((level, k) => w.kill(50 + k, 20, 21, 200, { questLevel: level, requiredLevel: level - 2 }));
  const graph = w.graph();
  assert.deepStrictEqual(havens(graph).map((h) => [h.point.zone, h.yards]), [[500, CHOICES.ARRIVAL_YARDS], [200, CHOICES.ARRIVAL_YARDS]]);
  const steps = [
    { action: "transport", kind: "boat", at: at(500, 50, 50), to: at(200, 50, 50) },
    { action: "accept", quest: 50, at: at(200, 55, 50) },  // 50 yards from where the boat lands
    { action: "travel", at: at(200, 80, 50) },             // 250 yards on: out of the haven
  ];
  assert.deepStrictEqual(dangerousWalks(w.db, graph, { steps }, human, levels(steps, 8)).map((d) => d.step), [2]);
  // and the planner's graph agrees
  const planner = plannerGraph(w.db, graph);
  const traveller = { faction: "Alliance", level: 8, flights: new Set(), hearth: null };
  assert.ok(travelPlan(w.db, planner, traveller, w.P(200, 50, 50), w.P(200, 55, 50)).seconds < Infinity);
  assert.strictEqual(travelPlan(w.db, planner, traveller, w.P(200, 50, 50), w.P(200, 80, 50)).seconds, Infinity);
});
