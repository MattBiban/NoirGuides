// Noir Guides, GPLv3. See LICENSE.
// Downloads the data the route planner is built from into tools/data/ (not committed):
//   QuestieDB (Forever and Vanilla flavors) -> forever_db.json, vanilla_db.json
//   client tables from wago.tools           -> wago/<Table>.csv
// usage: node fetch_data.js [--refresh]
// Needs 7-Zip (7z on PATH or C:\Program Files\7-Zip\7z.exe) or the Windows tar.exe to unpack the QuestieDB zips.
const fs = require("fs");
const path = require("path");
const { execFileSync, spawnSync } = require("child_process");

const SOURCES = JSON.parse(fs.readFileSync(path.join(__dirname, "data_sources.json"), "utf8"));
const DATA = path.join(__dirname, "data");
const WAGO = path.join(DATA, "wago");
// AreaTrigger, Map and TransportAnimation are evidence for the hand-written transport links (lib/travel.js checks them)
const WAGO_TABLES = ["AreaTable", "AreaTrigger", "CharBaseInfo", "ChrClasses", "ChrRaces", "Map", "QuestSort", "SkillLine", "SpellName", "Talent", "TalentTab",
  "TaxiNodes", "TaxiPath", "TaxiPathNode", "TransportAnimation",
  "UiMap", "UiMapAssignment"];
const refresh = process.argv.includes("--refresh");

class DownloadError extends Error {
  constructor(url, why) { super(`${why}: ${url}`); this.url = url; this.notFound = why === "HTTP 404"; }
}
async function fetchBytes(url) {
  let res;
  try { res = await fetch(url, { redirect: "follow", headers: { "User-Agent": "noir-guides-tools" } }); }
  catch (e) { throw new DownloadError(url, (e.cause && e.cause.code) || e.message); }
  if (!res.ok) throw new DownloadError(url, `HTTP ${res.status}`);
  return Buffer.from(await res.arrayBuffer());
}
async function download(url, file) {
  fs.writeFileSync(file, await fetchBytes(url));
}
function unzip(zip, dir) {
  fs.mkdirSync(dir, { recursive: true });
  for (const exe of ["7z", "C:\\Program Files\\7-Zip\\7z.exe"]) {
    if (spawnSync(exe, ["x", "-y", `-o${dir}`, zip], { stdio: "ignore" }).status === 0) return;
  }
  const tar = path.join(process.env.SystemRoot || "C:\\Windows", "System32", "tar.exe");
  if (spawnSync(tar, ["-xf", zip, "-C", dir], { stdio: "ignore" }).status === 0) return;
  throw new Error(`cannot unpack ${zip}: install 7-Zip`);
}

async function fetchQuestieDb() {
  const version = SOURCES.questiedb.release;
  for (const flavor of ["Forever", "Vanilla"]) {
    const dir = path.join(DATA, `QuestieDB-${flavor}`);
    const zip = path.join(DATA, `QuestieDB-${flavor}.zip`);
    if (refresh || !fs.existsSync(zip)) {
      console.log(`downloading QuestieDB ${version} ${flavor}`);
      // v1.0.11 added the version to the asset name (QuestieDB-1.0.11-Forever.zip); older releases have none
      const base = `https://github.com/Questie/QuestieDB/releases/download/${version}`;
      await download(`${base}/QuestieDB-${version.replace(/^v/, "")}-${flavor}.zip`, zip).catch((e) => {
        if (!e.notFound) throw e;
        return download(`${base}/QuestieDB-${flavor}.zip`, zip);
      });
    }
    if (refresh || !fs.existsSync(dir)) {
      fs.rmSync(dir, { recursive: true, force: true });
      unzip(zip, dir);
    }
    const json = path.join(DATA, `${flavor.toLowerCase()}_db.json`);
    if (refresh || !fs.existsSync(json)) {
      const toc = path.join(dir, "QuestieDB", `QuestieDB_${flavor}.toc`);
      execFileSync(process.execPath, [path.join(__dirname, "questiedb_export.js"), toc, json], { stdio: "inherit" });
    }
  }
}

async function fetchWago() {
  const build = SOURCES.wago.build;
  fs.mkdirSync(WAGO, { recursive: true });
  for (const table of WAGO_TABLES) {
    const file = path.join(WAGO, `${table}.csv`);
    if (!refresh && fs.existsSync(file)) continue;
    const url = `https://wago.tools/db2/${table}/csv?build=${build}&locale=enUS`;
    console.log(`downloading ${table} ${build}`);
    let body;
    for (let attempt = 1; !body; attempt++) {
      try { body = await fetchBytes(url); } catch (e) {
        if (attempt === 3 || e.notFound) throw e;
        await new Promise((r) => setTimeout(r, 3000 * attempt));
      }
    }
    // wago answers a table it does not have with a JSON error body, not a CSV
    if (body.subarray(0, 9).toString("utf8") === '{"errors"') throw new DownloadError(url, "not a table");
    fs.writeFileSync(file, body);
  }
}

(async () => {
  fs.mkdirSync(DATA, { recursive: true });
  await fetchQuestieDb();
  await fetchWago();
  console.log(`data is ready in ${DATA}`);
})().catch((e) => {
  console.error(e.url ? `download failed: ${e.message}` : e.message);
  process.exit(1);
});
