// Noir Guides, GPLv3. See LICENSE.
// Bundling: a race's layered format 2 action list (planner/plan.js, planner/classes.js) as format 3 steps, each a
// list of lines ("Route format 3" and task P1 in docs/superpowers/plans/2026-11-11-guide-rebuild.md).
//
//   bundleSteps(db, route, levels) -> { steps, origin }
//       steps   format 3 steps without `text`; origin[i] the indices of the actions step i came from, in line order;
//               origin.flat() is hubOrder's order. `levels` (the lowest validateRoute(...).levels of the route's
//               characters) only decides whether an accept with a level requirement may move earlier.
//   hubOrder(db, actions, levels) -> indices
//       the planner's order with each hub's actions brought together (below); every other action keeps its place.
//   flatten(steps) -> actions
//       the format 2 actions a format 3 step list stands for: one action per active line that has a format 2
//       counterpart (the objective lines of one quest in one step are that quest's one objective action), grind
//       steps included. An action's place is its line's own place, else its step's (without r).
//
// The rules (BUNDLE_YARDS, HUB_YARDS and the hub order: the project lead's P3 follow-up, docs/routes/DATA-NOTES.md):
//   - consecutive accept, turnin, getflight and sethearth actions at the first one's NPC or object, or within
//     HUB_YARDS of its place in the same zone, are one step
//   - consecutive objective actions within OBJECTIVE_YARDS of the first are one step; each quest gives one line per
//     objective index (lib/quests.js objectiveList; a quest with none gives index 1)
//   - an objective joins a talk step, and a talk action an objective step, within BUNDLE_YARDS of the first action
//   - the hub order: after a talk or objective action (the head), the run of talk and objective actions within
//     HUB_YARDS of it in the same zone is its hub; an action of the run that would join the head's step is moved up
//     to it past the run's other actions, unless one of those is its own quest, a prerequisite, the quest it needs
//     taken first, the quest that turns it off or one it excludes, the character may not have the accept's level
//     there yet, the log would go over 20 quests, or it is a getflight its fly follows. The first action outside
//     the run ends it. So an action never moves before its prerequisite, and an accept never after an objective
//     that needs it; every action outside a hub keeps the planner's order.
//   - the area's objectives: after an objective head, a later objective within OBJECTIVE_YARDS of it (same `when`) is
//     moved up to it past the actions in between, by the same rules (never past its own quest's accept or a related
//     quest), as long as every action in between is a hub action in the head's zone. So the objectives of one area
//     are one step, and the hand-ins come after the area is done.
//   - a getflight followed by a fly from that node is one step; every other fly, transport, travel, hearth and grind
//     is a step of its own
//   - actions with different `when` never share a step; the step carries the `when`
//   - a line more than OWN_PLACE_YARDS from the step's place carries its own place
//   - the step's place is the first action's, with the radius of its kind (RADIUS)
const { toPoint, distance, spawnPoints } = require("../lib/geo");
const { objectiveList, starterItems, sourceItems, prerequisites } = require("../lib/quests");

// Arrival radii in yards, by kind of place. zoneOnly is for a place the planner wrote as x = y = 0 (the zone, place
// unknown): a pin, no arrow, arrival = being in the zone.
const RADIUS = Object.freeze({ npc: 10, flightmaster: 10, dock: 15, goto: 20, area: 40, zoneOnly: 0 });
const BUNDLE_YARDS = 60;
const HUB_YARDS = 80;
const OWN_PLACE_YARDS = 30;
const OBJECTIVE_YARDS = 150;
const LOG_LIMIT = 20;         // planner/validate.js
const MAX_TARGETS = 6;        // enemy target buttons on one step
const MODES = new Set(["zeppelin", "boat", "tram", "portal"]);

const TALK = new Set(["accept", "turnin", "getflight", "sethearth"]);
const HUB = new Set([...TALK, "objective"]);
const ACTIONS = new Set([...HUB, "fly", "transport", "travel", "hearth", "grind"]);
// the radius of a step's place by the kind of its first action; a grind place never completes on arrival
const STEP_RADIUS = { accept: RADIUS.npc, turnin: RADIUS.npc, sethearth: RADIUS.npc, getflight: RADIUS.flightmaster, fly: RADIUS.flightmaster,
  transport: RADIUS.dock, travel: RADIUS.goto, objective: RADIUS.area, grind: undefined, hearth: undefined };

