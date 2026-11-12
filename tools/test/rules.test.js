// Noir Guides, GPLv3. See LICENSE.
// The rules loadDb applies where the data is known to be incomplete: class quests without a class mask, and the
// race masks of the Skyborne starting isle. docs/routes/DATA-NOTES.md has the evidence for each rule.
const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const path = require("path");
const { fixtureDb } = require("./fixture");
const { normalizeQuest, loadDb, applyDataRules } = require("../lib/db");
const { character, eligible, hasBit, classMask, ALL_CLASSES, HIGH_ORDER, WINDSHAPER, SKYBORNE_CONTINENT } = require("../lib/characters");
const DATA = path.join(__dirname, "..", "data");
const real = fs.existsSync(path.join(DATA, "forever_db.json"));

const ALLIANCE = 4294967373, HORDE = 8589934770; // the faction masks the data uses, each with its Skyborne race
const add = (db, id, raw) => db.quests.set(id, normalizeQuest(id, { name: "q" + id, startedBy: [[1]], finishedBy: [[1]], zoneOrSort: 1000, ...raw }));

test("class masks cover the nine classes", () => {
  assert.strictEqual(classMask("ROGUE"), 8);
  assert.strictEqual(classMask("DRUID"), 1024);
  assert.strictEqual(ALL_CLASSES, 1503);
});
test("a quest filed under a class sort is that class's quest even without a class mask", () => {
  const db = fixtureDb();
  add(db, 50, { zoneOrSort: -162 });                       // the Rogue quest sort
  add(db, 51, { zoneOrSort: -162, requiredClasses: 1 });   // the data's own mask always wins
  add(db, 52, { zoneOrSort: -22 });                        // a sort that is not a class
  applyDataRules(db);
  assert.strictEqual(db.quests.get(50).classes, classMask("ROGUE"));
  assert.match(db.quests.get(50).inferred.classes, /sort/);
  assert.strictEqual(db.quests.get(51).classes, 1);
  assert.strictEqual(db.quests.get(51).inferred.classes, undefined);
  assert.strictEqual(db.quests.get(52).classes, 0);
  assert.strictEqual(eligible(db.quests.get(50), character("Undead", "ROGUE")), true);
  assert.strictEqual(eligible(db.quests.get(50), character("Undead", "MAGE")), false);
});
test("a quest only reachable through class quests inherits their classes", () => {
  const db = fixtureDb();
  add(db, 60, { requiredClasses: 8 });                     // Rogue
  add(db, 61, { requiredClasses: 128 });                   // Mage
  add(db, 62, { preQuestSingle: [60] });                   // needs the Rogue quest
  add(db, 63, { preQuestSingle: [62] });                   // and so on down the chain
  add(db, 64, { preQuestSingle: [60, 61] });               // either class quest: both classes
  add(db, 65, { preQuestSingle: [60, 10] });               // quest 10 is open to all: no restriction
  add(db, 66, { preQuestGroup: [10, 61] });                // needs all of them, one is Mage only
  add(db, 67, { preQuestGroup: [60, 61] });                // needs a Rogue quest and a Mage quest: nobody, left as the data has it
  add(db, 68, { requiredClasses: ALL_CLASSES - 8 });       // everyone but Rogues
  add(db, 69, { preQuestSingle: [60, 68] });               // together the two versions cover every class
  add(db, 70, { preQuestSingle: [424242] });               // a prerequisite the data does not have
  applyDataRules(db);
  const classes = (id) => db.quests.get(id).classes;
  assert.strictEqual(classes(62), 8);
  assert.match(db.quests.get(62).inferred.classes, /prerequisite/);
  assert.strictEqual(classes(63), 8);
  assert.strictEqual(classes(64), 8 + 128);
  assert.strictEqual(classes(65), 0);
  assert.strictEqual(classes(66), 128);
  assert.strictEqual(classes(67), 0);
  assert.strictEqual(classes(69), 0);
  assert.strictEqual(classes(70), 0);
  assert.strictEqual(db.quests.get(62).asData.classes, 0, "what the data said is kept");
});
test("inherited classes do not depend on the order the quests are read in", () => {
  const db = fixtureDb();
  add(db, 71, { preQuestGroup: [73, 72] });                // read before 72 has its classes worked out
  add(db, 72, { preQuestSingle: [60] });
  add(db, 73, { requiredClasses: 8 + 128 });               // Rogue or Mage
  add(db, 60, { requiredClasses: 8 });                     // Rogue
  add(db, 74, { preQuestSingle: [75, 76] });               // read before 75 is known to be a class quest
  add(db, 75, { preQuestSingle: [60] });
  add(db, 76, { requiredClasses: 128 });
  applyDataRules(db);
  assert.strictEqual(db.quests.get(72).classes, 8);
  assert.strictEqual(db.quests.get(71).classes, 8, "both are needed: only a Rogue has done both");
  assert.strictEqual(db.quests.get(74).classes, 8 + 128);
});

