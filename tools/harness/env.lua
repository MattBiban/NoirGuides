-- Noir Guides, GPLv3. See LICENSE.
-- Builds the global table the addon runs in: the Lua 5.1 standard library as the game exposes it, plus the game's
-- global aliases (format, tinsert, strsplit, wipe, bit, ...). This file runs in the test VM (Lua 5.3) and may use
-- 5.3 features; the addon may not. Differences that cannot be hidden are listed in docs/ENGINE-NOTES.md.
HARNESS = HARNESS or {}
local Env = {}

local function copy(t, without)
  local out = {}
  for k, v in pairs(t) do
    if not (without and without[k]) then out[k] = v end
  end
  return out
end

-- Lua 5.1 prints every number with "%.14g"; Lua 5.3 prints floats that hold whole numbers as "5.0".
local function tostring51(v)
  if math.type(v) == "float" then
    if v ~= v then return "nan" end
    if v == math.huge then return "inf" end
    if v == -math.huge then return "-inf" end
    return string.format("%.14g", v)
  end
  return tostring(v)
end

-- string.format as in 5.1: %s goes through the 5.1 tostring, and %d, %x, %c accept numbers with a fraction
-- (5.1 truncates them where 5.3 raises an error).
local function format51(fmt, ...)
  local args, n = { ... }, select("#", ...)
  local i = 0
  for conv in string.gmatch(fmt, "%%[%-+ #0]*%d*%.?%d*([%a%%])") do
    if conv ~= "%" then
      i = i + 1
      local v = args[i]
      if conv == "s" then
        if type(v) == "number" then args[i] = tostring51(v) end
      elseif (conv == "d" or conv == "i" or conv == "x" or conv == "X" or conv == "c" or conv == "o" or conv == "u")
        and math.type(v) == "float" and v == v and v ~= math.huge and v ~= -math.huge then
        args[i] = (v >= 0) and math.floor(v) or math.ceil(v)
      end
    end
  end
  return string.format(fmt, table.unpack(args, 1, n))
end

