-- Noir Guides, GPLv3. See LICENSE.
-- The mock client itself: the addon's globals behave like Lua 5.1 and like the game, so that a passing engine
-- test means something.
local Client = HARNESS.Client

local function env()
  return Client.new({ files = {} }).G
end

test("the addon's globals are Lua 5.1, not the VM's 5.3", function()
  local G = env()
  eq(G._VERSION, "Lua 5.1")
  eq(type(G.unpack), "function")
  eq(type(G.loadstring), "function")
  eq(G.table.unpack, nil, "table.unpack")
  eq(G.table.pack, nil, "table.pack")
  eq(G.table.move, nil, "table.move")
  eq(G.math.type, nil, "math.type")
  eq(G.math.tointeger, nil, "math.tointeger")
  eq(G.string.pack, nil, "string.pack")
  eq(rawget(G, "utf8"), nil, "utf8")
  eq(rawget(G, "load"), nil, "load")
  eq(rawget(G, "require"), nil, "require")
  eq(rawget(G, "io"), nil, "io")
  eq(rawget(G, "os"), nil, "os")
  eq(rawget(G, "debug"), nil, "debug")
  eq(rawget(G, "setfenv"), nil, "setfenv is not emulated; the lint forbids it")
end)

test("numbers print as in Lua 5.1", function()
  local G = env()
  eq(G.tostring(10 / 2), "5")
  eq(G.tostring(2 ^ 31), "2147483648")
  eq(G.tostring(0.5), "0.5")
  eq(G.tostring(7), "7")
  eq(G.format("%s and %s", 10 / 2, "x"), "5 and x")
  eq(G.format("%d", 5.7), "5", "%d truncates in 5.1")
  eq(G.format("%d%%", 3.0), "3%")
  eq(G.format("%.1f", 2.26), "2.3") -- exact ties (2.25) round differently in the VM, see docs/ENGINE-NOTES.md
  eq(G.string.format("%s", 4 / 2), "2")
  eq(G.strjoin(",", 1, 4 / 2, "a"), "1,2,a")
end)

test("string methods reach the 5.1 library", function()
  local G = env()
  local f = G.loadstring("return (('%s'):format(10 / 2)), (('x').pack)")
  local text, pack = f()
  eq(text, "5")
  eq(pack, nil)
end)

test("xpcall refuses extra arguments, as Lua 5.1 does not pass them", function()
  local G = env()
  raises(function() G.xpcall(print, print, 1) end, "not Lua 5.1")
  local good, value = G.xpcall(function() return 7 end, function(e) return e end)
  eq(good, true)
  eq(value, 7)
end)

test("the game's string helpers", function()
  local G = env()
  eq({ G.strsplit(" ", "why  now") }, { "why", "", "now" })
  eq({ G.strsplit(" ", "skip 3 steps", 2) }, { "skip", "3 steps" })
  eq({ G.strsplit(",;", "a,b;c") }, { "a", "b", "c" })
  eq(G.strtrim("  hello \n"), "hello")
  eq(G.strtrim("xxhixx", "x"), "hi")
  eq(G.tContains({ "a", "b" }, "b"), true)
  eq(G.bit.band(6, 3), 2)
  eq(G.bit.bor(4, 1), 5)
  local t = { 1, 2, x = 3 }
  eq(G.wipe(t), {})
end)

