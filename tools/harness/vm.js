// Noir Guides, GPLv3. See LICENSE.
// A Lua state for the mock client and the Lua tests. The VM is fengari (MIT), which implements Lua 5.3 in JavaScript.
// The game runs Lua 5.1: tools/harness/env.lua builds the 5.1 global table the addon sees and tools/harness/lint.js
// rejects 5.2+ syntax, so between them the addon can only use what the game has. docs/ENGINE-NOTES.md lists what is left.
const fs = require("node:fs");
const path = require("node:path");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");

const ROOT = path.resolve(__dirname, "..", "..");

// Repo-relative path with forward slashes to an absolute one. Paths that leave the repository are refused.
function resolveInRepo(rel) {
  const abs = path.resolve(ROOT, rel);
  if (abs !== ROOT && !abs.startsWith(ROOT + path.sep)) throw new Error(`path leaves the repository: ${rel}`);
  return abs;
}

// `print` receives each line the Lua side prints (default: the console).
function createVm({ print = console.log } = {}) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  lua.lua_pushjsfunction(L, (L) => {
    const parts = [];
    const count = lua.lua_gettop(L);
    for (let i = 1; i <= count; i++) {
      lauxlib.luaL_tolstring(L, i); // pushes the value as a string
      parts.push(lua.lua_tojsstring(L, -1));
      lua.lua_pop(L, 1);
    }
    print(parts.join("\t"));
    return 0;
  });
  lua.lua_setglobal(L, to_luastring("print"));

  // Error values are turned into "message + traceback" strings at the point of the error.
  const traceback = (L) => {
    const msg = lua.lua_tojsstring(L, 1);
    lauxlib.luaL_traceback(L, L, to_luastring(msg === null ? "(error value is not a string)" : msg), 1);
    return 1;
  };

  const host = {
    // host.read(path) -> file contents as a Lua string, or nil and a message.
    read(L) {
      const rel = lua.lua_tojsstring(L, 1);
      try {
        lua.lua_pushstring(L, new Uint8Array(fs.readFileSync(resolveInRepo(rel))));
        return 1;
      } catch (e) {
        lua.lua_pushnil(L);
        lua.lua_pushstring(L, to_luastring(`cannot read ${rel}: ${e.code || e.message}`));
        return 2;
      }
    },
    // host.exists(path) -> boolean.
    exists(L) {
      let found = false;
      try { found = fs.existsSync(resolveInRepo(lua.lua_tojsstring(L, 1))); } catch (e) { found = false; }
      lua.lua_pushboolean(L, found);
      return 1;
    },
    // host.list(dir) -> sorted array of file names (not directories), empty when the directory is missing.
    list(L) {
      let names = [];
      try {
        names = fs.readdirSync(resolveInRepo(lua.lua_tojsstring(L, 1)), { withFileTypes: true })
          .filter((e) => e.isFile()).map((e) => e.name).sort();
      } catch (e) { names = []; }
      lua.lua_createtable(L, names.length, 0);
      names.forEach((n, i) => { lua.lua_pushstring(L, to_luastring(n)); lua.lua_rawseti(L, -2, i + 1); });
      return 1;
    },
  };
  lua.lua_createtable(L, 0, 3);
  for (const [name, fn] of Object.entries(host)) {
    lua.lua_pushjsfunction(L, fn);
    lua.lua_setfield(L, -2, to_luastring(name));
  }
  lua.lua_setglobal(L, to_luastring("host"));

  // Runs a chunk. Returns null on success or the error text with a Lua traceback.
  function run(source, chunkName) {
    lua.lua_pushjsfunction(L, traceback);
    const base = lua.lua_gettop(L);
    const bytes = typeof source === "string" ? to_luastring(source) : source;
    let status = lauxlib.luaL_loadbuffer(L, bytes, bytes.length, to_luastring(chunkName));
    if (status === lua.LUA_OK) status = lua.lua_pcall(L, 0, 0, base);
    let err = null;
    if (status !== lua.LUA_OK) {
      const text = lua.lua_tojsstring(L, -1);
      err = text === null ? "(error value is not a string)" : text;
    }
    lua.lua_settop(L, base - 1);
    return err;
  }
  function runFile(rel) {
    return run(new Uint8Array(fs.readFileSync(resolveInRepo(rel))), "@" + rel);
  }
  function globalNumber(name) {
    lua.lua_getglobal(L, to_luastring(name));
    const n = lua.lua_tonumber(L, -1);
    lua.lua_pop(L, 1);
    return n;
  }

  // The Lua value at `index` as a JavaScript value: a table whose keys are exactly 1..n (an empty table too) becomes
  // an array, any other table an object whose keys are the Lua keys as strings; nil becomes undefined. Functions and
  // other values that have no JavaScript form are refused.
  function toJs(index, depth) {
    if (depth > 64) throw new Error("the Lua value is nested too deeply (or refers to itself)");
    const at = lua.lua_absindex(L, index);
    switch (lua.lua_type(L, at)) {
      case lua.LUA_TNIL: return undefined;
      case lua.LUA_TBOOLEAN: return lua.lua_toboolean(L, at);
      case lua.LUA_TNUMBER: return lua.lua_tonumber(L, at);
      case lua.LUA_TSTRING: return lua.lua_tojsstring(L, at);
      case lua.LUA_TTABLE: {
        const entries = [];
        lauxlib.luaL_checkstack(L, 3, to_luastring("reading a nested Lua table"));
        lua.lua_pushnil(L);
        while (lua.lua_next(L, at) !== 0) {
          let key;
          if (lua.lua_type(L, -2) === lua.LUA_TNUMBER) key = lua.lua_tonumber(L, -2);
          else if (lua.lua_type(L, -2) === lua.LUA_TSTRING) key = lua.lua_tojsstring(L, -2);
          else throw new Error("a Lua table key that is neither a number nor a string has no JavaScript form");
          entries.push([key, toJs(-1, depth + 1)]);
          lua.lua_pop(L, 1);
        }
        const n = entries.length;
        const sequence = entries.every(([k]) => typeof k === "number" && Number.isInteger(k) && k >= 1 && k <= n);
        if (sequence) {
          const out = new Array(n);
          for (const [k, v] of entries) out[k - 1] = v;
          return out;
        }
        const out = {};
        for (const [k, v] of entries) out[String(k)] = v;
        return out;
      }
      default: throw new Error(`a Lua ${lua.lua_typename(L, lua.lua_type(L, at))} has no JavaScript form`);
    }
  }

  // Runs a chunk and returns its first return value as a JavaScript value (see toJs). Throws on a Lua error.
  function value(source, chunkName) {
    lua.lua_pushjsfunction(L, traceback);
    const base = lua.lua_gettop(L);
    const bytes = typeof source === "string" ? to_luastring(source) : source;
    let status = lauxlib.luaL_loadbuffer(L, bytes, bytes.length, to_luastring(chunkName));
    if (status === lua.LUA_OK) status = lua.lua_pcall(L, 0, 1, base);
    try {
      if (status !== lua.LUA_OK) throw new Error(lua.lua_tojsstring(L, -1) || "(error value is not a string)");
      return toJs(-1, 0);
    } finally {
      lua.lua_settop(L, base - 1);
    }
  }
  function valueOfFile(rel) {
    return value(new Uint8Array(fs.readFileSync(resolveInRepo(rel))), "@" + rel);
  }
  return { run, runFile, globalNumber, value, valueOfFile };
}

module.exports = { ROOT, createVm };
