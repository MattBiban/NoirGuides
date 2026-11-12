// Noir Guides, GPLv3. See LICENSE.
// Profession trainer steps (tools/planner/professions.js, task P3 of docs/superpowers/plans/2026-11-11-guide-rebuild.md,
// spec 3.8). Every map of the test world is 1000 yards square.
const test = require("node:test");
const assert = require("node:assert");
const { testWorld } = require("./world");
const { checkRoute3 } = require("../planner/format3");
const { applies } = require("../planner/validate3");
const { addProfessionSteps, primaryProfessions, professionTrainers, RANKS } = require("../planner/professions");

const P = (zone, x, y, r) => (r === undefined ? { zone, x, y } : { zone, x, y, r });
const SMITH = [{ skill: 164, name: "Blacksmithing" }];
function world() {
  const w = testWorld();
  const npc = (id, zone, x, y, friendly, subName) => w.db.npcs.set(id, { id, name: `Npc ${id}`, friendly, subName, spawns: { [zone]: [[x, y]] } });
  npc(700, 200, 78, 52, "A", "Blacksmithing Trainer");
  npc(701, 200, 70, 50, "H", "Blacksmithing Trainer");
  return { w, npc };
}
let serial = 0;
const obj = (zone, x = 50, y = 50) => { const q = 7000 + serial++; return { id: `o${q}`, at: P(zone, x, y, 40), lines: [{ kind: "objective", quest: q, index: 1 }] }; };
function chain(zones, perSection) {
  const sections = zones.map((zone, i) => ({ id: `human-${i}-westland`, name: `${i + 1} Zone`, group: "Alliance", subgroup: "1-20", minLevel: 1, zone, next: [],
    steps: Array.from({ length: perSection }, () => obj(zone)) }));
  sections[0].start = true;
  sections.forEach((s, i) => { if (i + 1 < sections.length) s.next = [{ section: sections[i + 1].id }]; });
  return sections;
}
function levelsOf(sections, list) {
  const map = new Map();
  sections.flatMap((s) => s.steps).forEach((s, i) => map.set(s, i));
  return (step) => ({ start: list[map.get(step)], end: list[map.get(step)] });
}
const profSteps = (sections) => sections.flatMap((s) => s.steps).filter((s) => s.id.startsWith("p"));

test("the ranks are the plan's: gates 50, 125, 200, caps 150, 225, 300, levels 10, 20, 35 not verified", () => {
  assert.deepStrictEqual(RANKS.map((r) => [r.rank, r.name, r.gate, r.cap, r.level, r.verified]),
    [[2, "Journeyman", 50, 150, 10, false], [3, "Expert", 125, 225, 20, false], [4, "Artisan", 200, 300, 35, false]]);
  assert.ok(Object.isFrozen(RANKS));
});

test("the primary professions come from Data/Professions.lua", () => {
  const list = primaryProfessions();
  assert.deepStrictEqual(list.map((p) => p.skill), [164, 165, 171, 182, 186, 197, 202, 333, 393]);
  assert.strictEqual(list.find((p) => p.skill === 164).name, "Blacksmithing");
});

test("a trainer step is written at the first step at or after the rank's level in a zone with that trainer", () => {
  const { w } = world();
  const sections = chain([100, 200], 6);
  // Westland 8 to 12, Eastland 13 to 21: level 10 is reached in Westland, where no smith trains
  const levels = [8, 9, 10, 11, 12, 12, 13, 15, 17, 19, 20, 21];
  const notes = [];
  const before = JSON.stringify(sections);
  const out = addProfessionSteps(w.db, sections, "Alliance", { professions: SMITH, levelOf: levelsOf(sections, levels), notes });
  assert.strictEqual(JSON.stringify(sections), before, "the input is not changed");
  assert.deepStrictEqual(out[1].steps.map((s) => s.id), ["p164-2", sections[1].steps[0].id, sections[1].steps[1].id, sections[1].steps[2].id, sections[1].steps[3].id,
    "p164-3", sections[1].steps[4].id, sections[1].steps[5].id]);
  assert.deepStrictEqual(out[1].steps[0], { id: "p164-2", when: { profession: 164 }, at: P(200, 78, 52, 10), lines: [{ kind: "train", skill: 164, rank: 2, npc: 700 }] });
  assert.strictEqual(out[0].steps.length, 6);
  assert.deepStrictEqual(notes.map((n) => [n.skill, n.rank]), [[164, 4]], "Artisan's level is never reached");
  assert.strictEqual(checkRoute3({ format: 3, race: "Human", faction: "Alliance", sections: out }), null);
});

test("a trainer's title gives the ranks it teaches", () => {
  const { w, npc } = world();
  w.db.npcs.delete(700);
  npc(702, 100, 52, 50, "A", "Journeyman Blacksmith");
  npc(703, 100, 54, 50, "A", "Artisan Blacksmith");
  npc(704, 100, 51, 50, "A", "Blacksmithing Supplies");
  assert.deepStrictEqual(professionTrainers(w.db, SMITH[0], 2, "Alliance").map((t) => t.npc), [702, 703]);
  assert.deepStrictEqual(professionTrainers(w.db, SMITH[0], 3, "Alliance").map((t) => t.npc), [703]);
  assert.deepStrictEqual(professionTrainers(w.db, SMITH[0], 2, "Horde").map((t) => t.npc), [701]);
  // the nearest one that teaches the rank
  const sections = chain([100], 4);
  const out = addProfessionSteps(w.db, sections, "Alliance", { professions: SMITH, levelOf: levelsOf(sections, [10, 20, 21, 22]), notes: [] });
  assert.deepStrictEqual(profSteps(out).map((s) => [s.id, s.lines[0].npc]), [["p164-2", 702], ["p164-3", 703]]);
});

test("the step exists only for characters with the profession", () => {
  const { w } = world();
  const sections = chain([200], 3);
  const out = addProfessionSteps(w.db, sections, "Alliance", { professions: SMITH, levelOf: levelsOf(sections, [10, 11, 12]), notes: [] });
  const [step] = profSteps(out);
  assert.deepStrictEqual(step.when, { profession: 164 });
  assert.ok(!applies(step.when, { race: "Human", cls: "WARRIOR" }));
  assert.ok(applies(step.when, { race: "Human", cls: "WARRIOR" }, [164]));
  assert.ok(!applies(step.when, { race: "Human", cls: "WARRIOR" }, [171]));
});

test("a rank with no trainer within three sections is listed in the notes and not written", () => {
  const { w } = world();
  // level 10 is reached in the first section; the smith stands in the fourth section's zone
  const sections = chain([100, 300, 301, 200], 2);
  const notes = [];
  const out = addProfessionSteps(w.db, sections, "Alliance", { professions: SMITH, levelOf: levelsOf(sections, [10, 10, 11, 11, 12, 12, 13, 13]), notes });
  assert.deepStrictEqual(profSteps(out), []);
  assert.deepStrictEqual(notes.map((n) => [n.skill, n.rank]), [[164, 2], [164, 3], [164, 4]]);
  assert.match(notes[0].text, /^Blacksmithing Journeyman \(rank 2, level 10\): no Alliance trainer in a zone of the route within three sections of section human-0-westland$/);
  // the Horde trainer in that zone is not used either
  const horde = addProfessionSteps(w.db, sections, "Horde", { professions: SMITH, levelOf: levelsOf(sections, [10, 10, 11, 11, 12, 12, 13, 13]), notes: [] });
  assert.deepStrictEqual(profSteps(horde), []);
});
