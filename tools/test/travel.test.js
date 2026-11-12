// Noir Guides, GPLv3. See LICENSE.
// Travel: the flight graph, the hand-written transport links and passes, and travelPlan.
// The first half runs on a small world written here; the second half checks the fetched client data and
// planner/transports.json against each other and plans real trips (skipped when tools/data is not fetched).
const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");
const { toPoint } = require("../lib/geo");
const { readCsv } = require("../lib/csv");
const { loadDb } = require("../lib/db");
const { ESTIMATES, buildGraph, loadTravel, walkYards, walkSeconds, travelPlan, toSteps, pointAt } = require("../lib/travel");

const DATA = path.join(__dirname, "..", "data");
const real = fs.existsSync(path.join(DATA, "forever_db.json")) && fs.existsSync(path.join(DATA, "wago", "TaxiPathNode.csv"));
const TRANSPORTS = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "planner", "transports.json"), "utf8"));
const E = ESTIMATES;
const ASSUMABLE = ["route", "factions", "boarding", "arrival", "kind"]; // what a link in transports.json may name as assumed
const near = (a, b, eps = 1e-6) => Math.abs(a - b) <= eps;
const actions = (plan) => plan.legs.map((l) => l.action);
const dist2 = (a, b) => Math.hypot(a.wx - b.wx, a.wy - b.wy);

// ---------------------------------------------------------------------------------------------------------------
// A small world. Every zone map is 1000 yards square, so one percent is 10 yards.
//   continent 0: Westland (100) | Eastland (200) | Uncharted (600), side by side from west to east;
//                Isle (300) and Isle Town (301) far to the north, joined to each other only
//   continent 1: Farshore (400)        continent 2991: Sky Isle (500)
function world() {
  const db = { quests: new Map(), npcs: new Map(), objects: new Map(), items: new Map(), areas: new Map(), maps: new Map(), taxi: [], eraQuestIds: new Set() };
  const zone = (id, name, continent, minX, minY) => {
    db.areas.set(id, { id, name, parent: 0, continent });
    db.maps.set(id, { area: id, uiMap: id, minX, minY, maxX: minX + 1000, maxY: minY + 1000 });
  };
  zone(100, "Westland", 0, 0, 0); zone(200, "Eastland", 0, 0, -1000); zone(600, "Uncharted", 0, 0, -2000);
  zone(300, "Isle", 0, 3000, 0); zone(301, "Isle Town", 0, 3000, -1000);
  zone(400, "Farshore", 1, 0, 0); zone(500, "Sky Isle", 2991, 0, 0);
  return db;
}
function sources(db) {
  const P = (z, x, y) => toPoint(db, z, x, y);
  const taxiNodes = [], flightMasters = [];
  // a node at a zone percent, with a flight master of the given friendliness standing 5 yards away ("" = nobody)
  const node = (id, name, z, x, y, flags, bit, friendly) => {
    const p = P(z, x, y);
    taxiNodes.push({ ID: String(id), Name_lang: name, Pos_0: String(p.wx), Pos_1: String(p.wy), Pos_2: "0", ContinentID: String(p.continent), Flags: String(flags), CharacterBitNumber: String(bit) });
    if (friendly) flightMasters.push({ id: 900 + id, name: `Master ${id}`, friendly, spawns: { [z]: [[x + 0.5, y]] } });
  };
  node(1, "West Camp, Westland", 100, 20, 50, 1025, 1, "A");
  node(2, "East Camp, Eastland", 200, 80, 50, 1025, 2, "A");
  node(3, "East Mid, Eastland", 200, 30, 50, 1025, 3, "A");
  node(4, "Horde Post, Westland", 100, 20, 60, 1026, 4, "H");
  node(5, "Horde East, Eastland", 200, 80, 60, 1026, 5, "H");
  node(6, "Far Port, Farshore", 400, 50, 50, 1027, 6, "AH");
  node(7, "Far Camp, Farshore", 400, 90, 50, 1027, 7, "AH");
  node(8, "zzOLD Thing, Westland", 100, 70, 70, 1025, 8, "A");       // no path leads anywhere
  node(9, "Druid Grove, Westland", 100, 5, 5, 1025, 0, "A");         // no bit in the known-nodes mask: cannot be learned
  node(10, "No Master, Eastland", 200, 50, 10, 1025, 10, "");        // nobody stands there in the data
  node(11, "Mixed Post, Farshore", 400, 10, 10, 1027, 11, "A");      // flagged for both, only an Alliance master
  node(12, "Transport, West - Far", 100, 50, 90, 1024, 0, "");       // a transport node: no faction flag
  const taxiPaths = [];
  const edge = (id, from, to) => taxiPaths.push({ ID: String(id), FromTaxiNode: String(from), ToTaxiNode: String(to), Cost: "10" });
  edge(11, 1, 3); edge(12, 3, 1); edge(13, 3, 2); edge(14, 2, 3); edge(15, 4, 5); edge(16, 5, 4);
  edge(17, 6, 7); edge(18, 7, 6); edge(19, 9, 1); edge(20, 10, 2); edge(21, 2, 10); edge(22, 11, 6); edge(23, 6, 11);
  edge(24, 12, 12);
  const taxiPathNodes = [];
  const pathNode = (pathId, index, continent, wx, wy, flags = 0, delay = 0) =>
    taxiPathNodes.push({ PathID: String(pathId), NodeIndex: String(index), ContinentID: String(continent), Loc_0: String(wx), Loc_1: String(wy), Loc_2: "0", Flags: String(flags), Delay: String(delay) });
  // path 11 (node 1 to node 3) bends: 500,800 -> 800,400 -> 500,-300 = 500 + 761.577... yards
  pathNode(11, 0, 0, 500, 800); pathNode(11, 2, 0, 500, -300); pathNode(11, 1, 0, 800, 400);
  // path 900, the boat: sails in at 100,900, stops at the Westland dock (100,500), leaves the map at 100,100,
  // appears on continent 1 at 900,900, stops at the Farshore dock (900,500), sails out to 900,300
  pathNode(900, 0, 0, 100, 900); pathNode(900, 1, 0, 100, 500, 2, 60); pathNode(900, 2, 0, 100, 100);
  pathNode(900, 3, 1, 900, 900); pathNode(900, 4, 1, 900, 500, 2, 60); pathNode(900, 5, 1, 900, 300);
  const transports = {
    links: [
      { id: "boat-west-far", kind: "boat", name: "West to Far", a: { zone: 100, x: 50, y: 90 }, b: { zone: 400, x: 50, y: 10 }, factions: ["Alliance"], verified: true, path: 900 },
      { id: "zeppelin-west-far", kind: "zeppelin", name: "West to Far", a: { zone: 100, x: 60, y: 90 }, b: { zone: 400, x: 60, y: 10 }, factions: ["Horde"], verified: false, assumed: ["route"], seconds: 240 },
      { id: "sky", kind: "boat", name: "Off the isle", a: { zone: 500, x: 50, y: 50 }, b: { zone: 100, x: 50, y: 50 }, factions: ["Alliance"], verified: false, assumed: ["route", "boarding"], seconds: 120,
        oneWay: true, requires: { level: 7, quest: 77 } },
    ],
    passes: [
      { a: 100, b: 200, at: { zone: 100, x: 100, y: 50 }, source: "map", verified: false },
      { a: 300, b: 301, at: { zone: 300, x: 100, y: 50 }, source: "map", verified: false },
    ],
  };
  return { taxiNodes, taxiPaths, taxiPathNodes, flightMasters, transports };
}
function fixture(change) {
  const db = world(), src = sources(db);
  if (change) change(src, db);
  return { db, graph: buildGraph(db, src), P: (z, x, y) => toPoint(db, z, x, y) };
}
const alliance = (flights = [], more = {}) => ({ faction: "Alliance", level: 10, flights: new Set(flights), hearth: null, ...more });
const horde = (flights = [], more = {}) => ({ faction: "Horde", level: 10, flights: new Set(flights), hearth: null, ...more });
const walkTime = (yards, level = 10) => (yards * E.WALK_DETOUR) / (level >= E.MOUNT_LEVEL ? E.MOUNT_SPEED : E.RUN_SPEED);

