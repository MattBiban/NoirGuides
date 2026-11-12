// Noir Guides, GPLv3. See LICENSE.
// Travel: how a character gets from one place to another, and how long it takes.
//   buildGraph / loadTravel  the flight graph (client tables TaxiNodes, TaxiPath, TaxiPathNode and the flight master
//                            NPCs of QuestieDB), the transport links and the passes between zones (both hand-written,
//                            planner/transports.json)
//   travelPlan               the fastest way for one character: walking, flights it has learned, flight points it
//                            passes, transports of its faction, and the hearthstone
//   toSteps                  the legs as route format 2 steps
// A place is a point as lib/geo.js makes it: { zone, x, y, wx, wy, continent }.
const fs = require("fs");
const path = require("path");
const { readCsv } = require("./csv");
const { toPoint } = require("./geo");

// Every number the times are estimated with, and where it comes from. None of them is in the fetched data unless the
// line says so; docs/routes/TRAVEL-NOTES.md repeats the list for the owner.
const ESTIMATES = Object.freeze({
  RUN_SPEED: 7,             // yards a second: a character's run speed in the original game
  MOUNT_LEVEL: 40,          // the level of the first mount in the original game; assumes the character buys it then
  MOUNT_SPEED: 11.2,        // run speed plus the first mount's 60%
  WALK_DETOUR: 1.25,        // roads and terrain against the straight line: a guess. The client's flight paths, which
                            // need no roads, are 1.36 times the straight line (see FLIGHT_PATH_RATIO)
  NEAR_BORDER: 500,         // yards: two places this close in neighbouring zones are walked straight (a river or an open
                            // border), not through the listed pass. A guess; the old planner used 1,500 for objectives
  FLIGHT_SPEED: 32,         // yards a second on a taxi mount: the figure open server projects use, not in the client data.
                            // It puts Stormwind to Ironforge (7,757 yards of path) at 4 minutes
  FLIGHT_PATH_RATIO: 1.36,  // measured: the median of path length over straight distance in the client's 314 taxi paths;
                            // only used for a path without TaxiPathNode rows (none today)
  BOARD_SECONDS: 10,        // talking to the flight master and taking off: a guess
  LEARN_SECONDS: 5,         // talking to a flight master to learn the point: a guess
  TRANSPORT_SPEED: 30,      // yards a second for boats and zeppelins: the server's setting in open server projects, not
                            // in the client data. It makes the Orgrimmar to Undercity loop about 5 minutes
  HEARTH_SECONDS: 15,       // the 10 second cast plus a loading screen
  PICKUP_SECONDS: 45,       // a flight point is picked up on the way when the detour costs no more than this: a choice
  FLIGHT_MASTER_YARDS: 40,  // a flight master belongs to a node when he stands this close to it (the widest real gap is 8)
  STOP_YARDS: 60,           // a link's end matches a transport path's stop within this distance: the stop is the ship's
                            // place in the water, the end is written to a tenth of a map percent
});
const E = ESTIMATES;
const FACTIONS = ["Alliance", "Horde"];
const FACTION_FLAG = { Alliance: 1, Horde: 2 }; // TaxiNodes.Flags: shown on the Alliance map, shown on the Horde map
const STOP = 2, TELEPORT = 1;                   // TaxiPathNode.Flags: the transport waits here; the next node is jumped to
// What a hand-written link may name in 'assumed', the list of what no fact stands behind:
//   route     that it runs between these two ends: no client transport path, or more than one, says so
//   factions  who may board
//   boarding  the conditions for boarding ('requires', 'oneWay')
//   arrival   the exact place it arrives at
//   kind      what it is (a ship, or a portal standing at the same dock)
const ASSUMABLE = Object.freeze(["route", "factions", "boarding", "arrival", "kind"]);
// QuestieDB npcFlags bit 8 is the flight master flag. Forever's own NPCs have no flags in the data, only the title.
const FLIGHT_MASTER_FLAG = 8;
const FLIGHT_MASTER_TITLE = /\b(Gryphon|Wind Rider|Hippogryph|Flight) (Master|Mistress)\b|\bBat Handler\b/;

const dist = (a, b) => Math.hypot(a.wx - b.wx, a.wy - b.wy);
const round2 = (n) => Math.round(n * 100) / 100;

