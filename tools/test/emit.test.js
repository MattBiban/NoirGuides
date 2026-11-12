// Noir Guides, GPLv3. See LICENSE.
// The data files beside the format 3 routes (tools/planner/emit.js): Names.lua, Zones.lua and Flights.lua.
const test = require("node:test");
const assert = require("node:assert");
const luaparse = require("luaparse");
const { testWorld } = require("./world");
const { emitNames, emitZones, emitFlights } = require("../planner/emit");

const P = (zone, x, y, r) => (r === undefined ? { zone, x, y } : { zone, x, y, r });
// a format 3 route that names quests, NPCs, objects and items in every place a route can name them
function route3(steps, extra = []) {
  return { id: "alliance-human", format: 3, race: "Human", faction: "Alliance",
    sections: [{ id: "human-01-05-westland", name: "1-5 Westland", group: "Alliance", subgroup: "1-20", minLevel: 1, zone: 100, start: true, next: [], steps }, ...extra] };
}

function world() {
  const w = testWorld();
  w.npc(10, 100, 30, 50, "AH", 'Ann "the Giver"'); w.npc(20, 100, 60, 30, "", "Wolf"); w.npc(21, 100, 61, 30, "", "Bear"); w.npc(22, 100, 62, 30, "AH", "Smith");
  w.npc(23, 100, 63, 30, "AH", "Vendor"); w.npc(24, 100, 64, 30, "", "Rare"); w.npc(25, 100, 65, 30, "AH", "Unused");
  w.object(30, 100, 40, 40, "Old Crate");
  for (const [id, name] of [[100, "Wolf Tooth"], [101, "Starter Letter"], [102, "Bait"], [103, "Bread"], [104, "Totem"], [105, "Unused Item"]]) w.db.items.set(id, { id, name, npcDrops: [], objectDrops: [] });
  w.quest(1, { name: "Teeth", startedBy: [[10]], finishedBy: [[10]], zoneOrSort: 100 });
  w.quest(2, { name: "Earlier", startedBy: [[10]], finishedBy: [[10]], zoneOrSort: 100 });
  w.quest(3, { name: "Gate", startedBy: [[10]], finishedBy: [[10]], zoneOrSort: 100 });
  w.quest(4, { name: "Never Planned", startedBy: [[10]], finishedBy: [[10]], zoneOrSort: 100 });
  return w;
}

test("Names.lua lists every quest, NPC, object and item the format 3 routes name, including items and targets", () => {
  const w = world();
  const routes = [route3([
    { id: "a1", at: P(100, 30, 50, 10), lines: [{ kind: "accept", quest: 1, npc: 10, requires: [2], ifDone: 3 }], items: [101], targets: { friend: [10] } },
    { id: "o1", at: P(100, 60, 30, 40), lines: [{ kind: "objective", quest: 1, index: 1, item: 100 }, { kind: "objective", quest: 1, index: 2, object: 30 },
      { kind: "use", item: 102 }, { kind: "target", npc: 24, enemy: true }], targets: { enemy: [20, 21] } },
    { id: "v23", at: P(100, 63, 30, 10), lines: [{ kind: "vendor", npc: 23, buy: { item: 103, count: 5 } }, { kind: "collect", item: 104, count: 1 }] },
    { id: "tWARRIOR-2", when: { class: "WARRIOR" }, at: P(100, 62, 30, 10), lines: [{ kind: "train", class: "WARRIOR", level: 2, npc: 22 }] },
    { id: "t1", at: P(100, 30, 50, 10), lines: [{ kind: "turnin", quest: 1, npc: 10 }] },
  ])];
  const names = emitNames(w.db, routes).split("\n");
  assert.strictEqual(names[0], "-- Noir Guides, GPLv3. See LICENSE.");
  assert.deepStrictEqual(names.slice(2), [
    'Noir.Data.quests[1] = "Teeth"', 'Noir.Data.quests[2] = "Earlier"', 'Noir.Data.quests[3] = "Gate"',
    'Noir.Data.npcs[10] = "Ann \\"the Giver\\""', 'Noir.Data.npcs[20] = "Wolf"', 'Noir.Data.npcs[21] = "Bear"', 'Noir.Data.npcs[22] = "Smith"',
    'Noir.Data.npcs[23] = "Vendor"', 'Noir.Data.npcs[24] = "Rare"',
    'Noir.Data.objects[30] = "Old Crate"',
    'Noir.Data.items[100] = "Wolf Tooth"', 'Noir.Data.items[101] = "Starter Letter"', 'Noir.Data.items[102] = "Bait"', 'Noir.Data.items[103] = "Bread"',
    'Noir.Data.items[104] = "Totem"', ""]);
  luaparse.parse(names.join("\n"), { luaVersion: "5.1" });
});

test("Zones.lua and Flights.lua name the zones and flight points the format 3 routes use", () => {
  const w = world();
  const graph = w.graph();
  const routes = [route3([
    { id: "a1", at: P(100, 30, 50, 10), lines: [{ kind: "accept", quest: 1, npc: 10 }] },
    { id: "x400", at: P(100, 50, 90, 15), lines: [{ kind: "transport", mode: "boat", at: P(100, 50, 90, 15), to: P(400, 50, 10) }] },
  ])];
  const zones = emitZones(w.db, routes, graph).split("\n");
  assert.ok(zones.includes('Noir.Data.zones[100] = { uiMap = 9100, name = "Westland", continent = 0 }'));
  assert.ok(zones.includes('Noir.Data.zones[400] = { uiMap = 9400, name = "Farshore", continent = 1 }'), "the far end of a transport and the zones of flight points are there");
  assert.ok(zones.includes('Noir.Data.zones[200] = { uiMap = 9200, name = "Eastland", continent = 0 }'));
  assert.ok(!zones.some((l) => l.includes("[300]")), "a zone nothing names is left out");
  const flights = emitFlights(graph).split("\n");
  assert.strictEqual(flights[2], 'Noir.Data.flights[1] = { name = "West Camp, Westland", zone = 100, x = 20, y = 50, factions = "A" }');
  assert.ok(flights.includes('Noir.Data.flights[4] = { name = "Horde Post, Westland", zone = 100, x = 20, y = 60, factions = "H" }'));
  assert.ok(flights.includes('Noir.Data.flights[6] = { name = "Far Port, Farshore", zone = 400, x = 50, y = 50, factions = "AH" }'), "whose flight point each is");
  assert.strictEqual(flights.filter((l) => l.startsWith("Noir.Data.flights[")).length, 7);
  for (const text of [zones, flights]) luaparse.parse(text.join("\n"), { luaVersion: "5.1" });
});

test("a route that is not in format 3 is refused", () => {
  const w = world();
  assert.throws(() => emitNames(w.db, [{ id: "horde-orc", format: 2, steps: [] }]), /format 3/);
});