// Walks a plan from its start and fails on the first leg that does not begin where the last one ended, on a flight
// through a node the character has not learned, and on a transport the character may not use.
function checkPlan(graph, state, from, to, plan, options = {}) {
  assert.ok(Number.isFinite(plan.seconds), "the place can be reached");
  const known = new Set(state.flights);
  const same = (a, b) => a.continent === b.continent && Math.hypot(a.wx - b.wx, a.wy - b.wy) < 1;
  let pos = from, sum = 0;
  for (const leg of plan.legs) {
    assert.ok(leg.seconds >= 0 && Number.isFinite(leg.seconds), `${leg.action} has a time`);
    sum += leg.seconds;
    if (leg.action === "walk" || leg.action === "travel") {
      assert.strictEqual(pos.continent, leg.at.continent, "walking stays on one continent");
      assert.strictEqual(leg.action === "travel", pos.zone !== leg.at.zone, "travel is a walk into another zone");
      pos = leg.at;
    } else if (leg.action === "getflight") {
      const node = graph.nodes.get(leg.node);
      assert.ok(node.factions.includes(state.faction), `node ${leg.node} is for ${state.faction}`);
      assert.ok(same(pos, leg.at), `the character stands at node ${leg.node} when learning it`);
      assert.ok(!known.has(leg.node), `node ${leg.node} is not learned twice`);
      known.add(leg.node);
    } else if (leg.action === "fly") {
      for (const id of [leg.from, ...leg.via, leg.to]) {
        assert.ok(known.has(id), `flight ${leg.from} to ${leg.to} uses node ${id}, which is not learned`);
        assert.ok(graph.nodes.get(id).factions.includes(state.faction));
      }
      const hops = [leg.from, ...leg.via, leg.to];
      for (let i = 1; i < hops.length; i++) assert.ok(graph.edges.get(hops[i - 1]).some((e) => e.to === hops[i]), `there is a taxi path ${hops[i - 1]} to ${hops[i]}`);
      assert.ok(same(pos, leg.at), "the flight leaves from where the character stands");
      pos = leg.land;
    } else if (leg.action === "transport") {
      const link = graph.links.find((l) => l.id === leg.link);
      assert.ok(link.factions.includes(state.faction), `${leg.link} is not for ${state.faction}`);
      assert.ok(!link.requires || !link.requires.level || state.level >= link.requires.level, `${leg.link} needs a higher level`);
      assert.ok(!link.requires || !link.requires.quest || (state.quests && state.quests.has(link.requires.quest)), `${leg.link} needs quest ${link.requires && link.requires.quest}`);
      assert.deepStrictEqual([leg.verified, leg.pathVerified, leg.assumed], [link.verified, link.pathVerified, link.assumed], `${leg.link} carries what is confirmed about it`);
      assert.strictEqual(leg.verified, leg.assumed.length === 0, `${leg.link} is verified exactly when nothing about it is assumed`);
      if (options.verifiedOnly) assert.ok(link.verified, `${leg.link} is not verified`);
      assert.ok(same(pos, leg.at), "the transport leaves from where the character stands");
      assert.ok(same(leg.at, link.a) ? same(leg.to, link.b) : !link.oneWay && same(leg.at, link.b) && same(leg.to, link.a), `${leg.link} runs that way`);
      pos = leg.to;
    } else if (leg.action === "hearth") {
      assert.ok(state.hearth && same(leg.to, state.hearth));
      pos = leg.to;
    } else assert.fail(`unknown leg ${leg.action}`);
  }
  assert.ok(same(pos, to), "the plan ends at the destination");
  assert.ok(near(sum, plan.seconds, 1e-6), "seconds is the sum of the legs");
  return known;
}

test("fixture: nodes take their faction from the client flags and the flight master standing there", () => {
  const { graph } = fixture();
  const n = (id) => graph.nodes.get(id);
  assert.deepStrictEqual(n(1).factions, ["Alliance"]);
  assert.deepStrictEqual(n(4).factions, ["Horde"]);
  assert.deepStrictEqual(n(6).factions, ["Alliance", "Horde"]);
  assert.strictEqual(n(1).npc, 901);
  assert.strictEqual(n(1).point.zone, 100);
  assert.ok(near(n(1).point.x, 20.5) && near(n(1).point.y, 50), "the step goes to the flight master");
  // flagged for both factions, but the only flight master found is friendly to the Alliance
  assert.deepStrictEqual(n(11).factions, ["Alliance"]);
  // nobody found: the client flag stands, without an NPC, and the graph says so
  assert.deepStrictEqual(n(10).factions, ["Alliance"]);
  assert.strictEqual(n(10).npc, 0);
  assert.ok(graph.notes.some((t) => t.includes("node 10") && t.includes("no flight master")));
  assert.ok(graph.notes.some((t) => t.includes("node 11") && t.includes("Horde")));
});
test("fixture: nodes that cannot be learned or lead nowhere are not in the graph", () => {
  const { graph } = fixture();
  assert.ok(!graph.nodes.has(8), "no path");
  assert.ok(!graph.nodes.has(9), "no bit in the known-nodes mask");
  assert.ok(!graph.nodes.has(12), "no faction flag");
  assert.ok(!graph.edges.get(1).some((e) => e.to === 9));
});
test("fixture: a flight's time is its path length at flight speed; without path nodes, the straight line times the usual ratio", () => {
  const { graph } = fixture();
  const e13 = graph.edges.get(1).find((e) => e.to === 3);
  const bent = Math.hypot(300, 400) + Math.hypot(300, 700);
  assert.ok(near(e13.yards, bent, 1e-6), "path nodes are read in NodeIndex order");
  assert.ok(near(e13.seconds, bent / E.FLIGHT_SPEED));
  const e32 = graph.edges.get(3).find((e) => e.to === 2);
  assert.ok(near(e32.yards, 500 * E.FLIGHT_PATH_RATIO));
  assert.strictEqual(e32.estimated, true);
});
test("fixture: a transport's time comes from its path: half a loop of waiting plus the ride between the stops", () => {
  const { graph } = fixture();
  const boat = graph.links.find((l) => l.id === "boat-west-far");
  const loop = 1400 / E.TRANSPORT_SPEED + 120; // 400 + 400, a jump, 400 + 200, a jump back: jumps have no length; two stops of 60 s
  assert.ok(near(boat.loopSeconds, loop));
  assert.ok(near(boat.secondsAB, loop / 2 + 800 / E.TRANSPORT_SPEED), "out of the first map and into the second");
  assert.ok(near(boat.secondsBA, loop / 2 + 600 / E.TRANSPORT_SPEED), "the rest of the loop");
  const zep = graph.links.find((l) => l.id === "zeppelin-west-far");
  assert.deepStrictEqual([zep.secondsAB, zep.secondsBA], [240, 240]);
});
test("fixture: a link marked verified must have a client path that stops at both ends", () => {
  assert.throws(() => fixture((src) => { src.transports.links[0].b = { zone: 400, x: 50, y: 30 }; }), /boat-west-far.*stop/);
  assert.throws(() => fixture((src) => { delete src.transports.links[0].path; }), /boat-west-far/);
  assert.throws(() => fixture((src) => { src.transports.links[1].verified = true; }), /zeppelin-west-far/);
  assert.throws(() => fixture((src) => { src.transports.links[1].a = { zone: 9999, x: 1, y: 1 }; }), /zeppelin-west-far/);
  assert.throws(() => fixture((src) => { delete src.transports.links[1].seconds; }), /zeppelin-west-far.*seconds/);
});
test("fixture: verified means nothing about the link is assumed, and an unverified link says what is", () => {
  // a client path that stops at both ends does not make an assumption about who may board a fact
  assert.throws(() => fixture((src) => { src.transports.links[0].assumed = ["factions"]; }), /boat-west-far.*verified.*factions/);
  assert.throws(() => fixture((src) => { delete src.transports.links[1].assumed; }), /zeppelin-west-far.*assumed/);
  assert.throws(() => fixture((src) => { src.transports.links[1].assumed = []; }), /zeppelin-west-far.*assumed/);
  assert.throws(() => fixture((src) => { src.transports.links[1].assumed = ["weather"]; }), /zeppelin-west-far.*weather/);
  assert.throws(() => fixture((src) => { src.transports.links[1].assumed = "route"; }), /zeppelin-west-far.*assumed/);
  // no client path: the route itself is an assumption and has to be named
  assert.throws(() => fixture((src) => { src.transports.links[1].assumed = ["factions"]; }), /zeppelin-west-far.*route/);
  const { graph } = fixture((src) => { Object.assign(src.transports.links[0], { verified: false, assumed: ["factions"] }); });
  const link = (id) => graph.links.find((l) => l.id === id);
  assert.deepStrictEqual([link("boat-west-far").verified, link("boat-west-far").pathVerified, link("boat-west-far").assumed], [false, true, ["factions"]]);
  assert.deepStrictEqual([link("zeppelin-west-far").verified, link("zeppelin-west-far").pathVerified, link("zeppelin-west-far").assumed], [false, false, ["route"]]);
  assert.deepStrictEqual([link("sky").verified, link("sky").pathVerified, link("sky").assumed], [false, false, ["route", "boarding"]]);
  const plain = fixture().graph.links.find((l) => l.id === "boat-west-far");
  assert.deepStrictEqual([plain.verified, plain.pathVerified, plain.assumed], [true, true, []]);
});

