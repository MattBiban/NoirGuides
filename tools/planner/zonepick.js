// Noir Guides, GPLv3. See LICENSE.
// Which zone comes next. A change of zone is the expensive thing in a route, so the choice looks many visits ahead:
// it plays out whole visits on a copy of the character (simVisit) and takes the first zone of the sequence of visits
// that earns the most XP. A zone that will offer three times as much two levels later is then left for later, and
// a zone with a single quest is not worth one of the visits.
//   view: { ctx, policy, st, secondsAt(from, to, level) } from planner/plan.js
const { distance } = require("../lib/geo");
const { PACE, XP_TO_LEVEL, gain, questXp, objectiveXp, objectiveSeconds, grindSeconds } = require("../lib/xp");
const { CHOICES: C } = require("./tuning");

const GRIND = -1; // in a sequence of zones: a level of grinding where the character stands

// A set seen through the quests a copy of the character has turned in since: the real set is never copied.
class Overlay {
  constructor(base, added) { this.base = base; this.added = new Set(added); }
  has(x) { return this.added.has(x) || this.base.has(x); }
  add(x) { this.added.add(x); return this; }
  get size() { return this.base.size + this.added.size; }
}
// A copy of the character for playing visits out: level, XP, done quests and the log.
function copyOf(S) {
  const log = new Map();
  for (const [quest, entry] of S.log) log.set(quest, { needsObjective: entry.needsObjective });
  const done = S.done instanceof Overlay ? new Overlay(S.done.base, S.done.added) : new Overlay(S.done, []);
  return { level: S.level, xp: S.xp, done, log, hopped: null, relaxed: S.relaxed };
}

// One whole visit to a zone, played on S (which it changes): the log's objectives and turn-ins there, every quest
// the zone offers under the policy, and what those open, with the levels gained on the way counted in. It is the
// session of planner/plan.js without the walking; the fights on the way are a flat PLAN_WALK_SHARE on top.
// Returns { xp, seconds, count }: XP gained (none once the character is at the cap), time on the spot, tasks done.
function simVisit(view, S, zone, cap = 60) {
  const { ctx, policy } = view;
  const out = { xp: 0, seconds: 0, count: 0 };
  const band = ctx.bands.get(zone);
  const walk = band && band.wild ? 1 + C.PLAN_WALK_SHARE : 1;
  const earn = (xp) => {
    if (S.level >= cap) return;
    const got = Math.round(xp * walk);
    out.xp += got;
    gain(S, got);
  };
  for (let changed = true; changed;) {
    changed = false;
    for (const [quest, entry] of S.log) {
      const i = ctx.info.get(quest);
      if (entry.needsObjective && policy.objectiveIn(i, zone)) {
        earn(objectiveXp(i.q, S.level));
        entry.needsObjective = false;
        out.seconds += objectiveSeconds(i.q) + C.QUEST_WALK_SECONDS; out.count++;
        changed = true;
      }
      if (!entry.needsObjective && i.endZone === zone) {
        earn(questXp(i.q.level, S.level));
        S.log.delete(quest);
        S.done.add(quest);
        out.seconds += PACE.TALK_SECONDS; out.count++;
        changed = true;
      }
    }
    for (const i of ctx.byZone.get(zone) || []) {
      if (S.log.size >= C.LOG_LIMIT) break;
      if (!policy.wanted(i, S)) continue;
      S.log.set(i.q.id, { needsObjective: !!i.obj });
      out.seconds += PACE.TALK_SECONDS; out.count++;
      changed = true;
    }
  }
  return out;
}

// The place of the next thing a log quest needs.
const nextPlace = (i, entry) => (entry.needsObjective ? i.obj.point : i.end.point);

// Where a zone is entered, for costing the way there: the log's nearest task in it, else the zone's main hub.
function entryOf(view, S, zone, from) {
  const { ctx, policy } = view;
  let best = null, bestYards = Infinity;
  for (const [quest, entry] of S.log) {
    const i = ctx.info.get(quest);
    const p = entry.needsObjective ? (policy.objectiveIn(i, zone) ? i.obj.point : null) : i.endZone === zone ? i.end.point : null;
    if (!p) continue;
    const yards = from.continent === p.continent ? distance(from, p) : Infinity;
    if (!best || yards < bestYards) { best = p; bestYards = yards; }
  }
  return best || ctx.hubs.get(zone) || null;
}

// The zones worth trying from a state: the ones the log has a task in, and the ones with the most quests to offer
// at the level (a cheap count; simVisit decides what they are really worth). all: every zone with a quest to offer.
function candidates(view, S, all) {
  const { ctx, policy } = view;
  const zones = new Set();
  for (const [quest, entry] of S.log) zones.add(nextPlace(ctx.info.get(quest), entry).zone);
  const counted = [];
  for (const [zone, list] of ctx.byZone) {
    let n = 0;
    for (const i of list) if (i.q.minLevel <= S.level && !S.done.has(i.q.id) && !S.log.has(i.q.id) && policy.worth(i, S.level)) n++;
    if (n) counted.push([zone, n]);
  }
  counted.sort((a, b) => b[1] - a[1] || a[0] - b[0]);
  for (const [zone] of all ? counted : counted.slice(0, C.SEARCH_ZONES)) zones.add(zone);
  return [...zones].sort((a, b) => a - b);
}

