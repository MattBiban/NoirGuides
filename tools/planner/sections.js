// Noir Guides, GPLv3. See LICENSE.
// Sections: a race's bundled format 3 steps (planner/bundle.js) cut into a chain of sections, each with a level range,
// a main zone, a name and an id; grind steps where the estimated level is under a step's minimum; level caps on the
// steps that only accept quests (task P2 in docs/superpowers/plans/2026-11-11-guide-rebuild.md, spec 2.1 and 3.7).
//
//   splitSections(db, race, faction, bundled, levelsByStep, classLevels, notes) -> Section3[] (no step `text` yet)
//       bundled       bundleSteps' result ({ steps, origin }) or its step list; it is not changed
//       levelsByStep  levelsByStep[i] = { start, end }: the shared route's estimated level at the start and end of
//                     step i (a fraction is part of a level: 4.9 is level 4)
//       classLevels   classLevels[CLASS] = the same list for that class's own replay of the route, one entry per
//                     bundled step (entries of steps that do not apply to the class are not read)
//       notes         optional list the planner's notes are pushed to as sentences: accept steps whose quests are
//                     grey before the step's minLevel or at the estimated level, zones without a name
//   insertGrinds(steps, levelsByStep, classLevels) -> steps (a new list; classLevels optional, as above)
//   regrindSections(sections, classes, levelOf) -> sections   the grinds again after steps were added to finished
//       sections (levelOf(cls, step) -> { start, end } or undefined), by the same rules
//   stepLevels(actionLevels, origin, endLevel) -> levelsByStep
//       from validateRoute(...).levels (the level at the start of each format 2 action) and bundleSteps' origin
//
// The rules:
//   - a step's work zone is the zone of its accept, turnin, objective, sethearth or grind lines; a step with none
//     (goto, fly, transport, hearth) belongs to the section of the next work step, so a section opens with the way in
//   - a section starts where the work zone changes and the new zone keeps at least MIN_SECTION_WORK work lines
//     before the next change; a shorter run stays in the current section
//   - a section is also cut where the estimated level crosses one of BANDS, and where it reaches MAX_SECTION_STEPS,
//     but only where both parts keep MIN_SECTION_WORK work lines
//   - a grind is inserted before every step whose minLevel is above the estimate at its start, right after the last
//     work step (before the way on), at that step's place; a class step is checked at each of its classes' own level
//     and its grind lifts only those classes, never the shared estimate; no section but the last ends with a grind of more than
//     one level: such a grind opens the next section instead
//   - a step that only accepts quests gets maxLevel, the last level at which every quest still gives XP
//     (lib/xp.js questXp: grey more than 8 levels above the quest), and the later objective and turnin lines of those quests skip when the quest is missing;
//     a later accept of a quest that needs one of them handed in gets ifDone (wanted only once it is), and so on down
//     the chain
//   - an objective or turnin line whose quest no line of its section accepts before it skips when the quest is missing
//     (taken in an earlier section, which a character who joined later may not have done); an accept whose required
//     quest is not accepted earlier in its section gets ifDone (that quest), and its quest's lines skip when missing,
//     down the chain
//   - ifDone names one quest, and `requires` holds both kinds of prerequisite (the quest data's preAll, all of them, and
//     of preAny, any one, those the route hands in), so the gate is worked out at the end from the data: when every
//     any-of member is uncertain, the accept becomes one line per member, each with its own ifDone (any one handed in
//     opens it); the uncertain all-of members get ifDone on the first (when no any-of line took it) and the accept moves
//     to a step of its own, right where it was (the lines before and after it keep their order in steps of their own),
//     with a skip condition "notturnedin" for each other one. Such a step keeps the original's `load` only on its
//     first part, and a reminder step is never split (an error)
const { questXp } = require("../lib/xp");
const { prerequisites } = require("../lib/quests");
const { stepId } = require("./bundle");

const MIN_SECTION_WORK = 12;
const MAX_SECTION_STEPS = 250;
const OUTLEVEL_MARGIN = 3;
const BANDS = Object.freeze([20, 30, 40, 50]);
const MAX_LEVEL = 60;