test("fixture, same zone: one walk leg at running speed, faster with a mount", () => {
  const { db, graph, P } = fixture();
  const from = P(100, 50, 50), to = P(100, 50, 20);
  const plan = travelPlan(db, graph, alliance(), from, to);
  assert.deepStrictEqual(actions(plan), ["walk"]);
  assert.ok(near(plan.legs[0].yards, 300));
  assert.ok(near(plan.seconds, walkTime(300)));
  const mounted = travelPlan(db, graph, alliance([], { level: E.MOUNT_LEVEL }), from, to);
  assert.ok(near(mounted.seconds, (300 * E.WALK_DETOUR) / E.MOUNT_SPEED));
  assert.deepStrictEqual(travelPlan(db, graph, alliance(), from, from), { legs: [], seconds: 0 });
  checkPlan(graph, alliance(), from, to, plan);
});
test("fixture, same continent without a flight: on foot through the pass, never in the air", () => {
  const { db, graph, P } = fixture();
  const from = P(100, 50, 50), to = P(200, 50, 20);
  // the pass is at world 500,0: 500 yards to it, then 500 east and 300 north
  const yards = 500 + Math.hypot(500, 300);
  const plain = travelPlan(db, graph, alliance(), from, to, { pickups: false });
  assert.deepStrictEqual(actions(plain), ["travel"]);
  assert.ok(near(plain.legs[0].yards, yards));
  assert.ok(near(plain.seconds, walkTime(yards)));
  assert.ok(near(walkSeconds(graph, 10, from, to), walkTime(yards)));
  checkPlan(graph, alliance(), from, to, plain);
  // the Horde has nodes in both zones too, but has learned none of them
  const h = travelPlan(db, graph, horde(), from, to);
  assert.ok(!actions(h).includes("fly"));
  checkPlan(graph, horde(), from, to, h);
});
test("fixture: a flight point close to the way is picked up", () => {
  const { db, graph, P } = fixture();
  const from = P(100, 50, 50), to = P(200, 50, 50);
  // node 3's flight master stands at Eastland 30.5,50: on the straight line from the pass to the destination
  const plan = travelPlan(db, graph, alliance(), from, to);
  assert.deepStrictEqual(actions(plan), ["travel", "getflight", "walk"]);
  assert.strictEqual(plan.legs[1].node, 3);
  assert.strictEqual(plan.legs[1].npc, 903);
  assert.ok(near(plan.seconds, walkTime(1000) + E.LEARN_SECONDS));
  checkPlan(graph, alliance(), from, to, plan);
  // already learned: not learned again
  const again = travelPlan(db, graph, alliance([3]), from, to);
  assert.ok(!again.legs.some((l) => l.action === "getflight" && l.node === 3));
  checkPlan(graph, alliance([3]), from, to, again);
  // switched off: the plain way
  assert.deepStrictEqual(actions(travelPlan(db, graph, alliance(), from, to, { pickups: false })), ["travel"]);
  // the Horde does not stop at an Alliance flight master
  assert.deepStrictEqual(actions(travelPlan(db, graph, horde(), from, to)), ["travel"]);
  // node 10 is 400 yards off the way: too far for a detour
  assert.ok(!travelPlan(db, graph, alliance(), from, to).legs.some((l) => l.node === 10));
});
test("fixture, same continent with a known flight: it flies, through learned nodes only", () => {
  const { db, graph, P } = fixture();
  const at1 = graph.nodes.get(1).point, at2 = graph.nodes.get(2).point, at3 = graph.nodes.get(3).point;
  const e = (a, b) => graph.edges.get(a).find((x) => x.to === b).seconds;
  // both ends learned
  let state = alliance([1, 3]);
  let plan = travelPlan(db, graph, state, at1, at3);
  assert.deepStrictEqual(actions(plan), ["fly"]);
  assert.deepStrictEqual([plan.legs[0].from, plan.legs[0].via, plan.legs[0].to], [1, [], 3]);
  assert.ok(near(plan.seconds, E.BOARD_SECONDS + e(1, 3)));
  assert.ok(plan.seconds < walkSeconds(graph, 10, at1, at3));
  checkPlan(graph, state, at1, at3, plan);
  // two hops when the node between is learned
  state = alliance([1, 2, 3]);
  plan = travelPlan(db, graph, state, at1, at2);
  assert.deepStrictEqual(actions(plan), ["fly"]);
  assert.deepStrictEqual([plan.legs[0].from, plan.legs[0].via, plan.legs[0].to], [1, [3], 2]);
  assert.ok(near(plan.seconds, E.BOARD_SECONDS + e(1, 3) + e(3, 2)));
  checkPlan(graph, state, at1, at2, plan);
  // the node between is not learned: no flight from 1. Walking past node 3 teaches it, and from there node 2 is known.
  state = alliance([1, 2]);
  plan = travelPlan(db, graph, state, at1, at2);
  assert.deepStrictEqual(actions(plan), ["travel", "getflight", "fly"]);
  assert.deepStrictEqual([plan.legs[1].node, plan.legs[2].from, plan.legs[2].to], [3, 3, 2]);
  checkPlan(graph, state, at1, at2, plan);
  // the destination's node is not learned: fly as far as is known, walk the rest, learn the node on arrival
  state = alliance([1, 3]);
  plan = travelPlan(db, graph, state, at1, at2);
  assert.deepStrictEqual(actions(plan), ["fly", "walk", "getflight"]);
  assert.strictEqual(plan.legs[0].to, 3);
  checkPlan(graph, state, at1, at2, plan);
  // nothing learned: no flight at all
  plan = travelPlan(db, graph, alliance(), at1, at2);
  assert.ok(!actions(plan).includes("fly"));
  // a short hop is walked even when the flight is known
  const a = P(200, 30, 50), b = P(200, 35, 50);
  assert.deepStrictEqual(actions(travelPlan(db, graph, alliance([1, 2, 3]), a, b)), ["walk"]);
});
test("fixture, another continent: each faction takes its own transport, and none when it has none", () => {
  const { db, graph, P } = fixture();
  const from = P(100, 50, 50), to = P(400, 50, 50);
  const a = travelPlan(db, graph, alliance(), from, to, { pickups: false });
  assert.deepStrictEqual(actions(a), ["walk", "transport", "walk"]);
  assert.deepStrictEqual([a.legs[1].link, a.legs[1].kind, a.legs[1].verified], ["boat-west-far", "boat", true]);
  assert.deepStrictEqual([a.legs[1].pathVerified, a.legs[1].assumed], [true, []]);
  const boat = graph.links.find((l) => l.id === "boat-west-far");
  assert.ok(near(a.seconds, walkTime(400) + boat.secondsAB + walkTime(400)));
  checkPlan(graph, alliance(), from, to, a);
  const back = travelPlan(db, graph, alliance(), to, from, { pickups: false });
  assert.ok(near(back.seconds, walkTime(400) + boat.secondsBA + walkTime(400)));
  checkPlan(graph, alliance(), to, from, back);
  const h = travelPlan(db, graph, horde(), from, to, { pickups: false });
  assert.deepStrictEqual(h.legs.filter((l) => l.action === "transport").map((l) => l.link), ["zeppelin-west-far"]);
  assert.strictEqual(h.legs.find((l) => l.action === "transport").verified, false);
  assert.deepStrictEqual([h.legs.find((l) => l.action === "transport").pathVerified, h.legs.find((l) => l.action === "transport").assumed], [false, ["route"]]);
  checkPlan(graph, horde(), from, to, h);
  // a caller that wants confirmed facts only plans without the unverified zeppelin; the verified boat stays
  assert.deepStrictEqual(travelPlan(db, graph, horde(), from, to, { verifiedOnly: true }), { legs: [], seconds: Infinity });
  const sure = travelPlan(db, graph, alliance(), from, to, { pickups: false, verifiedOnly: true });
  assert.deepStrictEqual(sure, a);
  checkPlan(graph, alliance(), from, to, sure, { verifiedOnly: true });
  // a link whose factions are assumed still carries its path's verdict, apart from the overall one
  const unsure = fixture((src) => { Object.assign(src.transports.links[0], { verified: false, assumed: ["factions"] }); });
  const leg = travelPlan(unsure.db, unsure.graph, alliance(), from, to, { pickups: false }).legs[1];
  assert.deepStrictEqual([leg.link, leg.verified, leg.pathVerified, leg.assumed], ["boat-west-far", false, true, ["factions"]]);
  assert.strictEqual(travelPlan(unsure.db, unsure.graph, alliance(), from, to, { verifiedOnly: true }).seconds, Infinity);
  // without the zeppelin the Horde cannot cross: the boat is not theirs
  const none = fixture((src) => { src.transports.links.splice(1, 1); });
  assert.deepStrictEqual(travelPlan(none.db, none.graph, horde(), from, to), { legs: [], seconds: Infinity });
});
test("fixture, off the isle: one way, from the required level, and only with the quest", () => {
  const { db, graph, P } = fixture();
  const from = P(500, 20, 20), to = P(100, 50, 20);
  const ready = (level = 7) => alliance([], { level, quests: new Set([77]) });
  const plan = travelPlan(db, graph, ready(), from, to);
  assert.deepStrictEqual(actions(plan), ["walk", "transport", "walk"]);
  assert.strictEqual(plan.legs[1].link, "sky");
  assert.deepStrictEqual(plan.legs[1].requires, { level: 7, quest: 77 });
  checkPlan(graph, ready(), from, to, plan);
  assert.strictEqual(travelPlan(db, graph, ready(6), from, to).seconds, Infinity);
  assert.strictEqual(travelPlan(db, graph, horde([], { level: 7, quests: new Set([77]) }), from, to).seconds, Infinity);
  assert.strictEqual(travelPlan(db, graph, ready(60), to, from).seconds, Infinity, "there is no way back");
  // the quest is not in the character's set: no boarding, and the plan says which link stopped it
  const other = travelPlan(db, graph, alliance([], { level: 7, quests: new Set([78]) }), from, to);
  assert.deepStrictEqual(other, { legs: [], seconds: Infinity, blocked: [{ link: "sky", requires: { level: 7, quest: 77 } }] });
  assert.deepStrictEqual(travelPlan(db, graph, ready(6), from, to).blocked, [{ link: "sky", requires: { level: 7, quest: 77 } }]);
  // a caller that passes no quests at all (the plain state of the plan's contract) has no quest: it does not board either
  const plain = travelPlan(db, graph, alliance([], { level: 7 }), from, to);
  assert.deepStrictEqual(plain, { legs: [], seconds: Infinity, blocked: [{ link: "sky", requires: { level: 7, quest: 77 } }] });
  // a link that was never reached is not named: the Horde has no link on the isle, and a reachable place names none
  assert.strictEqual(travelPlan(db, graph, horde([], { level: 7 }), from, to).blocked, undefined);
  assert.strictEqual(plan.blocked, undefined);
});
test("fixture: the hearthstone is used when it is ready and saves time", () => {
  const { db, graph, P } = fixture();
  const from = P(100, 10, 50), to = P(200, 80, 52), inn = P(200, 80, 50);
  const state = alliance([], { hearth: inn });
  const plan = travelPlan(db, graph, state, from, to, { pickups: false });
  assert.deepStrictEqual(actions(plan), ["hearth", "walk"]);
  assert.ok(near(plan.seconds, E.HEARTH_SECONDS + walkTime(20)));
  checkPlan(graph, state, from, to, plan);
  assert.ok(!actions(travelPlan(db, graph, alliance([], { hearth: inn, hearthReady: false }), from, to)).includes("hearth"));
  assert.ok(!actions(travelPlan(db, graph, alliance(), from, to)).includes("hearth"));
  // not for a place nearer than the inn
  assert.deepStrictEqual(actions(travelPlan(db, graph, state, from, P(100, 12, 50), { pickups: false })), ["walk"]);
  // it crosses continents
  const far = alliance([], { hearth: P(400, 50, 50) });
  assert.deepStrictEqual(actions(travelPlan(db, graph, far, from, P(400, 50, 52), { pickups: false })), ["hearth", "walk"]);
});
test("fixture: zones joined only to each other cannot be walked to; a zone without any pass is a straight-line guess", () => {
  const { db, graph, P } = fixture();
  assert.strictEqual(walkYards(graph, P(100, 50, 50), P(300, 50, 50)), null);
  assert.strictEqual(walkSeconds(graph, 10, P(100, 50, 50), P(300, 50, 50)), Infinity);
  assert.strictEqual(travelPlan(db, graph, alliance(), P(100, 50, 50), P(300, 50, 50)).seconds, Infinity);
  assert.ok(near(walkYards(graph, P(300, 50, 50), P(301, 50, 50)).yards, 1000));
  assert.strictEqual(walkYards(graph, P(100, 50, 50), P(400, 50, 50)), null, "another continent");
  const guess = walkYards(graph, P(200, 50, 50), P(600, 50, 50));
  assert.deepStrictEqual([Math.round(guess.yards), guess.guess], [1000, true]);
  const plan = travelPlan(db, graph, horde(), P(200, 50, 50), P(600, 50, 50), { pickups: false });
  assert.deepStrictEqual(actions(plan), ["travel"]);
  assert.strictEqual(plan.legs[0].guess, true);
  assert.ok(graph.notes.some((t) => t.includes("600") && t.includes("no pass")));
});
test("fixture: walks in a row that a guess joined are kept apart when the whole cannot be walked", () => {
  // a dock in Uncharted, which has no pass: from the Isle (joined to Isle Town only) it is a straight-line guess, and so
  // is the way on to Westland; the Isle to Westland as one walk does not exist
  const { db, graph, P } = fixture((src) => {
    src.transports.links.push({ id: "boat-uncharted-far", kind: "boat", name: "Uncharted to Far", a: { zone: 600, x: 50, y: 30 }, b: { zone: 400, x: 90, y: 90 },
      factions: ["Alliance"], verified: false, assumed: ["route"], seconds: 5000 });
  });
  const from = P(300, 50, 50), to = P(100, 50, 70), dock = P(600, 50, 30);
  assert.strictEqual(walkYards(graph, from, to), null);
  assert.deepStrictEqual([walkYards(graph, from, dock).guess, walkYards(graph, dock, to).guess], [true, true]);
  const plain = travelPlan(db, graph, alliance(), from, to, { pickups: false });
  assert.deepStrictEqual(plain.legs.map((l) => [l.action, l.guess, l.at.zone]), [["travel", true, 600], ["travel", true, 100]]);
  assert.ok(near(plain.seconds, walkTime(dist2(from, dock) + dist2(dock, to))));
  checkPlan(graph, alliance(), from, to, plain);
  // the same with flight points picked up on the way
  const plan = travelPlan(db, graph, alliance(), from, to);
  checkPlan(graph, alliance(), from, to, plan);
  assert.deepStrictEqual([plan.legs[0].action, plan.legs[0].guess, plan.legs[0].at.zone], ["travel", true, 600]);
  assert.ok(!actions(plan).includes("transport"));
});
test("fixture: walks in a row are one walk only when that is no longer than its parts", () => {
  // a Horde dock in Eastland, 20 yards behind the border and 300 yards north of the pass
  const { db, graph, P } = fixture((src) => {
    src.transports.links.push({ id: "zeppelin-east-far", kind: "zeppelin", name: "East to Far", a: { zone: 200, x: 2, y: 20 }, b: { zone: 400, x: 90, y: 90 },
      factions: ["Horde"], verified: false, assumed: ["route"], seconds: 5000 });
  });
  const from = P(100, 98, 20), dock = P(200, 2, 20), to = P(200, 60, 20);
  // the start to the dock is 40 yards straight over the border, the dock to the destination 580 in one zone; the
  // start to the destination is over NEAR_BORDER apart, so as one walk it goes through the pass and is longer
  const whole = walkYards(graph, from, to).yards;
  assert.ok(whole > 620 + 100, `${whole}`);
  const plan = travelPlan(db, graph, horde(), from, to, { pickups: false });
  assert.deepStrictEqual(actions(plan), ["travel", "walk"]);
  assert.ok(near(plan.legs[0].yards, 40) && near(plan.legs[1].yards, 580));
  assert.ok(near(plan.seconds, walkTime(620)), "the plan costs what the search found, not the longer walk through the pass");
  assert.ok(Math.hypot(plan.legs[0].at.wx - dock.wx, plan.legs[0].at.wy - dock.wy) < 1);
  checkPlan(graph, horde(), from, to, plan);
  // without the dock there is no place to cross at: through the pass
  const plain = fixture();
  const a = travelPlan(plain.db, plain.graph, horde(), from, to, { pickups: false });
  assert.deepStrictEqual(actions(a), ["travel"]);
  assert.ok(near(a.legs[0].yards, whole) && near(a.seconds, walkTime(whole)));
  // walks in a row that are shorter as one walk stay one walk: past the Alliance dock in Westland to a place behind it
  const one = travelPlan(db, graph, alliance(), P(100, 50, 50), P(100, 50, 95), { pickups: false });
  assert.deepStrictEqual(actions(one), ["walk"]);
  assert.ok(near(one.legs[0].yards, 450));
});
test("fixture: two places close together across a border are walked straight, not through the pass", () => {
  const { graph, P } = fixture();
  // 40 yards apart, 300 yards north of the pass
  assert.ok(near(walkYards(graph, P(100, 98, 20), P(200, 2, 20)).yards, 40));
  // further apart than NEAR_BORDER: through the pass
  const a = P(100, 60, 20), b = P(200, 40, 20);
  assert.ok(dist2(a, b) > E.NEAR_BORDER);
  assert.ok(near(walkYards(graph, a, b).yards, 2 * Math.hypot(400, 300)));
});
test("fixture: toSteps writes format 2 steps and leaves out the walking inside a zone", () => {
  const { db, graph, P } = fixture();
  const state = alliance([1, 2], { hearth: P(100, 20, 50) });
  // hearth to node 1's inn is not worth it here; build a plan with every kind of leg from two trips
  const legs = [
    ...travelPlan(db, graph, state, P(100, 20.5, 50), P(200, 80.5, 50)).legs,                  // travel, getflight, fly
    ...travelPlan(db, graph, alliance(), P(200, 80.5, 50), P(400, 50, 50), { pickups: false }).legs, // travel, transport, walk
    ...travelPlan(db, graph, state, P(400, 50, 50), P(100, 20, 50), { pickups: false }).legs,  // hearth
  ];
  assert.deepStrictEqual(toSteps(legs), [
    { action: "travel", at: { zone: 200, x: 30.5, y: 50 } },
    { action: "getflight", node: 3, at: { zone: 200, x: 30.5, y: 50 }, npc: 903 },
    { action: "fly", from: 3, to: 2, at: { zone: 200, x: 30.5, y: 50 } },
    { action: "travel", at: { zone: 100, x: 50, y: 90 } },
    { action: "transport", kind: "boat", at: { zone: 100, x: 50, y: 90 }, to: { zone: 400, x: 50, y: 10 } },
    { action: "hearth", to: { zone: 100, x: 20, y: 50 } },
  ]);
});
test("fixture: no plan flies through a node the character has not learned, whatever is known", () => {
  const { db, graph, P } = fixture();
  const places = [P(100, 20.5, 50), P(100, 50, 50), P(100, 90, 10), P(200, 30.5, 50), P(200, 80.5, 50), P(200, 50, 10), P(400, 50.5, 50), P(400, 90.5, 50), P(400, 10.5, 10)];
  const sets = [[], [1], [1, 3], [1, 2], [1, 2, 3], [2, 3, 10], [6], [6, 7], [1, 6, 7, 11], [4], [4, 5], [5, 6, 7]];
  let flights = 0;
  for (const faction of ["Alliance", "Horde"]) for (const set of sets) for (const from of places) for (const to of places) {
    const state = { faction, level: 20, flights: new Set(set.filter((id) => graph.nodes.get(id).factions.includes(faction))), hearth: null };
    const plan = travelPlan(db, graph, state, from, to);
    checkPlan(graph, state, from, to, plan);
    flights += plan.legs.filter((l) => l.action === "fly").length;
    if (!state.flights.size) assert.ok(!actions(plan).includes("fly"), "nothing learned, nothing flown");
  }
  assert.ok(flights > 50, "the check saw flights");
});
test("fixture: pointAt is the inverse of toPoint", () => {
  const db = world();
  const p = toPoint(db, 200, 12.5, 80);
  const q = pointAt(db, 200, p.wx, p.wy);
  assert.deepStrictEqual([q.zone, q.x, q.y, q.wx, q.wy, q.continent], [200, 12.5, 80, p.wx, p.wy, 0]);
  assert.strictEqual(pointAt(db, 9999, 0, 0), null);
});