// an isle in the fixture: area 3000 on the Skyborne continent, with a giver there
function isleDb() {
  const db = fixtureDb();
  db.areas.set(3000, { id: 3000, name: "Test Isle", parent: 0, continent: SKYBORNE_CONTINENT });
  db.maps.set(3000, { area: 3000, uiMap: 3, minX: 0, minY: 5000, maxX: 1000, maxY: 6000 });
  db.npcs.set(30, { id: 30, name: "Isle Elder", friendly: "AH", spawns: { 3000: [[50, 50]] } });
  db.npcs.set(31, { id: 31, name: "No Spawn", friendly: "AH", spawns: {} });
  const isle = (id, raw) => add(db, id, { startedBy: [[30]], finishedBy: [[30]], zoneOrSort: 3000, ...raw });
  isle(80, {});                                            // no mask
  isle(81, { requiredRaces: HIGH_ORDER });                 // the lone High Order bit: the data's mark for a shared isle quest
  isle(82, { requiredRaces: ALLIANCE });
  isle(83, { requiredRaces: HORDE });
  isle(84, { requiredRaces: 32 });                         // names only Tauren: a Horde quest, so the Horde Skyborne
  isle(85, { requiredRaces: WINDSHAPER });
  isle(86, { requiredRaces: HIGH_ORDER + 4 + 32 });        // names a Skyborne race among others: that race
  isle(87, { startedBy: [[31]] });                         // giver without a position: the quest's zone decides
  isle(88, { startedBy: [[1]] });                          // zoned on the isle but given in Testvale: not an isle quest
  add(db, 89, { requiredRaces: HIGH_ORDER });              // off the isle the lone bit means what it says
  applyDataRules(db);
  return db;
}
test("quests that start on the Skyborne isle are for the Skyborne races only", () => {
  const db = isleDb();
  const who = (id) => ["Human", "Tauren", "HighOrder", "Windshaper"].filter((race) => eligible(db.quests.get(id), character(race, "WARRIOR")));
  assert.deepStrictEqual(who(80), ["HighOrder", "Windshaper"]);
  assert.deepStrictEqual(who(81), ["HighOrder", "Windshaper"]);
  assert.deepStrictEqual(who(82), ["HighOrder"]);
  assert.deepStrictEqual(who(83), ["Windshaper"]);
  assert.deepStrictEqual(who(84), ["Windshaper"]);
  assert.deepStrictEqual(who(85), ["Windshaper"]);
  assert.deepStrictEqual(who(86), ["HighOrder"]);
  assert.deepStrictEqual(who(87), ["HighOrder", "Windshaper"]);
  assert.deepStrictEqual(who(88), ["Human", "Tauren", "HighOrder", "Windshaper"]);
  assert.deepStrictEqual(who(89), ["HighOrder"]);
  assert.match(db.quests.get(80).inferred.races, /isle/);
  assert.strictEqual(db.quests.get(81).asData.races, HIGH_ORDER);
  assert.match(db.quests.get(82).inferred.races, /isle/);
  assert.strictEqual(db.quests.get(89).inferred.races, undefined);
});
test("applying the rules twice changes nothing", () => {
  const db = isleDb();
  const before = JSON.stringify([...db.quests.values()]);
  applyDataRules(db);
  assert.strictEqual(JSON.stringify([...db.quests.values()]), before);
});

