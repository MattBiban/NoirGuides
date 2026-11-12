// Noir Guides, GPLv3. See LICENSE.
const path = require("path");
const { readCsv } = require("./csv");

// Class IDs: the client's ChrClasses. The class mask bit is id - 1.
const CLASSES = { WARRIOR: 1, PALADIN: 2, HUNTER: 3, ROGUE: 4, PRIEST: 5, SHAMAN: 7, MAGE: 8, WARLOCK: 9, DRUID: 11 };
const classMask = (cls) => 2 ** (CLASSES[cls] - 1);
const ALL_CLASSES = Object.keys(CLASSES).reduce((sum, cls) => sum + classMask(cls), 0); // 1503: a mask this wide restricts nothing
// The quest sorts the client files class quests under (QuestSort IDs, as named in QuestieDB's sort enum).
const CLASS_SORTS = { [-61]: "WARLOCK", [-81]: "WARRIOR", [-82]: "SHAMAN", [-141]: "PALADIN", [-161]: "MAGE", [-162]: "ROGUE",
  [-261]: "HUNTER", [-262]: "PRIEST", [-263]: "DRUID" };
// Race IDs and PlayableRaceBit: the client's ChrRaces. Start areas: AreaTable (1 Dun Morogh, 12 Elwynn Forest, 14 Durotar,
// 85 Tirisfal Glades, 141 Teldrassil, 215 Mulgore, 16593 Zephras Isle). Skyborne are two client races, one per faction.
const RACES = {
  Human: { id: 1, bit: 0, faction: "Alliance", startArea: 12 },
  Orc: { id: 2, bit: 1, faction: "Horde", startArea: 14 },
  Dwarf: { id: 3, bit: 2, faction: "Alliance", startArea: 1 },
  NightElf: { id: 4, bit: 3, faction: "Alliance", startArea: 141 },
  Undead: { id: 5, bit: 4, faction: "Horde", startArea: 85 },
  Tauren: { id: 6, bit: 5, faction: "Horde", startArea: 215 },
  Gnome: { id: 7, bit: 6, faction: "Alliance", startArea: 1 },
  Troll: { id: 8, bit: 7, faction: "Horde", startArea: 14 },
  HighOrder: { id: 95, bit: 32, faction: "Alliance", startArea: 16593 },
  Windshaper: { id: 96, bit: 33, faction: "Horde", startArea: 16593 },
};
// Masks reach bit 33, past what JS bitwise operators keep. A negative mask is two's complement (-1 = everyone).
const hasBit = (mask, bit) => ((BigInt.asUintN(64, BigInt(mask)) >> BigInt(bit)) & 1n) === 1n;
// Masks are sums of powers of two, and adding them is exact far past bit 33. These stand in for the operators & and |.
const bitsOf = (mask) => { const out = []; for (let bit = 0; bit < 40; bit++) if (hasBit(mask, bit)) out.push(bit); return out; };
const maskOf = (bits) => [...new Set(bits)].reduce((sum, bit) => sum + 2 ** bit, 0);
const maskAnd = (a, b) => maskOf(bitsOf(a).filter((bit) => hasBit(b, bit)));
const maskOr = (a, b) => maskOf([...bitsOf(a), ...bitsOf(b)]);

// The Skyborne start on Zephras Isle, which is its own continent (map 2991 in AreaTable).
const SKYBORNE_CONTINENT = 2991;
const HIGH_ORDER = 2 ** RACES.HighOrder.bit, WINDSHAPER = 2 ** RACES.Windshaper.bit;
// Who may take a quest that starts on the isle, from the race mask the data gives it. docs/routes/DATA-NOTES.md has the
// evidence: only the Skyborne are ever on the isle; a shared quest carries no mask or the lone High Order bit (Horde-only
// isle quests require such quests, so the lone bit cannot mean the Alliance race alone); a faction's own quest names
// its Skyborne race, or, in two quests, only another race of that faction.
function isleRaces(mask) {
  if (!mask || mask === HIGH_ORDER) return HIGH_ORDER + WINDSHAPER;
  const named = maskAnd(mask, HIGH_ORDER + WINDSHAPER);
  if (named) return named;
  const factions = new Set(Object.values(RACES).filter((r) => hasBit(mask, r.bit)).map((r) => r.faction));
  return (factions.has("Alliance") ? HIGH_ORDER : 0) + (factions.has("Horde") ? WINDSHAPER : 0);
}

function character(race, cls) {
  const r = RACES[race];
  if (!r || !CLASSES[cls]) throw new Error(`unknown character ${race} ${cls}`);
  return { race, cls, faction: r.faction, raceBit: r.bit, classId: CLASSES[cls], startArea: r.startArea };
}
function combos(dataDir) {
  const out = [];
  for (const row of readCsv(path.join(dataDir, "wago", "CharBaseInfo.csv"))) {
    const race = Object.keys(RACES).find((k) => RACES[k].id === +row.RaceID);
    const cls = Object.keys(CLASSES).find((k) => CLASSES[k] === +row.ClassID);
    if (race && cls) out.push(character(race, cls));
  }
  return out.sort((a, b) => a.race.localeCompare(b.race) || a.cls.localeCompare(b.cls));
}
const eligible = (quest, ch) =>
  (!quest.races || hasBit(quest.races, ch.raceBit)) && (!quest.classes || hasBit(quest.classes, ch.classId - 1));

module.exports = { CLASSES, RACES, CLASS_SORTS, ALL_CLASSES, SKYBORNE_CONTINENT, HIGH_ORDER, WINDSHAPER, classMask, hasBit, maskAnd, maskOr,
  isleRaces, character, combos, eligible };
