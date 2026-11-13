-- Noir Guides, GPLv3. See LICENSE.
-- Lines: when each kind of line is done, the skip conditions of a step and the places a step shows (plan task E3,
-- spec 3.2, 3.5, 3.7, 3.8). One test per row of the Lines table of "Route format 3". Driven by game events only.
use("tools/test-lua/sample/helper.lua")

-- Tirisfal Glades (area 85, map 1420) is 2400 by 1600 yards in the mock world: 1% of x is 24 yards, 1% of y 16.

local function play(opts)
  local c = sample3(opts):login()
  return c, c.G.Noir, c.G.Noir.Lines
end

-- A step holding these lines, and the state of its line i (default 1) for a step current since `since`.
local function stepOf(lines, extra)
  local step = { id = "s", n = 1, lines = lines }
  for k, v in pairs(extra or {}) do step[k] = v end
  return step
end

-- The professions part of Data/Professions.lua, which the sample data leaves out.
local function professionData(Noir)
  Noir.Data.professions = { [186] = { name = "Mining", kind = "primary" }, [171] = { name = "Alchemy", kind = "primary" } }
  Noir.Data.professionLines = { [2946] = 186, [2937] = 171 }
end

local function check(Lines, step, since, i, ctx)
  ctx = ctx or {}
  ctx.since = since
  return Lines.Check(step.lines[i or 1], step, ctx)
end

test("the constants of the plan", function()
  local _, _, Lines = play()
  eq(Lines.ACCEPT_GRACE, 2)
  eq(Lines.TURNIN_GRACE, 5)
  eq(Lines.FLY_GRACE, 1.5)
  eq(Lines.FLY_ARRIVE_YARDS, 60)
  eq(Lines.RANK_CAP, { 75, 150, 225, 300 })
  eq(Lines.RANK_GATE, { 0, 50, 125, 200 })
end)

test("Applies is the guide's one evaluator of conditions", function()
  local _, Noir, Lines = play({ class = "MAGE" })
  eq(Lines.Applies, Noir.Guide.When)
end)

test("accept is done when the quest is in the log, handed in, or accepted up to 2 s before the step became current, and not 3 s before", function()
  local c, Noir, Lines = play()
  local step = stepOf({ { kind = "accept", quest = 364, npc = 1569 } })
  eq((check(Lines, step, c.now)), "todo")
  c:acceptQuest(364)
  local state, evidence = check(Lines, step, c.now)
  eq(state, "done")
  ok(evidence, "done says why")
  c:abandonQuest(364)
  -- Accepted, then dropped: only the accept event remains.
  local at = c.now
  eq((check(Lines, step, at + 2)), "done", "an accept 2 s before the step counts")
  eq((check(Lines, step, at + 3)), "todo", "an accept 3 s before the step does not")
  eq((check(Lines, step, at - 10)), "done", "an accept during the step counts")
  c:acceptQuest(364)
  c:completeObjectives(364)
  c:turnInQuest(364)
  eq((check(Lines, step, c.now + 100)), "done", "handed in")
  eq(Lines.Active(step.lines[1]), true)
end)

test("accept with ifDone is passed at once, with its reason, when that quest is not handed in", function()
  local c, _, Lines = play()
  local step = stepOf({ { kind = "accept", quest = 376, ifDone = 363 } })
  local state, evidence = check(Lines, step, c.now)
  eq(state, "skip", "not taken: a skip, which the why-log keeps (review 2 of task X1)")
  has(evidence, "Rude Awakening")
  c:markCompleted(363)
  eq((check(Lines, step, c.now)), "todo", "once 363 is handed in the accept is wanted")
  c:acceptQuest(376)
  eq((check(Lines, step, c.now)), "done")
end)

test("accept with ifDone waits while an earlier line of its step still hands that quest in", function()
  -- Found by the simulator (task X1): "hand in A, accept B (ifDone A)" in one step would otherwise pass B the moment
  -- the step showed, before A was handed in.
  local c, _, Lines = play()
  local step = stepOf({ { kind = "turnin", quest = 363 }, { kind = "accept", quest = 376, ifDone = 363 } })
  c:acceptQuest(363)
  local state = Lines.Check(step.lines[2], step, { since = c.now })
  eq(state, "todo", "363 is in the log: it will be handed in, then 376 is wanted")
  c:turnInQuest(363)
  eq(Lines.Check(step.lines[2], step, { since = c.now }), "todo")
end)

