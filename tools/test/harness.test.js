// Noir Guides, GPLv3. See LICENSE.
// The Lua test tooling itself: a runner that cannot fail and a lint that lets Lua 5.3 through would make every
// engine test worthless. The fixtures in tools/harness/selftest/ fail on purpose.
const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");
const { runAll } = require("../harness/run");
const { lintSource, lintAddon, HEADER } = require("../harness/lint");
const { ROOT, createVm } = require("../harness/vm");

const SELFTEST = "tools/harness/selftest";
const run = (filter) => {
  const lines = [];
  const totals = runAll({ testDir: SELFTEST, filter, lint: false, pairsModes: ["normal"], log: (l) => lines.push(l) });
  return { totals, text: lines.join("\n") };
};
const lint = (body, rel = "NoirGuides/Sample.lua") => lintSource(`${HEADER}\n${body}\n`, rel).map((p) => p.message);

test("runner: a passing file is ok", () => {
  const { totals } = run("passing");
  assert.deepStrictEqual([totals.passed, totals.failed, totals.fileErrors, totals.ok], [2, 0, 0, true]);
});

test("runner: a failed assertion fails the run and shows both values", () => {
  const { totals, text } = run("failing");
  assert.deepStrictEqual([totals.passed, totals.failed, totals.ok], [1, 1, false]);
  assert.match(text, /FAILED {2}fails/);
  assert.match(text, /the table: expected \{ a = 2 \}/);
  assert.match(text, /but got \{ a = 1 \}/);
  assert.match(text, /failing\.lua:4/);
});

test("runner: a Lua error inside the addon or a forbidden call fails a test whose assertions hold", () => {
  const { totals, text } = run("addonerror");
  assert.deepStrictEqual([totals.passed, totals.failed, totals.ok], [0, 2, false]);
  assert.match(text, /raised inside the addon/);
  assert.match(text, /forbidden call: registered COMBAT_LOG_EVENT_UNFILTERED/);
});

test("runner: a file that does not parse, has no tests, or a filter that matches nothing is a failure", () => {
  const broken = run("broken");
  assert.strictEqual(broken.totals.ok, false);
  assert.strictEqual(broken.totals.fileErrors, 1);
  assert.match(broken.text, /broken\.lua:3/);
  const empty = run("empty");
  assert.strictEqual(empty.totals.ok, false);
  assert.match(empty.text, /defines no tests/);
  const none = run("no-such-file");
  assert.strictEqual(none.totals.ok, false);
  assert.match(none.text, /no test files/);
});

test("runner: by default every file runs a second time with pairs reversed", () => {
  const lines = [];
  const totals = runAll({ testDir: SELFTEST, filter: "passing", lint: false, log: (l) => lines.push(l) });
  assert.deepStrictEqual([totals.files, totals.passed, totals.ok], [2, 4, true]);
  assert.match(lines.join("\n"), /passing\.lua \(pairs reversed\)/);
});

test("runner: the command exits 1 on failure", () => {
  const { spawnSync } = require("node:child_process");
  const script = "const r = require('./harness/run'); process.exit(r.runAll({ testDir: 'tools/harness/selftest', filter: 'failing', lint: false, pairsModes: ['normal'], log() {} }).ok ? 0 : 1);";
  const result = spawnSync(process.execPath, ["-e", script], { cwd: path.join(ROOT, "tools") });
  assert.strictEqual(result.status, 1);
});

test("vm: files outside the repository cannot be read from Lua", () => {
  const vm = createVm();
  assert.strictEqual(vm.run('local text, err = host.read("../outside.txt") assert(text == nil and err, "must be refused")', "=t"), null);
  assert.strictEqual(vm.run('assert(host.exists("../") == false)', "=t"), null);
  assert.strictEqual(vm.run('assert(host.exists("LICENSE") == true)', "=t"), null);
  assert.match(vm.run('error("with a traceback")', "=t"), /with a traceback[\s\S]*stack traceback/);
});

test("lint: clean Lua 5.1 passes, including names that only look like forbidden ones", () => {
  assert.deepStrictEqual(lint('local t = { load = 1, unpack = unpack }\nlocal s = t.load\nprint(s, Noir.load, "a\\n\\065\\\\x", [[\\x]])'), []);
  assert.deepStrictEqual(lint("local load = 1\nprint(load)"), []);
  assert.deepStrictEqual(lint("local table = {}\nprint(table.unpack)"), []);
});

test("lint: the license header must be on line 1", () => {
  assert.match(lintSource("local a = 1\n", "NoirGuides/X.lua")[0].message, /line 1 must start with/);
  assert.match(lintSource(`\n${HEADER}\n`, "NoirGuides/X.lua")[0].message, /line 1 must start with/);
  assert.match(lintSource(`\ufeff${HEADER}\n`, "NoirGuides/X.lua")[0].message, /byte order mark/);
  assert.deepStrictEqual(lintSource(`${HEADER} Generated. Do not edit.\r\nlocal a = 1\r\n`, "NoirGuides/X.lua"), []);
});

