// Noir Guides, GPLv3. See LICENSE.
// Route format 3: the contract between the planner and the engine ("Route format 3" in
// docs/superpowers/plans/2026-11-11-guide-rebuild.md). A route file is a list of sections, each a list of steps, each
// a list of lines.
//
//   checkRoute3(route) -> null for a valid file, else one sentence naming the first three problems as
//                         "section <id> step <id> <problem>", joined by "; ", and "; and N more"
//   RULES              -> [{ id: "R1".."R12", text }]
//
// NoirGuides/Routes.lua (Routes.Check) is the same check in Lua, word for word: both are run against every case of
// tools/test-lua/sample/format3-cases.lua, which holds the expected sentences. Change both or neither.
//
// `route` has the shape of the Lua table: Lua sequences are arrays, other tables plain objects, and an empty table
// may come as either (tools/harness/vm.js reads an empty Lua table as an empty array). Lengths are counted in bytes
// of UTF-8, as Lua's # counts them. Problems that name a key list the keys in sorted order, so the message never
// depends on the order a table is walked in.

const FORMAT = 3;
const MAX_STEPS = 400;
const MAX_TEXT = 160;
const MAX_TITLE = 24;
const MAX_LEVEL = 60;
const MAX_RADIUS = 500;
const MAX_SHOWN = 3;

const RULES = [
  { id: "R1", text: "format is 3; race and faction known and matching" },
  { id: "R2", text: "sections is a non-empty array; section ids unique and well formed; exactly one start" },
  { id: "R3", text: "section name, group, subgroup, minLevel, maxLevel, zone as in the table" },
  { id: "R4", text: "every next.section exists in the file; no cycle through next unless a section on it has loop" },
  { id: "R5", text: "steps has 1 to 400 entries; step ids unique in the section and well formed" },
  { id: "R6", text: "every place is valid (zone positive whole number, x, y in 0..100, r nil or a number in 0..500)" },
  { id: "R7", text: "every line has a known kind and its required fields with the right types; unknown keys on a line or step are refused" },
  { id: "R8", text: "text and note/manual texts at most 160 characters; title at most 24" },
  { id: "R9", text: "conditions use only the known keys with known class tokens and race names; skip conditions use known kinds with their fields" },
  { id: "R10", text: "labels unique in the section; requires, reminder.ends and jump name an existing label (ends on a later step); load names a section in the file" },
  { id: "R11", text: "path only with at; points in 0..100" },
  { id: "R12", text: "items and targets hold positive whole numbers" },
];

const RACES = {
  Human: "Alliance", Dwarf: "Alliance", Gnome: "Alliance", NightElf: "Alliance", HighOrder: "Alliance",
  Orc: "Horde", Troll: "Horde", Tauren: "Horde", Undead: "Horde", Windshaper: "Horde",
};
const FACTIONS = new Set(["Alliance", "Horde"]);
const CLASSES = new Set(["WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID"]);
const GROUPS = new Set(["Alliance", "Horde"]);
const MODES = ["zeppelin", "boat", "tram", "portal"];

