// Noir Guides, GPLv3. See LICENSE.
const test = require("node:test");
const assert = require("node:assert");
const { testWorld } = require("./world");
const { classMask } = require("../lib/characters");
const { planRoute } = require("../planner/plan");
const { validateRoute } = require("../planner/validate");
const { classQuests, layerClasses } = require("../planner/classes");

const ROGUE = classMask("ROGUE"), MAGE = classMask("MAGE");
const M = (zone, x, y) => ({ zone, x, y });
const QUEST_ACTIONS = new Set(["accept", "objective", "turnin"]);

// A town in Westland with three quests for everyone, planned to level 3: the shared route the classes are layered into.
function town(w) {
  w.npc(10, 100, 30, 50); w.npc(11, 100, 31, 50); w.npc(12, 100, 30, 51);
  w.npc(20, 100, 60, 30, ""); w.npc(21, 100, 70, 50, ""); w.npc(22, 100, 60, 70, "");
  w.kill(1, 10, 20, 100); w.kill(2, 11, 21, 100); w.kill(3, 12, 22, 100);
}
function shared(w, maxLevel = 3) {
  const graph = w.graph();
  return { graph, route: planRoute(w.db, w.human(), { graph, inns: w.inns, maxLevel }) };
}
const check = (w, graph, route, ch) => validateRoute(w.db, route, ch, { graph, inns: w.inns });
const mine = (route, cls) => route.steps.filter((s) => !s.when || s.when.class === cls);
const questSteps = (route, quest) => route.steps.map((s, i) => ({ s, i })).filter(({ s }) => QUEST_ACTIONS.has(s.action) && s.quest === quest);

test("class quests: open to the race and class, ordinary, placeable and below the level cap", () => {
  const w = testWorld();
  town(w);
  w.npc(13, 100, 32, 50);
  w.quest(40, { startedBy: [[13]], finishedBy: [[13]], zoneOrSort: 100, requiredClasses: ROGUE });
  w.quest(41, { startedBy: [[13]], finishedBy: [[13]], zoneOrSort: -22, requiredClasses: ROGUE });          // a holiday
  w.quest(42, { startedBy: [[13]], finishedBy: [[13]], zoneOrSort: 100, requiredClasses: ROGUE, specialFlags: 1 }); // repeatable
  w.quest(43, { startedBy: [[13]], finishedBy: [[13]], zoneOrSort: 100, requiredClasses: ROGUE, requiredLevel: 60 });
  w.quest(44, { startedBy: [[13]], finishedBy: [[13]], zoneOrSort: -162, requiredClasses: ROGUE });         // the rogue sort
  w.quest(45, { startedBy: [[13]], finishedBy: [[13]], zoneOrSort: 100, requiredClasses: ROGUE, requiredRaces: 178 }); // Horde
  w.quest(46, { startedBy: [[13]], finishedBy: [[13]], zoneOrSort: 100, requiredClasses: MAGE });
  w.quest(47, { startedBy: [[13]], finishedBy: [[13]], zoneOrSort: 100, requiredClasses: ROGUE, requiredSkill: [164, 50] });
  w.quest(48, { startedBy: [[999]], finishedBy: [[13]], zoneOrSort: 100, requiredClasses: ROGUE });         // nobody gives it
  w.quest(49, { startedBy: [[13]], finishedBy: [[13]], zoneOrSort: 100, requiredClasses: ROGUE + MAGE });
  const graph = w.graph();
  const ids = (cls) => classQuests(w.db, w.human(cls), { graph }).map((c) => c.q.id);
  assert.deepStrictEqual(ids("ROGUE"), [40, 44, 49]);
  assert.deepStrictEqual(ids("MAGE"), [46, 49]);
  assert.deepStrictEqual(ids("WARRIOR"), [], "the quests everyone takes are the shared route's, not a class's");
});

