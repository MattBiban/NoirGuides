// Noir Guides, GPLv3. See LICENSE.
const test = require("node:test");
const assert = require("node:assert");
const { fixtureDb } = require("./fixture");
const { testWorld } = require("./world");
const { character, RACES } = require("../lib/characters");
const { PACE, mobXp, walkXp } = require("../lib/xp");
const { validateRoute } = require("../planner/validate");

RACES.Human.startArea = 1000;
const human = character("Human", "WARRIOR");
const at = { zone: 1000, x: 50, y: 50 };
const route = (steps) => ({ id: "t", format: 2, race: "Human", faction: "Alliance", steps, stats: {} });
const quest10 = [{ action: "accept", quest: 10, at, npc: 1 }, { action: "objective", quest: 10, at, npc: 3 }, { action: "turnin", quest: 10, at, npc: 1 }];

test("a correct route has no errors", () => {
  assert.deepStrictEqual(validateRoute(fixtureDb(), route(quest10), human).errors, []);
});
test("catches a quest of the other faction", () => {
  const e = validateRoute(fixtureDb(), route([{ action: "accept", quest: 13, at, npc: 7 }]), human).errors;
  assert.match(e[0], /^step 1: .*race/);
});
test("catches an accept below the required level", () => {
  const e = validateRoute(fixtureDb(), route([{ action: "accept", quest: 14, at, npc: 1 }]), human).errors;
  assert.match(e[0], /^step 1: .*level 40/);
});
test("catches a missing prerequisite", () => {
  const e = validateRoute(fixtureDb(), route([{ action: "accept", quest: 12, at, npc: 1 }]), human).errors;
  assert.match(e[0], /^step 1: .*prerequisite/);
});
test("catches a turn-in for a quest never accepted, and a turn-in before its objective", () => {
  const db = fixtureDb();
  assert.match(validateRoute(db, route([{ action: "turnin", quest: 10, at, npc: 1 }]), human).errors[0], /not in the log/);
  const r = route([{ action: "accept", quest: 10, at, npc: 1 }, { action: "turnin", quest: 10, at, npc: 1 }, { action: "objective", quest: 10, at, npc: 3 }]);
  assert.ok(validateRoute(db, r, human).errors.some((m) => /before its objective/.test(m)));
});
test("catches bad coordinates", () => {
  const db = fixtureDb();
  assert.ok(validateRoute(db, route([{ action: "accept", quest: 10, at: { zone: 1000, x: 150, y: 5 }, npc: 1 }]), human).errors.some((m) => /coordinates/.test(m)));
});
test("quests left in the log at the end are an error; a low end level is a warning", () => {
  const r = validateRoute(fixtureDb(), route([{ action: "accept", quest: 10, at, npc: 1 }]), human);
  assert.ok(r.errors.some((m) => /ends with 1 quest in the log: 10/.test(m)), r.errors.join("; "));
  assert.ok(r.warnings.some((m) => /ends at level/.test(m)));
});
test("catches a step with no place and a place that is not on a map", () => {
  const db = fixtureDb();
  const e = validateRoute(db, route([{ action: "accept", quest: 10, npc: 1 }]), human).errors;
  assert.match(e[0], /^step 1: .*no place/);
  const badZone = validateRoute(db, route([{ action: "accept", quest: 10, at: { zone: 999999, x: 50, y: 50 }, npc: 1 }]), human).errors;
  assert.match(badZone[0], /^step 1: .*not a zone with a map/);
  const t1 = validateRoute(db, route([{ action: "travel", at: { zone: 1000, x: -1, y: 50 } }]), human).errors;
  assert.match(t1[0], /^step 1: .*coordinates/);
  const t2 = validateRoute(db, route([{ action: "travel", at: { zone: 999999, x: 50, y: 50 } }]), human).errors;
  assert.match(t2[0], /^step 1: .*not a zone with a map/);
  assert.match(validateRoute(db, route([{ action: "travel", zone: 1000 }]), human).errors[0], /^step 1: travel has no place/);
  assert.deepStrictEqual(validateRoute(db, route([{ action: "travel", at }]), human).errors, []);
});
test("a grind step names the next whole level, and two never follow each other", () => {
  const db = fixtureDb();
  for (const level of [61, 0, 2.5, "30", undefined]) {
    const r = validateRoute(db, route([{ action: "grind", level, at }]), human);
    assert.match(r.errors[0], /^step 1: grind .*level/);
    assert.strictEqual(r.endLevel, 1);
  }
  const ok = validateRoute(db, route([{ action: "grind", level: 2, at }]), human);
  assert.deepStrictEqual(ok.errors, []);
  assert.strictEqual(ok.endLevel, 2);
  const far = validateRoute(db, route([{ action: "grind", level: 5, at }]), human);
  assert.match(far.errors[0], /^step 1: grind to level 5 from level 1: more than one level/);
  const twice = validateRoute(db, route([{ action: "grind", level: 2, at }, { action: "grind", level: 3, at }]), human);
  assert.match(twice.errors[0], /^step 2: two grind steps in a row/);
  assert.match(validateRoute(db, route([{ action: "grind", level: 2 }]), human).errors[0], /no place/);
});
test("an unknown action and a route in another format are errors", () => {
  const db = fixtureDb();
  assert.match(validateRoute(db, route([{ action: "dance", at }]), human).errors[0], /unknown action dance/);
  assert.ok(validateRoute(db, { ...route(quest10), format: 1 }, human).errors.some((m) => /format 2/.test(m)));
});

