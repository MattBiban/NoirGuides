-- Noir Guides, GPLv3. See LICENSE.
-- The addon exactly as the toc ships it, with the generated data and routes as they are in the repository now.
-- The generated files belong to the route planner and change with it, so these tests ask only for what must
-- always hold: everything loads without a Lua error and every route file is either registered or refused with a
-- reason the player can read.
local Client = HARNESS.Client

-- Generated data files the toc lists before the planner has written them. The client skips a listed file that
-- does not exist; anything else missing is a mistake in the toc.
local MAY_BE_MISSING = {
  ["NoirGuides/Data/Names.lua"] = true, ["NoirGuides/Data/Zones.lua"] = true, ["NoirGuides/Data/Flights.lua"] = true,
}

local RACES = { "Human", "Dwarf", "Gnome", "NightElf", "HighOrder", "Orc", "Troll", "Tauren", "Undead", "Windshaper" }

test("the toc declares the interface, the saved variables and a version", function()
  local toc = Client.parseToc(assert(host.read("NoirGuides/NoirGuides.toc")))
  eq(toc.meta.Interface, "16001")
  eq(toc.meta.SavedVariables, "NoirGuidesDB")
  eq(toc.meta.SavedVariablesPerCharacter, "NoirGuidesCharDB")
  ok(toc.meta.Version:match("^%d+%.%d+%.%d+$"), "version like 0.1.0")
  ok(toc.meta.Title and toc.meta.Title ~= "", "title")
end)

