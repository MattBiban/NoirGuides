// Noir Guides, GPLv3. See LICENSE.
// Which task comes next inside a zone. The candidates arrive with the time of the way to each (`cost`, seconds from
// where the player stands); this file only orders them. Nothing here reads the quest data or the clock.
const { CHOICES } = require("./tuning");

const KIND_ORDER = { turnin: 0, accept: 1, objective: 2, getflight: 3 };
const byCost = (a, b) => (a.cost !== b.cost ? (a.cost < b.cost ? -1 : 1) : KIND_ORDER[a.kind] - KIND_ORDER[b.kind] || a.id - b.id);

// Every order of a short list, each as an array of indices.
function orders(n) {
  const out = [];
  const walk = (prefix, rest) => {
    if (!rest.length) { out.push(prefix); return; }
    for (let i = 0; i < rest.length; i++) walk([...prefix, rest[i]], [...rest.slice(0, i), ...rest.slice(i + 1)]);
  };
  walk([], Array.from({ length: n }, (_, i) => i));
  return out;
}
const ORDERS = [0, 1, 2, 3, 4, 5].map(orders);

// The task to go to now.
//   candidates  [{ kind, id, point, cost }]: what can be done now, each with the seconds from here to it
//   between     (a, b) => seconds on foot from one candidate's place to another's
//   home        optional (candidate) => seconds from its place to where the loop has to end (the hub that is waiting
//               for these objectives); only counted when every candidate fits in the look-ahead
// Rule 1, the town first: a quest to take or hand in within TOWN_SECONDS comes before any objective, so a hub is
//   emptied before its loop starts.
// Rule 2, look-ahead: of the nearest LOOK_AHEAD candidates, every order is tried and the first task of the shortest
//   whole way is taken. Nearest-first alone walks into a corner and back across the zone; the best order of the next
//   few does not. Equal ways fall back to the nearer first task, then turn-ins before accepts before objectives,
//   then the lower ID, so the result never depends on the order of the input.
function nextTask(candidates, between, home) {
  let list = candidates.filter((c) => c.cost < Infinity);
  if (!list.length) return null;
  const town = list.filter((c) => (c.kind === "accept" || c.kind === "turnin") && c.cost <= CHOICES.TOWN_SECONDS);
  if (town.length) list = town;
  list.sort(byCost);
  const all = list.length <= CHOICES.LOOK_AHEAD;
  const near = list.slice(0, CHOICES.LOOK_AHEAD);
  if (near.length === 1) return near[0];
  const walk = near.map((a) => near.map((b) => (a === b ? 0 : between(a, b))));
  let best = null, bestTotal = Infinity;
  for (const order of ORDERS[near.length]) {
    let total = near[order[0]].cost;
    for (let i = 1; i < order.length && total < bestTotal; i++) total += walk[order[i - 1]][order[i]];
    if (all && home && total < bestTotal) total += home(near[order[order.length - 1]]);
    // the orders come with the nearer first task first, so a tie keeps the one found earlier
    if (total < bestTotal - 1e-9) { bestTotal = total; best = near[order[0]]; }
  }
  return best || near[0];
}

module.exports = { nextTask, byCost, KIND_ORDER };
