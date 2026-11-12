// Noir Guides, GPLv3. See LICENSE.
// Class quests, layered into a race's shared route. The shared route (planner/plan.js) is the same for every class
// of the race and takes no quest with a class mask; this file puts each class's own quests back in, as steps with
// `when = { class = ... }`, so one route file serves every class of its race.
//
// How one quest is layered: each of its parts (accept, objective if it has one, turn-in) goes into a slot of the
// shared route, the gap before one of its steps. A part is put where it costs the least extra time: the way from
// where the player is in that slot to the part's place and on to the next shared step, less the way the shared
// route already takes. The slots a part may use keep
//   the level         accepted at or above the quest's level requirement; its creatures not more than HARD levels
//                     above the player; all of it done before the player is LATE levels past it (wider only when
//                     nothing fits: then a step later, never left out for being late alone)
//   prerequisites     everything canAccept asks, from what the shared route and the class's own steps have done by then
//   the quest log     the shared route's quests in the log plus the class's never pass the log's 20
// A part in another zone than the slot's steps is reached by the fastest way travelPlan finds (walking, flights the
// player has learned by then, transports), and the way back to the next shared step is written too, all as class
// steps. The hearthstone is never used by a class step: its cooldown belongs to the shared route.
// The shared route is never changed: a character of a class with no quests plays it step for step.
const { zoneOf, toPoint, distance } = require("../lib/geo");
const { eligible, CLASS_SORTS, SKYBORNE_CONTINENT } = require("../lib/characters");
const { instanced, instanceBound, startPoint, endPoint, objectivePoint, canAccept } = require("../lib/quests");
const { ESTIMATES, travelPlan, walkYards, walkSeconds, toSteps } = require("../lib/travel");
const { validateRoute } = require("./validate");
const { CHOICES: C } = require("./tuning");
const { emptyGraph, plannerGraph, spot } = require("./context");

const ZEPHRAS_ISLE = 16593; // the Skyborne starting zone (AreaTable): its quests are Forever's own and still taken
// The planner's preferences for class quests; none is a game fact.
const LAYER = Object.freeze({
  LATE: 5,             // a class quest is done before the player is this many levels above it, while it still gives
                       // its full XP (lib/xp.js questXp); when nothing fits, the window grows by this much at a time
  CANDIDATES: 6,       // the slots with the shortest straight-line detour that are costed exactly with travelPlan
  CROSSING: 1200,      // seconds a way to another continent is guessed to take, to rank slots before costing them
});

// The class quests a character may be routed through: open to its race and class by the masks, ordinary one-time
// quests (not repeatable, not behind a reputation, skill or event, not in or needing an instance), filed under a
// zone or under the class's quest sort, classic or from the Skyborne start, given and ended by someone the faction can
// find, below the level cap, and with every place reachable. Returns [{ q, start, end, obj, kills }] by level and ID.
// options: { graph (as loadTravel gives it), maxLevel }.
function classQuests(db, ch, options = {}) {
  return candidates(db, ch, plannerGraph(options.graph || emptyGraph(db)), options.maxLevel || 60).routable;
}
// Whether a quest is from the Skyborne start: given on Zephras Isle. A quest filed under a class sort has no zone, so
// this is read from where it is given, not from the quest's zone.
const fromIsle = (db, q, start) => start.point.continent === SKYBORNE_CONTINENT || zoneOf(db, start.point.zone) === ZEPHRAS_ISLE || (!!q.zone && zoneOf(db, q.zone) === ZEPHRAS_ISLE);
const NOT_CLASSIC = "not a classic quest and not given on Zephras Isle (only those are routed, as in the shared route)";
// classQuests on a graph that has been through plannerGraph already: { routable, dropped: [{ quest, reason }] }.
// dropped: the quests that pass every rule but the classic one, so the route lists them as left out.
function candidates(db, ch, graph, maxLevel) {
  const nodes = [...graph.nodes.values()].filter((n) => n.factions.includes(ch.faction));
  const free = { faction: ch.faction, level: 60, flights: new Set(nodes.map((n) => n.id)), hearth: null, quests: new Set(db.quests.keys()) };
  const reach = (a, b) => travelPlan(db, graph, free, a, b, { pickups: false }).seconds < Infinity;
  const out = [], dropped = [];
  for (const q of db.quests.values()) {
    if (!q.classes || !eligible(q, ch) || q.repeatable || q.gated || q.minLevel >= maxLevel) continue;
    if (q.sort < 0 ? !CLASS_SORTS[q.sort] : !q.zone || instanced(db, q.zone)) continue;
    if (instanceBound(db, q)) continue;
    if (q.starts.items.length && !q.starts.npcs.length && !q.starts.objects.length) continue; // started by a drop
    const start = spot(db, startPoint(db, q, ch.faction)), end = spot(db, endPoint(db, q, ch.faction));
    if (!start || !end || !start.point || !end.point) continue;
    const hasObjectives = q.objectives.npcs.length + q.objectives.objects.length + q.objectives.items.length + (q.killCredit || []).length > 0 || !!q.trigger;
    const obj = spot(db, objectivePoint(db, q));
    if ((hasObjectives && !obj) || (obj && !obj.point)) continue;
    const places = [start, obj, end].filter(Boolean).map((p) => p.point);
    if (places.some((p) => instanced(db, p.zone))) continue;
    if (places.slice(1).some((p, i) => !reach(places[i], p))) continue;
    // last, so that a quest dropped for this rule alone is known and listed
    if (!db.eraQuestIds.has(q.id) && !fromIsle(db, q, start)) { dropped.push({ quest: q.id, reason: NOT_CLASSIC }); continue; }
    out.push({ q, start, end, obj, kills: q.objectives.npcs.length + q.objectives.items.length > 0 });
  }
  return { routable: out.sort((a, b) => a.q.minLevel - b.q.minLevel || a.q.id - b.q.id), dropped };
}

