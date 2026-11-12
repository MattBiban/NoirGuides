-- Noir Guides, GPLv3. See LICENSE.
-- Text (spec 3.1, 3.2): the words of every line of a step, built from the line, Noir.Data and what the client knows.
-- Only a step's `text` and note/manual lines carry sentences written by the planner.
--
--   Text.Line(line, step) -> { text, icon, quest, spans, tooltip }
--       icon: "accept", "turnin", "objective", "kill", "item", "vendor", "trainer", "gossip", "flight",
--       "flightpoint", "hearth", "bind", "goto", "xp", "error", "note".
--       quest: the quest ID of a quest line. spans: { { kind, from, to } } byte ranges of `text` naming things by
--       meaning ("friend", "enemy", "loot", "warning", "object", "buy") for highlighting. tooltip: extra lines, set
--       when an accept line's prerequisites (`requires`) are not all handed in (icon "error"; never skipped).
--   Text.StepTitle(step) -> step.title or tostring(step.n)
--   Text.QuestName(id), Text.NpcName(id), Text.ItemName(id), Text.ZoneName(area), Text.FlightName(node),
--   Text.SpellName(id): Noir.Data first, then the client, then "Quest 364", "NPC 42", "Item 1", "Zone 5",
--       "Flight point 7", "Spell 9"
--   Text.Place(point) -> "Tirisfal Glades 30.8, 66.2" (the zone alone when x = y = 0)
--   Text.Distance(yards) -> "120 yd"
--   Text.RANKS                     the names of the profession ranks 1 to 4
local Noir = Noir
local State = Noir.State

local Text = Noir.Text or {}
Noir.Text = Text

Text.RANKS = { "Apprentice", "Journeyman", "Expert", "Artisan" }
Text.PREREQ_TITLE = "Hand these in first:"

-- ---------------------------------------------------------------------------------------------------------------
-- Names
-- ---------------------------------------------------------------------------------------------------------------

local function filled(name)
  return type(name) == "string" and name ~= "" and name or nil
end

function Text.QuestName(id)
  local name = filled(Noir.Data.quests[id])
  if name then return name end
  local q = State.quests[id]
  name = q and filled(q.title)
  if name then return name end
  if C_QuestLog then
    name = (C_QuestLog.GetTitleForQuestID and filled(C_QuestLog.GetTitleForQuestID(id)))
      or (C_QuestLog.GetQuestInfo and filled(C_QuestLog.GetQuestInfo(id)))
    if name then return name end
  end
  return "Quest " .. tostring(id)
end

function Text.NpcName(id)
  return filled(Noir.Data.npcs[id]) or ("NPC " .. tostring(id))
end

function Text.ItemName(id)
  local name = filled(Noir.Data.items[id])
  if name then return name end
  if GetItemInfo then name = filled((GetItemInfo(id))) end
  if not name and C_Item and C_Item.GetItemNameByID then name = filled(C_Item.GetItemNameByID(id)) end
  return name or ("Item " .. tostring(id))
end

function Text.ZoneName(area)
  local z = Noir.Data.zones[area]
  local name = type(z) == "table" and filled(z.name)
  if name then return name end
  if C_Map and C_Map.GetAreaInfo then name = filled(C_Map.GetAreaInfo(area)) end
  return name or ("Zone " .. tostring(area))
end

function Text.FlightName(node)
  local f = Noir.Data.flights[node]
  return (type(f) == "table" and filled(f.name)) or ("Flight point " .. tostring(node))
end

function Text.SpellName(id)
  local name
  if GetSpellInfo then name = filled((GetSpellInfo(id))) end
  if not name and C_Spell and C_Spell.GetSpellName then name = filled(C_Spell.GetSpellName(id)) end
  return name or ("Spell " .. tostring(id))
end

local function number(v)
  return string.format("%.1f", v)
end

function Text.Place(point)
  if type(point) ~= "table" then return "" end
  local zone = Text.ZoneName(point.zone)
  if (point.x or 0) == 0 and (point.y or 0) == 0 then return zone end
  return zone .. " " .. number(point.x) .. ", " .. number(point.y)
end

function Text.Distance(yards)
  return string.format("%d yd", math.floor((yards or 0) + 0.5))
end

function Text.StepTitle(step)
  if type(step) ~= "table" then return "" end
  if filled(step.title) then return step.title end
  return tostring(step.n)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Building a line's text with its spans
-- ---------------------------------------------------------------------------------------------------------------

