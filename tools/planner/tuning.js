// Noir Guides, GPLv3. See LICENSE.
// The planner's choices: every number that decides what a route does next, with what it stands for. None of them
// is a game fact (those are in lib/xp.js PACE and lib/travel.js ESTIMATES); each is a preference, set once here.
const CHOICES = Object.freeze({
  LOG_LIMIT: 20,             // the classic quest log holds 20 quests (a fact, kept with the rest for the planner)
  HARD: 0,                   // a quest with fights is taken up to this many levels above the player. None: the owner's
                             // rule is a smooth run, every quest at the player's level or below (it was 3, and real
                             // players, who level a little behind the estimate, met quests three and four levels up)
  HARD_TALK: 0,              // the same for a quest without fights (a delivery, a talk): it too shows as hard in the log
  START_HARD: 2,             // ... except in the first levels: a new character is handed quests one and two levels up by its
  START_UNTIL: 10,           //   own starting zone (a level 1 orc gets level 2 quests, and the zone's quests run a little ahead of the
                             //   player to its end), so below this level that much is allowed. Without it a level 6 character was
                             //   sent to another race's starting zone for quests of its exact level
  EASY: 3,                   // a quest more than this many levels below the player is left out (little XP), unless a
                             // travel link or another quest needs it (planner/policy.js)
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
  LATE_LEVEL: 59,            // from here on no quest with a part in another zone is taken: the log has to be empty at 60
  HEARTH_MIN_SAVING: 60,     // the hearthstone is bound at a hub's inn when one use there saves at least a minute
  HEARTH_MARGIN: 600,        // seconds past the cooldown before the planner counts on the hearthstone: its clock is an estimate
  GETFLIGHT_SECONDS: 300,    // a flight point in the zone is fetched when it is this close on foot
  SEARCH_DEPTH: 8,           // the next zone is the first of the best sequence of this many visits,
  SEARCH_BEAM: 6,            //   with this many sequences kept after each visit,
  SEARCH_ZONES: 12,          //   each continued with the zones that have the most quests to offer (and the log's zones).
  SEARCH_TIME_XP: 2,         // XP a second of travel and work is worth when two sequences are compared: time breaks
                             //   ties between sequences, the XP of their visits decides
  MIN_VISIT: 0.25,           // a zone is gone to when the visit there is worth at least this share of the player's level
                             //   (planner/zonepick.js rule 3): four such visits are a level. Smaller ones wait and grow
  LAST_VISITS: 6,            // ... unless at most this many small visits reach the next level (rule 4); else the rest
                             //   of the level is a grind step. Lower: fewer zone changes, more grinding. Measured on
                             //   the ten routes: without the two rules 243 to 277 zone changes; 6 gives 129 to 138 and
                             //   no route more grind steps than before; 5 gives 120 to 135, three routes one step more
  PLAN_WALK_SHARE: 0.12,     // the fights on the way inside an open zone, as a share of a visit's XP, for comparing
                             //   visits before making them. Measured: walking gives an eighth of a route's XP
  MAX_GRINDS: 0,             // levels of grinding the look-ahead may plan in a route. None: a grind step is only
                             //   written when no quest is left for the level (see planRoute)
  SUPPLY_VISITS: 3,          // before a grind step, an errand is followed this many rounds of visits (planner/supply.js)
  SUPPLY_MIN_SHARE: 0.15,    //   and is worth its changes of zone when a visit of it gives this share of the level, or
                             //   when it reaches the next level. Measured: the share hardly matters from 0.08 up (the
                             //   errands that reach the level are the ones taken); under 0.05 every grind step saved
                             //   costs over twenty changes of zone
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