// A world position as a point on a zone's map: the inverse of geo.toPoint.
function pointAt(db, zone, wx, wy) {
  const m = db.maps.get(zone);
  if (!m) return null;
  const area = db.areas.get(zone);
  return { zone, x: ((m.maxY - wy) / (m.maxY - m.minY)) * 100, y: ((m.maxX - wx) / (m.maxX - m.minX)) * 100, wx, wy, continent: area ? area.continent : -1 };
}
// The zone map a world position without a flight master is shown on: the zone its node is named after ("Thelsamar,
// Loch Modan") when the position is on that map, else the smallest map of the continent that contains it.
function zoneAt(db, continent, wx, wy, name) {
  const inside = [...db.maps.values()].filter((m) => (db.areas.get(m.area) || {}).continent === continent && wx >= m.minX && wx <= m.maxX && wy >= m.minY && wy <= m.maxY);
  const named = inside.find((m) => name.endsWith(", " + db.areas.get(m.area).name));
  if (named) return named.area;
  inside.sort((a, b) => (a.maxX - a.minX) * (a.maxY - a.minY) - (b.maxX - b.minX) * (b.maxY - b.minY) || a.area - b.area);
  return inside.length ? inside[0].area : 0;
}

// TaxiPathNode rows by path, in flying order, with the length of each stretch. A stretch into another continent or
// out of a teleport node is a jump and has no length; so is a transport's way from its last node back to its first
// (Undercity to Grom'gol ends in Tirisfal and starts in Stranglethorn, 14,000 yards apart on one continent).
function readPaths(rows) {
  const paths = new Map();
  for (const r of rows) {
    const id = +r.PathID;
    if (!paths.has(id)) paths.set(id, []);
    paths.get(id).push({ index: +r.NodeIndex, continent: +r.ContinentID, wx: +r.Loc_0, wy: +r.Loc_1, wz: +r.Loc_2, flags: +r.Flags, delay: +r.Delay });
  }
  for (const nodes of paths.values()) {
    nodes.sort((a, b) => a.index - b.index);
    nodes.forEach((n, i) => {
      const next = nodes[i + 1];
      n.next = next && n.continent === next.continent && !(n.flags & TELEPORT) ? Math.hypot(n.wx - next.wx, n.wy - next.wy, n.wz - next.wz) : 0;
    });
  }
  return paths;
}
const pathYards = (nodes) => nodes.reduce((sum, n) => sum + n.next, 0);

// The flight graph: nodes a character can learn, who can use them, where their flight master stands, and the paths.
function buildFlights(db, src, paths, notes) {
  const masters = [];
  for (const npc of src.flightMasters) for (const [area, list] of Object.entries(npc.spawns || {})) for (const [x, y] of list) {
    const point = toPoint(db, +area, x, y);
    if (point) masters.push({ npc: npc.id, friendly: npc.friendly || "", point });
  }
  const nodes = new Map();
  for (const row of src.taxiNodes) {
    const id = +row.ID, wx = +row.Pos_0, wy = +row.Pos_1, continent = +row.ContinentID;
    const flagged = FACTIONS.filter((f) => +row.Flags & FACTION_FLAG[f]);
    // CharacterBitNumber is the node's bit in the character's known-nodes mask: without one it cannot be learned
    // (battleground nodes, the druid-only Nighthaven nodes, the Plaguelands towers, quest and transport paths)
    if (!flagged.length || !(+row.CharacterBitNumber > 0)) continue;
    const here = masters.filter((m) => m.point.continent === continent && Math.hypot(m.point.wx - wx, m.point.wy - wy) <= E.FLIGHT_MASTER_YARDS)
      .sort((a, b) => Math.hypot(a.point.wx - wx, a.point.wy - wy) - Math.hypot(b.point.wx - wx, b.point.wy - wy) || a.npc - b.npc);
    const node = { id, name: row.Name_lang, continent, wx, wy, bit: +row.CharacterBitNumber, flagged, factions: [], masters: {}, npc: 0, point: null };
    if (!here.length) {
      const point = pointAt(db, zoneAt(db, continent, wx, wy, node.name), wx, wy);
      if (!point) continue; // not on any zone map
      node.factions = flagged;
      for (const f of flagged) node.masters[f] = { npc: 0, point };
    } else {
      for (const f of flagged) {
        const master = here.find((m) => m.friendly.includes(f[0]));
        if (master) { node.factions.push(f); node.masters[f] = { npc: master.npc, point: master.point }; }
      }
    }
    if (!node.factions.length) continue;
    node.npc = node.masters[node.factions[0]].npc;
    node.point = node.masters[node.factions[0]].point;
    nodes.set(id, node);
  }
  // paths between two nodes that share a faction; a node no such path touches cannot be flown from or to
  const edges = new Map();
  const shared = (a, b) => a.factions.some((f) => b.factions.includes(f));
  for (let changed = true; changed;) {
    edges.clear();
    for (const row of src.taxiPaths) {
      const a = nodes.get(+row.FromTaxiNode), b = nodes.get(+row.ToTaxiNode);
      if (!a || !b || a === b || !shared(a, b)) continue;
      const along = paths.get(+row.ID);
      const edge = { to: b.id, path: +row.ID };
      if (along && along.length > 1) edge.yards = pathYards(along);
      else { edge.yards = Math.hypot(a.wx - b.wx, a.wy - b.wy) * E.FLIGHT_PATH_RATIO; edge.estimated = true; }
      edge.seconds = edge.yards / E.FLIGHT_SPEED;
      if (!edges.has(a.id)) edges.set(a.id, []);
      edges.get(a.id).push(edge);
    }
    const touched = new Set();
    for (const [from, list] of edges) { touched.add(from); for (const e of list) touched.add(e.to); }
    changed = false;
    for (const id of [...nodes.keys()]) if (!touched.has(id)) { nodes.delete(id); changed = true; }
  }
  for (const list of edges.values()) list.sort((a, b) => a.to - b.to);
  for (const node of nodes.values()) {
    if (!node.npc) notes.push(`node ${node.id} ${node.name}: no flight master in the data; the step has no NPC and stands at the node itself`);
    for (const f of node.flagged) {
      if (!node.factions.includes(f)) notes.push(`node ${node.id} ${node.name}: the client shows it to the ${f}, but no flight master friendly to the ${f} is in the data; not used for the ${f}`);
    }
  }
  return { nodes, edges };
}

