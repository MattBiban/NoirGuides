// Noir Guides, GPLv3. See LICENSE.
// CLI: plan the route of every race, layer its classes' quests in, validate every class and race combination on it,
// turn it into format 3 (bundle, sections, reminders, profession steps, class trainer visits, step texts), validate
// every character again on the format 3 route, measure, emit and report. node build_routes.js [--race Undead]
const fs = require("fs");
const path = require("path");
const { loadDb } = require("./lib/db");
const { loadTravel } = require("./lib/travel");
const { combos, RACES } = require("./lib/characters");
const { loadInns, plannerGraph } = require("./planner/context");
const { planRoute } = require("./planner/plan");
const { layerClasses } = require("./planner/classes");
const { validateRoute } = require("./planner/validate");
const { measureRoute } = require("./planner/measure");
const { emitNames, emitZones, emitFlights } = require("./planner/emit");
const { bundleSteps } = require("./planner/bundle");
const { splitSections, regrindSections, stepLevels, MAX_SECTION_STEPS } = require("./planner/sections");
const { addReminders } = require("./planner/reminders");
const { addProfessionSteps } = require("./planner/professions");
const { addClassTraining } = require("./planner/training");
const { stepText } = require("./planner/texts");
const { emitRoute3 } = require("./planner/emit3");
const { validate3, estimateSteps } = require("./planner/validate3");
const { reportMarkdown, summarize, acceptance, thousands, hours } = require("./planner/report");

const DATA = path.join(__dirname, "data");
const ADDON = path.join(__dirname, "..", "NoirGuides");
const REPORT = path.join(__dirname, "..", "docs", "routes", "REPORT.md");
const PROFESSION_NOTES = path.join(__dirname, "..", "docs", "routes", "PROFESSION-NOTES.md");
const BASELINE = path.join(__dirname, "planner", "baseline.json");
// what task P3 asks of every race's format 3 route
const MAX_BUNDLED_SHARE = 0.65, MIN_SECTIONS = 6, MAX_SECTIONS = 45;

// The format 3 route of one race from its layered format 2 route and each class's replay of it (validations).
function toFormat3(db, graph, inns, route, classes, validations) {
  const levels = validations.map((v) => v.result.levels);
  // the shared estimate: at each action, the lowest level any class has there
  const lowest = route.steps.map((_, k) => Math.min(...levels.map((l) => l[k])));
  const bundled = bundleSteps(db, route, lowest);
  const classLevels = {};
  validations.forEach((v) => { classLevels[v.character.cls] = stepLevels(v.result.levels, bundled.origin, v.result.endLevel); });
  const shared = stepLevels(lowest, bundled.origin, Math.min(...validations.map((v) => v.result.endLevel)));
  const notes = [];
  let sections = splitSections(db, route.race, route.faction, bundled, shared, classLevels, notes).map((s) => addReminders(db, s));
  // each class's estimated level at every step it plays, replayed on the sections
  const draft = { id: route.id, format: 3, race: route.race, faction: route.faction, sections };
  const estimate = {};
  for (const ch of classes) estimate[ch.cls] = estimateSteps(db, draft, ch, { graph, inns }).levels;
  const sharedLevel = (step) => {
    let start = Infinity, end = Infinity;
    for (const ch of classes) { const l = estimate[ch.cls].get(step); if (l) { start = Math.min(start, l.start); end = Math.min(end, l.end); } }
    return start === Infinity ? undefined : { start, end };
  };
  const professionNotes = [];
  sections = addProfessionSteps(db, sections, route.faction, { levelOf: sharedLevel, notes: professionNotes });
  const trainingNotes = [];
  // a trainer trip is planned like the route: without the links whose users are an assumption (planner/context.js)
  sections = addClassTraining(db, sections, route.faction, { graph: plannerGraph(graph), classes: classes.map((c) => c.cls), levelOf: (cls, step) => estimate[cls].get(step), notes: trainingNotes });
  // a trainer trip's way there and back changes its class's estimate: grinds again where a step's minLevel is missed
  const trained = { ...draft, sections };
  const after = {};
  for (const ch of classes) after[ch.cls] = estimateSteps(db, trained, ch, { graph, inns }).levels;
  sections = regrindSections(sections, classes.map((c) => c.cls), (cls, step) => after[cls].get(step));
  // texts: a step's previous step is the last one before it (also across sections) that every character has, or one
  // with the same condition
  let previous;
  sections = sections.map((section) => ({ ...section, steps: section.steps.map((step) => {
    const text = stepText(db, step, { previous, section, faction: route.faction });
    const out = text ? { ...step, text } : step;
    if (!step.when || (previous && JSON.stringify(previous.when) === JSON.stringify(step.when))) previous = out;
    return out;
  }) }));
  const route3 = { id: route.id, format: 3, race: route.race, faction: route.faction, sections };
  const checks = classes.map((ch) => ({ character: ch, result: validate3(db, route3, ch, { graph, inns }) }));
  return { route3, bundled, notes, professionNotes: professionNotes.map((n) => n.text), trainingNotes: trainingNotes.map((n) => `${n.cls} ${n.from} to ${n.to}: ${n.why}`), checks };
}