// ---------------------------------------------------------------------------------------------------------------
// planner/transports.json: the shape of every entry (no fetched data needed)
test("transports.json: every link has two ends, a kind, its factions and verified; every pass is unverified", () => {
  const ids = new Set();
  for (const l of TRANSPORTS.links) {
    assert.ok(typeof l.id === "string" && !ids.has(l.id), `link id ${l.id} is unique`);
    ids.add(l.id);
    assert.ok(["zeppelin", "boat", "tram", "portal"].includes(l.kind), `${l.id} kind`);
    for (const end of [l.a, l.b]) {
      assert.ok(Number.isInteger(end.zone) && end.zone > 0, `${l.id} zone`);
      for (const v of [end.x, end.y]) assert.ok(typeof v === "number" && v >= 0 && v <= 100, `${l.id} percent`);
    }
    assert.ok(Array.isArray(l.factions) && l.factions.length > 0 && l.factions.every((f) => f === "Alliance" || f === "Horde"), `${l.id} factions`);
    assert.strictEqual(typeof l.verified, "boolean", `${l.id} verified`);
    if (l.verified) assert.ok(Number.isInteger(l.path), `${l.id} is verified by a client path`);
    if (!l.path) assert.ok(l.seconds > 0, `${l.id} has its own time`);
    // verified covers the whole link. What is hand-written without a fact behind it is named in 'assumed', and a link
    // that names anything is not verified
    const assumed = l.assumed || [];
    assert.ok(Array.isArray(assumed) && assumed.every((a) => ASSUMABLE.includes(a)) && new Set(assumed).size === assumed.length, `${l.id} assumed`);
    assert.strictEqual(l.verified, assumed.length === 0, `${l.id}: verified exactly when nothing is assumed`);
    if (!l.path) assert.ok(assumed.includes("route"), `${l.id} has no client path: its route is assumed`);
    // a note that itself says something is assumed or unconfirmed cannot stand under verified = true
    if (l.verified) assert.ok(!/assum|not confirmed|unconfirmed|not known|not verified/i.test(l.note || ""), `${l.id} is verified, but its note names an assumption`);
    // the original game's transport paths have IDs below 1,000; Forever's own start at 11,000. For those there is no
    // public game fact about who may board or under which conditions, so something about them is always assumed
    if (l.path >= 10000) assert.ok(!l.verified && (assumed.includes("factions") || assumed.includes("boarding")), `${l.id} is a Forever route: who may board is not a public fact`);
  }
  const assumedOf = (id) => TRANSPORTS.links.find((l) => l.id === id).assumed;
  assert.deepStrictEqual(assumedOf("boat-steamwheedle-powderfuse"), ["factions"]);
  assert.deepStrictEqual(assumedOf("boat-stormwind-auberdine"), ["factions"]);
  assert.deepStrictEqual(assumedOf("boat-menethil-auberdine"), ["route"]);
  assert.deepStrictEqual(assumedOf("tram-stormwind-ironforge"), ["route"]);
  for (const id of ["skycutter-zephras-dalaran", "skycutter-zephras-mulgore"]) assert.deepStrictEqual(assumedOf(id), ["boarding", "arrival", "kind"]);
  assert.deepStrictEqual(TRANSPORTS.links.filter((l) => l.verified).map((l) => l.id), ["zeppelin-orgrimmar-undercity", "zeppelin-orgrimmar-gromgol", "zeppelin-undercity-gromgol",
    "boat-ratchet-bootybay", "boat-menethil-theramore", "boat-auberdine-rutheran", "boat-feathermoon-ferry"]);
  assert.ok(TRANSPORTS.passes.length > 40);
  for (const p of TRANSPORTS.passes) {
    assert.strictEqual(p.verified, false);
    assert.ok(["map", "spawns"].includes(p.source));
    assert.ok(p.at.zone === p.a || p.at.zone === p.b, `pass ${p.a}-${p.b} is placed in one of its zones`);
  }
  for (const id of ["tram-stormwind-ironforge", "skycutter-zephras-dalaran", "skycutter-zephras-mulgore", "zeppelin-orgrimmar-undercity", "boat-menethil-theramore"]) assert.ok(ids.has(id), id);
  const sky = TRANSPORTS.links.filter((l) => l.id.startsWith("skycutter"));
  assert.ok(sky.every((l) => l.oneWay === true && l.requires.level === 7 && l.a.zone === 16593));
  assert.strictEqual(TRANSPORTS.links.find((l) => l.id === "tram-stormwind-ironforge").verified, false);
});

