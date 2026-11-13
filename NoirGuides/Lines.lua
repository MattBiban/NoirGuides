-- Noir Guides, GPLv3. See LICENSE.
-- Lines (spec 3.2, 3.5, 3.7, 3.8): when each line of a step is done, which skip condition of a step holds, and which
-- places a step shows. It reads the game only through State; Progress (task E4) keeps the latches and the why-log.
--
--   Lines.ACCEPT_GRACE = 2, Lines.TURNIN_GRACE = 5      an accept / hand-in this many seconds before the step became
--                                                       current still counts
--   Lines.FLY_GRACE = 1.5                               control lost this soon after picking a flight counts as flying
--   Lines.FLY_ARRIVE_YARDS = 60                         this near the destination's flight master counts as arrived
--   Lines.RANK_CAP = { 75, 150, 225, 300 }              the skill cap of each profession rank
--   Lines.RANK_GATE = { 0, 50, 125, 200 }               the skill a Forever trainer asks before teaching each rank
--   Lines.SELL_JUNK_FLOOR = 1000                        copper (10 silver): while what the visit's training costs is
--                                                       not known, a selljunk line shows only below this much money
--   Lines.TrainingCost(step) -> copper or nil           what the class training of a visit step (its train line's
--                                                       class and level) cost before, State.TrainingCost
--   selljunk line ("sell your grey items before training", on early trainer visits): hidden while the bags hold no
--       grey item that sells, once the step's train line is done, and while the money covers the known cost of
--       the training (or, the cost unknown, is at least SELL_JUNK_FLOOR); shown, whatever the cost, while a trainer
--       window lists an available service the money does not cover. Done when a merchant window opened (and
--       closed) after the step became current: at any merchant, not only the line's.
--   skill line ("raise the skill to the trainer's gate", reminders before profession trainer steps): done at
--       skill >= value, with the counter { have, need }; hidden while the profession is neither learned nor planned.
--   Lines.Active(line) -> boolean                       use, target, note, and goto without a positive radius are
--                                                       passive (they never block the step and count as done)
--   Lines.Check(line, step, ctx) -> state, evidence, counter
--       state: "done", "todo", "skip" (a skipIf... option, an ifDone accept or a profession gate passed it; evidence
--              says why),
--       "missing" (a turn-in or objective whose quest is neither in the log nor handed in), "hidden" (a collect with
--       count 0, or a line whose `when` does not hold). evidence: a short sentence for done and skip.
--       counter: { have, need } (also as counter.have, counter.need) for objective, collect, grind and skill lines.
--       ctx (kept by Progress): since = GetTime() when the step became current; ticks = { [line index] = true }
--       for ticked lines (a manual line is done only when ticked); bound = the bind location name of this step's
--       inn when Progress knows it.
--   Lines.Applies = Guide.When                          the one evaluator of `when` (sections, steps, lines)
--   Lines.Condition(step [, gatesOnly]) -> nil | reason, jump
--                                                       the first skip condition of the step that holds; with
--                                                       gatesOnly only a "notturnedin" on a quest an accept line of
--                                                       the step requires (the game will not offer that accept)
--   Lines.Places(step, reached [, ctx]) -> { { at, line, nearest } }
--       the step's `at` first (line 0) while any line without its own `at` is not done, then each line's own `at`
--       while that line is not done (passive lines always show theirs), minus the places in `reached` (a set keyed
--       by the place tables); of the places marked nearest only the one closest to the player stays. ctx as for
--       Check; ctx.done = { [line index] = true } marks lines Progress has latched as done.
--   Lines.Yards(place) -> yards from the player, or nil when the client gives no position or no map size
--   Lines.Between(a, b) -> yards between two places, math.huge on two continents, nil when unknown (a zone-only
--                          place, or no map size)
--   Lines.Arrived(place) -> true | false | nil          within place.r yards (in the zone when x = y = 0); false
--                                                       without a positive radius; nil without a position
--   Lines.GrindCounter(line) -> xp, needed or nil       the XP a grind line counts at the current level: at `level`
--                                                       for a percent, at level - 1 for a plain "reach level"
--   Lines.ProfessionName(skillLine) -> name             Data.professions, then the client's, then "skill <id>"
local Noir = Noir
local State = Noir.State

