// Noir Guides, GPLv3. See LICENSE.
// Prints the CHANGELOG.md entry of one version (the text under "## <version>" up to the next "## "), for the release
// notes and the CurseForge changelog:   node tools/release_notes.js 0.2.1
const fs = require("node:fs");
const path = require("node:path");

function notes(changelog, version) {
  const lines = changelog.split(/\r?\n/);
  const start = lines.findIndex((l) => l.trim() === `## ${version}`);
  if (start < 0) throw new Error(`CHANGELOG.md has no "## ${version}" entry`);
  const out = [];
  for (let i = start + 1; i < lines.length && !/^## /.test(lines[i]); i++) out.push(lines[i]);
  return out.join("\n").trim();
}

if (require.main === module) {
  const version = process.argv[2];
  if (!version) throw new Error("usage: node tools/release_notes.js <version>");
  process.stdout.write(notes(fs.readFileSync(path.join(__dirname, "..", "CHANGELOG.md"), "utf8"), version) + "\n");
}
module.exports = { notes };
