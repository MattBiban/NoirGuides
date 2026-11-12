// Noir Guides, GPLv3. See LICENSE.
// Route format 3's validator on the JavaScript side (tools/planner/format3.js). The cases and their expected
// sentences are in tools/test-lua/sample/format3-cases.lua, read through the Lua VM, so the Lua validator
// (NoirGuides/Routes.lua, tested in tools/test-lua/routes.lua) is held to the same words.
const test = require("node:test");
const assert = require("node:assert");
const { createVm } = require("../harness/vm");
const { checkRoute3, RULES } = require("../planner/format3");

const CASES = "tools/test-lua/sample/format3-cases.lua";
const SAMPLES = ["tools/test-lua/sample/v3/horde-undead.lua", "tools/test-lua/sample/v3/alliance-human.lua"];

function readCases() {
  return createVm({ print() {} }).valueOfFile(CASES);
}

// A route file calls Noir.Route(id, data): this catches the call and returns { id, data }.
function readRouteFile(rel) {
  const vm = createVm({ print() {} });
  assert.strictEqual(vm.run("Noir = { Route = function(id, data) CAUGHT = { id = id, data = data } return true end }", "=stub"), null);
  assert.strictEqual(vm.runFile(rel), null, rel);
  return vm.value("return CAUGHT", "=caught");
}

test("every case in format3-cases.lua gets the expected verdict from checkRoute3", () => {
  const cases = readCases();
  assert.ok(cases.length >= 100, `${cases.length} cases`);
  const wrong = [];
  for (const c of cases) {
    assert.ok(c.valid === true || typeof c.expect === "string", `case "${c.name}" has an expected verdict`);
    const got = checkRoute3(c.route);
    const want = c.valid ? null : c.expect;
    if (got !== want) wrong.push(`${c.rule} ${c.name}\n    want ${JSON.stringify(want)}\n    got  ${JSON.stringify(got)}`);
  }
  assert.deepStrictEqual(wrong, []);
});

test("both v3 samples are valid", () => {
  for (const rel of SAMPLES) {
    const { id, data } = readRouteFile(rel);
    assert.match(id, /^(alliance|horde)-[a-z]+$/);
    assert.strictEqual(checkRoute3(data), null, rel);
  }
});

test("each rule R1 to R12 has at least one failing case", () => {
  assert.deepStrictEqual(RULES.map((r) => r.id), ["R1", "R2", "R3", "R4", "R5", "R6", "R7", "R8", "R9", "R10", "R11", "R12"]);
  for (const r of RULES) assert.ok(typeof r.text === "string" && r.text.length > 10, r.id);
  const cases = readCases();
  for (const r of RULES) {
    assert.ok(cases.some((c) => c.rule === r.id && typeof c.expect === "string"), `${r.id} has a failing case`);
    assert.ok(cases.some((c) => c.rule === r.id), r.id);
  }
  for (const c of cases) assert.ok(RULES.some((r) => r.id === c.rule), `case "${c.name}" names a known rule`);
});

test("the message names at most three problems and counts the rest", () => {
  const cases = readCases();
  const base = cases.find((c) => c.name === "the base route").route;
  assert.strictEqual(checkRoute3(base), null);
  for (const count of [1, 2, 3, 4, 9]) {
    const route = structuredClone(base);
    const step = route.sections[0].steps[0];
    for (let i = 0; i < count; i++) step[`extra${i}`] = i;
    const message = checkRoute3(route);
    const parts = message.split("; ");
    const named = parts.filter((p) => p.startsWith("section "));
    assert.strictEqual(named.length, Math.min(count, 3), message);
    for (const p of named) assert.match(p, /^section undead-01-03-deathknell step a364 has the unknown key "extra\d"$/);
    if (count > 3) assert.strictEqual(parts[parts.length - 1], `and ${count - 3} more`);
    else assert.ok(!message.includes("more"), message);
  }
});

test("problems that name keys list them in sorted order, whatever order the table was built in", () => {
  const base = readCases().find((c) => c.name === "the base route").route;
  const one = structuredClone(base);
  const two = structuredClone(base);
  Object.assign(one.sections[0].steps[0], { zeta: 1, alpha: 2 });
  Object.assign(two.sections[0].steps[0], { alpha: 2, zeta: 1 });
  assert.strictEqual(checkRoute3(one), checkRoute3(two));
  assert.match(checkRoute3(one), /"alpha".*"zeta"/);
});