local Lines = {}
Noir.Lines = Lines

Lines.ACCEPT_GRACE = 2
Lines.TURNIN_GRACE = 5
Lines.FLY_GRACE = 1.5
Lines.FLY_ARRIVE_YARDS = 60
Lines.RANK_CAP = { 75, 150, 225, 300 }
Lines.RANK_GATE = { 0, 50, 125, 200 }
Lines.SELL_JUNK_FLOOR = 1000
Lines.Applies = Noir.Guide.When

-- A bind within this many yards of the step's place is at the step's inn.
local INN_YARDS = 40
-- Without a radius, "at" a hearth or transport destination means this near it.
local AT_YARDS = 40
-- The Hearthstone's spell and the shaman's Astral Recall.
local HEARTH_SPELLS = { [8690] = true, [556] = true }

local PASSIVE = { use = true, target = true, note = true }

function Lines.Active(line)
  if type(line) ~= "table" then return false end
  if PASSIVE[line.kind] then return false end
  if line.kind == "goto" then
    local r = line.at and line.at.r
    return type(r) == "number" and r > 0
  end
  return true
end

-- ---------------------------------------------------------------------------------------------------------------
-- Names (for evidence and reasons). UI/Text.lua loads later; it is looked up when called.
-- ---------------------------------------------------------------------------------------------------------------

local function questName(id)
  local text = Noir.Text
  if text and text.QuestName then return text.QuestName(id) end
  return Noir.Data.quests[id] or ("Quest " .. tostring(id))
end

local function itemName(id)
  local text = Noir.Text
  if text and text.ItemName then return text.ItemName(id) end
  return Noir.Data.items[id] or ("Item " .. tostring(id))
end

local function zoneName(id)
  local text = Noir.Text
  if text and text.ZoneName then return text.ZoneName(id) end
  local z = Noir.Data.zones[id]
  return (type(z) == "table" and z.name) or ("Zone " .. tostring(id))
end

-- ---------------------------------------------------------------------------------------------------------------
-- Professions: by skill line, Forever's tier lines counted as their profession
-- ---------------------------------------------------------------------------------------------------------------

local function skillOf(skill)
  local rank, max = State.Profession(skill)
  if (rank or 0) > 0 or (max or 0) > 0 then return rank or 0, max or 0 end
  local tiers = Noir.Data.professionLines
  if type(tiers) == "table" then
    for line, parent in pairs(tiers) do
      if parent == skill then
        local r, m = State.Profession(line)
        if (r or 0) > 0 or (m or 0) > 0 then return r or 0, m or 0 end
      end
    end
  end
  return 0, 0
end

local function professionName(skill)
  local data = Noir.Data.professions
  if type(data) == "table" and type(data[skill]) == "table" and data[skill].name then return data[skill].name end
  local known = State.professions[skill]
  if known and known.name then return known.name end
  return "skill " .. tostring(skill)
end
Lines.ProfessionName = professionName

-- ---------------------------------------------------------------------------------------------------------------
-- Distances
-- ---------------------------------------------------------------------------------------------------------------

local sizes = {} -- uiMap -> { w, h } in yards, or false when the client cannot tell

local function vector(x, y)
  if CreateVector2D then return CreateVector2D(x, y) end
  return { x = x, y = y, GetXY = function(v) return v.x, v.y end }
end

local function xyOf(v)
  if type(v) ~= "table" then return nil end
  if v.GetXY then return v:GetXY() end
  return v.x, v.y
end

-- A map's size in yards: C_Map.GetMapWorldSize, else from the world places of two corners.
local function mapSize(uiMap)
  if not uiMap then return nil end
  local known = sizes[uiMap]
  if known ~= nil then return known and known[1], known and known[2] end
  local w, h
  if C_Map and C_Map.GetMapWorldSize then w, h = C_Map.GetMapWorldSize(uiMap) end
  if not (type(w) == "number" and w > 0) and C_Map and C_Map.GetWorldPosFromMapPos then
    local _, a = C_Map.GetWorldPosFromMapPos(uiMap, vector(0, 0))
    local _, b = C_Map.GetWorldPosFromMapPos(uiMap, vector(1, 1))
    local ax, ay = xyOf(a)
    local bx, by = xyOf(b)
    if ax and bx then w, h = math.abs(ay - by), math.abs(ax - bx) end
  end
  if type(w) == "number" and w > 0 and type(h) == "number" and h > 0 then
    sizes[uiMap] = { w, h }
    return w, h
  end
  sizes[uiMap] = false
  return nil
