// Noir Guides, GPLv3. See LICENSE.
// The planner's choices: every number that decides what a route does next, with what it stands for. None of them
// is a game fact (those are in lib/xp.js PACE and lib/travel.js ESTIMATES); each is a preference, set once here.
const CHOICES = Object.freeze({
  LOG_LIMIT: 20,             // the classic quest log holds 20 quests (a fact, kept with the rest for the planner)
  HARD: 3,                   // a quest with fights is taken up to this many levels above the player: creatures four
                             // levels up are missed and resisted too often to be worth it
  NEARBY: 1500,              // yards on foot: an objective over a zone border belongs to this zone when it is this close
                             // to one of the zone's quest places
  HUB_YARDS: 150,            // quest givers this close together are one hub: everything there is done in one stop
  READY_YARDS: 300,         // a hand-in that is ready and this close to the player is not left behind:
  LEAVE_YARDS: 500,         //   the route does not move farther than this while one waits (planner/leftbehind.js)
  TOWN_SECONDS: 60,          // quests to take or hand in within a minute's walk come before any objective
  SHORT_WALK_SECONDS: 60,    // a walk this short inside one zone is costed as a straight line, a longer way by travelPlan
  LOOK_AHEAD: 5,             // the next task is the first of the best order of the nearest five
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
  PLAN_WALK_SHARE: 0.12,     // the fights on the way inside an open zone, as a share of a visit's XP, for comparing
                             //   visits before making them. Measured: walking gives an eighth of a route's XP
  MAX_GRINDS: 0,             // levels of grinding the look-ahead may plan in a route. None: a grind step is only
                             //   written when no quest is left for the level (see planRoute)
  MAX_ITERATIONS: 200000,    // a guard against a planner bug that never finishes; real routes take a few thousand turns
});
module.exports = { CHOICES };
