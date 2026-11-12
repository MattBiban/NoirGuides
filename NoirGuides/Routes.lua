-- Noir Guides, GPLv3. See LICENSE.
-- Routes: the route files register here. The format is "Route format 3" in
-- docs/superpowers/plans/2026-11-11-guide-rebuild.md: one file per race, a list of sections, each a list of steps,
-- each a list of lines.
--
--   Noir.Route(id, data) -> boolean     called by each file in Routes/; registers a valid file, never raises
--   Routes.Check(data) -> nil | string  nil for a valid file, else one sentence naming the first three problems
--   Routes.Get(id), Routes.Ids()        registered files (Ids sorted)
--   Routes.ForRace(race, faction)       -> the ID of the file for that race and faction, or nil
--   Routes.rejected[id]                 why a file was refused (also in /noir problems)
--   Routes.Current()                    -> the ID of the file for the player's race once logged in, or nil; which
--                                          section of it is played is Guide.lua's (task E2)
--   Routes.Describe()                   -> one sentence naming the current file, its sections and steps (/noir state
--                                          prints it)
--
-- A file that fails a check is refused whole: showing part of a broken route would hide steps from the player
-- without saying so. On registration each step gets `n` (its position in its section) and each section gets `file`
-- (the route ID); nothing else is added and nothing is changed.
--
-- Routes.Check is word for word the same check as checkRoute3 in tools/planner/format3.js: both are held to the
-- sentences in tools/test-lua/sample/format3-cases.lua. Change both or neither. Problems that name keys list them in
-- sorted order, so a message never depends on the order pairs() walks a table in.
local Noir = Noir
local State = Noir.State

local Routes = { rejected = {} }
Noir.Routes = Routes

local FORMAT = 3
local MAX_STEPS = 400
local MAX_TEXT = 160
local MAX_TITLE = 24
local MAX_LEVEL = 60
local MAX_RADIUS = 500
local MAX_SHOWN = 3

local registered = {} -- id -> route data
local current = nil   -- the ID of the player's race's file

local RACES = {
  Human = "Alliance", Dwarf = "Alliance", Gnome = "Alliance", NightElf = "Alliance", HighOrder = "Alliance",
  Orc = "Horde", Troll = "Horde", Tauren = "Horde", Undead = "Horde", Windshaper = "Horde",
}
local FACTIONS = { Alliance = true, Horde = true }
local CLASSES = {
  WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true, SHAMAN = true, MAGE = true,
  WARLOCK = true, DRUID = true,
}
local GROUPS = { Alliance = true, Horde = true }
local MODES = { "zeppelin", "boat", "tram", "portal" }

-- Field kinds of lines and skip conditions (the same names as format3.js):
--   id     positive whole number           ids    list of positive whole numbers
--   place  a place (R6)                    bool   true or false
--   text   a string of at most 160 bytes   class  a class token
--   whole  whole number from lo to hi      number number from lo to hi
--   mode   one of MODES                    buy    { item = id, count = positive whole number }
-- Each list is in the order the fields are checked; `need` marks a required field.
local function F(name, kind, need, lo, hi)
  return { name = name, kind = kind, need = need == true, lo = lo, hi = hi }
