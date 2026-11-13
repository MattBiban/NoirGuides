-- Noir Guides, GPLv3. See LICENSE.
-- Reminder steps (plan task E4, spec 3.6): a step with reminder = { ends } stays on screen above the current step
-- until the place passes its ends step, never becomes the place itself, and is remembered once finished early.
use("tools/test-lua/sample/helper.lua")

local DEATHKNELL = "undead-01-03-deathknell"
local GUID = "Player-4444-0000002A"
local KEY = "Tester-Mock"

local QUEST3901 = { title = "Fresh Meat", objectives = { { text = "Rattlecage Bone", type = "item", need = 5 } } }

local function savedAt(section, stepId)
  local db = { schema = 2, owner = GUID, guide = { section = section, how = "hand", places = { [section] = { step = stepId } } } }
  return { account = {}, characters = { [KEY] = { NoirGuidesCharDB = db } } }
end

local function place(P)
  local _, index, _, step = P.Place()
  return step and step.id, index
end

local function kinds(P)
  local out = {}
  for i, card in ipairs(P.Cards()) do out[i] = card.kind .. " " .. card.step.id end
  return out
end

-- A mage at Sarvis's third quest giver (a3901) with Sarvis's two quests in the log.
local function atA3901(opts)
  opts = opts or {}
  local c = sample3({ class = "MAGE", level = opts.level or 2, saved = savedAt(DEATHKNELL, "a3901"), afterLoad = opts.afterLoad })
  c:markCompleted(363)
  c:acceptQuest(364)
  c:acceptQuest(376)
  c:login()
  return c, c.G.Noir, c.G.Noir.Progress
end

test("a reminder opens above the current step and the place moves on", function()
  local c, _, P = atA3901()
  eq(place(P), "a3901")
  c:acceptQuest(3901, QUEST3901)
  c:advance(0.5)
  eq(place(P), "o364.o376", "the place never stays on the reminder step")
  eq(kinds(P), { "reminder r3901", "nearby c2834", "current o364.o376" })
  eq(P.StepState(4), "reminder")
end)

test("it ends when the place passes its ends step", function()
  local c, _, P = atA3901()
  c:acceptQuest(3901, QUEST3901)
  c:advance(0.5)
  c:completeObjectives(364)
  c:completeObjectives(376)
  c:giveItem(2834, 4)
  c:advance(1)
  eq(place(P), "t364.t376")
  c:turnInQuest(364)
  c:turnInQuest(376)
  c:advance(0.5)
  eq(place(P), "t3901")
  eq(kinds(P), { "reminder r3901", "current t3901" }, "still open on its ends step")
  -- The ends step is passed by hand while the reminder's objective is still open.
  P.Tick(8, 1, true)
  c:advance(0.5)
  eq(place(P), "l3@85")
  eq(kinds(P), { "current l3@85" }, "the place passed the ends step: the reminder is gone")
end)

test("one finished early is remembered for the section", function()
  local c, Noir, P = atA3901()
  c:acceptQuest(3901, QUEST3901)
  c:advance(0.5)
  eq(kinds(P), { "reminder r3901", "nearby c2834", "current o364.o376" })
  c:progressQuest(3901, 1, 5)
  c:advance(0.2)
  eq(kinds(P), { "nearby c2834", "current o364.o376" }, "finished: gone")
  eq(Noir.char.guide.places[DEATHKNELL].reminders["r3901"], true)
  -- Dropped and taken again, the objective reads open, but the reminder stays finished.
  c:abandonQuest(3901)
  c:acceptQuest(3901, QUEST3901)
  c:advance(0.2)
  eq(kinds(P), { "nearby c2834", "current o364.o376" })
  local again = c:relog()
  eq(kinds(again.G.Noir.Progress), { "nearby c2834", "current o364.o376" }, "and after a relog")
end)

test("a reminder of only passive lines stays until its ends step", function()
  -- Spec 3.6: "keep an eye out for this rare" has nothing to finish; it lasts until the place passes its ends step.
  local c, Noir, P = atA3901({ afterLoad = function(client)
    client.G.Noir.Routes.Get("horde-undead").sections[1].steps[4].lines = {
      { kind = "target", npc = 1501, enemy = true },
      { kind = "note", text = "Keep an eye out for the rare skeleton." },
    }
  end })
  c:acceptQuest(3901, QUEST3901)
  c:advance(0.5)
  eq(place(P), "o364.o376")
  eq(kinds(P), { "reminder r3901", "nearby c2834", "current o364.o376" }, "it opens")
  c:advance(1)
  eq(kinds(P), { "reminder r3901", "nearby c2834", "current o364.o376" }, "and stays")
  eq(Noir.char.guide.places[DEATHKNELL].reminders["r3901"], nil, "not taken as finished")
  ok(P.Jump(9, "list"))
  eq(kinds(P), { "current l3@85" }, "past its ends step it is gone")
end)

