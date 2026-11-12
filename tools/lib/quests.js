// Noir Guides, GPLv3. See LICENSE.
const { eligible, SKYBORNE_CONTINENT } = require("./characters");
const { zoneOf, toPoint, distance, spawnPoints, centroid } = require("./geo");

// AreaTable IDs of the classic dungeons and raids, by ID, as AreaTable.csv names them: 209 Shadowfang Keep, 491 Razorfen
// Kraul, 717 The Stockade, 718 Wailing Caverns, 719 Blackfathom Deeps, 721 Gnomeregan, 722 Razorfen Downs, 796 Scarlet
// Monastery, 1176 Zul'Farrak, 1337 Uldaman, 1477 The Temple of Atal'Hakkar, 1581 The Deadmines, 1583 Blackrock Spire,
// 1584 Blackrock Depths, 1977 Zul'Gurub, 2017 Stratholme, 2057 Scholomance, 2100 Maraudon, 2159 Onyxia's Lair,
// 2437 Ragefire Chasm, 2557 Dire Maul, 2677 Blackwing Lair, 2717 Molten Core, 3428 Ahn'Qiraj, 3429 Ruins of Ahn'Qiraj,
// 3456 Naxxramas.
// The list is still needed for the four whose AreaTable row sits on a world continent (Temple of Atal'Hakkar, Blackrock
// Depths, Blackrock Spire, Onyxia's Lair); instanced() finds the others, and the battlegrounds, from the data.
const INSTANCE_AREAS = new Set([209, 491, 717, 718, 719, 721, 722, 796, 1176, 1337, 1477, 1581, 1583, 1584, 1977, 2017, 2057, 2100,
  2159, 2437, 2557, 2677, 2717, 3428, 3429, 3456]);
// The maps a character walks on (AreaTable ContinentID): Eastern Kingdoms, Kalimdor and the Skyborne isle. Every other
// map is a dungeon, a raid, a battleground or one of Forever's instanced places.
const OPEN_WORLD = new Set([0, 1, SKYBORNE_CONTINENT]);
// true when the area is inside an instance. An area the client tables do not have (QuestieDB's own cave IDs) is not
// known to be one.
function instanced(db, areaId) {
  for (let id = +areaId, i = 0; i < 6 && id; i++) {
    const a = db.areas.get(id);
    if (!a) return false;
    if (INSTANCE_AREAS.has(id) || !OPEN_WORLD.has(a.continent)) return true;
    id = a.parent;
  }
  return false;
}
const ZEPHRAS_ISLE = 16593; // the Skyborne starting zone (name checked in AreaTable.csv); its quests are Forever-only and still needed

const friendlyTo = (npc, faction) => !npc.friendly || npc.friendly.includes(faction[0]);
// the first giver or ender of a kind that has a known position and is usable by this faction (faction null = any)
function place(db, npcs, objects, faction) {
  for (const id of npcs) {
    const n = db.npcs.get(id);
    if (!n || (faction && !friendlyTo(n, faction))) continue;
    const c = centroid(spawnPoints(db, "npc", id));
    if (c) return { point: c, npc: id };
  }
  for (const id of objects) {
    const c = centroid(spawnPoints(db, "object", id));
    if (c) return { point: c, object: id };
  }
  return null;
}
const startPoint = (db, q, faction) => place(db, q.starts.npcs, q.starts.objects, faction || null);
const endPoint = (db, q, faction) => place(db, q.ends.npcs, q.ends.objects, faction || null);

// ESTIMATES for choosing where an objective is done; they only rank places, nothing in a route shows them.
const OBJECTIVE_KILLS = 8;    // kills or pickups an objective takes: the same guess lib/xp.js uses for objective XP
const RESPAWN_YARDS = 2100;   // waiting for one respawn, as running distance: about 5 minutes at 7 yards a second

