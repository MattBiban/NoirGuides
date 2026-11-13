// Noir Guides, GPLv3. See LICENSE.
// Class trainer visits: regular class training written into the route (task P3 in
// docs/superpowers/plans/2026-11-11-guide-rebuild.md, owner requirement 2026-11-11).
//
//   addClassTraining(db, sections, faction, options) -> sections
//       new section and step lists; the steps given are reused unchanged, the visits are new steps
//       options: { graph: lib/travel.js graph (for travelPlan), classes: [class tokens] (default all nine),
//                  levelOf(cls, step) -> { start, end, clock }: that class's estimated level at the step and the
//                  seconds played by then (planner/validate3.js estimateSteps); without it, each section's levels are
//                  spread evenly from minLevel to maxLevel - OUTLEVEL_MARGIN and the hearthstone is never used,
//                  notes: an array that receives { cls, from, to, why } for every stretch of more than GAP_LEVELS
//                  levels without a visit between level 4 and 58,
//                  margin: VISIT_MARGIN by default, townStop: false places a visit where it falls due, not at the next town stop }
//   classTrainers(db, cls, faction) -> [{ npc, points }]
//
// A visit is the step
//   { id = "t<CLASS>-<level>", when = { class = <CLASS> }, at = <trainer>, minLevel = <level>,
//     lines = { { kind = "train", class, level, npc }, { kind = "selljunk", npc, at } } }
// with the selljunk line only at levels up to SELL_JUNK_LEVEL (20), where training can cost more than the character
// carries: its npc is the nearest merchant (QuestieDB's vendor flag, lib/db.js) friendly to the faction in the
// trainer's zone within TRAINER_YARDS of the trainer, lowest NPC ID on a tie, and its at is that merchant's spawn; with
// no such merchant the line is left out. The engine shows it only when the bags hold grey items and the money may not
// cover the training (NoirGuides/Lines.lua, check.selljunk). Trainer prices are in none of the data.
// put right before the step it is written at (a trip's way there and back as steps around it, below). For each class, walking the sections in order over the steps that apply
// to the class (no profession step) and have a place:
//   - at the first step where the class's estimated level has reached an even level at least VISIT_EVERY above the
//     last visit, with a trainer of the class standing within TRAINER_YARDS of the step's place: a visit at that even
//     level
//     (the level reached is the estimate less VISIT_MARGIN, everywhere below). When that step hands nothing in, the
//     visit waits for the next step that hands a quest in with such a trainer near (a town stop), as long as the
//     class has not reached VISIT_EVERY levels more; else it is written where it fell due
//   - else, once FORCE_AFTER levels have passed since the last visit, at the first step in a zone where such a trainer
//     stands: a visit at the level reached
//   - a visit is only written when the walk there and back from the step's place (lib/travel.js travelPlan, on foot,
//     no flights) is at most MAX_DETOUR_SECONDS; of several trainers, the shortest detour, then the lowest NPC ID
//   - else, once TRIP_AFTER levels have passed since the last visit, a trip, written as the steps of its way there,
//     the visit, and the steps of its way back (tripSteps: goto, getflight, fly, transport and hearth lines) (the project lead's P3 follow-up): the way
//     from the step before to a trainer and on to the step, by travelPlan with the flight points the route has
//     learned by then and the hearthstone, takes a flight or the hearthstone and adds at most MAX_TRIP_SECONDS to the
//     way from the step before to the step. Within the level the trip falls due at, the first step that passes a
//     flight master (a getflight or fly line) and fits is taken; else the first step that fits. A trip is written at
//     the level reached and says how it goes in the step's text. The hearthstone is used only with a clock: when an
//     hour has passed since the route's (or a trip's) last hearth and an hour passes before its next, bound at the
//     route's last sethearth
// A class trainer is a QuestieDB NPC whose sub name is "<Class> Trainer" ("Warrior Trainer"), friendly to the faction,
// with a known spawn. The spells themselves are not listed: the trainer window shows them and the automation buys them.
const { toPoint, distance, spawnPoints } = require("../lib/geo");
const { travelPlan, toSteps, ESTIMATES } = require("../lib/travel");

