// Noir Guides, GPLv3. See LICENSE.
// Where a level is ground: the places in open country where creatures of about the player's level stand close
// together. A grind step names one of them (planner/plan.js), never the spot the character happens to stand on.
//
//   grindSpots(db, level) -> [{ at: { zone, x, y }, point, count, npcs }]
//       every place to grind at for a player of this level, the one with the most spawns first. at is rounded to a
//       hundredth of a map percent, as a route step names a place; count is the number of creature spawns that fit
//       within GRIND_RADIUS of it (at least GRIND_MIN_SPAWNS); npcs are the creatures to kill there, the one with the
//       most spawns first (those with at least GRIND_NAMED_SHARE of the spawns, at most GRIND_NAMED of them).
//   grindSpotAt(db, at, level) -> { count, npcs, min, max }
//       the same count around any place, with the creatures' level range there: what the bundler and the tests ask
//       of a grind step's place. count 0 when nothing that fits stands there.
//   grindTargets(db, at, level) -> [npc IDs]
//       the creatures to kill at a grind step's place, most spawns first; none when the place is not one of the above
//       (fewer than GRIND_MIN_SPAWNS around it).
//
// What fits a player of level L (the constants are in planner/tuning.js):
//   - a creature friendly to neither faction, not elite, rare or a boss (QuestieDB rank 0), with a name and a level;
//   - a classic creature, or one of Zephras Isle: Forever's own creatures elsewhere are left out (the data lists
//     mounts on show and event creatures among them as if they were hostile). A db without eraNpcIds, as the
//     tests' worlds, is not filtered;
//   - its whole level range within L - GRIND_BELOW to L + GRIND_ABOVE: never above L + GRIND_ABOVE;
//   - a spawn in open country: a zone lib/xp.js zoneLevels calls wild (no city, no peaceful place), not inside an
//     instance.
// The data has spawn points, not how many creatures are alive at once or how fast they come back, and nothing about
// caves and floors: a place is where the points are dense on the map.
const { zoneOf, toPoint } = require("../lib/geo");
const { instanced, ZEPHRAS_ISLE } = require("../lib/quests");
const { zoneLevels } = require("../lib/xp");
const { CHOICES: C } = require("./tuning");

const round2 = (n) => Math.round(n * 100) / 100;
const fits = (npc, level) => npc.minLevel >= level - C.GRIND_BELOW && npc.maxLevel <= level + C.GRIND_ABOVE;

// Every spawn a grind may count, by zone: [{ npc, x, y, wx, wy }] of the creatures above, whatever their level.
const tables = new WeakMap();
function spawnTable(db) {
  let cached = tables.get(db.npcs);
  if (cached && cached.size === db.npcs.size) return cached.byZone; // again when the table has grown, as test worlds do
  const bands = zoneLevels(db);
  const byZone = new Map();
  for (const npc of db.npcs.values()) {
    if (npc.friendly || npc.rank || !npc.name || !(npc.minLevel >= 1) || !(npc.maxLevel >= npc.minLevel)) continue;
    for (const [area, list] of Object.entries(npc.spawns || {})) {
      const zone = zoneOf(db, +area);
      const band = bands.get(zone);
      if (!band || !band.wild || instanced(db, +area)) continue;
      if (db.eraNpcIds && !db.eraNpcIds.has(npc.id) && zone !== ZEPHRAS_ISLE) continue;
      if (!byZone.has(zone)) byZone.set(zone, []);
      for (const [x, y] of list) {
        const p = toPoint(db, zone, x, y);
        if (p) byZone.get(zone).push({ npc, x, y, wx: p.wx, wy: p.wy });
      }
    }
  }
  tables.set(db.npcs, { size: db.npcs.size, byZone, spots: new Map() });
  return byZone;
}

