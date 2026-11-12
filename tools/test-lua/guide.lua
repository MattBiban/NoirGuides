-- Noir Guides, GPLv3. See LICENSE.
-- Guide: the section registry, the automatic choice of a section, the next section and the saved state per
-- character (plan task E2, spec 2.1 to 2.6). Driven by game events and logins only: nothing here types a command.
use("tools/test-lua/sample/helper.lua")

local DEATHKNELL = "undead-01-03-deathknell"
local TIRISFAL = "undead-03-05-tirisfal-glades"
local SILVERPINE = "undead-05-06-silverpine-forest"
local NORTHSHIRE = "human-01-05-northshire"
local GUID = "Player-4444-0000002A" -- what the mock's UnitGUID("player") returns
local KEY = "Tester-Mock"           -- the mock character's saved-variables key

-- Saved variables for the mock character, schema 2, with `char` merged into NoirGuidesCharDB.
local function savedWith(char)
  local db = { schema = 2, owner = GUID }
  for k, v in pairs(char or {}) do db[k] = v end
  return { account = {}, characters = { [KEY] = { NoirGuidesCharDB = db } } }
end

-- A logged-in client with the v3 samples; returns the client and Noir.
local function play(opts)
  local c = sample3(opts):login()
  return c, c.G.Noir
end