const TRAINER_YARDS = 300;
// A visit is placed where the class's estimate is at least its level plus this much of a level. Players fall behind
// the estimate (quests skipped, fights avoided): about 1,000 XP at the low levels, which is 0.13 to 0.28 of a level
// from level 6 to 10 (3,600 to 7,600 XP a level), so a visit at exactly the level often meets a player still under it.
const VISIT_MARGIN = 0.3;
const MAX_DETOUR_SECONDS = 120;
const VISIT_EVERY = 2;
const FORCE_AFTER = 6;
const TRIP_AFTER = 4;
const MAX_TRIP_SECONDS = 300;
const GAP_LEVELS = 6;        // a longer stretch without a visit is noted with the reason
const GAP_FROM = 4, GAP_TO = 58;
const HEARTH_COOLDOWN = 3600; // lib/xp.js PACE.HEARTH_COOLDOWN
const NPC_RADIUS = 10; // planner/bundle.js RADIUS.npc
const DOCK_RADIUS = 15, GOTO_RADIUS = 20; // planner/bundle.js RADIUS.dock, RADIUS.goto
const OUTLEVEL_MARGIN = 3; // planner/sections.js
const SELL_JUNK_LEVEL = 20; // visits up to this level carry a "sell your grey items" line
const ALL = ["DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR"];

const zoneOnly = (p) => p.x === 0 && p.y === 0;
const round2 = (n) => Math.round(n * 100) / 100;
const list = (v) => (Array.isArray(v) ? v : [v]);
function forClass(when, cls) {
  if (!when) return true;
  if (when.profession !== undefined) return false;
  if (when.class !== undefined && !list(when.class).includes(cls)) return false;
  if (when.notClass !== undefined && list(when.notClass).includes(cls)) return false;
  return true;
}
const title = (cls) => `${cls[0]}${cls.slice(1).toLowerCase()} Trainer`;

// Merchants friendly to the faction with a known spawn: [{ npc, points }], by NPC ID.
function merchants(db, faction) {
  const letter = faction[0];
  const out = [];
  for (const npc of db.npcs.values()) {
    if (!npc.vendor || !(npc.friendly || "").includes(letter)) continue;
    const points = spawnPoints(db, "npc", npc.id);
    if (points.length) out.push({ npc: npc.id, points });
  }
  return out.sort((a, b) => a.npc - b.npc);
}

// The merchant nearest to a point, in its zone and within TRAINER_YARDS: { npc, point } or null (lowest ID on a tie).
function nearestMerchant(list, point) {
  let pick = null;
  for (const m of list) for (const p of m.points) {
    if (p.zone !== point.zone) continue;
    const d = distance(point, p);
    if (!(d <= TRAINER_YARDS)) continue;
    if (!pick || d < pick.d || (d === pick.d && m.npc < pick.npc)) pick = { npc: m.npc, point: p, d };
  }
  return pick;
}

function classTrainers(db, cls, faction) {
  const want = title(cls), letter = faction[0];
  const out = [];
  for (const npc of db.npcs.values()) {
    if (npc.subName !== want || !(npc.friendly || "").includes(letter)) continue;
    const points = spawnPoints(db, "npc", npc.id);
    if (points.length) out.push({ npc: npc.id, points });
  }
  return out.sort((a, b) => a.npc - b.npc);
}

// Each section's levels spread evenly, for callers that have no estimate.
function evenLevels(sections) {
  const map = new Map();
  for (const s of sections) {
    const end = Math.max(s.minLevel, (s.maxLevel || s.minLevel) - OUTLEVEL_MARGIN);
    s.steps.forEach((step, i) => {
      const l = s.minLevel + ((end - s.minLevel) * i) / Math.max(1, s.steps.length);
      map.set(step, { start: l, end: l });
    });
  }
  return (cls, step) => map.get(step);
}

// Seconds on foot between two points for a character of `level`.
function walker(db, graph, faction) {
  const cache = new Map();
  return (from, to, level) => {
    const key = `${from.zone},${from.x},${from.y}>${to.zone},${to.x},${to.y}@${level >= ESTIMATES.MOUNT_LEVEL ? "m" : "r"}`;
    if (cache.has(key)) return cache.get(key);
    let seconds;
    if (graph) seconds = travelPlan(db, graph, { faction, level, flights: new Set(), hearth: null }, from, to, { pickups: false }).seconds;
    else seconds = from.continent === to.continent ? (distance(from, to) * ESTIMATES.WALK_DETOUR) / (level >= ESTIMATES.MOUNT_LEVEL ? ESTIMATES.MOUNT_SPEED : ESTIMATES.RUN_SPEED) : Infinity;
    cache.set(key, seconds);
    return seconds;
  };
}

