// Noir Guides, GPLv3. See LICENSE.
// A small world for the planner, validator and report tests: zones, flight points, transports, an inn, and helpers
// to put quests into it. Every zone map is 1000 yards square, so one percent is 10 yards.
//   continent 0:    Westland (100) | Eastland (200), joined by a pass at Westland's east edge;
//                   Lonely Isle (300) and Isle Town (301), joined to each other only
//   continent 1:    Farshore (400)
//   continent 2991: Sky Isle (500)
const { normalizeQuest } = require("../lib/db");
const { toPoint } = require("../lib/geo");
const { buildGraph } = require("../lib/travel");
const { character } = require("../lib/characters");

function testWorld(change) {
  const db = { quests: new Map(), npcs: new Map(), objects: new Map(), items: new Map(), areas: new Map(), maps: new Map(), taxi: [], eraQuestIds: new Set() };
  const zone = (id, name, continent, minX, minY) => {
    db.areas.set(id, { id, name, parent: 0, continent });
    db.maps.set(id, { area: id, uiMap: 9000 + id, minX, minY, maxX: minX + 1000, maxY: minY + 1000 });
  };
  zone(100, "Westland", 0, 0, 0); zone(200, "Eastland", 0, 0, -1000);
  zone(300, "Lonely Isle", 0, 3000, 0); zone(301, "Isle Town", 0, 3000, -1000);
  zone(400, "Farshore", 1, 0, 0); zone(500, "Sky Isle", 2991, 0, 0);
  const P = (z, x, y) => toPoint(db, z, x, y);
  const taxiNodes = [], flightMasters = [], taxiPaths = [];
  const node = (id, name, z, x, y, flags, friendly) => {
    const p = P(z, x, y);
    taxiNodes.push({ ID: String(id), Name_lang: name, Pos_0: String(p.wx), Pos_1: String(p.wy), Pos_2: "0", ContinentID: String(p.continent), Flags: String(flags), CharacterBitNumber: String(id) });
    flightMasters.push({ id: 900 + id, name: `Master ${id}`, friendly, spawns: { [z]: [[x, y]] } });
  };
  node(1, "West Camp, Westland", 100, 20, 50, 1, "A");
  node(2, "East Camp, Eastland", 200, 80, 50, 1, "A");
  node(3, "East Mid, Eastland", 200, 30, 50, 1, "A");
  node(4, "Horde Post, Westland", 100, 20, 60, 2, "H");
  node(5, "Horde East, Eastland", 200, 80, 60, 2, "H");
  node(6, "Far Port, Farshore", 400, 50, 50, 3, "AH");
  node(7, "Far Camp, Farshore", 400, 90, 50, 3, "AH");
  let pathId = 10;
  const edge = (a, b) => { for (const [from, to] of [[a, b], [b, a]]) taxiPaths.push({ ID: String(pathId++), FromTaxiNode: String(from), ToTaxiNode: String(to), Cost: "10" }); };
  edge(1, 3); edge(3, 2); edge(4, 5); edge(6, 7);
  const transports = {
    links: [
      { id: "boat-west-far", kind: "boat", name: "West to Far", a: { zone: 100, x: 50, y: 90 }, b: { zone: 400, x: 50, y: 10 }, factions: ["Alliance"], verified: false, assumed: ["route"], seconds: 200 },
      { id: "zeppelin-west-far", kind: "zeppelin", name: "West to Far", a: { zone: 100, x: 60, y: 90 }, b: { zone: 400, x: 60, y: 10 }, factions: ["Horde"], verified: false, assumed: ["route"], seconds: 240 },
      { id: "sky", kind: "boat", name: "Off the isle", a: { zone: 500, x: 50, y: 50 }, b: { zone: 100, x: 50, y: 50 }, factions: ["Alliance"], verified: false, assumed: ["route", "boarding"],
        seconds: 120, oneWay: true, requires: { level: 3, quest: 77 } },
      { id: "goblin", kind: "boat", name: "Whose boat is it", a: { zone: 200, x: 50, y: 90 }, b: { zone: 400, x: 20, y: 90 }, factions: ["Alliance", "Horde"], verified: false, assumed: ["route", "factions"], seconds: 60 },
    ],
    passes: [
      { a: 100, b: 200, at: { zone: 100, x: 100, y: 50 }, source: "map", verified: false },
      { a: 300, b: 301, at: { zone: 300, x: 100, y: 50 }, source: "map", verified: false },
    ],
  };
  const src = { taxiNodes, taxiPaths, taxiPathNodes: [], flightMasters, transports };
  if (change) change(src, db);
  const world = { db, P, src };
  world.npc = (id, z, x, y, friendly = "AH", name = "Npc " + id) => { db.npcs.set(id, { id, name, friendly, spawns: { [z]: [[x, y]] } }); return id; };
  world.object = (id, z, x, y, name = "Object " + id) => { db.objects.set(id, { id, name, spawns: { [z]: [[x, y]] } }); return id; };
  // a herd: enough hostile spawns around one place to make the zone open country
  world.herd = (id, z, x, y, count = 320) => { db.npcs.set(id, { id, name: "Beast " + id, friendly: "", spawns: { [z]: Array.from({ length: count }, () => [x, y]) } }); return id; };
  world.quest = (id, raw) => {
    db.quests.set(id, normalizeQuest(id, { name: "Quest " + id, requiredLevel: 1, questLevel: 1, ...raw }));
    db.eraQuestIds.add(id);
    return db.quests.get(id);
  };
  // the usual quest: given and taken back by one NPC, with one creature to kill
  world.kill = (id, giver, mob, zone, more = {}) => world.quest(id, { startedBy: [[giver]], finishedBy: [[giver]], objectives: [[[mob, null, 0]]], zoneOrSort: zone, ...more });
  world.errand = (id, from, to, zone, more = {}) => world.quest(id, { startedBy: [[from]], finishedBy: [[to]], zoneOrSort: zone, ...more });
  world.inns = [{ npc: 800, friendly: "AH", point: P(100, 22, 50) }, { npc: 801, friendly: "AH", point: P(200, 78, 50) }];
  db.npcs.set(800, { id: 800, name: "Innkeeper West", friendly: "AH", spawns: { 100: [[22, 50]] } });
  db.npcs.set(801, { id: 801, name: "Innkeeper East", friendly: "AH", spawns: { 200: [[78, 50]] } });
  world.graph = () => buildGraph(db, src); // built on demand: the tests add zones and links first
  world.human = (cls = "WARRIOR", startArea = 100) => ({ ...character("Human", cls), startArea });
  world.orc = (cls = "WARRIOR", startArea = 100) => ({ ...character("Orc", cls), startArea });
  return world;
}
const at = (zone, x, y) => ({ zone, x, y });
module.exports = { testWorld, at };
