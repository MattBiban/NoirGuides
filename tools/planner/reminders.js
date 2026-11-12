// Noir Guides, GPLv3. See LICENSE.
// Reminder steps: an objective the player finishes while doing the next few steps around one hub stays on screen as
// a reminder until its quest is handed in (task P3 in docs/superpowers/plans/2026-11-11-guide-rebuild.md, spec 3.6).
//
//   addReminders(db, section) -> section (a new section; the one given is not changed)
//
// The rule: a kill or item objective line (one that names an npc or an item) whose quest is handed in at least two
// steps later in the same section, and whose place (the line's own, else its step's) lies within REMINDER_YARDS of
// the place of every step in between, moves out of its step into a new step
//   { id = "r<quest>", at = <its place>, lines = { the line(s) }, targets = <its enemies>, reminder = { ends = "turnin<quest>" } }
// put where it was (before what is left of its step when the moved lines came first, else after it). The turn-in
// step gets label "turnin<quest>", or keeps the label it already has, which the reminder then ends at. Objective lines
// of one quest in one step move together. A step left without lines is removed.
// Not moved: a step in between without a place (a hearth) or in another zone than can be measured, and a turn-in
// step that applies to fewer characters than the objective's step (its label would be missing for some of them).
// The enemy targets that belong to the moved lines (their creature, the droppers of their item) go along, and so do
// the step's item buttons that belong to their quest (its usable source items, spec 4.6); the step left behind keeps
// the items its remaining lines' quests still use, and any item no quest on the step claims.
const { toPoint, distance } = require("../lib/geo");
const { sourceItems, starterItems } = require("../lib/quests");

const REMINDER_YARDS = 200;

const clone = (o) => JSON.parse(JSON.stringify(o));
const zoneOnly = (p) => p.x === 0 && p.y === 0;
const placeOf = (step) => step.at || (step.lines.find((l) => l.at) || {}).at;
const same = (a, b) => JSON.stringify(a || null) === JSON.stringify(b || null);

function addReminders(db, section) {
  const out = clone(section);
  const steps = out.steps;
  const point = (p) => (p && !zoneOnly(p) ? toPoint(db, p.zone, p.x, p.y) : null);
  const near = (a, b) => { const pa = point(a), pb = point(b); return !!pa && !!pb && distance(pa, pb) <= REMINDER_YARDS; };
  const turnin = (quest, from) => steps.findIndex((s, k) => k > from && s.lines.some((l) => l.kind === "turnin" && l.quest === quest));

  // what moves where, decided on the section as given
  const moves = new Map(); // step index -> [{ quest, place, lines: [line index], end }]
  steps.forEach((step, i) => {
    const byQuest = new Map();
    step.lines.forEach((l, j) => {
      if (l.kind !== "objective" || (l.npc === undefined && l.item === undefined)) return;
      const place = l.at || step.at;
      const end = turnin(l.quest, i);
      if (!place || end < 0 || end - i < 2) return;
      if (steps[end].when && !same(steps[end].when, step.when)) return;
      for (let k = i + 1; k < end; k++) if (!near(placeOf(steps[k]), place)) return;
      if (!byQuest.has(l.quest)) byQuest.set(l.quest, { quest: l.quest, place, lines: [], end });
      byQuest.get(l.quest).lines.push(j);
    });
    if (byQuest.size) moves.set(i, [...byQuest.values()]);
  });
  if (!moves.size) return out;

  const used = new Set(steps.map((s) => s.id));
  const uniqueId = (base) => { let id = base; for (let n = 2; used.has(id); n++) id = `${base}#${n}`; used.add(id); return id; };
  const labelOf = (k, quest) => { if (!steps[k].label) steps[k].label = `turnin${quest}`; return steps[k].label; };
  const result = [];
  steps.forEach((step, i) => {
    const list = moves.get(i);
    if (!list) { result.push(step); return; }
    const movedIdx = new Set(list.flatMap((m) => m.lines));
    const enemies = (step.targets && step.targets.enemy) || [];
    const taken = new Set();
    const stepItems = step.items || [];
    const usedBy = (quest, accept) => {
      const q = db.quests && db.quests.get(quest);
      return q ? [...sourceItems(q), ...(accept ? starterItems(q) : [])] : [];
    };
    const reminders = list.map((m) => {
      const lines = m.lines.map((j) => { const l = clone(step.lines[j]); delete l.at; return l; });
      const mine = new Set();
      for (const l of lines) {
        if (l.npc !== undefined) mine.add(l.npc);
        if (l.item !== undefined) for (const npc of ((db.items.get(l.item) || {}).npcDrops || [])) mine.add(npc);
      }
      const r = { id: uniqueId(`r${m.quest}`), at: clone(m.place), lines };
      const enemy = enemies.filter((id) => mine.has(id) && !taken.has(id));
      enemy.forEach((id) => taken.add(id));
      if (enemy.length) r.targets = { enemy };
      const own = new Set(usedBy(m.quest, false));
      const items = stepItems.filter((id) => own.has(id));
      if (items.length) r.items = items;
      r.reminder = { ends: labelOf(m.end, m.quest) };
      if (step.when) r.when = clone(step.when);
      return r;
    });
    const rest = step.lines.filter((_, j) => !movedIdx.has(j));
    if (!rest.length) { result.push(...reminders); return; }
    const lastMoved = Math.max(...movedIdx);
    const keptFirst = step.lines.findIndex((_, j) => !movedIdx.has(j));
    step.lines = rest;
    if (stepItems.length) {
      const movedQuests = new Set(list.map((m) => m.quest));
      const claimed = new Set([...movedQuests].flatMap((q) => usedBy(q, false)));
      const kept = new Set(rest.filter((l) => l.quest !== undefined).flatMap((l) => usedBy(l.quest, l.kind === "accept")));
      const items = stepItems.filter((id) => kept.has(id) || !claimed.has(id));
      if (items.length) step.items = items; else delete step.items;
    }
    if (step.targets) {
      const enemy = enemies.filter((id) => !taken.has(id));
      if (enemy.length) step.targets.enemy = enemy; else delete step.targets.enemy;
      if (!step.targets.enemy && !step.targets.friend) delete step.targets;
    }
    if (lastMoved < keptFirst) result.push(...reminders, step);
    else result.push(step, ...reminders);
  });
  out.steps = result;
  return out;
}

module.exports = { addReminders, REMINDER_YARDS };