function main(argv) {
  const flag = argv.indexOf("--race");
  const only = flag >= 0 ? argv[flag + 1] : null;
  if (flag >= 0 && !RACES[only]) {
    console.error(`unknown race ${only}; one of ${Object.keys(RACES).join(", ")}`);
    return 1;
  }
  const db = loadDb(DATA);
  const graph = loadTravel(db, DATA);
  const inns = loadInns(db, DATA);
  const all = combos(DATA);
  // races in the fixed order of RACES, each with its classes in the order combos gives
  const races = Object.keys(RACES).filter((race) => all.some((c) => c.race === race) && (!only || race === only));
  const started = Date.now(); // for the status file only; nothing in a route or the report reads the clock
  // per character: whether its route is valid and reaches 60, and what of its class it got
  const characters = [];
  const status = (done, current) => fs.writeFileSync(path.join(DATA, "build_status.json"),
    JSON.stringify({ phase: "Routes", total: races.length, done, current, started, characters }, null, 1) + "\n");

  fs.mkdirSync(path.join(ADDON, "Routes"), { recursive: true });
  const results = [];
  let failed = false;
  races.forEach((race, n) => {
    status(n, [race]);
    const classes = all.filter((c) => c.race === race);
    // the shared route takes no class quest, so any class plans it; each class's quests are then layered in
    const shared = planRoute(db, classes[0], { graph, inns });
    const layered = layerClasses(db, shared, classes, { graph });
    const route = layered.route;
    const validations = classes.map((character) => {
      const result = validateRoute(db, route, character, { graph, inns });
      // the character's own steps measured, to show what its class steps add to the shared route
      return { character, result, layer: layered.classes[character.cls], measure: measureRoute(db, graph, route, character, result.levels) };
    });
    const measure = measureRoute(db, graph, shared, classes[0], validateRoute(db, shared, classes[0], { graph, inns }).levels);
    const f3 = toFormat3(db, graph, inns, route, classes, validations);
    fs.writeFileSync(path.join(ADDON, "Routes", route.id + ".lua"), emitRoute3(f3.route3));
    const errors3 = f3.checks.flatMap(({ character, result: r }) => r.errors.map((e) => `${character.cls}: ${e}`));
    const result = { route, shared, validations, measure, route3: f3.route3,
      format3: { actions: route.steps.length, bundled: f3.bundled.steps.length, route3: f3.route3, professionNotes: f3.professionNotes, trainingNotes: f3.trainingNotes, notes: f3.notes, errors: errors3 } };
    for (const { character, result: r, layer, measure: own } of validations) {
      const r3 = f3.checks.find((c) => c.character.cls === character.cls).result;
      characters.push({ race, cls: character.cls, valid: r.errors.length === 0 && r.endLevel >= 60 && r3.errors.length === 0 && r3.endLevel >= 60, endLevel: r3.endLevel,
        errors: [...r.errors, ...r3.errors].slice(0, 20), zoneChanges: own.zoneChanges, travelSeconds: Math.round(own.seconds),
        steps: route.steps.filter((x) => !x.when || x.when.class === undefined || x.when.class === character.cls).length,
        classQuests: layer.layered, left: layer.left });
    }
    results.push(result);
    const s = summarize(db, result);
    if (s.errors.length || s.endLevel < 60) failed = true;
    console.log(`${race}: ${thousands(s.steps)} steps, ${thousands(s.quests)} quests, level ${s.endLevel}, ${s.zoneChanges} zone changes, ${hours(s.travelSeconds)} of travel, ` +
      `${s.grinds.length} grind steps, ${thousands(s.errors.length)} errors`);
    for (const c of s.characters) console.log(`  ${c.cls}: ${c.valid ? "valid" : "NOT VALID"}, level ${c.endLevel}, ${c.layered} class quests layered, ${c.left} left out, ` +
      `${c.zoneChanges} zone changes (${c.addedZoneChanges >= 0 ? "+" : ""}${c.addedZoneChanges}), ${hours(c.travelSeconds)} of travel`);
    for (const e of s.errors.slice(0, 20)) console.log(`  ${e}`);

    // format 3
    const sections = f3.route3.sections;
    const largest = Math.max(...sections.map((x) => x.steps.length));
    const share = f3.bundled.steps.length / route.steps.length;
    console.log(`  format 3: ${thousands(route.steps.length)} actions to ${thousands(f3.bundled.steps.length)} steps (${Math.round(share * 100)}%), ` +
      `${sections.length} sections, the largest ${largest} steps, ${thousands(sections.reduce((sum, x) => sum + x.steps.length, 0))} steps written, ${errors3.length} errors`);
    const visitId = /^t([A-Z]+)-(\d+)$/;
    for (const { character, result: r } of f3.checks) {
      const visits = sections.flatMap((x) => x.steps).map((x) => visitId.exec(x.id)).filter((m) => m && m[1] === character.cls).map((m) => m[2]);
      console.log(`    ${character.cls}: level ${r.endLevel}, ${r.errors.length} errors, trainer visits at ${visits.join(", ") || "none"}`);
      if (r.errors.length || r.endLevel < 60) failed = true;
    }
    for (const e of errors3.slice(0, 20)) console.log(`  ${e}`);
    const unmet = [];
    if (share > MAX_BUNDLED_SHARE) unmet.push(`steps after bundling are ${Math.round(share * 100)}% of the actions (at most ${MAX_BUNDLED_SHARE * 100}%)`);
    if (sections.length < MIN_SECTIONS || sections.length > MAX_SECTIONS) unmet.push(`${sections.length} sections (${MIN_SECTIONS} to ${MAX_SECTIONS})`);
    if (largest > MAX_SECTION_STEPS) unmet.push(`a section has ${largest} steps (at most ${MAX_SECTION_STEPS})`);
    // printed for the owner; the exit code says whether every character's route is valid and reaches 60
    for (const u of unmet) console.log(`  NOT MET: ${u}`);
    status(n + 1, []);
  });
  // A single-race run leaves the report and the shared data files alone: they cover every race.
  if (!only) {
    const routes = results.map((r) => r.route3);
    fs.mkdirSync(path.join(ADDON, "Data"), { recursive: true });
    fs.writeFileSync(path.join(ADDON, "Data", "Names.lua"), emitNames(db, routes));
    fs.writeFileSync(path.join(ADDON, "Data", "Zones.lua"), emitZones(db, routes, graph));
    fs.writeFileSync(path.join(ADDON, "Data", "Flights.lua"), emitFlights(graph));
    const baseline = fs.existsSync(BASELINE) ? JSON.parse(fs.readFileSync(BASELINE, "utf8")) : null;
    fs.mkdirSync(path.dirname(REPORT), { recursive: true });
    fs.writeFileSync(REPORT, reportMarkdown(db, results, baseline));
    fs.writeFileSync(PROFESSION_NOTES, professionNotesMarkdown(results));
    if (baseline) {
      const rows = results.map((r) => ({ race: r.route.race, s: summarize(db, r), before: baseline.races[r.route.race] }));
      for (const a of acceptance(rows)) console.log(`${a.met ? "met    " : "NOT MET"}  ${a.name}: ${a.detail}`);
    }
  }
  return failed ? 1 : 0;
}

