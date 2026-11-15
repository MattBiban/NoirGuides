// Noir Guides, GPLv3. See LICENSE.
// Routes -> markdown: what each route is, and how it compares with the routes of the baseline commit
// (planner/baseline.json, written by tools/baseline.js). Nothing here depends on the clock, so the report is as
// repeatable as the routes.
const { leftBehind, MAX_LEFT_BEHIND } = require("./leftbehind");
const { levelGap, MAX_ABOVE, MAX_BELOW_SHARE } = require("./levelgap");
const { MAX_DANGEROUS_WALKS } = require("./danger");
const { CHOICES: C } = require("./tuning");
const { PACE } = require("../lib/xp");
const CURVE = [10, 20, 30, 40, 50, 60];
// What is asked of a route beside the baseline. The routes plan for a realistic pace (lib/xp.js yieldAt: 60% of the
// estimated XP is counted on up to level 30, rising to 68% at level 50) and do quests instead of grinding: a small
// visit and an errand come before a grind step (planner/zonepick.js rule 4, planner/supply.js). So they do 11 to 25%
// more quests than the baseline routes did (850 to 935 against 680 to 795), in more visits to more zones, and the
// limits say what that may cost. Zone changes and travel time are ABOVE the baseline's: that is the accepted price
// of quests instead of grinding. The limits keep the price from growing unseen.
// The share of the baseline's zone changes a route may have. It was 0.9 while small visits waited and the rest of a
// level was ground (140 to 176 changes then, and 10 to 13 grind steps of up to a whole level); measured now: 236 to
// 258 changes against the baseline's 182 to 217, 110 to 132% of it (most: Undead, 240 against 182).
const MAX_ZONE_SHARE = 1.4;
// The share of the baseline's travel time a route may take. It was 1.25 (47 to 54 hours); measured now: 56 to 62
// hours against the baseline's 42 to 47, 128 to 143% of it (most: HighOrder, 61.5 against 43.2). The hours of
// grinding the routes no longer have are not travel, and are not in this number.
const MAX_TRAVEL_SHARE = 1.5;
// Grind steps in a route. A grind step is the last resort: the rest of one level, written when no visit and no
// errand is left for it. It was 20 (measured 10 to 13, most of them a whole level); measured now: none or one, the
// last 2 to 16% of level 59.
const MAX_GRIND_STEPS = 2;

const thousands = (n) => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
const zoneName = (db, zone) => (db.areas.get(zone) || {}).name || String(zone);
const hours = (seconds) => { const minutes = Math.round(seconds / 60); return `${Math.floor(minutes / 60)} h ${String(minutes % 60).padStart(2, "0")} min`; };
const percent = (before, after) => (before > 0 ? `${after <= before ? "-" : "+"}${Math.abs(Math.round((1 - after / before) * 100))}%` : "n/a");

// The facts of one route, counted from its steps. build_routes.js prints from the same numbers.
//   result: { route, validations: [{ character, result, layer, measure, danger }], measure, shared } (measure from planner/measure.js)
//   route is the route file as written; shared, when the classes are layered in (planner/classes.js), the route every
//   class has in common, which the facts and the measurement are about; layer is the class's entry of layerClasses;
//   a validation's measure is of the character's own steps (shared and its class's), so the report shows what each
//   class's steps add to the shared route's zone changes and travel time; danger is the character's walks through
//   zones too dangerous for its level (planner/danger.js dangerousWalks), and the report shows the class with the most.
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
    totalSeconds: route.stats.seconds, grinds, leftBehind: leftBehind(db, route),
    levelGap: validations.reduce((worst, v) => { const g = v.result.levels ? levelGap(db, written, v.result.levels, { cls: v.character.cls }) : null; return g && (!worst || g.above.length > worst.above.length || (g.above.length === worst.above.length && g.below.length > worst.below.length)) ? g : worst; }, null) || { above: [], below: [], steps: 0 },
    dangerous: validations.reduce((worst, v) => (v.danger && v.danger.length > worst.length ? v.danger.map((d) => ({ ...d, cls: v.character.cls })) : worst), []),
    visits: visits.map((v) => ({ name: zoneName(db, v.zone), steps: v.steps })),
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
// The pace the routes are planned at, in words: the share of the estimated XP that is counted on (lib/xp.js yieldAt).
function paceText() {
  const low = Math.round(PACE.YIELD * 100), high = Math.round(PACE.YIELD_LATE * 100);
  if (high === low) return `${low}% of the estimated XP`;
  return `${low}% of the estimated XP up to level ${PACE.YIELD_FROM}, rising to ${high}% at level ${PACE.YIELD_TO}`;
}
// The quests of the routes beside the baseline's, in words, from the rows that have a baseline.
function moreQuests(rows) {
  const shares = rows.filter((r) => r.before && r.before.quests > 0).map((r) => Math.round((r.s.quests / r.before.quests) * 100));
  const low = Math.min(...shares), high = Math.max(...shares);
  return `${low === high ? low : `${low} to ${high}`}% of the baseline's quests`;
}
const signed = (n) => (n < 0 ? "-" : "+") + Math.abs(n);
const signedHours = (seconds) => (seconds < 0 ? "-" : "+") + hours(Math.abs(seconds));

