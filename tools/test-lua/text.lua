-- Noir Guides, GPLv3. See LICENSE.
-- Text: the words, icon and highlighted names of every kind of line, built from the line and Noir.Data (plan task
-- E3, spec 3.1, 3.2).
use("tools/test-lua/sample/helper.lua")

local function play(opts)
  local c = sample3(opts):login()
  return c, c.G.Noir, c.G.Noir.Text
end

local function line(Text, l, step)
  return Text.Line(l, step or { id = "s", n = 1, lines = { l } })
end

-- The text of each span, as "kind:text".
local function spans(t)
  local out = {}
  for i, s in ipairs(t.spans or {}) do out[i] = s.kind .. ":" .. string.sub(t.text, s.from, s.to) end
  return out
end

test("each line kind has its words and icon", function()
  local c, Noir, Text = play({ class = "MAGE", level = 2, zone = 85, x = 30, y = 70 })
  Noir.Data.professions = { [186] = { name = "Mining", kind = "primary" } } -- left out of the sample data
  local function words(l, step)
    local t = line(Text, l, step)
    return { t.text, t.icon }
  end
  eq(words({ kind = "accept", quest = 364, npc = 1569 }), { "Accept The Mindless Ones", "accept" })
  eq(line(Text, { kind = "accept", quest = 364 }).quest, 364)
  eq(words({ kind = "turnin", quest = 364 }), { "Turn in The Mindless Ones", "turnin" })
  -- Objectives: the quest log's own text with have/need.
  c:acceptQuest(364)
  eq(words({ kind = "objective", quest = 364, index = 1, npc = 1501 }), { "Mindless Zombie slain: 0/8", "kill" })
  c:progressQuest(364, 1, 3)
  eq(words({ kind = "objective", quest = 364, index = 1 }), { "Mindless Zombie slain: 3/8", "kill" })
  eq(words({ kind = "objective", quest = 364, index = 2, cap = 4 }), { "Wretched Zombie slain: 0/4", "kill" }, "the cap is the need")
  c:acceptQuest(376)
  eq(words({ kind = "objective", quest = 376, index = 1 }), { "Scavenger Paw: 0/6", "item" })
  eq(words({ kind = "objective", quest = 365, index = 1, npc = 1501 }), { "Fields of Grief: objective 1", "kill" }, "not in the log")
  c:acceptQuest(363, { title = "Rude Awakening", objectives = {} })
  eq(words({ kind = "objective", quest = 363, index = 1 }), { "Rude Awakening: 0/1", "objective" })
  eq(words({ kind = "collect", item = 2834, count = 4, quest = 376 }), { "Collect Embalming Ichor 0/4", "item" })
  c:giveItem(2834, 2)
  eq(words({ kind = "collect", item = 2834, count = 4 }), { "Collect Embalming Ichor 2/4", "item" })
  eq(words({ kind = "goto", at = { zone = 85, x = 38.2, y = 56.8, r = 15 } }), { "Go to Tirisfal Glades 38.2, 56.8", "goto" })
  eq(words({ kind = "goto", at = { zone = 130, x = 0, y = 0, r = 5 } }), { "Go to Silverpine Forest", "goto" })
  eq(words({ kind = "getflight", node = 384, npc = 4551 }), { "Get the Brill, Tirisfal Glades flight point", "flightpoint" })
  eq(words({ kind = "fly", from = 384, to = 10 }), { "Fly to The Sepulcher, Silverpine Forest", "flight" })
  eq(words({ kind = "transport", mode = "zeppelin", at = { zone = 85, x = 60.7, y = 58.8 }, to = { zone = 14, x = 50.8, y = 13.6 } }),
    { "Take the zeppelin to Durotar", "flight" })
  eq(words({ kind = "sethearth", npc = 5688 }, { id = "s", n = 1, at = { zone = 85, x = 61.7, y = 52 }, lines = {} }),
    { "Set your hearthstone at Tirisfal Glades", "bind" })
  eq(words({ kind = "hearth", to = { zone = 85, x = 61.7, y = 52.0, r = 20 } }), { "Hearth to Tirisfal Glades", "hearth" })
  eq(words({ kind = "grind", level = 4 }), { "Grind to level 4", "xp" })
  eq(words({ kind = "grind", level = 3 }), { "Grind to level 3 0/800", "xp" }, "the counter while working toward it")
  eq(words({ kind = "grind", level = 2, percent = 30 }), { "Grind until 30% into level 2 0/240", "xp" })
  eq(words({ kind = "grind", level = 5, percent = 30 }), { "Grind until 30% into level 5", "xp" })
  eq(words({ kind = "train", spell = 556 }), { "Learn Astral Recall", "trainer" })
  eq(words({ kind = "train", skill = 186, rank = 2 }), { "Learn Journeyman Mining", "trainer" })
  eq(words({ kind = "train", class = "MAGE", level = 4, npc = 2124 }), { "Visit Isabella to learn your level 4 spells", "trainer" })
  eq(words({ kind = "vendor", npc = 5688, buy = { item = 159, count = 5 } }),
    { "Visit Innkeeper Renee, buy 5 Refreshing Spring Water", "vendor" })
  eq(words({ kind = "vendor", npc = 5688 }), { "Visit Innkeeper Renee", "vendor" })
  eq(words({ kind = "use", item = 2856 }), { "Use Scavenger Paw", "item" })
  eq(words({ kind = "target", npc = 1765, enemy = true }), { "Kill Worg", "kill" })
  eq(words({ kind = "target", npc = 1950 }), { "Talk to Rane Yorick", "gossip" })
  eq(words({ kind = "note", text = "Follow the road." }), { "Follow the road.", "note" })
  eq(words({ kind = "manual", text = "Open the chest." }), { "Open the chest.", "note" })
end)

