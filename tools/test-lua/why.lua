-- Noir Guides, GPLv3. See LICENSE.
-- Why v2: the log of every step the engine moved past without the player doing it in front of it, by section and
-- step id, and /noir why (plan task E4).
use("tools/test-lua/sample/helper.lua")

local DEATHKNELL = "undead-01-03-deathknell"

local function login(opts)
  local c = sample3(opts):login()
  return c, c.G.Noir.Why, c.G.Noir
end

local function entry(n, kind, text, step)
  return { section = DEATHKNELL, step = step or ("s" .. n), n = n, kind = kind or "jump", text = text or ("reason " .. n) }
end

test("a new character has an empty log and /noir why says so", function()
  local c, Why = login({ level = 2 })
  eq(Why.List(), {})
  c:takeChat()
  c:slash("/noir why")
  has(c:chatText(), "Nothing")
end)

test("an entry records the section, the step id, its number, the kind and the reason", function()
  local _, Why = login({ level = 2 })
  Why.Add({ section = DEATHKNELL, step = "a363", n = 1, kind = "done", text = "Rude Awakening is in your quest log",
    label = "Accept Rude Awakening" })
  local list = Why.List()
  eq(#list, 1)
  eq(list[1].section, DEATHKNELL)
  eq(list[1].step, "a363")
  eq(list[1].n, 1)
  eq(list[1].kind, "done")
  eq(list[1].text, "Rude Awakening is in your quest log")
  eq(list[1].label, "Accept Rude Awakening")
  eq(list[1].level, 2)
end)

test("an entry without a step is a note about the route as a whole", function()
  local c, Why = login({ level = 2 })
  Why.Add({ kind = "route", text = "the route changed to sections" })
  eq(Why.List()[1].n, nil)
  c:takeChat()
  c:slash("/noir why")
  has(c:chatText(), "the route changed to sections")
end)

test("ForStep returns the newest entry for a step", function()
  local _, Why = login({ level = 2 })
  eq(Why.ForStep(DEATHKNELL, "a363"), nil, "nothing logged yet")
  Why.Add(entry(1, "done", "first", "a363"))
  Why.Add(entry(2, "moot", "other step", "g.road"))
  Why.Add(entry(1, "jump", "newest", "a363"))
  Why.Add({ section = "undead-03-05-tirisfal-glades", step = "a363", n = 1, kind = "done", text = "another section" })
  eq(Why.ForStep(DEATHKNELL, "a363").text, "newest")
  eq(Why.ForStep(DEATHKNELL, "g.road").kind, "moot")
  eq(Why.ForStep("undead-03-05-tirisfal-glades", "a363").text, "another section", "steps are told apart by section")
  eq(Why.ForStep(DEATHKNELL, "t3901"), nil)
end)

test("every kind has its words", function()
  local _, Why = login({ level = 2 })
  local kinds = { "done", "moot", "cannot", "condition", "outleveled", "deferred", "tick", "jump", "place", "section", "route" }
  local seen = {}
  for _, kind in ipairs(kinds) do
    local words = Why.Words(kind)
    ok(type(words) == "string" and words ~= "" and words ~= kind, "words for " .. kind)
    no(seen[words], "each kind has its own words: " .. kind)
    seen[words] = true
  end
  local count = 0
  for _ in pairs(Why.KINDS) do count = count + 1 end
  eq(count, #kinds, "exactly the kinds of the plan")
  -- The words appear in /noir why.
  local c = login({ level = 2 })
  c.G.Noir.Why.Add(entry(4, "outleveled", "you are above level 5"))
  c:takeChat()
  c:slash("/noir why")
  has(c:chatText(), Why.Words("outleveled") .. ": you are above level 5")
end)

test("Describe labels a format 3 step by the words of its first line", function()
  local _, Why, Noir = login({ level = 2 })
  local step = Noir.Guide.Steps(DEATHKNELL)[1]
  eq(Why.Describe(step), "Accept " .. Noir.Text.QuestName(363))
  eq(Why.Describe(nil), "")
end)

test("every line kind has a label, with the data's names and without them", function()
  local _, Why = login({ level = 2 })
  local function step(line) return { id = "s", lines = { line } } end
  local cases = {
    { { kind = "accept", quest = 364 }, "Accept The Mindless Ones" },
    { { kind = "accept", quest = 99999 }, "Accept Quest 99999" },
    { { kind = "turnin", quest = 364 }, "Turn in The Mindless Ones" },
    { { kind = "turnin", quest = 99999 }, "Turn in Quest 99999" },
    { { kind = "objective", quest = 99999, index = 2 }, "Quest 99999: objective 2" },
    { { kind = "collect", item = 99998, count = 3 }, "Collect Item 99998" },
    { { kind = "getflight", node = 384 }, "Get the Brill, Tirisfal Glades flight point" },
    { { kind = "getflight", node = 77777 }, "Get the Flight point 77777 flight point" },
    { { kind = "fly", from = 384, to = 10 }, "Fly to The Sepulcher, Silverpine Forest" },
    { { kind = "fly", from = 384, to = 77777 }, "Fly to Flight point 77777" },
    { { kind = "transport", mode = "zeppelin", at = { zone = 85, x = 1, y = 1 }, to = { zone = 14, x = 1, y = 1 } }, "Take the zeppelin to Durotar" },
    { { kind = "transport", mode = "boat", at = { zone = 85, x = 1, y = 1 }, to = { zone = 4242, x = 1, y = 1 } }, "Take the boat to Zone 4242" },
    { { kind = "hearth", to = { zone = 85, x = 1, y = 1 } }, "Hearth to Tirisfal Glades" },
    { { kind = "grind", level = 12 }, "Grind to level 12" },
    { { kind = "vendor", npc = 99997 }, "Visit NPC 99997" },
    { { kind = "target", npc = 1765, enemy = true }, "Kill Worg" },
    { { kind = "target", npc = 99997 }, "Talk to NPC 99997" },
    { { kind = "note", text = "Mind the cliff." }, "Mind the cliff." },
  }
  for _, case in ipairs(cases) do
    local label = Why.Describe(step(case[1]))
    ok(label:sub(1, #case[2]) == case[2], case[1].kind .. ": " .. label)
  end
  eq(Why.Describe({ id = "only.hidden", lines = { { kind = "collect", item = 2834, count = 0 } } }), "only.hidden",
    "no shown line: the step id")
end)

test("/noir why prints the last 20 entries, oldest first, with section, step number, label and reason", function()
  local c, Why = login({ level = 2 })
  for i = 1, 25 do
    local e = entry(i)
    e.label = "label " .. i
    Why.Add(e)
  end
  c:takeChat()
  c:slash("/noir why")
  local lines = c:takeChat()
  eq(#lines, 21, "a heading and 20 entries")
  has(lines[1], "20")
  has(lines[1], "25")
  has(lines[2], DEATHKNELL .. " step 6")
  has(lines[2], "label 6")
  has(lines[2], "reason 6")
  has(lines[21], "step 25")
  has(lines[21], "reason 25")
  no(table.concat(lines, "\n"):find("reason 5", 1, true), "entry 5 is too old to be shown")
end)

test("the log keeps at most 100 entries and survives a relog as plain data", function()
  local c, Why = login({ level = 2 })
  for i = 1, 130 do Why.Add(entry(i)) end
  eq(#Why.List(), 100)
  eq(Why.List()[1].n, 31)
  local again = c:relog()
  local list = again.G.Noir.Why.List()
  eq(#list, 100)
  eq(list[100].text, "reason 130")
  eq(list[100].step, "s130")
  eq(again.G.Noir.Why.ForStep(DEATHKNELL, "s130").text, "reason 130")
end)

test("a damaged log in the saved variables is replaced, entry by entry or as a whole", function()
  local c = login({ level = 2 })
  c.G.Noir.char.why = { "junk", { kind = "jump", text = "kept", n = 2 }, { kind = 5 }, false,
    { kind = "done", text = "bad step", step = 7 } }
  local again = c:relog()
  local list = again.G.Noir.Why.List()
  eq(#list, 1)
  eq(list[1].text, "kept")
  again.G.Noir.char.why = "junk"
  local third = again:relog()
  eq(third.G.Noir.Why.List(), {})
  third.G.Noir.Why.Add(entry(1))
  eq(#third.G.Noir.Why.List(), 1)
end)

test("NOIR_WHY is fired for each new entry", function()
  local c, Why = login({ level = 2 })
  local seen = {}
  c.G.Noir.On("NOIR_WHY", function(_, e) seen[#seen + 1] = e.text end)
  Why.Add(entry(1, "jump", "first"))
  eq(seen, { "first" })
end)