test("a reminder with no end link ends at the normal step that requires it", function()
  -- Format 3 always writes `ends`; a route edited by hand may not. Spec 3.6: it ends at that step, not after it.
  local c, _, P = atA3901({ afterLoad = function(client)
    local steps = client.G.Noir.Routes.Get("horde-undead").sections[1].steps
    steps[4].reminder = {}
    steps[4].label = "bones"
    steps[7].requires = "bones"
  end })
  c:acceptQuest(3901, QUEST3901)
  c:advance(0.5)
  eq(kinds(P), { "reminder r3901", "nearby c2834", "current o364.o376" }, "open before the step that requires it")
  ok(P.Jump(7, "list"))
  eq(kinds(P), { "current t364.t376" }, "ended at the requiring step")
  c:completeObjectives(364)
  c:completeObjectives(376)
  c:turnInQuest(364)
  c:turnInQuest(376)
  c:advance(0.5)
  eq(place(P), "t3901", "the requiring step is not held by the reminder it ended")
end)

test("a reminder under its minimum level does not show", function()
  local c, _, P = atA3901({ afterLoad = function(client)
    client.G.Noir.Routes.Get("horde-undead").sections[1].steps[4].minLevel = 3
  end })
  c:acceptQuest(3901, QUEST3901)
  c:advance(0.5)
  eq(place(P), "o364.o376", "the place passed the reminder step")
  eq(kinds(P), { "nearby c2834", "current o364.o376" }, "level 2: the reminder does not show")
  c:setLevel(3)
  c:advance(0.2)
  eq(kinds(P), { "reminder r3901", "nearby c2834", "current o364.o376" }, "level 3: it shows")
end)