test("a class quest filed under a class sort and given on the Skyborne isle is taken although it is not classic", () => {
  const w = testWorld();
  const { character } = require("../lib/characters");
  w.npc(15, 500, 40, 40); w.npc(16, 100, 40, 40);
  // filed under the rogue sort: the quest has no zone, only its giver says where it starts
  w.quest(54, { startedBy: [[15]], finishedBy: [[15]], zoneOrSort: -162, requiredClasses: ROGUE });
  w.quest(55, { startedBy: [[16]], finishedBy: [[16]], zoneOrSort: -162, requiredClasses: ROGUE });
  w.db.eraQuestIds.delete(54); w.db.eraQuestIds.delete(55);
  const graph = w.graph();
  const skyborne = { ...character("HighOrder", "ROGUE"), startArea: 500 };
  assert.deepStrictEqual(classQuests(w.db, skyborne, { graph }).map((c) => c.q.id), [54], "the isle's quest, not the other Forever-only one");
});

test("a class quest that is not classic and not from the isle is listed as left out, with that reason", () => {
  const w = testWorld();
  town(w);
  const { graph, route } = shared(w);
  w.npc(13, 100, 32, 50);
  w.errand(56, 13, 13, 100, { requiredClasses: ROGUE });
  w.errand(57, 13, 13, -162, { requiredClasses: ROGUE });
  w.db.eraQuestIds.delete(57);
  w.errand(58, 13, 13, -162, { requiredClasses: ROGUE, specialFlags: 1 }); // repeatable as well: not a candidate at all
  w.db.eraQuestIds.delete(58);
  const out = layerClasses(w.db, route, [w.human("ROGUE")], { graph });
  assert.deepStrictEqual(out.classes.ROGUE.layered, [56]);
  assert.deepStrictEqual(out.classes.ROGUE.left.map((l) => l.quest), [57]);
  assert.match(out.classes.ROGUE.left[0].reason, /not a classic quest/);
});

test("a class quest next to the route is layered in with when = class, and other classes do not see it", () => {
  const w = testWorld();
  town(w);
  const { graph, route } = shared(w);
  w.npc(13, 100, 32, 50); w.npc(23, 100, 62, 32, "");
  w.kill(40, 13, 23, 100, { requiredClasses: ROGUE });
  const before = JSON.stringify(route);
  const out = layerClasses(w.db, route, [w.human("WARRIOR"), w.human("ROGUE")], { graph });
  assert.strictEqual(JSON.stringify(route), before, "the shared route is not changed");
  assert.deepStrictEqual(out.classes.ROGUE.layered, [40]);
  assert.deepStrictEqual(out.classes.WARRIOR.layered, []);
  const steps = questSteps(out.route, 40);
  assert.deepStrictEqual(steps.map(({ s }) => s.action), ["accept", "objective", "turnin"]);
  for (const { s } of steps) assert.deepStrictEqual(s.when, { class: "ROGUE" });
  for (const s of out.route.steps) if (s.when) assert.strictEqual(s.when.class, "ROGUE");
  // the warrior's route is the shared route, step for step
  assert.deepStrictEqual(mine(out.route, "WARRIOR"), route.steps);
  for (const cls of ["WARRIOR", "ROGUE"]) assert.deepStrictEqual(check(w, graph, out.route, w.human(cls)).errors, [], cls);
  // the giver is next to the town's hub: the quest is taken while the player is there, not at the end of the route
  const firstTurnin = out.route.steps.findIndex((s) => s.action === "turnin" && !s.when);
  assert.ok(steps[0].i < firstTurnin, `accepted at step ${steps[0].i + 1}, the town's first turn-in is step ${firstTurnin + 1}`);
  assert.deepStrictEqual(out.route.steps.filter((s) => s.when && !QUEST_ACTIONS.has(s.action)), [], "no travel for a quest in the same field");
  assert.strictEqual(out.route.id, route.id);
  assert.strictEqual(out.route.format, 2);
});

test("layering keeps the level and the prerequisites", () => {
  const w = testWorld();
  town(w);
  const { graph, route } = shared(w);
  w.npc(13, 100, 32, 50);
  w.errand(50, 13, 13, 100, { requiredClasses: ROGUE, requiredLevel: 3 });
  w.errand(51, 13, 13, 100, { requiredClasses: ROGUE, preQuestSingle: [2] });  // after a shared quest
  w.errand(52, 13, 13, 100, { requiredClasses: ROGUE });
  w.errand(53, 13, 13, 100, { requiredClasses: ROGUE, preQuestSingle: [52] }); // a class chain
  const rogue = w.human("ROGUE");
  const out = layerClasses(w.db, route, [rogue], { graph });
  assert.deepStrictEqual(out.classes.ROGUE.layered, [50, 51, 52, 53]);
  const r = check(w, graph, out.route, rogue);
  assert.deepStrictEqual(r.errors, []);
  const at = (action, quest) => out.route.steps.findIndex((s) => s.action === action && s.quest === quest);
  assert.ok(r.levels[at("accept", 50)] >= 3, "not below the level the quest asks");
  assert.ok(at("accept", 51) > at("turnin", 2));
  assert.ok(at("accept", 53) > at("turnin", 52));
});

