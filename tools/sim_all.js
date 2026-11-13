// Noir Guides, GPLv3. See LICENSE.
// CLI: npm run sim [-- --race Undead] [--class ROGUE] [--join 25] [--joiners all|only|none] [--api modern]
// The real engine plays every route: the whole addon as the toc loads it (with the shipped format 3 routes and data)
// runs in the mock client, in a world built here from the quest data and the character's flattened steps, and
// tools/harness/sim.lua's scripted player does what the cards on screen say. By default 56 fresh characters (level
// 1, nothing done), the PROFESSION_CHARACTERS (fresh, one per faction, each with a primary profession learned, so the
// profession trainer steps and their "raise the skill" reminders are played) and 50 joiners (each race at each of
// JOIN_LEVELS, its classes in turn) play; --joiners all plays every class at every join level. A run passes when nothing is stuck, no step shown is impossible, every skip has
// the game's evidence, no Lua error or forbidden call happens, no command is typed, no frame is off the screen at
// the end, the character ends at level 60, and a joiner is placed inside its window (see Sim.play).
// Writes docs/routes/SIM.md (full runs only) and tools/data/sim_status.json. Exits 1 when any run fails.
const fs = require("fs");
const os = require("os");
const path = require("path");
const luaparse = require("luaparse");
const { createVm, ROOT } = require("./harness/vm");
const { combos, eligible } = require("./lib/characters");
const { PACE, XP_TO_LEVEL, zoneLevels } = require("./lib/xp");
const { flatten } = require("./planner/bundle");
const { chainOf, applies } = require("./planner/validate3");
const { primaryProfessions } = require("./planner/professions");

const DATA = path.join(__dirname, "data");
const ROUTES = path.join(ROOT, "NoirGuides", "Routes");
const REPORT = path.join(ROOT, "docs", "routes", "SIM.md");
const STATUS = path.join(DATA, "sim_status.json");
// The real client's continent maps; Zephras Isle's is not in the fetched tables, so it gets a made-up ID.
const CONTINENT_MAPS = { 0: 1415, 1: 1414 };
const continentMap = (id) => CONTINENT_MAPS[id] || 100000 + id;
const round2 = (n) => Math.round(n * 100) / 100;
// One fresh character per faction with a primary profession whose Journeyman, Expert and Artisan trainer steps the
// route has (docs/routes/PROFESSION-NOTES.md lists none missing for these).
const PROFESSION_CHARACTERS = [
  { race: "Human", cls: "WARRIOR", professions: [186] }, // Mining
  { race: "Undead", cls: "MAGE", professions: [197] },   // Tailoring
];
const sortNum = (list) => [...new Set(list)].sort((a, b) => a - b);

// ---------------------------------------------------------------------------------------------------------------
// Route files
// ---------------------------------------------------------------------------------------------------------------

// A Lua table constructor, as route files write them, to plain JavaScript.
function luaValue(node) {
  switch (node.type) {
    case "NumericLiteral": return node.value;
    case "BooleanLiteral": return node.value;
    case "NilLiteral": return undefined;
    case "StringLiteral": return node.value !== null ? node.value : JSON.parse(node.raw.replace(/^'|'$/g, '"'));
    case "UnaryExpression":
      if (node.operator === "-") return -luaValue(node.argument);
      break;
    case "TableConstructorExpression": {
      const list = [], map = {};
      let isList = true;
      for (const field of node.fields) {
        if (field.type === "TableValue") list.push(luaValue(field.value));
        else {
          isList = false;
          const key = field.type === "TableKeyString" ? field.key.name : luaValue(field.key);
          map[key] = luaValue(field.value);
        }
      }
      return isList ? list : map;
    }
    default: break;
  }
  throw new Error(`a route file holds a ${node.type}, which is not plain data`);
}

// The text of a route file -> { id, ...data } as the file passes it to Noir.Route.
function parseRoute(text) {
  const ast = luaparse.parse(text, { encodingMode: "x-user-defined" });
  for (const statement of ast.body) {
    const call = statement.expression;
    if (statement.type === "CallStatement" && call.base && call.base.type === "MemberExpression" && call.base.identifier.name === "Route") {
      const [id, data] = call.arguments.map(luaValue);
      return { id, ...data };
    }
  }
  throw new Error("the file calls no Noir.Route");
}