// The fastest way between two points for a trip: flights over the learned nodes, the hearthstone when `hearth` is a
// point; { seconds, flies, hearths }.
function tripper(db, graph, faction) {
  return (from, to, level, flights, hearth) => {
    if (!graph) return { seconds: Infinity, flies: false, hearths: false };
    const plan = travelPlan(db, graph, { faction, level, flights, hearth: hearth || null }, from, to, { pickups: false });
    return { seconds: plan.seconds, flies: plan.legs.some((l) => l.action === "fly"), hearths: plan.legs.some((l) => l.action === "hearth"), legs: plan.legs };
  };
}

// A trip's legs (lib/travel.js travelPlan) as format 3 steps of the class, with IDs <visit id>:<part><k>: a goto for a
// walk into another zone, a getflight, a fly, a transport and a hearth line, each on its own step (walking inside a
// zone is no step: the next step's place leads there).
function tripSteps(legs, cls, id, part) {
  const bare = (p) => ({ zone: p.zone, x: p.x, y: p.y });
  return toSteps(legs || []).map((a, k) => {
    const step = { id: `${id}:${part}${k + 1}`, when: { class: cls } };
    switch (a.action) {
      case "travel": step.lines = [{ kind: "goto", at: { ...bare(a.at), r: GOTO_RADIUS } }]; break;
      case "getflight": step.at = { ...bare(a.at), r: NPC_RADIUS }; step.lines = [{ kind: "getflight", node: a.node, ...(a.npc !== undefined ? { npc: a.npc } : {}) }]; break;
      case "fly": step.at = { ...bare(a.at), r: NPC_RADIUS }; step.lines = [{ kind: "fly", from: a.from, to: a.to }]; break;
      case "transport": step.at = { ...bare(a.at), r: DOCK_RADIUS }; step.lines = [{ kind: "transport", mode: a.kind, at: { ...bare(a.at), r: DOCK_RADIUS }, to: bare(a.to) }]; break;
      case "hearth": step.lines = [{ kind: "hearth", to: bare(a.to) }]; break;
      default: throw new Error(`a trip has a leg ${a.action}`);
    }
    return step;
  });
}
const zoneName = (db, zone) => { const a = db.areas.get(zone); return a && a.name ? a.name : undefined; };