test("accept with ifDone waits while an earlier open line of its step still accepts that quest", function()
  -- Found by the simulator (task X1): "accept A, hand in A, accept B (ifDone A)" in one step passed B (and latched it)
  -- the moment the step showed, before A was even accepted, and B's chain was lost.
  local c, _, Lines = play()
  local step = stepOf({ { kind = "accept", quest = 364 }, { kind = "turnin", quest = 364 }, { kind = "accept", quest = 376, ifDone = 364 } })
  eq(Lines.Check(step.lines[3], step, { since = c.now }), "todo", "364 is accepted on this step first")
  c:acceptQuest(364)
  c:completeObjectives(364)
  c:turnInQuest(364)
  eq(Lines.Check(step.lines[3], step, { since = c.now }), "todo", "364 handed in: 376 is wanted")
  -- The earlier accept is passed itself (its own ifDone is not handed in): 376 will not be wanted either.
  local gated = stepOf({ { kind = "accept", quest = 363, ifDone = 9999 }, { kind = "accept", quest = 376, ifDone = 363 } })
  eq(Lines.Check(gated.lines[2], gated, { since = c.now }), "skip")
end)

test("accept with ifDone is passed at once while that quest is in the log but no line of its step hands it in", function()
  -- Review of task X1: a joiner still carrying A, whose hand-in lies in an earlier section, must not meet an accept of
  -- B that waits for ever (the game will not offer B before A is handed in). Route format 3: done at once when A is
  -- not handed in.
  local c, _, Lines = play()
  c:acceptQuest(363)
  local step = stepOf({ { kind = "accept", quest = 376, ifDone = 363 } })
  local state, evidence = check(Lines, step, c.now)
  eq(state, "skip")
  has(evidence, "Rude Awakening")
  local bundled = stepOf({ { kind = "accept", quest = 364 }, { kind = "accept", quest = 376, ifDone = 363 } })
  eq(Lines.Check(bundled.lines[2], bundled, { since = c.now }), "skip", "another line of the step does not hand 363 in")
end)

test("accept with ifDone is passed at once when the earlier hand-in of that quest on its step is passed", function()
  -- A joiner who never took A: the hand-in of A (skipIfMissing) is passed, and B is not wanted either.
  local c, _, Lines = play()
  local step = stepOf({ { kind = "turnin", quest = 363, skipIfMissing = true }, { kind = "accept", quest = 376, ifDone = 363 } })
  eq(Lines.Check(step.lines[1], step, { since = c.now }), "skip")
  eq(Lines.Check(step.lines[2], step, { since = c.now }), "skip")
end)

test("accept with ifDone waits while the earlier hand-in of that quest on its step is missing and waits on a detour", function()
  -- Review 2 of task X1: a hand-in of A in state "missing" (no skipIfMissing) waits for a detour to A's accept and
  -- hands A in after it, so B must wait too instead of being latched as passed and lost.
  local c, _, Lines = play()
  local step = stepOf({ { kind = "turnin", quest = 363 }, { kind = "accept", quest = 376, ifDone = 363 } })
  eq(Lines.Check(step.lines[1], step, { since = c.now }), "missing")
  eq(Lines.Check(step.lines[2], step, { since = c.now }), "todo", "363 will be handed in after the detour")
end)

test("an accept with one line per any-of prerequisite is wanted once any one of them is handed in", function()
  -- Review 2 of task X1: a quest that either of two quests unlocks gets one accept line per prerequisite, each with its
  -- own ifDone (planner, sections.js). The line of the quest handed in waits for the accept; the other is passed.
  local c, _, Lines = play()
  local step = stepOf({ { kind = "accept", quest = 376, ifDone = 363 }, { kind = "accept", quest = 376, ifDone = 364 } })
  eq(Lines.Check(step.lines[1], step, { since = c.now }), "skip", "neither handed in: not offered")
  eq(Lines.Check(step.lines[2], step, { since = c.now }), "skip")
  c:acceptQuest(364)
  c:completeObjectives(364)
  c:turnInQuest(364)
  eq(Lines.Check(step.lines[1], step, { since = c.now }), "skip", "363 is still not handed in")
  eq(Lines.Check(step.lines[2], step, { since = c.now }), "todo", "364 handed in: the game offers 376")
  c:acceptQuest(376)
  eq(Lines.Check(step.lines[2], step, { since = c.now }), "done")
  -- Both handed in: the first line asks for the accept, the second is hidden so the card shows it once.
  local c2, _, Lines2 = play()
  for _, q in ipairs({ 363, 364 }) do
    c2:acceptQuest(q)
    c2:completeObjectives(q)
    c2:turnInQuest(q)
  end
  eq(Lines2.Check(step.lines[1], step, { since = c2.now }), "todo")
  eq(Lines2.Check(step.lines[2], step, { since = c2.now }), "hidden")
  c2:acceptQuest(376)
  eq(Lines2.Check(step.lines[1], step, { since = c2.now }), "done")
  eq(Lines2.Check(step.lines[2], step, { since = c2.now }), "hidden")
end)

