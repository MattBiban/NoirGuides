// Noir Guides, GPLv3. See LICENSE.
// Decode a QuestieDB "baked" TOC (Forever flavor) into plain JSON for offline tooling.
// usage: node questiedb_export.js <QuestieDB_Forever.toc> <out.json>
//
// Format (see QuestieDB src/read/baked.lua):
//   ## X-<Entity>-IDS: base64(zlib(CBOR id list))
//   ## X-<Entity>-<id>-S: base64(CBOR scalar row; row.p = presence bitmask for table fields)
//   ## X-<Entity>-<id>-<field>: base64(CBOR table value)
//   values starting with "~N~" are split into "<key>-1".."<key>-N".
const fs = require("fs");
const zlib = require("zlib");

const [tocPath, outPath] = process.argv.slice(2);

// ---- minimal CBOR decoder (RFC 8949 subset used by C_EncodingUtil) ----
function decodeCBOR(buf) {
  let pos = 0;
  const f16 = (h) => {
    const s = h & 0x8000 ? -1 : 1, e = (h >> 10) & 0x1f, m = h & 0x3ff;
    if (e === 0) return s * 2 ** -14 * (m / 1024);
    if (e === 31) return m ? NaN : s * Infinity;
    return s * 2 ** (e - 15) * (1 + m / 1024);
  };
  function len(ai) {
    if (ai < 24) return ai;
    if (ai === 24) return buf[pos++];
    if (ai === 25) { const v = buf.readUInt16BE(pos); pos += 2; return v; }
    if (ai === 26) { const v = buf.readUInt32BE(pos); pos += 4; return v; }
    if (ai === 27) { const v = Number(buf.readBigUInt64BE(pos)); pos += 8; return v; }
    if (ai === 31) return -1;
    throw new Error("bad ai " + ai);
  }
  function item() {
    const ib = buf[pos++], mt = ib >> 5, ai = ib & 31;
    switch (mt) {
      case 0: return len(ai);
      case 1: return -1 - len(ai);
      case 2: case 3: {
        const n = len(ai);
        if (n < 0) { const parts = []; while (buf[pos] !== 0xff) parts.push(item()); pos++; return parts.join(""); }
        const s = buf.slice(pos, pos + n); pos += n;
        return mt === 3 ? s.toString("utf8") : s.toString("latin1");
      }
      case 4: {
        const n = len(ai), a = [];
        if (n < 0) { while (buf[pos] !== 0xff) a.push(item()); pos++; } else for (let i = 0; i < n; i++) a.push(item());
        return a;
      }
      case 5: {
        const n = len(ai), o = {};
        const one = () => { const k = item(); o[k] = item(); };
        if (n < 0) { while (buf[pos] !== 0xff) one(); pos++; } else for (let i = 0; i < n; i++) one();
        return o;
      }
      case 6: len(ai); return item(); // ignore tags
      case 7:
        if (ai === 20) return false; if (ai === 21) return true; if (ai === 22 || ai === 23) return null;
        if (ai === 25) { const v = f16(buf.readUInt16BE(pos)); pos += 2; return v; }
        if (ai === 26) { const v = buf.readFloatBE(pos); pos += 4; return v; }
        if (ai === 27) { const v = buf.readDoubleBE(pos); pos += 8; return v; }
        return ai;
    }
  }
  return item();
}

// Lua-style 1-based arrays come back either as arrays (index 0 = Lua [1]) or int-keyed maps.
function luaList(v) {
  if (v == null) return v;
  if (Array.isArray(v)) return v.map(luaList);
  if (typeof v === "object") {
    const o = {};
    for (const [k, x] of Object.entries(v)) o[k] = luaList(x);
    return o;
  }
  return v;
}
// field accessor for a decoded scalar row (array => 0-based, map => "1"-based keys)
const fieldOf = (row, i) => (Array.isArray(row) ? row[i - 1] : row[String(i)]);

