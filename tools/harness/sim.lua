-- Noir Guides, GPLv3. See LICENSE.
-- The simulator v3 (plan task X1): the whole addon, exactly as the toc loads it, plays a format 3 route in the mock
-- client (wow.lua) while a scripted player does what the cards on screen say, and nothing else.
--
-- The scripted player reads Progress.Cards() only and does every open active line of every card, in card order:
--   accept / turnin   walk to the line's place (else the step's) and talk to its NPC or object; the automation does
--                     the rest
--   objective         walk there and finish the quest's objectives (the fights give their XP)
--   collect           loot the item
--   goto              walk there
--   getflight         walk to the flight master and talk to it
--   fly               walk to the flight master of `from` and talk to it; the automation takes the flight, it lands
--   transport         walk to the dock and ride to `to`
--   sethearth         walk to the innkeeper and talk to it; the automation answers the bind question
--   hearth            click the item button that holds the Hearthstone
--   grind             fight to the level (or the percent into it)
--   train             walk to the trainer, open its window, buy every service the money covers (class training,
--                     priced by TRAINING_COPPER), close it; at a profession trainer, learn the rank
--   vendor            walk to the merchant, open its window, close it
--   selljunk          walk to the merchant, open its window, wait while the automation sells the grey items, close it
--                     (done before the step's other lines, as a player told to sell before training would)
--   skill             raise the profession to the line's value (SKILL_LINES_CHANGED)
--   manual            click the line's tick box in the window (Window.Tick)
-- It never types a command. When the cards are unchanged after TRIES attempts, the player ticks every open line with
-- the mouse (Window.Tick) and each such card counts as stuck. A level 1 character closes the setup wizard with its
-- close button when it appears.
--
-- The world comes from the quest data (tools/sim_all.js writes it as `facts`, see Sim.world): which NPC offers and
-- takes back which quest, what a quest needs before it is offered, its objectives, the flight masters and
-- innkeepers, the zones' maps, and the character's flattened route (facts.flat). The character's XP follows the pace
-- of tools/lib/xp.js (its constants come in `facts`), so the level the engine sees is the level the planner counted
-- on. The Hearthstone has no cooldown here: the simulated clock does not run at the speed of play.
-- Money: every quest handed in pays TURNIN_COPPER; every objective done leaves one grey item (GREY, real quality 0
-- and a sell price) in the bags, which the automation sells at merchants. A character with facts.professions has
-- learned them at skill 1 before it starts.
--
-- Sim.play(facts, opts) -> { race, class, join, stuck, cannot, unexplained, errors, slash, offScreen,
--                            placement = { expectedFrom, landed, from, to, inside, passedSteps, landedAt }, level,
--                            finished, shown, passed, manual, ticked, wizardClosed }
--   opts: join = level (the character joins there: Sim.prepareJoin), api ("classic"), register = true (facts.route
--   is registered as the race's route and the engine's data is filled from the facts), swap / afterLoad (Client.new
--   options, for tests), beforeAction = function(client, n) (tests), maxActions.
-- Sim.prepareJoin(facts, level) -> { server, expectedFrom, leftOut, to }
--   a player without the addon plays facts.flat in the simulated world until the level is at least `level`, leaving
--   out every 7th accept whose quest is no prerequisite of a later route quest (and that quest's objectives and
--   hand-in). For level 1 the player accepts the first quest only. server: the mock client's state to log in with;
--   expectedFrom: the index of the last action played; to: the first action after it that is not done.
-- Sim.problems(result [, endLevel]) -> { sentence }   what fails the run (nothing: it passes)
--
-- What fails a run: any stuck step, a step shown that the character cannot do (a walk to another continent), a why
-- entry of a kind outside EXPLAINED, a Lua error or forbidden call, a slash command, a frame off the screen at the
-- end, an end level below 60, and for a joiner a placement outside [expectedFrom - JOIN_BACK, to].
local Client = HARNESS.Client
local Sim = {}

Sim.JOIN_LEVELS = { 1, 12, 25, 40, 55 }
Sim.JOIN_BACK = 40   -- flattened actions a joiner may be placed before the last one it did
Sim.TRIES = 2        -- times the player does the cards before they count as stuck
Sim.SETTLE = 1.5     -- seconds after each round of the player's actions
Sim.FRAME = 0.25     -- the frame length inside SETTLE
Sim.END_LEVEL = 60
-- Why-log kinds that carry the game's evidence or describe placement.
Sim.EXPLAINED = { done = true, moot = true, condition = true, outleveled = true, place = true, section = true, route = true }

local HEARTHSTONE, HEARTH_SPELL, ASTRAL_RECALL = 6948, 8690, 556
local OPTIONAL_EVERY = 7
Sim.TURNIN_COPPER = 40
-- The grey items an objective leaves behind: item ID -> { name, price in copper }. Made-up items of quality 0.
Sim.GREY = { [90001] = { name = "Cracked Fang", price = 4 }, [90002] = { name = "Frayed Hide Scrap", price = 9 },
  [90003] = { name = "Dull Stone Chip", price = 17 } }
local GREY_ORDER = { 90001, 90002, 90003 }
-- What class training costs at a level: two services of TRAINING_COPPER(level) / 2 each.
function Sim.TRAINING_COPPER(level) return 20 * level * level end
local RANK_NAMES = { "Apprentice", "Journeyman", "Expert", "Artisan" }
local RANK_CAP = { 75, 150, 225, 300 }
local BAGS = { 16, 16, 16, 0, 0 }

-- ---------------------------------------------------------------------------------------------------------------
-- The pace: the formulas of tools/lib/xp.js (tools/test/sim.test.js checks that both give the same numbers)
-- ---------------------------------------------------------------------------------------------------------------

local function greyLevel(level)
  if level <= 5 then return 0 end
  if level <= 39 then return level - 5 - math.floor(level / 10) end
  if level <= 59 then return level - 1 - math.floor(level / 5) end
  return level - 9
end

local function zeroDifference(level)
  if level <= 7 then return 5 elseif level <= 9 then return 6 elseif level <= 11 then return 7
  elseif level <= 15 then return 8 elseif level <= 19 then return 9 elseif level <= 29 then return 11
  elseif level <= 39 then return 12 elseif level <= 44 then return 13 elseif level <= 49 then return 14
  elseif level <= 54 then return 15 elseif level <= 59 then return 16 end
  return 17
end

-- JavaScript's Math.round: halves go up.
local function round(v) return math.floor(v + 0.5) end

function Sim.mobXp(mobLevel, playerLevel)
  local mob = math.max(1, mobLevel)
  local base = 45 + 5 * playerLevel
  if mob >= playerLevel then return round(base * (1 + 0.05 * math.min(mob - playerLevel, 4))) end
  if mob <= greyLevel(playerLevel) then return 0 end
  return round(base * (1 - (playerLevel - mob) / zeroDifference(playerLevel)))
end

function Sim.questXp(questLevel, playerLevel)
  local diff = playerLevel - questLevel
  if diff > 8 then return 0 end
  local base = questLevel <= 10 and (60 * questLevel + 50) or (110 * questLevel - 500)
  local scale = diff <= 5 and 1 or diff == 6 and 0.8 or diff == 7 and 0.6 or 0.4
  return round(base * scale)
end

-- quest: { level, kills = creature objectives, items = item objectives }
function Sim.objectiveXp(quest, playerLevel, pace)
  local fights = ((quest.kills or 0) + (quest.items or 0) * pace.ITEM_KILL_FACTOR) * pace.OBJECTIVE_KILLS
  return fights * Sim.mobXp(quest.level or 1, playerLevel)
end

-- band: { min, max, wild } of the zone, or nil
function Sim.walkXp(yards, band, playerLevel, pace)
  if not band or not band.wild or not (yards > 0) or yards == math.huge then return 0 end
  local mob = math.min(math.max(playerLevel, band.min), band.max)
  return round((yards / pace.INCIDENTAL_YARDS) * Sim.mobXp(mob, playerLevel))
end

-- ---------------------------------------------------------------------------------------------------------------
-- The world
-- ---------------------------------------------------------------------------------------------------------------

-- facts:
--   race, class                      the character (route names: "Undead", "HighOrder", ...)
--   start = place                    where a fresh character stands
--   xpToLevel = { ... }              XP to finish each level; pace = { OBJECTIVE_KILLS, ITEM_KILL_FACTOR, INCIDENTAL_YARDS }
--   continents[mapId] = { uiMap, name, top, left, width, height }   world yards (top: north edge, left: west edge)
--   zones[area] = { uiMap, name, continent = mapId, minX, maxX, minY, maxY [, band = { min, max, wild }] }
--   quests[id] = { title, level, minLevel, maxLevel, pre, preAny, exclusive, closed, kills, objects, items, credits,
--                  event }
--   npcs[id], objects[id] = { name, offers = { quest IDs }, ends = { quest IDs }, taxi = node, binder = "inn name" }
--   taxi[node] = { name, continent = mapId, zone, x, y, npc }   where this faction's flight master stands
--   flat = { { action, quest, npc, object, node, from, to, at, level, section, step } }   the flattened route
--   route = { format = 3, race, faction, sections }   only for runs that register their own route (opts.register)

-- The objectives in the order of tools/lib/quests.js objectiveList: kills, objects, items, kill credits, the event.
local function objectivesOf(q)
  local out = {}
  for _ = 1, q.kills or 0 do out[#out + 1] = { text = "Creature slain", type = "monster", need = 8 } end
  for _ = 1, q.objects or 0 do out[#out + 1] = { text = "Object used", type = "object", need = 1 } end
  for _ = 1, q.items or 0 do out[#out + 1] = { text = "Item", type = "item", need = 8 } end
  for _ = 1, q.credits or 0 do out[#out + 1] = { text = "Creature slain", type = "monster", need = 8 } end
  if q.event then out[#out + 1] = { text = "Place found", type = "event" } end
  return out
end

-- The mock client's world for the facts.
function Sim.world(facts)
  local maps = {
    [946] = { name = "Cosmic", type = 0 },
    [947] = { name = "Azeroth", type = 1, parent = 946 },
  }
  for mapId, c in pairs(facts.continents) do
    maps[c.uiMap] = { name = c.name, type = 2, parent = 947, instance = mapId,
      world = { top = c.top, left = c.left, width = c.width, height = c.height } }
  end
  -- Two areas can share a map; the map is the lowest area's, as the engine reads it (State.lua, areaForMap).
  local areas = {}
  for area in pairs(facts.zones) do areas[#areas + 1] = area end
  table.sort(areas)
  for _, area in ipairs(areas) do
    local z = facts.zones[area]
    local c = facts.continents[z.continent]
    if not maps[z.uiMap] then
      maps[z.uiMap] = { name = z.name, type = 3, parent = c.uiMap, area = area, rect = {
        (c.left - z.maxY) / c.width, (c.top - z.maxX) / c.height, (c.left - z.minY) / c.width, (c.top - z.minX) / c.height,
      } }
    end
  end
  local taxi = {}
  for node, t in pairs(facts.taxi) do
    local z = facts.zones[t.zone]
    taxi[node] = { name = t.name, continent = facts.continents[t.continent].uiMap, at = { uiMap = z.uiMap, x = t.x, y = t.y } }
  end
  local quests = {}
  for id, q in pairs(facts.quests) do
    quests[id] = {
      title = q.title, level = q.level, header = "Quests", objectives = objectivesOf(q),
      minLevel = q.minLevel, maxLevel = q.maxLevel, pre = q.pre, preAny = q.preAny, exclusive = q.exclusive, closed = q.closed,
    }
  end
  local npcs = {}
  for id, n in pairs(facts.npcs) do
    npcs[id] = { name = n.name, offers = n.offers, ends = n.ends, taxi = n.taxi, binder = n.binder }
  end
  local items, qualities, prices = { [HEARTHSTONE] = "Hearthstone" }, {}, {}
  for id, g in pairs(Sim.GREY) do
    items[id], qualities[id], prices[id] = g.name, 0, g.price
  end
  return {
    maps = maps, taxi = taxi, quests = quests, npcs = npcs,
    items = items, qualities = qualities, prices = prices,
    spells = { [HEARTH_SPELL] = "Hearthstone", [ASTRAL_RECALL] = "Astral Recall" },
    itemSpells = { [HEARTHSTONE] = HEARTH_SPELL },
    stacks = { [HEARTHSTONE] = 1 },
  }
end

-- Quest money and the grey item an objective leaves.
local function pay(c, copper)
  c.s.money = c.s.money + copper
  c:fire("PLAYER_MONEY")
end
local greyCount = 0
local function dropGrey(c)
  greyCount = greyCount + 1
  c:giveItem(GREY_ORDER[(greyCount - 1) % #GREY_ORDER + 1], 1)
end

local function learnProfessions(c, facts)
  for _, skill in ipairs(facts.professions or {}) do
    c:setProfession(skill, facts.professionNames and facts.professionNames[skill] or ("Skill " .. skill), 1, RANK_CAP[1])
  end
end

-- Fills the engine's data tables from the facts, for a registered route that has no generated Data files beside it.
local function fillData(Noir, facts)
  for id, q in pairs(facts.quests) do Noir.Data.quests[id] = q.title end
  for id, n in pairs(facts.npcs) do Noir.Data.npcs[id] = n.name end
  for id, o in pairs(facts.objects or {}) do Noir.Data.objects[id] = o.name end
  for area, z in pairs(facts.zones) do Noir.Data.zones[area] = { uiMap = z.uiMap, name = z.name, continent = z.continent } end
  for node, t in pairs(facts.taxi) do Noir.Data.flights[node] = { name = t.name, zone = t.zone, x = t.x, y = t.y } end
  Noir.Data.items[HEARTHSTONE] = "Hearthstone"
end

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end

-- Yards between two places in one zone.
local function yards(zone, a, b)
  local dx = (a.x - b.x) / 100 * (zone.maxY - zone.minY)
  local dy = (a.y - b.y) / 100 * (zone.maxX - zone.minX)
  return math.sqrt(dx * dx + dy * dy)
end

local function startOf(facts)
  if facts.start and facts.zones[facts.start.zone] then return facts.start end
  for _, a in ipairs(facts.flat or {}) do
    if a.at and facts.zones[a.at.zone] then return a.at end
  end
  return nil
end

local function giveHearthstone(c)
  local bag = c.s.bags[0]
  for slot = 1, bag.size do
    if bag[slot] and bag[slot].id == HEARTHSTONE then return end
  end
  for slot = 1, bag.size do
    if not bag[slot] then
      bag[slot] = { id = HEARTHSTONE, count = 1 }
      return
    end
  end
end

-- Fights until the level, or the percent into it, is reached (or `cap`, a level not to pass).
local function grindTo(c, level, percent, cap)
  local function reached()
    if c.s.level >= 60 then return true end
    if cap and c.s.level >= cap then return true end
    if c.s.level > level then return true end
    if c.s.level < level then return false end
    if not percent or percent <= 0 then return true end
    return c.s.xp * 100 >= percent * c:xpForLevel(c.s.level)
  end
  local guard = 0
  while not reached() and guard < 100 do
    guard = guard + 1
    if c.s.level < level then
      c:gainXP(c:xpForLevel(c.s.level) - c.s.xp)
    else
      c:gainXP(math.max(1, math.ceil(c:xpForLevel(c.s.level) * percent / 100) - c.s.xp))
    end
  end
end

-- ---------------------------------------------------------------------------------------------------------------
-- A joiner's past: the route played without the addon
-- ---------------------------------------------------------------------------------------------------------------

-- Quests of accepts that are a prerequisite of a quest accepted later in the route: never left out.
local function neededLater(facts, flat)
  local needed = {}
  for j = #flat, 1, -1 do
    local a = flat[j]
    if a.action == "accept" then
      local q = facts.quests[a.quest]
      for _, list in ipairs({ q and q.pre or {}, q and q.preAny or {} }) do
        for _, id in ipairs(list) do
          needed[id] = needed[id] or j
        end
      end
    end
  end
  -- needed[id] = the latest accept index that needs it; an accept of id before it is a prerequisite of it.
  return needed
end

-- Whether an action is done in the client's state (for the end of a joiner's window).
local function actionDone(c, a, leftOut)
  local s = c.s
  if a.action == "accept" then return s.completed[a.quest] == true or c:findQuest(a.quest) ~= nil end
  if a.action == "turnin" then return s.completed[a.quest] == true end
  if a.action == "objective" then
    if s.completed[a.quest] then return true end
    local q = c:findQuest(a.quest)
    if not q then return false end
    for _, o in ipairs(q.objectives) do
      if o.type == "event" then
        if not o.done then return false end
      elseif (o.have or 0) < o.need then
        return false
      end
    end
    return true
  end
  if a.action == "getflight" then return s.flights[a.node] == true end
  if a.action == "grind" then return s.level >= a.level end
  return false
end

function Sim.prepareJoin(facts, level)
  local world = Sim.world(facts)
  local flat = facts.flat or {}
  local start = startOf(facts)
  local startZone = start and facts.zones[start.zone]
  local c = Client.new({
    race = facts.race, class = facts.class, level = 1, world = world, files = {}, xpToLevel = facts.xpToLevel,
    uiMap = startZone and startZone.uiMap or nil, x = start and start.x, y = start and start.y, bags = BAGS,
  })
  giveHearthstone(c)
  learnProfessions(c, facts)
  local pos = start and { zone = start.zone, x = start.x, y = start.y } or nil
  local needed = neededLater(facts, flat)
  local leftOut, skipped, objectivesDone = {}, {}, {}
  local optional, expectedFrom = 0, 0

  local function moveTo(point)
    local zone = point and facts.zones[point.zone]
    if not zone then return end
    if pos and pos.zone == point.zone then c:gainXP(Sim.walkXp(yards(zone, pos, point), zone.band, c.s.level, facts.pace)) end
    pos = { zone = point.zone, x = point.x, y = point.y }
    c.s.pos = { uiMap = zone.uiMap, x = point.x, y = point.y }
  end

  local function finishObjectives(id)
    local q = c:findQuest(id)
    if not q then return end
    for _, o in ipairs(q.objectives) do
      if o.type == "event" then o.done = true else o.have = o.need end
    end
  end

  local DO = {}
  function DO.accept(a, i)
    if c:findQuest(a.quest) or c.s.completed[a.quest] then return end
    if not (needed[a.quest] and needed[a.quest] > i) then
      optional = optional + 1
      if optional % OPTIONAL_EVERY == 0 then
        leftOut[#leftOut + 1] = a.quest
        skipped[a.quest] = true
        return
      end
    end
    if not c:offerable(a.quest) or #c.s.quests >= 20 then
      skipped[a.quest] = true
      return
    end
    skipped[a.quest] = nil
    c:acceptQuest(a.quest)
  end
  function DO.objective(a)
    if objectivesDone[a.quest] or not c:findQuest(a.quest) then return end
    objectivesDone[a.quest] = true
    finishObjectives(a.quest)
    c:gainXP(Sim.objectiveXp(facts.quests[a.quest] or {}, c.s.level, facts.pace))
  end
  function DO.turnin(a)
    if not c:findQuest(a.quest) then return end
    finishObjectives(a.quest)
    local quest = facts.quests[a.quest] or {}
    c:turnInQuest(a.quest, Sim.questXp(quest.level or 1, c.s.level))
    c.s.money = c.s.money + Sim.TURNIN_COPPER
  end
  function DO.getflight(a) c.s.flights[a.node] = true end
  function DO.fly(a)
    c.s.flights[a.from], c.s.flights[a.to] = true, true
    local t = facts.taxi[a.to]
    if t then moveTo({ zone = t.zone, x = t.x, y = t.y }) end
  end
  function DO.transport(a) if a.to then moveTo(a.to) end end
  function DO.travel() end
  function DO.hearth()
    local bind = c.s.bind
    if bind.pos and bind.area then moveTo(bind.area) end
  end
  function DO.sethearth(a)
    local def = facts.npcs[a.npc or 0]
    if pos and facts.zones[pos.zone] then
      c.s.bind = { name = def and def.binder or "Inn", pos = copy(c.s.pos), area = copy(pos) }
    end
  end
  function DO.grind(a) grindTo(c, a.level, nil, level) end

  for i, a in ipairs(flat) do
    if level <= 1 then
      if a.action == "accept" then
        if a.at then moveTo(a.at) end
        c:acceptQuest(a.quest)
        expectedFrom = i
        break
      end
    else
      if c.s.level >= level then break end
      if a.at and a.action ~= "hearth" and a.action ~= "fly" then moveTo(a.at) end
      if DO[a.action] then DO[a.action](a, i) end
      expectedFrom = i
    end
  end
  for _, q in ipairs(c.s.quests) do q.header = "Quests" end
  local to = #flat + 1
  for i = expectedFrom + 1, #flat do
    if not actionDone(c, flat[i], skipped) then
      to = i
      break
    end
  end
  c.s.bind.area = nil
  return { server = c.s, expectedFrom = expectedFrom, leftOut = leftOut, to = to }
end

-- ---------------------------------------------------------------------------------------------------------------
-- Playing
-- ---------------------------------------------------------------------------------------------------------------

local OPEN = { done = false, skip = false }

local function plural(n, one, many) return string.format("%d %s", n, n == 1 and one or many) end

function Sim.problems(r, endLevel)
  endLevel = endLevel or Sim.END_LEVEL
  local out = {}
  local n = function(list) return list and #list or 0 end
  if not r.finished then out[#out + 1] = "not played to its end" end
  if n(r.stuck) > 0 then out[#out + 1] = plural(n(r.stuck), "stuck step", "stuck steps") end
  if n(r.cannot) > 0 then out[#out + 1] = plural(n(r.cannot), "step the character cannot do", "steps the character cannot do") end
  if n(r.unexplained) > 0 then out[#out + 1] = plural(n(r.unexplained), "unexplained skip", "unexplained skips") end
  if n(r.errors) > 0 then out[#out + 1] = plural(n(r.errors), "Lua error", "Lua errors") end
  if (r.slash or 0) > 0 then out[#out + 1] = plural(r.slash, "slash command", "slash commands") end
  if n(r.offScreen) > 0 then out[#out + 1] = plural(n(r.offScreen), "frame off the screen", "frames off the screen") end
  if not (type(r.level) == "number" and r.level >= endLevel) then out[#out + 1] = "ends at level " .. tostring(r.level) end
  if r.join then
    local p = r.placement or {}
    if not p.inside then
      out[#out + 1] = string.format("placed at action %s, outside %s to %s", tostring(p.landed), tostring(p.from), tostring(p.to))
    end
  end
  return out
end

function Sim.play(facts, opts)
  opts = opts or {}
  local world = Sim.world(facts)
  local info = Client.RACES[facts.race]
  local flat = facts.flat or {}
  local result = { race = facts.race, class = facts.class, join = opts.join, stuck = {}, cannot = {}, unexplained = {},
    errors = {}, manual = {}, shown = 0, passed = {}, ticked = 0 }
  local tickAllowance = 0
  local whyLog = {}
  local capturing, landed = true, nil

  local prepared = opts.join and Sim.prepareJoin(facts, opts.join) or nil
  local start = startOf(facts)
  local startZone = start and facts.zones[start.zone]
  local clientOpts = {
    race = facts.race, class = facts.class, level = 1, world = world, api = opts.api or "classic",
    uiMap = startZone and startZone.uiMap or nil, x = start and start.x, y = start and start.y,
    xpToLevel = facts.xpToLevel, swap = opts.swap, server = prepared and prepared.server or nil, bags = BAGS,
    afterLoad = function(c)
      local Noir = c.G.Noir
      if opts.register then
        fillData(Noir, facts)
        Noir.Route(info.faction:lower() .. "-" .. facts.race:lower(), copy(facts.route))
      end
      Noir.On("NOIR_WHY", function(_, entry)
        if Sim.EXPLAINED[entry.kind] then
          result.passed[entry.kind] = (result.passed[entry.kind] or 0) + 1
        elseif entry.kind == "tick" and tickAllowance > 0 then
          tickAllowance = tickAllowance - 1
        else
          whyLog[#whyLog + 1] = { section = entry.section, step = entry.step, n = entry.n, kind = entry.kind, label = entry.label, text = entry.text }
        end
      end)
      -- The place the engine puts the character at when it loads a section during the login.
      local expect = false
      Noir.On("NOIR_SECTION", function() if capturing then expect = true end end)
      Noir.On("NOIR_PLACE", function(_, section, index)
        if capturing and expect then
          landed = { section = section, index = index }
          expect = false
        end
      end)
      if opts.afterLoad then opts.afterLoad(c) end
    end,
  }
  local c = Client.new(clientOpts)
  giveHearthstone(c)
  if not prepared then learnProfessions(c, facts) end
  c:login()
  capturing = false
  local Noir = c.G.Noir
  local P = Noir.Progress

  -- Where the character stands, as a zone of the facts (two zones can share a map: the one it walked to wins).
  local pos
  local function locate()
    local p = c.s.pos
    for area, z in pairs(facts.zones) do
      if z.uiMap == p.uiMap and (not pos or facts.zones[pos.zone].uiMap ~= p.uiMap or area == pos.zone) then
        pos = { zone = area, x = p.x, y = p.y }
        return
      end
    end
  end
  locate()

  -- ------------------------------------------------------------------------------------------------------------
  -- Placement of a joiner, in flattened actions
  -- ------------------------------------------------------------------------------------------------------------
  if prepared and opts.trace then
    for _, e in ipairs(Noir.Why.List()) do opts.placeNotes = (opts.placeNotes or "") .. "[" .. tostring(e.kind) .. ": " .. tostring(e.text) .. "] " end
  end
  if prepared then
    if not landed then
      local section, index = P.Place()
      landed = { section = section, index = index }
    end
    local order, position = {}, {}
    local first = flat[1] and flat[1].section
    for _, id in ipairs(first and Noir.Guide.Chain(first) or {}) do
      for _, step in ipairs(Noir.Guide.Steps(id)) do
        order[#order + 1] = id .. "/" .. step.id
        position[id .. "/" .. step.id] = #order
      end
    end
    local steps = landed.section and Noir.Guide.Steps(landed.section) or {}
    local step = steps[landed.index]
    local key = step and (landed.section .. "/" .. step.id)
    local at = key and position[key]
    local index = #flat + 1
    if at then
      for i, a in ipairs(flat) do
        local p = position[a.section .. "/" .. a.step]
        if p and p >= at then
          index = i
          break
        end
      end
    end
    local from = math.max(1, prepared.expectedFrom - Sim.JOIN_BACK)
    result.placement = {
      expectedFrom = prepared.expectedFrom, landed = index, from = from, to = prepared.to,
      inside = index >= from and index <= prepared.to, passedSteps = at and (at - 1) or nil,
      landedAt = key, leftOut = #prepared.leftOut, notes = opts.placeNotes,
    }
  end

  local function label(step) return Noir.Why.Describe(step) end
  local cannotSeen = {}
  local function cannot(step, reason)
    local key = tostring(step.id) .. "|" .. reason
    if cannotSeen[key] then return end
    cannotSeen[key] = true
    result.cannot[#result.cannot + 1] = { step = step.id, n = step.n, label = label(step), reason = reason }
  end

  -- Walks to a place: the fights on the way give their XP inside one zone, as the planner counts them.
  local function walk(step, point)
    if not point then return end
    local zone = facts.zones[point.zone]
    if not zone then
      cannot(step, "the zone " .. tostring(point.zone) .. " is not in the simulated world")
      return
    end
    local here = pos and facts.zones[pos.zone]
    if here and here.continent ~= zone.continent then
      cannot(step, string.format("%s is in %s, on another continent than the character (in %s), who cannot walk there",
        label(step), zone.name, here.name))
    elseif here and pos.zone == point.zone then
      c:gainXP(Sim.walkXp(yards(zone, pos, point), zone.band, c.s.level, facts.pace))
    end
    c:moveTo({ uiMap = zone.uiMap, x = point.x, y = point.y })
    pos = { zone = point.zone, x = point.x, y = point.y }
  end

  local function whoFor(line)
    if line.npc and line.npc > 0 then return facts.npcs[line.npc], line.npc, "NPC" end
    if line.object and line.object > 0 then return (facts.objects or {})[line.object], line.object, "object" end
    return nil
  end

  -- Where the client lists an NPC's quests by title only and the line's title belongs to more than one quest of the
  -- route (a chain whose parts share a name), the automation leaves the choice to the player (Automation.lua). The
  -- player then picks the line's quest, as a person would.
  local function pickByHand(step, quest, kind)
    local npc = c.npc
    if not (npc and (npc.window == "gossip" or npc.window == "greeting")) then return end
    local title = world.quests[quest] and world.quests[quest].title
    local listed, same = false, {}
    for _, id in ipairs(npc[kind] or {}) do
      if id == quest then listed = true end
      if world.quests[id] and world.quests[id].title == title then same[id] = true end
    end
    for id, q in pairs(world.quests) do
      if q.title == title then same[id] = true end
    end
    local count = 0
    for _ in pairs(same) do count = count + 1 end
    if not (listed and count > 1) then return end
    result.manual[#result.manual + 1] = { n = step.n, label = label(step),
      reason = string.format("%d quests share the title %q and the client gives titles only: the player picks", count, title) }
    if kind == "available" then c:showDetail(quest) else c:showActive(quest) end
  end

  local function talk(id, def)
    c:talkTo(id, def)
    c:advance(0.3, 0.1)
  end

  local objectivesDone = {}
  local ACT = {}

  function ACT.accept(line, step)
    if c:findQuest(line.quest) or c.s.completed[line.quest] then return nil end
    local def, id, kind = whoFor(line)
    if not def then return "the line names no NPC or object that offers quest " .. line.quest end
    local good, why = c:offerable(line.quest)
    local offers = false
    for _, q in ipairs(def.offers or {}) do if q == line.quest then offers = true end end
    talk(id, def)
    if not c:findQuest(line.quest) then pickByHand(step, line.quest, "available") end
    c:closeNpc()
    if c:findQuest(line.quest) then return nil end
    if not offers then return string.format("%s %d does not offer quest %d", kind, id, line.quest) end
    if not good then return "quest " .. line.quest .. " is not offered: " .. why end
    if #c.s.quests >= 20 then return "the quest log is full" end
    return "the automation did not accept quest " .. line.quest
  end

  function ACT.objective(line)
    if c.s.completed[line.quest] then return nil end
    local q = c:findQuest(line.quest)
    if not q then return "quest " .. line.quest .. " is not in the quest log" end
    if not objectivesDone[line.quest] then
      objectivesDone[line.quest] = true
      c:completeObjectives(line.quest)
      c:gainXP(Sim.objectiveXp(facts.quests[line.quest] or {}, c.s.level, facts.pace))
      dropGrey(c)
    end
    return nil
  end

  function ACT.turnin(line, step)
    if c.s.completed[line.quest] then return nil end
    local def, id, kind = whoFor(line)
    if not def then return "the line names no NPC or object that takes quest " .. line.quest end
    local q = c:findQuest(line.quest)
    if not q then return "quest " .. line.quest .. " is not in the quest log" end
    local quest = facts.quests[line.quest] or {}
    if world.quests[line.quest] then world.quests[line.quest].xp = Sim.questXp(quest.level or 1, c.s.level) end
    local calls = #c.calls
    talk(id, def)
    if opts.trace and not c.s.completed[line.quest] then
      local seen = {}
      for k = calls + 1, #c.calls do seen[#seen + 1] = tostring(c.calls[k][1]) .. "(" .. tostring(c.calls[k][2]) .. ")" end
      local npc = c.npc
      opts.traceNote = string.format("window=%s active=%s available=%s calls=%s", tostring(npc and npc.window),
        npc and table.concat(npc.active or {}, ",") or "", npc and table.concat(npc.available or {}, ",") or "", table.concat(seen, " "))
    end
    if not c.s.completed[line.quest] then pickByHand(step, line.quest, "active") end
    c:closeNpc()
    if c.s.completed[line.quest] then
      pay(c, Sim.TURNIN_COPPER)
      return nil
    end
    local ends = false
    for _, e in ipairs(def.ends or {}) do if e == line.quest then ends = true end end
    if not ends then return string.format("%s %d does not take quest %d", kind, id, line.quest) end
    for _, o in ipairs(q.objectives) do
      local done = (o.type == "event" and o.done) or (o.type ~= "event" and (o.have or 0) >= o.need)
      if not done then return "the objectives of quest " .. line.quest .. " are not complete" end
    end
    return "the automation did not hand in quest " .. line.quest
  end

  function ACT.collect(line)
    local have = c:itemCount(line.item)
    if have < line.count then c:giveItem(line.item, line.count - have) end
    return nil
  end

  ACT["goto"] = function() return nil end

  function ACT.getflight(line)
    local def = facts.npcs[line.npc or 0]
    if not (def and def.taxi) then return "NPC " .. tostring(line.npc) .. " is not a flight master" end
    talk(line.npc, def)
    c:closeTaxi()
    c:closeNpc()
    if def.taxi ~= line.node then return "NPC " .. line.npc .. " is the flight master of node " .. def.taxi .. ", not " .. line.node end
    return nil
  end

  function ACT.fly(line)
    local from = facts.taxi[line.from]
    if not from then return "flight point " .. line.from .. " is not one of the character's faction" end
    if not facts.taxi[line.to] then return "flight point " .. line.to .. " is not one of the character's faction" end
    if from.npc and facts.npcs[from.npc] then c:talkTo(from.npc, facts.npcs[from.npc]) else c:openTaxi(line.from) end
    c:advance(0.5, 0.1) -- the automation waits a moment after the flight map opens
    if c.flightTo then
      local to = c.flightTo
      c:advance(5, 1)
      c:landFlight()
      locate()
      if to ~= line.to then return "the automation took a flight to " .. to .. ", not " .. line.to end
      return nil
    end
    c:closeTaxi()
    c:closeNpc()
    local why = c.s.flights[line.to] and "" or " (the character has not learned it)"
    return "the flight to " .. line.to .. " was not taken" .. why
  end

  function ACT.transport(line, step)
    local zone = facts.zones[line.to.zone]
    if not zone then return "the zone " .. line.to.zone .. " is not in the simulated world" end
    c:moveTo({ uiMap = zone.uiMap, x = line.to.x, y = line.to.y })
    pos = { zone = line.to.zone, x = line.to.x, y = line.to.y }
    return nil
  end

  function ACT.sethearth(line, step)
    local def = facts.npcs[line.npc or 0]
    if not (def and def.binder) then return "NPC " .. tostring(line.npc) .. " is not an innkeeper" end
    talk(line.npc, def)
    c:closeNpc()
    return nil
  end

  -- The item button that holds the Hearthstone (or Astral Recall): a shown secure button of the item row.
  local function hearthButton()
    local row = Noir.Buttons and Noir.Buttons.items
    local found
    local function search(frame)
      for _, child in ipairs(frame.__children or {}) do
        if found then return end
        if child.__protected and child:IsVisible() then
          local kind = child:GetAttribute("type")
          if (kind == "item" and child:GetAttribute("item") == "item:" .. HEARTHSTONE)
            or (kind == "spell" and tonumber(child:GetAttribute("spell")) == ASTRAL_RECALL) then
            found = child
            return
          end
        end
        search(child)
      end
    end
    if row then search(row) end
    return found
  end

  function ACT.hearth()
    local button = hearthButton()
    if not button then return "no item button holds the Hearthstone" end
    local did = c:secureClick(button)
    if not did then return "the Hearthstone button did nothing" end
    locate()
    return nil
  end

  function ACT.grind(line)
    grindTo(c, line.level, line.percent)
    return nil
  end

  -- Class training: two services for the visit's level; the player buys each one the money covers.
  local function classServices(level)
    local each = math.floor(Sim.TRAINING_COPPER(level) / 2)
    return { { name = "Level " .. level .. " lesson", rank = "Rank 1", kind = "available", cost = each, level = level },
      { name = "Level " .. level .. " drill", rank = "Rank 1", kind = "available", cost = each, level = level } }
  end

  function ACT.train(line)
    if line.class and line.level and c.s.level < line.level then
      return string.format("the trainer visit is for level %d and the character is level %d", line.level, c.s.level)
    end
    if line.skill and line.rank then
      local name = facts.professionNames and facts.professionNames[line.skill] or ("Skill " .. line.skill)
      c:openTrainer(line.npc or 0, { { name = name, rank = RANK_NAMES[line.rank], kind = "available", cost = 0 } }, { tradeskill = true })
      c:advance(0.3, 0.1)
      local have = 1
      for _, p in ipairs(c.s.professions) do if p.skillLine == line.skill then have = p.rank end end
      c:setProfession(line.skill, name, have, RANK_CAP[line.rank])
      c:closeTrainer()
      return nil
    end
    c:openTrainer(line.npc or 0, line.class and line.level and classServices(line.level) or {})
    c:advance(0.3, 0.1)
    if line.class and c.trainer then
      for i, e in ipairs(c.trainer.services) do
        if e.kind == "available" and e.cost <= c.s.money then c.G.BuyTrainerService(i) end
      end
    end
    c:closeTrainer()
    if line.spell and not c.s.spells[line.spell] then return "spell " .. line.spell .. " was not learned at the trainer" end
    return nil
  end

  function ACT.vendor(line)
    local items = {}
    if line.buy then items[1] = { item = line.buy.item, price = 0, stack = 1, count = -1 } end
    c:openMerchant(line.npc or 0, items)
    c:advance(0.5 + 0.25 * #c.G.Noir.State.JunkSlots(), 0.1) -- the automation sells the grey items, one slot a tick
    c:closeMerchant()
    return nil
  end

  function ACT.selljunk(line)
    local before = c.s.money
    c:openMerchant(line.npc or 0, {})
    c:advance(0.5 + 0.25 * #c.G.Noir.State.JunkSlots(), 0.1)
    c:closeMerchant()
    result.sold = (result.sold or 0) + (c.s.money - before)
    result.sellLines = (result.sellLines or 0) + 1
    return nil
  end

  function ACT.skill(line)
    local have, name = 0, facts.professionNames and facts.professionNames[line.skill] or ("Skill " .. line.skill)
    local max = RANK_CAP[1]
    for _, p in ipairs(c.s.professions) do
      if p.skillLine == line.skill then have, max = p.rank, p.max end
    end
    if have < line.value then
      c:setProfession(line.skill, name, math.min(line.value, max), max)
      result.skillRaised = (result.skillRaised or 0) + 1
    end
    if math.min(line.value, max) < line.value then
      return string.format("%s cannot pass %d before its next rank, and the line asks for %d", name, max, line.value)
    end
    return nil
  end

  -- A line's tick box in the window: the card's place in the stack and the line's place on the card.
  local function tickBox(k, i)
    local window = Noir.Window
    return window and window.Tick and window.Tick(k, i)
  end

  local function clickTick(k, i, card, l)
    local box = tickBox(k, i)
    if box and c:click(box) then return true end
    result.errors[#result.errors + 1] = string.format("the tick box of line %d of card %d (step %s) could not be clicked", i, k, tostring(card.step.id))
    P.Tick(card.index, l.index, true)
    return false
  end

  -- Ticking is how a manual line is done: the "tick" entry it leaves in the why-log is the player's own.
  function ACT.manual(line, step, k, i, card, l)
    tickAllowance = tickAllowance + 1
    clickTick(k, i, card, l)
    return nil
  end

  local function placeOf(line, step)
    if line.kind == "goto" or line.kind == "transport" then return line.at end
    if line.kind == "hearth" or line.kind == "grind" or line.kind == "manual" or line.kind == "skill" then return nil end
    if line.kind == "fly" then
      -- The flight master of the node the flight leaves from (the step's own place may be another line's).
      local t = facts.taxi[line.from]
      if t then return { zone = t.zone, x = t.x, y = t.y } end
      return line.at or step.at
    end
    return line.at or step.at
  end

  local function open(l)
    return Noir.Lines.Active(l.line) and OPEN[l.state] == nil and not l.ticked
  end

  local function signature(cards)
    local parts = {}
    for k, card in ipairs(cards) do
      local piece = card.kind .. ":" .. tostring(card.step.id)
      for _, l in ipairs(card.lines) do
        local ctr = l.counter
        piece = piece .. "," .. tostring(l.index) .. l.state .. (l.ticked and "t" or "") .. (ctr and (tostring(ctr.have) .. "/" .. tostring(ctr.need)) or "")
      end
      parts[k] = piece
    end
    return table.concat(parts, ";")
  end

  local function closeWizard()
    local wizard = Noir.Wizard
    if not (wizard and wizard.Read and wizard.Read().shown) then return end
    local button = wizard.Button("close")
    if button and c:click(button) then result.wizardClosed = true end
  end

  local seen = {}
  local trace = opts.trace and {} or nil
  result.trace = trace
  local lastSig, tries = nil, 0
  local reasons = {}
  local idle = 0
  local actions, maxActions = 0, opts.maxActions or 30000
  while actions < maxActions do
    actions = actions + 1
    if opts.beforeAction then opts.beforeAction(c, actions) end
    closeWizard()
    if P.Complete() then break end
    local cards = P.Cards()
    if #cards == 0 then
      idle = idle + 1
      if idle > 5 then break end
      c:advance(Sim.SETTLE, Sim.FRAME)
    else
      idle = 0
      local currentCard = cards[#cards]
      if currentCard.kind == "current" and not seen[currentCard.step.id] then
        seen[currentCard.step.id] = true
        result.shown = result.shown + 1
      end
      local sig = signature(cards)
      if sig == lastSig then tries = tries + 1 else tries, lastSig = 0, sig end
      if tries >= Sim.TRIES then
        local section = P.Place()
        for k, card in ipairs(cards) do
          local ticks = {}
          for i, l in ipairs(card.lines) do
            if open(l) and l.index and l.index > 0 then ticks[#ticks + 1] = i end
          end
          if #ticks > 0 then
            -- The card's "tick" entry in the why-log belongs to this stuck step (counted here, not as unexplained).
            tickAllowance = tickAllowance + 1
            for _, i in ipairs(ticks) do
              clickTick(k, i, card, card.lines[i])
              result.ticked = result.ticked + 1
            end
            result.stuck[#result.stuck + 1] = { section = section, step = card.step.id, n = card.step.n, kind = card.kind,
              label = label(card.step), reason = reasons[card.step.id] or "the engine did not move on" }
          end
        end
        lastSig, tries = nil, 0
        if trace then
          local ids = {}
          for _, q in ipairs(c.s.quests) do ids[#ids + 1] = q.id end
          trace[#trace + 1] = string.format("%d STUCK %s log=%s", actions, tostring(result.stuck[#result.stuck] and result.stuck[#result.stuck].step), table.concat(ids, ","))
        end
      else
        local failed = {}
        for k, card in ipairs(cards) do
          local step = card.step
          -- A selljunk line is done before the card's other lines: sell first, then train.
          local order = {}
          for i, l in ipairs(card.lines) do if l.line and l.line.kind == "selljunk" then order[#order + 1] = i end end
          for i, l in ipairs(card.lines) do if not (l.line and l.line.kind == "selljunk") then order[#order + 1] = i end end
          for _, i in ipairs(order) do
            local l = card.lines[i]
            if open(l) then
              local line = l.line
              local act = ACT[line.kind]
              local reason
              local before = #c.calls
              if act then
                walk(step, placeOf(line, step))
                reason = act(line, step, k, i, card, l)
                -- The automation may take a flight at any flight map the player opened (a flight point learned
                -- just before the step that flies on): the player rides it to the end.
                if c.flightTo then
                  c:advance(5, 1)
                  c:landFlight()
                  locate()
                end
              else
                reason = "the simulator has no player action for " .. tostring(line.kind)
              end
              -- The first thing that went wrong on the card this round is why it is stuck.
              if reason and not failed[step.id] then reasons[step.id], failed[step.id] = reason, true end
              if trace then
                trace[#trace + 1] = string.format("%d L%d Q%d %s %s %s %s %s -> %s%s", actions, c.s.level, #c.s.quests, card.kind, tostring(step.id),
                  line.kind, tostring(line.quest or line.node or line.level or ""), l.state, tostring(reason or "ok"),
                  reason and opts.traceNote and (" [" .. opts.traceNote .. "]") or "")
                opts.traceNote = nil
                for n = before + 1, #c.calls do
                  if c.calls[n][1] == "TakeTaxiNode" then trace[#trace] = trace[#trace] .. " {TakeTaxiNode " .. tostring(c.calls[n][3]) .. "}" end
                end
              end
            end
          end
        end
      end
      c:advance(Sim.SETTLE, Sim.FRAME)
    end
  end

  closeWizard()
  result.finished = P.Complete() == true
  result.actions = actions
  result.level, result.xp = c.s.level, c.s.xp
  result.unexplained = whyLog
  result.slash = c:slashCount()
  result.offScreen = c:offScreen()
  for _, e in ipairs(c.errors) do result.errors[#result.errors + 1] = tostring(e) end
  for _, v in ipairs(c.violations) do result.errors[#result.errors + 1] = "forbidden call: " .. tostring(v) end
  c:takeErrors()
  c:takeViolations()
  result.client = c
  return result
end

-- ---------------------------------------------------------------------------------------------------------------
-- Output for tools/sim_all.js
-- ---------------------------------------------------------------------------------------------------------------

local function isArray(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  for i = 1, n do if t[i] == nil then return false end end
  return true
end

function Sim.json(v)
  local t = type(v)
  if t == "nil" then return "null" end
  if t == "boolean" then return tostring(v) end
  if t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "null" end
    if math.type(v) == "integer" or v == math.floor(v) then return string.format("%d", v) end
    return string.format("%.14g", v)
  end
  if t == "string" then
    return '"' .. v:gsub('[%c"\\]', function(ch)
      if ch == '"' then return '\\"' elseif ch == "\\" then return "\\\\" elseif ch == "\n" then return "\\n"
      elseif ch == "\r" then return "\\r" elseif ch == "\t" then return "\\t" end
      return string.format("\\u%04x", ch:byte())
    end) .. '"'
  end
  if t == "table" then
    local parts = {}
    if isArray(v) then
      for i = 1, #v do parts[i] = Sim.json(v[i]) end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for k in pairs(v) do if type(k) == "string" or type(k) == "number" then keys[#keys + 1] = k end end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
      local value = v[k]
      if type(value) ~= "function" and not (type(value) == "table" and getmetatable(value)) then
        parts[#parts + 1] = Sim.json(tostring(k)) .. ":" .. Sim.json(value)
      end
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return "null"
end

-- Plays the character in SIM_FACTS (the shipped route unless opts.register) and prints the result as one JSON line.
function Sim.main(facts, opts)
  local r = Sim.play(facts, opts)
  r.client = nil
  print("SIMRESULT " .. Sim.json(r))
end

HARNESS.Sim = Sim
