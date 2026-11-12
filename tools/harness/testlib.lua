-- Noir Guides, GPLv3. See LICENSE.
-- The small test library for tools/test-lua/*.lua. Runs in the test VM, outside the addon's globals.
--   test("name", function() ... end)
--   eq(actual, expected [, label])   deep comparison
--   ok(value [, label])              value must be truthy
--   no(value [, label])              value must be nil or false
--   near(actual, expected, tolerance [, label])
--   raises(fn [, pattern])           fn must raise an error (matching the Lua pattern)
--   has(text, piece [, label])       plain substring
--   use(path)                        run a helper file (repo-relative path)
-- After every test, each mock client the test created is checked: a Lua error raised inside the addon or a
-- forbidden call fails the test unless the test took it with client:takeErrors() or client:takeViolations().
HARNESS = HARNESS or {}
local T = { tests = {}, passed = 0, failed = 0, clients = {} }

local function show(v, depth)
  depth = depth or 0
  if type(v) == "string" then return string.format("%q", v) end
  if type(v) ~= "table" then return tostring(v) end
  if depth > 6 then return "{...}" end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    if type(a) == type(b) and (type(a) == "number" or type(a) == "string") then return a < b end
    return tostring(a) < tostring(b)
  end)
  local parts = {}
  for _, k in ipairs(keys) do
    local key = type(k) == "string" and k or ("[" .. tostring(k) .. "]")
    parts[#parts + 1] = key .. " = " .. show(v[k], depth + 1)
  end
  return "{ " .. table.concat(parts, ", ") .. " }"
end

local function same(a, b, seen)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  seen = seen or {}
  if seen[a] == b then return true end
  seen[a] = b
  for k, v in pairs(a) do
    if not same(v, b[k], seen) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

local function fail(message)
  error(message, 3)
end

function test(name, fn)
  assert(type(name) == "string" and type(fn) == "function", "test(name, fn)")
  T.tests[#T.tests + 1] = { name = name, fn = fn }
end

function eq(actual, expected, label)
  if not same(actual, expected) then
    fail((label and (label .. ": ") or "") .. "expected " .. show(expected) .. "\n       but got " .. show(actual))
  end
end

function ok(value, label)
  if not value then fail((label or "value") .. ": expected a true value, got " .. show(value)) end
end

function no(value, label)
  if value then fail((label or "value") .. ": expected nil or false, got " .. show(value)) end
end

function near(actual, expected, tolerance, label)
  if type(actual) ~= "number" or math.abs(actual - expected) > tolerance then
    fail((label and (label .. ": ") or "") .. "expected " .. show(expected) .. " within " .. tolerance .. ", got " .. show(actual))
  end
end

function raises(fn, pattern)
  local good, err = pcall(fn)
  if good then fail("expected an error, but the call succeeded") end
  if pattern and not string.find(tostring(err), pattern) then
    fail("expected an error matching " .. show(pattern) .. ", got " .. show(tostring(err)))
  end
end

function has(text, piece, label)
  if type(text) ~= "string" or not string.find(text, piece, 1, true) then
    fail((label and (label .. ": ") or "") .. "expected " .. show(text) .. " to contain " .. show(piece))
  end
end

-- Runs another Lua file in the test's globals, for shared helpers: use("tools/test-lua/sample/helper.lua").
function use(path)
  local source = assert(host.read(path))
  return assert(load(source, "@" .. path))()
end

T.show = show
T.same = same

-- Called by the mock client so the runner can check it after the test.
function T.track(client)
  T.clients[#T.clients + 1] = client
end

function T.run()
  for _, t in ipairs(T.tests) do
    T.clients = {}
    local good, err = xpcall(t.fn, function(e) return debug.traceback(tostring(e), 2) end)
    if good then
      for _, client in ipairs(T.clients) do
        if #client.errors > 0 then
          good, err = false, "the addon raised " .. #client.errors .. " Lua error(s), first:\n" .. tostring(client.errors[1])
          break
        end
        if #client.violations > 0 then
          good, err = false, "forbidden call: " .. tostring(client.violations[1])
          break
        end
      end
    end
    if good then
      T.passed = T.passed + 1
      print("  ok      " .. t.name)
    else
      T.failed = T.failed + 1
      print("  FAILED  " .. t.name)
      print("          " .. tostring(err):gsub("\n", "\n          "))
    end
  end
  TESTS_PASSED, TESTS_FAILED = T.passed, T.failed
end

HARNESS.T = T
