// Noir Guides, GPLv3. See LICENSE.
// Class trainer visits (tools/planner/training.js, task P3 of docs/superpowers/plans/2026-11-11-guide-rebuild.md,
// owner requirement 2026-11-11). Every map of the test world is 1000 yards square: one map percent is 10 yards.
const test = require("node:test");
const assert = require("node:assert");
const { testWorld } = require("./world");
const { checkRoute3 } = require("../planner/format3");
const { applies } = require("../planner/validate3");
const { addClassTraining, classTrainers, merchants, SELL_JUNK_LEVEL, TRAINER_YARDS, VISIT_MARGIN, MAX_DETOUR_SECONDS, VISIT_EVERY, FORCE_AFTER, TRIP_AFTER, MAX_TRIP_SECONDS } = require("../planner/training");

const P = (zone, x, y, r) => (r === undefined ? { zone, x, y } : { zone, x, y, r });
function world() {
  const w = testWorld();
  const trainer = (id, zone, x, y, friendly, subName) => w.db.npcs.set(id, { id, name: `Trainer ${id}`, friendly, subName, spawns: { [zone]: [[x, y]] } });
  trainer(600, 100, 32, 50, "A", "Warrior Trainer");   // 20 yards east of the hub at (30, 50)
  trainer(601, 100, 31, 50, "H", "Warrior Trainer");   // nearer, but Horde
  trainer(602, 100, 30, 52, "A", "Mage Trainer");
  trainer(603, 100, 55, 50, "A", "Rogue Trainer");     // 450 yards east of (10, 50)
  trainer(604, 100, 31, 51, "A", "Warrior Trainer?");  // not a trainer title
  return w;
}
// steps at one place, each with its own estimated level
let serial = 0;
const obj = (zone, x, y, when) => { const q = 5000 + serial++; const s = { id: `o${q}`, at: P(zone, x, y, 40), lines: [{ kind: "objective", quest: q, index: 1 }] }; if (when) s.when = when; return s; };
const section = (id, steps, extra = {}) => ({ id, name: "1-9 Westland", group: "Alliance", subgroup: "1-20", minLevel: 1, maxLevel: 12, zone: 100, next: [], steps, ...extra });
function chain(...lists) {
  const sections = lists.map((steps, i) => section(`human-0${i + 1}-09-westland`, steps));
  sections[0].start = true;
  sections.forEach((s, i) => { if (i + 1 < sections.length) s.next = [{ section: sections[i + 1].id }]; });
  return sections;
}
// levelOf from a list of levels in step order (the same for every class unless given per class)
function levelsOf(sections, list, perClass = {}) {
  const map = new Map();
  sections.flatMap((s) => s.steps).forEach((s, i) => map.set(s, i));
  return (cls, step) => { const l = (perClass[cls] || list)[map.get(step)]; return { start: l, end: l }; };
}
const visits = (sections) => sections.flatMap((s) => s.steps).filter((s) => /^t[A-Z]+-\d+$/.test(s.id));
const ids = (sections) => sections.flatMap((s) => s.steps.map((x) => x.id));
const route3 = (sections) => ({ format: 3, race: "Human", faction: "Alliance", sections });

test("the constants are the plan's", () => {
  assert.strictEqual(TRAINER_YARDS, 300);
  assert.strictEqual(MAX_DETOUR_SECONDS, 120);
  assert.strictEqual(VISIT_EVERY, 2);
  assert.strictEqual(FORCE_AFTER, 6);
});

test("trainers are found by their title and faction", () => {
  const { db } = world();
  assert.deepStrictEqual(classTrainers(db, "WARRIOR", "Alliance").map((t) => t.npc), [600]);
  assert.deepStrictEqual(classTrainers(db, "WARRIOR", "Horde").map((t) => t.npc), [601]);
  assert.deepStrictEqual(classTrainers(db, "PALADIN", "Alliance"), []);
});

