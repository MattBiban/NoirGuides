// Noir Guides, GPLv3. See LICENSE.
// The clean room (rebuild plan, task X2): nothing that ships or builds the addon points at the old fork's folder or
// reads a file outside this repository, and every addon source carries the license line on its first line.
// tools/data/ (fetched QuestieDB and client tables) and node_modules/ are not ours and are left out.
const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.join(__dirname, "..", "..");
const SKIP = new Set(["data", "node_modules", ".git"]);
// Split so that this file does not name the folder itself.
const FORK_FOLDER = ["Forever", "Leveling", "Guide"].join("-");
const LICENSE_LUA = "-- Noir Guides, GPLv3. See LICENSE.";
const LICENSE_XML = "<!-- Noir Guides, GPLv3. See LICENSE. -->";

function filesUnder(dir) {
  if (!fs.existsSync(dir)) return [];
  const out = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (SKIP.has(e.name)) continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...filesUnder(p));
    else out.push(p);
  }
  return out.sort();
}

const rel = (f) => path.relative(ROOT, f).split(path.sep).join("/");
const firstLine = (f) => fs.readFileSync(f, "utf8").replace(/^\uFEFF/, "").split(/\r?\n/)[0];

// Absolute paths written as string literals: a drive letter ("C:\\...", "C:/..."), or a POSIX form of a Windows or
// home folder ("/c/...", "/Users/...", "/home/..."). The only ones a tool may name are the system programs it runs
// to unpack downloads (7-Zip, the Windows tar.exe); those are programs, not files the tools read.
const ABSOLUTE = /["'`]((?:[A-Za-z]:(?:\\\\|\/)|\/[a-z]\/|\/Users\/|\/home\/)[^"'`]*)["'`]/g;
const SYSTEM_PROGRAMS = [/^C:\\\\Windows$/, /^C:\\\\Program Files\\\\7-Zip\\\\7z\.exe$/];

function absolutePaths(text) {
  return [...text.matchAll(ABSOLUTE)].map((m) => m[1]).filter((p) => !SYSTEM_PROGRAMS.some((re) => re.test(p)));
}

test("no file under NoirGuides/ or tools/ (outside tools/data/) names the old fork's folder", () => {
  const files = [...filesUnder(path.join(ROOT, "NoirGuides")), ...filesUnder(path.join(ROOT, "tools"))];
  assert.ok(files.length > 100, `${files.length} files scanned`);
  const hits = files.filter((f) => fs.readFileSync(f, "latin1").includes(FORK_FOLDER));
  assert.deepStrictEqual(hits.map(rel), []);
});

test("no tool reads a path outside the repository", () => {
  // This file holds sample paths for the check below, so it is the one file left out.
  const files = filesUnder(path.join(ROOT, "tools")).filter((f) => /\.(js|lua|json)$/.test(f) && f !== __filename);
  assert.ok(files.some((f) => rel(f) === "tools/build_routes.js"), "the tools are scanned");
  const hits = [];
  for (const f of files) {
    for (const p of absolutePaths(fs.readFileSync(f, "utf8"))) hits.push(`${rel(f)}: ${p}`);
  }
  assert.deepStrictEqual(hits, []);
});

test("the absolute path check finds drive letters and home folders, and lets the unpack programs through", () => {
  assert.deepStrictEqual(absolutePaths(String.raw`const a = "C:\\Users\\someone\\x"; const b = 'D:/data/y.json';`),
    [String.raw`C:\\Users\\someone\\x`, "D:/data/y.json"]);
  assert.deepStrictEqual(absolutePaths("read(`/c/Users/someone/x`); read('/home/someone/y')"),
    ["/c/Users/someone/x", "/home/someone/y"]);
  assert.deepStrictEqual(absolutePaths(String.raw`["7z", "C:\\Program Files\\7-Zip\\7z.exe"]; env.SystemRoot || "C:\\Windows"`), []);
  assert.deepStrictEqual(absolutePaths(String.raw`/^## Version:\s*(\S+)\s*$/m; path.join(ROOT, "data")`), []);
});

test("every Lua file under NoirGuides/ starts with the license line", () => {
  const lua = filesUnder(path.join(ROOT, "NoirGuides")).filter((f) => f.endsWith(".lua"));
  assert.ok(lua.length >= 30, `${lua.length} Lua files`);
  assert.deepStrictEqual(lua.filter((f) => firstLine(f) !== LICENSE_LUA).map(rel), []);
});

test("Bindings.xml starts with the license comment", () => {
  assert.strictEqual(firstLine(path.join(ROOT, "NoirGuides", "Bindings.xml")), LICENSE_XML);
});
