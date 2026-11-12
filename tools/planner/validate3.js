// Noir Guides, GPLv3. See LICENSE.
// The format 3 validator: a route file replayed for one character (task P3 in
// docs/superpowers/plans/2026-11-11-guide-rebuild.md).
//
//   validate3(db, route3, character, options) -> { errors, warnings, endLevel, levels }
//       the character's chain of sections (from the start section through `next`, the first candidate that exists and
//       applies), its applying steps and lines flattened to format 2 actions (planner/bundle.js flatten) and replayed
//       by planner/validate.js; its errors are named by section and step. Then:
//         - every section is reachable from the start section through next
//         - along the character's chain, a section's minLevel is never more than 1 below the one before it
//         - every reminder.ends and requires names a label of its section (ends on a later step)
//         - every applying step whose minLevel is above the estimate has a grind to that level before it
//       options: { graph, inns } as validateRoute takes them, and professions: [skill line IDs] the character plans
//   estimateSteps(db, route3, character, options) -> { chain, steps, levels, result }
//       steps: the applying steps in order, as { section, step }; levels: Map step -> { start, end, clock }, the
//       estimated level at its start and end and the seconds played at its start (a step without actions takes the
//       level and clock of the next action); result: validateRoute's
//   applies(when, character, professions) -> boolean     a format 3 condition
//   chainOf(route3, character, professions) -> sections   the character's chain
const { flatten } = require("./bundle");
const { validateRoute } = require("./validate");

const list = (v) => (Array.isArray(v) ? v : [v]);
function applies(when, ch, professions = []) {
  if (!when) return true;
  if (when.class !== undefined && !list(when.class).includes(ch.cls)) return false;
  if (when.notClass !== undefined && list(when.notClass).includes(ch.cls)) return false;
  if (when.race !== undefined && !list(when.race).includes(ch.race)) return false;
  if (when.notRace !== undefined && list(when.notRace).includes(ch.race)) return false;
  if (when.profession !== undefined && !professions.includes(when.profession)) return false;
  return true;
}

function chainOf(route3, ch, professions = []) {
  const byId = new Map(route3.sections.map((s) => [s.id, s]));
  const chain = [];
  const seen = new Set();
  let s = route3.sections.find((x) => x.start === true);
  while (s && !seen.has(s.id)) {
    seen.add(s.id);
    if (applies(s.when, ch, professions)) chain.push(s);
    const next = (s.next || []).find((n) => byId.has(n.section) && applies(n.when, ch, professions) && applies(byId.get(n.section).when, ch, professions));
    s = next ? byId.get(next.section) : null;
  }
  return chain;
}

function estimateSteps(db, route3, ch, options = {}) {
  const professions = options.professions || [];
  const chain = chainOf(route3, ch, professions);
  const steps = [];
  const actions = [];
  const owner = []; // owner[k] = index in steps of the step action k came from
  for (const section of chain) {
    for (const step of section.steps) {
      if (!applies(step.when, ch, professions)) continue;
      const lines = step.lines.filter((l) => applies(l.when, ch, professions));
      const mine = flatten([{ ...step, when: undefined, lines: lines.map((l) => ({ ...l, when: undefined })) }]);
      for (const a of mine) { delete a.when; actions.push(a); owner.push(steps.length); }
      steps.push({ section, step });
    }
  }
  const result = validateRoute(db, { format: 2, steps: actions }, ch, { graph: options.graph, inns: options.inns });
  // the level at each step's start: its first action's, else the next action's, else the end
  const firstAction = new Array(steps.length).fill(-1);
  owner.forEach((i, k) => { if (firstAction[i] < 0) firstAction[i] = k; });
  const startOf = new Array(steps.length), clockOf = new Array(steps.length);
  let next = result.endLevel, nextClock = result.seconds;
  for (let i = steps.length - 1; i >= 0; i--) {
    if (firstAction[i] >= 0) { next = result.levels[firstAction[i]]; nextClock = result.clocks[firstAction[i]]; }
    startOf[i] = next;
    clockOf[i] = nextClock;
  }
  const levels = new Map();
  steps.forEach(({ step }, i) => levels.set(step, { start: startOf[i], end: i + 1 < steps.length ? startOf[i + 1] : result.endLevel, clock: clockOf[i] }));
  return { chain, steps, levels, result, owner };
}

function validate3(db, route3, ch, options = {}) {
  const errors = [];
  const est = estimateSteps(db, route3, ch, options);
  // the replay's errors, named by section and step
  for (const e of est.result.errors) {
    const m = /^step (\d+): ([\s\S]*)$/.exec(e);
    if (!m) { errors.push(e); continue; }
    const { section, step } = est.steps[est.owner[+m[1] - 1]];
    errors.push(`section ${section.id} step ${step.id}: ${m[2]}`);
  }
  // reachable from the start
  const byId = new Map(route3.sections.map((s) => [s.id, s]));
  const reached = new Set();
  const start = route3.sections.find((s) => s.start === true);
  const open = start ? [start.id] : [];
  while (open.length) {
    const id = open.pop();
    if (reached.has(id) || !byId.has(id)) continue;
    reached.add(id);
    for (const n of byId.get(id).next || []) open.push(n.section);
  }
  for (const s of route3.sections) if (!reached.has(s.id)) errors.push(`section ${s.id} cannot be reached from the start section`);
  // levels along the chain
  for (let i = 1; i < est.chain.length; i++) {
    const a = est.chain[i - 1], b = est.chain[i];
    if (b.minLevel < a.minLevel - 1) errors.push(`section ${b.id} starts at level ${b.minLevel}, more than one level below section ${a.id} (${a.minLevel})`);
  }
  // labels
  for (const s of route3.sections) {
    const labels = new Map();
    s.steps.forEach((st, k) => { if (st.label && !labels.has(st.label)) labels.set(st.label, k); });
    s.steps.forEach((st, k) => {
      const ends = st.reminder && st.reminder.ends;
      if (ends !== undefined && ends !== "next") {
        if (!labels.has(ends)) errors.push(`section ${s.id} step ${st.id} reminder ends at the missing label "${ends}"`);
        else if (labels.get(ends) <= k) errors.push(`section ${s.id} step ${st.id} reminder ends at "${ends}", which is not a later step`);
      }
      if (st.requires !== undefined && !labels.has(st.requires)) errors.push(`section ${s.id} step ${st.id} requires the missing label "${st.requires}"`);
    });
  }
  // grinds before steps above the estimate
  const grindTo = new Map(); // section id -> highest grind level so far in the character's replay
  for (const { section, step } of est.steps) {
    const top = grindTo.get(section.id) || 0;
    if (step.minLevel !== undefined) {
      const at = Math.floor(est.levels.get(step).start);
      if (at < step.minLevel && top < step.minLevel) {
        errors.push(`section ${section.id} step ${step.id} needs level ${step.minLevel}, the estimate there is ${at} and no grind to ${step.minLevel} comes before it`);
      }
    }
    // only grind lines that apply to this character count (a grind for another class lifts nobody here)
    for (const l of step.lines) if (l.kind === "grind" && applies(l.when, ch, options.professions || [])) grindTo.set(section.id, Math.max(grindTo.get(section.id) || 0, l.level));
  }
  return { errors, warnings: est.result.warnings, endLevel: est.result.endLevel, levels: est.levels };
}

module.exports = { validate3, estimateSteps, applies, chainOf };
