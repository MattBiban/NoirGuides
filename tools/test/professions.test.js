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
  // 5 shared steps of lead: Journeyman's reminder reaches back into Westland (Expert's not: Journeyman is trained
  // in Eastland, so the skill cannot reach Expert's gate in Westland)
  assert.deepStrictEqual(out[0].steps.map((s) => s.id), ["p164-2-skill-lead", ...sections[0].steps.map((s) => s.id)]);
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
  assert.deepStrictEqual(out[0].steps.map((s) => s.id), ["p164-2-skill-lead", ...sections[0].steps.map((s) => s.id)],
    "only the reminder's leg in section 0 (5 steps of lead in section 1)");
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

test("a trainer step with a short lead also gets a reminder leg in the section before, ending one shared step before its end", () => {
  const { w } = world();
  // the smith's zone (200) is only the first step of section 1: no lead there
  const sections = zoned([Array(12).fill(100), [200, ...Array(11).fill(100)]]);
  const out = addProfessionSteps(w.db, sections, "Alliance", { professions: SMITH, levelOf: levelsOf(sections, Array(24).fill(12)), notes: [] });
  assert.deepStrictEqual(trainIndex(out, "p164-2"), [1, 1]);
  assert.deepStrictEqual(out[0].steps[0], { id: "p164-2-skill-lead", when: { profession: 164 }, reminder: { ends: "leadend" },
    lines: [{ kind: "skill", skill: 164, value: 50 }] });
  // the second-to-last step every character has gets the label: the last one is after it, so the leg (with work left)
  // never holds the place at the end of section 0 (spec 2.4)
  assert.deepStrictEqual(out[0].steps.map((s) => s.label).filter(Boolean), ["leadend"]);
  assert.strictEqual(out[0].steps[11].label, "leadend");
  assert.strictEqual(out[0].steps[11].id, sections[0].steps[10].id);
  assert.strictEqual(out[0].steps[12].id, sections[0].steps[11].id);
  assert.strictEqual(sections[0].steps[10].label, undefined, "the input is not changed");
  // the reminder in the train step's own section is still there
  assert.deepStrictEqual(trainIndex(out, "p164-2-skill"), [1, 0]);
  assert.strictEqual(checkRoute3({ format: 3, race: "Human", faction: "Alliance", sections: out }), null);
  // a label the step already has is the one the leg ends at
  sections[0].steps[10].label = "turnin7";
  const again = addProfessionSteps(w.db, sections, "Alliance", { professions: SMITH, levelOf: levelsOf(sections, Array(24).fill(12)), notes: [] });
  assert.deepStrictEqual(again[0].steps[0].reminder, { ends: "turnin7" });
  assert.deepStrictEqual(again[0].steps.map((s) => s.label).filter(Boolean), ["turnin7"]);
  assert.strictEqual(checkRoute3({ format: 3, race: "Human", faction: "Alliance", sections: again }), null);
});

test("no leg with ten shared steps of lead, and none before the first section", () => {
  const { w } = world();
  const sections = zoned([Array(12).fill(100), [...Array(10).fill(100), 200, 100]]);
  const out = addProfessionSteps(w.db, sections, "Alliance", { professions: SMITH, levelOf: levelsOf(sections, Array(24).fill(12)), notes: [] });
  assert.deepStrictEqual(trainIndex(out, "p164-2"), [1, 1 + 10]);
  assert.strictEqual(out[0].steps.length, 12);
  const first = zoned([[200, 100, 100, 100]]);
  const alone = addProfessionSteps(w.db, first, "Alliance", { professions: SMITH, levelOf: levelsOf(first, Array(4).fill(12)), notes: [] });
  assert.deepStrictEqual(alone[0].steps.map((s) => s.id).filter((id) => id.startsWith("p")), ["p164-2-skill", "p164-2"]);
});

test("a leg starts right after the previous rank's trainer step when that is in the section before", () => {
  const { w } = world();
  // Journeyman in section 0 (before its sixth step), Expert at the first step of section 1
  const sections = zoned([[...Array(6).fill(200), ...Array(6).fill(100)], [200, ...Array(11).fill(100)]]);
  const levels = [...Array(12).fill(10), ...Array(12).fill(20)];
  const out = addProfessionSteps(w.db, sections, "Alliance", { professions: SMITH, levelOf: levelsOf(sections, levels), notes: [] });
  const ids = out[0].steps.map((s) => s.id);
  assert.strictEqual(ids.indexOf("p164-3-skill-lead"), ids.indexOf("p164-2") + 1, "right after the Journeyman trainer step");
  assert.ok(ids.indexOf("p164-2") > 0);
  assert.ok(!ids.includes("p164-2-skill-lead"), "nothing before the first section");
  assert.deepStrictEqual(out[0].steps[ids.indexOf("p164-3-skill-lead")].lines, [{ kind: "skill", skill: 164, value: 125 }]);
  assert.strictEqual(checkRoute3({ format: 3, race: "Human", faction: "Alliance", sections: out }), null);
});