// The transport links. One with a client path takes its times from the path: half a loop of waiting, then the ride.
// verified = true says that nothing about the link is assumed: a client path stops at both ends, and who may board and
// how is a public fact of the original game. A link that is not verified names what is assumed; pathVerified tells the
// two apart for a caller: the client path is there, something else is not confirmed.
function buildLinks(db, src, paths) {
  const links = [];
  for (const raw of src.transports.links) {
    const fail = (why) => { throw new Error(`transports.json, ${raw.id}: ${why}`); };
    const end = (e) => {
      const p = toPoint(db, e.zone, e.x, e.y);
      if (!p || p.zone !== e.zone) fail(`zone ${e.zone} has no map`);
      return p;
    };
    if (raw.assumed !== undefined && !Array.isArray(raw.assumed)) fail("assumed is a list");
    const link = { id: raw.id, kind: raw.kind, name: raw.name || raw.id, a: end(raw.a), b: end(raw.b), factions: raw.factions.slice(), verified: raw.verified === true,
      assumed: (raw.assumed || []).slice(), pathVerified: false, oneWay: raw.oneWay === true, requires: raw.requires || null, path: raw.path || 0 };
    for (const what of link.assumed) if (!ASSUMABLE.includes(what)) fail(`assumed names "${what}"; it can name ${ASSUMABLE.join(", ")}`);
    if (link.verified && !link.path) fail("verified needs the client transport path that confirms it");
    if (link.verified && link.assumed.length) fail(`verified, but assumed names ${link.assumed.join(", ")}: a link with an assumption is verified = false`);
    if (!link.verified && !link.assumed.length) fail("not verified needs assumed: the list of what is not confirmed");
    if (!link.path && !link.assumed.includes("route")) fail("a link without a client path has an assumed route: assumed must name it");
    link.pathVerified = link.path > 0 && !link.assumed.includes("route"); // the stops at both ends are checked below
    if (!link.path) {
      if (!(raw.seconds > 0)) fail("a link without a path needs its own seconds");
      link.secondsAB = link.secondsBA = raw.seconds;
    } else {
      const nodes = paths.get(link.path);
      if (!nodes) fail(`path ${link.path} has no TaxiPathNode rows`);
      const stopsAt = (p) => nodes.map((n, i) => i).filter((i) => nodes[i].flags & STOP && nodes[i].continent === p.continent && Math.hypot(nodes[i].wx - p.wx, nodes[i].wy - p.wy) <= E.STOP_YARDS);
      const atA = stopsAt(link.a), atB = stopsAt(link.b);
      if (!atA.length) fail(`path ${link.path} has no stop within ${E.STOP_YARDS} yards of end a`);
      if (!atB.length) fail(`path ${link.path} has no stop within ${E.STOP_YARDS} yards of end b`);
      // the transport sails its path as a loop: from stop i on to stop j, waiting at every stop between
      const ride = (i, j) => {
        let seconds = 0;
        for (let k = i; k !== j; k = (k + 1) % nodes.length) seconds += nodes[k].next / E.TRANSPORT_SPEED + (k !== i ? nodes[k].delay : 0);
        return seconds;
      };
      const best = (from, to) => Math.min(...from.flatMap((i) => to.filter((j) => j !== i).map((j) => ride(i, j))));
      link.loopSeconds = nodes.reduce((sum, n) => sum + n.next / E.TRANSPORT_SPEED + n.delay, 0);
      link.secondsAB = link.loopSeconds / 2 + best(atA, atB);
      link.secondsBA = link.loopSeconds / 2 + best(atB, atA);
    }
    links.push(link);
  }
  return links;
}

