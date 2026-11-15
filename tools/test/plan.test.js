// Noir Guides, GPLv3. See LICENSE.
const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const path = require("path");
const { fixtureDb } = require("./fixture");
const { testWorld } = require("./world");
const { normalizeQuest } = require("../lib/db");
const { character, RACES } = require("../lib/characters");
const { levelingQuests } = require("../lib/quests");
const { zoneBands } = require("../planner/zones");
const { planRoute } = require("../planner/plan");
const { validateRoute } = require("../planner/validate");
const { zoneOrder, measureRoute, neededGrinds, planLevels } = require("../planner/measure");
const { leftBehind, MAX_LEFT_BEHIND } = require("../planner/leftbehind");
const { levelGap, MAX_ABOVE, MAX_BELOW_SHARE } = require("../planner/levelgap");
const { dangerousWalks, MAX_DANGEROUS_WALKS } = require("../planner/danger");
const { MAX_ZONE_SHARE, MAX_TRAVEL_SHARE, MAX_GRIND_STEPS } = require("../planner/report");
const { grindSpotAt } = require("../planner/grindspots");
const { zoneLevels } = require("../lib/xp");
const { CHOICES: C, gateLevel } = require("../planner/tuning");

const human = () => { RACES.Human.startArea = 1000; return character("Human", "WARRIOR"); };
const index = (route) => (action, quest) => route.steps.findIndex((s) => s.action === action && s.quest === quest);
// objectives per trip out: the objective steps of a route over its rows of objectives with no accept or turn-in between
const objectivesPerRun = (route) => {
  let objectives = 0, runs = 0, last = null;
  for (const s of route.steps) {
    if (s.action !== "objective" && s.action !== "accept" && s.action !== "turnin") continue;
    if (s.action === "objective") { objectives++; if (last !== "objective") runs++; }
    last = s.action;
  }
  return runs ? objectives / runs : 0;
};
const names = (route) => route.steps.map((s) => s.action + (s.quest !== undefined ? ":" + s.quest : s.node !== undefined ? ":" + s.node : ""));

test("zone bands come from quest levels", () => {
  const db = fixtureDb();
  const bands = zoneBands(db, levelingQuests(db, human()));
  assert.deepStrictEqual(bands.map((b) => b.zone), [1000, 2000]);
  assert.strictEqual(bands[0].name, "Testvale");
  assert.ok(bands[1].min >= 3);
});
test("a route accepts before it does objectives and turns in after", () => {
  const db = fixtureDb();
  const route = planRoute(db, human(), { maxLevel: 10 });
  const at = index(route);
  for (const q of [10, 11, 12, 20]) {
    assert.ok(at("accept", q) >= 0, `accepts ${q}`);
    assert.ok(at("accept", q) < at("objective", q), `objective after accept for ${q}`);
    assert.ok(at("objective", q) < at("turnin", q), `turn-in after objective for ${q}`);
  }
  assert.ok(at("turnin", 10) < at("accept", 12), "a follow-up waits for its prerequisite");
  assert.ok(at("accept", 21) > at("turnin", 20));
  assert.strictEqual(at("accept", 13), -1, "never the other faction's quest");
  assert.strictEqual(at("accept", 14), -1, "never a quest far above the level cap");
});
test("it travels between zones and records it", () => {
  const db = fixtureDb();
  const route = planRoute(db, human(), { maxLevel: 10 });
  const travel = route.steps.findIndex((s) => s.action === "travel" && s.at.zone === 2000);
  assert.ok(travel > 0);
  assert.ok(travel < route.steps.findIndex((s) => s.action === "accept" && s.quest === 20));
  assert.ok(route.stats.seconds > 0);
  assert.strictEqual(route.id, "alliance-human");
  assert.strictEqual(route.format, 2);
});
test("planning is deterministic", () => {
  const a = JSON.stringify(planRoute(fixtureDb(), human(), { maxLevel: 10 }));
  const b = JSON.stringify(planRoute(fixtureDb(), human(), { maxLevel: 10 }));
  assert.strictEqual(a, b);
  const plan = () => { const w = testWorld(); town(w); return JSON.stringify(planRoute(w.db, w.human(), { graph: w.graph(), inns: w.inns, maxLevel: 4 })); };
  assert.strictEqual(plan(), plan());
});
test("every step with a place carries percent coordinates in its zone, and no step is in the old format", () => {
  const route = planRoute(fixtureDb(), human(), { maxLevel: 10 });
  for (const s of route.steps) {
    assert.strictEqual(s.zone, undefined, "format 2 has no zone key on a step");
    if (s.action !== "hearth") assert.ok(s.at, `${s.action} has a place`);
    for (const p of [s.at, s.to].filter((v) => v && typeof v === "object")) {
      assert.ok(p.zone === 1000 || p.zone === 2000);
      assert.ok(p.x >= 0 && p.x <= 100 && p.y >= 0 && p.y <= 100);
    }
  }
});
test("an objective over a zone border is done from here when it is near this zone's tasks", () => {
  const db = fixtureDb();
  db.quests.clear();
  // two zones side by side, each 3,000 by 2,000 yards
  db.maps.set(1000, { area: 1000, uiMap: 1, minX: 0, minY: 0, maxX: 3000, maxY: 2000 });
  db.maps.set(2000, { area: 2000, uiMap: 2, minX: 0, minY: 2000, maxX: 3000, maxY: 4000 });
  const npc = (id, zone, x, y, friendly) => db.npcs.set(id, { id, name: "Npc " + id, friendly, spawns: { [zone]: [[x, y]] } });
  npc(50, 1000, 75, 50, "AH"); // the giver
  npc(51, 2000, 95, 50, "");   // over the border: 1,600 yards from the giver, 1,217 from npc 52
  npc(52, 1000, 5, 10, "");    // in the giver's zone, 1,844 yards from the giver
  const quest = (id, mob) => db.quests.set(id, normalizeQuest(id, { name: "Quest " + id, startedBy: [[50]], finishedBy: [[50]],
    requiredLevel: 1, questLevel: 1, objectives: [[[mob, null, 0]]], zoneOrSort: 1000 }));
  quest(1, 51); quest(2, 52);
  db.eraQuestIds.add(1).add(2);
  const route = planRoute(db, human(), { maxLevel: 10 });
  const at = index(route);
  assert.ok(at("objective", 1) >= 0 && at("objective", 2) >= 0);
  // planner v2 crosses a border once per visit: the work on this side comes first (here either order is as long)
  assert.ok(at("objective", 2) < at("objective", 1), "the one over the border waits until this side is done");
  assert.strictEqual(route.steps[at("objective", 1)].at.zone, 2000);
  assert.ok(at("turnin", 1) >= 0 && at("turnin", 2) >= 0);
  assert.ok(!route.steps.some((s) => s.action === "travel"), "no travel step for a hop over the border");
});