test("a warrior's route visits a warrior trainer at even levels when one stands near the route", () => {
  const w = world();
  const a = Array.from({ length: 6 }, () => obj(100, 30, 50)), b = Array.from({ length: 6 }, () => obj(100, 30, 50));
  const sections = chain(a, b);
  const levels = [1, 2, 2.5, 3, 3.9, 4.2, 5, 5.5, 6, 7, 7.5, 8];
  const before = JSON.stringify(sections);
  const out = addClassTraining(w.db, sections, "Alliance", { graph: w.graph(), margin: 0, townStop: false, classes: ["WARRIOR"], levelOf: levelsOf(sections, levels) });
  assert.strictEqual(JSON.stringify(sections), before, "the input is not changed");
  assert.deepStrictEqual(visits(out).map((s) => s.id), ["tWARRIOR-2", "tWARRIOR-4", "tWARRIOR-6", "tWARRIOR-8"]);
  // each visit stands right before the first step at its level, in that step's section
  const all = ids(out);
  assert.strictEqual(all[all.indexOf("tWARRIOR-2") + 1], a[1].id);
  assert.strictEqual(all[all.indexOf("tWARRIOR-4") + 1], a[5].id);
  assert.deepStrictEqual(out[1].steps.slice(0, 3).map((s) => s.id), [b[0].id, b[1].id, "tWARRIOR-6"]);
  assert.deepStrictEqual(visits(out)[0], { id: "tWARRIOR-2", when: { class: "WARRIOR" }, at: P(100, 32, 50, 10), minLevel: 2,
    lines: [{ kind: "train", class: "WARRIOR", level: 2, npc: 600 }] });
  assert.strictEqual(checkRoute3(route3(out)), null);
});

test("a visit falls due only where the estimate is VISIT_MARGIN above its level", () => {
  const w = world();
  const a = Array.from({ length: 6 }, () => obj(100, 30, 50));
  const sections = chain(a);
  const out = addClassTraining(w.db, sections, "Alliance", { graph: w.graph(), townStop: false, classes: ["WARRIOR"], levelOf: levelsOf(sections, [1, 2, 2.2, 2.3, 4.1, 4.5]) });
  assert.strictEqual(VISIT_MARGIN, 0.3);
  const all = ids(out);
  // 2 and 2.2 are short of 2.3; 4.1 is short of 4.3
  assert.strictEqual(all[all.indexOf("tWARRIOR-2") + 1], a[3].id);
  assert.strictEqual(all[all.indexOf("tWARRIOR-4") + 1], a[5].id);
});
test("a visit that falls due before field work waits for the next stop that hands quests in near a trainer", () => {
  const w = world();
  const turnin = (q) => ({ id: `t${q}`, at: P(100, 30, 50, 10), lines: [{ kind: "turnin", quest: q }] });
  // due at the first objective; the turn-in back in town comes two objectives later
  const steps = [obj(100, 30, 50), obj(100, 31, 50), obj(100, 30, 51), turnin(7001), obj(100, 30, 50)];
  const sections = chain(steps);
  const out = addClassTraining(w.db, sections, "Alliance", { graph: w.graph(), classes: ["WARRIOR"], levelOf: levelsOf(sections, [2.5, 2.6, 2.7, 2.9, 3.2]) });
  const all = ids(out);
  assert.strictEqual(all[all.indexOf("tWARRIOR-2") + 1], "t7001");
  assert.strictEqual(checkRoute3(route3(out)), null);
  // without a town stop before the class is VISIT_EVERY levels further, the visit stays where it fell due
  const fields = [obj(100, 30, 50), obj(100, 31, 50), obj(100, 30, 51), obj(100, 31, 51)];
  const field = chain(fields);
  const late = addClassTraining(w.db, field, "Alliance", { graph: w.graph(), classes: ["WARRIOR"], levelOf: levelsOf(field, [2.5, 3, 4.3, 4.5]) });
  const order = ids(late);
  assert.strictEqual(order[order.indexOf("tWARRIOR-2") + 1], fields[0].id);
});
test("a visit carries its level as its minLevel, so a character under it is shown a grind instead of a stalled visit", () => {
  // Found by the simulator (task X1): a character a level under the estimate stood before "visit the trainer for
  // your level 4 spells" with nothing it could do. Spec 3.7: a step that needs a level has it as its minimum.
  const w = world();
  const a = Array.from({ length: 6 }, () => obj(100, 30, 50));
  const out = addClassTraining(w.db, chain(a), "Alliance", { graph: w.graph(), margin: 0, townStop: false, classes: ["WARRIOR"], levelOf: levelsOf(chain(a), [1, 2, 3, 4, 5, 6]) });
  const found = visits(out);
  assert.ok(found.length > 0);
  for (const v of found) assert.strictEqual(v.minLevel, v.lines[0].level, v.id);
});