// ---------------------------------------------------------------------------------------------------------------
// The simulated world: what tools/harness/sim.lua documents as `facts`
// ---------------------------------------------------------------------------------------------------------------

// The character's flattened route: its chain of sections from the start section (planner/validate3.js chainOf, with
// the character's professions, ch.professions, none by default), the steps and lines whose `when` holds, flattened to format 2 actions (planner/bundle.js
// flatten), each tagged with its section and step IDs. These are "the indices of the flattened actions" that a
// joiner's placement is measured in (1-based in Lua).
function flattenFor(route3, ch) {
  const out = [];
  const professions = ch.professions || [];
  for (const section of chainOf(route3, ch, professions)) {
    for (const step of section.steps) {
      if (!applies(step.when, ch, professions)) continue;
      const lines = step.lines.filter((l) => applies(l.when, ch, professions)).map((l) => ({ ...l, when: undefined }));
      for (const a of flatten([{ ...step, when: undefined, lines }])) {
        delete a.when;
        out.push({ ...a, section: section.id, step: step.id });
      }
    }
  }
  return out;
}

// options: { withRoute: true } carries the route itself (for a run that registers it instead of the shipped one).
function buildFacts(db, graph, inns, route3, ch, options = {}) {
  const mine = flattenFor(route3, ch);
  const questIds = sortNum(mine.filter((s) => s.quest !== undefined).map((s) => s.quest));
  const quests = {};
  for (const id of questIds) {
    const q = db.quests.get(id);
    if (!q) continue;
    const f = { title: q.name, level: q.level, minLevel: q.minLevel };
    if (q.maxLevel) f.maxLevel = q.maxLevel;
    Object.assign(f, { pre: q.preAll.slice(), preAny: q.preAny.slice(), exclusive: q.exclusive.slice(),
      kills: q.objectives.npcs.length, items: q.objectives.items.length, objects: q.objectives.objects.length,
      credits: (q.killCredit || []).length, event: !!q.trigger });
    if (!eligible(q, ch)) f.closed = `it is not open to ${ch.race} ${ch.cls}`;
    quests[id] = f;
  }

  const npcs = {}, objects = {};
  const entry = (table, source, id) => {
    if (!table[id]) {
      const e = source.get(id);
      table[id] = { name: (e && e.name) || `${source === db.npcs ? "NPC" : "Object"} ${id}`, offers: [], ends: [] };
    }
    return table[id];
  };
  for (const s of mine) {
    if (s.npc) entry(npcs, db.npcs, s.npc);
    if (s.object) entry(objects, db.objects, s.object);
  }
  const taxi = {};
  for (const node of [...graph.nodes.values()].sort((a, b) => a.id - b.id)) {
    if (!node.factions.includes(ch.faction)) continue;
    const master = node.masters[ch.faction];
    taxi[node.id] = { name: node.name, continent: master.point.continent, zone: master.point.zone, x: round2(master.point.x), y: round2(master.point.y), npc: master.npc };
    if (master.npc) entry(npcs, db.npcs, master.npc).taxi = node.id;
  }
  for (const id of questIds) {
    const q = db.quests.get(id);
    if (!q) continue;
    for (const n of q.starts.npcs) if (npcs[n]) npcs[n].offers.push(id);
    for (const n of q.ends.npcs) if (npcs[n]) npcs[n].ends.push(id);
    for (const o of q.starts.objects) if (objects[o]) objects[o].offers.push(id);
    for (const o of q.ends.objects) if (objects[o]) objects[o].ends.push(id);
  }
  for (const inn of inns) {
    if (npcs[inn.npc] && inn.friendly.includes(ch.faction[0])) {
      const area = db.areas.get(inn.point.zone);
      npcs[inn.npc].binder = area ? area.name : `zone ${inn.point.zone}`;
    }
  }

  const zoneIds = new Set();
  for (const s of mine) for (const p of [s.at, typeof s.to === "object" ? s.to : null]) if (p) zoneIds.add(p.zone);
  // Steps without an action of their own (a trainer visit, a profession trainer) still have places the player walks to.
  const professions = ch.professions || [];
  for (const section of chainOf(route3, ch, professions)) {
    for (const step of section.steps) {
      if (!applies(step.when, ch, professions)) continue;
      if (step.at) zoneIds.add(step.at.zone);
      for (const l of step.lines) if (l.at && applies(l.when, ch, professions)) zoneIds.add(l.at.zone);
    }
  }
  for (const t of Object.values(taxi)) zoneIds.add(t.zone);
  const bands = zoneLevels(db);
  const zones = {}, continents = {};
  for (const id of sortNum([...zoneIds])) {
    const map = db.maps.get(id), area = db.areas.get(id);
    if (!map || !area) continue;
    const z = { uiMap: map.uiMap, name: area.name, continent: area.continent, minX: map.minX, maxX: map.maxX, minY: map.minY, maxY: map.maxY };
    const band = bands.get(id);
    if (band) z.band = { min: band.min, max: band.max, wild: band.wild };
    zones[id] = z;
    const c = continents[area.continent] || (continents[area.continent] = { minX: Infinity, maxX: -Infinity, minY: Infinity, maxY: -Infinity });
    c.minX = Math.min(c.minX, map.minX); c.maxX = Math.max(c.maxX, map.maxX);
    c.minY = Math.min(c.minY, map.minY); c.maxY = Math.max(c.maxY, map.maxY);
  }
  for (const [id, c] of Object.entries(continents)) {
    continents[id] = { uiMap: continentMap(+id), name: `continent ${id}`, top: c.maxX, left: c.maxY, width: c.maxY - c.minY, height: c.maxX - c.minX };
  }

  const xpToLevel = {};
  for (let level = 1; level < XP_TO_LEVEL.length; level++) xpToLevel[level] = XP_TO_LEVEL[level];
  const first = route3.sections.length && chainOf(route3, ch).flatMap((s) => s.steps).find((s) => applies(s.when, ch) && s.at && zones[s.at.zone]);
  const facts = {
    race: ch.race, class: ch.cls, start: first ? { ...first.at } : undefined,
    xpToLevel, pace: { OBJECTIVE_KILLS: PACE.OBJECTIVE_KILLS, ITEM_KILL_FACTOR: PACE.ITEM_KILL_FACTOR, INCIDENTAL_YARDS: PACE.INCIDENTAL_YARDS },
    continents, zones, quests, npcs, objects, taxi, flat: mine,
  };
  if (professions.length) {
    facts.professions = professions.slice();
    facts.professionNames = {};
    for (const p of primaryProfessions()) if (professions.includes(p.skill)) facts.professionNames[p.skill] = p.name;
  }
  if (options.withRoute) facts.route = { format: route3.format, race: route3.race, faction: route3.faction, sections: route3.sections };
  return facts;
}

