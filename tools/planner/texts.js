// Noir Guides, GPLv3. See LICENSE.
// Step texts: the short instruction note a format 3 step may carry, written here from templates in Noir's own words
// (task P3 in docs/superpowers/plans/2026-11-11-guide-rebuild.md, spec 3.1). The engine builds every line's own text
// from the line and the names in Data/; a step's `text` only says what the lines cannot.
//
//   stepText(db, step, context) -> string | undefined
//       context = { previous: the step before (or undefined), section, faction }
//   compass(db, from, to) -> "north" | "northeast" | ... | "northwest" | undefined
//       the direction from one place to another by world position, in eight directions; undefined across continents,
//       for a zone without a place (x = y = 0) and for the same point
//
// Templates, by the step's first line of a moving kind, else by what the whole step does:
//   fly        "Fly from <node> to <node>."
//   transport  "Take the <mode> from <dock zone> to <destination zone>."
//   hearth     "Use your hearthstone to return to <bind place>."
//   goto       "Head <direction> into <zone>."                    only into a zone the previous step is not in
//   grind      "Kill creatures around <zone> until you reach level <L>."
//   objective  "<Name> is <direction> of <previous NPC or your last stop>." for one named creature, an object or an
//              item ("are" for a plural object or item name); "The <plural> are ..." for a kill objective that needs
//              more than one; "The <name> is ..." for one creature that is not a named one. Only when more than
//              FAR_YARDS from the previous step. The subject is the step's first objective line that names a creature,
//              object or item, else its first enemy target (the project lead's P3 follow-up 3).
//   plural(name) -> the English plural of a creature name (its last word, or the word before " of ")
// A named creature: the objective text names it without an article ("Kill Meven Korgal", against "tame an Ornery
// Galestrider" or "destroy the Cirrusfly Queen"); where the text does not name it, the creatures in the data with its
// name have at most NAMED_SPAWNS spawn points together. How
// many an objective needs is not in the data: it is read from the quest's objective text (a number before the
// creature's name, or its plural in the text, means more than one).
// Every text is at most MAX_TEXT bytes; a template that would be longer gives no text.
const { toPoint, distance } = require("../lib/geo");

const MAX_TEXT = 160;
const FAR_YARDS = 200;
const NAMED_SPAWNS = 3;
const DIRECTIONS = ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"];

const zoneOnly = (p) => p.x === 0 && p.y === 0;
const point = (db, p) => (p && !zoneOnly(p) ? toPoint(db, p.zone, p.x, p.y) : null);

function compass(db, from, to) {
  const a = point(db, from), b = point(db, to);
  if (!a || !b || a.continent !== b.continent) return undefined;
  // world x grows to the north and world y to the west
  const north = b.wx - a.wx, east = a.wy - b.wy;
  if (Math.hypot(north, east) < 1e-6) return undefined;
  const degrees = (Math.atan2(east, north) * 180) / Math.PI; // 0 north, 90 east
  return DIRECTIONS[((Math.round(degrees / 45) % 8) + 8) % 8];
}

const zoneName = (db, zone) => { const a = db.areas.get(zone); return a && a.name ? a.name : undefined; };
const nodeName = (db, id) => { const t = db.taxi.find((n) => n.id === id); return t && t.name ? t.name : undefined; };
const npcName = (db, id) => { const n = db.npcs.get(id); return n && n.name ? n.name : undefined; };
// the place a step stands for: its own, else its first line's
const placeOf = (step) => (step ? step.at || (step.lines.find((l) => l.at) || {}).at : undefined);
const fits = (text) => (text !== undefined && Buffer.byteLength(text, "utf8") <= MAX_TEXT ? text : undefined);

// English plurals of creature names: the last word, or the word before " of " ("Spirits of the Glade").
const SAME = new Set(["vermin", "sheep", "deer", "fish", "folk", "kin", "people", "swine", "moose", "trout", "kodo"]);
const MAN = new Set(["shaman", "human", "talisman", "caiman", "ottoman"]);
const VES = { wolf: "wolves", elf: "elves", thief: "thieves", dwarf: "dwarves", calf: "calves", half: "halves", leaf: "leaves", wife: "wives", knife: "knives", life: "lives" };
function pluralWord(word) {
  const lower = word.toLowerCase();
  const keep = (out) => (word[0] === word[0].toUpperCase() ? out[0].toUpperCase() + out.slice(1) : out);
  if (SAME.has(lower)) return word;
  if (VES[lower]) return keep(VES[lower]);
  if (/man$/.test(lower) && !MAN.has(lower)) return word.slice(0, -3) + "men";
  if (/[^aeiou]y$/.test(lower)) return word.slice(0, -1) + "ies";
  if (/(s|x|z|ch|sh)$/.test(lower)) return word + "es";
  return word + "s";
}
function plural(name) {
  const of = name.indexOf(" of ");
  const head = of > 0 ? name.slice(0, of) : name, tail = of > 0 ? name.slice(of) : "";
  const words = head.split(" ");
  words[words.length - 1] = pluralWord(words[words.length - 1]);
  return words.join(" ") + tail;
}
// a name that reads as a plural already ("Kodo Bones")
const looksPlural = (name) => /[^su]s$/i.test(name.split(" of ")[0]);

