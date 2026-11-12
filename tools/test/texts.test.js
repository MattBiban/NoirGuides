// Noir Guides, GPLv3. See LICENSE.
// Step texts (tools/planner/texts.js, task P3 of docs/superpowers/plans/2026-11-11-guide-rebuild.md). Every map of
// the test world is 1000 yards square, so one map percent is 10 yards; map y grows to the south, x to the east.
const test = require("node:test");
const assert = require("node:assert");
const { testWorld } = require("./world");
const { stepText, compass, plural, MAX_TEXT, FAR_YARDS } = require("../planner/texts");

function world() {
  const w = testWorld();
  w.db.taxi.push({ id: 1, name: "West Camp, Westland" }, { id: 3, name: "East Mid, Eastland" });
  w.npc(10, 100, 30, 50, "AH", "Giver Ann");
  w.npc(20, 100, 80, 50, "", "Grey Wolf");
  // quest 1 asks for eight wolves (the count is read from the objective text)
  w.quest(1, { startedBy: [[10]], finishedBy: [[10]], objectives: [[[20, null, 0]]], zoneOrSort: 100, objectivesText: ["Kill 8 Grey Wolves for Giver Ann."] });
  return w;
}
const P = (zone, x, y, r) => (r === undefined ? { zone, x, y } : { zone, x, y, r });
const talk = { id: "a1", at: P(100, 30, 50, 10), lines: [{ kind: "accept", quest: 1, npc: 10 }], targets: { friend: [10] } };

test("the constants are the plan's", () => {
  assert.strictEqual(MAX_TEXT, 160);
  assert.strictEqual(FAR_YARDS, 200);
});

test("each template gives the text for its step kind", () => {
  const { db } = world();
  const section = { zone: 100 };
  // a goto into another zone: Eastland lies east of Westland (its map starts where Westland's ends)
  const go = { id: "g200@200", at: P(200, 50, 50, 20), lines: [{ kind: "goto", at: P(200, 50, 50, 20) }] };
  assert.strictEqual(stepText(db, go, { previous: talk, section }), "Head east into Eastland.");
  // a transport
  const boat = { id: "x400", at: P(100, 50, 90, 15), lines: [{ kind: "transport", mode: "boat", at: P(100, 50, 90, 15), to: P(400, 50, 10) }] };
  assert.strictEqual(stepText(db, boat, { previous: talk, section }), "Take the boat from Westland to Farshore.");
  // a fly, alone or after learning the point
  const fly = { id: "y1-3", at: P(100, 20, 50, 10), lines: [{ kind: "fly", from: 1, to: 3 }] };
  assert.strictEqual(stepText(db, fly, { previous: talk, section }), "Fly from West Camp, Westland to East Mid, Eastland.");
  const learnFly = { id: "f1.y1-3", at: P(100, 20, 50, 10), lines: [{ kind: "getflight", node: 1 }, { kind: "fly", from: 1, to: 3 }] };
  assert.strictEqual(stepText(db, learnFly, { previous: talk, section }), "Fly from West Camp, Westland to East Mid, Eastland.");
  // a hearth
  const hearth = { id: "h", lines: [{ kind: "hearth", to: P(100, 22, 50) }] };
  assert.strictEqual(stepText(db, hearth, { previous: talk, section }), "Use your hearthstone to return to Westland.");
  // a grind
  const grind = { id: "l7@100", at: P(100, 30, 50), lines: [{ kind: "grind", level: 7 }] };
  assert.strictEqual(stepText(db, grind, { previous: talk, section }), "Kill creatures around Westland until you reach level 7.");
  // an objective step far from the previous one (500 yards east of Giver Ann)
  const far = { id: "o1", at: P(100, 80, 50, 40), lines: [{ kind: "objective", quest: 1, index: 1, npc: 20 }], targets: { enemy: [20] } };
  assert.strictEqual(stepText(db, far, { previous: talk, section }), "The Grey Wolves are east of Giver Ann.");
  // with no NPC on the previous step, its place is named
  const before = { id: "g100@100", at: P(100, 30, 50, 20), lines: [{ kind: "goto", at: P(100, 30, 50, 20) }] };
  assert.strictEqual(stepText(db, far, { previous: before, section }), "The Grey Wolves are east of your last stop.");
});

test("compass directions come from world coordinates in eight directions", () => {
  const { db } = world();
  const from = P(100, 50, 50);
  const cases = [
    [P(100, 50, 10), "north"], [P(100, 90, 10), "northeast"], [P(100, 90, 50), "east"], [P(100, 90, 90), "southeast"],
    [P(100, 50, 90), "south"], [P(100, 10, 90), "southwest"], [P(100, 10, 50), "west"], [P(100, 10, 10), "northwest"],
    [P(100, 55, 10), "north"],                 // a little east of north is still north
    [P(200, 50, 50), "east"],                  // another zone of the continent: by world position
  ];
  for (const [to, want] of cases) assert.strictEqual(compass(db, from, to), want, JSON.stringify(to));
  assert.strictEqual(compass(db, from, P(400, 50, 50)), undefined, "another continent has no direction");
  assert.strictEqual(compass(db, from, P(100, 0, 0)), undefined, "a zone without a place has no direction");
  assert.strictEqual(compass(db, from, P(100, 50, 50)), undefined, "the same place has no direction");
});

