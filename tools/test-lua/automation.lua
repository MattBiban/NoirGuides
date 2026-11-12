-- Noir Guides, GPLv3. See LICENSE.
-- Automation v2 (plan task E9, spec 5, gaps #27 to #32 and #35): at an NPC the addon does what the steps on screen
-- (and the one right after the current step) say, and nothing else. Ctrl at an NPC keeps the quest automation away
-- for that conversation, Shift the flight, bind and dialogue automation. Every test is driven by game events, the
-- NPC windows and the mouse; none types a command.
use("tools/test-lua/sample/helper.lua")

local DEATHKNELL = "undead-01-03-deathknell"
local TIRISFAL = "undead-03-05-tirisfal-glades"
local GUID = "Player-4444-0000002A"
local KEY = "Tester-Mock"

local function savedAt(section, stepId, options)
  local db = { schema = 2, owner = GUID, guide = { section = section, how = "hand", places = { [section] = { step = stepId } } } }
  local account = {}
  if options then
    account.NoirGuidesDB = { schema = 2, profiles = { Default = options }, defaultProfile = "Default" }
  end
  return { account = account, characters = { [KEY] = { NoirGuidesCharDB = db } } }
end

-- A character logged in with its place saved at `stepId`. opts: section, class, level, zone, x, y, done, log
-- ({ id, def } pairs or ids), options, afterLoad, api, world (merged into the default world), money.
local function at(stepId, opts)
  opts = opts or {}
  local c = sample3({ class = opts.class or "MAGE", level = opts.level or 1, zone = opts.zone or 85,
    x = opts.x or 50, y = opts.y or 50, saved = savedAt(opts.section or DEATHKNELL, stepId, opts.options),
    afterLoad = opts.afterLoad, api = opts.api })
  for kind, entries in pairs(opts.world or {}) do
    c.world[kind] = c.world[kind] or {}
    for id, value in pairs(entries) do c.world[kind][id] = value end
  end
  c.s.money = opts.money or 0
  for _, q in ipairs(opts.done or {}) do c:markCompleted(q) end
  for _, q in ipairs(opts.log or {}) do
    if type(q) == "table" then c:acceptQuest(q[1], q[2]) else c:acceptQuest(q) end
  end
  c:login()
  c:advance(0.5)
  return c, c.G.Noir
end

local function placeId(Noir)
  local _, _, _, step = Noir.Progress.Place()
  return step and step.id
end

-- The calls to any of the given API functions, in order, by name only.
local function callNames(c, names)
  local wanted, out = {}, {}
  for _, name in ipairs(names) do wanted[name] = true end
  for _, call in ipairs(c.calls) do
    if wanted[call[1]] then out[#out + 1] = call[1] end
  end
  return out
end

-- Changes a step of the sample route after the files are loaded (before the saved variables are read).
local function editStep(sectionIndex, stepId, fn)
  return function(client)
    for _, step in ipairs(client.G.Noir.Routes.Get("horde-undead").sections[sectionIndex].steps) do
      if step.id == stepId then fn(step) end
    end
  end
end

local MORDO = { name = "Undertaker Mordo", offers = { 363 } }
local SARVIS = "Shadow Priest Sarvis"
local MASTER = { name = "Michael Garrett", taxi = 384, options = { { type = "gossip", text = "Tell me about the bats." } } }

-- Accepting --------------------------------------------------------------------------------------------------------

test("a quest of the next step is accepted at its NPC", function()
  local c, Noir = at("a363")
  eq(placeId(Noir), "a363")
  -- Sarvis's quests belong to the step after the current one.
  c:talkTo(1569, { name = SARVIS, offers = { 364 } })
  eq(c:callsTo("AcceptQuest"), { { "AcceptQuest", 364 } })
  ok(Noir.State.HasQuest(364))
  -- And the current step's own quest, of course.
  c:talkTo(1568, MORDO)
  eq(c:callsTo("AcceptQuest"), { { "AcceptQuest", 364 }, { "AcceptQuest", 363 } })
  eq(c:slashCount(), 0)
end)

test("a quest of no step on screen or next is left alone", function()
  local c, Noir = at("a363", { world = { quests = { [3901] = { title = "Rattling the Rattlecages", level = 1, objectives = {} } } } })
  -- A rogue's quest, for a mage: no step of this character names it.
  c:talkTo(6784)
  eq(c:callsTo("AcceptQuest"), {})
  eq(c.dialog and c.dialog.quest, 8, "the dialog stays open for the player")
  c:closeNpc()
  -- Executor Arren's quest is two steps ahead: not on screen and not the next step.
  c:talkTo(1570, { name = "Executor Arren", offers = { 3901 } })
  eq(c:callsTo("AcceptQuest"), {})
  eq(c.dialog and c.dialog.quest, 3901)
  eq(Noir.State.HasQuest(3901), false)
end)

test("Ctrl skips quest automation, Shift skips the flight, bind and dialogue", function()
  local c = at("a363")
  c:hold("CTRL", true)
  c:talkTo(1568, MORDO)
  c:hold("CTRL", false)
  eq(c:callsTo("AcceptQuest"), {}, "Ctrl held when the window opened")
  eq(c.dialog and c.dialog.quest, 363)
  c:closeNpc()
  c:hold("SHIFT", true)
  c:talkTo(1568, MORDO)
  c:hold("SHIFT", false)
  eq(c:callsTo("AcceptQuest"), { { "AcceptQuest", 363 } }, "Shift does not stop the quest automation")

  -- The flight master of a flight point step, with a second dialogue line so the list shows.
  local flights = at("fp384", { section = TIRISFAL, level = 3, x = 58.9, y = 51.9 })
  eq(placeId(flights.G.Noir), "fp384")
  flights:hold("SHIFT", true)
  flights:talkTo(4551, MASTER)
  flights:hold("SHIFT", false)
  eq(flights.gossipChosen, nil, "Shift: the flight line is not picked")
  flights:closeNpc()
  flights:hold("CTRL", true)
  flights:talkTo(4551, MASTER)
  flights:hold("CTRL", false)
  eq(flights.gossipChosen, nil, "no dialogue line is picked while a modifier is held")
  flights:closeNpc()
  flights:talkTo(4551, MASTER)
  eq(flights.gossipChosen, "taxi")

  -- The innkeeper of a bind step.
  local inn = at("inn", { section = TIRISFAL, level = 3, x = 61.7, y = 52.0 })
  eq(placeId(inn.G.Noir), "inn")
  inn:hold("SHIFT", true)
  inn:talkTo(5688)
  inn:hold("SHIFT", false)
  inn:advance(0.5)
  eq(inn.gossipChosen, nil, "Shift: the bind line is not picked")
  eq(inn:callsTo("ConfirmBinder"), {})
  inn:closeNpc()
  inn:talkTo(5688)
  eq(inn.gossipChosen, "binder")
  inn:advance(0.1)
  eq(#inn:callsTo("ConfirmBinder"), 1)
end)

test("Ctrl or Shift held when the gossip list opens still counts after the list gives way to a quest page or the flight map", function()
  -- The client's gossip frame closes (GOSSIP_CLOSED) when the quest frame takes its place.
  local c, Noir = at("t363.a364.a376", { log = { 363 } })
  eq(placeId(Noir), "t363.a364.a376")
  c:hold("CTRL", true)
  c:talkTo(1569, { name = SARVIS, ends = { 363 }, offers = { 364, 376 } })
  c:hold("CTRL", false)
  eq(callNames(c, { "SelectGossipActiveQuest", "SelectGossipAvailableQuest" }), {}, "the list is left to the player")
  -- The player picks the hand-in: its reward page is theirs too.
  c.G.SelectGossipActiveQuest(1)
  eq(c.dialog and c.dialog.kind, "complete")
  eq(c:callsTo("GetQuestReward"), {}, "Ctrl was held when the NPC window opened")
  eq(Noir.State.IsDone(363), false)
  c:closeNpc()
  c:advance(1)
  -- Ctrl again, and the player opens an accept from the list.
  c:hold("CTRL", true)
  c:talkTo(1569, { name = SARVIS, ends = { 363 }, offers = { 364, 376 } })
  c:hold("CTRL", false)
  c.G.SelectGossipAvailableQuest(1)
  eq(c.dialog and c.dialog.kind, "detail")
  eq(c:callsTo("AcceptQuest"), {})
  c:closeNpc()
  c:advance(1)
  -- A new conversation without Ctrl is automated again.
  c:talkTo(1569, { name = SARVIS, ends = { 363 }, offers = { 364, 376 } })
  eq(c:callsTo("GetQuestReward"), { { "GetQuestReward", 0, 363 } })
  -- A gossip list closed with no other window after it ends the conversation.
  c:closeNpc()
  c:hold("CTRL", true)
  c:talkTo(1569, { name = SARVIS, offers = { 364, 376 }, alwaysGossip = true })
  c:hold("CTRL", false)
  eq(c.G.Noir.Automation.Read().talk.ctrl, true)
  c:closeNpc()
  c:advance(1)
  eq(c.G.Noir.Automation.Read().talk, nil)

  -- Shift at the flight master's list: the player picks the flight line and the flight is theirs.
  local fly = at("fly10", { section = TIRISFAL, level = 3, x = 58.9, y = 51.9, api = "modern",
    afterLoad = editStep(2, "fly10", function(step) step.load = nil end) })
  eq(placeId(fly.G.Noir), "fly10")
  fly:knowFlight(10)
  fly:hold("SHIFT", true)
  fly:talkTo(4551, MASTER)
  fly:hold("SHIFT", false)
  eq(fly.gossipChosen, nil)
  fly:chooseOption(1) -- the player clicks the flight line
  fly:advance(0.5)
  ok(fly.taxiOpen, "the flight map is open")
  eq(fly:callsTo("TakeTaxiNode"), {}, "Shift was held when the NPC window opened")
end)

test("the dialogue picks a guide hand-in before an accept", function()
  local c, Noir = at("t363.a364.a376", { log = { 363 } })
  eq(placeId(Noir), "t363.a364.a376")
  c:talkTo(1569, { name = SARVIS, ends = { 363 }, offers = { 364, 376 } })
  eq(callNames(c, { "SelectGossipActiveQuest", "SelectGossipAvailableQuest" })[1], "SelectGossipActiveQuest")
  eq(c:callsTo("GetQuestReward"), { { "GetQuestReward", 0, 363 } })
  ok(Noir.State.IsDone(363), "handed in first")
  -- Talking again, the accepts come next, one at a time.
  c:talkTo(1569, { name = SARVIS, offers = { 364, 376 } })
  eq(c:callsTo("AcceptQuest"), { { "AcceptQuest", 364 } })
  c:talkTo(1569, { name = SARVIS, offers = { 364, 376 } })
  eq(c:callsTo("AcceptQuest"), { { "AcceptQuest", 364 }, { "AcceptQuest", 376 } })
end)

test("the dialogue opens an unfinished guide quest whose only objective is talking to this NPC", function()
  local talk = { title = "Speak with Sarvis", level = 1, objectives = { { text = "Speak with Sarvis", type = "event", need = 1 } } }
  local c = at("a363", { world = { quests = { [9100] = talk } }, log = { 9100 },
    afterLoad = editStep(1, "a363", function(step)
      step.lines[2] = { kind = "objective", quest = 9100, index = 1, npc = 1569 }
    end) })
  eq(placeId(c.G.Noir), "a363")
  c:talkTo(1569, { name = SARVIS, ends = { 9100 }, offers = { 8 }, alwaysGossip = true })
  eq(callNames(c, { "SelectGossipActiveQuest", "SelectGossipAvailableQuest" }), { "SelectGossipActiveQuest" })
  eq(c.dialog and c.dialog.quest, 9100)
end)

test("a non-guide follow-up offered right after a hand-in is closed", function()
  local world = { quests = { [9001] = { title = "An Errand", level = 1, after = 363, objectives = {} } } }
  local c, Noir = at("t363.a364.a376", { log = { 363 }, world = world })
  c:talkTo(1569, { name = SARVIS, ends = { 363 }, offers = { 9001 } })
  ok(Noir.State.IsDone(363))
  eq(c:callsTo("AcceptQuest"), {})
  eq(#c:callsTo("CloseQuest"), 1, "the follow-up's page is closed")
  eq(c.dialog, nil)
  eq(Noir.State.HasQuest(9001), false)
  -- A follow-up the guide wants is taken.
  local mindless = { title = "The Mindless Ones", level = 2, after = 363,
    objectives = { { text = "Mindless Zombie slain", type = "monster", need = 8 } } }
  local c2, Noir2 = at("t363.a364.a376", { log = { 363 }, world = { quests = { [364] = mindless } } })
  c2:talkTo(1569, { name = SARVIS, ends = { 363 }, offers = { 364 } })
  eq(c2:callsTo("AcceptQuest"), { { "AcceptQuest", 364 } })
  ok(Noir2.State.HasQuest(364))
  -- Later than 0.5 s after a hand-in, a quest page the guide does not want stays open.
  c:advance(1)
  c:talkTo(6784)
  eq(c.dialog and c.dialog.quest, 8)
  eq(#c:callsTo("CloseQuest"), 1)
end)

test("a shared quest of a guide step is confirmed", function()
  local c, Noir = at("a363", { world = { quests = { [3901] = { title = "Rattling the Rattlecages", level = 1, objectives = {} } } } })
  c:shareQuest(3901, "Friend")
  eq(c:callsTo("ConfirmAcceptQuest"), {}, "not a quest of the steps on screen or next")
  c:shareQuest(364, "Friend")
  eq(c:callsTo("ConfirmAcceptQuest"), { { "ConfirmAcceptQuest", 364 } })
  ok(Noir.State.HasQuest(364))
end)

-- Handing in and rewards -------------------------------------------------------------------------------------------

local RATTLE = { title = "Rattling the Rattlecages", level = 1, objectives = {} }
local MINDLESS_DONE = { title = "The Mindless Ones", level = 2, objectives = {} }
local CHOICES = {
  { item = 9101, name = "Worn Gloves", price = 12 },
  { item = 9102, name = "Bone Ring", price = 95 },
  { item = 9103, name = "Dusty Boots", price = 40 },
}

test("a reward page with one choice is taken; with several it is marked with a coin and left open", function()
  local c, Noir = at("t3901", { log = { { 3901, RATTLE } }, world = { quests = { [3901] = RATTLE } } })
  eq(placeId(Noir), "t3901")
  c:showReward(3901, { CHOICES[1] })
  eq(c:callsTo("GetQuestReward"), { { "GetQuestReward", 1, 3901 } })
  ok(Noir.State.IsDone(3901))

  local c2, Noir2 = at("t364.t376", { log = { { 364, MINDLESS_DONE } }, world = { quests = { [364] = MINDLESS_DONE } } })
  eq(placeId(Noir2), "t364.t376")
  c2:showReward(364, CHOICES)
  eq(c2:callsTo("GetQuestReward"), {}, "the choice is the player's")
  eq(c2.dialog and c2.dialog.kind, "complete", "the page stays open")
  local marker = Noir2.Automation.Read().marker
  ok(marker, "a choice is marked")
  eq({ marker.quest, marker.choice, marker.shown }, { 364, 2, true }, "the best sell price carries the coin")
  eq(c2:offScreen(), {})
  c2:closeNpc()
  eq(Noir2.Automation.Read().marker, nil, "the coin goes with the page")
end)

test("guide rewards and best reward take the choice when switched on", function()
  -- The step names reward 1: with guideRewards on it is taken, though another sells for more.
  local c = at("t3901", { log = { { 3901, RATTLE } }, world = { quests = { [3901] = RATTLE } }, options = { guideRewards = true } })
  c:showReward(3901, CHOICES)
  eq(c:callsTo("GetQuestReward"), { { "GetQuestReward", 1, 3901 } })
  -- Off, the step's reward is not taken for the player.
  local off = at("t3901", { log = { { 3901, RATTLE } }, world = { quests = { [3901] = RATTLE } } })
  off:showReward(3901, CHOICES)
  eq(off:callsTo("GetQuestReward"), {})
  -- bestReward takes the choice with the best sell price.
  local best = at("t364.t376", { log = { { 364, MINDLESS_DONE } }, world = { quests = { [364] = MINDLESS_DONE } }, options = { bestReward = true } })
  best:showReward(364, CHOICES)
  eq(best:callsTo("GetQuestReward"), { { "GetQuestReward", 2, 364 } })
  -- With the marker switched off and nothing to take, nothing is marked.
  local plain = at("t364.t376", { log = { { 364, MINDLESS_DONE } }, world = { quests = { [364] = MINDLESS_DONE } }, options = { rewardMarker = false } })
  plain:showReward(364, CHOICES)
  eq(plain:callsTo("GetQuestReward"), {})
  eq(plain.G.Noir.Automation.Read().marker, nil)
end)

test("the coin also marks the best choice of a quest selected in the quest log", function()
  local quest = { title = "The Mindless Ones", level = 2, objectives = {}, rewardItems = CHOICES }
  local c, Noir = at("t364.t376", { log = { { 364, quest } }, world = { quests = { [364] = quest } } })
  c:openQuestLog()
  c.G.SelectQuestLogEntry(c.G.GetQuestLogIndexByID(364))
  c:advance(0.5)
  local marker = Noir.Automation.Read().logMarker
  ok(marker, "a choice is marked")
  eq({ marker.quest, marker.choice, marker.shown }, { 364, 2, true })
  eq(c:offScreen(), {})
  c:closeQuestLog()
  c:advance(0.5)
  eq(Noir.Automation.Read().logMarker, nil)
end)

-- Flights ----------------------------------------------------------------------------------------------------------

local noLoad = editStep(2, "fly10", function(step) step.load = nil end)

test("the flight is matched by node ID before name", function()
  -- A known node whose name holds the destination's comes first on the map: matching by name would take it.
  local c = at("fly10", { section = TIRISFAL, level = 3, x = 58.9, y = 51.9, api = "modern", afterLoad = noLoad })
  eq(placeId(c.G.Noir), "fly10")
  c.world.taxi[2].name = "The Sepulcher, Silverpine Forest (old road)"
  c:knowFlight(2)
  c:knowFlight(10)
  c:openTaxi(384)
  c:advance(0.5)
  local calls = c:callsTo("TakeTaxiNode")
  eq(#calls, 1)
  eq(calls[1][3], 10, "node 10 by its ID")

  -- Where the client names its nodes differently from the data (no ID to go by), the name is the fallback.
  local renamed = function(client)
    noLoad(client)
    client.G.Noir.Data.flights[10] = { name = "The Sepulcher", zone = 130, x = 45.6, y = 42.6 }
  end
  local byName = at("fly10", { section = TIRISFAL, level = 3, x = 58.9, y = 51.9, afterLoad = renamed })
  byName:knowFlight(10)
  byName:openTaxi(384)
  byName:advance(0.5)
  calls = byName:callsTo("TakeTaxiNode")
  eq(#calls, 1)
  eq(calls[1][3], 10, "by name")

  -- Shift held at the flight master: the flight is left to the player.
  local held = at("fly10", { section = TIRISFAL, level = 3, x = 58.9, y = 51.9, api = "modern", afterLoad = noLoad })
  held:knowFlight(10)
  held:hold("SHIFT", true)
  held:openTaxi(384)
  held:hold("SHIFT", false)
  held:advance(0.5)
  eq(held:callsTo("TakeTaxiNode"), {})
end)

test("the flight master option is re-picked at most every 10 s for a flight point line", function()
  -- The line asks for Undercity's flight point, which this flight master's map does not teach.
  local c = at("fp384", { section = TIRISFAL, level = 3, x = 58.9, y = 51.9,
    afterLoad = editStep(2, "fp384", function(step) step.lines[1] = { kind = "getflight", node = 11, npc = 4551 } end) })
  c:knowFlight(384)
  eq(placeId(c.G.Noir), "fp384")
  c:talkTo(4551, MASTER)
  eq(c.gossipChosen, "taxi")
  c:closeTaxi()
  c.gossipChosen = nil
  c:advance(4)
  c:talkTo(4551, MASTER)
  eq(c.gossipChosen, nil, "not again within 10 s")
  c:closeNpc()
  c:advance(6.5)
  c:talkTo(4551, MASTER)
  eq(c.gossipChosen, "taxi", "after 10 s it is picked again")
end)

test("a fly line picks the flight master option once per step", function()
  local c = at("fly10", { section = TIRISFAL, level = 3, x = 58.9, y = 51.9, afterLoad = noLoad })
  c:knowFlight(384)
  c:talkTo(4551, MASTER)
  eq(c.gossipChosen, "taxi")
  c:closeTaxi()
  c.gossipChosen = nil
  c:advance(30)
  c:talkTo(4551, MASTER)
  eq(c.gossipChosen, nil)
end)

-- Hearthstone ------------------------------------------------------------------------------------------------------

test("the bind confirmation is answered on the next frame", function()
  local c, Noir = at("inn", { section = TIRISFAL, level = 3, x = 61.7, y = 52.0 })
  eq(placeId(Noir), "inn")
  c:talkTo(5688)
  eq(c.gossipChosen, "binder", "the bind line is picked by its type")
  eq(c:callsTo("ConfirmBinder"), {}, "not in the same frame")
  c:advance(0.1)
  eq(#c:callsTo("ConfirmBinder"), 1)
  eq(c:callsTo("StaticPopup_Hide"), { { "StaticPopup_Hide", "CONFIRM_BINDER" } }, "only the bind popup is closed")
  eq(c.G.GetBindLocation(), "Brill")
  -- At an innkeeper without a bind line on screen nothing is picked.
  local other = at("a363")
  other:talkTo(5688)
  other:advance(0.5)
  eq(other.gossipChosen, nil)
  eq(other:callsTo("ConfirmBinder"), {})
end)

-- Vendors and trainers ---------------------------------------------------------------------------------------------

test("a vendor line buys what is missing in full stacks, capped by stock, and closes the merchant", function()
  local wants45 = editStep(2, "inn", function(step) step.lines[2].buy = { item = 159, count = 45 } end)
  local c, Noir = at("inn", { section = TIRISFAL, level = 3, x = 61.7, y = 52.0, money = 100000, afterLoad = wants45 })
  eq(placeId(Noir), "inn")
  c:giveItem(159, 3)
  c:openMerchant(5688, {
    { item = 2287, price = 25 },
    { item = 159, price = 5, count = 30 },
  })
  -- 42 are missing, the vendor has 30: a stack of 20, then 10.
  eq(c:callsTo("BuyMerchantItem"), { { "BuyMerchantItem", 2, 20 }, { "BuyMerchantItem", 2, 10 } })
  eq(c:itemCount(159), 33)
  c:advance(0.2)
  eq(#c:callsTo("CloseMerchant"), 1, "closed once the bags have updated")
  -- With everything in the bags nothing is bought.
  local full = at("inn", { section = TIRISFAL, level = 3, x = 61.7, y = 52.0, money = 100000 })
  full:giveItem(159, 5)
  full:openMerchant(5688, { { item = 159, price = 5 } })
  full:advance(0.5)
  eq(full:callsTo("BuyMerchantItem"), {})
  eq(full:callsTo("CloseMerchant"), {}, "the merchant is the player's")
  -- buy off: nothing.
  local off = at("inn", { section = TIRISFAL, level = 3, x = 61.7, y = 52.0, money = 100000, options = { buy = false } })
  off:openMerchant(5688, { { item = 159, price = 5 } })
  off:advance(0.5)
  eq(off:callsTo("BuyMerchantItem"), {})
  -- An item sold in bundles of 5 (GetMerchantItemInfo's quantity): whole bundles, rounded up; the stock counts
  -- bundles.
  local wants7 = editStep(2, "inn", function(step) step.lines[2].buy = { item = 159, count = 7 } end)
  local bundles = at("inn", { section = TIRISFAL, level = 3, x = 61.7, y = 52.0, money = 100000, afterLoad = wants7 })
  bundles:openMerchant(5688, { { item = 159, price = 5, stack = 5 } })
  eq(bundles:callsTo("BuyMerchantItem"), { { "BuyMerchantItem", 1, 10 } })
  eq(bundles:itemCount(159), 10)
  local wants45b = editStep(2, "inn", function(step) step.lines[2].buy = { item = 159, count = 45 } end)
  local big = at("inn", { section = TIRISFAL, level = 3, x = 61.7, y = 52.0, money = 100000, afterLoad = wants45b })
  big:openMerchant(5688, { { item = 159, price = 5, stack = 6, count = 5 } })
  -- 45 wanted, 5 bundles of 6 in stock: 30, in purchases of at most 18 (the most whole bundles under 20).
  eq(big:callsTo("BuyMerchantItem"), { { "BuyMerchantItem", 1, 18 }, { "BuyMerchantItem", 1, 12 } })
  eq(big:itemCount(159), 30)
end)

local SERVICES = {
  { name = "Fireball", rank = "Rank 2", kind = "available", level = 6, cost = 100, spell = 143 },
  { name = "Frost Armor", rank = "Rank 1", kind = "available", level = 1, cost = 10, spell = 168 },
  { name = "Arcane Intellect", rank = "Rank 1", kind = "unavailable", level = 8, cost = 200, spell = 1459 },
  { name = "Frostbolt", rank = "Rank 2", kind = "available", level = 4, cost = 50, spell = 205 },
}

test("the trainer buys class spells for 15 s every 0.2 s when switched on, and nothing when off", function()
  local c = at("a363", { level = 8, money = 100000, options = { train = true } })
  c:openTrainer(2124, SERVICES)
  eq(c:callsTo("BuyTrainerService"), {}, "not before the first 0.2 s")
  c:advance(0.2)
  eq(c:callsTo("BuyTrainerService"), { { "BuyTrainerService", 2 } }, "the lowest level first")
  c:advance(0.4)
  eq(c:callsTo("BuyTrainerService"), { { "BuyTrainerService", 2 }, { "BuyTrainerService", 4 }, { "BuyTrainerService", 1 } })
  c:advance(1)
  eq(#c:callsTo("BuyTrainerService"), 3, "an unavailable service is never bought")
  -- After 15 s the trainer is left alone.
  c:advance(14)
  c.trainer.services[3].kind = "available"
  c:advance(1)
  eq(#c:callsTo("BuyTrainerService"), 3)

  local off = at("a363", { level = 8, money = 100000 })
  off:openTrainer(2124, SERVICES)
  off:advance(2)
  eq(off:callsTo("BuyTrainerService"), {})

  -- Pet trainers, and profession trainers without a train line on screen, are skipped.
  local pet = at("a363", { level = 8, money = 100000, options = { train = true } })
  pet:openTrainer(3698, { { name = "Growl", rank = "Rank 2", kind = "available", level = 8, skillLine = "Beast Training" } })
  pet:advance(1)
  eq(pet:callsTo("BuyTrainerService"), {})
  pet:closeTrainer()
  pet:openTrainer(3175, { { name = "Mining", rank = "Apprentice", kind = "available", level = 5 } }, { tradeskill = true })
  pet:advance(1)
  eq(pet:callsTo("BuyTrainerService"), {})
end)

test("at a profession trainer only what a train line on a card names is bought", function()
  local c, Noir = at("train.spell", { section = TIRISFAL, level = 8, money = 100000, x = 61.9, y = 52.5, options = { train = true } })
  eq(placeId(Noir), "train.spell")
  c.world.spells[1459] = "Arcane Intellect"
  c:openTrainer(2124, {
    { name = "Something Else", rank = "", kind = "available", level = 1 },
    { name = "Arcane Intellect", rank = "Rank 1", kind = "available", level = 8, spell = 1459 },
  }, { tradeskill = true })
  c:advance(1)
  eq(c:callsTo("BuyTrainerService"), { { "BuyTrainerService", 2 } })
end)

-- Section rules and switches ---------------------------------------------------------------------------------------

local AT_WAR = { title = "At War With The Scarlet Crusade", level = 4, objectives = {} }

test("nothing is done for a quest in the section's noAuto list", function()
  -- Quest 370 is in Tirisfal's noAuto list; the step's manual flag is taken away so only the list stops it.
  local c, Noir = at("a370", { section = TIRISFAL, level = 4, x = 60, y = 52, world = { quests = { [370] = AT_WAR } },
    afterLoad = editStep(2, "a370", function(step) step.lines[1].manual = nil end) })
  eq(placeId(Noir), "a370")
  c:talkTo(1500, { name = "Coleman Farthing", offers = { 370 } })
  eq(c:callsTo("AcceptQuest"), {})
  eq(c.dialog and c.dialog.quest, 370)
  c:closeNpc()
  c:shareQuest(370, "Friend")
  eq(c:callsTo("ConfirmAcceptQuest"), {})
end)

test("a manual accept line is left to the player", function()
  local c, Noir = at("a370", { section = TIRISFAL, level = 4, x = 60, y = 52, world = { quests = { [370] = AT_WAR } },
    afterLoad = function(client) client.G.Noir.Routes.Get("horde-undead").sections[2].noAuto = nil end })
  eq(placeId(Noir), "a370")
  c:talkTo(1500, { name = "Coleman Farthing", offers = { 370 } })
  eq(c:callsTo("AcceptQuest"), {})
end)

test("the switches turn each part off", function()
  local c = at("a363", { options = { autoQuests = false } })
  c:talkTo(1568, MORDO)
  eq(c:callsTo("AcceptQuest"), {})
  eq(c.G.Noir.Automation.Enabled("autoQuests"), false)
  eq(c.G.Noir.Automation.Enabled("flights"), true)
  eq(c.G.Noir.Automation.Enabled("train"), false, "trainer automation is off by default")
  eq(c.G.Noir.Automation.Enabled("windowScale"), false, "not an automation key")
  local inn = at("inn", { section = TIRISFAL, level = 3, x = 61.7, y = 52.0, options = { hearth = false } })
  inn:talkTo(5688)
  inn:advance(0.5)
  eq(inn.gossipChosen, nil)
  eq(inn:callsTo("ConfirmBinder"), {})
end)
