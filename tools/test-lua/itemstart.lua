-- Noir Guides, GPLv3. See LICENSE.
-- Quests started by an item found in the world: an accept line that names an item. Its npc or object is what drops
-- the item (a creature to kill, an object to loot), never someone to talk to; the quest is taken by using the item.
-- The mock client's side (an item that opens a quest page), the line's words, the item and target buttons, the
-- automation, placement of a joiner, and the simulator's scripted player.
use("tools/test-lua/sample/helper.lua")
use("tools/harness/sim.lua")
local Client = HARNESS.Client
local Sim = HARNESS.Sim

local DEATHKNELL = "undead-01-03-deathknell"
local TIRISFAL = "undead-03-05-tirisfal-glades"
local GUID = "Player-4444-0000002A"
local KEY = "Tester-Mock"
local ICHOR = 2834 -- "Embalming Ichor" in the sample data; here the item that starts Rude Awakening (363)
local ZOMBIE = 1501

local function savedAt(section, stepId)
  local db = { schema = 2, owner = GUID, guide = { section = section, how = "hand", places = { [section] = { step = stepId } } } }
  return { account = {}, characters = { [KEY] = { NoirGuidesCharDB = db } } }
end

-- The sample's first step (accept Rude Awakening from Undertaker Mordo) as a quest started by an item a creature
-- drops, the way the planner writes one (tools/planner/bundle.js).
local function dropStep(client)
  local step = client.G.Noir.Routes.Get("horde-undead").sections[1].steps[1]
  step.at = { zone = 85, x = 32, y = 64, r = 40 }
  step.text = nil
  step.lines = { { kind = "accept", quest = 363, npc = ZOMBIE, item = ICHOR } }
  step.items = { ICHOR }
  step.targets = { enemy = { ZOMBIE } }
end

-- A level 1 mage at the first step, which is the drop step. The world knows that the item starts the quest.
local function atDrop(opts)
  opts = opts or {}
  local c = sample3({ class = "MAGE", level = 1, zone = 85, x = 50, y = 50, saved = savedAt(DEATHKNELL, "a363"),
    afterLoad = function(client)
      dropStep(client)
      if opts.afterLoad then opts.afterLoad(client) end
    end })
  c.world.items[ICHOR] = "Embalming Ichor"
  c.world.itemQuests = { [ICHOR] = 363 }
  c:login()
  c:advance(0.5)
  return c, c.G.Noir
end

local function placeId(Noir)
  local _, _, _, step = Noir.Progress.Place()
  return step and step.id
end

