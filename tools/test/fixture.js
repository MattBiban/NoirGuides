// Noir Guides, GPLv3. See LICENSE.
const { normalizeQuest } = require("../lib/db");
function fixtureDb() {
  const db = { quests: new Map(), npcs: new Map(), objects: new Map(), items: new Map(), areas: new Map(), maps: new Map(), taxi: [], eraQuestIds: new Set() };
  const area = (id, name, parent) => db.areas.set(id, { id, name, parent, continent: 0 });
  area(1000, "Testvale", 0); area(1001, "Testvale Camp", 1000); area(2000, "Farlands", 0);
  db.maps.set(1000, { area: 1000, uiMap: 1, minX: 0, minY: 0, maxX: 1000, maxY: 1000 });
  db.maps.set(2000, { area: 2000, uiMap: 2, minX: 0, minY: 2000, maxX: 1000, maxY: 3000 });
  const npc = (id, name, zone, x, y, friendly = "AH") => db.npcs.set(id, { id, name, friendly, spawns: { [zone]: [[x, y]] } });
  npc(1, "Giver Ann", 1000, 50, 50); npc(2, "Giver Bob", 1000, 52, 50); npc(3, "Wolf", 1000, 60, 60, "");
  npc(4, "Boar", 1000, 40, 40, ""); npc(5, "Far Giver", 2000, 50, 50); npc(6, "Far Beast", 2000, 55, 55, "");
  npc(7, "Horde Only Giver", 1000, 50, 52, "H");
  db.items.set(100, { id: 100, name: "Boar Tusk", npcDrops: [4], objectDrops: [] });
  const quest = (id, raw) => { db.quests.set(id, normalizeQuest(id, raw)); db.eraQuestIds.add(id); };
  quest(10, { name: "Wolves", startedBy: [[1]], finishedBy: [[1]], requiredLevel: 1, questLevel: 2, objectives: [[[3, null, 0]]], zoneOrSort: 1001 });
  quest(11, { name: "Tusks", startedBy: [[2]], finishedBy: [[2]], requiredLevel: 1, questLevel: 3, objectives: { "3": [[100, null, 0]] }, zoneOrSort: 1000 });
  quest(12, { name: "More Wolves", startedBy: [[1]], finishedBy: [[2]], requiredLevel: 2, questLevel: 4, objectives: [[[3, null, 0]]], preQuestSingle: [10], zoneOrSort: 1000 });
  quest(13, { name: "Horde Errand", startedBy: [[7]], finishedBy: [[7]], requiredLevel: 1, questLevel: 2, requiredRaces: 178, zoneOrSort: 1000 });
  quest(14, { name: "Too High", startedBy: [[1]], finishedBy: [[1]], requiredLevel: 40, questLevel: 45, zoneOrSort: 1000 });
  quest(15, { name: "Daily", startedBy: [[1]], finishedBy: [[1]], requiredLevel: 1, questLevel: 2, specialFlags: 1, zoneOrSort: 1000 });
  quest(20, { name: "Far Beasts", startedBy: [[5]], finishedBy: [[5]], requiredLevel: 4, questLevel: 6, objectives: [[[6, null, 0]]], zoneOrSort: 2000 });
  quest(21, { name: "Far Report", startedBy: [[5]], finishedBy: [[5]], requiredLevel: 5, questLevel: 7, preQuestSingle: [20], zoneOrSort: 2000 });
  return db;
}
module.exports = { fixtureDb };