// ---------------------------------------------------------------------------------------------------------------
// Running one character
// ---------------------------------------------------------------------------------------------------------------

const luaString = (s) => `"${String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\r/g, "\\r").replace(/\n/g, "\\n")}"`;
// Plain data to a Lua table constructor. Arrays become lists; object keys that are whole numbers become [n].
function toLua(v) {
  if (v === undefined || v === null) return "nil";
  if (typeof v === "boolean" || typeof v === "number") return String(v);
  if (typeof v === "string") return luaString(v);
  if (Array.isArray(v)) return `{ ${v.map(toLua).join(", ")} }`;
  const parts = [];
  for (const [k, x] of Object.entries(v)) {
    if (x === undefined) continue;
    const key = /^-?\d+$/.test(k) ? `[${k}]` : /^[A-Za-z_]\w*$/.test(k) ? k : `[${luaString(k)}]`;
    parts.push(`${key} = ${toLua(x)}`);
  }
  return `{ ${parts.join(", ")} }`;
}

// Plays one character. options: { api, join (a level: the character joins there, see Sim.prepareJoin), register
// (the facts carry their own route, facts.route: the shipped routes and data are left out) }. Returns the result of
// Sim.play.
function simulate(facts, options = {}) {
  const lines = [];
  const vm = createVm({ print: (l) => lines.push(l) });
  const fail = (what, err) => { throw new Error(`${what}: ${err}`); };
  let err = vm.run("HARNESS = {}", "=sim");
  if (err) fail("setup", err);
  for (const file of ["tools/harness/env.lua", "tools/harness/wow.lua", "tools/harness/sim.lua"]) {
    err = vm.runFile(file);
    if (err) fail(file, err);
  }
  const opts = { api: options.api || "classic" };
  if (options.join) opts.join = options.join;
  if (options.trace) opts.trace = true;
  if (options.maxActions) opts.maxActions = options.maxActions;
  if (options.register) {
    opts.register = true;
    opts.swap = [{ match: "^Data/", with: [] }, { match: "^Routes/", with: [] }];
  }
  const who = `${facts.race} ${facts.class}${options.join ? ` joining at ${options.join}` : ""}`;
  err = vm.run(`SIM_FACTS = ${toLua(facts)}\nHARNESS.Sim.main(SIM_FACTS, ${toLua(opts)})`, `=sim ${who}`);
  if (err) fail(who, err);
  const line = lines.find((l) => l.startsWith("SIMRESULT "));
  if (!line) fail(who, "the simulator printed no result");
  return JSON.parse(line.slice("SIMRESULT ".length));
}

