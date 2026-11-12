// Noir Guides, GPLv3. See LICENSE.
// Draws the addon's textures (DESIGN.md, "Textures") and writes them to NoirGuides/Textures as TGA files.
//   npm run textures          writes the files
//   node gen_textures.js --check   exits 1 when a file on disk differs from what would be written
//
// Every texture is white with its shape in the alpha channel, so one file serves every color: the addon tints it
// with a color of the design (Theme.Tint). Shapes are described in a unit square (0 to 1, y down) and stay inside
// the circle that fits the square, because the addon turns the arrow by its texture coordinates and whatever
// lies outside that circle would be cut off. Edges are smoothed by sampling each pixel 8 by 8 times.
//
// The format is the plainest one the game reads: uncompressed 32-bit TGA, sides a power of two, rows stored from
// the bottom up. Nothing here depends on a library, the clock or the machine: the same source gives the same
// bytes, and tools/test/textures.test.js fails when the files on disk are not those bytes.
const fs = require("node:fs");
const path = require("node:path");

const OUT_DIR = path.join(__dirname, "..", "NoirGuides", "Textures");
const SAMPLES = 8;

// Even-odd test: is the point inside the polygon given as [[x, y], ...]?
function inPolygon(points, x, y) {
  let inside = false;
  for (let i = 0, j = points.length - 1; i < points.length; j = i++) {
    const [xi, yi] = points[i];
    const [xj, yj] = points[j];
    if ((yi > y) !== (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

const distance = (x, y) => Math.hypot(x - 0.5, y - 0.5);

// Small shapes the icons are built from, each a test on a point of the unit square.
const disc = (cx, cy, r) => (x, y) => Math.hypot(x - cx, y - cy) <= r;
const ring = (cx, cy, inner, outer) => (x, y) => {
  const d = Math.hypot(x - cx, y - cy);
  return d <= outer && d >= inner;
};
const box = (x0, y0, x1, y1) => (x, y) => x >= x0 && x <= x1 && y >= y0 && y <= y1;
const polygon = (points) => (x, y) => inPolygon(points, x, y);
// A stroke of the given width from (x0, y0) to (x1, y1), with round ends.
const stroke = (x0, y0, x1, y1, width) => (x, y) => {
  const dx = x1 - x0;
  const dy = y1 - y0;
  const t = Math.max(0, Math.min(1, ((x - x0) * dx + (y - y0) * dy) / (dx * dx + dy * dy)));
  return Math.hypot(x - (x0 + t * dx), y - (y0 + t * dy)) <= width / 2;
};
const any = (...shapes) => (x, y) => shapes.some((shape) => shape(x, y));
const minus = (shape, ...holes) => (x, y) => shape(x, y) && !holes.some((hole) => hole(x, y));

// A five-pointed star with its top point up.
function star(cx, cy, outer, inner) {
  const points = [];
  for (let i = 0; i < 10; i++) {
    const angle = -Math.PI / 2 + (i * Math.PI) / 5;
    const r = i % 2 === 0 ? outer : inner;
    points.push([cx + r * Math.cos(angle), cy + r * Math.sin(angle)]);
  }
  return polygon(points);
}

// name -> { size, inside(x, y), mirror }: the side in pixels, the shape in the unit square, and mirror: false for a
// shape that is not the same left and right.
const TEXTURES = {
  // A navigation arrowhead pointing up: tip, right wing, the notch between the wings, left wing.
  arrow: {
    size: 64,
    inside: (x, y) => inPolygon([[0.5, 0.1], [0.78, 0.8], [0.5, 0.64], [0.22, 0.8]], x, y),
  },
  // A next step's pin: a ring.
  pin: {
    size: 32,
    inside: (x, y) => distance(x, y) <= 0.4 && distance(x, y) >= 0.24,
  },
  // The current step's pin: a disc inside a thin ring, told from the other by shape and not only by color.
  "pin-active": {
    size: 32,
    inside: (x, y) => distance(x, y) <= 0.26 || (distance(x, y) <= 0.44 && distance(x, y) >= 0.36),
  },
  // The guide window's tick box: a square outline, and the tick drawn inside it when the line is done.
  box: {
    size: 32,
    inside: (x, y) => Math.max(Math.abs(x - 0.5), Math.abs(y - 0.5)) <= 0.3
      && Math.max(Math.abs(x - 0.5), Math.abs(y - 0.5)) >= 0.22,
  },
  tick: {
    size: 32,
    mirror: false,
    inside: any(stroke(0.27, 0.52, 0.43, 0.68, 0.1), stroke(0.43, 0.68, 0.73, 0.34, 0.1)),
  },
  // The resize grip: three diagonal strokes toward the lower right corner.
  grip: {
    size: 32,
    mirror: false,
    inside: any(stroke(0.78, 0.36, 0.36, 0.78, 0.09), stroke(0.78, 0.5, 0.5, 0.78, 0.09), stroke(0.78, 0.64, 0.64, 0.78, 0.09)),
  },
  // The window's menu button: three bars.
  menu: {
    size: 32,
    inside: any(box(0.24, 0.28, 0.76, 0.36), box(0.24, 0.46, 0.76, 0.54), box(0.24, 0.64, 0.76, 0.72)),
  },
  // The kind icons of a step's lines (spec 4.2), each a plain symbol of what the line asks for.
  "icon-accept": { size: 32, inside: any(box(0.44, 0.18, 0.56, 0.6), disc(0.5, 0.75, 0.07)) }, // an exclamation mark
  "icon-turnin": { // a question mark
    size: 32,
    mirror: false,
    inside: any(
      minus(ring(0.5, 0.34, 0.1, 0.2), box(0, 0.34, 0.5, 1)),
      stroke(0.62, 0.42, 0.5, 0.52, 0.1),
      box(0.45, 0.5, 0.55, 0.62),
      disc(0.5, 0.76, 0.07),
    ),
  },
  "icon-objective": { size: 32, inside: any(ring(0.5, 0.5, 0.28, 0.38), disc(0.5, 0.5, 0.12)) }, // a target
  "icon-kill": { size: 32, inside: any(stroke(0.25, 0.25, 0.75, 0.75, 0.12), stroke(0.75, 0.25, 0.25, 0.75, 0.12)) }, // a cross
  "icon-item": { size: 32, inside: any(disc(0.5, 0.6, 0.25), box(0.4, 0.22, 0.6, 0.38)) }, // a bag
  "icon-vendor": { size: 32, inside: minus(disc(0.5, 0.5, 0.34), box(0.46, 0.3, 0.54, 0.7)) }, // a coin
  "icon-trainer": { size: 32, inside: any(box(0.2, 0.28, 0.47, 0.72), box(0.53, 0.28, 0.8, 0.72)) }, // a book
  "icon-gossip": { // a speech bubble
    size: 32,
    mirror: false,
    inside: any(
      (x, y) => ((x - 0.5) / 0.32) ** 2 + ((y - 0.45) / 0.22) ** 2 <= 1,
      polygon([[0.3, 0.6], [0.42, 0.62], [0.26, 0.78]]),
    ),
  },
  "icon-flight": { // a plane seen from above, nose up
    size: 32,
    inside: any(
      box(0.46, 0.18, 0.54, 0.8),
      polygon([[0.5, 0.4], [0.82, 0.58], [0.82, 0.64], [0.5, 0.54], [0.18, 0.64], [0.18, 0.58]]),
      polygon([[0.5, 0.7], [0.64, 0.8], [0.36, 0.8]]),
    ),
  },
  "icon-flightpoint": { // a flag
    size: 32,
    mirror: false,
    inside: any(box(0.3, 0.18, 0.36, 0.82), polygon([[0.36, 0.2], [0.76, 0.34], [0.36, 0.5]])),
  },
  "icon-hearth": { // a house with a door
    size: 32,
    inside: minus(any(polygon([[0.5, 0.18], [0.82, 0.48], [0.18, 0.48]]), box(0.26, 0.48, 0.74, 0.8)), box(0.44, 0.62, 0.56, 0.81)),
  },
  "icon-bind": { // a stone: a diamond outline
    size: 32,
    inside: (x, y) => Math.abs(x - 0.5) + Math.abs(y - 0.5) <= 0.36 && Math.abs(x - 0.5) + Math.abs(y - 0.5) >= 0.22,
  },
  "icon-goto": { // a map pin
    size: 32,
    inside: minus(any(disc(0.5, 0.4, 0.22), polygon([[0.31, 0.5], [0.69, 0.5], [0.5, 0.84]])), disc(0.5, 0.4, 0.09)),
  },
  "icon-xp": { size: 32, inside: star(0.5, 0.53, 0.36, 0.15) }, // a star
  "icon-error": { // a warning triangle
    size: 32,
    inside: minus(polygon([[0.5, 0.18], [0.8, 0.76], [0.2, 0.76]]), box(0.47, 0.38, 0.53, 0.6), disc(0.5, 0.68, 0.04)),
  },
  "icon-note": { // a page with lines
    size: 32,
    inside: minus(box(0.28, 0.2, 0.72, 0.8), box(0.36, 0.33, 0.64, 0.38), box(0.36, 0.47, 0.64, 0.52), box(0.36, 0.61, 0.56, 0.66)),
  },
  "icon-timer": { // a clock at a quarter past
    size: 32,
    mirror: false,
    inside: any(ring(0.5, 0.5, 0.3, 0.38), stroke(0.5, 0.5, 0.5, 0.3, 0.1), stroke(0.5, 0.5, 0.65, 0.5, 0.1)),
  },
};

// The alpha of every pixel, row by row from the top: { size, alpha }. A shape that is the same left and right
// (every one without mirror: false) has its left half sampled and mirrored, so the two halves are equal to the
// last bit; the others are sampled whole.
function render(name) {
  const texture = TEXTURES[name];
  if (!texture) throw new Error(`no texture named ${name}`);
  const { size, inside } = texture;
  const mirror = texture.mirror !== false;
  const alpha = new Uint8Array(size * size);
  for (let py = 0; py < size; py++) {
    for (let px = 0; px < (mirror ? size / 2 : size); px++) {
      let covered = 0;
      for (let sy = 0; sy < SAMPLES; sy++) {
        for (let sx = 0; sx < SAMPLES; sx++) {
          if (inside((px + (sx + 0.5) / SAMPLES) / size, (py + (sy + 0.5) / SAMPLES) / size)) covered++;
        }
      }
      const value = Math.round((covered / (SAMPLES * SAMPLES)) * 255);
      alpha[py * size + px] = value;
      if (mirror) alpha[py * size + (size - 1 - px)] = value;
    }
  }
  return { size, alpha };
}

// A white image with the given alpha as an uncompressed 32-bit TGA.
function encodeTga(size, alpha) {
  const header = Buffer.alloc(18);
  header[2] = 2; // uncompressed true color
  header.writeUInt16LE(size, 12);
  header.writeUInt16LE(size, 14);
  header[16] = 32; // bits per pixel
  header[17] = 8; // 8 alpha bits; rows from the bottom up
  const pixels = Buffer.alloc(size * size * 4, 255); // blue, green, red: white
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      pixels[((size - 1 - y) * size + x) * 4 + 3] = alpha[y * size + x];
    }
  }
  return Buffer.concat([header, pixels]);
}

// file name -> contents, for every texture.
function generate() {
  const files = {};
  for (const name of Object.keys(TEXTURES).sort()) {
    const { size, alpha } = render(name);
    files[`${name}.tga`] = encodeTga(size, alpha);
  }
  return files;
}

function main(args) {
  const files = generate();
  if (args.includes("--check")) {
    const wrong = Object.keys(files).filter((file) => {
      const target = path.join(OUT_DIR, file);
      return !fs.existsSync(target) || !fs.readFileSync(target).equals(files[file]);
    });
    for (const file of wrong) console.log(`${file} differs from the generator`);
    console.log(`${Object.keys(files).length} texture(s) checked, ${wrong.length} differ`);
    return wrong.length === 0 ? 0 : 1;
  }
  fs.mkdirSync(OUT_DIR, { recursive: true });
  for (const [file, contents] of Object.entries(files)) {
    fs.writeFileSync(path.join(OUT_DIR, file), contents);
    console.log(`wrote NoirGuides/Textures/${file} (${contents.length} bytes)`);
  }
  return 0;
}

if (require.main === module) process.exit(main(process.argv.slice(2)));

module.exports = { TEXTURES, OUT_DIR, SAMPLES, render, encodeTga, generate };
