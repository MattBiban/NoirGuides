-- Noir Guides, GPLv3. See LICENSE.
-- The cases both format 3 validators are held to: Routes.Check in NoirGuides/Routes.lua (tools/test-lua/routes.lua)
-- and checkRoute3 in tools/planner/format3.js (tools/test/format3.test.js). Each case is a small route made from one
-- valid base by one change, the rule it is about (R1 to R12, "Rules" in "Route format 3" of the rebuild plan) and
-- the exact sentence both validators must give, or valid = true. Plain Lua: no addon and no client needed.
local cases = {}

local function place(zone, x, y, r)
  return { zone = zone, x = x, y = y, r = r }
end

-- Two sections chained by next, three steps.
local function base()
  return {
    format = 3, race = "Undead", faction = "Horde",
    sections = {
      {
        id = "undead-01-03-deathknell", name = "1-3 Deathknell", group = "Horde", subgroup = "1-20",
        minLevel = 1, maxLevel = 4, zone = 85, start = true,
        next = { { section = "undead-03-05-tirisfal-glades" } },
        steps = {
          { id = "a364", at = place(85, 30.84, 66.2, 10), lines = { { kind = "accept", quest = 364, npc = 1569 } } },
          { id = "t364", label = "turnin364", lines = { { kind = "turnin", quest = 364, npc = 1569 } } },
        },
      },
      {
        id = "undead-03-05-tirisfal-glades", name = "3-5 Tirisfal Glades", group = "Horde", subgroup = "1-20",
        minLevel = 3, maxLevel = 6, zone = 85, next = {},
        steps = {
          { id = "l5@85", at = place(85, 31, 64), lines = { { kind = "grind", level = 5 } } },
        },
      },
    },
  }
end

