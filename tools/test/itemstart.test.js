// Noir Guides, GPLv3. See LICENSE.
// Quests started by an item found in the open world (the item drops from a creature or is looted from an object;
// using it offers the quest), from the quest data to the simulator. The encoding: the accept action and the accept
// line name the item (`item`), and their `npc` or `object` is what drops it, never someone to talk to.
const test = require("node:test");
const assert = require("node:assert");
const { testWorld, at } = require("./world");
const { startPoint, levelingQuests } = require("../lib/quests");
const { planRoute } = require("../planner/plan");
const { validateRoute } = require("../planner/validate");
const { validate3 } = require("../planner/validate3");
const { checkRoute3 } = require("../planner/format3");
const { emitRoute3 } = require("../planner/emit3");
const { emitNames } = require("../planner/emit");
const { stepText } = require("../planner/texts");
const { bundleSteps, flatten, RADIUS } = require("../planner/bundle");
const { buildFacts, parseRoute, simulate } = require("../sim_all");

const M = (zone, x, y) => ({ zone, x, y });
const route2 = (steps) => ({ id: "alliance-human", format: 2, race: "Human", faction: "Alliance", steps });
const bundle = (w, steps) => bundleSteps(w.db, route2(steps), steps.map(() => 1));
const item = (w, id, name, npcDrops = [], objectDrops = []) => w.db.items.set(id, { id, name, npcDrops, objectDrops });

// A hub (NPC 10) with a field of looters (25) that drop a letter (300), which starts quest 4, handed in at the hub.
function letterWorld() {
  const w = testWorld();
  w.npc(10, 100, 30, 50, "AH", "Marshal");
  w.npc(25, 100, 60, 30, "", "Looter");
  item(w, 300, "Strange Letter", [25]);
  w.quest(4, { startedBy: [[], [], [300]], finishedBy: [[10]], zoneOrSort: 100 });
  return w;
}

test("the quest data: a quest started by a dropped item starts where the item drops, and is a leveling quest", () => {
  const w = letterWorld();
  const start = startPoint(w.db, w.db.quests.get(4), "Alliance");
  assert.deepStrictEqual([start.npc, start.item, start.object], [25, 300, undefined]);
  assert.deepStrictEqual([start.point.zone, start.point.x, start.point.y], [100, 60, 30]);
  assert.deepStrictEqual(levelingQuests(w.db, w.human()).map((q) => q.id), [4]);
  // an item nothing in the open world drops gives no start: the quest stays out of the pool
  item(w, 301, "Lost Page");
  w.quest(5, { startedBy: [[], [], [301]], finishedBy: [[10]], zoneOrSort: 100 });
  assert.strictEqual(startPoint(w.db, w.db.quests.get(5), "Alliance"), null);
  assert.deepStrictEqual(levelingQuests(w.db, w.human()).map((q) => q.id), [4]);
});

test("the planner's accept step of such a quest names the dropping creature and the item", () => {
  const w = letterWorld();
  w.npc(20, 100, 40, 50, ""); w.kill(1, 10, 20, 100);
  const ch = w.human();
  const graph = w.graph();
  const route = planRoute(w.db, ch, { graph, inns: w.inns, maxLevel: 3 });
  const accept = route.steps.find((s) => s.action === "accept" && s.quest === 4);
  assert.ok(accept, `quest 4 is accepted: ${route.steps.map((s) => `${s.action}:${s.quest || ""}`).join(" ")}`);
  assert.deepStrictEqual(accept, { action: "accept", quest: 4, at: M(100, 60, 30), npc: 25, item: 300 });
  const plain = route.steps.find((s) => s.action === "accept" && s.quest === 1);
  assert.strictEqual(plain.item, undefined, "an accept at a quest giver names no item");
  assert.deepStrictEqual(validateRoute(w.db, route, ch, { graph, inns: w.inns }).errors, []);
});