test("a visit up to level 20 carries a sell-grey-items line at the nearest friendly merchant near the trainer", () => {
  const w = world();
  const vendor = (id, zone, x, y, friendly, isVendor = true) =>
    w.db.npcs.set(id, { id, name: `Merchant ${id}`, friendly, subName: "General Goods", vendor: isVendor, spawns: { [zone]: [[x, y]] } });
  vendor(650, 100, 35, 50, "A");        // 30 yards from the warrior trainer at (32, 50)
  vendor(651, 100, 32, 51, "H");        // nearer, but Horde
  vendor(652, 100, 33, 50, "A", false); // nearer, but no merchant
  vendor(653, 100, 34, 50, "AH");       // nearest friendly merchant: 20 yards
  vendor(654, 200, 1, 50, "A");         // across the zone border
  assert.strictEqual(SELL_JUNK_LEVEL, 20);
  assert.deepStrictEqual(merchants(w.db, "Alliance").map((m) => m.npc), [650, 653, 654]);
  const steps = Array.from({ length: 4 }, () => obj(100, 30, 50));
  const sections = chain(steps);
  const out = addClassTraining(w.db, sections, "Alliance", { graph: w.graph(), margin: 0, townStop: false, classes: ["WARRIOR"], levelOf: levelsOf(sections, [18, 20, 22, 24]) });
  const byId = new Map(visits(out).map((v) => [v.id, v]));
  assert.deepStrictEqual([...byId.keys()], ["tWARRIOR-18", "tWARRIOR-20", "tWARRIOR-22", "tWARRIOR-24"]);
  assert.deepStrictEqual(byId.get("tWARRIOR-18").lines, [{ kind: "train", class: "WARRIOR", level: 18, npc: 600 },
    { kind: "selljunk", npc: 653, at: P(100, 34, 50, 10) }]);
  assert.strictEqual(byId.get("tWARRIOR-20").lines[1].npc, 653, "level 20 still has it");
  assert.strictEqual(byId.get("tWARRIOR-22").lines.length, 1, "above level 20 the visit has its train line only");
  assert.strictEqual(byId.get("tWARRIOR-24").lines.length, 1);
  assert.strictEqual(checkRoute3(route3(out)), null);
});

test("a visit with no friendly merchant within 300 yards of the trainer has no sell line", () => {
  const w = world();
  w.db.npcs.set(660, { id: 660, name: "Far Merchant", friendly: "A", subName: "", vendor: true, spawns: { 100: [[70, 50]] } }); // 380 yards away
  const sections = chain(Array.from({ length: 2 }, () => obj(100, 30, 50)));
  const out = addClassTraining(w.db, sections, "Alliance", { graph: w.graph(), margin: 0, townStop: false, classes: ["WARRIOR"], levelOf: levelsOf(sections, [2, 3]) });
  assert.deepStrictEqual(visits(out).map((v) => v.lines.map((l) => l.kind)), [["train"]]);
});

test("a visit near the end of a walk into town comes after the walk, not before it", () => {
  // Found by the simulator (task X1): "visit the trainer in Brill", then "head into Tirisfal Glades": the character,
  // still in Durotar, was sent to the trainer before the way there.
  const w = world();
  const far = obj(200, 60, 50);
  const walk = { id: "g100@100", at: P(100, 30, 50, 20), lines: [{ kind: "goto", at: P(100, 30, 50, 20) }] };
  const here = obj(100, 30, 50);
  const sections = chain([far, walk, here]);
  const out = addClassTraining(w.db, sections, "Alliance", { graph: w.graph(), margin: 0, townStop: false, classes: ["WARRIOR"], levelOf: levelsOf(sections, [2, 2, 2]) });
  assert.deepStrictEqual(ids(out), [far.id, walk.id, "tWARRIOR-2", here.id]);
});

test("a visit is forced after 6 levels without one when the route passes a trainer's zone", () => {
  const w = world();
  // the rogue trainer stands 450 yards from the route: too far for an even-level visit, near enough on a mount
  const steps = Array.from({ length: 9 }, () => obj(100, 10, 50));
  const sections = chain(steps);
  const levels = [40, 41, 42, 43, 44, 45, 46, 47, 48];
  const out = addClassTraining(w.db, sections, "Alliance", { graph: w.graph(), margin: 0, townStop: false, classes: ["ROGUE"], levelOf: levelsOf(sections, levels) });
  assert.deepStrictEqual(visits(out).map((s) => s.id), ["tROGUE-40", "tROGUE-46"]);
  assert.strictEqual(visits(out)[0].lines[0].npc, 603);
  // a route that never enters a zone with a trainer gets no visit, however long it runs
  const east = chain(Array.from({ length: 9 }, () => obj(200, 50, 50)));
  assert.deepStrictEqual(visits(addClassTraining(w.db, east, "Alliance", { graph: w.graph(), margin: 0, townStop: false, classes: ["ROGUE"], levelOf: levelsOf(east, levels) })), []);
});