// ---------------------------------------------------------------------------------------------------------------
// The fetched client data
let cache;
function realWorld() {
  if (!cache) {
    const db = loadDb(DATA);
    cache = { db, graph: loadTravel(db, DATA), P: (z, x, y) => toPoint(db, z, x, y) };
  }
  return cache;
}
const wago = (name) => readCsv(path.join(DATA, "wago", `${name}.csv`));

test("real data: flight nodes carry the faction, zone and flight master the data gives them", { skip: !real }, () => {
  const { db, graph } = realWorld();
  const n = (id) => graph.nodes.get(id);
  assert.deepStrictEqual([n(25).factions, n(25).npc, n(25).point.zone], [["Horde"], 3615, 17]);           // Crossroads, Devrak
  assert.deepStrictEqual([n(2).factions, n(2).npc, n(2).point.zone], [["Alliance"], 352, 1519]);          // Stormwind, Dungar Longdrink
  assert.deepStrictEqual([n(80).factions, n(80).npc], [["Alliance", "Horde"], 16227]);                    // Ratchet, Bragok
  assert.deepStrictEqual([n(79).factions, n(79).npc], [["Alliance", "Horde"], 10583]);                    // Marshal's Refuge, Gryfe
  assert.deepStrictEqual([n(67).npc, n(68).npc], [12617, 12636]);                                         // Light's Hope: one node and one master per faction
  assert.deepStrictEqual([n(3276).factions, n(3276).npc, n(3276).point.zone], [["Alliance"], 257087, 16591]); // Farholde Keep
  assert.deepStrictEqual([n(3203).factions, n(3203).npc, n(3203).point.zone], [["Horde"], 255993, 16591]);    // Rog'mar
  // transport nodes, unused nodes, battleground nodes, the druid-only Nighthaven nodes, the towers, quest paths, the isle's own
  for (const id of [1, 3, 9, 15, 24, 34, 35, 36, 46, 47, 50, 51, 54, 57, 59, 60, 62, 63, 78, 84, 85, 86, 87, 2913, 3205, 3206, 3207, 3208, 3260, 3274, 3275, 3361]) assert.ok(!graph.nodes.has(id), `node ${id}`);
  // 65 nodes: 33 for the Alliance only, 30 for the Horde only, 2 for both (Ratchet and Marshal's Refuge). The client
  // flags 4 for both; the two on Mount Hyjal (559, 3242) have only an Alliance flight master and count as Alliance
  assert.strictEqual(graph.nodes.size, 65);
  const usedBy = (...factions) => [...graph.nodes.values()].filter((x) => x.factions.join() === factions.join()).map((x) => x.id).sort((a, b) => a - b);
  assert.deepStrictEqual([usedBy("Alliance").length, usedBy("Horde").length, usedBy("Alliance", "Horde")], [33, 30, [79, 80]]);
  assert.deepStrictEqual([...graph.nodes.values()].filter((x) => x.flagged.length === 2).map((x) => x.id).sort((a, b) => a - b), [79, 80, 559, 3242]);
  for (const node of graph.nodes.values()) {
    assert.ok(node.factions.length > 0, `node ${node.id} has a faction`);
    assert.ok(db.maps.has(node.point.zone), `node ${node.id} is on a zone map`);
    assert.ok([0, 1].includes(node.point.continent), `node ${node.id} is on a continent`);
    assert.ok(node.npc > 0, `node ${node.id} has a flight master`);
    // the flight master stands at the node
    assert.ok(Math.hypot(node.point.wx - node.wx, node.point.wy - node.wy) < 40, `node ${node.id} ${node.name}`);
    const out = graph.edges.get(node.id) || [];
    assert.ok(out.length > 0, `node ${node.id} has a path out`);
    for (const e of out) {
      const other = graph.nodes.get(e.to);
      assert.ok(other, `edge ${node.id} to ${e.to} ends at a usable node`);
      assert.ok(node.factions.some((f) => other.factions.includes(f)), `edge ${node.id} to ${e.to} joins nodes of one faction`);
      assert.ok(e.seconds > 10 && e.seconds < 900, `edge ${node.id} to ${e.to}: ${e.seconds} s`);
      assert.ok(!e.estimated, `edge ${node.id} to ${e.to} has path nodes`);
      assert.ok(e.yards >= Math.hypot(node.wx - other.wx, node.wy - other.wy) * 0.95, `edge ${node.id} to ${e.to} is not shorter than the straight line`);
    }
  }
  // Stormwind to Ironforge is 7,757 yards of path for 4,331 in a straight line
  const e = graph.edges.get(2).find((x) => x.to === 6);
  assert.strictEqual(Math.round(e.yards), 7757);
  assert.ok(near(e.seconds, e.yards / E.FLIGHT_SPEED));
});
test("real data: the Mount Hyjal nodes are flagged for both factions but only an Alliance flight master is in the data", { skip: !real }, () => {
  const { graph } = realWorld();
  for (const id of [559, 3242]) {
    assert.deepStrictEqual(graph.nodes.get(id).factions, ["Alliance"]);
    assert.ok(graph.notes.some((t) => t.includes(`node ${id}`) && t.includes("Horde")), `node ${id} is in the notes`);
  }
  // every other node's flags and flight masters agree
  assert.deepStrictEqual(graph.notes.filter((t) => t.startsWith("node ")).length, 2);
});
test("real data: every verified link is a client transport path that stops at both ends", { skip: !real }, () => {
  const { graph } = realWorld();
  const pathNodes = wago("TaxiPathNode");
  for (const link of graph.links) {
    assert.ok(link.secondsAB > 30 && link.secondsAB < 900, `${link.id}: ${link.secondsAB} s`);
    if (!link.oneWay) assert.ok(link.secondsBA > 30 && link.secondsBA < 900, `${link.id} back: ${link.secondsBA} s`);
    assert.strictEqual(link.verified, link.assumed.length === 0, `${link.id}: verified exactly when nothing is assumed`);
    if (!link.pathVerified) { assert.ok(!link.verified, link.id); continue; }
    const stops = pathNodes.filter((n) => +n.PathID === link.path && (+n.Flags & 2) === 2);
    assert.ok(stops.length >= 2, `${link.id}: path ${link.path} has stops`);
    for (const end of [link.a, link.b]) {
      const d = Math.min(...stops.filter((s) => +s.ContinentID === end.continent).map((s) => Math.hypot(+s.Loc_0 - end.wx, +s.Loc_1 - end.wy)));
      assert.ok(d < 60, `${link.id}: the nearest stop of path ${link.path} is ${Math.round(d)} yards from the end in zone ${end.zone}`);
    }
    assert.ok(link.loopSeconds > 120 && link.loopSeconds < 900, `${link.id} loop: ${link.loopSeconds} s`);
  }
  assert.strictEqual(graph.links.filter((l) => l.verified).length, TRANSPORTS.links.filter((l) => l.verified).length);
  // the path is confirmed for these, something else about them is not
  assert.deepStrictEqual(graph.links.filter((l) => l.pathVerified && !l.verified).map((l) => l.id),
    ["boat-stormwind-auberdine", "boat-steamwheedle-powderfuse", "skycutter-zephras-dalaran", "skycutter-zephras-mulgore"]);
  assert.deepStrictEqual(graph.links.filter((l) => !l.pathVerified).map((l) => l.id), ["boat-menethil-auberdine", "tram-stormwind-ironforge", "portal-dalaran-stormwind"]);
  // Undercity to Grom'gol: the path jumps from Stranglethorn to Tirisfal, and the jump is not flown
  const zep = graph.links.find((l) => l.id === "zeppelin-undercity-gromgol");
  assert.ok(zep.loopSeconds < 400, `${zep.loopSeconds}`);
});
test("real data: the tram's ends are the client's area triggers, and its time fits the client's tram animation", { skip: !real }, () => {
  const { graph } = realWorld();
  const tram = graph.links.find((l) => l.id === "tram-stormwind-ironforge");
  const raw = TRANSPORTS.links.find((l) => l.id === "tram-stormwind-ironforge");
  const triggers = new Map(wago("AreaTrigger").map((t) => [+t.ID, t]));
  const [sw, ironforge] = raw.evidence.areaTriggers.map((id) => triggers.get(id));
  assert.ok(Math.hypot(+sw.Pos_0 - tram.a.wx, +sw.Pos_1 - tram.a.wy) < 15 && +sw.ContinentID === 0);
  assert.ok(Math.hypot(+ironforge.Pos_0 - tram.b.wx, +ironforge.Pos_1 - tram.b.wy) < 15 && +ironforge.ContinentID === 0);
  const map = wago("Map").find((m) => +m.ID === raw.evidence.map);
  assert.strictEqual(map.MapName_lang, "Deeprun Tram");
  assert.ok(Math.hypot(+map.Corpse_0 - tram.a.wx, +map.Corpse_1 - tram.a.wy) < 15, "the tram map's entrance is the Stormwind end");
  const frames = wago("TransportAnimation").filter((f) => +f.TransportID === raw.evidence.transport);
  const loop = Math.max(...frames.map((f) => +f.TimeIndex)) / 1000;
  assert.ok(near(loop, 143.333, 0.01));
  assert.ok(raw.seconds >= loop / 2 && raw.seconds <= loop * 1.25, "between a ride without waiting and a ride after a full wait");
});
test("real data: the Skyborne skycutters leave from the docks P1 found and arrive beside the quest's turn-in", { skip: !real }, () => {
  const { db, graph } = realWorld();
  const { spawnPoints } = require("../lib/geo");
  const dist = (a, b) => Math.hypot(a.wx - b.wx, a.wy - b.wy);
  const cases = [["skycutter-zephras-dalaran", 716301, 259084, 94946, "Alliance"], ["skycutter-zephras-mulgore", 716302, 259119, 95349, "Horde"]];
  for (const [id, portal, turnin, quest, faction] of cases) {
    const link = graph.links.find((l) => l.id === id);
    assert.deepStrictEqual([link.factions, link.oneWay, link.requires.quest, link.a.continent], [[faction], true, quest, 2991]);
    assert.ok(Math.min(...spawnPoints(db, "object", portal).map((p) => dist(p, link.a))) < 60, `${id} leaves from the dock`);
    assert.ok(Math.min(...spawnPoints(db, "npc", turnin).map((p) => dist(p, link.b))) < 250, `${id} arrives by the turn-in NPC`);
    assert.ok(db.quests.get(quest).ends.npcs.includes(turnin));
  }
});
test("real data: every pass lies on the border of the two zones it joins", { skip: !real }, () => {
  const { db } = realWorld();
  for (const p of TRANSPORTS.passes) {
    const label = `pass ${p.a}-${p.b}`;
    const a = db.areas.get(p.a), b = db.areas.get(p.b);
    assert.ok(a && b && db.maps.has(p.a) && db.maps.has(p.b), `${label}: both zones have a map`);
    assert.strictEqual(a.continent, b.continent, `${label}: one continent`);
    const at = toPoint(db, p.at.zone, p.at.x, p.at.y);
    for (const zone of [p.a, p.b]) {
      const q = pointAt(db, zone, at.wx, at.wy);
      assert.ok(q.x >= -10 && q.x <= 110 && q.y >= -10 && q.y <= 110, `${label}: ${q.x.toFixed(1)}, ${q.y.toFixed(1)} is not on the map of zone ${zone}`);
    }
  }
});
test("real data: the mainland of each continent is joined on foot, islands and other continents are not", { skip: !real }, () => {
  const { db, graph, P } = realWorld();
  const mid = (zone) => P(zone, 50, 50);
  const eastern = [1, 3, 4, 8, 10, 11, 12, 28, 33, 36, 38, 40, 41, 44, 45, 46, 47, 51, 85, 130, 139, 267, 1497, 1519, 1537, 16591];
  const kalimdor = [14, 15, 16, 17, 148, 215, 331, 357, 361, 400, 405, 406, 440, 490, 493, 618, 1377, 1637, 1638, 616, 16651];
  for (const set of [eastern, kalimdor]) for (const zone of set) {
    const w = walkYards(graph, mid(set[0]), mid(zone));
    assert.ok(w && Number.isFinite(w.yards) && !w.guess, `${db.areas.get(zone).name} is joined to ${db.areas.get(set[0]).name}`);
  }
  assert.strictEqual(walkYards(graph, mid(141), mid(148)), null, "Teldrassil is an island");
  assert.ok(walkYards(graph, mid(141), mid(1657)), "Darnassus is on it");
  assert.strictEqual(walkYards(graph, mid(12), mid(14)), null);
  assert.strictEqual(walkYards(graph, mid(16593), mid(36)), null);
  // a walk around the mountains is longer than the straight line: Menethil Harbor to Ironforge's gates
  const menethil = P(11, 10, 58), gates = P(1, 53.5, 35);
  assert.ok(walkYards(graph, menethil, gates).yards > 2 * Math.hypot(menethil.wx - gates.wx, menethil.wy - gates.wy));
  // every zone map on the two continents is in the pass table, so no walk there is a guess
  assert.deepStrictEqual(graph.notes.filter((t) => t.includes("no pass")), []);
});