// ---------------------------------------------------------------------------------------------------------------
// Planner v2, on the small world of test/world.js. One percent of a map is 10 yards.
const run = (w, ch, options = {}) => {
  ch = ch || w.human();
  const graph = w.graph();
  const route = planRoute(w.db, ch, { graph, inns: w.inns, ...options });
  const checked = validateRoute(w.db, route, ch, { graph, inns: w.inns });
  return { route, checked, at: index(route), order: zoneOrder(route, ch), names: names(route) };
};
// A town in Westland with three kill quests, their creatures in three fields around it.
function town(w) {
  w.npc(10, 100, 30, 50); w.npc(11, 100, 31, 50); w.npc(12, 100, 30, 51);
  w.npc(20, 100, 60, 30, ""); w.npc(21, 100, 70, 50, ""); w.npc(22, 100, 60, 70, "");
  w.kill(1, 10, 20, 100); w.kill(2, 11, 21, 100); w.kill(3, 12, 22, 100);
}

test("the plan and the independent replay agree: no errors, the same level", () => {
  const w = testWorld();
  town(w);
  const { route, checked } = run(w, null, { maxLevel: 3 });
  assert.deepStrictEqual(checked.errors, []);
  assert.strictEqual(route.stats.endLevel, checked.endLevel);
  assert.ok(Math.abs(route.stats.seconds - checked.seconds) < 1, `the planner's clock ${route.stats.seconds} and the validator's ${checked.seconds}`);
  assert.strictEqual(route.stats.quests, 3);
});
test("hub batching: everything at a hub is accepted, the objectives are one loop, and the player returns once", () => {
  const w = testWorld();
  town(w);
  const { names, checked } = run(w, null, { maxLevel: 3 });
  assert.deepStrictEqual(checked.errors, []);
  const quests = names.filter((n) => /^(accept|objective|turnin)/.test(n));
  assert.deepStrictEqual(quests.slice(0, 3).map((n) => n.split(":")[0]), ["accept", "accept", "accept"]);
  assert.deepStrictEqual(quests.slice(3, 6).map((n) => n.split(":")[0]), ["objective", "objective", "objective"]);
  assert.deepStrictEqual(quests.slice(6, 9).map((n) => n.split(":")[0]), ["turnin", "turnin", "turnin"]);
  // the loop goes round the fields in order, not out and back across the town
  assert.ok(["objective:1,objective:2,objective:3", "objective:3,objective:2,objective:1"].includes(quests.slice(3, 6).join(",")), quests.join(" "));
});
test("zone commitment: a zone is finished before the next one is entered", () => {
  const w = testWorld();
  town(w);
  // the same again in Eastland, and an errand that carries the player over
  w.npc(30, 200, 50, 50); w.npc(40, 200, 60, 30, ""); w.npc(41, 200, 70, 50, ""); w.npc(42, 200, 60, 70, "");
  w.kill(4, 30, 40, 200); w.kill(5, 30, 41, 200); w.kill(6, 30, 42, 200);
  w.errand(7, 10, 30, 100);
  const { order, at, checked, route } = run(w, null, { maxLevel: 4 });
  assert.deepStrictEqual(checked.errors, []);
  assert.deepStrictEqual(order, [100, 200], "one change of zone");
  assert.ok(at("accept", 7) < at("objective", 1), "the errand is picked up with the rest of the hub");
  assert.ok(at("turnin", 3) < at("turnin", 7) && at("turnin", 2) < at("turnin", 7), "and handed in when the route gets there");
  const travel = route.steps.findIndex((s) => s.action === "travel");
  assert.deepStrictEqual(route.steps[travel].at.zone, 200);
  assert.strictEqual(route.steps.filter((s) => s.action === "travel").length, 1);
});
test("a quest that needs a trip to another zone and back is left alone until the only other thing to do is grind", () => {
  const world = () => {
    const w = testWorld();
    town(w);
    w.npc(40, 400, 60, 30, "");
    w.kill(8, 10, 40, 100); // given and handed in in Westland, fought overseas in Farshore
    return w;
  };
  // the town's three quests reach level 2: with the cap there the route is done, and the trip is never made
  const done = run(world(), null, { maxLevel: 2 });
  assert.deepStrictEqual(done.checked.errors, []);
  assert.strictEqual(done.checked.endLevel, 2);
  assert.strictEqual(done.at("accept", 8), -1, "not taken with the town's quests, though its giver is one of theirs");
  assert.deepStrictEqual(done.order, [100]);
  // with the cap further on nothing else is left at level 2, and the trip comes before any grind step (an errand,
  // planner/supply.js): the quest is taken when the town is finished, not with the town's quests
  const { at, order, checked, names } = run(world(), null, { maxLevel: 4 });
  assert.deepStrictEqual(checked.errors, []);
  for (const quest of [1, 2, 3]) assert.ok(at("accept", 8) > at("turnin", quest), `quest 8 waits for the hand-in of quest ${quest}`);
  assert.ok(at("accept", 8) < at("objective", 8) && at("objective", 8) < at("turnin", 8), names.join(" "));
  assert.deepStrictEqual(order, [100, 400, 100], "out to Farshore and back");
  assert.ok(!names.includes("grind"), "the fights of a quest, not of a grind step: " + names.join(" "));
});
test("cost-based choice: the next zone is the one that takes less time to reach, not the one nearer in a straight line", () => {
  // Northland (700) lies north of Westland. Eastland's pass is moved to Westland's far corner: Eastland's quest is
  // 600 yards away in a straight line and 1,082 by the pass; Northland's is 800 yards either way.
  const build = (pass) => {
    const w = testWorld((src, db) => {
      db.areas.set(700, { id: 700, name: "Northland", parent: 0, continent: 0 });
      db.maps.set(700, { area: 700, uiMap: 9700, minX: 1000, minY: 0, maxX: 2000, maxY: 1000 });
      src.taxiNodes.length = 0; src.taxiPaths.length = 0; src.flightMasters.length = 0; // no flight point to walk to first
      src.transports.passes = [{ a: 100, b: 200, at: pass, source: "map", verified: false }, { a: 100, b: 700, at: { zone: 100, x: 70, y: 0 }, source: "map", verified: false }];
    });
    w.npc(10, 100, 70, 50); w.npc(20, 100, 70, 48, "");
    w.kill(1, 10, 20, 100);
    w.npc(30, 200, 30, 50); w.npc(31, 200, 31, 50, ""); w.kill(2, 30, 31, 200);
    w.npc(40, 700, 70, 70); w.npc(41, 700, 71, 70, ""); w.kill(3, 40, 41, 700);
    return w;
  };
  const far = run(build({ zone: 100, x: 100, y: 95 }), null, { maxLevel: 4 });
  assert.deepStrictEqual(far.checked.errors, []);
  assert.deepStrictEqual(far.order, [100, 700, 200]);
  // with the pass straight ahead Eastland is 600 yards by road as well, and comes first
  const straight = run(build({ zone: 100, x: 100, y: 50 }), null, { maxLevel: 4 });
  assert.deepStrictEqual(straight.order, [100, 200, 700]);
});
test("look-ahead: the nearest task is not taken first when that means crossing the zone twice", () => {
  const w = testWorld();
  // the hub in the middle; one field 100 yards west, three in a row to the east at 150, 300 and 450 yards, and
  // a second giver at the end of the row whose quest is fought back at the first field
  w.npc(10, 100, 50, 50); w.npc(11, 100, 95, 50);
  w.npc(20, 100, 40, 50, ""); w.npc(21, 100, 65, 50, ""); w.npc(22, 100, 80, 50, ""); w.npc(23, 100, 94, 50, "");
  w.kill(1, 10, 20, 100); w.kill(2, 10, 21, 100); w.kill(3, 10, 22, 100); w.kill(4, 10, 23, 100);
  const { names, checked } = run(w, null, { maxLevel: 4 });
  assert.deepStrictEqual(checked.errors, []);
  const objectives = names.filter((n) => n.startsWith("objective")).join(",");
  // nearest first would go west (100), then east to the end (550) and back (450): 1,100 yards. East first and the
  // west field on the way home is 450 + 550 + 100 = 1,100 as well; what must not happen is west, near east, far east
  // taken out of order with a second crossing of the hub
  assert.ok(["objective:1,objective:2,objective:3,objective:4", "objective:4,objective:3,objective:2,objective:1"].includes(objectives), objectives);
});
test("no hand-in left behind: the objective next to a hub with a ready hand-in is done in the same loop, before the next town", () => {
  const w = testWorld();
  // the hub at 30,50 with two quests, one fought 100 yards south and one 100 yards east, on the way to a second town
  // 600 yards east that offers a third. The best order of the five nearest ends the loop at the hub, so it used to go
  // to the far town first and leave quest 1's hand-in behind, with the east field taken on the way home. The far town
  // is within GATHER_SECONDS, so its quest is taken before the loop starts; the two fields by the hub are still one
  // loop that ends with both hand-ins.
  w.npc(10, 100, 30, 50); w.npc(11, 100, 90, 50);
  w.npc(20, 100, 30, 60, ""); w.npc(21, 100, 40, 50, ""); w.npc(22, 100, 95, 60, "");
  w.kill(1, 10, 20, 100); w.kill(2, 10, 21, 100); w.kill(3, 11, 22, 100);
  const { route, names, checked } = run(w, null, { maxLevel: 3 });
  assert.deepStrictEqual(checked.errors, []);
  const quests = names.filter((n) => /^(accept|objective|turnin)/.test(n)).join(" ");
  assert.strictEqual(quests, "accept:1 accept:2 accept:3 objective:3 turnin:3 objective:2 objective:1 turnin:1 turnin:2");
  assert.deepStrictEqual(leftBehind(w.db, route), []);
});
test("one loop: the quest givers around are visited before the first objective", () => {
  const w = testWorld();
  // two givers 400 yards apart, each with a quest fought in a field between them. Nearest first would do the first
  // quest out and back before the second giver is spoken to: two trips with one objective each.
  w.npc(10, 100, 20, 50); w.npc(11, 100, 60, 50);
  w.npc(20, 100, 40, 40, ""); w.npc(21, 100, 45, 60, "");
  w.kill(1, 10, 20, 100); w.kill(2, 11, 21, 100);
  const { route, names, checked } = run(w, null, { maxLevel: 3 });
  assert.deepStrictEqual(checked.errors, []);
  assert.strictEqual(names.filter((n) => /^(accept|objective|turnin)/.test(n)).join(" "), "accept:1 accept:2 objective:2 objective:1 turnin:1 turnin:2");
  assert.strictEqual(objectivesPerRun(route), 2);
  assert.deepStrictEqual(leftBehind(w.db, route), []);
});
test("one loop: a hand-in away from the objectives waits until they are done", () => {
  const w = testWorld();
  // three fields in a row east of the hub; the first quest is handed in at a camp 360 yards off the row. The camp
  // is not on the way to the next field, so it comes after the last one, not between two objectives.
  w.npc(10, 100, 20, 50); w.npc(12, 100, 50, 30);
  w.npc(20, 100, 40, 50, ""); w.npc(21, 100, 60, 50, ""); w.npc(22, 100, 80, 50, "");
  w.quest(1, { startedBy: [[10]], finishedBy: [[12]], objectives: [[[20, null, 0]]], zoneOrSort: 100 });
  w.kill(2, 10, 21, 100); w.kill(3, 10, 22, 100);
  const { route, names, checked } = run(w, null, { maxLevel: 4 });
  assert.deepStrictEqual(checked.errors, []);
  const quests = names.filter((n) => /^(accept|objective|turnin)/.test(n)).map((n) => n.split(":")[0]).join(" ");
  assert.strictEqual(quests, "accept accept accept objective objective objective turnin turnin turnin");
  assert.deepStrictEqual(leftBehind(w.db, route), []);
});
test("one loop: an order that breaks off a row of objectives for a quest giver has to save RUN_SECONDS", () => {
  const { nextTask } = require("../planner/session");
  const { CHOICES } = require("../planner/tuning");
  // a quest giver 70 seconds away and a field at 200, 150 seconds from each other
  const tasks = (field, apart) => ({ list: [{ kind: "accept", id: 1, cost: 70 }, { kind: "objective", id: 2, cost: field }], between: () => apart });
  const near = tasks(200, 150), far = tasks(CHOICES.RUN_SECONDS * 2, CHOICES.RUN_SECONDS * 2);
  // before the loop the giver is on the way: giver, field is the shorter order
  assert.strictEqual(nextTask(near.list, near.between).id, 1);
  // in the middle of a row of objectives the same giver waits: the field first is 130 seconds more, not RUN_SECONDS
  assert.strictEqual(nextTask(near.list, near.between, null, true).id, 2);
  // unless the row goes on so far away that coming back for the giver costs more than breaking it off
  assert.strictEqual(nextTask(far.list, far.between, null, true).id, 1);
});
test("format 2 travel: a flight point is learned before it is flown from, and a transport carries the route overseas", () => {
  const w = testWorld();
  town(w);
  w.npc(50, 400, 50, 12); w.npc(51, 400, 52, 14, "");
  w.kill(9, 50, 51, 400);
  w.errand(7, 10, 50, 100);
  const { route, checked, order } = run(w, null, { maxLevel: 5 });
  assert.deepStrictEqual(checked.errors, []);
  const boat = route.steps.find((s) => s.action === "transport");
  assert.deepStrictEqual(boat, { action: "transport", kind: "boat", at: { zone: 100, x: 50, y: 90 }, to: { zone: 400, x: 50, y: 10 } });
  assert.deepStrictEqual(order, [100, 400]);
  const learned = new Set();
  for (const s of route.steps) {
    if (s.action === "getflight") { assert.ok(!learned.has(s.node), "learned once"); learned.add(s.node); assert.ok(s.npc > 0); }
    if (s.action === "fly") assert.ok(learned.has(s.from) && learned.has(s.to), `flight ${s.from} to ${s.to}`);
  }
  assert.ok(learned.has(1), "the flight point in the town's zone is fetched");
  assert.deepStrictEqual(route.stats.links, [{ id: "boat-west-far", name: "West to Far", kind: "boat", assumed: ["route"] }]);
});
test("a transport whose users are assumed is never planned", () => {
  const w = testWorld((src) => { src.transports.links = src.transports.links.filter((l) => l.id === "goblin"); });
  town(w);
  w.npc(50, 400, 20, 88); w.errand(7, 10, 50, 100);
  const { at, checked, order } = run(w, null, { maxLevel: 4 });
  assert.deepStrictEqual(checked.errors, []);
  assert.strictEqual(at("accept", 7), -1, "the only way there is the boat nobody is known to board");
  assert.deepStrictEqual(order, [100]);
});
test("the hearthstone is bound at a hub's inn when that saves time, and used to come back", () => {
  const w = testWorld();
  // the hub stands at the inn; its creatures are at the far end of the zone
  w.npc(10, 100, 22, 52);
  w.npc(20, 100, 95, 20, ""); w.npc(21, 100, 97, 50, ""); w.npc(22, 100, 95, 80, "");
  w.kill(1, 10, 20, 100); w.kill(2, 10, 21, 100); w.kill(3, 10, 22, 100);
  const { names, route, checked } = run(w, null, { maxLevel: 4 });
  assert.deepStrictEqual(checked.errors, []);
  const bind = names.indexOf("sethearth"), home = names.indexOf("hearth");
  assert.ok(bind > 0 && bind < names.indexOf("objective:1") , names.join(" "));
  assert.deepStrictEqual(route.steps[bind], { action: "sethearth", at: { zone: 100, x: 22, y: 50 }, npc: 800 });
  assert.ok(home > names.lastIndexOf("objective:2") && home < names.indexOf("turnin:1"), names.join(" "));
  assert.deepStrictEqual(route.steps[home], { action: "hearth", to: { zone: 100, x: 22, y: 50 } });
  // with the creatures next door the inn is not worth the stop
  const near = testWorld();
  near.npc(10, 100, 22, 52); near.npc(20, 100, 25, 52, ""); near.kill(1, 10, 20, 100);
  assert.ok(!run(near, null, { maxLevel: 4 }).names.includes("sethearth"));
});
test("pacing: a grind step bridges one level to the next quests, and the route goes on to the cap while a later level opens any", () => {
  const world = (third) => {
    const w = testWorld();
    w.npc(10, 100, 30, 50); w.npc(20, 100, 40, 50, "");
    w.kill(1, 10, 20, 100);                                    // 400 XP of kills and 110 of reward, 306 of it counted
                                                               // (lib/xp.js yieldAt): short of level 2
    w.kill(2, 10, 20, 100, { requiredLevel: 2, questLevel: 2 }); // opens a level later, and is short of level 3
    if (third) w.kill(3, 10, 20, 100, { requiredLevel: third, questLevel: third });
    return w;
  };
  const shown = (r) => r.names.filter((n) => n !== "getflight:1");
  // a quest for every level: each is followed by the grind step to the next, and the last level is ground to the cap
  const each = run(world(3), null, { maxLevel: 4 });
  assert.deepStrictEqual(each.checked.errors, []);
  assert.deepStrictEqual(shown(each), ["accept:1", "objective:1", "turnin:1", "grind", "accept:2", "objective:2", "turnin:2", "grind", "accept:3", "objective:3", "turnin:3", "grind"]);
  assert.deepStrictEqual(each.route.steps.find((s) => s.action === "grind"), { action: "grind", level: 2, at: { zone: 100, x: 30, y: 50 } });
  assert.deepStrictEqual(each.route.steps.filter((s) => s.action === "grind").map((s) => s.level), [2, 3, 4], "each the rest of one level");
  assert.deepStrictEqual([each.route.stats.endLevel, each.checked.endLevel], [4, 4]);
  // no quest at any later level: nothing to grind towards, and the route ends where its quests end
  const none = run(world(0), null, { maxLevel: 10 });
  assert.deepStrictEqual(none.checked.errors, []);
  assert.deepStrictEqual(shown(none), ["accept:1", "objective:1", "turnin:1", "grind", "accept:2", "objective:2", "turnin:2"]);
  assert.deepStrictEqual([none.route.stats.endLevel, none.checked.endLevel], [2, 2]);
  // the next quest seven levels on: the route does not end short of the cap. It grinds a level a step to the quest
  // and does it. That is six grind steps after a grind step, and the validator reports every one of them: a world
  // with such a hole in its quests does not give a route that is accepted
  const hole = run(world(9), null, { maxLevel: 10 });
  assert.deepStrictEqual(shown(hole), ["accept:1", "objective:1", "turnin:1", "grind", "accept:2", "objective:2", "turnin:2",
    "grind", "grind", "grind", "grind", "grind", "grind", "grind", "accept:3", "objective:3", "turnin:3", "grind"]);
  assert.deepStrictEqual(hole.route.steps.filter((s) => s.action === "grind").map((s) => s.level), [2, 3, 4, 5, 6, 7, 8, 9, 10]);
  assert.deepStrictEqual([hole.route.stats.endLevel, hole.checked.endLevel], [10, 10]);
  assert.strictEqual(hole.checked.errors.length, 6);
  for (const e of hole.checked.errors) assert.match(e, /^step \d+: two grind steps in a row/);
});
test("a level is ground where creatures of the level stand, and the way there is part of the route", () => {
  const world = () => {
    const w = testWorld();
    w.npc(10, 100, 30, 50); w.npc(20, 100, 40, 50, "");
    w.kill(1, 10, 20, 100);                                      // short of level 2, as above
    w.kill(2, 10, 20, 100, { requiredLevel: 2, questLevel: 2 });
    return w;
  };
  // wolves of level 1 in Westland's south, and enough creatures there that Westland is open country
  const near = world();
  near.pack(50, 100, 30, 62, 1, 320); near.pack(51, 100, 80, 20, 1, 20); near.pack(52, 100, 32, 50, 4, 20);
  const a = run(near, null, { maxLevel: 3 });
  assert.deepStrictEqual(a.checked.errors, []);
  assert.deepStrictEqual(a.route.steps.find((s) => s.action === "grind"), { action: "grind", level: 2, at: { zone: 100, x: 30, y: 62 } },
    "the nearest wolves of the level: not the far ones, not the level 4 ones next to the giver");
  assert.ok(a.at("accept", 2) > a.names.indexOf("grind"));
  // none in Westland: the wolves are over the border in Eastland, and the walk there is a step of the route
  const far = world();
  // Eastland has quests, none for now; of level 5, so a level 1 character may walk there (planner/tuning.js DANGER_LEVELS)
  far.npc(30, 200, 50, 50); far.kill(9, 30, 30, 200, { requiredLevel: 5, questLevel: 5 });
  far.pack(50, 200, 20, 50, 1, 320);
  const b = run(far, null, { maxLevel: 3 });
  assert.deepStrictEqual(b.checked.errors, []);
  const ground = b.names.indexOf("grind");
  assert.deepStrictEqual(b.route.steps[ground], { action: "grind", level: 2, at: { zone: 200, x: 20, y: 50 } });
  const way = b.route.steps.slice(b.at("turnin", 1) + 1, ground);
  assert.ok(way[0].action === "travel" && way[0].at.zone === 200, "into Eastland, as a step");
  assert.ok(way.every((s) => s.action === "travel" || s.action === "getflight"), "nothing but the way (and a flight point beside it)");
  assert.ok(b.at("turnin", 1) < ground && b.at("accept", 2) > ground, "and back for the quest the level opens");
  assert.strictEqual(b.checked.endLevel, b.route.stats.endLevel);
  assert.ok(Math.abs(b.checked.seconds - b.route.stats.seconds) <= 1, "the validator walks the same way in the same time");
});
test("a small visit is made rather than a level ground: grinding is the last resort", () => {
  const { XP_TO_LEVEL, yieldAt, questXp } = require("../lib/xp");
  const { CHOICES } = require("../planner/tuning");
  // One errand at level 2 is a small visit (planner/zonepick.js rule 3): far under MIN_VISIT of the level.
  assert.ok(questXp(2, 2) * yieldAt(2) < CHOICES.MIN_VISIT * XP_TO_LEVEL[2]);
  const world = () => {
    const w = testWorld();
    w.npc(10, 100, 30, 50); w.npc(20, 100, 40, 50, ""); w.npc(21, 100, 40, 52, "");
    w.kill(1, 10, 20, 100); w.kill(2, 10, 21, 100);                            // Westland's two quests: their kills reach level 2
    w.npc(30, 200, 50, 50); w.npc(31, 200, 52, 50);
    w.errand(5, 30, 31, 200, { requiredLevel: 2, questLevel: 2 });             // all Eastland has: one errand
    return w;
  };
  const shown = (r) => r.names.filter((n) => !/^(getflight|travel|transport|fly|accept|objective)/.test(n));
  // Westland leaves level 2 open by far more than the errand gives. The errand is done all the same (rule 4): the
  // way east for one quest, not a grind step first. Nothing opens after it, so the route ends there without one.
  const short = run(world(), null, { maxLevel: 4 });
  assert.deepStrictEqual(short.checked.errors, []);
  assert.deepStrictEqual(shown(short), ["turnin:1", "turnin:2", "turnin:5"]);
  assert.deepStrictEqual(short.order, [100, 200]);
  assert.strictEqual(short.route.stats.levelAt[2], short.at("objective", 2));
  assert.strictEqual(short.checked.endLevel, 2, "the errand does not reach level 3, and no level opens anything more");
  // with a quest waiting at level 3 the route goes on: the small visit first, and it reaches level 3 without a grind
  // step; only the last level, with no quest left anywhere, is ground
  const w = world();
  for (const quest of [11, 12, 13, 14, 15, 16]) w.errand(quest, 10, 10, 100, { requiredLevel: 2, questLevel: 2 });
  w.npc(11, 100, 31, 50); w.errand(4, 11, 11, 100, { requiredLevel: 3, questLevel: 3 }); // something to do at level 3
  const enough = run(w, null, { maxLevel: 4 });
  assert.deepStrictEqual(enough.checked.errors, []);
  assert.strictEqual(enough.route.stats.levelAt[3], enough.at("turnin", 5), "the errand is the step that reaches level 3");
  assert.deepStrictEqual(enough.names.filter((n) => n === "grind"), ["grind"]);
  assert.ok(enough.names.indexOf("grind") > enough.at("turnin", 4), "the one grind step comes when every quest is done: " + enough.names.join(" "));
  assert.strictEqual(enough.checked.endLevel, 4);
  // a visit that is a real piece of the level comes before the small one, though it is over the sea and the small
  // one next door (rule 3); the small one is still made after it, before the grind step of the last level
  const both = world();
  both.npc(50, 400, 50, 12); both.npc(51, 400, 52, 14, ""); both.npc(52, 400, 54, 14, ""); both.npc(53, 400, 56, 14, "");
  for (const [quest, mob] of [[60, 51], [61, 52], [62, 53]]) both.kill(quest, 50, mob, 400, { requiredLevel: 2, questLevel: 2 });
  const far = run(both, null, { maxLevel: 4 });
  assert.deepStrictEqual(far.checked.errors, []);
  assert.deepStrictEqual(far.order, [100, 400, 200]);
  assert.deepStrictEqual(shown(far), ["turnin:1", "turnin:2", "turnin:60", "turnin:61", "turnin:62", "turnin:5", "grind"]);
  assert.strictEqual(far.checked.endLevel, 4);
});
test("the last level may be ground, and the route ends there", () => {
  const w = testWorld();
  w.npc(10, 100, 30, 50); w.npc(20, 100, 40, 50, "");
  w.kill(1, 10, 20, 100);
  const { names, route } = run(w, null, { maxLevel: 2 }); // the quest leaves level 1 open (lib/xp.js yieldAt)
  assert.deepStrictEqual(names.filter((n) => n !== "getflight:1"), ["accept:1", "objective:1", "turnin:1", "grind"]);
  assert.strictEqual(route.stats.endLevel, 2);
});
test("the last step: a route that reaches the cap ends with one grind step to the cap, which the plan passes at no cost", () => {
  // Westland's quest and three letters from Eastland reach level 2, the cap here, on quests alone (test/supply.test.js)
  const world = (letters) => {
    const w = testWorld();
    w.npc(10, 100, 30, 50); w.npc(20, 100, 40, 50, ""); w.kill(1, 10, 20, 100);
    w.npc(30, 200, 20, 50);
    for (let n = 0; n < letters; n++) w.errand(70 + n, 30, 10, 200);
    return w;
  };
  const w = world(3), ch = w.human(), graph = w.graph();
  const route = planRoute(w.db, ch, { graph, inns: w.inns, maxLevel: 2 });
  const checked = validateRoute(w.db, route, ch, { graph, inns: w.inns });
  const last = route.steps.length - 1;
  assert.deepStrictEqual(checked.errors, []);
  // the level is reached by a hand-in; the last step is a grind step to the cap at the place the route ends
  assert.strictEqual(route.steps[route.stats.levelAt[2]].action, "turnin");
  assert.deepStrictEqual(route.steps[last], { action: "grind", level: 2, at: { zone: 100, x: 30, y: 50 } });
  assert.deepStrictEqual(route.steps.filter((s) => s.action === "grind").length, 1, "exactly one");
  // it changed nothing of the plan: the level was reached before it, and the plan's clock is the validator's
  assert.ok(route.stats.levelAt[2] < last);
  assert.strictEqual(route.stats.endLevel, 2);
  assert.deepStrictEqual([checked.levels[last], checked.endLevel], [2, 2], "the character is at the cap when it comes to the step");
  assert.strictEqual(checked.seconds, checked.clocks[last], "no time");
  assert.ok(Math.abs(checked.seconds - route.stats.seconds) <= 1, `${checked.seconds} s replayed, ${route.stats.seconds} s planned`);
  // it is no grind step the plan needs, by the validator's levels and by the plan's own, and no work in a zone
  assert.deepStrictEqual([neededGrinds(route, checked.levels), neededGrinds(route)], [[], []]);
  assert.deepStrictEqual(planLevels(route), checked.levels);
  const without = { ...route, steps: route.steps.slice(0, last) };
  const m = measureRoute(w.db, graph, route, ch, checked.levels), bare = measureRoute(w.db, graph, without, ch, checked.levels);
  assert.deepStrictEqual({ ...m, steps: 0 }, { ...bare, steps: 0 }, "no zone change, no travel");
  assert.strictEqual(m.steps, bare.steps + 1);
  // a route whose last level is ground ends with that grind step and gets no second one
  const one = world(1), ground = planRoute(one.db, one.human(), { graph: one.graph(), inns: one.inns, maxLevel: 2 });
  assert.deepStrictEqual(ground.steps.filter((s) => s.action === "grind").map((s) => s.level), [2]);
  assert.strictEqual(ground.steps[ground.steps.length - 1].action, "grind");
  assert.strictEqual(ground.stats.levelAt[2], ground.steps.length - 1, "this one makes the level");
  assert.deepStrictEqual(neededGrinds(ground), [ground.steps.length - 1]);
  // a route that ends short of the cap has none: there is nothing to grind towards (the pacing test above)
  const short = world(1), under = planRoute(short.db, short.human(), { graph: short.graph(), inns: short.inns, maxLevel: 10 });
  assert.ok(under.stats.endLevel < 10 && under.steps[under.steps.length - 1].action !== "grind", names(under).join(" "));
});
test("the gate: a step that accepts a quest asks for the game's minimum, and no more than HARD_TALK + BEHIND under the quest", () => {
  assert.deepStrictEqual([C.HARD_TALK, C.BEHIND], [4, 1]);
  // far above its own minimum: the gate is five under the quest's level
  assert.strictEqual(gateLevel({ minLevel: 1, level: 20 }), 15);
  assert.strictEqual(gateLevel({ minLevel: 14, level: 20 }), 15);
  // the game's minimum when that is higher
  assert.strictEqual(gateLevel({ minLevel: 15, level: 20 }), 15);
  assert.strictEqual(gateLevel({ minLevel: 18, level: 20 }), 18);
  assert.strictEqual(gateLevel({ minLevel: 55, level: 60 }), 55);
  // a low quest, and one whose levels the data does not give, gate nothing
  assert.strictEqual(gateLevel({ minLevel: 1, level: 6 }), 1);
  assert.strictEqual(gateLevel({ minLevel: 1, level: 7 }), 2);
  assert.strictEqual(gateLevel({ minLevel: 1, level: -1 }), 1);
  assert.strictEqual(gateLevel({}), 1);
  // a player on the plan never meets it: the planner takes a quest at most HARD_TALK above the player
  for (let level = 1; level <= 60; level++) assert.ok(gateLevel({ minLevel: 1, level: level + C.HARD_TALK }) <= level);
});
test("the log is empty at the end: quests in hand at the level cap are finished, new ones are not taken", () => {
  const w = testWorld();
  // Westland: one quest and an errand to Eastland, too little for the cap, so the route goes on to Eastland's three
  w.npc(10, 100, 30, 50); w.npc(20, 100, 60, 30, ""); w.kill(1, 10, 20, 100);
  w.npc(30, 200, 50, 50); w.errand(7, 10, 30, 100);
  w.npc(31, 200, 60, 30, ""); w.npc(32, 200, 70, 50, ""); w.npc(33, 200, 60, 70, "");
  w.kill(34, 30, 31, 200); w.kill(35, 30, 32, 200); w.kill(36, 30, 33, 200);
  w.kill(37, 30, 31, 200, { preQuestSingle: [34] }); // offered when quest 34 is handed in
  const { route, checked, at, order } = run(w, null, { maxLevel: 2 });
  assert.deepStrictEqual(checked.errors, [], "nothing is left in the log");
  assert.strictEqual(route.stats.endLevel, 2);
  const capped = route.stats.levelAt[2];
  const open = [34, 35, 36].filter((q) => at("accept", q) < capped && at("turnin", q) > capped);
  assert.ok(open.length > 0, "the cap is reached with quests in the log");
  for (const quest of [1, 7, 34, 35, 36]) assert.ok(at("turnin", quest) >= 0, `quest ${quest} is finished`);
  assert.strictEqual(at("accept", 37), -1, "no new quest after the cap");
  assert.deepStrictEqual(order, [100, 200], "the errand is carried to its end");
});
test("off the isle: the quest the transport asks for is taken, the isle is finished, and nothing leads back", () => {
  const w = testWorld();
  w.npc(14, 500, 50, 48); w.npc(15, 100, 50, 52); w.npc(16, 500, 40, 40, "");
  w.kill(70, 14, 16, 500); w.kill(71, 14, 16, 500); w.kill(72, 14, 16, 500);
  w.errand(77, 14, 15, 500, { requiredLevel: 2 });
  town(w);
  const { route, checked, order, at } = run(w, w.human("WARRIOR", 500), { maxLevel: 5 });
  assert.deepStrictEqual(checked.errors, []);
  assert.deepStrictEqual(order, [500, 100]);
  const boat = route.steps.findIndex((s) => s.action === "transport");
  assert.ok(at("accept", 77) < boat && at("turnin", 72) < boat && boat < at("turnin", 77));
  assert.deepStrictEqual(route.stats.links.map((l) => [l.id, l.assumed]), [["sky", ["route", "boarding"]]]);
});
test("the level gap: a quest with fights may be HARD levels above the player, one without HARD_TALK, and far below is more than EASY", () => {
  const w = testWorld();
  w.npc(10, 100, 30, 50); w.npc(20, 100, 40, 50, "");
  const at = { zone: 100, x: 30, y: 50 };
  for (const level of [1, 5, 6]) {
    w.kill(100 + level, 10, 20, 100, { questLevel: level });
    w.errand(200 + level, 10, 10, 100, { questLevel: level });
  }
  const gapAt = (level, quest, action = "accept") => {
    const g = levelGap(w.db, { steps: [{ action, quest, at, npc: 10 }, { action: "turnin", quest, at, npc: 10 }] }, [level, level]);
    assert.strictEqual(g.steps, 1, "accepts and objectives are looked at, hand-ins are not");
    return g.above.length ? "above" : g.below.length ? "below" : "fine";
  };
  // a level 5 quest for a level 1 player: one level too far with fights, just allowed without; a level 6 one is too far for both
  assert.deepStrictEqual([1 + C.HARD, 1 + C.HARD_TALK], [4, 5]);
  assert.deepStrictEqual([gapAt(1, 105), gapAt(1, 205), gapAt(1, 106), gapAt(1, 206)], ["above", "fine", "above", "above"]);
  assert.deepStrictEqual([gapAt(2, 105), gapAt(2, 105, "objective"), gapAt(2, 206), gapAt(3, 106)], ["fine", "fine", "fine", "fine"]);
  assert.deepStrictEqual(levelGap(w.db, { steps: [{ action: "accept", quest: 105, at, npc: 10 }] }, [1]).above, [{ step: 0, quest: 105, questLevel: 5, level: 1 }]);
  // a level 1 quest is far below a player of level 7, not one of level 6
  assert.deepStrictEqual([gapAt(1 + C.EASY, 101), gapAt(2 + C.EASY, 101), gapAt(2 + C.EASY, 201)], ["fine", "below", "below"]);
  // another class's steps are not this class's
  const mixed = { steps: [{ action: "accept", quest: 106, at, npc: 10, when: { class: "ROGUE" } }, { action: "accept", quest: 205, at, npc: 10 }] };
  assert.deepStrictEqual([levelGap(w.db, mixed, [1, 1], { cls: "WARRIOR" }).above.length, levelGap(w.db, mixed, [1, 1], { cls: "ROGUE" }).above.length], [0, 1]);
});

