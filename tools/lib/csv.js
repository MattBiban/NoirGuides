// Noir Guides, GPLv3. See LICENSE.
const fs = require("fs");
function parseCsv(text) {
  const out = [];
  let row = [], cell = "", quoted = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (quoted) {
      if (ch === '"' && text[i + 1] === '"') { cell += '"'; i++; }
      else if (ch === '"') quoted = false;
      else cell += ch;
    } else if (ch === '"') quoted = true;
    else if (ch === ",") { row.push(cell); cell = ""; }
    else if (ch === "\n" || ch === "\r") {
      if (ch === "\r" && text[i + 1] === "\n") i++;
      row.push(cell); cell = "";
      if (row.length > 1 || row[0] !== "") out.push(row);
      row = [];
    } else cell += ch;
  }
  if (cell !== "" || row.length) { row.push(cell); out.push(row); }
  return { header: out[0] || [], rows: out.slice(1) };
}
function readCsv(file) {
  const { header, rows } = parseCsv(fs.readFileSync(file, "utf8"));
  return rows.map((r) => Object.fromEntries(header.map((h, i) => [h, r[i]])));
}
module.exports = { parseCsv, readCsv };