end
local LINES = {
  accept = { F("quest", "id", true), F("npc", "id"), F("object", "id"), F("item", "id"), F("manual", "bool"), F("ifDone", "id"), F("requires", "ids") },
  turnin = { F("quest", "id", true), F("npc", "id"), F("object", "id"), F("reward", "whole", false, 1, 6), F("manual", "bool"), F("skipIfMissing", "bool"), F("skipIfIncomplete", "bool") },
  objective = { F("quest", "id", true), F("index", "id", true), F("cap", "id"), F("skipIfMissing", "bool"), F("npc", "id"), F("object", "id"), F("item", "id") },
  collect = { F("item", "id", true), F("count", "whole", true, 0, 1000), F("quest", "id") },
  ["goto"] = { F("at", "place", true) },
  getflight = { F("node", "id", true), F("npc", "id") },
  fly = { F("from", "id", true), F("to", "id", true) },
  transport = { F("mode", "mode", true), F("at", "place", true), F("to", "place", true) },
  sethearth = { F("npc", "id") },
  hearth = { F("to", "place", true) },
  grind = { F("level", "whole", true, 2, MAX_LEVEL), F("percent", "number", false, 0, 99) },
  train = { F("spell", "id"), F("skill", "id"), F("rank", "whole", false, 1, 4), F("class", "class"), F("level", "whole", false, 2, MAX_LEVEL), F("npc", "id") },
  vendor = { F("npc", "id", true), F("buy", "buy") },
  use = { F("item", "id", true) },
  target = { F("npc", "id", true), F("enemy", "bool") },
  note = { F("text", "text", true) },
  manual = { F("text", "text", true) },
}
local LINE_COMMON = { "kind", "at", "when" }
local QUEST = { F("quest", "id", true) }
local SKIPS = {
  onquest = QUEST, notonquest = QUEST, complete = QUEST, notcomplete = QUEST, turnedin = QUEST, notturnedin = QUEST,
  level = { F("level", "whole", true, 1, MAX_LEVEL), F("percent", "number", false, 0, 99) },
  below = { F("level", "whole", true, 1, MAX_LEVEL) },
  maxlevel = { F("level", "whole", true, 1, MAX_LEVEL) },
  skill = { F("skill", "id", true), F("value", "whole", true, 0, 1000) },
  item = { F("item", "id", true), F("count", "id") },
  zone = { F("zone", "id", true) },
  bound = { F("zone", "id", true) },
}
local SKIP_COMMON = { "kind", "jump" }
local STEP_KEYS = {
  id = true, at = true, text = true, title = true, lines = true, when = true, minLevel = true, maxLevel = true,
  label = true, requires = true, reminder = true, skip = true, load = true, items = true, targets = true, path = true,
}
local CONDITION_KEYS = { class = true, notClass = true, race = true, notRace = true, profession = true }
local NAME_PATTERNS = { "^%d+%-%d+ .+$", "^%d+ .+$" }

-- ---------------------------------------------------------------------------------------------------------------
-- Small checks
-- ---------------------------------------------------------------------------------------------------------------

local function isTable(v) return type(v) == "table" end
local function isWhole(v) return type(v) == "number" and v > -math.huge and v < math.huge and v == math.floor(v) end
local function isId(v) return isWhole(v) and v > 0 end
local function inRange(v, lo, hi) return type(v) == "number" and v >= lo and v <= hi end
local function quoted(s) return "\"" .. s .. "\"" end

-- A list: a table whose keys are exactly 1..n (an empty table is an empty list).
local function isArray(t)
  if type(t) ~= "table" then return false end
  local n = 0
  for k in pairs(t) do
    if not (isWhole(k) and k >= 1) then return false end
    n = n + 1
  end
  for i = 1, n do
    if t[i] == nil then return false end
  end
  return true
end

local function allIds(t)
  if not isArray(t) then return false end
  for i = 1, #t do
    if not isId(t[i]) then return false end
  end
  return true
end

-- The keys as strings, sorted.
local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = tostring(k) end
  table.sort(keys)
  return keys
end

local function isPlace(p)
  if not isTable(p) or not isId(p.zone) then return false end
  if not inRange(p.x, 0, 100) or not inRange(p.y, 0, 100) then return false end
  if p.r ~= nil and not inRange(p.r, 0, MAX_RADIUS) then return false end
  if p.nearest ~= nil and p.nearest ~= true then return false end
  return true
end

local function nameOk(v)
  if type(v) ~= "string" then return false end
  for _, pattern in ipairs(NAME_PATTERNS) do
    if string.find(v, pattern) then return true end
  end
  return false
end