test("turnin is done on a hand-in up to 5 s before the step became current, and not 6 s before", function()
  local c, Noir, Lines = play()
  local step = stepOf({ { kind = "turnin", quest = 364, npc = 1569 } })
  eq((check(Lines, step, c.now)), "missing", "neither in the log nor handed in")
  c:acceptQuest(364)
  eq((check(Lines, step, c.now)), "todo")
  c:completeObjectives(364)
  eq((check(Lines, step, c.now)), "todo", "complete is not handed in")
  c:turnInQuest(364)
  local at = c.now
  eq((check(Lines, step, at + 100)), "done", "flagged handed in")
  -- A repeatable quest is not flagged as handed in: only the hand-in event counts.
  c.s.completed[364] = nil
  Noir.State.completed[364] = nil
  eq((check(Lines, step, at + 5)), "done", "a hand-in 5 s before the step counts")
  eq((check(Lines, step, at + 6)), "missing", "a hand-in 6 s before the step does not")
end)

test("turnin with skipIfMissing completes with a reason when the quest is not in the log", function()
  local c, _, Lines = play()
  local step = stepOf({
    { kind = "turnin", quest = 365, skipIfMissing = true },
    { kind = "turnin", quest = 364, skipIfIncomplete = true },
  })
  local state, evidence = check(Lines, step, c.now, 1)
  eq(state, "skip")
  has(evidence, "Fields of Grief")
  c:acceptQuest(364)
  local s2, e2 = check(Lines, step, c.now, 2)
  eq(s2, "skip", "in the log but not ready")
  has(e2, "The Mindless Ones")
  c:completeObjectives(364)
  eq((check(Lines, step, c.now, 2)), "todo", "ready: the hand-in is wanted")
  c:turnInQuest(364)
  eq((check(Lines, step, c.now, 2)), "done")
end)

test("objective follows its own counter and cap, and a quest with no objectives reads 0/1", function()
  local c, Noir, Lines = play()
  local step = stepOf({
    { kind = "objective", quest = 364, index = 1, npc = 1501 },
    { kind = "objective", quest = 364, index = 2, npc = 1502, cap = 3 },
    { kind = "objective", quest = 364, index = 3, skipIfMissing = true },
  })
  eq((check(Lines, step, c.now, 1)), "missing")
  local s3 = check(Lines, step, c.now, 3)
  eq(s3, "skip", "skipIfMissing")
  c:acceptQuest(364)
  local state, _, counter = check(Lines, step, c.now, 1)
  eq(state, "todo")
  eq({ counter.have, counter.need }, { 0, 8 })
  eq({ counter[1], counter[2] }, { 0, 8 }, "also as a pair")
  c:progressQuest(364, 1, 8)
  state, _, counter = check(Lines, step, c.now, 1)
  eq(state, "done")
  eq({ counter.have, counter.need }, { 8, 8 })
  eq((check(Lines, step, c.now, 2)), "todo", "the other objective has its own counter")
  c:progressQuest(364, 2, 2)
  state, _, counter = check(Lines, step, c.now, 2)
  eq({ state, counter.have, counter.need }, { "todo", 2, 3 }, "the cap is the need")
  c:progressQuest(364, 2, 3)
  eq((check(Lines, step, c.now, 2)), "done", "the count reached the cap")
  c:turnInQuest(364)
  state, _, counter = check(Lines, step, c.now, 1)
  eq(state, "done", "handed in")
  -- A quest without objectives, complete on the modern API.
  local m, _, MLines = play({ api = "modern" })
  local none = stepOf({ { kind = "objective", quest = 363, index = 1 } })
  m:acceptQuest(363, { title = "Rude Awakening", objectives = {} })
  local ms, _, mc = check(MLines, none, m.now)
  eq(ms, "done", "complete with no objectives")
  eq({ mc.have, mc.need }, { 1, 1 })
  local cl, _, CLines = play()
  cl:acceptQuest(363, { title = "Rude Awakening", objectives = {} })
  local cs, _, cc = check(CLines, none, cl.now)
  eq({ cs, cc.have, cc.need }, { "todo", 0, 1 }, "not yet complete reads 0/1")
end)

test("collect counts bags and is full when its quest is complete; count 0 hides it", function()
  local c, _, Lines = play()
  local step = stepOf({
    { kind = "collect", item = 2834, count = 4, quest = 376 },
    { kind = "collect", item = 2834, count = 0 },
  })
  local state, _, counter = check(Lines, step, c.now)
  eq({ state, counter.have, counter.need }, { "todo", 0, 4 })
  c:giveItem(2834, 3)
  state, _, counter = check(Lines, step, c.now)
  eq({ state, counter.have, counter.need }, { "todo", 3, 4 })
  c:giveItem(2834, 2)
  state, _, counter = check(Lines, step, c.now)
  eq({ state, counter.have, counter.need }, { "done", 5, 4 })
  c:takeItem(2834, 5)
  c:acceptQuest(376)
  c:completeObjectives(376)
  state, _, counter = check(Lines, step, c.now)
  eq({ state, counter.have, counter.need }, { "done", 4, 4 }, "shown full when its quest is complete")
  eq((check(Lines, step, c.now, 2)), "hidden")
end)

