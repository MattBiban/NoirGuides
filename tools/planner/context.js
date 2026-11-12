// Noir Guides, GPLv3. See LICENSE.
// What the planner knows about one character before it plans a step: its quests with their three places, how each
// quest sits in its zone, the inns and flight points of its faction, and the travel graph it may use.
const fs = require("fs");
const path = require("path");
const { toPoint, distance, centroid, spawnPoints } = require("../lib/geo");
const { eligible } = require("../lib/characters");
const { levelingQuests, startPoint, endPoint, objectivePoint } = require("../lib/quests");
const { zoneLevels } = require("../lib/xp");
const { buildGraph, travelPlan, walkYards } = require("../lib/travel");
const { CHOICES } = require("./tuning");

// "Welcome to Azeroth" and the quest after it: what a Skyborne character is given on arriving from Zephras Isle
// (docs/routes/DATA-NOTES.md, section 3). They are Forever's own quests outside the isle, which levelingQuests leaves
// out as a group; these four are the way from the arrival point into the faction's first shared zone.
//   94947 Dalaran -> the Skyborne Portal -> Stormwind    98021 Stormwind -> Sentinel Hill, Westfall
//   95350 Mulgore -> Orgrimmar                           98024 Orgrimmar -> the Crossroads, the Barrens
const ARRIVAL_QUESTS = Object.freeze([94947, 98021, 95350, 98024]);

// QuestieDB npcFlags bit 128 is the innkeeper flag; Forever's own NPCs often carry no flags, only the title.
const INNKEEPER_FLAG = 128;
const round2 = (n) => Math.round(n * 100) / 100;

const emptyGraph = (db) => buildGraph(db, { taxiNodes: [], taxiPaths: [], taxiPathNodes: [], flightMasters: [], transports: { links: [], passes: [] } });

// The graph without the links whose users are an assumption (transports.json: assumed "factions"): a route must not
// depend on a boat nobody has seen the faction board. The validator keeps the full graph and fails such a step.
function plannerGraph(graph) {
  const links = graph.links.filter((l) => !l.assumed.includes("factions"));
  const ground = {};
  for (const [faction, g] of Object.entries(graph.ground)) {
    // a link's two ends follow each other in the list, and both go together
    ground[faction] = { places: g.places.filter((p) => !p.link || links.includes(p.link)), nodeCount: g.nodeCount, indexOfNode: g.indexOfNode, yards: new Map() };
  }
  return { ...graph, links, ground };
}

// Every innkeeper with a known place: [{ npc, name, friendly, point }], by NPC ID.
function loadInns(db, dataDir) {
  const raw = JSON.parse(fs.readFileSync(path.join(dataDir, "forever_db.json"), "utf8"));
  const out = [];
  for (const [id, n] of Object.entries(raw.Npc)) {
    if (((n.npcFlags || 0) & INNKEEPER_FLAG) === 0 && !/\bInnkeeper\b/.test(n.subName || "")) continue;
    const point = centroid(spawnPoints(db, "npc", +id));
    if (point) out.push({ npc: +id, name: n.name || "", friendly: n.friendlyToFaction || "", point });
  }
  return out.sort((a, b) => a.npc - b.npc);
}

// A place as a route step names it: rounded to a hundredth of a map percent, with the point those numbers give. The
// planner works with the rounded point, so it stands exactly where the validator and the engine read the step.
function spot(db, place) {
  if (!place) return null;
  const at = { zone: place.point.zone, x: round2(place.point.x), y: round2(place.point.y) };
  return { ...place, at, point: toPoint(db, at.zone, at.x, at.y) };
}