// Every place a creature or object is found: the middle of its spawns in each zone it lives in and how many there are,
// the zone with the most spawns first.
function places(db, kind, id) {
  const byZone = new Map();
  for (const p of spawnPoints(db, kind, id)) {
    if (!byZone.has(p.zone)) byZone.set(p.zone, []);
    byZone.get(p.zone).push(p);
  }
  return [...byZone.values()].sort((a, b) => b.length - a.length || a[0].zone - b[0].zone).map((list) => ({ point: centroid(list), count: list.length }));
}
// Where to go for the quest's work: its first creature, object, item source or explore point that has a known place.
// null = nothing to do between accept and turn-in (a delivery or talk-to quest).
// A common drop has sources all over the world and a creature can live in several zones, so of the places for that one
// objective the cheapest is taken: the distance from the quest giver (from the turn-in when the giver has no place),
// plus up to one respawn's wait where there are fewer spawns than the objective needs, which keeps a lone named
// creature next to the giver from beating a herd down the road without sending anyone across the map for a herd.
// A place on another continent is never nearer. With nothing to measure from, or all the same, the first in the data stays.
function objectivePoint(db, q, faction) {
  const from = startPoint(db, q, faction) || endPoint(db, q, faction);
  const cost = (c) => (from ? distance(from.point, c.point) : 0) + RESPAWN_YARDS * Math.max(0, 1 - c.count / OBJECTIVE_KILLS);
  const cheapest = (candidates) => {
    let best = null;
    for (const c of candidates) if (!best || cost(c) < cost(best)) best = c;
    if (!best) return null;
    const { count, ...where } = best;
    return where;
  };
  const found = (kind, id, extra) => places(db, kind, id).map((place) => ({ ...place, ...extra }));
  for (const id of q.objectives.npcs) { const best = cheapest(found("npc", id, { npc: id })); if (best) return best; }
  for (const id of q.objectives.objects) { const best = cheapest(found("object", id, { object: id })); if (best) return best; }
  for (const id of q.objectives.items) {
    const item = db.items.get(id);
    const best = cheapest([...((item && item.npcDrops) || []).flatMap((n) => found("npc", n, { item: id, npc: n })),
      ...((item && item.objectDrops) || []).flatMap((o) => found("object", o, { item: id, object: o }))]);
    if (best) return best;
  }
  // a kill credit objective: any of its creatures counts
  for (const k of q.killCredit || []) {
    const best = cheapest(k.npcs.flatMap((n) => found("npc", n, { npc: n })));
    if (best) return best;
  }
  if (q.trigger) {
    const points = Object.entries(q.trigger.spawns).flatMap(([area, list]) => list.map(([x, y]) => toPoint(db, +area, x, y))).filter(Boolean);
    const best = cheapest(points.map((point) => ({ point, count: 1 })));
    if (best) return best;
  }
  return null;
}
// true when the quest has objectives but none can be placed on the map: the route could not say where to go
function unplaceable(db, q) {
  const has = q.objectives.npcs.length + q.objectives.objects.length + q.objectives.items.length + (q.killCredit || []).length > 0 || q.trigger;
  return has && !objectivePoint(db, q);
}

// true when one of the quest's objectives can only be found inside an instance: a creature or object whose every known
// spawn is in one, or an item whose every known drop is and that nothing sells. An objective with no known place at all
// proves nothing and does not count.
function instanceBound(db, q) {
  const spawnAreas = (entry) => Object.keys((entry && entry.spawns) || {});
  const allInside = (areas) => areas.length > 0 && areas.every((area) => instanced(db, area));
  if (q.objectives.npcs.some((id) => allInside(spawnAreas(db.npcs.get(id))))) return true;
  if (q.objectives.objects.some((id) => allInside(spawnAreas(db.objects.get(id))))) return true;
  // a kill credit: every creature that counts is only inside an instance
  if ((q.killCredit || []).some((k) => allInside(k.npcs.flatMap((n) => spawnAreas(db.npcs.get(n)))))) return true;
  return q.objectives.items.some((id) => {
    const item = db.items.get(id);
    if (!item || item.otherSources) return false;
    return allInside([...item.npcDrops.flatMap((n) => spawnAreas(db.npcs.get(n))), ...item.objectDrops.flatMap((o) => spawnAreas(db.objects.get(o)))]);
  });
}

