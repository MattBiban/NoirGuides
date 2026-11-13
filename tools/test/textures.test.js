// Noir Guides, GPLv3. See LICENSE.
// The addon's textures are drawn by tools/gen_textures.js, not by hand: the files in NoirGuides/Textures must be
// exactly what the generator draws, in a format the game loads, and shaped the way the interface code assumes.
const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");
const { TEXTURES, OUT_DIR, render, encodeTga, generate } = require("../gen_textures");

const ROOT = path.join(__dirname, "..", "..");
const names = Object.keys(TEXTURES).sort();

// Reads back what encodeTga wrote: { width, height, alpha(x, y) with y = 0 at the top, colors }.
function decode(buffer) {
  const width = buffer.readUInt16LE(12);
  const height = buffer.readUInt16LE(14);
  const pixel = (x, y) => 18 + ((height - 1 - y) * width + x) * 4; // rows are stored bottom to top
  return {
    width, height,
    alpha: (x, y) => buffer[pixel(x, y) + 3],
    color: (x, y) => [buffer[pixel(x, y)], buffer[pixel(x, y) + 1], buffer[pixel(x, y) + 2]],
  };
}

// The kind icons of the guide window (spec 4.2): one per icon UI/Text.lua gives a line, and the timer of the flight
// bar.
const ICONS = ["accept", "turnin", "objective", "kill", "item", "vendor", "trainer", "gossip", "flight", "flightpoint",
  "hearth", "bind", "goto", "xp", "error", "note", "timer"];

test("the generator draws the textures the interface uses", () => {
  const expected = ["arrow", "pin", "pin-active", "box", "tick", "grip", "menu", "sheen", "bar", ...ICONS.map((icon) => `icon-${icon}`)];
  assert.deepStrictEqual(names, expected.sort());
});

