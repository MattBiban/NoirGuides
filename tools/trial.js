// Noir Guides, GPLv3. See LICENSE.
// A quick look at what a planner change does: one line per race for the shared route, planned and validated but not
// written. Usage: node trial.js [race...]. Shown: end level, errors, steps, zone changes, travel, grind steps, quests
// above and far below the level, walks through zones too dangerous for the level (planner/danger.js), and below
// levels 22, 40 and 61 the quests handed in, zone changes, the fullest log, objectives per trip out (obj/run) and grind
// steps. Only the grind steps the plan needs are counted and shown (planner/measure.js neededGrinds): the last step
// to the cap, which the planned character passes as it comes, is none. A full build (npm run routes) takes minutes;
// this takes seconds.
const path = require("path");
const toolsDir = __dirname;
const { RACES } = require("./lib/characters");
const raceArgs = process.argv.length > 2 ? process.argv.slice(2) : Object.keys(RACES);
const T = (p) => require(path.join(toolsDir, p));
const { loadDb } = T("lib/db"); const { loadTravel } = T("lib/travel"); const { combos } = T("lib/characters");
const { loadInns } = T("planner/context"); const { planRoute } = T("planner/plan"); const { validateRoute } = T("planner/validate");
const { measureRoute, neededGrinds } = T("planner/measure"); const { questXp, XP_TO_LEVEL, grindSeconds } = T("lib/xp"); const { levelGap } = T("planner/levelgap"); const { dangerousWalks } = T("planner/danger");
const DATA = path.join(toolsDir, "data");
const db = loadDb(DATA), graph = loadTravel(db, DATA), inns = loadInns(db, DATA), all = combos(DATA);
const total = (lv) => XP_TO_LEVEL.slice(1, lv).reduce((a, b) => a + b, 0);
for (const race of raceArgs) {
  const t0 = Date.now();
  const ch = all.find((c) => c.race === race);
  const route = planRoute(db, ch, { graph, inns });
  const v = validateRoute(db, route, ch, { graph, inns });
  const m = measureRoute(db, graph, route, ch, v.levels);
  const needed = new Set(neededGrinds(route, v.levels));
  const at = (cap) => {
    let quests = 0, qxp = 0, zc = 0, last, maxLog = 0, objRuns = 0, obj = 0, run = null, grinds = 0; const log = new Set();
    route.steps.forEach((s, k) => {
      if (v.levels[k] >= cap) return;
      if (needed.has(k)) grinds++;
      if (s.action === "accept") { log.add(s.quest); maxLog = Math.max(maxLog, log.size); }
      if (s.action === "turnin") { log.delete(s.quest); quests++; qxp += questXp(db.quests.get(s.quest).level, Math.floor(v.levels[k])); }
      const kind = s.action === "objective" ? "obj" : s.action === "accept" || s.action === "turnin" ? "hub" : null;
      if (!kind) return;
      const z = s.at ? s.at.zone : s.zone; if (z !== undefined) { if (last !== undefined && z !== last) zc++; last = z; }
      if (kind !== run) { run = kind; if (kind === "obj") objRuns++; }
      if (kind === "obj") obj++;
    });
    return `<${cap}: ${quests} quests (${Math.round(100 * qxp / total(cap))}% of XP), ${zc} zone changes, max log ${maxLog}, ${(obj / objRuns).toFixed(1)} obj/run, ${grinds} grinds`;
  };
  const g = levelGap(db, route, v.levels);
  console.log(`${race}: end ${v.endLevel}, errors ${v.errors.length}, steps ${route.steps.length}, zone changes ${m.zoneChanges}, travel ${(m.seconds / 3600).toFixed(1)} h, grinds ${needed.size} [${route.steps.map((s, k) => (needed.has(k) ? `${v.levels[k]}:${Math.round(100 * (1 - v.xps[k] / XP_TO_LEVEL[v.levels[k]]))}%` : null)).filter(Boolean).join(" ")}] = ${route.steps.reduce((a, s, k) => a + (needed.has(k) ? grindSeconds(v.levels[k], v.xps[k]) / 3600 : 0), 0).toFixed(1)} h, above ${g.above.length}, below ${g.below.length}/${g.steps}, dangerous walks ${dangerousWalks(db, graph, route, ch, v.levels).length} | ${at(22)} | ${at(40)} | ${at(61)} | ${Math.round((Date.now() - t0) / 1000)} s`);
}
