// Noir Guides, GPLv3. See LICENSE.
// The simulator's Node side (tools/sim_all.js): the format 3 route files it reads, the world it builds from the
// flattened steps, the joiner's preparation (tools/harness/sim.lua, called through the VM), the pace formulas
// sim.lua carries in Lua (which must give the planner's numbers), and one whole character played by the real addon.
const test = require("node:test");
const assert = require("node:assert");
const { testWorld, at } = require("./world");
const { createVm } = require("../harness/vm");
const { mobXp, questXp, walkXp, objectiveXp, XP_TO_LEVEL } = require("../lib/xp");
const { emitRoute3 } = require("../planner/emit3");
const { buildFacts, flattenFor, parseRoute, toLua, simulate, summarize, passed, joinerList } = require("../sim_all");

// A VM with the simulator loaded, for calling its Lua functions from here.
function simVm() {
  const lines = [];
  const vm = createVm({ print: (l) => lines.push(l) });
  for (const file of ["tools/harness/env.lua", "tools/harness/wow.lua", "tools/harness/sim.lua"]) {
    assert.strictEqual(vm.runFile(file), null, file);
  }
  const call = (expr) => {
    lines.length = 0;
    assert.strictEqual(vm.run(`print(${expr})`, "=test"), null, expr);
    return Number(lines[0]);
  };
  const json = (code) => {
    lines.length = 0;
    assert.strictEqual(vm.run(code, "=test"), null, code.slice(0, 200));
    const line = lines.find((l) => l.startsWith("JSON "));
    assert.ok(line, "the Lua code printed no JSON line");
    return JSON.parse(line.slice(5));
  };
  return { vm, call, json };
}

// A format 3 section for the test world (Westland, zone 100).
function section(id, name, steps, more = {}) {
  return { id, name, group: "Horde", subgroup: "1-20", minLevel: 1, maxLevel: 10, zone: 100, ...more, next: more.next || [], steps };
}
function route3(sections) {
  return { id: "horde-orc", format: 3, race: "Orc", faction: "Horde", sections };
}
const npcPlace = (x, y) => ({ ...at(100, x, y), r: 10 });

test("the simulator's pace formulas give the numbers of lib/xp.js", () => {
  const { call } = simVm();
  for (let player = 1; player <= 60; player++) {
    for (let mob = 1; mob <= 64; mob += 3) assert.strictEqual(call(`HARNESS.Sim.mobXp(${mob}, ${player})`), mobXp(mob, player), `mobXp(${mob}, ${player})`);
    for (let level = 1; level <= 62; level += 2) assert.strictEqual(call(`HARNESS.Sim.questXp(${level}, ${player})`), questXp(level, player), `questXp(${level}, ${player})`);
  }
  const pace = "{ OBJECTIVE_KILLS = 8, ITEM_KILL_FACTOR = 2, INCIDENTAL_YARDS = 300 }";
  const quest = { level: 12, objectives: { npcs: [1, 2], objects: [3], items: [4] } };
  for (const player of [5, 12, 20]) {
    assert.strictEqual(call(`HARNESS.Sim.objectiveXp({ level = 12, kills = 2, items = 1, objects = 1 }, ${player}, ${pace})`), objectiveXp(quest, player));
    for (const yards of [0, 150, 777, 4000]) {
      const band = { min: 10, max: 18, wild: true };
      assert.strictEqual(call(`HARNESS.Sim.walkXp(${yards}, { min = 10, max = 18, wild = true }, ${player}, ${pace})`), walkXp(yards, band, player), `walkXp(${yards}, ${player})`);
    }
    assert.strictEqual(call(`HARNESS.Sim.walkXp(500, { min = 10, max = 18, wild = false }, ${player}, ${pace})`), 0);
  }
});