end

local function mapOf(area)
  local z = Noir.Data.zones[area]
  return type(z) == "table" and z.uiMap or nil
end

local function worldOf(uiMap, x, y)
  if not (uiMap and C_Map and C_Map.GetWorldPosFromMapPos) then return nil end
  local instance, pos = C_Map.GetWorldPosFromMapPos(uiMap, vector(x / 100, y / 100))
  local wx, wy = xyOf(pos)
  if not wx then return nil end
  return instance, wx, wy
end

-- Yards between the player and a point { zone, x, y }; nil when unknown, math.huge on another continent.
local function yardsTo(zone, x, y)
  local pz, px, py, pmap = State.Position()
  if not px then return nil end
  if pz and pz == zone then
    local w, h = mapSize(pmap)
    if not w then return nil end
    local dx, dy = (px - x) / 100 * w, (py - y) / 100 * h
    return math.sqrt(dx * dx + dy * dy)
  end
  local ai, ax, ay = worldOf(mapOf(zone), x, y)
  local bi, bx, by = worldOf(pmap, px, py)
  if not (ai and bi) then return nil end
  if ai ~= bi then return math.huge end
  local dx, dy = ax - bx, ay - by
  return math.sqrt(dx * dx + dy * dy)
end

local function zoneOnly(place)
  return (place.x or 0) == 0 and (place.y or 0) == 0
end

function Lines.Yards(place)
  if type(place) ~= "table" or not place.zone or zoneOnly(place) then return nil end
  return yardsTo(place.zone, place.x, place.y)
end

function Lines.Between(a, b)
  if type(a) ~= "table" or type(b) ~= "table" or not a.zone or not b.zone or zoneOnly(a) or zoneOnly(b) then
    return nil
  end
  if a.zone == b.zone then
    local w, h = mapSize(mapOf(a.zone))
    if not w then return nil end
    local dx, dy = (a.x - b.x) / 100 * w, (a.y - b.y) / 100 * h
    return math.sqrt(dx * dx + dy * dy)
  end
  local ai, ax, ay = worldOf(mapOf(a.zone), a.x, a.y)
  local bi, bx, by = worldOf(mapOf(b.zone), b.x, b.y)
  if not (ai and bi) then return nil end
  if ai ~= bi then return math.huge end
  local dx, dy = ax - bx, ay - by
  return math.sqrt(dx * dx + dy * dy)
end

-- In the place's zone: true, false, or nil when the client gives no position.
local function inZone(zone)
  local pz, px = State.Position()
  if not px then return nil end
  return pz == zone
end

function Lines.Arrived(place)
  if type(place) ~= "table" then return nil end
  if zoneOnly(place) then return inZone(place.zone) end
  local r = place.r
  if not (type(r) == "number" and r > 0) then return false end
  local yards = Lines.Yards(place)
  if yards == nil then
    -- In another zone the place is not reached, whatever the client can measure.
    local here = inZone(place.zone)
    if here == false then return false end
    return nil
  end
  return yards <= r
end

-- At a place for the hearth and transport lines: in its zone when x = y = 0, else within its radius (or AT_YARDS).
local function at(place)
  if type(place) ~= "table" then return false end
  if zoneOnly(place) then return inZone(place.zone) == true end
  local r = (type(place.r) == "number" and place.r > 0) and place.r or AT_YARDS
  local yards = Lines.Yards(place)
  return yards ~= nil and yards <= r
end

-- ---------------------------------------------------------------------------------------------------------------
-- Line states
-- ---------------------------------------------------------------------------------------------------------------

local function counter(have, need)
  return { have, need, have = have, need = need }
end

local function indexOf(step, line)
  local list = step and step.lines
  if type(list) ~= "table" then return nil end
  for i = 1, #list do
    if list[i] == line then return i end
  end
  return nil
