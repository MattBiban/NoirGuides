// Noir Guides, GPLv3. See LICENSE.
// Which quests a character takes. One set of rules serves the route itself and the look-ahead that picks the next
// zone (planner/zonepick.js), so what the look-ahead expects of a zone is what the route then does there.
//   S, the state the rules read: { level, done, log, hopped }, where done has has(), log is a Map of quest ID ->
//   { needsObjective } (or anything with has, keys, entries and size), and hopped is the set of neighbouring zones
//   this session has already crossed into.
const { questXp, objectiveXp } = require("../lib/xp");
const { canAccept } = require("../lib/quests");
const { CHOICES: C } = require("./tuning");

function makePolicy(ctx) {
  const { info, byZone } = ctx;

  // worth doing at this level: it gives XP, and its creatures are not too far above the player
  const worth = (i, level) => questXp(i.q.level, level) + objectiveXp(i.q, level) > 0 && !(i.kills && i.q.level > level + C.HARD);
  // true when the quest's objective is over the border of the zone it starts in and is done from there (a hop)
  const hops = (i) => i.objNear && i.obj.point.zone !== i.endZone;
  // true when the quest's objective is done in a session of this zone
  const objectiveIn = (i, zone) => i.obj.point.zone === zone || (hops(i) && i.zone === zone);

  // A quest with a part in another zone ("carry", "far") is never travelled for on its own: it is taken when the
  // route will be in those zones anyway, and each part is done when a session is there.
  const travelling = (S) => { let n = 0; for (const quest of S.log.keys()) if (info.get(quest).kind !== "local") n++; return n; };
  // the log already has something to do in the zone that was brought from elsewhere
  const business = (S, zone, but) => {
    for (const [quest, entry] of S.log.entries()) {
      const other = info.get(quest);
      if (quest !== but && other.zone !== zone && (entry.needsObjective ? other.obj.point.zone === zone : other.endZone === zone)) return true;
    }
    return false;
  };
  // Quests the zone offers within CARRY_AHEAD levels that are still worth doing then. later: only the ones that
  // cannot be done yet (the level, or creatures too far above the player): those bring the route back to the zone.
  function offers(S, zone, later) {
    let n = 0;
    for (const other of byZone.get(zone) || []) {
      const q = other.q;
      if (S.done.has(q.id) || S.log.has(q.id) || q.minLevel > S.level + C.CARRY_AHEAD || questXp(q.level, Math.max(S.level, q.minLevel)) <= 0) continue;
      if (!later || q.minLevel > S.level || (other.kills && q.level > S.level + C.HARD)) n++;
    }
    return n;
  }
  function travelWanted(i, S) {
    if (ctx.linkQuests.has(i.q.id)) return true;
    if (S.level >= C.LATE_LEVEL || travelling(S) >= C.MAX_CARRY) return false;
    // relaxed: nothing else is left anywhere, so a quest is taken even where the route was not going
    // S.plan: the zones of the visits the look-ahead has planned next; a copy played out by the look-ahead has none
    const going = (zone) => !!S.relaxed || business(S, zone, i.q.id) || (S.plan ? S.plan.has(zone) : offers(S, zone, false) >= C.CARRY_MIN_QUESTS);
    if (i.obj && i.obj.point.zone !== i.zone && !hops(i) && !going(i.obj.point.zone)) return false;
    if (i.endZone !== i.zone) return going(i.endZone);
    // out and back: the route has to return to this zone as well. Not even when relaxed: a quest that is two
    // crossings of a border for one reward is only taken when the route comes back here anyway
    return business(S, i.zone, i.q.id) || (S.plan ? S.plan.has(i.zone) : offers(S, i.zone, true) >= C.RETURN_MIN_QUESTS);
  }
  function wanted(i, S) {
    if (!canAccept(i.q, S) || !worth(i, S.level)) return false;
    // A session crosses into each neighbour once, at its end, for every objective waiting there. A quest that
    // needs the crossing again is left for the next visit.
    if (hops(i) && S.hopped && S.hopped.has(i.obj.point.zone)) return false;
    return i.kind === "local" || travelWanted(i, S);
  }
  return { worth, hops, objectiveIn, wanted };
}

module.exports = { makePolicy };
