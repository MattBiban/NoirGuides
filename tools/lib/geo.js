// Noir Guides, GPLv3. See LICENSE.
function zoneOf(db, areaId) {
  let id = +areaId;
  for (let i = 0; i < 6 && id; i++) {
    if (db.maps.has(id)) return id;
    const a = db.areas.get(id);
    id = a ? a.parent : 0;
  }
  return 0;
}
function toPoint(db, areaId, x, y) {
  const zone = zoneOf(db, areaId);
  const m = db.maps.get(zone);
  if (!m || x < 0 || y < 0) return null;
  const area = db.areas.get(zone);
  return { zone, x, y, wx: m.maxX - (y / 100) * (m.maxX - m.minX), wy: m.maxY - (x / 100) * (m.maxY - m.minY), continent: area ? area.continent : -1 };
}
const distance = (a, b) => (a.continent !== b.continent ? Infinity : Math.hypot(a.wx - b.wx, a.wy - b.wy));
function spawnPoints(db, kind, id) {
  const e = (kind === "npc" ? db.npcs : db.objects).get(id);
  const out = [];
  for (const [area, list] of Object.entries((e && e.spawns) || {})) for (const [x, y] of list) {
    const p = toPoint(db, +area, x, y);
    if (p) out.push(p);
  }
  return out;
}
// The middle of a set of spawns, in the zone most of them are in. Percent coordinates are recomputed from the average.
function centroid(points) {
  if (!points.length) return null;
  const count = new Map();
  for (const p of points) count.set(p.zone, (count.get(p.zone) || 0) + 1);
  const zone = [...count].sort((a, b) => b[1] - a[1] || a[0] - b[0])[0][0];
  const inZone = points.filter((p) => p.zone === zone);
  const avg = (k) => inZone.reduce((s, p) => s + p[k], 0) / inZone.length;
  return { zone, x: avg("x"), y: avg("y"), wx: avg("wx"), wy: avg("wy"), continent: inZone[0].continent };
}
module.exports = { zoneOf, toPoint, distance, spawnPoints, centroid };