test("a visit never adds a detour over 120 seconds", () => {
  const w = world();
  // 450 yards on foot at run speed there and back is about 160 seconds
  const steps = Array.from({ length: 12 }, () => obj(100, 10, 50));
  const sections = chain(steps);
  const levels = [10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21];
  assert.deepStrictEqual(visits(addClassTraining(w.db, sections, "Alliance", { graph: w.graph(), margin: 0, townStop: false, classes: ["ROGUE"], levelOf: levelsOf(sections, levels) })), []);
});

test("other classes do not see the step", () => {
  const w = world();
  const rogueOnly = obj(100, 30, 50, { class: "ROGUE" });
  const steps = [obj(100, 30, 50), rogueOnly, obj(100, 30, 50), obj(100, 30, 50)];
  const sections = chain(steps);
  const levels = [1, 2, 2, 2];
  const out = addClassTraining(w.db, sections, "Alliance", { graph: w.graph(), margin: 0, townStop: false, classes: ["MAGE", "WARRIOR"], levelOf: levelsOf(sections, levels) });
  assert.deepStrictEqual(ids(out), [steps[0].id, rogueOnly.id, "tMAGE-2", "tWARRIOR-2", steps[2].id, steps[3].id],
    "a step for another class is never where a visit is written");
  for (const v of visits(out)) {
    const cls = v.lines[0].class;
    assert.deepStrictEqual(v.when, { class: cls });
    for (const other of ["WARRIOR", "MAGE", "ROGUE", "PRIEST"]) assert.strictEqual(applies(v.when, { race: "Human", cls: other }), other === cls);
  }
  assert.strictEqual(visits(out).find((v) => v.id === "tMAGE-2").lines[0].npc, 602);
});

test("no visit uses a trainer of the other faction", () => {
  const w = world();
  const sections = chain([obj(100, 30, 50), obj(100, 30, 50)]);
  const levelOf = levelsOf(sections, [2, 2]);
  const alliance = addClassTraining(w.db, sections, "Alliance", { graph: w.graph(), margin: 0, townStop: false, classes: ["WARRIOR"], levelOf });
  assert.deepStrictEqual(visits(alliance).map((v) => v.lines[0].npc), [600]);
  const horde = addClassTraining(w.db, sections, "Horde", { graph: w.graph(), margin: 0, townStop: false, classes: ["WARRIOR", "MAGE"], levelOf });
  assert.deepStrictEqual(visits(horde).map((v) => v.lines[0].npc), [601], "no Horde mage trainer stands in the world");
});

// Trips (the project lead's P3 follow-up 2): a flight or the hearthstone to a trainer's city and back. In the test
// world the warrior trainer 600 stands in Westland 120 yards from West Camp (node 1); East Mid (node 3) is in Eastland
// at (30, 50), a flight of about a minute from West Camp.
const flightStep = (node, zone, x, y) => ({ id: `f${node}`, at: P(zone, x, y, 10), lines: [{ kind: "getflight", node }] });
const flyStep = (from, to, zone, x, y) => ({ id: `y${from}-${to}`, at: P(zone, x, y, 10), lines: [{ kind: "fly", from, to }] });
const tripRoute = (x, first = flightStep(1, 100, 20, 50)) => [first, flightStep(3, 200, 30, 50), ...Array.from({ length: 10 }, () => obj(200, x, 50))];
const levelsOfSteps = (steps, list) => { const m = new Map(steps.map((s, i) => [s, list[i]])); return (cls, step) => (m.has(step) ? { start: m.get(step), end: m.get(step) } : undefined); };
const trip = (w, steps, levels, notes) => addClassTraining(w.db, chain(steps), "Alliance", { graph: w.graph(), margin: 0, townStop: false, classes: ["WARRIOR"], levelOf: levelsOfSteps(steps, levels), notes });
const TRIP_LEVELS = [2, 3, 4, 5, 6, 6.5, 7, 8, 9, 10, 11, 12];
// The index of the first step after a visit and the steps of its way back.
const afterTrip = (all, id) => { let k = all.indexOf(id) + 1; while (k < all.length && all[k].startsWith(`${id}:back`)) k++; return k; };