const A = (level, flights = [], more = {}) => ({ faction: "Alliance", level, flights: new Set(flights), hearth: null, ...more });
const H = (level, flights = [], more = {}) => ({ faction: "Horde", level, flights: new Set(flights), hearth: null, ...more });

test("real data, same zone: Goldshire to Northshire is one walk", { skip: !real }, () => {
  const { db, graph, P } = realWorld();
  const from = P(12, 42.1, 65.9), to = P(12, 48.2, 42.9);
  const plan = travelPlan(db, graph, A(5), from, to);
  assert.deepStrictEqual(actions(plan), ["walk"]);
  assert.ok(plan.seconds > 60 && plan.seconds < 300, `${plan.seconds}`);
  checkPlan(graph, A(5), from, to, plan);
});
test("real data, same continent: on foot without a flight, by air with one", { skip: !real }, () => {
  const { db, graph, P } = realWorld();
  const from = P(1519, 62, 70), to = P(44, 31, 58); // Stormwind's Trade District to Lakeshire
  const foot = travelPlan(db, graph, A(18), from, to);
  assert.ok(!actions(foot).includes("fly") && actions(foot).includes("travel"));
  const learned = checkPlan(graph, A(18), from, to, foot);
  assert.ok(learned.has(5), "Lakeshire's flight point is learned on arrival");
  const air = travelPlan(db, graph, A(18, [2, 5]), from, to);
  const fly = air.legs.find((l) => l.action === "fly");
  assert.deepStrictEqual([fly.from, fly.to], [2, 5]);
  assert.ok(air.seconds < foot.seconds / 2, `${air.seconds} against ${foot.seconds}`);
  checkPlan(graph, A(18, [2, 5]), from, to, air);
  // the Horde side: Crossroads to Camp Taurajo's flight master, both learned
  const h = travelPlan(db, graph, H(20, [25, 77]), graph.nodes.get(25).point, graph.nodes.get(77).point);
  assert.deepStrictEqual(actions(h), ["fly"]);
  assert.deepStrictEqual([h.legs[0].from, h.legs[0].via, h.legs[0].to], [25, [], 77]);
  // a Horde character never uses the Alliance's nodes, even with their IDs in its list
  const cheat = travelPlan(db, graph, H(18, [2, 5]), from, to);
  assert.ok(!actions(cheat).includes("fly"));
});
test("real data, another continent: the Alliance sails, the Horde takes the zeppelin", { skip: !real }, () => {
  const { db, graph, P } = realWorld();
  let from = P(1519, 62, 70), to = P(148, 37, 44); // Stormwind to Auberdine
  let plan = travelPlan(db, graph, A(20), from, to);
  assert.deepStrictEqual(plan.legs.filter((l) => l.action === "transport").map((l) => l.link), ["boat-stormwind-auberdine"]);
  checkPlan(graph, A(20), from, to, plan);
  from = P(1637, 50, 65); to = P(85, 61, 52); // Orgrimmar to Brill
  plan = travelPlan(db, graph, H(12), from, to);
  assert.deepStrictEqual(plan.legs.filter((l) => l.action === "transport").map((l) => l.link), ["zeppelin-orgrimmar-undercity"]);
  assert.ok(plan.seconds > 240 && plan.seconds < 900, `${plan.seconds}`);
  checkPlan(graph, H(12), from, to, plan);
  // the Horde to Booty Bay from the Crossroads, the Alliance from Theramore to Menethil
  from = P(17, 52, 30); to = P(33, 27, 77);
  plan = travelPlan(db, graph, H(30), from, to);
  assert.ok(plan.legs.some((l) => l.action === "transport"));
  checkPlan(graph, H(30), from, to, plan);
  from = P(15, 66, 48); to = P(11, 10, 58);
  plan = travelPlan(db, graph, A(35), from, to);
  assert.deepStrictEqual(plan.legs.filter((l) => l.action === "transport").map((l) => l.link), ["boat-menethil-theramore"]);
  checkPlan(graph, A(35), from, to, plan);
  // Teldrassil is left by boat (or by the Rut'theran flight once Auberdine is learned)
  from = P(141, 56, 60); to = P(148, 37, 44);
  plan = travelPlan(db, graph, A(11), from, to);
  assert.deepStrictEqual(plan.legs.filter((l) => l.action === "transport").map((l) => l.link), ["boat-auberdine-rutheran"]);
  checkPlan(graph, A(11), from, to, plan);
  plan = travelPlan(db, graph, A(11, [26, 27]), from, to);
  assert.deepStrictEqual(plan.legs.filter((l) => l.action === "fly").map((l) => [l.from, l.to]), [[27, 26]]);
  // Dun Morogh to Elwynn goes by tram
  from = P(1, 46.7, 52.5); to = P(12, 42.1, 65.9);
  plan = travelPlan(db, graph, A(10), from, to);
  assert.deepStrictEqual(plan.legs.filter((l) => l.action === "transport").map((l) => [l.link, l.kind, l.verified]), [["tram-stormwind-ironforge", "tram", false]]);
  checkPlan(graph, A(10), from, to, plan);
});
test("real data: a leg on a link with an assumption says so, and verifiedOnly plans without such links", { skip: !real }, () => {
  const { db, graph, P } = realWorld();
  // the Forever boat between the goblin ports: the path is in the client, who may board is assumed for both factions
  const port = P(440, 67, 24), powderfuse = P(16591, 79, 54);
  for (const state of [A(45), H(45)]) {
    const plan = travelPlan(db, graph, state, port, powderfuse, { pickups: false });
    const legs = plan.legs.filter((l) => l.action === "transport");
    assert.deepStrictEqual(legs.map((l) => [l.link, l.verified, l.pathVerified, l.assumed]), [["boat-steamwheedle-powderfuse", false, true, ["factions"]]]);
    checkPlan(graph, state, port, powderfuse, plan);
    // the route stays playable without it: Riverglades is entered on foot from the Burning Steppes
    const sure = travelPlan(db, graph, state, port, powderfuse, { pickups: false, verifiedOnly: true });
    checkPlan(graph, state, port, powderfuse, sure, { verifiedOnly: true });
    assert.ok(sure.legs.some((l) => l.action === "transport") && sure.seconds > plan.seconds, `${sure.seconds} against ${plan.seconds}`);
  }
  // Stormwind to Auberdine: the Forever boat is assumed to be the Alliance's; without it (and without the unverified
  // Menethil to Auberdine boat) the way is on foot to Booty Bay, the boat to Ratchet, and on foot again
  const from = P(1519, 62, 70), to = P(148, 37, 44);
  const boat = travelPlan(db, graph, A(20), from, to).legs.find((l) => l.action === "transport");
  assert.deepStrictEqual([boat.link, boat.verified, boat.pathVerified, boat.assumed], ["boat-stormwind-auberdine", false, true, ["factions"]]);
  const sure = travelPlan(db, graph, A(20), from, to, { verifiedOnly: true });
  checkPlan(graph, A(20), from, to, sure, { verifiedOnly: true });
  assert.deepStrictEqual(sure.legs.filter((l) => l.action === "transport").map((l) => l.link), ["boat-ratchet-bootybay"]);
  assert.ok(sure.seconds > travelPlan(db, graph, A(20), from, to).seconds);
  // the skycutters are the only way off the isle and not verified: with confirmed facts only there is no way
  const isle = P(16593, 60, 60);
  const sky = travelPlan(db, graph, A(7, [], { quests: new Set([94946]) }), isle, from).legs.find((l) => l.action === "transport");
  assert.deepStrictEqual([sky.verified, sky.pathVerified, sky.assumed], [false, true, ["boarding", "arrival", "kind"]]);
  assert.strictEqual(travelPlan(db, graph, A(7, [], { quests: new Set([94946]) }), isle, from, { verifiedOnly: true }).seconds, Infinity);
});
test("real data, off Zephras Isle: each Skyborne race leaves by its skycutter from level 7 with its quest, and nobody goes back", { skip: !real }, () => {
  const { db, graph, P } = realWorld();
  const isle = P(16593, 60, 60), stormwind = P(1519, 62, 70), bluff = P(1638, 45, 60);
  const highOrder = (level) => A(level, [], { quests: new Set([94946]) }), windshaper = (level) => H(level, [], { quests: new Set([95349]) });
  let plan = travelPlan(db, graph, highOrder(7), isle, stormwind);
  assert.strictEqual(plan.legs.find((l) => l.action === "transport").link, "skycutter-zephras-dalaran");
  assert.strictEqual(plan.legs.find((l) => l.action === "transport").to.zone, 36);
  assert.deepStrictEqual(plan.legs.find((l) => l.action === "transport").requires, { level: 7, quest: 94946 });
  checkPlan(graph, highOrder(7), isle, stormwind, plan);
  assert.strictEqual(travelPlan(db, graph, highOrder(6), isle, stormwind).seconds, Infinity);
  plan = travelPlan(db, graph, windshaper(7), isle, bluff);
  assert.deepStrictEqual(plan.legs.filter((l) => l.action === "transport").map((l) => l.link), ["skycutter-zephras-mulgore"]);
  assert.ok(plan.seconds < 900, `${plan.seconds}`);
  checkPlan(graph, windshaper(7), isle, bluff, plan);
  for (const quest of [94946, 95349]) assert.ok(db.quests.has(quest), `quest ${quest} is in the data`);
  // a place on the isle is a walk; the mainland to the isle is not possible
  assert.deepStrictEqual(actions(travelPlan(db, graph, H(3), isle, P(16593, 40, 40))), ["walk"]);
  for (const state of [A(60), H(60)]) for (const from of [stormwind, bluff]) assert.strictEqual(travelPlan(db, graph, state, from, isle).seconds, Infinity);
  // the skycutter waits for its quest: not with the other race's quest, not with an empty set, and not for a caller
  // that passes no quests at all. The plan names the link that stopped it
  const stopped = [{ link: "skycutter-zephras-dalaran", requires: { level: 7, quest: 94946 } }];
  for (const more of [{ quests: new Set() }, { quests: new Set([95349]) }, {}]) {
    assert.deepStrictEqual(travelPlan(db, graph, A(7, [], more), isle, stormwind), { legs: [], seconds: Infinity, blocked: stopped });
  }
  assert.deepStrictEqual(travelPlan(db, graph, H(60), isle, bluff).blocked, [{ link: "skycutter-zephras-mulgore", requires: { level: 7, quest: 95349 } }]);
});
test("real data: no leg uses a flight that is not learned or a transport of the other faction", { skip: !real }, () => {
  const { db, graph, P } = realWorld();
  const places = [P(12, 42, 66), P(1519, 62, 70), P(40, 56, 47), P(44, 29, 46), P(1, 46.7, 52.5), P(11, 10, 58), P(45, 46, 46), P(33, 27, 77), P(139, 80, 58),
    P(14, 52, 42), P(1637, 50, 65), P(17, 52, 30), P(215, 47, 58), P(331, 35, 50), P(440, 51, 28), P(148, 37, 44), P(141, 56, 60), P(618, 61, 38), P(1377, 50, 36),
    P(85, 61, 52), P(130, 43, 41), P(16591, 60, 60), P(616, 55, 80)];
  const everyNode = (faction) => [...graph.nodes.values()].filter((n) => n.factions.includes(faction)).map((n) => n.id);
  const sets = { Alliance: [[], [2], [2, 4, 5, 6, 12], [6, 7, 8, 14, 16], [26, 27, 28, 32], everyNode("Alliance")], Horde: [[], [23], [22, 23, 25, 77], [10, 11, 13, 17, 21], [18, 20, 23, 25, 40], everyNode("Horde")] };
  let flown = 0, shipped = 0, learned = 0;
  for (const faction of ["Alliance", "Horde"]) for (const set of sets[faction]) for (const level of [10, 45]) {
    for (let i = 0; i < places.length; i++) for (let j = 0; j < places.length; j++) {
      if (i === j) continue;
      const state = { faction, level, flights: new Set(set), hearth: (i + j) % 5 === 0 ? places[(i + 7) % places.length] : null };
      const plan = travelPlan(db, graph, state, places[i], places[j]);
      // Teldrassil is reached by the Alliance's boat and flight only: the Horde gets there or away by hearthstone or not at all
      if (faction === "Horde" && (places[i].zone === 141) !== (places[j].zone === 141)) {
        if (!state.hearth) assert.strictEqual(plan.seconds, Infinity);
        if (plan.seconds === Infinity) continue;
        assert.strictEqual(plan.legs[0].action, "hearth");
      }
      checkPlan(graph, state, places[i], places[j], plan);
      if (!set.length) assert.ok(!plan.legs.some((l) => l.action === "fly"), "nothing learned, nothing flown");
      flown += plan.legs.filter((l) => l.action === "fly").length;
      shipped += plan.legs.filter((l) => l.action === "transport").length;
      learned += plan.legs.filter((l) => l.action === "getflight").length;
    }
  }
  assert.ok(flown > 1000 && shipped > 1000 && learned > 1000, `${flown} flights, ${shipped} transports, ${learned} flight points learned`);
});
test("real data: toSteps gives steps the route format accepts", { skip: !real }, () => {
  const { db, graph, P } = realWorld();
  const plan = travelPlan(db, graph, H(30, [23, 25]), P(17, 52, 30), P(85, 61, 52));
  const steps = toSteps(plan.legs);
  assert.ok(steps.length >= 2);
  for (const s of steps) {
    assert.ok(["travel", "getflight", "fly", "transport", "hearth"].includes(s.action));
    for (const p of [s.at, s.to].filter((v) => v && typeof v === "object")) {
      assert.deepStrictEqual(Object.keys(p), ["zone", "x", "y"]);
      assert.ok(db.maps.has(p.zone) && p.x >= 0 && p.x <= 100 && p.y >= 0 && p.y <= 100);
      assert.strictEqual(p.x, Math.round(p.x * 100) / 100);
    }
    if (s.action === "fly") assert.ok(graph.nodes.has(s.from) && graph.nodes.has(s.to) && s.at);
    if (s.action === "getflight") assert.ok(graph.nodes.has(s.node) && s.npc > 0 && s.at);
    if (s.action === "transport") assert.ok(["zeppelin", "boat", "tram", "portal"].includes(s.kind) && s.at && s.to);
  }
});
