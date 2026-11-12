// Noir Guides, GPLv3. See LICENSE.
// The project must contain nothing derived from the other guide addon. This looks for its name and its three-letter
// prefix in everything we write or generate. tools/data/ is left out: it is fetched QuestieDB data, not ours, and its
// base64 lines contain those three letters by chance.
const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");

const FORBIDDEN = new RegExp(["r" + "xp", "rested" + "xp"].join("|"), "i"); // split so this file does not match itself
const SKIP = new Set(["data", "node_modules", ".git"]);

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

test("nothing in tools/ or NoirGuides/ names the other guide addon", () => {
  const root = path.join(__dirname, "..", "..");
  const files = [...filesUnder(path.join(root, "tools")), ...filesUnder(path.join(root, "NoirGuides"))];
  assert.ok(files.length > 0);
  const hits = files.filter((f) => FORBIDDEN.test(path.basename(f)) || FORBIDDEN.test(fs.readFileSync(f, "latin1")));
  assert.deepStrictEqual(hits.map((f) => path.relative(root, f)), []);
});