test("goto completes inside its radius, is passive without one, and in the zone when x and y are 0", function()
  local c, _, Lines = play({ zone = 85, x = 30, y = 70 })
  local step = stepOf({
    { kind = "goto", at = { zone = 85, x = 38.2, y = 56.8, r = 15 } },
    { kind = "goto", at = { zone = 85, x = 38.2, y = 56.8 } },
    { kind = "goto", at = { zone = 130, x = 0, y = 0, r = 5 } },
    { kind = "goto", at = { zone = 85, x = 38.2, y = 56.8, r = 0 } },
  })
  eq(Lines.Active(step.lines[1]), true)
  eq(Lines.Active(step.lines[2]), false, "no radius: passive")
  eq(Lines.Active(step.lines[4]), false, "radius 0: passive")
  eq((check(Lines, step, c.now, 1)), "todo")
  c:moveTo({ zone = 85, x = 38.7, y = 56.8 }) -- 12 yards east
  eq((check(Lines, step, c.now, 1)), "done")
  eq(Lines.Arrived(step.lines[1].at), true)
  c:moveTo({ zone = 85, x = 38.2, y = 57.8 }) -- 16 yards south
  eq((check(Lines, step, c.now, 1)), "todo")
  eq(Lines.Arrived(step.lines[1].at), false)
  eq((check(Lines, step, c.now, 2)), "done", "a passive line counts as done")
  eq(Lines.Arrived(step.lines[2].at), false, "without a radius it never arrives")
  eq((check(Lines, step, c.now, 3)), "todo")
  eq(Lines.Arrived(step.lines[3].at), false)
  c:moveTo({ zone = 130, x = 80, y = 80 })
  eq((check(Lines, step, c.now, 3)), "done", "anywhere in the zone")
  c:moveTo({ hidden = true })
  eq(Lines.Arrived(step.lines[1].at), nil, "no position here")
end)

test("getflight completes on a known node or the discovery message", function()
  local c, _, Lines = play({ zone = 85, x = 58, y = 51 })
  local step = stepOf({ { kind = "getflight", node = 384, npc = 4551 } })
  eq((check(Lines, step, c.now)), "todo")
  c:discoverFlight(384) -- the message, near the node
  eq((check(Lines, step, c.now)), "done")
  -- Far from any node the message cannot tell which; during the step it still counts.
  local f, _, FLines = play({ zone = 130, x = 10, y = 10 })
  local fp = stepOf({ { kind = "getflight", node = 10 } })
  local since = f.now
  f:advance(1)
  f:discoverFlight(10)
  eq(f.G.Noir.State.KnowsFlight(10), false, "the node could not be told")
  eq((check(FLines, fp, since)), "done", "the discovery message arrived during the step")
  eq((check(FLines, fp, f.now + 1)), "todo", "a message before the step does not count")
  -- Known before the addon saw it: the flight map tells.
  local k, _, KLines = play({ zone = 85, x = 58.9, y = 51.9 })
  k:knowFlight(10)
  local fp10 = stepOf({ { kind = "getflight", node = 10 } })
  eq((check(KLines, fp10, k.now)), "todo")
  k:openTaxi(384)
  eq((check(KLines, fp10, k.now)), "done")
end)

test("fly completes when control is lost within 1.5 s of choosing, or at the destination", function()
  local c, Noir, Lines = play({ zone = 85, x = 58.9, y = 51.9, takeoffLag = 10 })
  local step = stepOf({ { kind = "fly", from = 384, to = 10 } })
  c:knowFlight(10)
  local since = c.now
  c:openTaxi(384)
  eq((check(Lines, step, since)), "todo")
  c.G.TakeTaxiNode(Noir.State.taxiSlots[10])
  c:advance(2)
  c:fire("PLAYER_CONTROL_LOST") -- 2 s after choosing, and not on a flight
  eq((check(Lines, step, since)), "todo", "control lost 2 s after choosing does not count")
  local d, DNoir, DLines = play({ zone = 85, x = 58.9, y = 51.9, takeoffLag = 10 })
  d:knowFlight(10)
  local dsince = d.now
  d:openTaxi(384)
  d.G.TakeTaxiNode(DNoir.State.taxiSlots[10])
  d:advance(1)
  d:fire("PLAYER_CONTROL_LOST")
  eq((check(DLines, step, dsince)), "done", "control lost 1 s after choosing")
  -- On a flight that started during the step.
  local f, FNoir, FLines = play({ zone = 85, x = 58.9, y = 51.9 })
  f:knowFlight(10)
  local fsince = f.now
  f:openTaxi(384)
  f.G.TakeTaxiNode(FNoir.State.taxiSlots[10])
  eq((check(FLines, step, fsince)), "done", "on the flight")
  eq((check(FLines, step, f.now + 1)), "todo", "a flight that started before the step")
  f:landFlight()
  eq((check(FLines, step, f.now + 1)), "done", "within 60 yards of the destination's flight master")
  f:moveTo({ zone = 130, x = 45.6 + 4, y = 42.6 }) -- 72 yards away
  eq((check(FLines, step, f.now + 1)), "todo")
end)

