-- Noir Guides, GPLv3. See LICENSE.
-- Core: the Noir namespace, saved variables, the event bus, timers and the /noir command.
use("tools/test-lua/sample/helper.lua")

test("loading creates the Noir namespace and only the globals the addon owns", function()
  local c = sample()
  c:login()
  local Noir = c.G.Noir
  eq(type(Noir), "table")
  eq(Noir.name, "NoirGuides")
  for _, kind in ipairs({ "quests", "npcs", "objects", "items", "zones", "flights" }) do
    eq(type(Noir.Data[kind]), "table", "Noir.Data." .. kind)
  end
  local allowed = { Noir = true, NoirGuidesDB = true, NoirGuidesCharDB = true, SLASH_NOIR1 = true,
    BINDING_HEADER_NOIRGUIDES = true }
  -- The key binding names of Bindings.xml (UI/Buttons.lua): BINDING_NAME_CLICK NoirGuidesItem1:LeftButton and so on.
  for _, kind in ipairs({ "Item", "Friend", "Enemy" }) do
    for i = 1, 4 do allowed["BINDING_NAME_CLICK NoirGuides" .. kind .. i .. ":LeftButton"] = true end
  end
  local extra = {}
  for name in pairs(c.globalsSet) do
    if not allowed[name] then extra[#extra + 1] = name end
  end
  table.sort(extra)
  eq(extra, {}, "globals the addon leaked")
end)

test("the version comes from the toc", function()
  local c = sample()
  c:login()
  eq(c.G.Noir.version, c.toc.meta.Version)
  ok(c.toc.meta.Version and c.toc.meta.Version ~= "", "the toc has a version")
  local modern = sample({ api = "modern" })
  modern:login()
  eq(modern.G.Noir.version, modern.toc.meta.Version)
end)

test("saved variables get schema 2 on first login", function()
  local c = sample()
  c:loadAddon()
  eq(c.G.Noir.db, nil, "no database before ADDON_LOADED")
  c:login()
  local Noir = c.G.Noir
  eq(Noir.db, c.G.NoirGuidesDB)
  eq(Noir.char, c.G.NoirGuidesCharDB)
  eq(Noir.db.schema, 2)
  eq(Noir.char.schema, 2)
  eq(Noir.db.profiles, { Default = {} })
  eq(Noir.db.defaultProfile, "Default")
  eq(Noir.char.profile, "Default")
  eq(Noir.db.options, nil, "schema 1's options table is not made any more")
end)

test("a character's owner GUID is saved", function()
  local c = sample()
  c:login()
  eq(c.G.Noir.char.owner, c.G.UnitGUID("player"))
  c.G.Noir.char.owner = "Player-1-00000001"
  local again = c:relog()
  eq(again.G.Noir.char.owner, "Player-1-00000001", "an owner already saved is left for the guide to check")
  local fresh = sample({ name = "Other", saved = again:logout() })
  fresh:login()
  eq(fresh.G.Noir.char.owner, fresh.G.UnitGUID("player"))
end)

test("saved variables survive a relog and are kept per character", function()
  local c = sample({ name = "Anna" })
  c:login()
  c.G.Noir.db.profiles.Default.sound = false
  c.G.Noir.char.note = "anna"
  local again = c:relog()
  eq(again.G.Noir.db.profiles.Default.sound, false)
  eq(again.G.Noir.char.note, "anna")
  again:logout()
  local other = sample({ name = "Bert", saved = again.saved })
  other:login()
  eq(other.G.Noir.db.profiles.Default.sound, false, "the account database is shared")
  eq(other.G.Noir.char.note, nil, "the character database is not")
end)

test("damaged saved variables are replaced and reported, not crashed on", function()
  local c = sample({ saved = { account = { NoirGuidesDB = "garbage" }, characters = { ["Tester-Mock"] = { NoirGuidesCharDB = { schema = "x", flights = 7 } } } } })
  c:login()
  local Noir = c.G.Noir
  eq(Noir.db.schema, 2)
  eq(type(Noir.db.profiles.Default), "table")
  eq(Noir.char.schema, 2)
  ok(#Noir.problems >= 1, "a problem was recorded")
  has(table.concat(Noir.problems, "\n"), "NoirGuidesDB")
end)

test("ADDON_LOADED for another addon does not initialize Noir", function()
  local c = sample()
  c:loadAddon()
  local inits = 0
  c.G.Noir.On("NOIR_INIT", function() inits = inits + 1 end)
  c:fire("ADDON_LOADED", "SomeOtherAddon")
  eq(inits, 0)
  eq(c.G.Noir.db, nil)
  c:fire("ADDON_LOADED", "NoirGuides")
  eq(inits, 1)
  c:fire("ADDON_LOADED", "NoirGuides")
  eq(inits, 1, "initialized once")
end)

test("NOIR_INIT comes before NOIR_LOGIN, each once", function()
  local c = sample()
  c:loadAddon()
  local order = {}
  c.G.Noir.On("NOIR_INIT", function() order[#order + 1] = "init" end)
  c.G.Noir.On("NOIR_LOGIN", function() order[#order + 1] = "login" end)
  c:login()
  eq(order, { "init", "login" })
end)

test("an addon loaded after login still gets NOIR_LOGIN", function()
  local c = sample()
  c:loadAddon()
  local order = {}
  c.G.Noir.On("NOIR_INIT", function() order[#order + 1] = "init" end)
  c.G.Noir.On("NOIR_LOGIN", function() order[#order + 1] = "login" end)
  c.loggedIn = true -- the player is already in the world when the addon is loaded on demand
  c:fire("ADDON_LOADED", "NoirGuides")
  eq(order, { "init", "login" })
  c:fire("PLAYER_LOGIN")
  eq(order, { "init", "login" }, "not twice")
end)

test("the event bus delivers game events in registration order with their arguments", function()
  local c = sample()
  c:login()
  local Noir = c.G.Noir
  local seen = {}
  eq(Noir.On("PLAYER_LEVEL_UP", function(event, level) seen[#seen + 1] = "a:" .. event .. ":" .. level end), true)
  eq(Noir.On("PLAYER_LEVEL_UP", function(_, level) seen[#seen + 1] = "b:" .. level end), true)
  c:fire("PLAYER_LEVEL_UP", 7)
  eq(seen, { "a:PLAYER_LEVEL_UP:7", "b:7" })
end)

test("internal events are delivered by Noir.Fire and never touch the game's frame", function()
  local c = sample()
  c:login()
  local Noir = c.G.Noir
  local got
  eq(Noir.On("NOIR_SAMPLE", function(event, a, b) got = { event, a, b } end), true)
  Noir.Fire("NOIR_SAMPLE", 1, "two")
  eq(got, { "NOIR_SAMPLE", 1, "two" })
  raises(function() Noir.Fire("PLAYER_LOGIN") end, "NOIR_")
end)

test("Noir.Off removes a handler, also from inside a handler", function()
  local c = sample()
  c:login()
  local Noir = c.G.Noir
  local log = {}
  local first, second
  first = function()
    log[#log + 1] = "first"
    Noir.Off("NOIR_SAMPLE", first)
  end
  second = function() log[#log + 1] = "second" end
  Noir.On("NOIR_SAMPLE", first)
  Noir.On("NOIR_SAMPLE", second)
  Noir.Fire("NOIR_SAMPLE")
  Noir.Fire("NOIR_SAMPLE")
  eq(log, { "first", "second", "second" })
  Noir.Off("NOIR_SAMPLE", second)
  Noir.Fire("NOIR_SAMPLE")
  eq(#log, 3)
end)

test("a handler added during delivery first runs on the next event", function()
  local c = sample()
  c:login()
  local Noir = c.G.Noir
  local log = {}
  Noir.On("NOIR_SAMPLE", function()
    log[#log + 1] = "outer"
    if #log == 1 then Noir.On("NOIR_SAMPLE", function() log[#log + 1] = "inner" end) end
  end)
  Noir.Fire("NOIR_SAMPLE")
  eq(log, { "outer" })
  Noir.Fire("NOIR_SAMPLE")
  eq(log, { "outer", "outer", "inner" })
end)

test("an error in one handler reaches the error handler and the other handlers still run", function()
  local c = sample()
  c:login()
  local Noir = c.G.Noir
  local reached = false
  Noir.On("PLAYER_MONEY", function() error("broken handler") end)
  Noir.On("PLAYER_MONEY", function() reached = true end)
  c:fire("PLAYER_MONEY")
  eq(reached, true)
  local errors = c:takeErrors()
  eq(#errors, 1)
  has(errors[1], "broken handler")
end)

test("an event this client does not have is reported and does not raise", function()
  local c = sample({ withoutEvents = { "HEARTHSTONE_BOUND" } })
  c:login()
  local Noir = c.G.Noir
  eq(Noir.On("PLAYER_UNGHOST", function() end), true)
  local before = #Noir.problems
  eq(Noir.On("NOT_A_REAL_EVENT", function() end), false)
  eq(#Noir.problems, before + 1)
  has(Noir.problems[#Noir.problems], "NOT_A_REAL_EVENT")
  eq(Noir.On("NOT_A_REAL_EVENT", function() end), false)
  eq(#Noir.problems, before + 1, "reported once")
end)

test("the combat log is refused without asking the client", function()
  local c = sample()
  c:login()
  local Noir = c.G.Noir
  eq(Noir.On("COMBAT_LOG_EVENT_UNFILTERED", function() end), false)
  eq(Noir.On("COMBAT_LOG_EVENT", function() end), false)
  eq(c.violations, {})
  has(table.concat(Noir.problems, "\n"), "combat log")
end)

test("bad arguments to Noir.On are programming errors", function()
  local c = sample()
  c:login()
  raises(function() c.G.Noir.On("PLAYER_LOGIN") end, "Noir.On")
  raises(function() c.G.Noir.On(nil, function() end) end, "Noir.On")
end)

-- Since task E8 "/noir" alone opens the settings (spec 6.3); tools/test-lua/commands.lua covers that in full.
test("/noir without arguments opens the settings and /noir help lists the commands", function()
  local c = sample()
  c:login()
  c:takeChat()
  c:slash("/noir")
  eq(c.G.Noir.SettingsPanel.Read().shown, true)
  c:takeChat()
  c:slash("/NOIR help")
  local text = c:chatText()
  has(text, "/noir help")
  has(text, "/noir version")
end)

test("/noir version prints the toc version", function()
  local c = sample()
  c:login()
  c:takeChat()
  c:slash("/noir version")
  has(c:chatText(), c.toc.meta.Version)
end)

test("modules add commands; arguments are passed trimmed; names are case-insensitive", function()
  local c = sample()
  c:login()
  local Noir = c.G.Noir
  local got
  Noir.Command("sample", "a command for the test", function(rest) got = rest end)
  c:slash("/noir Sample   two words  ")
  eq(got, "two words")
  c:slash("/noir sample")
  eq(got, "")
  c:takeChat()
  c:slash("/noir help")
  has(c:chatText(), "/noir sample")
  has(c:chatText(), "a command for the test")
end)

test("an unknown command says so and shows the list", function()
  local c = sample()
  c:login()
  c:takeChat()
  c:slash("/noir frobnicate")
  has(c:chatText(), "frobnicate")
  has(c:chatText(), "/noir help")
end)

test("an error inside a command reaches the error handler", function()
  local c = sample()
  c:login()
  c.G.Noir.Command("explode", "raises", function() error("command failed") end)
  c:slash("/noir explode")
  local errors = c:takeErrors()
  eq(#errors, 1)
  has(errors[1], "command failed")
end)

test("/noir problems lists what went wrong at load", function()
  local c = sample()
  c:login()
  c:takeChat()
  c:slash("/noir problems")
  has(c:chatText(), "No problems")
  c.G.Noir.Problem("something is off")
  c:takeChat()
  c:slash("/noir problems")
  has(c:chatText(), "something is off")
end)

test("problems recorded before login are announced once at login", function()
  local c = sample()
  c:loadAddon()
  c.G.Noir.Problem("early trouble")
  c:login()
  has(c:chatText(), "/noir problems")
end)

test("the problem list is bounded", function()
  local c = sample()
  c:login()
  for i = 1, 300 do c.G.Noir.Problem("problem " .. i) end
  ok(#c.G.Noir.problems <= 100, "at most 100 kept")
  eq(c.G.Noir.problems[#c.G.Noir.problems], "problem 300", "the newest is kept")
end)

test("Noir.After runs a function later, with the client's timer or without it", function()
  for _, without in ipairs({ {}, { "C_Timer" } }) do
    local c = sample({ without = without })
    c:login()
    local ran = 0
    c.G.Noir.After(2, function() ran = ran + 1 end)
    c:advance(1.5)
    eq(ran, 0)
    c:advance(1)
    eq(ran, 1)
    c:advance(5)
    eq(ran, 1, "once")
  end
end)

test("an error in a timer function reaches the error handler", function()
  local c = sample({ without = { "C_Timer" } })
  c:login()
  local later = false
  c.G.Noir.After(1, function() error("timer failed") end)
  c.G.Noir.After(1, function() later = true end)
  c:advance(2)
  eq(later, true)
  local errors = c:takeErrors()
  eq(#errors, 1)
  has(errors[1], "timer failed")
end)

test("Noir.Print writes to the chat frame with the addon's name", function()
  local c = sample()
  c:login()
  c:takeChat()
  c.G.Noir.Print("hello there")
  eq(#c.chat, 1)
  has(c.chat[1], "Noir")
  has(c.chat[1], "hello there")
end)
