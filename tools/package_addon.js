// Noir Guides, GPLv3. See LICENSE.
// Builds the release zip a player unpacks into Interface/AddOns:
//   npm run package      -> dist/NoirGuides-<version>.zip (the version is the toc's "## Version:")
//
// The zip holds one folder, NoirGuides/, with every file of the addon folder as it is on disk plus the GPL text as
// NoirGuides/LICENSE. It refuses to build when the toc lists a file that does not exist. Entries are sorted and carry
// a fixed date, so the same sources always give the same bytes. The zip format is written here (APPNOTE 4.3: local
// headers, central directory, end record; deflate from node:zlib), so packaging needs no tool beyond Node.
const fs = require("node:fs");
const path = require("node:path");
const zlib = require("node:zlib");

const ROOT = path.join(__dirname, "..");
const ADDON = path.join(ROOT, "NoirGuides");
const DEFAULT_OUT = path.join(ROOT, "dist");
const FOLDER = "NoirGuides";
// 2026-11-11 00:00, in the MS-DOS date and time the zip format stores
const DOS_DATE = ((2026 - 1980) << 9) | (11 << 5) | 11;
const DOS_TIME = 0;

function tocVersion(toc) {
  const m = /^## Version:\s*(\S+)\s*$/m.exec(toc);
  if (!m) throw new Error("the toc has no ## Version: line");
  return m[1];
}

// The files the toc loads, as written there (backslashes kept): every line that is not blank, a comment or a tag.
function tocFiles(toc) {
  return toc.split(/\r?\n/).map((l) => l.trim()).filter((l) => l && !l.startsWith("#"));
}

function checkToc(toc, present) {
  const missing = tocFiles(toc).filter((f) => !present.has(f.replace(/\\/g, "/")));
  if (missing.length) throw new Error(`the toc lists files that do not exist: ${missing.join(", ")}`);
}

function outputFile(outDir, version) {
  return path.join(outDir, `${FOLDER}-${version}.zip`);
}

function walk(dir) {
  const out = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...walk(p));
    else if (e.isFile()) out.push(p);
  }
  return out;
}

// [{ name, data }] -> the zip's bytes. Deflates an entry only when that makes it smaller.
function buildZip(entries) {
  const locals = [];
  const centrals = [];
  let offset = 0;
  for (const { name, data } of entries) {
    const nameBuf = Buffer.from(name, "utf8");
    const deflated = zlib.deflateRawSync(data, { level: 9 });
    const method = deflated.length < data.length ? 8 : 0;
    const body = method === 8 ? deflated : data;
    const crc = zlib.crc32(data);
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4); // version needed: 2.0
    local.writeUInt16LE(0x0800, 6); // names are UTF-8
    local.writeUInt16LE(method, 8);
    local.writeUInt16LE(DOS_TIME, 10);
    local.writeUInt16LE(DOS_DATE, 12);
    local.writeUInt32LE(crc, 14);
    local.writeUInt32LE(body.length, 18);
    local.writeUInt32LE(data.length, 22);
    local.writeUInt16LE(nameBuf.length, 26);
    local.writeUInt16LE(0, 28);
    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50, 0);
    central.writeUInt16LE(20, 4); // made by: 2.0, MS-DOS attributes
    central.writeUInt16LE(20, 6);
    central.writeUInt16LE(0x0800, 8);
    central.writeUInt16LE(method, 10);
    central.writeUInt16LE(DOS_TIME, 12);
    central.writeUInt16LE(DOS_DATE, 14);
    central.writeUInt32LE(crc, 16);
    central.writeUInt32LE(body.length, 20);
    central.writeUInt32LE(data.length, 24);
    central.writeUInt16LE(nameBuf.length, 28);
    central.writeUInt32LE(0, 38); // external attributes: a plain file
    central.writeUInt32LE(offset, 42);
    locals.push(local, nameBuf, body);
    centrals.push(central, nameBuf);
    offset += local.length + nameBuf.length + body.length;
  }
  const dir = Buffer.concat(centrals);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(entries.length, 8);
  end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(dir.length, 12);
  end.writeUInt32LE(offset, 16);
  return Buffer.concat([...locals, dir, end]);
}

// The entries of the release: the addon folder as on disk, plus the license.
function collect() {
  const files = walk(ADDON).map((f) => path.relative(ADDON, f).split(path.sep).join("/"));
  const toc = fs.readFileSync(path.join(ADDON, "NoirGuides.toc"), "utf8");
  checkToc(toc, new Set(files));
  if (files.includes("LICENSE")) throw new Error("NoirGuides/LICENSE would be overwritten by the repository's LICENSE");
  const entries = files.map((f) => ({ name: `${FOLDER}/${f}`, data: fs.readFileSync(path.join(ADDON, ...f.split("/"))) }));
  entries.push({ name: `${FOLDER}/LICENSE`, data: fs.readFileSync(path.join(ROOT, "LICENSE")) });
  entries.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
  return { version: tocVersion(toc), entries };
}

function packageAddon({ outDir = DEFAULT_OUT } = {}) {
  const { version, entries } = collect();
  const file = outputFile(outDir, version);
  fs.mkdirSync(outDir, { recursive: true });
  fs.writeFileSync(file, buildZip(entries));
  return { file, version, count: entries.length };
}

module.exports = { tocVersion, tocFiles, checkToc, outputFile, buildZip, collect, packageAddon, DEFAULT_OUT };

if (require.main === module) {
  const { file, version, count } = packageAddon();
  console.log(`Noir Guides ${version}: ${count} files -> ${path.relative(ROOT, file)} (${fs.statSync(file).size} bytes)`);
}