local function sectionLabel(s, i)
  if isTable(s) and type(s.id) == "string" and s.id ~= "" then return "section " .. s.id end
  return "section #" .. i
end

local function stepLabel(st, i)
  if isTable(st) and type(st.id) == "string" and st.id ~= "" then return "step " .. st.id end
  return "step #" .. i
end

-- ---------------------------------------------------------------------------------------------------------------
-- Conditions, lines and skip conditions
-- ---------------------------------------------------------------------------------------------------------------

local function checkCondition(when, where, add)
  if when == nil then return end
  if not isTable(when) then return add(where .. "when must be a table") end
  for _, key in ipairs(sortedKeys(when)) do
    if not CONDITION_KEYS[key] then add(where .. "when has the unknown key " .. quoted(key)) end
  end
  for _, key in ipairs({ "class", "notClass", "race", "notRace" }) do
    local v = when[key]
    if v ~= nil then
      local isClass = key == "class" or key == "notClass"
      local list = isArray(v) and v or { v }
      if isArray(v) and #v == 0 then add(where .. "when." .. key .. " must not be an empty list") end
      for i = 1, #list do
        local x = list[i]
        if type(x) == "string" then
          local known
          if isClass then known = CLASSES[x] else known = RACES[x] end
          if not known then add(where .. "when." .. key .. " " .. quoted(x) .. " is not " .. (isClass and "a class token" or "a race")) end
        else
          add(where .. "when." .. key .. " must be " .. (isClass and "a class token or a list of them" or "a race or a list of them"))
          break
        end
      end
    end
  end
  if when.profession ~= nil and not isId(when.profession) then add(where .. "when.profession must be a positive whole number") end
end

local function isMode(v)
  for _, mode in ipairs(MODES) do
    if v == mode then return true end
  end
  return false
end

local function checkFields(t, spec, common, where, what, add)
  local allowed = {}
  for _, key in ipairs(common) do allowed[key] = true end
  for _, f in ipairs(spec) do allowed[f.name] = true end
  for _, key in ipairs(sortedKeys(t)) do
    if not allowed[key] then add(where .. "has the unknown key " .. quoted(key)) end
  end
  for _, f in ipairs(spec) do
    local v = t[f.name]
    if v == nil then
      if f.need then add(where .. what .. " needs " .. f.name) end
    else
      local field = where .. f.name
      local kind = f.kind
      if kind == "id" then
        if not isId(v) then add(field .. " must be a positive whole number") end
      elseif kind == "ids" then
        if not allIds(v) then add(field .. " must be a list of positive whole numbers") end
      elseif kind == "place" then
        if not isPlace(v) then add(field .. " is not a valid place") end
      elseif kind == "bool" then
        if type(v) ~= "boolean" then add(field .. " must be true or false") end
      elseif kind == "text" then
        if type(v) ~= "string" then
          add(field .. " must be a string")
        elseif #v > MAX_TEXT then
          add(field .. " is longer than " .. MAX_TEXT .. " characters")
        end
      elseif kind == "class" then
        if not (type(v) == "string" and CLASSES[v]) then add(field .. " must be a class token") end
      elseif kind == "whole" then
        if not (isWhole(v) and v >= f.lo and v <= f.hi) then add(field .. " must be a whole number from " .. f.lo .. " to " .. f.hi) end
      elseif kind == "number" then
        if not inRange(v, f.lo, f.hi) then add(field .. " must be a number from " .. f.lo .. " to " .. f.hi) end
      elseif kind == "mode" then
        if not isMode(v) then add(field .. " must be one of " .. table.concat(MODES, ", ")) end
      elseif kind == "buy" then
        if not (isTable(v) and isId(v.item) and isId(v.count)) then add(field .. " must be { item, count } with positive whole numbers") end
      end
    end
  end
end

