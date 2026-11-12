// Noir Guides, GPLv3. See LICENSE.
// The data behind the ported modules (task X2): talent trees and builds, profession skill lines, and the quests the
// quest cleanup weighs before it lists a quest. tools/gen_ports.js writes them to NoirGuides/Data/ from the fetched data.
const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");
const { loadTrees, expand, checkBuild, POINTS } = require("../lib/talents");
const { BUILDS } = require("../lib/talent_builds");
const ports = require("../gen_ports");

const ROOT = path.join(__dirname, "..", "..");
const DATA = path.join(__dirname, "..", "data");
const real = ["Talent", "TalentTab", "SpellName", "SkillLine", "QuestSort", "ChrClasses"].every((t) => fs.existsSync(path.join(DATA, "wago", t + ".csv")))
  && fs.existsSync(path.join(DATA, "forever_db.json"));

// A made-up tree: tier 1 has A (3 ranks) and B (2), tier 2 has C (needs A at 3), tier 3 has D.
const TREE = {
  tabs: [{
    id: 1, name: "Tree", talents: [
      { id: 1, name: "A", tier: 1, column: 1, max: 3 },
      { id: 2, name: "B", tier: 1, column: 2, max: 2 },
      { id: 3, name: "C", tier: 2, column: 1, max: 5, prereq: 1, prereqRank: 3 },
      { id: 4, name: "D", tier: 3, column: 1, max: 1 },
    ],
  }, { id: 2, name: "Other", talents: [{ id: 5, name: "E", tier: 1, column: 1, max: 5 }] }],
};

test("expand turns picks into one talent per point", () => {
  assert.deepStrictEqual(expand([[1, 2], [5, 1]]), [1, 1, 5]);
});

test("checkBuild accepts a build that is learnable point by point", () => {
  assert.deepStrictEqual(checkBuild(TREE, expand([[1, 3], [2, 2], [3, 5], [4, 1]]), { points: 11 }), []);
});