test("lint: syntax newer than Lua 5.1 is rejected", () => {
  for (const body of ["goto done\n::done::", "local a = 7 // 2", "local a = 7 & 2", "local a = 1 << 2", "local a = ~5", "local a <const> = 1"]) {
    const messages = lint(body);
    assert.strictEqual(messages.length, 1, body);
    assert.match(messages[0], /not valid Lua 5\.1/, body);
  }
});

test("lint: string escapes newer than Lua 5.1 are rejected", () => {
  assert.match(lint('local a = "\\x41"')[0], /escape \\x/);
  assert.match(lint('local a = "\\u{48}"')[0], /escape \\u/);
  assert.match(lint("local a = '\\z  b'")[0], /escape \\z/);
});

test("lint: library functions Lua 5.1 does not have are rejected", () => {
  assert.match(lint("local a = table.unpack({})")[0], /table\.unpack does not exist in Lua 5\.1/);
  assert.match(lint("local a = table.pack(1)")[0], /table\.pack/);
  assert.match(lint("local a = math.tointeger(1)")[0], /math\.tointeger/);
  assert.match(lint("local a = math.type(1)")[0], /math\.type/);
  assert.match(lint('local a = ("x"):pack(1)')[0], /Lua 5\.3 string method/);
  assert.match(lint("local a = utf8.char(1)")[0], /utf8 must not be used/);
  assert.match(lint('local f = load("x")')[0], /load must not be used/);
  assert.match(lint("setfenv(1, {})")[0], /setfenv must not be used/);
});

test("lint: the project's forbidden calls are rejected", () => {
  assert.match(lint('EditMacro(1, "x")')[0], /never writes macros/);
  assert.match(lint('CreateMacro("x")')[0], /never writes macros/);
  assert.match(lint("local a = CombatLogGetCurrentEventInfo()")[0], /never reads the combat log/);
  assert.match(lint('f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")')[0], /combat log events must not be named/);
  assert.deepStrictEqual(lint('local refused = { "COMBAT_LOG_EVENT_UNFILTERED" }', "NoirGuides/Core.lua"), []);
});

test("lint refuses SetBinding and writing StaticPopupDialogs", () => {
  for (const call of ["SetBinding", "SetBindingClick", "SetBindingMacro", "SetOverrideBinding", "SetOverrideBindingClick",
    "SetOverrideBindingSpell", "SetOverrideBindingItem", "SetOverrideBindingMacro"]) {
    assert.match(lint(`${call}("CTRL-1", "x")`)[0] || "", /key bindings come only from Bindings.xml/, call);
  }
  assert.match(lint('StaticPopupDialogs.NOIR = { text = "x" }')[0] || "", /StaticPopupDialogs/);
  assert.match(lint('StaticPopupDialogs["NOIR"] = {}')[0] || "", /StaticPopupDialogs/);
  assert.match(lint('StaticPopupDialogs.CONFIRM_BINDER.text = "x"')[0] || "", /StaticPopupDialogs/);
  assert.match(lint("StaticPopup1:Hide()")[0] || "", /StaticPopup1/);
  assert.match(lint('StaticPopup3.text:SetText("x")')[0] || "", /StaticPopup3/);
  assert.match(lint("StaticPopup2.which = nil")[0] || "", /StaticPopup2/);
  assert.match(lint("local shown = StaticPopup4:IsShown()")[0] || "", /StaticPopup4/, "any method call on them");
  // Reading fields, and the client's own helper functions, are allowed.
  assert.deepStrictEqual(lint('local d = StaticPopupDialogs.CONFIRM_BINDER\nlocal w = StaticPopup1.which\nStaticPopup_Hide("CONFIRM_BINDER")'), []);
  assert.deepStrictEqual(lint("local SetBinding = 1\nlocal b = SetBinding"), []);
});

test("lint: every Lua file of the addon is clean", () => {
  const { files, problems } = lintAddon(ROOT);
  assert.ok(files.includes("NoirGuides/Core.lua"));
  assert.ok(files.length >= 3);
  assert.deepStrictEqual(problems, []);
});

test("every harness and Lua test file starts with the license header", () => {
  const dirs = ["tools/harness", "tools/harness/selftest", "tools/test-lua", "tools/test-lua/sample"];
  for (const dir of dirs) {
    for (const name of fs.readdirSync(path.join(ROOT, dir))) {
      const marker = name.endsWith(".lua") ? HEADER : name.endsWith(".js") ? HEADER.replace("--", "//") : null;
      if (!marker) continue;
      const first = fs.readFileSync(path.join(ROOT, dir, name), "utf8").split("\n", 1)[0];
      assert.ok(first.startsWith(marker), `${dir}/${name}`);
    }
  }
});