const spawnCount = (npc) => Object.values((npc && npc.spawns) || {}).reduce((sum, list) => sum + list.length, 0);
const nameCounts = new WeakMap();
function spawnsOfName(db, name) {
  // counted once per creature table (again when it has grown, as the tests' worlds do)
  let cached = nameCounts.get(db.npcs);
  if (!cached || cached.size !== db.npcs.size) {
    const counts = new Map();
    for (const n of db.npcs.values()) if (n && n.name) counts.set(n.name, (counts.get(n.name) || 0) + spawnCount(n));
    cached = { size: db.npcs.size, counts };
    nameCounts.set(db.npcs, cached);
  }
  return cached.counts.get(name) || 0;
}
const escape = (s) => s.replace(/[.*+?^(){}$|[\]\\]/g, "\\$&");
// whether the quest's objective text asks for more than one of a creature: a number above 1 within the four words
// before its name's first word, or the name in the plural
function needsMany(db, questId, name) {
  const q = questId !== undefined ? db.quests.get(questId) : null;
  const text = (q && q.objectivesText) || "";
  if (!text) return false;
  const many = plural(name);
  if (many !== name && new RegExp("\\b" + escape(many) + "\\b", "i").test(text)) return true;
  const first = name.split(" ")[0].toLowerCase();
  const words = text.split(/\s+/).map((w) => w.replace(/[^\w'-]/g, "").toLowerCase());
  for (let i = 0; i < words.length; i++) {
    if (!/^\d+$/.test(words[i]) || Number(words[i]) <= 1) continue;
    if (words.slice(i + 1, i + 5).includes(first)) return true;
  }
  return false;
}
// How the quest's objective text names a creature: "none" (a proper name), "a" (a, an, the, one) or undefined
// (not named there).
function articleOf(db, questId, name) {
  const q = questId !== undefined ? db.quests.get(questId) : null;
  const m = q && q.objectivesText ? new RegExp("(\\b\\w+\\s+)?\\b" + escape(name) + "\\b", "i").exec(q.objectivesText) : null;
  if (!m) return undefined;
  return m[1] && /^(a|an|the|one)\s+$/i.test(m[1]) ? "a" : "none";
}
// The subject of an objective step's text ("Meven Korgal is", "The Grey Wolves are", ...) or undefined.
function subject(db, step) {
  const creature = (id, quest) => {
    const npc = db.npcs.get(id);
    const name = npc && npc.name;
    if (!name) return undefined;
    if (needsMany(db, quest, name)) return "The " + plural(name) + " are";
    const article = articleOf(db, quest, name);
    const named = article ? article === "none" : spawnsOfName(db, name) <= NAMED_SPAWNS;
    return named ? name + " is" : "The " + name + " is";
  };
  const thing = (name) => (name ? name + (looksPlural(name) ? " are" : " is") : undefined);
  for (const l of step.lines) {
    if (l.kind !== "objective") continue;
    const s = l.npc !== undefined ? creature(l.npc, l.quest)
      : l.object !== undefined ? thing((db.objects.get(l.object) || {}).name)
        : l.item !== undefined ? thing((db.items.get(l.item) || {}).name) : undefined;
    if (s) return s;
  }
  const quest = (step.lines.find((l) => l.kind === "objective") || {}).quest;
  for (const id of (step.targets && step.targets.enemy) || []) { const s = creature(id, quest); if (s) return s; }
  return undefined;
}
// The NPC the previous step talks to, if any.
function previousNpc(db, step) {
  if (!step) return undefined;
  for (const l of step.lines) if (l.npc !== undefined && l.kind !== "objective") { const n = npcName(db, l.npc); if (n) return n; }
  return undefined;
}

function stepText(db, step, context = {}) {
  const previous = context.previous;
  const lines = step.lines || [];
  const fly = lines.find((l) => l.kind === "fly");
  if (fly) {
    const a = nodeName(db, fly.from), b = nodeName(db, fly.to);
    return a && b ? fits(`Fly from ${a} to ${b}.`) : undefined;
  }
  const boat = lines.find((l) => l.kind === "transport");
  if (boat) {
    const a = zoneName(db, boat.at.zone), b = zoneName(db, boat.to.zone);
    return a && b ? fits(`Take the ${boat.mode} from ${a} to ${b}.`) : undefined;
  }
  const hearth = lines.find((l) => l.kind === "hearth");
  if (hearth) {
    const name = zoneName(db, hearth.to.zone);
    return name ? fits(`Use your hearthstone to return to ${name}.`) : undefined;
  }
  const go = lines.find((l) => l.kind === "goto");
  if (go) {
    const from = placeOf(previous);
    if (!from || from.zone === go.at.zone) return undefined;
    const name = zoneName(db, go.at.zone);
    if (!name) return undefined;
    const way = compass(db, from, go.at);
    return fits(way ? `Head ${way} into ${name}.` : `Head into ${name}.`);
  }
  if (lines.length && lines.every((l) => l.kind === "grind")) {
    const at = placeOf(step);
    const name = zoneName(db, at ? at.zone : context.section && context.section.zone);
    const level = Math.max(...lines.map((l) => l.level));
    return name ? fits(`Kill creatures around ${name} until you reach level ${level}.`) : undefined;
  }
  if (lines.length && lines.every((l) => l.kind === "objective")) {
    const from = placeOf(previous), here = placeOf(step);
    const a = point(db, from), b = point(db, here);
    if (!a || !b || !(distance(a, b) > FAR_YARDS)) return undefined;
    const who = subject(db, step), way = compass(db, from, here);
    if (!who || !way) return undefined;
    return fits(`${who} ${way} of ${previousNpc(db, previous) || "your last stop"}.`);
  }
  return undefined;
}

module.exports = { stepText, compass, plural, MAX_TEXT, FAR_YARDS, NAMED_SPAWNS, DIRECTIONS };
