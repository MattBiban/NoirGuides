// Noir Guides, GPLv3. See LICENSE.
// Sections, level ranges, grind targets and chaining (tools/planner/sections.js, task P2 of
// docs/superpowers/plans/2026-11-11-guide-rebuild.md). Every map of the test world is 1000 yards square.
const test = require("node:test");
const fs = require("node:fs");
const assert = require("node:assert");
const { testWorld } = require("./world");
const { classMask } = require("../lib/characters");
const { planRoute } = require("../planner/plan");
const { layerClasses } = require("../planner/classes");
const { validateRoute } = require("../planner/validate");
const { checkRoute3 } = require("../planner/format3");
const { bundleSteps, flatten } = require("../planner/bundle");
const { splitSections, insertGrinds, regrindSections, stepLevels, MIN_SECTION_WORK, MAX_SECTION_STEPS, OUTLEVEL_MARGIN, BANDS } = require("../planner/sections");

// Steps in format 3 shape, as bundleSteps gives them. Each work step here has one work line.
let serial = 0;
const obj = (zone, q = 1000 + serial++) => ({ id: `o${q}`, at: { zone, x: 50, y: 50, r: 40 }, lines: [{ kind: "objective", quest: q, index: 1 }] });
const acc = (zone, q, x = 30, y = 30) => ({ id: `a${q}`, at: { zone, x, y, r: 10 }, lines: [{ kind: "accept", quest: q }] });
const turn = (zone, q, x = 30, y = 30) => ({ id: `t${q}`, at: { zone, x, y, r: 10 }, lines: [{ kind: "turnin", quest: q }] });
const go = (zone, x = 10, y = 10) => ({ id: `g${zone}@${zone}`, at: { zone, x, y, r: 20 }, lines: [{ kind: "goto", at: { zone, x, y, r: 20 } }] });
const fly = (from, to, zone) => ({ id: `y${from}-${to}`, at: { zone, x: 20, y: 50, r: 10 }, lines: [{ kind: "fly", from, to }] });
const run = (zone, n) => Array.from({ length: n }, () => obj(zone));
const flat = (n, level) => Array.from({ length: n }, () => ({ start: level, end: level }));
// unique ids in a list, as bundleSteps makes them
function uniq(steps) {
  const seen = new Map();
  for (const s of steps) { const c = (seen.get(s.id) || 0) + 1; seen.set(s.id, c); if (c > 1) s.id += `#${c}`; }
  return steps;
}
const split = (w, steps, levels, classLevels = {}) => splitSections(w.db, "Human", "Alliance", { steps: uniq(steps) }, levels, classLevels);
const sizes = (sections) => sections.map((s) => s.steps.length);
const clone = (o) => JSON.parse(JSON.stringify(o));
const route3 = (sections) =>({ format: 3, race: "Human", faction: "Alliance", sections });

test("the constants are the plan's", () => {
  assert.strictEqual(MIN_SECTION_WORK, 12);
  assert.strictEqual(MAX_SECTION_STEPS, 250);
  assert.strictEqual(OUTLEVEL_MARGIN, 3);
  assert.deepStrictEqual(BANDS, [20, 30, 40, 50]);
});

test("a zone change with 12 or more work lines starts a section; a shorter detour stays in the section", () => {
  const w = testWorld();
  // 15 in Westland, a 5 line detour to Eastland, 3 more in Westland, then 12 in Farshore
  const steps = [...run(100, 15), ...run(200, 5), ...run(100, 3), ...run(400, 12)];
  const sections = split(w, steps, flat(steps.length, 5));
  assert.deepStrictEqual(sizes(sections), [23, 12]);
  assert.deepStrictEqual(sections.map((s) => s.zone), [100, 400]);
  // 11 lines in Farshore are a detour too
  const short = [...run(100, 15), ...run(400, 11)];
  assert.deepStrictEqual(sizes(split(w, short, flat(short.length, 5))), [26]);
  // the lines are counted, not the steps: 6 steps of two lines are 12 work lines
  const two = () => { const s = obj(400); s.lines.push({ kind: "objective", quest: s.lines[0].quest, index: 2 }); return s; };
  const lines = [...run(100, 15), ...Array.from({ length: 6 }, two)];
  assert.deepStrictEqual(sizes(split(w, lines, flat(lines.length, 5))), [15, 6]);
});

test("movement steps open the section of the zone they lead to", () => {
  const w = testWorld();
  const steps = [...run(100, 12), go(100, 100, 50), fly(1, 3, 100), go(200), ...run(200, 12), go(200, 90, 90)];
  const sections = split(w, steps, flat(steps.length, 5));
  assert.deepStrictEqual(sizes(sections), [12, 16]);
  assert.deepStrictEqual(sections[1].steps.slice(0, 3).map((s) => s.lines[0].kind), ["goto", "fly", "goto"]);
  assert.strictEqual(sections[0].steps[11].lines[0].kind, "objective");
  assert.strictEqual(sections[1].steps[15].lines[0].kind, "goto", "movement after the last work stays in the last section");
});

test("a long stay is split at level 20, 30, 40 or 50 only when both parts keep 12 work lines", () => {
  const w = testWorld();
  const steps = run(100, 30);
  const levels = [...flat(15, 19), ...flat(15, 20)];
  const sections = split(w, steps, levels);
  assert.deepStrictEqual(sizes(sections), [15, 15]);
  assert.deepStrictEqual(sections.map((s) => [s.minLevel, s.subgroup]), [[19, "1-20"], [20, "20-30"]]);
  // crossing 30 with 5 lines left: no split
  const late = run(100, 30);
  assert.deepStrictEqual(sizes(split(w, late, [...flat(25, 29), ...flat(5, 30)])), [30]);
  // crossing 31 to 32 is not a band
  const none = run(100, 30);
  assert.deepStrictEqual(sizes(split(w, none, [...flat(15, 31), ...flat(15, 32)])), [30]);
  // two bands in one stay
  const both = run(100, 45);
  assert.deepStrictEqual(sizes(split(w, both, [...flat(15, 39), ...flat(15, 40), ...flat(15, 50)])), [15, 15, 15]);
});

