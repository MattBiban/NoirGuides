// Noir Guides, GPLv3. See LICENSE.
const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");
const { testWorld } = require("./world");
const { planRoute } = require("../planner/plan");
const { validateRoute } = require("../planner/validate");
const { measureRoute } = require("../planner/measure");
const { reportMarkdown, summarize, acceptance, hours, percent } = require("../planner/report");
const { parseRoute, parseReport } = require("../baseline");

function built(maxLevel = 4) {
  const w = testWorld();
  w.npc(10, 100, 30, 50); w.npc(20, 100, 60, 30, ""); w.kill(1, 10, 20, 100);
  w.npc(50, 400, 50, 12); w.errand(7, 10, 50, 100); w.npc(51, 400, 52, 14, ""); w.kill(9, 50, 51, 400); w.kill(10, 50, 51, 400); w.kill(11, 50, 51, 400);
  const graph = w.graph(), ch = w.human();
  const route = planRoute(w.db, ch, { graph, inns: w.inns, maxLevel });
  const result = validateRoute(w.db, route, ch, { graph, inns: w.inns });
  return { db: w.db, result: { route, validations: [{ character: ch, result }], measure: measureRoute(w.db, graph, route, ch, result.levels) } };
}
const before = (zoneChanges, travelSeconds) => ({ commit: "abc1234", races: { Human: { steps: 90, quests: 30, endLevel: 60, grindSteps: 1, straightYards: 5000, zoneChanges, travelSeconds, walkedYards: 4000, unreachable: 0 } } });