test("the second run gives the addon a pairs that visits keys in the opposite order", function()
  local G = env()
  local t = { a = 1, b = 2, c = 3, 10, 20 }
  local vmOrder, addonOrder = {}, {}
  for k in pairs(t) do vmOrder[#vmOrder + 1] = tostring(k) end
  for k, v in G.pairs(t) do
    eq(v, t[k])
    addonOrder[#addonOrder + 1] = tostring(k)
  end
  eq(#addonOrder, 5)
  if HARNESS.pairsMode == "reversed" then
    local reversed = {}
    for i = #vmOrder, 1, -1 do reversed[#reversed + 1] = vmOrder[i] end
    eq(addonOrder, reversed)
  else
    eq(addonOrder, vmOrder)
  end
end)

test("clearing fields while looping with pairs works in both orders", function()
  local G = env()
  local t = { a = 1, b = 2, c = 3, d = 4 }
  local visited = 0
  for k in G.pairs(t) do
    visited = visited + 1
    t[k] = nil
  end
  eq(visited, 4)
  eq(t, {})
  local u = { a = 1, b = 2, c = 3 }
  local seen = {}
  for k in G.pairs(u) do
    seen[#seen + 1] = k
    u.a, u.b, u.c = nil, nil, nil -- everything else is gone after the first visit
  end
  eq(#seen, 1)
end)

test("code loaded with loadstring runs in the addon's globals", function()
  local G = env()
  G.loadstring("leaked = 5")()
  eq(rawget(G, "leaked"), 5)
  eq(rawget(_G, "leaked"), nil)
end)

test("the toc parser reads metadata and files and ignores comments", function()
  local toc = Client.parseToc("## Interface: 16001\r\n## Title: Noir Guides\n# a comment\n\nCore.lua\nUI\\Window.lua\n  Routes/a.lua  \n")
  eq(toc.meta.Interface, "16001")
  eq(toc.meta.Title, "Noir Guides")
  eq(toc.files, { "Core.lua", "UI/Window.lua", "Routes/a.lua" })
end)

test("frames get events they registered for, and unknown events are refused like in the game", function()
  local c = Client.new({ files = {} })
  local seen = {}
  local f = c.G.CreateFrame("Frame")
  f:SetScript("OnEvent", function(_, event, a) seen[#seen + 1] = event .. ":" .. tostring(a) end)
  f:RegisterEvent("PLAYER_LEVEL_UP")
  raises(function() f:RegisterEvent("NOT_AN_EVENT") end, "unknown event")
  c:fire("PLAYER_LEVEL_UP", 2)
  c:fire("QUEST_LOG_UPDATE")
  eq(seen, { "PLAYER_LEVEL_UP:2" })
  raises(function() c:fire("NOT_AN_EVENT") end, "does not know the event")
end)

test("a Lua error in an event handler is recorded, not lost", function()
  local c = Client.new({ files = {} })
  local f = c.G.CreateFrame("Frame")
  f:SetScript("OnEvent", function() error("boom") end)
  f:RegisterEvent("PLAYER_LOGIN")
  c:fire("PLAYER_LOGIN")
  local errors = c:takeErrors()
  eq(#errors, 1)
  has(errors[1], "boom")
end)

test("registering the combat log is recorded as a violation", function()
  local c = Client.new({ files = {} })
  local f = c.G.CreateFrame("Frame")
  f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
  eq(c:takeViolations(), { "registered COMBAT_LOG_EVENT_UNFILTERED" })
end)

test("timers and OnUpdate run as time advances", function()
  local c = Client.new({ files = {} })
  local log = {}
  c.G.C_Timer.After(1, function() log[#log + 1] = "one" end)
  c.G.C_Timer.After(0.3, function() log[#log + 1] = "early" end)
  local elapsed = 0
  local f = c.G.CreateFrame("Frame")
  f:SetScript("OnUpdate", function(_, dt) elapsed = elapsed + dt end)
  c:advance(0.5)
  eq(log, { "early" })
  c:advance(0.6)
  eq(log, { "early", "one" })
  near(elapsed, 1.1, 1e-6)
  near(c.G.GetTime(), 1001.1, 1e-6)
end)

test("the quest log hides quests under a collapsed header and is empty before the server sends it", function()
  local c = Client.new({ files = {} })
  c.s.quests = { { id = 364, title = "The Mindless Ones", level = 2, header = "Tirisfal Glades", objectives = {} } }
  eq(c.G.GetNumQuestLogEntries(), 0)
  c.questLogReady = true
  eq(c.G.GetNumQuestLogEntries(), 2)
  eq(c.G.GetQuestLogIndexByID(364), 2)
  c:collapseHeader("Tirisfal Glades", true)
  eq(c.G.GetNumQuestLogEntries(), 1)
  eq(c.G.GetQuestLogIndexByID(364), 0)
  eq(c.G.C_QuestLog.IsOnQuest(364), true)
end)

test("the level shown by UnitLevel lags during PLAYER_LEVEL_UP", function()
  local c = Client.new({ files = {}, level = 4 })
  local during
  local f = c.G.CreateFrame("Frame")
  f:SetScript("OnEvent", function(_, event) if event == "PLAYER_LEVEL_UP" then during = c.G.UnitLevel("player") end end)
  f:RegisterEvent("PLAYER_LEVEL_UP")
  c:setLevel(5)
  eq(during, 4)
  eq(c.G.UnitLevel("player"), 5)
end)

test("positions convert to an ancestor map only when the mock knows the rectangle", function()
  local c = Client.new({ files = {}, zone = 85, x = 50, y = 50 })
  c:addMap(9001, { name = "A Cave", type = 5, parent = 1420, rect = { 0.2, 0.4, 0.3, 0.5 } })
  c:moveTo({ uiMap = 9001, x = 50, y = 50 })
  local x, y = c.G.C_Map.GetPlayerMapPosition(1420, "player"):GetXY()
  near(x, 0.25, 1e-9)
  near(y, 0.45, 1e-9)
  -- The default world says where Tirisfal Glades lies on its continent, so the cave converts two maps up.
  local cx, cy = c.G.C_Map.GetPlayerMapPosition(1415, "player"):GetXY()
  near(cx, 0.35, 1e-9)
  near(cy, 0.19, 1e-9)
  eq(c.G.C_Map.GetPlayerMapPosition(1411, "player"), nil, "a map that is not above the player's")
  -- A map whose place on its parent the mock does not know converts no further than itself.
  c:addMap(9002, { name = "An Unplaced Zone", type = 3, parent = 1415 })
  c:moveTo({ uiMap = 9002, x = 50, y = 50 })
  eq({ c.G.C_Map.GetPlayerMapPosition(9002, "player"):GetXY() }, { 0.5, 0.5 })
  eq(c.G.C_Map.GetPlayerMapPosition(1415, "player"), nil)
end)

test("saved variables must be plain data", function()
  local c = Client.new({ files = {} })
  c.toc = Client.parseToc("## SavedVariables: SomeDB\n")
  c.loaded, c.loggedIn = true, true
  c.G.SomeDB = { fn = function() end }
  raises(function() c:logout() end, "cannot be saved")
end)

test("the two Skyborne races share a race token and differ by race ID", function()
  local a = Client.new({ files = {}, race = "HighOrder" })
  local b = Client.new({ files = {}, race = "Windshaper" })
  local _, tokenA, idA = a.G.UnitRace("player")
  local _, tokenB, idB = b.G.UnitRace("player")
  eq(tokenA, tokenB)
  eq({ idA, idB }, { 95, 96 })
  eq(a.G.UnitFactionGroup("player"), "Alliance")
  eq(b.G.UnitFactionGroup("player"), "Horde")
end)

test("a Lua error raised inside the addon is kept for the runner to report", function()
  local c = Client.new({ files = {} })
  c:callAddon(function() error("inside the addon") end)
  eq(#c.errors, 1)
  c:takeErrors()
end)

-- What the simulator (tools/harness/sim.lua) needs from the mock: the game's experience table, NPCs that offer a
-- quest only when the game would, and a quest log that refuses a 21st quest the way the game does.
test("the experience per level can be the game's table: UnitXPMax and level-ups follow it", function()
  local c = Client.new({ files = {}, xpToLevel = { 400, 900, 1400 } }):login()
  eq(c.G.UnitXPMax("player"), 400)
  c:gainXP(1000)
  eq({ c.s.level, c.s.xp, c.G.UnitXPMax("player") }, { 2, 600, 900 })
  c:gainXP(300)
  eq({ c.s.level, c.s.xp }, { 3, 0 })
end)

test("an NPC offers a quest only when its level, prerequisites and exclusions allow it", function()
  local world = {
    maps = { [1420] = { name = "Tirisfal Glades", type = 3, area = 85 } }, taxi = {},
    quests = {
      [1] = { title = "First" }, [2] = { title = "High", minLevel = 3 }, [3] = { title = "After", pre = { 1 } },
      [4] = { title = "Either", preAny = { 1, 9 } }, [5] = { title = "Rival", exclusive = { 1 } },
      [6] = { title = "Closed", closed = "it is a quest of another class" }, [7] = { title = "Low", maxLevel = 1 },
    },
    npcs = { [50] = { name = "Giver", offers = { 1, 2, 3, 4, 5, 6, 7 }, alwaysGossip = true } },
  }
  local c = Client.new({ files = {}, world = world, uiMap = 1420, level = 2 }):login()
  eq({ c:offerable(1) }, { true })
  local good, why = c:offerable(2)
  eq(good, false)
  has(why, "level 3")
  good, why = c:offerable(3)
  eq(good, false)
  has(why, "quest 1")
  no((c:offerable(4)), "none of 1, 9 is done")
  eq({ c:offerable(5) }, { true })
  good, why = c:offerable(6)
  eq({ good, why }, { false, "it is a quest of another class" })
  good, why = c:offerable(7)
  eq(good, false)
  has(why, "up to level 1")
  c:talkTo(50)
  eq(c.npc.available, { 1, 5 })
  c:acceptQuest(1)
  good, why = c:offerable(5)
  eq(good, false)
  has(why, "quest 1")
  c:turnInQuest(1)
  c:talkTo(50)
  eq(c.npc.available, { 3, 4 })
end)

test("accepting a quest with a full log fails with the game's message", function()
  local world = { maps = { [1420] = { name = "Tirisfal Glades", type = 3, area = 85 } }, taxi = {}, quests = {},
    npcs = { [50] = { name = "Giver", offers = { 21 } } } }
  local c = Client.new({ files = {}, world = world, uiMap = 1420 }):login()
  for id = 1, 20 do c:acceptQuest(id) end
  local errorsSeen = {}
  local frame = c.G.CreateFrame("Frame")
  frame:RegisterEvent("UI_ERROR_MESSAGE")
  frame:SetScript("OnEvent", function(_, _, _, text) errorsSeen[#errorsSeen + 1] = text end)
  c:talkTo(50)
  c.G.AcceptQuest()
  eq(#c.s.quests, 20)
  eq(errorsSeen, { "Your quest log is full." })
end)

-- ---------------------------------------------------------------------------------------------------------------
-- Plan task E1: secure frames, the options window, merchants, trainers, rewards, the character
-- ---------------------------------------------------------------------------------------------------------------

test("a protected frame changed in combat records a blocked action", function()
  local c = Client.new({ files = {} })
  local G = c.G
  local holder = G.CreateFrame("Frame", nil, G.UIParent)
  local button = G.CreateFrame("Button", nil, holder, "SecureActionButtonTemplate")
  eq({ button:IsProtected() }, { true, true })
  eq({ holder:IsProtected() }, { true, false }, "protected through the button it holds")
  eq({ G.UIParent:IsProtected() }, { true, false })
  button:SetAttribute("type", "item")
  button:SetAttribute("item", "item:6948")
  eq(button:GetAttribute("type"), "item")
  button:SetSize(30, 30)
  button:SetPoint("CENTER")
  c:enterCombat()
  button:SetAttribute("item", "item:1")
  button:Hide()
  button:SetPoint("TOP")
  button:SetSize(10, 10)
  holder:Hide() -- a frame holding a protected one is locked in combat as well
  local blocked = c:takeViolations()
  eq(#blocked, 5)
  for _, v in ipairs(blocked) do has(v, "ADDON_ACTION_BLOCKED") end
  eq(button:GetAttribute("item"), "item:6948", "the change did not happen")
  eq({ button:IsShown(), holder:IsShown(), button:GetWidth() }, { true, true, 30 })
  local plain = G.CreateFrame("Frame", nil, G.UIParent)
  plain:Hide()
  plain:SetAttribute("anything", 1)
  eq(c.violations, {}, "an ordinary frame may change in combat")
  c:leaveCombat()
  button:SetAttribute("item", "item:1")
  eq(c.violations, {})
end)

test("secure buttons use items, cast spells and target an exact name that is near", function()
  local c = Client.new({ files = {}, class = "SHAMAN" }):login()
  local G = c.G
  local casts = {}
  local f = G.CreateFrame("Frame")
  f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
  f:SetScript("OnEvent", function(_, _, unit, _, spell) casts[#casts + 1] = unit .. " " .. spell end)
  local item = G.CreateFrame("Button", nil, G.UIParent, "SecureActionButtonTemplate")
  item:SetAttribute("type", "item")
  item:SetAttribute("item", "item:6948")
  eq(c:secureClick(item), nil, "nothing happens without the item in the bags")
  c:giveItem(6948, 1)
  eq(c:secureClick(item), "item 6948")
  eq(casts, { "player 8690" })
  local start, duration = G.GetItemCooldown(6948)
  eq({ start, duration }, { c.now, 3600 })
  eq(c:secureClick(item), nil, "not while it cools down")
  local spell = G.CreateFrame("Button", nil, G.UIParent, "SecureActionButtonTemplate")
  spell:SetAttribute("type", "spell")
  spell:SetAttribute("spell", 556)
  eq(c:secureClick(spell), nil, "an unknown spell is not cast")
  c:learnSpell(556)
  eq(c:secureClick(spell), "spell 556")
  local target = G.CreateFrame("Button", nil, G.UIParent, "SecureActionButtonTemplate")
  target:SetAttribute("type", "macro")
  target:SetAttribute("macrotext", "/targetexact Mindless Zombie")
  eq(c:secureClick(target), nil, "nobody of that name is near")
  eq(G.UnitExists("target"), false)
  c:near(1501, true)
  eq(c:secureClick(target), "target 1501")
  eq({ G.UnitExists("target"), G.UnitName("target") }, { true, "Mindless Zombie" })
  G.SetRaidTarget("target", 8)
  eq(G.GetRaidTargetIndex("target"), nil, "SetRaidTarget is protected: the addon's call marks nothing")
  eq(c:takeViolations(), { "ADDON_ACTION_FORBIDDEN: SetRaidTarget" })
  eq(#c:events("PLAYER_TARGET_CHANGED"), 1)
  local mark = G.CreateFrame("Button", nil, G.UIParent, "SecureActionButtonTemplate")
  mark:SetAttribute("type", "macro")
  mark:SetAttribute("macrotext", "/cleartarget\n/targetexact Mindless Zombie\n/tm 8")
  eq(c:secureClick(mark), "target 1501")
  eq(G.GetRaidTargetIndex("target"), 8, "a secure /tm sets the marker")
  c:near(1501, false)
  eq(c:secureClick(mark), nil)
  eq(G.UnitExists("target"), false, "/cleartarget first: a miss leaves nothing targeted to mark")
  eq(G.CreateMacro, nil, "the client in the mock has no macro functions to call")
end)

test("the modern and legacy options APIs record the category and what was opened", function()
  local modern = Client.new({ files = {}, settingsApi = "modern" })
  local G = modern.G
  local panel = G.CreateFrame("Frame")
  local category = G.Settings.RegisterCanvasLayoutCategory(panel, "Noir Guides")
  G.Settings.RegisterAddOnCategory(category)
  eq(modern:optionsCategories(), { "Noir Guides" })
  eq(modern:optionsOpenedTo(), nil)
  eq(panel:IsVisible(), false)
  G.Settings.OpenToCategory(category:GetID())
  eq(modern:optionsOpenedTo(), "Noir Guides")
  eq(panel:IsVisible(), true)
  eq(G.InterfaceOptions_AddCategory, nil)
  modern:closeOptions()
  eq({ modern:optionsOpenedTo(), panel:IsVisible() }, { nil, false })
  modern:enterCombat()
  G.Settings.OpenToCategory(category:GetID())
  has(modern:takeViolations()[1], "combat")
  eq(modern:optionsOpenedTo(), nil)

  local legacy = Client.new({ files = {}, settingsApi = "legacy" })
  local old = legacy.G.CreateFrame("Frame")
  old.name = "Noir Guides"
  legacy.G.InterfaceOptions_AddCategory(old)
  eq(legacy:optionsCategories(), { "Noir Guides" })
  legacy.G.InterfaceOptionsFrame_OpenToCategory(old)
  eq(legacy:optionsOpenedTo(), "Noir Guides")
  eq(old:IsVisible(), true)
  eq(legacy.G.Settings, nil)

  local none = Client.new({ files = {}, settingsApi = "none" })
  eq({ none.G.Settings, none.G.InterfaceOptions_AddCategory }, {})
end)

test("merchant, trainer, reward, corpse and bag functions answer from the fake state", function()
  local c = Client.new({ files = {} }):login()
  local G = c.G
  c.s.money = 1000
  -- Bags
  eq(G.GetItemCount(159), 0)
  c:giveItem(159, 5)
  eq(G.GetItemCount(159), 5)
  eq(G.GetContainerNumSlots(0), 16)
  eq(G.GetContainerItemID(0, 1), 159)
  eq(G.GetContainerItemID(0, 2), nil)
  c:takeItem(159, 2)
  eq(G.GetItemCount(159), 3)
  eq(#c:events("BAG_UPDATE"), 2)
  local modern = Client.new({ files = {}, api = "modern" })
  modern:giveItem(159, 1)
  eq(modern.G.C_Container.GetContainerItemID(0, 1), 159)
  eq(modern.G.C_Container.GetContainerNumSlots(0), 16)
  eq(modern.G.GetContainerItemID, nil)
  eq({ G.GetItemCooldown(6948) }, { 0, 0, 1 })

  -- A merchant
  c:openMerchant(5688, { { item = 159, price = 25, stack = 5 }, { item = 2287, price = 100, count = 2 } })
  eq(G.GetMerchantNumItems(), 2)
  local name, _, price, quantity, available = G.GetMerchantItemInfo(1)
  eq({ name, price, quantity, available }, { "Refreshing Spring Water", 25, 5, -1 })
  has(G.GetMerchantItemLink(1), "item:159")
  eq(G.GetMerchantItemMaxStack(1), 20)
  ok(G.UnitGUID("npc"):find("5688"), "the merchant is the NPC")
  G.BuyMerchantItem(1, 10)
  eq({ G.GetItemCount(159), c.s.money }, { 13, 950 })
  G.BuyMerchantItem(2, 5)
  eq(G.GetItemCount(2287), 0, "more than the stock is refused")
  G.BuyMerchantItem(2, 2)
  eq({ G.GetItemCount(2287), c.s.money }, { 2, 750 })
  eq(select(5, G.GetMerchantItemInfo(2)), 0)
  G.CloseMerchant()
  eq({ #c:events("MERCHANT_SHOW"), #c:events("MERCHANT_CLOSED"), G.GetMerchantNumItems() }, { 1, 1, 0 })
  eq(#c:callsTo("BuyMerchantItem"), 3)

  -- A trainer
  c:openTrainer(3156, {
    { name = "Battle Shout", rank = "Rank 2", kind = "available", cost = 100, spell = 5242, level = 12 },
    { name = "Charge", kind = "unavailable", cost = 0, spell = 100, level = 14 },
    { name = "Rend", kind = "used", spell = 772 },
  })
  eq(G.GetNumTrainerServices(), 3)
  eq({ G.GetTrainerServiceInfo(1) }, { "Battle Shout", "Rank 2", "available", false })
  eq({ G.GetTrainerServiceCost(1), G.GetTrainerServiceLevelReq(2), G.IsTradeskillTrainer() }, { 100, 14, false })
  G.BuyTrainerService(1)
  eq({ G.IsSpellKnown(5242), c.s.money, (select(3, G.GetTrainerServiceInfo(1))) }, { true, 650, "used" })
  G.BuyTrainerService(2)
  eq(G.IsSpellKnown(100), false, "an unavailable service is not bought")
  G.CloseTrainer()
  eq({ #c:events("TRAINER_SHOW"), #c:events("TRAINER_CLOSED"), G.GetNumTrainerServices() }, { 1, 1, 0 })
  c:openTrainer(1, {}, { tradeskill = true })
  eq(G.IsTradeskillTrainer(), true)
  c:closeTrainer()

  -- A reward page with choices
  c:acceptQuest(364)
  c:completeObjectives(364)
  c:showReward(364, { { item = 2287, count = 1 }, { item = 159, count = 2 } })
  eq(G.GetNumQuestChoices(), 2)
  local rewardName, _, count, _, _, id = G.GetQuestItemInfo("choice", 2)
  eq({ rewardName, count, id }, { "Refreshing Spring Water", 2, 159 })
  has(G.GetQuestItemLink("choice", 1), "item:2287")
  G.GetQuestReward(2)
  eq({ c.rewards[364], c.s.completed[364], G.GetItemCount(159) }, { 2, true, 15 })

  -- Death, the corpse and coming back
  c:moveTo({ zone = 85, x = 40, y = 60 })
  eq(G.C_DeathInfo.GetCorpseMapPosition(1420), nil)
  c:die()
  eq({ G.UnitIsDeadOrGhost("player"), G.UnitIsGhost("player") }, { true, false })
  c:releaseSpirit({ zone = 85, x = 50, y = 50 })
  eq({ G.UnitIsDeadOrGhost("player"), G.UnitIsGhost("player") }, { true, true })
  local corpse = G.C_DeathInfo.GetCorpseMapPosition(1420)
  near(corpse.x, 0.40, 1e-9)
  near(corpse.y, 0.60, 1e-9)
  eq(G.C_DeathInfo.GetCorpseMapPosition(1411), nil, "not on another map")
  c:resurrect()
  eq({ G.UnitIsDeadOrGhost("player"), G.C_DeathInfo.GetCorpseMapPosition(1420) }, { false, nil })
  eq({ #c:events("PLAYER_DEAD"), #c:events("PLAYER_ALIVE"), #c:events("PLAYER_UNGHOST") }, { 1, 1, 1 })
end)

test("spells, raids, markers, console variables, reloads, watches, shared quests and the game's frames", function()
  local c = Client.new({ files = {} }):login()
  local G = c.G
  eq(G.IsSpellKnown(556), false)
  c:learnSpell(556)
  eq({ G.IsSpellKnown(556), #c:events("LEARNED_SPELL_IN_TAB") }, { true, 1 })
  local seen = {}
  local f = G.CreateFrame("Frame")
  f:RegisterEvent("UNIT_SPELLCAST_START")
  f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
  f:SetScript("OnEvent", function(_, event, unit, _, spell) seen[#seen + 1] = event .. " " .. unit .. " " .. spell end)
  c:moveTo({ zone = 85, x = 61, y = 52 })
  c:bindHearth("Brill")
  c:moveTo({ zone = 130, x = 40, y = 40 })
  c:castSpell(8690)
  eq(seen, { "UNIT_SPELLCAST_START player 8690", "UNIT_SPELLCAST_SUCCEEDED player 8690" })
  eq(G.C_Map.GetBestMapForUnit("player"), 1420, "the hearthstone takes the player home")
  eq({ G.IsInRaid(), G.IsInGroup() }, { false, false })
  c:joinRaid(true)
  eq({ G.IsInRaid(), G.IsInGroup(), #c:events("GROUP_ROSTER_UPDATE") }, { true, true, 1 })
  c:joinRaid(false)
  eq(G.IsInRaid(), false)
  G.SetCVar("nameplateMaxDistance", "41")
  eq({ G.GetCVar("nameplateMaxDistance"), #c:events("CVAR_UPDATE") }, { "41", 1 })
  G.ReloadUI()
  eq(c.reloads, 1)
  eq(type(G.UnitGUID("player")), "string")
  -- The quest tracker
  c:acceptQuest(376)
  local index = G.GetQuestLogIndexByID(376)
  eq(G.IsQuestWatched(index), false)
  G.AddQuestWatch(index)
  eq({ G.IsQuestWatched(index), G.GetNumQuestWatches(), G.MAX_WATCHABLE_QUESTS }, { true, 1, 5 })
  G.RemoveQuestWatch(index)
  eq(G.GetNumQuestWatches(), 0)
  -- A quest shared by a party member
  c:shareQuest(8, "Friend")
  eq(c:events("QUEST_ACCEPT_CONFIRM")[1] ~= nil, true)
  G.ConfirmAcceptQuest()
  ok(c:findQuest(8), "the shared quest is in the log")
  -- The game's own frames: the addon may anchor to them and must not change them
  eq(G.QuestLogFrame:IsShown(), false)
  eq(G.TalentFrame, nil)
  c:openTalentFrame()
  eq({ G.TalentFrame:IsShown(), c:events("ADDON_LOADED")[1] ~= nil }, { true, true })
  G.TalentFrame:SetPoint("CENTER")
  G.QuestLogFrame:Hide()
  eq(#c:takeViolations(), 2)
  eq(G.GetActiveTalentGroup, nil)
  eq(Client.new({ files = {}, api = "modern" }).G.GetActiveTalentGroup(), 1)
  -- Slash commands typed by the test are counted
  G.SlashCmdList.SAMPLE = function() end
  G.SLASH_SAMPLE1 = "/sample"
  eq(c:slashCount(), 0)
  c:slash("/sample")
  eq(c:slashCount(), 1)
end)
