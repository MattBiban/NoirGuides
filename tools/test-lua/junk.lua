-- Noir Guides, GPLv3. See LICENSE.
-- Selling grey items before early class training (0.4.0): the money and the grey items State follows, the training
-- cost it remembers account-wide, the selljunk line (Lines.lua), its words (UI/Text.lua), the automatic sale at
-- merchants (Automation.lua) and the shape of NoirGuidesDB.trainerCosts (Core.lua). Driven by game events, windows and
-- the bags only.
use("tools/test-lua/sample/helper.lua")

local GREY, GREY2, WHITE, NOVALUE = 90001, 90002, 90010, 90020
local ITEMS = {
  items = { [GREY] = "Cracked Fang", [GREY2] = "Frayed Hide Scrap", [WHITE] = "Linen Scrap", [NOVALUE] = "Old Letter" },
  qualities = { [GREY] = 0, [GREY2] = 0, [WHITE] = 1, [NOVALUE] = 0 },
  prices = { [GREY] = 4, [GREY2] = 9, [WHITE] = 13 },
}
local GUID = "Player-4444-0000002A"
local KEY = "Tester-Mock"
local TIRISFAL = "undead-03-05-tirisfal-glades"

local function withItems(c)
  for kind, entries in pairs(ITEMS) do
    c.world[kind] = c.world[kind] or {}
    for id, value in pairs(entries) do c.world[kind][id] = value end
  end
  return c
end

-- A logged-in character (opts as for Client.new; money in copper).
local function play(opts)
  opts = opts or {}
  local c = withItems(sample3(opts))
  c.s.money = opts.money or 0
  c:login()
  return c, c.G.Noir
end

local function savedAt(section, stepId, account)
  local db = { schema = 2, owner = GUID, guide = { section = section, how = "hand", places = { [section] = { step = stepId } } } }
  return { account = account or {}, characters = { [KEY] = { NoirGuidesCharDB = db } } }
end

-- A visit step of a mage at level 4 with its selljunk line.
local function visit()
  return { id = "tMAGE-4", n = 1, minLevel = 4, lines = {
    { kind = "train", class = "MAGE", level = 4, npc = 2124 },
    { kind = "selljunk", npc = 5688, at = { zone = 85, x = 61.7, y = 52, r = 10 } },
  } }
end

local function sell(Noir, step, since)
  return Noir.Lines.Check(step.lines[2], step, { since = since })
end

local SERVICES = {
  { name = "Fireball", rank = "Rank 2", kind = "available", level = 4, cost = 100 },
  { name = "Frost Armor", rank = "Rank 1", kind = "available", level = 1, cost = 10 },
  { name = "Arcane Intellect", rank = "Rank 1", kind = "unavailable", level = 8, cost = 200 },
  { name = "Frostbolt", rank = "Rank 2", kind = "available", level = 4, cost = 50 },
}

-- State ------------------------------------------------------------------------------------------------------------

