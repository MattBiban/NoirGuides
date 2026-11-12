// Noir Guides, GPLv3. See LICENSE.
// The talent trees of the client (wago.tools Talent and TalentTab, names from SpellName) and the rules a build must
// keep to be learnable in the game, point by point:
//   * a character has one point at level 10 and one more each level, 51 at level 60;
//   * a talent in tier t (1-based) needs (t - 1) * 5 points already spent in its tree;
//   * a talent with a prerequisite needs that talent at the rank the data gives (PrereqRank, 0-based in the table);
//   * a talent takes at most as many points as it has ranks.
const path = require("path");
const { readCsv } = require("./csv");

const CLASS_TOKENS = { 1: "WARRIOR", 2: "PALADIN", 3: "HUNTER", 4: "ROGUE", 5: "PRIEST", 7: "SHAMAN", 8: "MAGE", 9: "WARLOCK", 11: "DRUID" };
const FIRST_LEVEL = 10; // the level of the first talent point
const POINTS = 51;      // points at level 60
const PER_TIER = 5;

// classToken -> { tabs: [ { id, name, talents: [ { id, name, tier, column, max, prereq, prereqRank } ] } ] }
// Tabs in the client's order (OrderIndex), talents by tier, then column. Tier and column are 1-based, as the game's
// talent functions count them. `name` is undefined when SpellName has no name for any of the talent's ranks.
function loadTrees(dataDir) {
  const wago = (name) => readCsv(path.join(dataDir, "wago", name + ".csv"));
  const names = new Map(wago("SpellName").map((r) => [+r.ID, r.Name_lang]));
  const tabsByClass = {};
  for (const tab of wago("TalentTab")) {
    const mask = +tab.ClassMask;
    const id = Object.keys(CLASS_TOKENS).find((c) => mask === 2 ** (c - 1));
    if (!id) continue;
    const token = CLASS_TOKENS[id];
    (tabsByClass[token] = tabsByClass[token] || []).push({ id: +tab.ID, name: tab.Name_lang, order: +tab.OrderIndex, talents: [] });
  }
  const tabById = new Map();
  for (const tabs of Object.values(tabsByClass)) {
    tabs.sort((a, b) => a.order - b.order || a.id - b.id);
    for (const tab of tabs) tabById.set(tab.id, tab);
  }
  for (const t of wago("Talent")) {
    const tab = tabById.get(+t.TabID);
    if (!tab) continue;
    const ranks = [];
    for (let i = 0; i < 9; i++) if (+t[`SpellRank_${i}`]) ranks.push(+t[`SpellRank_${i}`]);
    if (ranks.length === 0) continue;
    const name = ranks.map((spell) => names.get(spell)).find((n) => n);
    const talent = { id: +t.ID, name, tier: +t.TierID + 1, column: +t.ColumnIndex + 1, max: ranks.length };
    if (+t.PrereqTalent_0) { talent.prereq = +t.PrereqTalent_0; talent.prereqRank = +t.PrereqRank_0 + 1; }
    tab.talents.push(talent);
  }
  const out = {};
  for (const [token, tabs] of Object.entries(tabsByClass)) {
    for (const tab of tabs) tab.talents.sort((a, b) => a.tier - b.tier || a.column - b.column || a.id - b.id);
    out[token] = { tabs: tabs.map(({ id, name, talents }) => ({ id, name, talents })) };
  }
  return out;
}

// [[talentId, points], ...] -> one talent ID per point, in the order they are taken.
function expand(picks) {
  const ids = [];
  for (const [id, points] of picks) for (let i = 0; i < points; i++) ids.push(id);
  return ids;
}

// The problems of a build (one talent ID per point, from level 10 on) for one class's trees, as sentences; empty
// when every point can be learned at the level it comes at, in the order given.
function checkBuild(tree, ids, { points = POINTS } = {}) {
  const problems = [];
  const where = new Map();
  for (const tab of tree.tabs) for (const t of tab.talents) where.set(t.id, { tab, talent: t });
  const rank = new Map();
  const spent = new Map();
  if (ids.length !== points) problems.push(`the build has ${ids.length} points, not ${points}`);
  ids.forEach((id, i) => {
    const level = FIRST_LEVEL + i;
    const found = where.get(id);
    if (!found) { problems.push(`level ${level}: talent ${id} is not in this class's trees`); return; }
    const { tab, talent } = found;
    const label = `level ${level}: ${talent.name || `talent ${id}`} (${tab.name})`;
    const inTab = spent.get(tab.id) || 0;
    if (inTab < (talent.tier - 1) * PER_TIER) problems.push(`${label} needs ${(talent.tier - 1) * PER_TIER} points in ${tab.name}, has ${inTab}`);
    if (talent.prereq && (rank.get(talent.prereq) || 0) < talent.prereqRank) {
      const pre = where.get(talent.prereq);
      problems.push(`${label} needs ${(pre && pre.talent.name) || `talent ${talent.prereq}`} at rank ${talent.prereqRank}`);
    }
    const r = (rank.get(id) || 0) + 1;
    if (r > talent.max) problems.push(`${label} would be rank ${r} of ${talent.max}`);
    rank.set(id, r);
    spent.set(tab.id, inTab + 1);
  });
  return problems;
}

module.exports = { CLASS_TOKENS, FIRST_LEVEL, POINTS, PER_TIER, loadTrees, expand, checkBuild };