test("transport completes in the destination zone", function()
  local c, _, Lines = play({ zone = 85, x = 60.7, y = 58.8 })
  local step = stepOf({
    { kind = "transport", mode = "zeppelin", at = { zone = 85, x = 60.7, y = 58.8 }, to = { zone = 14, x = 50.8, y = 13.6, r = 50 } },
    { kind = "transport", mode = "boat", at = { zone = 85, x = 10, y = 10 }, to = { zone = 85, x = 20, y = 10, r = 50 } },
  })
  eq((check(Lines, step, c.now, 1)), "todo")
  c:moveTo({ zone = 14, x = 90, y = 90 })
  eq((check(Lines, step, c.now, 1)), "done", "anywhere in the destination zone")
  c:moveTo({ zone = 85, x = 10, y = 10 })
  eq((check(Lines, step, c.now, 2)), "todo", "both ends in one zone: within to.r")
  c:moveTo({ zone = 85, x = 21, y = 10 })
  eq((check(Lines, step, c.now, 2)), "done")
end)

test("sethearth completes on the bind at the step's inn", function()
  local c, _, Lines = play({ zone = 85, x = 61.7, y = 52.0 })
  local step = stepOf({ { kind = "sethearth", npc = 5688 } }, { at = { zone = 85, x = 61.7, y = 52.0, r = 10 } })
  local since = c.now
  eq((check(Lines, step, since)), "todo")
  c:advance(1)
  c:bindHearth("Brill")
  eq((check(Lines, step, since)), "done", "bound during the step")
  eq((check(Lines, step, c.now + 100)), "done", "already bound there")
  local far = stepOf({ { kind = "sethearth" } }, { at = { zone = 130, x = 45, y = 42, r = 10 } })
  eq((check(Lines, far, c.now + 100)), "todo", "bound at another inn")
  -- A bind somewhere else during the step is not this inn's.
  local o, _, OLines = play({ zone = 85, x = 20, y = 20 })
  local osince = o.now
  o:bindHearth("Elsewhere")
  eq((check(OLines, step, osince)), "todo")
end)

test("hearth completes on a hearthstone or Astral Recall cast", function()
  local c, _, Lines = play({ zone = 130, x = 50, y = 50 })
  local step = stepOf({ { kind = "hearth", to = { zone = 85, x = 61.7, y = 52.0, r = 20 } } })
  local since = c.now
  eq((check(Lines, step, since)), "todo")
  c:advance(1)
  c:castSpell(8690) -- the Hearthstone's spell; the mock knows no bind position, so the player stays
  eq((check(Lines, step, since)), "done")
  eq((check(Lines, step, c.now + 1)), "todo", "a cast before the step does not count")
  c:advance(5)
  c:castSpell(556)
  eq((check(Lines, step, c.now)), "done", "Astral Recall")
  c:moveTo({ zone = 85, x = 61.7, y = 52.5 })
  eq((check(Lines, step, c.now + 100)), "done", "at the destination")
end)

test("grind completes at the level and percent", function()
  local c, _, Lines = play({ level = 2 })
  local step = stepOf({ { kind = "grind", level = 3, percent = 30 }, { kind = "grind", level = 3 } })
  local state, _, counter = check(Lines, step, c.now, 2)
  eq(state, "todo")
  eq({ counter.have, counter.need }, { 0, 800 }, "toward level 3: level 2's experience")
  c:gainXP(400)
  state, _, counter = check(Lines, step, c.now, 2)
  eq({ state, counter.have, counter.need }, { "todo", 400, 800 })
  c:gainXP(400)
  eq((check(Lines, step, c.now, 2)), "done", "level 3 reached")
  state, _, counter = check(Lines, step, c.now, 1)
  eq({ state, counter.have, counter.need }, { "todo", 0, 360 }, "30% of level 3's 1200")
  c:gainXP(359)
  eq((check(Lines, step, c.now, 1)), "todo")
  c:gainXP(1)
  eq((check(Lines, step, c.now, 1)), "done")
  c:setLevel(4)
  eq((check(Lines, step, c.now, 1)), "done", "above the level")
end)

