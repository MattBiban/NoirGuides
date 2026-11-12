// Noir Guides, GPLv3. See LICENSE.
// Routes -> markdown: what each route is, and how it compares with the routes of the baseline commit
// (planner/baseline.json, written by tools/baseline.js). Nothing here depends on the clock, so the report is as
// repeatable as the routes.
const CURVE = [10, 20, 30, 40, 50, 60];
const TARGET = 0.6; // the share of the baseline's zone changes a route has to save

const thousands = (n) => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
const zoneName = (db, zone) => (db.areas.get(zone) || {}).name || String(zone);
const hours = (seconds) => { const minutes = Math.round(seconds / 60); return `${Math.floor(minutes / 60)} h ${String(minutes % 60).padStart(2, "0")} min`; };
const percent = (before, after) => (before > 0 ? `${after <= before ? "-" : "+"}${Math.abs(Math.round((1 - after / before) * 100))}%` : "n/a");

// The facts of one route, counted from its steps. build_routes.js prints from the same numbers.
//   result: { route, validations: [{ character, result, layer, measure }], measure, shared } (measure from planner/measure.js)
//   route is the route file as written; shared, when the classes are layered in (planner/classes.js), the route every
//   class has in common, which the facts and the measurement are about; layer is the class's entry of layerClasses;
//   a validation's measure is of the character's own steps (shared and its class's), so the report shows what each
//   class's steps add to the shared route's zone changes and travel time.
function summarize(db, { route: written, validations, measure, shared }) {
  const route = shared || written;
  const count = (action) => route.steps.filter((s) => s.action === action).length;
  const grinds = route.steps.filter((s) => s.action === "grind").map((s) => ({ from: s.level - 1, to: s.level }));
  // the zones the route works in, in order, with the number of steps that do something there
  const visits = [];
  for (const s of route.steps) {
    if (!["accept", "objective", "turnin", "grind", "sethearth"].includes(s.action)) continue;
    if (!visits.length || visits[visits.length - 1].zone !== s.at.zone) visits.push({ zone: s.at.zone, steps: 0 });
    visits[visits.length - 1].steps++;
  }
  const errors = [];
  const warnings = [];
  for (const { character, result } of validations) {
    for (const e of result.errors) errors.push(`${character.cls}: ${e}`);
    for (const w of result.warnings) if (!warnings.includes(w)) warnings.push(w); // the same for every class, said once
  }
  return {
    steps: route.steps.length, quests: route.stats.quests, endLevel: Math.min(route.stats.endLevel, ...validations.map((v) => v.result.endLevel)),
    zoneChanges: measure.zoneChanges, travelSeconds: measure.seconds, walkedYards: measure.yards, unreachable: measure.unreachable, byKind: measure.byKind,
    totalSeconds: route.stats.seconds, grinds, visits: visits.map((v) => ({ name: zoneName(db, v.zone), steps: v.steps })),
    flightsLearned: count("getflight"), flights: count("fly"), transports: count("transport"), binds: count("sethearth"), hearths: count("hearth"),
    links: route.stats.links || [], errors, warnings, classes: validations.map((v) => v.character.cls),
    characters: validations.map(({ character, result, layer, measure: mine }) => ({ race: character.race, cls: character.cls, valid: result.errors.length === 0 && result.endLevel >= 60,
      endLevel: result.endLevel, errors: result.errors.length, layered: layer ? layer.layered.length : 0, left: layer ? layer.left.length : 0,
      leftOut: layer ? layer.left : [], steps: layer ? layer.steps : 0, seconds: Math.round(result.seconds), ...own(mine, measure) })),
  };
}

// A character's own measurement beside the shared route's: { zoneChanges, addedZoneChanges, travelSeconds, addedSeconds }.
function own(mine, shared) {
  if (!mine) return {};
  return { zoneChanges: mine.zoneChanges, addedZoneChanges: mine.zoneChanges - shared.zoneChanges,
    travelSeconds: Math.round(mine.seconds), addedSeconds: Math.round(mine.seconds) - Math.round(shared.seconds) };
}
const signed = (n) => (n < 0 ? "-" : "+") + Math.abs(n);
const signedHours = (seconds) => (seconds < 0 ? "-" : "+") + hours(Math.abs(seconds));