local function strsplit(delims, text, pieces)
  assert(type(delims) == "string" and type(text) == "string", "strsplit(delimiters, text [, pieces])")
  local out, start = {}, 1
  local class = "[" .. delims:gsub("[%]%^%-%%]", "%%%0") .. "]"
  while true do
    if pieces and #out + 1 >= pieces then break end
    local at = string.find(text, class, start)
    if not at then break end
    out[#out + 1] = string.sub(text, start, at - 1)
    start = at + 1
  end
  out[#out + 1] = string.sub(text, start)
  return table.unpack(out)
end

local function strtrim(text, chars)
  if chars then
    local class = "[" .. chars:gsub("[%]%^%-%%]", "%%%0") .. "]"
    return (text:gsub("^" .. class .. "+", ""):gsub(class .. "+$", ""))
  end
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function strjoin(sep, ...)
  local parts = { ... }
  for i = 1, select("#", ...) do parts[i] = tostring51(parts[i]) end
  return table.concat(parts, sep)
end

-- pairs that visits the keys in the opposite order to the VM's. The order of pairs is unspecified and differs
-- between this VM and the game, so the runner plays every test a second time with this one: code that only
-- works for one order fails one of the two runs.
local function reversedPairs(t)
  local keys = {}
  for k in next, t do keys[#keys + 1] = k end
  local i = #keys + 1
  return function()
    while i > 1 do
      i = i - 1
      local k = keys[i]
      local v = rawget(t, k)
      if v ~= nil then return k, v end -- a key removed during the loop is skipped, as with the real pairs
    end
    return nil
  end
end

-- `hooks.print(text)` receives what the addon prints. HARNESS.pairsMode = "reversed" selects reversedPairs.
function Env.new(hooks)
  local G = {}

  local str = copy(string, { pack = true, unpack = true, packsize = true })
  str.format = format51
  -- Method calls on strings (text:format(...)) reach the same 5.1 library.
  getmetatable("").__index = str
  local tbl = copy(table, { unpack = true, pack = true, move = true })
  tbl.getn = function(t) return #t end
  tbl.maxn = function(t)
    local n = 0
    for k in pairs(t) do if type(k) == "number" and k > n then n = k end end
    return n
  end
  tbl.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
  local mth = copy(math, { tointeger = true, type = true, ult = true, maxinteger = true, mininteger = true })
  mth.pow = function(a, b) return a ^ b end
  mth.log10 = function(a) return math.log(a, 10) end
  mth.mod = math.fmod
  -- Lua 5.1 has math.atan2 and a one-argument math.atan; 5.3 folded the first into the second.
  mth.atan2 = function(y, x) return math.atan(y, x) end
  mth.atan = function(v) return math.atan(v) end

  G._G = G
  G._VERSION = "Lua 5.1"
  G.string, G.table, G.math = str, tbl, mth
  G.coroutine = copy(coroutine, { isyieldable = true })
  for _, name in ipairs({ "assert", "error", "ipairs", "next", "pairs", "pcall", "select", "type", "tonumber",
    "rawequal", "rawget", "rawset", "setmetatable", "getmetatable", "collectgarbage" }) do
    G[name] = _G[name]
  end
  G.tostring = tostring51
  if HARNESS.pairsMode == "reversed" then G.pairs = reversedPairs end
  G.unpack = table.unpack
  -- Lua 5.1's xpcall takes no extra arguments. Whether the game's does is unverified, so the addon may not rely on it.
  G.xpcall = function(f, handler, ...)
    if select("#", ...) > 0 then error("xpcall with arguments is not Lua 5.1", 2) end
    return xpcall(f, handler)
  end
  G.loadstring = function(source, chunkName)
    return load(source, chunkName or "=(loadstring)", "t", G)
  end
  G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring51((select(i, ...))) end
    hooks.print(table.concat(parts, " "))
  end
  G.gcinfo = function() return math.floor(collectgarbage("count")) end

  -- The game's global aliases for library functions.
  G.format, G.strsub, G.strfind, G.strmatch, G.gsub, G.gmatch = format51, string.sub, string.find, string.match, string.gsub, string.gmatch
  G.strlower, G.strupper, G.strlen, G.strrep, G.strbyte, G.strchar, G.strrev = string.lower, string.upper, string.len, string.rep, string.byte, string.char, string.reverse
  G.strsplit, G.strtrim, G.strjoin = strsplit, strtrim, strjoin
  str.split, str.trim, str.join = strsplit, strtrim, strjoin
  G.tinsert, G.tremove, G.sort, G.getn, G.wipe = table.insert, table.remove, table.sort, tbl.getn, tbl.wipe
  G.tContains = function(t, item)
    for _, v in pairs(t) do if v == item then return true end end
    return false
  end
  G.floor, G.ceil, G.abs, G.min, G.max, G.sqrt, G.random, G.mod = math.floor, math.ceil, math.abs, math.min, math.max, math.sqrt, math.random, math.fmod
  G.sin = function(deg) return math.sin(math.rad(deg)) end -- the game's global trig works in degrees
  G.cos = function(deg) return math.cos(math.rad(deg)) end
  G.bit = {
    band = function(a, b) return (a & b) & 0xFFFFFFFF end,
    bor = function(a, b) return (a | b) & 0xFFFFFFFF end,
    bxor = function(a, b) return (a ~ b) & 0xFFFFFFFF end,
    bnot = function(a) return (~a) & 0xFFFFFFFF end,
    lshift = function(a, n) return (a << n) & 0xFFFFFFFF end,
    rshift = function(a, n) return (a & 0xFFFFFFFF) >> n end,
  }
  G.date, G.time = os.date, os.time
  G.debugstack = function() return debug.traceback("", 2) end
  return G
end

Env.tostring51 = tostring51
HARNESS.Env = Env