test("train completes when the spell is known and when a profession cap covers the rank, and skips below the rank's gate of 50, 125 or 200", function()
  local c, Noir, Lines = play({ class = "MAGE" })
  professionData(Noir)
  local step = stepOf({
    { kind = "train", spell = 1459, npc = 2124 },
    { kind = "train", skill = 186, rank = 1 },
    { kind = "train", skill = 186, rank = 2 },
    { kind = "train", skill = 186, rank = 3 },
    { kind = "train", skill = 186, rank = 4 },
  })
  eq((check(Lines, step, c.now, 1)), "todo")
  c:learnSpell(1459)
  eq((check(Lines, step, c.now, 1)), "done")
  eq((check(Lines, step, c.now, 2)), "todo", "apprentice has no gate")
  local state, evidence = check(Lines, step, c.now, 3)
  eq(state, "skip")
  eq(evidence, "your Mining skill is below 50")
  c:setProfession(186, "Mining", 1, 75)
  eq((check(Lines, step, c.now, 2)), "done", "the cap 75 covers apprentice")
  c:setProfession(186, "Mining", 49, 75)
  eq((check(Lines, step, c.now, 3)), "skip")
  c:setProfession(186, "Mining", 50, 75)
  eq((check(Lines, step, c.now, 3)), "todo", "at the gate of 50")
  c:setProfession(186, "Mining", 60, 150)
  eq((check(Lines, step, c.now, 3)), "done")
  state, evidence = check(Lines, step, c.now, 4)
  eq({ state, evidence }, { "skip", "your Mining skill is below 125" })
  c:setProfession(186, "Mining", 125, 150)
  eq((check(Lines, step, c.now, 4)), "todo")
  state, evidence = check(Lines, step, c.now, 5)
  eq({ state, evidence }, { "skip", "your Mining skill is below 200" })
  c:setProfession(186, "Mining", 200, 225)
  eq((check(Lines, step, c.now, 5)), "todo")
  c:setProfession(186, "Mining", 200, 300)
  eq((check(Lines, step, c.now, 5)), "done")
  -- Forever's tier line of a profession counts as the profession.
  local t, TNoir, TLines = play()
  professionData(TNoir)
  t:setProfession(2946, "Mining", 10, 75)
  eq((check(TLines, step, t.now, 2)), "done", "the tier line 2946 is Mining")
end)

test("a skill line counts the profession's skill up to its value and is hidden while the profession is neither learned nor planned", function()
  local c, Noir, Lines = play()
  professionData(Noir)
  local step = stepOf({ { kind = "skill", skill = 186, value = 50 } })
  eq(Lines.Active(step.lines[1]), true)
  eq((check(Lines, step, c.now)), "hidden", "no Mining, none planned")
  Noir.Professions.SetPlanned(186, true)
  local state, evidence, counter = check(Lines, step, c.now)
  eq({ state, evidence, counter.have, counter.need }, { "todo", nil, 0, 50 }, "planned, not learned yet")
  c:setProfession(186, "Mining", 12, 75)
  state, evidence, counter = check(Lines, step, c.now)
  eq({ state, counter[1], counter[2], counter.have, counter.need }, { "todo", 12, 50, 12, 50 })
  c:setProfession(186, "Mining", 49, 75)
  eq((check(Lines, step, c.now)), "todo")
  c:setProfession(186, "Mining", 50, 75)
  state, evidence, counter = check(Lines, step, c.now)
  eq({ state, evidence, counter.have, counter.need }, { "done", "skill reached", 50, 50 })
  c:setProfession(186, "Mining", 70, 75)
  state, evidence, counter = check(Lines, step, c.now)
  eq({ state, counter.have }, { "done", 50 }, "the counter stops at the value")
  -- Forever's tier line of the profession counts, as for the train line and the skill condition.
  local t, TNoir, TLines = play()
  professionData(TNoir)
  t:setProfession(2946, "Mining", 30, 75)
  state, evidence, counter = check(TLines, step, t.now)
  eq({ state, counter.have }, { "todo", 30 })
end)

test("a class trainer visit completes when that trainer's window opens and closes at or above its level, and not below it", function()
  local c, _, Lines = play({ class = "ROGUE", level = 1 })
  local step = stepOf({ { kind = "train", class = "ROGUE", level = 2, npc = 2122 } })
  local since = c.now
  c:openTrainer(2122, {})
  c:closeTrainer()
  eq((check(Lines, step, since)), "todo", "below the level")
  c:advance(1)
  c:setLevel(2)
  eq((check(Lines, step, since)), "todo", "the visit was before reaching the level")
  c:advance(1)
  c:openTrainer(9999, {})
  c:closeTrainer()
  eq((check(Lines, step, since)), "todo", "another trainer")
  c:openTrainer(2122, {})
  eq((check(Lines, step, since)), "todo", "open, not yet closed")
  c:advance(3)
  c:closeTrainer()
  eq((check(Lines, step, since)), "done")
  -- Level reached before this session: a visit since the step became current counts.
  local r, _, RLines = play({ class = "ROGUE", level = 5 })
  local rsince = r.now
  r:advance(1)
  r:openTrainer(2122, {})
  r:closeTrainer()
  eq((check(RLines, step, rsince)), "done")
  eq((check(RLines, step, r.now + 1)), "todo", "a visit before the step")
end)

