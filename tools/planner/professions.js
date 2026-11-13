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
// reminder and the step it ends at in one section, so a section's length is as far ahead as it can stand). The engine
// passes a train step while the skill is below the gate, and the reminder ends with it, so the train step goes as
// late in its section as the trainers allow: the candidates are the steps (ones every character has, not reminders)
// at or after the rank's level that stand in a zone where a trainer of that profession and rank stands, friendly to
// the faction, searched from the section where the level is reached through the two after it. The train step goes
// right before the last candidate of the first of those sections where that candidate has at least LEAD_SHARE (half)
// of the section's shared steps before it, so the reminder stays on screen for most of the section (and from before
// the rank's level when the level is reached inside it); with no such section, before the candidate with the most
// shared steps of its section before it, the earliest on ties. Its trainer is the nearest of that zone's to that
// step. A rank with no candidate, or whose level the route never reaches, gets no step and a note
// (docs/routes/PROFESSION-NOTES.md).
// When the train step has fewer than LEAD_STEPS (10) shared steps of its section before it, the reminder also gets a
// leg in the section played just before (the one whose next names it; with none, the one before it in the list):
//   { id = "p<skill>-<rank>-skill-lead", when = { profession = <skill> }, reminder = { ends = <label> },
//     lines = { the same skill line } }
// at that section's start, or right after the previous rank's train step when that is in it (none when the previous
// rank's step is in the train step's own section or later: the skill cannot reach the gate before it). It ends at the
// second-to-last shared step of that section, which keeps its label or gets LEAD_END ("leadend"): never at the last,
// since an open reminder with work left holds the place at the end of its section (spec 2.4). Both legs check the same
// skill, so the one in the train step's section is finished as soon as it opens once the skill is reached.
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
const LEAD_SHARE = 0.5;
// a trainer step with fewer shared steps of its section before it than LEAD_STEPS also gets a reminder leg in the section before (LEAD_END: the label that leg ends at, when its step has none)
const LEAD_STEPS = 10, LEAD_END = "leadend";
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
  sections.forEach((s, si) => s.steps.forEach((step) => { if (!step.when && !step.reminder && step.at) shared.push({ si, step }); }));
  // per shared step, how many shared steps of its section come before it; per section, how many it has
  const leadOf = new Map(), sizes = sections.map(() => 0);
  for (const { si, step } of shared) leadOf.set(step, sizes[si]++);
  // The train step's place among the candidates (route order): the last one of the first section in which that one
  // stands in the second half of the section (LEAD_SHARE), so the reminder at the section's start is on screen for
  // most of the section; with none such, the one with the longest lead, the earliest on ties.
  const choose = (candidates) => {
    const last = new Map();
    for (const c of candidates) last.set(c.si, c);
    for (const c of last.values()) if (c.lead >= LEAD_SHARE * sizes[c.si]) return c;
    let best = null;
    for (const c of candidates) if (!best || c.lead > best.lead) best = c;
    return best;
  };
  const inserts = new Map();
  const reminders = new Map(); // section index -> reminder steps for its start
  const placed = new Map(); // trainer step id -> { si, step: the shared step it stands before }
  const legs = []; // { si, after: trainer step id or null, step }: reminder legs in the section before
  const endLabel = new Map(); // shared step -> the label a leg ends at
  // the section played just before section si: the one whose next names it, else the one before it in the list
  const previousSection = (si) => {
    const id = sections[si].id;
    const k = sections.findIndex((x) => (x.next || []).some((n) => n.section === id));
    return k >= 0 ? k : si - 1;
  };
  for (const profession of professions) {
    for (const r of RANKS) {
      const label = `${profession.name} ${r.name} (rank ${r.rank}, level ${r.level})`;
      const from = shared.findIndex(({ step }) => { const l = levelOf(step); return !!l && l.start >= r.level; });
      if (from < 0) { notes.push({ skill: profession.skill, rank: r.rank, text: `${label}: the route's estimate never reaches level ${r.level}` }); continue; }
      const trainers = professionTrainers(db, profession, r.rank, faction);
      const lastSection = shared[from].si + SEARCH_SECTIONS - 1;
      // every step in the window that stands in a trainer's zone, with the nearest trainer there
      const candidates = [];
      for (let k = from; k < shared.length && shared[k].si <= lastSection; k++) {
        const { si, step } = shared[k];
        const zone = zoneOf(db, step.at.zone);
        const here = zoneOnly(step.at) ? null : toPoint(db, step.at.zone, step.at.x, step.at.y);
        let pick = null;
        for (const t of trainers) for (const p of t.points) {
          if (p.zone !== zone) continue;
          const d = here ? distance(here, p) : 0;
          if (!pick || d < pick.d || (d === pick.d && t.npc < pick.npc)) pick = { npc: t.npc, point: p, d };
        }
        if (pick) candidates.push({ si, step, pick, lead: leadOf.get(step) });
      }
      const found = choose(candidates);
      if (!found) {
        notes.push({ skill: profession.skill, rank: r.rank, text: `${label}: no ${faction} trainer in a zone of the route within three sections of section ${sections[shared[from].si].id}` });
        continue;
      }
      const { npc, point } = found.pick;
      const id = `p${profession.skill}-${r.rank}`, ends = `train${profession.skill}_${r.rank}`;
      if (!inserts.has(found.step)) inserts.set(found.step, []);
      inserts.get(found.step).push({ id, label: ends, when: { profession: profession.skill },
        at: { zone: point.zone, x: round2(point.x), y: round2(point.y), r: NPC_RADIUS }, lines: [{ kind: "train", skill: profession.skill, rank: r.rank, npc }] });
      const si = found.si;
      placed.set(id, { si, step: found.step });
      if (!reminders.has(si)) reminders.set(si, []);
      const line = { kind: "skill", skill: profession.skill, value: r.gate };
      reminders.get(si).push({ id: `${id}-skill`, when: { profession: profession.skill }, reminder: { ends }, lines: [line] });
      // a short lead: the reminder reaches back into the section played just before
      if (found.lead >= LEAD_STEPS) continue;
      const pi = previousSection(si);
      if (pi < 0) continue;
      const own = shared.filter((x) => x.si === pi);
      if (own.length < 2) continue;
      const endStep = own[own.length - 2].step; // never the section's last shared step: it would hold the section end
      const before = placed.get(`p${profession.skill}-${r.rank - 1}`);
      let after = null; // the previous rank's trainer step, when it is in that section (the leg starts after it)
      if (before) {
        if (before.si >= si) continue; // the skill cannot pass the previous rank's cap there yet
        if (before.si === pi) {
          if (leadOf.get(before.step) >= own.length - 2) continue; // no room between it and the leg's end
          after = `p${profession.skill}-${r.rank - 1}`;
        } else if (before.si > pi) continue;
      }
      endLabel.set(endStep, endStep.label || endLabel.get(endStep) || LEAD_END);
      legs.push({ si: pi, after, step: { id: `${id}-skill-lead`, when: { profession: profession.skill }, reminder: { ends: endLabel.get(endStep) }, lines: [{ ...line }] } });
    }
  }
  const labeled = (step) => (endLabel.has(step) && !step.label ? { ...step, label: endLabel.get(step) } : step);
  return sections.map((s, si) => {
    const mine = legs.filter((l) => l.si === si);
    const start = [...(reminders.get(si) || []), ...mine.filter((l) => !l.after).map((l) => l.step)];
    const legsAfter = (step) => mine.filter((l) => l.after === step.id).map((l) => l.step);
    return { ...s, steps: [...start, ...s.steps.flatMap((step) => [...(inserts.get(step) || []).flatMap((t) => [t, ...legsAfter(t)]), labeled(step)])] };
  });
}

module.exports = { addProfessionSteps, primaryProfessions, professionTrainers, RANKS };