// What fails a run (the same rules as Sim.problems in tools/harness/sim.lua): not played to its end, any stuck
// step, a step the character cannot do, an unexplained skip, a Lua error or forbidden call, a slash command, a frame
// off the screen at the end, an end level below 60, and for a joiner a placement outside its window.
function problems(r) {
  const out = [];
  const n = (list) => (list || []).length;
  if (!r.finished) out.push("not played to its end");
  if (n(r.stuck)) out.push(`${n(r.stuck)} stuck`);
  if (n(r.cannot)) out.push(`${n(r.cannot)} cannot`);
  if (n(r.unexplained)) out.push(`${n(r.unexplained)} unexplained`);
  if (n(r.errors)) out.push(`${n(r.errors)} errors`);
  if (r.slash) out.push(`${r.slash} slash`);
  if (n(r.offScreen)) out.push(`${n(r.offScreen)} off screen`);
  if (!(r.level >= 60)) out.push(`level ${r.level}`);
  if (r.join && !(r.placement && r.placement.inside)) out.push("placed outside its window");
  return out;
}
const passed = (r) => problems(r).length === 0;

// The totals over a list of results.
function summarize(results) {
  const count = (key) => results.reduce((sum, r) => sum + (r[key] || []).length, 0);
  const s = { characters: results.length, at60: results.filter((r) => r.level >= 60).length, stuck: count("stuck"), cannot: count("cannot"),
    unexplained: count("unexplained"), errors: count("errors"), manual: count("manual"), finished: results.filter((r) => r.finished).length,
    slash: results.reduce((sum, r) => sum + (r.slash || 0), 0), offScreen: count("offScreen"),
    joiners: results.filter((r) => r.join).length, inside: results.filter((r) => r.join && r.placement && r.placement.inside).length };
  s.passed = results.filter(passed).length;
  s.ok = s.characters > 0 && s.passed === s.characters;
  return s;
}

// The joiner runs: for each race, each join level k (0-based) with the class classes[k mod #classes] of that race,
// in the order of `characters` (combos() order). all = true: every class of the race at every level.
function joinerList(characters, levels, all = false) {
  const races = [];
  const byRace = new Map();
  for (const ch of characters) {
    if (!byRace.has(ch.race)) { byRace.set(ch.race, []); races.push(ch.race); }
    byRace.get(ch.race).push(ch);
  }
  const out = [];
  for (const race of races) {
    const classes = byRace.get(race);
    if (all) {
      for (const ch of classes) for (const join of levels) out.push({ ...ch, join });
    } else {
      levels.forEach((join, k) => out.push({ ...classes[k % classes.length], join }));
    }
  }
  return out;
}