end

local function within(t, since, grace)
  return t ~= nil and t >= since - (grace or 0)
end

-- The quest is complete or handed in.
local function finished(quest)
  if State.IsDone(quest) then return true end
  local q = State.Quest(quest)
  return q ~= nil and q.complete == true
end

local check = {}

-- Whether a line before `line` in its step hands `quest` in or accepts it and is still to do ("todo", or "missing":
-- a hand-in waiting on a detour to its quest's accept, which hands the quest in after the detour).
local function handledBefore(step, line, quest, ctx)
  if type(step) ~= "table" or type(step.lines) ~= "table" then return false end
  for k = 1, #step.lines do
    local other = step.lines[k]
    if other == line then return false end
    if (other.kind == "accept" or other.kind == "turnin") and other.quest == quest
    then
      local state = Lines.Check(other, step, ctx)
      if state == "todo" or state == "missing" then return true end
    end
  end
  return false
end

check.accept = function(line, step, ctx)
  local quest = line.quest
  -- ifDone: wanted only once that quest is handed in, so passed at once while it is not (route format 3). The quest is
  -- not taken, so the state is "skip" with its reason, and the why-log keeps it (never skip silently). The one
  -- exception (the same-step rule, approved in X1 review 2 and written into route format 3) is the bundle "hand in A,
  -- accept B (ifDone A)": while an earlier line of the same step still hands A in or accepts it (todo, or missing and
  -- waiting on a detour), B waits for that line instead of passing before A could be handed in. A line that is passed
  -- (skipIfMissing) or a hand-in elsewhere does not hold B back.
  -- A quest that any one of several quests unlocks has one accept line per prerequisite (each with its own ifDone): a
  -- later one is hidden while an earlier accept line of that quest on the step is not passed, so the card shows it once.
  if type(step) == "table" and type(step.lines) == "table" then
    for k = 1, #step.lines do
      local other = step.lines[k]
      if other == line then break end
      if other.kind == "accept" and other.quest == quest then
        local state = Lines.Check(other, step, ctx)
        if state ~= "skip" and state ~= "hidden" then return "hidden" end
      end
    end
  end
  if line.ifDone and not State.IsDone(line.ifDone) and not handledBefore(step, line, line.ifDone, ctx) then
    return "skip", "only wanted once " .. questName(line.ifDone) .. " is handed in"
  end
  if State.HasQuest(quest) then return "done", "in the quest log" end
  if State.IsDone(quest) then return "done", "already handed in" end
  if within(State.acceptedAt[quest], ctx.since, Lines.ACCEPT_GRACE) then return "done", "accepted" end
  return "todo"
end

check.turnin = function(line, _, ctx)
  local quest = line.quest
  if State.IsDone(quest) then return "done", "handed in" end
  if within(State.turnedInAt[quest], ctx.since, Lines.TURNIN_GRACE) then return "done", "handed in" end
  local q = State.Quest(quest)
  if not q then
    if line.skipIfMissing then return "skip", questName(quest) .. " is not in your quest log" end
    return "missing"
  end
  if line.skipIfIncomplete and not q.complete then return "skip", questName(quest) .. " is not ready to hand in" end
  return "todo"
end

check.objective = function(line)
  local quest = line.quest
  local q = State.Quest(quest)
  local o = q and q.objectives[line.index]
  local need
  if q and #q.objectives == 0 then
    need = 1
  elseif o then
    need = o.need
    if type(need) ~= "number" or need <= 0 then need = 1 end
  else
    need = 1
  end
  if type(line.cap) == "number" and line.cap > 0 and line.cap < need then need = line.cap end
  if State.IsDone(quest) then return "done", "handed in", counter(need, need) end
  if not q then
    if line.skipIfMissing then return "skip", questName(quest) .. " is not in your quest log", nil end
    return "missing", nil, counter(0, need)
  end
  if q.complete then return "done", "quest complete", counter(need, need) end
  if not o then return "todo", nil, counter(0, need) end
  local have = o.have
  if type(have) ~= "number" then have = o.done and need or 0 end
  if have > need then have = need end
  if o.done then return "done", "objective finished", counter(need, need) end
  if have >= need then return "done", "count reached", counter(have, need) end
  return "todo", nil, counter(have, need)