test("a format 3 route file reads back as its sections, steps and lines", () => {
  const route = route3([
    section("orc-01-02-westland", "1-2 Westland", [
      { id: "a7", at: npcPlace(10.5, 20), text: "Grunt Varg waits by the gate.", lines: [{ kind: "accept", quest: 7, npc: 3 }], targets: { friend: [3] } },
      { id: "o7", at: { ...at(100, 30, 40), r: 40 }, label: "kill7", reminder: { ends: "turnin7" },
        lines: [{ kind: "objective", quest: 7, index: 1, npc: 12 }, { kind: "objective", quest: 7, index: 2, item: 99, skipIfMissing: true }] },
      { id: "t7", label: "turnin7", at: npcPlace(10.5, 20), minLevel: 2, lines: [{ kind: "turnin", quest: 7, npc: 3 }] },
      { id: "y4-5", at: npcPlace(20, 60), when: { class: ["ROGUE", "WARRIOR"] }, lines: [{ kind: "fly", from: 4, to: 5 }] },
      { id: "x400", at: { ...at(100, 60, 90), r: 15 }, lines: [{ kind: "transport", mode: "zeppelin", at: at(100, 60, 90), to: { ...at(400, 60, 10), r: 50 } }] },
      { id: "h", lines: [{ kind: "hearth", to: { ...at(100, 22, 50), r: 20 } }] },
      { id: "l3@100", at: at(100, 1, 2), lines: [{ kind: "grind", level: 3, percent: 40 }] },
    ], { start: true, next: [{ section: "orc-02-03-eastland" }] }),
    section("orc-02-03-eastland", "2-3 Eastland", [
      { id: "tWARRIOR-2", at: npcPlace(30, 30), when: { class: "WARRIOR" }, lines: [{ kind: "train", level: 2, class: "WARRIOR", npc: 44 }] },
    ], { minLevel: 2, zone: 200 }),
  ]);
  const back = parseRoute(emitRoute3(route));
  assert.deepStrictEqual(back, route);
});

test("the world is built from the flattened steps", () => {
  const w = testWorld();
  w.npc(10, 100, 30, 30, "AH", "Giver"); w.npc(11, 100, 40, 40, "AH", "Taker"); w.npc(12, 100, 50, 50, "", "Wolf");
  w.kill(1, 10, 12, 100, { questLevel: 3, requiredLevel: 2 });
  w.errand(2, 10, 11, 100, { preQuestGroup: [1], preQuestSingle: [5, 6], exclusiveTo: [3], requiredMaxLevel: 20 });
  w.errand(3, 10, 10, 100);
  w.quest(4, { startedBy: [null, [500]], finishedBy: [null, [501]], zoneOrSort: 100, triggerEnd: ["Find it", { 100: [[1, 1]] }] });
  w.object(500, 100, 60, 60, "Sign"); w.object(501, 100, 61, 61, "Chest");
  const ch = w.orc("WARRIOR");
  const route = route3([
    section("orc-01-02-westland", "1-2 Westland", [
      { id: "a1.a2", at: npcPlace(30, 30), lines: [{ kind: "accept", quest: 1, npc: 10 }, { kind: "accept", quest: 2, npc: 10 }] },
      { id: "a3", at: npcPlace(30, 30), when: { class: "MAGE" }, lines: [{ kind: "accept", quest: 3, npc: 10 }] },
      { id: "o1", at: { ...at(100, 50, 50), r: 40 }, lines: [{ kind: "objective", quest: 1, index: 1, npc: 12 }] },
      { id: "a4", at: npcPlace(60, 60), lines: [{ kind: "accept", quest: 4, object: 500 }, { kind: "accept", quest: 3, npc: 10, when: { class: "MAGE" } }] },
      { id: "b", at: npcPlace(22, 50), lines: [{ kind: "sethearth", npc: 800 }] },
    ], { start: true, next: [{ section: "orc-02-03-eastland" }] }),
    section("orc-02-03-eastland", "2-3 Eastland", [
      { id: "t2", at: npcPlace(40, 40), lines: [{ kind: "turnin", quest: 2, npc: 11 }] },
      { id: "t4", at: { ...at(400, 61, 61), r: 10 }, lines: [{ kind: "turnin", quest: 4, object: 501 }, { kind: "train", level: 2, class: "WARRIOR", npc: 44 }] },
    ], { minLevel: 2 }),
  ]);
  const flat = flattenFor(route, ch);
  assert.deepStrictEqual(flat.map((a) => `${a.section}/${a.step}:${a.action}${a.quest || ""}`), [
    "orc-01-02-westland/a1.a2:accept1", "orc-01-02-westland/a1.a2:accept2", "orc-01-02-westland/o1:objective1",
    "orc-01-02-westland/a4:accept4", "orc-01-02-westland/b:sethearth",
    "orc-02-03-eastland/t2:turnin2", "orc-02-03-eastland/t4:turnin4",
  ], "the character's steps in chain order, a line of another class left out, train lines have no action");
  const f = buildFacts(w.db, w.graph(), w.inns, route, ch);
  assert.deepStrictEqual(f.flat, flat.map((a) => JSON.parse(JSON.stringify(a))));
  assert.strictEqual(f.race, "Orc");
  assert.strictEqual(f.class, "WARRIOR");
  assert.deepStrictEqual(f.quests[1], { title: "Quest 1", level: 3, minLevel: 2, pre: [], preAny: [], exclusive: [], kills: 1, items: 0, objects: 0, credits: 0, event: false });
  assert.deepStrictEqual(f.quests[2], { title: "Quest 2", level: 1, minLevel: 1, maxLevel: 20, pre: [1], preAny: [5, 6], exclusive: [3], kills: 0, items: 0, objects: 0, credits: 0, event: false });
  assert.strictEqual(f.quests[3], undefined, "a line of another class is not part of this character's world");
  assert.strictEqual(f.quests[4].event, true);
  assert.deepStrictEqual(f.npcs[10].offers, [1, 2]);
  assert.deepStrictEqual(f.npcs[10].ends, [1]);
  assert.deepStrictEqual(f.npcs[11].ends, [2]);
  assert.deepStrictEqual(f.objects[500], { name: "Sign", offers: [4], ends: [] });
  assert.deepStrictEqual(f.objects[501], { name: "Chest", offers: [], ends: [4] });
  assert.strictEqual(f.npcs[800].binder, "Westland");
  assert.deepStrictEqual(f.start, npcPlace(30, 30), "the character starts at the first place of its route");
  // the Horde's flight points only, where the Horde's flight master stands
  assert.deepStrictEqual(Object.keys(f.taxi).map(Number).sort((a, b) => a - b), [4, 5, 6, 7]);
  assert.deepStrictEqual(f.taxi[4], { name: "Horde Post, Westland", continent: 0, zone: 100, x: 20, y: 60, npc: 904 });
  assert.strictEqual(f.npcs[904].taxi, 4);
  assert.deepStrictEqual(f.zones[100], { uiMap: 9100, name: "Westland", continent: 0, minX: 0, maxX: 1000, minY: 0, maxY: 1000,
    band: { min: 1, max: 3, wild: false } });
  assert.ok(f.zones[400] && f.zones[200], "zones of flight points and steps");
  assert.deepStrictEqual(f.continents[0], { uiMap: 1415, name: "continent 0", top: 1000, left: 1000, width: 2000, height: 1000 });
  assert.strictEqual(f.xpToLevel[1], XP_TO_LEVEL[1]);
  assert.strictEqual(f.xpToLevel[59], XP_TO_LEVEL[59]);
  assert.strictEqual(f.pace.OBJECTIVE_KILLS, 8);
  assert.strictEqual(f.route, undefined, "the shipped route is not carried in the facts unless asked for");
});