const WORK = new Set(["accept", "turnin", "objective", "sethearth", "grind"]);
const clone = (o) => JSON.parse(JSON.stringify(o));
const bare = (p) => ({ zone: p.zone, x: p.x, y: p.y });
const workLines = (step) => step.lines.filter((l) => WORK.has(l.kind)).length;
const isWork = (step) => workLines(step) > 0;
function workZone(step) {
  for (const l of step.lines) if (WORK.has(l.kind)) { const p = l.at || step.at; return p ? p.zone : undefined; }
  return undefined;
}
const isGrind = (step) => step.lines.length > 0 && step.lines.every((l) => l.kind === "grind");

// Does a condition let this class through? Only the class keys are read: sections are per race already.
function applies(when, cls) {
  if (!when) return true;
  const list = (v) => (Array.isArray(v) ? v : [v]);
  if (when.class !== undefined && !list(when.class).includes(cls)) return false;
  if (when.notClass !== undefined && list(when.notClass).includes(cls)) return false;
  return true;
}

function stepLevels(actionLevels, origin, endLevel) {
  return origin.map((list, i) => ({ start: actionLevels[list[0]], end: i + 1 < origin.length ? actionLevels[origin[i + 1][0]] : endLevel }));
}

// The grind insertion, with the levels of the new list: shared ({ start, end }) and per class.
// The shared estimate and each class's own level are lifted apart: a grind before a step that applies to every
// character lifts them all; a grind before a class step lifts only the classes it is for, each checked at its own
// level (classLevels), or at the shared estimate when no class levels are given.
const hasClassKey = (when) => !!when && (when.class !== undefined || when.notClass !== undefined);
function grindsWithLevels(steps, levels, classLevels, usedIds) {
  if (levels.length !== steps.length) throw new Error(`${steps.length} steps and ${levels.length} levels`);
  const used = usedIds || new Set(steps.map((s) => s.id));
  const known = Object.keys(classLevels).sort();
  const out = [], lv = [], cl = {};
  for (const cls of known) cl[cls] = [];
  let lastWork = -1;        // index in out of the last work step
  let floor = 0;            // no shared estimate after a grind to L is below L
  const classFloor = {};    // the same for each class's own level
  const whenFloor = {};     // the same for a class condition no class levels are given for
  for (const cls of known) classFloor[cls] = 0;
  const own = (cls, i) => classLevels[cls][i] || levels[i];
  const lift = (e, f) => ({ start: Math.max(e.start, f), end: Math.max(e.end, f) });
  steps.forEach((step, i) => {
    const need = step.minLevel;
    const start = Math.max(levels[i].start, floor);
    let when, lifts;  // the grind's condition, and whom it lifts: "all", a list of classes, or a when key
    if (need !== undefined && !hasClassKey(step.when)) {
      if (Math.floor(start) < need) { lifts = "all"; if (step.when) when = clone(step.when); }
    } else if (need !== undefined) {
      const targets = known.filter((cls) => applies(step.when, cls));
      if (targets.length) {
        const needy = targets.filter((cls) => Math.floor(Math.max(own(cls, i).start, classFloor[cls])) < need);
        if (needy.length) {
          lifts = needy;
          when = clone(step.when);
          if (needy.length < targets.length) { delete when.notClass; when.class = needy.length === 1 ? needy[0] : needy; }
        }
      } else {
        const key = JSON.stringify(step.when);
        if (Math.floor(Math.max(start, whenFloor[key] || 0)) < need) { lifts = key; when = clone(step.when); }
      }
    }
    const prev = out[out.length - 1];
    const covered = lifts !== undefined && prev && isGrind(prev) && prev.lines.every((l) => l.level >= need) &&
      (!hasClassKey(prev.when) || JSON.stringify(prev.when) === JSON.stringify(when));
    if (lifts !== undefined && !covered) {
      const from = lastWork >= 0 ? out[lastWork] : step;
      const place = from.at || (from.lines[0] && from.lines[0].at);
      let id = `l${need}` + (place ? `@${place.zone}` : "");
      for (let n = 2; used.has(id); n++) id = `l${need}` + (place ? `@${place.zone}` : "") + `#${n}`;
      used.add(id);
      const grind = { id };
      if (place) grind.at = bare(place);
      grind.lines = [{ kind: "grind", level: need }];
      if (when) grind.when = when;
      const at = lastWork + 1;
      const lifted = lifts === "all" ? known : Array.isArray(lifts) ? lifts : [];
      out.splice(at, 0, grind);
      lv.splice(at, 0, { start, end: lifts === "all" ? Math.max(start, need) : start });
      for (const cls of known) {
        const s = Math.max(own(cls, i).start, classFloor[cls]);
        cl[cls].splice(at, 0, { start: s, end: lifted.includes(cls) ? Math.max(s, need) : s });
      }
      if (lifts === "all") {
        floor = Math.max(floor, need);
        for (const key of Object.keys(whenFloor)) whenFloor[key] = Math.max(whenFloor[key], need);
      } else if (!Array.isArray(lifts)) whenFloor[lifts] = Math.max(whenFloor[lifts] || 0, need);
      for (const cls of lifted) classFloor[cls] = Math.max(classFloor[cls], need);
      // the way on after the grind is walked at the new level
      for (let k = at + 1; k < out.length; k++) {
        lv[k] = lift(lv[k], floor);
        for (const cls of lifted) cl[cls][k] = lift(cl[cls][k], classFloor[cls]);
      }
      lastWork = at;
    }
    out.push(step);
    lv.push(lift(levels[i], floor));
    for (const cls of known) cl[cls].push(lift(own(cls, i), classFloor[cls]));
    if (isWork(step)) lastWork = out.length - 1;
  });
  return { steps: out, levels: lv, classLevels: cl };
}