test("a route's facts are counted from its steps and its measurement", () => {
  const { db, result } = built();
  const s = summarize(db, result);
  assert.strictEqual(s.steps, result.route.steps.length);
  assert.strictEqual(s.quests, 5);
  assert.strictEqual(s.zoneChanges, 1);
  assert.deepStrictEqual(s.visits.map((v) => v.name), ["Westland", "Farshore"]);
  assert.strictEqual(s.visits.reduce((sum, v) => sum + v.steps, 0), result.route.steps.filter((x) => ["accept", "objective", "turnin", "grind", "sethearth"].includes(x.action)).length);
  assert.strictEqual(s.transports, 1);
  assert.deepStrictEqual(s.links.map((l) => l.id), ["boat-west-far"]);
  assert.ok(s.travelSeconds > 200 && s.byKind.transport === 200);
  assert.deepStrictEqual(s.errors, []);
  assert.deepStrictEqual(s.classes, ["WARRIOR"]);
});
test("the report sets the routes beside the baseline and says whether each acceptance line is met", () => {
  const { db, result } = built();
  const md = reportMarkdown(db, [result], before(10, 100000));
  assert.match(md, /^# Route report\n/);
  assert.match(md, /## Before and after/);
  assert.match(md, /commit `abc1234`/);
  const row = md.split("\n").find((l) => l.startsWith("| Human | "));
  assert.match(row, /^\| Human \| 10 \| 1 \| -90% \| 27 h 47 min \| 0 h \d\d min \| -\d+% \| 4,000 \| [\d,]+ \| [-+]\d+% \| 90 \| \d+ \| 30 \| 5 \| 1 \| \d \| \d+ \|$/);
  assert.match(md, /\| Zone changes at most 140% of the baseline for every race \| yes \| most: Human, 10 to 1 \(-90%\) \|/);
  assert.match(md, /\| Travel time at most 150% of the baseline for every race \| yes \| most: Human, 27 h 47 min to 0 h \d\d min \(-\d+%\) \|/);
  assert.match(md, /\| At most 2 grind steps in any race \| yes \| most: \d \|/);
  assert.match(md, /\| No quest more than 3 levels above the player in any race \(4 for a quest without fights\) \| yes \| most: 0 quest steps a class \(2 allowed: [^|]+\) \|/);
  assert.match(md, /\| At most 10% of quest steps more than 5 levels below the player in any race \| yes \| most: 0% \|/);
  // the pace is said as it is counted (lib/xp.js yieldAt), and the price of quests instead of grinding is said too
  assert.match(md, /The planner counts on 60% of the estimated XP up to level 30, rising to 68% at level 50, so a\nplayer at a usual pace is not behind the route\./);
  assert.match(md, /A grind step is the rest of one level and the last resort/);
  assert.match(md, /they do them rather than grind: 17% of the baseline's quests\./, "5 quests against the 30 of this test's baseline");
  assert.match(md, /change zone more often than the baseline's and\nspend more time on the way: that is the accepted price of quests instead of grinding\./);
  assert.ok(!/70%|fewer\s+zone\s+changes/.test(md), "nothing of the old pace or the old promise is left");
  assert.match(md, /\| No validator errors \| yes \| 0 errors \|/);
  assert.match(md, /\| Every race reaches level 60 \| \*\*no\*\* \| short: Human \(\d+\) \|/);
  assert.match(md, /\| Walked \| [\d,]+ yards \(before: 4,000\) \|/);
  assert.match(md, /\| Unconfirmed transports used \| West to Far \(boat; not confirmed: route\) \|/);
  assert.match(md, /\| Zones in order \(steps there\) \| Westland \(\d+\), Farshore \(\d+\) \|/);
  assert.ok(!md.includes("undefined") && !md.includes("NaN"));
  // the same input, the same report
  assert.strictEqual(md, reportMarkdown(db, [result], before(10, 100000)));
  // without a baseline there is nothing to compare, and the report says nothing about it
  assert.ok(!reportMarkdown(db, [result], null).includes("Before and after"));
});
test("an acceptance line that is not met is reported as not met", () => {
  const { db, result } = built();
  const s = summarize(db, result);
  const rows = (b) => [{ race: "Human", s, before: b.races.Human }];
  // The routes do quests instead of grinding and change zone more often than the baseline's for it: up to 140% of
  // the baseline's zone changes is the accepted price, more is not. 1 zone change before, 1 now is within it
  const few = acceptance(rows(before(1, 100000)));
  assert.deepStrictEqual([few[0].met, few[0].detail], [true, "most: Human, 1 to 1 (-0%)"]);
  // 10 before, 14 now is just within; 15 now is not
  const zones = (zoneChanges) => acceptance([{ race: "Human", s: { ...s, zoneChanges }, before: before(10, 100000).races.Human }])[0];
  assert.deepStrictEqual([zones(14).met, zones(14).detail], [true, "most: Human, 10 to 14 (+40%)"]);
  assert.deepStrictEqual([zones(15).met, zones(15).detail], [false, "most: Human, 10 to 15 (+50%)"]);
  // of several races the one furthest above its baseline is the one shown, and one over the limit fails the line
  const two = (orc) => acceptance([{ race: "Human", s: { ...s, zoneChanges: 12 }, before: before(10, 100000).races.Human },
    { race: "Orc", s: { ...s, zoneChanges: orc }, before: before(100, 100000).races.Human }])[0];
  assert.deepStrictEqual([two(130).met, two(130).detail], [true, "most: Orc, 100 to 130 (+30%)"]);
  assert.deepStrictEqual([two(110).met, two(110).detail], [true, "most: Human, 10 to 12 (+20%)"]);
  assert.deepStrictEqual([two(141).met, two(141).detail], [false, "most: Orc, 100 to 141 (+41%)"]);
  // travel may take half as long again as the baseline's, not more
  const travel = (travelSeconds) => acceptance([{ race: "Human", s: { ...s, travelSeconds }, before: before(10, 1000).races.Human }])[1];
  assert.deepStrictEqual([travel(1500).met, travel(1500).detail], [true, "most: Human, 0 h 17 min to 0 h 25 min (+50%)"]);
  assert.deepStrictEqual([travel(1501).met, travel(1501).detail], [false, "over: Human"]);
  // grinding is the last resort: two grind steps a route, not one more
  const grind = (n) => acceptance([{ race: "Human", s: { ...s, grinds: Array.from({ length: n }, (_, k) => ({ from: k + 1, to: k + 2 })) }, before: before(10, 100000).races.Human }]).find((a) => /grind steps/.test(a.name));
  assert.deepStrictEqual([grind(0).met, grind(0).detail], [true, "most: 0"]);
  assert.deepStrictEqual([grind(2).met, grind(2).detail], [true, "most: 2"]);
  assert.deepStrictEqual([grind(3).met, grind(3).detail], [false, "over: Human (3)"]);
  // quests above the level: two steps a class are allowed (planner/levelgap.js MAX_ABOVE), a third is not; and a
  // tenth of the quest steps may be far below the level, not more
  const gapLine = (levelGap, name) => acceptance([{ race: "Human", s: { ...s, levelGap }, before: before(10, 100000).races.Human }]).find((a) => name.test(a.name));
  const steps = (n) => Array.from({ length: n }, (_, k) => ({ step: k, quest: 1, questLevel: 9, level: 1 }));
  const above = (n) => gapLine({ above: steps(n), below: [], steps: 100 }, /levels above/), below = (n) => gapLine({ above: [], below: steps(n), steps: 100 }, /levels below/);
  assert.match(above(2).detail, /^most: 2 quest steps a class/);
  assert.deepStrictEqual([above(2).met, above(3).met, above(3).detail], [true, false, "over: Human (3)"]);
  assert.deepStrictEqual([below(10).met, below(10).detail], [true, "most: 10%"]);
  assert.deepStrictEqual([below(11).met, below(11).detail], [false, "over: Human"]);
  // one walk through a zone far above the player is one too many
  const walk = (n) => acceptance([{ race: "Human", s: { ...s, dangerous: Array.from({ length: n }, (_, k) => ({ step: k, level: 19, from: 33, to: 40, zone: 33, min: 36, cls: "WARRIOR" })) }, before: before(10, 100000).races.Human }]).find((a) => /No walk through/.test(a.name));
  assert.deepStrictEqual([walk(0).met, walk(0).detail], [true, "none"]);
  assert.deepStrictEqual([walk(1).met, walk(1).detail], [false, "over: Human (1)"]);
  assert.deepStrictEqual(s.dangerous, [], "a result without the check has none to show");
  // an error counts
  const bad = acceptance([{ race: "Human", s: { ...s, errors: ["WARRIOR: step 1: x"] }, before: before(10, 100000).races.Human }]);
  assert.deepStrictEqual([bad[2].met, bad[2].detail], [false, "1 errors"]);
  assert.strictEqual(hours(3661), "1 h 01 min");
  assert.strictEqual(percent(200, 80), "-60%");
  assert.strictEqual(percent(100, 150), "+50%");
});
test("the baseline reads the old route files and the old report", () => {
  const route = parseRoute([
    "-- Noir Guides, GPLv3. See LICENSE. Generated by tools/build_routes.js from QuestieDB Forever v1.0.14. Do not edit.",
    'Noir.Route("horde-undead", {',
    '  race = "Undead", faction = "Horde",',
    "  steps = {",
    '    { action = "accept", quest = 8, at = { zone = 85, x = 38.23, y = 56.79 }, npc = 6784 },',
    '    { action = "objective", quest = 8, at = { zone = 85, x = 30, y = 60.5 }, npc = 1501, item = 77 },',
    '    { action = "travel", zone = 130 },',
    '    { action = "grind", zone = 85, level = 6 },',
    "  },",
    "})",
  ].join("\n"));
  assert.deepStrictEqual([route.id, route.race, route.faction], ["horde-undead", "Undead", "Horde"]);
  assert.deepStrictEqual(route.steps, [
    { action: "accept", quest: 8, at: { zone: 85, x: 38.23, y: 56.79 }, npc: 6784 },
    { action: "objective", quest: 8, at: { zone: 85, x: 30, y: 60.5 }, npc: 1501, item: 77 },
    { action: "travel", zone: 130 },
    { action: "grind", zone: 85, level: 6 },
  ]);
  const old = parseReport(["## Undead (Horde, `horde-undead`)", "", "| Fact | Value |", "| --- | --- |", "| Steps | 2,090 |", "| Quests | 725 |", "| End level | 60 |",
    "| Travel distance | 1,232,768 yards |", "| Grind steps | 1 (level 59 to 60) |"].join("\n"));
  assert.deepStrictEqual(old, { Undead: { steps: 2090, quests: 725, endLevel: 60, straightYards: 1232768, grindSteps: 1 } });
});
test("the saved baseline covers every race with the numbers the report compares", () => {
  const baseline = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "planner", "baseline.json"), "utf8"));
  assert.strictEqual(baseline.commit, "37a4f8c");
  const { RACES } = require("../lib/characters");
  for (const race of Object.keys(RACES)) {
    const b = baseline.races[race];
    assert.ok(b, race);
    for (const key of ["steps", "quests", "endLevel", "grindSteps", "straightYards", "zoneChanges", "travelSeconds", "walkedYards"]) assert.ok(Number.isInteger(b[key]) && b[key] >= 0, `${race} ${key}`);
    assert.ok(b.zoneChanges > 150 && b.travelSeconds > 100000, `${race} was measured`);
  }
});

// The shared route with a rogue's quest layered in: the report counts the shared route and lists every character.
function layered() {
  const { layerClasses } = require("../planner/classes");
  const { classMask } = require("../lib/characters");
  const w = testWorld();
  w.npc(10, 100, 30, 50); w.npc(20, 100, 60, 30, ""); w.kill(1, 10, 20, 100);
  const graph = w.graph(), warrior = w.human(), rogue = w.human("ROGUE");
  const shared = planRoute(w.db, warrior, { graph, inns: w.inns, maxLevel: 2 });
  w.npc(13, 100, 32, 50);
  w.errand(40, 13, 13, 100, { requiredClasses: classMask("ROGUE") });
  w.errand(41, 13, 13, 100, { requiredClasses: classMask("ROGUE"), requiredLevel: 30 });
  const out = layerClasses(w.db, shared, [warrior, rogue], { graph });
  const check = (ch) => validateRoute(w.db, out.route, ch, { graph, inns: w.inns });
  const base = validateRoute(w.db, shared, warrior, { graph, inns: w.inns });
  return { db: w.db, result: { route: out.route, shared, classes: out.classes, measure: measureRoute(w.db, graph, shared, warrior, base.levels),
    validations: [warrior, rogue].map((character) => {
      const result = check(character);
      return { character, result, layer: out.classes[character.cls], measure: measureRoute(w.db, graph, out.route, character, result.levels) };
    }) } };
}
test("with classes layered, the facts are the shared route's and every character has a row", () => {
  const { db, result } = layered();
  const s = summarize(db, result);
  assert.strictEqual(s.steps, result.shared.steps.length, "the shared route's steps");
  assert.ok(result.route.steps.length > s.steps);
  assert.deepStrictEqual(s.characters.map((c) => [c.cls, c.layered, c.left]), [["WARRIOR", 0, 0], ["ROGUE", 1, 1]]);
  for (const c of s.characters) assert.strictEqual(c.valid, c.errors === 0 && c.endLevel >= 60);
  const md = reportMarkdown(db, [result], null);
  assert.match(md, /## Characters/);
  // each character's own steps are measured as well: what its class steps add to the shared route's way
  const [warriorRow, rogueRow] = s.characters;
  assert.strictEqual(warriorRow.zoneChanges, result.measure.zoneChanges, "a class with no quests has the shared route's zone changes");
  assert.strictEqual(warriorRow.travelSeconds, Math.round(result.measure.seconds));
  assert.strictEqual(rogueRow.zoneChanges, result.validations[1].measure.zoneChanges);
  assert.strictEqual(rogueRow.travelSeconds, Math.round(result.validations[1].measure.seconds));
  assert.strictEqual(rogueRow.addedSeconds, rogueRow.travelSeconds - Math.round(result.measure.seconds));
  assert.strictEqual(warriorRow.addedSeconds, 0);
  // Race | Class | Valid | End level | layered | left | class steps | zone changes | added | travel | added | whole route
  assert.match(md, /\| Human \| ROGUE \| (yes|\*\*no\*\*) \| \d+ \| 1 \| 1 \| \d+ \| \d+ \| [+-]\d+ \| \d+ h \d\d min \| [+-]\d+ h \d\d min \| \d+ h \d\d min \|/);
  assert.match(md, /\| Human \| WARRIOR \| (yes|\*\*no\*\*) \| \d+ \| 0 \| 0 \| 0 \| \d+ \| \+0 \| \d+ h \d\d min \| \+0 h 00 min \| \d+ h \d\d min \|/);
  assert.match(md, /\| Characters valid and at level 60 \| \*\*no\*\* \| 0 of 2 \|/, "the test routes end below 60");
  assert.match(md, /ROGUE: 41 \(the route never reaches level 30\)/);
  assert.ok(!md.includes("undefined") && !md.includes("NaN"));
});

test("the report gives each race's format 3 facts: bundling, sections, profession steps and class visits", () => {
  const { db, result } = built();
  const P = (x, y, r) => ({ zone: 100, x, y, r });
  const steps = [
    { id: "a1", at: P(30, 50, 10), lines: [{ kind: "accept", quest: 1, npc: 10 }] },
    { id: "tWARRIOR-2", when: { class: "WARRIOR" }, at: P(32, 50, 10), lines: [{ kind: "train", class: "WARRIOR", level: 2, npc: 600 }] },
    { id: "p164-2", when: { profession: 164 }, at: P(33, 50, 10), lines: [{ kind: "train", skill: 164, rank: 2, npc: 700 }] },
    { id: "tWARRIOR-4", when: { class: "WARRIOR" }, at: P(32, 50, 10), lines: [{ kind: "train", class: "WARRIOR", level: 4, npc: 600 }] },
    { id: "tMAGE-4", when: { class: "MAGE" }, at: P(32, 50, 10), lines: [{ kind: "train", class: "MAGE", level: 4, npc: 602 }] },
  ];
  const sections = [
    { id: "human-01-04-westland", name: "1-4 Westland", group: "Alliance", subgroup: "1-20", minLevel: 1, maxLevel: 7, zone: 100, start: true, next: [{ section: "human-04-06-farshore" }], steps },
    { id: "human-04-06-farshore", name: "4-6 Farshore", group: "Alliance", subgroup: "1-20", minLevel: 4, maxLevel: 9, zone: 400, next: [], steps: [steps[0]] },
  ];
  result.format3 = { actions: 20, bundled: 12, route3: { id: "alliance-human", format: 3, race: "Human", faction: "Alliance", sections },
    professionNotes: ["Blacksmithing Expert (rank 3, level 20): the route's estimate never reaches level 20"], notes: ["Human step a9: a note"], errors: [] };
  const md = reportMarkdown(db, [result], null);
  assert.match(md, /### Format 3/);
  assert.match(md, /\| Actions before bundling, steps after \| 20, 12 \(60%\) \|/);
  assert.match(md, /\| Sections \| 2 \|/);
  assert.match(md, /\| human-01-04-westland \| 1-4 Westland \| 5 \| 1-7 \|/);
  assert.match(md, /\| human-04-06-farshore \| 4-6 Farshore \| 1 \| 4-9 \|/);
  assert.match(md, /\| Profession steps written \| p164-2 \|/);
  assert.match(md, /\| Profession ranks without a step \| Blacksmithing Expert \(rank 3, level 20\): the route's estimate never reaches level 20 \|/);
  assert.match(md, /\| Class trainer visits \| MAGE: 4; WARRIOR: 2, 4 \|/);
  assert.match(md, /\| Planner notes \| Human step a9: a note \|/);
  assert.match(md, /\| Format 3 errors \| 0 \|/);
  assert.ok(!md.includes("undefined") && !md.includes("NaN"));
});
