// Noir Guides, GPLv3. See LICENSE.
// Planner v2: one route per race, in route format 2.
//   zone commitment   the route works one zone until nothing is left to do there (session), then picks the next
//   hub batching      at a hub everything is handed in and taken; the objectives are one loop; the hub is returned
//                     to once, when all its quests are ready (planner/session.js orders the loop)
//   cost-based        every way is costed in seconds by lib/travel.js travelPlan, and its legs become the steps
//   pacing            XP and time come from lib/xp.js; a grind step bridges one level, never two in a row
// The route's state changes in one place, emit(), from nothing but the step it is given: that is the rule the
// validator replays on its own, so the two agree on position, level and clock at every step.
const { zoneOf, toPoint, distance } = require("../lib/geo");
const { PACE, gain, questXp, objectiveXp, objectiveSeconds, walkXp, grindSeconds } = require("../lib/xp");
const { ESTIMATES, walkYards, walkSeconds, travelPlan } = require("../lib/travel");
const { CHOICES: C } = require("./tuning");
const { emptyGraph, plannerGraph, buildContext } = require("./context");
const { makePolicy } = require("./policy");
const { nextTask } = require("./session");
const { bestZone, urgentZone } = require("./zonepick");

function planRoute(db, ch, options = {}) {
  const maxLevel = options.maxLevel || 60;
  const id = `${ch.faction.toLowerCase()}-${ch.race.toLowerCase()}`;
  const graph = plannerGraph(options.graph || emptyGraph(db));
  const ctx = buildContext(db, ch, graph, options.inns || []);
  const { info, byZone, bands } = ctx;
  const st = { level: 1, xp: 0, pos: null, started: false, zone: zoneOf(db, ch.startArea), log: new Map(), done: new Set(), have: new Set(),
    flights: new Set(), hearth: null, lastHearth: -Infinity, clock: 0, steps: [], levelAt: [0, 0], links: new Map(),
    announce: false, skip: new Set(), barren: new Set(), chosen: false, finishing: false, hopped: new Set(), grinds: 0, relaxed: false, urgent: false };

  const speed = () => (st.level >= ESTIMATES.MOUNT_LEVEL ? ESTIMATES.MOUNT_SPEED : ESTIMATES.RUN_SPEED);
  const wrapUp = () => st.level >= maxLevel || st.finishing; // no new quests: what is in the log is finished
  const traveller = () => ({ faction: ch.faction, level: st.level, flights: st.flights, hearth: st.hearth,
    hearthReady: st.clock - st.lastHearth >= PACE.HEARTH_COOLDOWN + C.HEARTH_MARGIN, quests: st.have });
  // seconds from one place to another: a short walk inside a zone is a straight line, anything else is planned
  const seconds = (from, to) => {
    if (from.zone === to.zone) {
      const walk = (distance(from, to) * ESTIMATES.WALK_DETOUR) / speed();
      if (walk <= C.SHORT_WALK_SECONDS) return walk;
    }
    return travelPlan(db, graph, traveller(), from, to, { pickups: false }).seconds;
  };
  const secondsAt = (from, to, level) => travelPlan(db, graph, { ...traveller(), level }, from, to, { pickups: false }).seconds;
  const policy = makePolicy(ctx);
  const view = { ctx, policy, st, secondsAt }; // what planner/zonepick.js reads

  // The one place the route's state changes. A step with a place is walked to first; then it does its work.
  function emit(step) {
    const before = st.level;
    if (step.at) {
      const p = toPoint(db, step.at.zone, step.at.x, step.at.y);
      if (st.started) {
        const walk = walkYards(graph, st.pos, p);
        if (walk) st.clock += (walk.yards * ESTIMATES.WALK_DETOUR) / speed();
        if (st.pos.zone === p.zone) gain(st, walkXp(distance(st.pos, p), bands.get(p.zone), st.level));
      }
      st.pos = p;
      st.started = true;
    }
    const i = step.quest !== undefined ? info.get(step.quest) : null;
    if (step.action === "accept") {
      st.log.set(step.quest, { needsObjective: !!i.obj });
      st.have.add(step.quest);
      st.clock += PACE.TALK_SECONDS;
    } else if (step.action === "objective") {
      st.log.get(step.quest).needsObjective = false;
      gain(st, objectiveXp(i.q, st.level));
      st.clock += objectiveSeconds(i.q);
    } else if (step.action === "turnin") {
      st.log.delete(step.quest);
      st.done.add(step.quest);
      gain(st, questXp(i.q.level, st.level));
      st.clock += PACE.TALK_SECONDS;
    } else if (step.action === "getflight") {
      st.flights.add(step.node);
      st.clock += ESTIMATES.LEARN_SECONDS;
    } else if (step.action === "sethearth") {
      st.hearth = st.pos;
      st.clock += PACE.TALK_SECONDS;
    } else if (step.action === "grind") {
      const spent = grindSeconds(st.level, st.xp);
      st.clock += spent;
      // A character ahead of the estimate (a class with its own quests, planner/classes.js) skips the grind and its
      // time with it, so that time does not count towards the hearthstone's cooldown: the route plays for everyone.
      st.lastHearth += spent;
      st.level = step.level;
      st.xp = 0;
    }
    if (i) { st.barren.clear(); st.chosen = false; st.announce = false; }
    st.steps.push(step);
    for (let level = before + 1; level <= st.level; level++) st.levelAt[level] = st.steps.length - 1;
    if (st.level > before) st.relaxed = false;
  }
  // the legs of a flight, a transport and a hearth move the player without a walk
  function emitLeg(leg) {
    const place = (p) => ({ zone: p.zone, x: Math.round(p.x * 100) / 100, y: Math.round(p.y * 100) / 100 });
    if (leg.action === "getflight") emit({ action: "getflight", node: leg.node, at: place(leg.at), npc: leg.npc });
    else if (leg.action === "fly") {
      emit({ action: "fly", from: leg.from, to: leg.to, at: place(leg.at) });
      st.clock += leg.seconds;
      st.pos = leg.land;
    } else if (leg.action === "transport") {
      const to = place(leg.to);
      emit({ action: "transport", kind: leg.kind, at: place(leg.at), to });
      st.clock += leg.seconds;
      st.pos = toPoint(db, to.zone, to.x, to.y);
      if (!leg.verified) st.links.set(leg.link, { id: leg.link, name: leg.name, kind: leg.kind, assumed: leg.assumed });
    } else if (leg.action === "hearth") {
      const to = place(leg.to);
      st.steps.push({ action: "hearth", to });
      st.clock += ESTIMATES.HEARTH_SECONDS;
      st.lastHearth = st.clock;
      st.pos = toPoint(db, to.zone, to.x, to.y);
    } else if (leg.action === "travel") emit({ action: "travel", at: place(leg.at) });
  }
  // Goes to a place by the fastest way and writes its legs as steps. A walk inside a zone is no step, and neither is
  // a single walk over the border inside a session (a hop to an objective next door): the next step's own place
  // leads there. false when there is no way.
  function go(target) {
    if (!st.started) return true; // the route begins wherever its first step is
    if (distance(st.pos, target) < 0.5) return true;
    const plan = travelPlan(db, graph, traveller(), st.pos, target);
    if (plan.seconds === Infinity) return false;
    const hop = !st.announce && plan.legs.length === 1;
    for (const leg of plan.legs) if (leg.action !== "walk" && !(hop && leg.action === "travel")) emitLeg(leg);
    return true;
  }

  // ---- what can be done -------------------------------------------------------------------------------------
  // which quests are taken is planner/policy.js; it reads st as it is (level, done, log, hopped)
  const { wanted, objectiveIn } = policy;

  function tasks(zone) {
    const out = [];
    for (const [quest, entry] of st.log) {
      const i = info.get(quest);
      if (entry.needsObjective) { if (objectiveIn(i, zone)) out.push({ kind: "objective", id: quest, i, point: i.obj.point }); }
      else if (i.endZone === zone) out.push({ kind: "turnin", id: quest, i, point: i.end.point });
    }
    if (wrapUp()) return out;
    if (st.log.size < C.LOG_LIMIT) {
      for (const i of byZone.get(zone) || []) if (wanted(i, st)) out.push({ kind: "accept", id: i.q.id, i, point: i.start.point });
    }
    for (const node of ctx.nodesByZone.get(zone) || []) {
      if (!st.flights.has(node.id) && st.pos.continent === node.point.continent && walkSeconds(graph, st.level, st.pos, node.point) <= C.GETFLIGHT_SECONDS) {
        out.push({ kind: "getflight", id: node.id, node, point: node.point });
      }
    }
    return out;
  }
  const key = (t) => `${t.kind}:${t.id}`;
  const apart = (a, b) => distance(a, b) <= C.HUB_YARDS;

  function nextTarget() {
    // an urgent visit (zonepick.js rule 1) does the quests a transport asks for or that bring the player in, and
    // fetches the flight points on the way; the rest of the zone waits until they are handed in
    const urgent = (t) => t.kind === "getflight" || ctx.linkQuests.has(t.id);
    const all = tasks(st.zone).filter((t) => !st.skip.has(key(t)) && (!st.urgent || urgent(t)));
    const objectives = all.filter((t) => t.kind === "objective");
    // return once: a hub waits until the objectives of its quests are done
    let candidates = [];
    const waiting = [];
    for (const t of all) (t.kind === "turnin" && objectives.some((o) => apart(o.i.end.point, t.point)) ? waiting : candidates).push(t);
    // cross the border once: objectives next door wait until nothing is left on this side
    const hop = (t) => t.kind === "objective" && t.point.zone !== st.zone;
    if (candidates.some((t) => !hop(t) && t.kind !== "getflight")) candidates = candidates.filter((t) => !hop(t));
    for (const t of candidates) t.cost = seconds(st.pos, t.point);
    const between = (a, b) => walkSeconds(graph, st.level, a.point, b.point);
    const home = waiting.length ? (t) => Math.min(...waiting.map((w) => walkSeconds(graph, st.level, t.point, w.point))) : null;
    return nextTask(candidates, between, home);
  }
  const stepOf = (t) => {
    const place = t.kind === "accept" ? t.i.start : t.kind === "turnin" ? t.i.end : t.i.obj;
    const step = { action: t.kind, quest: t.id, at: place.at };
    if (place.npc !== undefined) step.npc = place.npc;
    else if (place.object !== undefined) step.object = place.object;
    if (t.kind === "objective" && place.item !== undefined) step.item = place.item;
    return step;
  };
  // Everything at the hub the player stands in: hand in what is ready, take what is offered, until nothing changes.
  function hub(anchor) {
    for (let guard = 0; guard < 200; guard++) {
      const open = tasks(st.zone).filter((t) => (t.kind === "accept" || t.kind === "turnin") && !st.skip.has(key(t)) && apart(anchor, t.point));
      if (!open.length) break;
      for (const t of open) t.cost = seconds(st.pos, t.point);
      const t = nextTask(open, (a, b) => walkSeconds(graph, st.level, a.point, b.point));
      if (!t || !go(t.point)) { for (const o of open) st.skip.add(key(o)); break; }
      emit(stepOf(t));
    }
    bindHearth(anchor);
  }
  // The hearthstone is bound at the hub's inn when one use from the farthest objective waiting in this zone saves time.
  function bindHearth(anchor) {
    if (wrapUp()) return;
    const inn = ctx.inns.filter((n) => n.point.zone === anchor.zone && apart(anchor, n.point)).sort((a, b) => distance(anchor, a.point) - distance(anchor, b.point) || a.npc - b.npc)[0];
    if (!inn || (st.hearth && distance(st.hearth, inn.point) < 1)) return;
    const objectives = tasks(st.zone).filter((t) => t.kind === "objective" && apart(t.i.end.point, anchor));
    if (!objectives.length) return;
    const back = Math.max(...objectives.map((t) => walkSeconds(graph, st.level, t.point, inn.point)));
    const detour = 2 * walkSeconds(graph, st.level, st.pos, inn.point) + PACE.TALK_SECONDS;
    if (back - ESTIMATES.HEARTH_SECONDS - detour < C.HEARTH_MIN_SAVING) return;
    if (go(inn.point)) emit({ action: "sethearth", at: inn.at, npc: inn.npc });
  }
  function perform(t) {
    if (!go(t.point)) { st.skip.add(key(t)); return; }
    if (t.kind === "getflight") {
      if (!st.flights.has(t.id)) emit({ action: "getflight", node: t.id, at: t.node.at, npc: t.node.npc }); // the way there may have fetched it
      return;
    }
    emit(stepOf(t));
    if (t.kind !== "objective") hub(st.pos);
    else if (t.point.zone !== st.zone) st.hopped.add(t.point.zone);
  }

  // ---- the route ----------------------------------------------------------------------------------------------
  // starting position: the giver of the lowest-level, lowest-ID quest in the starting zone
  const first = (byZone.get(st.zone) || []).slice().sort((a, b) => a.q.minLevel - b.q.minLevel || a.q.id - b.q.id)[0];
  st.pos = first ? first.start.point : toPoint(db, st.zone, 50, 50);
  // where the route is going after the starting zone: a quest that ends elsewhere is taken there only when the
  // route goes there (policy.js), as after every later choice of zone
  const opening = bestZone(view, { cap: maxLevel, here: true });
  if (opening.path) st.plan = new Set(opening.path[0] === st.zone ? opening.path.slice(1) : opening.path);

  for (let turn = 0; ; turn++) {
    if (turn >= C.MAX_ITERATIONS) throw new Error("planner did not finish for " + id);
    if (wrapUp() && !st.log.size) break;
    if (!st.pos) break; // a start zone without a map: nothing can be planned
    const t = nextTarget();
    if (t) { perform(t); continue; }
    if (st.urgent) {
      // the urgent part of this visit is done: the zone is worked like any other, unless another urgent task waits
      st.urgent = false;
      if (!urgentZone(view)) { st.chosen = true; continue; }
    }
    // the zone is spent (or was chosen and has nothing after all)
    if (st.chosen) st.barren.add(st.zone);
    const last = st.steps[st.steps.length - 1];
    const ground = !!last && last.action === "grind";
    const pick = bestZone(view, { wrapUp: wrapUp(), cap: maxLevel, ground });
    if (pick.zone) {
      st.zone = pick.zone; st.announce = true; st.chosen = !pick.urgent; st.urgent = !!pick.urgent; st.skip.clear(); st.hopped.clear();
      st.plan = pick.path ? new Set(pick.path.slice(1)) : null; // where the route is going after this zone
      continue;
    }
    if (wrapUp()) break; // quests in the log that no way leads to: the validator reports them
    if (!pick.grind) {
      // Nothing where the route was going: until the next level, quests are taken even where it was not going.
      if (!st.relaxed) { st.relaxed = true; st.barren.clear(); st.chosen = false; continue; }
      // Nothing anywhere at this level: one level of grinding when that opens something, or is the last level.
      // Otherwise the route ends here, short of the cap, once the log is empty.
      if (ground || (st.level + 1 < maxLevel && !bestZone(view, { level: st.level + 1 }).zone)) {
        st.finishing = true; st.barren.clear(); st.chosen = false;
        continue;
      }
    }
    st.grinds++;
    emit({ action: "grind", level: st.level + 1, at: { zone: st.pos.zone, x: Math.round(st.pos.x * 100) / 100, y: Math.round(st.pos.y * 100) / 100 } });
    st.barren.clear();
    st.chosen = false;
  }

  return { id, format: 2, race: ch.race, faction: ch.faction, steps: st.steps,
    stats: { quests: st.done.size, endLevel: st.level, levelAt: st.levelAt, seconds: Math.round(st.clock), links: [...st.links.values()].sort((a, b) => (a.id < b.id ? -1 : 1)) } };
}
module.exports = { planRoute };