// Field kinds of lines and skip conditions:
//   id        positive whole number          ids    list of positive whole numbers
//   place     a place (R6)                    bool   true or false
//   text      a string of at most 160 bytes   class  a class token
//   whole     whole number from lo to hi      number number from lo to hi
//   mode      one of MODES                    buy    { item = id, count = positive whole number }
//   label     a label of the section (R10)
// Each list is in the order the fields are checked; `need` marks a required field.
const F = (name, kind, need, lo, hi) => ({ name, kind, need: need === true, lo, hi });
const LINES = {
  accept: [F("quest", "id", true), F("npc", "id"), F("object", "id"), F("item", "id"), F("manual", "bool"), F("ifDone", "id"), F("requires", "ids")],
  turnin: [F("quest", "id", true), F("npc", "id"), F("object", "id"), F("reward", "whole", false, 1, 6), F("manual", "bool"), F("skipIfMissing", "bool"), F("skipIfIncomplete", "bool")],
  objective: [F("quest", "id", true), F("index", "id", true), F("cap", "id"), F("skipIfMissing", "bool"), F("npc", "id"), F("object", "id"), F("item", "id")],
  collect: [F("item", "id", true), F("count", "whole", true, 0, 1000), F("quest", "id")],
  goto: [F("at", "place", true)],
  getflight: [F("node", "id", true), F("npc", "id")],
  fly: [F("from", "id", true), F("to", "id", true)],
  transport: [F("mode", "mode", true), F("at", "place", true), F("to", "place", true)],
  sethearth: [F("npc", "id")],
  hearth: [F("to", "place", true)],
  grind: [F("level", "whole", true, 2, MAX_LEVEL), F("percent", "number", false, 0, 99)],
  train: [F("spell", "id"), F("skill", "id"), F("rank", "whole", false, 1, 4), F("class", "class"), F("level", "whole", false, 2, MAX_LEVEL), F("npc", "id")],
  vendor: [F("npc", "id", true), F("buy", "buy")],
  use: [F("item", "id", true)],
  target: [F("npc", "id", true), F("enemy", "bool")],
  note: [F("text", "text", true)],
  manual: [F("text", "text", true)],
};
const LINE_COMMON = ["kind", "at", "when"];
const QUEST = [F("quest", "id", true)];
const SKIPS = {
  onquest: QUEST, notonquest: QUEST, complete: QUEST, notcomplete: QUEST, turnedin: QUEST, notturnedin: QUEST,
  level: [F("level", "whole", true, 1, MAX_LEVEL), F("percent", "number", false, 0, 99)],
  below: [F("level", "whole", true, 1, MAX_LEVEL)],
  maxlevel: [F("level", "whole", true, 1, MAX_LEVEL)],
  skill: [F("skill", "id", true), F("value", "whole", true, 0, 1000)],
  item: [F("item", "id", true), F("count", "id")],
  zone: [F("zone", "id", true)],
  bound: [F("zone", "id", true)],
};
const SKIP_COMMON = ["kind", "jump"];
const STEP_KEYS = ["id", "at", "text", "title", "lines", "when", "minLevel", "maxLevel", "label", "requires", "reminder", "skip", "load", "items", "targets", "path"];
const CONDITION_KEYS = new Set(["class", "notClass", "race", "notRace", "profession"]);
const SECTION_ID = /^[a-z0-9-]+$/;
const STEP_ID = /^[A-Za-z0-9.\-+@#:]+$/;
const LABEL = /^[A-Za-z0-9_]+$/;
const NAME = [/^\d+-\d+ [\s\S]+$/, /^\d+ [\s\S]+$/];

const isTable = (v) => typeof v === "object" && v !== null;
// A list is a JavaScript array; an empty Lua table reads as an empty array (tools/harness/vm.js), so it is a list on
// both sides.
const isArray = (v) => Array.isArray(v);
const isWhole = (v) => typeof v === "number" && Number.isInteger(v);
const isId = (v) => isWhole(v) && v > 0;
const inRange = (v, lo, hi) => typeof v === "number" && v >= lo && v <= hi;
const bytes = (s) => Buffer.byteLength(s, "utf8");
const quoted = (v) => `"${String(v)}"`;
// The keys as Lua names them (an array's are 1..n), sorted as strings.
const sortedKeys = (t) => (Array.isArray(t) ? t.map((_, i) => String(i + 1)) : Object.keys(t)).sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));

function isPlace(p) {
  if (!isTable(p) || !isId(p.zone)) return false;
  if (!inRange(p.x, 0, 100) || !inRange(p.y, 0, 100)) return false;
  if (p.r !== undefined && !inRange(p.r, 0, MAX_RADIUS)) return false;
  if (p.nearest !== undefined && p.nearest !== true) return false;
  return true;
}