// Grinds again in finished sections, after steps were added that change the estimate (class trainer trips): before
// every step whose minLevel the new estimate does not reach, by the same rules as above. levelOf(cls, step) ->
// { start, end } or undefined (the class does not play the step); the shared estimate is the lowest of the classes.
function regrindSections(sections, classes, levelOf) {
  const used = new Set(sections.flatMap((s) => s.steps.map((x) => x.id)));
  return sections.map((section) => {
    const steps = section.steps;
    const own = {};
    for (const cls of classes) own[cls] = steps.map((s) => levelOf(cls, s));
    const shared = steps.map((_, i) => {
      let start = Infinity, end = Infinity;
      for (const cls of classes) { const l = own[cls][i]; if (l) { start = Math.min(start, l.start); end = Math.min(end, l.end); } }
      return start === Infinity ? { start: MAX_LEVEL, end: MAX_LEVEL } : { start, end };
    });
    const classLevels = {};
    for (const cls of classes) classLevels[cls] = own[cls].map((l, i) => l || shared[i]);
    return { ...section, steps: grindsWithLevels(steps.map(clone), shared, classLevels, used).steps };
  });
}

function insertGrinds(steps, levelsByStep, classLevels = {}) {
  return grindsWithLevels(steps.map(clone), levelsByStep, classLevels || {}).steps;
}

// The last level at which a quest of this level gives XP: questXp is nothing once the player is too far above it.
function lastXpLevel(questLevel) {
  let level = Math.max(1, questLevel);
  while (level < MAX_LEVEL && questXp(questLevel, level + 1) > 0) level++;
  return Math.min(level, MAX_LEVEL);
}