// What the acceptance of the planner asks, answered from the numbers: [{ name, met, detail }].
function acceptance(rows) {
  const compared = rows.filter((r) => r.before);
  const saved = (r) => 1 - r.s.zoneChanges / r.before.zoneChanges;
  const worst = compared.slice().sort((a, b) => saved(a) - saved(b))[0];
  const slower = compared.filter((r) => r.s.travelSeconds > r.before.travelSeconds);
  const errors = rows.reduce((sum, r) => sum + r.s.errors.length, 0);
  const short = rows.filter((r) => r.s.endLevel < 60);
  const characters = rows.flatMap((r) => r.s.characters || []);
  return [
    { name: `Zone changes down by at least ${TARGET * 100}% for every race`, met: compared.length > 0 && compared.every((r) => saved(r) >= TARGET),
      detail: worst ? `least: ${worst.race}, ${worst.before.zoneChanges} to ${worst.s.zoneChanges} (${percent(worst.before.zoneChanges, worst.s.zoneChanges)})` : "no baseline" },
    { name: "Travel time not worse for any race", met: compared.length > 0 && !slower.length, detail: slower.length ? `slower: ${slower.map((r) => r.race).join(", ")}` : "every race is faster" },
    { name: "No validator errors", met: errors === 0, detail: `${thousands(errors)} errors` },
    { name: "Every race reaches level 60", met: !short.length, detail: short.length ? `short: ${short.map((r) => `${r.race} (${r.s.endLevel})`).join(", ")}` : "all at 60" },
    characterLine(characters),
  ];
}

// Every class and race combination against its race's route with the class quests layered in.
function characterLine(characters) {
  const valid = characters.filter((c) => c.valid);
  return { name: "Characters valid and at level 60", met: characters.length > 0 && valid.length === characters.length, detail: `${valid.length} of ${characters.length}` };
}
function characterSection(rows) {
  const characters = rows.flatMap((r) => r.s.characters || []);
  if (!characters.length) return [];
  const line = characterLine(characters);
  const out = ["## Characters", ""];
  out.push("Every class of every race, replayed by the validator on its race's route file: the shared route and the steps marked");
  out.push("for its class (`when = { class = ... }`), which `tools/planner/classes.js` layers in at the cheapest detour that keeps");
  out.push("the quest's level and prerequisites. A class quest it could not fit is left out and listed under its race.");
  out.push("Zone changes and travel time are measured by `tools/planner/measure.js` on the character's own steps; \"added\" is");
  out.push("what its class steps add to the shared route's numbers, which the race's section gives.");
  out.push("");
  out.push("| Asked | Met | Evidence |", "| --- | --- | --- |", `| ${line.name} | ${line.met ? "yes" : "**no**"} | ${line.detail} |`, "");
  const measured = characters.every((c) => c.travelSeconds !== undefined);
  out.push(`| Race | Class | Valid | End level | Class quests layered | Left out | Class steps |${measured ? " Zone changes | Added | Travel time | Added |" : ""} Whole route, estimated |`);
  out.push(`| --- | --- | --- | --- | --- | --- | --- |${measured ? " --- | --- | --- | --- |" : ""} --- |`);
  for (const c of characters) {
    const m = measured ? ` ${c.zoneChanges} | ${signed(c.addedZoneChanges)} | ${hours(c.travelSeconds)} | ${signedHours(c.addedSeconds)} |` : "";
    out.push(`| ${c.race} | ${c.cls} | ${c.valid ? "yes" : "**no**"} | ${c.endLevel} | ${c.layered} | ${c.left} | ${c.steps} |${m} ${hours(c.seconds)} |`);
  }
  out.push("");
  return out;
}