test("no section has more than 250 steps", () => {
  const w = testWorld();
  const steps = run(100, 600);
  const sections = split(w, steps, flat(600, 10));
  assert.ok(sections.length >= 3, `${sections.length} sections`);
  for (const s of sections) {
    assert.ok(s.steps.length <= MAX_SECTION_STEPS, `${s.id} has ${s.steps.length} steps`);
    assert.ok(s.steps.length >= MIN_SECTION_WORK, `${s.id} has ${s.steps.length} steps`);
  }
  assert.strictEqual(sizes(sections).reduce((a, b) => a + b, 0), 600);
  assert.strictEqual(checkRoute3(route3(sections)), null);
});

test("names read 'min-end Zone' from the estimated levels, single level when equal, and a class gets its own name only when its range differs", () => {
  const w = testWorld();
  const rogue = run(100, 2).map((s) => ({ ...s, when: { class: "ROGUE" } }));
  const steps = [...rogue, ...run(100, 12), ...run(200, 12)];
  const ramp = (from, to, n) => Array.from({ length: n }, (_, i) => ({ start: from + ((to - from) * i) / n, end: from + ((to - from) * (i + 1)) / n }));
  // the shared route: 1 to 6.5 over Westland, then 7 to 7.8 in Eastland
  const levels = [...flat(2, 1), ...ramp(1, 6.5, 12), ...ramp(7, 7.8, 12)];
  // the rogue starts at 1 on its two own steps and reaches Westland's work at 3; the warrior skips those steps
  const classLevels = {
    ROGUE: [...flat(2, 1), ...ramp(3, 7.5, 12), ...ramp(7.5, 7.9, 12)],
    WARRIOR: [...flat(2, 9), ...ramp(1, 6.5, 12), ...ramp(7, 7.8, 12)],
  };
  const sections = split(w, steps, levels, classLevels);
  assert.deepStrictEqual(sections.map((s) => s.name), ["1-6 Westland", "7 Eastland"]);
  assert.deepStrictEqual(sections[0].names, { ROGUE: "1-7 Westland" }, "the rogue ends Westland at 7; the warrior's range is the shared one");
  assert.strictEqual(sections[1].names, undefined);
});

test("ids are padded, slugged, unique and stable", () => {
  const make = () => {
    const w = testWorld();
    serial = 0;
    const steps = [...run(100, 12), ...run(300, 12), ...run(100, 12)];
    return split(w, steps, [...flat(12, 5), ...flat(12, 5), ...flat(12, 5)]);
  };
  const a = make().map((s) => s.id), b = make().map((s) => s.id);
  assert.deepStrictEqual(a, ["human-05-05-westland", "human-05-05-lonely-isle", "human-05-05-westland-2"]);
  assert.deepStrictEqual(a, b);
  const w = testWorld();
  const ranged = split(w, run(100, 12), Array.from({ length: 12 }, (_, i) => ({ start: 3 + i, end: 4 + i })));
  assert.strictEqual(ranged[0].id, "human-03-15-westland");
});

test("maxLevel is the end level plus 3, at most 60", () => {
  const w = testWorld();
  const steps = [...run(100, 12), ...run(200, 12)];
  const sections = split(w, steps, [...flat(12, 10), ...flat(11, 58), { start: 58, end: 59.5 }]);
  assert.deepStrictEqual(sections.map((s) => [s.minLevel, s.maxLevel]), [[10, 13], [58, 60]]);
  assert.strictEqual(sections[1].name, "58-59 Eastland");
});

test("exactly one start section and every section but the last links the next", () => {
  const w = testWorld();
  const steps = [...run(100, 12), ...run(200, 12), ...run(400, 12)];
  const sections = split(w, steps, flat(steps.length, 4));
  assert.deepStrictEqual(sections.map((s) => s.start === true), [true, false, false]);
  assert.deepStrictEqual(sections[0].next, [{ section: sections[1].id }]);
  assert.deepStrictEqual(sections[1].next, [{ section: sections[2].id }]);
  assert.deepStrictEqual(sections[2].next, []);
  for (const s of sections) { assert.strictEqual(s.group, "Alliance"); assert.strictEqual(s.subgroup, "1-20"); }
  assert.strictEqual(checkRoute3(route3(sections)), null);
});

test("a step above the estimated level gets a grind step before it, at the last work place", () => {
  const w = testWorld();
  w.npc(10, 100, 30, 30); w.npc(20, 100, 60, 60, "");
  w.kill(1, 10, 20, 100, { requiredLevel: 6, questLevel: 6 });
  const need = { ...acc(100, 1, 70, 70), minLevel: 6 };
  const last = obj(100);
  const steps = [last, go(100, 70, 60), need];
  const out = insertGrinds(steps, flat(3, 4));
  assert.deepStrictEqual(out.map((s) => s.id), [last.id, "l6@100", "g100@100", "a1"], "the grind comes before the way to the step");
  assert.deepStrictEqual(out[1], { id: "l6@100", at: { zone: 100, x: 50, y: 50 }, lines: [{ kind: "grind", level: 6 }] });
  assert.strictEqual(steps.length, 3, "the given list is not changed");
  // at the estimated level or above: no grind; a fraction of a level below is a level below
  assert.strictEqual(insertGrinds(steps, flat(3, 6)).length, 3);
  assert.strictEqual(insertGrinds(steps, flat(3, 5.9)).length, 4);
  // a class step gets a grind for its class only
  const rogueStep = { ...need, when: { class: "ROGUE" } };
  assert.deepStrictEqual(insertGrinds([last, rogueStep], flat(2, 4))[1].when, { class: "ROGUE" });
});