// levels: the shared estimate per step, to report quests taken when already grey; notes: where to write what the
// data cannot settle (a list of sentences, for docs/routes/DATA-NOTES.md and the build report)
function capAccepts(db, steps, levels, notes, race) {
  steps.forEach((step, i) => {
    if (!step.lines.length || !step.lines.every((l) => l.kind === "accept")) return;
    let cap = MAX_LEVEL, lowest;
    for (const l of step.lines) {
      const q = db.quests.get(l.quest);
      if (!q || !(Number.isInteger(q.level) && q.level >= 1 && q.level <= MAX_LEVEL)) return; // a level the data does not give: no cap
      const last = lastXpLevel(q.level);
      if (lowest === undefined || last < cap) { cap = last; lowest = l.quest; }
    }
    if (cap < (step.minLevel || 1)) {
      notes.push(`${race} step ${step.id}: quest ${lowest} gives XP only up to level ${cap}, below the step's minLevel ${step.minLevel}; the step gets no maxLevel`);
      return;
    }
    const at = levels && levels[i] ? Math.floor(levels[i].start) : undefined;
    if (at !== undefined && cap < at) {
      notes.push(`${race} step ${step.id}: quest ${lowest} gives XP only up to level ${cap}, but the estimated level there is ${at}; with "skip content you outlevel" the step and its quest's later lines are skipped`);
    }
    step.maxLevel = cap;
    // the capped quests and, down their chains, the later quests that need one of them handed in (accepted only
    // once it is: ifDone), whose own objective and turnin lines skip when the quest is missing
    const quests = new Set(step.lines.map((l) => l.quest));
    for (const later of steps.slice(i + 1)) {
      for (const l of later.lines) {
        if ((l.kind === "objective" || l.kind === "turnin") && quests.has(l.quest)) l.skipIfMissing = true;
        if (l.kind === "accept" && !quests.has(l.quest) && Array.isArray(l.requires)) {
          const needs = l.requires.filter((q) => quests.has(q));
          if (needs.length) {
            gate(l, needs);
            quests.add(l.quest);
          }
        }
      }
    }
  });
}

// Cuts [a, b) of the step list into segments.
function segmentsOf(steps, levels) {
  const work = steps.map(workLines);
  const sum = (a, b) => { let n = 0; for (let k = a; k < b; k++) n += work[k]; return n; };
  // the index after the last work step before k (where a section opening at work step k starts)
  const opening = (k, lo) => { let c = k; while (c > lo && !work[c - 1]) c--; return c; };

  // by zone
  const cuts = [0];
  const runs = [];
  steps.forEach((s, k) => {
    if (!work[k]) return;
    const zone = workZone(s);
    const run = runs[runs.length - 1];
    if (run && run.zone === zone) run.work += work[k]; else runs.push({ zone, first: k, work: work[k] });
  });
  let current = runs.length ? runs[0].zone : undefined;
  for (const run of runs.slice(1)) {
    if (run.zone === current || run.work < MIN_SECTION_WORK) continue;
    cuts.push(opening(run.first, cuts[cuts.length - 1]));
    current = run.zone;
  }
  let segments = cuts.map((a, i) => [a, i + 1 < cuts.length ? cuts[i + 1] : steps.length]);

  // by level band
  const byBand = ([a, b]) => {
    const low = Math.floor(levels[a].start);
    for (const band of BANDS) {
      if (low >= band) continue;
      const k = steps.findIndex((s, j) => j >= a && j < b && work[j] && Math.floor(levels[j].start) >= band);
      if (k < 0) continue;
      const c = opening(k, a);
      if (c > a && sum(a, c) >= MIN_SECTION_WORK && sum(c, b) >= MIN_SECTION_WORK) return [...byBand([a, c]), ...byBand([c, b])];
    }
    return [[a, b]];
  };
  segments = segments.flatMap(byBand);

  // a grind of more than one level at the end of a section opens the next one (before the cut by length, which
  // never cuts after such a grind, so no section grows past MAX_SECTION_STEPS once it is cut)
  const bigGrind = (k) => isGrind(steps[k]) && Math.max(...steps[k].lines.map((l) => l.level)) - Math.floor(levels[k].start) > 1;
  for (let i = 0; i + 1 < segments.length; i++) {
    const seg = segments[i];
    while (seg[1] - seg[0] > 1 && bigGrind(seg[1] - 1)) {
      seg[1] -= 1;
      segments[i + 1][0] -= 1;
    }
  }

  // by length
  const byLength = ([a, b]) => {
    if (b - a <= MAX_SECTION_STEPS) return [[a, b]];
    for (let c = a + MAX_SECTION_STEPS; c > a; c--) {
      if (work[c - 1] && !bigGrind(c - 1) && sum(a, c) >= MIN_SECTION_WORK && sum(c, b) >= MIN_SECTION_WORK) return [[a, c], ...byLength([c, b])];
    }
    return [[a, b]];
  };
  return segments.flatMap(byLength);
}

