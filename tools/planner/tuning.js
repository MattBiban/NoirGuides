// Noir Guides, GPLv3. See LICENSE.
// The planner's choices: every number that decides what a route does next, with what it stands for. None of them
// is a game fact (those are in lib/xp.js PACE and lib/travel.js ESTIMATES); each is a preference, set once here.
const CHOICES = Object.freeze({
  LOG_LIMIT: 20,             // the classic quest log holds 20 quests (a fact, kept with the rest for the planner)
  HARD: 3,                   // a quest with fights is taken up to this many levels above the player: orange in the
                             // quest log at the most, never red. It was 0, then 2: with too few quests to take,
                             // routes ground 10 to 13 whole levels (0.5.0). At 3 a route has a quest for every level and
                             // grinds at most the end of level 59. A quest above the level is done because nothing at the
                             // level is left, not for choice: the look-ahead counts it for less (AHEAD_DISCOUNT)
  HARD_TALK: 4,              // the same for a quest without fights (a delivery, a talk): nothing in it can kill the player
  START_HARD: 2,             // ... and never less than this in the first levels, below START_UNTIL: a new character is
  START_UNTIL: 10,           //   handed quests one and two levels up by its own starting zone (a level 1 orc gets level 2
                             //   quests). Without it, when HARD was 0, a level 6 character was sent to another race's
                             //   starting zone for quests of its exact level. It changes nothing while HARD is this or more
  EASY: 5,                   // a quest more than this many levels below the player is left out, unless a travel link or
                             // another quest needs it (planner/policy.js). Down to five levels below a quest still gives
                             // its whole reward (lib/xp.js questXp), and its fights are quick. It was 3: quests that give
                             // their whole reward were left out, in routes that ground whole levels
  NEARBY: 1500,              // yards on foot: an objective over a zone border belongs to this zone when it is this close
                             // to one of the zone's quest places
  HUB_YARDS: 150,            // quest givers this close together are one hub: everything there is done in one stop
  READY_YARDS: 300,         // a hand-in that is ready and this close to the player is not left behind:
  LEAVE_YARDS: 500,         //   the route does not move farther than this while one waits (planner/leftbehind.js)
  TOWN_SECONDS: 60,          // quests to take or hand in within a minute's walk come before any objective
  SHORT_WALK_SECONDS: 60,    // a walk this short inside one zone is costed as a straight line, a longer way by travelPlan
  LOOK_AHEAD: 5,             // the next task is the first of the best order of the nearest five
  GATHER_SECONDS: 150,       // a quest to take within this walk comes before any objective: the givers around a hub
                             //   are all visited before the loop starts, so the loop is walked once with a fuller log
  LOOP_SHARE: 0.25,          // a hand-in away from the player waits while objectives are open: it comes first only when
                             //   it is at most this share of the way to the nearest of them (it is then on the way)
  RUN_SECONDS: 600,          // what breaking off a row of objectives for a quest giver costs when orders are compared:
                             //   objectives are done in one row unless the other order saves more than this
  QUEST_WALK_SECONDS: 120,   // the walking a quest takes inside its zone, for comparing visits before making them
  MAX_CARRY: 12,             // quests in the log with a part in another zone: the rest of the log stays free
  CARRY_MIN_QUESTS: 3,       // a quest with a part in another zone is taken when that zone has at least this many
  CARRY_AHEAD: 8,            //   quests to pick up within this many levels, so the route is going there anyway
  RETURN_MIN_QUESTS: 2,      // ... and, for a quest that comes back to be handed in, when the zone it starts in will
                             //   offer at least this many quests that cannot be done yet
  LATE_LEVEL: 60,            // from here on no quest with a part in another zone is taken. At the cap that is no limit of
                             //   its own: no quest is taken at 60 at all, and what is in the log is finished (plan.js
                             //   wrapUp). It was 59: the quests of level 59 with a part in another zone were left out
  HEARTH_MIN_SAVING: 60,     // the hearthstone is bound at a hub's inn when one use there saves at least a minute
  HEARTH_MARGIN: 600,        // seconds past the cooldown before the planner counts on the hearthstone: its clock is an estimate
  GETFLIGHT_SECONDS: 300,    // a flight point in the zone is fetched when it is this close on foot
  SEARCH_DEPTH: 8,           // the next zone is the first of the best sequence of this many visits,
  SEARCH_BEAM: 6,            //   with this many sequences kept after each visit,
  SEARCH_ZONES: 12,          //   each continued with the zones that have the most quests to offer (and the log's zones).
  SEARCH_TIME_XP: 2,         // XP a second of travel and work is worth when two sequences are compared: time breaks
                             //   ties between sequences, the XP of their visits decides
  SEARCH_TRAVEL_SHARE: 1, // ... and an hour on the way between zones costs this share of the level's XP on top: the way
                             //   earns nothing, so a zone across the sea has to be worth its crossing
  CROSSING_SECONDS: 3600,     // ... and a visit on another continent counts this much more of it: the boat or zeppelin has
                             //   to be waited for, and the way back is as long
  MIN_VISIT: 0.25,           // a zone is gone to when the visit there is worth at least this share of the player's level
                             //   (planner/zonepick.js rule 3): four such visits are a level. Smaller ones wait and grow
                             //   while a visit of that size is left anywhere
  LAST_VISITS: 3,            // ... and when none is, the small visits are made (rule 4): the next zone is the first of
                             //   the best sequence of this many of them. They used to wait while the rest of the level
                             //   was ground, unless this many reached the next level: that saved changes of zone (123 to
                             //   158 a route) and cost 10 to 12 grind steps of up to a whole level. Quests come before
                             //   grinding now, and the changes of zone are the price (planner/report.js MAX_ZONE_SHARE)
  PLAN_WALK_SHARE: 0.12,     // the fights on the way inside an open zone, as a share of a visit's XP, for comparing
                             //   visits before making them. Measured: walking gives an eighth of a route's XP
  MAX_GRINDS: 0,             // levels of grinding the look-ahead may plan in a route. None: a grind step is the last
                             //   resort, written only when no visit and no errand is left for the level (see planRoute)
  AHEAD_DISCOUNT: 0.2,       // when the look-ahead compares visits (planner/zonepick.js simVisit), a quest's XP counts
                             //   this much less for every level the quest is above the player: it can wait, and is
                             //   easier a level later. Five levels above would count for nothing; HARD_TALK allows four
  LAST_CHANCE: 2,            // ... and a quest within this many levels of being too easy (EASY: three to five levels
  LAST_CHANCE_BONUS: 1.5,    //   below the player) counts this many times: it is done now or never
  SUPPLY_VISITS: 3,          // before a grind step, an errand is followed this many rounds of visits (planner/supply.js)
  SUPPLY_RATE: 0,            // ... and taken when it gives at least this many times the XP a second that grinding gives
                             //   (its ways and its work against a fight every KILL_SECONDS), or reaches the next level.
                             //   At 0 every errand that gives XP comes before a grind step. It replaced a share of the
                             //   level a visit had to give (0.15), under which the rest of a level was ground instead
  SUPPLY_UNKNOWN_WAY: 1800,  // seconds counted for a leg of an errand whose time is not known: to a zone without a quest
                             //   giver to measure the way to, or one no way leads to from where the errand stands then
  DANGER_LEVELS: 5,          // an open zone is dangerous when the low end of its creatures' levels (lib/xp.js zoneLevels,
                             //   min) is more than this many levels above the player: no way on foot leads through it or
                             //   into it then (planner/danger.js; lib/travel.js keeps the rule for every way that is costed).
                             //   Lower: safer walks, later zones, more grind steps
  ARRIVAL_YARDS: 150,        // ... except within this distance of the end of a transport that asks for a quest: there the
                             //   game itself puts a new character down (the skycutter from Zephras Isle lands in Dalaran, in
                             //   the Alterac Mountains, 96 yards from the portal on to Stormwind)
  GRIND_BELOW: 2,            // a grind step is at a place where creatures stand whose levels are from this many under
  GRIND_ABOVE: 1,            //   the player's level to this many above it (planner/grindspots.js): never higher, and
                             //   not so low that a kill gives under two thirds of the XP of one at the level (from
                             //   level 8; lib/xp.js mobXp)
  GRIND_RADIUS: 150,         // yards: the creatures of one place to grind at stand within this of its middle
  GRIND_MIN_SPAWNS: 12,      // ... and at least this many spawn there: a fight every 30 seconds (lib/xp.js KILL_SECONDS)
                             //   empties ten spawns in the five minutes a creature takes to come back (a guess)
  GRIND_NAMED_SHARE: 0.2,    // the creatures a grind step names and offers as targets: those with at least this share
  GRIND_NAMED: 3,            //   of the place's spawns, at most this many
  GRIND_LOOK: 8,             // the places weighed for a grind step (planner/plan.js grindSpot): the nearest this many
                             //   in the zone the player stands in; when it has none, the nearest this many anywhere
                             //   and as many in the zone the route goes to next
  GRIND_ZONE_SECONDS: 900,   // what a place costs that is neither in the zone the player stands in nor in the one the
                             //   route goes to next: grinding there is a change of zone of its own
  MAX_ITERATIONS: 200000,    // a guard against a planner bug that never finishes; real routes take a few thousand turns
});
// How many levels above the player a quest may be at this level: HARD or HARD_TALK, and START_HARD in the first levels.
const above = (level, kills) => Math.max(kills ? CHOICES.HARD : CHOICES.HARD_TALK, level < CHOICES.START_UNTIL ? CHOICES.START_HARD : 0);
module.exports = { CHOICES, above };