function checkRoute3(route) {
  if (!isTable(route)) return "the route data is not a table";
  if (route.format !== FORMAT) {
    return `it is in format ${String(route.format === undefined ? 1 : route.format)} and this version of the addon reads format ${FORMAT}`;
  }
  const problems = [];
  const add = (text) => problems.push(text);

  // R1
  const race = route.race, faction = route.faction;
  const raceOk = typeof race === "string" && Object.prototype.hasOwnProperty.call(RACES, race);
  if (typeof race !== "string") add("race must be a race name");
  else if (!raceOk) add(`unknown race ${quoted(race)}`);
  if (typeof faction !== "string") add('faction must be "Alliance" or "Horde"');
  else if (!FACTIONS.has(faction)) add(`unknown faction ${quoted(faction)}`);
  else if (raceOk && RACES[race] !== faction) add(`race ${quoted(race)} is not of faction ${quoted(faction)}`);

  // R2
  const sections = route.sections;
  if (!isArray(sections) || sections.length === 0) {
    add("sections must be a list of at least one section");
    return finish(problems);
  }
  const ids = new Map(); // id -> index of the first section with it
  let starts = 0;
  sections.forEach((s, i) => {
    if (!isTable(s)) return;
    if (typeof s.id === "string" && !ids.has(s.id)) ids.set(s.id, i);
    if (s.start === true) starts += 1;
  });
  if (starts !== 1) add(`it has ${starts} start sections; exactly one must have start = true`);

  // R4: the sections next leads to, from the first section of each id; loop sections break a cycle
  const edges = new Map();
  for (const [id, i] of ids) {
    const s = sections[i];
    const out = [];
    if (isArray(s.next)) for (const n of s.next) if (isTable(n) && typeof n.section === "string" && ids.has(n.section)) out.push(n.section);
    edges.set(id, out);
  }
  const cycles = (from) => {
    const seen = new Set();
    const stack = [...edges.get(from)];
    while (stack.length > 0) {
      const id = stack.pop();
      if (id === from) return true;
      if (seen.has(id)) continue;
      seen.add(id);
      if (sections[ids.get(id)].loop === true) continue;
      stack.push(...edges.get(id));
    }
    return false;
  };

  sections.forEach((s, i) => checkSection(s, i, sections, ids, cycles, add));
  return finish(problems);
}

function finish(problems) {
  if (problems.length === 0) return null;
  const shown = problems.slice(0, MAX_SHOWN).join("; ");
  return problems.length > MAX_SHOWN ? `${shown}; and ${problems.length - MAX_SHOWN} more` : shown;
}

const sectionLabel = (s, i) => (isTable(s) && typeof s.id === "string" && s.id !== "" ? `section ${s.id}` : `section #${i + 1}`);
const stepLabel = (st, i) => (isTable(st) && typeof st.id === "string" && st.id !== "" ? `step ${st.id}` : `step #${i + 1}`);

function checkCondition(when, where, add) {
  if (when === undefined) return;
  if (!isTable(when)) return add(`${where}when must be a table`);
  for (const key of sortedKeys(when)) {
    if (!CONDITION_KEYS.has(key)) add(`${where}when has the unknown key ${quoted(key)}`);
  }
  for (const key of ["class", "notClass", "race", "notRace"]) {
    const v = when[key];
    if (v === undefined) continue;
    const isClass = key === "class" || key === "notClass";
    const known = (x) => typeof x === "string" && (isClass ? CLASSES.has(x) : Object.prototype.hasOwnProperty.call(RACES, x));
    const list = isArray(v) ? v : [v];
    if (isArray(v) && v.length === 0) add(`${where}when.${key} must not be an empty list`);
    for (const x of list) {
      if (typeof x === "string") {
        if (!known(x)) add(`${where}when.${key} ${quoted(x)} is not ${isClass ? "a class token" : "a race"}`);
      } else {
        add(`${where}when.${key} must be ${isClass ? "a class token or a list of them" : "a race or a list of them"}`);
        break;
      }
    }
  }
  if (when.profession !== undefined && !isId(when.profession)) add(`${where}when.profession must be a positive whole number`);
}

