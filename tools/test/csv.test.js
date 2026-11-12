// Noir Guides, GPLv3. See LICENSE.
const test = require("node:test");
const assert = require("node:assert");
const { parseCsv } = require("../lib/csv");

test("parses quoted fields with commas and doubled quotes", () => {
  const { header, rows } = parseCsv('Name,ID\n"Ironforge, Dun Morogh",6\n"Say ""hi""",7\n');
  assert.deepStrictEqual(header, ["Name", "ID"]);
  assert.deepStrictEqual(rows, [["Ironforge, Dun Morogh", "6"], ['Say "hi"', "7"]]);
});
test("handles CRLF and a missing final newline", () => {
  assert.deepStrictEqual(parseCsv("a,b\r\n1,2").rows, [["1", "2"]]);
});