local function checkLine(line, j, where, add)
  local at = where .. "line " .. j .. " "
  if not isTable(line) then return add(at .. "is not a table") end
  if type(line.kind) ~= "string" then return add(at .. "needs a kind") end
  local spec = LINES[line.kind]
  if not spec then return add(at .. "has the unknown kind " .. quoted(line.kind)) end
  checkFields(line, spec, LINE_COMMON, at, line.kind, add)
  if line.kind == "train" then
    local forms = line.spell ~= nil or (line.skill ~= nil and line.rank ~= nil) or (line.class ~= nil and line.level ~= nil)
    if not forms then add(at .. "train needs spell, skill and rank, or class and level") end
  end
  if line.kind ~= "goto" and line.kind ~= "transport" and line.at ~= nil and not isPlace(line.at) then
    add(at .. "at is not a valid place")
  end
  checkCondition(line.when, at, add)
end

local function checkSkip(entry, k, where, labels, add)
  local at = where .. "skip " .. k .. " "
  if not isTable(entry) then return add(at .. "is not a table") end
  if type(entry.kind) ~= "string" then return add(at .. "needs a kind") end
  local spec = SKIPS[entry.kind]
  if not spec then return add(at .. "has the unknown kind " .. quoted(entry.kind)) end
  checkFields(entry, spec, SKIP_COMMON, at, entry.kind, add)
  if entry.jump ~= nil then
    if type(entry.jump) ~= "string" then
      add(at .. "jump must be a label")
    elseif not labels[entry.jump] then
      add(at .. "jump names the missing label " .. quoted(entry.jump))
    end
  end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Steps and sections
-- ---------------------------------------------------------------------------------------------------------------

local function level(v)
  return isWhole(v) and v >= 1 and v <= MAX_LEVEL
end