// ---------------------------------------------------------------------------------------------------------------
// Travel, on the small world of test/world.js
const M = (zone, x, y) => ({ zone, x, y });
const westCamp = M(100, 20, 50), eastMid = M(200, 30, 50), eastCamp = M(200, 80, 50), dockA = M(100, 50, 90), farA = M(400, 50, 10);
function check(steps, ch, change) {
  const w = testWorld();
  w.npc(10, 100, 30, 50); w.npc(11, 200, 80, 52); w.npc(12, 400, 50, 12); w.npc(13, 300, 50, 50); w.npc(14, 500, 50, 48); w.npc(15, 100, 50, 52);
  w.errand(1, 10, 11, 100); w.errand(2, 10, 12, 100); w.errand(3, 10, 13, 100); w.errand(77, 14, 15, 500);
  w.errand(4, 10, 10, 100, { requiredClasses: 8 }); // rogues only
  if (change) change(w);
  ch = ch || w.human();
  return validateRoute(w.db, { id: "t", format: 2, race: ch.race, faction: ch.faction, steps, stats: {} }, ch, { graph: w.graph(), inns: w.inns });
}
const errors = (steps, ch, change) => check(steps, ch, change).errors;

test("a route that learns its flights, flies, sails and hearths is correct", () => {
  const r = check([
    { action: "accept", quest: 1, at: M(100, 30, 50), npc: 10 },
    { action: "accept", quest: 2, at: M(100, 30, 50), npc: 10 },
    { action: "sethearth", at: M(100, 22, 50), npc: 800 },
    { action: "getflight", node: 1, at: westCamp, npc: 901 },
    { action: "travel", at: eastMid },
    { action: "getflight", node: 3, at: eastMid, npc: 903 },
    { action: "getflight", node: 2, at: eastCamp, npc: 902 },
    { action: "turnin", quest: 1, at: M(200, 80, 52), npc: 11 },
    { action: "fly", from: 2, to: 1, at: eastCamp },
    { action: "transport", kind: "boat", at: dockA, to: farA },
    { action: "turnin", quest: 2, at: M(400, 50, 12), npc: 12 },
    { action: "hearth", to: M(100, 22, 50) },
    { action: "fly", from: 1, to: 3, at: westCamp },
  ]);
  assert.deepStrictEqual(r.errors, []);
  assert.strictEqual(r.levels.length, 13);
  assert.ok(r.seconds > 200 + 15, "the boat and the hearthstone take their time");
});
test("fails on a flight that is not learned, at either end or on the way", () => {
  const learn1 = { action: "getflight", node: 1, at: westCamp, npc: 901 }, learn2 = [{ action: "travel", at: eastCamp }, { action: "getflight", node: 2, at: eastCamp, npc: 902 }];
  assert.match(errors([{ action: "fly", from: 1, to: 3, at: westCamp }])[0], /^step 1: flight from node 1.*not learned/);
  assert.match(errors([learn1, { action: "fly", from: 1, to: 3, at: westCamp }])[0], /^step 2: flight to node 3.*not learned/);
  // 1 and 2 are learned, 3 between them is not: no path through learned points
  const e = errors([learn1, ...learn2, { action: "fly", from: 2, to: 1, at: eastCamp }]);
  assert.match(e[0], /^step 4: no flight path from node 2 to node 1 through learned flight points/);
  assert.match(errors([{ action: "getflight", node: 4, at: M(100, 20, 60), npc: 904 }])[0], /node 4 .*Alliance/);
  assert.match(errors([{ action: "getflight", node: 99, at: westCamp, npc: 1 }])[0], /unknown flight point 99/);
  assert.match(errors([{ action: "getflight", node: 1, at: M(100, 60, 50), npc: 901 }])[0], /not at the flight master/);
  assert.match(errors([learn1, { action: "travel", at: eastMid }, { action: "getflight", node: 3, at: eastMid, npc: 903 }, { action: "fly", from: 1, to: 3, at: eastMid }])[0], /^step 4: .*does not leave from/);
});
test("fails on a transport the faction cannot use, one whose quest or level is missing, and one that does not exist", () => {
  assert.match(errors([{ action: "transport", kind: "boat", at: dockA, to: farA }], testWorld().orc())[0], /^step 1: the Horde cannot use/);
  assert.match(errors([{ action: "transport", kind: "boat", at: M(100, 10, 10), to: farA }])[0], /^step 1: no transport runs from/);
  assert.match(errors([{ action: "transport", kind: "zeppelin", at: dockA, to: farA }])[0], /is a boat, not a zeppelin/);
  assert.match(errors([{ action: "travel", at: M(200, 50, 90) }, { action: "transport", kind: "boat", at: M(200, 50, 90), to: M(400, 20, 90) }])[0], /^step 2: .*who may board.*not confirmed/);
  // off the isle: level 3 and quest 77
  const sky = { action: "transport", kind: "boat", at: M(500, 50, 50), to: M(100, 50, 50) };
  const run = (steps) => errors(steps, testWorld().human("WARRIOR", 500));
  let e = run([sky]);
  assert.ok(e.some((m) => /^step 1: .*needs level 3/.test(m)) && e.some((m) => /^step 1: .*needs quest 77/.test(m)), e.join("; "));
  e = run([{ action: "accept", quest: 77, at: M(500, 50, 48), npc: 14 }, { action: "grind", level: 2, at: M(500, 50, 48) }, sky]);
  assert.ok(e.some((m) => /needs level 3/.test(m)) && !e.some((m) => /needs quest/.test(m)), e.join("; "));
  // one way: nothing sails back
  assert.match(errors([{ action: "transport", kind: "boat", at: M(100, 50, 50), to: M(500, 50, 50) }])[0], /^step 1: no transport runs from/);
});
test("fails on a step on another continent, or over water, without a leg that got the player there", () => {
  assert.match(errors([{ action: "accept", quest: 1, at: M(100, 30, 50), npc: 10 }, { action: "turnin", quest: 1, at: M(400, 50, 12), npc: 12 }])[0],
    /^step 2: turnin of quest 1 is in zone 400 on another continent than the player/);
  const e = errors([{ action: "accept", quest: 3, at: M(100, 30, 50), npc: 10 }, { action: "turnin", quest: 3, at: M(300, 50, 50), npc: 13 }]);
  assert.match(e[0], /^step 2: there is no way on foot from zone 100 to zone 300/);
  // the first step must be on the continent the race starts on
  assert.match(errors([{ action: "travel", at: M(400, 50, 50) }])[0], /another continent/);
});
test("fails on a hearth that is not bound, bound elsewhere, or used again within the hour", () => {
  const bind = { action: "sethearth", at: M(100, 22, 50), npc: 800 };
  assert.match(errors([{ action: "hearth", to: M(100, 22, 50) }])[0], /^step 1: hearth before the hearthstone is bound/);
  assert.match(errors([bind, { action: "hearth", to: M(200, 78, 50) }])[0], /^step 2: hearth to zone 200.*bound in zone 100/);
  assert.match(errors([bind, { action: "hearth", to: M(100, 22, 50) }, { action: "travel", at: eastMid }, { action: "hearth", to: M(100, 22, 50) }])[0], /^step 4: .*cooldown/);
  assert.match(errors([{ action: "sethearth", at: M(100, 60, 60), npc: 800 }])[0], /^step 1: .*no innkeeper/);
  assert.match(errors([{ action: "sethearth", at: M(100, 22, 50), npc: 10 }])[0], /^step 1: .*no innkeeper/);
});
test("a when step is left out for other classes, and fails when its quest is not open to the class it names", () => {
  const rogue = [{ action: "accept", quest: 4, at: M(100, 30, 50), npc: 10, when: { class: "ROGUE" } }, { action: "turnin", quest: 4, at: M(100, 30, 50), npc: 10, when: { class: "ROGUE" } }];
  assert.deepStrictEqual(errors(rogue), [], "a warrior's route does not contain the rogue's steps");
  assert.deepStrictEqual(errors(rogue, testWorld().human("ROGUE")), []);
  const wrong = rogue.map((s) => ({ ...s, when: { class: "MAGE" } }));
  for (const ch of [testWorld().human("WARRIOR"), testWorld().human("MAGE")]) {
    assert.ok(errors(wrong, ch).some((m) => /^step 1: .*for MAGE.*quest 4 is not open to that class/.test(m)));
  }
  assert.match(errors([{ ...rogue[0], when: { class: "BARD" } }])[0], /unknown class BARD/);
  // without a when, the class quest reaches a class it is not for
  assert.ok(errors([{ action: "accept", quest: 4, at: M(100, 30, 50), npc: 10 }]).some((m) => /not open to this race or class/.test(m)));
  // a minimum level: the step is not part of the route below it
  const r = check([{ action: "accept", quest: 1, at: M(100, 30, 50), npc: 10, when: { level: 5 } }]);
  assert.deepStrictEqual(r.errors, []);
});
test("the level at each step counts quest, objective and walking XP", () => {
  const steps = [
    { action: "accept", quest: 5, at: M(100, 30, 50), npc: 10 },
    { action: "objective", quest: 5, at: M(100, 90, 50), npc: 20 },
    { action: "turnin", quest: 5, at: M(100, 30, 50), npc: 10 },
  ];
  const quiet = check(steps, null, (w) => { w.npc(20, 100, 90, 50, ""); w.kill(5, 10, 20, 100); });
  const wild = check(steps, null, (w) => { w.herd(20, 100, 90, 50); w.kill(5, 10, 20, 100); });
  assert.deepStrictEqual(quiet.errors, []);
  assert.deepStrictEqual(wild.errors, []);
  const total = (r) => { let sum = r.xp; for (let level = 1; level < r.endLevel; level++) sum += [0, 400, 900, 1400][level]; return sum; };
  assert.strictEqual(total(quiet), PACE.OBJECTIVE_KILLS * mobXp(1, 1) + 110);
  // 600 yards out at level 1, 600 back at level 2 (the kills gave it): creatures of level 1 both times
  const band = { min: 1, max: 1, wild: true };
  assert.strictEqual(total(wild), walkXp(600, band, 1) + PACE.OBJECTIVE_KILLS * mobXp(1, 1) + walkXp(600, band, 2) + 110);
  assert.deepStrictEqual(wild.levels, [1, 1, 2]);
});
test("replays when a quest is offered: its top level, a quest in the log that hides it, one that ends it, one that opens it, and exclusive quests", () => {
  const town = M(100, 30, 50);
  const accept = (quest) => ({ action: "accept", quest, at: town, npc: 10 });
  const turnin = (quest) => ({ action: "turnin", quest, at: town, npc: 10 });
  const grind = (level) => ({ action: "grind", level, at: town });
  const more = (w) => {
    w.errand(40, 10, 10, 100, { requiredMaxLevel: 1 });        // offered up to level 1
    w.errand(41, 10, 10, 100, { disabledByQuest: 4 });         // not offered while quest 4 is in the log
    w.errand(42, 10, 10, 100, { availableUntilCompleted: 43 }); // gone once quest 43 is handed in
    w.errand(43, 10, 10, 100);
    w.errand(44, 10, 10, 100, { availableStartingWith: 43 });   // offered once quest 43 is taken
    w.errand(45, 10, 10, 100, { exclusiveTo: [46] }); w.errand(46, 10, 10, 100, { exclusiveTo: [45] });
  };
  const rogue = { ...character("Human", "ROGUE"), startArea: 100 };
  const fails = (steps, pattern, ch) => { const e = errors(steps, ch, more); assert.ok(e.some((m) => pattern.test(m)), e.join("; ") || "no error"); };
  assert.deepStrictEqual(errors([accept(40), turnin(40)], null, more), []);
  fails([grind(2), accept(40)], /offered up to level 1/);
  assert.deepStrictEqual(errors([accept(41), turnin(41)], null, more), []);
  fails([accept(4), accept(41)], /not offered while quest 4/, rogue);
  fails([accept(43), turnin(43), accept(42)], /no longer offered once quest 43/);
  fails([accept(44)], /offered only after quest 43/);
  assert.deepStrictEqual(errors([accept(43), accept(44), turnin(43), turnin(44)], null, more), []);
  fails([accept(45), accept(46)], /exclusive with 45/);
  fails([accept(46), turnin(46), accept(45)], /exclusive with 46/);
});