// ---------------------------------------------------------------------------------------------------------------
// The report
// ---------------------------------------------------------------------------------------------------------------

function failureLines(r) {
  const out = [];
  if (!r.finished) out.push("- the route was not played to its end");
  if (!(r.level >= 60)) out.push(`- ends at level ${r.level}`);
  if (r.slash) out.push(`- ${r.slash} slash command(s)`);
  for (const f of (r.offScreen || []).slice(0, 5)) out.push(`- off the screen at the end: ${f}`);
  if (r.join && !(r.placement && r.placement.inside)) {
    const p = r.placement || {};
    out.push(`- placed at action ${p.landed}, outside ${p.from} to ${p.to} (the prepared player stopped at action ${p.expectedFrom})`);
  }
  for (const x of (r.stuck || []).slice(0, 20)) out.push(`- stuck at ${x.section} step ${x.n} (${x.label}): ${x.reason}`);
  for (const x of (r.cannot || []).slice(0, 20)) out.push(`- cannot do step ${x.n} (${x.label}): ${x.reason}`);
  for (const x of (r.unexplained || []).slice(0, 20)) out.push(`- passed ${x.section || ""} step ${x.n} (${x.label}) as ${x.kind}: ${x.text}`);
  for (const x of (r.errors || []).slice(0, 5)) out.push(`- Lua error: ${String(x).split("\n")[0]}`);
  return out;
}

function reportMarkdown(fresh, joiners, api) {
  const all = [...fresh, ...joiners];
  const f = summarize(fresh), j = summarize(joiners), s = summarize(all);
  const passedAs = (r, kind) => (r.passed && r.passed[kind]) || 0;
  const out = [
    "# Simulator report",
    "",
    "Generated by `npm run sim` (tools/sim_all.js). The whole addon, as the toc loads it, plays each character's route",
    `in the mock client (quest log API: ${api}); a scripted player reads the cards the engine shows (Progress.Cards) and`,
    "does every open line with the mouse and the world, never a command. See tools/harness/sim.lua.",
    "",
    `**${f.passed} of ${f.characters} fresh characters and ${j.passed} of ${j.characters} joiners pass.** ` +
      `${s.at60} of ${s.characters} runs reach level 60; ${s.stuck} stuck steps; ${s.cannot} steps the character cannot do; ` +
      `${s.unexplained} unexplained skips; ${s.errors} Lua errors; ${s.slash} slash commands; ${s.offScreen} frames off the screen; ` +
      `${j.inside} of ${j.joiners} joiners placed inside their window.`,
    "",
    `The player picked a quest by hand ${s.manual} times: where two quests in one NPC's list share a title and the client`,
    "gives titles only, the automation leaves the choice to the player by design (NoirGuides/Automation.lua). That is not a failure.",
    "",
    "Passed (done), (moot), (condition) and (outleveled) count the steps and lines the engine moved past with the game's",
    "evidence and wrote to the why-log. Every other way past a step is unexplained.",
    "",
    "## Fresh characters (level 1, nothing done)",
    "",
    "| Character | Result | Level | Steps shown | Stuck | Cannot | Unexplained | Errors | Passed (done) | Passed (moot) | Passed (condition) | Passed (outleveled) | Picked by hand |",
    "|---|---|---|---|---|---|---|---|---|---|---|---|---|",
  ];
  for (const r of fresh) {
    out.push(`| ${r.race} ${r.class}${r.professions ? ` (profession ${r.professions.join(", ")})` : ""} | ${passed(r) ? "pass" : "FAIL"} | ${r.level} | ${r.shown} | ${(r.stuck || []).length} | ${(r.cannot || []).length} | ` +
      `${(r.unexplained || []).length} | ${(r.errors || []).length} | ${passedAs(r, "done")} | ${passedAs(r, "moot")} | ${passedAs(r, "condition")} | ` +
      `${passedAs(r, "outleveled")} | ${(r.manual || []).length} |`);
  }
  out.push(
    "",
    "## Joiners (a character that played without the addon, then installs it)",
    "",
    "The prepared player plays the route's flattened actions until the join level, leaving out every 7th accept whose",
    "quest is no prerequisite of a later route quest; the addon then logs in with empty saved variables. Placement is",
    "measured in flattened actions: the window runs from 40 actions before the last one the prepared player did to the",
    "first one after it that is not done.",
    "",
    "| Character | Join level | Result | Level | Expected from | Landed | Window | Steps passed by placement | Stuck | Unexplained | Errors |",
    "|---|---|---|---|---|---|---|---|---|---|---|",
  );
  for (const r of joiners) {
    const p = r.placement || {};
    out.push(`| ${r.race} ${r.class} | ${r.join} | ${passed(r) ? "pass" : "FAIL"} | ${r.level} | ${p.expectedFrom} | ${p.landed}${p.landedAt ? ` (${p.landedAt})` : ""} | ` +
      `${p.from} to ${p.to} | ${p.passedSteps} | ${(r.stuck || []).length} | ${(r.unexplained || []).length} | ${(r.errors || []).length} |`);
  }
  const failing = all.filter((r) => !passed(r));
  if (failing.length) {
    out.push("", "## Failures", "");
    for (const r of failing) {
      out.push(`### ${r.race} ${r.class}${r.professions ? ` (profession ${r.professions.join(", ")})` : ""}${r.join ? ` joining at level ${r.join}` : ""}`, "", ...failureLines(r), "");
    }
  }
  return out.join("\n") + "\n";
}

