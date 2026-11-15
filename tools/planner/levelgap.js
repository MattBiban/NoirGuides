// Noir Guides, GPLv3. See LICENSE.
// Quests against the level they are played at: a route can be played when no quest it takes is further above the
// player than the player gets through: HARD levels for a quest with fights, HARD_TALK for one without, and never
// less than START_HARD below START_UNTIL (planner/tuning.js HARD, HARD_TALK, START_HARD, START_UNTIL, EASY;
// planner/policy.js applies them). And it wastes little when few of its quests are far below the player.
//
//   levelGap(db, route, levels) -> { above: [{ step, quest, questLevel, level }], below: [...], steps }
//
// route is a format 2 route, levels[k] the player's level at step k (planner/validate.js). Each accept and each
// objective step is looked at: above, when the quest's level is over the player's whole level there by more than the
// level allows such a quest (tuning.js above; a quest has fights when it has a creature or an item objective, as in
// planner/context.js); below, when it is more than EASY levels under it. A quest taken below START_UNTIL is judged
// where it was taken: its objective step is not counted as above when the player has reached START_UNTIL in between.
// steps is the number of steps looked at. Only the route's own steps are read, so the check stands apart from the
// rule that plans them. With cls, the steps of other classes (when.class) are left out, so a layered route is
// measured class by class, each against its own levels.
const { CHOICES: C, above: allowed } = require("./tuning");

// No quest above what the level allows is the rule, and the shared route meets it exactly (measured: none in any
// race). A class layered onto it can be a few XP behind the class the shared route was planned with, and so meet a
// quest one level further up at a level's very start: at most this many steps a class (measured: none to two, one
// quest's accept and objective).
const MAX_ABOVE = 2;
// Quests far below the level are the ones a chain or a travel link needs (planner/policy.js): at most this share of
// the steps looked at. It was 0.25 while a quest more than three levels under the player counted as far below
// (3 to 22% a route then, most where a race starts in long chains). Far below is more than five levels now (EASY):
// measured 1 to 5% on the shared routes, up to 6% for a class with its own quests layered in.
const MAX_BELOW_SHARE = 0.1;

const fights = (q) => q.objectives.npcs.length + q.objectives.items.length > 0;

function levelGap(db, route, levels, { easy = C.EASY, cls } = {}) {
  const above = [], below = [], starter = new Set();
  let steps = 0;
  route.steps.forEach((s, k) => {
    if (s.action !== "accept" && s.action !== "objective") return;
    if (cls && s.when && s.when.class && s.when.class !== cls) return; // another class's step
    const q = db.quests.get(s.quest);
    if (!q) return;
    steps++;
    const level = Math.floor(levels[k]);
    const entry = { step: k, quest: s.quest, questLevel: q.level, level };
    if (s.action === "accept" && level < C.START_UNTIL) starter.add(s.quest); // taken in the starting zone: judged there
    if (q.level > level + allowed(level, fights(q)) && !(s.action === "objective" && starter.has(s.quest))) above.push(entry);
    else if (q.level < level - easy) below.push(entry);
  });
  return { above, below, steps };
}

module.exports = { levelGap, MAX_ABOVE, MAX_BELOW_SHARE };