test("a class step's grind lifts only that class, and later shared steps still get their own grind", () => {
  const w = testWorld();
  const o1 = obj(100), o2 = obj(100);
  const rogueStep = { id: "r1", at: { zone: 100, x: 40, y: 40, r: 10 }, lines: [{ kind: "objective", quest: 1, index: 1 }], minLevel: 10, when: { class: "ROGUE" } };
  const shared = { id: "s2", at: { zone: 100, x: 45, y: 45, r: 10 }, lines: [{ kind: "objective", quest: 2, index: 1 }], minLevel: 9 };
  // without class levels: the rogue grinds to 10, everyone else still arrives at s2 at 8 and needs 9
  const out = insertGrinds([o1, rogueStep, o2, shared], flat(4, 8));
  assert.deepStrictEqual(out.map((s) => [s.id, s.when]), [[o1.id, undefined], ["l10@100", { class: "ROGUE" }], ["r1", { class: "ROGUE" }], [o2.id, undefined], ["l9@100", undefined], ["s2", undefined]]);
  // with class levels: a class is checked at its own level
  const tail = run(100, 12);
  const steps = [obj(100), rogueStep, ...tail];
  const ahead = split(w, steps.map(clone), flat(steps.length, 8), { ROGUE: flat(steps.length, 10), WARRIOR: flat(steps.length, 8) });
  assert.ok(!ahead[0].steps.some((s) => s.lines[0].kind === "grind"), "a rogue already at 10 gets no grind, even with the shared estimate at 8");
  const behind = split(w, steps.map(clone), flat(steps.length, 10), { ROGUE: flat(steps.length, 8), WARRIOR: flat(steps.length, 10) });
  assert.deepStrictEqual(behind[0].steps.filter((s) => s.lines[0].kind === "grind").map((s) => [s.id, s.when]), [["l10@100", { class: "ROGUE" }]],
    "a rogue at 8 grinds although the shared estimate is 10");
  // a step for two classes where only one is behind: the grind names that one
  const pair = { ...rogueStep, when: { class: ["ROGUE", "WARRIOR"] } };
  const two = [obj(100), pair, ...run(100, 12)];
  const s3 = split(w, two, flat(two.length, 8), { ROGUE: flat(two.length, 10), WARRIOR: flat(two.length, 8), MAGE: flat(two.length, 8) });
  assert.deepStrictEqual(s3[0].steps.filter((s) => s.lines[0].kind === "grind").map((s) => s.when), [{ class: "WARRIOR" }]);
  // a class grind does not lift the shared estimate: the section's range is the shared one
  assert.strictEqual(behind[0].minLevel, 10);
  assert.strictEqual(behind[0].name, "10 Westland");
  assert.strictEqual(checkRoute3(route3(s3)), null);
});

test("a grind moved to the next section never takes it over 250 steps", () => {
  const w = testWorld();
  const steps = [...run(100, 249), { ...obj(100), minLevel: 7 }, ...run(100, 249)];
  const sections = split(w, steps, flat(steps.length, 4));
  for (const s of sections) assert.ok(s.steps.length <= MAX_SECTION_STEPS, `${s.id} has ${s.steps.length} steps`);
  assert.strictEqual(sizes(sections).reduce((a, b) => a + b, 0), steps.length + 1);
  for (const s of sections.slice(0, -1)) {
    const last = s.steps[s.steps.length - 1];
    assert.ok(!(last.lines[0].kind === "grind" && last.lines[0].level > 5), `${s.id} ends with ${last.id}`);
  }
});

test("what the data cannot settle is written to the notes: accepts grey or uncapped, zones without a name", () => {
  const w = testWorld();
  w.npc(10, 100, 30, 30); w.npc(20, 100, 60, 60, "");
  w.kill(1, 10, 20, 100, { questLevel: 5 }); w.kill(2, 10, 20, 100, { questLevel: 5 });
  const notes = [];
  // quest 1 gives XP up to 13 but the step needs 15: no cap; quest 2 is taken at 20, already grey
  const steps = [{ ...acc(100, 1), minLevel: 15 }, acc(100, 2), ...run(100, 12), ...run(999, 12)];
  const sections = splitSections(w.db, "Human", "Alliance", { steps: uniq(steps) }, flat(steps.length, 20), {}, notes);
  assert.strictEqual(sections[0].steps.find((s) => s.id === "a1").maxLevel, undefined);
  assert.strictEqual(sections[0].steps.find((s) => s.id === "a2").maxLevel, 13);
  assert.strictEqual(sections[1].name, "20 Zone 999");
  const text = notes.join("\n");
  assert.match(text, /a1.*quest 1.*13.*15/);
  assert.match(text, /a2.*quest 2.*13.*20/);
  assert.match(text, /zone 999.*no name/);
  // notes are optional
  assert.doesNotThrow(() => split(w, steps.map(clone), flat(steps.length, 20)));
});

test("no section ends with a grind of more than one level", () => {
  const w = testWorld();
  w.npc(10, 200, 30, 30);
  w.kill(1, 10, 10, 200, { requiredLevel: 8, questLevel: 8 });
  w.kill(2, 10, 10, 200, { requiredLevel: 6, questLevel: 6 });
  // Westland at 5, then Eastland whose first quest needs 8: the grind is done in Westland, at the start of Eastland's section
  const steps = [...run(100, 12), go(200), { ...acc(200, 1), minLevel: 8 }, ...run(200, 12)];
  const levels = [...flat(14, 5), ...flat(12, 8)];
  const sections = split(w, steps, levels);
  assert.strictEqual(sections.length, 2);
  assert.deepStrictEqual(sections[1].steps.slice(0, 3).map((s) => s.id), ["l8@100", "g200@200", "a1"]);
  assert.strictEqual(sections[1].minLevel, 5);
  assert.strictEqual(sections[0].steps[sections[0].steps.length - 1].lines[0].kind, "objective");
  // a grind of one level may end a section
  const one = [...run(100, 12), go(200), { ...acc(200, 2), minLevel: 6 }, ...run(200, 12)];
  const s2 = split(w, one, [...flat(14, 5), ...flat(12, 6)]);
  assert.strictEqual(s2[0].steps[s2[0].steps.length - 1].id, "l6@100");
});

