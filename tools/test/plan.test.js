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
const { zoneOrder } = require("../planner/measure");
const { leftBehind, MAX_LEFT_BEHIND } = require("../planner/leftbehind");

const human = () => { RACES.Human.startArea = 1000; return character("Human", "WARRIOR"); };
const index = (route) => (action, quest) => route.steps.findIndex((s) => s.action === action && s.quest === quest);
const names = (route) => route.steps.map((s) => s.action + (s.quest !== undefined ? ":" + s.quest : s.node !== undefined ? ":" + s.node : ""));

test("zone bands come from quest levels", () => {
  const db = fixtureDb();
  const bands = zoneBands(db, levelingQuests(db, human()));
  assert.deepStrictEqual(bands.map((b) => b.zone), [1000, 2000]);
  assert.strictEqual(bands[0].name, "Testvale");
  assert.ok(bands[1].min >= 4);
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
test("a quest that needs a trip to another zone and back is left alone", () => {
  const w = testWorld();
  town(w);
  w.npc(40, 400, 60, 30, "");
  w.kill(8, 10, 40, 100); // given and handed in in Westland, fought overseas in Farshore
  const { at, order, checked } = run(w, null, { maxLevel: 4 });
  assert.deepStrictEqual(checked.errors, []);
  assert.strictEqual(at("accept", 8), -1);
  assert.deepStrictEqual(order, [100]);
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
  // to the far town first and leave quest 1's hand-in behind, with the east field taken on the way home.
  w.npc(10, 100, 30, 50); w.npc(11, 100, 90, 50);
  w.npc(20, 100, 30, 60, ""); w.npc(21, 100, 40, 50, ""); w.npc(22, 100, 95, 60, "");
  w.kill(1, 10, 20, 100); w.kill(2, 10, 21, 100); w.kill(3, 11, 22, 100);
  const { route, names, checked } = run(w, null, { maxLevel: 3 });
  assert.deepStrictEqual(checked.errors, []);
  const quests = names.filter((n) => /^(accept|objective|turnin)/.test(n)).join(" ");
  assert.strictEqual(quests, "accept:1 accept:2 objective:1 objective:2 turnin:1 turnin:2 accept:3 objective:3 turnin:3");
  assert.deepStrictEqual(leftBehind(w.db, route), []);
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
test("pacing: a grind step bridges one level to the next quests, and the route stops rather than grind two", () => {
  const w = testWorld();
  w.npc(10, 100, 30, 50); w.npc(20, 100, 40, 50, "");
  w.kill(1, 10, 20, 100);                                    // 400 XP of kills and 110 of reward: level 2
  w.kill(2, 10, 20, 100, { requiredLevel: 3, questLevel: 3 }); // opens a level later
  w.kill(3, 10, 20, 100, { requiredLevel: 9, questLevel: 9 }); // out of reach
  const { names, route, checked } = run(w, null, { maxLevel: 10 });
  assert.deepStrictEqual(checked.errors, []);
  assert.deepStrictEqual(names.filter((n) => n !== "getflight:1"), ["accept:1", "objective:1", "turnin:1", "grind", "accept:2", "objective:2", "turnin:2"]);
  assert.deepStrictEqual(route.steps.find((s) => s.action === "grind"), { action: "grind", level: 3, at: { zone: 100, x: 30, y: 50 } });
  assert.ok(route.stats.endLevel < 9);
  assert.strictEqual(checked.endLevel, route.stats.endLevel);
});
test("the last level may be ground, and the route ends there", () => {
  const w = testWorld();
  w.npc(10, 100, 30, 50); w.npc(20, 100, 40, 50, "");
  w.kill(1, 10, 20, 100);
  const { names, route } = run(w, null, { maxLevel: 3 });
  assert.deepStrictEqual(names.filter((n) => n !== "getflight:1"), ["accept:1", "objective:1", "turnin:1", "grind"]);
  assert.strictEqual(route.stats.endLevel, 3);
});
test("the log is empty at the end: quests in hand at the level cap are finished, new ones are not taken", () => {
  const w = testWorld();
  // Westland: one quest and an errand to Eastland, too little for the cap, so the route goes on to Eastland's three
  w.npc(10, 100, 30, 50); w.npc(20, 100, 60, 30, ""); w.kill(1, 10, 20, 100);
  w.npc(30, 200, 50, 50); w.errand(7, 10, 30, 100);
  w.npc(31, 200, 60, 30, ""); w.npc(32, 200, 70, 50, ""); w.npc(33, 200, 60, 70, "");
  w.kill(34, 30, 31, 200); w.kill(35, 30, 32, 200); w.kill(36, 30, 33, 200);
  w.kill(37, 30, 31, 200, { preQuestSingle: [34] }); // offered when quest 34 is handed in
  const { route, checked, at, order } = run(w, null, { maxLevel: 3 });
  assert.deepStrictEqual(checked.errors, [], "nothing is left in the log");
  assert.strictEqual(route.stats.endLevel, 3);
  const capped = route.stats.levelAt[3];
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
  test(`real data: the ${race} route reaches 60 with no errors, an empty log, and far fewer zone changes than the baseline`, { skip: !real }, () => {
    const { ch, route, checked } = realRoute(race);
    const { graph, db } = realWorld();
    const { measureRoute } = require("../planner/measure");
    const baseline = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "planner", "baseline.json"), "utf8")).races[race];
    assert.deepStrictEqual(checked.errors.slice(0, 5), []);
    assert.strictEqual(checked.endLevel, 60);
    assert.strictEqual(route.stats.endLevel, 60);
    const m = measureRoute(db, graph, route, ch, checked.levels);
    assert.ok(m.zoneChanges <= baseline.zoneChanges * 0.4, `${m.zoneChanges} zone changes against ${baseline.zoneChanges}: not 60% fewer`);
    assert.ok(m.seconds <= baseline.travelSeconds, `${m.seconds} s of travel against ${baseline.travelSeconds}`);
    assert.strictEqual(m.unreachable, 0);
    // no hand-in that is ready is walked away from (planner/leftbehind.js; the threshold is explained there)
    const behind = leftBehind(db, route);
    assert.ok(behind.length <= MAX_LEFT_BEHIND, `${behind.length} hand-ins left behind: ${JSON.stringify(behind.slice(0, 5))}`);
    // grind steps are rare and short: one level each, never two in a row, a handful in a whole route
    const grinds = route.steps.map((s, i) => (s.action === "grind" ? i : -1)).filter((i) => i >= 0);
    assert.ok(grinds.length <= 3, `${grinds.length} grind steps`);
    for (const i of grinds) assert.notStrictEqual(route.steps[i + 1] && route.steps[i + 1].action, "grind");
    // travel is format 2: every flight is learned first
    const learned = new Set();
    for (const s of route.steps) {
      if (s.action === "getflight") learned.add(s.node);
      if (s.action === "fly") assert.ok(learned.has(s.from) && learned.has(s.to));
    }
    assert.ok(route.steps.some((s) => s.action === "fly") && route.steps.some((s) => s.action === "sethearth") && route.steps.some((s) => s.action === "hearth"));
  });
}
test("real data: planning the same race twice gives the same route", { skip: !real }, () => {
  const { db, graph, inns } = realWorld();
  const ch = character("Tauren", "WARRIOR");
  assert.strictEqual(JSON.stringify(planRoute(db, ch, { graph, inns })), JSON.stringify(realRoute("Tauren").route));
});
