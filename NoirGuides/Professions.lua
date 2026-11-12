-- Noir Guides, GPLv3. See LICENSE.
-- Professions: the profession plan. For each profession the character has, or has planned, what to do next:
--
--   learn   planned, not learned yet: find a trainer
--   raise   below the skill at which the next rank can be trained
--   train   at or past that skill: the next rank waits at a trainer
--   wait    at or past that skill, but the next rank needs a higher level
--   max     the highest rank is trained
--
-- Ranks and their trainer gates on Forever (50, 125 and 200, not the 65/125/205 of other clients):
--   Apprentice up to 75, Journeyman up to 150 from skill 50, Expert up to 225 from 125, Artisan up to 300 from 200.
-- The levels the ranks need (10, 20, 35) are the common Classic ones and unverified on Forever (docs/ENGINE-NOTES.md).
--
--   Professions.RANKS                   { name, level, verified, gate, cap }; gate and cap are Lines.RANK_GATE[i]
--                                          and Lines.RANK_CAP[i], read when asked
--   Professions.Known()                 -> { [skillLine] = { name, rank, max } }, Forever's tier lines counted for
--                                          their profession (Data/Professions.lua)
--   Professions.Has(skillLine)          -> whether it is learned (a tier line counts); with IsPlanned, what a
--                                          route's `when.profession` reads through Guide.When
--   Professions.Plan()                  -> { { skillLine, name, kind, rank, max, action, next, text } }
--   Professions.SetPlanned(skillLine, on), Professions.IsPlanned(skillLine)   kept per character
--   Professions.Lines()                 what /noir professions prints
-- Skills come from State (by skill line ID, never by spell name). Fires NOIR_PROFESSIONS when the plan may change.
local Noir = Noir
local State = Noir.State

local Professions = {}
Noir.Professions = Professions

-- The gates (50, 125, 200) are the owner's Forever finding. The levels 10, 20 and 35 are those of other Classic
-- clients and are in none of the data: verified = false marks them (ENGINE-NOTES assumption 45).
-- Each rank's `gate` and `cap` are read from Lines.RANK_GATE and Lines.RANK_CAP whenever they are asked for, so the
-- chat plan and the route's training steps (Lines.Check of a `train` line) can never disagree.
Professions.RANKS = {
  { name = "Apprentice", level = 1 },
  { name = "Journeyman", level = 10, verified = false },
  { name = "Expert", level = 20, verified = false },
  { name = "Artisan", level = 35, verified = false },
}
local RANKS = Professions.RANKS
for i, rank in ipairs(RANKS) do
  setmetatable(rank, { __index = function(_, key)
    if key == "gate" then return Noir.Lines.RANK_GATE[i] end
    if key == "cap" then return Noir.Lines.RANK_CAP[i] end
    return nil
  end })
end

local function professions()
  local list = Noir.Data.professions
  return type(list) == "table" and list or {}
end

local function lines()
  local list = Noir.Data.professionLines
  return type(list) == "table" and list or {}
end

local function saved()
  if not Noir.char then return { plan = {}, told = {} } end
  local mine = Noir.Table(Noir.char, "professions")
  Noir.Table(mine, "plan")
  Noir.Table(mine, "told")
  return mine
end

function Professions.Known()
  local out = {}
  for skillLine, p in pairs(State.professions) do
    local own = lines()[skillLine] or skillLine
    local have = out[own]
    if not have or p.rank > have.rank or (p.rank == have.rank and p.max > have.max) then
      local data = professions()[own]
      out[own] = { name = (data and data.name) or p.name, rank = p.rank, max = p.max }
    end
  end
  return out
end

-- Learned: the profession itself or one of Forever's tier lines of it.
function Professions.Has(skillLine)
  return Professions.Known()[skillLine] ~= nil
end

function Professions.IsPlanned(skillLine)
  return saved().plan[skillLine] == true
end

-- Returns false for a skill line that is not a profession of the data.
function Professions.SetPlanned(skillLine, on)
  if not professions()[skillLine] then return false end
  saved().plan[skillLine] = on and true or nil
  Noir.Fire("NOIR_PROFESSIONS")
  return true
end

-- The rank a maximum skill belongs to (its index in RANKS); 0 when it is below the first.
local function rankOf(max)
  local found = 0
  for i, r in ipairs(RANKS) do
    if max >= r.cap then found = i end
  end
  return found
end

local function describe(e)
  local name, nextRank = e.name, e.next
  if e.action == "learn" then return "Learn " .. name .. " from a trainer." end
  if e.action == "max" then return string.format("%s %d/%d: %s, the highest rank, is trained.", name, e.rank, e.max, RANKS[#RANKS].name) end
  if e.action == "train" then
    return string.format("Train %s %s at a trainer (%d/%d now; up to %d after).", nextRank.name, name, e.rank, e.max, nextRank.cap)
  end
  if e.action == "wait" then
    return string.format("%s %s needs level %d (%d/%d now).", nextRank.name, name, nextRank.level, e.rank, e.max)
  end
  return string.format("Raise %s to %d to train %s %s (%d/%d now).", name, nextRank.gate, nextRank.name, name, e.rank, e.max)
end

function Professions.Plan()
  local out = {}
  local known = Professions.Known()
  local listed = {}
  for skillLine in pairs(known) do listed[skillLine] = true end
  for skillLine in pairs(saved().plan) do listed[skillLine] = true end
  for skillLine in pairs(listed) do
    local data = professions()[skillLine]
    local have = known[skillLine]
    local e = { skillLine = skillLine, name = (have and have.name) or (data and data.name) or ("skill " .. skillLine), kind = data and data.kind or "primary" }
    if not have then
      e.action, e.rank, e.max = "learn", 0, 0
    else
      e.rank, e.max = have.rank, have.max
      local nextRank = RANKS[rankOf(have.max) + 1]
      e.next = nextRank
      if not nextRank then
        e.action = "max"
      elseif have.rank >= nextRank.gate then
        e.action = State.level >= nextRank.level and "train" or "wait"
      else
        e.action = "raise"
      end
    end
    e.text = describe(e)
    out[#out + 1] = e
  end
  table.sort(out, function(a, b)
    if a.kind ~= b.kind then return a.kind == "primary" end
    return a.name < b.name
  end)
  return out
end

function Professions.Lines()
  local plan = Professions.Plan()
  if #plan == 0 then
    return { "You have no profession and none planned. Plan one in /noir menu, Professions." }
  end
  local out = {}
  for _, e in ipairs(plan) do out[#out + 1] = e.text end
  return out
end

function Professions.Print()
  for _, line in ipairs(Professions.Lines()) do Noir.Print(line) end
end

-- Says once per profession and rank when the next rank can be trained.
local function check()
  Noir.Fire("NOIR_PROFESSIONS")
  if not Noir.char then return end
  local told = saved().told
  for _, e in ipairs(Professions.Plan()) do
    if e.action == "train" then
      local key = e.next.name
      if told[e.skillLine] ~= key then
        told[e.skillLine] = key
        Noir.Print(e.text)
      end
    end
  end
end

Noir.On("NOIR_STATE", function(_, what)
  if what == "professions" or what == "level" then check() end
end)

Noir.Command("professions", "your professions and what to do next for each", Professions.Print)