const zoneOnly = (p) => p.x === 0 && p.y === 0;
const whenKey = (a) => (a.when ? JSON.stringify(a.when) : "");
const bare = (p) => ({ zone: p.zone, x: p.x, y: p.y });
// a place with a radius: zone-only places always get RADIUS.zoneOnly; r undefined leaves it out
function placed(p, r) {
  const out = bare(p);
  const radius = zoneOnly(p) ? RADIUS.zoneOnly : r;
  if (radius !== undefined) out.r = radius;
  return out;
}

function nearness(db) {
  const point = (p) => (p && !zoneOnly(p) ? toPoint(db, p.zone, p.x, p.y) : null);
  return (a, b, yards) => {
    if (!a || !b || a.zone !== b.zone) return false;
    const pa = point(a), pb = point(b);
    return !!pa && !!pb && distance(pa, pb) <= yards;
  };
}
const sameGiver = (a, b) => (a.npc !== undefined && a.npc === b.npc) || (a.object !== undefined && a.object === b.object);
// whether hub action b joins a step whose first action is a
function sharesStep(near, a, b) {
  if (whenKey(a) !== whenKey(b) || !HUB.has(a.action) || !HUB.has(b.action)) return false;
  if (TALK.has(a.action) && TALK.has(b.action)) return sameGiver(a, b) || near(a.at, b.at, HUB_YARDS);
  if (a.action === "objective" && b.action === "objective") return near(a.at, b.at, OBJECTIVE_YARDS);
  return near(a.at, b.at, BUNDLE_YARDS);
}

function hubOrder(db, actions, levels) {
  const near = nearness(db);
  const n = actions.length;
  // the number of quests in the log before each action, every class's actions counted together (an upper bound)
  const logBefore = [];
  let log = 0;
  for (const a of actions) { logBefore.push(log); if (a.action === "accept") log++; else if (a.action === "turnin") log--; }
  // the quests an action may not be moved past
  const related = (a) => {
    const out = new Set([a.quest]);
    const q = a.action === "accept" ? db.quests.get(a.quest) : null;
    if (q) for (const p of [...q.preAll, ...q.preAny, ...q.exclusive, q.availableAfter, q.disabledBy]) if (p) out.add(p);
    return out;
  };
  const movable = (b, k, passed) => {
    if (b.action === "getflight" && k + 1 < n && actions[k + 1].action === "fly" && actions[k + 1].from === b.node) return false;
    if (b.quest === undefined) return true;
    const rel = related(b);
    if (passed.some((s) => actions[s].quest !== undefined && rel.has(actions[s].quest))) return false;
    if (b.action === "accept") {
      const q = db.quests.get(b.quest);
      const need = (q && q.minLevel) || 1;
      if (need > 1 && !(levels && levels[passed[0]] >= need)) return false;
      if (Math.max(...passed.map((s) => logBefore[s])) + 1 > LOG_LIMIT) return false;
    }
    return true;
  };
  const used = new Array(n).fill(false);
  const order = [];
  for (let i = 0; i < n; i++) {
    if (used[i]) continue;
    used[i] = true;
    order.push(i);
    const head = actions[i];
    if (!HUB.has(head.action) || !head.at || zoneOnly(head.at)) continue;
    const passed = []; // the run's actions left where they are, in order
    for (let k = i + 1; k < n; k++) {
      if (used[k]) continue;
      const b = actions[k];
      if (!HUB.has(b.action) || !near(head.at, b.at, HUB_YARDS)) break;
      if (sharesStep(near, head, b) && (!passed.length || movable(b, k, passed))) {
        used[k] = true;
        order.push(k);
        // the actions it passed now come after it in the log
        if (b.action === "accept") for (const s of passed) logBefore[s]++;
        else if (b.action === "turnin") for (const s of passed) logBefore[s]--;
      } else passed.push(k);
    }
    if (head.action !== "objective") continue;
    // the area's objectives: a later objective of the same zone session within OBJECTIVE_YARDS of the head joins it,
    // past the actions in between, by the same rules; a step that leaves the zone (or is no hub action) ends the run
    const between = [];
    for (let k = i + 1; k < n; k++) {
      if (used[k]) continue;
      const b = actions[k];
      if (!HUB.has(b.action) || !b.at || zoneOnly(b.at) || b.at.zone !== head.at.zone) break;
      if (b.action === "objective" && sharesStep(near, head, b) && movable(b, k, between)) {
        used[k] = true;
        order.push(k);
      } else between.push(k);
    }
  }
  return order;
}