// ---------------------------------------------------------------------------------------------------------------
// The CLI: characters run in parallel worker threads
// ---------------------------------------------------------------------------------------------------------------

function loadWorld() {
  const { loadDb } = require("./lib/db");
  const { loadTravel } = require("./lib/travel");
  const { loadInns } = require("./planner/context");
  const db = loadDb(DATA);
  return { db, graph: loadTravel(db, DATA), inns: loadInns(db, DATA) };
}

function routeFor(ch) {
  const file = path.join(ROUTES, `${ch.faction.toLowerCase()}-${ch.race.toLowerCase()}.lua`);
  return parseRoute(fs.readFileSync(file, "utf8"));
}

const emptyResult = (ch, e) => ({ race: ch.race, class: ch.cls, join: ch.join, finished: false, level: 0, shown: 0, stuck: [], cannot: [],
  unexplained: [], manual: [], offScreen: [], slash: 0, errors: [String(e.stack || e)] });

function workerMain() {
  const { parentPort, workerData } = require("worker_threads");
  const world = loadWorld();
  const routes = new Map();
  parentPort.on("message", (ch) => {
    if (ch === null) { process.exit(0); }
    const started = Date.now();
    let result;
    try {
      const key = `${ch.race}`;
      if (!routes.has(key)) routes.set(key, routeFor(ch));
      result = simulate(buildFacts(world.db, world.graph, world.inns, routes.get(key), ch), { api: workerData.api, join: ch.join });
    } catch (e) {
      result = emptyResult(ch, e);
    }
    if (ch.professions) result.professions = ch.professions;
    result.seconds = Math.round((Date.now() - started) / 1000);
    parentPort.postMessage(result);
  });
}

function argValue(argv, name) {
  const i = argv.indexOf(name);
  return i >= 0 ? argv[i + 1] : null;
}

const JOIN_LEVELS = [1, 12, 25, 40, 55];