test("the trip constants are the project lead's", () => {
  assert.strictEqual(TRIP_AFTER, 4);
  assert.strictEqual(MAX_TRIP_SECONDS, 300);
});

test("after 4 levels without a visit, a visit flies to a trainer's city and back when that adds at most 300 seconds", () => {
  const w = world();
  const steps = tripRoute(60);   // the route works 300 yards east of East Mid
  const out = trip(w, steps, TRIP_LEVELS);
  assert.deepStrictEqual(visits(out).map((s) => s.id), ["tWARRIOR-2", "tWARRIOR-6", "tWARRIOR-10"]);
  const all = ids(out);
  assert.strictEqual(all[afterTrip(all, "tWARRIOR-6")], steps[4].id, "written at the first step of the level");
  const v = visits(out)[1];
  assert.deepStrictEqual(v.at, P(100, 32, 50, 10));
  assert.deepStrictEqual(v.lines, [{ kind: "train", class: "WARRIOR", level: 6, npc: 600 }]);
  assert.strictEqual(v.text, "Fly to Westland for class training, then return.");
  assert.strictEqual(visits(out)[0].text, undefined, "a visit on the way needs no text");
  assert.strictEqual(checkRoute3(route3(out)), null);
});

test("a trip's way there and back is written as steps the engine follows, not only as text", () => {
  // Found by the simulator (task X1): a visit in another zone said "Fly to Orgrimmar for class training, then
  // return." and had only its train line, so nothing on screen took the character there or back.
  const w = world();
  const steps = tripRoute(60);
  const out = trip(w, steps, TRIP_LEVELS);
  const all = out.flatMap((sec) => sec.steps);
  const at = all.findIndex((x) => x.id === "tWARRIOR-6");
  const go = [], back = [];
  for (let k = at - 1; k >= 0 && all[k].id.startsWith("tWARRIOR-6:go"); k--) go.unshift(all[k]);
  for (let k = at + 1; k < all.length && all[k].id.startsWith("tWARRIOR-6:back"); k++) back.push(all[k]);
  const lines = (list) => list.flatMap((x) => x.lines);
  assert.ok(go.length > 0 && back.length > 0, "steps there and back");
  assert.deepStrictEqual(lines(go).filter((l) => l.kind === "fly"), [{ kind: "fly", from: 3, to: 1 }], "the flight there");
  assert.deepStrictEqual(lines(back).filter((l) => l.kind === "fly"), [{ kind: "fly", from: 1, to: 3 }], "the flight back");
  for (const x of [...go, ...back]) {
    assert.deepStrictEqual(x.when, { class: "WARRIOR" }, x.id);
    for (const l of x.lines) assert.ok(["goto", "getflight", "fly", "transport", "hearth"].includes(l.kind), `${x.id}: ${l.kind}`);
  }
  assert.strictEqual(all[at + back.length + 1].id, steps[4].id, "then the route goes on where it was");
  assert.strictEqual(checkRoute3(route3(out)), null);
});

test("a trip after a boat starts where the boat lands, not at its dock", () => {
  // Found by the validator once trips became steps (task X1): the trip after "take the boat from Dustwallow Marsh to
  // Wetlands" started at the Dustwallow dock and took the boat again.
  const w = world();
  const boat = { id: "x200", at: P(400, 20, 90, 15), lines: [{ kind: "transport", mode: "boat", at: P(400, 20, 90, 15), to: P(200, 50, 90) }] };
  const steps = [flightStep(1, 100, 20, 50), flightStep(3, 200, 30, 50), obj(200, 60, 50), boat, ...Array.from({ length: 8 }, () => obj(200, 60, 50))];
  const out = trip(w, steps, TRIP_LEVELS);
  const all = out.flatMap((sec) => sec.steps);
  const go = all.filter((x) => x.id.startsWith("tWARRIOR-6:go"));
  assert.ok(go.length > 0, "a trip is written");
  assert.deepStrictEqual(go.flatMap((x) => x.lines).map((l) => l.kind), ["fly"], "from the landing: walk to East Mid and fly");
});