-- Records every NOIR_SECTION as "id how previous".
local function recordSections(c)
  local seen = {}
  c.G.Noir.On("NOIR_SECTION", function(_, id, how, previous)
    seen[#seen + 1] = tostring(id) .. " " .. tostring(how) .. " " .. tostring(previous)
  end)
  return seen
end

local function ids(sections)
  local out = {}
  for i, s in ipairs(sections) do out[i] = s.id end
  return out
end

test("When: and across keys, or inside lists, not keys exclude, profession learned or planned", function()
  local c, Noir = play({ race = "Undead", class = "MAGE" })
  local When = Noir.Guide.When
  eq(When(nil), true, "no condition holds")
  eq(When({}), true, "an empty condition holds")
  eq(When({ class = "MAGE" }), true)
  eq(When({ class = "ROGUE" }), false)
  eq(When({ class = { "ROGUE", "MAGE" } }), true, "a list means any of them")
  eq(When({ class = "MAGE", race = "Undead" }), true, "both keys hold")
  eq(When({ class = "MAGE", race = "Orc" }), false, "every key given must hold")
  eq(When({ race = { "Orc", "Troll" } }), false)
  eq(When({ notClass = "MAGE" }), false, "notClass excludes")
  eq(When({ notClass = { "ROGUE", "WARRIOR" } }), true)
  eq(When({ notRace = { "Orc", "Undead" } }), false, "notRace excludes")
  eq(When({ class = "MAGE", notRace = "Orc" }), true)
  eq(When({ profession = 186 }), false, "a profession neither learned nor planned")
  c:setProfession(186, "Mining", 1, 75)
  eq(When({ profession = 186 }), true, "a learned profession")
  eq(When({ profession = 171 }), false)
  local planned = {}
  Noir.Professions.IsPlanned = function(skill) return planned[skill] == true end -- looked up when called
  planned[171] = true
  eq(When({ profession = 171 }), true, "a planned profession")
  eq(When({ profession = 171, class = "ROGUE" }), false, "and across keys, profession included")
  eq(Noir.Guide.Steps(TIRISFAL)[1].n, 1, "steps keep n")
  local tirisfal = {}
  for _, step in ipairs(Noir.Guide.Steps(TIRISFAL)) do tirisfal[step.id] = step.n end
  ok(tirisfal["train.spell"], "the mage's trainer step applies to a mage")
  ok(tirisfal["train.mining"], "the mining step applies to a miner")
  local deathknell = {}
  for _, step in ipairs(Noir.Guide.Steps(DEATHKNELL)) do deathknell[step.id] = step.n end
  no(deathknell["a8.train"], "the rogue's step does not exist for a mage")
  eq(deathknell["l3@85"], 10, "the step after the rogue's keeps its position in the file")
  eq(c:offScreen(), {})
end)

test("a section is found by its padded and unpadded ID", function()
  local _, Noir = play()
  local Guide = Noir.Guide
  eq(Guide.Section(DEATHKNELL).id, DEATHKNELL)
  eq(Guide.Section("undead-1-3-deathknell").id, DEATHKNELL, "unpadded levels")
  eq(Guide.Section("undead-3-5-tirisfal-glades").id, TIRISFAL)
  eq(Guide.Section("undead-05-6-silverpine-forest").id, SILVERPINE, "half padded")
  eq(Guide.Section(NORTHSHIRE).id, NORTHSHIRE, "another race's file")
  eq(Guide.Section("human-1-5-northshire").id, NORTHSHIRE)
  eq(Guide.Section("undead-01-03-nowhere"), nil)
  eq(Guide.Section(nil), nil)
  eq(Guide.Section(12), nil)
  ok(Guide.Select("undead-3-5-tirisfal-glades", "hand"), "Select takes the unpadded form")
  eq(Guide.Current(), TIRISFAL, "and saves the padded one")
end)

test("a level 1 Undead gets the start section without any command", function()
  local c, Noir = play({ race = "Undead", class = "WARRIOR", level = 1 })
  eq(Noir.Guide.Current(), DEATHKNELL)
  eq(Noir.char.guide.section, DEATHKNELL)
  eq(Noir.char.guide.how, "auto")
  eq(c:slashCount(), 0, "no command was typed")
  eq(c:offScreen(), {})
end)

test("a level 4 Undead with nothing saved gets the section whose range contains 4", function()
  -- In Undercity no section is named after the zone: the first section along the chain whose range holds 4.
  local _, Noir = play({ race = "Undead", class = "MAGE", level = 4, zone = 1497, x = 50, y = 50 })
  eq(Noir.Guide.Current(), DEATHKNELL)
  eq(Noir.char.guide.how, "auto")
  eq(Noir.Guide.ForLevel(4), DEATHKNELL)
  eq(Noir.Guide.ForLevel(5), TIRISFAL, "Deathknell ends at 4")
  eq(Noir.Guide.ForLevel(7), SILVERPINE)
  -- Level 6 is past Deathknell's range: the chain's next section that holds it.
  local _, again = play({ race = "Undead", class = "MAGE", level = 6, zone = 1497, x = 50, y = 50 })
  eq(again.Guide.Current(), TIRISFAL)
end)

test("evidence from the quest log decides the section above level 1", function()
  local asked
  local _, Noir = play({ race = "Undead", class = "MAGE", level = 4, zone = 1497, x = 50, y = 50,
    afterLoad = function(client)
      client.G.Noir.Progress.Locate = function(chain)
        asked = chain
        return SILVERPINE, 3, 8, 0
      end
    end })
  eq(asked, { DEATHKNELL, TIRISFAL, SILVERPINE }, "placement searches the character's chain from the start")
  eq(Noir.Guide.Current(), SILVERPINE)
  local _, none = play({ race = "Undead", class = "MAGE", level = 4, zone = 1497, x = 50, y = 50,
    afterLoad = function(client)
      client.G.Noir.Progress.Locate = function() return DEATHKNELL, 1, 0, 0 end
    end })
  eq(none.Guide.Current(), DEATHKNELL, "score 0 is no evidence: the level decides")
end)

test("the recommendation prefers a section named after the current zone", function()
  -- Level 3 lies in Deathknell (1-4) and Tirisfal (3-6); the chain alone would give Deathknell.
  local _, Noir = play({ race = "Undead", class = "MAGE", level = 3, zone = 85, x = 50, y = 50 })
  eq(Noir.Guide.Current(), TIRISFAL, "the zone's name picks Tirisfal Glades")
  -- A subzone is more precise than the zone around it.
  local c2 = sample3({ race = "Undead", class = "MAGE", level = 3, zone = 85, x = 50, y = 50 })
  c2:loadAddon()
  c2:moveTo({ zone = 85, x = 30, y = 70, subZone = "Deathknell" })
  c2:login()
  eq(c2.G.Noir.Guide.Current(), DEATHKNELL, "the subzone's name picks Deathknell")
  -- The section already loaded comes first.
  ok(Noir.Guide.Select(SILVERPINE, "hand"))
  eq(Noir.Guide.Recommend(), SILVERPINE, "the loaded section")
  -- Only sections whose range holds the level count for the zone rule.
  local _, low = play({ race = "Undead", class = "MAGE", level = 1, zone = 85, x = 50, y = 50 })
  eq(low.Guide.Current(), DEATHKNELL, "Tirisfal starts at 3")
end)

test("a saved section is kept at the next login", function()
  local c, Noir = play({ race = "Undead", class = "MAGE", level = 1 })
  ok(Noir.Guide.Select(TIRISFAL, "hand"))
  local again = c:relog()
  eq(again.G.Noir.Guide.Current(), TIRISFAL)
  eq(again.G.Noir.char.guide.how, "hand", "how it was chosen is kept too")
  local third = again:relog({ reload = true })
  eq(third.G.Noir.Guide.Current(), TIRISFAL, "and over a reload")
end)

test("a saved section the character has outleveled is kept at login", function()
  local _, Noir = play({ race = "Undead", class = "MAGE", level = 12,
    saved = savedWith({ guide = { section = DEATHKNELL, how = "auto" } }) })
  eq(Noir.Options.Get("outlevel"), true)
  no(Noir.Guide.Offered(Noir.Guide.Section(DEATHKNELL)), "Deathknell is not offered at 12")
  ok(Noir.Guide.Applies(Noir.Guide.Section(DEATHKNELL)), "but it still applies")
  eq(Noir.Guide.Current(), DEATHKNELL, "outleveling never switches the section in the background")
end)

test("Next follows the conditional link for a hunter and the plain link for a mage", function()
  local c, Noir = play({ race = "Undead", class = "HUNTER", level = 1 })
  local seen = recordSections(c)
  eq(Noir.Guide.Current(), DEATHKNELL)
  eq(Noir.Guide.Next(), SILVERPINE, "hunters go straight to Silverpine")
  eq(Noir.Guide.Current(), SILVERPINE)
  eq(Noir.char.guide.how, "next")
  eq(seen, { SILVERPINE .. " next " .. DEATHKNELL })
  eq(Noir.Guide.Chain(DEATHKNELL), { DEATHKNELL, SILVERPINE })
  no(Noir.Guide.IsDefault(Noir.Guide.Section(TIRISFAL)), "Tirisfal is not on a hunter's chain")
  local _, mage = play({ race = "Undead", class = "MAGE", level = 1 })
  eq(mage.Guide.Next(), TIRISFAL, "a mage takes the plain link")
  eq(mage.Guide.Next(), SILVERPINE)
  eq(mage.Guide.Chain(DEATHKNELL), { DEATHKNELL, TIRISFAL, SILVERPINE })
  ok(mage.Guide.IsDefault(mage.Guide.Section(TIRISFAL)))
end)

test("Next skips an outleveled section through its own next list when outlevel is on, and not when it is off", function()
  local _, Noir = play({ race = "Undead", class = "MAGE", level = 7,
    saved = savedWith({ guide = { section = DEATHKNELL, how = "hand" } }) })
  eq(Noir.Guide.Current(), DEATHKNELL)
  eq(Noir.Guide.Next(), SILVERPINE, "Tirisfal ends at 6: its own next is taken")
  local _, off = play({ race = "Undead", class = "MAGE", level = 7,
    saved = savedWith({ guide = { section = DEATHKNELL, how = "hand" } }) })
  ok(off.Options.Set("outlevel", false))
  ok(off.Guide.Offered(off.Guide.Section(TIRISFAL)), "with outlevel off an outleveled section is offered")
  eq(off.Guide.Next(), TIRISFAL)
end)

test("the last section ends with NOIR_ROUTE_DONE", function()
  local c, Noir = play({ race = "Undead", class = "MAGE", level = 5,
    saved = savedWith({ guide = { section = SILVERPINE, how = "next" } }) })
  local done, sections = {}, recordSections(c)
  Noir.On("NOIR_ROUTE_DONE", function(_, id) done[#done + 1] = tostring(id) end)
  eq(Noir.Guide.Next(), nil)
  eq(done, { SILVERPINE })
  eq(sections, {}, "no section was loaded")
  eq(Noir.Guide.Current(), SILVERPINE, "the window stays on the last section")
end)

test("List groups and orders sections and marks other races' sections only when the setting is on", function()
  local _, Noir = play({ race = "Undead", class = "HUNTER", level = 1 })
  local list = Noir.Guide.List()
  eq(#list, 1, "one group: the Horde route")
  eq(list[1].group, "Horde")
  eq(#list[1].subgroups, 1)
  eq(list[1].subgroups[1].name, "1-20")
  eq(ids(list[1].subgroups[1].sections), { DEATHKNELL, SILVERPINE }, "a hunter's sections in level order")
  ok(Noir.Options.Set("otherSections", true))
  local all = Noir.Guide.List()
  eq(#all, 2)
  eq(all[1].group, "Horde", "the main route first")
  eq(all[2].group, "Other races and classes")
  local other = {}
  for _, sub in ipairs(all[2].subgroups) do
    for _, s in ipairs(sub.sections) do other[#other + 1] = s.id end
  end
  eq(other, { NORTHSHIRE, TIRISFAL }, "another race's section and a section off the hunter's chain, in level order")
  eq(#Noir.Guide.List(false), 1, "List(false) leaves them out whatever the setting")
  -- A level 7 hunter: Deathknell (up to 4) is not offered while outlevel is on.
  local _, high = play({ race = "Undead", class = "HUNTER", level = 7 })
  eq(ids(high.Guide.List()[1].subgroups[1].sections), { SILVERPINE })
  eq(high.Guide.Name(high.Guide.Section(SILVERPINE)), "5-6 Silverpine Forest")
end)

test("Name gives the class's own name when the section has one", function()
  local c, Noir = play({ race = "Undead", class = "WARRIOR", level = 1 })
  local section = Noir.Guide.Section(DEATHKNELL)
  eq(Noir.Guide.Name(section), "1-3 Deathknell")
  section.names = { WARRIOR = "1-2 Deathknell" }
  eq(Noir.Guide.Name(section), "1-2 Deathknell")
  section.names = nil
  eq(c:offScreen(), {})
end)

test("a section that no longer exists is replaced and the why-log says so", function()
  local c, Noir = play({ race = "Undead", class = "MAGE", level = 1,
    saved = savedWith({ guide = { section = "undead-01-04-gone", how = "auto" } }) })
  eq(Noir.Guide.Current(), DEATHKNELL)
  local list = Noir.Why.List()
  local last = list[#list]
  eq(last.kind, "section")
  has(last.text, "undead-01-04-gone")
  -- A saved section of another race's file does not apply to this character: it is replaced in the same way.
  local _, other = play({ race = "Undead", class = "MAGE", level = 1,
    saved = savedWith({ guide = { section = NORTHSHIRE, how = "auto" } }) })
  eq(other.Guide.Current(), DEATHKNELL)
  eq(other.Why.List()[#other.Why.List()].kind, "section")
  eq(c:offScreen(), {})
end)

test("a recreated character at level 1 is asked, and yes starts fresh", function()
  local asked = {}
  local function confirmer(answer)
    return function(client)
      client.G.Noir.Panel.Confirm = function(text, onYes, onNo)
        asked[#asked + 1] = text
        if answer then onYes() else onNo() end
      end
    end
  end
  local old = "Player-4444-00000001"
  local saved = savedWith({ owner = old, guide = { section = TIRISFAL, how = "hand", places = { [TIRISFAL] = { step = "a367", n = 5 } } },
    why = { { kind = "jump", text = "an old entry" } } })
  local _, Noir = play({ race = "Undead", class = "MAGE", level = 1, saved = saved, afterLoad = confirmer(true) })
  eq(asked, { "This character's saved guide belongs to an earlier character of the same name. Start fresh?" })
  eq(Noir.char.owner, GUID)
  eq(Noir.Guide.Current(), DEATHKNELL, "fresh: the recommendation for level 1")
  eq(Noir.char.guide.how, "auto")
  eq(Noir.char.guide.places[TIRISFAL], nil, "the old places are gone")
  eq(Noir.char.guide.places[DEATHKNELL].step, "a363", "only the fresh section has a place: its first step")
  eq(#Noir.Why.List(), 0, "the old why-log is gone")
  -- No keeps everything and takes the new owner, so the question is not asked again.
  asked = {}
  local c2, kept = play({ race = "Undead", class = "MAGE", level = 1, saved = copy(saved), afterLoad = confirmer(false) })
  eq(#asked, 1)
  eq(kept.char.owner, GUID)
  eq(kept.Guide.Current(), TIRISFAL)
  eq(kept.char.guide.places[TIRISFAL].step, "a367")
  eq(kept.Why.List()[1].text, "an old entry")
  asked = {}
  c2:relog()
  eq(asked, {}, "asked once")
  -- Above level 1 nobody is asked.
  asked = {}
  local _, high = play({ race = "Undead", class = "MAGE", level = 2, saved = copy(saved), afterLoad = confirmer(true) })
  eq(asked, {})
  eq(high.Guide.Current(), TIRISFAL)
end)

test("Select fires NOIR_SECTION with how and the previous section", function()
  local c, Noir = play({ race = "Undead", class = "MAGE", level = 1 })
  local seen = recordSections(c)
  ok(Noir.Guide.Select(TIRISFAL, "wizard"))
  ok(Noir.Guide.Select(SILVERPINE, "step"))
  eq(seen, { TIRISFAL .. " wizard " .. DEATHKNELL, SILVERPINE .. " step " .. TIRISFAL })
  eq(Noir.char.guide.section, SILVERPINE)
  eq(Noir.char.guide.how, "step")
  no(Noir.Guide.Select("undead-09-09-nowhere", "hand"), "an unknown section")
  no(Noir.Guide.Select(NORTHSHIRE, "wizard"), "another race's section does not apply")
  no(Noir.Guide.Select(TIRISFAL, "sideways"), "an unknown how")
  eq(#seen, 2, "nothing fired for a refused choice")
  ok(Noir.Guide.Select(NORTHSHIRE, "hand"), "by hand any registered section")
  eq(seen[3], NORTHSHIRE .. " hand " .. SILVERPINE)
  eq(c:offScreen(), {})
end)

test("the first login fires NOIR_SECTION once for the automatic choice and a later login for the kept one", function()
  local fired = {}
  local function listen(client)
    client.G.Noir.On("NOIR_SECTION", function(_, id, how, previous)
      fired[#fired + 1] = tostring(id) .. " " .. tostring(how) .. " " .. tostring(previous)
    end)
  end
  local c = sample3({ race = "Undead", class = "MAGE", level = 1, afterLoad = listen }):login()
  eq(fired, { DEATHKNELL .. " auto nil" })
  fired = {}
  c:relog()
  eq(fired, { DEATHKNELL .. " auto " .. DEATHKNELL }, "the kept section loads again, unchanged")
end)
