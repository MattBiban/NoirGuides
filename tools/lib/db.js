// Noir Guides, GPLv3. See LICENSE.
const fs = require("fs");
const path = require("path");
const { readCsv } = require("./csv");
const { CLASS_SORTS, ALL_CLASSES, SKYBORNE_CONTINENT, classMask, maskAnd, maskOr, isleRaces } = require("./characters");

// The merchant bit of QuestieDB npcFlags (the classic client's NPC flags: 1 gossip, 2 quest giver, 4 vendor, 8 flight
// master, 16 trainer, 128 innkeeper, 16384 repair). The data agrees: "General Goods Vendor" and "Trade Supplies" NPCs
// carry 4, weaponsmiths and armorers 16388 (vendor and repair), innkeepers 135.
const VENDOR_FLAG = 4;

// QuestieDB lists are arrays, or objects keyed "1".."n" (1-based) when sparse.
const slot = (v, i) => (!v ? [] : Array.isArray(v) ? v[i] || [] : v[String(i + 1)] || []);
const ids = (list) => (list || []).map((e) => (Array.isArray(e) ? e[0] : e)).filter((n) => typeof n === "number");

// A table keyed by area ID. The exporter writes a Lua table whose keys run 1..n as a JSON array, which happens for
// Dun Morogh (area 1): index i is area i + 1.
function areaMap(v) {
  if (!v) return {};
  if (!Array.isArray(v)) return v;
  const out = {};
  v.forEach((list, i) => { if (list) out[i + 1] = list; });
  return out;
}

function normalizeQuest(id, raw) {
  const z = raw.zoneOrSort || 0;
  return {
    id: +id, name: raw.name || "", level: raw.questLevel || 0, minLevel: raw.requiredLevel || 0,
    races: raw.requiredRaces || 0, classes: raw.requiredClasses || 0,
    preAny: raw.preQuestSingle || [], preAll: raw.preQuestGroup || [], exclusive: raw.exclusiveTo || [],
    zone: z > 0 ? z : 0, sort: z < 0 ? z : 0,
    starts: { npcs: ids(slot(raw.startedBy, 0)), objects: ids(slot(raw.startedBy, 1)), items: ids(slot(raw.startedBy, 2)) },
    ends: { npcs: ids(slot(raw.finishedBy, 0)), objects: ids(slot(raw.finishedBy, 1)) },
    objectives: { npcs: ids(slot(raw.objectives, 0)), objects: ids(slot(raw.objectives, 1)), items: ids(slot(raw.objectives, 2)) },
    // kill credit objectives (QuestieDB objectives slot 5: [[creature IDs], credited creature, text, ...]): any of the
    // creatures counts for the one objective, which the game credits to the credited creature (sometimes a stand-in
    // outside the list). { npcs, credit }; credit 0 when the data gives none
    killCredit: slot(raw.objectives, 4).filter((e) => Array.isArray(e) && Array.isArray(e[0]))
      .map((e) => ({ npcs: e[0].filter((n) => typeof n === "number"), credit: typeof e[1] === "number" ? e[1] : 0 }))
      .filter((k) => k.npcs.length),
    // the items the quest gives or asks the player to carry (QuestieDB sourceItemId, requiredSourceItems)
    sourceItem: raw.sourceItemId || 0, sourceItems: raw.requiredSourceItems || [],
    // the quest log's objective text (QuestieDB objectivesText) as one string; step texts read counts from it
    objectivesText: Array.isArray(raw.objectivesText) ? raw.objectivesText.join(" ") : typeof raw.objectivesText === "string" ? raw.objectivesText : "",
    trigger: raw.triggerEnd ? { text: raw.triggerEnd[0], spawns: areaMap(raw.triggerEnd[1]) } : null,
    repeatable: ((raw.specialFlags || 0) & 1) === 1,
    gated: !!(raw.requiredSkill || raw.requiredMinRep || raw.requiredMaxRep || raw.requiredSpell || raw.requiredSpecialization || raw.requiredRanks || raw.parentQuest),
    // conditions that take a quest away again (QuestieDB's field notes): a level cap; a quest that switches this one off
    // while it is in the log; a quest whose turn-in ends this one's availability; a quest that must be taken first
    maxLevel: raw.requiredMaxLevel || 0, disabledBy: raw.disabledByQuest || 0,
    availableUntil: raw.availableUntilCompleted || 0, availableAfter: raw.availableStartingWith || 0,
    asData: { races: raw.requiredRaces || 0, classes: raw.requiredClasses || 0 }, // the masks as fetched, before applyDataRules
    inferred: {},                                                                 // which mask a rule set, and why
  };
}