// How a quest sits in the zone it starts in:
//   local   everything is in the zone, or its objective is just over the border (NEARBY, on foot)
//   carry   it ends in another zone; its objective, if any, is in the start zone or in the zone it ends in
//   far     anything else: out and back to another zone, or three zones. One such quest is two border crossings for
//           one reward: planner/policy.js takes it only when the route is going to each of its zones anyway
function buildContext(db, ch, graph, inns) {
  const quests = levelingQuests(db, ch);
  const have = new Set(quests.map((q) => q.id));
  for (const id of ARRIVAL_QUESTS) {
    const q = db.quests.get(id);
    if (q && !have.has(id) && eligible(q, ch) && startPoint(db, q, ch.faction) && endPoint(db, q, ch.faction)) quests.push(q);
  }
  quests.sort((a, b) => a.id - b.id);

  const nodes = [...graph.nodes.values()].filter((n) => n.factions.includes(ch.faction)).sort((a, b) => a.id - b.id);
  const free = { faction: ch.faction, level: 60, flights: new Set(nodes.map((n) => n.id)), hearth: null, quests: new Set(db.quests.keys()) };
  const reach = (a, b) => travelPlan(db, graph, free, a, b, { pickups: false }).seconds < Infinity;

  const info = new Map(), byZone = new Map(), anchors = new Map();
  const anchor = (point) => { if (!anchors.has(point.zone)) anchors.set(point.zone, []); anchors.get(point.zone).push(point); };
  for (const q of quests) {
    const start = spot(db, startPoint(db, q, ch.faction)), end = spot(db, endPoint(db, q, ch.faction)), obj = spot(db, objectivePoint(db, q));
    if (!start.point || !end.point || (obj && !obj.point)) continue;
    // a quest no way leads through, even with every flight learned and every transport open, is not planned
    if (obj ? !reach(start.point, obj.point) || !reach(obj.point, end.point) : !reach(start.point, end.point)) continue;
    info.set(q.id, { q, start, end, obj, zone: start.point.zone, endZone: end.point.zone, objNear: false, kind: "far",
      kills: q.objectives.npcs.length + q.objectives.items.length > 0 });
    anchor(start.point); anchor(end.point); if (obj) anchor(obj.point);
  }
  for (const i of info.values()) {
    const inStart = !i.obj || i.obj.point.zone === i.zone;
    // near is measured on foot: a place 1,000 yards away behind a mountain range is not next door
    if (!inStart) i.objNear = (anchors.get(i.zone) || []).some((p) => { const walk = walkYards(graph, p, i.obj.point); return !!walk && walk.yards <= CHOICES.NEARBY; });
    if (i.endZone === i.zone) i.kind = inStart || i.objNear ? "local" : "far";
    else i.kind = inStart || i.objNear || i.obj.point.zone === i.endZone ? "carry" : "far";
    if (!byZone.has(i.zone)) byZone.set(i.zone, []);
    byZone.get(i.zone).push(i);
  }

  // the main hub of each zone: the quest giver with the most quest givers around it (the lower quest ID of equals)
  const hubs = new Map();
  for (const [zone, list] of byZone) {
    let best = null, bestCount = 0;
    for (const i of list) {
      let count = 0;
      for (const other of list) if (distance(i.start.point, other.start.point) <= CHOICES.HUB_YARDS) count++;
      if (count > bestCount) { best = i.start.point; bestCount = count; }
    }
    hubs.set(zone, best);
  }

  const mine = inns.filter((inn) => inn.friendly.includes(ch.faction[0])).map((inn) => ({ npc: inn.npc, ...spot(db, { point: inn.point }) })).filter((inn) => inn.point);
  const nodesByZone = new Map();
  for (const node of nodes) {
    const master = node.masters[ch.faction];
    const place = spot(db, { point: master.point });
    if (!nodesByZone.has(place.point.zone)) nodesByZone.set(place.point.zone, []);
    nodesByZone.get(place.point.zone).push({ id: node.id, npc: master.npc, at: place.at, point: place.point });
  }
  // quests a transport of this faction asks for: without them a place cannot be left, so they are always taken
  const linkQuests = new Set(graph.links.filter((l) => l.factions.includes(ch.faction) && l.requires && l.requires.quest).map((l) => l.requires.quest));
  for (const id of ARRIVAL_QUESTS) linkQuests.add(id);
  return { db, ch, graph, info, byZone, hubs, bands: zoneLevels(db), inns: mine, nodesByZone, linkQuests };
}

module.exports = { ARRIVAL_QUESTS, emptyGraph, plannerGraph, loadInns, spot, buildContext };
