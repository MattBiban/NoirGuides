-- Noir Guides, GPLv3. See LICENSE.
-- The settings panel (plan task E8, spec 4.1 entry points, 6.1, gap #3): registered in the game's options window
-- (modern or legacy) or opened as a free window, one control per option in its tab, the buttons of spec 6.1, the
-- questions before a reload, profiles, and the conflict warning. Driven by clicks and game events only; every test
-- ends with nothing off the screen.
use("tools/test-lua/sample/helper.lua")

local DEATHKNELL = "undead-01-03-deathknell"
local GUID = "Player-4444-0000002A"
local KEY = "Tester-Mock"

-- The tab of spec 6.1 each option key lives in.
local TAB_OF = {
  shown = "General", locked = "General", hideInRaid = "General", minimap = "General", minimapAngle = "General",
  windowHidden = "Guide window", cardsBelow = "Guide window", windowScale = "Guide window", fontSize = "Guide window", accent = "Guide window",
  stepList = "Guide window", hideFinished = "Guide window", otherSections = "Guide window", highlight = "Guide window",
  itemButtons = "Guide window", buttonBackground = "Guide window", buttonScale = "Guide window",
  backgroundAlpha = "Guide window",
  arrow = "Navigation", arrowScale = "Navigation", arrowText = "Navigation", minimapPins = "Navigation",
  pinRing = "Navigation", worldPins = "Navigation", pinSize = "Navigation", pinMerge = "Navigation",
  pinAlpha = "Navigation",
  autoQuests = "Automation", guideRewards = "Automation", rewardMarker = "Automation", bestReward = "Automation",
  train = "Automation", flights = "Automation", hearth = "Automation", dialogue = "Automation", buy = "Automation",
  targetButtons = "Automation", nameplates = "Automation", markers = "Automation",
  outlevel = "Route", groupQuests = "Route", talents = "Route",
  neverSkip = "Advanced", offerCleanup = "Advanced", conflicts = "Advanced", debug = "Advanced",
}

-- The buttons of spec 6.1 and the plan, by tab.
local BUTTONS = {
  General = { "wizard", "cleanup", "bug" },
  ["Guide window"] = { "resetButtons", "preview" },
  Navigation = { "resetArrow" },
  Advanced = { "findPlace" },
  Profiles = { "newProfile", "copyProfile", "deleteProfile", "resetProfile", "defaultProfile", "resetProgress" },
}

local function saved(options)
  local db = { schema = 2, owner = GUID, guide = { section = DEATHKNELL, how = "hand", wizard = true,
    places = { [DEATHKNELL] = { step = "a363" } } } }
  local account = {}
  if options then
    account.NoirGuidesDB = { schema = 2, profiles = { Default = options }, defaultProfile = "Default" }
  end
  return { account = account, characters = { [KEY] = { NoirGuidesCharDB = db } } }
end

-- A character logged in on the first step. opts: settingsApi, options, addons, screen, afterLoad.
local function at(opts)
  opts = opts or {}
  local c = sample3({ class = "MAGE", level = 2, settingsApi = opts.settingsApi or "modern", addons = opts.addons,
    screen = opts.screen, afterLoad = opts.afterLoad, saved = saved(opts.options) })
  c:login()
  c:advance(0.5)
  return c, c.G.Noir, c.G.Noir.SettingsPanel
end

local function control(S, key)
  for _, ctl in ipairs(S.Read().controls) do
    if ctl.key == key then return ctl end
  end
  return nil
end

local function menuRow(Noir, text)
  local read = Noir.Menu.Read().levels[1]
  for i, row in ipairs(read and read.rows or {}) do
    if row.text == text then return Noir.Menu.Row(1, i) end
  end
  error("no menu row " .. tostring(text), 2)
end

local function center(c, frame)
  local left, bottom, right, top = c:rectOf(frame)
  return (left + right) / 2, (bottom + top) / 2
end

-- The main menu's "Options" row, opened from the window's header.
local function openFromMenu(c, Noir)
  c:setCursor(300, 500)
  ok(c:click(Noir.Window.Header(), "RightButton"), "the header opens the main menu")
  ok(c:click(menuRow(Noir, "Options")), "the Options row takes the click")
end

test("the panel is registered in the modern options window", function()
  local c, Noir, S = at({ settingsApi = "modern" })
  eq(c:optionsCategories(), { "Noir Guides" })
  eq(#c:callsTo("Settings.RegisterCanvasLayoutCategory"), 1)
  eq(#c:callsTo("Settings.RegisterAddOnCategory"), 1)
  eq(S.Read().shown, false, "closed until opened")
  openFromMenu(c, Noir)
  eq(c:optionsOpenedTo(), "Noir Guides", "the main menu's Options opens the game's options window at the page")
  eq(S.Read().shown, true)
  eq(S.Read().tab, "General")
  eq(S.TABS, { "General", "Guide window", "Navigation", "Automation", "Route", "Advanced", "Profiles" })
  -- Another tab by clicking its name.
  ok(c:click(S.Tab("Navigation")))
  eq(S.Read().tab, "Navigation")
  ok(control(S, "arrowScale"), "the Navigation controls are listed")
  c:closeOptions()
  eq(S.Read().shown, false)
  eq(c:slashCount(), 0)
  eq(c:offScreen(), {})
end)

test("and in the legacy one", function()
  local c, Noir, S = at({ settingsApi = "legacy" })
  eq(c:optionsCategories(), { "Noir Guides" })
  eq(#c:callsTo("InterfaceOptions_AddCategory"), 1)
  openFromMenu(c, Noir)
  eq(c:optionsOpenedTo(), "Noir Guides")
  eq(S.Read().shown, true)
  S.Open("Automation")
  eq(S.Read().tab, "Automation")
  eq(c:offScreen(), {})
end)

test("and opens as a window when neither exists", function()
  for _, screen in ipairs({ { 1024, 768, 1 }, { 1920, 1080, 0.64 }, { 3840, 1080, 1 } }) do
    local c, Noir, S = at({ settingsApi = "none", screen = screen })
    eq(c:optionsCategories(), {})
    openFromMenu(c, Noir)
    eq(S.Read().shown, true, "a free window")
    local W, H = c.G.GetScreenWidth(), c.G.GetScreenHeight()
    local x, y = center(c, S.frame)
    near(x, W / 2, 1, "centered across")
    local _, bottom, _, top = c:rectOf(S.frame)
    ok(top <= H + 0.5 and bottom >= -0.5, "inside the screen")
    if top - bottom < H * 0.9 - 1 and top < H - 1 then near(y, H / 2 + 60, 1, "at the dialog's place") end
    for _, tab in ipairs(S.TABS) do
      ok(c:click(S.Tab(tab)), tab)
      eq(S.Read().tab, tab)
      eq(c:offScreen(), {}, tab .. " at " .. table.concat(screen, "x"))
    end
    ok(c:click(S.CloseButton()), "the window has a close button")
    eq(S.Read().shown, false)
    eq(c:offScreen(), {})
  end
end)

test("opening in combat waits for combat to end", function()
  local c, Noir, S = at({ settingsApi = "modern" })
  c:enterCombat()
  openFromMenu(c, Noir)
  eq(S.Read().shown, false, "not in combat")
  eq(c:optionsOpenedTo(), nil)
  c:advance(2)
  eq(S.Read().shown, false)
  c:leaveCombat()
  eq(S.Read().shown, true, "opened when combat ends")
  eq(c:optionsOpenedTo(), "Noir Guides")
  -- The free window waits too.
  local c2, Noir2, S2 = at({ settingsApi = "none" })
  c2:enterCombat()
  S2.Open("Route")
  eq(S2.Read().shown, false)
  c2:leaveCombat()
  eq(S2.Read().shown, true)
  eq(S2.Read().tab, "Route", "on the tab asked for")
  eq(c2:offScreen(), {})
end)

test("every option key has one control in its tab, and changing it changes the option", function()
  local c, Noir, S = at({ settingsApi = "modern" })
  local Options = Noir.Options
  local seen = {}
  for _, tab in ipairs(S.TABS) do
    S.Open(tab)
    eq(S.Read().tab, tab)
    for _, ctl in ipairs(S.Read().controls) do
      if Options.DEFAULTS[ctl.key] ~= nil then
        ok(not seen[ctl.key], ctl.key .. " has one control")
        seen[ctl.key] = tab
      end
    end
    for _, key in ipairs(BUTTONS[tab] or {}) do
      local ctl = control(S, key)
      ok(ctl and ctl.kind == "button", tab .. " has the button " .. key)
    end
  end
  for key in pairs(Options.DEFAULTS) do
    eq(seen[key], TAB_OF[key], key .. " in its tab")
  end
  -- Each control changes its option.
  for _, tab in ipairs(S.TABS) do
    S.Open(tab)
    for _, ctl in ipairs(S.Read().controls) do
      local key = ctl.key
      local default = Options.DEFAULTS[key]
      if default ~= nil then
        eq(ctl.value, Options.Get(key), key .. " shows its value")
        local frame = S.Control(key)
        ok(frame and frame:IsVisible(), key .. " is on screen in its tab")
        if ctl.kind == "tick" then
          eq(type(default), "boolean", key)
          local before = Options.Get(key)
          ok(c:click(frame), key .. " takes the click")
          if Noir.Panel.ConfirmRead().shown then c:click(Noir.Panel.ConfirmButton("yes")) end
          eq(Options.Get(key), not before, key .. " ticked")
          eq(control(S, key).value, not before, key .. " shows the new value")
        elseif ctl.kind == "slider" then
          local range = Options.RANGES[key]
          local before = Options.Get(key)
          local delta = before >= range.max and -1 or 1
          ok(c:wheel(frame, delta), key .. " takes the wheel")
          local after = Options.Get(key)
          ok(delta > 0 and after > before or after < before, key .. " moved by the wheel")
          ok(after >= range.min and after <= range.max, key .. " stays in its range")
          eq(control(S, key).value, after)
        else
          eq(ctl.kind, "choice", key)
        end
      end
    end
  end
  eq(c.reloads, 0, "nothing reloaded the interface")
  eq(c:slashCount(), 0)
end)

test("a slider follows a click on its track and a drag of its thumb", function()
  local c, Noir, S = at({ settingsApi = "none" })
  S.Open("Guide window")
  local slider = S.Control("windowScale")
  local left, bottom, right, top = c:rectOf(S.Track("windowScale"))
  c:setCursor(right, (bottom + top) / 2)
  ok(c:click(slider))
  near(Noir.Options.Get("windowScale"), 2, 1e-9, "the right end is the most")
  c:setCursor(left, (bottom + top) / 2)
  c:drag(slider, 0, 0)
  near(Noir.Options.Get("windowScale"), 0.2, 1e-9, "dragged to the left end: the least")
  c:setCursor(left + (right - left) * 0.5, (bottom + top) / 2)
  ok(c:click(slider))
  near(Noir.Options.Get("windowScale"), 1.1, 1e-9, "the middle, on a step of 0.05")
  eq(c:offScreen(), {})
end)

test("the accent color asks and reloads the UI", function()
  local c, Noir, S = at({ settingsApi = "modern" })
  S.Open("Guide window")
  eq(control(S, "accent").value, "class", "the class color by default")
  c:setCursor(400, 400)
  ok(c:click(S.Control("accent")))
  local texts = {}
  for _, row in ipairs(Noir.Menu.Read().levels[1].rows) do texts[#texts + 1] = row.text end
  eq(texts, { "Class color (automatic)", "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage",
    "Warlock", "Druid", "Gold", "Black" }, "the menu lists every theme by name")
  ok(c:click(menuRow(Noir, "Gold")))
  eq(Noir.Panel.ConfirmRead().shown, true, "a question first")
  c:click(Noir.Panel.ConfirmButton("no"))
  eq(Noir.Options.Get("accent"), "class", "no: nothing changes")
  eq(c.reloads, 0)
  ok(c:click(S.Control("accent")))
  ok(c:click(menuRow(Noir, "Gold")))
  c:click(Noir.Panel.ConfirmButton("yes"))
  eq(Noir.Options.Get("accent"), "gold")
  eq(c.reloads, 1, "yes: the interface reloads")
  ok(c:click(S.Control("accent")))
  ok(c:click(menuRow(Noir, "Black")))
  c:click(Noir.Panel.ConfirmButton("yes"))
  eq(Noir.Options.Get("accent"), "black", "the stored value is the lowercase key")
  eq(c.reloads, 2)
  eq(c:offScreen(), {})
end)

test("the background opacity slider applies without a reload", function()
  local c, Noir, S = at({ settingsApi = "none" })
  S.Open("Guide window")
  eq(control(S, "backgroundAlpha").value, 0.75, "75% by default")
  local slider = S.Control("backgroundAlpha")
  local left, bottom, right, top = c:rectOf(S.Track("backgroundAlpha"))
  c:setCursor(right, (bottom + top) / 2)
  ok(c:click(slider))
  near(Noir.Options.Get("backgroundAlpha"), 1, 1e-9, "the right end is opaque")
  c:setCursor(left, (bottom + top) / 2)
  c:drag(slider, 0, 0)
  near(Noir.Options.Get("backgroundAlpha"), 0.2, 1e-9, "dragged to the left end: the least")
  eq(Noir.Panel.ConfirmRead().shown, false, "no question")
  eq(c.reloads, 0, "no reload")
  eq(c:offScreen(), {})
end)

test("font size asks and reloads the UI; outlevel asks and reloads the section", function()
  local c, Noir, S = at({ settingsApi = "modern" })
  S.Open("Guide window")
  eq(control(S, "fontSize").value, "standard")
  c:setCursor(400, 400)
  ok(c:click(S.Control("fontSize")))
  ok(Noir.Menu.IsOpen(), "the choices open as a menu at the cursor")
  ok(c:click(menuRow(Noir, "large")))
  eq(Noir.Panel.ConfirmRead().shown, true, "a question first")
  c:click(Noir.Panel.ConfirmButton("no"))
  eq(Noir.Options.Get("fontSize"), "standard", "no: nothing changes")
  eq(c.reloads, 0)
  ok(c:click(S.Control("fontSize")))
  ok(c:click(menuRow(Noir, "large")))
  c:click(Noir.Panel.ConfirmButton("yes"))
  eq(Noir.Options.Get("fontSize"), "large")
  eq(c.reloads, 1, "yes: the interface reloads")
  -- outlevel
  local loads = {}
  local real = Noir.Progress.Load
  Noir.Progress.Load = function(id, ...)
    loads[#loads + 1] = id
    return real(id, ...)
  end
  S.Open("Route")
  ok(c:click(S.Control("outlevel")))
  eq(Noir.Panel.ConfirmRead().shown, true, "a question first")
  c:click(Noir.Panel.ConfirmButton("no"))
  eq(Noir.Options.Get("outlevel"), true)
  eq(loads, {})
  ok(c:click(S.Control("outlevel")))
  c:click(Noir.Panel.ConfirmButton("yes"))
  eq(Noir.Options.Get("outlevel"), false)
  eq(loads, { DEATHKNELL }, "the section is loaded again")
  eq(c:offScreen(), {})
end)

test("reset buttons put the arrow and item buttons back at their defaults", function()
  local c, Noir, S = at({ settingsApi = "modern" })
  local Screen = Noir.Screen
  Screen.Preview(true)
  local arrow = Noir.Arrow.frame
  local items
  for _, entry in ipairs(Screen.Registered()) do
    if entry.key == "items" then items = entry.frame end
  end
  ok(arrow:IsShown() and items and items:IsShown(), "both shown by the preview")
  c:drag(arrow, -200, -150)
  c:drag(items, 150, 120)
  ok(Noir.Options.Position("arrow") and Noir.Options.Position("items"), "both places saved")
  local W, H = c.G.GetScreenWidth(), c.G.GetScreenHeight()
  S.Open("Navigation")
  ok(c:click(S.Control("resetArrow")))
  local x, y = center(c, arrow)
  local d = Screen.DEFAULTS.arrowReset
  near(x, W / 2 + d[3], 0.5, "the arrow back across")
  near(y, H / 2 + d[4], 0.5, "slightly above the screen's centre")
  S.Open("Guide window")
  ok(c:click(S.Control("resetButtons")))
  eq(Noir.Options.Position("items"), nil, "the item buttons' place is forgotten")
  x, y = center(c, items)
  near(x, W / 2, 0.5)
  near(y, H / 2 + Screen.DEFAULTS.items[4], 0.5)
  Screen.Preview(false)
  eq(c:offScreen(), {})
end)

test("profiles can be made, copied, used, deleted and reset, and window places follow the profile", function()
  local c, Noir, S = at({ settingsApi = "modern" })
  local Options = Noir.Options
  local window = Noir.Window.frame
  S.Open("Profiles")
  eq(control(S, "profile").value, "Default")
  Options.Set("arrowScale", 1.5)
  local defaultLeft, _, _, defaultTop = c:rectOf(window)
  -- New: an empty profile under the name typed, used at once.
  S.Control("profileName"):SetText("Second")
  ok(c:click(S.Control("newProfile")))
  eq(Options.Profiles(), { "Default", "Second" })
  eq(Options.Profile(), "Second")
  eq(Options.Get("arrowScale"), 1, "a new profile has the defaults")
  eq(control(S, "profile").value, "Second")
  c:drag(Noir.Window.Header(), 120, -80)
  local secondLeft, _, _, secondTop = c:rectOf(window)
  ok(math.abs(secondLeft - defaultLeft) > 50, "the window moved in the second profile")
  -- Use: the choice lists the profiles; the window goes to that profile's place.
  c:setCursor(400, 400)
  ok(c:click(S.Control("profile")))
  ok(c:click(menuRow(Noir, "Default")))
  eq(Options.Profile(), "Default")
  local left, _, _, top = c:rectOf(window)
  near(left, defaultLeft, 0.5, "the window at the Default profile's place")
  near(top, defaultTop, 0.5)
  ok(c:click(S.Control("profile")))
  ok(c:click(menuRow(Noir, "Second")))
  left, _, _, top = c:rectOf(window)
  near(left, secondLeft, 0.5, "and back at the second profile's place")
  near(top, secondTop, 0.5)
  ok(c:click(S.Control("profile")))
  ok(c:click(menuRow(Noir, "Default")))
  -- Copy: a new profile with the settings of the one in use.
  S.Control("profileName"):SetText("Third")
  ok(c:click(S.Control("copyProfile")))
  eq(Options.Profiles(), { "Default", "Second", "Third" })
  eq(Options.Profile(), "Third")
  eq(Options.Get("arrowScale"), 1.5, "copied from Default")
  -- With no name typed, a free name is made up.
  S.Control("profileName"):SetText("")
  ok(c:click(S.Control("newProfile")))
  eq(#Options.Profiles(), 4)
  ok(c:click(S.Control("profile")))
  ok(c:click(menuRow(Noir, "Third")))
  -- Delete: another profile, after a question.
  ok(c:click(S.Control("deleteProfile")))
  ok(Noir.Menu.IsOpen(), "the profiles that can be deleted")
  local rows = {}
  for _, row in ipairs(Noir.Menu.Read().levels[1].rows) do rows[#rows + 1] = row.text end
  no(rows[1] == "Third" or rows[2] == "Third" or rows[3] == "Third", "not the one in use")
  ok(c:click(menuRow(Noir, "Second")))
  eq(Noir.Panel.ConfirmRead().shown, true)
  c:click(Noir.Panel.ConfirmButton("yes"))
  eq(#Options.Profiles(), 3)
  for _, name in ipairs(Options.Profiles()) do no(name == "Second", "Second is deleted") end
  -- Reset: the profile in use back to its defaults, after a question.
  ok(c:click(S.Control("resetProfile")))
  c:click(Noir.Panel.ConfirmButton("yes"))
  eq(Options.Get("arrowScale"), 1)
  -- The default for new characters.
  ok(c:click(S.Control("defaultProfile")))
  eq(Noir.db.defaultProfile, "Third")
  -- Reset guide progress for this character, after a question.
  ok(Noir.char.guide.places[DEATHKNELL], "a place is saved")
  ok(c:click(S.Control("resetProgress")))
  eq(Noir.Panel.ConfirmRead().shown, true)
  c:click(Noir.Panel.ConfirmButton("no"))
  eq(Noir.char.guide.places[DEATHKNELL].step, "a363", "no: kept")
  ok(c:click(S.Control("resetProgress")))
  c:click(Noir.Panel.ConfirmButton("yes"))
  c:advance(0.5)
  ok(Noir.Guide.Current(), "a section is chosen again")
  eq(Noir.char.guide.wizard, true, "the wizard is not asked again")
  local last = Noir.char.why[#Noir.char.why]
  has(last.text, "reset")
  eq(c:slashCount(), 0)
  eq(c:offScreen(), {})
end)

test("the conflict warning comes once, 20 s after login", function()
  local c = at({ addons = { "TomTom" } })
  c:takeChat()
  c:advance(19)
  eq(string.find(c:chatText(), "TomTom", 1, true), nil, "not before 20 s")
  c:advance(1.1)
  local text = c:chatText()
  ok(string.find(text, "TomTom", 1, true), "20 s after login")
  local _, count = string.gsub(text, "TomTom is loaded", "")
  eq(count, 1)
  c:advance(120)
  _, count = string.gsub(c:chatText(), "TomTom is loaded", "")
  eq(count, 1, "once")
  -- Not with the setting off, nor without another arrow addon; the modern API is read too.
  local quiet = at({ addons = { "TomTom" }, options = { conflicts = false } })
  quiet:advance(30)
  eq(string.find(quiet:chatText(), "TomTom", 1, true), nil)
  local alone = at({})
  alone:advance(30)
  eq(string.find(alone:chatText(), "TomTom is loaded", 1, true), nil)
  local modern = sample3({ api = "modern", class = "MAGE", level = 2, addons = { "TomTom" }, saved = saved() })
  modern:login()
  modern:advance(21)
  ok(string.find(modern:chatText(), "TomTom is loaded", 1, true))
end)
