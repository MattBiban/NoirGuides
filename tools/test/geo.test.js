// Noir Guides, GPLv3. See LICENSE.
const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const path = require("path");
const { fixtureDb } = require("./fixture");
const { zoneOf, toPoint, distance, spawnPoints, centroid } = require("../lib/geo");
const { loadDb } = require("../lib/db");
const DATA = path.join(__dirname, "..", "data");
const real = fs.existsSync(path.join(DATA, "forever_db.json"));

test("zoneOf climbs to the zone that has a map", () => {
  const db = fixtureDb();
  assert.strictEqual(zoneOf(db, 1001), 1000);
  assert.strictEqual(zoneOf(db, 1000), 1000);
  assert.strictEqual(zoneOf(db, 999999), 0);
});
test("toPoint converts percent to world and distance is in yards", () => {
  const db = fixtureDb();
  const a = toPoint(db, 1000, 50, 50), b = toPoint(db, 1000, 60, 50);
  assert.deepStrictEqual([a.wx, a.wy, a.zone], [500, 500, 1000]);
  assert.strictEqual(Math.round(distance(a, b)), 100);
  assert.strictEqual(toPoint(db, 999999, 1, 1), null);
});
test("spawnPoints uses the zone map even when the spawn is keyed by a subzone", () => {
  const db = fixtureDb();
  db.npcs.get(1).spawns = { 1001: [[50, 50]] };
  assert.strictEqual(spawnPoints(db, "npc", 1)[0].zone, 1000);
});
test("centroid averages world positions and keeps the commonest zone", () => {
  const db = fixtureDb();
  const c = centroid([toPoint(db, 1000, 40, 40), toPoint(db, 1000, 60, 60)]);
  assert.deepStrictEqual([Math.round(c.x), Math.round(c.y)], [50, 50]);
  assert.strictEqual(centroid([]), null);
});
test("real data: Devrak stands at the Crossroads taxi node", { skip: !real }, () => {
  const db = loadDb(DATA);
  const p = spawnPoints(db, "npc", 3615)[0];
  const node = db.taxi.find((t) => t.name.startsWith("Crossroads"));
  assert.ok(Math.hypot(p.wx - node.x, p.wy - node.y) < 15);
});