test("State follows the money through PLAYER_MONEY and says so with NOIR_STATE money", function()
  local c, Noir = play({ money = 500 })
  eq(Noir.State.money, 500)
  local said = {}
  Noir.On("NOIR_STATE", function(_, what) said[#said + 1] = what end)
  c:setMoney(1234)
  eq(Noir.State.money, 1234)
  eq(said, { "money" })
  c:setMoney(1234)
  eq(said, { "money" }, "no change, no event")
end)

test("the grey items are the quality 0 slots that sell, with their value, through either container API", function()
  for _, api in ipairs({ "classic", "modern" }) do
    local c, Noir = play({ api = api })
    eq(Noir.State.JunkSlots(), {}, api .. ": empty bags")
    c:giveItem(GREY, 3)
    c:giveItem(WHITE, 2)
    c:giveItem(NOVALUE, 1)
    c:giveItem(GREY2, 1)
    local slots = Noir.State.JunkSlots()
    eq(#slots, 2, api .. ": the white item and the grey item without a price are not junk")
    eq({ slots[1].item, slots[1].count, slots[1].price, slots[1].value }, { GREY, 3, 4, 12 }, api)
    eq({ slots[2].item, slots[2].value }, { GREY2, 9 }, api)
    local value, stacks = Noir.State.Junk()
    eq({ value, stacks }, { 21, 2 }, api)
    ok(api == "modern" and c.G.C_Container ~= nil or c.G.GetContainerItemInfo ~= nil, api .. " has its own API")
  end
end)

test("a class trainer's available services are remembered per class and level, account-wide, never lowered", function()
  local c, Noir = play({ class = "MAGE", level = 4, money = 5000 })
  eq(Noir.State.TrainingCost("MAGE", 4), nil)
  eq(Noir.db.trainerCosts, nil, "reading makes nothing")
  c:openTrainer(2124, SERVICES)
  eq(Noir.State.TrainingCost("MAGE", 4), 160, "100 + 10 + 50; the unavailable one is not counted")
  eq(Noir.db.trainerCosts, { MAGE = { [4] = 160 } })
  c.G.BuyTrainerService(1)
  c:closeTrainer()
  c:openTrainer(2124, { { name = "Frost Armor", rank = "Rank 1", kind = "available", level = 1, cost = 10 } })
  c:closeTrainer()
  eq(Noir.State.TrainingCost("MAGE", 4), 160, "a later, smaller list does not lower it")
  c:openTrainer(3000, { { name = "Mining", rank = "Journeyman", kind = "available", cost = 500 } }, { tradeskill = true })
  c:closeTrainer()
  c:openTrainer(3001, { { name = "Growl", rank = "Rank 2", kind = "available", cost = 900, skillLine = "Beast Training" } })
  c:closeTrainer()
  eq(Noir.db.trainerCosts, { MAGE = { [4] = 160 } }, "profession and pet trainers are not class training")
  -- Another character of the account knows it.
  c:logout()
  local other = withItems(sample3({ name = "Other", class = "MAGE", level = 4, saved = c.saved }))
  other:login()
  eq(other.G.Noir.State.TrainingCost("MAGE", 4), 160)
  eq(other.G.Noir.State.TrainingCost("WARRIOR", 4), nil)
end)

test("NoirGuidesDB.trainerCosts keeps only class tables of whole levels 1 to 60 with copper of at least 0", function()
  local account = { NoirGuidesDB = { schema = 2, profiles = { Default = {} }, defaultProfile = "Default",
    trainerCosts = { MAGE = { [4] = 160, [6] = 0, [0] = 5, [61] = 9, [2.5] = 3, x = 2, [8] = -1, [10] = "lots" }, WARRIOR = "x", [3] = { [4] = 1 } } } }
  local c = sample3({ saved = { account = account, characters = {} } })
  c:login()
  eq(c.G.Noir.db.trainerCosts, { MAGE = { [4] = 160, [6] = 0 } })
  local bad = sample3({ saved = { account = { NoirGuidesDB = { schema = 2, trainerCosts = 7 } }, characters = {} } })
  bad:login()
  eq(bad.G.Noir.db.trainerCosts, nil, "not a table: dropped")
  eq(bad.G.Noir.db.profiles, { Default = {} })
  -- Schema 1 still migrates, with no costs yet.
  local old = sample3({ saved = { account = { NoirGuidesDB = { schema = 1, options = { auto = { accept = true } } } }, characters = {} } })
  old:login()
  eq(old.G.Noir.db.schema, 2)
  eq(old.G.Noir.db.profiles.Default.autoQuests, true)
  eq(old.G.Noir.db.trainerCosts, nil)
end)

-- The selljunk line ------------------------------------------------------------------------------------------------

test("selljunk is hidden without grey items, and while the money covers the remembered cost of the training", function()
  local c, Noir = play({ class = "MAGE", level = 4, money = 100 })
  local step = visit()
  local since = c.now
  eq((sell(Noir, step, since)), "hidden", "no grey items")
  c:giveItem(WHITE, 4)
  eq((sell(Noir, step, since)), "hidden", "white items are not junk")
  c:giveItem(GREY, 2)
  eq((sell(Noir, step, since)), "todo", "grey items, cost unknown, 100 copper is under the floor")
  eq(Noir.Lines.SELL_JUNK_FLOOR, 1000)
  c:setMoney(999)
  eq((sell(Noir, step, since)), "todo")
  c:setMoney(1000)
  eq((sell(Noir, step, since)), "hidden", "the cost unknown, 10 silver is enough to hide it")
  -- A cost remembered from an earlier visit decides instead of the floor.
  Noir.db.trainerCosts = { MAGE = { [4] = 1500 } }
  eq(Noir.Lines.TrainingCost(step), 1500)
  eq((sell(Noir, step, since)), "todo", "1000 copper does not cover 1500")
  c:setMoney(1500)
  eq((sell(Noir, step, since)), "hidden", "covered")
  Noir.db.trainerCosts = { MAGE = { [4] = 160 } }
  c:setMoney(200)
  eq((sell(Noir, step, since)), "hidden", "200 covers 160, below the floor or not")
  c:setMoney(150)
  eq((sell(Noir, step, since)), "todo")
end)

test("selljunk shows while an open trainer lists a service the money does not cover, and hides once the visit is done", function()
  local c, Noir = play({ class = "MAGE", level = 4, money = 300 })
  Noir.db.trainerCosts = { MAGE = { [4] = 160 } }
  local step = visit()
  local since = c.now
  c:giveItem(GREY, 1)
  eq((sell(Noir, step, since)), "hidden", "300 covers what was remembered")
  c:advance(1)
  c:openTrainer(2124, { { name = "Blink", rank = "Rank 1", kind = "available", level = 4, cost = 500 } })
  eq((sell(Noir, step, since)), "todo", "Blink costs 500")
  c:advance(1)
  c:closeTrainer()
  eq((Noir.Lines.Check(step.lines[1], step, { since = since })), "done", "the visit")
  eq((sell(Noir, step, since)), "hidden", "the train line is done: too late to sell for it")
end)

test("selljunk is done when a merchant window opens and closes after the step became current", function()
  local c, Noir = play({ class = "MAGE", level = 4, money = 0 })
  local step = visit()
  c:openMerchant(1234, {})
  c:closeMerchant()
  c:advance(2)
  c:giveItem(GREY, 1)
  local since = c.now
  eq((sell(Noir, step, since)), "todo", "a merchant visit before the step does not count")
  c:advance(1)
  c:openMerchant(1234, {}) -- any merchant, not only the line's
  c:advance(1)
  local state, evidence = sell(Noir, step, since)
  eq({ state, evidence }, { "done", "grey items sold" }, "the automation sold them while the window is open")
  c:closeMerchant()
  state, evidence = sell(Noir, step, since)
  eq({ state, evidence }, { "done", "sold at a vendor" })
  -- With the automatic sale off the window must close first.
  local off, ONoir = play({ class = "MAGE", level = 4, money = 0,
    saved = { account = { NoirGuidesDB = { schema = 2, profiles = { Default = { sellJunk = false } }, defaultProfile = "Default" } }, characters = {} } })
  off:giveItem(GREY, 1)
  local osince = off.now
  off:advance(1)
  off:openMerchant(1234, {})
  off:advance(1)
  eq((sell(ONoir, step, osince)), "todo", "still open, still grey items")
  off:closeMerchant()
  eq((sell(ONoir, step, osince)), "done")
end)

test("selljunk is an active line whose place is the merchant's while it is open", function()
  local c, Noir = play({ class = "MAGE", level = 4, money = 0 })
  local step = visit()
  step.at = { zone = 85, x = 30.9, y = 66.1, r = 10 }
  eq(Noir.Lines.Active(step.lines[2]), true)
  eq(#Noir.Lines.Places(step, {}, { since = c.now }), 1, "no grey items: the trainer only")
  c:giveItem(GREY, 1)
  local places = Noir.Lines.Places(step, {}, { since = c.now })
  eq(#places, 2)
  eq(places[2].line, 2)
end)

-- Words ------------------------------------------------------------------------------------------------------------

test("money is written in gold, silver and copper, leaving out the parts that are 0", function()
  local _, Noir = play()
  local Money = Noir.Text.Money
  eq(Money(0), "0c")
  eq(Money(85), "85c")
  eq(Money(120), "1s 20c")
  eq(Money(10000), "1g")
  eq(Money(10005), "1g 5c")
  eq(Money(1234567), "123g 45s 67c")
  eq(Money(-3), "0c")
end)

test("the selljunk line names the merchant and, when known, what training costs and what the character has", function()
  local c, Noir = play({ class = "MAGE", level = 4, money = 85 })
  local step = visit()
  local t = Noir.Text.Line(step.lines[2], step)
  eq(t.text, "Sell your grey items at Innkeeper Renee before training")
  eq(t.icon, "vendor")
  eq(t.spans[1].kind, "friend")
  eq(string.sub(t.text, t.spans[1].from, t.spans[1].to), "Innkeeper Renee")
  Noir.db.trainerCosts = { MAGE = { [4] = 120 } }
  eq(Noir.Text.Line(step.lines[2], step).text, "Sell your grey items at Innkeeper Renee (training costs about 1s 20c, you have 85c)")
  c:setMoney(10250)
  eq(Noir.Text.Line(step.lines[2], step).text, "Sell your grey items at Innkeeper Renee (training costs about 1s 20c, you have 1g 2s 50c)")
end)

-- The automatic sale -----------------------------------------------------------------------------------------------

test("at a merchant the grey items are sold, one bag slot per tick, never anything above quality 0, with one chat line", function()
  local c, Noir = play({ money = 10 })
  eq(Noir.Options.Get("sellJunk"), true, "on by default")
  eq(Noir.Automation.SELL_EVERY, 0.2)
  c:giveItem(GREY, 3)
  c:giveItem(WHITE, 2)
  c:giveItem(GREY2, 1)
  c:giveItem(NOVALUE, 1)
  c:takeChat()
  c:openMerchant(1234, {})
  eq(c:callsTo("UseContainerItem"), {}, "nothing at once")
  ok(Noir.Automation.Read().selling)
  c:advance(0.2)
  eq(#c:callsTo("UseContainerItem"), 1, "one slot a tick")
  c:advance(1)
  eq(#c:callsTo("UseContainerItem"), 2)
  eq(c:itemCount(GREY), 0)
  eq(c:itemCount(GREY2), 0)
  eq(c:itemCount(WHITE), 2, "white items stay")
  eq(c:itemCount(NOVALUE), 1, "a grey item without a price stays")
  for _, sold in ipairs(c.sold) do eq(sold.quality, 0) end
  eq(c.s.money, 10 + 12 + 9)
  eq(Noir.Automation.Read().selling, false)
  has(c:chatText(), "Sold 4 grey items for 21c.")
  eq(#c:takeChat(), 1, "one line")
  c:closeMerchant()
  -- The modern container API sells through C_Container.
  local m, MNoir = play({ api = "modern" })
  m:giveItem(GREY, 1)
  m:openMerchant(1234, {})
  m:advance(1)
  eq(m:itemCount(GREY), 0)
  eq(MNoir.Automation.Read().selling, false)
end)

test("nothing is sold with sellJunk off, or when a modifier key is held as the merchant opens", function()
  local off = play({ saved = { account = { NoirGuidesDB = { schema = 2, profiles = { Default = { sellJunk = false } }, defaultProfile = "Default" } }, characters = {} } })
  off:giveItem(GREY, 2)
  off:openMerchant(1234, {})
  off:advance(1)
  eq(off:callsTo("UseContainerItem"), {})
  eq(off:itemCount(GREY), 2)
  for _, key in ipairs({ "SHIFT", "CTRL", "ALT" }) do
    local c = play()
    c:giveItem(GREY, 2)
    c.mods[key] = true
    c:openMerchant(1234, {})
    c.mods[key] = false
    c:advance(1)
    eq(c:callsTo("UseContainerItem"), {}, key)
    eq(c:itemCount(GREY), 2, key)
  end
end)

test("an item a collect line on the cards still needs is never sold, and closing the merchant stops the sale", function()
  local wantsGrey = function(client)
    for _, step in ipairs(client.G.Noir.Routes.Get("horde-undead").sections[2].steps) do
      if step.id == "inn" then table.insert(step.lines, { kind = "collect", item = GREY, count = 5 }) end
    end
  end
  local c = withItems(sample3({ class = "MAGE", level = 3, zone = 85, x = 61.7, y = 52.0, saved = savedAt(TIRISFAL, "inn"), afterLoad = wantsGrey }))
  c:login()
  c:advance(0.5)
  local _, _, _, step = c.G.Noir.Progress.Place()
  eq(step and step.id, "inn")
  c:giveItem(GREY, 3)
  c:giveItem(GREY2, 2)
  c:openMerchant(5688, {})
  c:advance(1)
  eq(c:itemCount(GREY), 3, "the collect line wants 5 of them")
  eq(c:itemCount(GREY2), 0)
  -- Closing the window ends the sale where it stands.
  local s = play()
  for _ = 1, 3 do
    s:giveItem(GREY, 20)
    s:giveItem(GREY2, 20)
  end
  s:openMerchant(1234, {})
  s:advance(0.2)
  s:closeMerchant()
  s:advance(1)
  eq(#s:callsTo("UseContainerItem"), 1)
  eq(s.G.Noir.Automation.Read().selling, false)
end)

test("a vendor line that closes the merchant after buying waits for the sale to end", function()
  local wants = function(client)
    for _, step in ipairs(client.G.Noir.Routes.Get("horde-undead").sections[2].steps) do
      if step.id == "inn" then step.lines[2].buy = { item = 159, count = 5 } end
    end
  end
  local c = withItems(sample3({ class = "MAGE", level = 3, zone = 85, x = 61.7, y = 52.0, saved = savedAt(TIRISFAL, "inn"), afterLoad = wants }))
  c.s.money = 100000
  c:login()
  c:advance(0.5)
  c:giveItem(GREY, 1)
  c:giveItem(GREY2, 1)
  c:openMerchant(5688, { { item = 159, price = 5 } })
  eq(c:itemCount(159), 5, "bought at once")
  c:advance(0.1)
  eq(c:callsTo("CloseMerchant"), {}, "still selling")
  c:advance(1)
  eq(c:itemCount(GREY) + c:itemCount(GREY2), 0)
  eq(#c:callsTo("CloseMerchant"), 1, "closed once the sale ended")
end)