// A race's format 3 route as the build wrote it. f = { actions, bundled, route3, professionNotes, notes, errors }:
// the format 2 actions and the steps bundling made of them, the route file's content, the profession ranks that got
// no step, the planner's notes (planner/sections.js) and the format 3 validator's errors over every class.
const VISIT = /^t([A-Z]+)-(\d+)$/;
const PROFESSION_STEP = /^p\d+-\d$/;
function format3Section(f) {
  const steps = f.route3.sections.flatMap((s) => s.steps);
  const unique = (list) => [...new Set(list)];
  const professions = unique(steps.filter((s) => PROFESSION_STEP.test(s.id)).map((s) => s.id));
  const visits = {};
  for (const s of steps) {
    const m = VISIT.exec(s.id);
    if (!m || !s.lines.some((l) => l.kind === "train" && l.class === m[1])) continue;
    (visits[m[1]] = visits[m[1]] || []).push(+m[2]);
  }
  const classes = Object.keys(visits).sort();
  const share = f.actions > 0 ? `${Math.round((f.bundled / f.actions) * 100)}%` : "n/a";
  const cell = (list) => (list.length ? list.join("; ") : "none");
  const out = ["### Format 3", ""];
  out.push("| Fact | Value |", "| --- | --- |");
  out.push(`| Actions before bundling, steps after | ${thousands(f.actions)}, ${thousands(f.bundled)} (${share}) |`);
  out.push(`| Steps in the route file | ${thousands(steps.length)} |`);
  out.push(`| Sections | ${f.route3.sections.length} |`);
  out.push(`| Profession steps written | ${professions.length ? professions.join(", ") : "none"} |`);
  out.push(`| Profession ranks without a step | ${cell(f.professionNotes || [])} |`);
  out.push(`| Class trainer visits | ${classes.length ? classes.map((c) => `${c}: ${unique(visits[c]).sort((a, b) => a - b).join(", ")}`).join("; ") : "none"} |`);
  out.push(`| Class trainer gaps | ${cell(f.trainingNotes || [])} |`);
  out.push(`| Planner notes | ${cell(f.notes || [])} |`);
  out.push(`| Format 3 errors | ${(f.errors || []).length} |`);
  out.push("");
  out.push("| Section | Name | Steps | Levels |", "| --- | --- | --- | --- |");
  for (const s of f.route3.sections) out.push(`| ${s.id} | ${s.name} | ${s.steps.length} | ${s.minLevel}-${s.maxLevel === undefined ? s.minLevel : s.maxLevel} |`);
  out.push("");
  if ((f.errors || []).length) {
    out.push("Format 3 errors:", "");
    for (const e of f.errors) out.push(`- ${e}`);
    out.push("");
  }
  return out;
}

