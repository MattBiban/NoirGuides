// Noir Guides, GPLv3. See LICENSE.
// An independent replay of a format 2 route for one character. It shares no rule code with the planner (nothing
// from planner/plan.js or its parts, no canAccept, no travelPlan): every rule is checked again from the data, so a
// planner bug cannot hide behind shared code. What it does share is the data (the quests, the travel graph's nodes,
// paths, links and passes) and the pace estimates of lib/xp.js, so both agree on the level at each step.
//
// How a route is replayed, step by step:
//   - a step whose `when` does not fit the character is not part of the character's route
//   - a step with a place (`at`) is walked to from where the last step left the player; walking inside one open zone
//     gives the fights' XP (walkXp); then the step does its own work
//   - fly ends at the flight master of `to`, transport at its `to`, hearth at its `to`
const { zoneOf, toPoint } = require("../lib/geo");
const { eligible, hasBit, CLASSES } = require("../lib/characters");
const { PACE, gain, questXp, objectiveXp, objectiveSeconds, zoneLevels, walkXp, grindSeconds } = require("../lib/xp");
const { ESTIMATES, buildGraph, walkYards } = require("../lib/travel");

const LOG_LIMIT = 20;   // the classic quest log holds 20 quests
const MAX_LEVEL = 60;   // the classic level cap
const SAME_PLACE = 60;  // yards: a step is "at" a flight master, a dock or an inn when it is this close (a route's
                        // places are rounded to a hundredth of a map percent, a few yards on the largest map)
const QUEST_ACTIONS = new Set(["accept", "objective", "turnin"]);
const ACTIONS = new Set([...QUEST_ACTIONS, "getflight", "fly", "transport", "travel", "sethearth", "hearth", "grind"]);

const emptyGraph = (db) => buildGraph(db, { taxiNodes: [], taxiPaths: [], taxiPathNodes: [], flightMasters: [], transports: { links: [], passes: [] } });
const yardsApart = (a, b) => (a.continent !== b.continent ? Infinity : Math.hypot(a.wx - b.wx, a.wy - b.wy));