-- A profession's "raise the skill" reminder as tools/planner/professions.js writes it: at the start of the section,
-- ending at the profession trainer step, which the generator puts late in the section (Lines: the train line is
-- skipped while the skill is below the rank's gate). Mining 60/150 learned; the Expert gate is 125.
local function withSkillReminder(client)
  client.G.Noir.Data.professions = { [186] = { name = "Mining", kind = "primary" } }
  local steps = client.G.Noir.Routes.Get("horde-undead").sections[1].steps
  steps[4] = { id = "p186-3-skill", when = { profession = 186 }, reminder = { ends = "train186_3" },
    lines = { { kind = "skill", skill = 186, value = 125 } } }
  steps[8] = { id = "p186-3", label = "train186_3", when = { profession = 186 }, at = { zone = 85, x = 31.1, y = 65.1, r = 8 },
    lines = { { kind = "train", skill = 186, rank = 3, npc = 1570 } } }
  client:setProfession(186, "Mining", 60, 150)
end

local function playToTrainer(c)
  c:completeObjectives(364)
  c:completeObjectives(376)
  c:giveItem(2834, 4)
  c:advance(1)
  eq(place(c.G.Noir.Progress), "t364.t376")
end

test("a skill reminder stays on screen over the steps before its trainer step, and ends with it below the gate", function()
  local c, _, P = atA3901({ afterLoad = withSkillReminder })
  c:acceptQuest(3901, QUEST3901)
  c:advance(0.5)
  eq(place(P), "o364.o376")
  eq(kinds(P), { "reminder p186-3-skill", "nearby c2834", "current o364.o376" }, "open from the start of the section")
  playToTrainer(c)
  eq(kinds(P), { "reminder p186-3-skill", "current t364.t376" }, "still open on the last step before the trainer")
  c:turnInQuest(364)
  c:turnInQuest(376)
  c:advance(1)
  eq(place(P), "l3@85", "Mining 60 is below 125: the trainer step is passed, questing goes on")
  eq(kinds(P), { "current l3@85" }, "past its ends step the reminder is gone")
end)

test("a skill reminder raised to its gate finishes, and the trainer step then waits to be visited", function()
  local c, Noir, P = atA3901({ afterLoad = withSkillReminder })
  c:acceptQuest(3901, QUEST3901)
  c:advance(0.5)
  eq(kinds(P), { "reminder p186-3-skill", "nearby c2834", "current o364.o376" })
  c:setProfession(186, "Mining", 125, 150)
  c:advance(0.2)
  eq(kinds(P), { "nearby c2834", "current o364.o376" }, "finished: gone")
  eq(Noir.char.guide.places[DEATHKNELL].reminders["p186-3-skill"], true)
  playToTrainer(c)
  c:turnInQuest(364)
  c:turnInQuest(376)
  c:advance(1)
  eq(place(P), "p186-3", "at the gate the trainer step is current")
  eq(kinds(P), { "current p186-3" })
end)

-- A trainer step with a short lead in its section also gets a leg of its "raise the skill" reminder in the section
-- before (tools/planner/professions.js): the same line, ending at that section's second-to-last step every character
-- has, never at its last. Here Deathknell holds the leg (ending at l3@85, before g.road) and Tirisfal opens with the
-- reminder of its Mining Expert trainer step. Mining 60/150 learned; the Expert gate is 125.
local TIRISFAL = "undead-03-05-tirisfal-glades"
local function withSkillLeg(endsOnLast)
  return function(client)
    client.G.Noir.Data.professions = { [186] = { name = "Mining", kind = "primary" } }
    local sections = client.G.Noir.Routes.Get("horde-undead").sections
    local first, second = sections[1].steps, sections[2].steps
    first[4] = { id = "p186-3-skill-lead", when = { profession = 186 }, reminder = { ends = "leadend" },
      lines = { { kind = "skill", skill = 186, value = 125 } } }
    -- l3@85 is the second-to-last step every character has; g.road (no label) is the last
    first[endsOnLast and 11 or 10].label = "leadend"
    for _, step in ipairs(second) do
      if step.id == "train.mining" then
        step.label = "train186_3"
        step.lines = { { kind = "train", skill = 186, rank = 3, npc = 3175 } }
      end
    end
    table.insert(second, 1, { id = "p186-3-skill", when = { profession = 186 }, reminder = { ends = "train186_3" },
      lines = { { kind = "skill", skill = 186, value = 125 } } })
    client:setProfession(186, "Mining", 60, 150)
  end
end

local function atGrind(endsOnLast)
  local c = sample3({ class = "MAGE", level = 2, saved = savedAt(DEATHKNELL, "l3@85"), afterLoad = withSkillLeg(endsOnLast) })
  c:login()
  c:advance(0.5)
  return c, c.G.Noir, c.G.Noir.Progress
end

test("a skill reminder's leg with work left ends before the section's last step and never holds the place", function()
  local c, Noir, P = atGrind()
  eq(place(P), "l3@85")
  eq(kinds(P), { "reminder p186-3-skill-lead", "current l3@85" }, "the leg is on screen in the section before")
  c:setLevel(4)
  c:advance(1)
  eq(place(P), "g.road")
  eq(kinds(P), { "current g.road" }, "on the last step the leg has ended, its skill still below the gate")
  c:moveTo({ zone = 85, x = 38.2, y = 56.8 })
  c:advance(1)
  eq(Noir.Guide.Current(), TIRISFAL, "the end of the section is not held")
  c:advance(0.5)
  eq(kinds(P)[1], "reminder p186-3-skill", "the trainer step's own reminder takes over in its section")
end)

test("a leg ending on the section's last step would hold the place there (why the generator never ends one there)", function()
  local c, Noir, P = atGrind(true)
  c:setLevel(4)
  c:advance(1)
  eq(place(P), "g.road")
  eq(kinds(P), { "reminder p186-3-skill-lead", "current g.road" })
  c:moveTo({ zone = 85, x = 38.2, y = 56.8 })
  c:advance(5)
  eq(Noir.Guide.Current(), DEATHKNELL, "held at the end of the section while the skill is below the gate")
  eq(place(P), "g.road")
end)

test("a skill raised to the gate during the leg finishes both legs: the next section's reminder does not show", function()
  local c, Noir, P = atGrind()
  eq(kinds(P), { "reminder p186-3-skill-lead", "current l3@85" })
  c:setProfession(186, "Mining", 125, 150)
  c:advance(0.2)
  eq(kinds(P), { "current l3@85" }, "finished: gone")
  eq(Noir.char.guide.places[DEATHKNELL].reminders["p186-3-skill-lead"], true)
  c:setLevel(4)
  c:advance(1)
  c:moveTo({ zone = 85, x = 38.2, y = 56.8 })
  c:advance(1)
  eq(Noir.Guide.Current(), TIRISFAL)
  for _ = 1, 4 do
    c:advance(0.5)
    for _, k in ipairs(kinds(P)) do ok(k ~= "reminder p186-3-skill", "the reminder does not re-appear: " .. k) end
  end
  eq(Noir.char.guide.places[TIRISFAL].reminders["p186-3-skill"], true, "taken as finished as soon as it opened")
  local again = c:relog()
  for _, k in ipairs(kinds(again.G.Noir.Progress)) do ok(k ~= "reminder p186-3-skill", "nor after a relog: " .. k) end
end)
