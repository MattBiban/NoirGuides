-- Noir Guides, GPLv3. See LICENSE.
-- Shared by the test files: a client that loads the real engine files from the toc with the format 3 sample data
-- and routes (tools/test-lua/sample/v3/) in place of the generated ones.
local Client = HARNESS.Client

SAMPLE3_DATA = "tools/test-lua/sample/v3/data.lua"
SAMPLE3_ROUTES = { "tools/test-lua/sample/v3/horde-undead.lua", "tools/test-lua/sample/v3/alliance-human.lua" }

local SWAP3 = {
  { match = "^Data/", with = { SAMPLE3_DATA } },
  { match = "^Routes/", with = SAMPLE3_ROUTES },
}

-- sample3(opts) -> a client that has not logged in yet, with the v3 samples. opts as for Client.new.
function sample3(opts)
  opts = opts or {}
  if opts.swap == nil then opts.swap = SWAP3 end
  return Client.new(opts)
end

-- The format 2 samples are gone: every test that asks for "the sample" gets the format 3 one.
sample = sample3

-- A deep copy of a table (routes are plain data).
function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = copy(v) end
  return out
end

-- The data of a v3 sample route file, as the file passes it to Noir.Route, without loading the addon.
function sampleRoute(path)
  local caught
  local env = setmetatable({ Noir = { Route = function(_, data) caught = data return true end } }, { __index = _G })
  local chunk = assert(load(assert(host.read(path)), "@" .. path, "t", env))
  chunk()
  return caught
end