// The quests a route may use for this character: takeable by race, class and faction; ordinary one-time world quests
// (not repeatable, not behind a reputation, skill or event, not in or needing a dungeon, raid or battleground);
// classic quests (or the Skyborne start); with a giver and a turn-in we can point at.
function levelingQuests(db, ch) {
  const out = [];
  for (const q of db.quests.values()) {
    if (!eligible(q, ch) || q.repeatable || q.gated || q.classes) continue;
    if (q.sort < 0 || !q.zone || instanced(db, q.zone) || instanceBound(db, q)) continue;
    if (!db.eraQuestIds.has(q.id) && zoneOf(db, q.zone) !== ZEPHRAS_ISLE) continue;
    if (q.starts.items.length && !q.starts.npcs.length && !q.starts.objects.length) continue; // started by a drop
    if (!startPoint(db, q, ch.faction) || !endPoint(db, q, ch.faction) || unplaceable(db, q)) continue;
    out.push(q);
  }
  return out.sort((a, b) => a.id - b.id);
}
function canAccept(q, state) {
  if (state.done.has(q.id) || state.log.has(q.id) || state.level < q.minLevel) return false;
  if (q.maxLevel && state.level > q.maxLevel) return false;
  if (q.disabledBy && state.log.has(q.disabledBy)) return false;
  if (q.availableUntil && state.done.has(q.availableUntil)) return false;
  if (q.availableAfter && !state.log.has(q.availableAfter) && !state.done.has(q.availableAfter)) return false;
  if (q.preAny.length && !q.preAny.some((p) => state.done.has(p))) return false;
  if (q.preAll.some((p) => !state.done.has(p))) return false;
  if (q.exclusive.some((p) => state.done.has(p) || state.log.has(p))) return false;
  return true;
}
// The quest's objectives in the order of their index (1..n) in the game's quest log: creatures, objects, items, kill
// credit, then an explore trigger. [{ index, kind: "kill" | "object" | "item" | "credit" | "event", id, npcs }]; id is
// the creature, object or item (none for "event"), npcs the creatures that count for "credit"; a credit objective's id
// is the credited creature when it is one of them (the quest log names it), else the first (the credited one is then
// a stand-in such as an invisible dummy). A quest with nothing to
// do gives []. QuestieDB keeps creatures and objects apart, so a quest that mixes them may list them in another order
// than the game: an assumption (docs/routes/DATA-NOTES.md), and only the objective lines' order depends on it.
function objectiveList(q) {
  const out = [];
  const add = (kind, id, npcs) => out.push({ index: out.length + 1, kind, id, npcs });
  for (const id of q.objectives.npcs) add("kill", id);
  for (const id of q.objectives.objects) add("object", id);
  for (const id of q.objectives.items) add("item", id);
  for (const k of q.killCredit || []) add("credit", k.npcs.includes(k.credit) ? k.credit : k.npcs[0], k.npcs);
  if (q.trigger) add("event");
  return out;
}
// Items that start the quest when used (the third list of QuestieDB's startedBy).
const starterItems = (q) => q.starts.items.slice();
// The items the quest hands the player or needs carried (QuestieDB source item and required source items), without
// the objectives' own items: the ones a quest asks to be used. The data has no "usable" flag; DATA-NOTES.md says so.
function sourceItems(q) {
  const own = new Set(q.objectives.items);
  const out = [];
  for (const id of [q.sourceItem || 0, ...(q.sourceItems || [])]) if (id > 0 && !own.has(id) && !out.includes(id)) out.push(id);
  return out;
}
// The quests that must be handed in first: all of `all`, any one of `any` (QuestieDB preQuestGroup, preQuestSingle).
const prerequisites = (q) => ({ all: q.preAll.slice(), any: q.preAny.slice() });
module.exports = { INSTANCE_AREAS, OPEN_WORLD, instanced, instanceBound, levelingQuests, startPoint, endPoint, objectivePoint, canAccept,
  objectiveList, starterItems, sourceItems, prerequisites };
