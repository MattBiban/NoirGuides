-- Noir Guides, GPLv3. See LICENSE.
-- Core: the Noir namespace, saved variables, the event bus, timers and the /noir command.
-- Every other file of the addon builds on what this one defines and is loaded after it (see NoirGuides.toc).
local ADDON = ...

Noir = Noir or {}
local Noir = Noir

Noir.name = ADDON or "NoirGuides"
Noir.version = "dev"
-- Filled by the generated files in Data/. The tables exist from the start so that those files, and code that
-- reads them, work whether or not a data file is present.
Noir.Data = { quests = {}, npcs = {}, objects = {}, items = {}, zones = {}, flights = {} }
-- Things that went wrong and the player should be able to see: /noir problems. Newest last, at most 100.
Noir.problems = {}

local MAX_PROBLEMS = 100
-- What every chat line starts with. Plain here; UI/Theme.lua replaces it with the name in the design's accent color.
Noir.prefix = "Noir: "

-- ---------------------------------------------------------------------------------------------------------------
-- Chat output and the problem list
-- ---------------------------------------------------------------------------------------------------------------

function Noir.Print(text)
  text = tostring(Noir.prefix) .. tostring(text)
  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
    DEFAULT_CHAT_FRAME:AddMessage(text)
  else
    print(text)
  end
end

-- Hands an error to the client's error handler (the Lua error window or an error addon) without stopping the caller.
-- Every error the addon catches (event handlers, timers, commands) goes through Noir.ReportError, looked up at the
-- time of the error, so a module that wraps it (Diagnostics keeps the last few for /noir bug) sees all of them.
local function report(err)
  local handler = geterrorhandler and geterrorhandler()
  if handler then
    handler(err)
  else
    Noir.Print(tostring(err))
  end
end
Noir.ReportError = report