test("a class quest on another continent is reached with class steps of the way, and the route comes back", () => {
  const w = testWorld();
  town(w);
  const { graph, route: town3 } = shared(w);
  // the route goes on in Westland to level 7, past the quest's levels: the quest is done on the way, not after the end
  const more = [];
  for (let level = 4; level <= 7; level++) more.push({ action: "travel", at: M(100, 40 + level, 50) }, { action: "grind", level, at: M(100, 40 + level, 50) });
  const route = { ...town3, steps: [...town3.steps, ...more] };
  w.npc(60, 400, 50, 14);
  w.errand(60, 60, 60, 400, { requiredClasses: ROGUE });
  const rogue = w.human("ROGUE");
  const out = layerClasses(w.db, route, [w.human("WARRIOR"), rogue], { graph });
  assert.deepStrictEqual(out.classes.ROGUE.layered, [60]);
  const ways = out.route.steps.filter((s) => s.when && s.action === "transport");
  assert.strictEqual(ways.length, 2, "over and back by boat");
  for (const s of ways) assert.deepStrictEqual(s.when, { class: "ROGUE" });
  assert.deepStrictEqual(check(w, graph, out.route, rogue).errors, []);
  assert.deepStrictEqual(check(w, graph, out.route, w.human("WARRIOR")).errors, []);
});

test("a class quest is never held past a full quest log", () => {
  const w = testWorld();
  // twenty errands taken at one hub and handed in over the border, then the class quest that goes the same way
  w.npc(10, 100, 30, 50); w.npc(11, 200, 50, 50);
  const steps = [];
  for (let id = 101; id <= 120; id++) { w.errand(id, 10, 11, 100); steps.push({ action: "accept", quest: id, at: M(100, 30, 50), npc: 10 }); }
  steps.push({ action: "travel", at: M(200, 50, 50) });
  for (let id = 101; id <= 120; id++) steps.push({ action: "turnin", quest: id, at: M(200, 50, 50), npc: 11 });
  const graph = w.graph();
  const route = { id: "alliance-human", format: 2, race: "Human", faction: "Alliance", steps, stats: {} };
  w.npc(12, 100, 30, 52);
  w.errand(70, 12, 11, 100, { requiredClasses: ROGUE });
  const rogue = w.human("ROGUE");
  assert.deepStrictEqual(check(w, graph, route, rogue).errors, []);
  const out = layerClasses(w.db, route, [rogue], { graph });
  assert.deepStrictEqual(out.classes.ROGUE.layered, [70]);
  assert.deepStrictEqual(check(w, graph, out.route, rogue).errors, []);
});

test("a class quest that cannot be layered is left out with the reason", () => {
  const w = testWorld();
  town(w);
  const { graph, route } = shared(w);
  w.npc(13, 100, 32, 50);
  w.errand(80, 13, 13, 100, { requiredClasses: ROGUE, preQuestSingle: [999] }); // its prerequisite is never done
  w.errand(81, 13, 13, 100, { requiredClasses: ROGUE, requiredLevel: 30 });     // the route never gets there
  const out = layerClasses(w.db, route, [w.human("ROGUE")], { graph });
  assert.deepStrictEqual(out.classes.ROGUE.layered, []);
  assert.deepStrictEqual(out.classes.ROGUE.left.map((l) => l.quest), [80, 81]);
  for (const l of out.classes.ROGUE.left) assert.ok(typeof l.reason === "string" && l.reason.length > 0);
  assert.deepStrictEqual(out.route.steps, route.steps);
});

