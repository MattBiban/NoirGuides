// Noir Guides, GPLv3. See LICENSE.
// Runs the Lua side's checks: `npm run test:lua` (from tools/).
//   1. lint.js over every Lua file of the addon (Lua 5.1 syntax and the project's forbidden calls).
//   2. every tools/test-lua/*.lua in its own Lua state, with the mock client (wow.lua) and the test library.
// `node harness/run.js state` runs only the test files whose name contains "state".
// Every test file runs twice: once as is and once with the addon's pairs() visiting keys in reverse, because the
// order of pairs differs between the test VM and the game.
// Exits 1 when anything fails.
const fs = require("node:fs");
const path = require("node:path");
const { ROOT, createVm } = require("./vm");
const { lintAddon } = require("./lint");

const PRELUDE = ["tools/harness/env.lua", "tools/harness/testlib.lua", "tools/harness/wow.lua"];

// Runs one test file. Returns { passed, failed, error } where error is a load or run failure of the file itself.
// `pairsMode` "reversed" makes the addon's pairs() visit keys in the opposite order (see env.lua).
function runTestFile(rel, log = console.log, pairsMode = "normal") {
  const vm = createVm({ print: log });
  const modeErr = vm.run(`HARNESS = { pairsMode = "${pairsMode}" }`, "=runner");
  if (modeErr) return { passed: 0, failed: 0, error: modeErr };
  for (const file of PRELUDE) {
    const err = vm.runFile(file);
    if (err) return { passed: 0, failed: 0, error: `${file}: ${err}` };
  }
  let err = vm.runFile(rel);
  if (!err) err = vm.run("HARNESS.T.run()", "=runner");
  if (err) return { passed: 0, failed: 0, error: err };
  return { passed: vm.globalNumber("TESTS_PASSED"), failed: vm.globalNumber("TESTS_FAILED"), error: null };
}

// Runs the lint and the test files under `testDir` (repo-relative). Returns the totals; prints as it goes.
function runAll({ testDir = "tools/test-lua", filter = "", lint = true, log = console.log, pairsModes = ["normal", "reversed"] } = {}) {
  const totals = { lintProblems: 0, passed: 0, failed: 0, fileErrors: 0, files: 0 };
  if (lint) {
    const { files, problems } = lintAddon(ROOT);
    totals.lintProblems = problems.length;
    for (const p of problems) log(`lint  ${p.file}:${p.line}: ${p.message}`);
    log(`# lint: ${files.length} addon Lua files, ${problems.length} problem(s)`);
  }
  const dir = path.join(ROOT, testDir);
  const tests = fs.existsSync(dir) ? fs.readdirSync(dir).filter((f) => f.endsWith(".lua") && f.includes(filter)).sort() : [];
  const runs = [];
  for (const mode of pairsModes) for (const name of tests) runs.push({ name, mode });
  for (const { name, mode } of runs) {
    const rel = `${testDir}/${name}`;
    log(mode === "normal" ? rel : `${rel} (pairs ${mode})`);
    const result = runTestFile(rel, log, mode);
    totals.files += 1;
    totals.passed += result.passed;
    totals.failed += result.failed;
    if (result.error) {
      totals.fileErrors += 1;
      log(`  FAILED  the file did not run:\n          ${result.error.replace(/\n/g, "\n          ")}`);
    } else if (result.passed + result.failed === 0) {
      totals.fileErrors += 1;
      log("  FAILED  the file defines no tests");
    }
  }
  if (tests.length === 0) {
    totals.fileErrors += 1;
    log(`  FAILED  no test files in ${testDir}${filter ? ` matching "${filter}"` : ""}`);
  }
  log(`# lua tests: ${totals.files} file run(s) with pairs order ${pairsModes.join(" and ")}, ${totals.passed} passed, ${totals.failed} failed, ${totals.fileErrors} file error(s)`);
  totals.ok = totals.lintProblems === 0 && totals.failed === 0 && totals.fileErrors === 0;
  return totals;
}

if (require.main === module) {
  const totals = runAll({ filter: process.argv[2] || "" });
  process.exit(totals.ok ? 0 : 1);
}

module.exports = { runAll, runTestFile };
