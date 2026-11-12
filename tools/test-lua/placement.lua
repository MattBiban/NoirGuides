-- Noir Guides, GPLv3. See LICENSE.
-- Placement (plan task E4, spec 2.5): a character that joins the route mid-way, or whose saved place is behind its
-- quest log, is placed from its quest history with no command. Scoring (kept from 0.1.1/0.1.2): a quest in the log
-- +4, handed in +2, missing -1, one count per quest at its first line, unknown flight points 0; the place is just
-- after the highest score, latest on ties. Content the character outlevels is not counted as missing.
use("tools/test-lua/sample/helper.lua")

local DEATHKNELL = "undead-01-03-deathknell"
local TIRISFAL = "undead-03-05-tirisfal-glades"
local SILVERPINE = "undead-05-06-silverpine-forest"
local GUID = "Player-4444-0000002A"
local KEY = "Tester-Mock"

local function savedAt(section, stepId)
  local db = { schema = 2, owner = GUID, guide = { section = section, how = "auto", places = { [section] = { step = stepId } } } }
  return { account = {}, characters = { [KEY] = { NoirGuidesCharDB = db } } }
end

local function place(P)
  local section, index, _, step = P.Place()
  return section, step and step.id, index
end

-- A logged-in mage: `done` handed in before the addon was installed, `log` in the quest log.
local function join(level, done, log, opts)
  opts = opts or {}
  local c = sample3({ class = opts.class or "MAGE", level = level, saved = opts.saved, zone = opts.zone,
    x = opts.x, y = opts.y, afterLoad = opts.afterLoad })
  for _, q in ipairs(done or {}) do c:markCompleted(q) end
  for _, q in ipairs(log or {}) do c:acceptQuest(q) end
  c:login()
  return c, c.G.Noir, c.G.Noir.Progress
end

test("a level 1 character with nothing done starts at the first step", function()
  local c, Noir, P = join(1)
  eq({ place(P) }, { DEATHKNELL, "a363", 1 })
  eq(Noir.Why.List(), {}, "nothing was passed")
  eq(c:slashCount(), 0)
end)

test("a level 4 character with the second section's quests in the log is placed in the second section, after those quests", function()
  local c, Noir, P = join(4, { 363, 364, 376, 3901 }, { 365 })
  eq(Noir.Guide.Current(), TIRISFAL)
  eq({ place(P) }, { TIRISFAL, "fp384", 2 }, "just after the accept of Fields of Grief")
  local id, index, score = P.Locate(Noir.Guide.Chain(DEATHKNELL))
  eq({ id, index }, { TIRISFAL, 2 })
  ok(score > 0)
  local last = Noir.Why.List()[#Noir.Why.List()]
  eq(last.kind, "place")
  eq(c:slashCount(), 0)
end)

test("a character joining at the third section's level with its first quest handed in lands after it", function()
  local _, Noir, P = join(6, {}, {})
  -- Nothing done: the level decides the section (Tirisfal holds 3 to 6) and the place is its first step.
  eq({ place(P) }, { TIRISFAL, "a365", 1 })
  local c2, Noir2, P2 = join(6, { 435 }, {})
  eq(Noir2.Guide.Current(), SILVERPINE)
  local id, index, score = P2.Locate(Noir2.Guide.Chain(DEATHKNELL))
  eq({ id, index }, { SILVERPINE, 4 }, "just after the accept of Escorting Erland")
  eq(score, 1, "Tirisfal's Fields of Grief missing (-1), Erland handed in (+2); outleveled steps not counted")
  local section, _, at = place(P2)
  eq(section, SILVERPINE)
  ok(at >= 4, "placed after the quest")
  c2:advance(2)
  eq(select(2, place(P2)), "hs", "the work after it that is done passes by itself")
  eq(Noir.Guide.Current(), TIRISFAL)
end)

test("the place stays on the step of the best evidence while that step still has a quest line to do", function()
  -- Found by the simulator (task X1): a joiner who had taken the first of six quests at one NPC was placed after the
  -- whole step, and the five other accepts were passed without a word.
  local _, Noir, P = join(2, { 363 }, { 364 })
  eq({ place(P) }, { DEATHKNELL, "t363.a364.a376", 2 }, "The Damned is still to accept on that step")
  local _, index = P.Locate(Noir.Guide.Chain(DEATHKNELL))
  eq(index, 2)
  local _, _, P2 = join(2, { 363 }, { 364, 376 })
  eq(select(2, place(P2)), "a3901", "all done on that step: just after it")
end)

test("a quest in the log counts where it is accepted, not at a later objective of a section that does not accept it", function()
  -- Found by the simulator's joiners (task X1): placement inside a section counted a quest taken in an earlier section
  -- at its objective near the section's end, and the place jumped over hand-ins still to do.
  local c, Noir, P = join(4, { 363, 364, 376 }, { 3901, 365 }, { afterLoad = function(client)
    local sec = client.G.Noir.Routes.Get("horde-undead").sections[2]
    table.insert(sec.steps, #sec.steps, { id = "o3901late", at = { zone = 85, x = 40, y = 40, r = 40 },
      lines = { { kind = "objective", quest = 3901, index = 1 } } })
  end })
  eq(Noir.Guide.Current(), TIRISFAL)
  eq({ place(P) }, { TIRISFAL, "fp384", 2 }, "just after the accept of Fields of Grief")
end)