test("a trip after a hearthstone step without a place starts at the inn", () => {
  const w = world();
  const hearth = { id: "h", lines: [{ kind: "hearth", to: P(200, 50, 90) }] };
  const steps = [flightStep(1, 100, 20, 50), flightStep(3, 200, 30, 50), obj(400, 60, 50), hearth, ...Array.from({ length: 8 }, () => obj(200, 60, 50))];
  const out = trip(w, steps, TRIP_LEVELS);
  const go = out.flatMap((sec) => sec.steps).filter((x) => x.id.startsWith("tWARRIOR-6:go"));
  assert.ok(go.length > 0, "a trip is written");
  assert.deepStrictEqual(go.flatMap((x) => x.lines).map((l) => l.kind), ["fly"], "from the inn in Eastland, not from Farshore");
});

test("a trip that adds more than 300 seconds is not written, and the gap is noted with the cheapest trip", () => {
  const w = world();
  const notes = [];
  const out = trip(w, tripRoute(95), TRIP_LEVELS, notes);   // 650 yards from East Mid: over 300 seconds there and back
  assert.deepStrictEqual(visits(out).map((s) => s.id), ["tWARRIOR-2"]);
  assert.strictEqual(notes.length, 1);
  assert.strictEqual(notes[0].cls, "WARRIOR");
  assert.strictEqual(notes[0].from, 2);
  assert.strictEqual(notes[0].to, 12);
  assert.match(notes[0].why, /^the cheapest trip to a trainer adds \d+ seconds \(at most 300\)$/);
  assert.ok(Number(/adds (\d+)/.exec(notes[0].why)[1]) > MAX_TRIP_SECONDS);
});

test("a trip never uses a flight point the route has not learned", () => {
  const w = world();
  const steps = tripRoute(60, obj(100, 20, 50));   // West Camp is never learned
  assert.deepStrictEqual(visits(trip(w, steps, TRIP_LEVELS)).map((s) => s.id), ["tWARRIOR-2"]);
});

test("a trip waits for the route's flight master within the level it falls due", () => {
  const w = world();
  const steps = [flightStep(1, 100, 20, 50), flightStep(3, 200, 30, 50), obj(200, 60, 50), obj(200, 60, 50), obj(200, 60, 50),
    flyStep(3, 1, 200, 30, 50), obj(200, 60, 50)];
  const at = (levels) => { const out = trip(w, steps, levels); const all = ids(out); return all[afterTrip(all, visits(out)[1].id)]; };
  assert.strictEqual(at([2, 3, 4, 5, 6, 6.6, 7]), steps[5].id, "the flight master is passed at level 6: the trip starts there");
  assert.strictEqual(at([2, 3, 4, 5, 6, 7.2, 8]), steps[4].id, "passed only at level 7: the trip is taken at level 6 where it fits");
});

test("every class visits a trainer at least every 6 levels from 4 to 58 in the shipped routes, or the report says why", () => {
  const fs = require("node:fs");
  const path = require("node:path");
  const dir = path.join(__dirname, "..", "..", "NoirGuides", "Routes");
  const report = fs.readFileSync(path.join(__dirname, "..", "..", "docs", "routes", "REPORT.md"), "utf8");
  const files = fs.readdirSync(dir).filter((f) => f.endsWith(".lua"));
  assert.strictEqual(files.length, 10);
  const unexplained = [];
  for (const f of files) {
    const text = fs.readFileSync(path.join(dir, f), "utf8");
    const race = /race = "(\w+)"/.exec(text)[1];
    const part = report.split(/^## /m).find((s) => s.startsWith(`${race} (`)) || "";
    const row = (part.split("\n").find((l) => l.startsWith("| Class trainer gaps |")) || "");
    const levels = {};
    for (const m of text.matchAll(/id = "t([A-Z]+)-(\d+)"/g)) (levels[m[1]] = levels[m[1]] || new Set()).add(+m[2]);
    for (const [cls, set] of Object.entries(levels)) {
      const list = [...set].sort((a, b) => a - b);
      const points = [...list.filter((l) => l <= 58), 58];
      for (let i = 1; i < points.length; i++) {
        const a = points[i - 1], b = points[i];
        if (b - a > 6 && b > 4 && !row.includes(`${cls} ${a} to `)) unexplained.push(`${race} ${cls} ${a} to ${b}`);
      }
    }
  }
  assert.deepStrictEqual(unexplained, []);
});