// The passes, and the walking distance between every two of them: two passes of one zone are joined by a straight
// line, longer ways go from pass to pass.
function buildPasses(db, src, notes) {
  const passes = src.transports.passes.map((raw) => {
    const point = toPoint(db, raw.at.zone, raw.at.x, raw.at.y);
    if (!point) throw new Error(`transports.json, pass ${raw.a}-${raw.b}: zone ${raw.at.zone} has no map`);
    return { a: raw.a, b: raw.b, point };
  });
  const passesOf = new Map();
  passes.forEach((p, i) => { for (const z of [p.a, p.b]) { if (!passesOf.has(z)) passesOf.set(z, []); passesOf.get(z).push(i); } });
  const n = passes.length;
  const between = passes.map(() => new Array(n).fill(Infinity));
  for (let i = 0; i < n; i++) for (let j = 0; j < n; j++) {
    const p = passes[i], q = passes[j];
    if (i === j) between[i][j] = 0;
    else if (p.a === q.a || p.a === q.b || p.b === q.a || p.b === q.b) between[i][j] = dist(p.point, q.point);
  }
  for (let k = 0; k < n; k++) for (let i = 0; i < n; i++) for (let j = 0; j < n; j++) {
    if (between[i][k] + between[k][j] < between[i][j]) between[i][j] = between[i][k] + between[k][j];
  }
  // a zone map without a pass, on a continent that has passes: walking there can only be guessed
  const charted = new Set(passes.map((p) => p.point.continent));
  for (const m of [...db.maps.values()].sort((a, b) => a.area - b.area)) {
    const area = db.areas.get(m.area);
    if (area && charted.has(area.continent) && !passesOf.has(m.area)) notes.push(`zone ${m.area} ${area.name} has no pass: walking to it is a straight-line guess`);
  }
  return { passes, passesOf, between };
}

// src: { taxiNodes, taxiPaths, taxiPathNodes: rows of the client tables; flightMasters: [{ id, name, friendly, spawns }];
//        transports: the content of planner/transports.json }
function buildGraph(db, src) {
  const notes = [];
  const paths = readPaths(src.taxiPathNodes || []);
  const { nodes, edges } = buildFlights(db, src, paths, notes);
  const links = buildLinks(db, src, paths);
  const graph = { nodes, edges, links, ...buildPasses(db, src, notes), notes, ground: {} };
  // the fixed places a trip can pass through, per faction: its flight masters and the ends of its transports
  for (const faction of FACTIONS) {
    const places = [];
    for (const node of [...nodes.values()].sort((a, b) => a.id - b.id)) if (node.factions.includes(faction)) places.push({ node, point: node.masters[faction].point });
    const nodeCount = places.length;
    for (const link of links) if (link.factions.includes(faction)) { places.push({ link, end: "a", point: link.a }); places.push({ link, end: "b", point: link.b }); }
    graph.ground[faction] = { places, nodeCount, indexOfNode: new Map(places.slice(0, nodeCount).map((p, i) => [p.node.id, i])), yards: new Map() };
  }
  return graph;
}
function loadTravel(db, dataDir, transportsFile = path.join(__dirname, "..", "planner", "transports.json")) {
  const wago = (name) => {
    const file = path.join(dataDir, "wago", name + ".csv");
    if (!fs.existsSync(file)) throw new Error(`${file} is missing: run "npm run fetch" in tools/`);
    return readCsv(file);
  };
  const raw = JSON.parse(fs.readFileSync(path.join(dataDir, "forever_db.json"), "utf8"));
  const flightMasters = [];
  for (const [id, n] of Object.entries(raw.Npc)) {
    if (((n.npcFlags || 0) & FLIGHT_MASTER_FLAG) === 0 && !FLIGHT_MASTER_TITLE.test(n.subName || "")) continue;
    const known = db.npcs.get(+id); // the loader has already turned the spawn lists into one shape
    flightMasters.push({ id: +id, name: n.name || "", friendly: n.friendlyToFaction || "", spawns: known ? known.spawns : {} });
  }
  return buildGraph(db, { taxiNodes: wago("TaxiNodes"), taxiPaths: wago("TaxiPath"), taxiPathNodes: wago("TaxiPathNode"), flightMasters,
    transports: JSON.parse(fs.readFileSync(transportsFile, "utf8")) });
}

