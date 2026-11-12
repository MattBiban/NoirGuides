-- Noir Guides, GPLv3. See LICENSE.
-- Cleanup.lua (spec 5.9, 6.1, gap #38): the quest log against the rest of the route, from the current step to the end
-- of the chain. Never listed: class, profession, dungeon and raid quests and anything under the class or a
-- profession header. Listed and ticked from the start: failed quests and quests off the route. Listed unticked:
-- grey quests still on the route, quests ready to hand in, event quests and quests started by an item. Nothing is
-- abandoned before the player presses the button; then bottom of the log first, one every 0.2 s, stopped by combat.
use("tools/test-lua/sample/ports.lua")

-- Made-up quest IDs; the test gives each its ties in Noir.Data.questTies.
local ROUTE_A, ROUTE_B, OFF, READY, ITEM, EVENT = 900001, 900002, 900003, 900004, 900005, 900006
local MINE, OTHER_CLASS, SKILLED, UNSKILLED, DUNGEON = 900007, 900008, 900009, 900010, 900011
local UNDER_CLASS, UNDER_TRADE = 900012, 900013

local STEPS = {
  { id = "a1", at = { zone = 14, x = 50, y = 50 }, lines = { { kind = "accept", quest = ROUTE_A } } },
  { id = "a2", at = { zone = 14, x = 50, y = 50 }, lines = { { kind = "accept", quest = ROUTE_B } } },
  { id = "t1", at = { zone = 14, x = 50, y = 50 }, lines = { { kind = "turnin", quest = ROUTE_A } } },
  { id = "t2", at = { zone = 14, x = 50, y = 50 }, lines = { { kind = "turnin", quest = ROUTE_B } } },
}

local TIES = {
  [ITEM] = { item = "Odd Note" },
  [EVENT] = { event = "Lunar Festival" },
  [MINE] = { classes = { "WARRIOR", "ROGUE" } },
  [OTHER_CLASS] = { classes = { "MAGE" } },
  [SKILLED] = { skill = 182 },
  [UNSKILLED] = { skill = 393 },
  [DUNGEON] = { instance = "Ragefire Chasm" },
}

local function quest(id, title, extra)
  local def = { title = title, level = 12, objectives = { { type = "monster", text = "Boar slain", need = 5 } } }
  for k, v in pairs(extra or {}) do def[k] = v end
  return def
end

local function start(opts)
  opts = opts or {}
  opts.level = opts.level or 12
  opts.class = opts.class or "WARRIOR"
  local c, Noir = portedRoute(STEPS, opts)
  for id, ties in pairs(TIES) do Noir.Data.questTies[id] = ties end
  c:setProfession(182, "Herbalism", 40, 75)
  c:acceptQuest(ROUTE_A, quest(ROUTE_A, "Route Quest A"))
  c:acceptQuest(OFF, quest(OFF, "Somewhere Else"))
  c:acceptQuest(READY, quest(READY, "Ready Elsewhere", { objectives = { { type = "monster", text = "Boar slain", need = 1, have = 1 } } }))
  c:acceptQuest(ITEM, quest(ITEM, "From an Item"))
  c:acceptQuest(MINE, quest(MINE, "My Class Quest"))
  return c, Noir.Cleanup, Noir
end

local function rows(C)
  local out = {}
  for _, row in ipairs((C.Scan())) do out[#out + 1] = { row.quest, row.group, row.ticked } end
  return out
end

local function reasonOf(C, id)
  for _, row in ipairs((C.Scan())) do
    if row.quest == id then return row.reason end
  end
end

local function rowOf(C, id)
  for _, row in ipairs((C.Scan())) do
    if row.quest == id then return row end
  end
end

for _, api in ipairs({ "classic", "modern" }) do
  test(api .. ": failed and off-route quests start ticked; grey on-route, ready, event and item-started quests are listed unticked", function()
    local c, C = start({ api = api, level = 30 })
    c:acceptQuest(EVENT, quest(EVENT, "A Festival"))
    c:acceptQuest(ROUTE_B, quest(ROUTE_B, "Route Quest B", { level = 29 }))
    c:failQuest(ROUTE_B)
    eq(rows(C), {
      { OFF, "drop", true }, { ROUTE_B, "drop", true },
      { EVENT, "check", false }, { ITEM, "check", false }, { READY, "check", false }, { ROUTE_A, "check", false },
    })
    eq(reasonOf(C, OFF), "Grey, and not on your route")
    has(reasonOf(C, ROUTE_B), "Failed")
    eq(reasonOf(C, EVENT), "Offered only during Lunar Festival")
    has(reasonOf(C, ITEM), "Odd Note")
    has(reasonOf(C, READY), "Ready to hand in")
    eq(reasonOf(C, ROUTE_A), "Grey, but your route still uses it")
  end)

  test(api .. ": nothing is abandoned until the player presses the button; then only what is ticked", function()
    local c, C, Noir = start({ api = api })
    C.Open()
    eq(C.Ticked(), { OFF }, "the off-route quest starts ticked")
    c:advance(2)
    eq(#c:callsTo("AbandonQuest"), 0, "nothing goes by itself")
    ok(c:click(C.RowFrame(ITEM)), "the row takes the click")
    eq(C.Ticked(), { OFF, ITEM })
    has(C.Read().button, "Abandon 2 quests")
    ok(c:click(C.ButtonFrame()))
    c:advance(2)
    no(c:findQuest(OFF), "a ticked quest is gone")
    no(c:findQuest(ITEM), "a ticked quest is gone")
    ok(c:findQuest(READY) and c:findQuest(MINE) and c:findQuest(ROUTE_A), "the others stay")
    eq(#c:callsTo("AbandonQuest"), 2)
    has(c:chatText(), "Abandoned 2 quests")
    eq(rows(C), { { READY, "check", false } })
    no(Noir.State.HasQuest(OFF))
    eq(c:offScreen(), {})
  end)
end

test("abandoning goes from the bottom of the quest log up, one every 0.2 s", function()
  local c, C = start()
  C.Open()
  c:click(C.RowFrame(ITEM))
  c:click(C.RowFrame(READY))
  eq(C.Abandon(), 3)
  -- The log holds OFF, READY, ITEM in that order (accepted so): ITEM goes first.
  eq(#c:callsTo("AbandonQuest"), 1)
  ok(c:findQuest(OFF) and c:findQuest(READY), "the higher ones wait")
  no(c:findQuest(ITEM), "the bottom one went first")
  c:advance(0.15, 0.05)
  eq(#c:callsTo("AbandonQuest"), 1, "not before 0.2 s")
  c:advance(0.1, 0.05)
  eq(#c:callsTo("AbandonQuest"), 2)
  no(c:findQuest(READY))
  c:advance(0.2, 0.05)
  no(c:findQuest(OFF))
end)

test("class and profession quests are never listed", function()
  local c, C = start()
  c:acceptQuest(OTHER_CLASS, quest(OTHER_CLASS, "Arcane Business"))
  c:acceptQuest(SKILLED, quest(SKILLED, "Herbs"))
  c:acceptQuest(UNSKILLED, quest(UNSKILLED, "Hides"))
  c:acceptQuest(DUNGEON, quest(DUNGEON, "Into the Chasm"))
  c:acceptQuest(UNDER_CLASS, quest(UNDER_CLASS, "Warrior Business", { header = "Warrior" }))
  c:acceptQuest(UNDER_TRADE, quest(UNDER_TRADE, "Fishy Business", { header = "Fishing" }))
  c:failQuest(UNDER_TRADE)
  for _, id in ipairs({ MINE, OTHER_CLASS, SKILLED, UNSKILLED, DUNGEON, UNDER_CLASS, UNDER_TRADE }) do
    eq(rowOf(C, id), nil, "quest " .. id .. " is not listed")
  end
  -- The real generated data: quest 26 is a Druid quest in NoirGuides/Data/Cleanup.lua.
  ok(c.G.Noir.Data.questTies[26], "the generated file defines quest 26")
  c:acceptQuest(26, quest(26, "A Druid Quest"))
  eq(rowOf(C, 26), nil)
end)

test("the class header is found in the client's language", function()
  local c, C = start()
  c.G.LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Krieger" }
  c:acceptQuest(UNDER_CLASS, quest(UNDER_CLASS, "Kriegerkram", { header = "Krieger" }))
  eq(rowOf(C, UNDER_CLASS), nil)
end)

test("a quest the rest of the route names is not listed; one only behind the current step is", function()
  local c, C, Noir = start()
  c:acceptQuest(ROUTE_B, quest(ROUTE_B, "Route Quest B"))
  eq(rowOf(C, ROUTE_A), nil)
  eq(rowOf(C, ROUTE_B), nil)
  -- The player goes on to the last step: ROUTE_A is behind and no later step names it.
  ok(Noir.Progress.Jump(4, "list"))
  local row = rowOf(C, ROUTE_A)
  eq({ row.group, row.ticked, row.reason }, { "drop", true, "Not on your route" })
  eq(rowOf(C, ROUTE_B), nil, "still handed in by the current step")
end)

test("Offer opens nothing when no row would start ticked", function()
  local c, C = start()
  c:abandonQuest(OFF)
  ok(rowOf(C, READY), "there are rows, but none starts ticked")
  no(C.Offer())
  eq(C.Read().shown, false)
  c:acceptQuest(EVENT + 100, quest(EVENT + 100, "Far Away"))
  ok(C.Offer())
  eq(C.Read().shown, true)
  eq(C.Ticked(), { EVENT + 100 })
  eq(c:offScreen(), {})
end)

test("the window is on screen at 1024x768 with 25 rows", function()
  -- 25 rows need a log larger than the classic 20 quests (Forever's log size is not known; the window must not care).
  local c, C = start({ screen = { w = 1024, h = 768, scale = 1 }, questLogSize = 35 })
  for i = 1, 22 do c:acceptQuest(910000 + i, quest(910000 + i, string.format("Far Away %02d", i), { level = 5 + i % 7 })) end
  C.Open()
  local view = C.Read()
  eq(view.shown, true)
  eq(#view.rows, 25, "every row is in the list")
  eq(c:offScreen(), {})
  local _, bottom, _, top = c:rectOf(C.frame)
  ok(top - bottom <= 0.9 * 768 + 0.5, "capped at 90% of the screen's height")
  local _, buttonBottom = c:rectOf(C.ButtonFrame())
  ok(buttonBottom >= bottom - 0.5, "the button is inside the window")
  -- A larger UI scale leaves less room: the window is fitted again and the rest of the rows scroll.
  c:setScreen(1024, 768, 1.5)
  eq(c:offScreen(), {})
  _, bottom, _, top = c:rectOf(C.frame)
  ok(top - bottom <= 0.9 * 768 / 1.5 + 0.5, "capped at 90% of the smaller screen")
  ok(C.List():Range() > 0, "the rest scrolls")
  _, buttonBottom = c:rectOf(C.ButtonFrame())
  ok(buttonBottom >= bottom - 0.5, "the button stays inside the window")
  ok(c:click(C.ButtonFrame()), "the button takes the click below the list")
  c:advance(6)
  c:setScreen(1920, 1080, 0.64)
  eq(c:offScreen(), {})
end)

test("the quest log button opens it", function()
  local c, C = start()
  local button = C.LogButton()
  ok(button, "a button is anchored beside the quest log frame")
  no(button:IsVisible(), "hidden while the quest log is closed")
  c:openQuestLog()
  ok(button:IsVisible(), "shown with the quest log")
  local left = c:rectOf(button)
  local _, _, logRight = c:rectOf(c.G.QuestLogFrame)
  ok(left >= logRight - 0.5, "beside the quest log frame")
  ok(c:click(button), "it takes the click")
  eq(C.Read().shown, true)
  c:closeQuestLog()
  eq(c:offScreen(), {})
end)

test("Keep everything closes the window and abandons nothing", function()
  local c, C = start()
  C.Open()
  ok(c:click(C.CloseFrame()))
  eq(C.Read().shown, false)
  c:advance(2)
  eq(#c:callsTo("AbandonQuest"), 0)
end)

test("clicking a ticked row unticks it, and clicking it again ticks it", function()
  local c, C = start()
  C.Open()
  c:click(C.RowFrame(OFF))
  eq(C.Ticked(), {})
  has(C.Read().button, "Abandon 0 quests")
  c:click(C.RowFrame(OFF))
  eq(C.Ticked(), { OFF })
end)

test("nothing is abandoned in combat", function()
  local c, C = start()
  C.Open()
  c:enterCombat()
  c:takeChat()
  eq(C.Abandon(), 0)
  has(c:chatText(), "combat")
  c:advance(2)
  ok(c:findQuest(OFF))
end)

test("combat that starts during the abandoning stops it", function()
  local c, C = start()
  C.Open()
  c:click(C.RowFrame(ITEM))
  eq(C.Abandon(), 2)
  c:enterCombat()
  c:advance(2)
  eq(#c:callsTo("AbandonQuest"), 1, "the first went before the fight")
  c:leaveCombat()
  c:advance(2)
  eq(#c:callsTo("AbandonQuest"), 1, "the rest waits for the player to press again")
end)

test("a ticked quest that left the log in the meantime is passed over", function()
  local c, C = start()
  C.Open()
  c:abandonQuest(OFF)
  C.Abandon()
  c:advance(2)
  eq(#c:callsTo("AbandonQuest"), 0)
end)

test("a ticked quest that became the character's own training by its turn is not abandoned", function()
  local c, C = start()
  C.Open()
  c:click(C.RowFrame(ITEM))
  eq(C.Abandon(), 2)
  -- The bottom quest (ITEM) goes at once; before OFF's turn it becomes a profession quest.
  no(c:findQuest(ITEM))
  c.G.Noir.Data.questTies[OFF] = { skill = 393 }
  c:advance(2)
  ok(c:findQuest(OFF))
  ok(c:findQuest(MINE))
end)

test("only the player's click ticks a quest: there is no function that ticks one", function()
  local _, C = start()
  for name, value in pairs(C) do
    ok(not (type(value) == "function" and string.find(string.lower(name), "tick") and name ~= "Ticked"), "Cleanup." .. name .. " could tick a quest")
  end
end)

test("/noir cleanup shows both groups under their headings", function()
  local c, C = start()
  c:slash("/noir cleanup")
  local view = C.Read()
  eq(view.shown, true)
  eq(#view.rows, 3)
  has(view.rows[1], "Somewhere Else")
  has(view.rows[1], "Not on your route")
  local text = shownText(c, C.frame)
  has(text, "Nothing is abandoned until you press")
  has(text, "OFF YOUR ROUTE")
  has(text, "CHECK BEFORE DROPPING")
  has(view.close, "Keep everything")
end)

test("a group with no quests shows no heading", function()
  local c, C = start()
  c:abandonQuest(READY)
  c:abandonQuest(ITEM)
  C.Open()
  local text = shownText(c, C.frame)
  has(text, "OFF YOUR ROUTE")
  no(string.find(text, "CHECK BEFORE DROPPING", 1, true))
end)

test("without a route the cleanup lists nothing and says why", function()
  local c = ported({ race = "Orc", zone = 14, swap = { { match = "^Data/", with = { SAMPLE3_DATA, "NoirGuides/Data/Cleanup.lua" } }, { match = "^Routes/", with = {} } } }):login()
  c:acceptQuest(OFF, quest(OFF, "Somewhere Else"))
  local C = c.G.Noir.Cleanup
  local list, hasRoute = C.Scan()
  eq(list, {})
  no(hasRoute)
  no(C.Offer())
  c:slash("/noir cleanup")
  has(shownText(c, C.frame), "No route")
end)