function bundleSteps(db, route, levels) {
  const actions = route.steps;
  const near = nearness(db);
  function joins(group, a) {
    const first = group.actions[0], last = group.actions[group.actions.length - 1];
    if (whenKey(first) !== whenKey(a) || last.action === "fly") return false;
    if (a.action === "fly") return last.action === "getflight" && last.node === a.from;
    return sharesStep(near, first, a);
  }

  actions.forEach((a, k) => {
    if (!ACTIONS.has(a.action)) throw new Error(`action ${k + 1}: unknown action ${a.action}`);
    if (a.action === "transport" && !MODES.has(a.kind)) throw new Error(`action ${k + 1}: unknown transport kind ${a.kind}`);
  });
  const groups = [];
  for (const k of hubOrder(db, actions, levels)) {
    const a = actions[k];
    const group = groups[groups.length - 1];
    if (group && joins(group, a)) { group.actions.push(a); group.origin.push(k); } else groups.push({ actions: [a], origin: [k] });
  }

  // the quests handed in so far, with the conditions of the steps that hand them in ("" for everyone)
  const handedIn = new Map();
  const seen = new Map(); // step id -> times used
  const steps = groups.map((g) => {
    const step = makeStep(db, g.actions, handedIn, near);
    const count = (seen.get(step.id) || 0) + 1;
    seen.set(step.id, count);
    if (count > 1) step.id += `#${count}`;
    for (const a of g.actions) if (a.action === "turnin") {
      if (!handedIn.has(a.quest)) handedIn.set(a.quest, new Set());
      handedIn.get(a.quest).add(whenKey(a));
    }
    return step;
  });
  return { steps, origin: groups.map((g) => g.origin) };
}

const named = (map, id) => { const e = map.get(id); return !!e && typeof e.name === "string" && e.name !== ""; };