-- Records something the player should know about but that must not stop the addon: a route that failed its
-- checks, an event this client does not have, damaged saved variables.
function Noir.Problem(text)
  local list = Noir.problems
  list[#list + 1] = tostring(text)
  while #list > MAX_PROBLEMS do table.remove(list, 1) end
  Noir.Fire("NOIR_PROBLEM", text)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Event bus
--   Noir.On(event, fn)    fn(event, ...) is called for a game event or an internal one (name starts with NOIR_)
--   Noir.Off(event, fn)
--   Noir.Fire(event, ...) internal events only
-- Handlers run in the order they were added. An error in one goes to the error handler; the rest still run.
-- ---------------------------------------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
local handlers = {}    -- event -> array of functions (false where one was removed during delivery)
local delivering = 0   -- how many deliveries are in progress
local needsSweep = {}  -- event -> true when its array has holes
local unavailable = {} -- game events this client refused

-- The combat log is never registered: the Forever client shows its "blocked" popup for it even inside pcall.
local REFUSED = { COMBAT_LOG_EVENT_UNFILTERED = true, COMBAT_LOG_EVENT = true }

local function isInternal(event)
  return string.sub(event, 1, 5) == "NOIR_"
end

local function sweep()
  for event in pairs(needsSweep) do
    local list, kept = handlers[event], {}
    for i = 1, #list do
      if list[i] then kept[#kept + 1] = list[i] end
    end
    handlers[event] = kept
    needsSweep[event] = nil
  end
end

local function deliver(event, ...)
  local list = handlers[event]
  if not list then return end
  delivering = delivering + 1
  local count = #list -- handlers added during this delivery wait for the next event
  for i = 1, count do
    local fn = list[i]
    if fn then
      local good, err = pcall(fn, event, ...)
      if not good then Noir.ReportError(err) end
    end
  end
  delivering = delivering - 1
  if delivering == 0 and next(needsSweep) then sweep() end
end

-- Returns true when the handler will be called, false when this client does not have the event (or it is refused).
function Noir.On(event, fn)
  if type(event) ~= "string" or type(fn) ~= "function" then
    error("Noir.On(event, fn): event must be a string and fn a function", 2)
  end
  if REFUSED[event] then
    Noir.Problem("The combat log event " .. event .. " is never registered.")
    return false
  end
  if unavailable[event] then return false end
  local list = handlers[event]
  if not list then
    if not isInternal(event) then
      -- RegisterEvent raises an error for an event name the client does not know.
      local good = pcall(frame.RegisterEvent, frame, event)
      if not good then
        unavailable[event] = true
        Noir.Problem("This client has no event " .. event .. "; what depends on it will not update by itself.")
        return false
      end
    end
    list = {}
    handlers[event] = list
  end
  list[#list + 1] = fn
  return true
end

function Noir.Off(event, fn)
  local list = handlers[event]
  if not list then return end
  for i = 1, #list do
    if list[i] == fn then
      list[i] = false
      needsSweep[event] = true
    end
  end
  if delivering == 0 then sweep() end
end

function Noir.Fire(event, ...)
  if type(event) ~= "string" or not isInternal(event) then
    error("Noir.Fire(event, ...): only internal events, whose names start with NOIR_, can be fired", 2)
  end
  deliver(event, ...)
end

frame:SetScript("OnEvent", function(_, event, ...)
  deliver(event, ...)
end)

-- ---------------------------------------------------------------------------------------------------------------
-- Timers: Noir.After(seconds, fn). Uses the client's timer when it has one, else an OnUpdate clock.
-- ---------------------------------------------------------------------------------------------------------------

local waiting = {} -- array of { at = time, fn = function }, only used without C_Timer
local ticker

local function tick()
  local now = GetTime()
  local due
  for i = #waiting, 1, -1 do
    if waiting[i].at <= now then
      due = due or {}
      due[#due + 1] = table.remove(waiting, i)
    end
  end
  if #waiting == 0 then ticker:Hide() end
  if due then
    table.sort(due, function(a, b) return a.at < b.at end)
    for i = 1, #due do
      local good, err = pcall(due[i].fn)
      if not good then Noir.ReportError(err) end
    end
  end
end

function Noir.After(seconds, fn)
  if type(seconds) ~= "number" or type(fn) ~= "function" then
    error("Noir.After(seconds, fn): seconds must be a number and fn a function", 2)
  end
  if C_Timer and C_Timer.After then
    C_Timer.After(seconds, function()
      local good, err = pcall(fn)
      if not good then Noir.ReportError(err) end
    end)
    return
  end
  if not ticker then
    ticker = CreateFrame("Frame")
    ticker:SetScript("OnUpdate", tick)
  end
  waiting[#waiting + 1] = { at = GetTime() + seconds, fn = fn }
  ticker:Show()
end

-- ---------------------------------------------------------------------------------------------------------------
-- Saved variables: NoirGuidesDB for the account, NoirGuidesCharDB for the character, schema 2:
--   NoirGuidesDB     = { schema = 2, profiles = { <name> = { <option key> = value, positions = { ... } } },
--                        defaultProfile = "Default",                      (Options.lua reads and writes the profiles)
--                        trainerCosts = { <CLASS> = { [level] = copper } } }   (State.lua: what class training cost,
--                                                                          for every character of the account)
--   NoirGuidesCharDB = { schema = 2, profile = "<name>", owner = "<UnitGUID('player')>", guide = { ... },
--                        why = { ... }, professions = { ... }, talents = { ... } }
-- Schema 1 (0.1.x) is migrated, not reset: NoirGuidesDB.options becomes the Default profile (the automation
-- switches accept/turnin -> autoQuests, flight -> flights, hearth -> hearth, gossip -> dialogue; the window and
-- arrow places -> positions), and NoirGuidesCharDB.progress (format 2 places) is dropped with one why-log entry of
-- kind "route". Modules keep their own keys and must cope with a key that is missing or has the wrong type
-- (Noir.Table helps).
-- ---------------------------------------------------------------------------------------------------------------

local SCHEMA = 2
local DEFAULT_PROFILE = "Default"

-- Returns parent[key] if it is a table, else puts a new table there and returns it.
function Noir.Table(parent, key)
  local value = parent[key]
  if type(value) ~= "table" then
    value = {}
    parent[key] = value
  end
  return value
end

local function finite(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Schema 1 account options -> the Default profile. Only values of the right type are carried over.
local function migrateAccount(db)
  local old = type(db.options) == "table" and db.options or {}
  db.options = nil
  local profile = {}
  local auto = type(old.auto) == "table" and old.auto or old
  local function switch(key)
    if type(auto[key]) == "boolean" then return auto[key] end
    return nil
  end
  local accept, turnin = switch("accept"), switch("turnin")
  if accept == false or turnin == false then
    profile.autoQuests = false
  elseif accept or turnin then
    profile.autoQuests = true
  end
  profile.flights, profile.hearth, profile.dialogue = switch("flight"), switch("hearth"), switch("gossip")
  local function place(key, saved)
    if type(saved) == "table" and finite(saved.x) and finite(saved.y) then
      Noir.Table(profile, "positions")[key] = { "TOPLEFT", "BOTTOMLEFT", saved.x, saved.y }
    end
  end
  local window = type(old.window) == "table" and old.window or {}
  place("window", window)
  if finite(window.scale) and window.scale >= 0.2 and window.scale <= 2 then profile.windowScale = window.scale end
  if type(window.locked) == "boolean" then profile.locked = window.locked end
  if type(window.hidden) == "boolean" then profile.windowHidden = window.hidden end
  local arrow = type(old.arrow) == "table" and old.arrow or {}
  place("arrow", arrow)
  if type(arrow.off) == "boolean" then profile.arrow = not arrow.off end
  db.profiles = { [DEFAULT_PROFILE] = profile }
  db.defaultProfile = DEFAULT_PROFILE
end

-- The remembered training costs: class tokens to tables of whole levels 1 to 60 and copper amounts of at least 0.
-- Added in 0.4.0 within schema 2 (a missing table is simply empty); anything else in it is dropped.
local function shapeCosts(db)
  local costs = db.trainerCosts
  if costs == nil then return end
  if type(costs) ~= "table" then
    db.trainerCosts = nil
    return
  end
  for class, levels in pairs(costs) do
    if type(class) ~= "string" or type(levels) ~= "table" then
      costs[class] = nil
    else
      for level, cost in pairs(levels) do
        local wholeLevel = type(level) == "number" and level == math.floor(level) and level >= 1 and level <= 60
        if not (wholeLevel and finite(cost) and cost >= 0) then levels[level] = nil end
      end
    end
  end
end

-- Schema 1 character data: the format 2 places are dropped, with one entry in the why-log saying so.
local function migrateCharacter(char)
  if char.progress ~= nil then
    char.progress = nil
    local why = Noir.Table(char, "why")
    why[#why + 1] = {
      kind = "route",
      text = "The route changed to sections in this version; your place in it will be found again from your quest log.",
    }
  end
end

local function prepare(name, value, migrate)
  if value ~= nil and type(value) ~= "table" then
    Noir.Problem("The saved variable " .. name .. " was damaged and has been reset.")
    value = nil
  end
  value = value or {}
  if value.schema == 1 then
    migrate(value)
    value.schema = SCHEMA
  elseif value.schema ~= SCHEMA then
    if value.schema ~= nil then
      Noir.Problem("The saved variable " .. name .. " had an unknown schema and has been reset.")
      value = {}
    end
    value.schema = SCHEMA
  end
  return value
end

-- The account's profiles: a table of tables with at least one profile, and a default that exists.
local function shapeAccount(db)
  local profiles = Noir.Table(db, "profiles")
  for name, profile in pairs(profiles) do
    if type(name) ~= "string" or type(profile) ~= "table" then profiles[name] = nil end
  end
  if next(profiles) == nil then profiles[DEFAULT_PROFILE] = {} end
  if type(db.defaultProfile) ~= "string" or not profiles[db.defaultProfile] then
    local first
    for name in pairs(profiles) do
      if first == nil or name < first then first = name end
    end
    db.defaultProfile = profiles[DEFAULT_PROFILE] and DEFAULT_PROFILE or first
  end
  shapeCosts(db)
end

-- A character uses its saved profile while it exists, else the account's default for new characters.
local function shapeCharacter(char, db)
  if type(char.profile) ~= "string" or not db.profiles[char.profile] then char.profile = db.defaultProfile end
end

-- ---------------------------------------------------------------------------------------------------------------
-- /noir (spec 6.3)
--   Noir.Command(name, help, fn)   fn(rest) is called for "/noir name rest"
--   Noir.Commands() -> names       every registered command, sorted
--   Noir.PrintHelp()               what "/noir help" prints
--   Noir.RunCommand(text)          "/noir text"; an empty text opens the settings (SettingsPanel.Open)
-- Every command also has a mouse path (Menu.MOUSE_PATHS). The commands are: show, hide, toggle, preview
-- (UI/Screen.lua), wizard (UI/Wizard.lua), cleanup, talents, professions, bug, help, and the extras why, state,
-- problems, step, skip, back, sync (Menu.lua), version; a module adds no other.
-- ---------------------------------------------------------------------------------------------------------------

local commands = {} -- name -> { help = "...", fn = function }

function Noir.Command(name, help, fn)
  if type(name) ~= "string" or type(help) ~= "string" or type(fn) ~= "function" then
    error("Noir.Command(name, help, fn)", 2)
  end
  commands[string.lower(name)] = { help = help, fn = fn }
end

function Noir.Commands()
  local list = {}
  for name in pairs(commands) do list[#list + 1] = name end
  table.sort(list)
  return list
end

local function printHelp()
  local list = Noir.Commands()
  Noir.Print("Noir Guides " .. Noir.version .. ". Commands:")
  Noir.Print("  /noir - the settings")
  for i = 1, #list do
    Noir.Print("  /noir " .. list[i] .. " - " .. commands[list[i]].help)
  end
end
Noir.PrintHelp = printHelp

-- The settings panel (UI/SettingsPanel.lua), looked up when asked; without it the list of commands.
local function openSettings()
  local panel = Noir.SettingsPanel
  if panel and type(panel.Open) == "function" then
    panel.Open()
  else
    printHelp()
  end
end

function Noir.RunCommand(text)
  text = string.gsub(string.gsub(tostring(text or ""), "^%s+", ""), "%s+$", "")
  local name, rest = string.match(text, "^(%S+)%s*(.*)$")
  if not name then
    local good, err = pcall(openSettings)
    if not good then Noir.ReportError(err) end
    return
  end
  local command = commands[string.lower(name)]
  if not command then
    Noir.Print("There is no command \"" .. name .. "\".")
    printHelp()
    return
  end
  local good, err = pcall(command.fn, rest)
  if not good then Noir.ReportError(err) end
end

Noir.Command("help", "this list", function() Noir.PrintHelp() end)
Noir.Command("version", "the addon's version", function()
  Noir.Print("Noir Guides " .. Noir.version)
end)
Noir.Command("problems", "what went wrong while loading", function()
  local list = Noir.problems
  if #list == 0 then
    Noir.Print("No problems recorded.")
    return
  end
  Noir.Print(#list .. " problem(s):")
  for i = 1, #list do Noir.Print("  " .. list[i]) end
end)

SLASH_NOIR1 = "/noir"
if SlashCmdList then
  SlashCmdList["NOIR"] = function(text)
    Noir.RunCommand(text)
  end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Life cycle
--   NOIR_INIT   the saved variables are ready (Noir.db, Noir.char)
--   NOIR_LOGIN  the character's basic facts can be read; fired once, after NOIR_INIT
-- ---------------------------------------------------------------------------------------------------------------

local initialized, loggedIn = false, false

local function login()
  if loggedIn or not initialized then return end
  loggedIn = true
  -- The character the saved data belongs to, for the recreated-character check (task E2). Set once, when missing.
  if type(Noir.char.owner) ~= "string" and UnitGUID then
    local guid = UnitGUID("player")
    if type(guid) == "string" and guid ~= "" then Noir.char.owner = guid end
  end
  Noir.Fire("NOIR_LOGIN")
  if #Noir.problems > 0 then
    Noir.Print(#Noir.problems .. " problem(s) while loading. Type /noir problems to see them.")
  end
end

Noir.On("ADDON_LOADED", function(_, name)
  if name ~= Noir.name or initialized then return end
  initialized = true
  local metadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local version = metadata and metadata(Noir.name, "Version")
  if type(version) == "string" and version ~= "" then Noir.version = version end
  NoirGuidesDB = prepare("NoirGuidesDB", NoirGuidesDB, migrateAccount)
  NoirGuidesCharDB = prepare("NoirGuidesCharDB", NoirGuidesCharDB, migrateCharacter)
  Noir.db, Noir.char = NoirGuidesDB, NoirGuidesCharDB
  shapeAccount(Noir.db)
  shapeCharacter(Noir.char, Noir.db)
  Noir.Fire("NOIR_INIT")
  -- Loaded on demand after the player entered the world: PLAYER_LOGIN will not come again.
  if IsLoggedIn and IsLoggedIn() then login() end
end)

Noir.On("PLAYER_LOGIN", login)