test("several classes share one route file, and each sees only its own quests", () => {
  const w = testWorld();
  town(w);
  const { graph, route } = shared(w);
  w.npc(13, 100, 32, 50); w.npc(14, 100, 29, 49);
  w.errand(90, 13, 13, 100, { requiredClasses: ROGUE });
  w.errand(91, 14, 14, 100, { requiredClasses: MAGE });
  w.errand(92, 14, 13, 100, { requiredClasses: ROGUE + MAGE }); // one quest for two classes: each takes it in its own steps
  const chars = ["WARRIOR", "ROGUE", "MAGE"].map((cls) => w.human(cls));
  const out = layerClasses(w.db, route, chars, { graph });
  assert.deepStrictEqual(out.classes.ROGUE.layered, [90, 92]);
  assert.deepStrictEqual(out.classes.MAGE.layered, [91, 92]);
  for (const ch of chars) {
    const r = check(w, graph, out.route, ch);
    assert.deepStrictEqual(r.errors, [], ch.cls);
    // no class quest reaches a class it is not for
    for (const s of mine(out.route, ch.cls)) {
      const q = QUEST_ACTIONS.has(s.action) ? w.db.quests.get(s.quest) : null;
      if (q && q.classes) assert.ok(s.when && s.when.class === ch.cls, `${ch.cls} sees ${s.action} of quest ${q.id}`);
    }
  }
  // the same input gives the same route
  assert.strictEqual(JSON.stringify(layerClasses(w.db, route, chars, { graph }).route), JSON.stringify(out.route));
});

// ---------------------------------------------------------------------------------------------------------------
// The real data: every class and race combination the client has, against its race's route with the classes layered.
const fs = require("node:fs");
const path = require("node:path");
const DATA = path.join(__dirname, "..", "data");
const real = fs.existsSync(path.join(DATA, "forever_db.json")) && fs.existsSync(path.join(DATA, "wago", "TaxiPathNode.csv"));
test("real data: all 56 characters are valid and reach 60 on their race's route with the class quests layered", { skip: !real, timeout: 600000 }, () => {
  const { loadDb } = require("../lib/db");
  const { loadTravel } = require("../lib/travel");
  const { loadInns } = require("../planner/context");
  const { combos, RACES } = require("../lib/characters");
  const db = loadDb(DATA), graph = loadTravel(db, DATA), inns = loadInns(db, DATA);
  const all = combos(DATA);
  assert.strictEqual(all.length, 56);
  const failures = [];
  let layered = 0;
  // the Skyborne class starters, filed under class sorts and given on Zephras Isle
  const starters = { MAGE: [92481], HUNTER: [92482], ROGUE: [92483], SHAMAN: [92484], DRUID: [92485], WARRIOR: [92532] };
  for (const race of Object.keys(RACES)) {
    const chars = all.filter((c) => c.race === race);
    const route = planRoute(db, chars[0], { graph, inns });
    const out = layerClasses(db, route, chars, { graph });
    for (const ch of chars) {
      const { layered: got, left } = out.classes[ch.cls];
      for (const id of (race === "HighOrder" || race === "Windshaper") ? starters[ch.cls] || [] : []) {
        if (db.quests.has(id) && require("../lib/characters").eligible(db.quests.get(id), ch) && !got.includes(id)) failures.push(`${race} ${ch.cls}: isle starter ${id} not layered`);
      }
      if (race === "Dwarf" && ch.cls === "SHAMAN" && !left.some((l) => l.quest === 94373 && /not a classic quest/.test(l.reason))) failures.push("Dwarf SHAMAN: 94373 Call of Earth is not listed as left out");
      for (const id of got) if (left.some((l) => l.quest === id)) failures.push(`${race} ${ch.cls}: ${id} both layered and left out`);
      const r = validateRoute(db, out.route, ch, { graph, inns });
      layered += out.classes[ch.cls].layered.length;
      if (r.errors.length || r.endLevel < 60) failures.push(`${race} ${ch.cls}: level ${r.endLevel}, ${r.errors.slice(0, 3).join("; ")}`);
      // no class quest reaches a class it is not for
      for (const s of mine(out.route, ch.cls)) {
        const q = QUEST_ACTIONS.has(s.action) ? db.quests.get(s.quest) : null;
        if (q && q.classes && !(s.when && s.when.class === ch.cls)) failures.push(`${race} ${ch.cls}: ${s.action} of class quest ${q.id} without its class`);
      }
    }
  }
  assert.deepStrictEqual(failures, []);
  assert.ok(layered > 500, `${layered} class quests layered in all`);
});
