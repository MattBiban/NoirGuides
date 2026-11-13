-- Noir Guides, GPLv3. See LICENSE.
-- Work ahead and nearby objectives (spec 3.3, 3.7, 4.4): a step under its level is deferred while work after it can
-- be done now, comes back as a card the moment the level is reached, and the arrow never points at it before; with
-- nothing to do ahead a grind card points at an area to grind in, never at the gated NPC; objective steps next to the
-- current one show as nearby cards, latch, and the arrow picks the nearest with hysteresis. The steps are written
-- into the Tirisfal section of the sample route; Tirisfal is 2400 by 1600 yards (1% of x is 24 yards, 1% of y 16).
-- Driven by game events, the mouse and logins only: nothing here types a command.
use("tools/test-lua/sample/helper.lua")

local TIRISFAL = "undead-03-05-tirisfal-glades"
local SILVERPINE = "undead-05-06-silverpine-forest"
local GUID = "Player-4444-0000002A"
local KEY = "Tester-Mock"

local function savedAt(stepId, profile)
  local db = { schema = 2, owner = GUID,
    guide = { section = TIRISFAL, how = "hand", places = { [TIRISFAL] = { step = stepId } } } }
  local account = {}
  if profile then account.NoirGuidesDB = { schema = 2, profiles = { Default = profile }, defaultProfile = "Default" } end
  return { account = account, characters = { [KEY] = { NoirGuidesCharDB = db } } }
end

local function P(x, y, r) return { zone = 85, x = x, y = y, r = r } end

-- A quest with one kill objective of 8.
local function Q(id) return { title = "Quest " .. id, objectives = { { text = "Thing slain", type = "monster", need = 8 } } } end

-- A mage at `stepId` of a Tirisfal section made of `list`. opts: level, x, y, log (quest IDs), profile.
local function play(list, stepId, opts) -- the player stands at 53, 50 unless opts.x, opts.y
  opts = opts or {}
  local c = sample3({ class = "MAGE", level = opts.level or 3, zone = 85, x = opts.x or 53, y = opts.y or 50,
    saved = savedAt(stepId, opts.profile),
    afterLoad = function(client)
      for n, step in ipairs(list) do step.n = n end
      client.G.Noir.Routes.Get("horde-undead").sections[2].steps = list
    end })
  for _, q in ipairs(opts.log or {}) do c:acceptQuest(q, Q(q)) end
  c:login()
  c:advance(0.5)
  return c, c.G.Noir, c.G.Noir.Progress
end

local function place(P_)
  local _, _, _, step = P_.Place()
  return step and step.id
end

local function kinds(P_)
  local out = {}
  for i, card in ipairs(P_.Cards()) do out[i] = card.kind .. " " .. card.step.id end
  return out
end

local function deferredIds(P_)
  local out = {}
  for i, d in ipairs(P_.Deferred()) do out[i] = P_.Steps()[d.index].id .. "@" .. d.level .. (d.gated and " gated" or "") end
  return out
end