// Checks the fields of a line or a skip condition by its spec; `labels` for jump.
function checkFields(t, spec, common, where, what, add) {
  const allowed = new Set([...common, ...spec.map((f) => f.name)]);
  for (const key of sortedKeys(t)) {
    if (!allowed.has(key)) add(`${where}has the unknown key ${quoted(key)}`);
  }
  for (const f of spec) {
    const v = t[f.name];
    if (v === undefined) {
      if (f.need) add(`${where}${what} needs ${f.name}`);
      continue;
    }
    const field = `${where}${f.name}`;
    switch (f.kind) {
      case "id": if (!isId(v)) add(`${field} must be a positive whole number`); break;
      case "ids": if (!isArray(v) || !v.every(isId)) add(`${field} must be a list of positive whole numbers`); break;
      case "place": if (!isPlace(v)) add(`${field} is not a valid place`); break;
      case "bool": if (typeof v !== "boolean") add(`${field} must be true or false`); break;
      case "text":
        if (typeof v !== "string") add(`${field} must be a string`);
        else if (bytes(v) > MAX_TEXT) add(`${field} is longer than ${MAX_TEXT} characters`);
        break;
      case "class": if (!(typeof v === "string" && CLASSES.has(v))) add(`${field} must be a class token`); break;
      case "whole": if (!(isWhole(v) && v >= f.lo && v <= f.hi)) add(`${field} must be a whole number from ${f.lo} to ${f.hi}`); break;
      case "number": if (!inRange(v, f.lo, f.hi)) add(`${field} must be a number from ${f.lo} to ${f.hi}`); break;
      case "mode": if (!MODES.includes(v)) add(`${field} must be one of ${MODES.join(", ")}`); break;
      case "buy": if (!(isTable(v) && isId(v.item) && isId(v.count))) add(`${field} must be { item, count } with positive whole numbers`); break;
      default: throw new Error(`unknown field kind ${f.kind}`);
    }
  }
}

function checkLine(line, j, where, add) {
  const at = `${where}line ${j + 1} `;
  if (!isTable(line)) return add(`${at}is not a table`);
  if (typeof line.kind !== "string") return add(`${at}needs a kind`);
  if (!Object.prototype.hasOwnProperty.call(LINES, line.kind)) return add(`${at}has the unknown kind ${quoted(line.kind)}`);
  checkFields(line, LINES[line.kind], LINE_COMMON, at, line.kind, add);
  if (line.kind === "train") {
    const forms = line.spell !== undefined || (line.skill !== undefined && line.rank !== undefined) || (line.class !== undefined && line.level !== undefined);
    if (!forms) add(`${at}train needs spell, skill and rank, or class and level`);
  }
  if (line.kind !== "goto" && line.kind !== "transport" && line.at !== undefined && !isPlace(line.at)) add(`${at}at is not a valid place`);
  checkCondition(line.when, at, add);
}

function checkSkip(entry, k, where, labels, add) {
  const at = `${where}skip ${k + 1} `;
  if (!isTable(entry)) return add(`${at}is not a table`);
  if (typeof entry.kind !== "string") return add(`${at}needs a kind`);
  if (!Object.prototype.hasOwnProperty.call(SKIPS, entry.kind)) return add(`${at}has the unknown kind ${quoted(entry.kind)}`);
  checkFields(entry, SKIPS[entry.kind], SKIP_COMMON, at, entry.kind, add);
  if (entry.jump !== undefined) {
    if (typeof entry.jump !== "string") add(`${at}jump must be a label`);
    else if (!labels.has(entry.jump)) add(`${at}jump names the missing label ${quoted(entry.jump)}`);
  }
}