test("a quest the character may not take is closed in the simulated world, with the reason", () => {
  const w = testWorld();
  w.npc(10, 100, 30, 30, "AH", "Giver");
  w.errand(3, 10, 10, 100, { requiredRaces: 1 });
  const route = route3([section("orc-01-02-westland", "1-2 Westland", [{ id: "a3", at: npcPlace(30, 30), lines: [{ kind: "accept", quest: 3, npc: 10 }] }], { start: true })]);
  const f = buildFacts(w.db, w.graph(), w.inns, route, w.orc("WARRIOR"));
  assert.match(f.quests[3].closed, /not open to Orc WARRIOR/);
});

test("prepareJoin leaves out every 7th optional accept", () => {
  const w = testWorld();
  w.npc(10, 100, 30, 30, "AH", "Giver"); w.npc(12, 100, 50, 50, "", "Wolf");
  for (let q = 1; q <= 16; q++) w.kill(q, 10, 12, 100, q === 16 ? { preQuestGroup: [14] } : {});
  const accepts = [], objectives = [], turnins = [];
  for (let q = 1; q <= 15; q++) {
    accepts.push({ kind: "accept", quest: q, npc: 10 });
    objectives.push({ kind: "objective", quest: q, index: 1, npc: 12 });
    turnins.push({ kind: "turnin", quest: q, npc: 10 });
  }
  const route = route3([section("orc-01-02-westland", "1-2 Westland", [
    { id: "a", at: npcPlace(30, 30), lines: accepts },
    { id: "o", at: { ...at(100, 50, 50), r: 40 }, lines: objectives },
    { id: "t", at: npcPlace(30, 30), lines: turnins },
    { id: "a16", at: npcPlace(30, 30), lines: [{ kind: "accept", quest: 16, npc: 10 }] },
    { id: "l60@100", at: at(100, 50, 50), lines: [{ kind: "grind", level: 60 }] },
  ], { start: true })]);
  const f = buildFacts(w.db, w.graph(), w.inns, route, w.orc("WARRIOR"));
  const { json } = simVm();
  const run = (level) => json(`SIM_FACTS = ${toLua(f)}
    local p = HARNESS.Sim.prepareJoin(SIM_FACTS, ${level})
    local log, done = {}, {}
    for _, q in ipairs(p.server.quests) do log[#log + 1] = q.id end
    for id in pairs(p.server.completed) do done[#done + 1] = id end
    table.sort(done)
    print("JSON " .. HARNESS.Sim.json({ leftOut = p.leftOut, expectedFrom = p.expectedFrom, log = log, done = done, level = p.server.level }))`);
  // Quest 14 is a prerequisite of quest 16, a later route quest: never left out, so the 7th and 14th optional
  // accepts are quests 7 and 15.
  const all = run(60);
  assert.deepStrictEqual(all.leftOut, [7, 15]);
  assert.deepStrictEqual(all.done, [1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12, 13, 14], "their objectives and hand-ins are left out with them");
  assert.deepStrictEqual(all.log, [16]);
  assert.strictEqual(all.level, 60);
  assert.strictEqual(all.expectedFrom, f.flat.length, "the last action the prepared player did");
  const first = run(1);
  assert.deepStrictEqual([first.log, first.done, first.expectedFrom, first.level], [[1], [], 1, 1], "level 1: the first quest only");
});

