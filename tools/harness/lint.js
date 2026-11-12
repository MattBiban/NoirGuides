// Noir Guides, GPLv3. See LICENSE.
// Static checks on the addon's Lua. The test VM is Lua 5.3 and would happily run 5.3 code that the game (Lua 5.1)
// rejects, so everything the VM cannot catch at run time is caught here: syntax, string escapes, library functions
// that only newer Lua has, and the calls the project forbids outright.
const fs = require("node:fs");
const path = require("node:path");
const luaparse = require("luaparse");

const HEADER = "-- Noir Guides, GPLv3. See LICENSE.";

// Library members Lua 5.1 does not have. env.lua also leaves them out of the addon's globals; this catches them
// when reached through a string method (("x"):pack) or on a code path no test runs.
const NOT_IN_51 = {
  table: ["unpack", "pack", "move"],
  math: ["tointeger", "type", "ult", "maxinteger", "mininteger"],
  string: ["pack", "unpack", "packsize"],
  coroutine: ["isyieldable"],
};
const STRING_METHODS_NOT_IN_51 = ["pack", "unpack", "packsize"];
// Globals the addon must not touch, with the reason shown to the author.
const FORBIDDEN_GLOBALS = {
  setfenv: "the test VM cannot emulate it, so code using it would be untested",
  getfenv: "the test VM cannot emulate it, so code using it would be untested",
  utf8: "Lua 5.3 only",
  rawlen: "Lua 5.2+ only",
  load: "the game has loadstring; load differs between Lua 5.1 and the test VM",
  require: "not available in the game",
  CreateMacro: "the addon never writes macros",
  EditMacro: "the addon never writes macros",
  DeleteMacro: "the addon never writes macros",
  CombatLogGetCurrentEventInfo: "the addon never reads the combat log",
};
// Key bindings come only from Bindings.xml: the addon never sets one from Lua.
for (const name of ["SetBinding", "SetBindingClick", "SetBindingMacro", "SetBindingSpell", "SetBindingItem",
  "SetOverrideBinding", "SetOverrideBindingClick", "SetOverrideBindingSpell", "SetOverrideBindingItem",
  "SetOverrideBindingMacro"]) {
  FORBIDDEN_GLOBALS[name] = "key bindings come only from Bindings.xml";
}
// The game's popups are the client's: the addon never writes StaticPopupDialogs and never calls a method of (or
// writes a field of) StaticPopup1 to StaticPopup4. Confirmations use the addon's own dialog (Panel.Confirm).
const POPUP_FRAME = /^StaticPopup[1-4]$/;
// The combat log events may be named only where Core refuses them.
const COMBAT_LOG = /COMBAT_LOG_EVENT/;
const COMBAT_LOG_ALLOWED_IN = new Set(["NoirGuides/Core.lua"]);
// Escapes valid inside a Lua 5.1 quoted string: one of these letters, a quote, a backslash, a newline or digits.
const ESCAPE_OK = /^[abfnrtv\\"'\n\r0-9]$/;

function badEscapes(raw) {
  if (raw[0] !== '"' && raw[0] !== "'") return []; // long bracket strings have no escapes
  const out = [];
  for (let i = 1; i < raw.length - 1; i++) {
    if (raw[i] !== "\\") continue;
    const next = raw[i + 1];
    if (!ESCAPE_OK.test(next)) out.push("\\" + next);
    i++;
  }
  return out;
}

// Returns a list of { file, line, message } for one source text. `rel` is the repo-relative path used in messages
// and for the per-file exceptions.
function lintSource(source, rel) {
  const problems = [];
  const add = (line, message) => problems.push({ file: rel, line, message });
  if (source.charCodeAt(0) === 0xfeff) add(1, "file starts with a byte order mark");
  const firstLine = source.split("\n", 1)[0].replace(/\r$/, "").replace(/^﻿/, "");
  if (!firstLine.startsWith(HEADER)) add(1, `line 1 must start with "${HEADER}"`);

  let ast;
  try {
    ast = luaparse.parse(source.replace(/^﻿/, ""), { luaVersion: "5.1", locations: true, comments: false, scope: true });
  } catch (e) {
    add(e.line || 0, `not valid Lua 5.1: ${e.message}`);
    return problems;
  }
  // The global a chain of fields and indexes starts from (StaticPopup1.text:SetText -> StaticPopup1), or null.
  const rootGlobal = (node) => {
    let at = node;
    while (at && (at.type === "MemberExpression" || at.type === "IndexExpression")) at = at.base;
    return at && at.type === "Identifier" && !at.isLocal ? at.name : null;
  };
  // Walks the tree. Names after a dot or colon and table keys are not variable references and are not visited
  // as identifiers.
  const walk = (node) => {
    if (!node || typeof node !== "object") return;
    if (Array.isArray(node)) { node.forEach(walk); return; }
    const line = node.loc ? node.loc.start.line : 0;
    if (node.type === "Identifier") {
      if (FORBIDDEN_GLOBALS[node.name] && !node.isLocal) add(line, `${node.name} must not be used: ${FORBIDDEN_GLOBALS[node.name]}`);
      return;
    }
    if (node.type === "StringLiteral") {
      for (const esc of badEscapes(node.raw)) add(line, `string escape ${esc} is not valid in Lua 5.1`);
      if (COMBAT_LOG.test(node.raw) && !COMBAT_LOG_ALLOWED_IN.has(rel)) add(line, "the combat log events must not be named outside Core's refusal list");
      return;
    }
    if (node.type === "MemberExpression") {
      const member = node.identifier.name;
      if (node.base.type === "Identifier" && !node.base.isLocal && NOT_IN_51[node.base.name] && NOT_IN_51[node.base.name].includes(member)) {
        add(line, `${node.base.name}.${member} does not exist in Lua 5.1`);
      }
      if (node.indexer === ":" && STRING_METHODS_NOT_IN_51.includes(member)) add(line, `:${member}() is a Lua 5.3 string method`);
      walk(node.base);
      return;
    }
    if (node.type === "TableKeyString") { walk(node.value); return; }
    if (node.type === "AssignmentStatement") {
      for (const target of node.variables) {
        if (target.type !== "MemberExpression" && target.type !== "IndexExpression") continue;
        const root = rootGlobal(target);
        if (root === "StaticPopupDialogs") add(line, "StaticPopupDialogs must not be written: confirmations use the addon's own dialog");
        if (root && POPUP_FRAME.test(root)) add(line, `${root} must not be changed: the game's popups are left alone`);
      }
    }
    if (node.type === "CallExpression" || node.type === "StringCallExpression" || node.type === "TableCallExpression") {
      const callee = node.base;
      if (callee && callee.type === "MemberExpression" && callee.indexer === ":") {
        const root = rootGlobal(callee);
        if (root && POPUP_FRAME.test(root)) add(line, `no method of ${root} may be called: the game's popups are left alone`);
      }
    }
    for (const key of Object.keys(node)) {
      if (key === "loc" || key === "type" || key === "globals") continue;
      walk(node[key]);
    }
  };
  walk(ast);
  return problems.sort((a, b) => a.line - b.line);
}

function luaFilesUnder(dir, rel = "") {
  if (!fs.existsSync(dir)) return [];
  const out = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const childRel = rel ? `${rel}/${e.name}` : e.name;
    if (e.isDirectory()) out.push(...luaFilesUnder(path.join(dir, e.name), childRel));
    else if (e.name.endsWith(".lua")) out.push(childRel);
  }
  return out.sort();
}

// Lints every Lua file of the addon. Returns { files, problems }.
function lintAddon(root) {
  const addonDir = path.join(root, "NoirGuides");
  const files = luaFilesUnder(addonDir).map((f) => `NoirGuides/${f}`);
  const problems = [];
  for (const rel of files) problems.push(...lintSource(fs.readFileSync(path.join(root, rel), "utf8"), rel));
  return { files, problems };
}

module.exports = { HEADER, lintSource, lintAddon };