-- case(rule, name, edit, expect): edit(route) changes the base in place or returns a value to use instead.
local function case(rule, name, edit, expect)
  local route = base()
  if edit then
    local other = edit(route)
    if other ~= nil then route = other end
  end
  cases[#cases + 1] = { rule = rule, name = name, route = route, expect = expect, valid = (expect == nil) or nil }
end

local S1 = "section undead-01-03-deathknell"
local S2 = "section undead-03-05-tirisfal-glades"
local A = S1 .. " step a364"
local T = S1 .. " step t364"
local LONG = string.rep("a", 161)

local function first(r) return r.sections[1] end
local function second(r) return r.sections[2] end
local function step1(r) return r.sections[1].steps[1] end
local function step2(r) return r.sections[1].steps[2] end
local function line1(r) return r.sections[1].steps[1].lines[1] end
local function setLine(r, line) r.sections[1].steps[1].lines = { line } end

-- Valid files ------------------------------------------------------------------------------------------------------
case("R1", "the base route", nil, nil)
case("R3", "a single-level name", function(r) first(r).name = "7 Deathknell" end, nil)
case("R3", "a class's own name", function(r) first(r).names = { WARRIOR = "1-5 Deathknell" } end, nil)
case("R3", "a section at level 25 belongs to 20-30", function(r)
  first(r).minLevel, first(r).maxLevel, first(r).subgroup = 25, 30, "20-30"
end, nil)
case("R3", "maxLevel may be left out", function(r) first(r).maxLevel = nil end, nil)
case("R4", "a cycle through a loop section", function(r)
  second(r).loop = true
  second(r).next = { { section = "undead-01-03-deathknell" } }
end, nil)
case("R6", "a zone-only place and a pin without an arrow", function(r)
  step1(r).at = place(85, 0, 0, 0)
  step2(r).at = { zone = 85, x = 10, y = 10, nearest = true }
end, nil)
case("R7", "every line kind with its fields", function(r)
  step1(r).lines = {
    { kind = "accept", quest = 364, npc = 1569, manual = false, ifDone = 363, requires = { 363 } },
    { kind = "accept", quest = 365, object = 7, at = place(85, 1, 2) },
    { kind = "turnin", quest = 364, npc = 1569, reward = 2, skipIfMissing = true, skipIfIncomplete = true },
    { kind = "objective", quest = 364, index = 1, cap = 4, skipIfMissing = true, npc = 1501, item = 2 },
    { kind = "collect", item = 2856, count = 0, quest = 365 },
    { kind = "goto", at = place(85, 40, 40, 15) },
    { kind = "getflight", node = 384, npc = 4551 },
    { kind = "fly", from = 384, to = 10 },
    { kind = "transport", mode = "zeppelin", at = place(85, 60.7, 58.8), to = place(14, 50.8, 13.6) },
    { kind = "sethearth", npc = 5688 },
    { kind = "hearth", to = place(85, 61.7, 52) },
    { kind = "grind", level = 6, percent = 50 },
    { kind = "train", spell = 1752 },
    { kind = "train", skill = 186, rank = 2, npc = 3175 },
    { kind = "train", class = "ROGUE", level = 4, npc = 2122 },
    { kind = "vendor", npc = 5688, buy = { item = 159, count = 5 } },
    { kind = "use", item = 6948 },
    { kind = "target", npc = 1501, enemy = true },
    { kind = "note", text = "Stay on the road.", when = { class = "ROGUE" } },
    { kind = "manual", text = string.rep("b", 160) },
  }
end, nil)
case("R8", "texts at their longest", function(r)
  step1(r).text = string.rep("c", 160)
  step1(r).title = string.rep("d", 24)
end, nil)
case("R9", "conditions with lists and every key", function(r)
  step1(r).when = { class = { "ROGUE", "MAGE" }, notRace = "Orc", profession = 186 }
  first(r).when = { race = { "Undead" }, notClass = "PALADIN" }
end, nil)
case("R9", "every skip condition kind", function(r)
  step1(r).label = "start"
  step2(r).skip = {
    { kind = "onquest", quest = 1 }, { kind = "notonquest", quest = 1 }, { kind = "complete", quest = 1 },
    { kind = "notcomplete", quest = 1 }, { kind = "turnedin", quest = 1 }, { kind = "notturnedin", quest = 1, jump = "start" },
    { kind = "level", level = 5, percent = 20 }, { kind = "below", level = 4 }, { kind = "maxlevel", level = 9 },
    { kind = "skill", skill = 186, value = 50 }, { kind = "item", item = 2856, count = 3 }, { kind = "zone", zone = 85 },
    { kind = "bound", zone = 85 },
  }
end, nil)
case("R10", "labels, requires, reminders and load", function(r)
  step1(r).reminder = { ends = "turnin364" }
  step2(r).requires = "turnin364"
  step2(r).reminder = { ends = "next" }
  step2(r).load = "undead-03-05-tirisfal-glades"
end, nil)
case("R11", "a loop path", function(r)
  step1(r).path = { points = { { x = 1, y = 2 }, { x = 3, y = 4 } }, loop = true }
end, nil)
case("R12", "items and targets", function(r)
  step1(r).items = { 2856 }
  step1(r).targets = { enemy = { 1501 }, friend = { 1569 } }
end, nil)

-- R1 ---------------------------------------------------------------------------------------------------------------
case("R1", "format 2", function(r) r.format = 2 end, "it is in format 2 and this version of the addon reads format 3")
case("R1", "no format", function(r) r.format = nil end, "it is in format 1 and this version of the addon reads format 3")
case("R1", "not a table", function() return "a route" end, "the route data is not a table")
case("R1", "unknown race", function(r) r.race = "Murloc" end, 'unknown race "Murloc"')
case("R1", "no race", function(r) r.race = nil end, "race must be a race name")
case("R1", "a race of the other faction", function(r) r.race = "Human" end, 'race "Human" is not of faction "Horde"')
case("R1", "unknown faction", function(r) r.faction = "Neutral" end, 'unknown faction "Neutral"')

-- R2 ---------------------------------------------------------------------------------------------------------------
case("R2", "no sections", function(r) r.sections = {} end, "sections must be a list of at least one section")
case("R2", "no start", function(r) first(r).start = nil end, "it has 0 start sections; exactly one must have start = true")
case("R2", "two starts", function(r) second(r).start = true end, "it has 2 start sections; exactly one must have start = true")
case("R2", "start that is not true", function(r) first(r).start = false end,
  "it has 0 start sections; exactly one must have start = true; " .. S1 .. " start must be true or left out")
case("R2", "a malformed section id", function(r)
  second(r).id = "Bad_ID"
  first(r).next = { { section = "Bad_ID" } }
end, "section Bad_ID id must be made of a-z, 0-9 and -")
case("R2", "a section id used twice", function(r)
  second(r).id = "undead-01-03-deathknell"
  first(r).next = {}
end, S1 .. " id is used twice")
case("R2", "a section that is not a table", function(r)
  r.sections[2] = "x"
  first(r).next = {}
end, "section #2 is not a table")
case("R2", "a section without id", function(r)
  second(r).id = nil
  first(r).next = {}
end, "section #2 id must be made of a-z, 0-9 and -")

-- R3 ---------------------------------------------------------------------------------------------------------------
case("R3", "a name without levels", function(r) first(r).name = "Deathknell" end, S1 .. ' name must look like "1-6 Zone" or "6 Zone"')
case("R3", "names for an unknown class", function(r) first(r).names = { BARD = "1-2 Lute" } end,
  S1 .. ' names has the key "BARD", which is not a class token')
case("R3", "a class name without levels", function(r) first(r).names = { ROGUE = "Deathknell" } end,
  S1 .. ' names.ROGUE must look like "1-6 Zone" or "6 Zone"')
case("R3", "an unknown group", function(r) first(r).group = "Dungeons" end, S1 .. ' group must be "Alliance" or "Horde"')
case("R3", "a subgroup that does not fit minLevel", function(r) first(r).subgroup = "20-30" end, S1 .. ' subgroup must be "1-20"')
case("R3", "minLevel 0", function(r) first(r).minLevel = 0 end, S1 .. " minLevel must be a whole number from 1 to 60")
case("R3", "maxLevel 61", function(r) first(r).maxLevel = 61 end, S1 .. " maxLevel must be a whole number from 1 to 60")
case("R3", "minLevel above maxLevel", function(r) first(r).minLevel = 5 end, S1 .. " minLevel is above maxLevel")
case("R3", "zone not whole", function(r) first(r).zone = 85.5 end, S1 .. " zone must be a positive whole number")
case("R3", "loop that is not true", function(r) first(r).loop = 1 end, S1 .. " loop must be true or left out")
case("R3", "noAuto with a name", function(r) first(r).noAuto = { "x" } end, S1 .. " noAuto must be a list of positive whole numbers")

-- R4 ---------------------------------------------------------------------------------------------------------------
case("R4", "next to a missing section", function(r) first(r).next = { { section = "nowhere" } } end,
  S1 .. ' next 1 names the missing section "nowhere"')
case("R4", "next without section", function(r) first(r).next = { { when = { class = "HUNTER" } } } end, S1 .. " next 1 needs section")
case("R4", "next that is not a list", function(r) first(r).next = "undead-03-05-tirisfal-glades" end, S1 .. " next must be a list")
case("R4", "a cycle of two sections", function(r) second(r).next = { { section = "undead-01-03-deathknell" } } end,
  S1 .. " next leads back to this section and no section on the way has loop; "
  .. S2 .. " next leads back to this section and no section on the way has loop")
case("R4", "a section that leads to itself", function(r) second(r).next = { { section = "undead-03-05-tirisfal-glades" } } end,
  S2 .. " next leads back to this section and no section on the way has loop")

-- R5 ---------------------------------------------------------------------------------------------------------------
case("R5", "no steps", function(r) second(r).steps = {} end, S2 .. " steps must hold 1 to 400 steps")
case("R5", "401 steps", function(r)
  local steps = {}
  for i = 1, 401 do steps[i] = { id = "g" .. i, lines = { { kind = "grind", level = 5 } } } end
  second(r).steps = steps
end, S2 .. " steps must hold 1 to 400 steps")
case("R5", "a step id used twice", function(r) step2(r).id = "a364" end, A .. " id is used twice")
case("R5", "a malformed step id", function(r) step1(r).id = "a 364" end, S1 .. " step a 364 id must be made of letters, digits and . - + @ # :")
case("R5", "a step without id", function(r) step1(r).id = nil end, S1 .. " step #1 id must be made of letters, digits and . - + @ # :")
case("R5", "a step that is not a table", function(r) first(r).steps[2] = 5 end, S1 .. " step #2 is not a table")

-- R6 ---------------------------------------------------------------------------------------------------------------
case("R6", "x above 100", function(r) step1(r).at.x = 101 end, A .. " at is not a valid place")
case("R6", "a radius above 500", function(r) step1(r).at.r = 600 end, A .. " at is not a valid place")
case("R6", "a negative radius", function(r) step1(r).at.r = -1 end, A .. " at is not a valid place")
case("R6", "zone 0", function(r) step1(r).at.zone = 0 end, A .. " at is not a valid place")
case("R6", "nearest that is not true", function(r) step1(r).at.nearest = false end, A .. " at is not a valid place")
case("R6", "a line's place without y", function(r) line1(r).at = { zone = 85, x = 5 } end, A .. " line 1 at is not a valid place")
case("R6", "a transport to a zone without coordinates", function(r)
  setLine(r, { kind = "transport", mode = "zeppelin", at = place(85, 60.7, 58.8), to = { zone = 14 } })
end, A .. " line 1 to is not a valid place")

-- R7 ---------------------------------------------------------------------------------------------------------------
case("R7", "an unknown line kind", function(r) setLine(r, { kind = "dance" }) end, A .. ' line 1 has the unknown kind "dance"')
case("R7", "a line without kind", function(r) setLine(r, { quest = 364 }) end, A .. " line 1 needs a kind")
case("R7", "a line that is not a table", function(r) setLine(r, "accept 364") end, A .. " line 1 is not a table")
case("R7", "accept without quest", function(r) setLine(r, { kind = "accept", npc = 1569 }) end, A .. " line 1 accept needs quest")
case("R7", "a quest as a string", function(r) line1(r).quest = "364" end, A .. " line 1 quest must be a positive whole number")
case("R7", "an unknown key on a line", function(r) line1(r).verified = false end, A .. ' line 1 has the unknown key "verified"')
case("R7", "an unknown key on a step", function(r) step1(r).foo = 1 end, A .. ' has the unknown key "foo"')
case("R7", "the old action key on a step", function(r) step1(r).action = "accept" end, A .. ' has the unknown key "action"')
case("R7", "no lines", function(r) step1(r).lines = {} end, A .. " lines must hold at least one line")
case("R7", "an unknown transport mode", function(r)
  setLine(r, { kind = "transport", mode = "rocket", at = place(85, 60.7, 58.8), to = place(14, 50.8, 13.6) })
end, A .. " line 1 mode must be one of zeppelin, boat, tram, portal")
case("R7", "objective without index", function(r) setLine(r, { kind = "objective", quest = 364 }) end, A .. " line 1 objective needs index")
case("R7", "train with a skill and no rank", function(r) setLine(r, { kind = "train", skill = 186 }) end,
  A .. " line 1 train needs spell, skill and rank, or class and level")
case("R7", "train for an unknown class", function(r) setLine(r, { kind = "train", class = "BARD", level = 4 }) end,
  A .. " line 1 class must be a class token")
case("R7", "grind to level 1", function(r) setLine(r, { kind = "grind", level = 1 }) end, A .. " line 1 level must be a whole number from 2 to 60")
case("R7", "collect more than 1000", function(r) setLine(r, { kind = "collect", item = 2856, count = 1001 }) end,
  A .. " line 1 count must be a whole number from 0 to 1000")
case("R7", "buy without count", function(r) setLine(r, { kind = "vendor", npc = 5688, buy = { item = 159 } }) end,
  A .. " line 1 buy must be { item, count } with positive whole numbers")
case("R7", "reward 7", function(r) setLine(r, { kind = "turnin", quest = 364, reward = 7 }) end, A .. " line 1 reward must be a whole number from 1 to 6")
case("R7", "manual as a word", function(r) line1(r).manual = "yes" end, A .. " line 1 manual must be true or false")
case("R7", "an npc on a goto line", function(r) setLine(r, { kind = "goto", at = place(85, 1, 1, 5), npc = 5 }) end,
  A .. ' line 1 has the unknown key "npc"')
case("R7", "requires with a name", function(r) line1(r).requires = { 363, "x" } end, A .. " line 1 requires must be a list of positive whole numbers")
case("R7", "fly with neither end", function(r) setLine(r, { kind = "fly" }) end, A .. " line 1 fly needs from; " .. A .. " line 1 fly needs to")
case("R7", "grind percent of 100", function(r) setLine(r, { kind = "grind", level = 5, percent = 100 }) end,
  A .. " line 1 percent must be a number from 0 to 99")

-- R8 ---------------------------------------------------------------------------------------------------------------
case("R8", "a step text of 161 characters", function(r) step1(r).text = LONG end, A .. " text is longer than 160 characters")
case("R8", "a title of 25 characters", function(r) step1(r).title = string.rep("t", 25) end, A .. " title is longer than 24 characters")
case("R8", "a note of 161 characters", function(r) setLine(r, { kind = "note", text = LONG }) end, A .. " line 1 text is longer than 160 characters")
case("R8", "a manual line of 161 characters", function(r) setLine(r, { kind = "manual", text = LONG }) end, A .. " line 1 text is longer than 160 characters")
case("R8", "a text that is not a string", function(r) step1(r).text = 5 end, A .. " text must be a string")

-- R9 ---------------------------------------------------------------------------------------------------------------
case("R9", "an unknown class", function(r) step1(r).when = { class = "BARD" } end, A .. ' when.class "BARD" is not a class token')
case("R9", "a class token in lower case", function(r) step1(r).when = { class = "rogue" } end, A .. ' when.class "rogue" is not a class token')
case("R9", "the old level condition", function(r) step1(r).when = { level = 10 } end, A .. ' when has the unknown key "level"')
case("R9", "an unknown race", function(r) step1(r).when = { race = "Murloc" } end, A .. ' when.race "Murloc" is not a race')
case("R9", "a condition that is not a table", function(r) step1(r).when = "ROGUE" end, A .. " when must be a table")
case("R9", "an empty class list", function(r) step1(r).when = { class = {} } end, A .. " when.class must not be an empty list")
case("R9", "a class as a number", function(r) step1(r).when = { class = 5 } end, A .. " when.class must be a class token or a list of them")
case("R9", "a profession by name", function(r) step1(r).when = { profession = "Mining" } end, A .. " when.profession must be a positive whole number")
case("R9", "a section condition", function(r) first(r).when = { notClass = "BARD" } end, S1 .. ' when.notClass "BARD" is not a class token')
case("R9", "a line condition", function(r) line1(r).when = { race = 3 } end, A .. " line 1 when.race must be a race or a list of them")
case("R9", "a next condition", function(r) first(r).next[1].when = { class = "BARD" } end, S1 .. ' next 1 when.class "BARD" is not a class token')
case("R9", "an unknown skip kind", function(r) step1(r).skip = { { kind = "maybe" } } end, A .. ' skip 1 has the unknown kind "maybe"')
case("R9", "a skip condition without its field", function(r) step1(r).skip = { { kind = "onquest" } } end, A .. " skip 1 onquest needs quest")
case("R9", "a skip condition with an unknown key", function(r) step1(r).skip = { { kind = "zone", zone = 85, x = 1 } } end,
  A .. ' skip 1 has the unknown key "x"')
case("R9", "skip that is not a list", function(r) step1(r).skip = { kind = "zone", zone = 85 } end, A .. " skip must be a list of skip conditions")

-- R10 --------------------------------------------------------------------------------------------------------------
case("R10", "a label used twice", function(r) step1(r).label = "turnin364" end, T .. " label is used twice")
case("R10", "a malformed label", function(r) step2(r).label = "turn-in" end, T .. " label must be made of letters, digits and _")
case("R10", "requires a missing label", function(r) step2(r).requires = "nope" end, T .. ' requires names the missing label "nope"')
case("R10", "a reminder ending at a missing label", function(r) step1(r).reminder = { ends = "nope" } end,
  A .. ' reminder ends at the missing label "nope"')
case("R10", "a reminder ending at an earlier step", function(r)
  step1(r).label = "first"
  step2(r).reminder = { ends = "first" }
end, T .. ' reminder ends at "first", which is not a later step')
case("R10", "a reminder ending at its own step", function(r) step2(r).reminder = { ends = "turnin364" } end,
  T .. ' reminder ends at "turnin364", which is not a later step')
case("R10", "a reminder without ends", function(r) step1(r).reminder = {} end, A .. ' reminder must be { ends = "next" or a label }')
case("R10", "a jump to a missing label", function(r) step1(r).skip = { { kind = "turnedin", quest = 364, jump = "nope" } } end,
  A .. ' skip 1 jump names the missing label "nope"')
case("R10", "load of a missing section", function(r) step1(r).load = "nope" end, A .. ' load names the missing section "nope"')

-- R11 --------------------------------------------------------------------------------------------------------------
case("R11", "a path without at", function(r) step2(r).path = { points = { { x = 1, y = 2 } } } end, T .. " path needs at")
case("R11", "a path point off the map", function(r) step1(r).path = { points = { { x = 101, y = 2 } } } end,
  A .. " path must have points { x, y } from 0 to 100")
case("R11", "a path loop that is not true", function(r) step1(r).path = { points = { { x = 1, y = 2 } }, loop = 1 } end,
  A .. " path loop must be true or left out")

-- R12 --------------------------------------------------------------------------------------------------------------
case("R12", "item 0", function(r) step1(r).items = { 0 } end, A .. " items must be a list of positive whole numbers")
case("R12", "a target by name", function(r) step1(r).targets = { enemy = { "Zombie" } } end, A .. " targets.enemy must be a list of positive whole numbers")
case("R12", "an unknown target group", function(r) step1(r).targets = { ally = { 1 } } end, A .. ' targets has the unknown key "ally"')
case("R12", "targets as a number", function(r) step1(r).targets = 5 end, A .. " targets must be { enemy = { ... }, friend = { ... } }")

-- The message ------------------------------------------------------------------------------------------------------
case("R7", "three problems are all named", function(r)
  step1(r).a, step1(r).b, step1(r).c = 1, 2, 3
end, A .. ' has the unknown key "a"; ' .. A .. ' has the unknown key "b"; ' .. A .. ' has the unknown key "c"')
case("R7", "five problems: three named and the rest counted", function(r)
  step1(r).a, step1(r).b, step1(r).c, step1(r).d, step1(r).e = 1, 2, 3, 4, 5
end, A .. ' has the unknown key "a"; ' .. A .. ' has the unknown key "b"; ' .. A .. ' has the unknown key "c"; and 2 more')

return cases
