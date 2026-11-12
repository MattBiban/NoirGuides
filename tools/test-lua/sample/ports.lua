-- Noir Guides, GPLv3. See LICENSE.
-- Shared by the tests of the ported modules (Talents, Professions, Cleanup, Menu, Diagnostics): the sample data and
-- routes, plus the generated data those modules read (NoirGuides/Data/Talents.lua, Professions.lua, Cleanup.lua).
use("tools/test-lua/sample/helper.lua")
local Client = HARNESS.Client

local DATA = { SAMPLE3_DATA, "NoirGuides/Data/Talents.lua", "NoirGuides/Data/Professions.lua", "NoirGuides/Data/Cleanup.lua" }

PORT_SWAP = {
  { match = "^Data/", with = DATA },
  { match = "^Routes/", with = SAMPLE3_ROUTES },
}

-- A client with the sample routes and the ported modules' data, not logged in yet.
function ported(opts)
  opts = opts or {}
  if opts.swap == nil then opts.swap = PORT_SWAP end
  return Client.new(opts)
end

-- A logged-in client whose character has a route written in the test (Horde Orc in Durotar unless opts say else),
-- with the ported modules' data. `steps` are format 3 steps; they become the one section of the route file.
function portedRoute(steps, opts)
  opts = opts or {}
  opts.race = opts.race or "Orc"
  opts.zone = opts.zone or 14
  opts.swap = { { match = "^Data/", with = DATA }, { match = "^Routes/", with = {} } }
  local info = Client.RACES[opts.race]
  opts.afterLoad = function(client)
    local section = {
      id = "test-01-10-route", name = "1-10 Test Route", group = info.faction, subgroup = "1-20",
      minLevel = 1, maxLevel = 10, zone = opts.zone, start = true, next = {}, steps = copy(steps),
    }
    local file = info.faction:lower() .. "-" .. opts.race:lower()
    assert(client.G.Noir.Route(file, { format = 3, race = opts.race, faction = info.faction, sections = { section } }),
      "the test's route is valid format 3")
  end
  local c = Client.new(opts):login()
  return c, c.G.Noir
end

-- The font strings of a frame and the frames inside it that are shown, as one string per line.
function shownText(c, frame)
  local out = {}
  for _, region in ipairs(c:regionsOf(frame)) do
    if region.__type == "FontString" then
      local at, visible = region, true
      while at do
        if not at.__shown then visible = false end
        at = at.__parent
      end
      if visible and region.__text and region.__text ~= "" then out[#out + 1] = region.__text end
    end
  end
  return table.concat(out, "\n")
end
