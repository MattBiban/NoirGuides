// Noir Guides, GPLv3. See LICENSE.
// The format 3 validator (tools/planner/validate3.js, task P3 of docs/superpowers/plans/2026-11-11-guide-rebuild.md).
const test = require("node:test");
const assert = require("node:assert");
const { testWorld } = require("./world");
const { planRoute } = require("../planner/plan");
const { validateRoute } = require("../planner/validate");
const { bundleSteps } = require("../planner/bundle");
const { splitSections, stepLevels } = require("../planner/sections");
const { validate3, estimateSteps, applies, chainOf } = require("../planner/validate3");

const clone = (o) => JSON.parse(JSON.stringify(o));
// a small planned route on the test world, in format 3
function built() {
  const w = testWorld();
  w.npc(10, 100, 30, 50); w.npc(20, 100, 60, 30, ""); w.kill(1, 10, 20, 100);
  w.npc(50, 400, 50, 12); w.errand(7, 10, 50, 100); w.npc(51, 400, 52, 14, ""); w.kill(9, 50, 51, 400); w.kill(10, 50, 51, 400); w.kill(11, 50, 51, 400);
  const graph = w.graph(), ch = w.human();
  const route = planRoute(w.db, ch, { graph, inns: w.inns, maxLevel: 4 });
  const v = validateRoute(w.db, route, ch, { graph, inns: w.inns });
  assert.deepStrictEqual(v.errors, []);
  const bundled = bundleSteps(w.db, route, v.levels);
  const sections = splitSections(w.db, "Human", "Alliance", bundled, stepLevels(v.levels, bundled.origin, v.endLevel), {});
  return { w, graph, ch, v, route3: { id: "alliance-human", format: 3, race: "Human", faction: "Alliance", sections } };
}

test("conditions apply by class, race and planned professions", () => {
  const ch = { race: "Human", cls: "ROGUE" };
  assert.ok(applies(undefined, ch));
  assert.ok(applies({ class: "ROGUE" }, ch) && applies({ class: ["MAGE", "ROGUE"] }, ch));
  assert.ok(!applies({ class: "MAGE" }, ch) && !applies({ notClass: "ROGUE" }, ch));
  assert.ok(applies({ race: "Human", notRace: ["Dwarf"] }, ch) && !applies({ race: "Dwarf" }, ch));
  assert.ok(!applies({ profession: 164 }, ch), "a profession nobody planned");
  assert.ok(applies({ profession: 164 }, ch, [164]));
});

test("a valid route has no errors", () => {
  const { w, graph, ch, v, route3 } = built();
  const got = validate3(w.db, route3, ch, { graph, inns: w.inns });
  assert.deepStrictEqual(got.errors, []);
  assert.strictEqual(got.endLevel, v.endLevel, "the same replay as the format 2 route");
  // every applying step has a level estimate
  const est = estimateSteps(w.db, route3, ch, { graph, inns: w.inns });
  const steps = route3.sections.flatMap((s) => s.steps);
  assert.strictEqual(est.levels.size, steps.length);
  for (const s of steps) assert.ok(est.levels.get(s).start >= 1);
  assert.deepStrictEqual(chainOf(route3, ch).map((s) => s.id), route3.sections.map((s) => s.id));
});

test("an unreachable section, a broken reminder label and a missing grind are each reported", () => {
  const { w, graph, ch, route3 } = built();
  const opts = { graph, inns: w.inns };
  const first = route3.sections[0];
  // a section no next leads to
  const lonely = clone(route3);
  lonely.sections.push({ ...clone(first), id: "human-09-09-westland", start: undefined, next: [] });
  delete lonely.sections[lonely.sections.length - 1].start;
  const e1 = validate3(w.db, lonely, ch, opts).errors;
  assert.deepStrictEqual(e1, ["section human-09-09-westland cannot be reached from the start section"]);
  // a reminder that ends at a label nobody has
  const broken = clone(route3);
  broken.sections[0].steps[1].reminder = { ends: "turnin999" };
  const e2 = validate3(w.db, broken, ch, opts).errors;
  assert.deepStrictEqual(e2, [`section ${first.id} step ${first.steps[1].id} reminder ends at the missing label "turnin999"`]);
  const req = clone(route3);
  req.sections[0].steps[2].requires = "nowhere";
  assert.deepStrictEqual(validate3(w.db, req, ch, opts).errors, [`section ${first.id} step ${first.steps[2].id} requires the missing label "nowhere"`]);
  // a step that needs a level far above the estimate, with no grind before it
  const high = clone(route3);
  const last = high.sections[0].steps.length - 1;
  high.sections[0].steps[last].minLevel = 40;
  const e3 = validate3(w.db, high, ch, opts).errors;
  assert.strictEqual(e3.length, 1);
  assert.match(e3[0], new RegExp(`^section ${first.id} step ${first.steps[last].id.replace(/[.#]/g, "\\$&")} needs level 40, the estimate there is \\d+ and no grind to 40 comes before it$`));
  // a grind line limited to another class does not stand in for the character's own grind
  const other = clone(high);
  const grindLine = { kind: "grind", level: 40, when: { class: "MAGE" } };
  other.sections[0].steps.splice(last, 0, { id: "l40@100", at: clone(other.sections[0].steps[last - 1].at || { zone: 100, x: 30, y: 50 }), lines: [grindLine] });
  const e5 = validate3(w.db, other, ch, opts).errors;
  assert.ok(e5.some((e) => /needs level 40, the estimate there is \d+ and no grind to 40 comes before it$/.test(e)), e5.join("\n"));
  // a section that starts more than one level below the one before it
  const down = clone(route3);
  down.sections[0].next = [{ section: "human-01-01-low" }];
  down.sections.push({ ...clone(first), id: "human-01-01-low", minLevel: Math.max(1, first.minLevel), steps: [{ id: "g100@100", at: { zone: 100, x: 30, y: 50, r: 20 }, lines: [{ kind: "goto", at: { zone: 100, x: 30, y: 50, r: 20 } }] }] });
  delete down.sections[1].start;
  down.sections[0].minLevel = 4; down.sections[0].maxLevel = 7;
  const e4 = validate3(w.db, down, ch, opts).errors;
  assert.ok(e4.includes(`section human-01-01-low starts at level ${Math.max(1, first.minLevel)}, more than one level below section ${first.id} (4)`), e4.join("\n"));
});