local function checkStep(st, k, sectionWhere, stepIds, labels, sectionIds, add)
  local where = sectionWhere .. stepLabel(st, k) .. " "
  if not isTable(st) then return add(where .. "is not a table") end
  -- R5
  if type(st.id) ~= "string" or not string.find(st.id, "^[%w%.%-%+@#:]+$") then
    add(where .. "id must be made of letters, digits and . - + @ # :")
  elseif stepIds[st.id] ~= k then
    add(where .. "id is used twice")
  end
  -- R7
  for _, key in ipairs(sortedKeys(st)) do
    if not STEP_KEYS[key] then add(where .. "has the unknown key " .. quoted(key)) end
  end
  -- R6
  if st.at ~= nil and not isPlace(st.at) then add(where .. "at is not a valid place") end
  -- R8
  if st.text ~= nil then
    if type(st.text) ~= "string" then
      add(where .. "text must be a string")
    elseif #st.text > MAX_TEXT then
      add(where .. "text is longer than " .. MAX_TEXT .. " characters")
    end
  end
  if st.title ~= nil then
    if type(st.title) ~= "string" then
      add(where .. "title must be a string")
    elseif #st.title > MAX_TITLE then
      add(where .. "title is longer than " .. MAX_TITLE .. " characters")
    end
  end
  -- R7
  if not isArray(st.lines) or #st.lines == 0 then
    add(where .. "lines must hold at least one line")
  else
    for j = 1, #st.lines do checkLine(st.lines[j], j, where, add) end
  end
  -- R9
  checkCondition(st.when, where, add)
  if st.minLevel ~= nil and not level(st.minLevel) then add(where .. "minLevel must be a whole number from 1 to " .. MAX_LEVEL) end
  if st.maxLevel ~= nil and not level(st.maxLevel) then add(where .. "maxLevel must be a whole number from 1 to " .. MAX_LEVEL) end
  if level(st.minLevel) and level(st.maxLevel) and st.minLevel > st.maxLevel then add(where .. "minLevel is above maxLevel") end
  -- R10
  if st.label ~= nil then
    if type(st.label) ~= "string" or not string.find(st.label, "^[%w_]+$") then
      add(where .. "label must be made of letters, digits and _")
    elseif labels[st.label] ~= k then
      add(where .. "label is used twice")
    end
  end
  if st.requires ~= nil then
    if type(st.requires) ~= "string" then
      add(where .. "requires must be a label")
    elseif not labels[st.requires] then
      add(where .. "requires names the missing label " .. quoted(st.requires))
    end
  end
  if st.reminder ~= nil then
    local ends = isTable(st.reminder) and st.reminder.ends or nil
    if type(ends) ~= "string" then
      add(where .. "reminder must be { ends = \"next\" or a label }")
    elseif ends ~= "next" then
      if not labels[ends] then
        add(where .. "reminder ends at the missing label " .. quoted(ends))
      elseif labels[ends] <= k then
        add(where .. "reminder ends at " .. quoted(ends) .. ", which is not a later step")
      end
    end
  end
  -- R9
  if st.skip ~= nil then
    if not isArray(st.skip) then
      add(where .. "skip must be a list of skip conditions")
    else
      for j = 1, #st.skip do checkSkip(st.skip[j], j, where, labels, add) end
    end
  end
  -- R10
  if st.load ~= nil then
    if type(st.load) ~= "string" then
      add(where .. "load must be a section id")
    elseif not sectionIds[st.load] then
      add(where .. "load names the missing section " .. quoted(st.load))
    end
  end
  -- R12
  if st.items ~= nil and not allIds(st.items) then add(where .. "items must be a list of positive whole numbers") end
  if st.targets ~= nil then
    if not isTable(st.targets) then
      add(where .. "targets must be { enemy = { ... }, friend = { ... } }")
    else
      for _, key in ipairs(sortedKeys(st.targets)) do
        if key ~= "enemy" and key ~= "friend" then add(where .. "targets has the unknown key " .. quoted(key)) end
      end
      for _, key in ipairs({ "enemy", "friend" }) do
        local v = st.targets[key]
        if v ~= nil and not allIds(v) then add(where .. "targets." .. key .. " must be a list of positive whole numbers") end
      end
    end
  end
  -- R11
  if st.path ~= nil then
    if st.at == nil then add(where .. "path needs at") end
    local p = st.path
    local pointsOk = isTable(p) and isArray(p.points) and #p.points > 0
    if pointsOk then
      for i = 1, #p.points do
        local pt = p.points[i]
        if not (isTable(pt) and inRange(pt.x, 0, 100) and inRange(pt.y, 0, 100)) then pointsOk = false end
      end
    end
    if not pointsOk then add(where .. "path must have points { x, y } from 0 to 100") end
    if isTable(p) and p.loop ~= nil and p.loop ~= true then add(where .. "path loop must be true or left out") end
  end
end