// What the shared route does, slot by slot. Slot k is the gap before step k (slot steps.length is after the last).
function sharedFacts(db, route, ch, rawGraph) {
  const steps = route.steps, n = steps.length;
  const replay = validateRoute(db, route, ch, { graph: rawGraph });
  const levels = replay.levels.slice();
  levels.push(replay.endLevel);
  const at = (p) => (p ? toPoint(db, p.zone, p.x, p.y) : null);
  const before = [null];           // where the player stands in slot k: after step k - 1
  const next = [];                 // where step k walks to; null for a hearth step and after the last step
  const accepted = new Map(), turnedIn = new Map(), learned = new Map();
  const logBefore = [0];
  let pos = null, log = 0;
  steps.forEach((s, k) => {
    next.push(s.action === "hearth" ? null : at(s.at));
    if (s.at) pos = at(s.at);
    if (s.action === "fly") { const node = rawGraph.nodes.get(s.to); if (node && node.masters[ch.faction]) pos = node.masters[ch.faction].point; }
    else if (s.action === "transport" || s.action === "hearth") pos = at(s.to);
    else if (s.action === "getflight" && !learned.has(s.node)) learned.set(s.node, k);
    else if (s.action === "accept") { if (!accepted.has(s.quest)) accepted.set(s.quest, k); log++; }
    else if (s.action === "turnin") { turnedIn.set(s.quest, k); log--; }
    before.push(pos);
    logBefore.push(log);
  });
  next.push(null);
  // the most quests the shared route holds at any moment of slot k: before step k, or after it
  const logPeak = logBefore.map((v, k) => Math.max(v, k < n ? logBefore[k + 1] : v));
  return { n, levels, before, next, accepted, turnedIn, learned, logPeak };
}