// ---- read TOC metadata ----
const meta = new Map();
for (const line of fs.readFileSync(tocPath, "utf8").split(/\r?\n/)) {
  const m = line.match(/^## (X-[^:]+):\s?(.*)$/);
  if (m) meta.set(m[1], m[2]);
}
function getStored(key) {
  const v = meta.get(key);
  if (v == null) return null;
  const c = v.match(/^~(\d+)~$/);
  if (!c) return v;
  let s = "";
  for (let i = 1; i <= +c[1]; i++) {
    const p = meta.get(`${key}-${i}`);
    if (p == null) throw new Error(`missing chunk ${key}-${i}`);
    s += p;
  }
  return s;
}
const b64 = (s) => Buffer.from(s, "base64");
function inflate(buf) {
  for (const fn of [zlib.inflateSync, zlib.inflateRawSync, zlib.gunzipSync]) {
    try { return fn(buf); } catch (_) {}
  }
  throw new Error("cannot inflate");
}

const schemas = {
  Quest: { count: 36, names: ["name","startedBy","finishedBy","requiredLevel","questLevel","requiredRaces","requiredClasses","objectivesText","triggerEnd","objectives","sourceItemId","preQuestGroup","preQuestSingle","childQuests","inGroupWith","exclusiveTo","zoneOrSort","requiredSkill","requiredMinRep","requiredMaxRep","requiredSourceItems","nextQuestInChain","questFlags","specialFlags","parentQuest","reputationReward","breadcrumbForQuestId","breadcrumbs","extraObjectives","requiredSpell","requiredSpecialization","requiredMaxLevel","availableUntilCompleted","availableStartingWith","requiredRanks","disabledByQuest"],
    tables: [2,3,8,9,10,12,13,14,15,16,18,19,20,21,26,28,29,35] },
  Npc: { count: 15, names: ["name","minLevelHealth","maxLevelHealth","minLevel","maxLevel","rank","spawns","waypoints","zoneID","questStarts","questEnds","factionID","friendlyToFaction","subName","npcFlags"],
    tables: [7,8,10,11] },
  Object: { count: 7, names: ["name","questStarts","questEnds","spawns","zoneID","factionID","waypoints"], tables: [2,3,4,7] },
  Item: { count: 16, names: ["name","npcDrops","objectDrops","itemDrops","startQuest","questRewards","flags","foodType","itemLevel","requiredLevel","ammoType","class","subClass","vendors","relatedQuests","teachesSpell"],
    tables: [2,3,4,6,14,15] },
};

const out = { flavor: meta.get("X-Flavor"), build: meta.get("X-BUILD-COMMIT") };
for (const [entity, sc] of Object.entries(schemas)) {
  if (!sc) continue;
  const prefix = `X-${entity}-`;
  const ids = luaList(decodeCBOR(inflate(b64(getStored(prefix + "IDS")))));
  const rows = {};
  let bad = 0;
  for (const id of ids) {
    const s = getStored(`${prefix}${id}-S`);
    if (!s) continue;
    let row;
    try { row = luaList(decodeCBOR(b64(s))); } catch (e) { bad++; continue; }
    const rec = {};
    for (let i = 1; i <= sc.count; i++) {
      let v;
      if (sc.tables.includes(i)) {
        const p = Array.isArray(row) ? undefined : row.p;
        if (p == null || Math.floor(p / 2 ** (i - 1)) % 2 !== 1) continue;
        const t = getStored(`${prefix}${id}-${i}`);
        if (!t) continue;
        try { v = luaList(decodeCBOR(b64(t))); } catch (e) { bad++; continue; }
      } else v = fieldOf(row, i);
      if (v !== undefined && v !== null) rec[sc.names[i - 1]] = v;
    }
    rows[id] = rec;
  }
  out[entity] = rows;
  console.log(entity, Object.keys(rows).length, "records", bad ? `(${bad} decode errors)` : "");
}
fs.writeFileSync(outPath, JSON.stringify(out));