function checkSection(s, i, sections, ids, cycles, add) {
  const where = `${sectionLabel(s, i)} `;
  if (!isTable(s)) return add(`${where}is not a table`);
  // R2
  if (typeof s.id !== "string" || !SECTION_ID.test(s.id)) add(`${where}id must be made of a-z, 0-9 and -`);
  else if (ids.get(s.id) !== i) add(`${where}id is used twice`);
  if (s.start !== undefined && s.start !== true) add(`${where}start must be true or left out`);
  // R3
  const nameOk = (v) => typeof v === "string" && NAME.some((re) => re.test(v));
  if (!nameOk(s.name)) add(`${where}name must look like "1-6 Zone" or "6 Zone"`);
  if (s.names !== undefined) {
    if (!isTable(s.names)) add(`${where}names must be a table of class tokens`);
    else for (const key of sortedKeys(s.names)) {
      if (!CLASSES.has(key)) add(`${where}names has the key ${quoted(key)}, which is not a class token`);
      else if (!nameOk(s.names[key])) add(`${where}names.${key} must look like "1-6 Zone" or "6 Zone"`);
    }
  }
  if (!(typeof s.group === "string" && GROUPS.has(s.group))) add(`${where}group must be "Alliance" or "Horde"`);
  const minOk = isWhole(s.minLevel) && s.minLevel >= 1 && s.minLevel <= MAX_LEVEL;
  if (!minOk) add(`${where}minLevel must be a whole number from 1 to ${MAX_LEVEL}`);
  const maxOk = s.maxLevel === undefined || (isWhole(s.maxLevel) && s.maxLevel >= 1 && s.maxLevel <= MAX_LEVEL);
  if (!maxOk) add(`${where}maxLevel must be a whole number from 1 to ${MAX_LEVEL}`);
  if (minOk && maxOk && s.maxLevel !== undefined && s.minLevel > s.maxLevel) add(`${where}minLevel is above maxLevel`);
  if (minOk) {
    const band = s.minLevel < 20 ? "1-20" : `${Math.floor(s.minLevel / 10) * 10}-${Math.floor(s.minLevel / 10) * 10 + 10}`;
    if (s.subgroup !== band) add(`${where}subgroup must be "${band}"`);
  } else if (typeof s.subgroup !== "string") {
    add(`${where}subgroup must be a level band like "1-20"`);
  }
  if (!isId(s.zone)) add(`${where}zone must be a positive whole number`);
  checkCondition(s.when, where, add);
  if (s.loop !== undefined && s.loop !== true) add(`${where}loop must be true or left out`);
  if (s.noAuto !== undefined && !(isArray(s.noAuto) && s.noAuto.every(isId))) add(`${where}noAuto must be a list of positive whole numbers`);
  // R4
  if (s.next !== undefined && !isArray(s.next)) add(`${where}next must be a list`);
  else if (s.next !== undefined) s.next.forEach((n, k) => {
    const at = `${where}next ${k + 1} `;
    if (!isTable(n)) return add(`${at}is not a table`);
    if (typeof n.section !== "string") add(`${at}needs section`);
    else if (!ids.has(n.section)) add(`${at}names the missing section ${quoted(n.section)}`);
    checkCondition(n.when, at, add);
  });
  if (typeof s.id === "string" && ids.get(s.id) === i && s.loop !== true && cycles(s.id)) {
    add(`${where}next leads back to this section and no section on the way has loop`);
  }
  // R5
  const steps = s.steps;
  if (!isArray(steps) || steps.length < 1 || steps.length > MAX_STEPS) {
    add(`${where}steps must hold 1 to ${MAX_STEPS} steps`);
    if (!isArray(steps)) return;
  }
  const stepIds = new Map();
  const labels = new Map(); // label -> index of the first step with it
  steps.forEach((st, k) => {
    if (!isTable(st)) return;
    if (typeof st.id === "string" && !stepIds.has(st.id)) stepIds.set(st.id, k);
    if (typeof st.label === "string" && !labels.has(st.label)) labels.set(st.label, k);
  });
  steps.forEach((st, k) => checkStep(st, k, where, stepIds, labels, ids, add));
}

