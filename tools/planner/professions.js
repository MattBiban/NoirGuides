// Noir Guides, GPLv3. See LICENSE.
// Profession trainer steps: where a character who planned a profession learns its next rank (task P3 in
// docs/superpowers/plans/2026-11-11-guide-rebuild.md, spec 3.8).
//
//   addProfessionSteps(db, sections, faction, options) -> sections
//       new section and step lists; the steps given are reused unchanged, the trainer steps are new
//       options: { levelOf(step) -> { start, end }: the shared estimated level at a step (without it, each section's
//                  levels spread evenly), professions: [{ skill, name }] (default primaryProfessions()),
//                  notes: a list each rank that gets no step is pushed to as { skill, rank, text } }
//   primaryProfessions() -> [{ skill, name }]      the primary skill lines of NoirGuides/Data/Professions.lua
//   professionTrainers(db, profession, rank, faction) -> [{ npc, points }]
//   RANKS                                          Journeyman, Expert, Artisan with their gate, cap and level
//
// For each primary profession and each rank 2 to 4, one step
//   { id = "p<skill>-<rank>", label = "train<skill>_<rank>", when = { profession = <skill> }, at = <trainer>,
//     lines = { { kind = "train", skill, rank, npc } } }
// and its reminder step
//   { id = "p<skill>-<rank>-skill", when = { profession = <skill> }, reminder = { ends = "train<skill>_<rank>" },
//     lines = { { kind = "skill", skill, value = <the rank's gate> } } }
// at the start of the train step's section: "raise the skill to the gate" stays on screen as a reminder while that
// section is played, until the skill is reached or the train step is passed (route format 3 rule R10 keeps a
// reminder and the step it ends at in one section, so a section's length is as far ahead as it can stand). The train
// step goes
// right before the first step (one every character has) at or after the rank's level that stands in a zone where a
// trainer of that profession and rank stands, friendly to the faction; of several there, the nearest. The search runs
// from the section where the level is reached through the two after it; a rank with no trainer there, or whose level
// the route never reaches, gets no step and a note (docs/routes/PROFESSION-NOTES.md).
// Who trains a rank (QuestieDB sub names; not verified in game, see PROFESSION-NOTES.md): "<Profession> Trainer" or
// "<Crafter> Trainer" ("Blacksmithing Trainer", "Tailor Trainer") teaches every rank; "<Title> <Crafter>" teaches up
// to its title's rank: Journeyman 2, Expert 3, Artisan and Master 4 ("Expert Blacksmith" teaches 2 and 3).
const fs = require("fs");
const path = require("path");
const { toPoint, distance, spawnPoints, zoneOf } = require("../lib/geo");
const { evenLevels } = require("./training");

const RANKS = Object.freeze([
  Object.freeze({ rank: 2, name: "Journeyman", gate: 50, cap: 150, level: 10, verified: false }),
  Object.freeze({ rank: 3, name: "Expert", gate: 125, cap: 225, level: 20, verified: false }),
  Object.freeze({ rank: 4, name: "Artisan", gate: 200, cap: 300, level: 35, verified: false }),
]);
const SEARCH_SECTIONS = 3;
const NPC_RADIUS = 10; // planner/bundle.js RADIUS.npc
const CRAFTER = { Alchemy: "Alchemist", Blacksmithing: "Blacksmith", Enchanting: "Enchanter", Engineering: "Engineer", Herbalism: "Herbalist",
  Leatherworking: "Leatherworker", Mining: "Miner", Skinning: "Skinner", Tailoring: "Tailor" };
const TITLES = { Journeyman: 2, Expert: 3, Artisan: 4, Master: 4 };
const PROFESSIONS_LUA = path.join(__dirname, "..", "..", "NoirGuides", "Data", "Professions.lua");

function primaryProfessions(file = PROFESSIONS_LUA) {
  const out = [];
  const re = /\[(\d+)\]\s*=\s*\{\s*name\s*=\s*"([^"]+)",\s*kind\s*=\s*"primary"\s*\}/g;
  const text = fs.readFileSync(file, "utf8");
  for (let m = re.exec(text); m; m = re.exec(text)) out.push({ skill: +m[1], name: m[2] });
  return out.sort((a, b) => a.skill - b.skill);
}