test("vendor completes when the merchant window closes after opening", function()
  local c, _, Lines = play()
  local step = stepOf({ { kind = "vendor", npc = 5688, buy = { item = 159, count = 5 } } })
  local since = c.now
  c:advance(1)
  c:openMerchant(5688, {})
  eq((check(Lines, step, since)), "todo", "still open")
  c:closeMerchant()
  eq((check(Lines, step, since)), "done")
  eq((check(Lines, step, c.now + 1)), "todo", "a visit before the step")
  c:advance(2)
  local other = c.now
  c:openMerchant(1234, {})
  c:closeMerchant()
  eq((check(Lines, step, other)), "todo", "another merchant")
  local o, _, OLines = play({ oldGuid = true })
  local osince = o.now
  o:openMerchant(1234, {})
  o:closeMerchant()
  eq((check(OLines, step, osince)), "done", "the client gives no NPC: any merchant")
end)

test("use, target and note are passive", function()
  local c, _, Lines = play()
  local step = stepOf({
    { kind = "use", item = 2856 },
    { kind = "target", npc = 1765, enemy = true },
    { kind = "note", text = "Keep the wolves off him." },
  })
  for i = 1, 3 do
    eq(Lines.Active(step.lines[i]), false, step.lines[i].kind)
    eq((check(Lines, step, c.now, i)), "done", step.lines[i].kind)
  end
  for _, kind in ipairs({ "accept", "turnin", "objective", "collect", "getflight", "fly", "transport", "sethearth", "hearth", "grind", "train", "vendor", "manual" }) do
    eq(Lines.Active({ kind = kind }), true, kind)
  end
end)

test("manual is done only when ticked", function()
  local c, _, Lines = play()
  local step = stepOf({ { kind = "note", text = "x" }, { kind = "manual", text = "Open the chest." } })
  eq((check(Lines, step, c.now, 2)), "todo")
  eq((check(Lines, step, c.now, 2, { ticks = { [1] = true } })), "todo", "another line's tick")
  eq((check(Lines, step, c.now, 2, { ticks = { [2] = true } })), "done")
end)

test("every skip condition kind holds and fails as written", function()
  local c, _, Lines = play({ level = 4, zone = 85, x = 40, y = 40, api = "modern" })
  local function cond(entry)
    local reason, jump = Lines.Condition({ id = "x", lines = { { kind = "note", text = "x" } }, skip = { entry } })
    return reason, jump
  end
  eq(Lines.Condition({ id = "x", lines = {} }), nil, "no skip list")
  eq(cond({ kind = "onquest", quest = 364 }), nil)
  eq(cond({ kind = "notonquest", quest = 364 }), "you are not on The Mindless Ones")
  c:acceptQuest(364)
  eq(cond({ kind = "onquest", quest = 364 }), "you are on The Mindless Ones")
  eq(cond({ kind = "notonquest", quest = 364 }), nil)
  eq(cond({ kind = "complete", quest = 364 }), nil)
  eq(cond({ kind = "notcomplete", quest = 364 }), "The Mindless Ones is not complete")
  c:completeObjectives(364)
  eq(cond({ kind = "complete", quest = 364 }), "The Mindless Ones is complete")
  eq(cond({ kind = "notcomplete", quest = 364 }), nil)
  eq(cond({ kind = "turnedin", quest = 364 }), nil)
  eq(cond({ kind = "notturnedin", quest = 364 }), "you have not handed in The Mindless Ones")
  c:turnInQuest(364)
  local reason, jump = cond({ kind = "turnedin", quest = 364, jump = "brill_inn" })
  eq({ reason, jump }, { "you have handed in The Mindless Ones", "brill_inn" })
  eq(cond({ kind = "notturnedin", quest = 364 }), nil)
  eq(cond({ kind = "complete", quest = 364 }), "The Mindless Ones is complete", "handed in counts as complete")
  eq(cond({ kind = "level", level = 4 }), "you have reached level 4")
  eq(cond({ kind = "level", level = 5 }), nil)
  eq(cond({ kind = "level", level = 4, percent = 50 }), nil)
  c:gainXP(800) -- half of level 4's 1600
  eq(cond({ kind = "level", level = 4, percent = 50 }), "you are 50% into level 4")
  eq(cond({ kind = "below", level = 5 }), "you have not reached level 5")
  eq(cond({ kind = "below", level = 4 }), nil)
  eq(cond({ kind = "maxlevel", level = 4 }), nil)
  eq(cond({ kind = "maxlevel", level = 3 }), "you are above level 3")
  eq(cond({ kind = "skill", skill = 186, value = 50 }), nil)
  c:setProfession(186, "Mining", 50, 75)
  eq(cond({ kind = "skill", skill = 186, value = 50 }), "your Mining skill is at least 50")
  eq(cond({ kind = "item", item = 2834, count = 2 }), nil)
  c:giveItem(2834, 2)
  eq(cond({ kind = "item", item = 2834, count = 2 }), "you have 2 Embalming Ichor")
  eq(cond({ kind = "zone", zone = 85 }), "you are in Tirisfal Glades")
  eq(cond({ kind = "zone", zone = 130 }), nil)
  eq(cond({ kind = "bound", zone = 85 }), nil)
  c:bindHearth("Brill")
  eq(cond({ kind = "bound", zone = 85 }), "your hearthstone is set in Tirisfal Glades")
  eq(cond({ kind = "bound", zone = 130 }), nil)
  -- The first entry that holds wins.
  local first = Lines.Condition({ id = "x", lines = {}, skip = {
    { kind = "zone", zone = 130 }, { kind = "below", level = 9, jump = "a" }, { kind = "zone", zone = 85 } } })
  eq(first, "you have not reached level 9")
end)

