// Noir Guides, GPLv3. See LICENSE.
// Pacing: how much XP and time the planner expects a step to give and take. The planner and the validator both
// replay a route with these functions, so they agree on the level at every step; the engine reads the real XP in
// the game and never sees these numbers.
const { zoneOf } = require("./geo");

// XP needed to finish each level 1-59: the classic client's level table (what UnitXPMax reports).
const XP_TO_LEVEL = [0, 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900, 14400, 16000, 17700, 19400,
  21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400, 50800, 54500, 58600, 62800, 67100, 71600,
  76100, 80800, 85700, 90700, 95800, 101000, 106300, 111800, 117500, 123200, 129100, 135100, 141200, 147500, 153900, 160400,
  167100, 173900, 180800, 187900, 195000, 202300, 209800];

// Every estimate of the pace, and where it comes from. None of them is in the fetched data. They decide which zone
// comes when and how long a route is said to take; a wrong one moves a zone a level earlier or later, it never makes
// a step impossible.
const PACE = Object.freeze({
  OBJECTIVE_KILLS: 8,     // kills behind one creature objective: a guess. Quests ask for 5 to 15 of a creature;
                          // lib/quests.js ranks objective places with the same 8
  ITEM_KILL_FACTOR: 2,    // an item objective takes this many times the kills: a guess. An item a quest asks for
                          // drops from about one creature in two, so eight of them are sixteen fights
  KILL_SECONDS: 30,       // one fight with a creature of the player's level and the way to the next: a guess
  INCIDENTAL_YARDS: 300,  // one fight for every 300 yards walked inside a zone with creatures worth fighting: a guess.
                          // At 7 yards a second that is a fight every 43 seconds of running between a zone's tasks
  WILD_SPAWNS: 300,       // measured: a zone with this many creature spawns that are friendly to neither faction is
                          // open country. The capital with the most has 247 (critters, neutral traders), the emptiest
                          // questing zone 364 (Riverglades); the peaceful places below it (Moonglade 119, Mount Hyjal
                          // 114) give no walking XP
  TALK_SECONDS: 10,       // accepting or turning in a quest, binding the hearthstone: a guess
  HEARTH_COOLDOWN: 3600,  // the hearthstone's cooldown in the original game: one hour
});

function gain(state, xp) {
  state.xp += xp;
  while (state.level < 60 && state.xp >= XP_TO_LEVEL[state.level]) { state.xp -= XP_TO_LEVEL[state.level]; state.level++; }
}

// XP for one kill: the original game's public formula. A creature of the player's level gives 45 + 5 x level; a
// higher one 5% more per level, up to four levels; a lower one loses an even share per level until it is grey.
const greyLevel = (level) => (level <= 5 ? 0 : level <= 39 ? level - 5 - Math.floor(level / 10) : level <= 59 ? level - 1 - Math.floor(level / 5) : level - 9);
const zeroDifference = (level) => (level <= 7 ? 5 : level <= 9 ? 6 : level <= 11 ? 7 : level <= 15 ? 8 : level <= 19 ? 9 : level <= 29 ? 11 :
  level <= 39 ? 12 : level <= 44 ? 13 : level <= 49 ? 14 : level <= 54 ? 15 : level <= 59 ? 16 : 17);
function mobXp(mobLevel, playerLevel) {
  const mob = Math.max(1, mobLevel);
  const base = 45 + 5 * playerLevel;
  if (mob >= playerLevel) return Math.round(base * (1 + 0.05 * Math.min(mob - playerLevel, 4)));
  if (mob <= greyLevel(playerLevel)) return 0;
  return Math.round(base * (1 - (playerLevel - mob) / zeroDifference(playerLevel)));
}

// Quest XP is not in the data. A quest is worth roughly a fixed share of its own level, less when it is below the
// player, nothing when grey (more than 8 levels under the player).
function questXp(questLevel, playerLevel) {
  const diff = playerLevel - questLevel;
  if (diff > 8) return 0;
  const base = questLevel <= 10 ? 60 * questLevel + 50 : 110 * questLevel - 500;
  const scale = diff <= 5 ? 1 : diff === 6 ? 0.8 : diff === 7 ? 0.6 : 0.4;
  return Math.round(base * scale);
}
// The fights of a quest's objectives: OBJECTIVE_KILLS creatures of the quest's level for each creature objective,
// ITEM_KILL_FACTOR times as many for each item objective. An object to click or a place to find has no fight of
// its own.
const fights = (quest) => (quest.objectives.npcs.length + quest.objectives.items.length * PACE.ITEM_KILL_FACTOR) * PACE.OBJECTIVE_KILLS;
const objectiveXp = (quest, playerLevel) => fights(quest) * mobXp(quest.level, playerLevel);
// The time an objective takes on the spot: its fights, or one talk's worth for an object or a place.
const objectiveSeconds = (quest) => (fights(quest) ? fights(quest) * PACE.KILL_SECONDS : PACE.TALK_SECONDS);

// The levels of each zone's creatures, as far as the data tells: the 20th to 80th percentile of the levels of the
// quests filed under the zone, and whether the zone is open country (WILD_SPAWNS). Map of zone -> { min, max, wild }.
function zoneLevels(db) {
  const levels = new Map(), hostile = new Map();
  for (const q of db.quests.values()) {
    if (!q.zone || !(q.level >= 1 && q.level <= 60)) continue;
    const zone = zoneOf(db, q.zone);
    if (!zone) continue;
    if (!levels.has(zone)) levels.set(zone, []);
    levels.get(zone).push(q.level);
  }
  for (const npc of db.npcs.values()) {
    if (npc.friendly) continue;
    for (const [area, list] of Object.entries(npc.spawns || {})) {
      const zone = zoneOf(db, +area);
      if (zone) hostile.set(zone, (hostile.get(zone) || 0) + list.length);
    }
  }
  const out = new Map();
  for (const [zone, list] of levels) {
    list.sort((a, b) => a - b);
    const pick = (f) => list[Math.min(list.length - 1, Math.floor(f * list.length))];
    out.set(zone, { min: pick(0.2), max: pick(0.8), wild: (hostile.get(zone) || 0) >= PACE.WILD_SPAWNS });
  }
  return out;
}
// XP from the fights on the way: one for every INCIDENTAL_YARDS walked inside an open zone, against a creature of the
// zone's levels nearest the player's own. band is the zone's entry in zoneLevels, or nothing.
function walkXp(yards, band, playerLevel) {
  if (!band || !band.wild || !(yards > 0) || !Number.isFinite(yards)) return 0;
  const mob = Math.min(Math.max(playerLevel, band.min), band.max);
  return Math.round((yards / PACE.INCIDENTAL_YARDS) * mobXp(mob, playerLevel));
}
// One level of nothing but fights with creatures of the player's level: how long a grind step is said to take.
const grindSeconds = (level, xp) => Math.ceil(Math.max(0, XP_TO_LEVEL[level] - xp) / mobXp(level, level)) * PACE.KILL_SECONDS;

module.exports = { PACE, XP_TO_LEVEL, gain, mobXp, questXp, objectiveXp, objectiveSeconds, zoneLevels, walkXp, grindSeconds };
