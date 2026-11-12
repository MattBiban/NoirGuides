-- Noir Guides, GPLv3. See LICENSE.
-- Routes: registration and validation of route format 3, and finding the file for the character's race.
use("tools/test-lua/sample/helper.lua")
local CASES = use("tools/test-lua/sample/format3-cases.lua")

local FORMAT_SENTENCE = "it is in format 2 and this version of the addon reads format 3"

local function loaded(opts)
  local c = sample3(opts)
  c:loadAddon()
  return c, c.G.Noir, c.G.Noir.Routes
end

-- The valid base route of the case file, as a fresh copy.
local function baseRoute()
  for _, case in ipairs(CASES) do
    if case.name == "the base route" then return copy(case.route) end
  end
  error("the case file has no base route")
end

local function keysOf(t)
  local out = {}
  for k in pairs(t) do out[#out + 1] = tostring(k) end
  table.sort(out)
  return out
end

test("every case in format3-cases.lua gets the same verdict from Routes.Check as from checkRoute3", function()
  local _, _, Routes = loaded()
  ok(#CASES >= 100, "the case file holds the cases")
  for _, case in ipairs(CASES) do
    local before = copy(case.route)
    local want = nil
    if not case.valid then want = case.expect end
    eq(Routes.Check(case.route), want, case.rule .. " " .. case.name)
    eq(case.route, before, case.name .. ": the check changes nothing")
  end
end)

test("a format 2 file is refused with the format sentence and listed in /noir problems", function()
  local c, Noir, Routes = loaded()
  local registered = Noir.Route("horde-orc", { format = 2, race = "Orc", faction = "Horde",
    steps = { { action = "accept", quest = 1, at = { zone = 14, x = 1, y = 1 } } } })
  eq(registered, false)
  eq(Routes.Get("horde-orc"), nil)
  eq(Routes.rejected["horde-orc"], FORMAT_SENTENCE)
  eq(#Noir.problems, 1)
  has(Noir.problems[1], "horde-orc")
  has(Noir.problems[1], FORMAT_SENTENCE)
  c:login()
  c:takeChat()
  c:slash("/noir problems")
  has(c:chatText(), "horde-orc")
  has(c:chatText(), FORMAT_SENTENCE)
end)

test("a refused file does not stop the next file from registering", function()
  local _, Noir, Routes = loaded()
  eq(Noir.Route("horde-orc", { format = 2, race = "Orc", faction = "Horde", steps = {} }), false)
  eq(Noir.Route(nil, baseRoute()), false)
  eq(Noir.Route("horde-tauren", "not a table"), false)
  local troll = baseRoute()
  troll.race = "Troll"
  eq(Noir.Route("horde-troll", troll), true)
  ok(Routes.Get("horde-troll"), "the file after the refused ones is registered")
  eq(Routes.Ids(), { "alliance-human", "horde-troll", "horde-undead" })
  eq(#Noir.problems, 3)
  has(Noir.problems[2], "(no id)")
  has(Noir.problems[3], "the route data is not a table")
end)

test("a refused file is refused whole, with the first problems named", function()
  local _, Noir, Routes = loaded()
  local route = baseRoute()
  route.race = "Orc"
  route.sections[2].steps[1].lines[1].kind = "dance"
  eq(Noir.Route("horde-orc", route), false)
  eq(Routes.Get("horde-orc"), nil)
  eq(Routes.rejected["horde-orc"], 'section undead-03-05-tirisfal-glades step l5@85 line 1 has the unknown kind "dance"')
end)

test("registering the same id twice keeps the first and reports the second", function()
  local _, Noir, Routes = loaded()
  local first = Routes.Get("horde-undead")
  eq(Noir.Route("horde-undead", baseRoute()), false)
  ok(Routes.Get("horde-undead") == first, "the first file is kept")
  has(Noir.problems[1], "horde-undead")
  has(Noir.problems[1], "twice")
  eq(Routes.rejected["horde-undead"], nil, "the registered file is not marked refused")
end)

test("steps get n, sections get file, and nothing else is added", function()
  local _, Noir, Routes = loaded()
  local route = baseRoute()
  route.race = "Orc"
  local before = copy(route)
  eq(Noir.Route("horde-orc", route), true)
  local got = Routes.Get("horde-orc")
  ok(got == route, "the registered route is the file's own table")
  eq(keysOf(got), keysOf(before), "the route's own fields")
  for i, section in ipairs(got.sections) do
    eq(section.file, "horde-orc")
    local old = before.sections[i]
    local expected = keysOf(old)
    expected[#expected + 1] = "file"
    table.sort(expected)
    eq(keysOf(section), expected, section.id)
    for k, step in ipairs(section.steps) do
      eq(step.n, k, section.id .. " step " .. step.id)
      local oldStep = old.steps[k]
      local stepKeys = keysOf(oldStep)
      stepKeys[#stepKeys + 1] = "n"
      table.sort(stepKeys)
      eq(keysOf(step), stepKeys, step.id)
      eq(step.lines, oldStep.lines, step.id .. ": lines are untouched")
    end
  end
end)

test("the two v3 samples register without a problem", function()
  local _, Noir, Routes = loaded()
  eq(Noir.problems, {})
  eq(Routes.Ids(), { "alliance-human", "horde-undead" })
  local undead = Routes.Get("horde-undead")
  eq(#undead.sections, 3)
  local count = 0
  for _, section in ipairs(undead.sections) do count = count + #section.steps end
  ok(count >= 30, count .. " steps")
  eq(#Routes.Get("alliance-human").sections, 1)
  eq(#Routes.Get("alliance-human").sections[1].steps, 4)
  eq(Routes.Get("no-such-route"), nil)
end)

test("the Undead sample uses every line kind and every step field", function()
  local route = sampleRoute(SAMPLE3_ROUTES[1])
  local kinds, fields = {}, {}
  for _, section in ipairs(route.sections) do
    for _, step in ipairs(section.steps) do
      for key in pairs(step) do fields[key] = true end
      for _, line in ipairs(step.lines) do kinds[line.kind] = true end
    end
  end
  for kind in ([[accept turnin objective collect goto getflight fly transport sethearth hearth grind train vendor use
    target note manual]]):gmatch("%S+") do ok(kinds[kind], "line kind " .. kind) end
  for field in ([[id at text title lines when minLevel maxLevel label requires reminder skip load items targets path]]):gmatch("%S+") do
    ok(fields[field], "step field " .. field)
  end
  eq(route.sections[1].next[1], { section = "undead-05-06-silverpine-forest", when = { class = "HUNTER" } })
end)

test("ForRace finds the file for the character's race and faction", function()
  local _, Noir, Routes = loaded()
  eq(Routes.ForRace("Undead", "Horde"), "horde-undead")
  eq(Routes.ForRace("Human", "Alliance"), "alliance-human")
  eq(Routes.ForRace("Human", "Horde"), nil)
  eq(Routes.ForRace("Orc", "Horde"), nil)
  eq(Routes.ForRace(nil, nil), nil)
  -- A second file for one race: the first ID in order is used and the clash is reported.
  eq(Noir.Route("horde-undead-b", baseRoute()), true)
  eq(Routes.ForRace("Undead", "Horde"), "horde-undead")
  has(table.concat(Noir.problems, "\n"), "horde-undead-b")
end)

test("each of the ten races finds its own file, Skyborne by race ID", function()
  local races = {
    Human = "Alliance", Dwarf = "Alliance", Gnome = "Alliance", NightElf = "Alliance", HighOrder = "Alliance",
    Orc = "Horde", Troll = "Horde", Tauren = "Horde", Undead = "Horde", Windshaper = "Horde",
  }
  local files = { "NoirGuides/Core.lua", "NoirGuides/State.lua", "NoirGuides/Routes.lua" }
  for race, faction in pairs(races) do
    local c = HARNESS.Client.new({ race = race, files = files })
    c:loadAddon()
    for other, otherFaction in pairs(races) do
      local route = baseRoute()
      route.race, route.faction = other, otherFaction
      for _, section in ipairs(route.sections) do section.group = otherFaction end
      eq(c.G.Noir.Route(otherFaction:lower() .. "-" .. other:lower(), route), true, other)
    end
    c:login()
    eq(c.G.Noir.Routes.ForRace(c.G.Noir.State.race, c.G.Noir.State.faction), faction:lower() .. "-" .. race:lower(), race)
    eq((c.G.Noir.Routes.Current()), faction:lower() .. "-" .. race:lower(), race)
    eq(c.G.Noir.problems, {}, race)
  end
end)

test("at login the race's file is the current route; a race without one gets a clear problem", function()
  local c = sample3({ race = "Undead", class = "ROGUE" }):login()
  eq((c.G.Noir.Routes.Current()), "horde-undead")
  eq(c.G.Noir.problems, {})
  local t = sample3({ race = "Tauren", class = "DRUID" }):login()
  eq(t.G.Noir.Routes.Current(), nil)
  has(table.concat(t.G.Noir.problems, "\n"), "Tauren")
  has(t:chatText(), "/noir problems")
end)

test("/noir state names the race's file and its sections", function()
  local c = sample3({ race = "Undead", class = "ROGUE" }):login()
  c:takeChat()
  c:slash("/noir state")
  has(c:chatText(), "horde-undead")
  has(c:chatText(), "3 sections")
end)