end

check.collect = function(line)
  local need = line.count
  if line.quest and finished(line.quest) then return "done", "quest complete", counter(need, need) end
  local have = State.ItemCount(line.item)
  if have >= need then return "done", "in your bags", counter(have, need) end
  return "todo", nil, counter(have, need)
end

check["goto"] = function(line)
  if not Lines.Active(line) then return "done" end
  if Lines.Arrived(line.at) then return "done", "arrived" end
  return "todo"
end

check.getflight = function(line, _, ctx)
  local node = line.node
  if State.KnowsFlight(node) then return "done", "flight point known" end
  local pick = State.taxiPick
  if pick and within(pick.time, ctx.since) and (pick.from == node or pick.to == node) then
    return "done", "flown from or to it"
  end
  if within(State.discoveredAt, ctx.since) then return "done", "new flight path discovered" end
  return "todo"
end

check.fly = function(line, _, ctx)
  local pick = State.taxiPick
  local wrong = pick and pick.to and pick.to ~= line.to
  if not wrong then
    if State.OnTaxi() and within(State.flightStart, ctx.since) then return "done", "on the flight" end
    if pick and within(pick.time, ctx.since) and State.controlLost
      and State.controlLost >= pick.time and State.controlLost - pick.time <= Lines.FLY_GRACE then
      return "done", "taking off"
    end
  end
  local f = Noir.Data.flights[line.to]
  if type(f) == "table" and f.zone and f.x and f.y then
    local yards = yardsTo(f.zone, f.x, f.y)
    if yards and yards <= Lines.FLY_ARRIVE_YARDS then return "done", "at the destination" end
  end
  return "todo"
end

check.transport = function(line)
  local to = line.to
  local here = inZone(to.zone)
  if not here then return "todo" end
  local from = line.at
  if from and from.zone == to.zone and not zoneOnly(to) then
    if at(to) then return "done", "arrived" end
    return "todo"
  end
  return "done", "arrived"
end

check.sethearth = function(line, step, ctx)
  local place = line.at or (step and step.at)
  local hearth = State.hearth
  local function atInn()
    if not (hearth and hearth.zone) then return nil end
    if not (place and place.zone) then return true end
    if hearth.zone ~= place.zone then return false end
    if zoneOnly(place) or not hearth.x then return true end
    local w, h = mapSize(mapOf(place.zone))
    if not w then return true end
    local dx, dy = (hearth.x - place.x) / 100 * w, (hearth.y - place.y) / 100 * h
    return math.sqrt(dx * dx + dy * dy) <= INN_YARDS
  end
  local inn = atInn()
  if within(State.boundAt, ctx.since) and inn ~= false then return "done", "hearthstone bound here" end
  if inn then return "done", "hearthstone already bound here" end
  if ctx.bound and hearth and hearth.name == ctx.bound then return "done", "hearthstone already bound here" end
  return "todo"
end

check.hearth = function(line, _, ctx)
  local cast = State.lastCast
  if cast and HEARTH_SPELLS[cast.spell] and within(cast.time, ctx.since) then return "done", "hearthed" end
  if at(line.to) then return "done", "arrived" end
  return "todo"
end

-- The XP a grind line waits for at the character's level: { have, need }, or nil when the level does not count.
local function grindCounter(line)
  local level, xp, max = State.level, State.xp or 0, State.xpMax or 0
  local percent = line.percent
  if percent and percent > 0 then
    if level == line.level and max > 0 then return xp, math.ceil(max * percent / 100) end
  elseif level == line.level - 1 and max > 0 then
    return xp, max
  end
  return nil
end
Lines.GrindCounter = grindCounter

-- The level or percent into it is reached.
local function reached(level, percent)
  if State.level > level then return true end
  if State.level < level then return false end
  if not percent or percent <= 0 then return true end
  local max = State.xpMax or 0
  return max > 0 and (State.xp or 0) * 100 >= percent * max
end

check.grind = function(line)
  local have, need = grindCounter(line)
  local c = have and counter(have, need) or nil
  if reached(line.level, line.percent) then
    if c then c[1], c.have = c[2], c[2] end
    return "done", "level reached", c
  end
  return "todo", nil, c
