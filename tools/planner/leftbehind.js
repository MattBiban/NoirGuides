// Noir Guides, GPLv3. See LICENSE.
// Hand-ins left behind: a route that walks off while a quest it could hand in waits a few steps away. The player
// then comes back for it later, or carries it about for an hour, and sees the guide pass a "?" it could have taken.
//
//   leftBehind(db, route) -> [{ step, quests, yards }]
//
// A departure is a step that takes the player more than LEAVE_YARDS from where the previous step left them (a walk in
// a straight line, or any flight, transport or hearth). It leaves a hand-in behind when, at that moment, a quest of the
// log is ready (its objective step is done, or the route has none for it) and its turn-in lies within READY_YARDS of
// where the player stands. Each quest is counted at the first departure that leaves it behind; a departure that
// leaves nothing new behind is not counted again.
//   step    the index of the departing step in route.steps
//   quests  the quests it leaves behind, by ID
//   yards   how far the step moves the player (Infinity for a flight, a transport or a hearth)
// Only the route's own steps are read: which quests are ready comes from the order of its accept, objective and
// turn-in steps, not from the planner's state, so the check stands apart from the rule that avoids the pattern
// (planner/plan.js nextTarget).
const { toPoint, distance } = require("../lib/geo");
const { CHOICES: C } = require("./tuning");

// What a route may have before the build and the tests fail. Not zero: the planner decides from where the player
// stands with the travel times of lib/travel.js, the check looks at straight lines from step to step, and a data
// update can bring a turn-in behind a cliff that the planner rightly walks around. Two a route still catches the
// pattern coming back: before the planner avoided it, every route had between 14 and 35.
const MAX_LEFT_BEHIND = 2;

function leftBehind(db, route, { leaveYards = C.LEAVE_YARDS, readyYards = C.READY_YARDS } = {}) {
  const steps = route.steps;
  const point = (at) => (at ? toPoint(db, at.zone, at.x, at.y) : null);
  // per quest: the step that makes it ready (its objective, else its accept) and its turn-in's place
  const objectiveAt = new Map(), turnin = new Map();
  steps.forEach((s, k) => {
    if (s.action === "objective" && !objectiveAt.has(s.quest)) objectiveAt.set(s.quest, k);
    if (s.action === "turnin" && !turnin.has(s.quest)) turnin.set(s.quest, { k, point: point(s.at) });
  });
  const ready = new Map(); // quest -> turn-in point
  const counted = new Set();
  const out = [];
  let pos = null;
  steps.forEach((s, k) => {
    const moving = s.action === "fly" || s.action === "transport" || s.action === "hearth";
    const to = s.action === "hearth" ? null : point(s.at);
    const yards = moving ? Infinity : pos && to ? distance(pos, to) : 0;
    if (pos && yards > leaveYards) {
      const behind = [...ready].filter(([quest, p]) => !counted.has(quest) && turnin.get(quest).k !== k && p && distance(pos, p) <= readyYards).map(([quest]) => quest);
      if (behind.length) {
        behind.sort((a, b) => a - b).forEach((q) => counted.add(q));
        out.push({ step: k, quests: behind, yards: Math.round(yards) });
      }
    }
    // the state after the step
    if (s.action === "accept" && turnin.has(s.quest) && !(objectiveAt.get(s.quest) < turnin.get(s.quest).k && objectiveAt.get(s.quest) > k)) ready.set(s.quest, turnin.get(s.quest).point);
    if (s.action === "objective" && turnin.has(s.quest)) ready.set(s.quest, turnin.get(s.quest).point);
    if (s.action === "turnin") ready.delete(s.quest);
    if (s.action === "fly") pos = null; // lands where the next step is
    else if (s.action === "transport" || s.action === "hearth") pos = point(s.to);
    else if (to) pos = to;
  });
  return out;
}

module.exports = { leftBehind, MAX_LEFT_BEHIND };
