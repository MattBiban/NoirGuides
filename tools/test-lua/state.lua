-- Noir Guides, GPLv3. See LICENSE.
-- State: what is true about the character right now, refreshed from the client's events.
use("tools/test-lua/sample/helper.lua")

local function login(opts)
  local c = sample(opts):login()
  return c, c.G.Noir.State, c.G.Noir
end

-- Records every NOIR_STATE the engine fires, e.g. { "quests", "level" }.
local function watch(c)
  local seen = {}
  c.G.Noir.On("NOIR_STATE", function(_, what) seen[#seen + 1] = what end)
  return seen
end

local function count(list, what)
  local n = 0
  for _, v in ipairs(list) do if v == what then n = n + 1 end end
  return n
end

-- Character --------------------------------------------------------------------------------------------------

test("class, race, faction and level are known at login", function()
  local _, State = login({ race = "Undead", class = "ROGUE", level = 7 })
  eq(State.class, "ROGUE")
  eq(State.race, "Undead")
  eq(State.faction, "Horde")
  eq(State.level, 7)
end)

test("every race is recognized, the Skyborne races by race ID", function()
  for race, info in pairs(HARNESS.Client.RACES) do
    local _, State, Noir = login({ race = race })
    eq(State.race, race)
    eq(State.faction, info.faction)
    no(table.concat(Noir.problems, "\n"):find("Unknown race", 1, true), race)
  end
end)

test("without a race ID the race comes from the token, and Skyborne from the faction", function()
  for race, info in pairs(HARNESS.Client.RACES) do
    local _, State = login({ race = race, raceId = false })
    eq(State.race, race)
    eq(State.faction, info.faction)
  end
end)

test("level follows PLAYER_LEVEL_UP even though UnitLevel still shows the old level", function()
  local c, State = login({ level = 4 })
  local seen = watch(c)
  local during
  c.G.Noir.On("PLAYER_LEVEL_UP", function() during = { State.level, c.G.UnitLevel("player") } end)
  c:setLevel(5)
  eq(during, { 5, 4 }, "already right while the event is delivered")
  eq(State.level, 5)
  eq(count(seen, "level"), 1)
  c:fire("QUEST_LOG_UPDATE")
  eq(State.level, 5)
end)

test("experience from quests raises the level", function()
  local c, State = login({ level = 1 })
  c:acceptQuest(363)
  c:turnInQuest(363, 450)
  eq(State.level, 2)
  eq(State.xp, 50)
  eq(State.xpMax, 800)
end)

-- Quest log ---------------------------------------------------------------------------------------------------

for _, api in ipairs({ "classic", "modern" }) do
  test(api .. ": accepting a quest puts it in the state with its objectives", function()
    local c, State = login({ api = api })
    local seen = watch(c)
    eq(State.HasQuest(364), false)
    c:acceptQuest(364)
    eq(State.HasQuest(364), true)
    local q = State.Quest(364)
    eq(q.id, 364)
    eq(q.title, "The Mindless Ones")
    eq(q.level, 2)
    eq(q.complete, false)
    eq(q.failed, false)
    eq(#q.objectives, 2)
    eq(q.objectives[1], { text = "Mindless Zombie slain: 0/8", kind = "monster", done = false, have = 0, need = 8 })
    ok(count(seen, "quests") >= 1, "NOIR_STATE quests fired")
  end)

  test(api .. ": objective progress and completion are tracked", function()
    local c, State = login({ api = api })
    c:acceptQuest(364)
    c:progressQuest(364, 1, 3)
    eq(State.Quest(364).objectives[1].have, 3)
    eq(State.Quest(364).objectives[1].done, false)
    eq(State.Quest(364).complete, false)
    c:progressQuest(364, 1, 8)
    eq(State.Quest(364).objectives[1].done, true)
    eq(State.Quest(364).complete, false, "one objective left")
    c:progressQuest(364, 2, 8)
    eq(State.Quest(364).complete, true)
  end)

  test(api .. ": an event objective has no count", function()
    local c, State = login({ api = api })
    c:acceptQuest(435)
    local o = State.Quest(435).objectives[1]
    eq(o.kind, "event")
    eq(o.done, false)
    c:progressQuest(435, 1, true)
    eq(State.Quest(435).objectives[1].done, true)
    eq(State.Quest(435).complete, true)
  end)

  test(api .. ": turning in removes the quest and marks it done", function()
    local c, State = login({ api = api })
    c:acceptQuest(364)
    c:completeObjectives(364)
    local seen = watch(c)
    c:turnInQuest(364, 100)
    eq(State.HasQuest(364), false)
    eq(State.Quest(364), nil)
    eq(State.IsDone(364), true)
    ok(count(seen, "completed") == 1, "NOIR_STATE completed fired once")
    ok(count(seen, "quests") >= 1, "NOIR_STATE quests fired")
  end)

  test(api .. ": a turned-in quest is not 'in the log' even while the client still lists it", function()
    local c, State = login({ api = api })
    c:acceptQuest(364)
    local during
    c.G.Noir.On("QUEST_TURNED_IN", function() during = { State.HasQuest(364), State.IsDone(364) } end)
    c:turnInQuest(364)
    eq(during, { false, true })
  end)

  test(api .. ": abandoning removes the quest without marking it done", function()
    local c, State = login({ api = api })
    c:acceptQuest(364)
    c:abandonQuest(364)
    eq(State.HasQuest(364), false)
    eq(State.IsDone(364), false)
  end)

  test(api .. ": a failed quest is flagged", function()
    local c, State = login({ api = api })
    c:acceptQuest(435)
    c:failQuest(435)
    eq(State.Quest(435).failed, true)
    eq(State.Quest(435).complete, false)
  end)

  test(api .. ": quests done before the addon was installed are known at login", function()
    local c = sample({ api = api })
    c:markCompleted(363)
    c:markCompleted(364)
    c:login()
    local State = c.G.Noir.State
    eq(State.IsDone(363), true)
    eq(State.IsDone(364), true)
    eq(State.IsDone(376), false)
  end)

  test(api .. ": quests in the log at login are read once the server has sent the log", function()
    local c = sample({ api = api })
    c.s.quests = { { id = 376, title = "The Damned", level = 2, header = "Tirisfal Glades", objectives = { { text = "Scavenger Paw", type = "item", need = 6, have = 2 } } } }
    local ready = 0
    c:loadAddon()
    c.G.Noir.On("NOIR_READY", function() ready = ready + 1 end)
    c:login()
    local State = c.G.Noir.State
    eq(ready, 1)
    eq(State.ready, true)
    eq(State.HasQuest(376), true)
    eq(State.Quest(376).objectives[1].have, 2)
    c:fire("QUEST_LOG_UPDATE")
    eq(ready, 1, "ready fires once")
  end)

  test(api .. ": quests under a collapsed header are still found, and the log is flagged as partly hidden", function()
    local c, State = login({ api = api })
    c:acceptQuest(364)
    c:acceptQuest(435)
    c:collapseHeader("Tirisfal Glades", true)
    eq(State.logHidden, true)
    eq(State.HasQuest(364), true, "found by ID")
    eq(State.HasQuest(435), true)
    eq(State.HasQuest(376), false)
    c:progressQuest(364, 1, 5)
    eq(State.Quest(364).objectives[1].have, 5)
    c:collapseHeader("Tirisfal Glades", false)
    eq(State.logHidden, false)
    eq(State.Quest(364).title, "The Mindless Ones")
    eq(c:takeViolations(), {}, "the engine never expands or collapses the player's quest log")
    eq(c.selectionChanges, 0, "the engine never changes the selected quest")
  end)

  test(api .. ": a quest handed in under a collapsed header is not 'in the log' while the client still has it", function()
    local c, State = login({ api = api })
    c:acceptQuest(364)
    c:collapseHeader("Tirisfal Glades", true)
    local during
    c.G.Noir.On("QUEST_TURNED_IN", function()
      during = { c.G.C_QuestLog.IsOnQuest(364), State.HasQuest(364), State.IsDone(364) }
    end)
    c:turnInQuest(364)
    eq(during, { true, false, true })
    eq(State.HasQuest(364), false)
  end)

  test(api .. ": a repeatable quest taken again after handing it in is in the log again", function()
    local c, State = login({ api = api })
    c:acceptQuest(364)
    c:turnInQuest(364)
    c:acceptQuest(364)
    eq(State.HasQuest(364), true)
    eq(State.IsDone(364), true)
  end)
end

test("the state is not ready, and the log not trusted, before the first quest log update", function()
  local c = sample()
  c.s.quests = { { id = 376, title = "The Damned", level = 2, header = "Tirisfal Glades", objectives = {} } }
  c:loadAddon()
  c:fire("ADDON_LOADED", "NoirGuides")
  c.loggedIn = true
  c:fire("PLAYER_LOGIN")
  c:fire("PLAYER_ENTERING_WORLD", true, false)
  local State = c.G.Noir.State
  eq(State.ready, false)
  eq(State.HasQuest(376), false)
  -- No QUEST_LOG_UPDATE arrives: after a few seconds the engine reads the log anyway.
  c.questLogReady = true
  local ready = 0
  c.G.Noir.On("NOIR_READY", function() ready = ready + 1 end)
  c:advance(6)
  eq(State.ready, true)
  eq(ready, 1)
  eq(State.HasQuest(376), true)
end)

test("a quest log update before the character is in the world does not make the state ready", function()
  local c = sample()
  c:loadAddon()
  c:fire("ADDON_LOADED", "NoirGuides")
  c.loggedIn = true
  c:fire("PLAYER_LOGIN")
  c:fire("QUEST_LOG_UPDATE")
  local State = c.G.Noir.State
  eq(State.ready, false)
  c:fire("PLAYER_ENTERING_WORLD", true, false)
  eq(State.ready, false)
  c.questLogReady = true
  c:fire("QUEST_LOG_UPDATE")
  eq(State.ready, true)
end)

test("NOIR_STATE quests fires only when the log really changed", function()
  local c = login()
  c:acceptQuest(364)
  local seen = watch(c)
  c:fire("QUEST_LOG_UPDATE")
  c:fire("QUEST_LOG_UPDATE")
  c:fire("UNIT_QUEST_LOG_CHANGED", "player")
  eq(count(seen, "quests"), 0)
  c:progressQuest(364, 1, 1)
  eq(count(seen, "quests"), 1)
end)

test("quest objectives are read without the by-ID API too", function()
  local c, State = login({ without = { "C_QuestLog.GetQuestObjectives" } })
  c:acceptQuest(376)
  c:progressQuest(376, 2, 4)
  eq(State.Quest(376).objectives[2], { text = "Duskbat Wing: 4/6", kind = "item", done = false, have = 4, need = 6 })
end)

test("IsDone asks the client when the quest was not in the login list", function()
  local c, State = login()
  eq(State.IsDone(363), false)
  c:markCompleted(363) -- done without any event reaching the addon
  eq(State.IsDone(363), true)
end)

-- Flight points -----------------------------------------------------------------------------------------------

for _, taxiIds in ipairs({ true, false }) do
  local label = taxiIds and "taxi API with node IDs" or "taxi API with names only"

  test(label .. ": opening the taxi map records the known flight points", function()
    local c = sample({ taxiIds = taxiIds })
    c:knowFlight(10)
    c:knowFlight(11)
    c:knowFlight(23) -- another continent: not on this map
    c:login()
    local State = c.G.Noir.State
    eq(State.KnowsFlight(10), false, "nothing is known before the map was seen")
    local seen = watch(c)
    c:moveTo({ zone = 85, x = 58.9, y = 51.9 })
    c:openTaxi(384)
    eq(State.KnowsFlight(384), true)
    eq(State.KnowsFlight(10), true)
    eq(State.KnowsFlight(11), true)
    eq(State.KnowsFlight(23), false)
    eq(State.taxiOpen, true)
    eq(State.taxiNode, 384)
    eq(State.taxiSlots[10], 1, "slot for TakeTaxiNode")
    ok(count(seen, "flights") >= 1, "NOIR_STATE flights fired")
    c:closeTaxi()
    eq(State.taxiOpen, false)
    eq(State.taxiNode, nil)
    eq(State.taxiSlots, {})
  end)

  test(label .. ": known flight points survive a relog", function()
    local c = sample({ taxiIds = taxiIds })
    c:login()
    c:moveTo({ zone = 85, x = 58.9, y = 51.9 })
    c:openTaxi(384)
    c:closeTaxi()
    local again = c:relog()
    eq(again.G.Noir.State.KnowsFlight(384), true)
    eq(again.G.Noir.State.KnowsFlight(10), false)
  end)
end

test("a discovery message near a flight point marks that node, before any taxi map", function()
  local c, State = login()
  local discovered = {}
  c.G.Noir.On("NOIR_FLIGHT_DISCOVERED", function(_, node) discovered[#discovered + 1] = tostring(node) end)
  c:moveTo({ zone = 85, x = 59.2, y = 52.3 })
  c:discoverFlight(384)
  eq(State.KnowsFlight(384), true)
  eq(discovered, { "384" })
end)

test("a discovery message far from every known node marks nothing and says so", function()
  local c, State = login()
  local discovered = {}
  c.G.Noir.On("NOIR_FLIGHT_DISCOVERED", function(_, node) discovered[#discovered + 1] = tostring(node) end)
  c:moveTo({ zone = 85, x = 10, y = 10 })
  c:discoverFlight(384)
  eq(State.KnowsFlight(384), false)
  eq(discovered, { "nil" })
end)

test("LearnFlight lets another module record a flight point", function()
  local c, State = login()
  local seen = watch(c)
  State.LearnFlight(10, "step")
  State.LearnFlight(10, "step")
  eq(State.KnowsFlight(10), true)
  eq(count(seen, "flights"), 1)
end)

test("a taxi node name the data does not have is kept for the diagnostics, not guessed", function()
  local c = sample({ taxiIds = false })
  c.world.taxi[999] = { name = "Nowhere, Unknown Lands", continent = 1415, at = { uiMap = 1420, x = 1, y = 1 } }
  c:knowFlight(999)
  c:login()
  c:openTaxi(384)
  local State = c.G.Noir.State
  eq(State.unknownTaxiNames["Nowhere, Unknown Lands"], true)
  eq(State.KnowsFlight(999), false)
end)

-- Neutral towns have one flight point per faction, and both carry the town's name (Booty Bay is nodes 18 and 19).
-- The data says whose each is, and a character only ever deals with its own faction's.
local function twoBootyBays(c)
  local flights = c.G.Noir.Data.flights
  flights[18] = { name = "Booty Bay, Stranglethorn", zone = 85, x = 70, y = 70, factions = "H" }
  flights[19] = { name = "Booty Bay, Stranglethorn", zone = 85, x = 71, y = 71, factions = "A" }
  c.world.taxi[18] = { name = "Booty Bay, Stranglethorn", continent = 1415, at = { uiMap = 1420, x = 70, y = 70 } }
  c.world.taxi[19] = { name = "Booty Bay, Stranglethorn", continent = 1415, at = { uiMap = 1420, x = 71, y = 71 } }
end

test("taxi API with names only: a name two factions' flight points share means the player's own", function()
  for _, race in ipairs({ "Undead", "Human" }) do
    local c = sample({ taxiIds = false, race = race, afterLoad = twoBootyBays })
    c:knowFlight(18)
    c:knowFlight(19)
    c:login()
    c:openTaxi(384)
    local State = c.G.Noir.State
    local mine, theirs = 18, 19
    if race == "Human" then mine, theirs = 19, 18 end
    eq(State.KnowsFlight(mine), true, race)
    eq(State.KnowsFlight(theirs), false, race)
    ok(State.taxiSlots[mine], race .. ": the slot to take the flight")
  end
end)

test("a discovery message marks the nearest flight point of the player's own faction", function()
  local c = sample({ race = "Undead", afterLoad = twoBootyBays }):login()
  c:moveTo({ zone = 85, x = 71, y = 71 }) -- on the Alliance's flight master
  c:discoverFlight(18)
  eq(c.G.Noir.State.KnowsFlight(18), true)
  eq(c.G.Noir.State.KnowsFlight(19), false)
end)

-- Hearthstone ---------------------------------------------------------------------------------------------------

test("the bind name is known at login, its position only after binding", function()
  local _, State = login()
  eq(State.hearth, { name = "Deathknell" })
end)

test("binding records the inn's name and where the player stood", function()
  local c, State = login()
  local seen = watch(c)
  c:moveTo({ zone = 85, x = 61.7, y = 52.0, subZone = "Brill" })
  c:bindHearth("Brill")
  eq(State.hearth, { name = "Brill", zone = 85, x = 61.7, y = 52.0 })
  eq(count(seen, "hearth"), 1)
  local again = c:relog()
  eq(again.G.Noir.State.hearth, { name = "Brill", zone = 85, x = 61.7, y = 52.0 })
end)

test("binding again at an inn with the same name still records the position", function()
  local c, State = login()
  eq(State.hearth, { name = "Deathknell" })
  c:moveTo({ zone = 85, x = 32.2, y = 65.5 })
  c:bindHearth("Deathknell")
  eq(State.hearth, { name = "Deathknell", zone = 85, x = 32.2, y = 65.5 })
end)

test("a bind changed while the addon was not running keeps the name and drops the stale position", function()
  local c = login()
  c:moveTo({ zone = 85, x = 61.7, y = 52.0 })
  c:bindHearth("Brill")
  c:logout()
  c.s.bind = { name = "The Sepulcher" }
  local again = c:relog()
  eq(again.G.Noir.State.hearth, { name = "The Sepulcher" })
end)

test("without the bind event the change is still noticed at the next zone event", function()
  local c, State = login({ withoutEvents = { "HEARTHSTONE_BOUND" } })
  c:takeChat()
  c.s.bind = { name = "Brill" }
  c:moveTo({ zone = 85, x = 61.7, y = 52.0, subZone = "Brill" })
  eq(State.hearth.name, "Brill")
end)

-- Professions -------------------------------------------------------------------------------------------------

for _, api in ipairs({ "book", "tradeskill" }) do
  test("professions are read by skill line ID (" .. api .. " API)", function()
    local c, State = login({ professionApi = api })
    eq(State.professions, {})
    local seen = watch(c)
    c:setProfession(186, "Mining", 1, 75)
    c:setProfession(129, "First Aid", 40, 75, "firstaid")
    eq(State.professions[186].rank, 1)
    eq(State.professions[186].max, 75)
    eq(State.professions[129].rank, 40)
    eq(count(seen, "professions"), 2)
    c:setProfession(186, "Mining", 50, 75)
    eq(State.professions[186].rank, 50)
    eq({ State.Profession(186) }, { 50, 75 })
    eq({ State.Profession(171) }, { 0, 0 })
    c:fire("SKILL_LINES_CHANGED")
    eq(count(seen, "professions"), 3, "no event without a change")
  end)
end

test("a client without a profession API by ID is reported once, and nothing is guessed from names", function()
  local c, State, Noir = login({ professionApi = "none" })
  c:setProfession(186, "Mining", 50, 75)
  c:setProfession(186, "Mining", 60, 75)
  eq(State.professions, {})
  local hits = 0
  for _, p in ipairs(Noir.problems) do
    if p:find("profession", 1, true) then hits = hits + 1 end
  end
  eq(hits, 1)
end)

-- Position ----------------------------------------------------------------------------------------------------

test("position is the zone's area ID and map percent", function()
  local c, State = login({ zone = 85, x = 30.5, y = 71.25 })
  local zone, x, y, uiMap = State.Position()
  eq(zone, 85)
  near(x, 30.5, 1e-9)
  near(y, 71.25, 1e-9)
  eq(uiMap, 1420)
  eq(State.zone, 85)
  c:moveTo({ zone = 85, x = 40, y = 50 })
  zone, x, y = State.Position()
  eq({ zone, x, y }, { 85, 40, 50 })
end)

test("positions are rounded to the route files' precision, not left with float noise", function()
  local c, State = login()
  -- 0.57 * 100 and 0.07 * 100 are not exactly 57 and 7 in floating point.
  c:moveTo({ zone = 85, x = 57, y = 7 })
  ok(0.57 * 100 ~= 57, "the case really has float noise")
  local _, x, y = State.Position()
  eq({ x, y }, { 57, 7 })
  c:moveTo({ zone = 85, x = 12.3456, y = 99.994 })
  _, x, y = State.Position()
  eq({ x, y }, { 12.35, 99.99 })
end)

test("changing zone updates State.zone and fires once", function()
  local c, State = login()
  local seen = watch(c)
  c:moveTo({ zone = 130, x = 60, y = 10 })
  eq(State.zone, 130)
  eq(count(seen, "zone"), 1)
  c:moveTo({ zone = 130, x = 50, y = 20, subZone = "The Dead Field" })
  eq(count(seen, "zone"), 1, "a subzone is not a new zone")
end)

test("inside a cave the position is given on the zone map", function()
  local c, State = login()
  c:addMap(9001, { name = "Night Web's Hollow", type = 5, parent = 1420, rect = { 0.2, 0.4, 0.3, 0.5 } })
  c:moveTo({ uiMap = 9001, x = 50, y = 50 })
  local zone, x, y, uiMap = State.Position()
  eq(zone, 85)
  near(x, 25, 1e-9)
  near(y, 45, 1e-9)
  eq(uiMap, 1420)
  eq(State.zone, 85)
end)

test("a map the data does not know gives the raw map position and no zone", function()
  local c, State = login()
  c:moveTo({ zone = 1637, x = 45, y = 60 }) -- Orgrimmar is not in the sample data
  local zone, x, y, uiMap = State.Position()
  eq(zone, nil)
  eq({ x, y, uiMap }, { 45, 60, 1454 })
  eq(State.zone, nil)
end)

test("no map position (an instance) gives nil and no error", function()
  local c, State = login()
  c:moveTo({ hidden = true })
  eq(State.Position(), nil)
  eq(State.zone, nil)
end)

test("a client without the map API gives no position, reported once", function()
  local c, State, Noir = login({ without = { "C_Map" } })
  eq(State.Position(), nil)
  eq(State.Position(), nil)
  local hits = 0
  for _, p in ipairs(Noir.problems) do
    if p:find("C_Map", 1, true) then hits = hits + 1 end
  end
  eq(hits, 1)
  c:moveTo({ zone = 130 })
  eq(State.zone, nil)
end)

test("the continent is found by walking up the map tree", function()
  local c, State = login({ zone = 85 })
  eq(State.Continent(), 1415)
  c:moveTo({ zone = 14, x = 50, y = 50 })
  eq(State.Continent(), 1414)
  c:moveTo({ hidden = true })
  eq(State.Continent(), nil)
end)

-- Combat and taxi ---------------------------------------------------------------------------------------------

test("combat is tracked from the regen events", function()
  local c, State = login()
  eq(State.inCombat, false)
  c:enterCombat()
  eq(State.inCombat, true)
  c:leaveCombat()
  eq(State.inCombat, false)
end)

test("being on a flight is read live", function()
  local c, State = login()
  c:knowFlight(10)
  c:moveTo({ zone = 85, x = 58.9, y = 51.9 })
  c:openTaxi(384)
  eq(State.OnTaxi(), false)
  c.G.TakeTaxiNode(State.taxiSlots[10])
  eq(State.OnTaxi(), true)
  eq(State.taxiOpen, false)
  c:landFlight()
  eq(State.OnTaxi(), false)
  eq(State.zone, 130)
end)

-- Facts the lines need (plan task E3) ----------------------------------------------------------------------------

test("bags and known spells are read live on both APIs", function()
  for _, api in ipairs({ "classic", "modern" }) do
    local c, State = login({ api = api })
    eq(State.ItemCount(2834), 0)
    c:giveItem(2834, 3)
    eq(State.ItemCount(2834), 3, api)
    c:takeItem(2834, 1)
    eq(State.ItemCount(2834), 2)
    eq(State.KnowsSpell(1459), false)
    c:learnSpell(1459)
    eq(State.KnowsSpell(1459), true)
  end
end)

test("accept and hand-in times are remembered per quest", function()
  local c, State = login()
  eq(State.RecentAccept(364), nil)
  c:acceptQuest(364)
  eq(State.RecentAccept(364), 0)
  c:advance(3)
  near(State.RecentAccept(364), 3, 1e-6)
  eq(State.RecentTurnIn(364), nil)
  c:completeObjectives(364)
  c:turnInQuest(364)
  eq(State.RecentTurnIn(364), 0)
  c:advance(1.5)
  near(State.RecentTurnIn(364), 1.5, 1e-6)
  -- On older clients QUEST_ACCEPTED gives the log index first, then the quest ID.
  local c2, State2 = login({ api = "modern" })
  c2:acceptQuest(376)
  eq(State2.RecentAccept(376), 0)
end)

test("death, the corpse, instances and raids", function()
  local c, State = login({ zone = 85, x = 40, y = 60 })
  eq(State.IsGhost(), false)
  eq(State.Corpse(), nil)
  c:die()
  eq(State.IsGhost(), false, "dead but not released")
  c:releaseSpirit({ zone = 85, x = 30, y = 70 })
  eq(State.IsGhost(), true)
  local zone, x, y = State.Corpse()
  eq(zone, 85)
  near(x, 40, 1e-6)
  near(y, 60, 1e-6)
  c:moveTo({ zone = 130, x = 50, y = 50 })
  eq(State.Corpse(), 85, "the corpse is found from another zone")
  c:resurrect()
  eq(State.IsGhost(), false)
  eq(State.Corpse(), nil)
  eq(State.InInstance(), false)
  c:moveTo({ hidden = true })
  eq(State.InInstance(), true)
  eq(State.InRaid(), false)
  c:joinRaid(true)
  eq(State.InRaid(), true)
end)

test("the last successful cast of the player is kept", function()
  local c, State = login()
  eq(State.lastCast, nil)
  c:advance(2)
  c:castSpell(556)
  eq(State.lastCast, { spell = 556, time = c.now })
  c:fire("UNIT_SPELLCAST_SUCCEEDED", "target", "Cast-x", 133)
  eq(State.lastCast.spell, 556, "another unit's cast is not the player's")
end)

test("merchant and trainer windows record the NPC and when they opened and closed", function()
  local c, State = login()
  eq(State.merchant, { })
  c:openMerchant(5688, { { item = 159, price = 25 } })
  eq(State.merchant, { npc = 5688, opened = c.now })
  c:advance(4)
  c:closeMerchant()
  eq(State.merchant, { npc = 5688, opened = c.now - 4, closed = c.now })
  c:openTrainer(2122, {})
  eq(State.trainer.npc, 2122)
  eq(State.trainer.closed, nil, "a new visit clears the old close")
  c:closeTrainer()
  eq(State.trainer.closed, c.now)
  -- Without a readable NPC ID the visit is still recorded.
  local c2, State2 = login({ oldGuid = true })
  c2:openMerchant(5688, {})
  c2:closeMerchant()
  eq(State2.merchant, { opened = c2.now, closed = c2.now })
end)

test("the flight picked on the flight map and the moment control was lost are kept", function()
  local c, State = login({ zone = 85, x = 58.9, y = 51.9, takeoffLag = 1 })
  c:knowFlight(10)
  c:openTaxi(384)
  c:advance(1)
  c.G.TakeTaxiNode(State.taxiSlots[10])
  eq(State.taxiPick, { from = 384, to = 10, time = c.now })
  eq(State.controlLost, nil)
  c:advance(1)
  eq(State.controlLost, c.now)
  eq(State.flightStart, c.now, "control lost while on a flight")
  c:fire("PLAYER_CONTROL_LOST")
  eq(State.flightStart, c.now)
end)

test("the time a level was reached and the time of the last bind are kept", function()
  local c, State = login({ level = 2 })
  eq(State.levelAt[3], nil)
  c:advance(5)
  c:setLevel(3)
  eq(State.levelAt[3], c.now)
  eq(State.boundAt, nil)
  c:bindHearth("Brill")
  eq(State.boundAt, c.now)
end)

-- Everything together -------------------------------------------------------------------------------------------

test("/noir state prints a summary without errors on both APIs", function()
  for _, api in ipairs({ "classic", "modern" }) do
    local c = login({ api = api, class = "ROGUE", level = 3 })
    c:acceptQuest(364)
    c:takeChat()
    c:slash("/noir state")
    local text = c:chatText()
    has(text, "Undead")
    has(text, "ROGUE")
    has(text, "3")
  end
end)

test("the saved variables written by State are plain data on both APIs", function()
  for _, api in ipairs({ "classic", "modern" }) do
    local c = login({ api = api })
    c:acceptQuest(364)
    c:moveTo({ zone = 85, x = 58.9, y = 51.9 })
    c:openTaxi(384)
    c:bindHearth("Brill")
    c:setProfession(186, "Mining", 1, 75)
    c:logout() -- raises when a saved variable holds something that cannot be saved
  end
end)
