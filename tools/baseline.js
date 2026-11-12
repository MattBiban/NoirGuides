// Noir Guides, GPLv3. See LICENSE.
// CLI: measures the routes of the baseline commit and writes planner/baseline.json, which the route report compares
// today's routes against. node baseline.js [commit]
// The route files and the report are read from git, never from the working tree. The numbers of the old planner's own
// report (steps, quests, end level, grind steps, straight-line distance) are taken as it wrote them; zone changes,
// travel time and walked yards are measured with planner/measure.js, the same code that measures today's routes.
const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");
const { loadDb } = require("./lib/db");
const { loadTravel } = require("./lib/travel");
const { combos, RACES } = require("./lib/characters");
const { validateRoute } = require("./planner/validate");
const { measureRoute } = require("./planner/measure");

const COMMIT = "37a4f8c";
const DATA = path.join(__dirname, "data");
const OUT = path.join(__dirname, "planner", "baseline.json");
const REPO = path.join(__dirname, "..");

// A route file as the old emitter wrote it: one step per line, plain keys, `at` the only table.
function parseRoute(lua) {
  const head = /Noir\.Route\("([^"]+)"/.exec(lua), who = /race = "(\w+)", faction = "(\w+)"/.exec(lua);
  if (!head || !who) throw new Error("not a route file");
  const steps = [];
  for (const line of lua.split("\n")) {
    if (!/^\s*\{ action = /.test(line)) continue;
    const step = {};
    const at = /at = \{ zone = (\d+), x = ([\d.]+), y = ([\d.]+) \}/.exec(line);
    if (at) step.at = { zone: +at[1], x: +at[2], y: +at[3] };
    for (const [, key, value] of line.replace(/at = \{[^}]*\},?/, "").matchAll(/(\w+) = ("[^"]*"|[\d.]+)/g)) step[key] = value[0] === '"' ? value.slice(1, -1) : +value;
    steps.push(step);
  }
  return { id: head[1], race: who[1], faction: who[2], steps };
}
// The old report's table for each race: "| Steps | 2,154 |" and so on.
function parseReport(markdown) {
  const out = {};
  let race = null;
  const number = (s) => +s.replace(/,/g, "");
  for (const line of markdown.split("\n")) {
    const head = /^## (\w+) \(/.exec(line);
    if (head) { race = head[1]; out[race] = {}; continue; }
    const row = /^\| ([^|]+) \| ([^|]*) \|$/.exec(line);
    if (!race || !row) continue;
    if (row[1] === "Steps") out[race].steps = number(row[2]);
    if (row[1] === "Quests") out[race].quests = number(row[2]);
    if (row[1] === "End level") out[race].endLevel = number(row[2]);
    if (row[1] === "Travel distance") out[race].straightYards = number(row[2].replace(" yards", ""));
    if (row[1] === "Grind steps") out[race].grindSteps = number(/^\d+/.exec(row[2])[0]);
  }
  return out;
}

function main(commit) {
  const show = (file) => execFileSync("git", ["show", `${commit}:${file}`], { cwd: REPO, encoding: "utf8", maxBuffer: 1 << 28 });
  const db = loadDb(DATA);
  const graph = loadTravel(db, DATA);
  const all = combos(DATA);
  const reported = parseReport(show("docs/routes/REPORT.md"));
  const races = {};
  for (const race of Object.keys(RACES)) {
    const ch = all.find((c) => c.race === race);
    const route = parseRoute(show(`NoirGuides/Routes/${ch.faction.toLowerCase()}-${race.toLowerCase()}.lua`));
    const replay = validateRoute(db, route, ch, { graph });
    const m = measureRoute(db, graph, route, ch, replay.levels);
    if (m.steps !== reported[race].steps) throw new Error(`${race}: the route file has ${m.steps} steps, the report of ${commit} says ${reported[race].steps}`);
    races[race] = { ...reported[race], zoneChanges: m.zoneChanges, travelSeconds: m.seconds, walkedYards: m.yards, unreachable: m.unreachable };
    console.log(`${race}: ${m.steps} steps, ${m.zoneChanges} zone changes, ${m.seconds} s of travel, ${m.unreachable} places with no way to them`);
  }
  const about = [
    `The routes of commit ${commit}, the last ones of the first planner, measured by tools/baseline.js. Generated; do not edit.`,
    "steps, quests, endLevel, grindSteps, straightYards: as that commit's docs/routes/REPORT.md gives them (the distance is straight lines between steps).",
    "zoneChanges, travelSeconds, walkedYards, unreachable: measured by planner/measure.js from that commit's route files. The old format has no travel legs, so each",
    "route is given the fastest way lib/travel.js finds between two places in a row, with every transport open to it and today's XP estimates for its level.",
    "That flatters the old routes: a comparison against these numbers errs against the new planner.",
  ];
  fs.writeFileSync(OUT, JSON.stringify({ about, commit, races }, null, 2) + "\n");
  return 0;
}

if (require.main === module) process.exitCode = main(process.argv[2] || COMMIT);
module.exports = { parseRoute, parseReport };