local function builder()
  local b = { parts = {}, len = 0, spans = {} }
  function b.add(piece, kind)
    piece = tostring(piece)
    if kind and piece ~= "" then
      b.spans[#b.spans + 1] = { kind = kind, from = b.len + 1, to = b.len + #piece }
    end
    b.parts[#b.parts + 1] = piece
    b.len = b.len + #piece
    return b
  end
  function b.done(icon, quest)
    return { text = table.concat(b.parts), icon = icon, quest = quest, spans = b.spans }
  end
  return b
end

local function counterText(counter)
  if not counter then return "" end
  return counter.have .. "/" .. counter.need
end

local function check(line, step)
  return Noir.Lines.Check(line, step or { lines = { line } }, {})
end

-- Quest IDs of `requires` not yet handed in.
local function missingPrereqs(line)
  local out = {}
  if type(line.requires) ~= "table" then return out end
  for i = 1, #line.requires do
    if not State.IsDone(line.requires[i]) then out[#out + 1] = line.requires[i] end
  end
  return out
end

local OBJECTIVE_SPAN = { monster = "enemy", item = "loot", object = "object" }
local OBJECTIVE_ICON = { monster = "kill", item = "item" }

local words = {}

words.accept = function(line)
  local missing = missingPrereqs(line)
  local b = builder().add("Accept ")
  if #missing == 0 then
    return b.add(Text.QuestName(line.quest)).done("accept", line.quest)
  end
  local t = b.add(Text.QuestName(line.quest), "warning").done("error", line.quest)
  t.tooltip = { Text.PREREQ_TITLE }
  for i = 1, #missing do t.tooltip[#t.tooltip + 1] = Text.QuestName(missing[i]) end
  return t
end

words.turnin = function(line)
  return builder().add("Turn in ").add(Text.QuestName(line.quest)).done("turnin", line.quest)
end

words.objective = function(line, step)
  local _, _, counter = check(line, step)
  local q = State.Quest(line.quest)
  local o = q and q.objectives[line.index]
  local b = builder()
  if o then
    -- The quest log's text without its own counter, then ours (the cap may lower the need).
    local label = string.gsub(o.text or "", "%s*:?%s*%d+%s*/%s*%d+%s*$", "")
    if label == "" then label = Text.QuestName(line.quest) end
    b.add(label, OBJECTIVE_SPAN[o.kind])
    if counter and o.kind ~= "event" then b.add(": " .. counterText(counter)) end
    return b.done(OBJECTIVE_ICON[o.kind] or "objective", line.quest)
  end
  local icon = (line.npc and "kill") or (line.item and "item") or "objective"
  if q and #q.objectives == 0 then
    return b.add(Text.QuestName(line.quest)).add(": " .. counterText(counter)).done("objective", line.quest)
  end
  return b.add(Text.QuestName(line.quest)).add(": objective " .. tostring(line.index)).done(icon, line.quest)
end

words.collect = function(line, step)
  local _, _, counter = check(line, step)
  return builder().add("Collect ").add(Text.ItemName(line.item), "loot").add(" " .. counterText(counter))
    .done("item", line.quest)
end

words["goto"] = function(line)
  return builder().add("Go to " .. Text.Place(line.at)).done("goto")
end

words.getflight = function(line)
  return builder().add("Get the " .. Text.FlightName(line.node) .. " flight point").done("flightpoint")
end

words.fly = function(line)
  return builder().add("Fly to " .. Text.FlightName(line.to)).done("flight")
end

words.transport = function(line)
  return builder().add("Take the " .. tostring(line.mode) .. " to " .. Text.ZoneName(line.to.zone)).done("flight")
end

words.sethearth = function(line, step)
  local place = line.at or (step and step.at)
  local where = place and Text.ZoneName(place.zone) or "the inn"
  return builder().add("Set your hearthstone at " .. where).done("bind")
end

words.hearth = function(line)
  return builder().add("Hearth to " .. Text.ZoneName(line.to.zone)).done("hearth")
end

words.grind = function(line)
  local b = builder()
  if line.percent and line.percent > 0 then
    b.add("Grind until " .. line.percent .. "% into level " .. line.level)
  else
    b.add("Grind to level " .. line.level)
  end
  local have, need = Noir.Lines.GrindCounter(line)
  if have then b.add(" " .. have .. "/" .. need) end
  return b.done("xp")
end

words.train = function(line)
  local b = builder()
  if line.spell then return b.add("Learn " .. Text.SpellName(line.spell)).done("trainer") end
  if line.skill and line.rank then
    local rank = Text.RANKS[line.rank] or ("rank " .. tostring(line.rank))
    return b.add("Learn " .. rank .. " " .. Noir.Lines.ProfessionName(line.skill)).done("trainer")
  end
  if line.npc then
    b.add("Visit ").add(Text.NpcName(line.npc), "friend")
    return b.add(" to learn your level " .. tostring(line.level) .. " spells").done("trainer")
  end
  return b.add("Learn your level " .. tostring(line.level) .. " spells at your trainer").done("trainer")
end

words.vendor = function(line)
  local b = builder().add("Visit ").add(Text.NpcName(line.npc), "friend")
  if type(line.buy) == "table" then
    b.add(", buy " .. tostring(line.buy.count) .. " ").add(Text.ItemName(line.buy.item), "buy")
  end
  return b.done("vendor")
end

words.use = function(line)
  return builder().add("Use ").add(Text.ItemName(line.item), "loot").done("item")
end

words.target = function(line)
  if line.enemy then
    return builder().add("Kill ").add(Text.NpcName(line.npc), "enemy").done("kill")
  end
  return builder().add("Talk to ").add(Text.NpcName(line.npc), "friend").done("gossip")
end

words.note = function(line)
  return builder().add(line.text or "").done("note")
end
words.manual = words.note

function Text.Line(line, step)
  local fn = type(line) == "table" and words[line.kind]
  if not fn then return { text = "", icon = "note", spans = {} } end
  return fn(line, step)
end
