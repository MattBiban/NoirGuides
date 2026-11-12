-- Noir Guides, GPLv3. See LICENSE.
-- Professions.lua: the profession plan. Skills are read by skill line ID (State), Forever's tier lines count for
-- their profession, and the trainer gates are 50, 125 and 200: at those skills the next rank (Journeyman, Expert,
-- Artisan) can be trained.
use("tools/test-lua/sample/ports.lua")

local function start(opts)
  opts = opts or {}
  opts.race, opts.class = opts.race or "Undead", opts.class or "ROGUE"
  local c = ported(opts):login()
  return c, c.G.Noir.Professions, c.G.Noir
end

local function entry(P, skillLine)
  for _, e in ipairs(P.Plan()) do
    if e.skillLine == skillLine then return e end
  end
  return nil
end

for _, api in ipairs({ "book", "tradeskill" }) do
  test(api .. ": a profession read under Forever's tier line counts for the profession", function()
    local c, P = start({ professionApi = api, level = 20 })
    c:setProfession(2947, "Skinning", 150, 225)
    local known = P.Known()
    if api == "book" then
      eq(known[393], { name = "Skinning", rank = 150, max = 225 })
    else
      -- C_TradeSkillUI is asked by the professions' own skill lines only, so a tier line is never seen there.
      eq(known[393], nil)
    end
    eq(known[2947], nil)
  end)
end

test("below a gate the plan says how far to raise the skill", function()
  local c, P = start({ level = 12 })
  c:setProfession(393, "Skinning", 30, 75)
  local e = entry(P, 393)
  eq({ e.action, e.rank, e.max }, { "raise", 30, 75 })
  has(e.text, "Raise Skinning to 50 to train Journeyman Skinning")
end)

test("at 50 the player is told once to train Journeyman", function()
  local c, P = start({ level = 12 })
  c:setProfession(393, "Skinning", 49, 75)
  c:takeChat()
  c:setProfession(393, "Skinning", 50, 75)
  eq(entry(P, 393).action, "train")
  has(c:chatText(), "Train Journeyman Skinning")
  c:takeChat()
  c:setProfession(393, "Skinning", 51, 75)
  c:fire("SKILL_LINES_CHANGED")
  no(c:chatText():find("Train", 1, true), "said once")
end)

test("the gates are 50, 125 and 200, then the highest rank", function()
  local c, P = start({ level = 40 })
  c:setProfession(186, "Mining", 124, 150)
  eq(entry(P, 186).action, "raise")
  c:setProfession(186, "Mining", 125, 150)
  eq({ entry(P, 186).action, entry(P, 186).next.name, entry(P, 186).next.cap }, { "train", "Expert", 225 })
  c:setProfession(186, "Mining", 199, 225)
  eq(entry(P, 186).action, "raise")
  c:setProfession(186, "Mining", 200, 225)
  eq({ entry(P, 186).action, entry(P, 186).next.name, entry(P, 186).next.cap }, { "train", "Artisan", 300 })
  c:setProfession(186, "Mining", 260, 300)
  eq(entry(P, 186).action, "max")
  has(entry(P, 186).text, "Artisan")
end)

test("a gate reached below the rank's level says which level", function()
  local c, P = start({ level = 15 })
  c:setProfession(182, "Herbalism", 125, 150)
  local e = entry(P, 182)
  eq(e.action, "wait")
  has(e.text, "level 20")
  c:setLevel(20)
  eq(entry(P, 182).action, "train")
end)

test("a planned profession the character does not have yet is to be learned, and the plan is kept over a relog", function()
  local c, P = start({ level = 5 })
  ok(P.SetPlanned(182, true))
  no(P.SetPlanned(99999, true), "not a profession")
  local e = entry(P, 182)
  eq({ e.action, e.name }, { "learn", "Herbalism" })
  has(e.text, "Learn Herbalism")
  c = c:relog()
  P = c.G.Noir.Professions
  ok(P.IsPlanned(182))
  eq(entry(P, 182).action, "learn")
  c:setProfession(182, "Herbalism", 1, 75)
  eq(entry(P, 182).action, "raise")
  P.SetPlanned(182, false)
  no(P.IsPlanned(182))
end)

test("secondary skills are in the plan like the others", function()
  local c, P = start({ level = 20 })
  c:setProfession(129, "First Aid", 125, 150, "firstaid")
  local e = entry(P, 129)
  eq({ e.action, e.kind }, { "train", "secondary" })
end)

