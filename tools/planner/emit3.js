// Noir Guides, GPLv3. See LICENSE.
// A format 3 route as the Lua text of its route file (task P3 in docs/superpowers/plans/2026-11-11-guide-rebuild.md,
// "Route format 3").
//
//   emitRoute3(route3) -> string
//       route3 = { id, format = 3, race, faction, sections }. Throws with checkRoute3's sentence when the route is not
//       valid. The text is deterministic: every table's keys in a fixed order, one block per section, one block per
//       step with one route line per text line, and the lists whose order means nothing sorted (accept requires,
//       noAuto, the class and race lists of conditions). The same route always gives the same bytes.
const fs = require("fs");
const path = require("path");
const { checkRoute3 } = require("./format3");

const LICENSE = "-- Noir Guides, GPLv3. See LICENSE.";
const release = () => JSON.parse(fs.readFileSync(path.join(__dirname, "..", "data_sources.json"), "utf8")).questiedb.release;

// Key orders. A key not listed comes after the listed ones, sorted (checkRoute3 refuses such keys anyway).
const ORDER = {
  section: ["id", "name", "names", "group", "subgroup", "minLevel", "maxLevel", "zone", "start", "when", "loop", "noAuto", "next", "steps"],
  step: ["id", "label", "title", "at", "text", "when", "minLevel", "maxLevel", "requires", "reminder", "skip", "load", "items", "targets", "path", "lines"],
  line: ["kind", "quest", "index", "item", "count", "node", "from", "to", "mode", "at", "level", "percent", "spell", "skill", "rank", "value", "class", "npc", "object",
    "buy", "reward", "cap", "ifDone", "requires", "manual", "skipIfMissing", "skipIfIncomplete", "enemy", "text", "when"],
  place: ["zone", "x", "y", "r", "nearest"],
  when: ["class", "notClass", "race", "notRace", "profession"],
  next: ["section", "when"],
  skip: ["kind", "quest", "level", "percent", "skill", "value", "item", "count", "zone", "jump"],
  targets: ["enemy", "friend"],
  path: ["points", "loop"],
  point: ["x", "y"],
  buy: ["item", "count"],
  reminder: ["ends"],
};
// The order hint of a value under a key of a table of some kind.
const CHILD = {
  section: { names: "names", when: "when", next: "next[]", steps: "step[]", noAuto: "sorted" },
  step: { at: "place", when: "when", reminder: "reminder", skip: "skip[]", targets: "targets", path: "path", lines: "line[]" },
  line: { at: "place", to: "place", when: "when", buy: "buy", requires: "sorted" },
  when: { class: "sorted", notClass: "sorted", race: "sorted", notRace: "sorted" },
  next: { when: "when" },
  path: { points: "point[]" },
};

const str = (s) => `"${String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\r/g, "\\r").replace(/\n/g, "\\n")}"`;
function num(n) {
  if (!Number.isFinite(n)) throw new Error(`the number ${n} cannot be written`);
  return String(n);
}
function keysOf(obj, kind) {
  const order = ORDER[kind] || [];
  const keys = Object.keys(obj).filter((k) => obj[k] !== undefined);
  const known = order.filter((k) => keys.includes(k));
  const rest = keys.filter((k) => !order.includes(k)).sort();
  return [...known, ...rest];
}
const byValue = (a, b) => (typeof a === "number" && typeof b === "number" ? a - b : String(a) < String(b) ? -1 : String(a) > String(b) ? 1 : 0);

// One value on one line.
function value(v, kind) {
  if (typeof v === "string") return str(v);
  if (typeof v === "number") return num(v);
  if (typeof v === "boolean") return String(v);
  if (Array.isArray(v)) {
    if (!v.length) return "{}";
    const items = kind === "sorted" ? v.slice().sort(byValue) : v;
    const of = kind && kind.endsWith("[]") ? kind.slice(0, -2) : undefined;
    return `{ ${items.map((x) => value(x, of)).join(", ")} }`;
  }
  if (v && typeof v === "object") {
    const keys = keysOf(v, kind);
    if (!keys.length) return "{}";
    return `{ ${fields(v, kind, keys).join(", ")} }`;
  }
  throw new Error(`a value of type ${typeof v} cannot be written`);
}
function fields(obj, kind, keys) {
  const child = CHILD[kind] || {};
  return keys.map((k) => `${k} = ${value(obj[k], child[k])}`);
}

function stepLua(step) {
  const keys = keysOf(step, "step").filter((k) => k !== "lines");
  const out = [`        { ${fields(step, "step", keys).join(", ")},`, "          lines = {"];
  for (const line of step.lines) out.push(`            ${value(line, "line")},`);
  out.push("          } },");
  return out;
}
function sectionLua(section) {
  const keys = keysOf(section, "section").filter((k) => k !== "steps" && k !== "next");
  const out = ["    {", `      ${fields(section, "section", keys).join(", ")},`];
  out.push(`      next = ${value(section.next || [], "next[]")},`);
  out.push("      steps = {");
  for (const step of section.steps) out.push(...stepLua(step));
  out.push("      },", "    },");
  return out;
}

function emitRoute3(route3) {
  const data = { format: route3.format, race: route3.race, faction: route3.faction, sections: route3.sections };
  const problem = checkRoute3(data);
  if (problem) throw new Error(`route ${route3.id} is not valid format 3: ${problem}`);
  return [
    LICENSE,
    `-- Generated by tools/build_routes.js from QuestieDB Forever ${release()}. Do not edit.`,
    `Noir.Route(${str(route3.id)}, {`,
    `  format = 3, race = ${str(route3.race)}, faction = ${str(route3.faction)},`,
    "  sections = {",
    ...route3.sections.flatMap(sectionLua),
    "  },",
    "})",
    "",
  ].join("\n");
}

module.exports = { emitRoute3 };
