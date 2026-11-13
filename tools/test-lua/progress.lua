-- Noir Guides, GPLv3. See LICENSE.
-- Progress v3: the place in a section, line states and latches, passing steps, conditions, detours, jumps, the end
-- of a section and the saved place (plan task E4, spec 3.3 to 3.7, 2.4). Driven by game events, clicks on the
-- engine's own functions (what the window calls) and logins: nothing here types a command.
use("tools/test-lua/sample/helper.lua")

local DEATHKNELL = "undead-01-03-deathknell"
local TIRISFAL = "undead-03-05-tirisfal-glades"
local SILVERPINE = "undead-05-06-silverpine-forest"
local GUID = "Player-4444-0000002A"
local KEY = "Tester-Mock"

-- Saved variables for the mock character: `char` merged into NoirGuidesCharDB, `profile` the Default profile.
local function savedWith(char, profile)
  local db = { schema = 2, owner = GUID }
  for k, v in pairs(char or {}) do db[k] = v end
  local account = {}
  if profile then account.NoirGuidesDB = { schema = 2, profiles = { Default = profile }, defaultProfile = "Default" } end
  return { account = account, characters = { [KEY] = { NoirGuidesCharDB = db } } }
end

-- Saved with the place in `section` at the step `stepId`.
local function savedAt(section, stepId, char, profile)
  char = char or {}
  char.guide = { section = section, how = "hand", places = { [section] = { step = stepId } } }
  return savedWith(char, profile)
end

local function play(opts)
  local c = sample3(opts):login()
  return c, c.G.Noir, c.G.Noir.Progress
end

-- The id of the step at the place, and its index.
local function place(P)
  local _, index, _, step = P.Place()
  return step and step.id, index
end

