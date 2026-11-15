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
const { PACE, mobXp, yieldAt } = require("../lib/xp");

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
  const ctx = buildContext(w.db, ch, plannerGraph(w.db, w.graph()), w.inns);
  const st = { level: 1, xp: 0, log: new Map(), done: new Set(), hopped: new Set(), barren: new Set(), zone: 100, relaxed: true, errands: true,
    pos: w.P(100, 30, 50), ...state };
  return { ctx, policy: makePolicy(ctx), st, secondsAt: () => 60 };
}

test("an errand is the visit and what it leads to: quests picked up in one zone and handed in in the next", () => {
  const w = testWorld();
  letters(w, 2);
  const view = viewOf(w, { done: new Set([1]) });
  // each visit is two talks (lib/xp.js TALK_SECONDS) and the way to the zone's hub, a minute in this view
  const talks = 2 * PACE.TALK_SECONDS;
  assert.deepStrictEqual(errand(view, 200), { xp: 220, visits: 2, seconds: (talks + 60) + (talks + 60) }, "two letters of 110 XP: picked up in Eastland, handed in in Westland");
  assert.deepStrictEqual(errand(view, 100), { xp: 0, visits: 0, seconds: 0 }, "nothing to do in Westland: no errand");
  assert.strictEqual(view.st.log.size, 0, "played on a copy: the character's own log is untouched");
});
test("an errand is judged by its XP a second against a grind step's, and is taken at any rate when it reaches the next level", () => {
  const w = testWorld();
  letters(w, 1);
  const grind = mobXp(1, 1) / PACE.KILL_SECONDS; // what a second of a grind step gives at level 1
  // one letter is 110 XP, 66 as the planner counts it, for two visits: with 300 of level 1's 400 XP it does not
  // reach level 2, so its rate decides (SUPPLY_RATE times the grind step's; at 0 every errand that gives XP is taken)
  const short = viewOf(w, { done: new Set([1]), xp: 300 });
  const one = errand(short, 200);
  assert.deepStrictEqual([one.xp, one.visits], [110, 2]);
  assert.ok(300 + one.xp * yieldAt(1) < 400);
  assert.strictEqual(supplyZone(short), one.xp / one.seconds >= C.SUPPLY_RATE * grind ? 200 : 0, `${one.xp} XP in ${one.seconds} s against ${grind} XP a second of grinding`);
  // with a way so long that the letter gives less a second than SUPPLY_RATE asks, the grind step is the quicker way
  const slow = { ...short, secondsAt: () => 1e9 };
  assert.ok(errand(slow, 200).xp / errand(slow, 200).seconds < 1e-6);
  assert.strictEqual(supplyZone(slow), C.SUPPLY_RATE > 0 ? 0 : 200);
  // ... unless the letter reaches level 2: then no grind step is needed at all, whatever the way
  assert.strictEqual(supplyZone(viewOf(w, { done: new Set([1]), xp: 340 })), 200, "the letter reaches level 2: no grind step is needed");
  assert.strictEqual(supplyZone({ ...viewOf(w, { done: new Set([1]), xp: 340 }), secondsAt: () => 1e9 }), 200, "at any rate");
  assert.strictEqual(supplyZone(viewOf(w, { done: new Set([1]), xp: 340, barren: new Set([200]) })), 0, "not a zone found spent");
  assert.strictEqual(supplyZone({ ...viewOf(w, { done: new Set([1]), xp: 340 }), secondsAt: () => Infinity }), 0, "only a zone a way leads to");
  assert.strictEqual(supplyZone(viewOf(w, { done: new Set([1, 70]), xp: 340 })), 0, "nothing to fetch: no errand");
});
test("of two errands the one with more XP a second is chosen, not the one with more XP a visit", () => {
  const w = testWorld();
  letters(w, 2);
  // Lonely Isle: one kill quest, done in a single visit. More XP than the two letters, and far more a visit, but its
  // eight fights take longer than the letters' two short ways
  w.npc(60, 300, 50, 50); w.npc(61, 300, 55, 50, ""); w.kill(9, 60, 61, 300);
  const view = viewOf(w, { done: new Set([1]) });
  const mail = errand(view, 200), hunt = errand(view, 300);
  assert.deepStrictEqual([mail.xp, mail.visits, hunt.xp, hunt.visits], [220, 2, 510, 1]);
  assert.ok(hunt.xp / hunt.visits > mail.xp / mail.visits && mail.xp / mail.seconds > hunt.xp / hunt.seconds, `${mail.seconds} s for the letters, ${hunt.seconds} s for the hunt`);
  assert.strictEqual(supplyZone(view), 200);
  assert.strictEqual(supplyZone({ ...view, st: { ...view.st, barren: new Set([200]) } }), 300, "the hunt is an errand too, when the letters are gone");
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
  // the talk in Westland and the way there; the eight fights in Farshore, the walk a quest takes in its zone and a
  // way of unknown length (Farshore has no quest giver to measure it to); the talk in Westland and the way back
  const seconds = (PACE.TALK_SECONDS + 60) + (8 * PACE.KILL_SECONDS + C.QUEST_WALK_SECONDS + C.SUPPLY_UNKNOWN_WAY) + (PACE.TALK_SECONDS + 60);
  assert.deepStrictEqual(errand(out, 100), { xp: 510, visits: 3, seconds }, "taken in Westland, fought in Farshore, handed in in Westland");
  assert.strictEqual(supplyZone(out), 100, "the errand starts where the quest is given");
});
test("planned: letters waiting next door are fetched before any grind step, a single letter too", () => {
  const w = testWorld();
  letters(w, 3);
  const { names, order, checked } = run(w, { maxLevel: 2 });
  assert.deepStrictEqual(checked.errors, []);
  assert.strictEqual(checked.endLevel, 2);
  // no grind step but the last step to the cap, which the character passes: the level is made by the letters
  assert.strictEqual(names.indexOf("grind"), names.length - 1, names.join(" "));
  assert.strictEqual(checked.levels[names.length - 1], 2, "at the cap before the last step");
  assert.strictEqual(checked.seconds, checked.clocks[names.length - 1], "which costs no time");
  assert.deepStrictEqual(order, [100, 200, 100]);
  for (const quest of [70, 71, 72]) assert.ok(names.indexOf("accept:" + quest) > names.indexOf("turnin:1") && names.includes("turnin:" + quest), `letter ${quest}`);

  const one = testWorld();
  letters(one, 1);
  // one letter does not reach level 2. It is fetched all the same, and only what it leaves of the level is ground:
  // the grind step is the last step, after the letter is handed in
  const lone = run(one, { maxLevel: 2 });
  assert.deepStrictEqual(lone.checked.errors, []);
  assert.strictEqual(lone.checked.endLevel, 2);
  assert.deepStrictEqual(lone.order, [100, 200, 100]);
  assert.deepStrictEqual(lone.names.filter((n) => n === "grind"), ["grind"], lone.names.join(" "));
  assert.ok(lone.names.indexOf("turnin:70") > lone.names.indexOf("turnin:1") && lone.names.indexOf("grind") > lone.names.indexOf("turnin:70"), lone.names.join(" "));
  assert.strictEqual(lone.names[lone.names.length - 1], "grind");
  // and it is a shorter grind step than without the letter: the clock says so
  const none = testWorld();
  letters(none, 0);
  const bare = run(none, { maxLevel: 2 });
  assert.deepStrictEqual(bare.order, [100]);
  const ground = (r) => r.checked.seconds - r.checked.clocks[r.names.indexOf("grind")]; // the grind step is the last
  assert.ok(ground(lone) < ground(bare), `${ground(lone)} s of grinding with the letter, ${ground(bare)} s without`);
});
