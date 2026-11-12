-- Noir Guides, GPLv3. See LICENSE.
-- State: what is true about the character right now. Other modules read it and never ask the client themselves.
--
--   State.class, .race, .faction      "ROGUE", "Undead", "Horde" (race as the routes name it)
--   State.level, .xp, .xpMax
--   State.ready                       true once the quest log has been read after entering the world
--   State.quests[id]                  { id, title, level, complete, failed, objectives = { { text, kind, done, have, need } } }
--   State.logHidden                   true while a collapsed header hides part of the quest log
--   State.Quest(id), .HasQuest(id), .IsDone(id)
--   State.flights[node], .KnowsFlight(node), .LearnFlight(node, how)
--   State.taxiOpen, .taxiNode, .taxiSlots[node]   while the flight map is open
--   State.hearth                      { name [, zone, x, y] } or nil
--   State.professions[skillLine]      { name, rank, max };  State.Profession(skillLine) -> rank, max
--   State.zone                        area ID of the current zone, nil when unknown
--   State.Position()                  -> zone, x, y, uiMap (x and y in map percent), or nil
--   State.Continent()                 -> uiMap of the continent, or nil
--   State.inCombat, State.OnTaxi()
--
-- Facts the lines of a step read (plan task E3); times are GetTime() seconds:
--   State.ItemCount(id)               how many the bags hold
--   State.KnowsSpell(id)              the spell is known
--   State.RecentAccept(quest), State.RecentTurnIn(quest)   seconds since the accept / hand-in event, or nil
--   State.acceptedAt[quest], State.turnedInAt[quest]       the times themselves
--   State.IsGhost(), State.Corpse() -> zone, x, y or nil   released spirit; where the corpse lies
--   State.InInstance(), State.InRaid()
--   State.lastCast = { spell, time }  the player's last successful cast
--   State.merchant, State.trainer = { npc, opened, closed }   the last merchant / trainer window (npc nil when the
--                                     client gives no readable NPC ID; closed nil while it is open)
--   State.taxiPick = { from, to, time }   the flight last picked on the flight map (nodes nil when not known)
--   State.controlLost, State.flightStart  when control was last lost, and when that happened on a flight
--   State.discoveredAt                when the "new flight path" message last arrived
--   State.boundAt                     when the hearthstone was last bound
--   State.levelAt[level]              when this session saw the character reach that level
--
-- Events fired: NOIR_STATE with "level", "quests", "completed", "flights", "hearth", "professions" or "zone" when
-- that part changed; NOIR_READY once; NOIR_FLIGHT_DISCOVERED with the node ID (or nil when it could not be told).
local Noir = Noir

local State = {
  class = nil, race = nil, faction = nil,
  level = 0, xp = 0, xpMax = 0,
  ready = false,
  quests = {}, logHidden = false,
  completed = {},
  flights = {}, taxiOpen = false, taxiNode = nil, taxiSlots = {}, unknownTaxiNames = {},
  hearth = nil,
  professions = {},
  zone = nil,
  inCombat = false,
  acceptedAt = {}, turnedInAt = {}, levelAt = {},
  lastCast = nil, merchant = {}, trainer = {},
  taxiPick = nil, controlLost = nil, flightStart = nil, discoveredAt = nil, boundAt = nil,
}
Noir.State = State

local function changed(what)
  Noir.Fire("NOIR_STATE", what)
end

-- Reports a missing client API once.
local reported = {}
local function missing(key, text)
  if not reported[key] then
    reported[key] = true
    Noir.Problem(text)
  end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Character
-- ---------------------------------------------------------------------------------------------------------------

