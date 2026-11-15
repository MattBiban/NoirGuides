// Noir Guides, GPLv3. See LICENSE.
// The numbers a route is judged by: steps, zone changes, and the time and distance spent travelling. The same
// rules measure the routes of today and the routes of the baseline commit, so "before" and "after" can be compared.
//   zone changes   how often the route moves its work to another zone: two steps in a row that do something in a
//                  zone (accept, objective, turnin, grind, sethearth) and name different zones. The steps of the way
//                  (travel, getflight, fly, transport, hearth) are not counted: a dock or a flight master passed on
//                  the way is not a zone the route works in, and the old format had no such steps at all
//   travel time    a format 2 route is timed as written: every walk between two steps, every flight, transport and
//                  hearth. A route in the old format has no legs, only places; it is given the fastest way travelPlan
//                  finds between two places in a row, with every transport open to it, which flatters it
//   walked yards   the walking part of that, through the passes between zones
//   grind steps    only those the character needs: a grind step to a level the character already has when it comes
//                  to it is passed as it comes (the engine does the same). It is no work in its zone, nobody walks
//                  to it, and it is not counted. Every route that reaches the cap ends with one (planner/plan.js):
//                  the last step, for a player who arrives at the end under the cap
const { toPoint } = require("../lib/geo");
const { ESTIMATES, walkYards, travelPlan } = require("../lib/travel");

const WORK = new Set(["accept", "objective", "turnin", "grind", "sethearth"]);
const zoneOfStep = (step) => (!WORK.has(step.action) ? undefined : step.at ? step.at.zone : step.zone);

// Whether a step is a grind step to a level the character already has there (level: its level at the step's start).
const passedGrind = (step, level) => step.action === "grind" && level !== undefined && Math.floor(level) >= step.level;
// The level at the start of each step as the plan itself counted it (route.stats.levelAt: the step that reached each
// level). A route without those numbers is at level 1 throughout: every grind step of it is needed.
function planLevels(route) {
  const reached = (route.stats && route.stats.levelAt) || [];
  let level = 1;
  return route.steps.map((_, i) => { while (reached[level + 1] !== undefined && reached[level + 1] < i) level++; return level; });
}
// The indices of the grind steps a character needs: those it comes to below their level. levels: the level at each
// step (validateRoute(...).levels); without them, the plan's own.
function neededGrinds(route, levels) {
  const at = levels || planLevels(route);
  return route.steps.map((s, i) => (s.action === "grind" && !passedGrind(s, at[i]) ? i : -1)).filter((i) => i >= 0);
}

// The zones a route works in, in order, without repeats in a row. levels (optional): the character's level at each
// step; a grind step it passes is no work in its zone.
function zoneOrder(route, ch, levels) {
  const zones = [];
  route.steps.forEach((step, i) => {
    if (ch && step.when && step.when.class !== undefined && step.when.class !== ch.cls) return;
    if (levels && passedGrind(step, levels[i])) return;
    const zone = zoneOfStep(step);
    if (zone !== undefined && zones[zones.length - 1] !== zone) zones.push(zone);
  });
  return zones;
}

// levels: the character's level at each step, as the validator returns it (levels[i] for step i).
// Returns { steps, zones, zoneChanges, seconds, yards, unreachable, byKind: { walk, fly, transport, hearth } }.
// unreachable counts the places that could not be reached from the place before; they add no time.
function measureRoute(db, graph, route, ch, levels) {
  const out = { steps: 0, zones: zoneOrder(route, ch, levels), zoneChanges: 0, seconds: 0, yards: 0, unreachable: 0, byKind: { walk: 0, fly: 0, transport: 0, hearth: 0 } };
  out.zoneChanges = Math.max(0, out.zones.length - 1);
  const speed = (level) => (level >= ESTIMATES.MOUNT_LEVEL ? ESTIMATES.MOUNT_SPEED : ESTIMATES.RUN_SPEED);
  const add = (kind, seconds) => { out.byKind[kind] += seconds; out.seconds += seconds; };
  const place = (p) => (p && db.maps.has(p.zone) ? toPoint(db, p.zone, p.x, p.y) : null);
  const written = route.format === 2;
  const everyQuest = new Set(db.quests.keys());
  const flights = new Set();
  let pos = null;

  // the fastest flight between two nodes: the route's own validator has checked that it can be flown
  const flightSeconds = (from, to) => {
    const best = new Map([[from, 0]]), open = [from];
    while (open.length) {
      open.sort((a, b) => best.get(a) - best.get(b));
      const u = open.shift();
      if (u === to) return best.get(u);
      for (const e of graph.edges.get(u) || []) {
        if (written && !flights.has(e.to)) continue;
        const cost = best.get(u) + e.seconds;
        if (!best.has(e.to) || cost < best.get(e.to)) { best.set(e.to, cost); if (!open.includes(e.to)) open.push(e.to); }
      }
    }
    return 0;
  };

  route.steps.forEach((step, i) => {
    if (step.when && step.when.class !== undefined && step.when.class !== ch.cls) return;
    out.steps++;
    const level = levels ? levels[i] : 1;
    if (levels && passedGrind(step, level)) return; // passed as it comes: nobody walks to it
    const p = place(step.at);
    if (p) {
      if (pos && written) {
        const walk = pos.continent === p.continent ? walkYards(graph, pos, p) : null;
        if (!walk) out.unreachable++;
        else { out.yards += walk.yards; add("walk", (walk.yards * ESTIMATES.WALK_DETOUR) / speed(level)); }
      } else if (pos) {
        const plan = travelPlan(db, graph, { faction: ch.faction, level, flights, hearth: null, quests: everyQuest }, pos, p);
        if (plan.seconds === Infinity) out.unreachable++;
        for (const leg of plan.legs) {
          if (leg.action === "getflight") flights.add(leg.node);
          if (leg.action === "walk" || leg.action === "travel") out.yards += leg.yards;
          add(leg.action === "fly" ? "fly" : leg.action === "transport" ? "transport" : "walk", leg.seconds);
        }
      }
      pos = p;
    }
    if (!written) return;
    if (step.action === "getflight") { flights.add(step.node); add("walk", ESTIMATES.LEARN_SECONDS); }
    else if (step.action === "fly") {
      const to = graph.nodes.get(step.to);
      add("fly", ESTIMATES.BOARD_SECONDS + flightSeconds(step.from, step.to));
      if (to && to.masters[ch.faction]) pos = to.masters[ch.faction].point;
    } else if (step.action === "transport") {
      const q = place(step.to);
      const near = (a, b) => a.continent === b.continent && Math.hypot(a.wx - b.wx, a.wy - b.wy) <= 60;
      const there = p && q && graph.links.find((l) => near(p, l.a) && near(q, l.b)), back = p && q && graph.links.find((l) => near(p, l.b) && near(q, l.a));
      add("transport", there ? there.secondsAB : back ? back.secondsBA : 0);
      if (q) pos = q;
    } else if (step.action === "hearth") {
      add("hearth", ESTIMATES.HEARTH_SECONDS);
      const q = place(step.to);
      if (q) pos = q;
    }
  });
  out.seconds = Math.round(out.seconds);
  out.yards = Math.round(out.yards);
  for (const kind of Object.keys(out.byKind)) out.byKind[kind] = Math.round(out.byKind[kind]);
  return out;
}

module.exports = { measureRoute, zoneOrder, neededGrinds, planLevels, passedGrind };
