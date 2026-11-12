// Noir Guides, GPLv3. See LICENSE.
const { zoneOf } = require("../lib/geo");
function zoneBands(db, quests) {
  const byZone = new Map();
  for (const q of quests) {
    const z = zoneOf(db, q.zone);
    if (!z) continue;
    if (!byZone.has(z)) byZone.set(z, []);
    byZone.get(z).push(q.minLevel);
  }
  const out = [];
  for (const [zone, levels] of byZone) {
    levels.sort((a, b) => a - b);
    const pick = (f) => levels[Math.min(levels.length - 1, Math.floor(f * levels.length))];
    out.push({ zone, name: (db.areas.get(zone) || {}).name || String(zone), min: pick(0.2), max: pick(0.8), count: levels.length });
  }
  return out.sort((a, b) => a.min - b.min || a.zone - b.zone);
}
module.exports = { zoneBands };