test("Condition with gatesOnly keeps only a notturnedin on a quest an accept line of the step requires", function()
  -- Review 2 of task X1: with "never auto-skip" on, Progress asks only for gates, so a step whose accept the game will
  -- not offer does not wait for ever.
  local c, _, Lines = play({ level = 4, zone = 85, x = 40, y = 40 })
  local gated = { id = "g", lines = { { kind = "accept", quest = 376, ifDone = 363, requires = { 363, 364 } } },
    skip = { { kind = "zone", zone = 85 }, { kind = "notturnedin", quest = 364 } } }
  eq(Lines.Condition(gated), "you are in Tirisfal Glades", "all conditions: the first that holds")
  eq(Lines.Condition(gated, true), "you have not handed in The Mindless Ones", "gates only: the zone is not a gate")
  local plain = { id = "p", lines = { { kind = "accept", quest = 376 } }, skip = { { kind = "notturnedin", quest = 364 } } }
  eq(Lines.Condition(plain, true), nil, "364 is no prerequisite of an accept on the step: not a gate")
  c:acceptQuest(364)
  c:completeObjectives(364)
  c:turnInQuest(364)
  eq(Lines.Condition(gated, true), nil, "364 handed in: the gate is open")
end)

test("a line whose when does not hold is hidden", function()
  local c, _, Lines = play({ class = "MAGE" })
  local step = stepOf({
    { kind = "accept", quest = 8, when = { class = "ROGUE" } },
    { kind = "accept", quest = 8, when = { class = "MAGE" } },
  })
  eq((check(Lines, step, c.now, 1)), "hidden")
  eq((check(Lines, step, c.now, 2)), "todo")
end)

test("Places lists the step place, then undone lines' own places, keeps the nearest of a nearest group and drops reached ones", function()
  local c, _, Lines = play({ zone = 85, x = 40, y = 50 })
  local stepAt = { zone = 85, x = 59.4, y = 52.4, r = 10 }
  local fieldA = { zone = 85, x = 36.0, y = 50.0, nearest = true }
  local fieldB = { zone = 85, x = 52.0, y = 30.0, nearest = true }
  local road = { zone = 85, x = 38.2, y = 56.8, r = 15 }
  local step = stepOf({
    { kind = "accept", quest = 365 },
    { kind = "objective", quest = 376, index = 1, at = fieldA },
    { kind = "objective", quest = 376, index = 2, at = fieldB },
    { kind = "goto", at = road },
  }, { at = stepAt })
  local function where(list)
    local out = {}
    for i, p in ipairs(list) do out[i] = { p.at, p.line, p.nearest or false } end
    return out
  end
  c:acceptQuest(376)
  eq(where(Lines.Places(step, {})), { { stepAt, 0, false }, { fieldA, 2, true }, { road, 4, false } },
    "the step's place, the nearer field, the road")
  c:moveTo({ zone = 85, x = 52, y = 32 })
  eq(where(Lines.Places(step, {})), { { stepAt, 0, false }, { fieldB, 3, true }, { road, 4, false } }, "now the other field is nearer")
  eq(where(Lines.Places(step, { [road] = true })), { { stepAt, 0, false }, { fieldB, 3, true } }, "a reached place is dropped")
  c:acceptQuest(365)
  eq(where(Lines.Places(step, {})), { { fieldB, 3, true }, { road, 4, false } },
    "every line without its own place is done: the step's place goes")
  c:progressQuest(376, 2, 6)
  eq(where(Lines.Places(step, {})), { { fieldA, 2, true }, { road, 4, false } }, "a done line's place goes")
  c:moveTo({ zone = 85, x = 38.2, y = 56.8 })
  eq(where(Lines.Places(step, {})), { { fieldA, 2, true } }, "the goto line is done once there")
  eq(where(Lines.Places(step, {}, { done = { [2] = true } })), {}, "latched lines count as done")
  eq(where(Lines.Places(stepOf({ { kind = "note", text = "x" } }, { at = stepAt }), {})), { { stepAt, 0, false } },
    "a step of passive lines keeps its place")
end)