test("accept-only steps get the last level their quests give XP, and the quests' later lines skip if missing", () => {
  const w = testWorld();
  w.npc(10, 100, 30, 30); w.npc(20, 100, 60, 60, "");
  w.kill(1, 10, 20, 100, { questLevel: 5 }); w.kill(2, 10, 20, 100, { questLevel: 7 });
  w.kill(3, 10, 20, 100, { questLevel: 4 }); w.kill(4, 10, 20, 100, { questLevel: 57 });
  const both = { id: "a1.a2", at: { zone: 100, x: 30, y: 30, r: 10 }, lines: [{ kind: "accept", quest: 1 }, { kind: "accept", quest: 2 }] };
  const mixed = { id: "t9.a3", at: { zone: 100, x: 30, y: 30, r: 10 }, lines: [{ kind: "turnin", quest: 9 }, { kind: "accept", quest: 3 }] };
  w.kill(9, 10, 20, 100, { questLevel: 3 });
  const steps = [both, mixed, acc(100, 4), ...run(100, 9),
    { id: "o1.o3", at: { zone: 100, x: 60, y: 60, r: 40 }, lines: [{ kind: "objective", quest: 1, index: 1 }, { kind: "objective", quest: 3, index: 1 }] },
    turn(100, 1), turn(100, 3), turn(100, 4)];
  const [section] = split(w, steps, flat(steps.length, 5));
  const byId = new Map(section.steps.map((s) => [s.id, s]));
  assert.strictEqual(byId.get("a1.a2").maxLevel, 13, "quest 5 gives XP up to level 13, quest 7 up to 15: the lower wins");
  assert.strictEqual(byId.get("t9.a3").maxLevel, undefined, "a step with a turn-in is not accept-only");
  assert.strictEqual(byId.get("a4").maxLevel, 60);
  assert.strictEqual(byId.get("a1.a2").lines[0].skipIfMissing, undefined, "the accept itself does not skip");
  const [o1, o3] = byId.get("o1.o3").lines;
  assert.strictEqual(o1.skipIfMissing, true);
  assert.strictEqual(o3.skipIfMissing, undefined);
  assert.strictEqual(byId.get("t1").lines[0].skipIfMissing, true);
  assert.strictEqual(byId.get("t3").lines[0].skipIfMissing, undefined);
  assert.strictEqual(byId.get("t4").lines[0].skipIfMissing, true);
  assert.strictEqual(checkRoute3(route3([section])), null);
});

test("a quest that needs a capped quest is accepted only once that one is handed in, and its own lines skip if missing", () => {
  // Found by the simulator (task X1): a rogue above the cap of "Road to Salvation" skipped its accept, and the next
  // quest of the chain, which needs it handed in, could never be accepted.
  const w = testWorld();
  w.npc(10, 100, 30, 30); w.npc(20, 100, 60, 60, "");
  w.kill(1, 10, 20, 100, { questLevel: 5 });
  w.kill(5, 10, 20, 100, { questLevel: 6, preQuestSingle: [1] }); w.kill(6, 10, 20, 100, { questLevel: 6, preQuestSingle: [5] });
  const steps = [acc(100, 1), ...run(100, 9), turn(100, 1),
    { id: "a5", at: { zone: 100, x: 30, y: 30, r: 10 }, lines: [{ kind: "accept", quest: 5, requires: [1] }] },
    { id: "o5", at: { zone: 100, x: 60, y: 60, r: 40 }, lines: [{ kind: "objective", quest: 5, index: 1 }] },
    { id: "t5.a6", at: { zone: 100, x: 30, y: 30, r: 10 }, lines: [{ kind: "turnin", quest: 5 }, { kind: "accept", quest: 6, requires: [5] }] },
    turn(100, 6)];
  const [section] = split(w, steps, flat(steps.length, 5));
  const byId = new Map(section.steps.map((s) => [s.id, s]));
  assert.strictEqual(byId.get("a1").maxLevel, 13);
  assert.strictEqual(byId.get("a5").maxLevel, 14, "a5 is accept-only too: capped on its own");
  assert.strictEqual(byId.get("a5").lines[0].ifDone, 1, "wanted only once quest 1 is handed in");
  assert.strictEqual(byId.get("o5").lines[0].skipIfMissing, true);
  const [t5, a6] = byId.get("t5.a6").lines;
  assert.strictEqual(t5.skipIfMissing, true);
  assert.strictEqual(a6.ifDone, 5, "down the chain");
  assert.strictEqual(byId.get("t6").lines[0].skipIfMissing, true);
  assert.strictEqual(checkRoute3(route3([section])), null);
});

