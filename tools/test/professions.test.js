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
// the trainer steps; their reminders ("raise the skill to the gate") are p<skill>-<rank>-skill
const profSteps = (sections) => sections.flatMap((s) => s.steps).filter((s) => /^p\d+-\d$/.test(s.id));
const reminderSteps = (sections) => sections.flatMap((s) => s.steps).filter((s) => /^p\d+-\d-skill$/.test(s.id));

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

test("a trainer step is written late in the first section at or after the rank's level with that trainer in its zone", () => {
  const { w } = world();
  const sections = chain([100, 200], 6);
  // Westland 8 to 12, Eastland 13 to 21: level 10 is reached in Westland, where no smith trains
  const levels = [8, 9, 10, 11, 12, 12, 13, 15, 17, 19, 20, 21];
  const notes = [];
  const before = JSON.stringify(sections);
  const out = addProfessionSteps(w.db, sections, "Alliance", { professions: SMITH, levelOf: levelsOf(sections, levels), notes });
  assert.strictEqual(JSON.stringify(sections), before, "the input is not changed");
  // before the last step of Eastland: both reminders, at Eastland's start, stay on screen for nearly all of it
  assert.deepStrictEqual(out[1].steps.map((s) => s.id), ["p164-2-skill", "p164-3-skill", ...sections[1].steps.slice(0, 5).map((s) => s.id),
    "p164-2", "p164-3", sections[1].steps[5].id]);
  assert.deepStrictEqual(out[1].steps[7], { id: "p164-2", label: "train164_2", when: { profession: 164 }, at: P(200, 78, 52, 10),
    lines: [{ kind: "train", skill: 164, rank: 2, npc: 700 }] });
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

test("each trainer step has a reminder to raise the skill to the rank's gate, from the start of its section", () => {
  const { w } = world();
  const sections = chain([100, 200], 6);
  const levels = [8, 9, 10, 11, 12, 12, 13, 15, 17, 19, 20, 21];
  const out = addProfessionSteps(w.db, sections, "Alliance", { professions: SMITH, levelOf: levelsOf(sections, levels), notes: [] });
  assert.deepStrictEqual(reminderSteps(out), [
    { id: "p164-2-skill", when: { profession: 164 }, reminder: { ends: "train164_2" }, lines: [{ kind: "skill", skill: 164, value: 50 }] },
    { id: "p164-3-skill", when: { profession: 164 }, reminder: { ends: "train164_3" }, lines: [{ kind: "skill", skill: 164, value: 125 }] },
  ]);
  // in the train step's section, before it, with the same condition
  for (const r of reminderSteps(out)) {
    const section = out.find((s) => s.steps.includes(r));
    const at = section.steps.indexOf(r), train = section.steps.findIndex((s) => s.label === r.reminder.ends);
    assert.ok(train > at, `${r.id} comes before its train step`);
    assert.deepStrictEqual(section.steps[train].when, r.when);
  }
  assert.strictEqual(reminderSteps([out[0]]).length, 0, "nothing in a section without a trainer step");
  // a rank with no step gets no reminder
  assert.ok(!reminderSteps(out).some((r) => r.id === "p164-4-skill"));
  assert.strictEqual(checkRoute3({ format: 3, race: "Human", faction: "Alliance", sections: out }), null);
});

// sections whose steps stand in the zones given, one list of zones per section
function zoned(lists) {
  const sections = chain(lists.map((zones) => zones[0]), 0);
  lists.forEach((zones, i) => { sections[i].steps = zones.map((zone) => obj(zone)); });
  return sections;
}
const trainIndex = (out, id) => { const si = out.findIndex((s) => s.steps.some((x) => x.id === id)); return [si, out[si] ? out[si].steps.findIndex((x) => x.id === id) : -1]; };

test("a trainer zone visited only at the start of a section moves the trainer step to a later section of the three", () => {
  const { w } = world();
  // the smith's zone (200) is the first step of section 0 only, and all of section 1
  const sections = zoned([[200, 100, 100, 100, 100, 100], [200, 200, 200, 200, 200, 200]]);
  const levels = Array(12).fill(12);
  const out = addProfessionSteps(w.db, sections, "Alliance", { professions: SMITH, levelOf: levelsOf(sections, levels), notes: [] });
  assert.deepStrictEqual(trainIndex(out, "p164-2"), [1, 1 + 5], "before the last step of section 1 (after its reminder)");
  assert.deepStrictEqual(trainIndex(out, "p164-2-skill"), [1, 0]);
  assert.strictEqual(out[0].steps.length, 6, "nothing in section 0");
  assert.strictEqual(checkRoute3({ format: 3, race: "Human", faction: "Alliance", sections: out }), null);
});

test("with no section where the trainer zone reaches the second half, the step goes where the most of its section is before it", () => {
  const { w } = world();
  // section 0: the smith's zone at its first step; section 1: at its fourth of eight (3 before it, under half);
  // section 2: none
  const sections = zoned([[200, 100, 100, 100], [100, 100, 100, 200, 100, 100, 100, 100], [100, 100, 100]]);
  const levels = Array(15).fill(12);
  const out = addProfessionSteps(w.db, sections, "Alliance", { professions: SMITH, levelOf: levelsOf(sections, levels), notes: [] });
  assert.deepStrictEqual(trainIndex(out, "p164-2"), [1, 1 + 3]);
  assert.strictEqual(out[1].steps[1 + 4].id, sections[1].steps[3].id, "right before the step in the smith's zone");
  assert.deepStrictEqual(trainIndex(out, "p164-2-skill"), [1, 0]);
  assert.strictEqual(checkRoute3({ format: 3, race: "Human", faction: "Alliance", sections: out }), null);
});

test("a trainer step is never the last step of its section, so its reminder never holds the end of the section", () => {
  const { w } = world();
  const sections = chain([200, 200], 5);
  const levels = Array.from({ length: 10 }, (_, i) => 10 + 2 * i);
  const out = addProfessionSteps(w.db, sections, "Alliance", { professions: SMITH, levelOf: levelsOf(sections, levels), notes: [] });
  for (const step of profSteps(out)) {
    const section = out.find((s) => s.steps.includes(step));
    const after = section.steps.slice(section.steps.indexOf(step) + 1);
    assert.ok(after.some((s) => !s.when), `${step.id} has a step every character has after it`);
  }
});

test("in the shipped routes the profession characters' reminders cover most of their section, and no trainer step ends one", () => {
  const fs = require("fs");
  const path = require("path");
  const { parseRoute } = require("../sim_all");
  const routes = path.join(__dirname, "..", "..", "NoirGuides", "Routes");
  const shared = (s) => !s.when && !s.reminder;
  const lead = {};
  for (const file of fs.readdirSync(routes).filter((f) => f.endsWith(".lua"))) {
    const route = parseRoute(fs.readFileSync(path.join(routes, file), "utf8"));
    for (const section of route.sections) {
      section.steps.forEach((step, i) => {
        if (!/^p\d+-\d$/.test(step.id)) return;
        assert.ok(section.steps.slice(i + 1).some(shared), `${route.race} ${step.id} has a shared step after it`);
        lead[`${route.race} ${step.id}`] = section.steps.slice(0, i).filter(shared).length / section.steps.filter(shared).length;
      });
    }
  }
  // sim_all.js PROFESSION_CHARACTERS: Human Mining, Undead Tailoring (its Artisan trainer is only in Undercity, which
  // the route passes through at the start of a section: the longest lead there is)
  for (const key of ["Human p186-2", "Human p186-3", "Undead p197-2", "Undead p197-3"]) {
    assert.ok(lead[key] >= 0.5, `${key}: ${lead[key]}`);
  }
  for (const key of ["Human p186-4", "Undead p197-4"]) assert.ok(lead[key] !== undefined, key);
  // Artisan (rank 4) trainers sit in cities the routes pass at a section start (levels 36-40), so their reminder
  // starts late; no more of those than now (24 of 194 after the 0.4 route order), until reminders reach back a section.
  const short = Object.values(lead).filter((v, i, all) => v * 1 < 0.05).length;
  assert.ok(short <= 24, `trainer steps with almost no reminder lead: ${short}`);
});
