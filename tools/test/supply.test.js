// Noir Guides, GPLv3. See LICENSE.
// The last look before a grind step (planner/supply.js), on the small world of test/world.js.
const test = require("node:test");
const assert = require("node:assert");
const { testWorld } = require("./world");
const { planRoute } = require("../planner/plan");
const { validateRoute } = require("../planner/validate");
const { zoneOrder } = require("../planner/measure");
const { buildContext, plannerGraph } = require("../planner/context");
const { makePolicy } = require("../planner/policy");
const { errand, supplyZone } = require("../planner/supply");
const { CHOICES: C } = require("../planner/tuning");

const run = (w, options = {}) => {
  const ch = w.human(), graph = w.graph();
  const route = planRoute(w.db, ch, { graph, inns: w.inns, ...options });
  const checked = validateRoute(w.db, route, ch, { graph, inns: w.inns });
  const names = route.steps.map((s) => s.action + (s.quest !== undefined ? ":" + s.quest : ""));
  return { route, checked, names, order: zoneOrder(route, ch) };
};
// Westland: one kill quest, most of level 1 as the planner counts XP. Eastland: an NPC with letters for Westland.
function letters(w, count) {
  w.npc(10, 100, 30, 50); w.npc(20, 100, 40, 50, ""); w.kill(1, 10, 20, 100);
  w.npc(30, 200, 20, 50);
  for (let n = 0; n < count; n++) w.errand(70 + n, 30, 10, 200);
}
// what planner/supply.js reads of the planner, for a character standing at the Westland quest giver
function viewOf(w, state) {
  const ch = w.human();
  const ctx = buildContext(w.db, ch, plannerGraph(w.graph()), w.inns);
  const st = { level: 1, xp: 0, log: new Map(), done: new Set(), hopped: new Set(), barren: new Set(), zone: 100, relaxed: true, errands: true,
    pos: w.P(100, 30, 50), ...state };
  return { ctx, policy: makePolicy(ctx), st, secondsAt: () => 60 };
}

test("an errand is the visit and what it leads to: quests picked up in one zone and handed in in the next", () => {
  const w = testWorld();
  letters(w, 2);
  const view = viewOf(w, { done: new Set([1]) });
  assert.deepStrictEqual(errand(view, 200), { xp: 220, visits: 2 }, "two letters of 110 XP: picked up in Eastland, handed in in Westland");
  assert.deepStrictEqual(errand(view, 100), { xp: 0, visits: 0 }, "nothing to do in Westland: no errand");
  assert.strictEqual(view.st.log.size, 0, "played on a copy: the character's own log is untouched");
});
test("the errand's zone is chosen when the errand reaches the next level or a visit of it gives enough of the level", () => {
  const w = testWorld();
  letters(w, 1);
  // one letter, 66 XP as the planner counts it over two visits: under SUPPLY_MIN_SHARE of level 1's 400 a visit
  assert.ok((110 * 0.6) / 2 < C.SUPPLY_MIN_SHARE * 400);
  assert.strictEqual(supplyZone(viewOf(w, { done: new Set([1]), xp: 300 })), 0, "66 XP short of the level by 34: the grind step is the shorter way");
  assert.strictEqual(supplyZone(viewOf(w, { done: new Set([1]), xp: 340 })), 200, "the letter reaches level 2: no grind step is needed");
  assert.strictEqual(supplyZone(viewOf(w, { done: new Set([1]), xp: 340, barren: new Set([200]) })), 0, "not a zone found spent");
  const many = testWorld();
  letters(many, 3);
  assert.strictEqual(supplyZone(viewOf(many, { done: new Set([1]) })), 200, "three letters: each visit gives a quarter of the level");
});
test("a quest out to another zone and back is taken on an errand, and only then", () => {
  const w = testWorld();
  w.npc(10, 100, 30, 50); w.npc(40, 400, 60, 30, "");
  w.kill(8, 10, 40, 100); // given and handed in in Westland, fought overseas in Farshore
  const i = (view) => view.ctx.info.get(8);
  const plain = viewOf(w, { errands: false });
  assert.strictEqual(i(plain).kind, "far");
  assert.strictEqual(plain.policy.wanted(i(plain), plain.st), false, "not even when relaxed");
  const out = viewOf(w, {});
  assert.strictEqual(out.policy.wanted(i(out), out.st), true);
  assert.deepStrictEqual(errand(out, 100), { xp: 510, visits: 3 }, "taken in Westland, fought in Farshore, handed in in Westland");
  assert.strictEqual(supplyZone(out), 100, "the errand starts where the quest is given");
});
test("planned: letters waiting next door are fetched instead of a grind step, a single letter is not worth the way", () => {
  const w = testWorld();
  letters(w, 3);
  const { names, order, checked } = run(w, { maxLevel: 2 });
  assert.deepStrictEqual(checked.errors, []);
  assert.strictEqual(checked.endLevel, 2);
  assert.ok(!names.includes("grind"), names.join(" "));
  assert.deepStrictEqual(order, [100, 200, 100]);
  for (const quest of [70, 71, 72]) assert.ok(names.indexOf("accept:" + quest) > names.indexOf("turnin:1") && names.includes("turnin:" + quest), `letter ${quest}`);

  const one = testWorld();
  letters(one, 1);
  const lone = run(one, { maxLevel: 2 });
  assert.deepStrictEqual(lone.checked.errors, []);
  assert.ok(lone.names.includes("grind") && !lone.names.includes("accept:70"), lone.names.join(" "));
  assert.deepStrictEqual(lone.order, [100]);
});