async function main(argv) {
  const { Worker } = require("worker_threads");
  const race = argValue(argv, "--race"), cls = argValue(argv, "--class"), api = argValue(argv, "--api") || "classic";
  const joinArg = argValue(argv, "--join"), joinersArg = argValue(argv, "--joiners");
  const characters = combos(DATA);
  const match = (c) => (!race || c.race === race) && (!cls || c.cls === cls);
  let joiners = joinerList(characters, JOIN_LEVELS, joinersArg === "all").filter(match);
  if (joinArg) joiners = joiners.filter((j) => j.join === Number(joinArg));
  const withProfessions = PROFESSION_CHARACTERS.map((p) => ({ ...characters.find((c) => c.race === p.race && c.cls === p.cls), professions: p.professions }))
    .filter((c) => c.faction && match(c));
  let fresh = joinArg ? [] : [...characters.filter(match), ...withProfessions];
  if (joinersArg === "only") fresh = [];
  if (joinersArg === "none") joiners = [];
  const all = [...fresh, ...joiners];
  if (!all.length) { console.error("no character matches"); return 1; }
  const threads = Math.max(1, Math.min(all.length, Number(argValue(argv, "--threads")) || Math.max(1, os.cpus().length - 1)));
  const started = Date.now();
  const results = new Array(all.length);
  const name = (r) => `${r.race} ${r.class || r.cls}${r.professions ? ` with profession ${r.professions.join(", ")}` : ""}${r.join ? ` joining at ${r.join}` : ""}`;
  const status = (done) => fs.writeFileSync(STATUS, JSON.stringify({ phase: "Simulator", total: all.length, done, started,
    characters: results.filter(Boolean).map((r) => ({ race: r.race, cls: r.class, join: r.join, passed: passed(r), level: r.level, stuck: r.stuck.length,
      cannot: r.cannot.length, unexplained: r.unexplained.length, errors: r.errors.length })) }, null, 1) + "\n");
  console.log(`simulating ${fresh.length} fresh characters and ${joiners.length} joiners on ${threads} threads (quest log API: ${api})`);
  status(0);
  // Longest first: joiners at low levels and fresh characters play the whole route.
  const order = all.map((_, i) => i).sort((a, b) => (all[a].join || 0) - (all[b].join || 0));
  let next = 0, done = 0;
  await new Promise((resolve) => {
    for (let t = 0; t < threads; t++) {
      const worker = new Worker(__filename, { workerData: { worker: true, api } });
      const feed = () => {
        if (next >= order.length) { worker.postMessage(null); return; }
        const i = order[next++];
        worker.once("message", (r) => {
          results[i] = r;
          done++;
          const p = r.placement;
          console.log(`${passed(r) ? "pass" : "FAIL"}  ${name(r)}: level ${r.level}, ${r.shown} steps shown, ${r.stuck.length} stuck, ` +
            `${r.cannot.length} cannot, ${r.unexplained.length} unexplained, ${r.errors.length} errors, ${r.slash || 0} slash, ` +
            `${(r.offScreen || []).length} off screen, ${r.sellLines || 0} sell lines (${r.sold || 0}c), ${r.skillRaised || 0} skill raises${p ? `, placed at ${p.landed} (window ${p.from} to ${p.to})` : ""} (${r.seconds} s)`);
          status(done);
          if (done === all.length) resolve();
          feed();
        });
        worker.postMessage(all[i]);
      };
      feed();
    }
  });
  const freshResults = results.slice(0, fresh.length), joinResults = results.slice(fresh.length);
  const s = summarize(results), f = summarize(freshResults), j = summarize(joinResults);
  if (!race && !cls && !joinArg && !joinersArg) {
    fs.mkdirSync(path.dirname(REPORT), { recursive: true });
    fs.writeFileSync(REPORT, reportMarkdown(freshResults, joinResults, api));
  }
  console.log(`${f.passed} of ${f.characters} fresh and ${j.passed} of ${j.characters} joiners pass: ${s.at60} at level 60, ${s.stuck} stuck, ` +
    `${s.cannot} cannot, ${s.unexplained} unexplained, ${s.errors} Lua errors, ${s.slash} slash, ${s.offScreen} off screen, ` +
    `${j.inside} of ${j.joiners} joiners inside their window (${Math.round((Date.now() - started) / 1000)} s)`);
  return s.ok ? 0 : 1;
}

const threads = require("worker_threads");
if (!threads.isMainThread && threads.workerData && threads.workerData.worker) workerMain();
else if (require.main === module) main(process.argv.slice(2)).then((code) => { process.exitCode = code; });

module.exports = { parseRoute, flattenFor, buildFacts, toLua, simulate, problems, summarize, passed, joinerList, reportMarkdown, JOIN_LEVELS, PROFESSION_CHARACTERS };