local function currentCard(P)
  local cards = P.Cards()
  local card = cards[#cards]
  if card and card.kind == "current" then return card end
  return nil
end

local function states(card)
  local out = {}
  for i, l in ipairs(card.lines) do out[i] = l.state end
  return out
end

local function kinds(P)
  local out = {}
  for i, card in ipairs(P.Cards()) do out[i] = card.kind .. " " .. card.step.id end
  return out
end

-- A quest the default mock world does not define, with one item objective.
local QUEST3901 = { title = "Fresh Meat", objectives = { { text = "Rattlecage Bone", type = "item", need = 5 } } }

test("the constants of the plan", function()
  local _, _, P = play()
  eq(P.PASS_SECONDS, 0.1)
  eq(P.ARRIVAL_SECONDS, 0.33)
  eq(P.SIGNAL_QUIET, 1)
  eq(P.LOOKAHEAD_TEXT, 8)
  eq(P.BEHIND_STEPS, 3)
end)

test("a bundled step completes only when all its lines are done", function()
  local c, _, P = play({ class = "MAGE", level = 1 })
  eq(place(P), "a363", "a new character starts at the first step")
  c:acceptQuest(363)
  c:advance(0.2)
  eq(place(P), "t363.a364.a376")
  c:turnInQuest(363)
  c:advance(0.5)
  eq(place(P), "t363.a364.a376", "one of three lines is done")
  eq(states(currentCard(P)), { "done", "todo", "todo" })
  c:acceptQuest(364)
  c:advance(0.5)
  eq(place(P), "t363.a364.a376", "two of three lines are done")
  eq(states(currentCard(P)), { "done", "done", "todo" })
  c:acceptQuest(376)
  c:advance(0.2)
  eq(place(P), "a3901", "all three lines done: the next step")
  eq(c:slashCount(), 0)
end)

test("a line ticked by hand counts and untick reopens it", function()
  local c, Noir, P = play({ class = "MAGE", level = 1 })
  ok(P.Jump(2, "list"))
  eq(place(P), "t363.a364.a376")
  P.Tick(2, 2, true)
  local card = currentCard(P)
  eq(card.lines[2].ticked, true)
  eq(card.lines[2].state, "done")
  eq(Noir.char.guide.places[DEATHKNELL].ticks["t363.a364.a376"][2], true, "the tick is saved")
  c:advance(0.5)
  eq(place(P), "t363.a364.a376", "one ticked line does not finish the step")
  P.Tick(2, 2, false)
  card = currentCard(P)
  eq(card.lines[2].ticked, false)
  eq(card.lines[2].state, "todo", "untick reopens it")
  P.Tick(2, 1, true)
  P.Tick(2, 2, true)
  P.Tick(2, 3, true)
  c:advance(0.2)
  eq(place(P), "a3901", "ticking the last open line completes the step")
  eq(Noir.Why.ForStep(DEATHKNELL, "t363.a364.a376").kind, "tick")
  eq(Noir.char.guide.places[DEATHKNELL].ticks["t363.a364.a376"], nil, "ticks of a step no longer on screen are dropped")
end)

test("a line done once stays done while its step is on screen", function()
  local c, _, P = play({ class = "MAGE", level = 1 })
  ok(P.Jump(2, "list"))
  c:acceptQuest(364)
  c:advance(0.2)
  eq(states(currentCard(P)), { "missing", "done", "todo" })
  c:abandonQuest(364)
  c:advance(0.2)
  eq(currentCard(P).lines[2].state, "done", "the accept line stays done after the quest left the log")
  ok(P.Jump(9, "list"))
  c:advance(3) -- past the 2 s an accept event counts for
  ok(P.Jump(2, "list"))
  eq(currentCard(P).lines[2].state, "todo", "entered again, it is judged again")
end)

test("an accept event 1 s before the step became current completes the accept line; 3 s before does not", function()
  local c, _, P = play({ class = "MAGE", level = 1 })
  c:acceptQuest(3901, QUEST3901)
  c:abandonQuest(3901)
  c:advance(1)
  ok(P.Jump(3, "list"))
  eq(place(P), "a3901")
  eq(currentCard(P).lines[1].state, "done", "accepted 1 s before the step became current")
  c:advance(0.2)
  eq(place(P), "o364.o376", "the step passed and the reminder after it opened")

  local c2, _, P2 = play({ class = "MAGE", level = 1 })
  c2:acceptQuest(3901, QUEST3901)
  c2:abandonQuest(3901)
  c2:advance(3)
  ok(P2.Jump(3, "list"))
  eq(currentCard(P2).lines[1].state, "todo", "accepted 3 s before")
  c2:advance(0.5)
  eq(place(P2), "a3901")
end)

test("a hand-in 4 s before the step became current completes the turn-in line", function()
  local c, Noir, P = play({ class = "MAGE", level = 1 })
  c:acceptQuest(3901, QUEST3901)
  c:turnInQuest(3901)
  -- A repeatable quest is not flagged as handed in: only the hand-in event counts.
  c.s.completed[3901] = nil
  Noir.State.completed[3901] = nil
  c:advance(4)
  ok(P.Jump(8, "list"))
  eq(place(P), "t3901")
  eq(currentCard(P).lines[1].state, "done", "handed in 4 s before the step became current")

  local c2, Noir2, P2 = play({ class = "MAGE", level = 1 })
  c2:acceptQuest(3901, QUEST3901)
  c2:turnInQuest(3901)
  c2.s.completed[3901] = nil
  Noir2.State.completed[3901] = nil
  c2:advance(6)
  ok(P2.Jump(8, "list"))
  ok(currentCard(P2).lines[1].state ~= "done", "handed in 6 s before")
end)

test("a run of done steps passes one per pass and is logged as already done", function()
  local moves = {}
  local c = sample3({ class = "MAGE", level = 1, saved = savedAt(DEATHKNELL, "o364.o376"),
    afterLoad = function(client)
      client.G.Noir.On("NOIR_PLACE", function(_, section, index) moves[#moves + 1] = { section, index, client.now } end)
    end })
  for _, q in ipairs({ 364, 376, 3901 }) do c:markCompleted(q) end
  c:login()
  c:advance(2)
  local P, Why = c.G.Noir.Progress, c.G.Noir.Why
  eq(place(P), "l3@85", "stops at the first step that is not done")
  local indexes = {}
  for i, m in ipairs(moves) do indexes[i] = m[2] end
  eq(indexes, { 5, 6, 7, 8, 9 }, "loaded at 5, then one step at a time")
  for i = 2, #moves do
    ok(moves[i][3] - moves[i - 1][3] >= 0.1 - 1e-6, "one step per pass of 0.1 s (move " .. i .. ")")
  end
  for _, id in ipairs({ "o364.o376", "c2834", "t364.t376", "t3901" }) do
    local e = Why.ForStep(DEATHKNELL, id)
    ok(e, "logged: " .. id)
    eq(e.kind, "done", id)
  end
end)

test("a skip condition passes the step with its reason, and never when 'never auto-skip' is on", function()
  local function withCondition(client)
    client.G.Noir.Routes.Get("horde-undead").sections[2].steps[2].skip = { { kind = "zone", zone = 85 } }
  end
  local c, Noir, P = play({ class = "MAGE", level = 3, saved = savedAt(TIRISFAL, "fp384"), afterLoad = withCondition })
  c:advance(0.5)
  eq(place(P), "inn")
  local e = Noir.Why.ForStep(TIRISFAL, "fp384")
  eq(e.kind, "condition")
  has(e.text, "Tirisfal Glades")

  local c2, _, P2 = play({ class = "MAGE", level = 3, afterLoad = withCondition,
    saved = savedAt(TIRISFAL, "fp384", nil, { neverSkip = true }) })
  c2:advance(1)
  eq(place(P2), "fp384", "never auto-skip keeps the step")

  -- While the addon is hidden the condition waits; lines would still complete.
  local c3, Noir3, P3 = play({ class = "MAGE", level = 3, afterLoad = withCondition,
    saved = savedAt(TIRISFAL, "fp384", nil, { shown = false }) })
  c3:advance(1)
  eq(place(P3), "fp384", "no condition is checked while the addon is hidden")
  ok(Noir3.Options.Set("shown", true))
  c3:advance(0.5)
  eq(place(P3), "inn")
end)

test("with 'never auto-skip' on, a gated accept the game will not offer is still passed, and a plain condition is not", function()
  -- Review 2 of task X1: an accept needing two quests gets a step of its own with a "notturnedin" skip per further
  -- quest (planner, isolateGated). With "neverSkip" on, a joiner lacking that quest would wait for ever.
  local function withSteps(gateSkip)
    return function(client)
      local sec = client.G.Noir.Routes.Get("horde-undead").sections[2]
      sec.steps = {
        { id = "a376g", at = { zone = 85, x = 60, y = 52, r = 10 },
          lines = { { kind = "accept", quest = 376, npc = 1570, ifDone = 363, requires = { 363, 364 } } }, skip = { gateSkip } },
        { id = "a365x", at = { zone = 85, x = 59.4, y = 52.4, r = 10 }, lines = { { kind = "accept", quest = 365 } } },
      }
    end
  end
  local c = sample3({ class = "MAGE", level = 3, zone = 85, x = 60, y = 52, afterLoad = withSteps({ kind = "notturnedin", quest = 364 }),
    saved = savedAt(TIRISFAL, "a376g", nil, { neverSkip = true }) })
  c:markCompleted(363)
  c:login()
  local Noir, P = c.G.Noir, c.G.Noir.Progress
  c:advance(1)
  eq(place(P), "a365x", "364 is not handed in: the game will not offer 376")
  local e = Noir.Why.ForStep(TIRISFAL, "a376g")
  ok(e, "logged")
  eq(e.kind, "condition")
  has(e.text, "Mindless Ones")
  -- The same step with a condition that is no gate stays under "never auto-skip".
  local c2 = sample3({ class = "MAGE", level = 3, zone = 85, x = 60, y = 52, afterLoad = withSteps({ kind = "zone", zone = 85 }),
    saved = savedAt(TIRISFAL, "a376g", nil, { neverSkip = true }) })
  c2:markCompleted(363)
  c2:markCompleted(364)
  c2:login()
  c2:advance(1)
  eq(place(c2.G.Noir.Progress), "a376g", "never auto-skip keeps the step")
end)

test("a jump condition goes to its label", function()
  local c = sample3({ class = "MAGE", level = 3, saved = savedAt(TIRISFAL, "a365") })
  c:markCompleted(365)
  c:login()
  c:advance(0.5)
  local P = c.G.Noir.Progress
  eq(place(P), "inn", "Fields of Grief handed in: straight to the inn, past the flight master")
  local e = c.G.Noir.Why.ForStep(TIRISFAL, "a365")
  eq(e.kind, "condition")
  has(e.text, "handed in")
end)

test("with work ahead off, a step under its minimum level shows a grind line first and waits", function()
  local c, _, P = play({ class = "MAGE", level = 5, saved = savedAt(TIRISFAL, "a367", nil, { workAhead = false }) })
  c:advance(0.5)
  eq(place(P), "a367")
  local card = currentCard(P)
  eq(card.lines[1].line.kind, "grind")
  eq(card.lines[1].line.level, 7)
  eq(card.lines[1].line.synthetic, true)
  eq(card.lines[1].state, "todo")
  c:acceptQuest(367)
  c:advance(0.5)
  eq(place(P), "a367", "the quest is accepted but the level is not reached")
  c:setLevel(7)
  c:advance(0.5)
  eq(place(P), "m.chest", "level 7: the step completes (and the level 5 step after it is outleveled)")
end)

test("an outleveled step is passed with the reason", function()
  local c, Noir, P = play({ class = "MAGE", level = 6, saved = savedAt(TIRISFAL, "a370") })
  c:advance(0.5)
  eq(place(P), "m.chest")
  local e = Noir.Why.ForStep(TIRISFAL, "a370")
  eq(e.kind, "outleveled")
  has(e.text, "5")
  local c2, _, P2 = play({ class = "MAGE", level = 6, saved = savedAt(TIRISFAL, "a370", nil, { outlevel = false }) })
  c2:advance(0.5)
  eq(place(P2), "a370", "with 'skip content you outlevel' off the step stays")
end)

test("a missing quest shows its accept step as a detour card", function()
  local c = sample3({ class = "MAGE", level = 2 })
  c:markCompleted(363)
  c:markCompleted(3901)
  c:login()
  local P = c.G.Noir.Progress
  ok(P.Jump(5, "list"))
  eq(kinds(P), { "detour t363.a364.a376", "current o364.o376" })
  eq(currentCard(P).lines[1].state, "missing")
  c:advance(1)
  eq(place(P), "o364.o376", "the step waits for its quests")
  c:acceptQuest(364)
  c:acceptQuest(376)
  c:advance(0.2)
  eq(kinds(P), { "nearby c2834", "current o364.o376" }, "the quests are back: no detour")
end)

test("a missing quest that an earlier line of the same step accepts waits for that line", function()
  -- Found by the simulator (task X1): a bundled step "accept, then do its objective" passed the objective as
  -- impossible ("nothing earlier in this section accepts it") the moment the step became current.
  local c, Noir, P = play({ class = "MAGE", level = 1, afterLoad = function(client)
    local step = client.G.Noir.Routes.Get("horde-undead").sections[1].steps[2]
    step.lines[#step.lines + 1] = { kind = "objective", quest = 364, index = 1 }
  end })
  c:acceptQuest(363)
  c:advance(0.5)
  eq(place(P), "t363.a364.a376")
  eq(kinds(P), { "current t363.a364.a376" }, "no detour: the step itself accepts the quest")
  eq(states(currentCard(P)), { "todo", "todo", "todo", "missing" })
  eq(Noir.Why.ForStep(DEATHKNELL, "t363.a364.a376"), nil, "nothing passed")
  local chat = c:chatText()
  ok(not chat:find("that line was passed", 1, true), "no chat line about a passed line")
  c:turnInQuest(363)
  c:acceptQuest(364)
  c:acceptQuest(376)
  c:advance(0.5)
  eq(place(P), "t363.a364.a376", "the objective is still to do")
  eq(states(currentCard(P)), { "done", "done", "done", "todo" })
  c:progressQuest(364, 1, 8)
  c:advance(0.5)
  eq(place(P), "a3901", "the objective done, the step completes")
end)

test("a skipIfMissing line of a quest an earlier line of the same step accepts waits instead of skipping", function()
  -- Found by the simulator (task X1): "accept A, do A, hand in A (skip if missing), accept B" in one step skipped the
  -- hand-in the moment the step showed, and A stayed in the quest log for good.
  local c, Noir, P = play({ class = "MAGE", level = 1, afterLoad = function(client)
    local step = client.G.Noir.Routes.Get("horde-undead").sections[1].steps[2]
    step.lines[#step.lines + 1] = { kind = "objective", quest = 364, index = 1, skipIfMissing = true }
    step.lines[#step.lines + 1] = { kind = "turnin", quest = 364, npc = 1569, skipIfMissing = true }
  end })
  c:acceptQuest(363)
  c:advance(0.5)
  eq(place(P), "t363.a364.a376")
  eq(states(currentCard(P)), { "todo", "todo", "todo", "missing", "missing" }, "waiting for the accept, not skipped")
  eq(Noir.Why.ForStep(DEATHKNELL, "t363.a364.a376"), nil, "nothing passed")
  c:turnInQuest(363)
  c:acceptQuest(364)
  c:acceptQuest(376)
  c:advance(0.5)
  eq(states(currentCard(P)), { "done", "done", "done", "todo", "todo" })
end)

test("a hand-in whose objectives are not done shows the earlier objective step as a detour", function()
  -- Found by the simulator's joiners (task X1): placed past the objective step of a quest in their log, they stood
  -- before its hand-in with nothing on screen that said to finish it.
  local c = sample3({ class = "MAGE", level = 3, saved = savedAt(DEATHKNELL, "t364.t376") })
  c:markCompleted(363)
  c:markCompleted(3901)
  c:acceptQuest(364)
  c:acceptQuest(376)
  c:login()
  local P = c.G.Noir.Progress
  c:advance(0.5)
  eq(kinds(P), { "detour o364.o376", "current t364.t376" })
  c:completeObjectives(364)
  c:advance(0.5)
  eq(kinds(P)[1] ~= "detour o364.o376", true, "the objectives done: no detour")
end)

test("a hand-in the player jumped to does not bring back the objective steps passed as detours", function()
  -- Spec 3.5: going to a step from the list is a manual skip; the detours are for a place found by placement.
  local c = sample3({ class = "MAGE", level = 3, saved = savedAt(DEATHKNELL, "t364.t376") })
  c:markCompleted(363)
  c:markCompleted(3901)
  c:acceptQuest(364)
  c:acceptQuest(376)
  c:login()
  local P = c.G.Noir.Progress
  c:advance(0.5)
  eq(kinds(P), { "detour o364.o376", "current t364.t376" })
  local _, here = P.Place()
  ok(P.Jump(here, "list"))
  c:advance(0.5)
  eq(kinds(P), { "current t364.t376" })
end)

test("an accept whose required quest is still in the log shows that quest's earlier steps as detours", function()
  local c = sample3({ class = "MAGE", level = 3, saved = savedAt(DEATHKNELL, "t3901"), afterLoad = function(client)
    for _, step in ipairs(client.G.Noir.Routes.Get("horde-undead").sections[1].steps) do
      if step.id == "t3901" then step.lines[2] = { kind = "accept", quest = 8, npc = 1570, requires = { 364 } } end
    end
  end })
  c:markCompleted(363)
  c:markCompleted(3901)
  c:acceptQuest(364)
  c:login()
  local P = c.G.Noir.Progress
  c:advance(0.5)
  eq(kinds(P), { "detour o364.o376", "detour t364.t376", "current t3901" })
end)

test("a move whose next task is done is passed as moot", function()
  local c = sample3({ class = "MAGE", level = 6, saved = savedAt(SILVERPINE, "z130", { flights = { [10] = true } }) })
  c:acceptQuest(435)
  c:login()
  c:advance(2)
  local Noir, P = c.G.Noir, c.G.Noir.Progress
  local e = Noir.Why.ForStep(SILVERPINE, "z130")
  ok(e, "the move is logged")
  eq(e.kind, "moot")
  eq(place(P), "t435", "past the flight point, the accept, the passive steps and the grind")
  -- A move the player went back to is not passed as moot.
  ok(P.Jump(1, "list"))
  c:advance(1)
  eq(place(P), "z130")
end)

test("a move that still leads to the work left is not moot", function()
  -- The flight point is known but Erland's quest, in Silverpine, is still to take: the road there still leads.
  local c = sample3({ class = "MAGE", level = 6, saved = savedAt(SILVERPINE, "z130", { flights = { [10] = true } }) })
  c:login()
  c:advance(1)
  eq(place(c.G.Noir.Progress), "z130")
end)

test("a boat whose journey goes on by a walk and a flight to the work left is not moot", function()
  -- Found by the simulator (task X1): "take the zeppelin to Durotar", "head into Orgrimmar", "fly to Un'Goro" with a
  -- done step and then work in Un'Goro after them: the zeppelin was passed as moot and the character was stranded.
  local c = sample3({ class = "MAGE", level = 6, zone = 85, x = 60, y = 58, saved = savedAt(SILVERPINE, "zep"),
    afterLoad = function(client)
      local sec = client.G.Noir.Routes.Get("horde-undead").sections[3]
      local zep, g14
      for _, step in ipairs(sec.steps) do
        if step.id == "zep" then zep = step elseif step.id == "g14" then g14 = step end
      end
      sec.steps = { zep, g14,
        { id = "y23-10", at = { zone = 14, x = 50, y = 20, r = 10 }, lines = { { kind = "fly", from = 23, to = 10 } } },
        { id = "a363x", at = { zone = 85, x = 30.2, y = 71.6, r = 8 }, lines = { { kind = "accept", quest = 363, npc = 1568 } } },
        { id = "a435x", at = { zone = 130, x = 56.2, y = 9.2, r = 10 }, lines = { { kind = "accept", quest = 435, npc = 1950 } } },
      }
    end })
  c:markCompleted(363)
  c:login()
  local Noir, P = c.G.Noir, c.G.Noir.Progress
  c:advance(1)
  eq(place(P), "zep", "the zeppelin starts the way to the work left in Silverpine")
  local e = Noir.Why.ForStep(SILVERPINE, "zep")
  ok(not (e and e.kind == "moot"), "not passed as moot")
end)

test("a journey goes on past a work step already done in its middle: its first move is not moot", function()
  -- Found by the simulator (task X1): "zeppelin to Durotar, into Orgrimmar, fly to Ratchet, (a hand-in already done),
  -- fly to Freewind Post" with work in Thousand Needles: the zeppelin was passed as moot because the journey stopped
  -- at the done hand-in, and the walk into Orgrimmar was then shown on the other continent.
  local c = sample3({ class = "MAGE", level = 6, zone = 14, x = 50, y = 14, saved = savedAt(SILVERPINE, "zepT"),
    afterLoad = function(client)
      local sec = client.G.Noir.Routes.Get("horde-undead").sections[3]
      sec.steps = {
        { id = "zepT", at = { zone = 14, x = 51, y = 13.9, r = 15 },
          lines = { { kind = "transport", mode = "zeppelin", at = { zone = 14, x = 51, y = 13.9, r = 15 }, to = { zone = 85, x = 60.6, y = 58.9 } } } },
        { id = "g1497", at = { zone = 1497, x = 63.3, y = 48.5, r = 20 }, lines = { { kind = "goto", at = { zone = 1497, x = 63.3, y = 48.5, r = 20 } } } },
        { id = "y11-384", at = { zone = 1497, x = 63.3, y = 48.5, r = 10 }, lines = { { kind = "fly", from = 11, to = 384 } } },
        { id = "a363x", at = { zone = 85, x = 58.9, y = 51.9, r = 8 }, lines = { { kind = "accept", quest = 363, npc = 1568 } } },
        { id = "y384-10", at = { zone = 85, x = 58.9, y = 51.9, r = 10 }, lines = { { kind = "fly", from = 384, to = 10 } } },
        { id = "a435x", at = { zone = 130, x = 56.2, y = 9.2, r = 10 }, lines = { { kind = "accept", quest = 435, npc = 1950 } } },
      }
    end })
  c:markCompleted(363)
  c:login()
  local Noir, P = c.G.Noir, c.G.Noir.Progress
  c:advance(1)
  eq(place(P), "zepT", "the zeppelin starts the way to the work left in Silverpine")
  local e = Noir.Why.ForStep(SILVERPINE, "zepT")
  ok(not (e and e.kind == "moot"), "not passed as moot")
end)

test("a move near the end of a section with no work left after it is not moot: it leads into the next section", function()
  -- Found by the simulator (task X1): "take the boat to Wetlands" with only a skipped hand-in after it in its section
  -- was passed as moot, and the next section began with a walk in Hillsbrad the character could not reach.
  local c = sample3({ class = "MAGE", level = 4, zone = 85, x = 50, y = 50, saved = savedAt(TIRISFAL, "zepX"),
    afterLoad = function(client)
      local sec = client.G.Noir.Routes.Get("horde-undead").sections[2]
      sec.steps = {
        { id = "zepX", at = { zone = 85, x = 60.7, y = 58.8, r = 15 },
          lines = { { kind = "transport", mode = "zeppelin", at = { zone = 85, x = 60.7, y = 58.8 }, to = { zone = 14, x = 50.8, y = 13.6, r = 50 } } } },
        { id = "a363x", at = { zone = 14, x = 50, y = 20, r = 8 }, lines = { { kind = "accept", quest = 363, npc = 1568 } } },
      }
    end })
  c:markCompleted(363)
  c:login()
  local Noir, P = c.G.Noir, c.G.Noir.Progress
  c:advance(1)
  eq(Noir.Guide.Current(), TIRISFAL)
  eq(place(P), "zepX", "the zeppelin is the way on")
  c:moveTo({ zone = 14, x = 50.8, y = 13.6 })
  c:advance(2)
  eq(Noir.Guide.Current(), SILVERPINE, "after the ride the section ends and the next one loads")
end)

test("a move at the end of a section is moot when the player already stands where the next section begins", function()
  -- Review of task X1: with no work left after it, a move leads into the next section only when that section begins
  -- somewhere the player is not; a joiner placed at the end of a section must not be sent on a pointless trip.
  local c = sample3({ class = "MAGE", level = 5, zone = 130, x = 45, y = 42, saved = savedAt(TIRISFAL, "zepX"),
    afterLoad = function(client)
      local sec = client.G.Noir.Routes.Get("horde-undead").sections[2]
      sec.steps = {
        { id = "zepX", at = { zone = 85, x = 60.7, y = 58.8, r = 15 },
          lines = { { kind = "transport", mode = "zeppelin", at = { zone = 85, x = 60.7, y = 58.8 }, to = { zone = 14, x = 50.8, y = 13.6, r = 50 } } } },
        { id = "a363x", at = { zone = 14, x = 50, y = 20, r = 8 }, lines = { { kind = "accept", quest = 363, npc = 1568 } } },
      }
    end })
  c:markCompleted(363)
  c:login()
  local Noir = c.G.Noir
  c:advance(2)
  eq(Noir.Guide.Current(), SILVERPINE, "Silverpine begins where the player stands: the zeppelin is passed")
  local e = Noir.Why.ForStep(TIRISFAL, "zepX")
  ok(e and e.kind == "moot", "the zeppelin is logged as moot")
end)

test("a move the player is already past on its journey is passed as moot", function()
  -- Found by the simulator (task X1): a warrior's hand-in in Alterac was passed (its quest missing), so the zeppelin
  -- there was moot and the character stayed in Durotar; "head into Tirisfal" and "the zeppelin to Durotar" were then
  -- shown to a character already standing where that way leads.
  local c = sample3({ class = "MAGE", level = 6, zone = 14, x = 50, y = 30, saved = savedAt(SILVERPINE, "g85x"),
    afterLoad = function(client)
      local sec = client.G.Noir.Routes.Get("horde-undead").sections[3]
      sec.steps = {
        { id = "g85x", at = { zone = 85, x = 60.6, y = 58.9, r = 20 }, lines = { { kind = "goto", at = { zone = 85, x = 60.6, y = 58.9, r = 20 } } } },
        { id = "zep14", at = { zone = 85, x = 60.6, y = 58.9, r = 15 },
          lines = { { kind = "transport", mode = "zeppelin", at = { zone = 85, x = 60.6, y = 58.9, r = 15 }, to = { zone = 14, x = 51, y = 13.9 } } } },
        { id = "g1637x", at = { zone = 1637, x = 45, y = 64, r = 20 }, lines = { { kind = "goto", at = { zone = 1637, x = 45, y = 64, r = 20 } } } },
        { id = "a435x", at = { zone = 1637, x = 50, y = 50, r = 10 }, lines = { { kind = "accept", quest = 435, npc = 1950 } } },
      }
    end })
  c:login()
  local Noir, P = c.G.Noir, c.G.Noir.Progress
  c:advance(1)
  eq(place(P), "g1637x", "in Durotar already: on to Orgrimmar")
  local e = Noir.Why.ForStep(SILVERPINE, "g85x")
  ok(e and e.kind == "moot", "the walk into Tirisfal is logged as moot")
  -- In Tirisfal the walk and the zeppelin still lead.
  local c2 = sample3({ class = "MAGE", level = 6, zone = 85, x = 50, y = 50, saved = savedAt(SILVERPINE, "g85x"),
    afterLoad = function(client)
      local sec = client.G.Noir.Routes.Get("horde-undead").sections[3]
      sec.steps = {
        { id = "g85x", at = { zone = 85, x = 60.6, y = 58.9, r = 20 }, lines = { { kind = "goto", at = { zone = 85, x = 60.6, y = 58.9, r = 20 } } } },
        { id = "zep14", at = { zone = 85, x = 60.6, y = 58.9, r = 15 },
          lines = { { kind = "transport", mode = "zeppelin", at = { zone = 85, x = 60.6, y = 58.9, r = 15 }, to = { zone = 14, x = 51, y = 13.9 } } } },
        { id = "a435x", at = { zone = 14, x = 50, y = 50, r = 10 }, lines = { { kind = "accept", quest = 435, npc = 1950 } } },
      }
    end })
  c2:login()
  c2:advance(1)
  eq(place(c2.G.Noir.Progress), "g85x")
end)

test("Jump goes back and forward without confirmation and logs it", function()
  local c, Noir, P = play({ class = "MAGE", level = 1 })
  local asked = 0
  Noir.Panel.Confirm = function() asked = asked + 1 end
  ok(P.Jump(9, "list"))
  eq(place(P), "l3@85")
  eq(Noir.Why.ForStep(DEATHKNELL, "l3@85").kind, "jump")
  ok(P.Jump(2, "back"))
  eq(place(P), "t363.a364.a376")
  eq(Noir.Why.ForStep(DEATHKNELL, "t363.a364.a376").kind, "jump")
  no(P.Jump(99, "list"), "no such step")
  eq(asked, 0, "no confirmation")
  eq(c:slashCount(), 0)
  -- Back goes to the nearest earlier step that is not done.
  c:acceptQuest(363)
  ok(P.Jump(5, "list"))
  ok(P.Back())
  eq(place(P), "a3901", "Rude Awakening is in the log: the first open step back is a3901")
end)

test("the end of a section loads the next section with no cleanup prompt", function()
  local c, Noir, P = play({ class = "MAGE", level = 3, saved = savedAt(DEATHKNELL, "g.road") })
  local sections = {}
  Noir.On("NOIR_SECTION", function(_, id, how) sections[#sections + 1] = id .. " " .. how end)
  c:advance(0.5)
  eq(place(P), "g.road")
  c:moveTo({ zone = 85, x = 38.2, y = 56.8 })
  c:advance(1)
  eq(sections, { TIRISFAL .. " next" })
  eq(Noir.Guide.Current(), TIRISFAL)
  eq((P.Place()), TIRISFAL)
  c:advance(5)
  eq(Noir.Cleanup.Read().shown, false, "no cleanup prompt for the automatic change")
  eq(c:offScreen(), {})
end)

test("the next section starts at its first step, not past a quest in the log further on", function()
  -- Spec 2.4.4: the new section starts at its saved place or its start, and done steps pass by themselves. Found by
  -- the simulator (task X1): placement from the quest log jumped over undone steps of the next section because a
  -- quest accepted earlier on the route is turned in further into it.
  local c, Noir, P = play({ class = "MAGE", level = 3, saved = savedAt(DEATHKNELL, "g.road") })
  c:acceptQuest(367, { title = "A New Plague", objectives = {} })
  c:advance(0.5)
  eq(place(P), "g.road")
  c:moveTo({ zone = 85, x = 38.2, y = 56.8 })
  c:advance(1)
  eq(Noir.Guide.Current(), TIRISFAL)
  eq(place(P), "a365", "the first step of the section, whose quest is not taken yet")
  for _, e in ipairs(Noir.Why.List()) do
    ok(not (e.section == TIRISFAL and e.kind == "place"), "no placement inside the next section: " .. tostring(e.text))
  end
end)

test("open reminders hold the place at the end of a section", function()
  local function reminderToEnd(client)
    local steps = client.G.Noir.Routes.Get("horde-undead").sections[1].steps
    steps[11].label = "road"
    steps[4].reminder = { ends = "road" }
  end
  local c = sample3({ class = "MAGE", level = 3, saved = savedAt(DEATHKNELL, "g.road"), afterLoad = reminderToEnd })
  c:acceptQuest(3901, QUEST3901)
  c:login()
  local Noir, P = c.G.Noir, c.G.Noir.Progress
  eq(kinds(P), { "reminder r3901", "current g.road" })
  c:moveTo({ zone = 85, x = 38.2, y = 56.8 })
  c:advance(1)
  eq(Noir.Guide.Current(), DEATHKNELL, "the reminder holds the place")
  eq(place(P), "g.road")
  c:progressQuest(3901, 1, 5)
  c:advance(1)
  eq(Noir.Guide.Current(), TIRISFAL, "the reminder is done: the next section")
end)

test("the last section says the route is complete", function()
  local c, Noir, P = play({ class = "MAGE", level = 8, saved = savedAt(SILVERPINE, "g14") })
  local done = 0
  Noir.On("NOIR_ROUTE_DONE", function() done = done + 1 end)
  c:advance(0.5)
  eq(place(P), "g14")
  no(P.Complete())
  c:takeChat()
  c:moveTo({ zone = 14, x = 52, y = 28 })
  c:advance(1)
  eq(done, 1)
  ok(P.Complete())
  eq(P.Cards(), {})
  has(c:chatText(), "end of the route")
  -- Spec 2.4.5: the window stays on the last step.
  local _, index, count, step = P.Place()
  eq({ index, step and step.id }, { count, "g14" })
  eq(P.StepState(count), "done")
  -- Still complete after a relog, far from the last step's place, and nothing is printed again.
  c:moveTo({ zone = 14, x = 40, y = 70 })
  local again = c:relog()
  local P2 = again.G.Noir.Progress
  again:advance(1)
  ok(P2.Complete(), "the finished route is remembered")
  eq(P2.Cards(), {})
  local _, index2, count2, step2 = P2.Place()
  eq({ index2, step2 and step2.id }, { count2, "g14" })
  no(again:chatText():find("end of the route", 1, true), "no second message")
  eq(again:slashCount(), 0)
end)

test("a finished section picked again by hand shows its last step", function()
  local c, Noir, P = play({ class = "MAGE", level = 3, saved = savedAt(DEATHKNELL, "g.road") })
  c:moveTo({ zone = 85, x = 38.2, y = 56.8 })
  c:advance(1)
  eq(Noir.Guide.Current(), TIRISFAL, "the end of Deathknell loaded the next section")
  c:moveTo({ zone = 85, x = 59, y = 52 })
  ok(Noir.Guide.Select(DEATHKNELL, "hand"))
  c:advance(1)
  eq(Noir.Guide.Current(), DEATHKNELL)
  local _, index, count = P.Place()
  eq({ place(P), index }, { "g.road", count }, "on the last step, not past it")
  eq(kinds(P), { "current g.road" })
  no(P.Complete())
end)

-- Spec 2.4 and 2.5: placement that lands just after the section's last step is the end of the section, never a
-- place with no step on it (the window would stay empty and the guide would stall).
test("a placement past the last step ends the route instead of stalling", function()
  local c = sample3({ class = "MAGE", level = 6, afterLoad = function(client)
    -- Silverpine up to the turn-in, without its accept: the turn-in's quest counts at the last step.
    local sec = client.G.Noir.Routes.Get("horde-undead").sections[3]
    local kept = {}
    for i = 1, 7 do
      if sec.steps[i].id ~= "a435" then kept[#kept + 1] = sec.steps[i] end
    end
    sec.steps = kept
  end })
  c:markCompleted(435)
  c:login()
  local Noir, P = c.G.Noir, c.G.Noir.Progress
  c:advance(3)
  eq(Noir.Guide.Current(), SILVERPINE, "the level and the quest log chose Silverpine")
  local _, index, count, step = P.Place()
  eq({ index, step and step.id }, { count, "t435" }, "the place stays on the last step")
  ok(P.Complete(), "the route is complete")
  local chat = c:chatText()
  has(chat, "end of the route")
  has(chat, "past its last step")
  no(chat:find("step " .. (count + 1), 1, true), "no step number past the end")
  eq(c:offScreen(), {})
end)

test("a placement past the last step of a section with a next section loads the next one", function()
  local c = sample3({ class = "MAGE", level = 2, afterLoad = function(client)
    local sec = client.G.Noir.Routes.Get("horde-undead").sections[1]
    sec.steps = { sec.steps[1], sec.steps[8] } -- a363, t3901
  end })
  c:markCompleted(3901)
  c:login()
  local Noir, P = c.G.Noir, c.G.Noir.Progress
  eq(Noir.Guide.Current(), TIRISFAL, "placement across the chain went past Deathknell")
  -- Picked by hand with no saved place in it: placement inside Deathknell lands past its last step.
  ok(Noir.Guide.Select(DEATHKNELL, "hand"))
  c:advance(3)
  eq(Noir.Guide.Current(), TIRISFAL, "the end of the section loaded the next one")
  eq((P.Place()), TIRISFAL)
  local _, _, _, step = P.Place()
  ok(step ~= nil, "a step is current")
  no(P.Complete())
end)

test("catching up past the last step of the route ends it instead of stalling", function()
  local c = sample3({ class = "MAGE", level = 6, saved = savedAt(SILVERPINE, "z130"), afterLoad = function(client)
    local sec = client.G.Noir.Routes.Get("horde-undead").sections[3]
    local function q(kind, quest) return { id = kind .. quest, lines = { { kind = kind, quest = quest, npc = 1950 } } } end
    sec.steps = { sec.steps[1], q("accept", 435), q("accept", 436), q("accept", 437), q("turnin", 438) }
  end })
  for _, quest in ipairs({ 435, 436, 437, 438 }) do c:markCompleted(quest) end
  c:login()
  c:advance(3)
  local P = c.G.Noir.Progress
  local _, index, count, step = P.Place()
  eq({ index, step and step.id }, { count, "turnin438" })
  ok(P.Complete(), "the route is complete")
  local chat = c:chatText()
  has(chat, "Moved ahead to 5-6 Silverpine Forest")
  has(chat, "end of the route")
  no(chat:find("step 6", 1, true), "no step number past the end")
end)

test("a section with no step for the character is passed with a reason", function()
  local c = sample3({ class = "MAGE", level = 3, saved = savedAt(DEATHKNELL, "g.road"), afterLoad = function(client)
    local sec = client.G.Noir.Routes.Get("horde-undead").sections[2]
    for _, step in ipairs(sec.steps) do step.when = { class = "ROGUE" } end
  end })
  c:login()
  local Noir = c.G.Noir
  c:moveTo({ zone = 85, x = 38.2, y = 56.8 })
  c:advance(2)
  eq(Noir.Guide.Current(), SILVERPINE, "Tirisfal has nothing for a mage: passed to the next section")
  local found
  for _, e in ipairs(Noir.Why.List()) do
    if e.section == TIRISFAL and e.kind == "section" then found = e end
  end
  ok(found, "the why-log says Tirisfal was passed")
  has(found.text, "no step")
end)

test("a line passed by its skipIfMissing option is logged", function()
  local c, Noir, P = play({ class = "MAGE", level = 1, afterLoad = function(client)
    client.G.Noir.Routes.Get("horde-undead").sections[1].steps[2].lines[1].skipIfMissing = true
  end })
  c:acceptQuest(363)
  c:advance(0.5)
  eq(place(P), "t363.a364.a376")
  c:abandonQuest(363)
  c:advance(0.5)
  eq(currentCard(P).lines[1].state, "skip")
  local e = Noir.Why.ForStep(DEATHKNELL, "t363.a364.a376")
  ok(e, "the skipped line has a reason")
  eq(e.kind, "condition")
  has(e.text, "not in your quest log")
  c:acceptQuest(364)
  c:acceptQuest(376)
  c:advance(0.5)
  eq(place(P), "a3901")
  ok(Noir.Why.ForStep(DEATHKNELL, "t363.a364.a376"), "still there once the step passed")
end)

test("an accept passed because its ifDone quest is not handed in is logged", function()
  -- Review 2 of task X1 (never skip silently): the accept is not taken, so the line must say why.
  local c, Noir, P = play({ class = "MAGE", level = 1, afterLoad = function(client)
    client.G.Noir.Routes.Get("horde-undead").sections[1].steps[2].lines[3].ifDone = 9999
  end })
  c:acceptQuest(363)
  c:advance(0.5)
  eq(place(P), "t363.a364.a376")
  c:completeObjectives(363)
  c:turnInQuest(363)
  c:acceptQuest(364)
  c:advance(0.5)
  eq(place(P), "a3901")
  local e = Noir.Why.ForStep(DEATHKNELL, "t363.a364.a376")
  ok(e, "the passed accept has a reason")
  eq(e.kind, "condition")
  has(e.text, "only wanted once")
end)

test("a step of only notes and markers passes with a reason", function()
  local c, Noir, P = play({ class = "MAGE", level = 5, saved = savedAt(SILVERPINE, "tg1950") })
  c:advance(1)
  eq(place(P), "l6@130")
  local e = Noir.Why.ForStep(SILVERPINE, "tg1950")
  ok(e, "the passive step is logged")
  eq(e.kind, "done")
  has(e.text, "nothing to do")
end)

test("signals are not raised within 1 s of a place change", function()
  local c, Noir, P = play({ class = "MAGE", level = 1 })
  local steps, objectives = {}, {}
  Noir.On("NOIR_STEP_DONE", function(_, section, id) steps[#steps + 1] = id end)
  Noir.On("NOIR_OBJECTIVE_DONE", function(_, section, id, line) objectives[#objectives + 1] = id .. ":" .. line end)
  c:advance(2)
  c:acceptQuest(363)
  c:advance(0.2)
  eq(steps, { "a363" }, "done 2 s after the last place change: signalled")
  c:turnInQuest(363)
  c:acceptQuest(364)
  c:acceptQuest(376)
  c:advance(0.2)
  eq(place(P), "a3901")
  eq(steps, { "a363" }, "done within 1 s of the place change: no signal")
  ok(P.Jump(5, "list"))
  c:progressQuest(364, 1, 8)
  c:advance(0.2)
  eq(objectives, {}, "within 1 s of the jump: no signal")
  c:advance(2)
  c:progressQuest(364, 2, 8)
  c:advance(0.2)
  eq(objectives, { "o364.o376:2" })
end)

test("the quest tracker follows the current quest", function()
  local c = sample3({ class = "MAGE", level = 2, saved = savedAt(DEATHKNELL, "o364.o376") })
  c:markCompleted(363)
  c:acceptQuest(364)
  c:acceptQuest(376)
  c:login()
  c:advance(0.5)
  eq(place(c.G.Noir.Progress), "o364.o376")
  eq(c.watched[364], true)
  eq(c.watched[376], true)
end)

test("the place is saved by step id and survives a relog; an edited section finds the step by id", function()
  local c, Noir, P = play({ class = "MAGE", level = 1 })
  ok(P.Jump(9, "list"))
  eq(Noir.char.guide.places[DEATHKNELL].step, "l3@85")
  local again = c:relog()
  local id, index = place(again.G.Noir.Progress)
  eq({ id, index }, { "l3@85", 9 })
  -- A new step at the top of the section moves every step one down: the place is found by its id.
  local third = again:relog({ afterLoad = function(client)
    local steps = client.G.Noir.Routes.Get("horde-undead").sections[1].steps
    table.insert(steps, 1, { id = "intro", lines = { { kind = "manual", text = "Read the intro." } } })
  end })
  id, index = place(third.G.Noir.Progress)
  eq({ id, index }, { "l3@85", 10 })
end)

test("Lookahead, Steps and StepState describe the section around the place", function()
  local c, _, P = play({ class = "MAGE", level = 1 })
  eq(#P.Steps(), 10, "a mage's Deathknell steps")
  eq(P.Lookahead().id, "t363.a364.a376")
  ok(P.Jump(5, "list"))
  eq(P.StepState(5), "current")
  eq(P.StepState(9), "ahead")
  eq(P.StepState(1), "behind", "not done and before the place")
  c:acceptQuest(363)
  eq(P.StepState(1), "done")
  eq(P.StepState(2), "reminder", "the detour for the missing quests is on screen")
end)