test("every file the toc lists exists, except generated data not written yet", function()
  local c = Client.new({})
  c:loadAddon()
  local unexpected = {}
  for _, file in ipairs(c.missingFiles) do
    if not MAY_BE_MISSING[file] then unexpected[#unexpected + 1] = file end
  end
  eq(unexpected, {})
end)

-- The final list of plan task E1, in this order, then the generated data files and the route files.
local FINAL = {
  "Core.lua", "Options.lua", "State.lua", "Routes.lua", "Guide.lua", "Why.lua", "Lines.lua", "Progress.lua",
  "Automation.lua", "UI/Theme.lua", "UI/Screen.lua", "UI/Text.lua", "UI/Panel.lua", "UI/Window.lua", "UI/Arrow.lua",
  "UI/Map.lua", "UI/Buttons.lua", "UI/Wizard.lua", "UI/SettingsPanel.lua", "UI/MinimapButton.lua", "Talents.lua",
  "Professions.lua", "Cleanup.lua", "Diagnostics.lua", "Menu.lua",
}
local DATA = { "Data/Names.lua", "Data/Zones.lua", "Data/Flights.lua", "Data/Talents.lua", "Data/Professions.lua", "Data/Cleanup.lua" }

test("the toc lists exactly the files of the final list, each once, and every one exists", function()
  local toc = Client.parseToc(assert(host.read("NoirGuides/NoirGuides.toc")))
  local expected = {}
  for _, file in ipairs(FINAL) do expected[#expected + 1] = file end
  for _, file in ipairs(DATA) do expected[#expected + 1] = file end
  local routes = {}
  for _, name in ipairs(host.list("NoirGuides/Routes")) do
    if name:match("%.lua$") then routes[#routes + 1] = "Routes/" .. name end
  end
  table.sort(routes)
  for _, file in ipairs(routes) do expected[#expected + 1] = file end
  eq(toc.files, expected)
  local seen = {}
  for _, file in ipairs(toc.files) do
    no(seen[file:lower()], file .. " is listed twice")
    seen[file:lower()] = true
  end
  for _, file in ipairs(FINAL) do ok(host.exists("NoirGuides/" .. file), file .. " exists") end
  -- The client reads Bindings.xml by itself; the toc must not list it.
  ok(host.exists("NoirGuides/Bindings.xml"), "Bindings.xml exists")
  no(seen["bindings.xml"], "Bindings.xml is not in the toc")
  local bindings = assert(host.read("NoirGuides/Bindings.xml"))
  ok(bindings:find("^<!%-%- Noir Guides, GPLv3%. See LICENSE%. %-%->"), "Bindings.xml starts with the license comment")
  ok(bindings:find("<Bindings>") and bindings:find("</Bindings>"), "Bindings.xml is a Bindings document")
end)

test("every route file in the repository is in the toc, and one per race", function()
  local toc = Client.parseToc(assert(host.read("NoirGuides/NoirGuides.toc")))
  local listed = {}
  for _, file in ipairs(toc.files) do listed[file] = true end
  for _, name in ipairs(host.list("NoirGuides/Routes")) do
    ok(listed["Routes/" .. name], "Routes/" .. name .. " is not in the toc")
  end
  for _, race in ipairs(RACES) do
    local faction = Client.RACES[race].faction
    ok(listed["Routes/" .. faction:lower() .. "-" .. race:lower() .. ".lua"], race)
  end
end)

for _, api in ipairs({ "classic", "modern" }) do
  test("the shipped addon loads and logs in for every race without a Lua error (" .. api .. " API)", function()
    for _, race in ipairs(RACES) do
      local c = Client.new({ race = race, api = api })
      c:login()
      eq(c.errors, {}, race)
      local Noir = c.G.Noir
      eq(Noir.State.race, race)
      -- Every route file either registered its route or was refused with a recorded reason.
      local faction = Client.RACES[race].faction
      local id = faction:lower() .. "-" .. race:lower()
      ok(Noir.Routes.Get(id) or Noir.Routes.rejected[id], id .. " neither registered nor refused")
      local current = Noir.Routes.Current()
      if Noir.Routes.Get(id) then
        eq(current, id)
      else
        eq(current, nil)
        has(table.concat(Noir.problems, "\n"), id)
      end
      c:slash("/noir state")
      c:slash("/noir problems")
      c:logout()
      eq(c.errors, {}, race)
    end
  end)
end

-- A misspelled API name reads as nil, which looks exactly like "this client does not have it". The mock records
-- every global the engine reads that does not exist; each must be one the engine deliberately probes for.
test("the engine reads no missing global except the APIs it feature-detects", function()
  use("tools/test-lua/sample/helper.lua")
  local probed = {}
  for name in ([[
    Noir NoirGuidesDB NoirGuidesCharDB
    C_AddOns GetAddOnMetadata C_Timer C_Map C_TaxiMap GetTaxiMapID NumTaxiNodes TaxiNodeName TaxiNodeGetType
    GetQuestsCompleted IsQuestComplete IsQuestFlaggedCompleted GetNumQuestLogEntries GetQuestLogTitle
    GetNumQuestLeaderBoards GetQuestLogLeaderBoard C_TradeSkillUI GetProfessions GetProfessionInfo C_Container
    GetActiveTalentGroup Settings InterfaceOptions_AddCategory InterfaceOptionsFrame_OpenToCategory IsAddOnLoaded
  ]]):gmatch("%S+") do
    probed[name] = true
  end
  local variants = {
    { api = "classic" }, { api = "modern" }, { api = "classic", taxiIds = true }, { api = "modern", taxiIds = false },
    { professionApi = "tradeskill" }, { professionApi = "none" }, { without = { "C_Timer" } }, { without = { "C_Map" } },
  }
  for _, opts in ipairs(variants) do
    local c = sample(opts):login()
    c:acceptQuest(364)
    c:completeObjectives(364)
    c:turnInQuest(364, 500)
    c:moveTo({ zone = 85, x = 58.9, y = 51.9 })
    c:openTaxi(384)
    c:closeTaxi()
    c:bindHearth("Brill")
    c:setProfession(186, "Mining", 1, 75)
    c:moveTo({ zone = 130, x = 40, y = 40 })
    c.G.Noir.After(1, function() end)
    c:advance(6)
    c:advance(20) -- the conflict check
    for _, command in ipairs({ "", "state", "problems", "version", "help" }) do c:slash("/noir " .. command) end
    c:logout()
    local unexpected = {}
    for name in pairs(c.undefined) do
      if not probed[name] then unexpected[#unexpected + 1] = name end
    end
    table.sort(unexpected)
    eq(unexpected, {})
  end
end)

-- The same for Progress and Automation, which talk to NPCs: the NPC windows of the sample route are opened on every
-- shape of the gossip API, so every API name those files read is either there or probed for. Since task C1 both are
-- skeletons until E4 and E9 rewrite them: the test does by hand what the automation did (accept, bind, fly) and
-- no longer asks that the route was played to its end; tools/test-lua/sim.lua (X1) plays routes again.
test("the route engine and the automation read no missing global except the APIs they feature-detect", function()
  use("tools/test-lua/sample/helper.lua")
  local probed = {}
  for name in ([[
    Noir NoirGuidesDB NoirGuidesCharDB
    C_AddOns GetAddOnMetadata C_TaxiMap GetTaxiMapID C_TradeSkillUI IsQuestComplete GetQuestsCompleted
    C_GossipInfo GetGossipAvailableQuests GetGossipActiveQuests GetNumGossipAvailableQuests GetNumGossipActiveQuests
    SelectGossipAvailableQuest SelectGossipActiveQuest GetGossipOptions SelectGossipOption
    GetActiveQuestID GetQuestID UnitGUID IsShiftKeyDown C_Container GetActiveTalentGroup
    Settings InterfaceOptions_AddCategory InterfaceOptionsFrame_OpenToCategory IsAddOnLoaded
  ]]):gmatch("%S+") do
    probed[name] = true
  end
  local variants = {
    { api = "classic", gossipApi = "global" }, { api = "modern", gossipApi = "info" }, { api = "modern", gossipApi = "info-index" },
    { api = "classic", greeting = true }, { api = "classic", greeting = true, greetingIds = false },
    { api = "classic", without = { "GetQuestID", "UnitGUID", "IsShiftKeyDown" } },
  }
  for i, opts in ipairs(variants) do
    local greeting = opts.greeting
    opts.greeting = nil
    opts.race, opts.class, opts.level = "Undead", "ROGUE", 10
    local c = sample(opts):login()
    c:talkTo(1569, { greeting = greeting, offers = { 376, 364 } })
    c:acceptQuest(364)
    c:completeObjectives(364)
    c:talkTo(1569, { greeting = greeting, ends = { 364 }, offers = { 376 }, alwaysGossip = true })
    c:turnInQuest(364)
    c:talkTo(6784)
    c:moveTo({ zone = 85, x = 61.7, y = 52.0 })
    c:talkTo(5688)
    c:bindHearth("Brill")
    c:moveTo({ zone = 85, x = 58.9, y = 51.9 })
    c:talkTo(4551, { taxi = 384, options = { { type = "gossip", text = "Hello." } } })
    c:knowFlight(10)
    c:closeTaxi()
    c:talkTo(4551)
    c:advance(1)
    c:moveTo({ zone = 130, x = 45.6, y = 42.6 })
    c:talkTo(1950)
    c:setLevel(12)
    c:useHearth()
    c:advance(2)
    c:moveTo({ zone = 14, x = 50.8, y = 13.6 })
    eq(c.errors, {}, "variant " .. i)
    for _, command in ipairs({ "why", "step", "skip", "back", "sync", "hide", "show", "toggle", "preview", "preview" }) do
      c:slash("/noir " .. command)
    end
    c:logout()
    local unexpected = {}
    for name in pairs(c.undefined) do
      if not probed[name] then unexpected[#unexpected + 1] = name end
    end
    table.sort(unexpected)
    eq(unexpected, {}, "variant " .. i)
  end
end)

test("the shipped addon creates only its own globals", function()
  local c = Client.new({}):login()
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
  eq(extra, {})
end)