const pad = (n) => String(n).padStart(2, "0");
const slug = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
const rangeName = (min, end, zoneName) => (end > min ? `${min}-${end} ${zoneName}` : `${min} ${zoneName}`);
const subgroupOf = (min) => (min < 20 ? "1-20" : `${Math.floor(min / 10) * 10}-${Math.floor(min / 10) * 10 + 10}`);

function splitSections(db, race, faction, bundled, levelsByStep, classLevels = {}, notes = []) {
  const given = Array.isArray(bundled) ? bundled : bundled.steps;
  const copied = given.map(clone);
  capAccepts(db, copied, levelsByStep, notes, race);
  const { steps, levels, classLevels: cl } = grindsWithLevels(copied, levelsByStep, classLevels || {});
  const segments = segmentsOf(steps, levels);

  const zoneName = (zone) => {
    const a = db.areas.get(zone);
    if (a && a.name) return a.name;
    notes.push(`${race}: zone ${zone} has no name in the area table; its section is named "Zone ${zone}"`);
    return `Zone ${zone}`;
  };
  const usedIds = new Map();
  const sections = segments.map(([a, b]) => {
    const list = steps.slice(a, b);
    // the main zone: the one with the most work lines, the first of equals
    const work = new Map();
    list.forEach((s) => { const z = workZone(s); if (z !== undefined) work.set(z, (work.get(z) || 0) + workLines(s)); });
    let zone, most = -1;
    for (const [z, n] of work) if (n > most) { zone = z; most = n; }
    if (zone === undefined) zone = (list.find((s) => s.at) || { at: { zone: 0 } }).at.zone;
    const name = zoneName(zone);
    const min = Math.max(1, Math.floor(levels[a].start));
    const end = Math.min(MAX_LEVEL, Math.max(min, Math.floor(levels[b - 1].end)));
    let id = `${race.toLowerCase()}-${pad(min)}-${pad(end)}-${slug(name) || `zone-${zone}`}`;
    const n = (usedIds.get(id) || 0) + 1;
    usedIds.set(id, n);
    if (n > 1) id += `-${n}`;
    const section = { id, name: rangeName(min, end, name) };
    // a class's own range over the steps it plays here
    const names = {};
    for (const cls of Object.keys(cl).sort()) {
      const mine = [];
      for (let k = a; k < b; k++) if (applies(steps[k].when, cls)) mine.push(k);
      if (!mine.length) continue;
      const cmin = Math.max(1, Math.floor(cl[cls][mine[0]].start));
      const cend = Math.min(MAX_LEVEL, Math.max(cmin, Math.floor(cl[cls][mine[mine.length - 1]].end)));
      const own = rangeName(cmin, cend, name);
      if (own !== section.name) names[cls] = own;
    }
    if (Object.keys(names).length) section.names = names;
    Object.assign(section, { group: faction, subgroup: subgroupOf(min), minLevel: min, maxLevel: Math.min(MAX_LEVEL, end + OUTLEVEL_MARGIN), zone });
    section.next = [];
    section.steps = list;
    return section;
  });
  if (sections.length) sections[0].start = true;
  sections.forEach((s, i) => { if (i + 1 < sections.length) s.next = [{ section: sections[i + 1].id }]; });
  // a quest no line of the section accepts before its objective or turnin line was taken in an earlier section: a
  // character who joined later may not have it, and no detour of this section can bring it back. An accept that needs
  // such a quest (or one handed in in an earlier section) handed in is wanted only once it is (ifDone), and the
  // accepted quest's own lines skip when it is missing, and so on down the chain
  for (const section of sections) {
    const accepted = new Set(), maybe = new Set();
    for (const step of section.steps) {
      for (const l of step.lines) {
        if (l.kind === "accept") {
          const needs = Array.isArray(l.requires) ? l.requires.filter((q) => !accepted.has(q) || maybe.has(q)) : [];
          if (needs.length) {
            gate(l, needs);
            maybe.add(l.quest);
          }
          accepted.add(l.quest);
        } else if ((l.kind === "objective" || l.kind === "turnin") && (!accepted.has(l.quest) || maybe.has(l.quest))) l.skipIfMissing = true;
      }
    }
  }
  for (const section of sections) section.steps = isolateGated(db, section.steps);
  return sections;
}

