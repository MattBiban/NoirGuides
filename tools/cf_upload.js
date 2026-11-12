// Noir Guides, GPLv3. See LICENSE.
// Uploads a release zip to the project on CurseForge (the WoW upload API). Run by .github/workflows/release.yml;
// the one-time setup is in docs/RELEASING.md.
//
//   CF_API_KEY        an API token from CurseForge (a GitHub secret; never written to a file)
//   CF_PROJECT_ID     the project's ID on CurseForge
//   CF_GAME_VERSIONS  comma-separated game version IDs (node tools/cf_versions.js lists them)
//   CF_RELEASE_TYPE   alpha, beta or release (default beta)
//
//   node tools/cf_upload.js <zip> <version>
const fs = require("node:fs");
const path = require("node:path");
const { notes } = require("./release_notes");

const API = "https://wow.curseforge.com/api";

function metadata(version, changelog, gameVersions, releaseType) {
  if (!gameVersions.length) throw new Error("CF_GAME_VERSIONS is empty: set it to the game version ID(s) to upload for");
  if (!["alpha", "beta", "release"].includes(releaseType)) {
    throw new Error(`CF_RELEASE_TYPE must be alpha, beta or release, not ${releaseType}`);
  }
  return { changelog, changelogType: "markdown", displayName: `Noir Guides ${version}`, gameVersions, releaseType };
}

function parseIds(text) {
  return String(text || "").split(",").map((s) => s.trim()).filter(Boolean).map((s) => {
    const n = Number(s);
    if (!Number.isInteger(n) || n <= 0) throw new Error(`not a game version ID: ${s}`);
    return n;
  });
}

async function upload({ zip, version, token, projectId, gameVersions, releaseType, changelog }) {
  const form = new FormData();
  form.append("metadata", JSON.stringify(metadata(version, changelog, gameVersions, releaseType)));
  form.append("file", new Blob([fs.readFileSync(zip)], { type: "application/zip" }), path.basename(zip));
  const res = await fetch(`${API}/projects/${projectId}/upload-file`, {
    method: "POST", headers: { "X-Api-Token": token }, body: form,
  });
  const body = await res.text();
  if (!res.ok) throw new Error(`CurseForge refused the upload (${res.status}): ${body}`);
  return JSON.parse(body);
}

if (require.main === module) {
  const [zip, version] = process.argv.slice(2);
  const token = process.env.CF_API_KEY;
  const projectId = process.env.CF_PROJECT_ID;
  if (!zip || !version) throw new Error("usage: node tools/cf_upload.js <zip> <version>");
  if (!token || !projectId) {
    console.log("CF_API_KEY or CF_PROJECT_ID is not set: skipping the CurseForge upload (docs/RELEASING.md).");
    process.exit(0);
  }
  const changelog = notes(fs.readFileSync(path.join(__dirname, "..", "CHANGELOG.md"), "utf8"), version);
  upload({
    zip, version, token, projectId, gameVersions: parseIds(process.env.CF_GAME_VERSIONS),
    releaseType: process.env.CF_RELEASE_TYPE || "beta", changelog,
  })
    .then((r) => console.log(`Uploaded to CurseForge: file ${r.id}`))
    .catch((e) => { console.error(e.message); process.exit(1); });
}
module.exports = { metadata, parseIds };
