-- Noir Guides, GPLv3. See LICENSE.
-- Commands (plan task E8, spec 6.3, gap #49): one command word; "/noir" alone opens the settings; every command
-- also has a mouse path (Menu.MOUSE_PATHS), and following that path by clicks does what typing the command does.
-- The preview and hide-in-raid are checked end to end over every registered window.
use("tools/test-lua/sample/helper.lua")

local DEATHKNELL = "undead-01-03-deathknell"
local GUID = "Player-4444-0000002A"
local KEY = "Tester-Mock"

local COMMANDS = { "back", "bug", "cleanup", "help", "hide", "preview", "problems", "professions", "show", "skip",
  "state", "step", "sync", "talents", "toggle", "version", "why", "wizard" }

local function saved(options)
  local db = { schema = 2, owner = GUID, guide = { section = DEATHKNELL, how = "hand", wizard = true,
    places = { [DEATHKNELL] = { step = "a363" } } } }
  local account = {}
  if options then
    account.NoirGuidesDB = { schema = 2, profiles = { Default = options }, defaultProfile = "Default" }
  end
  return { account = account, characters = { [KEY] = { NoirGuidesCharDB = db } } }
end

local function at(opts)
  opts = opts or {}
  local c = sample3({ class = "MAGE", level = 2, settingsApi = opts.settingsApi or "modern",
    saved = saved(opts.options) })
  c:login()
  c:advance(0.5)
  -- Some history, so that "skip", "back", "why" and "sync" have something to work on.
  c:markCompleted(363)
  c:acceptQuest(364)
  c:advance(0.5)
  c.G.Noir.Progress.Jump(1, "list")
  c:advance(0.5)
  c:takeChat()
  return c, c.G.Noir
end

local function registered(Noir)
  local out = {}
  for _, entry in ipairs(Noir.Screen.Registered()) do out[entry.key] = entry.frame end
  return out
end

-- What a command can change, as plain data.
local function snapshot(c, Noir)
  local shown = {}
  for key, frame in pairs(registered(Noir)) do shown[key] = frame:IsShown() and true or false end
  local options = {}
  for key in pairs(Noir.Options.DEFAULTS) do options[key] = Noir.Options.Get(key) end
  local _, index, _, step = Noir.Progress.Place()
  local chat = {}
  for i, line in ipairs(c:takeChat()) do chat[i] = line end
  return {
    chat = chat, shown = shown, options = options, preview = Noir.Screen.IsPreview(),
    confirm = Noir.Panel.ConfirmRead(), section = Noir.Guide.Current(), index = index, step = step and step.id,
    settings = Noir.SettingsPanel.Read().shown, menu = Noir.Menu.IsOpen(), wizard = Noir.Wizard.Read().shown,
    bug = Noir.Diagnostics.Read().shown, options_window = c:optionsOpenedTo(),
  }
end

local function rowIndex(Noir, level, text)
  local read = Noir.Menu.Read().levels[level]
  for i, row in ipairs(read and read.rows or {}) do
    if row.text == text then return i end
  end
  error("no row \"" .. tostring(text) .. "\" in menu level " .. tostring(level), 2)
end

-- Follows a mouse path by clicks: "main" opens the main menu with a right click on the minimap button, then
-- hovers each submenu row and clicks the last row; "minimap" clicks the minimap button with the button named.
local function follow(c, Noir, path)
  local button = Noir.MinimapButton.frame
  if path[1] == "minimap" then
    ok(c:click(button, path[2]), "the minimap button takes the " .. tostring(path[2]))
    return
  end
  eq(path[1], "main", "a path starts at the main menu or the minimap button")
  c:setCursor(300, 500)
  ok(c:click(button, "RightButton"), "the minimap button opens the main menu")
  for i = 2, #path do
    local level = i - 1
    local row = Noir.Menu.Row(level, rowIndex(Noir, level, path[i]))
    if i < #path then
      ok(c:hover(row), "hover " .. path[i])
      eq(#Noir.Menu.Read().levels, level + 1, path[i] .. " opened its submenu")
    else
      ok(c:click(row), "click " .. path[i])
    end
  end
end

test("/noir alone opens settings", function()
  local c, Noir = at({ settingsApi = "modern" })
  c:slash("/noir")
  eq(c:optionsOpenedTo(), "Noir Guides")
  eq(Noir.SettingsPanel.Read().shown, true)
  local free, Noir2 = at({ settingsApi = "none" })
  free:slash("/noir   ")
  eq(Noir2.SettingsPanel.Read().shown, true, "the free window without an options window")
  eq(free:offScreen(), {})
  -- Help says so.
  free:takeChat()
  free:slash("/noir help")
  has(free:chatText(), "/noir - ")
end)

test("every registered command is in MOUSE_PATHS and following that path by clicks does the same thing", function()
  local _, Noir = at()
  eq(Noir.Commands(), COMMANDS, "exactly the commands of spec 6.3 and the extras")
  for _, name in ipairs(COMMANDS) do
    local path = Noir.Menu.MOUSE_PATHS[name]
    ok(type(path) == "table" and #path >= 2, name .. " has a mouse path")
    -- "show" is tried with the windows hidden, everything else as the character logs in.
    local options = name == "show" and { shown = false } or nil
    local typed, A = at({ options = options })
    typed:slash("/noir " .. name)
    typed:advance(0.3)
    local byCommand = snapshot(typed, A)
    local clicked, B = at({ options = options })
    follow(clicked, B, path)
    clicked:advance(0.3)
    local byMouse = snapshot(clicked, B)
    eq(byMouse, byCommand, name .. ": the mouse path does what the command does")
    eq(clicked:slashCount(), 0, name)
    eq(clicked.errors, {}, name)
  end
end)

test("the preview button fills every registered window and returns to the section", function()
  local c, Noir = at({ settingsApi = "modern" })
  local S = Noir.SettingsPanel
  -- The quest cleanup and the bug report make their windows when first opened.
  Noir.Cleanup.Open()
  Noir.Cleanup.Close()
  Noir.Diagnostics.Open()
  Noir.Diagnostics.Close()
  local frames = registered(Noir)
  for _, key in ipairs({ "window", "arrow", "items", "targets", "wizard", "cleanup", "bug" }) do
    ok(frames[key], key .. " is registered")
  end
  local before = Noir.Window.Read()
  no(frames.wizard:IsShown())
  S.Open("Guide window")
  ok(c:click(S.Control("preview")))
  ok(Noir.Screen.IsPreview())
  ok(Noir.Window.Read().preview, "the window shows sample content")
  for _, key in ipairs({ "window", "arrow", "items", "targets", "wizard" }) do
    ok(frames[key]:IsShown(), key .. " shown with sample content to place it")
  end
  -- The quest cleanup and the bug report always open at the fixed Screen.DEFAULTS.dialog place and cannot be
  -- moved, so the preview has nothing to place there: they stay as they were (they take part in hide, show and
  -- hide in raid, checked below and in minimap.lua).
  no(frames.cleanup:IsShown(), "cleanup: nothing to place, not opened by the preview")
  no(frames.bug:IsShown(), "bug report: nothing to place, not opened by the preview")
  eq(c:offScreen(), {})
  ok(c:click(S.Control("preview")), "the same button ends the preview")
  no(Noir.Screen.IsPreview())
  local after = Noir.Window.Read()
  eq(after.preview, nil)
  eq(after.title, before.title, "back on the section")
  eq(after.cards, before.cards)
  no(frames.wizard:IsShown(), "the wizard was only there for the preview")
  no(frames.items:IsShown(), "no item on this step")
  no(frames.targets:IsShown())
  eq(c:offScreen(), {})
end)

test("with hide in raid on, joining a raid hides every registered window", function()
  local c, Noir = at({ settingsApi = "modern" })
  local S = Noir.SettingsPanel
  S.Open("General")
  ok(c:click(S.Control("hideInRaid")))
  eq(Noir.Options.Get("hideInRaid"), true)
  Noir.Cleanup.Open()
  Noir.Diagnostics.Open()
  Noir.Wizard.Open()
  Noir.Screen.Preview(true)
  local frames = registered(Noir)
  for _, key in ipairs({ "window", "arrow", "items", "targets", "wizard", "cleanup", "bug" }) do
    ok(frames[key]:IsShown(), key .. " shown before the raid")
  end
  c:joinRaid(true)
  for key, frame in pairs(frames) do no(frame:IsShown(), key .. " hidden in the raid") end
  c:advance(1)
  c:acceptQuest(376)
  c:advance(1)
  for key, frame in pairs(frames) do no(frame:IsShown(), key .. " stays hidden while things change") end
  c:joinRaid(false)
  for _, key in ipairs({ "window", "arrow", "items", "targets", "wizard", "cleanup", "bug" }) do
    ok(frames[key]:IsShown(), key .. " back after the raid")
  end
  Noir.Screen.Preview(false)
  -- With the setting off nothing hides.
  ok(c:click(S.Control("hideInRaid")))
  c:joinRaid(true)
  ok(frames.window:IsShown())
  eq(c:offScreen(), {})
end)