test("no text is longer than 160 characters", () => {
  const { db } = world();
  db.taxi.push({ id: 8, name: "A".repeat(90) }, { id: 9, name: "B".repeat(90) });
  const fly = { id: "y8-9", at: P(100, 20, 50, 10), lines: [{ kind: "fly", from: 8, to: 9 }] };
  assert.strictEqual(stepText(db, fly, { previous: talk, section: { zone: 100 } }), undefined);
  db.npcs.set(20, { ...db.npcs.get(20), name: "W".repeat(150) });
  const far = { id: "o1", at: P(100, 80, 50, 40), lines: [{ kind: "objective", quest: 1, index: 1, npc: 20 }], targets: { enemy: [20] } };
  const text = stepText(db, far, { previous: talk, section: { zone: 100 } });
  assert.ok(text === undefined || Buffer.byteLength(text) <= 160, text);
  // every template on long real names stays in bounds
  db.areas.get(200).name = "E".repeat(155);
  const go = { id: "g200@200", at: P(200, 50, 50, 20), lines: [{ kind: "goto", at: P(200, 50, 50, 20) }] };
  const t = stepText(db, go, { previous: talk, section: { zone: 100 } });
  assert.ok(t === undefined || Buffer.byteLength(t) <= 160, t);
});

test("a step without a template gets no text", () => {
  const { db } = world();
  const section = { zone: 100 };
  assert.strictEqual(stepText(db, talk, { previous: undefined, section }), undefined, "quest NPC steps have none");
  // an objective close to the previous step
  const near = { id: "o1", at: P(100, 35, 50, 40), lines: [{ kind: "objective", quest: 1, index: 1, npc: 20 }], targets: { enemy: [20] } };
  assert.strictEqual(stepText(db, near, { previous: talk, section }), undefined);
  // "more than 200 yards": an objective exactly 200 yards from the previous step gets none, 210 yards gets one
  const edge = { id: "o1", at: P(100, 50, 50, 40), lines: [{ kind: "objective", quest: 1, index: 1, npc: 20 }], targets: { enemy: [20] } };
  assert.strictEqual(stepText(db, edge, { previous: talk, section }), undefined, "exactly 200 yards");
  const past = { ...edge, at: P(100, 51, 50, 40) };
  assert.strictEqual(stepText(db, past, { previous: talk, section }), "The Grey Wolves are east of Giver Ann.");
  // a goto inside the zone the previous step was in
  const inside = { id: "g100@100", at: P(100, 90, 50, 20), lines: [{ kind: "goto", at: P(100, 90, 50, 20) }] };
  assert.strictEqual(stepText(db, inside, { previous: talk, section }), undefined);
  // a class trainer visit
  const train = { id: "tWARRIOR-4", at: P(100, 30, 52, 10), lines: [{ kind: "train", class: "WARRIOR", level: 4, npc: 10 }] };
  assert.strictEqual(stepText(db, train, { previous: talk, section }), undefined);
});

// Grammar (the project lead's P3 follow-up 3): one named creature, an object or an item is "<Name> is"; only a kill
// objective that needs more than one is "The <plural> are".
test("a single named creature reads '<Name> is <direction> of <place>.'", () => {
  const w = world();
  w.npc(30, 100, 80, 50, "", "Meven Korgal");
  w.quest(2, { startedBy: [[10]], finishedBy: [[10]], objectives: [[[30, null, 0]]], zoneOrSort: 100, objectivesText: ["Kill Meven Korgal and return to Giver Ann."] });
  const step = { id: "o2", at: P(100, 80, 50, 40), lines: [{ kind: "objective", quest: 2, index: 1, npc: 30 }], targets: { enemy: [30] } };
  assert.strictEqual(stepText(w.db, step, { previous: talk, section: { zone: 100 } }), "Meven Korgal is east of Giver Ann.");
});