local function lastCard(P_)
  local cards = P_.Cards()
  return cards[#cards]
end

-- A trainer for level 4 in the hub at 50, 50, a quest beside it, its field 124 yards away, its hand-in, then a hub
-- 850 yards away. Step o1 is an earlier field 240 yards west.
local function hub()
  return {
    { id = "o1", at = P(40, 50, 40), lines = { { kind = "objective", quest = 9001, index = 1 } } },
    { id = "train4", minLevel = 4, at = P(50, 50, 10), lines = { { kind = "train", class = "MAGE", level = 4, npc = 2124 } } },
    { id = "a9002", at = P(52, 50, 10), lines = { { kind = "accept", quest = 9002, npc = 1518 } } },
    { id = "o9002", at = P(55, 52, 40), lines = { { kind = "objective", quest = 9002, index = 1 } } },
    { id = "t9002", at = P(52, 50, 10), lines = { { kind = "turnin", quest = 9002, npc = 1518 } } },
    { id = "far", at = P(80, 80, 10), lines = { { kind = "accept", quest = 9003, npc = 1519 } } },
  }
end

local function visitTrainer(c)
  c:openTrainer(2124, {})
  c:advance(0.2)
  c:closeTrainer()
  c:advance(0.5)
end

test("the constants", function()
  local _, Noir, P_ = play(hub(), "a9002")
  eq(P_.WORK_AHEAD_STEPS, 8)
  eq(P_.WORK_AHEAD_YARDS, 300)
  eq(P_.NEARBY_YARDS, 150)
  eq(P_.NEARBY_CARDS, 3)
  eq(Noir.Arrow.SWITCH_YARDS, 15)
  eq(Noir.Arrow.SWITCH_SHARE, 0.2)
  eq(Noir.Options.Get("workAhead"), true, "on by default")
end)

test("under its level a step is deferred, the place works ahead, and the step comes back at the level", function()
  local c, Noir, P_ = play(hub(), "train4")
  eq(place(P_), "a9002", "the trainer waits for level 4; the quest beside it comes first")
  local e = Noir.Why.ForStep(TIRISFAL, "train4")
  eq(e.kind, "deferred")
  has(e.text, "deferred until level 4")
  eq(deferredIds(P_), { "train4@4 gated" })
  eq(kinds(P_), { "current a9002" }, "hidden while under level")
  eq(P_.StepState(2), "deferred")
  eq(Noir.char.guide.places[TIRISFAL].deferred.train4, 4, "saved")
  eq(Noir.Arrow.Target().step.id, "a9002")
  c:acceptQuest(9002, Q(9002))
  c:advance(0.5)
  eq(place(P_), "o9002")
  c:completeObjectives(9002)
  c:advance(0.5)
  eq(place(P_), "t9002")
  c:setLevel(4)
  c:advance(0.5)
  eq(kinds(P_), { "deferred train4", "current t9002" }, "at level 4 it comes back first")
  eq(Noir.Arrow.Target().step.id, "train4", "and the arrow points at it")
  eq(P_.StepState(2), "reminder")
  visitTrainer(c)
  eq(kinds(P_), { "current t9002" }, "done: gone")
  eq(deferredIds(P_), {})
  eq(Noir.char.guide.places[TIRISFAL].deferred.train4, nil)
  eq(Noir.Why.ForStep(TIRISFAL, "train4").kind, "deferred", "done in front of the player: no new why entry")
  eq(c:slashCount(), 0)
end)

test("the deferred step survives a reload and still comes back", function()
  local c, _, P_ = play(hub(), "train4")
  eq(place(P_), "a9002")
  local c2 = c:relog({ reload = true })
  c2:advance(0.5)
  local P2 = c2.G.Noir.Progress
  eq(place(P2), "a9002")
  eq(deferredIds(P2), { "train4@4 gated" })
  c2:setLevel(4)
  c2:advance(0.5)
  eq(kinds(P2), { "deferred train4", "current a9002" })
end)

test("a step that needs a deferred one is deferred with it, and no detour points back at the gated step", function()
  local list = {
    { id = "o1", at = P(40, 50, 40), lines = { { kind = "objective", quest = 9001, index = 1 } } },
    { id = "a9003", minLevel = 4, at = P(50, 50, 10), lines = { { kind = "accept", quest = 9003, npc = 1519 } } },
    { id = "o9003", at = P(53, 50, 40), lines = { { kind = "objective", quest = 9003, index = 1 } } },
    { id = "t9003", at = P(50, 50, 10), lines = { { kind = "turnin", quest = 9003, npc = 1519 } } },
    { id = "a9002", at = P(52, 50, 10), lines = { { kind = "accept", quest = 9002, npc = 1518 } } },
    { id = "far", at = P(80, 80, 10), lines = { { kind = "accept", quest = 9004, npc = 1520 } } },
  }
  local c, Noir, P_ = play(list, "a9003")
  eq(place(P_), "a9002")
  eq(deferredIds(P_), { "a9003@4 gated", "o9003@4 gated", "t9003@4 gated" })
  eq(kinds(P_), { "current a9002" }, "no detour to the gated accept")
  eq(Noir.Why.ForStep(TIRISFAL, "o9003").kind, "deferred")
  ok(Noir.Arrow.Target().step.id ~= "a9003")
  c:setLevel(4)
  c:advance(0.5)
  eq(kinds(P_), { "deferred a9003", "deferred o9003", "deferred t9003", "current a9002" })
  eq(Noir.Arrow.Target().step.id, "a9003", "the first deferred step takes the arrow")
  c:acceptQuest(9003, Q(9003))
  c:advance(0.5)
  eq(kinds(P_), { "deferred o9003", "deferred t9003", "current a9002" })
  c:completeObjectives(9003)
  c:advance(0.5)
  c:turnInQuest(9003)
  c:advance(0.5)
  eq(kinds(P_), { "current a9002" })
  eq(deferredIds(P_), {})
end)

test("past the work within reach a grind card stands in, pointing at the last field, never at the trainer", function()
  local c, Noir, P_ = play(hub(), "train4")
  c:acceptQuest(9002, Q(9002))
  c:advance(0.5)
  c:completeObjectives(9002)
  c:advance(0.5)
  c:turnInQuest(9002)
  c:advance(0.5)
  eq(place(P_), "far", "the place is on the hub 850 yards away")
  local card = lastCard(P_)
  eq(kinds(P_), { "current train4" }, "but the card asks for the grind first")
  eq(card.gated, true)
  eq(#card.lines, 1)
  eq(card.lines[1].line.kind, "grind")
  eq(card.lines[1].line.level, 4)
  eq(card.lines[1].index, 0)
  eq(card.lines[1].line.at, { zone = 85, x = 40, y = 50 }, "the area of the last objective step")
  local t = Noir.Arrow.Target()
  eq(t.at.x, 40)
  eq(t.grind, true)
  c:setLevel(4)
  c:advance(0.5)
  eq(kinds(P_), { "deferred train4", "current far" })
end)

test("with nothing to do ahead the step waits with a grind line whose place is not the gated NPC", function()
  local list = {
    { id = "o1", at = P(40, 50, 40), lines = { { kind = "objective", quest = 9001, index = 1 } } },
    { id = "train4", minLevel = 4, at = P(50, 50, 10), lines = { { kind = "train", class = "MAGE", level = 4, npc = 2124 } } },
    { id = "fly10", at = P(58.9, 51.9, 10), lines = { { kind = "fly", from = 384, to = 10 } } },
  }
  local c, Noir, P_ = play(list, "train4")
  eq(place(P_), "train4", "a flight is no work to do here")
  eq(deferredIds(P_), {})
  local card = lastCard(P_)
  eq(card.kind, "current")
  eq(card.gated, true)
  eq(card.lines[1].line.kind, "grind")
  eq(card.lines[1].line.at, { zone = 85, x = 40, y = 50 })
  eq(card.lines[2].line.kind, "train", "the gated step's own lines follow")
  local t = Noir.Arrow.Target()
  eq(t.at.x, 40, "the arrow points at the field, not at the trainer 0 yards away")
  eq(t.grind, true)
  c:setLevel(4)
  c:advance(0.5)
  eq(lastCard(P_).gated, nil)
  eq(Noir.Arrow.Target().at.x, 50, "at the level the trainer")
end)

test("a gated step with an objective area of its own grinds there; with no area at all the arrow has no target", function()
  local list = {
    { id = "o5", minLevel = 4, at = P(60, 60, 40), lines = { { kind = "objective", quest = 9005, index = 1 } } },
    { id = "fly10", at = P(58.9, 51.9, 10), lines = { { kind = "fly", from = 384, to = 10 } } },
  }
  local _, Noir, P_ = play(list, "o5")
  eq(lastCard(P_).lines[1].line.at, { zone = 85, x = 60, y = 60 })
  local bare = {
    { id = "train4", minLevel = 4, at = P(50, 50, 10), lines = { { kind = "train", class = "MAGE", level = 4, npc = 2124 } } },
    { id = "fly10", at = P(58.9, 51.9, 10), lines = { { kind = "fly", from = 384, to = 10 } } },
  }
  local _, Noir2, P2 = play(bare, "train4")
  eq(lastCard(P2).lines[1].line.at, nil)
  eq(Noir2.Arrow.Target(), nil, "no grind area: no arrow rather than the trainer")
  ok(Noir)
end)

test("deferral never crosses the end of the section: the place holds there with a grind card", function()
  local list = {
    { id = "o1", at = P(40, 50, 40), lines = { { kind = "objective", quest = 9001, index = 1 } } },
    { id = "train4", minLevel = 4, at = P(50, 50, 10), lines = { { kind = "train", class = "MAGE", level = 4, npc = 2124 } } },
    { id = "a9002", at = P(52, 50, 10), lines = { { kind = "accept", quest = 9002, npc = 1518 } } },
  }
  local c, Noir, P_ = play(list, "train4")
  eq(place(P_), "a9002")
  c:acceptQuest(9002, Q(9002))
  c:advance(1)
  eq(Noir.Guide.Current(), TIRISFAL, "the section does not end while the trainer waits")
  eq(place(P_), "a9002")
  eq(kinds(P_), { "current train4" })
  eq(lastCard(P_).gated, true)
  c:setLevel(4)
  c:advance(0.5)
  eq(kinds(P_), { "deferred train4", "current a9002" })
  eq(Noir.Guide.Current(), TIRISFAL)
  visitTrainer(c)
  c:advance(1)
  eq(Noir.Guide.Current(), SILVERPINE, "the trainer done: the next section")
end)

test("a reminder whose ends step is deferred stays open until that step is done", function()
  local list = {
    { id = "r.keep", reminder = { ends = "trainX" }, lines = { { kind = "manual", text = "Keep the skill up" } } },
    { id = "a9001", at = P(50, 50, 10), lines = { { kind = "accept", quest = 9001, npc = 1518 } } },
    { id = "train4", label = "trainX", minLevel = 4, at = P(50, 50, 10), lines = { { kind = "train", class = "MAGE", level = 4, npc = 2124 } } },
    { id = "a9002", at = P(52, 50, 10), lines = { { kind = "accept", quest = 9002, npc = 1518 } } },
    { id = "far", at = P(80, 80, 10), lines = { { kind = "accept", quest = 9003, npc = 1519 } } },
  }
  local c, _, P_ = play(list, "a9001", { log = { 9001 } })
  eq(place(P_), "a9002", "past the accept and the deferred trainer")
  eq(kinds(P_), { "reminder r.keep", "current a9002" }, "the reminder is still open: its trainer is not done")
  c:setLevel(4)
  c:advance(0.5)
  eq(kinds(P_), { "deferred train4", "reminder r.keep", "current a9002" })
  visitTrainer(c)
  eq(kinds(P_), { "current a9002" }, "the trainer done: the reminder ends")
end)

test("with 'work ahead' off the step waits as before, its grind line pointing at the field", function()
  local _, Noir, P_ = play(hub(), "train4", { profile = { workAhead = false } })
  eq(place(P_), "train4")
  eq(deferredIds(P_), {})
  local card = lastCard(P_)
  eq(card.gated, true)
  eq(card.lines[1].line.at, { zone = 85, x = 40, y = 50 })
  eq(Noir.Arrow.Target().at.x, 40)
  eq(Noir.Why.ForStep(TIRISFAL, "train4"), nil)
end)

test("a step the player jumped to is not deferred", function()
  local _, _, P_ = play(hub(), "a9002")
  ok(P_.Jump(2, "list"))
  eq(place(P_), "train4")
  eq(lastCard(P_).gated, true)
end)

-- Three fields close together around 40, 40 (o1 current, o2 50 yards east, o3 54 yards south), a fourth whose quest
-- is not in the log, and a hand-in.
local function fields()
  return {
    { id = "o1", at = P(40, 40), lines = { { kind = "objective", quest = 9001, index = 1 } } },
    { id = "o2", at = P(42, 41), lines = { { kind = "objective", quest = 9002, index = 1 } } },
    { id = "o3", at = P(41, 43), lines = { { kind = "objective", quest = 9003, index = 1 } } },
    { id = "o4", at = P(45, 40), lines = { { kind = "objective", quest = 9004, index = 1 } } },
    { id = "t9001", at = P(30, 30, 10), lines = { { kind = "turnin", quest = 9001, npc = 1518 } } },
  }
end

test("objective steps next to the current one show as nearby cards, up to the cap", function()
  local _, _, P_ = play(fields(), "o1", { x = 40, y = 40, log = { 9001, 9002, 9003 } })
  eq(kinds(P_), { "nearby o2", "nearby o3", "current o1" }, "o4's quest is not in the log: the run ends there")
  eq(P_.StepState(2), "reminder")
  P_.NEARBY_CARDS = 1
  eq(kinds(P_), { "nearby o2", "current o1" })
  P_.NEARBY_CARDS = 3
  -- A hand-in is never pulled forward.
  local list = fields()
  table.insert(list, 2, { id = "t9009", at = P(41, 40, 10), lines = { { kind = "turnin", quest = 9009, npc = 1518 } } })
  local _, _, P2 = play(list, "o1", { x = 40, y = 40, log = { 9001, 9002, 9003, 9009 } })
  eq(kinds(P2), { "current o1" })
  -- Too far: 169 yards.
  local far = fields()
  far[2].at = P(47, 41)
  local _, _, P3 = play(far, "o1", { x = 40, y = 40, log = { 9001, 9002, 9003 } })
  eq(kinds(P3), { "current o1" })
end)

test("lines done while nearby stay latched, so the step passes as done with no why entry", function()
  local c, Noir, P_ = play(fields(), "o1", { x = 40, y = 40, log = { 9001, 9002, 9003 } })
  c:completeObjectives(9002)
  c:advance(0.5)
  eq(kinds(P_), { "nearby o3", "current o1" }, "o2 is done: no longer shown")
  c:abandonQuest(9002)
  c:advance(0.5)
  eq(kinds(P_), { "current o1" }, "with its quest gone the run ends at o2")
  c:completeObjectives(9003)
  c:completeObjectives(9001)
  c:advance(1)
  eq(place(P_), "t9001", "o2 latched done and o3 done: both passed (o4, whose quest is not in the log, cannot be done)")
  eq(Noir.Why.ForStep(TIRISFAL, "o2"), nil, "done in front of the player")
  eq(Noir.Why.ForStep(TIRISFAL, "o1"), nil)
end)

test("the arrow points at the nearest of the current and nearby places, and does not flip between near-equal ones", function()
  local c, Noir, P_ = play(fields(), "o1", { x = 40, y = 40, log = { 9001, 9002, 9003 } })
  local Arrow = Noir.Arrow
  eq(Arrow.Target().step.id, "o1", "standing on o1")
  c:moveTo({ zone = 85, x = 42, y = 41 })
  eq(Arrow.Target().step.id, "o2", "on o2: 50 yards nearer, it switches")
  c:moveTo({ zone = 85, x = 40.8, y = 40.4 })
  -- o1 is 20 yards away and o2 30: 10 yards nearer is not enough.
  eq(Arrow.Target().step.id, "o2", "kept")
  c:moveTo({ zone = 85, x = 40.2, y = 40.1 })
  eq(Arrow.Target().step.id, "o1", "40 yards nearer: switched")
  ok(P_)
end)

test("without nearby cards the arrow keeps the card order", function()
  local _, Noir, P_ = play(fields(), "o1", { x = 42, y = 41, log = { 9001 } })
  eq(kinds(P_), { "current o1" })
  eq(Noir.Arrow.Target().step.id, "o1")
end)
