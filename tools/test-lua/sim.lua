-- Noir Guides, GPLv3. See LICENSE.
-- The simulator v3 (tools/harness/sim.lua, plan task X1): the whole addon plays the format 3 sample routes in the
-- mock client while the scripted player reads Progress.Cards() only, does every open active line with the mouse and
-- the world, and never types a command.
use("tools/test-lua/sample/helper.lua")
use("tools/harness/sim.lua")
local Sim = HARNESS.Sim

local DEATHKNELL = "undead-01-03-deathknell"
local TIRISFAL = "undead-03-05-tirisfal-glades"
local SILVERPINE = "undead-05-06-silverpine-forest"
local SWAP = {
  { match = "^Data/", with = { SAMPLE3_DATA } },
  { match = "^Routes/", with = SAMPLE3_ROUTES },
}

-- The quest facts of tools/sim_all.js for the sample world: the same zones, maps and flight points as the sample's
-- Data file (tools/test-lua/sample/v3/data.lua), and the givers and takers the sample route names.
local function quest(title, level, kills, items, objects)
  return { title = title, level = level, minLevel = 1, pre = {}, preAny = {}, exclusive = {}, kills = kills or 0,
    items = items or 0, objects = objects or 0, credits = 0, event = false }
end

local function xpTable()
  local t, xp = {}, { 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600 }
  for level = 1, 59 do t[level] = xp[level] or (level * 1000) end
  return t
end

local function sampleFacts(class)
  local facts = {
    race = "Undead", class = class or "ROGUE",
    start = { zone = 85, x = 30.2, y = 71.6 },
    xpToLevel = xpTable(),
    pace = { OBJECTIVE_KILLS = 8, ITEM_KILL_FACTOR = 2, INCIDENTAL_YARDS = 300 },
    continents = {
      [0] = { uiMap = 1415, name = "Eastern Kingdoms", top = 5000, left = 4000, width = 12000, height = 8000 },
      [1] = { uiMap = 1414, name = "Kalimdor", top = 12000, left = 4000, width = 15000, height = 10000 },
    },
    zones = {
      [85] = { uiMap = 1420, name = "Tirisfal Glades", continent = 0, minX = 2600, maxX = 4200, minY = -2000, maxY = 400 },
      [130] = { uiMap = 1421, name = "Silverpine Forest", continent = 0, minX = 1600, maxX = 2800, minY = -800, maxY = 1000 },
      [1497] = { uiMap = 1458, name = "Undercity", continent = 0, minX = 2800, maxX = 3100, minY = -1800, maxY = -1300 },
      [14] = { uiMap = 1411, name = "Durotar", continent = 1, minX = 6500, maxX = 8000, minY = -6500, maxY = -4250 },
    },
    quests = {
      [363] = quest("Rude Awakening", 1),
      [364] = quest("The Mindless Ones", 2, 2),
      [376] = quest("The Damned", 2, 1),
      [3901] = quest("Rattling the Rattlecages", 2, 1),
      [8] = quest("A Rogue's Deal", 2),
      [365] = quest("Fields of Grief", 4, 0, 0, 2),
      [367] = quest("A New Plague", 7),
      [370] = quest("At War With The Scarlet Crusade", 5),
      [435] = quest("Escorting Erland", 6),
    },
    npcs = {
      [1568] = { name = "Undertaker Mordo", offers = { 363 }, ends = {} },
      [1569] = { name = "Shadow Priest Sarvis", offers = { 364, 376 }, ends = { 363, 364, 376 } },
      [1570] = { name = "Executor Arren", offers = { 3901 }, ends = { 3901 } },
      [2122] = { name = "David Trias", offers = { 8 }, ends = {} },
      [1518] = { name = "Apothecary Johaan", offers = { 365, 367 }, ends = { 365 } },
      [1500] = { name = "Coleman Farthing", offers = { 370 }, ends = {} },
      [4551] = { name = "Michael Garrett", offers = {}, ends = {}, taxi = 384 },
      [2226] = { name = "Karos Razok", offers = {}, ends = {}, taxi = 10 },
      [5688] = { name = "Innkeeper Renee", offers = {}, ends = {}, binder = "Brill" },
      [1950] = { name = "Rane Yorick", offers = { 435 }, ends = {} },
      [1951] = { name = "Quinn Yorick", offers = {}, ends = { 435 } },
    },
    objects = {},
    taxi = {
      [384] = { name = "Brill, Tirisfal Glades", continent = 0, zone = 85, x = 58.9, y = 51.9, npc = 4551 },
      [10] = { name = "The Sepulcher, Silverpine Forest", continent = 0, zone = 130, x = 45.6, y = 42.6, npc = 2226 },
      [11] = { name = "Undercity, Tirisfal", continent = 0, zone = 1497, x = 63.3, y = 48.5 },
    },
  }
  return facts
end

-- The flattened actions of the sample for one class, as tools/sim_all.js flattenFor writes them: the chain from
-- the start section, the steps and lines whose `when` holds, one action per line with a counterpart (one per quest
-- for objectives), each tagged with its section and step.
local function applies(when, class)
  if type(when) ~= "table" then return true end
  if when.class and when.class ~= class then return false end
  if when.profession then return false end
  return true
end

