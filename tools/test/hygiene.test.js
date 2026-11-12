// Noir Guides, GPLv3. See LICENSE.
// House rules for the files in the repository: the license line comes first, and text files use LF line endings.
const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.join(__dirname, "..", "..");
const SKIP = new Set(["data", "node_modules", ".git", "dist"]);
const HEADER = { ".js": "// Noir Guides, GPLv3. See LICENSE.", ".lua": "-- Noir Guides, GPLv3. See LICENSE." };

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
const relative = (files) => files.map((f) => path.relative(ROOT, f).split(path.sep).join("/"));

test("every JavaScript file in tools/ starts with the license line", () => {
  const files = filesUnder(path.join(ROOT, "tools")).filter((f) => path.extname(f) === ".js");
  assert.ok(files.some((f) => path.basename(f) === "hygiene.test.js"));
  const missing = files.filter((f) => fs.readFileSync(f, "utf8").split(/\r?\n/, 1)[0] !== HEADER[".js"]);
  assert.deepStrictEqual(relative(missing), []);
});

test(".gitattributes forces LF for Lua, JavaScript and Markdown", () => {
  const lines = fs.readFileSync(path.join(ROOT, ".gitattributes"), "utf8").split("\n").map((l) => l.trim());
  for (const ext of ["lua", "js", "md"]) assert.ok(lines.includes(`*.${ext} text eol=lf`), `*.${ext} text eol=lf`);
});

test("no Lua, JavaScript or Markdown file has CRLF line endings", () => {
  const files = filesUnder(ROOT).filter((f) => [".lua", ".js", ".md"].includes(path.extname(f)));
  assert.ok(files.length > 0);
  const crlf = files.filter((f) => fs.readFileSync(f, "latin1").includes("\r\n"));
  assert.deepStrictEqual(relative(crlf), []);
});