test("the joiners: each race at each join level, its class picked in turn", () => {
  const combos = [
    { race: "Orc", cls: "HUNTER" }, { race: "Orc", cls: "ROGUE" }, { race: "Orc", cls: "WARRIOR" },
    { race: "Troll", cls: "MAGE" },
  ];
  const list = joinerList(combos, [1, 12, 25, 40, 55]);
  assert.deepStrictEqual(list.map((j) => `${j.race} ${j.cls} ${j.join}`), [
    "Orc HUNTER 1", "Orc ROGUE 12", "Orc WARRIOR 25", "Orc HUNTER 40", "Orc ROGUE 55",
    "Troll MAGE 1", "Troll MAGE 12", "Troll MAGE 25", "Troll MAGE 40", "Troll MAGE 55",
  ]);
  assert.strictEqual(joinerList(combos, [1, 12, 25, 40, 55], true).length, 20, "--joiners all: every class at every level");
});

test("facts become a Lua table the VM reads back", () => {
  const lua = toLua({ a: 1, b: [1, 2], c: { 5: "x\"y\\z\n" }, d: true, e: undefined });
  const lines = [];
  const vm = createVm({ print: (l) => lines.push(l) });
  assert.strictEqual(vm.run(`local t = ${lua}\nprint(t.a, t.b[2], t.c[5], t.d, t.e)`, "=test"), null);
  assert.deepStrictEqual(lines, ["1\t2\tx\"y\\z\n\ttrue\tnil"]);
});

test("a whole character played by the real addon in the simulated world", () => {
  // The shipped addon with its shipped routes needs the fetched data; this plays a small hand-written world
  // through the same runner instead, with the route registered by the simulator.
  const w = testWorld();
  w.npc(10, 100, 30, 30, "AH", "Giver"); w.npc(12, 100, 50, 50, "", "Wolf");
  w.kill(1, 10, 12, 100, { questLevel: 1 });
  const route = route3([section("orc-01-02-westland", "1-2 Westland", [
    { id: "a1", at: npcPlace(30, 30), lines: [{ kind: "accept", quest: 1, npc: 10 }] },
    { id: "o1", at: { ...at(100, 50, 50), r: 40 }, lines: [{ kind: "objective", quest: 1, index: 1, npc: 12 }] },
    { id: "t1", at: npcPlace(30, 30), lines: [{ kind: "turnin", quest: 1, npc: 10 }] },
    { id: "f4", at: npcPlace(20, 60), lines: [{ kind: "getflight", node: 4, npc: 904 }] },
  ], { start: true })]);
  const ch = w.orc("WARRIOR");
  const f = buildFacts(w.db, w.graph(), w.inns, route, ch, { withRoute: true });
  assert.ok(f.route, "the route is carried for registering");
  const r = simulate(f, { register: true });
  assert.deepStrictEqual([r.finished, r.stuck, r.cannot, r.unexplained, r.errors, r.slash, r.offScreen], [true, [], [], [], [], 0, []]);
  assert.strictEqual(r.level, 2);
  assert.strictEqual(passed(r), false, "a run that ends below level 60 fails");
  assert.strictEqual(passed({ ...r, level: 60 }), true);
  assert.strictEqual(passed({ ...r, level: 60, slash: 1 }), false, "a slash command fails the run");
  assert.strictEqual(passed({ ...r, level: 60, join: 12, placement: { expectedFrom: 50, landed: 9, inside: false } }), false, "a joiner placed outside its window fails");
  const s = summarize([{ ...r, level: 60 }, r]);
  assert.deepStrictEqual([s.characters, s.at60, s.stuck, s.unexplained, s.ok], [2, 1, 0, 0, false]);
});