// What the acceptance of the planner asks, answered from the numbers: [{ name, met, detail }].
function acceptance(rows) {
  const compared = rows.filter((r) => r.before);
  const changes = (r) => r.s.zoneChanges / r.before.zoneChanges;
  const worst = compared.slice().sort((a, b) => changes(b) - changes(a))[0];
  const travel = (r) => r.s.travelSeconds / r.before.travelSeconds;
  const slower = compared.filter((r) => r.s.travelSeconds > r.before.travelSeconds * MAX_TRAVEL_SHARE);
  const longest = compared.slice().sort((a, b) => travel(b) - travel(a))[0];
  const grinding = rows.filter((r) => (r.s.grinds || []).length > MAX_GRIND_STEPS);
  const errors = rows.reduce((sum, r) => sum + r.s.errors.length, 0);
  const short = rows.filter((r) => r.s.endLevel < 60);
  const characters = rows.flatMap((r) => r.s.characters || []);
  const behind = rows.filter((r) => (r.s.leftBehind || []).length > MAX_LEFT_BEHIND);
  const gap = (r) => r.s.levelGap || { above: [], below: [], steps: 0 };
  const over = rows.filter((r) => gap(r).above.length > MAX_ABOVE);
  const easy = rows.filter((r) => gap(r).steps > 0 && gap(r).below.length / gap(r).steps > MAX_BELOW_SHARE);
  const unsafe = rows.filter((r) => (r.s.dangerous || []).length > MAX_DANGEROUS_WALKS);
  return [
    { name: `Zone changes at most ${Math.round(MAX_ZONE_SHARE * 100)}% of the baseline for every race`, met: compared.length > 0 && compared.every((r) => r.s.zoneChanges <= r.before.zoneChanges * MAX_ZONE_SHARE),
      detail: worst ? `most: ${worst.race}, ${worst.before.zoneChanges} to ${worst.s.zoneChanges} (${percent(worst.before.zoneChanges, worst.s.zoneChanges)})` : "no baseline" },
    { name: `Travel time at most ${Math.round(MAX_TRAVEL_SHARE * 100)}% of the baseline for every race`, met: compared.length > 0 && !slower.length,
      detail: slower.length ? `over: ${slower.map((r) => r.race).join(", ")}` : longest ? `most: ${longest.race}, ${hours(longest.before.travelSeconds)} to ${hours(longest.s.travelSeconds)} (${percent(longest.before.travelSeconds, longest.s.travelSeconds)})` : "no baseline" },
    { name: "No validator errors", met: errors === 0, detail: `${thousands(errors)} errors` },
    { name: "Every race reaches level 60", met: !short.length, detail: short.length ? `short: ${short.map((r) => `${r.race} (${r.s.endLevel})`).join(", ")}` : "all at 60" },
    { name: `At most ${MAX_LEFT_BEHIND} hand-ins left behind in any race`, met: !behind.length,
      detail: behind.length ? `over: ${behind.map((r) => `${r.race} (${r.s.leftBehind.length})`).join(", ")}` : `${rows.reduce((sum, r) => sum + (r.s.leftBehind || []).length, 0)} in all` },
    { name: `No quest more than ${C.HARD} levels above the player in any race (${C.HARD_TALK} for a quest without fights)`, met: !over.length,
      detail: over.length ? `over: ${over.map((r) => `${r.race} (${gap(r).above.length})`).join(", ")}` : `most: ${Math.max(0, ...rows.map((r) => gap(r).above.length))} quest steps a class (${MAX_ABOVE} allowed: a class a few XP behind the shared route at a level's start)` },
    { name: `At most ${Math.round(MAX_BELOW_SHARE * 100)}% of quest steps more than ${C.EASY} levels below the player in any race`, met: !easy.length,
      detail: easy.length ? `over: ${easy.map((r) => r.race).join(", ")}` : `most: ${Math.round(Math.max(0, ...rows.map((r) => (gap(r).steps ? gap(r).below.length / gap(r).steps : 0))) * 100)}%` },
    { name: `No walk through a zone whose creatures start more than ${C.DANGER_LEVELS} levels above the player, for any class of any race`, met: !unsafe.length,
      detail: unsafe.length ? `over: ${unsafe.map((r) => `${r.race} (${r.s.dangerous.length})`).join(", ")}` : MAX_DANGEROUS_WALKS ? `most: ${Math.max(0, ...rows.map((r) => (r.s.dangerous || []).length))}` : "none" },
    { name: `At most ${MAX_GRIND_STEPS} grind steps in any race`, met: !grinding.length,
      detail: grinding.length ? `over: ${grinding.map((r) => `${r.race} (${r.s.grinds.length})`).join(", ")}` : `most: ${Math.max(0, ...rows.map((r) => (r.s.grinds || []).length))}` },
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
    "route, the game decides the rest.",
    `The planner counts on ${paceText()}, so a`,
    "player at a usual pace is not behind the route. A grind step is the rest of one level and the last resort: it is",
    "written only when no zone has a quest left that the character can do at its level; a zone with a single quest is",
    "gone to first.",
    "A hand-in left behind is a step that moves the player more than LEAVE_YARDS while a quest ready to hand in waits",
    "within READY_YARDS of them (`tools/planner/leftbehind.js`, `tools/planner/tuning.js`).",
    "A dangerous walk is a walk through or inside an open zone whose creatures start more than DANGER_LEVELS above the",
    "player's level there (`tools/planner/danger.js`); flying over it or standing where a boat arrives is none.",
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
    out.push("The baseline routes counted on the whole XP estimate.");
    out.push(`The routes now count on ${paceText()},`);
    out.push(`so they need more quests to reach level 60, and they do them rather than grind: ${moreQuests(rows)}.`);
    out.push("More quests are more visits to more zones, so the routes now change zone more often than the baseline's and");
    out.push("spend more time on the way: that is the accepted price of quests instead of grinding. The acceptance below");
    out.push("says how far above the baseline a route may be.");
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
    out.push(`| Hand-ins left behind | ${s.leftBehind.length ? s.leftBehind.map((b) => `step ${thousands(b.step + 1)} (quest ${b.quests.join(", ")})`).join("; ") : "none"} |`);
    out.push(`| Quests above the level allowed, far below the player's level | ${(s.levelGap || { above: [] }).above.length}, ${(s.levelGap || { below: [] }).below.length} of ${(s.levelGap || { steps: 0 }).steps} quest steps |`);
    out.push(`| Walks through dangerous zones | ${s.dangerous.length ? s.dangerous.map((d) => `step ${thousands(d.step + 1)} (${d.cls}, level ${d.level}: ${zoneName(db, d.zone)}, creatures from ${d.min})`).join("; ") : "none"} |`);
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
module.exports = { reportMarkdown, summarize, acceptance, thousands, hours, percent, MAX_ZONE_SHARE, MAX_TRAVEL_SHARE, MAX_GRIND_STEPS };