-- The client's race ID and race file name to the name the routes use. Both Skyborne races have the file name
-- "Skyborne" in the client's race table and differ by ID and faction.
local RACE_BY_ID = {
  [1] = "Human", [2] = "Orc", [3] = "Dwarf", [4] = "NightElf", [5] = "Undead", [6] = "Tauren", [7] = "Gnome",
  [8] = "Troll", [95] = "HighOrder", [96] = "Windshaper",
}
local RACE_BY_TOKEN = {
  human = "Human", orc = "Orc", dwarf = "Dwarf", nightelf = "NightElf", scourge = "Undead", undead = "Undead",
  tauren = "Tauren", gnome = "Gnome", troll = "Troll", highorder = "HighOrder", windshaper = "Windshaper",
}

local function readCharacter()
  local _, class = UnitClass("player")
  local raceName, raceToken, raceId = UnitRace("player")
  local faction = UnitFactionGroup("player")
  State.class = class
  State.faction = faction
  local race = RACE_BY_ID[raceId]
  if not race and type(raceToken) == "string" then
    local token = string.lower(raceToken)
    race = RACE_BY_TOKEN[token]
    if not race and token == "skyborne" then
      if faction == "Alliance" then race = "HighOrder" elseif faction == "Horde" then race = "Windshaper" end
    end
  end
  State.race = race
  if not race then
    Noir.Problem("Unknown race: " .. tostring(raceName) .. " (" .. tostring(raceToken) .. ", ID " .. tostring(raceId) .. ").")
  end
end

local function readXP()
  State.xp = UnitXP and UnitXP("player") or 0
  State.xpMax = UnitXPMax and UnitXPMax("player") or 0
end

-- `known` is the level an event told us. UnitLevel still returns the old level while PLAYER_LEVEL_UP is being
-- delivered, so the level never goes down here.
local function now()
  return GetTime and GetTime() or 0
end

local function setLevel(known)
  local level = known or UnitLevel("player") or 0
  if type(level) == "number" and level > State.level then
    -- The first reading at login is not "reaching" the level: when that happened is not known.
    if State.level > 0 then
      for l = State.level + 1, level do State.levelAt[l] = now() end
    end
    State.level = level
    readXP()
    changed("level")
  end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Quest log
-- ---------------------------------------------------------------------------------------------------------------

local logSignature = ""
-- Quests handed in a moment ago. The client can still list one until QUEST_REMOVED; it is not "in the log".
local leaving = {}

local function objectivesById(id)
  local list = C_QuestLog and C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(id)
  if type(list) ~= "table" then return nil end
  local out = {}
  for i = 1, #list do
    local o = list[i]
    out[i] = {
      text = o.text or "", kind = o.type or "", done = o.finished and true or false,
      have = o.numFulfilled or 0, need = o.numRequired or 0,
    }
    if out[i].kind == "event" then out[i].have, out[i].need = nil, nil end
  end
  return out
end

-- The old API gives objectives per quest log index, with the counts only inside the text ("Thing slain: 3/8").
local function objectivesByIndex(index)
  if not (GetNumQuestLeaderBoards and GetQuestLogLeaderBoard) then return {} end
  local out = {}
  for i = 1, GetNumQuestLeaderBoards(index) or 0 do
    local text, kind, done = GetQuestLogLeaderBoard(i, index)
    local o = { text = text or "", kind = kind or "", done = done and true or false }
    if o.kind ~= "event" then
      local have, need = string.match(o.text, "(%d+)%s*/%s*(%d+)")
      o.have, o.need = tonumber(have) or 0, tonumber(need) or 0
    end
    out[i] = o
  end
  return out
end

local function isFailed(id)
  return (C_QuestLog and C_QuestLog.IsFailed and C_QuestLog.IsFailed(id)) and true or false
end

-- The client's own "ready to hand in" flag, by quest ID. Returns nil when no API can tell.
local function isCompleteById(id)
  if C_QuestLog and C_QuestLog.IsComplete then return C_QuestLog.IsComplete(id) and true or false end
  if IsQuestComplete then return IsQuestComplete(id) and true or false end
  return nil
end

local function allDone(objectives)
  if #objectives == 0 then return false end
  for i = 1, #objectives do
    if not objectives[i].done then return false end
  end
  return true
end