// The spawns that fit the level within GRIND_RADIUS of a point, of a list of spawns in the point's zone.
const around = (list, p, level) => list.filter((s) => fits(s.npc, level) && Math.hypot(s.wx - p.wx, s.wy - p.wy) <= C.GRIND_RADIUS);
// What stands there: the count, the creatures by their number of spawns (the lower ID of equals), their levels.
function census(members) {
  const per = new Map();
  let min = Infinity, max = -Infinity;
  for (const s of members) {
    per.set(s.npc.id, (per.get(s.npc.id) || 0) + 1);
    min = Math.min(min, s.npc.minLevel); max = Math.max(max, s.npc.maxLevel);
  }
  const ranked = [...per].sort((a, b) => b[1] - a[1] || a[0] - b[0]);
  const npcs = ranked.filter(([, n]) => n >= members.length * C.GRIND_NAMED_SHARE).slice(0, C.GRIND_NAMED).map(([id]) => id);
  return { count: members.length, npcs: npcs.length ? npcs : ranked.slice(0, 1).map(([id]) => id), min, max };
}

function grindSpotAt(db, at, level) {
  const p = at ? toPoint(db, at.zone, at.x, at.y) : null;
  const list = p ? spawnTable(db).get(p.zone) : null;
  if (!list) return { count: 0, npcs: [] };
  const members = around(list, p, level);
  return members.length ? census(members) : { count: 0, npcs: [] };
}

// The places of one zone: the map is cut into squares of GRIND_RADIUS; the middle of each square's spawns is tried
// as a place, moved once to the middle of what stands around it. Of two places within GRIND_RADIUS of each other the
// one with more spawns stays.
function spotsOfZone(db, zone, list, level) {
  const mine = list.filter((s) => fits(s.npc, level));
  if (mine.length < C.GRIND_MIN_SPAWNS) return [];
  const cells = new Map();
  for (const s of mine) {
    const key = `${Math.floor(s.wx / C.GRIND_RADIUS)}:${Math.floor(s.wy / C.GRIND_RADIUS)}`;
    if (!cells.has(key)) cells.set(key, []);
    cells.get(key).push(s);
  }
  const middle = (members) => ({ x: members.reduce((sum, s) => sum + s.x, 0) / members.length, y: members.reduce((sum, s) => sum + s.y, 0) / members.length });
  const found = [];
  for (const key of [...cells.keys()].sort()) {
    const seed = middle(cells.get(key));
    const near = around(mine, toPoint(db, zone, seed.x, seed.y), level);
    if (near.length < C.GRIND_MIN_SPAWNS) continue;
    const m = middle(near);
    const at = { zone, x: round2(m.x), y: round2(m.y) };
    const point = toPoint(db, zone, at.x, at.y);
    const members = around(mine, point, level);
    if (members.length >= C.GRIND_MIN_SPAWNS) found.push({ at, point, ...census(members) });
  }
  found.sort((a, b) => b.count - a.count || a.at.x - b.at.x || a.at.y - b.at.y);
  const kept = [];
  for (const f of found) if (!kept.some((k) => Math.hypot(k.point.wx - f.point.wx, k.point.wy - f.point.wy) <= C.GRIND_RADIUS)) kept.push(f);
  return kept;
}

function grindSpots(db, level) {
  const byZone = spawnTable(db);
  const cache = tables.get(db.npcs).spots;
  if (cache.has(level)) return cache.get(level);
  const out = [];
  for (const zone of [...byZone.keys()].sort((a, b) => a - b)) out.push(...spotsOfZone(db, zone, byZone.get(zone), level));
  out.sort((a, b) => b.count - a.count || a.at.zone - b.at.zone || a.at.x - b.at.x || a.at.y - b.at.y);
  cache.set(level, out);
  return out;
}

function grindTargets(db, at, level) {
  const spot = grindSpotAt(db, at, level);
  return spot.count >= C.GRIND_MIN_SPAWNS ? spot.npcs : [];
}

module.exports = { grindSpots, grindSpotAt, grindTargets };