function makeStep(db, actions, handedIn, near) {
  const first = actions[0];
  const step = { id: "" };
  if (first.at) step.at = placed(first.at, STEP_RADIUS[first.action]);
  const lines = [];
  // a line's own place when it is farther than OWN_PLACE_YARDS from the step's
  const own = (a, r) => (step.at && a.at && !near(step.at, a.at, OWN_PLACE_YARDS) && !(a.at.zone === step.at.zone && a.at.x === step.at.x && a.at.y === step.at.y) ? placed(a.at, r) : undefined);
  const giver = (line, a) => { if (a.npc !== undefined) line.npc = a.npc; else if (a.object !== undefined) line.object = a.object; return line; };
  const withAt = (line, at) => { if (at) line.at = at; return line; };
  const fit = (a) => { const k = whenKey(a); return (set) => set.has("") || set.has(k); };
  const handedHere = new Set(); // quests handed in earlier in this step (every action of a step has the step's when)
  for (const a of actions) {
    const q = a.quest !== undefined ? db.quests.get(a.quest) : null;
    if ((a.action === "accept" || a.action === "turnin" || a.action === "objective") && !q) throw new Error(`quest ${a.quest} is not in the data`);
    switch (a.action) {
      case "accept": {
        const line = giver({ kind: "accept", quest: a.quest }, a);
        const pre = prerequisites(q);
        const done = (p) => handedHere.has(p) || (handedIn.has(p) && fit(a)(handedIn.get(p)));
        // all of the group; of "any one of", those the route hands in before, in an earlier step or earlier in this
        // one (another race's version never is)
        const requires = [...pre.all, ...pre.any.filter((p) => done(p) && !pre.all.includes(p))];
        if (requires.length) line.requires = requires;
        lines.push(withAt(line, own(a, RADIUS.npc)));
        break;
      }
      case "turnin": lines.push(withAt(giver({ kind: "turnin", quest: a.quest }, a), own(a, RADIUS.npc))); handedHere.add(a.quest); break;
      case "objective": {
        const at = own(a, RADIUS.area);
        const list = objectiveList(q);
        if (!list.length) lines.push(withAt({ kind: "objective", quest: a.quest, index: 1 }, at));
        for (const o of list) {
          const line = { kind: "objective", quest: a.quest, index: o.index };
          if ((o.kind === "kill" || o.kind === "credit") && named(db.npcs, o.id)) line.npc = o.id;
          else if (o.kind === "object" && named(db.objects, o.id)) line.object = o.id;
          else if (o.kind === "item" && named(db.items, o.id)) line.item = o.id;
          lines.push(withAt(line, at));
        }
        break;
      }
      case "getflight": { const line = { kind: "getflight", node: a.node }; if (a.npc !== undefined) line.npc = a.npc; lines.push(withAt(line, own(a, RADIUS.flightmaster))); break; }
      case "sethearth": { const line = { kind: "sethearth" }; if (a.npc !== undefined) line.npc = a.npc; lines.push(withAt(line, own(a, RADIUS.npc))); break; }
      case "fly": lines.push({ kind: "fly", from: a.from, to: a.to }); break;
      case "travel": lines.push({ kind: "goto", at: placed(a.at, RADIUS.goto) }); break;
      case "transport": lines.push({ kind: "transport", mode: a.kind, at: placed(a.at, RADIUS.dock), to: bare(a.to) }); break;
      case "hearth": lines.push({ kind: "hearth", to: bare(a.to) }); break;
      case "grind": lines.push({ kind: "grind", level: a.level }); break;
      default: throw new Error(`unknown action ${a.action}`);
    }
  }
  step.lines = lines;
  if (first.when) step.when = JSON.parse(JSON.stringify(first.when));

  // the highest level the step's accepted quests ask for
  let minLevel = 1;
  for (const a of actions) if (a.action === "accept") minLevel = Math.max(minLevel, db.quests.get(a.quest).minLevel || 1);
  if (minLevel > 1) step.minLevel = minLevel;

  // item buttons: starter items of the quests accepted here, then the usable items of every quest on the step
  const items = [];
  const addItem = (id) => { if (!items.includes(id) && named(db.items, id)) items.push(id); };
  for (const a of actions) {
    if (a.quest === undefined) continue;
    const q = db.quests.get(a.quest);
    if (a.action === "accept") starterItems(q).forEach(addItem);
    sourceItems(q).forEach(addItem);
  }
  if (items.length) step.items = items;

  // target buttons: the creatures of the step's kill objectives and the droppers of its item objectives, nearest
  // spawn first; the NPCs its quest lines talk to
  const enemies = [];
  const addEnemy = (id) => { if (!enemies.includes(id) && named(db.npcs, id)) enemies.push(id); };
  for (const a of actions) {
    if (a.action !== "objective") continue;
    for (const o of objectiveList(db.quests.get(a.quest))) {
      if (o.kind === "kill") addEnemy(o.id);
      else if (o.kind === "credit") o.npcs.forEach(addEnemy); // the creatures that count, not a stand-in credited one
      else if (o.kind === "item") { const item = db.items.get(o.id); ((item && item.npcDrops) || []).forEach(addEnemy); }
    }
  }
  const friends = [];
  for (const l of lines) if ((l.kind === "accept" || l.kind === "turnin") && l.npc !== undefined && !friends.includes(l.npc) && named(db.npcs, l.npc)) friends.push(l.npc);
  const targets = {};
  if (enemies.length) {
    const here = step.at && !zoneOnly(step.at) ? toPoint(db, step.at.zone, step.at.x, step.at.y) : null;
    const far = (id) => (here ? Math.min(Infinity, ...spawnPoints(db, "npc", id).map((p) => distance(here, p))) : Infinity);
    const ranked = enemies.map((id) => ({ id, d: far(id) })).sort((a, b) => a.d - b.d || a.id - b.id);
    targets.enemy = ranked.slice(0, MAX_TARGETS).map((e) => e.id);
  }
  if (friends.length) targets.friend = friends;
  if (targets.enemy || targets.friend) step.targets = targets;

  step.id = stepId(step);
  return step;
}

