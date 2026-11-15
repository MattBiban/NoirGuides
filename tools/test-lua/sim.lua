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

test("the world gives the planner's share of the estimated XP, and grind cards are counted with their places", function()
  -- The share at a level (tools/lib/xp.js yieldAt): YIELD up to YIELD_FROM, YIELD_LATE from YIELD_TO, a straight
  -- line between; the whole estimate for a world that names no share, and one share throughout for a world that
  -- names no late one. tools/test/sim.test.js holds it against the planner's own numbers.
  local pace = { YIELD = 0.6, YIELD_LATE = 0.68, YIELD_FROM = 30, YIELD_TO = 50 }
  eq({ Sim.yieldAt(pace, 1), Sim.yieldAt(pace, 30), Sim.yieldAt(pace, 50), Sim.yieldAt(pace, 60) }, { 0.6, 0.6, 0.68, 0.68 })
  ok(math.abs(Sim.yieldAt(pace, 40) - 0.64) < 1e-12, "halfway between at level 40: " .. tostring(Sim.yieldAt(pace, 40)))
  ok(Sim.yieldAt(pace, 31) > 0.6 and Sim.yieldAt(pace, 49) < 0.68, "rising from level 30 to level 50")
  eq({ Sim.yieldAt({}, 1), Sim.yieldAt({}, 60) }, { 1, 1 }, "no share named: the whole estimate")
  eq({ Sim.yieldAt({ YIELD = 0.6 }, 1), Sim.yieldAt({ YIELD = 0.6 }, 60) }, { 0.6, 0.6 }, "no late share named: one share at every level")
  -- The share scales every XP of the world at the level it is earned at, like --xp-scale: a prepared joiner needs
  -- more of the route to reach a level at a lower yield.
  local function playedTo(level, yield, scale)
    local facts = sampleFacts("ROGUE")
    facts.pace.YIELD = yield
    facts.flat = sampleFlat("ROGUE")
    local p = Sim.prepareJoin(facts, level, scale)
    return { p.expectedFrom, p.server.level, p.server.xp }
  end
  ok(playedTo(3, 0.6)[1] > playedTo(3)[1], "a yield of 0.6 gives less than the whole estimate")
  eq(playedTo(3, 0.6), playedTo(3, nil, 0.6), "the yield and the XP scale are the same factor")
  -- A slow player meets steps under their level: every grind card is counted, and those without a place to grind at.
  local facts = sampleFacts("ROGUE")
  facts.pace.YIELD = 0.3
  local r = play(facts)
  eq(Sim.problems(r, 7), {})
  ok(r.grindCards > 0, "the slow player saw a grind card")
  ok(r.grindNoPlace >= 0 and r.grindNoPlace <= r.grindCards, "grind cards without a place are among them")
  eq(r.gatedAims, 0, "the arrow never aimed at a step under its level")
end)

test("a joiner's past grinds to the gate of a quest far above it before taking it, as the guide would have asked", function()
  -- tools/sim_all.js passes pace.GATE = HARD_TALK + BEHIND (tools/planner/tuning.js gateLevel): a step that accepts a
  -- quest more than that many levels above the player waits for the level, so the player the guide led here has it.
  local function prepared(level, gate, questLevel)
    local facts = sampleFacts("ROGUE")
    facts.pace.GATE = gate
    if questLevel then facts.quests[364].level = questLevel end
    facts.flat = sampleFlat("ROGUE")
    local p = Sim.prepareJoin(facts, level)
    return { from = p.expectedFrom, level = p.server.level, xp = p.server.xp, at = facts.flat[p.expectedFrom] }
  end
  -- The Mindless Ones as a level 9 quest, offered to a character of level 1: its gate is level 4.
  local gated = prepared(4, 5, 9)
  eq({ gated.at.action, gated.at.quest }, { "accept", 364 }, "the past ends at the accept: the level was ground there")
  eq({ gated.level, gated.xp }, { 4, 0 })
  local free = prepared(4, nil, 9)
  ok(free.from > gated.from, "without a gate the same character plays on for the level: action " .. tostring(free.from))
  -- The grind stops at the level the joiner joins at: a joiner of level 3 is not made level 4 for it.
  local capped = prepared(3, 5, 9)
  eq({ capped.at.quest, capped.level }, { 364, 3 })
  -- A quest within the gate of the player's level is not ground for: the sample as it is plays the same with a gate.
  local plain, same = prepared(4, nil), prepared(4, 5)
  eq({ same.from, same.level, same.xp }, { plain.from, plain.level, plain.xp })
end)

test("a joiner's past grinds to a step's level before doing it, never walking through a step under its level", function()
  -- tools/sim_all.js tags every flattened action with its step's minLevel. The engine shows a grind line on a step
  -- under its level, so the player the guide led here has the level; a past that walked on through such steps
  -- (nothing offered, the moves made all the same) ended a continent away from the last thing it did.
  local function prepared(level, minLevel)
    local facts = sampleFacts("ROGUE")
    facts.flat = sampleFlat("ROGUE")
    for _, a in ipairs(facts.flat) do
      if a.step == "t363.a364.a376" then a.minLevel = minLevel end
    end
    local p = Sim.prepareJoin(facts, level)
    return { from = p.expectedFrom, level = p.server.level, at = facts.flat[p.expectedFrom] }
  end
  local held = prepared(4, 4)
  eq({ held.at.step, held.at.action, held.level }, { "t363.a364.a376", "turnin", 4 }, "the level was ground at the step's first action")
  local free = prepared(4, nil)
  ok(free.from > held.from, "without a level on the step the same character plays on for the level: action " .. tostring(free.from))
  -- The grind stops at the level the joiner joins at.
  local capped = prepared(3, 4)
  eq({ capped.at.step, capped.level }, { "t363.a364.a376", 3 })
  -- A step at or under the player's level is not ground for.
  local plain, same = prepared(4, nil), prepared(4, 1)
  eq({ same.from, same.level }, { plain.from, plain.level })
end)

test("the player does not act on a card in the instant it appears: steps that pass by themselves are waited out", function()
  -- Found by the simulator's joiners: after a run of steps that passed by themselves, a flight on the other continent
  -- became the place at the very end of the player's wait. It was moot (the next move came back to where the player
  -- stood) and would have passed a moment later, but the player had already walked to it: a step it "cannot do".
  for notes = 0, 10 do
    local r = play(sampleFacts("ROGUE"), { afterLoad = function(c)
      local steps = c.G.Noir.Routes.Get("horde-undead").sections[1].steps
      local at = 2
      for n = 1, notes do
        table.insert(steps, at, { id = "note" .. n, lines = { { kind = "note", text = "Nothing to do here." } } })
        at = at + 1
      end
      table.insert(steps, at, { id = "g14x", at = { zone = 14, x = 51, y = 13.9, r = 20 },
        lines = { { kind = "goto", at = { zone = 14, x = 51, y = 13.9, r = 20 } } } })
      table.insert(steps, at + 1, { id = "zep85", at = { zone = 14, x = 51, y = 13.9, r = 15 },
        lines = { { kind = "transport", mode = "zeppelin", at = { zone = 14, x = 51, y = 13.9, r = 15 }, to = { zone = 85, x = 60.7, y = 58.8 } } } })
    end })
    eq(r.cannot, {}, "with " .. notes .. " steps passing before the moot walk")
    eq(Sim.problems(r, 7), {})
  end
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
