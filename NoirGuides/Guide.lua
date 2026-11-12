-- Noir Guides, GPLv3. See LICENSE.
-- Guide (spec 2.1 to 2.6): which section of which route file the character plays, chosen by itself at login, the
-- next section at a section's end, and the saved state per character. No command is needed for any of it.
--
--   Guide.When(cond) -> boolean          the one evaluator of `when` tables (Lines.Applies is this function)
--   Guide.Section(id) -> section or nil  by ID, padded ("undead-01-03-...") or not ("undead-1-3-...")
--   Guide.Current() -> id or nil         the section being played (NoirGuidesCharDB.guide.section)
--   Guide.Steps(id) -> steps             the section's steps whose `when` holds for this character (each keeps n)
--   Guide.Applies(section) -> boolean    the file's race and faction are the character's and the section's `when`
--                                        holds
--   Guide.Offered(section) -> boolean    Applies, and not above maxLevel while the option "outlevel" is on
--   Guide.IsDefault(section) -> boolean  on the character's chain: the race file's start section and the sections
--                                        reached from it through `next`
--   Guide.Name(section) -> string        names[class] or name
--   Guide.List(all) -> { { group, subgroups = { { name, sections = { section, ... } } } } }
--                                        offered default sections by group (main route first), subgroups and sections
--                                        in level order; all = true (default: the option "otherSections") adds the
--                                        other sections, other races' files included, under OTHER_GROUP
--   Guide.Recommend() -> id              (1) the section loaded, (2) a section whose name holds the subzone or zone
--                                        name, default ones first, (3) the default section whose range holds the
--                                        level, (4) the race's start section; (2) and (3) only count offered
--                                        sections whose minLevel..maxLevel holds the level
--   Guide.ForLevel(level) -> id          along the chain from the start, the first offered section holding level
--   Guide.Select(id, how) -> boolean     how: "auto", "hand", "wizard", "next", "step"; saves guide.section and
--                                        guide.how and fires NOIR_SECTION (id, how, previous id). Refuses an unknown
--                                        or non-applying section; "hand" may pick any registered section
--   Guide.Next() -> id or nil            spec 2.4: the next section, chosen and selected with how "next"; without
--                                        one fires NOIR_ROUTE_DONE (id) and returns nil
--   Guide.Chain(fromId) -> { ids }       the sections from fromId along `next` for this character, in order
--   Guide.Reset()                        "Reset guide progress for this character" (settings, Profiles): forgets the
--                                        section and every saved place (the wizard and setup answers stay), writes a
--                                        why entry, and chooses again as at a first login
--
-- At NOIR_READY (spec 2.3, 2.5): a saved section that exists and applies is kept, outleveled or not, and loaded
-- again (NOIR_SECTION with the same id as previous). Otherwise, at level 1 the recommendation is selected at once
-- (the setup wizard, task E7, opens by itself and may change it); above level 1 Progress.Locate over the chain
-- decides when it finds evidence, else Recommend (the zone rule, then the level along the chain). A saved section
-- that no longer exists or applies is replaced in the same way with a why entry of kind "section".
-- Recreated character (spec 2.6): at level 1, when the saved owner is not UnitGUID("player") and there is saved
-- guide data, Panel.Confirm asks whether to start fresh; yes clears guide and why, no keeps them; both save the
-- new owner.
local Noir = Noir
local State = Noir.State
local Routes = Noir.Routes

local Guide = {}
Noir.Guide = Guide

Guide.OTHER_GROUP = "Other races and classes"
Guide.RECREATED = "This character's saved guide belongs to an earlier character of the same name. Start fresh?"

local HOW = { auto = true, hand = true, wizard = true, next = true, step = true }
local MAX_LEVEL = 60

-- ---------------------------------------------------------------------------------------------------------------
-- Conditions
-- ---------------------------------------------------------------------------------------------------------------

-- A condition value is one name or a list of names; true when `value` is one of them.
local function matches(want, value)
  if type(want) == "table" then
    for i = 1, #want do
      if want[i] == value then return true end
    end
    return false
  end
  return want == value
end

local function hasProfession(skill)
  local rank = State.Profession and State.Profession(skill) or 0
  if type(rank) == "number" and rank > 0 then return true end
  local professions = Noir.Professions
  -- Learned under one of Forever's tier lines (Professions.Has counts them for their profession), or planned.
  if professions and type(professions.Has) == "function" and professions.Has(skill) then return true end
  if professions and type(professions.IsPlanned) == "function" and professions.IsPlanned(skill) then return true end
  return false
end

