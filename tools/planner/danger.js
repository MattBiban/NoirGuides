// Noir Guides, GPLv3. See LICENSE.
// Dangerous walks: a route that sends a character on foot through a zone whose creatures are far above its level. A
// level 19 character that walks the length of a zone of level 30 creatures dies on the way, again and again.
//
//   safeLevels(db) -> Map of zone -> the lowest level that walks there safely
//   havens(graph)  -> [{ point, yards }]: the places where a walk is safe whatever the zone
//   dangerousWalks(db, graph, route, ch, levels) -> [{ step, level, from, to, zone, min }]
//
// A zone is dangerous for a level when it is open country (lib/xp.js zoneLevels, wild) and the low end of its
// creatures' levels is more than DANGER_LEVELS (planner/tuning.js) above the level. A city is never dangerous, and
// neither is a zone the data files no quests under (it has no levels to go by).
// The rule itself is in lib/travel.js: the planner's graph carries safeLevels (planner/context.js plannerGraph), and
// travelPlan and walkSeconds then know no walk through a zone that is dangerous for the traveller's level. So every
// way the planner costs keeps it: the next zone, an errand, a carried quest, a class quest, a trainer. Flying over a
// zone, riding a boat or a zeppelin and standing where one arrives are fine; walking on from there is a walk.
// There is no road data, so a zone crossed counts as walked through, wherever its road runs.
// One exception, a haven: the end of a transport that asks for a quest is where the game puts a new character down,
// and a walk that stays within ARRIVAL_YARDS of it is safe (the Skyborne arrive in Dalaran, in a zone of level 33
// creatures, hand a quest in and step through a portal 96 yards on).
//
// dangerousWalks is the check on a finished route. route is a format 2 route, levels[k] the character's level at step
// k (planner/validate.js); the steps of other classes (when.class) are left out. Every step with a place is walked to
// from where the step before left the player, as the validator walks it, and the zones of that walk (lib/travel.js
// walkZones) are held against the level. One entry a walk, for the most dangerous zone on it:
//   step    the index of the step walked to     level   the character's level there
//   from    the zone the walk starts in         to      the zone it ends in
//   zone    the dangerous zone                  min     the low end of its creatures' levels
// Only the route's own steps are read, so the check stands apart from the search that plans them.
const { toPoint } = require("../lib/geo");
const { zoneLevels } = require("../lib/xp");
const { walkYards, walkZones } = require("../lib/travel");
const { CHOICES: C } = require("./tuning");

// A walk this short is no walk: a route's places are rounded to a hundredth of a map percent, so the step at a
// flight master or a dock stands a yard or two from where the flight or the boat put the player down.
const STILL_YARDS = 5;
// What a route may have before the build and the tests fail: none.
const MAX_DANGEROUS_WALKS = 0;

const tables = new WeakMap(); // one table a database: it is read for every route and every class
function safeLevels(db) {
  if (!tables.has(db)) {
    const out = new Map();
    for (const [zone, band] of zoneLevels(db)) if (band.wild) out.set(zone, band.min - C.DANGER_LEVELS);
    tables.set(db, out);
  }
  return tables.get(db);
}

const havens = (graph) => graph.links.filter((l) => l.requires && l.requires.quest).flatMap((l) => [l.a, l.b]).map((point) => ({ point, yards: C.ARRIVAL_YARDS }));

function dangerousWalks(db, graph, route, ch, levels) {
  const safe = safeLevels(db);
  const shelters = havens(graph);
  const sheltered = (p) => shelters.some((h) => h.point.zone === p.zone && Math.hypot(h.point.wx - p.wx, h.point.wy - p.wy) <= h.yards);
  const point = (at) => (at && db.maps.has(at.zone) ? toPoint(db, at.zone, at.x, at.y) : null);
  const out = [];
  let pos = null;
  route.steps.forEach((s, k) => {
    const level = Math.floor(levels[k]);
    if (s.when && ((s.when.class !== undefined && s.when.class !== ch.cls) || (s.when.level !== undefined && level < s.when.level))) return;
    const p = point(s.at);
    if (p) {
      const walk = pos && pos.continent === p.continent ? walkYards(graph, pos, p) : null;
      if (walk && walk.yards > STILL_YARDS && !(pos.zone === p.zone && sheltered(pos) && sheltered(p))) {
        const worst = walkZones(graph, pos, p).filter((zone) => safe.get(zone) > level).sort((a, b) => safe.get(b) - safe.get(a) || a - b)[0];
        if (worst !== undefined) out.push({ step: k, level, from: pos.zone, to: p.zone, zone: worst, min: safe.get(worst) + C.DANGER_LEVELS });
      }
      pos = p;
    }
    if (s.action === "fly") { const node = graph.nodes.get(s.to); if (node && node.masters[ch.faction]) pos = node.masters[ch.faction].point; }
    else if (s.action === "transport" || s.action === "hearth") pos = point(s.to) || pos;
  });
  return out;
}

module.exports = { safeLevels, havens, dangerousWalks, MAX_DANGEROUS_WALKS, STILL_YARDS };