local function signatureOf(quests)
  local ids = {}
  for id in pairs(quests) do ids[#ids + 1] = id end
  table.sort(ids)
  local parts = {}
  for i = 1, #ids do
    local q = quests[ids[i]]
    local piece = ids[i] .. (q.complete and "c" or "") .. (q.failed and "f" or "")
    for j = 1, #q.objectives do
      local o = q.objectives[j]
      piece = piece .. "," .. (o.done and "d" or "") .. (o.have or "")
    end
    parts[i] = piece
  end
  return table.concat(parts, ";")
end

-- Reads the whole quest log. Quests under a collapsed header are not listed by the client; they are found one
-- by one in State.Quest when asked for.
local function readLog()
  local quests, hidden = {}, false
  if C_QuestLog and C_QuestLog.GetInfo and C_QuestLog.GetNumQuestLogEntries then
    for i = 1, C_QuestLog.GetNumQuestLogEntries() or 0 do
      local info = C_QuestLog.GetInfo(i)
      if info then
        if info.isHeader then
          if info.isCollapsed then hidden = true end
        elseif info.questID and info.questID > 0 and not info.isHidden then
          local id = info.questID
          local failed = isFailed(id)
          local objectives = objectivesById(id) or {}
          local complete = isCompleteById(id)
          if complete == nil then complete = allDone(objectives) end
          quests[id] = {
            id = id, title = info.title, level = info.level or 0,
            complete = complete and not failed, failed = failed, objectives = objectives,
          }
        end
      end
    end
  elseif GetNumQuestLogEntries and GetQuestLogTitle then
    for i = 1, GetNumQuestLogEntries() or 0 do
      local title, level, _, isHeader, isCollapsed, isComplete, _, id = GetQuestLogTitle(i)
      if isHeader then
        if isCollapsed then hidden = true end
      elseif type(id) == "number" and id > 0 then
        local failed = (isComplete == -1) or isFailed(id)
        quests[id] = {
          id = id, title = title, level = level or 0,
          complete = (isComplete == 1 or isComplete == true) and not failed, failed = failed,
          objectives = objectivesById(id) or objectivesByIndex(i),
        }
      elseif title then
        missing("questid", "This client's quest log gives no quest IDs; quest steps cannot be followed.")
      end
    end
  else
    missing("questlog", "This client has no quest log API the addon knows.")
  end
  for id in pairs(leaving) do
    if quests[id] then
      quests[id] = nil
    elseif not hidden then
      leaving[id] = nil -- the client no longer lists it
    end
    -- With part of the log hidden, "not listed" proves nothing: QUEST_REMOVED clears it.
  end
  State.quests, State.logHidden = quests, hidden
  local signature = signatureOf(quests)
  -- With part of the log hidden, progress on the hidden quests cannot be seen here: always tell the listeners.
  if signature ~= logSignature or hidden then
    logSignature = signature
    changed("quests")
  end
end

-- The quest's record, or nil when it is not in the log.
function State.Quest(id)
  if leaving[id] then return nil end
  local q = State.quests[id]
  if q then return q end
  if not (State.ready and State.logHidden) then return nil end
  if not (C_QuestLog and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(id)) then return nil end
  local objectives = objectivesById(id) or {}
  local failed = isFailed(id)
  local complete = isCompleteById(id)
  if complete == nil then complete = allDone(objectives) end
  q = {
    id = id, title = Noir.Data.quests[id], level = 0,
    complete = complete and not failed, failed = failed, objectives = objectives,
  }
  State.quests[id] = q -- until the next reading of the log
  return q
end

function State.HasQuest(id)
  return State.Quest(id) ~= nil
end

-- True when the character has handed this quest in, now or at any time before.
function State.IsDone(id)
  if State.completed[id] then return true end
  local flagged = (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or IsQuestFlaggedCompleted
  if flagged and flagged(id) then
    State.completed[id] = true
    return true
  end
  return false
end

local function readCompleted()
  if GetQuestsCompleted then
    local list = GetQuestsCompleted()
    if type(list) == "table" then
      for id, done in pairs(list) do
        if done then State.completed[id] = true end
      end
    end
  elseif C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
    local list = C_QuestLog.GetAllCompletedQuestIDs()
    if type(list) == "table" then
      for i = 1, #list do State.completed[list[i]] = true end
    end
  end
end

local entered = false -- PLAYER_ENTERING_WORLD has been seen

local function becomeReady()
  if State.ready or not entered then return end
  State.ready = true
  readLog()
  Noir.Fire("NOIR_READY")
end

-- ---------------------------------------------------------------------------------------------------------------
-- Flight points. The client only tells which are known while the flight map is open, so they are kept in the
-- character's saved variables. A flight point is never forgotten.
-- ---------------------------------------------------------------------------------------------------------------

function State.KnowsFlight(node)
  return State.flights[node] == true
end

-- Records a flight point as known. `how` says where the knowledge came from ("map", "discovered", "step").
function State.LearnFlight(node, how)
  if type(node) ~= "number" or State.flights[node] then return false end
  State.flights[node] = true
  changed("flights")
  return true
end

-- Whether a flight point of the data can be the player's: the data says whose it is ("A", "H", "AH"); without that
-- it can be anyone's. Neutral towns have one point per faction under the same name.
local function usable(flight)
  local factions = flight.factions
  if type(factions) ~= "string" or type(State.faction) ~= "string" then return true end
  return string.find(factions, string.sub(State.faction, 1, 1), 1, true) ~= nil
end

local nameToNode = nil -- built on first use, after login; the data files are complete before any event arrives

-- Node ID for a flight map name, from the player's faction's points in Data.flights. Names that two of them share
-- are not matched.
local function nodeByName(name)
  if not nameToNode then
    nameToNode = {}
    for id, flight in pairs(Noir.Data.flights) do
      local key = usable(flight) and type(flight.name) == "string" and string.lower(flight.name)
      if key then
        if nameToNode[key] == nil then nameToNode[key] = id else nameToNode[key] = false end
      end
    end
  end
  return type(name) == "string" and nameToNode[string.lower(name)] or nil
end

-- The last flight map read: picking a destination closes the map (and clears State.taxiSlots) before a hook on
-- TakeTaxiNode runs.
local lastTaxi = { slots = {} }

local function readTaxiMap()
  State.taxiOpen, State.taxiNode, State.taxiSlots = true, nil, {}
  if C_TaxiMap and C_TaxiMap.GetAllTaxiNodes then
    local uiMap = (GetTaxiMapID and GetTaxiMapID()) or (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
    local nodes = C_TaxiMap.GetAllTaxiNodes(uiMap)
    local states = Enum and Enum.FlightPathState
    local current, reachable = states and states.Current or 0, states and states.Reachable or 1
    if type(nodes) == "table" then
      for i = 1, #nodes do
        local node = nodes[i]
        if node.nodeID and (node.state == current or node.state == reachable) then
          State.LearnFlight(node.nodeID, "map")
          State.taxiSlots[node.nodeID] = node.slotIndex or i
          if node.state == current then State.taxiNode = node.nodeID end
        end
      end
    end
  elseif NumTaxiNodes and TaxiNodeName and TaxiNodeGetType then
    for i = 1, NumTaxiNodes() or 0 do
      local kind = TaxiNodeGetType(i)
      if kind == "CURRENT" or kind == "REACHABLE" or kind == "DISTANT" then
        local name = TaxiNodeName(i)
        local node = nodeByName(name)
        if node then
          State.LearnFlight(node, "map")
          State.taxiSlots[node] = i
          if kind == "CURRENT" then State.taxiNode = node end
        elseif type(name) == "string" then
          State.unknownTaxiNames[name] = true
        end
      end
    end
  else
    missing("taxi", "This client has no flight map API the addon knows; flight points cannot be read.")
  end
  lastTaxi = { node = State.taxiNode, slots = State.taxiSlots }
end

-- "New flight path discovered" does not say which. If the nearest unknown node of the player's faction in this zone
-- is close to the player it is taken; otherwise the listeners get nil and the flight map settles it when it opens.
local DISCOVERY_RANGE = 10 -- map percent

local function flightDiscovered()
  local zone, x, y = State.Position()
  local best, bestDistance
  if zone then
    for id, flight in pairs(Noir.Data.flights) do
      if flight.zone == zone and not State.flights[id] and usable(flight) and type(flight.x) == "number" and type(flight.y) == "number" then
        local dx, dy = flight.x - x, flight.y - y
        local distance = math.sqrt(dx * dx + dy * dy)
        if distance <= DISCOVERY_RANGE and (not bestDistance or distance < bestDistance) then
          best, bestDistance = id, distance
        end
      end
    end
  end
  State.discoveredAt = now()
  if best then State.LearnFlight(best, "discovered") end
  Noir.Fire("NOIR_FLIGHT_DISCOVERED", best)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Position
-- ---------------------------------------------------------------------------------------------------------------

local areaByMap = nil -- built on first use

-- Area ID for a uiMap, from Data.zones. When two areas share a map the lowest area ID is used.
local function areaForMap(uiMap)
  if not areaByMap then
    areaByMap = {}
    for area, zone in pairs(Noir.Data.zones) do
      local map = type(zone) == "table" and zone.uiMap
      if map and (not areaByMap[map] or area < areaByMap[map]) then areaByMap[map] = area end
    end
  end
  return areaByMap[uiMap]
end

local function percent(fraction)
  return math.floor(fraction * 10000 + 0.5) / 100
end

local function positionOn(uiMap)
  local position = C_Map.GetPlayerMapPosition(uiMap, "player")
  if not position then return nil end
  local x, y
  if position.GetXY then x, y = position:GetXY() else x, y = position.x, position.y end
  if type(x) ~= "number" or type(y) ~= "number" then return nil end
  return percent(x), percent(y)
end

local CONTINENT = 2 -- Enum.UIMapType.Continent
local MAX_DEPTH = 10

-- Where the player is: the zone's area ID, x and y in percent of that zone's map, and the map's ID.
-- Inside a cave or building with its own map, the position is given on the zone's map around it.
-- When no map up the tree is a zone the data knows, zone is nil and x, y are on the client's best map.
-- Returns nil where the client gives no position (instances).
function State.Position()
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then
    missing("map", "This client has no C_Map API; the addon cannot tell where the character is.")
    return nil
  end
  local best = C_Map.GetBestMapForUnit("player")
  if not best then return nil end
  local uiMap, depth = best, 0
  while uiMap and uiMap > 0 and depth < MAX_DEPTH do
    local area = areaForMap(uiMap)
    if area then
      local x, y = positionOn(uiMap)
      if x then return area, x, y, uiMap end
    end
    local info = C_Map.GetMapInfo and C_Map.GetMapInfo(uiMap)
    uiMap, depth = info and info.parentMapID, depth + 1
  end
  local x, y = positionOn(best)
  if not x then return nil end
  return nil, x, y, best
end

-- The uiMap of the continent the player is on, or nil.
function State.Continent()
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo) then return nil end
  local continentType = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or CONTINENT
  local uiMap, depth = C_Map.GetBestMapForUnit("player"), 0
  while uiMap and uiMap > 0 and depth < MAX_DEPTH do
    local info = C_Map.GetMapInfo(uiMap)
    if not info then return nil end
    if info.mapType == continentType then return uiMap end
    uiMap, depth = info.parentMapID, depth + 1
  end
  return nil
end

-- ---------------------------------------------------------------------------------------------------------------
-- Hearthstone
-- ---------------------------------------------------------------------------------------------------------------

-- `atInn` is true when the client just told us the bind changed: the player is standing at the innkeeper, so
-- the current position is the bind's position. Otherwise only the name is known.
local function readHearth(atInn)
  local name = GetBindLocation and GetBindLocation()
  if type(name) ~= "string" or name == "" or not Noir.char then return end
  local old = State.hearth
  if not atInn and old and old.name == name then return end
  local hearth = { name = name }
  if atInn then
    local zone, x, y = State.Position()
    if zone then hearth.zone, hearth.x, hearth.y = zone, x, y end
  end
  State.hearth = hearth
  Noir.char.hearth = hearth
  changed("hearth")
end

-- ---------------------------------------------------------------------------------------------------------------
-- Professions, by skill line ID
-- ---------------------------------------------------------------------------------------------------------------

-- Skill lines of the professions (the client's SkillLine table).
local SKILL_LINES = { 129, 164, 165, 171, 182, 185, 186, 197, 202, 333, 356, 393 }
local professionSignature = ""

local function readProfessions()
  local found = {}
  if GetProfessions and GetProfessionInfo then
    local a, b, c, d, e, f = GetProfessions()
    local slots = { a or false, b or false, c or false, d or false, e or false, f or false }
    for i = 1, 6 do
      if slots[i] then
        local name, _, rank, max, _, _, skillLine = GetProfessionInfo(slots[i])
        if type(skillLine) == "number" then
          found[skillLine] = { name = name, rank = rank or 0, max = max or 0 }
        end
      end
    end
  elseif C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
    for i = 1, #SKILL_LINES do
      local info = C_TradeSkillUI.GetProfessionInfoBySkillLineID(SKILL_LINES[i])
      if type(info) == "table" and (info.skillLevel or 0) > 0 then
        found[SKILL_LINES[i]] = { name = info.professionName, rank = info.skillLevel, max = info.maxSkillLevel or 0 }
      end
    end
  else
    missing("professions", "This client has no profession API by skill line ID; the profession plan cannot follow your skills.")
  end
  local lines = {}
  for skillLine in pairs(found) do lines[#lines + 1] = skillLine end
  table.sort(lines)
  local parts = {}
  for i = 1, #lines do
    local p = found[lines[i]]
    parts[i] = lines[i] .. ":" .. p.rank .. "/" .. p.max
  end
  local signature = table.concat(parts, ";")
  State.professions = found
  if signature ~= professionSignature then
    professionSignature = signature
    changed("professions")
  end
end

-- Rank and maximum of a profession, 0 and 0 when the character does not have it.
function State.Profession(skillLine)
  local p = State.professions[skillLine]
  if not p then return 0, 0 end
  return p.rank, p.max
end

-- ---------------------------------------------------------------------------------------------------------------
-- Zone, combat, taxi
-- ---------------------------------------------------------------------------------------------------------------

local function readZone()
  local zone = State.Position()
  if zone ~= State.zone then
    State.zone = zone
    changed("zone")
  end
  readHearth(false)
end

function State.OnTaxi()
  return (UnitOnTaxi and UnitOnTaxi("player")) and true or false
end

-- ---------------------------------------------------------------------------------------------------------------
-- Bags, spells, death, groups, windows: the facts the lines of a step read
-- ---------------------------------------------------------------------------------------------------------------

function State.ItemCount(id)
  local count = GetItemCount or (C_Item and C_Item.GetItemCount)
  if not count then
    missing("items", "This client has no GetItemCount; collect lines cannot count your bags.")
    return 0
  end
  return tonumber(count(id)) or 0
end

function State.KnowsSpell(id)
  if IsSpellKnown and IsSpellKnown(id) then return true end
  if IsPlayerSpell and IsPlayerSpell(id) then return true end
  return false
end

local function since(at)
  if not at then return nil end
  return now() - at
end

function State.RecentAccept(quest)
  return since(State.acceptedAt[quest])
end

function State.RecentTurnIn(quest)
  return since(State.turnedInAt[quest])
end

function State.IsGhost()
  return (UnitIsGhost and UnitIsGhost("player")) and true or false
end

-- Where the corpse lies: the map of the zone the player is in first, then every zone map the data knows.
function State.Corpse()
  if not (C_DeathInfo and C_DeathInfo.GetCorpseMapPosition) then return nil end
  if UnitIsDeadOrGhost and not UnitIsDeadOrGhost("player") then return nil end
  local function on(area, uiMap)
    local position = uiMap and C_DeathInfo.GetCorpseMapPosition(uiMap)
    if not position then return nil end
    local x, y
    if position.GetXY then x, y = position:GetXY() else x, y = position.x, position.y end
    if type(x) ~= "number" or type(y) ~= "number" or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    if x == 0 and y == 0 then return nil end
    return area, percent(x), percent(y)
  end
  local zone, _, _, uiMap = State.Position()
  if zone then
    local a, x, y = on(zone, uiMap)
    if a then return a, x, y end
  end
  local areas = {}
  for area in pairs(Noir.Data.zones) do areas[#areas + 1] = area end
  table.sort(areas)
  for i = 1, #areas do
    local z = Noir.Data.zones[areas[i]]
    if areas[i] ~= zone and type(z) == "table" then
      local a, x, y = on(areas[i], z.uiMap)
      if a then return a, x, y end
    end
  end
  return nil
end

function State.InInstance()
  return (IsInInstance and IsInInstance()) and true or false
end

function State.InRaid()
  return (IsInRaid and IsInRaid()) and true or false
end

-- The NPC ID inside the GUID of the unit the player talks to; nil for the old hexadecimal GUIDs.
local function npcId()
  local guid = UnitGUID and UnitGUID("npc")
  if type(guid) ~= "string" then return nil end
  local id = string.match(guid, "^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
  return tonumber(id)
end

local function windowOpened(key)
  State[key] = { npc = npcId(), opened = now() }
end

local function windowClosed(key)
  local w = State[key]
  if w.opened and not w.closed then w.closed = now() end
end

-- Picking a destination on the flight map: the node from the slot of the last map read.
local function picked(slot)
  local to
  for node, s in pairs(lastTaxi.slots) do
    if s == slot then to = node end
  end
  State.taxiPick = { from = lastTaxi.node, to = to, time = now() }
end
if hooksecurefunc and TakeTaxiNode then hooksecurefunc("TakeTaxiNode", picked) end

-- ---------------------------------------------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------------------------------------------

local READY_FALLBACK_SECONDS = 5

Noir.On("NOIR_INIT", function()
  State.flights = Noir.Table(Noir.char, "flights")
  if type(Noir.char.hearth) == "table" and type(Noir.char.hearth.name) == "string" then
    State.hearth = Noir.char.hearth
  else
    Noir.char.hearth = nil
  end
end)

Noir.On("NOIR_LOGIN", function()
  readCharacter()
  setLevel()
  readXP()
  readCompleted()
  State.inCombat = (InCombatLockdown and InCombatLockdown()) and true or false
end)

Noir.On("PLAYER_ENTERING_WORLD", function()
  entered = true
  setLevel()
  readZone()
  readProfessions()
  -- The quest log is empty to the API until the server has sent it; QUEST_LOG_UPDATE says when. If that event
  -- does not come, read the log anyway after a moment.
  if not State.ready then Noir.After(READY_FALLBACK_SECONDS, becomeReady) end
end)

Noir.On("PLAYER_LEVEL_UP", function(_, level)
  setLevel(tonumber(level))
end)
Noir.On("PLAYER_XP_UPDATE", function()
  readXP()
  setLevel()
end)

local function questLogChanged()
  if State.ready then readLog() else becomeReady() end
end
Noir.On("QUEST_LOG_UPDATE", questLogChanged)
Noir.On("UNIT_QUEST_LOG_CHANGED", function(_, unit)
  if unit == "player" and State.ready then readLog() end
end)
Noir.On("QUEST_ACCEPTED", function(_, a, b)
  local id = b or a -- (quest log index, quest ID) on older clients, (quest ID) on newer ones
  if type(id) == "number" then
    leaving[id] = nil -- a repeatable quest taken again
    State.acceptedAt[id] = now()
  end
  if State.ready then readLog() end
end)
Noir.On("QUEST_REMOVED", function(_, id)
  if type(id) == "number" then leaving[id] = nil end
  if State.ready then readLog() end
end)
Noir.On("QUEST_TURNED_IN", function(_, id)
  if type(id) == "number" then
    leaving[id] = true
    State.turnedInAt[id] = now()
    if not State.completed[id] then
      State.completed[id] = true
      changed("completed")
    end
  end
  if State.ready then readLog() end
end)

Noir.On("TAXIMAP_OPENED", readTaxiMap)
Noir.On("TAXIMAP_CLOSED", function()
  State.taxiOpen, State.taxiNode, State.taxiSlots = false, nil, {}
end)
Noir.On("UI_INFO_MESSAGE", function(_, a, b)
  local text = ERR_NEWTAXIPATH
  if text and (a == text or b == text) then flightDiscovered() end
end)

Noir.On("HEARTHSTONE_BOUND", function()
  State.boundAt = now()
  readHearth(true)
end)

Noir.On("MERCHANT_SHOW", function() windowOpened("merchant") end)
Noir.On("MERCHANT_CLOSED", function() windowClosed("merchant") end)
Noir.On("TRAINER_SHOW", function() windowOpened("trainer") end)
Noir.On("TRAINER_CLOSED", function() windowClosed("trainer") end)

-- (unit, cast GUID, spell ID) on current clients; the spell ID is the fifth value on older ones.
Noir.On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, a, b, c, d)
  if unit ~= "player" then return end
  local spell = b
  if type(spell) ~= "number" then spell = d end
  if type(spell) ~= "number" then spell = tonumber(b) or tonumber(d) end
  if spell then State.lastCast = { spell = spell, time = now() } end
end)

Noir.On("PLAYER_CONTROL_LOST", function()
  State.controlLost = now()
  if State.OnTaxi() then State.flightStart = State.controlLost end
end)

Noir.On("ZONE_CHANGED_NEW_AREA", readZone)
Noir.On("ZONE_CHANGED", readZone)
Noir.On("ZONE_CHANGED_INDOORS", readZone)

Noir.On("SKILL_LINES_CHANGED", readProfessions)
Noir.On("CHAT_MSG_SKILL", readProfessions)

Noir.On("PLAYER_REGEN_DISABLED", function()
  State.inCombat = true
end)
Noir.On("PLAYER_REGEN_ENABLED", function()
  State.inCombat = false
end)

-- ---------------------------------------------------------------------------------------------------------------
-- /noir state
-- ---------------------------------------------------------------------------------------------------------------

local function countKeys(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

Noir.Command("state", "what the addon knows about your character", function()
  Noir.Print(string.format("%s %s (%s), level %d", tostring(State.race), tostring(State.class), tostring(State.faction), State.level))
  local routes = Noir.Routes
  if routes and type(routes.Describe) == "function" then Noir.Print("  " .. routes.Describe()) end
  local zone, x, y, uiMap = State.Position()
  if x then
    Noir.Print(string.format("  at %.1f, %.1f in zone %s (map %s)", x, y, tostring(zone), tostring(uiMap)))
  else
    Noir.Print("  position unknown here")
  end
  Noir.Print(string.format("  quests in log: %d%s, done: %d", countKeys(State.quests), State.logHidden and " (part of the log is collapsed)" or "", countKeys(State.completed)))
  Noir.Print(string.format("  flight points known: %d", countKeys(State.flights)))
  Noir.Print("  hearthstone: " .. (State.hearth and State.hearth.name or "unknown"))
  for skillLine, p in pairs(State.professions) do
    Noir.Print(string.format("  profession %d %s: %d/%d", skillLine, tostring(p.name), p.rank, p.max))
  end
end)