// options: { graph: the travel graph (lib/travel.js); without one the world has no flights and no transports
//            inns: [{ npc, friendly, point }]; when given, a sethearth step must stand at one of them }
// Returns { errors, warnings, endLevel, xp, levels, clocks, seconds }: levels[i] is the character's level when step i
// starts, clocks[i] the estimated seconds played by then, seconds the estimated time of the whole route.
function validateRoute(db, route, ch, options = {}) {
  const errors = [];
  const warnings = [];
  const graph = options.graph || emptyGraph(db);
  const bands = zoneLevels(db);
  const startZone = zoneOf(db, ch.startArea);
  const startArea = db.areas.get(startZone);
  const state = { level: 1, xp: 0, pos: null, continent: startArea ? startArea.continent : -1, zone: startZone, log: new Set(), done: new Set(), objectiveDone: new Set(),
    flights: new Set(), hearth: null, lastHearth: -Infinity, clock: 0, lastGrind: false };
  const speed = () => (state.level >= ESTIMATES.MOUNT_LEVEL ? ESTIMATES.MOUNT_SPEED : ESTIMATES.RUN_SPEED);
  const levels = [];
  const clocks = [];

  if (route.format !== 2) errors.push(`the route is in format ${route.format === undefined ? 1 : route.format}; this validator reads format 2`);

  // Rule 6 needs to know up front which quests have an objective step anywhere in this character's route.
  const mine = (step) => !step.when || step.when.class === undefined || step.when.class === ch.cls;
  const hasObjectiveStep = new Set();
  for (const s of route.steps) if (s.action === "objective" && mine(s)) hasObjectiveStep.add(s.quest);

  // the fastest flight between two nodes over learned nodes only: seconds, or -1 when there is none
  const flightSeconds = (from, to) => {
    const best = new Map([[from, 0]]), open = [from];
    while (open.length) {
      open.sort((a, b) => best.get(a) - best.get(b));
      const u = open.shift();
      if (u === to) return best.get(u);
      for (const e of graph.edges.get(u) || []) {
        if (!state.flights.has(e.to)) continue;
        const cost = best.get(u) + e.seconds;
        if (!best.has(e.to) || cost < best.get(e.to)) { best.set(e.to, cost); if (!open.includes(e.to)) open.push(e.to); }
      }
    }
    return -1;
  };

  route.steps.forEach((step, i) => {
    const err = (msg) => errors.push(`step ${i + 1}: ${msg}`);
    levels.push(state.level);
    clocks.push(state.clock);
    const what = QUEST_ACTIONS.has(step.action) ? `${step.action} of quest ${step.quest}` : String(step.action);

    // `when`: checked for every character, whoever the route is replayed for
    if (step.when !== undefined) {
      const cls = step.when.class;
      if (cls !== undefined && !CLASSES[cls]) err(`${what} is for the unknown class ${cls}`);
      else if (cls !== undefined && QUEST_ACTIONS.has(step.action)) {
        const q = db.quests.get(step.quest);
        if (q && q.classes && !hasBit(q.classes, CLASSES[cls] - 1)) err(`${what} is for ${cls}, but quest ${q.id} is not open to that class`);
      }
      if (step.when.level !== undefined && !(Number.isInteger(step.when.level) && step.when.level >= 1 && step.when.level <= MAX_LEVEL)) err(`${what} has a minimum level that is not a whole level`);
      if (!mine(step) || (step.when.level !== undefined && state.level < step.when.level)) return; // not part of this character's route
    }
    if (!ACTIONS.has(step.action)) { err(`unknown action ${step.action}`); return; }

    // A place: on a map, inside it, on the player's continent and reachable on foot. Returns the point, or null.
    const point = (place, name) => {
      const { zone, x, y } = place;
      if (!db.maps.has(zone)) { err(`${name} is in ${zone}, which is not a zone with a map`); return null; }
      if (!(x >= 0 && x <= 100 && y >= 0 && y <= 100)) { err(`${name} has coordinates outside 0-100 (${x}, ${y})`); return null; }
      return toPoint(db, zone, x, y);
    };
    const arrive = () => {
      if (!step.at) { err(`${what} has no place`); return null; }
      const p = point(step.at, what);
      if (!p) return null;
      if (p.continent !== state.continent) {
        err(`${what} is in zone ${p.zone} on another continent than the player (zone ${state.zone}), with no flight, transport or hearth that got them there`);
      } else if (state.pos) {
        const walk = walkYards(graph, state.pos, p);
        if (!walk) err(`there is no way on foot from zone ${state.pos.zone} to zone ${p.zone}, and no flight, transport or hearth leads to ${what}`);
        else {
          state.clock += (walk.yards * ESTIMATES.WALK_DETOUR) / speed();
          if (state.pos.zone === p.zone) gain(state, walkXp(yardsApart(state.pos, p), bands.get(p.zone), state.level));
        }
      }
      state.pos = p; state.continent = p.continent; state.zone = p.zone;
      return p;
    };
    const jump = (p) => { state.pos = p; state.continent = p.continent; state.zone = p.zone; };
    const wasGrind = state.lastGrind;
    state.lastGrind = false;

    if (step.action === "travel") { arrive(); return; }
    if (step.action === "grind") {
      // A grind step may only name a whole level from 1 to the cap; anything else is reported and not replayed.
      if (!Number.isInteger(step.level) || step.level < 1 || step.level > MAX_LEVEL) {
        err(`grind to level ${step.level}, which is not a whole level from 1 to ${MAX_LEVEL}`);
        return;
      }
      arrive();
      if (wasGrind) err("two grind steps in a row: a grind of more than one level");
      if (step.level > state.level + 1) err(`grind to level ${step.level} from level ${state.level}: more than one level`);
      if (step.level > state.level) { state.clock += grindSeconds(state.level, state.xp); state.level = step.level; state.xp = 0; }
      state.lastGrind = true;
      return;
    }
    if (step.action === "getflight") {
      const p = arrive();
      const node = graph.nodes.get(step.node);
      if (!node) { err(`unknown flight point ${step.node}`); return; }
      if (!node.factions.includes(ch.faction)) { err(`node ${node.id} (${node.name}) is not a flight point of the ${ch.faction}`); return; }
      const master = node.masters[ch.faction];
      if (p && yardsApart(p, master.point) > SAME_PLACE) err(`flight point ${node.id} (${node.name}) is learned in zone ${master.point.zone}, and the step is not at the flight master`);
      if (master.npc && step.npc !== master.npc) err(`flight point ${node.id} is taught by NPC ${master.npc}, not ${step.npc}`);
      state.flights.add(node.id);
      state.clock += ESTIMATES.LEARN_SECONDS;
      return;
    }
    if (step.action === "fly") {
      const p = arrive();
      const from = graph.nodes.get(step.from), to = graph.nodes.get(step.to);
      if (!from || !from.factions.includes(ch.faction)) { err(`flight from node ${step.from}, which is not a flight point of the ${ch.faction}`); return; }
      if (!to || !to.factions.includes(ch.faction)) { err(`flight to node ${step.to}, which is not a flight point of the ${ch.faction}`); return; }
      if (!state.flights.has(from.id)) err(`flight from node ${from.id} (${from.name}), which is not learned`);
      if (!state.flights.has(to.id)) err(`flight to node ${to.id} (${to.name}), which is not learned`);
      if (p && yardsApart(p, from.masters[ch.faction].point) > SAME_PLACE) err(`flight from node ${from.id} does not leave from its flight master`);
      if (state.flights.has(from.id) && state.flights.has(to.id)) {
        const seconds = from.id === to.id ? -1 : flightSeconds(from.id, to.id);
        if (seconds < 0) err(`no flight path from node ${from.id} to node ${to.id} through learned flight points`);
        else state.clock += ESTIMATES.BOARD_SECONDS + seconds;
      }
      jump(to.masters[ch.faction].point);
      return;
    }
    if (step.action === "transport") {
      const p = arrive();
      if (!step.to) { err("transport has no destination"); return; }
      const q = point(step.to, "the transport's destination");
      if (!p || !q) return;
      let link = null, seconds = 0;
      for (const l of graph.links) {
        if (yardsApart(p, l.a) <= SAME_PLACE && yardsApart(q, l.b) <= SAME_PLACE) { link = l; seconds = l.secondsAB; break; }
        if (!l.oneWay && yardsApart(p, l.b) <= SAME_PLACE && yardsApart(q, l.a) <= SAME_PLACE) { link = l; seconds = l.secondsBA; break; }
      }
      if (!link) { err(`no transport runs from zone ${p.zone} (${step.at.x}, ${step.at.y}) to zone ${q.zone} (${step.to.x}, ${step.to.y})`); jump(q); return; }
      if (link.kind !== step.kind) err(`"${link.name}" is a ${link.kind}, not a ${step.kind}`);
      if (!link.factions.includes(ch.faction)) err(`the ${ch.faction} cannot use the ${link.kind} "${link.name}"`);
      else if (link.assumed.includes("factions")) err(`who may board the ${link.kind} "${link.name}" is not confirmed: a route must not depend on it`);
      if (link.requires && link.requires.level && state.level < link.requires.level) err(`the ${link.kind} "${link.name}" needs level ${link.requires.level}, the character is level ${state.level}`);
      if (link.requires && link.requires.quest && !state.log.has(link.requires.quest) && !state.done.has(link.requires.quest)) err(`the ${link.kind} "${link.name}" needs quest ${link.requires.quest}, which the character has not accepted`);
      state.clock += seconds;
      jump(q);
      return;
    }
    if (step.action === "sethearth") {
      const p = arrive();
      if (!p) return;
      if (options.inns && !options.inns.some((inn) => inn.npc === step.npc && inn.friendly.includes(ch.faction[0]) && yardsApart(p, inn.point) <= SAME_PLACE)) {
        err(`sethearth with NPC ${step.npc} in zone ${p.zone}: no innkeeper of the ${ch.faction} with that ID stands there`);
      }
      state.hearth = p;
      state.clock += PACE.TALK_SECONDS;
      return;
    }
    if (step.action === "hearth") {
      if (!step.to) { err("hearth has no destination"); return; }
      const q = point(step.to, "the hearth's destination");
      if (!q) return;
      if (!state.hearth) err("hearth before the hearthstone is bound by a sethearth step");
      else if (yardsApart(q, state.hearth) > SAME_PLACE) err(`hearth to zone ${q.zone} (${step.to.x}, ${step.to.y}), but the hearthstone is bound in zone ${state.hearth.zone}`);
      const since = state.clock - state.lastHearth;
      if (since < PACE.HEARTH_COOLDOWN) err(`hearth ${Math.round(since / 60)} minutes after the last one: the hearthstone has a cooldown of ${PACE.HEARTH_COOLDOWN / 60} minutes`);
      state.clock += ESTIMATES.HEARTH_SECONDS;
      state.lastHearth = state.clock;
      jump(q);
      return;
    }

    // accept, objective, turnin
    arrive();
    const q = db.quests.get(step.quest);
    if (!q) { err(`${step.action} of unknown quest ${step.quest}`); return; }

    if (step.action === "accept") {
      if (!eligible(q, ch)) err(`quest ${q.id} is not open to this race or class (${ch.race} ${ch.cls})`);
      if (q.preAny.length && !q.preAny.some((p) => state.done.has(p))) err(`quest ${q.id} has no prerequisite turned in (any of ${q.preAny.join(", ")})`);
      const missing = q.preAll.filter((p) => !state.done.has(p));
      if (missing.length) err(`quest ${q.id} is missing prerequisite ${missing.join(", ")}`);
      const clash = q.exclusive.filter((p) => state.done.has(p) || state.log.has(p));
      if (clash.length) err(`quest ${q.id} is exclusive with ${clash.join(", ")}, already taken`);
      // The level check comes after the prerequisite checks so a quest failing both reports the prerequisite first.
      if (state.level < q.minLevel) err(`quest ${q.id} needs level ${q.minLevel}, the character is level ${state.level}`);
      if (q.maxLevel && state.level > q.maxLevel) err(`quest ${q.id} is offered up to level ${q.maxLevel}, the character is level ${state.level}`);
      if (q.disabledBy && state.log.has(q.disabledBy)) err(`quest ${q.id} is not offered while quest ${q.disabledBy} is in the log`);
      if (q.availableUntil && state.done.has(q.availableUntil)) err(`quest ${q.id} is no longer offered once quest ${q.availableUntil} is turned in`);
      if (q.availableAfter && !state.log.has(q.availableAfter) && !state.done.has(q.availableAfter)) err(`quest ${q.id} is offered only after quest ${q.availableAfter} is taken`);
      if (state.log.has(q.id)) err(`quest ${q.id} is already in the log`);
      else if (state.done.has(q.id)) err(`quest ${q.id} is already done`);
      else {
        if (state.log.size >= LOG_LIMIT) err(`accepting quest ${q.id} would put more than ${LOG_LIMIT} quests in the log`);
        state.log.add(q.id);
      }
      state.clock += PACE.TALK_SECONDS;
      return;
    }

    // Rule 5: objective and turn-in need the quest in the log.
    if (!state.log.has(q.id)) { err(`${step.action} of quest ${q.id}, which is not in the log`); return; }

    if (step.action === "objective") {
      if (!state.objectiveDone.has(q.id)) {
        state.objectiveDone.add(q.id);
        gain(state, objectiveXp(q, state.level));
        state.clock += objectiveSeconds(q);
      }
      return;
    }

    // turn-in
    if (hasObjectiveStep.has(q.id) && !state.objectiveDone.has(q.id)) err(`quest ${q.id} is turned in before its objective`);
    state.log.delete(q.id);
    state.done.add(q.id);
    gain(state, questXp(q.level, state.level));
    state.clock += PACE.TALK_SECONDS;
  });

  if (state.log.size) {
    const ids = [...state.log].sort((a, b) => a - b);
    errors.push(`the route ends with ${ids.length} quest${ids.length === 1 ? "" : "s"} in the log: ${ids.join(", ")}`);
  }
  if (state.level < MAX_LEVEL) warnings.push(`route ends at level ${state.level}`);
  return { errors, warnings, endLevel: state.level, xp: state.xp, levels, clocks, seconds: state.clock };
}

module.exports = { validateRoute };