test("a kill objective that needs more than one reads 'The <plural> are ...'", () => {
  const w = world();
  const step = (quest, npc) => ({ id: `o${quest}`, at: P(100, 80, 50, 40), lines: [{ kind: "objective", quest, index: 1, npc }], targets: { enemy: [npc] } });
  assert.strictEqual(stepText(w.db, step(1, 20), { previous: talk, section: { zone: 100 } }), "The Grey Wolves are east of Giver Ann.");
  // no number, but the text names them in the plural
  w.herd(31, 100, 80, 50, 12); w.db.npcs.get(31).name = "Scarlet Missionary";
  w.quest(3, { startedBy: [[10]], finishedBy: [[10]], objectives: [[[31, null, 0]]], zoneOrSort: 100, objectivesText: ["Drive the Scarlet Missionaries out."] });
  assert.strictEqual(stepText(w.db, step(3, 31), { previous: talk, section: { zone: 100 } }), "The Scarlet Missionaries are east of Giver Ann.");
  // one creature of a herd: not a named one, so "The <name> is"
  w.quest(4, { startedBy: [[10]], finishedBy: [[10]], objectives: [[[31, null, 0]]], zoneOrSort: 100, objectivesText: ["Tame a Scarlet Missionary."] });
  assert.strictEqual(stepText(w.db, step(4, 31), { previous: talk, section: { zone: 100 } }), "The Scarlet Missionary is east of Giver Ann.");
  // a name a herd shares is not a named one either, though this entry stands alone
  w.npc(32, 100, 80, 50, "", "Kobold Worker"); w.herd(33, 100, 10, 10, 12); w.db.npcs.get(33).name = "Kobold Worker";
  w.quest(5, { startedBy: [[10]], finishedBy: [[10]], objectives: [[[32, null, 0]]], zoneOrSort: 100, objectivesText: ["Kill a Kobold Worker."] });
  assert.strictEqual(stepText(w.db, step(5, 32), { previous: talk, section: { zone: 100 } }), "The Kobold Worker is east of Giver Ann.");
  // a person the text names without an article is a named creature, however many spawns its versions have
  w.npc(34, 100, 80, 50, "", "Belathaan Brightwish"); w.herd(35, 100, 10, 10, 6); w.db.npcs.get(35).name = "Belathaan Brightwish";
  w.quest(7, { startedBy: [[10]], finishedBy: [[10]], objectives: [[[34, null, 0]]], zoneOrSort: 100, objectivesText: ["Find Belathaan Brightwish."] });
  assert.strictEqual(stepText(w.db, step(7, 34), { previous: talk, section: { zone: 100 } }), "Belathaan Brightwish is east of Giver Ann.");
});

test("an object or an item reads '<Name> is ...', or 'are' for a plural name", () => {
  const w = world();
  w.object(40, 100, 80, 50, "Sacred Fire");
  w.object(41, 100, 80, 50, "Kodo Bones");
  w.db.items.set(300, { id: 300, name: "Small Egg", npcDrops: [20], objectDrops: [] });
  w.quest(6, { startedBy: [[10]], finishedBy: [[10]], objectives: { "2": [[40, null, 0], [41, null, 0]], "3": [[300, null, 0]] }, zoneOrSort: 100 });
  const at = P(100, 80, 50, 40);
  const ctx = { previous: talk, section: { zone: 100 } };
  assert.strictEqual(stepText(w.db, { id: "o6", at, lines: [{ kind: "objective", quest: 6, index: 1, object: 40 }] }, ctx), "Sacred Fire is east of Giver Ann.");
  assert.strictEqual(stepText(w.db, { id: "o6", at, lines: [{ kind: "objective", quest: 6, index: 2, object: 41 }] }, ctx), "Kodo Bones are east of Giver Ann.");
  assert.strictEqual(stepText(w.db, { id: "o6", at, lines: [{ kind: "objective", quest: 6, index: 3, item: 300 }], targets: { enemy: [20] } }, ctx), "Small Egg is east of Giver Ann.",
    "the item, not the creature that drops it");
});

test("plurals follow English rules on the last word", () => {
  const cases = [["Grey Wolf", "Grey Wolves"], ["Young Stranglethorn Tiger", "Young Stranglethorn Tigers"], ["Scarlet Missionary", "Scarlet Missionaries"],
    ["Defias Watchman", "Defias Watchmen"], ["Stormscale Sorceress", "Stormscale Sorceresses"], ["Kobold Vermin", "Kobold Vermin"],
    ["Mottled Boar", "Mottled Boars"], ["Bloodscalp Shaman", "Bloodscalp Shamans"], ["Thistlefur Ursa", "Thistlefur Ursas"],
    ["Spirit of the Glade", "Spirits of the Glade"], ["Dark Iron Dwarf", "Dark Iron Dwarves"], ["Swamp Jaguar", "Swamp Jaguars"], ["Venture Co. Thief", "Venture Co. Thieves"],
    ["Ghoul", "Ghouls"], ["Gnoll Brute", "Gnoll Brutes"], ["Highland Fox", "Highland Foxes"]];
  for (const [one, many] of cases) assert.strictEqual(plural(one), many);
});

test("where the objective text does not name the creature, a name with at most 3 spawns is a named one", () => {
  const w = world();
  w.npc(36, 100, 80, 50, "", "Old Murk-Eye"); w.herd(37, 100, 80, 50, 12); w.db.npcs.get(37).name = "Dire Mottled Boar";
  w.quest(8, { startedBy: [[10]], finishedBy: [[10]], objectives: [[[36, null, 0], [37, null, 0]]], zoneOrSort: 100, objectivesText: ["Bring proof to Giver Ann."] });
  const step = (npc) => ({ id: "o8", at: P(100, 80, 50, 40), lines: [{ kind: "objective", quest: 8, index: 1, npc }] });
  const ctx = { previous: talk, section: { zone: 100 } };
  assert.strictEqual(stepText(w.db, step(36), ctx), "Old Murk-Eye is east of Giver Ann.");
  assert.strictEqual(stepText(w.db, step(37), ctx), "The Dire Mottled Boar is east of Giver Ann.");
});