// An accept wanted only once the quests `needs` (of its `requires`) are handed in, which a character may not have done:
// kept in the working field _need, which isolateGated turns into ifDone lines and skip conditions.
function gate(line, needs) {
  line._need = [...new Set([...(line._need || []), ...needs])];
}

// The lines an accept with _need becomes, and the quests that gate it as a step of its own (see the header).
function gateLines(db, line) {
  const need = line._need;
  delete line._need;
  const q = db.quests.get(line.quest);
  const pre = q ? prerequisites(q) : { all: [], any: [] };
  const requires = Array.isArray(line.requires) ? line.requires : [];
  const anyOf = requires.filter((p) => pre.any.includes(p) && !pre.all.includes(p));
  // the group is uncertain only when every member the route hands in is: one certain member opens it
  const anyNeed = anyOf.length && anyOf.every((p) => need.includes(p)) ? anyOf : [];
  const allNeed = need.filter((p) => !anyOf.includes(p));
  if (line.ifDone !== undefined) return { lines: [line], gates: need.filter((p) => p !== line.ifDone) };
  if (anyNeed.length) return { lines: anyNeed.map((m) => ({ ...clone(line), ifDone: m })), gates: allNeed };
  if (allNeed.length) return { lines: [{ ...line, ifDone: allNeed[0] }], gates: allNeed.slice(1) };
  return { lines: [line], gates: [] };
}

// Each accept line with _need becomes its gate lines; one gated by further quests moves to a step of its own at its
// place in the list, with a "notturnedin" skip condition per such quest; the lines before and after it stay together,
// in order, in steps of their own. Ids are made again from the lines (bundle's stepId), unique in the section; minLevel
// from each part's accepts; `load` stays on the first part only; a reminder step is never split.
function isolateGated(db, steps) {
  const used = new Set(steps.map((s) => s.id));
  const out = [];
  for (const step of steps) {
    if (!step.lines.some((l) => l._need)) { out.push(step); continue; }
    const parts = [];
    let run = [];
    for (const l of step.lines) {
      if (!l._need) { run.push(l); continue; }
      const { lines, gates } = gateLines(db, l);
      if (!gates.length) { run.push(...lines); continue; }
      if (run.length) parts.push({ lines: run });
      run = [];
      parts.push({ lines, skip: gates.map((quest) => ({ kind: "notturnedin", quest })) });
    }
    if (run.length) parts.push({ lines: run });
    if (parts.length === 1 && !parts[0].skip) { step.lines = parts[0].lines; out.push(step); continue; }
    if (step.reminder) throw new Error(`step ${step.id}: a reminder step would be split for its gated accept; it would remind once per part`);
    used.delete(step.id);
    parts.forEach((p, n) => {
      const { id: _id, lines: _lines, minLevel: _min, skip, label, load, ...rest } = step;
      const part = { ...clone(rest), lines: p.lines };
      if (label !== undefined && n === 0) part.label = label;
      if (load !== undefined && n === 0) part.load = load;
      const conditions = [...(skip ? clone(skip) : []), ...(p.skip || [])];
      if (conditions.length) part.skip = conditions;
      let min = 1;
      for (const l of p.lines) if (l.kind === "accept") { const q = db.quests.get(l.quest); min = Math.max(min, (q && q.minLevel) || 1); }
      if (min > 1) part.minLevel = min;
      const base = stepId(part);
      let id = base;
      for (let k = 2; used.has(id); k++) id = `${base}#${k}`;
      used.add(id);
      out.push({ id, ...part });
    });
  }
  return out;
}

module.exports = { splitSections, insertGrinds, regrindSections, stepLevels, lastXpLevel, MIN_SECTION_WORK, MAX_SECTION_STEPS, OUTLEVEL_MARGIN, BANDS };