test("bundling: the line carries the item, the creature is an enemy target and no friend, the place is an area", () => {
  const w = letterWorld();
  const out = bundle(w, [
    { action: "accept", quest: 4, at: M(100, 60, 30), npc: 25, item: 300 },
    { action: "turnin", quest: 4, at: M(100, 30, 50), npc: 10 },
  ]);
  const [accept, turnin] = out.steps;
  assert.deepStrictEqual(accept, {
    id: "a4", at: { zone: 100, x: 60, y: 30, r: RADIUS.area },
    lines: [{ kind: "accept", quest: 4, npc: 25, item: 300 }],
    items: [300], targets: { enemy: [25] },
  });
  assert.deepStrictEqual(turnin.targets, { friend: [10] });
});

test("bundling: an item looted from an object names the object, and gives no target", () => {
  const w = letterWorld();
  w.object(500, 100, 70, 30, "Crate");
  item(w, 310, "Sealed Orders", [], [500]);
  w.quest(6, { startedBy: [[], [], [310]], finishedBy: [[10]], zoneOrSort: 100 });
  const start = startPoint(w.db, w.db.quests.get(6), "Alliance");
  assert.deepStrictEqual([start.object, start.item, start.npc], [500, 310, undefined]);
  const [step] = bundle(w, [{ action: "accept", quest: 6, at: M(100, 70, 30), object: 500, item: 310 }]).steps;
  assert.deepStrictEqual(step, { id: "a6", at: { zone: 100, x: 70, y: 30, r: RADIUS.area },
    lines: [{ kind: "accept", quest: 6, object: 500, item: 310 }], items: [310] });
});

test("bundling: a drop place is no quest hub: a giver 70 yards away has its own step, an objective 50 yards away shares it", () => {
  const w = letterWorld();
  w.npc(11, 100, 67, 30, "AH", "Scout");      // a quest giver 70 yards from the looters
  w.npc(26, 100, 60, 35, "", "Boar");          // creatures 50 yards from them
  w.kill(2, 11, 26, 100);
  const out = bundle(w, [
    { action: "accept", quest: 4, at: M(100, 60, 30), npc: 25, item: 300 },
    { action: "accept", quest: 2, at: M(100, 67, 30), npc: 11 },
    { action: "objective", quest: 2, at: M(100, 60, 35), npc: 26 },
  ]);
  assert.deepStrictEqual(out.steps.map((s) => s.id), ["a4", "a2", "o2"], "two givers that far apart would be one hub step");
  const near = bundle(w, [
    { action: "accept", quest: 2, at: M(100, 67, 30), npc: 11 },
    { action: "objective", quest: 2, at: M(100, 60, 35), npc: 26 },
    { action: "accept", quest: 4, at: M(100, 60, 30), npc: 25, item: 300 },
  ]);
  assert.deepStrictEqual(near.steps.map((s) => s.id), ["a2", "o2.a4"]);
  const shared = near.steps[1];
  assert.deepStrictEqual(shared.targets, { enemy: [26, 25] }, "the objective's creature and the dropper, no friend");
  assert.deepStrictEqual(shared.lines[1], { kind: "accept", quest: 4, npc: 25, item: 300, at: { zone: 100, x: 60, y: 30, r: RADIUS.area } },
    "its own place, 50 yards from the step's, with the radius of an area");
});

test("bundling: a quest with a giver and a starter item is a plain accept at the giver", () => {
  const w = letterWorld();
  w.quest(7, { startedBy: [[10], [], [300]], finishedBy: [[10]], zoneOrSort: 100 });
  const start = startPoint(w.db, w.db.quests.get(7), "Alliance");
  assert.deepStrictEqual([start.npc, start.item], [10, undefined]);
  const [step] = bundle(w, [{ action: "accept", quest: 7, at: M(100, 30, 50), npc: 10 }]).steps;
  assert.deepStrictEqual(step.lines, [{ kind: "accept", quest: 7, npc: 10 }]);
  assert.deepStrictEqual(step.targets, { friend: [10] });
  assert.deepStrictEqual(step.items, [300], "the item still goes on a button for a player who finds it");
});