function addClassTraining(db, sections, faction, options = {}) {
  const classes = (options.classes || ALL).slice().sort();
  const levelOf = options.levelOf || evenLevels(sections);
  const margin = options.margin === undefined ? VISIT_MARGIN : options.margin;
  const townStop = options.townStop !== false;
  const seconds = walker(db, options.graph, faction);
  const travel = tripper(db, options.graph, faction);
  const inserts = new Map(); // step -> visits to put before it, in class order
  const notes = options.notes;
  let vendors = null; // merchants(db, faction), read at the first visit that wants one
  const sellLine = (point) => {
    vendors = vendors || merchants(db, faction);
    const m = nearestMerchant(vendors, point);
    return m ? { kind: "selljunk", npc: m.npc, at: { zone: m.point.zone, x: round2(m.point.x), y: round2(m.point.y), r: NPC_RADIUS } } : null;
  };
  const pointOf = (p) => (p && !zoneOnly(p) ? toPoint(db, p.zone, p.x, p.y) : null);
  // Where a step leaves the character: the end of its last move line (a boat's landing, a flight's destination, the
  // hearthstone's inn, a goto's place), else nothing (the step's own place).
  const nodePoint = (id) => {
    const node = options.graph && options.graph.nodes && options.graph.nodes.get(id);
    const master = node && node.masters && node.masters[faction];
    return master ? master.point : null;
  };
  const endOf = (step) => {
    for (let k = step.lines.length - 1; k >= 0; k--) {
      const l = step.lines[k];
      if (l.kind === "transport" || l.kind === "hearth") return pointOf(l.to);
      if (l.kind === "goto") return pointOf(l.at);
      if (l.kind === "fly") return nodePoint(l.to);
    }
    return null;
  };
  for (const cls of classes) {
    const trainers = classTrainers(db, cls, faction);
    if (!trainers.length) continue;
    // the class's walk: its steps with what it knows before each (flight points, hearthstone bind, clock)
    const walk = [];
    {
      const flights = new Set();
      let bind = null;
      for (const section of sections) for (const step of section.steps) {
        if (!forClass(step.when, cls)) continue;
        const estimate = levelOf(cls, step);
        // a walk (only goto lines) ends at its place: the character is not there before it, so no visit goes before it
        const walking = step.lines.length > 0 && step.lines.every((l) => l.kind === "goto");
        walk.push({ step, estimate, flights: new Set(flights), bind, here: step.at && !walking ? pointOf(step.at) : null, after: endOf(step),
          master: step.lines.some((l) => l.kind === "getflight" || l.kind === "fly"),
          hearths: step.lines.some((l) => l.kind === "hearth") });
        for (const l of step.lines) {
          if (l.kind === "getflight") flights.add(l.node);
          if (l.kind === "fly") { flights.add(l.from); flights.add(l.to); }
          if (l.kind === "sethearth") bind = pointOf(l.at || step.at);
        }
      }
    }
    const hearthClocks = walk.filter((w) => w.hearths && w.estimate && w.estimate.clock !== undefined).map((w) => w.estimate.clock);
    const tripHearths = [];   // the clocks of the trips that use the hearthstone
    const visitLevels = [];
    const cheapest = {};      // last visit level -> the cheapest trip (seconds added) seen after it while none fitted
    let last = 0;
    let pending = null;       // a trip that fits, waiting for a flight master within its level
    let held = null;          // a visit near a trainer, waiting for the next talk stop near one
    let prevPlace = null;     // where the class's step before leaves the character
    let finalLevel = 0;
    const write = (step, level, npc, point, text, way) => {
      last = level;
      visitLevels.push(level);
      if (!inserts.has(step)) inserts.set(step, []);
      // minLevel: a character under the level is shown a grind first (spec 3.7), never a visit it cannot finish.
      const visit = { id: `t${cls}-${level}`, when: { class: cls }, at: { zone: point.zone, x: round2(point.x), y: round2(point.y), r: NPC_RADIUS }, minLevel: level,
        lines: [{ kind: "train", class: cls, level, npc }] };
      if (level <= SELL_JUNK_LEVEL) { const sell = sellLine(point); if (sell) visit.lines.push(sell); }
      if (text) visit.text = text;
      if (way) inserts.get(step).push(...tripSteps(way.there.legs, cls, visit.id, "go"));
      inserts.get(step).push(visit);
      if (way) inserts.get(step).push(...tripSteps(way.back.legs, cls, visit.id, "back"));
    };
    const commit = (c) => {
      write(c.step, c.level, c.pick.npc, c.pick.point, c.pick.text, c.pick.way);
      if (c.pick.hearths) tripHearths.push(c.clock);
    };
    // the hearthstone's bind when it may be used at this clock: an hour after the last hearth, an hour before the next
    const hearthAt = (w) => {
      const clock = w.estimate.clock;
      if (!w.bind || clock === undefined) return null;
      const lastHearth = Math.max(-Infinity, ...hearthClocks.filter((c) => c <= clock), ...tripHearths);
      const nextHearth = Math.min(Infinity, ...hearthClocks.filter((c) => c > clock));
      return clock - lastHearth >= HEARTH_COOLDOWN && nextHearth - clock >= HEARTH_COOLDOWN + MAX_TRIP_SECONDS ? w.bind : null;
    };
    // the cheapest trip from the step before to a trainer and on to this step that takes a flight or the hearthstone:
    // { npc, point, added, hearths, text } or null
    const bestTrip = (w, level) => {
      const from = prevPlace || w.here;
      const hearth = hearthAt(w);
      const direct = travel(from, w.here, level, w.flights, null).seconds;
      let pick = null;
      for (const t of trainers) for (const p of t.points) {
        const ways = [];
        const there = travel(from, p, level, w.flights, null);
        ways.push({ there, back: travel(p, w.here, level, w.flights, hearth) });
        if (hearth) {
          const thereH = travel(from, p, level, w.flights, hearth);
          if (thereH.hearths) ways.push({ there: thereH, back: travel(p, w.here, level, w.flights, null) });
        }
        for (const o of ways) {
          const added = o.there.seconds + o.back.seconds - direct;
          if (!(added < Infinity) || !(o.there.flies || o.back.flies || o.there.hearths || o.back.hearths)) continue;
          if (!pick || added < pick.added || (added === pick.added && t.npc < pick.npc)) pick = { npc: t.npc, point: p, added, way: o };
        }
      }
      if (!pick) return null;
      const city = zoneName(db, pick.point.zone) || "the trainer";
      const { there, back } = pick.way;
      pick.hearths = there.hearths || back.hearths;
      pick.text = there.hearths ? `Use your hearthstone to reach ${city} for class training, then return.`
        : back.hearths ? `Fly to ${city} for class training, then use your hearthstone to return.`
          : `Fly to ${city} for class training, then return.`;
      return pick;
    };
    for (const w of walk) {
      const { step, estimate, here } = w;
      if (!estimate) continue;
      finalLevel = Math.max(finalLevel, Math.floor(estimate.end));
      // the level the class is sure to have here: VISIT_MARGIN of a level below the estimate
      const level = Math.floor(estimate.start - margin + 1e-9);
      if (pending && level >= pending.level + 1) { commit(pending); pending = null; }
      if (!here) {
        if (w.after) prevPlace = w.after; // a hearth or goto step without a place of its own still moves the character
        continue;
      }
      const even = level - (level % 2);
      let visit = null;
      const best = (near) => {
        let pick = null;
        for (const t of trainers) for (const p of t.points) {
          if (!near(p)) continue;
          const s = seconds(here, p, level) + seconds(p, here, level);
          if (s <= MAX_DETOUR_SECONDS && (!pick || s < pick.s || (s === pick.s && t.npc < pick.npc))) pick = { npc: t.npc, point: p, s };
        }
        return pick;
      };
      const nearTrainer = () => best((p) => distance(here, p) <= TRAINER_YARDS);
      const talkStop = step.lines.some((l) => l.kind === "turnin");
      if (held) {
        // a visit that is due waits for the next stop that hands quests in near a trainer
        const pick = talkStop ? nearTrainer() : null;
        if (pick) {
          write(step, held.level, pick.npc, pick.point);
          held = null;
          prevPlace = w.after || here;
          continue;
        }
        if (level < held.level + VISIT_EVERY) { prevPlace = w.after || here; continue; }
        write(held.step, held.level, held.pick.npc, held.pick.point); // no such stop came in time: where it fell due
        held = null;
      }
      if (even >= 2 && even >= last + VISIT_EVERY) {
        const pick = nearTrainer();
        if (pick && townStop && !talkStop) { held = { step, level: even, pick }; pending = null; prevPlace = w.after || here; continue; }
        if (pick) visit = { level: even, pick };
      }
      if (!visit && level >= 2 && level >= last + FORCE_AFTER) {
        const pick = best((p) => p.zone === here.zone);
        if (pick) visit = { level, pick };
      }
      if (visit) {
        pending = null;
        write(step, visit.level, visit.pick.npc, visit.pick.point);
      } else if (level >= 2 && level >= last + TRIP_AFTER && (!pending || w.master)) {
        const pick = bestTrip(w, level);
        if (pick && pick.added <= MAX_TRIP_SECONDS) {
          const trip = { step, level, pick, clock: estimate.clock };
          if (w.master) { pending = null; commit(trip); } else pending = trip;
        } else if (pick && !(cheapest[last] <= pick.added)) cheapest[last] = Math.ceil(pick.added);
      }
      prevPlace = w.after || here;
    }
    if (held) write(held.step, held.level, held.pick.npc, held.pick.point);
    if (pending) commit(pending);
    if (notes) {
      const points = [...visitLevels.filter((l) => l <= GAP_TO), Math.min(GAP_TO, finalLevel)];
      for (let i = 1; i < points.length; i++) {
        const from = points[i - 1], to = points[i];
        if (to - from <= GAP_LEVELS || to <= GAP_FROM) continue;
        const why = cheapest[from] !== undefined ? `the cheapest trip to a trainer adds ${cheapest[from]} seconds (at most ${MAX_TRIP_SECONDS})`
          : "no trainer can be reached by a flight over the learned flight points or by the hearthstone";
        notes.push({ cls, from, to, why });
      }
    }
  }
  return sections.map((s) => ({ ...s, steps: s.steps.flatMap((step) => [...(inserts.get(step) || []), step]) }));
}

module.exports = { addClassTraining, classTrainers, merchants, nearestMerchant, evenLevels, SELL_JUNK_LEVEL, TRAINER_YARDS, VISIT_MARGIN, MAX_DETOUR_SECONDS, VISIT_EVERY, FORCE_AFTER, TRIP_AFTER, MAX_TRIP_SECONDS, GAP_LEVELS };