local function sampleFlat(class)
  local route = sampleRoute(SAMPLE3_ROUTES[1])
  local byId = {}
  for _, s in ipairs(route.sections) do byId[s.id] = s end
  local section, out = nil, {}
  for _, s in ipairs(route.sections) do if s.start then section = s end end
  while section do
    for _, step in ipairs(section.steps) do
      if applies(step.when, class) then
        local seen = {}
        for _, line in ipairs(step.lines) do
          if applies(line.when, class) then
            local a
            local at = line.at or step.at
            if line.kind == "accept" or line.kind == "turnin" then
              a = { action = line.kind, quest = line.quest, npc = line.npc, object = line.object, at = at }
            elseif line.kind == "objective" and not seen[line.quest] then
              seen[line.quest] = true
              a = { action = "objective", quest = line.quest, at = at }
            elseif line.kind == "getflight" then a = { action = "getflight", node = line.node, npc = line.npc, at = at }
            elseif line.kind == "sethearth" then a = { action = "sethearth", npc = line.npc, at = at }
            elseif line.kind == "fly" then a = { action = "fly", from = line.from, to = line.to, at = at }
            elseif line.kind == "goto" then a = { action = "travel", at = line.at }
            elseif line.kind == "transport" then a = { action = "transport", at = line.at, to = line.to }
            elseif line.kind == "hearth" then a = { action = "hearth", to = line.to }
            elseif line.kind == "grind" then a = { action = "grind", level = line.level, at = at }
            end
            if a then
              a.section, a.step = section.id, step.id
              out[#out + 1] = a
            end
          end
        end
      end
    end
    local nextSection
    for _, n in ipairs(section.next or {}) do
      if not nextSection and byId[n.section] and applies(n.when, class) then nextSection = byId[n.section] end
    end
    section = nextSection
  end
  return out
end

local function play(facts, opts)
  opts = opts or {}
  opts.swap = SWAP
  opts.endLevel = opts.endLevel or 7
  facts.flat = facts.flat or sampleFlat(facts.class)
  return Sim.play(facts, opts)
end

test("a fresh character plays the v3 sample to its end without a command", function()
  local r = play(sampleFacts("ROGUE"))
  eq(r.stuck, {}, "stuck")
  eq(r.cannot, {}, "cannot")
  eq(r.unexplained, {}, "unexplained")
  eq(r.errors, {}, "errors")
  eq(r.slash, 0, "slash commands")
  eq(r.offScreen, {}, "off screen")
  eq(r.finished, true, "the route was played to its end")
  ok(r.level >= 7, "the grind to the step at level 7 was played: level " .. tostring(r.level))
  eq(r.join, nil)
  eq(r.wizardClosed, true, "the level 1 character closed the setup wizard with its close button")
  eq(Sim.problems(r, 7), {})
end)

test("a joiner at the second sample section's level is placed there and plays on", function()
  local facts = sampleFacts("ROGUE")
  local r = play(facts, { join = 4 })
  eq(r.join, 4)
  local p = r.placement
  ok(p and p.expectedFrom and p.landed, "placement is reported")
  eq(facts.flat[p.landed].section, TIRISFAL, "landed in the second section")
  ok(p.inside, string.format("placed inside its window: landed %s, expected from %s (window %s to %s)",
    tostring(p.landed), tostring(p.expectedFrom), tostring(p.from), tostring(p.to)))
  ok(p.passedSteps > 0, "steps passed by placement")
  eq(r.stuck, {}, "stuck")
  eq(r.unexplained, {}, "unexplained")
  eq(r.errors, {}, "errors")
  eq(r.slash, 0)
  eq(r.finished, true)
  eq(r.wizardClosed, nil, "no wizard above level 1")
  eq(Sim.problems(r, 7), {})
end)

test("a stuck card is ticked with the mouse and reported", function()
  local facts = sampleFacts("ROGUE")
  -- Executor Arren takes nothing back in this world: the hand-in of Rattling the Rattlecages cannot be done.
  facts.npcs[1570].ends = {}
  local r = play(facts)
  eq(#r.stuck, 1, "one stuck step")
  eq(r.stuck[1].step, "t3901")
  has(r.stuck[1].reason, "does not take quest 3901")
  eq(r.ticked, 1, "its open line was ticked through the window's tick box")
  eq(r.slash, 0, "no command was typed")
  eq(r.unexplained, {}, "the tick is the stuck step's, not an unexplained skip")
  eq(r.finished, true, "the run plays on to the end")
  eq(Sim.problems(r, 7), { "1 stuck step" })
end)

test("a slash command fails the run", function()
  local r = play(sampleFacts("ROGUE"), { beforeAction = function(c, n)
    if n == 3 then c:slash("/noir step") end
  end })
  eq(r.slash, 1)
  eq(r.finished, true)
  eq(Sim.problems(r, 7), { "1 slash command" })
end)

test("a run below its end level, off the screen or placed outside its window fails", function()
  local base = { finished = true, level = 60, stuck = {}, cannot = {}, unexplained = {}, errors = {}, slash = 0, offScreen = {} }
  eq(Sim.problems(base), {})
  local low = copy(base)
  low.level = 42
  eq(Sim.problems(low), { "ends at level 42" })
  local off = copy(base)
  off.offScreen = { "NoirGuidesWindow" }
  eq(Sim.problems(off), { "1 frame off the screen" })
  local joiner = copy(base)
  joiner.join, joiner.placement = 25, { expectedFrom = 300, landed = 100, from = 260, to = 301, inside = false }
  eq(Sim.problems(joiner), { "placed at action 100, outside 260 to 301" })
end)