// One class's quests in the shared route: { inserts: Map slot -> steps, layered: [quest IDs], left: [{ quest, reason }] }.
function layerClass(db, graph, facts, ch, maxLevel) {
  const { n, levels, before, next, accepted, turnedIn, learned, logPeak } = facts;
  const parts = new Map();          // slot -> [{ point, step }], in the order they are done
  const held = new Map();           // quest -> { s, u }: the slots it is accepted and handed in
  const occupied = new Int32Array(n + 1); // class quests in the log during each slot
  const speed = (level) => (level >= ESTIMATES.MOUNT_LEVEL ? ESTIMATES.MOUNT_SPEED : ESTIMATES.RUN_SPEED);
  const flightsAt = (k) => { const out = new Set(); for (const [node, i] of learned) if (i < k) out.add(node); return out; };
  const flightCache = new Map();
  const flightSet = (k) => { if (!flightCache.has(k)) flightCache.set(k, flightsAt(k)); return flightCache.get(k); };
  // what the character has and has done in slot k, as canAccept and travelPlan read it
  const view = (k) => {
    const doneShared = (id) => turnedIn.has(id) && turnedIn.get(id) < k;
    const inShared = (id) => accepted.has(id) && accepted.get(id) < k && !doneShared(id);
    const mine = (id) => held.get(id);
    return {
      level: levels[k],
      done: { has: (id) => doneShared(id) || (!!mine(id) && mine(id).u <= k) },
      log: { has: (id) => inShared(id) || (!!mine(id) && mine(id).s <= k && mine(id).u > k) },
      quests: { has: (id) => (accepted.has(id) && accepted.get(id) < k) || (!!mine(id) && mine(id).s <= k) },
    };
  };
  const traveller = (k, flights) => ({ faction: ch.faction, level: levels[k], flights: flights || flightSet(k), hearth: null, quests: view(k).quests });
  // seconds from a to b in slot k: a short walk as the validator walks it, anything longer by travelPlan
  const seconds = (k, a, b) => {
    if (a.continent === b.continent) {
      const walk = walkSeconds(graph, levels[k], a, b);
      if (walk <= C.SHORT_WALK_SECONDS) return walk;
    }
    return travelPlan(db, graph, traveller(k), a, b, { pickups: false }).seconds;
  };
  const last = (k) => { const list = parts.get(k); return list && list.length ? list[list.length - 1].point : before[k]; };
  // the way the slot already takes from its last place to the next shared step
  const onward = (k) => {
    const from = last(k), to = next[k];
    if (!to) return 0;
    return parts.has(k) ? seconds(k, from, to) : walkSeconds(graph, levels[k], from, to);
  };
  const guess = (k, p) => {
    const from = last(k), to = next[k];
    const leg = (a, b) => (a.continent === b.continent ? (distance(a, b) * ESTIMATES.WALK_DETOUR) / speed(levels[k]) : LAYER.CROSSING);
    return leg(from, p) + (to ? leg(p, to) - leg(from, to) : 0);
  };
  const exact = (k, p) => {
    const there = seconds(k, last(k), p);
    if (there === Infinity) return Infinity;
    const back = next[k] ? seconds(k, p, next[k]) : 0;
    return there + back - onward(k);
  };
  // the cheapest slot of the list for a part at p: the few best by straight line, then costed exactly
  // seen: when given, the slots costed are added to it
  const cheapest = (slots, p, seen) => {
    const ranked = slots.map((k) => ({ k, g: guess(k, p) })).sort((a, b) => a.g - b.g || a.k - b.k).slice(0, LAYER.CANDIDATES);
    let best = null;
    for (const { k } of ranked) {
      if (seen) seen.add(k);
      const cost = exact(k, p);
      if (cost < Infinity && (!best || cost < best.cost - 1e-9 || (Math.abs(cost - best.cost) <= 1e-9 && k < best.k))) best = { k, cost };
    }
    return best;
  };
  const roomFrom = (s) => { // the last slot a quest accepted in slot s can still be in the log
    let k = s;
    while (k <= n && logPeak[k] + occupied[k] + 1 <= C.LOG_LIMIT) k++;
    return k - 1;
  };
  const stepOf = (c, action, place) => {
    const step = { action, quest: c.q.id, at: place.at };
    if (place.npc !== undefined) step.npc = place.npc;
    else if (place.object !== undefined) step.object = place.object;
    if (action === "objective" && place.item !== undefined) step.item = place.item;
    step.when = { class: ch.cls };
    return step;
  };

  // Quests whose offer depends on another quest, looked up from that other quest: placing a quest must not take the
  // offer away from one already in a route (the shared route's or this class's).
  const exclusiveWith = (id) => { const other = db.quests.get(id); return other ? other.exclusive : []; };
  const rivals = (q) => {
    const out = new Set(q.exclusive);
    for (const id of held.keys()) if (exclusiveWith(id).includes(q.id)) out.add(id);
    for (const id of accepted.keys()) if (exclusiveWith(id).includes(q.id)) out.add(id);
    return out;
  };
  const taken = (q) => [...rivals(q)].some((id) => held.has(id) || accepted.has(id));
  // true when a quest held from slot s to slot u takes the offer away from a quest a route takes later or earlier:
  //   disabledBy      the other quest is accepted while this one is in the log
  //   availableUntil  this one is handed in before the other is accepted
  // A quest the shared route accepts at step b is accepted in slot b, after the class steps of that slot.
  function spoils(q, s, u) {
    for (const [id, h] of held) {   // a class quest, accepted in slot h.s before this one's parts of that slot
      const other = db.quests.get(id);
      if (other.disabledBy === q.id && s < h.s && h.s <= u) return true;
      if (other.availableUntil === q.id && u < h.s) return true;
    }
    for (const [id, b] of accepted) { // a shared quest, accepted at step b after the class steps of slot b
      const other = db.quests.get(id);
      if (other && other.disabledBy === q.id && s <= b && b < u) return true;
      if (other && other.availableUntil === q.id && u <= b) return true;
    }
    return false;
  }

  // Places one quest: { cost, undo } with its parts written, or { reason } and nothing written.
  function place(c) {
    const { q } = c;
    if (taken(q)) return { reason: "an exclusive quest is taken instead" };
    const missing = q.preAll.filter((id) => !takeable.has(id));
    if (missing.length) return { reason: `it needs quest ${missing.join(", ")} first, which no step of this route can take` };
    if (q.preAny.length && !q.preAny.some((id) => takeable.has(id))) return { reason: `it needs one of quests ${q.preAny.join(", ")} first, which no step of this route can take` };
    let reason = `the route never reaches level ${q.minLevel}`;
    for (let late = LAYER.LATE; ; late += LAYER.LATE) {
      const top = Math.max(q.level, q.minLevel) + late;
      const inWindow = (k) => k >= 1 && levels[k] <= top;
      const offered = [];
      for (let k = 1; k <= n; k++) {
        if (!inWindow(k) || levels[k] < q.minLevel) continue;
        if (!canAccept(q, view(k))) { reason = "the route never offers it (a prerequisite, an exclusive quest or its level cap)"; continue; }
        if (logPeak[k] + occupied[k] + 1 > C.LOG_LIMIT) { reason = "the quest log is full wherever it is offered"; continue; }
        offered.push(k);
      }
      const tried = new Set();
      while (offered.some((k) => !tried.has(k))) {
        const a = cheapest(offered.filter((k) => !tried.has(k)), c.start.point, tried);
        if (!a) { reason = "no way to where it is given"; continue; }
        const room = roomFrom(a.k);
        const range = (from, ok) => { const out = []; for (let k = from; k <= room; k++) if (inWindow(k) && ok(k)) out.push(k); return out; };
        // the parts go in one after the other: what the accept leaves behind is where the objective is costed from
        const plan = [{ k: a.k, action: "accept", place: c.start, cost: a.cost }];
        push(plan[0], c);
        let ok = true, from = a.k;
        if (c.obj) {
          const o = cheapest(range(from, (k) => !c.kills || levels[k] >= q.level - C.HARD), c.obj.point);
          if (!o) ok = false;
          else { plan.push({ k: o.k, action: "objective", place: c.obj, cost: o.cost }); push(plan[plan.length - 1], c); from = o.k; }
        }
        if (ok) {
          const t = cheapest(range(from, () => true), c.end.point);
          if (!t) ok = false;
          else { plan.push({ k: t.k, action: "turnin", place: c.end, cost: t.cost }); push(plan[plan.length - 1], c); }
        }
        const u = plan[plan.length - 1].k;
        if (ok && !spoils(q, a.k, u)) {
          held.set(q.id, { s: a.k, u });
          for (let k = a.k; k <= u; k++) occupied[k]++;
          const undo = () => {
            for (const p of plan.slice().reverse()) parts.get(p.k).pop();
            held.delete(q.id);
            for (let k = a.k; k <= u; k++) occupied[k]--;
          };
          return { cost: plan.reduce((sum, p) => sum + p.cost, 0), undo };
        }
        for (const p of plan.slice().reverse()) parts.get(p.k).pop();
        reason = ok ? "it would take the offer of another quest away" : "no room in the quest log, or no way to its objective or turn-in, at its level";
      }
      if (top >= maxLevel + LAYER.LATE) return { reason };
    }
  }
  function push(p, c) {
    if (!parts.has(p.k)) parts.set(p.k, []);
    parts.get(p.k).push({ point: c[p.action === "accept" ? "start" : p.action === "objective" ? "obj" : "end"].point, step: stepOf(c, p.action, p.place) });
  }

  // Quests are placed lowest level first, and again while any new one opens up (a class chain). Of quests that
  // exclude each other (one version per race of a trainer's errand, say), the one with the cheapest detour is taken;
  // of equal ones the lower level and ID.
  const layered = [], reasons = new Map();
  const found = candidates(db, ch, graph, maxLevel); // graph has been through plannerGraph in layerClasses
  let pending = found.routable;
  // the quests a step of this character's route could ever take: the shared route's and its class quests
  const takeable = new Set([...accepted.keys(), ...pending.map((c) => c.q.id)]);
  for (let changed = true; changed && pending.length; ) {
    changed = false;
    for (const c of pending.slice()) {
      if (!pending.includes(c)) continue; // placed already, as the cheapest of its group
      const group = pending.filter((o) => o === c || o.q.exclusive.includes(c.q.id) || c.q.exclusive.includes(o.q.id));
      let best = null;
      for (const o of group) {
        const tried = place(o);
        if (tried.reason) { reasons.set(o.q.id, tried.reason); continue; }
        tried.undo();
        if (!best || tried.cost < best.cost - 1e-9) best = { c: o, cost: tried.cost };
      }
      if (!best) continue;
      place(best.c);
      layered.push(best.c.q.id);
      pending = pending.filter((o) => o !== best.c);
      changed = true;
    }
  }
  for (const c of pending) if (taken(c.q)) reasons.set(c.q.id, "an exclusive quest is taken instead");

  // The steps: each slot's parts, with the way to each written as class steps, and the way on to the next shared step.
  const inserts = new Map();
  const known = new Set();
  const cls = { class: ch.cls };
  for (const k of [...parts.keys()].sort((a, b) => a - b)) {
    const list = parts.get(k);
    if (!list.length) continue;
    const out = [];
    const flights = () => { const f = new Set(flightSet(k)); for (const node of known) f.add(node); return f; };
    const way = (from, to) => {
      if (from.continent === to.continent && walkYards(graph, from, to) && walkSeconds(graph, levels[k], from, to) <= C.SHORT_WALK_SECONDS) return;
      const plan = travelPlan(db, graph, traveller(k, flights()), from, to, { pickups: false });
      const legs = toSteps(plan.legs);
      // a walk over a border to the place itself needs no step: the next step's own place leads there
      if (legs.length && legs[legs.length - 1].action === "travel") legs.pop();
      for (const s of legs) {
        if (s.action === "getflight") known.add(s.node);
        out.push({ ...s, when: cls });
      }
    };
    let from = before[k];
    for (const part of list) {
      way(from, part.point);
      out.push(part.step);
      from = part.point;
    }
    if (next[k]) way(from, next[k]);
    inserts.set(k, out);
  }
  const left = [...pending.map((c) => ({ quest: c.q.id, reason: reasons.get(c.q.id) })), ...found.dropped].sort((a, b) => a.quest - b.quest);
  return { inserts, layered: layered.sort((a, b) => a - b), left };
}