end

check.train = function(line, _, ctx)
  if line.spell then
    if State.KnowsSpell(line.spell) then return "done", "spell known" end
    return "todo"
  end
  if line.skill and line.rank then
    local skill, max = skillOf(line.skill)
    if max >= (Lines.RANK_CAP[line.rank] or math.huge) then return "done", "rank trained" end
    local gate = Lines.RANK_GATE[line.rank] or 0
    if skill < gate then
      return "skip", "your " .. professionName(line.skill) .. " skill is below " .. gate
    end
    return "todo"
  end
  if line.class and line.level then
    if State.level < line.level then return "todo" end
    local t = State.trainer
    local from = State.levelAt[line.level] or ctx.since
    if t.opened and t.closed and t.opened >= from and (not line.npc or not t.npc or t.npc == line.npc) then
      return "done", "trainer visited"
    end
    return "todo"
  end
  return "todo"
end

-- The step's class train line, if any.
local function classTrain(step)
  local list = type(step) == "table" and step.lines or {}
  for i = 1, #list do
    local l = list[i]
    if l.kind == "train" and l.class and l.level then return l end
  end
  return nil
end

function Lines.TrainingCost(step)
  local train = classTrain(step)
  if not train then return nil end
  return State.TrainingCost(train.class, train.level)
end

check.selljunk = function(line, step, ctx)
  local train = classTrain(step)
  if train and Lines.Check(train, step, ctx) == "done" then return "hidden" end
  local m = State.merchant
  if m.opened and within(m.opened, ctx.since) then
    if m.closed then return "done", "sold at a vendor" end
    local _, stacks = State.Junk()
    if stacks == 0 then return "done", "grey items sold" end
    return "todo"
  end
  local _, stacks = State.Junk()
  if stacks == 0 then return "hidden" end
  if State.TrainerShort() then return "todo" end
  local cost = Lines.TrainingCost(step)
  local money = State.money or 0
  if cost then
    if money >= cost then return "hidden" end
  elseif money >= Lines.SELL_JUNK_FLOOR then
    return "hidden"
  end
  return "todo"
end

check.skill = function(line)
  local professions = Noir.Professions
  local learned = professions and professions.Has and professions.Has(line.skill)
  local planned = professions and professions.IsPlanned and professions.IsPlanned(line.skill)
  if not (learned or planned) then return "hidden" end
  local have = skillOf(line.skill)
  local need = line.value or 0
  if have >= need then return "done", "skill reached", counter(need, need) end
  return "todo", nil, counter(have, need)
end

check.vendor = function(line, _, ctx)
  local m = State.merchant
  if m.opened and m.closed and within(m.opened, ctx.since) and (not line.npc or not m.npc or m.npc == line.npc) then
    return "done", "vendor visited"
  end
  return "todo"
end

check.manual = function(line, step, ctx)
  local ticks = ctx.ticks
  if type(ticks) == "table" and (ticks[indexOf(step, line) or 0] or ticks[line]) then return "done", "ticked" end
  return "todo"
end

function Lines.Check(line, step, ctx)
  ctx = ctx or {}
  if type(ctx.since) ~= "number" then
    local copy = {}
    for k, v in pairs(ctx) do copy[k] = v end
    copy.since = 0
    ctx = copy
  end
  if type(line) ~= "table" then return "hidden" end
  if line.when ~= nil and not Lines.Applies(line.when) then return "hidden" end
  if line.kind == "collect" and line.count == 0 then return "hidden" end
  if not Lines.Active(line) then return "done" end
  local fn = check[line.kind]
  if not fn then return "hidden" end
  return fn(line, step, ctx)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Skip conditions (on steps)
-- ---------------------------------------------------------------------------------------------------------------