test("early quests left undone do not hold the place back", function()
  -- Rude Awakening and The Mindless Ones were never done; the rest of Deathknell was, and Fields of Grief is taken.
  local _, Noir, P = join(3, { 376, 3901 }, { 365 })
  eq(Noir.Guide.Current(), TIRISFAL)
  eq({ place(P) }, { TIRISFAL, "fp384", 2 })
  local _, index, _, left = P.Locate(Noir.Guide.Chain(DEATHKNELL))
  eq(index, 2)
  eq(left, 2, "two quest steps before the place are left undone")
end)

test("a saved place behind the quest log moves forward at login with one chat line", function()
  local c = sample3({ class = "MAGE", level = 2, saved = savedAt(DEATHKNELL, "a363") })
  c:acceptQuest(364)
  c:acceptQuest(376)
  c:acceptQuest(3901)
  local lines = {}
  c:loadAddon()
  c:login()
  for _, line in ipairs(c:takeChat()) do
    if line:find("Moved ahead", 1, true) then lines[#lines + 1] = line end
  end
  eq(#lines, 1, "one chat line")
  has(lines[1], "1-3 Deathknell step 5")
  has(lines[1], "your quest log shows the work before it done")
  local P = c.G.Noir.Progress
  eq({ place(P) }, { DEATHKNELL, "o364.o376", 5 }, "past the reminder step, on the objectives")
  eq(c.G.Noir.Why.List()[#c.G.Noir.Why.List()].kind, "place")
  -- Into a later section the same way.
  local c2 = sample3({ class = "MAGE", level = 4, saved = savedAt(DEATHKNELL, "a363") })
  for _, q in ipairs({ 364, 376, 3901 }) do c2:markCompleted(q) end
  c2:acceptQuest(365)
  c2:login()
  eq(c2.G.Noir.Guide.Current(), TIRISFAL)
  eq({ place(c2.G.Noir.Progress) }, { TIRISFAL, "fp384", 2 })
  has(c2:chatText(), "Moved ahead to 3-5 Tirisfal Glades step 2")
end)

test("a saved place ahead of the quest log is never moved back", function()
  local c = sample3({ class = "MAGE", level = 2, saved = savedAt(DEATHKNELL, "l3@85") })
  c:markCompleted(363)
  c:acceptQuest(364)
  c:login()
  c:advance(1)
  eq({ place(c.G.Noir.Progress) }, { DEATHKNELL, "l3@85", 9 })
  no(c:chatText():find("Moved", 1, true))
end)

test("placement runs with no command and the result is the current step", function()
  local seen = {}
  local c, Noir, P = join(4, { 363, 364, 376, 3901 }, { 365 }, { afterLoad = function(client)
    client.G.Noir.On("NOIR_STEP", function(_, cards)
      local last = cards and cards[#cards]
      seen[#seen + 1] = last and last.step.id or "none"
    end)
  end })
  eq(c:slashCount(), 0)
  local cards = P.Cards()
  eq(cards[#cards].kind, "current")
  eq(cards[#cards].step.id, "fp384")
  eq(seen[#seen], "fp384", "the window was told")
  eq(P.StepState(2), "current")
  eq(Noir.Guide.Current(), TIRISFAL)
end)

test("joiners at several levels land where their quest log says, never on a starting-zone quest they outleveled", function()
  local cases = {
    -- level, handed in, in the log, section, step at the place after catching up
    -- the step of the best evidence still accepts The Damned: the place stays on it (nothing passed silently)
    { 2, { 363 }, { 364 }, DEATHKNELL, "t363.a364.a376" },
    { 3, { 363, 364, 376 }, { 3901 }, DEATHKNELL, "t3901" },
    { 4, { 363, 364, 376, 3901 }, { 365 }, TIRISFAL, "fp384" },
    { 6, { 365 }, { 435 }, SILVERPINE, "t435" },
    { 8, {}, { 435 }, SILVERPINE, "t435" },
  }
  for _, case in ipairs(cases) do
    local c, Noir, P = join(case[1], case[2], case[3])
    c:advance(2)
    local label = "level " .. case[1]
    eq(Noir.Guide.Current(), case[4], label)
    eq(select(2, place(P)), case[5], label)
    eq(c:slashCount(), 0, label)
  end
end)

test("a level 12 character with no quest history is not held on a level 1 quest", function()
  -- 0.1.0 started every character at the first step; nothing here may land a level 12 on Rude Awakening.
  local c, Noir, P = join(12, {}, {}, { zone = 1497, x = 50, y = 50 })
  c:advance(2)
  eq(Noir.Guide.Current(), SILVERPINE, "the highest section the level has reached")
  local _, id = place(P)
  ok(id ~= "a363", "not on Rude Awakening")
  -- A level 12 standing in Tirisfal: no section holds 12, so the zone rule cannot pick one; the level does.
  local _, Noir2 = join(12, {}, {}, { zone = 85, x = 50, y = 50 })
  eq(Noir2.Guide.Current(), SILVERPINE)
end)
