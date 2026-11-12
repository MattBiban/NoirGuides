// Noir Guides, GPLv3. See LICENSE.
// The release helpers: the changelog entry used as release notes, and the CurseForge upload's checks.
const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");
const { notes } = require("../release_notes");
const { metadata, parseIds } = require("../cf_upload");

const LOG = "# Changelog\n\n## 0.2.2\n\n- New thing.\n- Other thing.\n\n## 0.2.1\n\n- Older.\n";

test("the release notes are the version's changelog entry, without the heading or the next entry", () => {
  assert.strictEqual(notes(LOG, "0.2.2"), "- New thing.\n- Other thing.");
  assert.strictEqual(notes(LOG, "0.2.1"), "- Older.");
});

test("a version without a changelog entry is refused", () => {
  assert.throws(() => notes(LOG, "9.9.9"), /no "## 9.9.9" entry/);
});

test("the shipped changelog has an entry for the toc's version", () => {
  const root = path.join(__dirname, "..", "..");
  const toc = fs.readFileSync(path.join(root, "NoirGuides", "NoirGuides.toc"), "utf8");
  const version = /^## Version:\s*(\S+)/m.exec(toc)[1];
  assert.ok(notes(fs.readFileSync(path.join(root, "CHANGELOG.md"), "utf8"), version).length > 0);
});

test("the CurseForge metadata names the version, the changelog, the game versions and the release type", () => {
  assert.deepStrictEqual(metadata("0.2.2", "- New.", [1234], "beta"), {
    changelog: "- New.", changelogType: "markdown", displayName: "Noir Guides 0.2.2", gameVersions: [1234], releaseType: "beta",
  });
});

test("an upload without a game version or with an unknown release type is refused", () => {
  assert.throws(() => metadata("0.2.2", "x", [], "beta"), /CF_GAME_VERSIONS is empty/);
  assert.throws(() => metadata("0.2.2", "x", [1], "final"), /alpha, beta or release/);
});

test("game version IDs are read from a comma-separated list and must be whole numbers", () => {
  assert.deepStrictEqual(parseIds(" 1234, 5678 "), [1234, 5678]);
  assert.deepStrictEqual(parseIds(""), []);
  assert.throws(() => parseIds("12a"), /not a game version ID/);
});