// A town with quests in Westland, a rogue quest, and a trip to Eastland: a real planner route, bundled.
function plannedRoute() {
  const w = testWorld();
  const ROGUE = classMask("ROGUE");
  w.herd(90, 100, 70, 70); w.herd(91, 200, 60, 60);
  for (let k = 0; k < 14; k++) {
    w.npc(10 + k, 100, 30 + (k % 4), 50 + Math.floor(k / 4));
    w.npc(40 + k, 100, 60 + k, 30 + k, "");
    w.kill(1 + k, 10 + k, 40 + k, 100, { questLevel: 1 + Math.floor(k / 3) });
  }
  w.npc(30, 100, 32, 52); w.npc(31, 100, 62, 32, "");
  w.kill(40, 30, 31, 100, { requiredClasses: ROGUE });
  for (let k = 0; k < 14; k++) {
    w.npc(60 + k, 200, 50 + (k % 3), 50 + Math.floor(k / 3));
    w.npc(80 + k, 200, 55 + k, 20 + k * 2, "");
    w.kill(60 + k, 60 + k, 80 + k, 200, { requiredLevel: 4, questLevel: 5 + Math.floor(k / 4) });
  }
  const graph = w.graph();
  const shared = planRoute(w.db, w.human(), { graph, inns: w.inns, maxLevel: 8 });
  const chars = [w.human("WARRIOR"), w.human("ROGUE")];
  const route = layerClasses(w.db, shared, chars, { graph }).route;
  const levelsOf = (ch) => validateRoute(w.db, route, ch, { graph, inns: w.inns });
  const bundled = bundleSteps(w.db, route);
  const v = levelsOf(chars[0]);
  const levelsByStep = stepLevels(v.levels, bundled.origin, v.endLevel);
  const classLevels = {};
  for (const ch of chars) { const r = levelsOf(ch); classLevels[ch.cls] = stepLevels(r.levels, bundled.origin, r.endLevel); }
  return { w, route, bundled, levelsByStep, classLevels };
}

test("stepLevels gives each bundled step its start and end level from the action levels", () => {
  assert.deepStrictEqual(stepLevels([1, 1, 2, 3, 3], [[0, 1], [2], [3, 4]], 4), [{ start: 1, end: 2 }, { start: 2, end: 3 }, { start: 3, end: 4 }]);
});

test("flatten over all sections gives the route's actions plus the inserted grinds, in order", () => {
  const { w, bundled, levelsByStep, classLevels } = plannedRoute();
  // a step the estimate does not reach: a grind must come before it
  const k = bundled.steps.findIndex((s, i) => i > 0 && s.lines[0].kind === "accept" && !s.when);
  bundled.steps[k].minLevel = Math.floor(levelsByStep[k].start) + 2;
  const before = flatten(bundled.steps);
  const ids = new Set(bundled.steps.map((s) => s.id));
  const sections = splitSections(w.db, "Human", "Alliance", bundled, levelsByStep, classLevels);
  const all = sections.flatMap((s) => s.steps);
  // the steps the route had keep their ids; the inserted ones are grinds with new ids
  const added = all.filter((s) => !ids.has(s.id));
  assert.ok(added.length >= 1, "a grind was inserted");
  for (const s of added) assert.deepStrictEqual(s.lines.map((l) => l.kind), ["grind"], s.id);
  const kept = all.filter((s) => ids.has(s.id));
  assert.deepStrictEqual(kept.map((s) => s.id), bundled.steps.map((s) => s.id), "every step once, in order");
  // the actions: the route's, with one grind action per inserted step at its place in the order
  const what = (list) => list.map(({ action, quest, node, from, to, level, when }) => JSON.stringify({ action, quest, node, from, to, level, when }));
  assert.deepStrictEqual(what(flatten(kept)), what(before));
  assert.strictEqual(flatten(all).length, before.length + added.length);
  // the grind comes before the step that needed it
  const at = all.findIndex((s) => s.id === bundled.steps[k].id);
  assert.ok(all.slice(0, at).some((s) => added.includes(s) && s.lines[0].level === bundled.steps[k].minLevel));
});

test("the sections pass checkRoute3", () => {
  const { w, bundled, levelsByStep, classLevels } = plannedRoute();
  const sections = splitSections(w.db, "Human", "Alliance", bundled, levelsByStep, classLevels);
  assert.ok(sections.length >= 2, sections.map((s) => s.id).join(" "));
  assert.strictEqual(checkRoute3(route3(sections)), null);
});

test("regrindSections: a step whose minLevel a later estimate does not reach gets a grind, checked per class", () => {
  // Found once class trainer trips became steps (task X1): the way to a trainer and back changed a class's estimate,
  // and a step at level 30 came at an estimated 29 with no grind before it.
  const step = { ...acc(100, 7), minLevel: 5 };
  const rogue = { ...acc(100, 8), minLevel: 6, when: { class: "ROGUE" } };
  const before = [obj(100), step, obj(100), rogue];
  const sections = [{ id: "human-01-09-westland", steps: before }];
  const levels = new Map([[before[0], 4], [before[1], 4.6], [before[2], 5.1], [before[3], 5.5]]);
  const levelOf = (cls, s) => {
    const l = levels.get(s);
    if (l === undefined || (s.when && s.when.class !== cls)) return undefined;
    return { start: cls === "WARRIOR" ? l + 1 : l, end: cls === "WARRIOR" ? l + 1 : l };
  };
  const out = regrindSections(sections, ["ROGUE", "WARRIOR"], levelOf);
  assert.deepStrictEqual(out[0].steps.map((s) => s.id), [before[0].id, "l5@100", step.id, before[2].id, "l6@100", rogue.id]);
  assert.deepStrictEqual(out[0].steps[4].when, { class: "ROGUE" }, "the class step's grind is for its class");
  assert.strictEqual(sections[0].steps.length, 4, "the input is not changed");
  const enough = regrindSections(sections, ["ROGUE"], (cls, s) => (s.when && s.when.class !== cls ? undefined : { start: 7, end: 7 }));
  assert.deepStrictEqual(enough[0].steps.map((s) => s.id), before.map((s) => s.id), "every estimate reaches: nothing added");
});