// The format 3 route of the letter world: the drop step, then the hand-in.
function letterRoute(w) {
  const actions = [
    { action: "accept", quest: 4, at: M(100, 60, 30), npc: 25, item: 300 },
    { action: "turnin", quest: 4, at: M(100, 30, 50), npc: 10 },
  ];
  const steps = bundle(w, actions).steps;
  const route = { id: "alliance-human", format: 3, race: "Human", faction: "Alliance", sections: [
    { id: "human-01-02-westland", name: "1-2 Westland", group: "Alliance", subgroup: "1-20", minLevel: 1, maxLevel: 10, zone: 100, start: true, next: [], steps },
  ] };
  return { actions, steps, route };
}

test("format 3: the step is valid, is written with its item, reads back, and flattens to the action it came from", () => {
  const w = letterWorld();
  const { actions, steps, route } = letterRoute(w);
  assert.strictEqual(checkRoute3({ format: 3, race: route.race, faction: route.faction, sections: route.sections }), null);
  const text = emitRoute3(route);
  assert.ok(text.includes('{ kind = "accept", quest = 4, item = 300, npc = 25 },'), text);
  assert.deepStrictEqual(parseRoute(text), route);
  assert.deepStrictEqual(flatten(steps), actions, "the item comes back on the accept action");
  const ch = w.human();
  assert.deepStrictEqual(validate3(w.db, route, ch, { graph: w.graph(), inns: w.inns }).errors, []);
  const names = emitNames(w.db, [route]);
  assert.ok(names.includes('Noir.Data.items[300] = "Strange Letter"'), "the item is named for the engine");
  assert.ok(names.includes('Noir.Data.npcs[25] = "Looter"'), "and so is the creature");
});

test("step texts: a creature that drops a quest's item is nobody to stand by", () => {
  const w = letterWorld();
  w.npc(27, 100, 60, 70, "", "Wolf");
  w.kill(3, 10, 27, 100);
  const [drop] = bundle(w, [{ action: "accept", quest: 4, at: M(100, 60, 30), npc: 25, item: 300 }]).steps;
  const [objective] = bundle(w, [{ action: "objective", quest: 3, at: M(100, 60, 70), npc: 27 }]).steps;
  const text = stepText(w.db, objective, { previous: drop });
  assert.match(text, / south of your last stop\.$/);
  assert.doesNotMatch(text, /Looter/);
});

test("the simulator: the world knows which item starts which quest, and the dropper offers nothing", () => {
  const w = letterWorld();
  const { route } = letterRoute(w);
  const f = buildFacts(w.db, w.graph(), w.inns, route, w.human());
  assert.deepStrictEqual(f.items, { 300: { name: "Strange Letter", quest: 4 } });
  assert.deepStrictEqual(f.npcs[25], { name: "Looter", offers: [], ends: [] });
  assert.deepStrictEqual(f.npcs[10].ends, [4]);
  assert.deepStrictEqual(f.flat[0], { action: "accept", quest: 4, at: M(100, 60, 30), npc: 25, item: 300, section: "human-01-02-westland", step: "a4" });
  // a route without such a quest has no items
  const plain = { ...route, sections: [{ ...route.sections[0], steps: [{ id: "g100@100", lines: [{ kind: "goto", at: { ...at(100, 30, 50), r: 20 } }] }] }] };
  assert.strictEqual(buildFacts(w.db, w.graph(), w.inns, plain, w.human()).items, undefined);
});

test("the simulator: the real addon plays the drop step, fresh and as a joiner who took the quest before", () => {
  const w = letterWorld();
  const { route } = letterRoute(w);
  const f = buildFacts(w.db, w.graph(), w.inns, route, w.human(), { withRoute: true });
  const r = simulate(f, { register: true });
  assert.deepStrictEqual([r.finished, r.stuck, r.cannot, r.unexplained, r.errors, r.slash, r.offScreen], [true, [], [], [], [], 0, []]);
  assert.strictEqual(r.itemStarts, 1, "the quest was started from its item");
  const j = simulate(f, { register: true, join: 1 });
  assert.deepStrictEqual([j.finished, j.stuck, j.cannot, j.unexplained, j.errors], [true, [], [], [], []]);
  assert.strictEqual(j.placement.inside, true, `placed at action ${j.placement.landed}`);
  assert.strictEqual(j.itemStarts, undefined, "the joiner had the quest already");
});
