-- Noir Guides, GPLv3. See LICENSE.
-- Menus at the cursor (plan task E7, spec 2.2, 4.1 menus, 4.3, gap #1, #5, #7, #49): the main menu, the step
-- menu and the section picker. Every menu here is opened and used with the mouse and the keyboard; no test types a
-- command. Every test ends with nothing off the screen.
use("tools/test-lua/sample/helper.lua")

local DEATHKNELL = "undead-01-03-deathknell"
local TIRISFAL = "undead-03-05-tirisfal-glades"
local SILVERPINE = "undead-05-06-silverpine-forest"
local GUID = "Player-4444-0000002A"
local KEY = "Tester-Mock"

local function savedAt(section, stepId, options)
  local db = { schema = 2, owner = GUID, guide = { section = section, how = "hand", wizard = true,
    places = { [section] = { step = stepId } } } }
  local account = {}
  if options then
    account.NoirGuidesDB = { schema = 2, profiles = { Default = options }, defaultProfile = "Default" }
  end
  return { account = account, characters = { [KEY] = { NoirGuidesCharDB = db } } }
end

-- A character logged in with its place saved. opts: section, step, level, class, race, zone, options, afterLoad,
-- screen.
local function at(opts)
  opts = opts or {}
  local c = sample3({ race = opts.race, class = opts.class or "MAGE", level = opts.level or 2, zone = opts.zone,
    screen = opts.screen, afterLoad = opts.afterLoad,
    saved = savedAt(opts.section or DEATHKNELL, opts.step or "a363", opts.options) })
  c:login()
  c:advance(0.5)
  return c, c.G.Noir, c.G.Noir.Menu
end

local function texts(M, level)
  local out = {}
  local read = M.Read().levels[level]
  for i, row in ipairs(read and read.rows or {}) do out[i] = row.text end
  return out
end

-- The index of the row of `level` whose text is `text`.
local function rowIndex(M, level, text)
  local read = M.Read().levels[level]
  for i, row in ipairs(read and read.rows or {}) do
    if row.text == text then return i end
  end
  error("no row \"" .. tostring(text) .. "\" in menu level " .. tostring(level), 2)
end

local function row(M, level, text)
  return M.Row(level, rowIndex(M, level, text))
end

local function placeId(Noir)
  local _, _, _, step = Noir.Progress.Place()
  return step and step.id
end

local function spy(t, name)
  local calls = {}
  t[name] = function(...) calls[#calls + 1] = { ... } end
  return calls
end

-- Opens the main menu with a right-click on the window's header, the cursor at (x, y).
local function openMain(c, Noir, x, y)
  c:setCursor(x, y)
  ok(c:click(Noir.Window.Header(), "RightButton"), "the header takes the right-click")
  eq(c.errors, {}, "opening the menu raised no error")
  ok(Noir.Menu.IsOpen(), "the main menu is open")
end

-- The rows of the window's step list by step number.
local function listRow(W, n)
  for i, r in ipairs(W.Read().list) do
    if r.n == n then return W.Row(i) end
  end
  error("no list row for step " .. tostring(n), 2)
end

-- A route for Orcs with `count` sections, all in the 1-20 band, chained one after another.
local function orcRoute(count)
  local sections = {}
  for i = 1, count do
    local low = 1 + math.floor((i - 1) * 18 / count)
    sections[i] = {
      id = string.format("orc-%02d-%02d-durotar-%02d", low, low + 1, i),
      name = string.format("%d-%d Durotar part %d", low, low + 1, i),
      group = "Horde", subgroup = "1-20", minLevel = low, maxLevel = low + 1, zone = 14,
      start = (i == 1) or nil,
      next = (i < count) and { { section = string.format("orc-%02d-%02d-durotar-%02d", 1 + math.floor(i * 18 / count),
        2 + math.floor(i * 18 / count), i + 1) } } or {},
      steps = { { id = "n" .. i, at = { zone = 14, x = 50, y = 50 }, lines = { { kind = "manual", text = "Part " .. i .. "." } } } },
    }
  end
  return { format = 3, race = "Orc", faction = "Horde", sections = sections }
end

-- The main menu opens beside the guide window (right of it when it fits, else left), never over it.
local function besideWindow(c, Noir, M)
  local ml, mb, mr, mt = c:rectOf(M.Level(1))
  local wl, wb, wr, wt = c:rectOf(Noir.Window.frame)
  ok(mr <= wl + 1e-6 or ml >= wr - 1e-6, "the menu does not cover the window")
  near(mt, wt, 1e-6, "its top level with the window's top")
end

test("the main menu opens beside the window from the header and from the menu button", function()
  local c, Noir, M = at()
  openMain(c, Noir, 400, 500)
  besideWindow(c, Noir, M)
  eq(texts(M, 1), { "Choose a section", "Reload section", "Find my place again", "Step", "Show the arrow",
    "Show all map pins", "Lock windows", "Options", "Setup wizard", "Quest cleanup", "Talents", "Professions",
    "Report a problem", "Preview window positions", "More", "Hide Noir Guides" })
  local rows = M.Read().levels[1].rows
  eq(rows[1].sub, true, "the picker is a submenu")
  eq(rows[4].sub, true, "so is Step")
  eq(rows[5].checked, true, "the arrow is shown")
  eq(rows[7].checked, false, "windows are not locked")
  M.Close()
  no(M.IsOpen())
  c:setCursor(300, 400)
  ok(c:click(Noir.Window.MenuButton()), "the menu button takes the click")
  ok(M.IsOpen())
  besideWindow(c, Noir, M)
  eq(c:slashCount(), 0)
  eq(c:offScreen(), {})
end)

test("a submenu opens to the right, and to the left at the screen's right edge", function()
  local c, Noir, M = at()
  local W = c.G.GetScreenWidth()
  openMain(c, Noir, 200, 600)
  ok(c:hover(row(M, 1, "Choose a section")), "the row takes the mouse")
  eq(#M.Read().levels, 2, "hovering opens the submenu")
  local _, _, right1 = c:rectOf(M.Level(1))
  local left2 = c:rectOf(M.Level(2))
  near(left2, right1, 1e-6, "to the right of the menu")
  -- Hovering a row without a submenu closes the deeper level.
  c:hover(row(M, 1, "Reload section"))
  eq(#M.Read().levels, 1)
  M.Close()
  -- a menu opened at the cursor by the right screen edge (the main menu itself follows the window)
  c:setCursor(W - 10, 600)
  M.Open(M.MainItems(), { title = "Noir Guides" })
  local _, _, rightMain = c:rectOf(M.Level(1))
  ok(rightMain <= W + 1e-6, "the menu flips to the cursor's left")
  c:hover(row(M, 1, "Choose a section"))
  local leftMain = c:rectOf(M.Level(1))
  local _, _, right2 = c:rectOf(M.Level(2))
  near(right2, leftMain, 1e-6, "the submenu opens to the left")
  eq(c:offScreen(), {})
end)

test("a long picker is capped to the screen, scrolls with the wheel and opens at the current section", function()
  local route = orcRoute(60)
  local current = route.sections[45].id
  local c, Noir, M = at({ race = "Orc", class = "WARRIOR", level = 1, zone = 14, section = current, step = "n45",
    afterLoad = function(client) client.G.Noir.Route("horde-orc", route) end })
  eq(Noir.Guide.Current(), current, "the saved section is loaded")
  openMain(c, Noir, 100, 700)
  c:hover(row(M, 1, "Choose a section"))
  c:hover(row(M, 2, "Horde"))
  c:hover(row(M, 3, "1-20"))
  local level = M.Read().levels[4]
  eq(#level.rows, 60, "every section is a row")
  local H = c.G.GetScreenHeight()
  local _, bottom, _, top = c:rectOf(M.Level(4))
  ok(top - bottom <= Noir.Screen.MAX_SHARE * H + 1e-6, "capped to 90% of the screen")
  local index = rowIndex(M, 4, Noir.Guide.Name(Noir.Guide.Section(current)))
  eq(level.rows[index].current, true, "the section played is highlighted")
  ok(level.scroll > 0, "the level opens scrolled")
  local _, rowBottom, _, rowTop = c:rectOf(M.Row(4, index))
  local _, listBottom, _, listTop = c:rectOf(M.List(4))
  ok(rowTop <= listTop + 1e-6 and rowBottom >= listBottom - 1e-6, "the current section is in view")
  local before = level.scroll
  ok(c:wheel(M.Level(4), 1), "the level takes the wheel")
  local up = M.Read().levels[4].scroll
  ok(up < before, "the wheel scrolls up")
  c:wheel(M.Level(4), -1)
  ok(M.Read().levels[4].scroll > up, "and down")
  for _ = 1, 30 do c:wheel(M.Level(4), 1) end
  eq(M.Read().levels[4].scroll, 0, "up to the first row")
  local _, _, _, firstTop = c:rectOf(M.Row(4, 1))
  near(firstTop, listTop, 1e-6, "which is then the top row")
  eq(c:offScreen(), {})
end)

test("the picker lists groups, subgroups and sections in level order with ranges on the right", function()
  local c, Noir, M = at()
  openMain(c, Noir, 100, 700)
  c:hover(row(M, 1, "Choose a section"))
  eq(texts(M, 2), { "Horde" }, "the character's groups")
  c:hover(M.Row(2, 1))
  eq(texts(M, 3), { "1-20" }, "the group's subgroups")
  c:hover(M.Row(3, 1))
  eq(texts(M, 4), { "1-3 Deathknell", "3-5 Tirisfal Glades", "5-6 Silverpine Forest" }, "the sections in level order")
  local rights = {}
  for i, r in ipairs(M.Read().levels[4].rows) do rights[i] = r.right end
  eq(rights, { "1-4", "3-6", "5-8" }, "each level range on the right")
  M.Close()
  -- Sections for other races and classes, with the setting on.
  Noir.Options.Set("otherSections", true)
  openMain(c, Noir, 100, 700)
  c:hover(row(M, 1, "Choose a section"))
  eq(texts(M, 2), { "Horde", Noir.Guide.OTHER_GROUP })
  c:hover(M.Row(2, 2))
  c:hover(M.Row(3, 1))
  eq(texts(M, 4), { "1-5 Northshire" })
  eq(c:offScreen(), {})
end)

test("the current section is highlighted; 'your level' and 'passed' markers are set", function()
  local c, Noir, M = at({ level = 5, section = TIRISFAL, step = "a365", options = { outlevel = false } })
  eq(Noir.Guide.Current(), TIRISFAL)
  openMain(c, Noir, 100, 700)
  c:hover(row(M, 1, "Choose a section"))
  eq(M.Read().levels[2].rows[1].current, true, "the group holding the current section is marked")
  c:hover(M.Row(2, 1))
  eq(M.Read().levels[3].rows[1].current, true, "so is the subgroup")
  c:hover(M.Row(3, 1))
  local rows = M.Read().levels[4].rows
  eq({ rows[1].current, rows[2].current, rows[3].current }, { false, true, false })
  eq({ rows[1].marker, rows[2].marker, rows[3].marker }, { "passed", "level", "level" })
  local tab = M.Row(4, 1).marker
  ok(tab and tab:IsShown(), "a colored tab shows the marker")
  local r, g, b = tab:GetVertexColor()
  local dr, dg, db = Noir.Theme.Color("dim")
  near(r + g + b, dr + dg + db, 1e-3, "in the dim color for a passed range")
  r, g, b = M.Row(4, 2).marker:GetVertexColor()
  local lr, lg, lb = Noir.Theme.Color("lamp")
  near(r + g + b, lr + lg + lb, 1e-3, "in the lamp color for the character's level")
  eq(c:offScreen(), {})
end)

test("picking a section loads it and offers the cleanup 3 s later when the setting is on", function()
  local c, Noir, M = at()
  local offers = spy(Noir.Cleanup, "Offer")
  openMain(c, Noir, 100, 700)
  c:hover(row(M, 1, "Choose a section"))
  c:hover(M.Row(2, 1))
  c:hover(M.Row(3, 1))
  ok(c:click(row(M, 4, "3-5 Tirisfal Glades")), "the section row takes the click")
  eq(Noir.Guide.Current(), TIRISFAL, "the section is loaded")
  eq(Noir.char.guide.how, "hand", "by hand")
  eq((Noir.Progress.Place()), TIRISFAL, "and placed")
  no(M.IsOpen(), "the menu closes")
  c:advance(2.9)
  eq(#offers, 0, "not yet")
  c:advance(0.2)
  eq(#offers, 1, "3 s later the cleanup is offered")
  -- The same section again: nothing changed, nothing offered.
  openMain(c, Noir, 100, 700)
  c:hover(row(M, 1, "Choose a section"))
  c:hover(M.Row(2, 1))
  c:hover(M.Row(3, 1))
  c:click(row(M, 4, "3-5 Tirisfal Glades"))
  c:advance(4)
  eq(#offers, 1, "the same section is no change")
  -- With the setting off, no offer.
  Noir.Options.Set("offerCleanup", false)
  openMain(c, Noir, 100, 700)
  c:hover(row(M, 1, "Choose a section"))
  c:hover(M.Row(2, 1))
  c:hover(M.Row(3, 1))
  c:click(row(M, 4, "5-6 Silverpine Forest"))
  eq(Noir.Guide.Current(), SILVERPINE)
  c:advance(4)
  eq(#offers, 1, "switched off: no offer")
  eq(c:slashCount(), 0)
  eq(c:offScreen(), {})
end)

test("finding the place in another section offers the cleanup 3 s later", function()
  local c, Noir, M = at()
  local offers = spy(Noir.Cleanup, "Offer")
  for _, id in ipairs({ 363, 364, 376, 3901, 8 }) do c:markCompleted(id) end
  c:acceptQuest(365)
  c:advance(0.3)
  openMain(c, Noir, 100, 700)
  c:click(row(M, 1, "Find my place again"))
  c:click(Noir.Panel.ConfirmButton("yes"))
  c:advance(0.3)
  eq(Noir.Guide.Current(), TIRISFAL, "the quest log places the character in the next section")
  eq(Noir.char.guide.how, "hand", "a change made by hand")
  c:advance(2.6)
  eq(#offers, 0, "not yet")
  c:advance(0.2)
  eq(#offers, 1, "3 s later the cleanup is offered, as after picking a section")
  -- With the setting off, no offer.
  Noir.Options.Set("offerCleanup", false)
  Noir.Guide.Select(DEATHKNELL, "hand")
  c:advance(0.3)
  openMain(c, Noir, 100, 700)
  c:click(row(M, 1, "Find my place again"))
  c:click(Noir.Panel.ConfirmButton("yes"))
  c:advance(4)
  eq(Noir.Guide.Current(), TIRISFAL)
  eq(#offers, 1, "the setting is off")
  eq(c:offScreen(), {})
end)

test("Escape closes the whole menu; so does a click outside", function()
  local c, Noir, M = at()
  openMain(c, Noir, 100, 700)
  c:hover(row(M, 1, "Choose a section"))
  c:hover(M.Row(2, 1))
  eq(#M.Read().levels, 3)
  ok(c:pressKey("ESCAPE"), "the menu takes Escape")
  no(M.IsOpen(), "Escape closes every level")
  eq(M.Read().levels, {})
  no(M.Level(1):IsShown())
  openMain(c, Noir, 100, 700)
  c:hover(row(M, 1, "Step"))
  ok(c:click(M.Catcher()), "a click outside the menu lands on the catcher")
  no(M.IsOpen(), "and closes the menu")
  no(M.Catcher():IsShown(), "the catcher goes with it")
  -- Other keys pass through to the game while the menu is open.
  openMain(c, Noir, 100, 700)
  c:pressKey("W")
  ok(M.IsOpen(), "a key other than Escape leaves the menu open")
  ok(M.Catcher():GetPropagateKeyboardInput(), "and passes the key on")
  eq(c:offScreen(), {})
end)

test("every step menu entry does what it says", function()
  local c, Noir, M = at()
  local W = Noir.Window
  eq(placeId(Noir), "a363")
  -- Go to this step (a right-click on the list row of step 5).
  c:setCursor(300, 500)
  ok(c:click(listRow(W, 5), "RightButton"))
  ok(M.IsOpen(), "the step menu is open")
  eq(texts(M, 1), { "Go to this step", "Back to the last open step", "Choose another section", "Reload section",
    "Options", "Report a problem with this step", "Close" }, "a step that is not current has no skip entry")
  c:click(row(M, 1, "Go to this step"))
  eq(placeId(Noir), "o364.o376", "went to step 5")
  no(M.IsOpen())
  -- Back to the last open step.
  c:click(listRow(W, 5), "RightButton")
  ok(c:click(row(M, 1, "Back to the last open step")))
  eq(placeId(Noir), "a3901", "back to the nearest earlier step that is not done (the reminder is not one)")
  -- Skip this step: only on the current step.
  c:click(listRow(W, 3), "RightButton")
  eq(texts(M, 1)[2], "Skip this step")
  c:click(row(M, 1, "Skip this step"))
  c:advance(0.3)
  ok(placeId(Noir) ~= "a3901", "the current step was skipped")
  local why = Noir.Why.ForStep(DEATHKNELL, "a3901")
  ok(why, "and the why-log says why")
  -- Choose another section opens the picker.
  c:click(listRow(W, 1), "RightButton")
  c:hover(row(M, 1, "Choose another section"))
  eq(texts(M, 2), { "Horde" })
  M.Close()
  -- Reload section loads the section again.
  local loads = {}
  local load = Noir.Progress.Load
  Noir.Progress.Load = function(id) loads[#loads + 1] = id return load(id) end
  c:click(listRow(W, 1), "RightButton")
  c:click(row(M, 1, "Reload section"))
  eq(loads, { DEATHKNELL })
  Noir.Progress.Load = load
  -- Options and the problem report, by name at click time.
  Noir.SettingsPanel = Noir.SettingsPanel or {}
  local opened = spy(Noir.SettingsPanel, "Open")
  c:click(listRow(W, 1), "RightButton")
  c:click(row(M, 1, "Options"))
  eq(#opened, 1, "Options opens the settings")
  local reports = spy(Noir.Diagnostics, "Open")
  c:click(listRow(W, 1), "RightButton")
  c:click(row(M, 1, "Report a problem with this step"))
  eq(#reports, 1, "the bug report opens")
  eq(reports[1][1], 1, "for the step of the row (its index in the list)")
  -- Close.
  c:click(listRow(W, 1), "RightButton")
  ok(M.IsOpen())
  c:click(row(M, 1, "Close"))
  no(M.IsOpen())
  eq(c:slashCount(), 0)
  eq(c:offScreen(), {})
end)

test("every main menu entry does what it says", function()
  local c, Noir, M = at()
  local function pick(...)
    local path = { ... }
    openMain(c, Noir, 100, 700)
    for i = 1, #path - 1 do c:hover(row(M, i, path[i])) end
    ok(c:click(row(M, #path, path[#path])), path[#path] .. " takes the click")
  end
  pick("Show the arrow")
  eq(Noir.Options.Get("arrow"), false, "the arrow tick turns the arrow off")
  eq(M.Read().levels[1].rows[5].checked, false, "the menu stays open with the tick updated")
  M.Close()
  pick("Show the arrow")
  eq(Noir.Options.Get("arrow"), true)
  -- "Show all map pins": the world map always keeps the cards' own pins (worldPins 0 is not an off switch, #77),
  -- so the tick is on only while the minimap pins and the following steps' world map pins both show.
  openMain(c, Noir, 100, 700)
  eq(M.Read().levels[1].rows[rowIndex(M, 1, "Show all map pins")].checked, true, "every pin shows by default")
  M.Close()
  Noir.Options.Set("minimapPins", false)
  openMain(c, Noir, 100, 700)
  eq(M.Read().levels[1].rows[rowIndex(M, 1, "Show all map pins")].checked, false,
    "no minimap pins: not all pins show, so the tick is off")
  M.Close()
  pick("Show all map pins")
  eq({ Noir.Options.Get("minimapPins"), Noir.Options.Get("worldPins") }, { true, 8 }, "all pins on")
  M.Close()
  pick("Show all map pins")
  eq({ Noir.Options.Get("minimapPins"), Noir.Options.Get("worldPins") }, { false, 0 },
    "off: no minimap pins, only the cards' pins on the world map")
  eq(M.Read().levels[1].rows[rowIndex(M, 1, "Show all map pins")].checked, false)
  M.Close()
  pick("Show all map pins")
  eq({ Noir.Options.Get("minimapPins"), Noir.Options.Get("worldPins") }, { true, 8 }, "and on again")
  M.Close()
  pick("Lock windows")
  eq(Noir.Options.Get("locked"), true)
  M.Close()
  pick("Step", "Skip this step")
  c:advance(0.3)
  ok(placeId(Noir) ~= "a363", "Step > Skip this step skips")
  pick("Step", "Back to the last open step")
  eq(placeId(Noir), "a363", "Step > Back returns")
  local talents = spy(Noir.Talents, "Print")
  pick("Talents")
  eq(#talents, 1)
  local cleanup = spy(Noir.Cleanup, "Open")
  pick("Quest cleanup")
  eq(#cleanup, 1)
  local reports = spy(Noir.Diagnostics, "Open")
  pick("Report a problem")
  eq(#reports, 1)
  pick("Setup wizard")
  ok(Noir.Wizard.Read().shown, "the wizard opens")
  Noir.Wizard.Close()
  pick("Preview window positions")
  ok(Noir.Screen.IsPreview(), "the preview is on")
  pick("Preview window positions")
  no(Noir.Screen.IsPreview(), "and off again")
  -- Find my place again asks first, then places the character by the quest log.
  c:markCompleted(363)
  c:acceptQuest(364)
  c:acceptQuest(376)
  Noir.Progress.Jump(1, "list")
  c:advance(0.05)
  eq(placeId(Noir), "a363", "back on the first step by hand")
  pick("Find my place again")
  eq(Noir.Panel.ConfirmRead().shown, true, "a question first")
  c:click(Noir.Panel.ConfirmButton("yes"))
  c:advance(0.3)
  eq(placeId(Noir), "a3901", "placed again from the quest log, after the last quest it shows")
  pick("Hide Noir Guides")
  eq(Noir.Options.Get("shown"), false, "every window hidden")
  no(Noir.Window.frame:IsShown())
  eq(c:slashCount(), 0)
  eq(c:offScreen(), {})
end)

test("the menu works in combat", function()
  local c, Noir, M = at()
  c:enterCombat()
  openMain(c, Noir, 100, 700)
  c:hover(row(M, 1, "Choose a section"))
  c:hover(M.Row(2, 1))
  c:hover(M.Row(3, 1))
  eq(#M.Read().levels, 4)
  c:click(row(M, 4, "3-5 Tirisfal Glades"))
  eq(Noir.Guide.Current(), TIRISFAL, "a section picked in combat loads")
  openMain(c, Noir, 100, 700)
  c:click(row(M, 1, "Lock windows"))
  eq(Noir.Options.Get("locked"), true)
  c:pressKey("ESCAPE")
  no(M.IsOpen(), "Escape closes it in combat")
  ok(M.Catcher():GetPropagateKeyboardInput(), "in combat the addon may not stop Escape: the game sees it too (#78)")
  eq(c:takeViolations(), {}, "no keyboard change in combat")
  openMain(c, Noir, 100, 700)
  c:pressKey("W")
  ok(M.IsOpen())
  c:click(M.Catcher())
  no(M.IsOpen())
  c:leaveCombat()
  eq(c:offScreen(), {})
end)

test("no menu is off-screen at 1024x768 with the cursor in each corner", function()
  local c, Noir, M = at({ screen = { 1024, 768, 1 } })
  local W, H = c.G.GetScreenWidth(), c.G.GetScreenHeight()
  for _, corner in ipairs({ { 0, 0 }, { W, 0 }, { 0, H }, { W, H }, { W / 2, H / 2 } }) do
    openMain(c, Noir, corner[1], corner[2])
    c:hover(row(M, 1, "Choose a section"))
    c:hover(M.Row(2, 1))
    c:hover(M.Row(3, 1))
    eq(#M.Read().levels, 4)
    eq(c:offScreen(), {}, "cursor at " .. corner[1] .. ", " .. corner[2])
    M.Close()
    c:setCursor(corner[1], corner[2])
    c:click(listRow(Noir.Window, 2), "RightButton")
    c:hover(row(M, 1, "Choose another section"))
    eq(c:offScreen(), {}, "step menu, cursor at " .. corner[1] .. ", " .. corner[2])
    M.Close()
  end
end)