test("the objective and turnin lines of a quest accepted in an earlier section skip when the quest is missing", () => {
  // Found by the simulator's joiners (task X1): a character that joined with one quest of an earlier section never
  // taken met its hand-in further on, which no step of that section could accept ("cannot", no evidence).
  const w = testWorld();
  w.npc(10, 100, 30, 30); w.npc(20, 200, 60, 60, "");
  w.kill(1, 10, 20, 100, { questLevel: 5 }); w.kill(2, 10, 20, 200, { questLevel: 5 });
  // no step here is accept-only, so no level cap marks a line: only the rule under test can
  const first = { id: "a1.g", at: { zone: 100, x: 30, y: 30, r: 10 }, lines: [{ kind: "accept", quest: 1 }, { kind: "goto", at: { zone: 100, x: 31, y: 31, r: 20 } }] };
  const steps = [first, ...run(100, 12), go(200), ...run(200, 12),
    { id: "o1.a2", at: { zone: 200, x: 60, y: 60, r: 40 }, lines: [{ kind: "objective", quest: 1, index: 1 }, { kind: "accept", quest: 2 }] },
    { id: "o2", at: { zone: 200, x: 60, y: 60, r: 40 }, lines: [{ kind: "objective", quest: 2, index: 1 }] },
    turn(200, 1), turn(200, 2)];
  const sections = split(w, steps, flat(steps.length, 5));
  assert.strictEqual(sections.length, 2);
  const byId = new Map(sections[1].steps.map((s) => [s.id, s]));
  assert.strictEqual(byId.get("o1.a2").lines[0].skipIfMissing, true, "quest 1 was accepted in the first section");
  assert.strictEqual(byId.get("t1").lines[0].skipIfMissing, true);
  assert.strictEqual(byId.get("o2").lines[0].skipIfMissing, undefined, "quest 2 is accepted in this section: a detour can bring it back");
  assert.strictEqual(byId.get("t2").lines[0].skipIfMissing, undefined);
  assert.strictEqual(checkRoute3(route3(sections)), null);
});

test("an accept that needs a quest of an earlier section is wanted only once that one is handed in, down its chain", () => {
  // Found by the simulator's joiners (task X1): a joiner who never took "Harpy Raiders" in the section before met
  // "Harpy Lieutenants", which needs it handed in, and could neither accept it nor do its lines.
  const w = testWorld();
  w.npc(10, 100, 30, 30); w.npc(20, 200, 60, 60, "");
  w.kill(1, 10, 20, 100, { questLevel: 5 });
  w.kill(3, 20, 20, 200, { questLevel: 6, preQuestSingle: [1] }); w.kill(4, 20, 20, 200, { questLevel: 6, preQuestSingle: [3] });
  w.kill(2, 20, 20, 200, { questLevel: 5 });
  // no step here is accept-only, so no level cap marks a line: only the rule under test can
  const first = { id: "a1.g", at: { zone: 100, x: 30, y: 30, r: 10 }, lines: [{ kind: "accept", quest: 1 }, { kind: "goto", at: { zone: 100, x: 31, y: 31, r: 20 } }] };
  const steps = [first, { id: "o1", at: { zone: 100, x: 60, y: 60, r: 40 }, lines: [{ kind: "objective", quest: 1, index: 1 }] },
    ...run(100, 12), go(200), ...run(200, 12),
    { id: "t1.a3.a2", at: { zone: 200, x: 60, y: 60, r: 10 }, lines: [{ kind: "turnin", quest: 1 }, { kind: "accept", quest: 3, requires: [1] }, { kind: "accept", quest: 2 }] },
    { id: "o3.o2", at: { zone: 200, x: 60, y: 60, r: 40 }, lines: [{ kind: "objective", quest: 3, index: 1 }, { kind: "objective", quest: 2, index: 1 }] },
    { id: "t3.a4.t2", at: { zone: 200, x: 60, y: 60, r: 10 }, lines: [{ kind: "turnin", quest: 3 }, { kind: "accept", quest: 4, requires: [3] }, { kind: "turnin", quest: 2 }] },
    obj(200), turn(200, 4)];
  const sections = split(w, steps, flat(steps.length, 5));
  assert.strictEqual(sections.length, 2);
  const byId = new Map(sections[1].steps.map((s) => [s.id, s]));
  const [t1, a3, a2] = byId.get("t1.a3.a2").lines;
  assert.strictEqual(t1.skipIfMissing, true, "quest 1 was accepted in the first section");
  assert.strictEqual(a3.ifDone, 1, "wanted only once quest 1 is handed in");
  assert.strictEqual(a2.ifDone, undefined, "quest 2 needs nothing");
  const [o3, o2] = byId.get("o3.o2").lines;
  assert.strictEqual(o3.skipIfMissing, true, "quest 3 may never be accepted");
  assert.strictEqual(o2.skipIfMissing, undefined, "quest 2 is accepted in this section: a detour can bring it back");
  const [t3, a4, t2] = byId.get("t3.a4.t2").lines;
  assert.strictEqual(t3.skipIfMissing, true);
  assert.strictEqual(a4.ifDone, 3, "down the chain");
  assert.strictEqual(t2.skipIfMissing, undefined);
  assert.strictEqual(byId.get("t4").lines[0].skipIfMissing, true);
  assert.strictEqual(checkRoute3(route3(sections)), null);
});