local function checkSection(s, i, sections, ids, cycles, add)
  local where = sectionLabel(s, i) .. " "
  if not isTable(s) then return add(where .. "is not a table") end
  -- R2
  if type(s.id) ~= "string" or not string.find(s.id, "^[a-z0-9%-]+$") then
    add(where .. "id must be made of a-z, 0-9 and -")
  elseif ids[s.id] ~= i then
    add(where .. "id is used twice")
  end
  if s.start ~= nil and s.start ~= true then add(where .. "start must be true or left out") end
  -- R3
  if not nameOk(s.name) then add(where .. "name must look like \"1-6 Zone\" or \"6 Zone\"") end
  if s.names ~= nil then
    if not isTable(s.names) then
      add(where .. "names must be a table of class tokens")
    else
      for _, key in ipairs(sortedKeys(s.names)) do
        if not CLASSES[key] then
          add(where .. "names has the key " .. quoted(key) .. ", which is not a class token")
        elseif not nameOk(s.names[key]) then
          add(where .. "names." .. key .. " must look like \"1-6 Zone\" or \"6 Zone\"")
        end
      end
    end
  end
  if not (type(s.group) == "string" and GROUPS[s.group]) then add(where .. "group must be \"Alliance\" or \"Horde\"") end
  local minOk = level(s.minLevel)
  if not minOk then add(where .. "minLevel must be a whole number from 1 to " .. MAX_LEVEL) end
  local maxOk = s.maxLevel == nil or level(s.maxLevel)
  if not maxOk then add(where .. "maxLevel must be a whole number from 1 to " .. MAX_LEVEL) end
  if minOk and maxOk and s.maxLevel ~= nil and s.minLevel > s.maxLevel then add(where .. "minLevel is above maxLevel") end
  if minOk then
    local band = "1-20"
    if s.minLevel >= 20 then
      local low = math.floor(s.minLevel / 10) * 10
      band = low .. "-" .. (low + 10)
    end
    if s.subgroup ~= band then add(where .. "subgroup must be \"" .. band .. "\"") end
  elseif type(s.subgroup) ~= "string" then
    add(where .. "subgroup must be a level band like \"1-20\"")
  end
  if not isId(s.zone) then add(where .. "zone must be a positive whole number") end
  checkCondition(s.when, where, add)
  if s.loop ~= nil and s.loop ~= true then add(where .. "loop must be true or left out") end
  if s.noAuto ~= nil and not allIds(s.noAuto) then add(where .. "noAuto must be a list of positive whole numbers") end
  -- R4
  if s.next ~= nil and not isArray(s.next) then
    add(where .. "next must be a list")
  elseif s.next ~= nil then
    for k = 1, #s.next do
      local n = s.next[k]
      local at = where .. "next " .. k .. " "
      if not isTable(n) then
        add(at .. "is not a table")
      else
        if type(n.section) ~= "string" then
          add(at .. "needs section")
        elseif not ids[n.section] then
          add(at .. "names the missing section " .. quoted(n.section))
        end
        checkCondition(n.when, at, add)
      end
    end
  end
  if type(s.id) == "string" and ids[s.id] == i and s.loop ~= true and cycles(s.id) then
    add(where .. "next leads back to this section and no section on the way has loop")
  end
  -- R5
  local steps = s.steps
  if not isArray(steps) or #steps < 1 or #steps > MAX_STEPS then
    add(where .. "steps must hold 1 to " .. MAX_STEPS .. " steps")
    if not isArray(steps) then return end
  end
  local stepIds, labels = {}, {}
  for k = 1, #steps do
    local st = steps[k]
    if isTable(st) then
      if type(st.id) == "string" and stepIds[st.id] == nil then stepIds[st.id] = k end
      if type(st.label) == "string" and labels[st.label] == nil then labels[st.label] = k end
    end
  end
  for k = 1, #steps do checkStep(steps[k], k, where, stepIds, labels, ids, add) end
end