// The lines in order as <letter><id> joined by "." (the same token twice in a row once), then "@<zone>" when the step
// has a goto, grind or sethearth line.
function stepId(step) {
  const tokens = [];
  let zoned = false;
  for (const l of step.lines) {
    let t;
    switch (l.kind) {
      case "accept": t = `a${l.quest}`; break;
      case "turnin": t = `t${l.quest}`; break;
      case "objective": t = `o${l.quest}`; break;
      case "getflight": t = `f${l.node}`; break;
      case "fly": t = `y${l.from}-${l.to}`; break;
      case "transport": t = `x${l.to.zone}`; break;
      case "goto": t = `g${l.at.zone}`; zoned = true; break;
      case "hearth": t = "h"; break;
      case "sethearth": t = "b"; zoned = true; break;
      case "grind": t = `l${l.level}`; zoned = true; break;
      default: throw new Error(`no step id letter for ${l.kind}`);
    }
    if (tokens[tokens.length - 1] !== t) tokens.push(t);
  }
  const zone = step.at ? step.at.zone : step.lines[0].at ? step.lines[0].at.zone : undefined;
  return tokens.join(".") + (zoned && zone !== undefined ? `@${zone}` : "");
}

function flatten(steps) {
  const out = [];
  for (const step of steps) {
    const place = (line) => { const p = line.at || step.at; return p ? bare(p) : undefined; };
    const objectives = new Set(), accepts = new Set();
    for (const line of step.lines) {
      let a = null;
      switch (line.kind) {
        case "accept": // one action for the lines of an any-of gate (one accept line per prerequisite, planner/sections.js)
          if (accepts.has(line.quest)) break;
          accepts.add(line.quest);
          a = { action: line.kind, quest: line.quest, at: place(line) };
          if (line.npc !== undefined) a.npc = line.npc; else if (line.object !== undefined) a.object = line.object;
          break;
        case "turnin":
          a = { action: line.kind, quest: line.quest, at: place(line) };
          if (line.npc !== undefined) a.npc = line.npc; else if (line.object !== undefined) a.object = line.object;
          break;
        case "objective":
          if (objectives.has(line.quest)) break;
          objectives.add(line.quest);
          a = { action: "objective", quest: line.quest, at: place(line) };
          for (const k of ["npc", "object", "item"]) if (line[k] !== undefined) a[k] = line[k];
          break;
        case "getflight": a = { action: "getflight", node: line.node, at: place(line) }; if (line.npc !== undefined) a.npc = line.npc; break;
        case "sethearth": a = { action: "sethearth", at: place(line) }; if (line.npc !== undefined) a.npc = line.npc; break;
        case "fly": a = { action: "fly", from: line.from, to: line.to, at: place(line) }; break;
        case "goto": a = { action: "travel", at: bare(line.at) }; break;
        case "transport": a = { action: "transport", kind: line.mode, at: bare(line.at), to: bare(line.to) }; break;
        case "hearth": a = { action: "hearth", to: bare(line.to) }; break;
        case "grind": a = { action: "grind", level: line.level, at: place(line) }; break;
        default: break; // lines with no format 2 counterpart (train, vendor, notes, ...)
      }
      if (!a) continue;
      if (a.at === undefined) delete a.at;
      const when = line.when || step.when;
      if (when) a.when = JSON.parse(JSON.stringify(when));
      out.push(a);
    }
  }
  return out;
}

module.exports = { bundleSteps, flatten, hubOrder, stepId, RADIUS, BUNDLE_YARDS, HUB_YARDS, OWN_PLACE_YARDS, OBJECTIVE_YARDS };
