-- Noir Guides, GPLv3. See LICENSE.
-- The guide window v2 (plan task E5, spec 4.1 to 4.3, gap #13, #14): the header, the card stack with a tick box
-- per line, the scrolling step list and the footer. Every behavior here is driven by the mouse and by game events;
-- no test types a command. Every test ends with nothing off the screen.
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

-- A mage logged in with its place saved at `stepId` of Deathknell. opts: level, done, log, screen, options,
-- afterLoad.
local function at(stepId, opts)
  opts = opts or {}
  local c = sample3({ class = opts.class or "MAGE", level = opts.level or 2, screen = opts.screen,
    saved = savedAt(opts.section or DEATHKNELL, stepId, opts.options), afterLoad = opts.afterLoad })
  for _, q in ipairs(opts.done or {}) do c:markCompleted(q) end
  for _, q in ipairs(opts.log or {}) do c:acceptQuest(q) end
  c:login()
  c:advance(0.5)
  return c, c.G.Noir, c.G.Noir.Window
end

local function placeId(Noir)
  local _, _, _, step = Noir.Progress.Place()
  return step and step.id
end

local function rect(c, frame)
  return { c:rectOf(frame) }
end

local function cardKinds(W)
  local out = {}
  for i, card in ipairs(W.Read().cards) do out[i] = card.kind end
  return out
end

-- The list index of the row showing step `n`.
local function rowOf(W, n)
  for i, row in ipairs(W.Read().list) do
    if row.n == n then return i end
  end
  return nil
end

local function stub(Noir, name)
  local calls = {}
  Noir.Menu = Noir.Menu or {}
  Noir.Menu[name] = function(...) calls[#calls + 1] = { ... } end
  return calls
end

test("the window opens at its default place on the left, a little above the middle", function()
  local c, Noir, W = at("a363")
  ok(W.frame, "the window exists")
  ok(W.frame:IsShown(), "and is shown")
  eq(W.Read().shown, true)
  local left, bottom, _, top = c:rectOf(W.frame)
  local H = c.G.GetScreenHeight()
  near(left, Noir.Screen.DEFAULTS.window[3], 1e-6, "at the left edge")
  ok((bottom + top) / 2 > H / 2, "a little above the vertical middle")
  ok(W.frame:IsClampedToScreen(), "kept on the screen")
  eq(c:offScreen(), {})
  eq(c.errors, {})
end)

test("a bundled step shows as one card with a tick box per line", function()
  local c, _, W = at("t363.a364.a376", { log = { 363 } })
  local cards = W.Read().cards
  eq(#cards, 1, "one card for the bundled step")
  local card = cards[1]
  eq(card.kind, "current")
  eq(card.badge, "Sarvis", "the step's title on the badge")
  eq(#card.lines, 3)
  eq(card.lines[1].icon, "turnin")
  eq(card.lines[2].icon, "error", "Rude Awakening is not handed in yet: the accept shows the prerequisite")
  has(card.lines[1].text, "Rude Awakening")
  for i = 1, 3 do
    local tick = W.Tick(1, i)
    ok(tick and tick:IsVisible(), "line " .. i .. " has a tick box")
    eq(card.lines[i].ticked, false)
  end
  has(card.text, "Shadow Priest Sarvis", "the step's own text is on the card")
  eq(c:offScreen(), {})
end)

test("ticking a line by mouse completes it and the next step slides in", function()
  local c, Noir, W = at("a363", { level = 1 })
  eq(placeId(Noir), "a363")
  ok(c:click(W.Tick(1, 1)), "the tick box takes the click")
  c:advance(0.05)
  eq(placeId(Noir), "t363.a364.a376", "ticked by hand: the place moved on")
  local function current() local cards = W.Read().cards return cards[#cards] end
  local card = current()
  eq(card.kind, "current")
  eq(card.badge, "Sarvis")
  ok(card.slide and card.slide > 0, "the new card is sliding in")
  eq(card.mark, "turnin", "its side bar shows the step's most prominent kind")
  c:advance(0.5)
  eq(current().slide, 0, "the slide is over")
  eq(current().mark, "turnin", "the mark stays for 3 seconds")
  c:advance(3)
  eq(current().mark, nil, "and is gone after them")
  eq(Noir.Why.ForStep(DEATHKNELL, "a363").kind, "tick", "the why-log keeps the tick")
  eq(c:slashCount(), 0)
  eq(c:offScreen(), {})
end)

test("reminders show as their own cards above the current card", function()
  local c, Noir, W = at("a3901", { done = { 363 }, log = { 364, 376 } })
  c:acceptQuest(3901, QUEST3901)
  c:advance(0.5)
  eq(placeId(Noir), "o364.o376")
  eq(cardKinds(W), { "reminder", "current" })
  local reminder, current = W.Card(1), W.Card(2)
  local _, rBottom = c:rectOf(reminder)
  local _, _, _, cTop = c:rectOf(current)
  ok(rBottom >= cTop - 1e-6, "the reminder sits above the current card")
  local _, _, _, cardsTop = c:rectOf(current)
  local _, _, _, windowTop = c:rectOf(W.frame)
  ok(cardsTop >= windowTop - 1e-6, "the cards stack above the header")
  eq(c:offScreen(), {})
end)

test("cards flip below when there is no room above", function()
  local c, Noir, W = at("a363")
  local H = c.G.GetScreenHeight()
  Noir.Options.SavePosition("window", { "TOPLEFT", "BOTTOMLEFT", 20, H - 5 })
  Noir.Screen.Place(W.frame, "window")
  W.Refresh()
  local _, windowBottom = c:rectOf(W.frame)
  local _, _, _, cardTop = c:rectOf(W.Card(1))
  ok(cardTop <= windowBottom + 1e-6, "the card is below the window")
  eq(W.Read().side, "below")
  -- With cardsBelow on and the window at the bottom, they flip above.
  Noir.Options.Set("cardsBelow", true)
  Noir.Options.SavePosition("window", { "TOPLEFT", "BOTTOMLEFT", 20, 200 })
  Noir.Screen.Place(W.frame, "window")
  W.Refresh()
  eq(W.Read().side, "above")
  eq(c:offScreen(), {})
end)

test("the step list dims finished steps and highlights the current one", function()
  local c, Noir, W = at("a3901", { done = { 363 }, log = { 364, 376 } })
  eq(placeId(Noir), "a3901")
  local list = W.Read().list
  ok(#list >= 8, "every step of the section for the character")
  local first, current = list[rowOf(W, 1)], list[rowOf(W, 3)]
  eq(first.dim, true, "a step behind the place is dimmed")
  eq(first.current, false)
  eq(current.current, true, "the current step is highlighted")
  eq(current.dim, false)
  local later = list[rowOf(W, 5)]
  eq(later.dim, false, "later steps are full")
  has(later.text, "\n", "a row holds every line of its step")
  eq(rowOf(W, 9), nil, "the rogue's step is not in a mage's list")
  near(W.Row(rowOf(W, 1)):GetAlpha(), 0.5, 1e-6, "dimmed to half")
  near(W.Row(rowOf(W, 3)):GetAlpha(), 1, 1e-6)
  -- Hover brightens a row.
  c:hover(W.Row(rowOf(W, 5)))
  eq(W.Read().list[rowOf(W, 5)].lit, true)
  c:hover(W.Row(rowOf(W, 5)), true)
  eq(W.Read().list[rowOf(W, 5)].lit, false)
  eq(c:offScreen(), {})
end)

test("a double-click within 0.5 s opens the step menu; two clicks 0.6 s apart do not", function()
  local c, Noir, W = at("a363")
  local opened = stub(Noir, "OpenStep")
  local row = W.Row(rowOf(W, 5))
  c:doubleClick(row, 0.3)
  eq(#opened, 1, "a double-click opens it")
  local step5 = Noir.Progress.Steps()[opened[1][1]]
  eq(step5.n, 5, "for that row's step")
  c:advance(2)
  c:doubleClick(row, 0.6)
  eq(#opened, 1, "two clicks 0.6 s apart are two clicks")
  c:advance(2)
  c:click(row)
  eq(#opened, 1, "one click opens nothing")
  eq(placeId(Noir), "a363", "and moves nothing")
  eq(c:offScreen(), {})
end)

test("a right-click on a row opens the step menu", function()
  local c, Noir, W = at("a363")
  local opened = stub(Noir, "OpenStep")
  c:click(W.Row(rowOf(W, 4)), "RightButton")
  eq(#opened, 1)
  eq(Noir.Progress.Steps()[opened[1][1]].n, 4)
  eq(c:offScreen(), {})
end)

test("the list scrolls so the current step is the top row after a place change", function()
  local c, Noir, W = at("a363")
  ok(c:drag(W.Grip(), 0, 150), "the grip takes the drag")
  W.Refresh()
  local list = W.ListFrame()
  local _, _, _, listTop = c:rectOf(list)
  Noir.Progress.Jump(5, "list")
  c:advance(0.05)
  local _, _, _, rowTop = c:rectOf(W.Row(rowOf(W, 5)))
  near(rowTop, listTop, 1e-6, "step 5 is the top row")
  has(W.Read().range, "5", "the header's range starts at the top row")
  -- The wheel scrolls back up.
  for _ = 1, 10 do c:wheel(list, 1) end
  local _, _, _, topNow = c:rectOf(W.Row(1))
  near(topNow, listTop, 1e-6, "scrolled to the first row")
  eq(c:offScreen(), {})
end)

test("hide finished steps stops the list above the current step", function()
  local c, Noir, W = at("a363", { options = { hideFinished = true } })
  c:drag(W.Grip(), 0, 150)
  W.Refresh()
  local list = W.ListFrame()
  local _, _, _, listTop = c:rectOf(list)
  Noir.Progress.Jump(5, "list")
  c:advance(0.05)
  for _ = 1, 5 do c:wheel(list, 1) end
  local _, _, _, rowTop = c:rectOf(W.Row(rowOf(W, 5)))
  near(rowTop, listTop, 1e-6, "the list cannot scroll above the current step")
  for _ = 1, 2 do c:wheel(list, -1) end
  local _, _, _, below = c:rectOf(W.Row(rowOf(W, 5)))
  ok(below > listTop, "it still scrolls down")
  eq(c:offScreen(), {})
end)

test("hovering a passed step shows why it was passed", function()
  local c, Noir, W = at("a363", { done = { 363 }, log = { 364, 376 } })
  ok(placeId(Noir) ~= "a363", "the done step was passed")
  ok(c:hover(W.Row(rowOf(W, 1))), "the row takes the mouse")
  local tip = table.concat(c:tooltip(), "\n")
  has(tip, Noir.Why.Words("done"))
  c:hover(W.Row(rowOf(W, 1)), true)
  eq(c:tooltip(), {}, "the tooltip goes with the mouse")
  eq(c:offScreen(), {})
end)

test("hovering an accept line shows the quest tooltip", function()
  local c, _, W = at("a363", { level = 1 })
  ok(c:hover(W.Line(1, 1)), "the line takes the mouse")
  eq(c:tooltip()[1], "Rude Awakening", "the quest's own tooltip")
  c:hover(W.Line(1, 1), true)
  c:hover(W.Tick(1, 1))
  eq(c:tooltip(), { "Tick to treat this line as done" })
  eq(c:offScreen(), {})
end)

test("the header shows the section name and subgroup, and right-click opens the main menu", function()
  local c, Noir, W = at("a363")
  local read = W.Read()
  eq(read.title, "1-3 Deathknell")
  eq(read.subtitle, "1-20")
  local opened = stub(Noir, "OpenMain")
  c:click(W.Header(), "RightButton")
  eq(#opened, 1, "right-click on the header")
  c:click(W.Footer(), "RightButton")
  eq(#opened, 2, "right-click on the footer")
  c:click(W.MenuButton())
  eq(#opened, 3, "the menu button")
  c:click(W.Header(), "LeftButton")
  eq(#opened, 3, "a left click on the header opens nothing")
  local footer = W.Read().footer
  eq(footer.level, 2)
  eq(footer.version, Noir.version)
  eq(type(footer.share), "number")
  eq(c:offScreen(), {})
end)

test("without a section the window collapses to its header", function()
  local c = sample3({ race = "Orc", class = "WARRIOR", level = 1 }):login()
  local Noir, W = c.G.Noir, c.G.Noir.Window
  eq(Noir.Guide.Current(), nil, "no section for this character")
  local read = W.Read()
  eq(read.title, "Choose a section")
  eq(read.cards, {})
  eq(read.list, {})
  ok(not W.ListFrame():IsVisible(), "no step list")
  ok(not W.Footer():IsVisible(), "no footer")
  local _, bottom, _, top = c:rectOf(W.frame)
  near(top - bottom, Noir.Theme.metrics.header, 1e-6, "only the header")
  eq(c:offScreen(), {})
end)

test("resizing saves the list height; locking stops moving and resizing", function()
  local c, Noir, W = at("a363")
  local listBefore = W.ListFrame():GetHeight()
  ok(c:drag(W.Grip(), 0, -50), "dragging the grip down")
  near(W.ListFrame():GetHeight(), listBefore + 50, 1e-6, "the list grew")
  local saved = Noir.Options.Position("window")
  ok(saved and saved[6], "the size is saved")
  -- After a relog the list keeps its height.
  local again = c:relog()
  again:advance(0.5)
  near(again.G.Noir.Window.ListFrame():GetHeight(), listBefore + 50, 1e-6, "kept over a relog")
  -- Moving by the header and the body.
  local W2 = again.G.Noir.Window
  local before = rect(again, W2.frame)
  ok(again:drag(W2.Header(), 30, -20))
  local after = rect(again, W2.frame)
  near(after[1], before[1] + 30, 1e-6, "moved by the header")
  again:drag(W2.Row(1), 10, 0)
  near(rect(again, W2.frame)[1], after[1] + 10, 1e-6, "moved by the list")
  -- Locked: neither moves nor resizes.
  again.G.Noir.Options.Set("locked", true)
  local fixed = rect(again, W2.frame)
  again:drag(W2.Header(), 40, 40)
  eq(rect(again, W2.frame), fixed, "a locked window does not move")
  again:drag(W2.Grip(), 0, -40)
  eq(rect(again, W2.frame), fixed, "nor resize")
  again:hold("ALT", true)
  again:drag(W2.Header(), 0, -40)
  eq(rect(again, W2.frame), fixed, "Alt does not resize it either")
  again:hold("ALT", false)
  eq(again:offScreen(), {})
end)

test("scaling keeps the top-left corner", function()
  local c, Noir, W = at("a363")
  local left, _, _, top = c:rectOf(W.frame)
  local width = select(3, c:rectOf(W.frame)) - left
  Noir.Options.Set("windowScale", 1.25)
  local l2, _, r2, t2 = c:rectOf(W.frame)
  near(l2, left, 1e-6, "same left edge")
  near(t2, top, 1e-6, "same top edge")
  near(r2 - l2, width * 1.25, 1e-6, "drawn larger")
  Noir.Options.Set("windowScale", 0.5)
  local l3, _, _, t3 = c:rectOf(W.frame)
  near(l3, left, 1e-6)
  near(t3, top, 1e-6)
  eq(c:offScreen(), {})
end)

test("nothing is off-screen at 1024x768 with 12 cards", function()
  local function manyReminders(client)
    local sec = client.G.Noir.Routes.Get("horde-undead").sections[1]
    sec.steps[#sec.steps].label = "valley_end"
    for i = 11, 1, -1 do
      table.insert(sec.steps, 1, { id = "r" .. i, reminder = { ends = "valley_end" },
        lines = { { kind = "note", text = "Keep an eye out for reminder number " .. i .. " on the way through the valley." } } })
    end
  end
  for _, screen in ipairs({ { w = 1024, h = 768, scale = 1 }, { w = 1920, h = 1080, scale = 0.64 } }) do
    local c, Noir, W = at("a363", { level = 1, screen = screen, afterLoad = manyReminders })
    eq(placeId(Noir), "a363")
    eq(#Noir.Progress.Cards(), 12, "eleven reminders and the current step")
    eq(#W.Read().cards, 12)
    ok(W.Card(12):IsVisible(), "the current card is always shown")
    eq(c:offScreen(), {}, screen.w .. "x" .. screen.h)
    -- Moved to the top and to the bottom of the screen, still nothing leaves it.
    local H = c.G.GetScreenHeight()
    for _, y in ipairs({ H, 120 }) do
      Noir.Options.SavePosition("window", { "TOPLEFT", "BOTTOMLEFT", 20, y })
      Noir.Screen.Place(W.frame, "window")
      W.Refresh()
      ok(W.Card(12):IsVisible())
      eq(c:offScreen(), {}, "window top at " .. y)
    end
    c:setScreen(800, 600, 1)
    eq(c:offScreen(), {}, "after a resolution change")
  end
end)

test("no sound is played on a step change", function()
  local c, Noir, W = at("a363", { level = 1 })
  c:click(W.Tick(1, 1))
  c:advance(4)
  eq(placeId(Noir), "t363.a364.a376")
  eq(c:callsTo("PlaySound"), {})
  eq(c:callsTo("PlaySoundFile"), {})
  eq(c:offScreen(), {})
end)

test("no font object is set", function()
  local c, Noir, W = at("a3901", { done = { 363 }, log = { 364, 376 } })
  c:acceptQuest(3901, QUEST3901)
  c:advance(0.5)
  W.Preview(true)
  W.Preview(false)
  Noir.Panel.Confirm("Start fresh?", function() end, function() end)
  local count = 0
  for _, region in ipairs(c:regionsOf(W.frame)) do
    if region.__type == "FontString" then
      count = count + 1
      ok(region:GetFont() ~= nil, "every font string has its font file")
    end
  end
  ok(count > 10, "the window has text")
  eq(c.violations, {})
  eq(c.errors, {})
  eq(c:offScreen(), {})
end)

test("named things are colored by meaning, and one plain color with highlighting off", function()
  local c, Noir, W = at("inn", { section = "undead-03-05-tirisfal-glades", level = 3, done = { 363 } })
  eq(placeId(Noir), "inn")
  local text = W.LineText(1, 2):GetText()
  has(text, "|cff" .. Noir.Theme.Hex("friend"), "the vendor in the friend color")
  has(text, "|cff" .. Noir.Theme.Hex("buy"), "the item to buy in the buy color")
  Noir.Options.Set("highlight", false)
  ok(not W.LineText(1, 2):GetText():find("|c", 1, true), "plain text")
  eq(c:offScreen(), {})
end)

test("the step list can be turned off, and the window hidden while the engine runs on", function()
  local c, Noir, W = at("a363", { level = 1 })
  Noir.Options.Set("stepList", false)
  ok(not W.ListFrame():IsVisible(), "the list is gone")
  ok(W.Card(1):IsVisible(), "the cards stay")
  local _, bottom, _, top = c:rectOf(W.frame)
  near(top - bottom, Noir.Theme.metrics.header, 1e-6, "the window is the header")
  Noir.Options.Set("windowHidden", true)
  ok(not W.frame:IsVisible(), "hidden")
  c:acceptQuest(363)
  c:advance(0.5)
  eq(placeId(Noir), "t363.a364.a376", "the engine kept following the game")
  Noir.Options.Set("windowHidden", false)
  ok(W.frame:IsVisible())
  eq(W.Read().cards[1].badge, "Sarvis", "and the window shows the new step")
  Noir.Screen.SetShown(false)
  ok(not W.frame:IsVisible(), "hide all hides the window")
  Noir.Screen.SetShown(true)
  ok(W.frame:IsVisible())
  eq(c:offScreen(), {})
end)

test("the window keeps updating in combat", function()
  local c, Noir, W = at("a363", { level = 1 })
  c:enterCombat()
  c:acceptQuest(363)
  c:advance(0.5)
  eq(W.Read().cards[1].badge, "Sarvis")
  eq(c.violations, {})
  c:leaveCombat()
  eq(c:offScreen(), {})
end)

test("preview fills the window with sample content and returns to the section", function()
  local c, Noir, W = at("a363")
  Noir.Screen.Preview(true)
  local read = W.Read()
  ok(read.preview, "in preview")
  ok(#read.cards >= 2 and #read.list >= 3, "sample cards and rows")
  eq(c:offScreen(), {})
  Noir.Screen.Preview(false)
  eq(W.Read().title, "1-3 Deathknell")
  eq(W.Read().preview, nil)
  eq(c:offScreen(), {})
end)

test("the scrollbar pages the list", function()
  local c, _, W = at("a363")
  c:drag(W.Grip(), 0, 150)
  W.Refresh()
  local list = W.ListFrame()
  local _, _, _, listTop = c:rectOf(list)
  local bar = W.ScrollBar()
  ok(bar:IsVisible(), "a scrollbar when the rows do not fit")
  local left, bottom = c:rectOf(bar)
  c:setCursor(left + 1, bottom + 1)
  c:click(bar)
  local _, _, _, firstTop = c:rectOf(W.Row(1))
  ok(firstTop > listTop + 1, "a click below the thumb pages down")
  eq(c:offScreen(), {})
end)

test("the addon's own confirmation dialog answers yes and no", function()
  local c, Noir = at("a363")
  local answers = {}
  local Panel = Noir.Panel
  Panel.Confirm("Start fresh?", function() answers[#answers + 1] = "yes" end, function() answers[#answers + 1] = "no" end)
  local read = Panel.ConfirmRead()
  eq(read.shown, true)
  eq(read.text, "Start fresh?")
  local _, bottom, _, top = c:rectOf(Panel.ConfirmButton("yes"):GetParent())
  local H = c.G.GetScreenHeight()
  ok(math.abs((bottom + top) / 2 - (H / 2 + Noir.Screen.DEFAULTS.dialog[4])) < 1e-6, "at the dialog's place")
  c:click(Panel.ConfirmButton("yes"))
  eq(answers, { "yes" })
  eq(Panel.ConfirmRead().shown, false)
  Panel.Confirm("Again?", function() answers[#answers + 1] = "yes" end, function() answers[#answers + 1] = "no" end)
  c:click(Panel.ConfirmButton("no"))
  eq(answers, { "yes", "no" })
  eq(c.violations, {})
  eq(c:offScreen(), {})
end)

test("the resize grip sits above the step list's rows, so the list never takes its mouse", function()
  local c, _, W = at()
  local grip = W.Grip()
  for i = 1, 40 do
    local row = W.Row(i)
    if not row then break end
    ok(grip:GetFrameLevel() > row:GetFrameLevel(), "above row " .. i)
  end
  ok(grip:GetWidth() >= 20, "big enough to find")
  eq(c:offScreen(), {})
end)

test("line icons are colored by kind: gold for quests, red to kill, blue to travel", function()
  local c, _, W = at()
  eq(W.ICON_COLORS.accept, "quest", "quest icons stay gold whatever the accent")
  eq(W.ICON_COLORS.turnin, "quest")
  eq(W.ICON_COLORS.kill, "enemy")
  eq(W.ICON_COLORS["goto"], "friend")
  eq(c:offScreen(), {})
end)
