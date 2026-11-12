// Noir Guides, GPLv3. See LICENSE.
const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const path = require("path");
const { hasBit, character, eligible, combos, RACES } = require("../lib/characters");
const { normalizeQuest } = require("../lib/db");
const DATA = path.join(__dirname, "..", "data");
const real = fs.existsSync(path.join(DATA, "wago", "CharBaseInfo.csv"));

test("hasBit works above 32 bits", () => {
  assert.strictEqual(hasBit(8589934770, 33), true);   // Horde mask includes Windshaper (bit 33)
  assert.strictEqual(hasBit(8589934770, 32), false);
  assert.strictEqual(hasBit(4294967373, 32), true);   // Alliance mask includes High Order (bit 32)
  assert.strictEqual(hasBit(178, 4), true);           // Undead
  assert.strictEqual(hasBit(178, 0), false);          // not Human
});
test("eligibility by race and class", () => {
  const rogue = character("Undead", "ROGUE");
  assert.strictEqual(eligible(normalizeQuest(1, { requiredRaces: 8589934770 }), rogue), true);
  assert.strictEqual(eligible(normalizeQuest(1, { requiredRaces: 4294967373 }), rogue), false);
  assert.strictEqual(eligible(normalizeQuest(1, {}), rogue), true);
  assert.strictEqual(eligible(normalizeQuest(1, { requiredClasses: 1 }), rogue), false); // Warrior only
  assert.strictEqual(eligible(normalizeQuest(1, { requiredClasses: 8 }), rogue), true);  // Rogue = class ID 4, bit 3
});
test("start areas are real areas", () => {
  assert.strictEqual(RACES.Undead.startArea, 85);
  assert.strictEqual(RACES.HighOrder.startArea, 16593);
});
test("the client offers 56 combinations", { skip: !real }, () => {
  const all = combos(DATA);
  assert.strictEqual(all.length, 56);
  assert.ok(all.some((c) => c.race === "Undead" && c.cls === "PALADIN"));
});
