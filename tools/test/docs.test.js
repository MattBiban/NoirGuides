// Noir Guides, GPLv3. See LICENSE.
// The release documents (tasks X3 and, for 0.2.0, rebuild X2) stay in step with the code: the independence review has a result for every file
// that ships, the in-game checklist carries every assumption the engine notes mark unverified and every transport the
// planner could not verify, and the changelog and README name the version the toc ships.
const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");
const { tocVersion } = require("../package_addon");

const ROOT = path.join(__dirname, "..", "..");
const read = (...p) => fs.readFileSync(path.join(ROOT, ...p), "utf8");

function walk(dir) {
  const out = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...walk(p));
    else out.push(p);
  }
  return out;
}

// The rows of the review's per-file table: "| `NoirGuides/Core.lua` | result | ... |"
function reviewRows() {
  const text = read("docs", "INDEPENDENCE-REVIEW.md");
  const start = text.indexOf("## 0.2.0: every shipped file");
  assert.ok(start >= 0, 'the review has the section "## 0.2.0: every shipped file"');
  const rows = new Map();
  for (const line of text.slice(start).split("\n")) {
    const m = /^\| `(NoirGuides\/[^`]+)` \| ([^|]+) \|/.exec(line);
    if (m) rows.set(m[1], m[2].trim());
  }
  return rows;
}

test("the independence review records a result for every shipped file", () => {
  const shipped = walk(path.join(ROOT, "NoirGuides")).map((f) => path.relative(ROOT, f).split(path.sep).join("/")).sort();
  const rows = reviewRows();
  assert.deepStrictEqual(shipped.filter((f) => !rows.has(f)), []);
  assert.deepStrictEqual([...rows.keys()].filter((f) => !shipped.includes(f)), [], "no row for a file that does not exist");
});

test("every review result is one of the defined verdicts", () => {
  const allowed = new Set(["Clean", "Rewritten"]);
  const odd = [...reviewRows()].filter(([, v]) => !allowed.has(v.replace(/\*/g, "")));
  assert.deepStrictEqual(odd, []);
});

test("the checklist carries every numbered assumption of the engine notes", () => {
  const notes = read("docs", "ENGINE-NOTES.md");
  const numbers = [...notes.matchAll(/^\| (\d+) \| /gm)].map((m) => Number(m[1]));
  assert.ok(numbers.length >= 50, `${numbers.length} assumptions`);
  const checklist = read("docs", "INGAME-CHECKLIST.md");
  const missing = numbers.filter((n) => !new RegExp(`[(\\s]#${n}[,)]`).test(checklist));
  assert.deepStrictEqual(missing, [], "each assumption is cited as (#N) or in a list such as (#16, #17)");
});

test("the checklist names every transport link the planner could not verify", () => {
  const { links } = JSON.parse(read("tools", "planner", "transports.json"));
  const unverified = links.filter((l) => !l.verified).map((l) => l.id);
  assert.ok(unverified.length > 0);
  const checklist = read("docs", "INGAME-CHECKLIST.md");
  assert.deepStrictEqual(unverified.filter((id) => !checklist.includes("`" + id + "`")), []);
});

test("the checklist covers the Skyborne start, the passes and the owner's open points in the route notes", () => {
  const checklist = read("docs", "INGAME-CHECKLIST.md");
  for (const s of ["Zephras Isle", "16593", "HighOrder", "Windshaper", "pass", "A Rogue's Deal", "92514", "92595", "92460",
    "Deeprun Tram", "Mount Hyjal", "Forever-only", "4964", "1641"]) {
    assert.ok(checklist.includes(s), `checklist mentions ${s}`);
  }
});

test("the changelog's newest entry is the toc's version", () => {
  const version = tocVersion(read("NoirGuides", "NoirGuides.toc"));
  const first = /^## (\S+)/m.exec(read("CHANGELOG.md"));
  assert.ok(first, "the changelog has an entry");
  assert.strictEqual(first[1], version);
});

test("the README says how to build, test, package and install", () => {
  const readme = read("README.md");
  for (const s of ["npm run fetch", "npm test", "npm run test:lua", "npm run sim", "npm run package", "Interface", "AddOns",
    "docs/INGAME-CHECKLIST.md", "docs/INDEPENDENCE-REVIEW.md"]) {
    assert.ok(readme.includes(s), `README mentions ${s}`);
  }
});

test("the README tells a player what the first login shows and that no command is needed (0.2.0)", () => {
  const readme = read("README.md");
  for (const s of ["first login", "guide window", "arrow", "minimap button", "setup wizard", "No command is needed",
    "Options", "AddOns", "Noir Guides"]) {
    assert.ok(readme.includes(s), `README mentions ${s}`);
  }
});

test("the 0.2.0 changelog entry names what the rebuild brings", () => {
  const log = read("CHANGELOG.md");
  const start = log.indexOf("## 0.2.0");
  assert.ok(start >= 0, "the changelog has a 0.2.0 entry");
  const next = log.indexOf("\n## ", start + 1);
  const entry = log.slice(start, next < 0 ? undefined : next).toLowerCase();
  for (const s of ["sections", "bundled steps", "card stack", "step list", "settings panel", "minimap button",
    "menus at the cursor", "pins", "arrow", "joiners", "item buttons", "target buttons"]) {
    assert.ok(entry.includes(s), `0.2.0 entry mentions ${s}`);
  }
});
