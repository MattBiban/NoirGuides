// Noir Guides, GPLv3. See LICENSE.
// The last look before a grind step. The look-ahead (planner/zonepick.js) picks a zone by the XP a visit earns, so
// a zone where quests are only picked up (a delivery that is handed in elsewhere, the first quest of a chain) or
// where the log only has a place to find earns nothing in its eyes and is never chosen. When the look-ahead finds
// no zone at all, such a visit can still beat a level of grinding: it puts quests in the log, or moves them on,
// and the look-ahead then leads to their ends.
//   view: { ctx, policy, st, secondsAt(from, to, level) } from planner/plan.js
const { PACE, XP_TO_LEVEL } = require("../lib/xp");
const { CHOICES: C } = require("./tuning");
const { copyOf, simVisit } = require("./zonepick");

// What a visit to a zone leads to, played on a copy of the character: the visit itself, then, SUPPLY_VISITS times
// at most, a visit to every zone the quests it took or moved on send the player to next (the lower zone ID first).
// Returns { xp, visits }: the XP of it all and the visits it took; no visits when the first one does nothing.
function errand(view, zone) {
  const { ctx, st } = view;
  const S = copyOf(st);
  S.errands = st.errands; // the copy takes what the character would take now (planner/policy.js)
  const out = { xp: 0, visits: 0 };
  let zones = [zone];
  for (let round = 0; round <= C.SUPPLY_VISITS && zones.length; round++) {
    for (const z of zones) {
      const visit = simVisit(view, S, z);
      if (!round && !visit.count) return out;
      out.xp += visit.xp;
      out.visits++;
    }
    const next = new Set();
    for (const [quest, entry] of S.log) {
      const before = st.log.get(quest);
      if (before && before.needsObjective === entry.needsObjective) continue; // as it was: not this errand's
      const i = ctx.info.get(quest);
      next.add((entry.needsObjective ? i.obj.point : i.end.point).zone);
    }
    zones = [...next].sort((a, b) => a - b);
  }
  return out;
}

// The zone to go to though the visit itself earns nothing: the one whose errand gives the most XP a visit. An
// errand is worth its changes of zone when a visit of it gives SUPPLY_MIN_SHARE of the level, or when the whole of
// it reaches the next level, so that no grind step is written at all (XP as the planner counts it, PACE.YIELD).
// Below that the grind step is the shorter way. Not a zone found spent; only zones a way leads to. 0 when there
// is none. Equal zones: the lower ID.
function supplyZone(view) {
  const { ctx, policy, st } = view;
  const zones = new Set();
  for (const [zone, list] of ctx.byZone) if (list.some((i) => policy.wanted(i, st))) zones.add(zone);
  for (const [quest, entry] of st.log) zones.add((entry.needsObjective ? ctx.info.get(quest).obj.point : ctx.info.get(quest).end.point).zone);
  const need = XP_TO_LEVEL[st.level];
  let best = 0, bestXp = 0;
  for (const zone of [...zones].sort((a, b) => a - b)) {
    if (st.barren.has(zone)) continue;
    const { xp, visits } = errand(view, zone);
    if (!visits || xp / visits <= bestXp) continue;
    if ((xp / visits) * PACE.YIELD < C.SUPPLY_MIN_SHARE * need && st.xp + xp * PACE.YIELD < need) continue;
    const hub = ctx.hubs.get(zone);
    if (!hub || view.secondsAt(st.pos, hub, st.level) === Infinity) continue;
    best = zone; bestXp = xp / visits;
  }
  return best;
}

module.exports = { errand, supplyZone };