// Walking distance in yards: { yards } or { yards, guess: true }, or null when there is no way on foot.
function walkYards(graph, p, q) {
  if (p.continent !== q.continent) return null;
  const straight = dist(p, q);
  if (p.zone === q.zone) return { yards: straight };
  const from = graph.passesOf.get(p.zone), to = graph.passesOf.get(q.zone);
  if (!from || !to) return { yards: straight, guess: true };
  let best = Infinity;
  for (const i of from) {
    const first = dist(p, graph.passes[i].point);
    for (const j of to) {
      const d = first + graph.between[i][j] + dist(graph.passes[j].point, q);
      if (d < best) best = d;
    }
  }
  if (best === Infinity) return null;
  return straight <= E.NEAR_BORDER && straight < best ? { yards: straight } : { yards: best };
}
const speedAt = (level) => (level >= E.MOUNT_LEVEL ? E.MOUNT_SPEED : E.RUN_SPEED);
function walkSeconds(graph, level, p, q) {
  const w = walkYards(graph, p, q);
  return w ? (w.yards * E.WALK_DETOUR) / speedAt(level) : Infinity;
}

// The fastest way from one place to another for one character.
//   state:   { faction, level, flights: Set of learned taxi node IDs, hearth: point or null }, and optionally
//            hearthReady: false (the hearthstone is on cooldown) and quests: a Set of quest IDs the character has or
//            has done. A transport that names a quest is boarded only when the quest is in that set: a caller that
//            passes no set has no quests, so it never boards one (the two skycutters off Zephras Isle today)
//   options: { pickups: false } leaves out the detours to flight points near the way
//            { verifiedOnly: true } plans without the links that are not verified
// Returns { legs, seconds }; seconds is Infinity (and legs empty) when the place cannot be reached. Then blocked, when
// present, lists the links the character got to and could not board for their level or quest: [{ link, requires }].
// A leg is one of
//   { action: "walk" | "travel", at, yards, seconds }             travel = the walk ends in another zone
//   { action: "getflight", node, at, npc, seconds }
//   { action: "fly", from, to, via: [node IDs between], at, land, seconds }
//   { action: "transport", kind, link, name, at, to, verified, pathVerified, assumed, seconds } (and requires, when the
//                                                                  link has one); see buildLinks for the three flags
//   { action: "hearth", to, seconds }
// A flight only passes through nodes in state.flights; its first node may be one learned by a getflight leg earlier in
// the same plan. `db` is not read today (points carry their world position); it is part of the planner's calling form.
function travelPlan(db, graph, state, from, to, options = {}) {
  if (from.continent === to.continent && dist(from, to) < 0.5) return { legs: [], seconds: 0 };
  const { faction, level } = state;
  const known = state.flights || new Set();
  const speed = speedAt(level);
  const ground = graph.ground[faction];
  if (!ground) throw new Error(`unknown faction ${faction}`);
  const fixed = ground.places, n = fixed.length;
  const hearth = state.hearth && state.hearthReady !== false ? state.hearth : null;
  // vertices: 0 the start, 1 the destination, 2.. the fixed places, then the hearth's inn, then one "in the air at node"
  // for each of the faction's nodes
  const S = 0, T = 1, F = 2, H = hearth ? F + n : -1, AIR = F + n + (hearth ? 1 : 0), V = AIR + ground.nodeCount;
  const pointOf = (v) => (v === S ? from : v === T ? to : v === H ? hearth : fixed[v - F].point);
  const allowed = (link) => (!link.requires || ((!link.requires.level || level >= link.requires.level) && (!link.requires.quest || (!!state.quests && state.quests.has(link.requires.quest)))));
  const blocked = []; // links the search got to and could not board
  const walk = (u, v) => {
    if (u >= F && v >= F && u !== H && v !== H) { // between two fixed places: worked out once per graph
      const key = (u - F) * n + (v - F);
      let w = ground.yards.get(key);
      if (w === undefined) { w = walkYards(graph, pointOf(u), pointOf(v)); ground.yards.set(key, w); }
      return w;
    }
    return walkYards(graph, pointOf(u), pointOf(v));
  };
  const cost = new Float64Array(V).fill(Infinity), prev = new Int32Array(V).fill(-1), how = new Array(V), done = new Uint8Array(V);
  const relax = (u, v, seconds, edge) => {
    if (cost[u] + seconds < cost[v]) { cost[v] = cost[u] + seconds; prev[v] = u; how[v] = edge; }
  };
  cost[S] = 0;
  for (;;) {
    let u = -1;
    for (let v = 0; v < V; v++) if (!done[v] && cost[v] < Infinity && (u < 0 || cost[v] < cost[u])) u = v;
    if (u < 0 || u === T) break;
    done[u] = 1;
    if (u >= AIR) { // in the air at a node: on to a learned neighbour, or land here if this node is learned
      const node = fixed[u - AIR].node;
      if (known.has(node.id)) relax(u, F + (u - AIR), 0, { type: "land" });
      for (const e of graph.edges.get(node.id) || []) {
        const k = ground.indexOfNode.get(e.to);
        if (k !== undefined && known.has(e.to)) relax(u, AIR + k, e.seconds, { type: "air", to: e.to, seconds: e.seconds });
      }
      continue;
    }
    for (let v = T; v < AIR; v++) { // on foot to the destination and to every fixed place
      if (v === u || v === H || done[v]) continue;
      const w = walk(u, v);
      if (w) relax(u, v, (w.yards * E.WALK_DETOUR) / speed, { type: "walk", yards: w.yards, guess: w.guess === true });
    }
    if (u === S && hearth) relax(u, H, E.HEARTH_SECONDS, { type: "hearth" });
    const place = u >= F && u !== H ? fixed[u - F] : null;
    if (place && place.node) relax(u, AIR + (u - F), E.BOARD_SECONDS + (known.has(place.node.id) ? 0 : E.LEARN_SECONDS), { type: "board", node: place.node });
    if (place && place.link && (place.end === "a" || !place.link.oneWay) && (place.link.verified || options.verifiedOnly !== true)) {
      if (!allowed(place.link)) {
        if (!blocked.some((b) => b.link === place.link.id)) blocked.push({ link: place.link.id, requires: place.link.requires });
        continue;
      }
      const other = u + (place.end === "a" ? 1 : -1); // a link's two ends follow each other in the list
      relax(u, other, place.end === "a" ? place.link.secondsAB : place.link.secondsBA, { type: "link", link: place.link, from: place.end });
    }
  }
  if (cost[T] === Infinity) return blocked.length ? { legs: [], seconds: Infinity, blocked } : { legs: [], seconds: Infinity };

  const chain = [];
  for (let v = T; v !== S; v = prev[v]) chain.unshift({ v, edge: how[v] });
  const learned = new Set(known); // grows as the plan learns flight points
  for (const { edge } of chain) if (edge.type === "board") learned.add(edge.node.id);
  const legs = [];
  const walkLeg = (p, q, w) => {
    if (w.yards < 0.5) return;
    const leg = { action: p.zone === q.zone ? "walk" : "travel", at: q, yards: w.yards, seconds: (w.yards * E.WALK_DETOUR) / speed };
    if (w.guess) leg.guess = true;
    legs.push(leg);
  };
  // a walk, with the flight points near it picked up on the way
  const walkTo = (p, q) => {
    while (options.pickups !== false) {
      const direct = walkYards(graph, p, q);
      let best = null;
      for (let k = 0; k < ground.nodeCount; k++) {
        const { node, point } = fixed[k];
        if (learned.has(node.id) || point.continent !== p.continent) continue;
        const there = walkYards(graph, p, point), on = there && walkYards(graph, point, q);
        if (!on) continue;
        const extra = there.yards + on.yards - direct.yards;
        if ((extra * E.WALK_DETOUR) / speed <= E.PICKUP_SECONDS && (!best || extra < best.extra)) best = { node, point, there, extra };
      }
      if (!best) break;
      walkLeg(p, best.point, best.there);
      legs.push({ action: "getflight", node: best.node.id, at: best.point, npc: best.node.masters[faction].npc, seconds: E.LEARN_SECONDS });
      learned.add(best.node.id);
      p = best.point;
    }
    walkLeg(p, q, walkYards(graph, p, q));
  };
  // Walks in a row are one walk, as long as that walk is no longer than its parts. It can be longer, or not exist at
  // all: two places within NEAR_BORDER are walked straight while the whole goes through a pass, and a zone without a
  // pass is a straight-line guess from anywhere, also from land the passes do not join. Then the parts are kept.
  let pos = from, flight = null, walked = null;
  const walkAll = () => {
    const { places, yards } = walked;
    walked = null;
    const whole = places.length > 2 ? walkYards(graph, places[0], places[places.length - 1]) : null;
    if (places.length === 2 || (whole && whole.yards <= yards + 1e-6)) walkTo(places[0], places[places.length - 1]);
    else for (let i = 1; i < places.length; i++) walkTo(places[i - 1], places[i]);
  };
  const taught = new Set(known);
  for (const { v, edge } of chain) {
    if (edge.type === "walk") {
      if (!walked) walked = { places: [pos], yards: 0 };
      pos = pointOf(v);
      walked.places.push(pos);
      walked.yards += edge.yards;
      continue;
    }
    if (walked) walkAll();
    if (edge.type === "hearth") { legs.push({ action: "hearth", to: hearth, seconds: E.HEARTH_SECONDS }); pos = hearth; }
    else if (edge.type === "board") {
      const master = edge.node.masters[faction];
      if (!taught.has(edge.node.id)) { legs.push({ action: "getflight", node: edge.node.id, at: master.point, npc: master.npc, seconds: E.LEARN_SECONDS }); taught.add(edge.node.id); }
      flight = { action: "fly", from: edge.node.id, to: 0, via: [], at: master.point, land: null, seconds: E.BOARD_SECONDS };
    } else if (edge.type === "air") { flight.via.push(edge.to); flight.seconds += edge.seconds; }
    else if (edge.type === "land") {
      flight.to = flight.via.pop();
      flight.land = pointOf(v);
      legs.push(flight);
      pos = flight.land; flight = null;
    } else if (edge.type === "link") {
      const { link } = edge, out = edge.from === "a";
      const leg = { action: "transport", kind: link.kind, link: link.id, name: link.name, at: out ? link.a : link.b, to: out ? link.b : link.a, verified: link.verified,
        pathVerified: link.pathVerified, assumed: link.assumed.slice(), seconds: out ? link.secondsAB : link.secondsBA };
      if (link.requires) leg.requires = link.requires;
      legs.push(leg);
      pos = leg.to;
    }
  }
  if (walked) walkAll();
  return { legs, seconds: legs.reduce((sum, leg) => sum + leg.seconds, 0) };
}

// The legs as route format 2 steps. Walking inside a zone is no step: the next step's own place leads there.
function toSteps(legs) {
  const at = (p) => ({ zone: p.zone, x: round2(p.x), y: round2(p.y) });
  const steps = [];
  for (const leg of legs) {
    if (leg.action === "travel") steps.push({ action: "travel", at: at(leg.at) });
    else if (leg.action === "getflight") steps.push({ action: "getflight", node: leg.node, at: at(leg.at), npc: leg.npc });
    else if (leg.action === "fly") steps.push({ action: "fly", from: leg.from, to: leg.to, at: at(leg.at) });
    else if (leg.action === "transport") steps.push({ action: "transport", kind: leg.kind, at: at(leg.at), to: at(leg.to) });
    else if (leg.action === "hearth") steps.push({ action: "hearth", to: at(leg.to) });
  }
  return steps;
}

module.exports = { ESTIMATES, ASSUMABLE, buildGraph, loadTravel, walkYards, walkSeconds, travelPlan, toSteps, pointAt };