test("an accept that needs several quests of an earlier section gets a step of its own that skips unless each is handed in", () => {
  // Review of task X1: ifDone names one quest, so an accept needing two quests taken in an earlier section was gated on
  // the first only, and a joiner without the second met an accept the game would not offer.
  const w = testWorld();
  w.npc(10, 100, 30, 30); w.npc(20, 200, 60, 60, "");
  w.kill(1, 10, 20, 100, { questLevel: 5 }); w.kill(7, 10, 20, 100, { questLevel: 5 });
  w.kill(8, 20, 20, 200, { questLevel: 6, preQuestGroup: [1, 7] });
  w.kill(2, 20, 20, 200, { questLevel: 5 });
  const first = { id: "a1.a7.g", at: { zone: 100, x: 30, y: 30, r: 10 }, lines: [{ kind: "accept", quest: 1 }, { kind: "accept", quest: 7 }, { kind: "goto", at: { zone: 100, x: 31, y: 31, r: 20 } }] };
  const steps = [first, { id: "o1.o7", at: { zone: 100, x: 60, y: 60, r: 40 }, lines: [{ kind: "objective", quest: 1, index: 1 }, { kind: "objective", quest: 7, index: 1 }] },
    ...run(100, 12), go(200), ...run(200, 12),
    { id: "t1.t7.a8.a2", at: { zone: 200, x: 60, y: 60, r: 10 }, targets: { friend: [20] },
      lines: [{ kind: "turnin", quest: 1 }, { kind: "turnin", quest: 7 }, { kind: "accept", quest: 8, requires: [1, 7] }, { kind: "accept", quest: 2 }] },
    { id: "o8.o2", at: { zone: 200, x: 60, y: 60, r: 40 }, lines: [{ kind: "objective", quest: 8, index: 1 }, { kind: "objective", quest: 2, index: 1 }] },
    { id: "t8.t2", at: { zone: 200, x: 60, y: 60, r: 10 }, lines: [{ kind: "turnin", quest: 8 }, { kind: "turnin", quest: 2 }] }];
  const sections = split(w, steps, flat(steps.length, 5));
  assert.strictEqual(sections.length, 2);
  const ids = sections[1].steps.map((s) => s.id);
  const at = ids.indexOf("t1.t7");
  assert.ok(at >= 0, `the hand-ins keep their step: ${ids.join(" ")}`);
  assert.deepStrictEqual(ids.slice(at, at + 3), ["t1.t7", "a8", "a2"], "the gated accept stands alone between the rest, in order");
  const byId = new Map(sections[1].steps.map((s) => [s.id, s]));
  const a8 = byId.get("a8");
  assert.deepStrictEqual(a8.lines.map((l) => l.quest), [8]);
  assert.strictEqual(a8.lines[0].ifDone, 1);
  assert.deepStrictEqual(a8.skip, [{ kind: "notturnedin", quest: 7 }], "the second required quest gates the step");
  assert.deepStrictEqual(a8.at, { zone: 200, x: 60, y: 60, r: 10 });
  assert.deepStrictEqual(a8.targets, { friend: [20] });
  assert.strictEqual(byId.get("a2").lines[0].ifDone, undefined);
  for (const s of sections[1].steps) for (const l of s.lines) assert.strictEqual(l._need, undefined, "no working field is left on a line");
  assert.deepStrictEqual(flatten(sections.flatMap((s) => s.steps)).filter((a) => a.action !== "grind").map((a) => `${a.action}${a.quest || ""}`),
    flatten(steps).map((a) => `${a.action}${a.quest || ""}`), "flatten still lists every action in order");
  assert.strictEqual(checkRoute3(route3(sections)), null);
});

// The test world of the gate tests: quests 1, 7 and 9 taken in the first section and handed in in the second, then
// quest 8 accepted with the prerequisites `pre` (QuestieDB fields) and its `requires` as bundle builds it.
function gatedWorld(pre, requires, extra = {}) {
  const w = testWorld();
  w.npc(10, 100, 30, 30); w.npc(20, 200, 60, 60, "");
  for (const q of [1, 7, 9]) w.kill(q, 10, 20, 100, { questLevel: 5 });
  w.kill(8, 20, 20, 200, { questLevel: 6, ...pre });
  w.kill(2, 20, 20, 200, { questLevel: 5 });
  const steps = [{ id: "a1.a7.a9", at: { zone: 100, x: 30, y: 30, r: 10 }, lines: [{ kind: "accept", quest: 1 }, { kind: "accept", quest: 7 }, { kind: "accept", quest: 9 }] },
    { id: "o1.o7.o9", at: { zone: 100, x: 60, y: 60, r: 40 }, lines: [1, 7, 9].map((quest) => ({ kind: "objective", quest, index: 1 })) },
    ...run(100, 12), go(200), ...run(200, 12),
    { id: "t1.t7.t9.a8.a2", at: { zone: 200, x: 60, y: 60, r: 10 }, ...extra,
      lines: [{ kind: "turnin", quest: 1 }, { kind: "turnin", quest: 7 }, { kind: "turnin", quest: 9 }, { kind: "accept", quest: 8, requires }, { kind: "accept", quest: 2 }] },
    { id: "o8.o2", at: { zone: 200, x: 60, y: 60, r: 40 }, lines: [{ kind: "objective", quest: 8, index: 1 }, { kind: "objective", quest: 2, index: 1 }] },
    { id: "t8.t2", at: { zone: 200, x: 60, y: 60, r: 10 }, lines: [{ kind: "turnin", quest: 8 }, { kind: "turnin", quest: 2 }] }];
  return { w, steps };
}
const linesOf8 = (sections) => sections[1].steps.flatMap((st) => st.lines.filter((l) => l.kind === "accept" && l.quest === 8).map((l) => ({ step: st, line: l })));