// The zone of the nearest task among the log's quests that pass the filter; 0 when there is none within reach.
function nearestTask(view, wanted, skipped) {
  const { ctx, st } = view;
  let best = 0, bestTravel = Infinity;
  for (const [quest, entry] of st.log) {
    if (!wanted(quest)) continue;
    const next = nextPlace(ctx.info.get(quest), entry);
    if (skipped(next.zone)) continue;
    const travel = view.secondsAt(st.pos, next, st.level);
    if (travel < bestTravel || (travel === bestTravel && travel < Infinity && next.zone < best)) { best = next.zone; bestTravel = travel; }
  }
  return best;
}

// The zone of the nearest next place of a quest a transport asks for or of an arrival quest (ctx.linkQuests), other
// than the zone the route is in and the zones found spent; 0 when no such quest is in the log.
function urgentZone(view) {
  const { st } = view;
  return nearestTask(view, (quest) => view.ctx.linkQuests.has(quest), (zone) => zone === st.zone || st.barren.has(zone));
}

// What comes next: { zone } (0 when no zone is worth going to), or { zone: 0, grind: true } when the look-ahead
// plans a level of grinding first.
//   options.wrapUp      no new quests are taken: only the log counts, and the nearest task wins
//   options.cap         the level the route ends at (60)
//   options.ground      the last step was a grind step: the look-ahead must not start with another
//   options.here        the zone the route is in may be the first visit (the plan at the start of the route)
//   options.level       look only one visit ahead, as if the player had this level and stood anywhere: is there
//                       a zone with anything to do? (What one more level would open.)
// Otherwise:
//   1. a quest a transport asks for, or one of the arrival quests, goes straight to its next place: the zone of the
//      nearest such task wins, as { zone, urgent: true }. (The way off Zephras Isle ends beside the quest's turn-in;
//      nothing should come between: planner/plan.js does nothing else in that zone until it is handed in.)
//   2. sequences of up to SEARCH_DEPTH visits are played out, the SEARCH_BEAM best kept after each visit. After the
//      same number of visits the sequence with more XP is the better one (less SEARCH_TIME_XP for every second of
//      travel and work), so the search spends its visits where they give most: the fewest zone changes to the cap.
//      A sequence that reaches the cap ends the search; of several, the quickest wins. The first zone of the best
//      sequence is the answer. Equal sequences: the one whose zones have the lower IDs.
function bestZone(view, options = {}) {
  const { st } = view;
  const peek = options.level !== undefined;
  const skipped = (zone) => !peek && ((zone === st.zone && !options.here) || st.barren.has(zone));
  if (options.wrapUp) return { zone: nearestTask(view, () => true, skipped) };
  const urgent = peek ? 0 : urgentZone(view);
  if (urgent) return { zone: urgent, urgent: true };

  const cap = options.cap || 60;
  const start = copyOf(st);
  if (peek) { start.level = options.level; start.xp = 0; }
  let beam = [{ S: start, pos: st.pos, zone: st.zone, xp: 0, time: 0, path: [], score: 0, grinds: st.grinds, ground: !!options.ground }];
  let best = null;
  const order = (a, b) => (a.score !== b.score ? b.score - a.score : a.path.join(",") < b.path.join(",") ? -1 : 1);
  for (let depth = 1; depth <= (peek ? 1 : C.SEARCH_DEPTH); depth++) {
    const next = [], seen = new Set();
    for (const node of beam) {
      if (node.S.level >= cap) continue;
      // one level of nothing but fights: MAX_GRINDS times in a route, never twice in a row
      if (!peek && node.grinds < C.MAX_GRINDS && !node.ground) {
        const S = copyOf(node.S);
        const made = { S, pos: node.pos, zone: node.zone, xp: node.xp + XP_TO_LEVEL[S.level] - S.xp, time: node.time + grindSeconds(S.level, S.xp),
          path: [...node.path, GRIND], grinds: node.grinds + 1, ground: true };
        S.level++; S.xp = 0;
        made.score = made.xp - C.SEARCH_TIME_XP * made.time;
        next.push(made);
      }
      for (const zone of candidates(view, node.S, depth === 1)) {
        if (depth === 1 ? skipped(zone) : zone === node.zone) continue;
        const entry = entryOf(view, node.S, zone, node.pos);
        if (!entry) continue;
        const travel = peek ? 0 : view.secondsAt(node.pos, entry, node.S.level);
        if (travel === Infinity) continue;
        const S = copyOf(node.S);
        const visit = simVisit(view, S, zone, cap);
        if (visit.xp <= 0 && !(peek && visit.count > 0)) continue; // a quest to pick up counts when asking what a level opens
        const key = `${zone}:${S.level}:${S.xp}:${S.log.size}`;
        if (seen.has(key)) continue; // the same visits in another order
        seen.add(key);
        const made = { S, pos: entry, zone, xp: node.xp + visit.xp, time: node.time + travel + visit.seconds, path: [...node.path, zone], grinds: node.grinds, ground: false };
        made.score = made.xp - C.SEARCH_TIME_XP * made.time;
        next.push(made);
      }
    }
    if (!next.length) break;
    next.sort(order);
    beam = next.slice(0, C.SEARCH_BEAM);
    best = beam[0];
    const finished = beam.filter((n) => n.S.level >= cap);
    if (finished.length) { best = finished.sort((a, b) => a.time - b.time || order(a, b))[0]; break; }
  }
  if (!best) return { zone: 0 };
  return best.path[0] === GRIND ? { zone: 0, grind: true, path: best.path } : { zone: best.path[0], path: best.path };
}

module.exports = { Overlay, copyOf, simVisit, bestZone, urgentZone };