test("every icon a step's line can show has a texture", () => {
  const text = fs.readFileSync(path.join(ROOT, "NoirGuides", "UI", "Text.lua"), "utf8");
  const used = new Set();
  for (const match of text.matchAll(/done\("(\w+)"/g)) used.add(match[1]);
  for (const match of text.matchAll(/icon = "(\w+)"/g)) used.add(match[1]);
  for (const match of text.matchAll(/(?:OBJECTIVE_ICON|or) "(\w+)"/g)) used.add(match[1]);
  assert.ok(used.size >= 10, "the icons were found in Text.lua");
  for (const icon of used) assert.ok(TEXTURES[`icon-${icon}`], `icon-${icon} is drawn`);
});

test("shapes that are not the same left and right are drawn whole, not mirrored", () => {
  for (const name of ["tick", "grip", "icon-turnin", "icon-flightpoint", "icon-gossip", "icon-timer"]) {
    assert.strictEqual(TEXTURES[name].mirror, false, `${name} is drawn whole`);
    const image = decode(generate()[`${name}.tga`]);
    let differs = false;
    for (let y = 0; y < image.height && !differs; y++) {
      for (let x = 0; x < image.width / 2; x++) {
        if (image.alpha(x, y) !== image.alpha(image.width - 1 - x, y)) { differs = true; break; }
      }
    }
    assert.ok(differs, `${name} differs between its left and right halves`);
  }
});

test("the tick box is an outline", () => {
  const box = decode(generate()["box.tga"]);
  const middle = box.width / 2;
  assert.strictEqual(box.alpha(middle, middle), 0, "the box is an outline");
  assert.ok(box.alpha(Math.round(box.width * 0.22), middle) > 127, "with a solid edge");
});

test("the generator is deterministic", () => {
  const a = generate();
  const b = generate();
  assert.deepStrictEqual(Object.keys(a).sort(), names.map((n) => `${n}.tga`).sort());
  for (const file of Object.keys(a)) assert.ok(a[file].equals(b[file]), file);
});

test("NoirGuides/Textures holds exactly the generated files, byte for byte", () => {
  assert.strictEqual(path.resolve(OUT_DIR), path.join(ROOT, "NoirGuides", "Textures"));
  const generated = generate();
  const onDisk = fs.readdirSync(OUT_DIR).sort();
  assert.deepStrictEqual(onDisk, Object.keys(generated).sort(), "run `npm run textures` in tools/");
  for (const file of onDisk) {
    assert.ok(fs.readFileSync(path.join(OUT_DIR, file)).equals(generated[file]), `${file} differs from the generator: run \`npm run textures\``);
  }
});

test("every texture is an uncompressed 32-bit TGA with power-of-two sides, which the game loads", () => {
  for (const [file, buffer] of Object.entries(generate())) {
    const size = TEXTURES[file.replace(/\.tga$/, "")].size;
    assert.strictEqual(buffer[0], 0, `${file}: no image ID`);
    assert.strictEqual(buffer[1], 0, `${file}: no color map`);
    assert.strictEqual(buffer[2], 2, `${file}: uncompressed true color`);
    assert.strictEqual(buffer.readUInt16LE(12), size, `${file}: width`);
    assert.strictEqual(buffer.readUInt16LE(14), size, `${file}: height`);
    assert.strictEqual(buffer[16], 32, `${file}: 32 bits per pixel`);
    assert.strictEqual(buffer[17], 8, `${file}: 8 alpha bits, rows bottom to top`);
    assert.strictEqual(buffer.length, 18 + size * size * 4, `${file}: no footer, no padding`);
    assert.strictEqual(size & (size - 1), 0, `${file}: side is a power of two`);
  }
});

const isGradient = (file) => Boolean(TEXTURES[file.replace(/.tga$/, "")].gradient);

test("every texture is white with the shape in its alpha, so the theme's colors tint it", () => {
  for (const [file, buffer] of Object.entries(generate())) {
    const image = decode(buffer);
    let opaque = 0;
    let clear = 0;
    for (let y = 0; y < image.height; y++) {
      for (let x = 0; x < image.width; x++) {
        assert.deepStrictEqual(image.color(x, y), [255, 255, 255], `${file} at ${x},${y}`);
        if (image.alpha(x, y) === 255) opaque++;
        if (image.alpha(x, y) === 0) clear++;
      }
    }
    assert.ok(opaque > 0, `${file} has solid pixels`);
    if (!isGradient(file)) assert.ok(clear > 0, `${file} has clear pixels`);
  }
});

test("every shape lies inside the circle that fits the texture, so it can be turned without being cut", () => {
  for (const [file, buffer] of Object.entries(generate())) {
    if (isGradient(file)) continue; // gradients fill their square and are never turned
    const image = decode(buffer);
    const half = image.width / 2;
    for (let y = 0; y < image.height; y++) {
      for (let x = 0; x < image.width; x++) {
        const distance = Math.hypot(x + 0.5 - half, y + 0.5 - half);
        if (distance > half - 1) assert.strictEqual(image.alpha(x, y), 0, `${file} at ${x},${y}`);
      }
    }
  }
});

test("the arrow points up and is the same left and right", () => {
  const image = decode(generate()["arrow.tga"]);
  const widthOfRow = (y) => {
    let count = 0;
    for (let x = 0; x < image.width; x++) if (image.alpha(x, y) > 127) count++;
    return count;
  };
  for (let y = 0; y < image.height; y++) {
    for (let x = 0; x < image.width / 2; x++) {
      assert.strictEqual(image.alpha(x, y), image.alpha(image.width - 1 - x, y), `row ${y}, column ${x}`);
    }
  }
  let first = 0;
  while (widthOfRow(first) === 0) first++;
  let last = image.height - 1;
  while (widthOfRow(last) === 0) last--;
  assert.ok(first < image.height / 4, "the tip is near the top");
  assert.ok(widthOfRow(first) <= 4, "the top of the shape is a tip");
  assert.ok(widthOfRow(first + 20) > widthOfRow(first + 8), "it widens downward");
  assert.ok(last > image.height / 2, "it reaches into the lower half");
});

test("the two pins can be told apart by shape alone: the next step's is a ring, the current step's is filled", () => {
  const ring = decode(generate()["pin.tga"]);
  const filled = decode(generate()["pin-active.tga"]);
  const middle = ring.width / 2;
  assert.strictEqual(ring.alpha(middle, middle), 0, "the ring is open in the middle");
  assert.strictEqual(filled.alpha(middle, middle), 255, "the current step's pin is solid in the middle");
});

test("render and encodeTga agree on which way is up", () => {
  const shape = render("arrow");
  const image = decode(encodeTga(shape.size, shape.alpha));
  for (const [x, y] of [[32, 8], [32, 40], [10, 50], [5, 5]]) {
    assert.strictEqual(image.alpha(x, y), shape.alpha[y * shape.size + x], `${x},${y}`);
  }
});

test("the design document lists each texture with the size the generator draws", () => {
  const design = fs.readFileSync(path.join(ROOT, "DESIGN.md"), "utf8");
  const section = design.split(/^## /m).find((part) => part.startsWith("Textures"));
  assert.ok(section, "DESIGN.md has a Textures section");
  const listed = {};
  for (const match of section.matchAll(/^\| `([\w-]+)` \| (\d+) \|/gm)) listed[match[1]] = Number(match[2]);
  const drawn = {};
  for (const name of names) drawn[name] = TEXTURES[name].size;
  assert.deepStrictEqual(listed, drawn);
});

test("package.json has the textures script", () => {
  const scripts = JSON.parse(fs.readFileSync(path.join(ROOT, "tools", "package.json"), "utf8")).scripts;
  assert.strictEqual(scripts.textures, "node gen_textures.js");
});

test("the sheen fades from the top edge to nothing, and the bar is glossy: brightest on top, deeper below", () => {
  const sheen = decode(generate()["sheen.tga"]);
  const bar = decode(generate()["bar.tga"]);
  const column = (image) => Array.from({ length: image.height }, (_, y) => image.alpha(3, y));
  const s = column(sheen);
  assert.ok(s[0] > 200, "the sheen is strong at the top");
  assert.strictEqual(s[s.length - 1], 0, "and gone at the bottom");
  for (let y = 1; y < s.length; y++) assert.ok(s[y] <= s[y - 1], "never brighter lower down");
  const b = column(bar);
  assert.strictEqual(b[0], 255, "a bright top edge");
  assert.ok(b[8] > b[24], "the upper half lighter than the lower");
  assert.ok(b[b.length - 1] > 120, "solid enough to read as a fill");
  for (const image of [sheen, bar]) {
    for (let y = 0; y < image.height; y++) {
      for (let x = 1; x < image.width; x++) assert.strictEqual(image.alpha(x, y), image.alpha(0, y), "the same on every column");
    }
  }
});