local function currentLine(Noir)
  local cards = Noir.Progress.Cards()
  local card = cards[#cards]
  return card and card.lines[1]
end

local function spans(t)
  local out = {}
  for i, s in ipairs(t.spans or {}) do out[i] = s.kind .. ":" .. string.sub(t.text, s.from, s.to) end
  return out
end

-- The mock client -------------------------------------------------------------------------------------------------

test("the mock: an item that starts a quest opens the quest's page when used, with nobody to talk to", function()
  local c = Client.new({ files = {} }):login()
  local G = c.G
  c.world.items[ICHOR] = "Embalming Ichor"
  c.world.itemQuests = { [ICHOR] = 364 }
  eq(c:useItem(ICHOR), false, "nothing without the item")
  c:giveItem(ICHOR, 1)
  eq(c:useItem(ICHOR), true)
  eq({ c.dialog.kind, c.dialog.quest }, { "detail", 364 })
  eq(G.GetQuestID(), 364)
  eq(G.UnitGUID("npc"), nil, "the page comes from an item: no NPC is talked to")
  eq(#c:events("QUEST_DETAIL"), 1)
  G.AcceptQuest()
  ok(c:findQuest(364), "the quest is in the log")
  eq(c.dialog, nil)
  eq(c:itemCount(ICHOR), 0, "the item is gone once its quest is taken")
  c:giveItem(ICHOR, 1)
  eq(c:useItem(ICHOR), false, "the quest is in the log: the item opens nothing")
  eq(#c:events("QUEST_DETAIL"), 1)
end)

test("the mock: an item whose quest is not open to the character opens nothing", function()
  local c = Client.new({ files = {}, level = 1 }):login()
  c.world.items[ICHOR] = "Embalming Ichor"
  c.world.itemQuests = { [ICHOR] = 364 }
  c.world.quests[364].minLevel = 5
  c:giveItem(ICHOR, 1)
  eq(c:useItem(ICHOR), false)
  eq(c.dialog, nil)
  eq(c:itemCount(ICHOR), 1)
end)

-- The words -------------------------------------------------------------------------------------------------------

test("the line says to kill or loot for the item, then to use it; with the item in the bags, to use it", function()
  local c = sample3({ class = "MAGE", level = 2, zone = 85, x = 30, y = 70 }):login()
  local Noir, Text = c.G.Noir, c.G.Noir.Text
  Noir.Data.objects[3001] = "Rotting Crate"
  local function line(l) return Text.Line(l, { id = "s", n = 1, lines = { l } }) end
  local kill = { kind = "accept", quest = 364, npc = ZOMBIE, item = ICHOR }
  local t = line(kill)
  eq({ t.text, t.icon, t.quest },
    { "Kill Mindless Zombie until it drops Embalming Ichor, then use it to accept The Mindless Ones", "kill", 364 })
  eq(spans(t), { "enemy:Mindless Zombie", "loot:Embalming Ichor" })
  local loot = { kind = "accept", quest = 364, object = 3001, item = ICHOR }
  t = line(loot)
  eq({ t.text, t.icon, t.quest },
    { "Loot Rotting Crate for Embalming Ichor, then use it to accept The Mindless Ones", "item", 364 })
  eq(spans(t), { "object:Rotting Crate", "loot:Embalming Ichor" })
  eq(Text.ObjectName(3001), "Rotting Crate")
  eq(Text.ObjectName(77), "Object 77", "an object the data does not name")
  -- An item with no known source on the line: all there is to say is to use it.
  t = line({ kind = "accept", quest = 364, item = ICHOR })
  eq({ t.text, t.icon }, { "Use Embalming Ichor to accept The Mindless Ones", "accept" })
  -- Prerequisites not handed in are shown as on any accept line.
  t = line({ kind = "accept", quest = 364, npc = ZOMBIE, item = ICHOR, requires = { 363 } })
  eq(t.icon, "error")
  eq(t.tooltip, { Text.PREREQ_TITLE, "Rude Awakening" })
  eq(spans(t), { "enemy:Mindless Zombie", "loot:Embalming Ichor", "warning:The Mindless Ones" })
  -- With the item in the bags there is nothing left to kill or loot.
  c:giveItem(ICHOR, 1)
  for _, l in ipairs({ kill, loot }) do
    t = line(l)
    eq({ t.text, t.icon, t.quest }, { "Use Embalming Ichor to accept The Mindless Ones", "accept", 364 })
    eq(spans(t), { "loot:Embalming Ichor" })
  end
  -- A plain accept line is worded as before.
  eq(line({ kind = "accept", quest = 364, npc = 1569 }).text, "Accept The Mindless Ones")
  eq(c:takeErrors(), {})
end)

-- The step on screen ----------------------------------------------------------------------------------------------

test("the card follows the bags: kill for the item, then use it; the step is done once the quest is in the log", function()
  local c, Noir = atDrop()
  eq(placeId(Noir), "a363")
  local l = currentLine(Noir)
  eq({ l.state, l.text }, { "todo", "Kill Mindless Zombie until it drops Embalming Ichor, then use it to accept Rude Awakening" })
  local aim = Noir.Arrow.Target()
  eq({ aim.step.id, aim.at.zone, aim.at.x, aim.at.y }, { "a363", 85, 32, 64 }, "the arrow points at the drop place")
  c:giveItem(ICHOR, 1)
  c:advance(0.5)
  l = currentLine(Noir)
  eq({ l.state, l.text }, { "todo", "Use Embalming Ichor to accept Rude Awakening" })
  eq(placeId(Noir), "a363", "the item alone does not pass the step")
  c:acceptQuest(363)
  c:advance(1)
  eq(placeId(Noir), "t363.a364.a376", "in the quest log: done, like any accept")
  eq(c:slashCount(), 0)
  eq(c:takeErrors(), {})
end)

test("the dropping creature is an enemy target, never a friendly one; the item goes on a button once it is in the bags", function()
  local c, Noir = atDrop()
  local Buttons = Noir.Buttons
  eq(Buttons.Targets(), { enemy = { "Mindless Zombie" }, friend = {} })
  ok(string.find(c.G.NoirGuidesEnemy1:GetAttribute("macrotext"), "/targetexact Mindless Zombie", 1, true), "the enemy button targets the creature")
  no(c.G.NoirGuidesFriend1:IsVisible(), "no friendly target button")
  eq(Buttons.Items(), {}, "nothing to use yet")
  c:giveItem(ICHOR, 1)
  c:advance(0.5)
  eq(Buttons.Items(), { { kind = "item", id = ICHOR } })
  local button = c.G.NoirGuidesItem1
  ok(button and button:IsVisible(), "the item button shows")
  eq(button:GetAttribute("item"), "item:" .. ICHOR)
  -- A click uses the item, the quest's page opens and the automation accepts it.
  eq(c:secureClick(button), "item " .. ICHOR)
  eq(c:callsTo("AcceptQuest"), { { "AcceptQuest", 363 } })
  ok(Noir.State.HasQuest(363))
  c:advance(1)
  eq(Buttons.Items(), {}, "the starter leaves the buttons with its quest in the log")
  eq(placeId(Noir), "t363.a364.a376")
  eq(c:slashCount(), 0)
  eq(c:offScreen(), {})
  eq(c:takeErrors(), {})
end)

-- Automation ------------------------------------------------------------------------------------------------------

test("the quest page an item opens is accepted by the automation, and left alone with Ctrl held or for a manual line", function()
  local c, Noir = atDrop()
  c:giveItem(ICHOR, 1)
  c:advance(0.5)
  c:hold("CTRL", true)
  eq(c:useItem(ICHOR), true)
  eq(c:callsTo("AcceptQuest"), {}, "Ctrl keeps the automation away")
  eq(c.dialog and c.dialog.quest, 363, "the page stays open for the player")
  c:closeNpc()
  c:hold("CTRL", false)
  eq(c:useItem(ICHOR), true)
  eq(c:callsTo("AcceptQuest"), { { "AcceptQuest", 363 } })
  ok(Noir.State.HasQuest(363))
  -- A manual line: the player accepts by hand.
  local m, MNoir = atDrop({ afterLoad = function(client)
    client.G.Noir.Routes.Get("horde-undead").sections[1].steps[1].lines[1].manual = true
  end })
  m:giveItem(ICHOR, 1)
  m:advance(0.5)
  eq(m:useItem(ICHOR), true)
  eq(m:callsTo("AcceptQuest"), {})
  eq(MNoir.State.HasQuest(363), false)
  eq(c:takeErrors(), {})
  eq(m:takeErrors(), {})
end)

-- Placement -------------------------------------------------------------------------------------------------------

test("a joiner with the item's quest in the log is placed after its step, as with any accept", function()
  local function join(log, done)
    local c = sample3({ class = "MAGE", level = 1, afterLoad = dropStep })
    for _, q in ipairs(done or {}) do c:markCompleted(q) end
    for _, q in ipairs(log or {}) do c:acceptQuest(q) end
    c:login()
    local section, _, _, step = c.G.Noir.Progress.Place()
    return section, step and step.id, c
  end
  local section, step, c = join({})
  eq({ section, step }, { DEATHKNELL, "a363" }, "nothing done: the drop step")
  eq(c:takeErrors(), {})
  section, step, c = join({ 363 })
  eq({ section, step }, { DEATHKNELL, "t363.a364.a376" }, "in the log: placed after it")
  eq(c:takeErrors(), {})
  section, step, c = join({ 364, 376 }, { 363 })
  eq(section, DEATHKNELL)
  ok(step ~= "a363", "handed in: never back at the drop step")
  eq(c:takeErrors(), {})
  eq(TIRISFAL ~= nil, true)
end)

-- The simulator ---------------------------------------------------------------------------------------------------

local function simFacts()
  local SECTION = "undead-01-02-drops"
  local zombies, crate, sarvis = { zone = 85, x = 32, y = 64, r = 40 }, { zone = 85, x = 34, y = 62, r = 40 }, { zone = 85, x = 30.84, y = 66.2, r = 10 }
  local route = { format = 3, race = "Undead", faction = "Horde", sections = { {
    id = SECTION, name = "1-2 Deathknell", group = "Horde", subgroup = "1-20", minLevel = 1, maxLevel = 4, zone = 85, start = true,
    next = {},
    steps = {
      { id = "a900", at = zombies, items = { 5000 }, targets = { enemy = { ZOMBIE } },
        lines = { { kind = "accept", quest = 900, npc = ZOMBIE, item = 5000 } } },
      { id = "a901", at = crate, items = { 5001 }, lines = { { kind = "accept", quest = 901, object = 3001, item = 5001 } } },
      { id = "t900.t901", at = sarvis, targets = { friend = { 1569 } },
        lines = { { kind = "turnin", quest = 900, npc = 1569 }, { kind = "turnin", quest = 901, npc = 1569 } } },
    },
  } } }
  local function quest(title)
    return { title = title, level = 1, minLevel = 1, pre = {}, preAny = {}, exclusive = {}, kills = 0, items = 0, objects = 0, credits = 0, event = false }
  end
  local xp = {}
  for level = 1, 59 do xp[level] = level * 1000 end
  local function action(a, step) a.section, a.step = SECTION, step return a end
  return {
    race = "Undead", class = "MAGE", start = { zone = 85, x = 30.2, y = 71.6 }, xpToLevel = xp,
    pace = { OBJECTIVE_KILLS = 8, ITEM_KILL_FACTOR = 2, INCIDENTAL_YARDS = 300 },
    continents = { [0] = { uiMap = 1415, name = "Eastern Kingdoms", top = 5000, left = 4000, width = 12000, height = 8000 } },
    zones = { [85] = { uiMap = 1420, name = "Tirisfal Glades", continent = 0, minX = 2600, maxX = 4200, minY = -2000, maxY = 400 } },
    quests = { [900] = quest("The Torn Letter"), [901] = quest("The Sealed Orders") },
    npcs = {
      [ZOMBIE] = { name = "Mindless Zombie", offers = {}, ends = {} },
      [1569] = { name = "Shadow Priest Sarvis", offers = {}, ends = { 900, 901 } },
    },
    objects = { [3001] = { name = "Rotting Crate", offers = {}, ends = {} } },
    items = { [5000] = { name = "Torn Letter", quest = 900 }, [5001] = { name = "Sealed Orders", quest = 901 } },
    taxi = {},
    route = route,
    flat = {
      action({ action = "accept", quest = 900, npc = ZOMBIE, item = 5000, at = zombies }, "a900"),
      action({ action = "accept", quest = 901, object = 3001, item = 5001, at = crate }, "a901"),
      action({ action = "turnin", quest = 900, npc = 1569, at = sarvis }, "t900.t901"),
      action({ action = "turnin", quest = 901, npc = 1569, at = sarvis }, "t900.t901"),
    },
  }
end
local REGISTER = { { match = "^Data/", with = {} }, { match = "^Routes/", with = {} } }

test("the simulated player kills or loots for the item, clicks its button and the quest is taken", function()
  local r = Sim.play(simFacts(), { register = true, swap = REGISTER })
  eq(r.stuck, {}, "stuck")
  eq(r.cannot, {}, "cannot")
  eq(r.unexplained, {}, "unexplained")
  eq(r.errors, {}, "errors")
  eq(r.finished, true)
  eq(r.itemStarts, 2, "both quests were started from their items")
  eq(r.client:callsTo("UseItem"), { { "UseItem", 5000 }, { "UseItem", 5001 } })
  eq(r.client:callsTo("AcceptQuest"), { { "AcceptQuest", 900 }, { "AcceptQuest", 901 } })
  ok(r.client.s.completed[900] and r.client.s.completed[901], "both were handed in")
  eq(Sim.problems(r, 1), {})
end)

test("the simulated player is stuck, with the reason, at an item that starts no quest", function()
  local facts = simFacts()
  facts.items[5001] = nil
  local r = Sim.play(facts, { register = true, swap = REGISTER })
  ok(#r.stuck >= 1, "the step is stuck")
  eq(r.stuck[1].step, "a901", "the first stuck step (what needs its quest is stuck after it)")
  eq(r.itemStarts, 1, "the other quest was started from its item")
  ok(string.find(r.stuck[1].reason, "item 5001", 1, true), r.stuck[1].reason)
end)

test("a simulated joiner who took the first item's quest without the addon is placed after it and plays on", function()
  local r = Sim.play(simFacts(), { register = true, swap = REGISTER, join = 1 })
  eq(r.placement.expectedFrom, 1)
  eq(r.placement.inside, true, "placed at action " .. tostring(r.placement.landed))
  eq(r.placement.landedAt, "undead-01-02-drops/a901")
  eq(r.itemStarts, 1, "only the second quest was left to start")
  eq(Sim.problems(r, 1), {})
end)