function Guide.When(cond)
  if type(cond) ~= "table" then return true end
  if cond.class ~= nil and not matches(cond.class, State.class) then return false end
  if cond.notClass ~= nil and matches(cond.notClass, State.class) then return false end
  if cond.race ~= nil and not matches(cond.race, State.race) then return false end
  if cond.notRace ~= nil and matches(cond.notRace, State.race) then return false end
  if cond.profession ~= nil and not hasProfession(cond.profession) then return false end
  return true
end

-- ---------------------------------------------------------------------------------------------------------------
-- The registry: every section of every registered route file
-- ---------------------------------------------------------------------------------------------------------------

-- An ID with the leading zeros of its numbers dropped, so "undead-01-03-x" and "undead-1-3-x" are the same.
local function loose(id)
  return (string.gsub("-" .. id, "%-0+(%d)", "-%1"))
end

-- The character's own route file first, then the others in ID order.
local function fileIds()
  local all = Routes.Ids()
  local mine = Routes.Current and Routes.Current()
  if not mine then return all end
  local out = { mine }
  for i = 1, #all do
    if all[i] ~= mine then out[#out + 1] = all[i] end
  end
  return out
end

local function forEachSection(fn)
  local files = fileIds()
  for i = 1, #files do
    local route = Routes.Get(files[i])
    if route then
      for j = 1, #route.sections do
        if fn(route.sections[j], route) then return end
      end
    end
  end
end

function Guide.Section(id)
  if type(id) ~= "string" or id == "" then return nil end
  local found
  forEachSection(function(section)
    if section.id == id then
      found = section
      return true
    end
  end)
  if found then return found end
  local want = loose(id)
  forEachSection(function(section)
    if loose(section.id) == want then
      found = section
      return true
    end
  end)
  return found
end

local function routeOf(section)
  return section and Routes.Get(section.file)
end

local function level()
  return type(State.level) == "number" and State.level or 0
end

local function outleveled(section)
  if not Noir.Options or Noir.Options.Get("outlevel") == false then return false end
  return type(section.maxLevel) == "number" and level() > section.maxLevel
end

local function holdsLevel(section, at)
  return at >= (section.minLevel or 1) and at <= (section.maxLevel or MAX_LEVEL)
end

function Guide.Applies(section)
  local route = routeOf(section)
  if not route then return false end
  if route.race ~= State.race or route.faction ~= State.faction then return false end
  return Guide.When(section.when)
end

function Guide.Offered(section)
  return Guide.Applies(section) and not outleveled(section)
end

function Guide.Name(section)
  if type(section) ~= "table" then return nil end
  local names = section.names
  if type(names) == "table" and State.class and type(names[State.class]) == "string" then return names[State.class] end
  return section.name
end

function Guide.Steps(id)
  local section = Guide.Section(id)
  local out = {}
  if not section then return out end
  for i = 1, #section.steps do
    local step = section.steps[i]
    if Guide.When(step.when) then out[#out + 1] = step end
  end
  return out
end

-- ---------------------------------------------------------------------------------------------------------------
-- Chains: walking `next`
-- ---------------------------------------------------------------------------------------------------------------

-- The candidate of a `next` list that spec 2.4 takes: the first that exists and applies (its link's `when` and
-- the section itself), else the last listed that exists.
local function pick(section)
  local list = type(section.next) == "table" and section.next or {}
  local last
  for i = 1, #list do
    local target = Guide.Section(list[i].section)
    if target then
      if Guide.When(list[i].when) and Guide.Applies(target) then return target end
      last = target
    end
  end
  return last
end

local function startSection()
  local route = Routes.Get(Routes.Current and Routes.Current())
  if not route then return nil end
  for i = 1, #route.sections do
    if route.sections[i].start then return route.sections[i] end
  end
  return nil
end

function Guide.Chain(fromId)
  local out, seen = {}, {}
  local section = Guide.Section(fromId)
  while section and not seen[section.id] do
    seen[section.id] = true
    out[#out + 1] = section.id
    section = pick(section)
  end
  return out
end

local function defaultIds()
  local start = startSection()
  local set = {}
  if start then
    local chain = Guide.Chain(start.id)
    for i = 1, #chain do set[chain[i]] = true end
  end
  return set
end

function Guide.IsDefault(section)
  return type(section) == "table" and defaultIds()[section.id] == true
end

-- ---------------------------------------------------------------------------------------------------------------
-- Choosing
-- ---------------------------------------------------------------------------------------------------------------

local function saved()
  if not Noir.char then return nil end
  local guide = Noir.Table(Noir.char, "guide")
  Noir.Table(guide, "places")
  local setup = Noir.Table(guide, "setup")
  if type(setup.groupQuests) ~= "boolean" then setup.groupQuests = false end
  if type(setup.auctionHouse) ~= "boolean" then setup.auctionHouse = true end
  return guide
end

function Guide.Current()
  local guide = Noir.char and Noir.char.guide
  local id = type(guide) == "table" and guide.section or nil
  if type(id) ~= "string" then return nil end
  return id
end

function Guide.ForLevel(at)
  at = at or level()
  local start = startSection()
  if not start then return nil end
  local chain = Guide.Chain(start.id)
  local below
  for i = 1, #chain do
    local section = Guide.Section(chain[i])
    if Guide.Offered(section) and holdsLevel(section, at) then return section.id end
    if (section.minLevel or 1) <= at then below = section.id end
  end
  return below or start.id
end

-- The names of where the character is, most precise first: the subzone, then the zone.
local function placeNames()
  local out = {}
  local function add(name)
    if type(name) == "string" and name ~= "" then
      name = string.lower(name)
      for i = 1, #out do
        if out[i] == name then return end
      end
      out[#out + 1] = name
    end
  end
  if GetSubZoneText then add(GetSubZoneText()) end
  local zone = State.zone and Noir.Data.zones[State.zone]
  if type(zone) == "table" then add(zone.name) end
  if GetRealZoneText then add(GetRealZoneText()) end
  return out
end

local function named(section, place)
  local names = { Guide.Name(section), section.name }
  for i = 1, #names do
    if type(names[i]) == "string" and string.find(string.lower(names[i]), place, 1, true) then return true end
  end
  return false
end

-- Rule (2) of Recommend: the first section, defaults first, whose name holds the most precise place name.
local function byZone()
  local at, defaults = level(), defaultIds()
  local candidates = {}
  forEachSection(function(section)
    if Guide.Offered(section) and holdsLevel(section, at) then candidates[#candidates + 1] = section end
  end)
  local places = placeNames()
  for p = 1, #places do
    local other
    for i = 1, #candidates do
      if named(candidates[i], places[p]) then
        if defaults[candidates[i].id] then return candidates[i].id end
        other = other or candidates[i].id
      end
    end
    if other then return other end
  end
  return nil
end

function Guide.Recommend()
  local current = Guide.Section(Guide.Current())
  if current and Guide.Applies(current) then return current.id end
  local zoned = byZone()
  if zoned then return zoned end
  local start = startSection()
  local chain = start and Guide.Chain(start.id) or {}
  for i = 1, #chain do
    local section = Guide.Section(chain[i])
    if Guide.Offered(section) and holdsLevel(section, level()) then return section.id end
  end
  return start and start.id or nil
end

function Guide.Select(id, how)
  if not HOW[how] then return false end
  local section = Guide.Section(id)
  if not section then return false end
  if how ~= "hand" and not Guide.Applies(section) then return false end
  local guide = saved()
  if not guide then return false end
  local previous = guide.section
  guide.section, guide.how = section.id, how
  Noir.Fire("NOIR_SECTION", section.id, how, previous)
  return true
end

function Guide.Next()
  local current = Guide.Section(Guide.Current())
  if not current then return nil end
  local chosen, seen = pick(current), { [current.id] = true }
  -- A section excluded by "outlevel" hands over to its own next; when that leads nowhere it is taken after all.
  local excluded = nil
  while chosen and outleveled(chosen) and not seen[chosen.id] do
    seen[chosen.id] = true
    excluded = excluded or chosen
    chosen = pick(chosen)
  end
  -- Stopped on a circle of excluded sections: none of them is better than the first.
  if chosen and outleveled(chosen) then chosen = nil end
  chosen = chosen or excluded
  if not chosen then
    Noir.Fire("NOIR_ROUTE_DONE", current.id)
    return nil
  end
  Guide.Select(chosen.id, "next")
  return chosen.id
end

-- ---------------------------------------------------------------------------------------------------------------
-- The picker's list
-- ---------------------------------------------------------------------------------------------------------------

local function bandStart(name)
  return tonumber(string.match(tostring(name), "^(%d+)")) or MAX_LEVEL + 1
end

local function bySectionLevel(a, b)
  if (a.minLevel or 1) ~= (b.minLevel or 1) then return (a.minLevel or 1) < (b.minLevel or 1) end
  if (a.maxLevel or MAX_LEVEL) ~= (b.maxLevel or MAX_LEVEL) then return (a.maxLevel or MAX_LEVEL) < (b.maxLevel or MAX_LEVEL) end
  return a.id < b.id
end

local function bySubgroup(a, b)
  local la, lb = bandStart(a.name), bandStart(b.name)
  if la ~= lb then return la < lb end
  return a.name < b.name
end

-- Sections into { { name, sections } } by subgroup, everything in level order.
local function subgroupsOf(sections)
  local byName, out = {}, {}
  for i = 1, #sections do
    local name = tostring(sections[i].subgroup or "")
    local sub = byName[name]
    if not sub then
      sub = { name = name, sections = {} }
      byName[name] = sub
      out[#out + 1] = sub
    end
    sub.sections[#sub.sections + 1] = sections[i]
  end
  for i = 1, #out do table.sort(out[i].sections, bySectionLevel) end
  table.sort(out, bySubgroup)
  return out
end

-- Order weight of a group: the faction's main route first, other groups after it by name.
local function groupWeight(group)
  if group == State.faction then return 0 end
  return 10
end

function Guide.List(all)
  if all == nil then all = Noir.Options and Noir.Options.Get("otherSections") == true end
  local defaults = defaultIds()
  local groups, order, others = {}, {}, {}
  forEachSection(function(section)
    if Guide.Offered(section) and defaults[section.id] then
      local name = tostring(section.group or "")
      if not groups[name] then
        groups[name] = {}
        order[#order + 1] = name
      end
      local list = groups[name]
      list[#list + 1] = section
    elseif all and not outleveled(section) then
      others[#others + 1] = section
    end
  end)
  table.sort(order, function(a, b)
    if groupWeight(a) ~= groupWeight(b) then return groupWeight(a) < groupWeight(b) end
    return a < b
  end)
  local out = {}
  for i = 1, #order do
    out[#out + 1] = { group = order[i], subgroups = subgroupsOf(groups[order[i]]) }
  end
  if #others > 0 then
    -- One list in level order: the subgroups of other files would only repeat the same bands.
    out[#out + 1] = { group = Guide.OTHER_GROUP, subgroups = subgroupsOf(others) }
  end
  return out
end

-- ---------------------------------------------------------------------------------------------------------------
-- The automatic choice at login
-- ---------------------------------------------------------------------------------------------------------------

local function why(text)
  if Noir.Why and Noir.Why.Add then Noir.Why.Add({ kind = "section", text = text }) end
end

-- Nothing usable saved: the section the character's level, place and quest history point to.
local function chooseFresh()
  if level() > 1 then
    local progress = Noir.Progress
    local start = startSection()
    if start and progress and type(progress.Locate) == "function" then
      local id, _, score = progress.Locate(Guide.Chain(start.id))
      if type(score) == "number" and score > 0 and Guide.Select(id, "auto") then return end
    end
    -- No evidence: the zone rule, else the level along the chain. Recommend's last rule (the race's start section)
    -- would put a character far past level 1 on its starting zone's first quest.
    local id = byZone() or Guide.ForLevel(level())
    if id and Guide.Select(id, "auto") then return end
  end
  local id = Guide.Recommend()
  if id then Guide.Select(id, "auto") end
end

local function choose()
  if not Routes.Current or not Routes.Current() then return end
  local guide = saved()
  if not guide then return end
  local id = guide.section
  if id ~= nil then
    local section = Guide.Section(id)
    if section and Guide.Applies(section) then
      Guide.Select(section.id, HOW[guide.how] and guide.how or "auto")
      return
    end
    guide.section = nil
    if section then
      why("The saved section " .. tostring(id) .. " is not for this character any more; another was chosen.")
    else
      why("The saved section " .. tostring(id) .. " is no longer in the route; another was chosen.")
    end
  end
  chooseFresh()
end

local function wipe(t)
  for k in pairs(t) do t[k] = nil end
end

-- True when the character's saved data holds something worth asking about.
local function hasHistory()
  local guide = Noir.char.guide
  if type(guide) == "table" and (guide.section ~= nil or (type(guide.places) == "table" and next(guide.places) ~= nil)) then
    return true
  end
  return type(Noir.char.why) == "table" and #Noir.char.why > 0
end

-- Spec 2.6, gap #48: a character deleted and made again under the same name finds the old one's saved guide.
local function checkOwner()
  local guid = UnitGUID and UnitGUID("player")
  if type(guid) ~= "string" or guid == "" or Noir.char.owner == guid then return end
  if level() ~= 1 or not hasHistory() then
    Noir.char.owner = guid
    return
  end
  local panel = Noir.Panel
  -- Panel.Confirm comes with the window (task E5). Without it nothing is changed and the question waits.
  if not (panel and type(panel.Confirm) == "function") then return end
  panel.Confirm(Guide.RECREATED, function()
    Noir.char.owner = guid
    Noir.char.guide = {}
    if type(Noir.char.why) == "table" then wipe(Noir.char.why) end
    chooseFresh()
  end, function()
    Noir.char.owner = guid
  end)
end

function Guide.Reset()
  local guide = saved()
  if not guide then return false end
  guide.section, guide.how, guide.places = nil, nil, {}
  why("Guide progress for this character was reset from the settings; the section and the place are found again.")
  chooseFresh()
  return true
end

Noir.On("NOIR_READY", function()
  if not Noir.char then return end
  choose()
  checkOwner()
end)