function checkStep(st, k, sectionWhere, stepIds, labels, sectionIds, add) {
  const where = `${sectionWhere}${stepLabel(st, k)} `;
  if (!isTable(st)) return add(`${where}is not a table`);
  // R5
  if (typeof st.id !== "string" || !STEP_ID.test(st.id)) add(`${where}id must be made of letters, digits and . - + @ # :`);
  else if (stepIds.get(st.id) !== k) add(`${where}id is used twice`);
  // R7
  const allowed = new Set(STEP_KEYS);
  for (const key of sortedKeys(st)) {
    if (!allowed.has(key)) add(`${where}has the unknown key ${quoted(key)}`);
  }
  // R6
  if (st.at !== undefined && !isPlace(st.at)) add(`${where}at is not a valid place`);
  // R8
  if (st.text !== undefined) {
    if (typeof st.text !== "string") add(`${where}text must be a string`);
    else if (bytes(st.text) > MAX_TEXT) add(`${where}text is longer than ${MAX_TEXT} characters`);
  }
  if (st.title !== undefined) {
    if (typeof st.title !== "string") add(`${where}title must be a string`);
    else if (bytes(st.title) > MAX_TITLE) add(`${where}title is longer than ${MAX_TITLE} characters`);
  }
  // R7
  if (!isArray(st.lines) || st.lines.length === 0) add(`${where}lines must hold at least one line`);
  else st.lines.forEach((line, j) => checkLine(line, j, where, add));
  // R9
  checkCondition(st.when, where, add);
  const level = (v) => isWhole(v) && v >= 1 && v <= MAX_LEVEL;
  if (st.minLevel !== undefined && !level(st.minLevel)) add(`${where}minLevel must be a whole number from 1 to ${MAX_LEVEL}`);
  if (st.maxLevel !== undefined && !level(st.maxLevel)) add(`${where}maxLevel must be a whole number from 1 to ${MAX_LEVEL}`);
  if (level(st.minLevel) && level(st.maxLevel) && st.minLevel > st.maxLevel) add(`${where}minLevel is above maxLevel`);
  // R10
  if (st.label !== undefined) {
    if (typeof st.label !== "string" || !LABEL.test(st.label)) add(`${where}label must be made of letters, digits and _`);
    else if (labels.get(st.label) !== k) add(`${where}label is used twice`);
  }
  if (st.requires !== undefined) {
    if (typeof st.requires !== "string") add(`${where}requires must be a label`);
    else if (!labels.has(st.requires)) add(`${where}requires names the missing label ${quoted(st.requires)}`);
  }
  if (st.reminder !== undefined) {
    const ends = isTable(st.reminder) ? st.reminder.ends : undefined;
    if (typeof ends !== "string") add(`${where}reminder must be { ends = "next" or a label }`);
    else if (ends !== "next") {
      if (!labels.has(ends)) add(`${where}reminder ends at the missing label ${quoted(ends)}`);
      else if (labels.get(ends) <= k) add(`${where}reminder ends at ${quoted(ends)}, which is not a later step`);
    }
  }
  // R9
  if (st.skip !== undefined) {
    if (!isArray(st.skip)) add(`${where}skip must be a list of skip conditions`);
    else st.skip.forEach((entry, j) => checkSkip(entry, j, where, labels, add));
  }
  // R10
  if (st.load !== undefined) {
    if (typeof st.load !== "string") add(`${where}load must be a section id`);
    else if (!sectionIds.has(st.load)) add(`${where}load names the missing section ${quoted(st.load)}`);
  }
  // R12
  if (st.items !== undefined && !(isArray(st.items) && st.items.every(isId))) add(`${where}items must be a list of positive whole numbers`);
  if (st.targets !== undefined) {
    if (!isTable(st.targets)) add(`${where}targets must be { enemy = { ... }, friend = { ... } }`);
    else {
      for (const key of sortedKeys(st.targets)) {
        if (key !== "enemy" && key !== "friend") add(`${where}targets has the unknown key ${quoted(key)}`);
      }
      for (const key of ["enemy", "friend"]) {
        const v = st.targets[key];
        if (v !== undefined && !(isArray(v) && v.every(isId))) add(`${where}targets.${key} must be a list of positive whole numbers`);
      }
    }
  }
  // R11
  if (st.path !== undefined) {
    if (st.at === undefined) add(`${where}path needs at`);
    const p = st.path;
    const pointsOk = isTable(p) && isArray(p.points) && p.points.length > 0
      && p.points.every((pt) => isTable(pt) && inRange(pt.x, 0, 100) && inRange(pt.y, 0, 100));
    if (!pointsOk) add(`${where}path must have points { x, y } from 0 to 100`);
    if (isTable(p) && p.loop !== undefined && p.loop !== true) add(`${where}path loop must be true or left out`);
  }
}

module.exports = { checkRoute3, RULES, FORMAT };