const DATA = path.join(__dirname, "..", "data");
const real = fs.existsSync(path.join(DATA, "forever_db.json")) && fs.existsSync(path.join(DATA, "wago", "TaxiPathNode.csv"));
let cache;
function realWorld() {
  if (!cache) {
    const { loadDb } = require("../lib/db");
    const { loadTravel } = require("../lib/travel");
    const { loadInns } = require("../planner/context");
    const db = loadDb(DATA);
    cache = { db, graph: loadTravel(db, DATA), inns: loadInns(db, DATA), routes: new Map() };
  }
  return cache;
}
function realRoute(race) {
  const w = realWorld();
  if (!w.routes.has(race)) {
    const saved = RACES.Human.startArea;
    RACES.Human.startArea = 12; // other tests in this file point Humans at the fixture; these plan the real thing
    try {
      const ch = character(race, "WARRIOR");
      const route = planRoute(w.db, ch, { graph: w.graph, inns: w.inns });
      w.routes.set(race, { ch, route, checked: validateRoute(w.db, route, ch, { graph: w.graph, inns: w.inns }) });
    } finally { RACES.Human.startArea = saved; }
  }
  return w.routes.get(race);
}
test("real data: both Skyborne races start with their Zephras Isle quests, and nobody else goes there", { skip: !real }, () => {
  const ISLE = 16593;
  const zone = (s) => (s.at ? s.at.zone : s.to.zone);
  for (const race of ["HighOrder", "Windshaper"]) {
    const { route } = realRoute(race);
    assert.deepStrictEqual([route.steps[0].action, route.steps[0].quest, route.steps[0].at.zone], ["accept", 92460, ISLE], `${race} starts with Coming of Age`);
    const leaves = route.steps.findIndex((s) => s.action === "transport");
    assert.ok(leaves >= 150, `${race} does ${leaves} steps before it leaves`);
    for (const s of route.steps.slice(0, leaves + 1)) assert.strictEqual(zone(s), ISLE, `${race} stays on the isle until it sails`);
    assert.strictEqual(route.steps[leaves].to.zone, race === "HighOrder" ? 36 : 215);
    const exit = race === "HighOrder" ? 94946 : 95349;
    const accepted = route.steps.findIndex((s) => s.action === "accept" && s.quest === exit);
    assert.ok(accepted >= 0 && accepted < leaves, `${race} takes the quest that leads off the isle (${exit}) before leaving`);
    // the data knows no way back to the isle, and no isle quest sends the player to the mainland for a common drop
    const back = route.steps.slice(leaves + 1).filter((s) => zone(s) === ISLE || (s.to && s.to.zone === ISLE));
    assert.deepStrictEqual(back, [], `${race} never returns to the isle`);
  }
  for (const race of ["Human", "Tauren"]) {
    const { route } = realRoute(race);
    assert.ok(!route.steps.some((s) => zone(s) === ISLE), `${race} never goes to the isle`);
  }
});
test("real data: a High Order character takes the Skyborne Portal from Dalaran to Stormwind and goes on to Westfall", { skip: !real }, () => {
  const { route } = realRoute("HighOrder");
  const at = index(route);
  const portal = route.steps.findIndex((s) => s.action === "transport" && s.kind === "portal");
  assert.ok(at("accept", 94947) >= 0 && at("accept", 94947) < at("objective", 94947) && at("objective", 94947) < portal && portal < at("turnin", 94947));
  assert.deepStrictEqual([route.steps[portal].at.zone, route.steps[portal].to.zone], [36, 1519]);
  assert.strictEqual(route.steps[at("objective", 94947)].object, 631299);
  // between the accept in Dalaran and the turn-in in Stormwind there is nothing but the way
  for (const s of route.steps.slice(at("accept", 94947) + 1, at("turnin", 94947))) assert.ok(s.quest === undefined || s.quest === 94947, `${s.action} ${s.quest}`);
  assert.ok(at("turnin", 98021) > at("turnin", 94947), "the quest to Sentinel Hill is carried to Westfall");
  const horde = realRoute("Windshaper").route, h = index(horde);
  assert.ok(h("turnin", 95350) > h("turnin", 95349) && h("turnin", 98024) > h("turnin", 95350));
});
for (const race of Object.keys(RACES)) {
  test(`real data: the ${race} route reaches 60 on quests with no errors and an empty log, within the accepted price in zone changes and travel`, { skip: !real }, () => {
    const { ch, route, checked } = realRoute(race);
    const { graph, db } = realWorld();
    const { measureRoute } = require("../planner/measure");
    const baseline = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "planner", "baseline.json"), "utf8")).races[race];
    assert.deepStrictEqual(checked.errors.slice(0, 5), []);
    assert.strictEqual(checked.endLevel, 60);
    assert.strictEqual(route.stats.endLevel, 60);
    const m = measureRoute(db, graph, route, ch, checked.levels);
    // The limits are planner/report.js's, and the reasons are there: the routes count on 60 to 68% of the estimated
    // XP (lib/xp.js yieldAt) and do quests instead of grinding, so they change zone more often than the baseline
    // routes did and are longer on the way. That is the accepted price; the limits are how high it may go.
    assert.strictEqual(MAX_ZONE_SHARE, 1.4);
    assert.ok(m.zoneChanges <= baseline.zoneChanges * MAX_ZONE_SHARE, `${m.zoneChanges} zone changes against ${baseline.zoneChanges}: over ${MAX_ZONE_SHARE * 100}% of the baseline`);
    // quests that can be played: none further above the player than HARD levels (HARD_TALK without fights:
    // planner/tuning.js), few far below it (planner/levelgap.js). The shared route has none above at all; MAX_ABOVE
    // is the room of a class layered onto it
    assert.deepStrictEqual([C.HARD, C.HARD_TALK, C.EASY], [3, 4, 5]);
    const gap = levelGap(db, route, checked.levels);
    assert.ok(gap.above.length === 0 && MAX_ABOVE <= 2, `${gap.above.length} quests above the level: ${JSON.stringify(gap.above.slice(0, 5))}`);
    assert.strictEqual(MAX_BELOW_SHARE, 0.1);
    assert.ok(gap.below.length <= gap.steps * MAX_BELOW_SHARE, `${gap.below.length} of ${gap.steps} quest steps far below the level`);
    assert.strictEqual(MAX_TRAVEL_SHARE, 1.5);
    assert.ok(m.seconds <= baseline.travelSeconds * MAX_TRAVEL_SHARE, `${m.seconds} s of travel against ${baseline.travelSeconds}: over ${MAX_TRAVEL_SHARE * 100}% of the baseline`);
    // the price buys quests: more of them than the baseline route did
    assert.ok(route.stats.quests > baseline.quests, `${route.stats.quests} quests against the baseline's ${baseline.quests}`);
    assert.strictEqual(m.unreachable, 0);
    // no hand-in that is ready is walked away from (planner/leftbehind.js; the threshold is explained there)
    const behind = leftBehind(db, route);
    assert.ok(behind.length <= MAX_LEFT_BEHIND, `${behind.length} hand-ins left behind: ${JSON.stringify(behind.slice(0, 5))}`);
    // no walk through a zone whose creatures are far above the player (planner/danger.js)
    const unsafe = dangerousWalks(db, graph, route, ch, checked.levels);
    assert.strictEqual(MAX_DANGEROUS_WALKS, 0);
    assert.deepStrictEqual(unsafe.slice(0, 5), [], `${unsafe.length} dangerous walks`);
    // the route has exactly one grind step to the cap, and no step after it needs XP: a player who comes to it under
    // 60 is told to grind the rest. Where the plan reached 60 on quests it is the route's last step, passed as it
    // comes: no time, and not counted below. Where the plan grinds the end of level 59 (Orc, Tauren, Troll,
    // Windshaper) it is that grind step, and only what is left in the log is finished after it.
    const all = route.steps.map((s, i) => (s.action === "grind" ? i : -1)).filter((i) => i >= 0);
    const toCap = all.filter((i) => route.steps[i].level === 60);
    assert.strictEqual(toCap.length, 1, `grind steps to 60 at ${toCap.join(", ")}`);
    const last = toCap[0];
    assert.strictEqual(all[all.length - 1], last, "the route's last grind step");
    assert.strictEqual(checked.levels[last + 1] === undefined ? checked.endLevel : checked.levels[last + 1], 60);
    for (const s of route.steps.slice(last + 1)) assert.notStrictEqual(s.action, "accept", "no new quest after it");
    if (checked.levels[last] === 60) assert.strictEqual(last, route.steps.length - 1, "passed on the plan: the route's last step");
    assert.deepStrictEqual(planLevels(route), checked.levels, "the plan's levels are the validator's");
    if (checked.levels[last] === 60) assert.strictEqual(checked.seconds, checked.clocks[last], "it costs no time on the plan");
    assert.ok(Math.abs(checked.seconds - route.stats.seconds) <= 1, `${checked.seconds} s replayed, ${route.stats.seconds} s planned`);
    // grinding is the last resort: at most two grind steps in a whole route that the plan needs (measured: none or
    // one, the end of level 59), each the rest of one level, never two in a row
    const grinds = neededGrinds(route, checked.levels);
    assert.deepStrictEqual(all.filter((i) => !grinds.includes(i)), checked.levels[last] === 60 ? [last] : [], "only the last step is passed");
    assert.strictEqual(MAX_GRIND_STEPS, 2);
    assert.ok(grinds.length <= MAX_GRIND_STEPS, `${grinds.length} grind steps: ${grinds.map((i) => `to ${route.steps[i].level}`).join(", ")}`);
    for (const i of grinds) assert.strictEqual(route.steps[i].level, checked.levels[i] + 1, `the grind step at ${i} ends the level it starts in`);
    for (const i of grinds) assert.notStrictEqual(route.steps[i + 1] && route.steps[i + 1].action, "grind");
    // ... and each at a real place to grind (planner/grindspots.js): in open country, never a city, with at least
    // GRIND_MIN_SPAWNS spawns of creatures of the level around it, none elite, none above the level by more than one
    const bands = zoneLevels(db);
    for (const i of grinds) {
      const step = route.steps[i], level = step.level - 1;
      const where = `the grind step to ${step.level} in ${db.areas.get(step.at.zone).name} (${step.at.x}, ${step.at.y})`;
      assert.ok((bands.get(step.at.zone) || {}).wild, `${where} is not in open country`);
      const spot = grindSpotAt(db, step.at, level);
      assert.ok(spot.count >= C.GRIND_MIN_SPAWNS, `${where} has ${spot.count} spawns of the level around it`);
      assert.ok(spot.min >= level - C.GRIND_BELOW && spot.max <= level + C.GRIND_ABOVE, `${where}: creatures of level ${spot.min} to ${spot.max} for a player of ${level}`);
      for (const id of spot.npcs) { const npc = db.npcs.get(id); assert.ok(npc.name && !npc.friendly && !npc.rank, `${where}: ${npc.name}`); }
    }
    // travel is format 2: every flight is learned first
    const learned = new Set();
    for (const s of route.steps) {
      if (s.action === "getflight") learned.add(s.node);
      if (s.action === "fly") assert.ok(learned.has(s.from) && learned.has(s.to));
    }
    assert.ok(route.steps.some((s) => s.action === "fly") && route.steps.some((s) => s.action === "sethearth") && route.steps.some((s) => s.action === "hearth"));
  });
}
for (const race of Object.keys(RACES)) {
  test(`real data: the ${race} route does its objectives in loops and never fills the log past its limit`, { skip: !real }, () => {
    const { route } = realRoute(race);
    // It was 1.25 to 1.4 before the quests around were gathered first and hand-ins waited for the end of the loop.
    // Most trips still have one objective: a visit often has one quest to offer, or a chain that gives one at a time.
    const perRun = objectivesPerRun(route);
    assert.ok(perRun >= 1.4, `${perRun.toFixed(2)} objectives per trip out`);
    const log = new Set();
    for (const s of route.steps) {
      if (s.action === "accept") log.add(s.quest);
      if (s.action === "turnin") log.delete(s.quest);
      assert.ok(log.size <= 20, `${log.size} quests in the log`);
    }
  });
}
test("real data: planning the same race twice gives the same route", { skip: !real }, () => {
  const { db, graph, inns } = realWorld();
  const ch = character("Tauren", "WARRIOR");
  assert.strictEqual(JSON.stringify(planRoute(db, ch, { graph, inns })), JSON.stringify(realRoute("Tauren").route));
});