// docs/routes/PROFESSION-NOTES.md: the profession ranks no step could be written for, per race.
function professionNotesMarkdown(results) {
  const out = [
    "# Profession notes",
    "",
    "Generated by `tools/build_routes.js` (`tools/planner/professions.js`). Do not edit.",
    "",
    "Each primary profession gets a trainer step for Journeyman, Expert and Artisan (ranks 2 to 4) at or after the",
    "rank's level (10, 20, 35), in a zone with a trainer of that rank friendly to the faction, searched over the section",
    "where the level is reached and the two after it: at the last such step of the first section where that step stands",
    "in the second half of the section, else where the most of its section comes before it. The ranks listed below got",
    "no step; the profession plan in chat still covers them. Each rank that has a step also gets a reminder to raise the",
    "skill to the rank's gate, from the start of the trainer step's section to the trainer step (the trainer step is",
    "passed while the skill is below the gate, so it stands late in its section). Not verified in game",
    "(`verified = false`):",
    "",
    "- the levels 10, 20 and 35: Forever gates the ranks by skill (50, 125, 200); the levels only place the steps;",
    "- who trains which rank, read from QuestieDB sub names: \"<Profession> Trainer\" or \"<Crafter> Trainer\" teaches",
    "  every rank, \"Journeyman <Crafter>\" up to Journeyman, \"Expert <Crafter>\" up to Expert, \"Artisan <Crafter>\" and",
    "  \"Master <Crafter>\" up to Artisan.",
    "",
  ];
  for (const r of results) {
    const notes = r.format3.professionNotes;
    out.push(`## ${r.route.race}`, "");
    if (!notes.length) out.push("Every rank of every primary profession has a step.");
    else for (const n of notes) out.push(`- ${n}`);
    out.push("");
  }
  return out.join("\n");
}

process.exitCode = main(process.argv.slice(2));