local function finish(problems)
  if #problems == 0 then return nil end
  local shown = {}
  for i = 1, math.min(#problems, MAX_SHOWN) do shown[i] = problems[i] end
  local text = table.concat(shown, "; ")
  if #problems > MAX_SHOWN then text = text .. "; and " .. (#problems - MAX_SHOWN) .. " more" end
  return text
end

function Routes.Check(data)
  if type(data) ~= "table" then return "the route data is not a table" end
  if data.format ~= FORMAT then
    local format = data.format
    if format == nil then format = 1 end
    return "it is in format " .. tostring(format) .. " and this version of the addon reads format " .. FORMAT
  end
  local problems = {}
  local function add(text) problems[#problems + 1] = text end

  -- R1
  local race, faction = data.race, data.faction
  local raceOk = type(race) == "string" and RACES[race] ~= nil
  if type(race) ~= "string" then
    add("race must be a race name")
  elseif not raceOk then
    add("unknown race " .. quoted(race))
  end
  if type(faction) ~= "string" then
    add("faction must be \"Alliance\" or \"Horde\"")
  elseif not FACTIONS[faction] then
    add("unknown faction " .. quoted(faction))
  elseif raceOk and RACES[race] ~= faction then
    add("race " .. quoted(race) .. " is not of faction " .. quoted(faction))
  end

  -- R2
  local sections = data.sections
  if not isArray(sections) or #sections == 0 then
    add("sections must be a list of at least one section")
    return finish(problems)
  end
  local ids, starts = {}, 0 -- id -> index of the first section with it
  for i = 1, #sections do
    local s = sections[i]
    if isTable(s) then
      if type(s.id) == "string" and ids[s.id] == nil then ids[s.id] = i end
      if s.start == true then starts = starts + 1 end
    end
  end
  if starts ~= 1 then add("it has " .. starts .. " start sections; exactly one must have start = true") end

  -- R4: the sections next leads to, from the first section of each id; loop sections break a cycle
  local edges = {}
  for id, i in pairs(ids) do
    local out, links = {}, sections[i].next
    if isArray(links) then
      for k = 1, #links do
        local n = links[k]
        if isTable(n) and type(n.section) == "string" and ids[n.section] then out[#out + 1] = n.section end
      end
    end
    edges[id] = out
  end
  local function cycles(from)
    local seen, stack = {}, {}
    for _, id in ipairs(edges[from]) do stack[#stack + 1] = id end
    while #stack > 0 do
      local id = table.remove(stack)
      if id == from then return true end
      if not seen[id] then
        seen[id] = true
        if sections[ids[id]].loop ~= true then
          for _, to in ipairs(edges[id]) do stack[#stack + 1] = to end
        end
      end
    end
    return false
  end

  for i = 1, #sections do checkSection(sections[i], i, sections, ids, cycles, add) end
  return finish(problems)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------------------------------------------

local function reject(id, why)
  local name = type(id) == "string" and id ~= "" and id or "(no id)"
  if type(id) == "string" and not registered[id] then Routes.rejected[id] = why end
  Noir.Problem("Route " .. name .. " was not loaded: " .. why .. ".")
end

local function sortedIds()
  local ids = {}
  for id in pairs(registered) do ids[#ids + 1] = id end
  table.sort(ids)
  return ids
end

-- Registers a route file. Never raises: a file with a mistake must not stop the files after it.
function Noir.Route(id, data)
  if type(id) ~= "string" or id == "" then
    reject(id, "it has no id")
    return false
  end
  if registered[id] then
    reject(id, "the id is registered twice; the first one is kept")
    return false
  end
  local good, wrong = pcall(Routes.Check, data)
  if not good then wrong = "the check itself failed (" .. tostring(wrong) .. ")" end
  if wrong then
    reject(id, wrong)
    return false
  end
  for _, otherId in ipairs(sortedIds()) do
    local other = registered[otherId]
    if other.race == data.race and other.faction == data.faction then
      Noir.Problem("Routes " .. otherId .. " and " .. id .. " are both for " .. data.faction .. " " .. data.race .. "; the first by name is used.")
    end
  end
  for _, section in ipairs(data.sections) do
    section.file = id
    for n, step in ipairs(section.steps) do step.n = n end
  end
  registered[id] = data
  Routes.rejected[id] = nil
  return true
end

function Routes.Get(id)
  return registered[id]
end

function Routes.Ids()
  return sortedIds()
end

function Routes.ForRace(race, faction)
  local ids = sortedIds()
  for i = 1, #ids do
    local route = registered[ids[i]]
    if route.race == race and route.faction == faction then return ids[i] end
  end
  return nil
end

function Routes.Current()
  return current
end

Noir.On("NOIR_LOGIN", function()
  current = Routes.ForRace(State.race, State.faction)
  if not current then
    Noir.Problem("There is no route for " .. tostring(State.faction) .. " " .. tostring(State.race) .. ".")
  end
end)

function Routes.Describe()
  local id = current
  if not id then return "No route. Type /noir problems to see why." end
  local route = registered[id]
  local steps = 0
  for _, section in ipairs(route.sections) do steps = steps + #section.steps end
  return "Route " .. id .. " (" .. route.faction .. " " .. route.race .. "): " .. #route.sections .. " sections, " .. steps .. " steps."
end
