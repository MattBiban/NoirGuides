// Noir Guides, GPLv3. See LICENSE.
const test = require("node:test");
const assert = require("node:assert");
const { testWorld } = require("./world");
const { ESTIMATES: E, walkSeconds } = require("../lib/travel");
const { measureRoute, zoneOrder } = require("../planner/measure");

const M = (zone, x, y) => ({ zone, x, y });
const near = (a, b) => Math.abs(a - b) <= 1;

test("zone changes count the zones the route works in, one after the other; the way between them is not counted", () => {
  const route = { format: 2, steps: [
    { action: "accept", quest: 1, at: M(100, 30, 50) }, { action: "accept", quest: 2, at: M(100, 31, 50) },
    { action: "travel", at: M(200, 30, 50) }, { action: "turnin", quest: 1, at: M(200, 30, 50) },
    { action: "hearth", to: M(100, 22, 50) }, { action: "turnin", quest: 2, at: M(100, 30, 50) },
    { action: "accept", quest: 3, at: M(400, 30, 50), when: { class: "ROGUE" } },
  ] };
  assert.deepStrictEqual(zoneOrder(route, { cls: "WARRIOR" }), [100, 200, 100]);
  assert.deepStrictEqual(zoneOrder(route, { cls: "ROGUE" }), [100, 200, 100, 400]);
  // a dock, a flight master or a pass on the way is not a zone the route works in
  const way = { format: 2, steps: [{ action: "accept", quest: 1, at: M(100, 30, 50) }, { action: "travel", at: M(200, 30, 50) }, { action: "getflight", node: 3, at: M(200, 30, 50) },
    { action: "transport", kind: "boat", at: M(200, 50, 90), to: M(400, 20, 90) }, { action: "turnin", quest: 1, at: M(400, 30, 50) }, { action: "sethearth", at: M(400, 31, 50) }] };
  assert.deepStrictEqual(zoneOrder(way), [100, 400]);
  // the old format: a grind step names its zone itself, a travel step only announces the next one
  const old = { steps: [{ action: "accept", quest: 1, at: M(100, 30, 50) }, { action: "travel", zone: 200 }, { action: "grind", level: 3, zone: 200 }, { action: "travel", zone: 100 },
    { action: "travel", zone: 400 }, { action: "accept", quest: 2, at: M(400, 30, 50) }] };
  assert.deepStrictEqual(zoneOrder(old), [100, 200, 400]);
});
test("a format 2 route is timed as written: walks, flights, transports and the hearthstone", () => {
  const w = testWorld(), graph = w.graph(), ch = w.human();
  const steps = [
    { action: "accept", quest: 1, at: M(100, 30, 50) },
    { action: "getflight", node: 1, at: M(100, 20, 50), npc: 901 },
    { action: "travel", at: M(200, 30, 50) },
    { action: "getflight", node: 3, at: M(200, 30, 50), npc: 903 },
    { action: "fly", from: 3, to: 1, at: M(200, 30, 50) },
    { action: "transport", kind: "boat", at: M(100, 50, 90), to: M(400, 50, 10) },
    { action: "hearth", to: M(100, 22, 50) },
    { action: "turnin", quest: 1, at: M(100, 30, 50) },
  ];
  const m = measureRoute(w.db, graph, { format: 2, steps }, ch, steps.map(() => 10));
  const walk = (a, b) => walkSeconds(graph, 10, w.P(a.zone, a.x, a.y), w.P(b.zone, b.x, b.y));
  const walked = walk(M(100, 30, 50), M(100, 20, 50)) + walk(M(100, 20, 50), M(200, 30, 50)) + walk(M(100, 20, 50), M(100, 50, 90)) + walk(M(100, 22, 50), M(100, 30, 50));
  assert.ok(near(m.byKind.walk, walked + 2 * E.LEARN_SECONDS), `${m.byKind.walk} against ${walked}`);
  assert.ok(near(m.byKind.fly, E.BOARD_SECONDS + graph.edges.get(3).find((e) => e.to === 1).seconds));
  assert.strictEqual(m.byKind.transport, 200);
  assert.strictEqual(m.byKind.hearth, E.HEARTH_SECONDS);
  assert.ok(near(m.seconds, m.byKind.walk + m.byKind.fly + m.byKind.transport + m.byKind.hearth));
  assert.strictEqual(m.unreachable, 0);
  assert.strictEqual(m.steps, 8);
  assert.deepStrictEqual(m.zones, [100]);
  assert.strictEqual(m.zoneChanges, 0);
  assert.ok(m.yards > 1000);
  // mounted from level 40: the same walks are faster
  assert.ok(measureRoute(w.db, graph, { format: 2, steps }, ch, steps.map(() => 40)).byKind.walk < m.byKind.walk);
});
test("a step that cannot be walked to counts as unreachable and adds no time", () => {
  const w = testWorld(), graph = w.graph();
  const steps = [{ action: "accept", quest: 1, at: M(100, 30, 50) }, { action: "turnin", quest: 1, at: M(300, 30, 50) }, { action: "accept", quest: 2, at: M(400, 30, 50) }];
  const m = measureRoute(w.db, graph, { format: 2, steps }, w.human(), [1, 1, 1]);
  assert.deepStrictEqual([m.unreachable, m.seconds, m.zoneChanges], [2, 0, 2]);
});
test("a route in the old format gets the fastest way between its places, with every transport open", () => {
  const w = testWorld(), graph = w.graph();
  w.npc(14, 500, 50, 48); w.errand(77, 14, 14, 500); // the quest the boat off the isle asks for exists in the data
  const steps = [
    { action: "accept", quest: 1, at: M(500, 50, 48) },                 // on the isle: the boat off it needs a quest
    { action: "travel", zone: 100 },
    { action: "turnin", quest: 1, at: M(100, 50, 52) },
    { action: "travel", zone: 400 },
    { action: "accept", quest: 2, at: M(400, 50, 12) },
    { action: "accept", quest: 3, at: M(300, 50, 50) },                 // no way there at all
  ];
  const m = measureRoute(w.db, graph, { steps }, w.human("WARRIOR", 500), steps.map(() => 10));
  assert.strictEqual(m.byKind.transport, 120 + 200);
  assert.strictEqual(m.unreachable, 1);
  assert.ok(m.byKind.walk > 0 && m.seconds > 320);
  assert.deepStrictEqual(m.zones, [500, 100, 400, 300]);
  assert.strictEqual(m.steps, 6);
});