test("an accept that any one of several quests of an earlier section unlocks gets one accept line per quest, each with its own ifDone", () => {
  // Review 2 of task X1: requires holds preAny members too, and gating them all (ifDone on one, "notturnedin" on the
  // others) passed the accept for a character who had handed in only one, though the game offers it.
  const { w, steps } = gatedWorld({ preQuestSingle: [1, 7] }, [1, 7]);
  const sections = split(w, steps, flat(steps.length, 5));
  assert.strictEqual(sections.length, 2);
  const found = linesOf8(sections);
  assert.deepStrictEqual(found.map((f) => f.line.ifDone), [1, 7], "one line per any-of member");
  assert.ok(found.every((f) => f.step === found[0].step), "both in one step");
  assert.strictEqual(found[0].step.skip, undefined, "no member gates the step: any one opens it");
  assert.deepStrictEqual(found[0].step.lines.map((l) => `${l.kind}${l.quest}`), ["turnin1", "turnin7", "turnin9", "accept8", "accept8", "accept2"],
    "the accept stays in its step, in order");
  for (const st of sections[1].steps) for (const l of st.lines) assert.strictEqual(l._need, undefined, "no working field is left on a line");
  assert.deepStrictEqual(flatten(sections.flatMap((st) => st.steps)).filter((a) => a.action !== "grind").map((a) => `${a.action}${a.quest || ""}`),
    flatten(steps).map((a) => `${a.action}${a.quest || ""}`), "flatten gives one accept action for the two lines");
  assert.strictEqual(checkRoute3(route3(sections)), null);
});

test("an accept with all-of and any-of prerequisites: one line per any-of member, and a step of its own gated on the all-of ones", () => {
  const { w, steps } = gatedWorld({ preQuestGroup: [9], preQuestSingle: [1, 7] }, [9, 1, 7]);
  const sections = split(w, steps, flat(steps.length, 5));
  const found = linesOf8(sections);
  assert.deepStrictEqual(found.map((f) => f.line.ifDone), [1, 7]);
  assert.deepStrictEqual(found[0].step.lines.map((l) => l.quest), [8, 8], "a step of its own");
  assert.deepStrictEqual(found[0].step.skip, [{ kind: "notturnedin", quest: 9 }], "the all-of quest gates the step");
  assert.strictEqual(checkRoute3(route3(sections)), null);
});

test("an any-of member the section itself makes certain opens the accept: no gate", () => {
  // quest 7 is accepted and handed in within the second section: the group is open whatever happened to quest 1
  const { w, steps } = gatedWorld({ preQuestSingle: [1, 7] }, [1, 7]);
  const late = steps.findIndex((st) => st.id === "t1.t7.t9.a8.a2");
  // (with a work line: an accept-only step is capped by its XP level, which makes its quests uncertain again)
  steps.splice(late, 0, { id: "a7.o2b", at: { zone: 200, x: 60, y: 60, r: 10 }, lines: [{ kind: "accept", quest: 7 }, { kind: "objective", quest: 2, index: 1 }] }, { id: "o7b", at: { zone: 200, x: 60, y: 60, r: 40 }, lines: [{ kind: "objective", quest: 7, index: 1 }] });
  steps[0] = { ...steps[0], lines: steps[0].lines.filter((l) => l.quest !== 7) };
  steps[1] = { ...steps[1], lines: steps[1].lines.filter((l) => l.quest !== 7) };
  const sections = split(w, steps, flat(steps.length, 5));
  const found = linesOf8(sections);
  assert.deepStrictEqual(found.map((f) => f.line.ifDone), [undefined], "one line, not gated");
});

test("a split gated step keeps load on its first part only, and a reminder step is never split", () => {
  const { w, steps } = gatedWorld({ preQuestGroup: [1, 7] }, [1, 7], { load: "elsewhere" });
  const sections = split(w, steps, flat(steps.length, 5));
  const parts = sections[1].steps.filter((st) => st.lines.some((l) => (l.kind === "turnin" && [1, 7, 9].includes(l.quest)) || (l.kind === "accept" && [8, 2].includes(l.quest))));
  assert.deepStrictEqual(parts.map((st) => st.load), ["elsewhere", undefined, undefined], "load fires once, on the first part");
  const reminded = gatedWorld({ preQuestGroup: [1, 7] }, [1, 7], { reminder: { ends: "x" } });
  assert.throws(() => split(reminded.w, reminded.steps, flat(reminded.steps.length, 5)), /reminder step would be split/);
});

const ROUTES = require("node:path").join(__dirname, "..", "..", "NoirGuides", "Routes");
const DATA_DIR = require("node:path").join(__dirname, "..", "data");
const haveReal = fs.existsSync(require("node:path").join(DATA_DIR, "forever_db.json")) && fs.existsSync(require("node:path").join(ROUTES, "horde-orc.lua"));
test("real route: March of the Silithid (4494), which either 32 or 7732 unlocks, has one accept line per prerequisite wherever a route takes it", { skip: !haveReal }, (t) => {
  // Review 2 of task X1: the route emitted ifDone = 7732 and a "notturnedin 32" skip, so a character who had handed in
  // only one of them had 4494 passed while the game offered it, and its chain (4496 ifDone 4494) was lost. The routes
  // of 0.4.0 took it on horde-orc; a route that reaches 60 without the chain leaves the check to the tests above.
  const { loadDb } = require("../lib/db");
  const { parseRoute } = require("../sim_all");
  const q = loadDb(DATA_DIR).quests.get(4494);
  assert.deepStrictEqual(q.preAll, []);
  assert.deepStrictEqual([...q.preAny].sort((a, b) => a - b), [32, 7732]);
  let routes = 0;
  for (const file of fs.readdirSync(ROUTES).filter((f) => f.endsWith(".lua")).sort()) {
    const route = parseRoute(fs.readFileSync(require("node:path").join(ROUTES, file), "utf8"));
    const hits = [];
    for (const sec of route.sections) for (const st of sec.steps) for (const l of st.lines) if (l.kind === "accept" && l.quest === 4494) hits.push({ st, l });
    if (!hits.length) continue;
    routes++;
    assert.deepStrictEqual(hits.map((h) => h.l.ifDone).sort((a, b) => a - b), [32, 7732], file);
    assert.ok(hits.every((h) => h.st === hits[0].st), `${file}: in one step`);
    assert.ok(!(hits[0].st.skip || []).some((c) => c.kind === "notturnedin"), `${file}: no any-of member gates the step`);
  }
  if (!routes) t.skip("no route takes 4494 today");
});
