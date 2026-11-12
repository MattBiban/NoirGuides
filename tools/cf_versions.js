// Noir Guides, GPLv3. See LICENSE.
// Lists the WoW game versions CurseForge accepts, to find the ID(s) for CF_GAME_VERSIONS (docs/RELEASING.md).
//   CF_API_KEY=<token> node tools/cf_versions.js [filter]
const token = process.env.CF_API_KEY;
if (!token) throw new Error("set CF_API_KEY to your CurseForge API token first");
const filter = (process.argv[2] || "").toLowerCase();
fetch("https://wow.curseforge.com/api/game/versions", { headers: { "X-Api-Token": token } })
  .then((r) => {
    if (!r.ok) throw new Error(`CurseForge answered ${r.status}`);
    return r.json();
  })
  .then((list) => {
    for (const v of list) if (!filter || String(v.name).toLowerCase().includes(filter)) console.log(`${v.id}\t${v.name}`);
  })
  .catch((e) => { console.error(e.message); process.exit(1); });
