-- Noir Guides, GPLv3. See LICENSE.
-- Map pins v2 (plan task E6, spec 4.5, gap #24): pins on the world map and the minimap for the steps on the cards
-- and the steps after them, merging, the look, tooltips, mouse, path lines, what has no pin, the rebuild rate,
-- sub-zone maps and instances. The world map and the minimap are the game's own frames: the mock records a
-- violation for any change to them, and every test fails on a violation. Tirisfal Glades is 2400 by 1600 yards
-- (1% of x is 24 yards, 1% of y is 16 yards) and lies at 0.30 to 0.50, 0.10 to 0.30 of the Eastern Kingdoms.
use("tools/test-lua/sample/helper.lua")

local DEATHKNELL = "undead-01-03-deathknell"
local GUID = "Player-4444-0000002A"
local KEY = "Tester-Mock"

local QUEST3901 = { title = "Fresh Meat", objectives = { { text = "Rattlecage Bone", type = "item", need = 5 } } }

local function savedAt(section, stepId, options)
  local db = { schema = 2, owner = GUID, guide = { section = section, how = "hand", places = { [section] = { step = stepId } } } }
  local account = {}
  if options then
    account.NoirGuidesDB = { schema = 2, profiles = { Default = options }, defaultProfile = "Default" }
  end
  return { account = account, characters = { [KEY] = { NoirGuidesCharDB = db } } }
end

-- A mage with its place saved at `stepId` of Deathknell. opts: level, x, y, done, log, options, afterLoad, map
-- (a uiMap to open the world map on), maps (extra maps for the mock world: { [id] = map }).
local function at(stepId, opts)
  opts = opts or {}
  local c = sample3({ class = opts.class or "MAGE", level = opts.level or 1, zone = 85, x = opts.x or 50,
    y = opts.y or 50, saved = savedAt(opts.section or DEATHKNELL, stepId, opts.options), afterLoad = opts.afterLoad })
  for id, map in pairs(opts.maps or {}) do c:addMap(id, map) end
  for _, q in ipairs(opts.done or {}) do c:markCompleted(q) end
  for _, q in ipairs(opts.log or {}) do c:acceptQuest(q) end
  c:login()
  c:advance(0.5)
  if opts.map then
    c:openWorldMap(opts.map)
    c:advance(0.5)
  end
  return c, c.G.Noir, c.G.Noir.Map
end

-- The step ids of a pin list, in order.
local function stepIds(pins)
  local out = {}
  for _, pin in ipairs(pins) do
    for _, s in ipairs(pin.steps) do out[#out + 1] = s.id end
  end
  return out
end

local function sorted(list)
  local out = {}
  for i, v in ipairs(list) do out[i] = v end
  table.sort(out)
  return out
end

-- Distinct step ids, in order of first appearance.
local function distinct(list)
  local seen, out = {}, {}
  for _, v in ipairs(list) do
    if not seen[v] then seen[v] = true out[#out + 1] = v end
  end
  return out
end

local function pinWith(pins, id)
  for i, pin in ipairs(pins) do
    for _, s in ipairs(pin.steps) do
      if s.id == id then return pin, i end
    end
  end
  return nil
end

-- Mordo's step (a363) gets a note with a place of its own `yards` south of the step's place.
local function noteSouth(yards)
  return function(client)
    local step = client.G.Noir.Routes.Get("horde-undead").sections[1].steps[1]
    step.lines[2] = { kind = "note", text = "The coffins are by the south wall.",
      at = { zone = 85, x = 30.2, y = 71.6 + yards / 16 } }
  end
end

local DEATHKNELL_MAGE = { "a363", "t363.a364.a376", "a3901", "o364.o376", "c2834", "t364.t376", "t3901", "l3@85", "g.road" }

test("the world map shows the cards' places and the next steps up to 8", function()
  local c, Noir, Map = at("a363", { map = 1420 })
  local pins = Map.Pins("world")
  eq(distinct(stepIds(pins)), { "a363", "t363.a364.a376", "a3901", "t364.t376", "t3901", "o364.o376", "l3@85", "c2834" },
    "the current step first, then seven more steps with a place (the reminder has none), merged pins together")
  eq(#distinct(stepIds(pins)), 8)
  ok(pins[1].current, "the card's pin comes first")
  eq(pins[1].steps[1].id, "a363")
  local drawn = Map.Read().world
  eq(drawn.shown, true)
  eq(drawn.map, 1420)
  eq(#drawn.pins, #pins, "every pin falls on Tirisfal's map")
  near(drawn.pins[1].x, 0.302, 1e-9)
  near(drawn.pins[1].y, 0.716, 1e-9)
  -- The pin frame sits on the addon's own layer on the canvas, at the place's share of its size.
  local frame = Map.parts.world[1]
  ok(frame:IsVisible())
  local point, relative, relativePoint, x, y = frame:GetPoint(1)
  eq({ point, relativePoint }, { "CENTER", "TOPLEFT" })
  eq(relative:GetParent(), c.worldMapCanvas)
  local w, h = c.worldMapCanvas:GetWidth(), c.worldMapCanvas:GetHeight()
  near(x, 0.302 * w, 1e-6)
  near(y, -0.716 * h, 1e-6)
  -- The pins follow the route: once Mordo's quest is taken, the next step's place takes the lead.
  c:acceptQuest(363)
  c:advance(0.5)
  local _, _, _, step = Noir.Progress.Place()
  eq(step.id, "t363.a364.a376")
  eq(Map.Pins("world")[1].steps[1].id, "t363.a364.a376")
  c:closeWorldMap()
  eq(Map.Read().world.shown, false)
  eq(c:offScreen(), {})
end)

test("the setting changes the limit from 0 to 20, raised to fit every place on the cards", function()
  local c, Noir, Map = at("a363", { map = 1420 })
  Noir.Options.Set("worldPins", 0)
  c:advance(0.5)
  eq(distinct(stepIds(Map.Pins("world"))), { "a363" }, "0: only the card's places, raised to fit them")
  Noir.Options.Set("worldPins", 3)
  c:advance(0.5)
  eq(sorted(distinct(stepIds(Map.Pins("world")))), sorted({ "a363", "t363.a364.a376", "a3901" }))
  Noir.Options.Set("worldPins", 20)
  c:advance(0.5)
  eq(sorted(distinct(stepIds(Map.Pins("world")))), sorted(DEATHKNELL_MAGE), "20: every step of the section with a place")
  eq(#Map.Read().world.pins, #Map.Pins("world"))
  -- Two cards (a reminder with a place and the current step) with the limit at 1: both are pinned.
  local function reminderPlace(client)
    client.G.Noir.Routes.Get("horde-undead").sections[1].steps[4].at = { zone = 85, x = 31.5, y = 64.0 }
  end
  local c2, Noir2, Map2 = at("a3901", { done = { 363 }, log = { 364, 376 }, afterLoad = reminderPlace,
    options = { worldPins = 1 }, map = 1420 })
  c2:acceptQuest(3901, QUEST3901)
  c2:advance(0.5)
  local _, _, _, step = Noir2.Progress.Place()
  eq(step.id, "o364.o376")
  eq(#Noir2.Progress.Cards(), 2)
  eq(sorted(distinct(stepIds(Map2.Pins("world")))), sorted({ "r3901", "o364.o376" }), "raised to fit both cards")
  eq(c:offScreen(), {})
  eq(c2:offScreen(), {})
end)

test("the minimap shows the cards' places and the upcoming steps, and can be switched off", function()
  -- The player stands 5% (80 yards) north of Mordo's place, facing north.
  local c, Noir, Map = at("a363", { x = 30.2, y = 66.6 })
  local world = stepIds(Map.Pins("world"))
  eq(stepIds(Map.Pins("minimap"))[1], "a363", "the current step first")
  ok(#Map.Pins("minimap") > 1, "the upcoming steps are on the minimap too")
  eq(sorted(distinct(stepIds(Map.Pins("minimap")))), sorted(distinct(world)), "the same steps as the world map")
  -- With the upcoming steps set to 0, only the cards' places are left.
  Noir.Options.Set("worldPins", 0)
  c:advance(0.5)
  eq(stepIds(Map.Pins("minimap")), { "a363" })
  local list = Map.Read().minimap.pins
  eq(#list, 1)
  -- Zoomed out the minimap is 466 2/3 yards across, drawn 140 wide: 0.3 units per yard.
  near(list[1].x, 0, 1e-6)
  near(list[1].y, -24, 1e-6, "80 yards south")
  eq(list[1].edge, false)
  local frame = Map.parts.minimap[1]
  eq(frame:GetParent(), c.minimapFrame)
  ok(frame:IsShown())
  Noir.Options.Set("minimapPins", false)
  c:advance(0.5)
  eq(Map.Pins("minimap"), {})
  eq(Map.Read().minimap.pins, {})
  eq(frame:IsShown(), false)
  Noir.Options.Set("minimapPins", true)
  c:advance(0.5)
  eq(#Map.Read().minimap.pins, 1)
  -- Out of range, the current step's pin waits on the rim in its direction.
  c:moveTo({ zone = 85, x = 30.2, y = 31.6 })
  c:advance(0.5)
  list = Map.Read().minimap.pins
  eq(#list, 1)
  eq(list[1].edge, true)
  near(list[1].y, -70, 1e-6)
  eq(c:offScreen(), {})
end)

test("places within 60 yards share a pin with '+' on the world map, 25 yards on the minimap, scaled by the merge setting", function()
  -- Mordo's step and a note 40 yards south of it, both on the current card.
  local c, Noir, Map = at("a363", { x = 30.2, y = 66.6, afterLoad = noteSouth(40), map = 1420 })
  -- The minimap also shows the upcoming steps; the merging of the card's two places is read on the card's pins.
  local function cardPins(list)
    local out = {}
    for _, p in ipairs(list) do if p.current then out[#out + 1] = p end end
    return out
  end
  local world = Map.Pins("world")
  local pin = world[1]
  eq(#pin.steps, 2, "40 yards apart: one pin on the world map")
  eq(pin.merged, true)
  eq(pin.plus, true)
  eq(pin.label, "1", "labelled with the number of the first step")
  eq({ pin.steps[1].line, pin.steps[2].line }, { 0, 2 })
  local mini = cardPins(Map.Pins("minimap"))
  eq(#mini, 2, "40 yards is more than 25: two pins on the minimap")
  eq(mini[1].merged, false)
  eq(Map.Read().world.pins[1].plus, true)
  ok(Map.parts.world[1].plus:IsShown(), "the '+' is drawn")
  eq(Map.parts.world[1].plus:GetText(), "+")
  -- t363 (30.84, 66.2) and a3901 (31.1, 65.1) are 18.7 yards apart; o364 lies 61 yards from t363.
  local t363 = pinWith(world, "t363.a364.a376")
  ok(pinWith({ t363 }, "a3901"), "18.7 yards: one pin")
  no(pinWith({ t363 }, "o364.o376"), "61 yards: a pin of its own")
  -- The merge setting scales both distances.
  Noir.Options.Set("pinMerge", 0.5)
  c:advance(0.5)
  eq(#Map.Pins("world")[1].steps, 1, "30 yards on the world map: the note gets its own pin")
  eq(Map.Pins("world")[1].plus, false)
  Noir.Options.Set("pinMerge", 2)
  c:advance(0.5)
  eq(#cardPins(Map.Pins("minimap")), 1, "50 yards on the minimap: one pin")
  eq(cardPins(Map.Pins("minimap"))[1].plus, true)
  eq(c:offScreen(), {})
end)

test("the current pins are larger and opaque, later ones fade by step down to 0.4", function()
  local c, Noir, Map = at("a363", { options = { worldPins = 20, pinMerge = 0.05, pinSize = 1.5, pinRing = true }, map = 1420 })
  local pins = Map.Pins("world")
  local Theme = Noir.Theme
  local expected = { ["t363.a364.a376"] = 0.9, ["a3901"] = 0.8, ["o364.o376"] = 0.7, ["c2834"] = 0.6,
    ["l3@85"] = 0.4, ["g.road"] = 0.4 }
  eq(pins[1].current, true)
  near(pins[1].alpha, 1, 1e-9)
  near(pins[1].size, Theme.metrics.active * 1.5, 1e-9)
  eq(pins[1].ring, true, "the ring is around the current pin")
  for id, alpha in pairs(expected) do
    local pin = pinWith(pins, id)
    ok(pin, id .. " has a pin")
    near(pin.alpha, alpha, 1e-9, id)
    eq(pin.current, false, id)
    eq(pin.ring, false, id)
    near(pin.size, Theme.metrics.pin * 1.5, 1e-9, id)
  end
  -- t364.t376 (5th step after) shares t363's place exactly, so its pin is t363's.
  eq(pinWith(pins, "t364.t376"), pinWith(pins, "t363.a364.a376"))
  -- The frames carry it: alpha, size, the ring texture and the background's opacity.
  local frame = Map.parts.world[1]
  near(frame:GetAlpha(), 1, 1e-9)
  ok(frame.ring:IsShown(), "ring drawn")
  near(select(4, frame.back:GetVertexColor()), 0.6, 1e-9, "pinAlpha is the background's opacity")
  local _, i = pinWith(Map.Read().world.pins, "o364.o376")
  near(Map.parts.world[i]:GetAlpha(), 0.7, 1e-9)
  eq(Map.parts.world[i].ring:IsShown(), false)
  Noir.Options.Set("pinAlpha", 0.2)
  Noir.Options.Set("pinRing", false)
  c:advance(0.5)
  near(select(4, Map.parts.world[1].back:GetVertexColor()), 0.2, 1e-9)
  eq(Map.parts.world[1].ring:IsShown(), false)
  eq(c:offScreen(), {})
end)

test("hovering a merged pin lists each step and line", function()
  local c, Noir, Map = at("a363", { map = 1420 })
  local _, i = pinWith(Map.Read().world.pins, "t363.a364.a376")
  local frame = Map.parts.world[i]
  local pin = Map.Read().world.pins[i]
  ok(pin.merged)
  ok(c:hover(frame), "the pin takes mouse motion")
  local tip = c:tooltip()
  eq(#tip, #pin.steps, "one line per merged place")
  eq(tip[1], "Sarvis: Turn in Rude Awakening")
  has(tip[2], "3: Accept ")
  c:hover(frame, true)
  eq(c:tooltip(), {})
  eq(c:offScreen(), {})
end)

test("a click on a pin reaches the map", function()
  local c, _, Map = at("a363", { map = 1420, x = 30.2, y = 66.6 })
  for _, frame in ipairs({ Map.parts.world[1], Map.parts.minimap[1] }) do
    ok(frame:IsVisible())
    eq(frame:IsMouseClickEnabled(), false, "no clicks")
    eq(frame:IsMouseMotionEnabled(), true, "motion only, for the tooltip")
    eq(c:click(frame), false, "the click passes through to the map")
  end
  eq(c:offScreen(), {})
end)

test("a path is drawn while its step is on a card", function()
  local c, Noir, Map = at("o364.o376", { done = { 363 }, log = { 364, 376 }, map = 1420 })
  local lines = Map.Read().world.lines
  ok(#lines > 0, "the loop's dashes are drawn")
  -- First leg: 32.6, 63.5 to 35.0, 61.0 is 57.6 yards east and 40 north, 70.1 yards: dashes of 8 yards every 14.
  local leg = math.sqrt(57.6 * 57.6 + 40 * 40)
  local function yards(ax, ay, bx, by) return math.sqrt(((bx - ax) * 2400) ^ 2 + ((by - ay) * 1600) ^ 2) end
  local d1, d2 = lines[1], lines[2]
  near(d1.x1, 0.326, 1e-9)
  near(d1.y1, 0.635, 1e-9)
  near(yards(d1.x1, d1.y1, d1.x2, d1.y2), 8, 1e-6, "a dash is 8 yards")
  near(yards(d1.x1, d1.y1, d2.x1, d2.y1), 14, 1e-6, "then 6 yards skipped")
  local onLeg = 0
  for _, d in ipairs(lines) do
    if yards(0.326, 0.635, d.x1, d.y1) < leg - 1e-6 and math.abs((d.y1 - 0.635) * 1600 * 57.6 + (d.x1 - 0.326) * 2400 * 40) < 1e-3 then
      onLeg = onLeg + 1
    end
  end
  eq(onLeg, 6, "70.1 yards hold six dashes (the last one short)")
  local legs = { leg, math.sqrt((1.5 * 24) ^ 2 + (2.5 * 16) ^ 2), math.sqrt((0.9 * 24) ^ 2 + (5 * 16) ^ 2) }
  local expected = 0
  for _, l in ipairs(legs) do expected = expected + math.ceil(l / 14) end
  eq(#lines, expected, "three legs: the loop is closed")
  eq(#Map.parts.lines >= #lines, true)
  ok(Map.parts.lines[1]:IsShown())
  -- Not on the continent's map, only on the zone's.
  c:setWorldMap(1415)
  c:advance(0.5)
  eq(Map.Read().world.lines, {})
  eq(Map.parts.lines[1]:IsShown(), false)
  c:setWorldMap(1420)
  c:advance(0.5)
  eq(#Map.Read().world.lines, expected)
  -- A step that is pinned but not on a card draws no path.
  local c2, _, Map2 = at("a363", { map = 1420 })
  ok(pinWith(Map2.Pins("world"), "o364.o376"), "the loop's step is pinned")
  eq(Map2.Read().world.lines, {}, "but not on a card: no path")
  eq(c:offScreen(), {})
  eq(c2:offScreen(), {})
end)

test("done, ticked and reached places have no pin", function()
  -- Mordo's step gets a go-to line and a manual line, each with a place of its own.
  local function morePlaces(client)
    local step = client.G.Noir.Routes.Get("horde-undead").sections[1].steps[1]
    step.lines[2] = { kind = "goto", at = { zone = 85, x = 35.0, y = 70.0, r = 5 } }
    step.lines[3] = { kind = "manual", text = "Look behind the coffins.", at = { zone = 85, x = 26.0, y = 70.0 } }
  end
  local c, Noir, Map = at("a363", { x = 50, y = 50, afterLoad = morePlaces, options = { worldPins = 0 }, map = 1420 })
  local function lines()
    local out = {}
    for _, pin in ipairs(Map.Pins("world")) do
      for _, s in ipairs(pin.steps) do out[#out + 1] = s.line end
    end
    table.sort(out)
    return out
  end
  eq(lines(), { 0, 2, 3 }, "the step's place and the two lines' places")
  -- Ticked by mouse in the window: the manual line's pin goes.
  ok(c:click(Noir.Window.Tick(1, 3)), "the manual line's tick box")
  c:advance(0.5)
  eq(lines(), { 0, 2 })
  -- Done: the go-to line completes on arrival.
  c:moveTo({ zone = 85, x = 35.0, y = 70.1 })
  c:advance(1)
  eq(lines(), { 0 })
  -- Reached: inside the step's radius; the accept is still to do, so the step stays.
  c:moveTo({ zone = 85, x = 30.2, y = 71.8 })
  c:advance(1)
  local _, _, _, step = Noir.Progress.Place()
  eq(step.id, "a363")
  ok(Noir.Progress.Reached(1, 0))
  eq(lines(), {})
  eq(Map.Read().world.pins, {})
  eq(c:offScreen(), {})
end)

test("pins rebuild at most three times a second", function()
  local c, Noir, Map = at("a363", { map = 1420 })
  local times, last = {}, Map.Read().builds
  for _ = 1, 40 do
    Noir.Fire("NOIR_STEP", Noir.Progress.Cards())
    c:advance(0.05)
    local read = Map.Read()
    if read.builds ~= last then
      ok(read.builds - last == 1, "one rebuild at a time")
      times[#times + 1] = read.builtAt
      last = read.builds
    end
  end
  ok(#times >= 3, "it does rebuild")
  ok(#times <= 7, "2 seconds hold at most 7 rebuilds")
  for i = 2, #times do
    ok(times[i] - times[i - 1] >= 0.33 - 1e-6, "rebuilds are 0.33 s apart (" .. i .. ")")
  end
  -- A change of the shown map draws at once.
  c:setWorldMap(1415)
  c:advance(0.3)
  eq(Map.Read().world.map, 1415)
  ok(#Map.Read().world.pins > 0)
  eq(c:offScreen(), {})
end)

test("sub-zone maps show pins that fall on them; instances show none", function()
  -- A sub-zone map of Deathknell inside Tirisfal: 0.25 to 0.40 across, 0.62 to 0.80 down.
  local maps = { [2000] = { name = "Deathknell", type = 5, parent = 1420, rect = { 0.25, 0.62, 0.40, 0.80 } } }
  local c, Noir, Map = at("a363", { maps = maps, map = 2000 })
  local drawn = Map.Read().world
  eq(drawn.map, 2000)
  local first = drawn.pins[1]
  eq(first.steps[1].id, "a363")
  near(first.x, (0.302 - 0.25) / 0.15, 1e-9)
  near(first.y, (0.716 - 0.62) / 0.18, 1e-9)
  ok(pinWith(drawn.pins, "o364.o376"), "o364 (32.63, 63.5) is on it")
  no(pinWith(drawn.pins, "c2834"), "c2834 (34, 60) is north of it")
  -- The continent's map holds every place.
  c:setWorldMap(1415)
  c:advance(0.5)
  eq(#Map.Read().world.pins, #Map.Pins("world"))
  near(Map.Read().world.pins[1].x, 0.30 + 0.302 * 0.2, 1e-9)
  -- Silverpine's map holds none.
  c:setWorldMap(1421)
  c:advance(0.5)
  eq(Map.Read().world.pins, {})
  -- In an instance there are no pins at all.
  c:setWorldMap(1420)
  c:moveTo({ hidden = true })
  c:advance(0.5)
  eq(Map.Pins("world"), {})
  eq(Map.Read().world.pins, {})
  eq(Map.Read().minimap.pins, {})
  for _, frame in ipairs(Map.parts.world) do eq(frame:IsShown(), false) end
  eq(c:offScreen(), {})
end)

test("the map frames are never changed", function()
  local c, Noir, Map = at("o364.o376", { done = { 363 }, log = { 364, 376 }, x = 32, y = 64, map = 1420 })
  local mapScripts = {}
  for k in pairs(c.worldMapFrame.__scripts) do mapScripts[#mapScripts + 1] = k end
  for k in pairs(c.worldMapCanvas.__scripts) do mapScripts[#mapScripts + 1] = k end
  for k in pairs(c.minimapFrame.__scripts) do mapScripts[#mapScripts + 1] = k end
  eq(mapScripts, {}, "no script set on the map frames")
  c:hover(Map.parts.world[1])
  c:setWorldMap(1415)
  c:advance(0.5)
  c.minimapZoom = 3
  c:advance(0.5)
  c:closeWorldMap()
  c:openWorldMap(1420)
  c:advance(0.5)
  Noir.Options.Set("pinSize", 2)
  c:advance(0.5)
  eq(c:takeViolations(), {}, "nothing of the map frames was changed")
  ok(#Map.parts.world > 0 and #Map.parts.minimap > 0, "and the pins were drawn")
  eq(c.worldMapFrame:IsShown(), true)
  eq(c:offScreen(), {})
end)
