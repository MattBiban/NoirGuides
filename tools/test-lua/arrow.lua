-- Noir Guides, GPLv3. See LICENSE.
-- The arrow v2 (plan task E6, spec 4.4, gap #23): which place it points at, how far it is, arrival, nearest
-- groups, the corpse, loops, another continent, when it hides, small turns and the reset. The mock world is laid out
-- so the answers can be worked out by hand: Tirisfal Glades is 2400 by 1600 yards (1% of x is 24 yards, 1% of y is
-- 16 yards), north is up, and an angle is counted from straight ahead turning left. Every test is driven by game
-- events and the mouse; none types a command, and each ends with nothing off the screen.
use("tools/test-lua/sample/helper.lua")

local PI = math.pi
local DEATHKNELL = "undead-01-03-deathknell"
local TIRISFAL = "undead-03-05-tirisfal-glades"
local SILVERPINE = "undead-05-06-silverpine-forest"
local GUID = "Player-4444-0000002A"
local KEY = "Tester-Mock"

local FIELDS = { title = "Fields of Grief", objectives = {
  { text = "Pumpkin", type = "item", need = 10 }, { text = "Grain", type = "item", need = 10 } } }

local function savedAt(section, stepId, options)
  local db = { schema = 2, owner = GUID, guide = { section = section, how = "hand", places = { [section] = { step = stepId } } } }
  local account = {}
  if options then
    account.NoirGuidesDB = { schema = 2, profiles = { Default = options }, defaultProfile = "Default" }
  end
  return { account = account, characters = { [KEY] = { NoirGuidesCharDB = db } } }
end

-- A mage logged in with its place saved at `stepId`. opts: section, level, zone, x, y, done, log ({ id, def }
-- pairs or ids), options, afterLoad, without.
local function at(stepId, opts)
  opts = opts or {}
  local c = sample3({ class = opts.class or "MAGE", level = opts.level or 1, zone = opts.zone or 85,
    x = opts.x or 50, y = opts.y or 50, saved = savedAt(opts.section or DEATHKNELL, stepId, opts.options),
    afterLoad = opts.afterLoad, without = opts.without })
  for _, q in ipairs(opts.done or {}) do c:markCompleted(q) end
  for _, q in ipairs(opts.log or {}) do
    if type(q) == "table" then c:acceptQuest(q[1], q[2]) else c:acceptQuest(q) end
  end
  c:login()
  c:advance(0.5)
  return c, c.G.Noir, c.G.Noir.Arrow
end

local function placeId(Noir)
  local _, _, _, step = Noir.Progress.Place()
  return step and step.id
end

local function chatCount(c, piece)
  local n = 0
  for _, line in ipairs(c.chat) do
    if string.find(line, piece, 1, true) then n = n + 1 end
  end
  return n
end

test("points to the first undone place of the current card and shows whole yards", function()
  -- Undertaker Mordo's step is at 30.2, 71.6; the player stands 5% (80 yards) south of it, facing north.
  local c, Noir, Arrow = at("a363", { x = 30.2, y = 76.6 })
  eq(placeId(Noir), "a363")
  local target = Arrow.Target()
  ok(target, "there is a target")
  eq({ target.index, target.line, target.title }, { 1, 0, "1" })
  eq({ target.at.x, target.at.y }, { 30.2, 71.6 })
  local shown = Arrow.Read()
  eq(shown.shown, true)
  near(shown.angle, 0, 1e-9, "straight ahead")
  near(shown.yards, 80, 1e-6)
  has(shown.text, "80 yd")
  has(shown.text, "1", "the label names the step")
  eq(shown.frozen, false)
  ok(Arrow.frame:IsShown())
  c:moveTo({ zone = 85, x = 30.2, y = 74.33 }) -- 43.68 yards: shown as whole yards
  c:advance(0.2)
  has(Arrow.Read().text, "44 yd")
  -- Facing east, the place is a quarter turn to the left.
  c:face(-PI / 2)
  c:advance(0.2)
  near(Arrow.Read().angle, PI / 2, 1e-9)
  eq(c:slashCount(), 0)
  eq(c:offScreen(), {})
end)

test("the label is the step's title when it has one", function()
  local c, Noir, Arrow = at("t363.a364.a376", { log = { 363 }, x = 30.84, y = 70.2 })
  eq(placeId(Noir), "t363.a364.a376")
  has(Arrow.Read().text, "Sarvis")
  has(Arrow.Read().text, "64 yd")
  eq(c:offScreen(), {})
end)

test("a reached place moves the arrow to the next one", function()
  -- Mordo's step gets a second place of its own: a note by the coffins, 10% (160 yards) further south.
  local function withSecondPlace(client)
    local step = client.G.Noir.Routes.Get("horde-undead").sections[1].steps[1]
    step.lines[2] = { kind = "note", text = "The coffins are by the south wall.", at = { zone = 85, x = 30.2, y = 81.6 } }
  end
  local c, Noir, Arrow = at("a363", { x = 30.2, y = 60, afterLoad = withSecondPlace })
  eq(Arrow.Target().line, 0, "the step's own place comes first")
  c:moveTo({ zone = 85, x = 30.2, y = 71.9 }) -- 4.8 yards from it: inside its radius of 8
  c:advance(0.5)
  eq(placeId(Noir), "a363", "the accept is still to do")
  ok(Noir.Progress.Reached(1, 0), "the place is marked reached")
  local target = Arrow.Target()
  eq(target.line, 2, "the arrow moved to the note's place")
  eq({ target.at.x, target.at.y }, { 30.2, 81.6 })
  local shown = Arrow.Read()
  near(shown.yards, 155.2, 1e-6)
  near(math.abs(shown.angle), PI, 1e-9, "behind the player, who faces north")
  eq(c:offScreen(), {})
end)

test("of a nearest group only the closest is the target", function()
  local c, Noir, Arrow = at("o365", { section = TIRISFAL, level = 3, x = 51, y = 32, log = { { 365, FIELDS } } })
  eq(placeId(Noir), "o365")
  local target = Arrow.Target()
  eq({ target.at.x, target.at.y }, { 52.0, 30.0 }, "the northern field is nearer")
  c:moveTo({ zone = 85, x = 37, y = 51 })
  c:advance(0.5)
  target = Arrow.Target()
  eq({ target.at.x, target.at.y }, { 36.0, 50.0 }, "now the western field is")
  eq(c:offScreen(), {})
end)

test("a ghost gets the corpse", function()
  local c, Noir, Arrow = at("a363", { x = 40, y = 40 })
  c:die()
  c:releaseSpirit({ zone = 85, x = 40, y = 50 })
  c:advance(0.5)
  local target = Arrow.Target()
  ok(target and target.corpse, "the corpse is the target")
  eq({ target.at.zone, target.at.x, target.at.y }, { 85, 40, 40 })
  local shown = Arrow.Read()
  eq(shown.shown, true)
  near(shown.yards, 160, 1e-6, "10% north")
  near(shown.angle, 0, 1e-9)
  c:resurrect()
  c:advance(0.5)
  eq(Arrow.Target().index, 1, "alive again: back to the step")
  eq(c:offScreen(), {})
end)

test("a loop resets after the last point and restarts when far off", function()
  -- The objectives of Deathknell's step 5 are walked as a loop of three points; the step's place has no radius, so
  -- each point counts as reached within 20 yards.
  local c, Noir, Arrow = at("o364.o376", { done = { 363 }, log = { 364, 376 }, x = 30, y = 66 })
  eq(placeId(Noir), "o364.o376")
  local function point()
    local t = Arrow.Target()
    return t and t.loop, t and { t.at.x, t.at.y }
  end
  local k, xy = point()
  eq({ k, xy }, { 1, { 32.6, 63.5 } }, "the loop starts at its first point")
  c:moveTo({ zone = 85, x = 32.6, y = 64.2 }) -- 11.2 yards from it
  c:advance(0.5)
  k, xy = point()
  eq({ k, xy }, { 2, { 35.0, 61.0 } })
  c:moveTo({ zone = 85, x = 35.0, y = 61.5 })
  c:advance(0.5)
  eq((point()), 3)
  c:moveTo({ zone = 85, x = 33.5, y = 58.0 })
  c:advance(0.5)
  eq((point()), 1, "after the last point the loop starts again")
  -- 1333 yards from the first point, past 1000 yards and 1.3 legs: the nearest point (the second) takes over.
  c:moveTo({ zone = 85, x = 80, y = 20 })
  c:advance(0.5)
  eq((point()), 2, "far off the loop it restarts from the nearest point")
  eq(placeId(Noir), "o364.o376")
  eq(c:offScreen(), {})
end)

test("another continent freezes the arrow and says so once in chat", function()
  -- The last step of Silverpine lies in Durotar, on the other continent.
  local c, Noir, Arrow = at("g14", { section = SILVERPINE, level = 6, zone = 85, x = 50, y = 50 })
  eq(placeId(Noir), "g14")
  local target = Arrow.Target()
  ok(target and target.elsewhere, "the target is reported as elsewhere")
  eq(target.at.zone, 14)
  local shown = Arrow.Read()
  eq(shown.shown, true)
  eq(shown.frozen, true)
  eq(shown.angle, 0, "pointing straight up")
  has(shown.text, "On another continent")
  c:face(1)
  c:advance(2)
  eq(Arrow.Read().angle, 0, "frozen: it does not turn")
  eq(chatCount(c, "another continent"), 1, "one chat line")
  c:advance(5)
  eq(chatCount(c, "another continent"), 1, "and only one")
  eq(c:offScreen(), {})
end)

test("hidden in an instance, without a position, or when switched off", function()
  local c, Noir, Arrow = at("a363", { x = 30.2, y = 76.6 })
  eq(Arrow.Read().shown, true)
  Noir.Options.Set("arrow", false)
  c:advance(0.2)
  eq(Arrow.Read().shown, false, "switched off")
  eq(Arrow.frame:IsShown(), false)
  Noir.Options.Set("arrow", true)
  c:advance(0.2)
  eq(Arrow.Read().shown, true, "on again")
  c:moveTo({ hidden = true })
  c:advance(0.5)
  eq(Arrow.Read().shown, false, "in an instance")
  eq(Arrow.frame:IsShown(), false)
  c:moveTo({ zone = 85, x = 30.2, y = 76.6 })
  c:advance(0.5)
  eq(Arrow.Read().shown, true, "outside again")
  local blind = at("a363", { x = 30.2, y = 76.6, without = { "UnitPosition", "C_Map.GetPlayerMapPosition" } })
  eq(blind.G.Noir.Arrow.Read().shown, false, "the client gives no position")
  blind:takeChat()
  -- No target: a step without any place (a manual line only).
  local none = at("m.chest", { section = TIRISFAL, level = 5, x = 50, y = 50 })
  eq(placeId(none.G.Noir), "m.chest")
  eq(none.G.Noir.Arrow.Target(), nil)
  eq(none.G.Noir.Arrow.Read().shown, false, "nothing to point at")
  eq(c:offScreen(), {})
  eq(blind:offScreen(), {})
  eq(none:offScreen(), {})
end)

test("small turns under a tenth of a degree do not redraw", function()
  local c, _, Arrow = at("a363", { x = 30.2, y = 76.6 })
  local before = Arrow.Read()
  local coords = { Arrow.parts.arrow:GetTexCoord() }
  c:face(math.rad(0.05))
  c:advance(0.3)
  local after = Arrow.Read()
  eq(after.draws, before.draws, "no redraw for 0.05 degrees")
  eq(after.angle, before.angle)
  eq({ Arrow.parts.arrow:GetTexCoord() }, coords)
  c:face(math.rad(0.8))
  c:advance(0.3)
  eq(Arrow.Read().draws, before.draws + 1, "0.8 degrees redraws once")
  near(Arrow.Read().angle, -math.rad(0.8), 1e-9)
  c:moveTo({ zone = 85, x = 30.2, y = 76.62 }) -- 80.32 yards: still 80 whole yards
  c:advance(0.3)
  eq(Arrow.Read().draws, before.draws + 1, "the same whole yards do not redraw")
  c:moveTo({ zone = 85, x = 30.2, y = 76.7 }) -- 81.6 yards
  c:advance(0.3)
  eq(Arrow.Read().draws, before.draws + 2)
  has(Arrow.Read().text, "82 yd")
  eq(c:offScreen(), {})
end)

test("it opens at the top middle, is dragged and kept, and reset re-enables and recentres it slightly above the middle", function()
  local c, Noir, Arrow = at("a363", { x = 30.2, y = 76.6 })
  local W, H = c:uiSize()
  local left, bottom, right, top = c:rectOf(Arrow.frame)
  near((left + right) / 2, W / 2, 1e-6, "centred")
  near(top, H - 100, 1e-6, "near the top")
  ok(Arrow.frame:IsClampedToScreen())
  ok(c:drag(Arrow.frame, -300, -200), "the arrow can be dragged")
  local l2, _, _, t2 = c:rectOf(Arrow.frame)
  near(l2, left - 300, 1e-6)
  near(t2, top - 200, 1e-6)
  ok(Noir.Options.Position("arrow"), "its place is saved")
  Noir.Options.Set("locked", true)
  c:drag(Arrow.frame, 100, 0)
  near((c:rectOf(Arrow.frame)), l2, 1e-6, "locked: it stays")
  Noir.Options.Set("locked", false)
  Noir.Options.Set("arrow", false)
  c:advance(0.2)
  eq(Arrow.Read().shown, false)
  Arrow.Reset()
  c:advance(0.2)
  eq(Noir.Options.Get("arrow"), true, "re-enabled")
  eq(Arrow.Read().shown, true)
  left, bottom, right, top = c:rectOf(Arrow.frame)
  near((left + right) / 2, W / 2, 1e-6)
  near((bottom + top) / 2, H / 2 + 150, 1e-6, "slightly above the middle")
  -- A drag far off the screen stays inside it.
  c:drag(Arrow.frame, 5000, 5000)
  eq(c:offScreen(), {})
end)

test("scale and label size come from the settings", function()
  local c, Noir, Arrow = at("a363", { x = 30.2, y = 76.6 })
  local _, _, _, top = c:rectOf(Arrow.frame)
  Noir.Options.Set("arrowScale", 2)
  c:advance(0.2)
  eq(Arrow.frame:GetScale(), 2)
  local _, _, _, top2 = c:rectOf(Arrow.frame)
  near(top2, top, 1e-6, "the top stays where it was")
  Noir.Options.Set("arrowText", 18)
  c:advance(0.2)
  eq(select(2, Arrow.parts.label:GetFont()), 18)
  eq(c:offScreen(), {})
end)