// Every class of a race layered into its shared route. characters: the race's characters (one per class), in the
// order their steps are written where two classes use the same slot.
// options: { graph, maxLevel }. Returns { route, classes: { [cls]: { layered, left, steps } } }; the route is a new
// object and the shared one is not changed.
function layerClasses(db, route, characters, options = {}) {
  const maxLevel = options.maxLevel || 60;
  const rawGraph = options.graph || emptyGraph(db);
  const graph = plannerGraph(rawGraph);
  const classes = {};
  const inserts = new Map();
  if (characters.length) {
    const facts = sharedFacts(db, route, characters[0], rawGraph);
    for (const ch of characters) {
      const layer = layerClass(db, graph, facts, ch, maxLevel);
      let count = 0;
      for (const [k, steps] of layer.inserts) {
        if (!inserts.has(k)) inserts.set(k, []);
        inserts.get(k).push(...steps);
        count += steps.length;
      }
      classes[ch.cls] = { layered: layer.layered, left: layer.left, steps: count };
    }
  }
  const steps = [];
  for (let k = 0; k <= route.steps.length; k++) {
    if (inserts.has(k)) steps.push(...inserts.get(k));
    if (k < route.steps.length) steps.push(route.steps[k]);
  }
  return { route: { ...route, steps }, classes };
}

module.exports = { LAYER, classQuests, layerClasses };