test("in the shipped routes the profession characters' reminders cover most of their section or reach back a section, and neither a trainer step nor a leg ends one", () => {
  const fs = require("fs");
  const path = require("path");
  const { parseRoute } = require("../sim_all");
  const routes = path.join(__dirname, "..", "..", "NoirGuides", "Routes");
  const shared = (s) => !s.when && !s.reminder;
  const lead = {}, combined = {};
  let legs = 0;
  for (const file of fs.readdirSync(routes).filter((f) => f.endsWith(".lua"))) {
    const route = parseRoute(fs.readFileSync(path.join(routes, file), "utf8"));
    for (const section of route.sections) {
      const sharedSteps = section.steps.filter(shared);
      section.steps.forEach((step, i) => {
        if (/^p\d+-\d-skill-lead$/.test(step.id)) {
          // a leg ends at a later shared step that is not the section's last one: with work left it never holds the
          // place at the end of the section (spec 2.4); its line and condition are its trainer step's reminder's
          legs++;
          const end = section.steps.findIndex((s) => s.label === step.reminder.ends);
          assert.ok(end > i && shared(section.steps[end]), `${route.race} ${step.id} ends at a later shared step`);
          assert.ok(section.steps.slice(end + 1).some(shared), `${route.race} ${step.id} does not end at the section's last shared step`);
          const next = route.sections.find((s) => (section.next || []).some((n) => n.section === s.id));
          const main = next && next.steps.find((s) => s.id === step.id.replace(/-lead$/, ""));
          assert.ok(main, `${route.race} ${step.id}: its trainer step's reminder is in the next section`);
          assert.deepStrictEqual([step.lines, step.when], [main.lines, main.when]);
          return;
        }
        if (!/^p\d+-\d$/.test(step.id)) return;
        assert.ok(section.steps.slice(i + 1).some(shared), `${route.race} ${step.id} has a shared step after it`);
        const own = section.steps.slice(0, i).filter(shared).length;
        lead[`${route.race} ${step.id}`] = own / sharedSteps.length;
        // shared steps the reminder is on screen for: from its own section's start, and from its leg in the section
        // before (if any) to the leg's end
        const before = route.sections.find((s) => (s.next || []).some((n) => n.section === section.id));
        const k = before ? before.steps.findIndex((s) => s.id === `${step.id}-skill-lead`) : -1;
        const end = k >= 0 ? before.steps.findIndex((s) => s.label === before.steps[k].reminder.ends) : -1;
        combined[`${route.race} ${step.id}`] = own + (k >= 0 ? before.steps.slice(k + 1, end + 1).filter(shared).length : 0);
      });
    }
  }
  // sim_all.js PROFESSION_CHARACTERS: Human Mining, Undead Tailoring (its Artisan trainer is only in Undercity, which
  // the route passes through at the start of a section: the longest lead there is)
  for (const key of ["Human p186-2", "Human p186-3", "Undead p197-2", "Undead p197-3"]) {
    assert.ok(lead[key] >= 0.5, `${key}: ${lead[key]}`);
  }
  for (const key of ["Human p186-4", "Undead p197-4"]) assert.ok(lead[key] !== undefined, key);
  // Artisan (rank 4) trainers sit in cities the routes pass at a section start (levels 36-40): 24 of 194 trainer
  // steps had almost no reminder lead in their own section after the 0.4 route order; a leg in the section before
  // gives every trainer step at least ten shared steps of reminder (both legs counted)
  const short = Object.values(lead).filter((v) => v < 0.05).length;
  assert.ok(short <= 24, `trainer steps with almost no reminder lead in their section: ${short}`);
  assert.deepStrictEqual(Object.entries(combined).filter(([, n]) => n < 10).map(([k, n]) => `${k}: ${n}`), []);
  assert.ok(legs >= 24, `reminder legs: ${legs}`);
});
