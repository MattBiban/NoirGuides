-- Noir Guides, GPLv3. See LICENSE.
-- Fixture for tools/test/harness.test.js: one assertion fails, on purpose.
test("passes", function() eq({ a = 1 }, { a = 1 }) end)
test("fails", function() eq({ a = 1 }, { a = 2 }, "the table") end)