test("real data: class quests the data leaves without a class mask", { skip: !real }, () => {
  const db = loadDb(DATA);
  const q = (id) => db.quests.get(id);
  assert.strictEqual(q(8249).classes, classMask("ROGUE"));   // Junkboxes Needed, Rogue sort
  assert.strictEqual(q(93797).classes, classMask("MAGE"));   // Boughs in the Wind, Mage sort
  assert.strictEqual(q(96136).classes, classMask("SHAMAN")); // Call of Air
  assert.strictEqual(q(98341).classes, classMask("DRUID"));
  assert.strictEqual(q(5127).classes, 1 + 2 + 64);           // The Demon Forge: after 5126, a Warrior, Paladin or Shaman quest
  assert.strictEqual(q(8922).classes, ALL_CLASSES - 64);     // after the eight Alliance class versions: no Shaman version
  assert.strictEqual(q(794).classes, 0);                     // after either version of Vile Familiars: every class
  // A Rogue's Deal: nothing in the data ties it to a class (see DATA-NOTES), so no rule may invent that
  assert.strictEqual(q(8).classes, 0);
  assert.strictEqual(q(590).classes, 0);
  // the whole list, as DATA-NOTES prints it: a change in the data or the rules shows up here
  const inferred = [...db.quests.values()].filter((x) => x.inferred.classes).map((x) => x.id).sort((a, b) => a - b);
  assert.deepStrictEqual(inferred, [5127, 8249, 8922, 8923, 8929, 8930, 8960, 9032, 93797, 96136, 98341, 98404, 98517, 98738]);
});
test("real data: Zephras Isle quests are for the Skyborne, shared ones for both", { skip: !real }, () => {
  const db = loadDb(DATA);
  const who = (id) => ["Human", "Tauren", "HighOrder", "Windshaper"].filter((race) => eligible(db.quests.get(id), character(race, "WARRIOR")));
  assert.deepStrictEqual(who(92460), ["HighOrder", "Windshaper"]); // Coming of Age: the first quest, masked High Order only
  assert.deepStrictEqual(who(92464), ["HighOrder", "Windshaper"]); // Elemental Unrest: no mask
  assert.deepStrictEqual(who(92550), ["HighOrder", "Windshaper"]); // Havoc in the Highlands: needed by both "To Valanaar"
  assert.deepStrictEqual(who(92514), ["Windshaper"]);              // Welcome to Shen'dar Village, the Horde version (mask 32)
  assert.deepStrictEqual(who(93461), ["HighOrder"]);               // and the Alliance version
  assert.deepStrictEqual(who(92579), ["Windshaper"]);              // To Valanaar, Horde mask
  assert.deepStrictEqual(who(94946), ["HighOrder"]);               // the way off the isle for the Alliance
  assert.deepStrictEqual(who(95349), ["Windshaper"]);              // and for the Horde
  const hunters = ["Human", "Tauren", "HighOrder", "Windshaper"].filter((race) => eligible(db.quests.get(92482), character(race, "HUNTER")));
  assert.deepStrictEqual(hunters, ["HighOrder", "Windshaper"]);    // The Way of the Hunter: a class quest given on the isle
  assert.deepStrictEqual(who(94947), ["HighOrder"]);               // Welcome to Azeroth starts in Dalaran: the mask stands
  assert.ok(hasBit(db.quests.get(364).races, 4));                  // a Tirisfal quest is untouched
  assert.strictEqual(db.quests.get(364).inferred.races, undefined);
});
