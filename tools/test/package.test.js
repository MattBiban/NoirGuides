// Noir Guides, GPLv3. See LICENSE.
// The release zip (task X3, rebuild X2 for 0.2.0): `npm run package` writes dist/NoirGuides-<version>.zip, which a player unpacks into
// Interface/AddOns. It must hold exactly one folder, NoirGuides/, with every file the toc loads, the textures and the
// license, byte for byte, and nothing from tools/ or docs/.
const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const zlib = require("node:zlib");
const { spawnSync } = require("node:child_process");
const pkg = require("../package_addon");

const ROOT = path.join(__dirname, "..", "..");
const ADDON = path.join(ROOT, "NoirGuides");

// A zip reader written from the format (APPNOTE 4.3): the central directory gives every entry, the local header and
// the data are read from where it points, and each entry's CRC is checked. It reads only what package_addon writes:
// stored (0) or deflated (8) entries, no zip64, no encryption.
function readZip(buf) {
  let eocd = -1;
  for (let i = buf.length - 22; i >= Math.max(0, buf.length - 22 - 65535); i--) {
    if (buf.readUInt32LE(i) === 0x06054b50) { eocd = i; break; }
  }
  assert.ok(eocd >= 0, "end of central directory found");
  const count = buf.readUInt16LE(eocd + 10);
  let p = buf.readUInt32LE(eocd + 16);
  const entries = [];
  for (let n = 0; n < count; n++) {
    assert.strictEqual(buf.readUInt32LE(p), 0x02014b50, "central directory header");
    const method = buf.readUInt16LE(p + 10);
    const crc = buf.readUInt32LE(p + 16);
    const csize = buf.readUInt32LE(p + 20);
    const usize = buf.readUInt32LE(p + 24);
    const nameLen = buf.readUInt16LE(p + 28);
    const extraLen = buf.readUInt16LE(p + 30);
    const commentLen = buf.readUInt16LE(p + 32);
    const local = buf.readUInt32LE(p + 42);
    const name = buf.toString("utf8", p + 46, p + 46 + nameLen);
    assert.strictEqual(buf.readUInt32LE(local), 0x04034b50, `local header of ${name}`);
    const start = local + 30 + buf.readUInt16LE(local + 26) + buf.readUInt16LE(local + 28);
    const raw = buf.subarray(start, start + csize);
    const data = method === 0 ? Buffer.from(raw) : zlib.inflateRawSync(raw);
    assert.ok(method === 0 || method === 8, `${name}: method ${method}`);
    assert.strictEqual(data.length, usize, `${name}: size`);
    assert.strictEqual(zlib.crc32(data), crc, `${name}: crc`);
    entries.push({ name, data });
    p += 46 + nameLen + extraLen + commentLen;
  }
  return entries;
}

function walk(dir) {
  const out = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...walk(p));
    else out.push(p);
  }
  return out;
}

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "noir-package-"));
test.after(() => fs.rmSync(tmp, { recursive: true, force: true }));
const built = pkg.packageAddon({ outDir: tmp });
const entries = readZip(fs.readFileSync(built.file));
const byName = new Map(entries.map((e) => [e.name, e.data]));

test("the version comes from the toc and is 0.2.1", () => {
  assert.strictEqual(pkg.tocVersion(fs.readFileSync(path.join(ADDON, "NoirGuides.toc"), "utf8")), "0.2.1");
  assert.strictEqual(built.version, "0.2.1");
  assert.strictEqual(path.basename(built.file), "NoirGuides-0.2.1.zip");
});

test("the default output is dist/NoirGuides-<version>.zip at the repository root", () => {
  assert.strictEqual(pkg.outputFile(path.join(ROOT, "dist"), "0.2.0"), path.join(ROOT, "dist", "NoirGuides-0.2.0.zip"));
  assert.strictEqual(pkg.DEFAULT_OUT, path.join(ROOT, "dist"));
});

test("every entry is inside the one folder NoirGuides/", () => {
  assert.ok(entries.length > 0);
  const outside = entries.map((e) => e.name).filter((n) => !n.startsWith("NoirGuides/") || n.includes("\\") || n.includes(".."));
  assert.deepStrictEqual(outside, []);
  assert.deepStrictEqual([...new Set(entries.map((e) => e.name.split("/")[0]))], ["NoirGuides"]);
});

test("every file of the addon folder is in the zip, byte for byte, and nothing else but the license", () => {
  const expected = walk(ADDON).map((f) => "NoirGuides/" + path.relative(ADDON, f).split(path.sep).join("/")).sort();
  const files = entries.map((e) => e.name).filter((n) => !n.endsWith("/"));
  assert.deepStrictEqual(files.filter((n) => n !== "NoirGuides/LICENSE").sort(), expected);
  for (const name of expected) {
    assert.ok(byName.get(name).equals(fs.readFileSync(path.join(ROOT, ...name.split("/")))), `${name} is unchanged`);
  }
});

test("the zip carries the GPL text as NoirGuides/LICENSE", () => {
  assert.ok(byName.get("NoirGuides/LICENSE").equals(fs.readFileSync(path.join(ROOT, "LICENSE"))));
});

test("every file the toc loads is in the zip", () => {
  const toc = byName.get("NoirGuides/NoirGuides.toc").toString("utf8");
  const listed = pkg.tocFiles(toc);
  assert.ok(listed.length >= 30, `${listed.length} files listed`);
  assert.deepStrictEqual(listed.filter((f) => !byName.has("NoirGuides/" + f.replace(/\\/g, "/"))), []);
});

test("a toc that lists a missing file refuses to package", () => {
  assert.throws(() => pkg.checkToc("## Version: 0.1.0\nCore.lua\nNope.lua\n", new Set(["Core.lua"])), /Nope\.lua/);
});

test("the same sources give the same bytes", () => {
  const again = pkg.packageAddon({ outDir: path.join(tmp, "again") });
  assert.ok(fs.readFileSync(again.file).equals(fs.readFileSync(built.file)));
});

test(".gitattributes fixes the bytes of every kind of file in the zip, so any checkout gives the same zip", () => {
  const lines = fs.readFileSync(path.join(ROOT, ".gitattributes"), "utf8").split("\n").map((l) => l.trim());
  const rule = { lua: "*.lua text eol=lf", toc: "*.toc text eol=lf", tga: "*.tga binary", xml: "*.xml text eol=lf" };
  for (const e of entries.filter((x) => x.name !== "NoirGuides/LICENSE")) {
    const ext = path.extname(e.name).slice(1);
    assert.ok(rule[ext], `${e.name}: no rule for .${ext} files`);
    assert.ok(lines.includes(rule[ext]), `.gitattributes has "${rule[ext]}"`);
  }
  assert.ok(lines.includes("LICENSE text eol=lf"), '.gitattributes has "LICENSE text eol=lf"');
});

test("an unzip tool the player may use unpacks it into one folder", (t) => {
  const tar = process.platform === "win32" ? path.join(process.env.SystemRoot || "C:\\Windows", "System32", "tar.exe") : "tar";
  const dir = path.join(tmp, "unpacked");
  fs.mkdirSync(dir);
  const r = spawnSync(tar, ["-xf", built.file, "-C", dir]);
  if (r.error) return t.skip("no tar on this machine");
  assert.strictEqual(r.status, 0, String(r.stderr));
  assert.deepStrictEqual(fs.readdirSync(dir), ["NoirGuides"]);
  assert.ok(fs.existsSync(path.join(dir, "NoirGuides", "NoirGuides.toc")));
  assert.ok(fs.existsSync(path.join(dir, "NoirGuides", "Routes", "horde-undead.lua")));
});