test("checkBuild refuses a tier taken too early, a missing prerequisite, too many ranks and a wrong count", () => {
  const tier = checkBuild(TREE, expand([[1, 3], [2, 1], [3, 1]]), { points: 5 });
  assert.match(tier.join("\n"), /level 14: C \(Tree\) needs 5 points in Tree, has 4/);
  const prereq = checkBuild(TREE, expand([[2, 2], [5, 3], [1, 2], [3, 1]]), { points: 8 });
  assert.match(prereq.join("\n"), /level 17: C \(Tree\) needs A at rank 3/);
  const ranks = checkBuild(TREE, expand([[2, 3]]), { points: 3 });
  assert.match(ranks.join("\n"), /level 12: B \(Tree\) would be rank 3 of 2/);
  assert.match(checkBuild(TREE, [1], {}).join("\n"), /the build has 1 points, not 51/);
  assert.match(checkBuild(TREE, [99], { points: 1 }).join("\n"), /talent 99 is not in this class's trees/);
});

test("checkBuild counts the tier rule per tree", () => {
  // Points in another tree do not open tier 2 of this one.
  assert.match(checkBuild(TREE, expand([[5, 5], [1, 3], [3, 1]]), { points: 9 }).join("\n"), /needs 5 points in Tree, has 3/);
});

test("Lua output of the talents is plain data the engine reads", () => {
  const lua = ports.talentsLua({ ROGUE: TREE }, { ROGUE: { spec: "Tree", picks: [[1, 3], [2, 2], [3, 5], [4, 1]] } }, { build: "1.2.3", points: 11 });
  assert.ok(lua.startsWith("-- Noir Guides, GPLv3. See LICENSE.\n"));
  assert.match(lua, /Noir\.Data\.talents = \{/);
  assert.match(lua, /ROGUE = \{\n    spec = "Tree",/);
  assert.match(lua, /\{ id = 3, name = "C", tier = 2, column = 1, max = 5, prereq = 1, prereqRank = 3 \}/);
  assert.match(lua, /build = \{ 1, 1, 1, 2, 2, 3, 3, 3, 3, 3, 4 \}/);
});

test("talentsLua refuses a build that cannot be learned", () => {
  assert.throws(() => ports.talentsLua({ ROGUE: TREE }, { ROGUE: { spec: "Tree", picks: [[3, 1]] } }, { build: "x", points: 1 }), /ROGUE.*needs/);
});

test("a talent without a name in the data is written without one", () => {
  const tree = { tabs: [{ id: 1, name: "T", talents: [{ id: 7, name: undefined, tier: 1, column: 1, max: 1 }] }] };
  const lua = ports.talentsLua({ MAGE: tree }, { MAGE: { spec: "T", picks: [[7, 1]] } }, { build: "x", points: 1 });
  assert.match(lua, /\{ id = 7, tier = 1, column = 1, max = 1 \}/);
});

test("questTies records what ties a quest beyond its giver: class, skill, instance, event, starting item", () => {
  const quests = [
    { id: 1, classes: 1 + 8, sort: 0, zone: 12, starts: { items: [] } },
    { id: 2, classes: 0, sort: -24, zone: 0, starts: { items: [] } },
    { id: 3, classes: 0, sort: 0, zone: 12, requiredSkill: [2944, 50], starts: { items: [] } },
    { id: 4, classes: 0, sort: 0, zone: 1581, starts: { items: [] } },
    { id: 5, classes: 0, sort: -1, zone: 0, starts: { items: [] } },
    { id: 6, classes: 0, sort: -22, zone: 0, starts: { items: [] } },
    { id: 7, classes: 0, sort: 0, zone: 12, starts: { items: [1307, 1308] } },
    { id: 8, classes: 0, sort: -367, zone: 0, starts: { items: [] } },
    { id: 9, classes: 0, sort: 0, zone: 12, starts: { items: [] } },
    { id: 10, classes: 4, sort: 0, zone: 1581, starts: { items: [900] } },
  ];
  const ctx = {
    sortName: (id) => ({ 1: "Epic", 22: "Seasonal", 24: "Herbalism", 367: "Reputation" })[id],
    professions: { 182: { name: "Herbalism" } },
    lines: { 2944: 182 },
    instanceName: (zone) => (zone === 1581 ? "The Deadmines" : null),
    itemName: (id) => ({ 1307: "Gold Pickup Schedule", 900: "Odd Note" })[id],
  };
  assert.deepStrictEqual(ports.questTies(quests, ctx), {
    1: { classes: ["WARRIOR", "ROGUE"] },
    2: { skill: 182 },
    3: { skill: 182 },
    4: { instance: "The Deadmines" },
    6: { event: "Seasonal" },
    7: { item: "Gold Pickup Schedule" },
    10: { classes: ["HUNTER"], instance: "The Deadmines", item: "Odd Note" },
  });
});

test("questTiesLua writes one plain table per quest, sorted, in Noir's namespace", () => {
  const lua = ports.questTiesLua({ 7: { item: "A \"B\"" }, 1: { classes: ["WARRIOR"], skill: 182 } }, { release: "v9" });
  assert.ok(lua.startsWith("-- Noir Guides, GPLv3. See LICENSE.\n"));
  const body = [
    "Noir.Data.questTies = {",
    '  [1] = { classes = { "WARRIOR" }, skill = 182 },',
    '  [7] = { item = "A \\"B\\"" },',
    "}",
  ].join("\n");
  assert.ok(lua.includes(body), lua);
});

test("real data: every class has a build that is learnable point by point, 51 points, names as in the data", { skip: !real }, () => {
  const trees = loadTrees(DATA);
  assert.deepStrictEqual(Object.keys(BUILDS).sort(), Object.keys(trees).sort());
  assert.strictEqual(Object.keys(trees).length, 9);
  for (const [cls, build] of Object.entries(BUILDS)) {
    const tree = trees[cls];
    assert.ok(tree.tabs.some((t) => t.name === build.spec), `${cls}: ${build.spec} is one of its trees`);
    assert.deepStrictEqual(checkBuild(tree, expand(build.picks)), [], cls);
    assert.strictEqual(expand(build.picks).length, POINTS);
    const byId = new Map(tree.tabs.flatMap((t) => t.talents.map((x) => [x.id, x])));
    for (const [id, , name] of build.picks) assert.strictEqual(byId.get(id).name || null, name, `${cls} talent ${id}`);
    // The build's main tree gets the 31 points that reach its last tier.
    const main = tree.tabs.find((t) => t.name === build.spec);
    const inMain = expand(build.picks).filter((id) => main.talents.some((x) => x.id === id)).length;
    assert.ok(inMain >= 31, `${cls}: ${inMain} points in ${build.spec}`);
  }
});

test("real data: the professions and Forever's tier lines are read from SkillLine", { skip: !real }, () => {
  const { professions, lines } = ports.loadProfessions(DATA);
  assert.deepStrictEqual(Object.keys(professions).map(Number).sort((a, b) => a - b), [129, 164, 165, 171, 182, 185, 186, 197, 202, 333, 356, 393]);
  assert.deepStrictEqual(professions[393], { name: "Skinning", kind: "primary" });
  assert.deepStrictEqual(professions[185], { name: "Cooking", kind: "secondary" });
  assert.strictEqual(lines[2947], 393);
  assert.strictEqual(Object.keys(lines).length, 12);
});

test("real data: class, skill, instance, event and item ties are found in plausible numbers", { skip: !real }, () => {
  const ties = ports.loadQuestTies(DATA);
  const db = JSON.parse(fs.readFileSync(path.join(DATA, "forever_db.json"), "utf8")).Quest;
  const firstWith = (fn) => Number(Object.keys(db).find((id) => fn(db[id])));
  assert.ok(ties[firstWith((q) => q.requiredClasses && q.requiredClasses !== 1503)].classes.length > 0);
  const skilled = firstWith((q) => q.requiredSkill);
  assert.ok(ties[skilled].skill > 0, `quest ${skilled} has a skill tie`);
  const count = (key) => Object.values(ties).filter((t) => t[key] !== undefined).length;
  for (const key of ["classes", "skill", "instance", "event", "item"]) assert.ok(count(key) > 20, `${key}: ${count(key)}`);
  assert.ok(Object.values(ties).every((t) => !t.classes || t.classes.every((c) => /^[A-Z]+$/.test(c))));
});

test("real data: NoirGuides/Data holds exactly what gen_ports.js writes (run `npm run ports` in tools/)", { skip: !real }, () => {
  const files = ports.generate(DATA);
  assert.deepStrictEqual(Object.keys(files).sort(), ["Cleanup.lua", "Professions.lua", "Talents.lua"]);
  for (const [name, text] of Object.entries(files)) {
    const onDisk = path.join(ROOT, "NoirGuides", "Data", name);
    assert.ok(fs.existsSync(onDisk), name);
    assert.strictEqual(fs.readFileSync(onDisk, "utf8"), text, name);
  }
});