test("a client with no profession API still shows the planned professions", function()
  local c, P = start({ professionApi = "none", level = 10 })
  P.SetPlanned(393, true)
  eq(entry(P, 393).action, "learn")
  c:slash("/noir professions")
end)

test("/noir professions prints the plan", function()
  local c = start({ level = 12 })
  c:setProfession(393, "Skinning", 50, 75)
  c:setProfession(186, "Mining", 20, 75)
  c:takeChat()
  c:slash("/noir professions")
  local text = c:chatText()
  has(text, "Train Journeyman Skinning")
  has(text, "Raise Mining to 50")
end)

test("with no professions and none planned, /noir professions says how to plan one", function()
  local c = start({ level = 12 })
  c:takeChat()
  c:slash("/noir professions")
  has(c:chatText(), "/noir menu")
end)

test("the rank levels are not in the data, so the ranks that need one say verified = false; the gates are the owner's", function()
  local _, P = start()
  local gates = {}
  for i, r in ipairs(P.RANKS) do
    gates[i] = r.gate
    if r.level > 1 then eq(r.verified, false, r.name .. " needs a level nobody confirmed on Forever") end
  end
  eq(gates, { 0, 50, 125, 200 })
end)

-- ---------------------------------------------------------------------------------------------------------------
-- The route's training steps (spec 3.8, gap #36)
-- ---------------------------------------------------------------------------------------------------------------

local TRAIN_STEPS = {
  { id = "a1", at = { zone = 14, x = 50, y = 50 }, lines = { { kind = "note", text = "Start." } } },
  { id = "mining2", at = { zone = 14, x = 52, y = 41 }, when = { profession = 186 },
    lines = { { kind = "train", skill = 186, rank = 2 } } },
  { id = "skinning2", at = { zone = 14, x = 52, y = 42 }, when = { profession = 393 },
    lines = { { kind = "train", skill = 393, rank = 2 } } },
  { id = "a2", at = { zone = 14, x = 50, y = 50 }, lines = { { kind = "note", text = "End." } } },
}

local function stepIds(Noir)
  local out = {}
  for _, step in ipairs(Noir.Guide.Steps("test-01-10-route")) do out[#out + 1] = step.id end
  return out
end

test("a training step exists only with the profession learned or planned", function()
  local c, Noir = portedRoute(TRAIN_STEPS, { level = 12 })
  local P = Noir.Professions
  eq(stepIds(Noir), { "a1", "a2" }, "no profession, no training step")
  P.SetPlanned(186, true)
  eq(stepIds(Noir), { "a1", "mining2", "a2" }, "planned in settings")
  P.SetPlanned(186, false)
  c:setProfession(186, "Mining", 10, 75)
  eq(stepIds(Noir), { "a1", "mining2", "a2" }, "learned")
  -- Skinning learned under Forever's tier line counts as Skinning.
  c:setProfession(2947, "Skinning", 10, 75)
  eq(stepIds(Noir), { "a1", "mining2", "skinning2", "a2" }, "learned under the tier line")
end)

test("the chat plan and the route's training steps read the same gates and caps", function()
  local c, Noir = portedRoute(TRAIN_STEPS, { level = 40 })
  local P, L = Noir.Professions, Noir.Lines
  for i = 1, 4 do
    eq({ P.RANKS[i].gate, P.RANKS[i].cap }, { L.RANK_GATE[i], L.RANK_CAP[i] }, "rank " .. i)
  end
  local train = { kind = "train", skill = 186, rank = 2 }
  local step = { id = "x", lines = { train } }
  -- At 50 both say Journeyman can be trained.
  c:setProfession(186, "Mining", 50, 75)
  eq(entry(P, 186).action, "train")
  eq((L.Check(train, step, { since = 0 })), "todo")
  -- A different gate in Lines is what both read: the plan has no copy of its own.
  L.RANK_GATE[2] = 60
  eq(entry(P, 186).action, "raise")
  has(entry(P, 186).text, "Raise Mining to 60")
  eq((L.Check(train, step, { since = 0 })), "skip")
  c:setProfession(186, "Mining", 60, 75)
  eq(entry(P, 186).action, "train")
  eq((L.Check(train, step, { since = 0 })), "todo")
  -- And a different cap: the rank counts as trained from that cap on, for both.
  L.RANK_CAP[2] = 140
  c:setProfession(186, "Mining", 120, 140)
  eq(entry(P, 186).next.name, "Expert")
  eq((L.Check(train, step, { since = 0 })), "done")
  L.RANK_GATE[2], L.RANK_CAP[2] = 50, 150
end)