local condition = {
  onquest = function(e) if State.HasQuest(e.quest) then return "you are on " .. questName(e.quest) end end,
  notonquest = function(e) if not State.HasQuest(e.quest) then return "you are not on " .. questName(e.quest) end end,
  complete = function(e) if finished(e.quest) then return questName(e.quest) .. " is complete" end end,
  notcomplete = function(e) if not finished(e.quest) then return questName(e.quest) .. " is not complete" end end,
  turnedin = function(e) if State.IsDone(e.quest) then return "you have handed in " .. questName(e.quest) end end,
  notturnedin = function(e)
    if not State.IsDone(e.quest) then return "you have not handed in " .. questName(e.quest) end
  end,
  level = function(e)
    if not reached(e.level, e.percent) then return nil end
    if e.percent and e.percent > 0 and State.level == e.level then
      return "you are " .. e.percent .. "% into level " .. e.level
    end
    return "you have reached level " .. e.level
  end,
  below = function(e) if State.level < e.level then return "you have not reached level " .. e.level end end,
  maxlevel = function(e) if State.level > e.level then return "you are above level " .. e.level end end,
  skill = function(e)
    local skill = skillOf(e.skill)
    if skill >= e.value then return "your " .. professionName(e.skill) .. " skill is at least " .. e.value end
  end,
  item = function(e)
    if State.ItemCount(e.item) >= e.count then return "you have " .. e.count .. " " .. itemName(e.item) end
  end,
  zone = function(e) if State.zone == e.zone then return "you are in " .. zoneName(e.zone) end end,
  bound = function(e)
    local hearth = State.hearth
    if not hearth then return nil end
    local name = zoneName(e.zone)
    if hearth.zone == e.zone or (not hearth.zone and hearth.name == name) then
      return "your hearthstone is set in " .. name
    end
  end,
}

-- Whether `quest` is a prerequisite (`requires`) of an accept line of the step: then "notturnedin" on it means the
-- game will not offer that accept, not a step the player may want to do anyway.
local function gates(step, quest)
  for i = 1, #step.lines do
    local line = step.lines[i]
    if line.kind == "accept" and type(line.requires) == "table" then
      for r = 1, #line.requires do
        if line.requires[r] == quest then return true end
      end
    end
  end
  return false
end

function Lines.Condition(step, gatesOnly)
  local list = type(step) == "table" and step.skip
  if type(list) ~= "table" then return nil end
  for i = 1, #list do
    local entry = list[i]
    local fn = type(entry) == "table" and condition[entry.kind]
    if fn and gatesOnly and not (entry.kind == "notturnedin" and type(step.lines) == "table" and gates(step, entry.quest)) then
      fn = nil
    end
    local reason = fn and fn(entry)
    if reason then return reason, entry.jump end
  end
  return nil
end

-- ---------------------------------------------------------------------------------------------------------------
-- Places
-- ---------------------------------------------------------------------------------------------------------------

-- Whether a line no longer needs its place: hidden, or an active line that is done or skipped. Passive lines keep
-- their places while the step is shown.
local function settled(line, step, i, ctx)
  if ctx.done and ctx.done[i] then return true end
  local state = Lines.Check(line, step, ctx)
  if state == "hidden" then return true end
  if not Lines.Active(line) then return false end
  return state == "done" or state == "skip"
end

function Lines.Places(step, reached, ctx)
  reached = reached or {}
  ctx = ctx or {}
  local out = {}
  local list = type(step) == "table" and step.lines or {}
  local open, needsStep = {}, false
  for i = 1, #list do
    local line = list[i]
    open[i] = not settled(line, step, i, ctx)
    if open[i] and not line.at then needsStep = true end
  end
  if step.at and needsStep and not reached[step.at] then
    out[#out + 1] = { at = step.at, line = 0, nearest = step.at.nearest == true }
  end
  for i = 1, #list do
    local place = list[i].at
    if open[i] and place and not reached[place] then
      out[#out + 1] = { at = place, line = i, nearest = place.nearest == true }
    end
  end
  -- Of the nearest places only the closest stays (the first when no distance can be told).
  local best, bestYards
  for i = 1, #out do
    if out[i].nearest then
      local yards = Lines.Yards(out[i].at)
      if not best or (yards and (not bestYards or yards < bestYards)) then
        best, bestYards = out[i], yards
      end
    end
  end
  if best then
    local kept = {}
    for i = 1, #out do
      if not out[i].nearest or out[i] == best then kept[#kept + 1] = out[i] end
    end
    out = kept
  end
  return out
end