// baseline: the content of planner/baseline.json, or null when there is none to compare with.
function reportMarkdown(db, results, baseline) {
  const rows = results.map((r) => ({ race: r.route.race, r, s: summarize(db, r), before: baseline && baseline.races[r.route.race] }));
  const out = [
    "# Route report",
    "",
    "Generated by `tools/build_routes.js`. Do not edit.",
    "",
    "One route per race, planned by `tools/planner/plan.js` and replayed step by step by `tools/planner/validate.js`.",
    "XP and times are estimates (`tools/lib/xp.js`, `tools/lib/travel.js`, `tools/planner/tuning.js`): they pace the",
    "route, the game decides the rest. A grind step means no quest was left for the level.",
    "",
  ];
  if (baseline) {
    out.push("## Before and after", "");
    out.push(`Before: the routes of commit \`${baseline.commit}\`, the last ones of the first planner, as \`tools/baseline.js\` measured them`);
    out.push("(`tools/planner/baseline.json`). After: the routes in `NoirGuides/Routes/` now. Both are measured by `tools/planner/measure.js`:");
    out.push("");
    out.push("- **Zone changes:** how often the route moves its work to another zone: two steps in a row that do something in");
    out.push("  a zone (accept, objective, turn-in, grind, bind) and name different zones. Steps of the way (travel, flight,");
    out.push("  transport, hearth, learning a flight point) are not counted: the old routes had no such steps.");
    out.push("- **Travel time:** every walk between two steps, every flight, transport and hearth. The new routes are timed as");
    out.push("  written. The old routes name no way at all, so each got the fastest way `tools/lib/travel.js` finds between two");
    out.push("  steps, with every transport open to it: the comparison errs in favour of the old routes.");
    out.push("- **Walked:** the yards of all that on foot, through the passes between zones; the old routes on the same way.");
    out.push("- **Steps, quests, grind steps:** before, as the old report gave them.");
    out.push("");
    out.push("| Race | Zone changes | | | Travel time | | | Walked yards | | | Steps | | Quests | | Grind steps | | End level |");
    out.push("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |");
    out.push("| | before | after | change | before | after | change | before | after | change | before | after | before | after | before | after | after |");
    for (const { race, s, before } of rows) {
      if (!before) { out.push(`| ${race} | n/a | ${s.zoneChanges} | n/a | n/a | ${hours(s.travelSeconds)} | n/a | n/a | ${thousands(s.walkedYards)} | n/a | n/a | ${thousands(s.steps)} | n/a | ${thousands(s.quests)} | n/a | ${s.grinds.length} | ${s.endLevel} |`); continue; }
      out.push(`| ${race} | ${before.zoneChanges} | ${s.zoneChanges} | ${percent(before.zoneChanges, s.zoneChanges)} | ${hours(before.travelSeconds)} | ${hours(s.travelSeconds)} | ${percent(before.travelSeconds, s.travelSeconds)} | ` +
        `${thousands(before.walkedYards)} | ${thousands(s.walkedYards)} | ${percent(before.walkedYards, s.walkedYards)} | ` +
        `${thousands(before.steps)} | ${thousands(s.steps)} | ${thousands(before.quests)} | ${thousands(s.quests)} | ${before.grindSteps} | ${s.grinds.length} | ${s.endLevel} |`);
    }
    out.push("", "### Acceptance", "");
    out.push("| Asked | Met | Evidence |", "| --- | --- | --- |");
    for (const a of acceptance(rows)) out.push(`| ${a.name} | ${a.met ? "yes" : "**no**"} | ${a.detail} |`);
    out.push("");
  }
  out.push(...characterSection(rows));
  for (const { r, s, before } of rows) {
    const route = r.shared || r.route;
    out.push(`## ${route.race} (${route.faction}, \`${route.id}\`)`, "");
    out.push("| Fact | Value |", "| --- | --- |");
    out.push(`| Classes validated | ${s.classes.join(", ")} |`);
    out.push(`| Steps | ${thousands(s.steps)} |`);
    out.push(`| Quests | ${thousands(s.quests)} |`);
    out.push(`| End level | ${s.endLevel} |`);
    out.push(`| Zone changes | ${s.zoneChanges}${before ? ` (before: ${before.zoneChanges})` : ""} |`);
    out.push(`| Travel time | ${hours(s.travelSeconds)}: on foot ${hours(s.byKind.walk)}, in the air ${hours(s.byKind.fly)}, on transports ${hours(s.byKind.transport)}, hearthstone ${hours(s.byKind.hearth)}${before ? ` (before: ${hours(before.travelSeconds)})` : ""} |`);
    out.push(`| Walked | ${thousands(s.walkedYards)} yards${before ? ` (before: ${thousands(before.walkedYards)})` : ""} |`);
    out.push(`| Whole route, estimated | ${hours(s.totalSeconds)} |`);
    out.push(`| Flight points learned, flights taken | ${s.flightsLearned}, ${s.flights} |`);
    out.push(`| Transports taken | ${s.transports} |`);
    out.push(`| Hearthstone bound, used | ${s.binds}, ${s.hearths} |`);
    out.push(`| Grind steps | ${s.grinds.length}${s.grinds.length ? ` (${s.grinds.map((g) => `level ${g.from} to ${g.to}`).join(", ")})` : ""} |`);
    out.push(`| Unconfirmed transports used | ${s.links.length ? s.links.map((l) => `${l.name} (${l.kind}; not confirmed: ${l.assumed.join(", ")})`).join("; ") : "none"} |`);
    out.push(`| Zones in order (steps there) | ${s.visits.map((v) => `${v.name} (${v.steps})`).join(", ")} |`);
    if (s.characters.some((c) => c.left)) {
      const left = s.characters.filter((c) => c.left).map((c) => `${c.cls}: ${c.leftOut.map((l) => `${l.quest} (${l.reason})`).join(", ")}`);
      out.push(`| Class quests left out | ${left.join("; ")} |`);
    }
    out.push(`| Errors | ${s.errors.length} |`);
    out.push(`| Warnings | ${s.warnings.length ? s.warnings.join("; ") : "none"} |`);
    out.push("");
    if (s.errors.length) {
      out.push("Errors:", "");
      for (const e of s.errors) out.push(`- ${e}`);
      out.push("");
    }
    if (r.format3) out.push(...format3Section(r.format3));
    out.push("### Level curve", "");
    out.push("| Level | Reached at step |", "| --- | --- |");
    for (const level of CURVE) {
      const at = route.stats.levelAt[level];
      out.push(`| ${level} | ${s.endLevel >= level && at !== undefined ? thousands(at + 1) : "not reached"} |`);
    }
    out.push("");
  }
  return out.join("\n");
}
module.exports = { reportMarkdown, summarize, acceptance, thousands, hours, percent };