// The highest rank an NPC's title says it teaches for this profession, or 0.
function teaches(subName, profession) {
  if (!subName) return 0;
  const crafter = CRAFTER[profession.name];
  if (subName === `${profession.name} Trainer` || (crafter && subName === `${crafter} Trainer`)) return 4;
  if (!crafter) return 0;
  const m = /^(\w+) (.+)$/.exec(subName);
  return m && m[2] === crafter && TITLES[m[1]] ? TITLES[m[1]] : 0;
}

function professionTrainers(db, profession, rank, faction) {
  const letter = faction[0];
  const out = [];
  for (const npc of db.npcs.values()) {
    if (teaches(npc.subName, profession) < rank || !(npc.friendly || "").includes(letter)) continue;
    const points = spawnPoints(db, "npc", npc.id);
    if (points.length) out.push({ npc: npc.id, points });
  }
  return out.sort((a, b) => a.npc - b.npc);
}

const round2 = (n) => Math.round(n * 100) / 100;
const zoneOnly = (p) => p.x === 0 && p.y === 0;

function addProfessionSteps(db, sections, faction, options = {}) {
  const professions = options.professions || primaryProfessions();
  const even = evenLevels(sections);
  const levelOf = options.levelOf || ((step) => even(null, step));
  const notes = options.notes || [];
  // the steps every character has, in route order, with their section's index
  const shared = [];
  sections.forEach((s, si) => s.steps.forEach((step) => { if (!step.when && step.at) shared.push({ si, step }); }));
  const inserts = new Map();
  const reminders = new Map(); // section index -> reminder steps for its start
  for (const profession of professions) {
    for (const r of RANKS) {
      const label = `${profession.name} ${r.name} (rank ${r.rank}, level ${r.level})`;
      const from = shared.findIndex(({ step }) => { const l = levelOf(step); return !!l && l.start >= r.level; });
      if (from < 0) { notes.push({ skill: profession.skill, rank: r.rank, text: `${label}: the route's estimate never reaches level ${r.level}` }); continue; }
      const trainers = professionTrainers(db, profession, r.rank, faction);
      const lastSection = shared[from].si + SEARCH_SECTIONS - 1;
      let found = null;
      for (let k = from; k < shared.length && shared[k].si <= lastSection && !found; k++) {
        const { step } = shared[k];
        const zone = zoneOf(db, step.at.zone);
        const here = zoneOnly(step.at) ? null : toPoint(db, step.at.zone, step.at.x, step.at.y);
        let pick = null;
        for (const t of trainers) for (const p of t.points) {
          if (p.zone !== zone) continue;
          const d = here ? distance(here, p) : 0;
          if (!pick || d < pick.d || (d === pick.d && t.npc < pick.npc)) pick = { npc: t.npc, point: p, d };
        }
        if (pick) found = { step, pick };
      }
      if (!found) {
        notes.push({ skill: profession.skill, rank: r.rank, text: `${label}: no ${faction} trainer in a zone of the route within three sections of section ${sections[shared[from].si].id}` });
        continue;
      }
      const { npc, point } = found.pick;
      const id = `p${profession.skill}-${r.rank}`, ends = `train${profession.skill}_${r.rank}`;
      if (!inserts.has(found.step)) inserts.set(found.step, []);
      inserts.get(found.step).push({ id, label: ends, when: { profession: profession.skill },
        at: { zone: point.zone, x: round2(point.x), y: round2(point.y), r: NPC_RADIUS }, lines: [{ kind: "train", skill: profession.skill, rank: r.rank, npc }] });
      const si = sections.findIndex((s) => s.steps.includes(found.step));
      if (!reminders.has(si)) reminders.set(si, []);
      reminders.get(si).push({ id: `${id}-skill`, when: { profession: profession.skill }, reminder: { ends },
        lines: [{ kind: "skill", skill: profession.skill, value: r.gate }] });
    }
  }
  return sections.map((s, si) => ({ ...s, steps: [...(reminders.get(si) || []), ...s.steps.flatMap((step) => [...(inserts.get(step) || []), step])] }));
}

module.exports = { addProfessionSteps, primaryProfessions, professionTrainers, RANKS };