// true when the quest is handed out on the Skyborne isle: every giver with a known position stands there, or, when no
// giver has a position (an item drop, a missing spawn), the quest is filed under an isle area
function startsOnIsle(db, q) {
  const onIsle = (area) => { const a = db.areas.get(+area); return !!a && a.continent === SKYBORNE_CONTINENT; };
  const areas = [];
  for (const id of q.starts.npcs) areas.push(...Object.keys((db.npcs.get(id) || {}).spawns || {}));
  for (const id of q.starts.objects) areas.push(...Object.keys((db.objects.get(id) || {}).spawns || {}));
  return areas.length ? areas.every(onIsle) : onIsle(q.zone);
}
// The classes a quest is open to when the data gives it no class mask but its prerequisites do: 0 = no restriction.
function inheritedClasses(db, q) {
  const mask = (id) => { const p = db.quests.get(id); return p ? p.classes : 0; };
  let out = 0;
  // any one of preAny is enough: restricted only when every one of them is, to all their classes together
  if (q.preAny.length && q.preAny.every((id) => mask(id))) out = q.preAny.reduce((sum, id) => maskOr(sum, mask(id)), 0);
  // all of preAll are needed: every restricted one narrows it
  for (const id of q.preAll) if (mask(id)) out = out ? maskAnd(out, mask(id)) : mask(id);
  return out === ALL_CLASSES ? 0 : out;
}
// Fills in what the fetched data leaves out, from the data's own evidence (docs/routes/DATA-NOTES.md lists every quest
// each rule touches). It never changes a class mask the data has and never invents a restriction from a quest's name.
//   races:   quests that start on the Skyborne isle are for the Skyborne races (isleRaces)
//   classes: a quest filed under a class's quest sort is that class's quest; a quest that can only be reached through
//            class quests is open to those classes only
// Running it again changes nothing.
function applyDataRules(db) {
  for (const q of db.quests.values()) {
    if (startsOnIsle(db, q)) {
      const races = isleRaces(q.asData.races);
      if (races !== q.asData.races) { q.races = races; q.inferred.races = "starts on the Skyborne isle"; }
    }
    if (!q.asData.classes && CLASS_SORTS[q.sort]) { q.classes = classMask(CLASS_SORTS[q.sort]); q.inferred.classes = "class quest sort"; }
  }
  // Inherited classes are worked out again on every pass until nothing moves, so the result does not depend on the
  // order the quests are read in. Real chains settle in a few passes; the limit only stops a loop of prerequisites.
  const inherits = [...db.quests.values()].filter((q) => !q.asData.classes && !CLASS_SORTS[q.sort] && q.preAny.length + q.preAll.length > 0);
  for (let pass = 1, changed = true; changed; pass++) {
    if (pass > 100) throw new Error("class inheritance did not settle: the prerequisites form a loop");
    changed = false;
    for (const q of inherits) {
      const classes = inheritedClasses(db, q);
      if (classes === q.classes) continue;
      q.classes = classes;
      if (classes) q.inferred.classes = "every prerequisite path is a class quest";
      else delete q.inferred.classes;
      changed = true;
    }
  }
  return db;
}

function loadDb(dataDir) {
  const raw = JSON.parse(fs.readFileSync(path.join(dataDir, "forever_db.json"), "utf8"));
  const era = JSON.parse(fs.readFileSync(path.join(dataDir, "vanilla_db.json"), "utf8"));
  const db = { quests: new Map(), npcs: new Map(), objects: new Map(), items: new Map(), areas: new Map(), maps: new Map(), taxi: [], eraQuestIds: new Set() };
  for (const [id, q] of Object.entries(raw.Quest)) db.quests.set(+id, normalizeQuest(id, q));
  // subName: the title under the name ("Warrior Trainer", "Journeyman Blacksmith"), "" when there is none
  // vendor: QuestieDB npcFlags has the merchant bit (VENDOR_FLAG): the NPC buys and sells items
  for (const [id, n] of Object.entries(raw.Npc)) db.npcs.set(+id, { id: +id, name: n.name || "", friendly: n.friendlyToFaction || "", subName: n.subName || "",
    vendor: ((n.npcFlags || 0) & VENDOR_FLAG) !== 0, spawns: areaMap(n.spawns) });
  for (const [id, o] of Object.entries(raw.Object)) db.objects.set(+id, { id: +id, name: o.name || "", spawns: areaMap(o.spawns) });
  // otherSources: the item is also sold by a vendor or found inside another item, so a drop is not the only way to it
  for (const [id, i] of Object.entries(raw.Item)) db.items.set(+id, { id: +id, name: i.name || "", npcDrops: i.npcDrops || [], objectDrops: i.objectDrops || [],
    otherSources: !!((i.vendors && i.vendors.length) || (i.itemDrops && i.itemDrops.length)) });
  for (const id of Object.keys(era.Quest)) db.eraQuestIds.add(+id);
  const wago = (name) => readCsv(path.join(dataDir, "wago", name + ".csv"));
  for (const a of wago("AreaTable")) db.areas.set(+a.ID, { id: +a.ID, name: a.AreaName_lang, parent: +a.ParentAreaID, continent: +a.ContinentID });
  // world bounds of each zone map: the full-map assignment row (UiMin 0,0 to UiMax 1,1) with the lowest OrderIndex.
  // The file is not sorted by OrderIndex, so the lowest is tracked; of equal ones the first read stays.
  const order = new Map();
  for (const m of wago("UiMapAssignment")) {
    if (+m.UiMin_0 !== 0 || +m.UiMin_1 !== 0 || +m.UiMax_0 !== 1 || +m.UiMax_1 !== 1 || +m.AreaID === 0) continue;
    if (order.has(+m.AreaID) && order.get(+m.AreaID) <= +m.OrderIndex) continue;
    order.set(+m.AreaID, +m.OrderIndex);
    db.maps.set(+m.AreaID, { area: +m.AreaID, uiMap: +m.UiMapID, minX: +m.Region_0, minY: +m.Region_1, maxX: +m.Region_3, maxY: +m.Region_4 });
  }
  for (const t of wago("TaxiNodes")) db.taxi.push({ id: +t.ID, name: t.Name_lang, x: +t.Pos_0, y: +t.Pos_1, continent: +t.ContinentID });
  return applyDataRules(db);
}
module.exports = { loadDb, normalizeQuest, areaMap, applyDataRules, VENDOR_FLAG };
