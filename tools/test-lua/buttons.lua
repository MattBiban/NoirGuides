-- Noir Guides, GPLv3. See LICENSE.
-- Item, spell and target buttons (plan task E9, spec 4.6, gaps #25, #26 and #31): secure buttons built from the
-- steps on screen, changed only out of combat, targeting by an attribute (never a macro), raid markers by position,
-- key bindings from Bindings.xml. Every test is driven by game events and clicks, and ends with nothing off screen.
use("tools/test-lua/sample/helper.lua")

local DEATHKNELL = "undead-01-03-deathknell"
local SILVERPINE = "undead-05-06-silverpine-forest"
local GUID = "Player-4444-0000002A"
local KEY = "Tester-Mock"

local function savedAt(section, stepId, options)
  local db = { schema = 2, owner = GUID, guide = { section = section, how = "hand", places = { [section] = { step = stepId } } } }
  local account = {}
  if options then
    account.NoirGuidesDB = { schema = 2, profiles = { Default = options }, defaultProfile = "Default" }
  end
  return { account = account, characters = { [KEY] = { NoirGuidesCharDB = db } } }
end

-- NPCs the sample's steps name, as the mock world needs them for /targetexact.
local NPCS = {
  [1501] = { name = "Mindless Zombie", enemy = true },
  [1502] = { name = "Wretched Ghoul", enemy = true },
  [1508] = { name = "Young Scavenger", enemy = true },
  [1890] = { name = "Rattlecage Skeleton", enemy = true },
  [1765] = { name = "Worg", enemy = true },
  [1950] = { name = "Rane Yorick", offers = { 435 }, ends = { 435 } },
}

local MINDLESS = { title = "The Mindless Ones", level = 2, objectives = {
  { text = "Mindless Zombie slain", type = "monster", need = 8 }, { text = "Wretched Ghoul slain", type = "monster", need = 8 } } }
local DAMNED = { title = "The Damned", level = 2, objectives = {
  { text = "Scavenger Paw", type = "item", need = 6 }, { text = "Duskbat Wing", type = "item", need = 6 } } }

-- A character logged in with its place saved at `stepId`. opts: section, class, level, zone, x, y, log, items
-- ({ id, count } pairs given before login), spells, cooldowns ({ [item] = seconds }), options, screen, api,
-- afterLoad.
local function at(stepId, opts)
  opts = opts or {}
  local c = sample3({ class = opts.class or "WARRIOR", level = opts.level or 2, zone = opts.zone or 85,
    x = opts.x or 50, y = opts.y or 50, saved = savedAt(opts.section or DEATHKNELL, stepId, opts.options),
    screen = opts.screen, api = opts.api, afterLoad = opts.afterLoad })
  for id, def in pairs(NPCS) do c.world.npcs[id] = c.world.npcs[id] or def end
  c.world.items[2856] = "Scavenger Paw"
  for _, q in ipairs(opts.log or {}) do
    if type(q) == "table" then c:acceptQuest(q[1], q[2]) else c:acceptQuest(q) end
  end
  for _, e in ipairs(opts.items or {}) do c:giveItem(e[1], e[2] or 1) end
  for _, spell in ipairs(opts.spells or {}) do c.s.spells[spell] = true end
  for id, seconds in pairs(opts.cooldowns or {}) do c.world.itemCooldowns[id] = seconds end
  c:login()
  c:advance(0.5)
  return c, c.G.Noir, c.G.Noir.Buttons
end

-- The escort step names Rane Yorick and a worg with passive lines only, which would pass it at once: a line to tick
-- keeps it on screen.
local function holdEscort(client)
  for _, step in ipairs(client.G.Noir.Routes.Get("horde-undead").sections[3].steps) do
    if step.id == "tg1950" then step.lines[#step.lines + 1] = { kind = "manual", text = "Walk Erland home." } end
  end
end

local function placeId(Noir)
  local _, _, _, step = Noir.Progress.Place()
  return step and step.id
end

local function names(list)
  local out = {}
  for i, e in ipairs(list) do out[i] = e.name end
  return out
end

local OBJECTIVES = { log = { { 364, MINDLESS }, { 376, DAMNED } } }
local function objectives(extra)
  local opts = { log = OBJECTIVES.log }
  for k, v in pairs(extra or {}) do opts[k] = v end
  return at("o364.o376", opts)
end

-- Item and spell buttons -------------------------------------------------------------------------------------------

test("a use line puts its item on a button and clicking uses it", function()
  local c, Noir, Buttons = at("c2834", { log = { { 376, DAMNED } }, items = { { 2856, 3 } }, cooldowns = { [2856] = 30 } })
  eq(placeId(Noir), "c2834")
  eq(Buttons.Items(), { { kind = "item", id = 2856 } })
  local button = c.G.NoirGuidesItem1
  ok(button and button:IsVisible(), "the first item button shows")
  eq(button:GetAttribute("type"), "item")
  eq(button:GetAttribute("item"), "item:2856")
  eq(c:secureClick(button), "item 2856", "a click uses the item")
  eq(c:callsTo("UseItem"), { { "UseItem", 2856 } })
  -- Its cooldown is shown on the button.
  local cooldown = Buttons.Read().items.buttons[1].cooldown
  eq(cooldown and cooldown.duration, 30)
  -- Hovering shows the item's tooltip.
  c:hover(button)
  eq(c:tooltip()[1], "Scavenger Paw")
  eq(c:offScreen(), {})
end)

test("a hearth line puts the hearthstone on a button, and Astral Recall for a shaman", function()
  local c, Noir, Buttons = at("hs", { section = SILVERPINE, level = 6, zone = 130, x = 50, y = 50, items = { { 6948, 1 } } })
  eq(placeId(Noir), "hs")
  eq(Buttons.Items(), { { kind = "item", id = 6948 } })
  local shaman, _, ShamanButtons = at("hs", { class = "SHAMAN", section = SILVERPINE, level = 6, zone = 130, items = { { 6948, 1 } }, spells = { 556 } })
  eq(ShamanButtons.Items(), { { kind = "spell", id = 556 }, { kind = "item", id = 6948 } }, "spells first")
  local first = shaman.G.NoirGuidesItem1
  eq(first:GetAttribute("type"), "spell")
  eq(shaman:secureClick(first), "spell 556")
  -- Hearthing finishes the step: the next step has no item, so the row goes away.
  eq(c:secureClick(c.G.NoirGuidesItem1), "item 6948")
  c:advance(0.5)
  eq(placeId(Noir), "zep")
  eq(Buttons.Read().items.shown, false)
  eq(c:offScreen(), {})
  eq(shaman:offScreen(), {})
end)

test("buttons appear only with something to show", function()
  local c, Noir, Buttons = at("a363", { level = 1 })
  eq(placeId(Noir), "a363")
  local read = Buttons.Read()
  eq(read.items.shown, false, "no item on the step")
  eq(read.targets.shown, false, "no target on the step")
  -- The objectives step names an item that is not in the bags yet, and three enemies.
  local c2, Noir2, Buttons2 = objectives()
  eq(placeId(Noir2), "o364.o376")
  eq(Buttons2.Items(), {})
  eq(Buttons2.Read().items.shown, false)
  eq(Buttons2.Read().targets.shown, true)
  c2:giveItem(2856, 1)
  c2:advance(0.2)
  eq(Buttons2.Items(), { { kind = "item", id = 2856 } })
  eq(Buttons2.Read().items.shown, true)
  -- With the item buttons switched off they go away.
  Noir2.Options.Set("itemButtons", false)
  eq(Buttons2.Read().items.shown, false)
  Noir2.Options.Set("targetButtons", false)
  eq(Buttons2.Read().targets.shown, false)
  eq(c:offScreen(), {})
  eq(c2:offScreen(), {})
end)

test("nothing secure changes in combat; the change happens after combat", function()
  local c, _, Buttons = objectives()
  eq(Buttons.Read().items.shown, false)
  c:enterCombat()
  c:giveItem(2856, 1)
  c:advance(0.5)
  eq(Buttons.Read().items.shown, false, "not in combat")
  eq(Buttons.Read().pending, true, "the change waits")
  c:leaveCombat()
  eq(Buttons.Read().pending, false)
  eq(Buttons.Read().items.shown, true, "built when combat ends")
  eq(c.G.NoirGuidesItem1:GetAttribute("item"), "item:2856")
  -- Moving a row is refused in combat (the game would block it), whether the drag starts on the row or on one of
  -- its buttons, and with Alt too; out of combat it moves again.
  c:enterCombat()
  local l0, b0 = c:rectOf(Buttons.items)
  ok(c:drag(Buttons.items, 30, 0))
  ok(c:drag(c.G.NoirGuidesItem1, 30, 0))
  c:hold("ALT", true)
  ok(c:drag(Buttons.items, 30, 0))
  c:hold("ALT", false)
  local tl0, tb0 = c:rectOf(Buttons.targets)
  ok(c:drag(c.G.NoirGuidesEnemy1, 0, 30))
  eq(c:takeViolations(), {}, "no protected call in combat")
  local l1, b1 = c:rectOf(Buttons.items)
  eq({ l1, b1 }, { l0, b0 }, "the item row stays")
  local tl1, tb1 = c:rectOf(Buttons.targets)
  eq({ tl1, tb1 }, { tl0, tb0 }, "the target row stays")
  c:leaveCombat()
  c:drag(c.G.NoirGuidesItem1, 30, 0)
  near(c:rectOf(Buttons.items), l0 + 30, 0.01)
  -- The forbidden-call record of the mock is checked after every test: no protected change happened in combat.
  eq(c:offScreen(), {})
end)

-- Target buttons ---------------------------------------------------------------------------------------------------

test("target buttons target the exact name and set markers by position", function()
  local c, Noir, Buttons = objectives()
  -- The current step's enemies first; the open reminder's (Rattlecage Skeleton) after them.
  eq(Buttons.Targets(), { enemy = { "Mindless Zombie", "Wretched Ghoul", "Young Scavenger", "Rattlecage Skeleton" }, friend = {} })
  local second = c.G.NoirGuidesEnemy2
  eq(second:GetAttribute("type"), "macro")
  eq(second:GetAttribute("macrotext"), "/targetexact Wretched Ghoul")
  c:near(1502)
  eq(c:secureClick(second), "target 1502")
  eq(c.marks[1502], 7, "the second enemy gets the cross")
  c:near(1501)
  c:secureClick(c.G.NoirGuidesEnemy1)
  eq(c.marks[1501], 8, "the first enemy gets the skull")
  -- Not near: nothing is targeted and nothing marked.
  local before = #c:callsTo("SetRaidTarget")
  c:secureClick(c.G.NoirGuidesEnemy3)
  eq(#c:callsTo("SetRaidTarget"), before)
  -- The portrait shows once the unit was the target; until then a placeholder.
  local read = Buttons.Read().targets
  eq({ read.enemy[1].portrait, read.enemy[3].portrait }, { true, false })
  -- A friendly target: Rane Yorick on the escort step gets the star.
  local f, Noir2, FButtons = at("tg1950", { section = SILVERPINE, level = 6, zone = 130, afterLoad = holdEscort })
  eq(placeId(Noir2), "tg1950")
  eq(FButtons.Targets(), { enemy = { "Worg" }, friend = { "Rane Yorick" } })
  f:near(1950)
  eq(f:secureClick(f.G.NoirGuidesFriend1), "target 1950")
  eq(f.marks[1950], 1)
  -- Markers off: targeting only.
  Noir2.Options.Set("markers", false)
  f:near(1765)
  f:secureClick(f.G.NoirGuidesEnemy1)
  eq(f.marks[1765], nil)
  eq(c:offScreen(), {})
  eq(f:offScreen(), {})
end)

test("a friendly target talked to is removed", function()
  local c, Noir, Buttons = at("tg1950", { section = SILVERPINE, level = 6, zone = 130, afterLoad = holdEscort })
  eq(Buttons.Targets().friend, { "Rane Yorick" })
  ok(c.G.NoirGuidesFriend1:IsVisible())
  c:talkTo(1950)
  c:closeNpc()
  c:advance(0.2)
  eq(Buttons.Targets().friend, {})
  eq(c.G.NoirGuidesFriend1:IsShown(), false)
  eq(Buttons.Targets().enemy, { "Worg" }, "the enemies stay")
  eq(c:offScreen(), {})
end)

test("target buttons hide on a flight and in raids", function()
  local c, _, Buttons = objectives()
  eq(Buttons.Read().targets.shown, true)
  c:joinRaid(true)
  eq(Buttons.Read().targets.shown, false, "in a raid")
  c:joinRaid(false)
  eq(Buttons.Read().targets.shown, true)
  c:startFlight(10)
  c:advance(0.2)
  eq(Buttons.Read().targets.shown, false, "on a flight")
  c:landFlight()
  c:advance(0.2)
  eq(Buttons.Read().targets.shown, true)
  -- While the hearthstone is being cast.
  c:fire("UNIT_SPELLCAST_START", "player", "Cast-3-4444-0-1-8690-00000A1B2C", 8690)
  eq(Buttons.Read().targets.shown, false, "while hearthing")
  c:fire("UNIT_SPELLCAST_STOP", "player", "Cast-3-4444-0-1-8690-00000A1B2C", 8690)
  eq(Buttons.Read().targets.shown, true)
  eq(c:offScreen(), {})
end)

test("no macro function is called", function()
  local c = objectives()
  c:near(1501)
  c:secureClick(c.G.NoirGuidesEnemy1)
  c:enterCombat()
  c:leaveCombat()
  -- The mock client has none of these functions (calling one would raise an error); the addon does not even look
  -- one up.
  for _, name in ipairs({ "CreateMacro", "EditMacro", "DeleteMacro", "SetBinding", "SetBindingClick", "SetBindingMacro",
    "SetOverrideBinding", "SetOverrideBindingClick" }) do
    eq(c.undefined[name], nil, name)
    eq(c:callsTo(name), {}, name)
  end
  eq(c.errors, {})
  -- The targeting lives in the button's own attribute.
  has(c.G.NoirGuidesEnemy1:GetAttribute("macrotext"), "/targetexact ")
  eq(c:offScreen(), {})
end)

test("the first four buttons of each kind are named and bound in Bindings.xml", function()
  local c = objectives()
  local xml = assert(host.read("NoirGuides/Bindings.xml"))
  local wanted = {}
  for _, kind in ipairs({ "Item", "Friend", "Enemy" }) do
    for i = 1, 4 do
      local name = "NoirGuides" .. kind .. i
      wanted[#wanted + 1] = name
      local frame = c.G[name]
      ok(frame and frame.__protected, name .. " is a secure button")
      ok(xml:find('<Binding name="CLICK ' .. name .. ':LeftButton"', 1, true), name .. " is bound in Bindings.xml")
      eq(type(c.G["BINDING_NAME_CLICK " .. name .. ":LeftButton"]), "string", name .. " has a binding name")
    end
  end
  eq(type(c.G.BINDING_HEADER_NOIRGUIDES), "string")
  ok(xml:find('header="NOIRGUIDES"', 1, true), "the bindings have the addon's header")
  -- These are the only named frames of the addon.
  local named = {}
  for _, frame in ipairs(c.frames) do
    if frame.__name and not frame.__mock then named[#named + 1] = frame.__name end
  end
  table.sort(named)
  table.sort(wanted)
  eq(named, wanted)
  eq(c:offScreen(), {})
end)

test("buttons open at their defaults and stay on screen", function()
  local c, Noir, Buttons = objectives({ items = { { 2856, 1 } } })
  local w, h = c:uiSize()
  local left, bottom, right, top = c:rectOf(Buttons.items)
  near((left + right) / 2, w / 2, 0.01, "items centered")
  near((top + bottom) / 2, h / 2 - 100, 0.01, "items 100 below the middle")
  left, bottom, right, top = c:rectOf(Buttons.targets)
  near((left + right) / 2, w / 2, 0.01, "targets centered")
  near((top + bottom) / 2, h / 2 - 170, 0.01, "targets 170 below the middle")
  -- With enemies and friends (two groups) the target row grows down from its top: it stays below the item row.
  local oneRowTop = top
  Buttons.Preview(true)
  local _, itemsBottom = c:rectOf(Buttons.items)
  left, bottom, right, top = c:rectOf(Buttons.targets)
  ok(top - bottom > 2 * Noir.Theme.metrics.button, "two groups are taller than one row")
  near(top, oneRowTop, 0.01, "the top stays")
  ok(top < itemsBottom, "a little below the item buttons")
  near((left + right) / 2, w / 2, 0.01, "still centered")
  Buttons.Preview(false)
  -- Bigger buttons and a smaller screen: still on the screen.
  Noir.Options.Set("buttonScale", 3)
  c:advance(0.1)
  eq(c:offScreen(), {})
  c:setScreen(800, 600, 1)
  c:advance(0.1)
  eq(c:offScreen(), {})
  -- Locked, an Alt-drag still moves the item buttons; a plain drag does not.
  Noir.Options.Set("buttonScale", 1)
  Noir.Options.Set("locked", true)
  local l0 = c:rectOf(Buttons.items)
  c:drag(Buttons.items, 30, 0)
  eq(c:rectOf(Buttons.items), l0)
  c:hold("ALT", true)
  c:drag(Buttons.items, 30, 0)
  c:hold("ALT", false)
  near(c:rectOf(Buttons.items), l0 + 30, 0.01)
  -- Reset puts both back.
  Buttons.Reset()
  left, bottom, right, top = c:rectOf(Buttons.items)
  w, h = c:uiSize()
  near((left + right) / 2, w / 2, 0.01)
  eq(c:offScreen(), {})
  -- The background follows its switch.
  eq(Buttons.Read().background, true)
  Noir.Options.Set("buttonBackground", false)
  eq(Buttons.Read().background, false)
end)

test("the preview fills the buttons so they can be placed, and goes away again", function()
  local c, Noir, Buttons = at("a363", { level = 1 })
  eq(Buttons.Read().items.shown, false)
  Noir.Screen.Preview(true)
  eq(Buttons.Read().items.shown, true)
  eq(Buttons.Read().targets.shown, true)
  eq(c:offScreen(), {})
  Noir.Screen.Preview(false)
  eq(Buttons.Read().items.shown, false)
  eq(Buttons.Read().targets.shown, false)
end)

test("the nameplate distance is raised and given back when switched off", function()
  local c = sample3({ class = "WARRIOR", cvars = { nameplateMaxDistance = "20" } })
  c:login()
  c:advance(0.5)
  eq(c.G.GetCVar("nameplateMaxDistance"), "41")
  c.G.Noir.Options.Set("nameplates", false)
  eq(c.G.GetCVar("nameplateMaxDistance"), "20")
  -- A client without the setting is left alone.
  local none = sample3({ class = "WARRIOR" })
  none:login()
  eq(none:callsTo("SetCVar"), {})
  -- Logged in (or reloaded) in combat, and switched in combat: the change waits for the end of combat.
  -- (Combat starts once the files are loaded, before the saved variables are read and the addon starts.)
  local seen = { account = {}, characters = { [KEY] = { NoirGuidesCharDB = { schema = 2, owner = GUID, guide = { wizard = true } } } } }
  local fighting = sample3({ class = "WARRIOR", cvars = { nameplateMaxDistance = "20" }, saved = seen,
    afterLoad = function(client) client.s.combat = true end })
  fighting:login()
  fighting:advance(0.5)
  eq(fighting.G.GetCVar("nameplateMaxDistance"), "20", "not in combat")
  fighting:leaveCombat()
  eq(fighting.G.GetCVar("nameplateMaxDistance"), "41", "raised when combat ends")
  fighting:enterCombat()
  fighting.G.Noir.Options.Set("nameplates", false)
  eq(fighting.G.GetCVar("nameplateMaxDistance"), "41")
  fighting:leaveCombat()
  eq(fighting.G.GetCVar("nameplateMaxDistance"), "20", "given back when combat ends")
end)