test("names come from Noir.Data, then the client, then 'Quest 364'", function()
  local c, Noir, Text = play()
  eq(Text.QuestName(364), "The Mindless Ones", "from the data")
  Noir.Data.quests[364] = nil
  eq(Text.QuestName(364), "The Mindless Ones", "from the client")
  eq(Text.QuestName(5000), "Quest 5000", "nobody knows it")
  c:acceptQuest(5000, { title = "A Quest Only The Log Names" })
  eq(Text.QuestName(5000), "A Quest Only The Log Names", "from the quest log")
  eq(Text.QuestName(99999), "Quest 99999")
  eq(Text.NpcName(1569), "Shadow Priest Sarvis")
  eq(Text.NpcName(42), "NPC 42")
  eq(Text.ItemName(2834), "Embalming Ichor")
  eq(Text.ItemName(2287), "Haunch of Meat", "from the client's item cache")
  eq(Text.ItemName(1), "Item 1")
  eq(Text.ZoneName(85), "Tirisfal Glades")
  eq(Text.ZoneName(1637), "Orgrimmar", "from the client's area names")
  eq(Text.ZoneName(5), "Zone 5")
  eq(Text.FlightName(384), "Brill, Tirisfal Glades")
  eq(Text.FlightName(7), "Flight point 7")
  eq(Text.Place({ zone = 85, x = 30.84, y = 66.2 }), "Tirisfal Glades 30.8, 66.2")
  eq(Text.Place({ zone = 130, x = 0, y = 0 }), "Silverpine Forest")
  eq(Text.Distance(119.6), "120 yd")
  eq(Text.Distance(4), "4 yd")
  eq(Text.StepTitle({ n = 7 }), "7")
  eq(Text.StepTitle({ n = 7, title = "Sarvis" }), "Sarvis")
  eq(line(Text, { kind = "accept", quest = 12345 }).text, "Accept Quest 12345")
end)

test("missing prerequisites show the error icon and list the quests", function()
  local c, Noir, Text = play()
  local l = { kind = "accept", quest = 364, npc = 1569, requires = { 363, 376 } }
  local t = line(Text, l)
  eq(t.icon, "error")
  eq(t.text, "Accept The Mindless Ones")
  eq(t.tooltip, { "Hand these in first:", "Rude Awakening", "The Damned" })
  c:markCompleted(363)
  t = line(Text, l)
  eq(t.tooltip, { "Hand these in first:", "The Damned" })
  c:markCompleted(376)
  t = line(Text, l)
  eq(t.icon, "accept")
  eq(t.tooltip, nil)
  -- The line is not skipped.
  eq((Noir.Lines.Check({ kind = "accept", quest = 365, requires = { 999 } }, { id = "s", lines = {} }, { since = c.now })), "todo")
end)

test("named things are marked by meaning", function()
  local c, _, Text = play()
  eq(spans(line(Text, { kind = "target", npc = 1765, enemy = true })), { "enemy:Worg" })
  eq(spans(line(Text, { kind = "target", npc = 1950 })), { "friend:Rane Yorick" })
  eq(spans(line(Text, { kind = "vendor", npc = 5688, buy = { item = 159, count = 5 } })),
    { "friend:Innkeeper Renee", "buy:Refreshing Spring Water" })
  eq(spans(line(Text, { kind = "collect", item = 2834, count = 4 })), { "loot:Embalming Ichor" })
  eq(spans(line(Text, { kind = "use", item = 2856 })), { "loot:Scavenger Paw" })
  eq(spans(line(Text, { kind = "train", class = "MAGE", level = 4, npc = 2124 })), { "friend:Isabella" })
  c:acceptQuest(364)
  c:acceptQuest(376)
  eq(spans(line(Text, { kind = "objective", quest = 364, index = 1 })), { "enemy:Mindless Zombie slain" })
  eq(spans(line(Text, { kind = "objective", quest = 376, index = 1 })), { "loot:Scavenger Paw" })
  eq(spans(line(Text, { kind = "accept", quest = 435, requires = { 999 } })), { "warning:Escorting Erland" })
  eq(spans(line(Text, { kind = "accept", quest = 435 })), {})
end)
