-- Noir Guides, GPLv3. See LICENSE.
-- Talents (spec 5.11, gap #37): the class's leveling build (Data/Talents.lua, made by tools/gen_ports.js) and the
-- next points to spend, told in chat and shown in the addon's own frames above the game's talent window.
--
--   Talents.LOGIN_SECONDS = 5, Talents.LEVEL_SECONDS = 1.5   the chat reminder's delay after login, and after a
--                            level-up or a talent group change
--   Talents.PULSE_SECONDS = 1.2, Talents.PULSE_LOW = 0.4     the ring's alpha goes 1 -> 0.4 -> 1 in one period
--   Talents.Builds()      -> { { id, name } } the class's builds (one per class today; more are owner data, later)
--   Talents.Choose(id)    -> true, or false for a build the class does not have; kept per character and per talent
--                            group (GetActiveTalentGroup where the client has it, else group 1)
--   Talents.Chosen()      -> the chosen build's id for the active talent group, or nil
--   Talents.Spec()        -> the build's main tree ("Combat"), or nil when there is no build for the class
--   Talents.Check()       -> true when the build fits the client's own trees; false and the reasons otherwise
--   Talents.Unspent()     -> points the character has to spend
--   Talents.Plan(count)   -> the next `count` points of the build that are still to learn, each
--                            { name, tree, rank, max, tab, index, learnable, why }: tab and index as the client's
--                            talent functions count them, rank the rank this point brings, learnable whether the game
--                            would take it now, why the reason when it would not
--   Talents.Off()         -> talents with more points than the build gives them: { { name, tree, rank } }
--   Talents.Lines()       -> what /noir talents prints
--   Talents.Read()        -> { shown, build, info, ring } what the frames above the talent window show (ring: whether
--                            the ring is shown); Talents.Frame(), .PickerFrame(), .RingFrame() the frames, for tests
--
-- Chat reminders (only while the option "talents" is on), LOGIN_SECONDS after login and LEVEL_SECONDS after a
-- level-up or a talent group change: asked once per talent group from level 10 to choose a build; told how many
-- points are ready and the next pick (once per pick and count); warned once per talent group about points spent off
-- the build. In the talent window (Blizzard_TalentUI loaded, TalentFrame shown) the addon's own frames, children of
-- TalentFrame anchored above it, show a build picker (Menu.Open), a line with the next point, and a ring on the next
-- talent's button (TalentFrameTalent<index> of the tab shown) pulsing between PULSE_LOW and 1. Nothing of the game's
-- frames is changed or hooked: they are only read (ENGINE-NOTES #93, #94).
--
-- The build is checked against the client before anything is suggested: every talent of the build must be where
-- the data puts it (tab, tier, column) with the same number of ranks. Forever changes talents between patches; a
-- build that no longer fits is reported in /noir problems and nothing is suggested, rather than advice the game
-- would refuse. Legality of each pick follows the game's rules: (tier - 1) * 5 points in the tree, the prerequisite
-- at its rank, at most the talent's ranks, and a point to spend. The addon never spends a point itself.
-- Fires NOIR_TALENTS when the plan may have changed.
local Noir = Noir
local State = Noir.State

local Talents = {}
Noir.Talents = Talents

Talents.LOGIN_SECONDS = 5
Talents.LEVEL_SECONDS = 1.5
Talents.PULSE_SECONDS = 1.2
Talents.PULSE_LOW = 0.4

local PER_TIER = 5
local FIRST_LEVEL = 10
local SHOWN = 5 -- picks /noir talents lists

-- ---------------------------------------------------------------------------------------------------------------
-- The data and the client's trees
-- ---------------------------------------------------------------------------------------------------------------

local function data()
  local all = Noir.Data.talents
  local mine = type(all) == "table" and State.class and all[State.class]
  if type(mine) ~= "table" or type(mine.tabs) ~= "table" or type(mine.build) ~= "table" then return nil end
  return mine
end

-- The build's id: its tree's name in lower case with dashes ("Feral Combat" -> "feral-combat").
local function idOf(name)
  return (string.gsub(string.lower(tostring(name)), "[^%w]+", "-"))
end

local function group()
  if GetActiveTalentGroup then
    local active = GetActiveTalentGroup()
    if type(active) == "number" and active >= 1 then return active end
  end
  return 1
end

-- Per character: builds[group] = id, asked[group] = true, warned[group] = true.
local function saved()
  if not Noir.char then return { builds = {}, asked = {}, warned = {} } end
  local mine = Noir.Table(Noir.char, "talents")
  Noir.Table(mine, "builds")
  Noir.Table(mine, "asked")
  Noir.Table(mine, "warned")
  return mine
end

function Talents.Builds()
  local d = data()
  if not d then return {} end
  return { { id = idOf(d.spec), name = d.spec } }
end

local function known(id)
  for _, b in ipairs(Talents.Builds()) do
    if b.id == id then return b end
  end
  return nil
end

function Talents.Choose(id)
  if not known(id) then return false end
  saved().builds[group()] = id
  Noir.Fire("NOIR_TALENTS")
  return true
end

function Talents.Chosen()
  local id = saved().builds[group()]
  if id and known(id) then return id end
  return nil
end

local function hasApi()
  return GetNumTalentTabs and GetNumTalents and GetTalentInfo and true or false
end

-- The client's trees: { { name, spent, talents = { { index, name, tier, column, rank, max } } } }, or nil.
local function readTrees()
  if not hasApi() then return nil end
  local trees = {}
  for tab = 1, GetNumTalentTabs() or 0 do
    local name = GetTalentTabInfo and GetTalentTabInfo(tab)
    local tree = { name = type(name) == "string" and name or nil, spent = 0, talents = {} }
    for index = 1, GetNumTalents(tab) or 0 do
      local talentName, _, tier, column, rank, max = GetTalentInfo(tab, index)
      if type(tier) == "number" and type(column) == "number" then
        rank = type(rank) == "number" and rank or 0
        tree.talents[#tree.talents + 1] = {
          index = index, name = talentName, tier = tier, column = column, rank = rank, max = type(max) == "number" and max or 0,
        }
        tree.spent = tree.spent + rank
      end
    end
    trees[tab] = tree
  end
  return trees
end

-- Matches the data's talents to the client's: id -> { tab, talent (the client's), def (the data's), tree }.
-- Returns the map and the reasons the build does not fit (empty when it does).
local function match(d, trees)
  local map, wrong = {}, {}
  for tab, def in ipairs(d.tabs) do
    local tree = trees[tab]
    for _, t in ipairs(def.talents) do
      local found
      if tree then
        for _, c in ipairs(tree.talents) do
          if c.tier == t.tier and c.column == t.column then found = c end
        end
      end
      map[t.id] = { tab = tab, talent = found, def = t, tree = tree and tree.name or def.name }
    end
  end
  local seen = {}
  for _, id in ipairs(d.build) do
    if not seen[id] then
      seen[id] = true
      local m = map[id]
      local label = m and (m.def.name or (m.talent and m.talent.name)) or ("talent " .. tostring(id))
      if not m then
        wrong[#wrong + 1] = label .. " is not in the data's trees"
      elseif not m.talent then
        wrong[#wrong + 1] = string.format("%s (%s) is not at tier %d, column %d on this client", label, m.tree, m.def.tier, m.def.column)
      elseif m.talent.max ~= m.def.max then
        wrong[#wrong + 1] = string.format("%s has %d ranks on this client, %d in the build's data", label, m.talent.max, m.def.max)
      end
    end
  end
  return map, wrong
end

local function nameOf(m)
  return (m.talent and type(m.talent.name) == "string" and m.talent.name ~= "" and m.talent.name) or m.def.name
    or string.format("the talent at tier %d, column %d", m.def.tier, m.def.column)
end

-- ---------------------------------------------------------------------------------------------------------------
-- State of the build, worked out fresh on every call: the client's trees change with every point.
-- ---------------------------------------------------------------------------------------------------------------

local reportedFit = false

-- -> d, trees, map, wrong; any of the first three nil when it cannot be told.
local function look()
  local d = data()
  if not d then return nil end
  local trees = readTrees()
  if not trees then return d end
  local map, wrong = match(d, trees)
  if #wrong > 0 and not reportedFit then
    reportedFit = true
    Noir.Problem("The " .. tostring(d.spec) .. " talent build for " .. tostring(State.class) .. " does not fit this client's talent trees, so no talent is suggested: "
      .. table.concat(wrong, "; ") .. ".")
  end
  return d, trees, map, wrong
end

function Talents.Spec()
  local d = data()
  return d and d.spec or nil
end

function Talents.Check()
  local d, trees, _, wrong = look()
  if not (d and trees) then return false, { d and "the client has no talent functions" or "there is no build for this class" } end
  return #wrong == 0, wrong
end

-- Points to spend: the client's count where it gives one, else one per level from 10 minus the points spent.
function Talents.Unspent()
  if UnitCharacterPoints then
    local points = UnitCharacterPoints("player")
    if type(points) == "number" then return math.max(0, points) end
  end
  if GetUnspentTalentPoints then
    local points = GetUnspentTalentPoints()
    if type(points) == "number" then return math.max(0, points) end
  end
  local trees = readTrees()
  if not trees then return 0 end
  local spent = 0
  for _, tree in ipairs(trees) do spent = spent + tree.spent end
  return math.max(0, math.max(0, State.level - FIRST_LEVEL + 1) - spent)
end

-- Why the game would not take a point now, or nil when it would. ranks: id -> rank; spent: tab -> points.
local function refusal(d, map, m, rank, ranks, spent, unspent)
  local need = (m.def.tier - 1) * PER_TIER
  if (spent[m.tab] or 0) < need then
    return string.format("needs %d points in %s, you have %d", need, m.tree, spent[m.tab] or 0)
  end
  if m.def.prereq then
    local pre = map[m.def.prereq]
    local preRank = m.def.prereqRank or (pre and pre.def.max) or 1
    if (ranks[m.def.prereq] or 0) < preRank then
      return string.format("needs %s at rank %d", pre and nameOf(pre) or "another talent", preRank)
    end
  end
  if (ranks[m.def.id] or 0) + 1 ~= rank then return string.format("comes after rank %d", rank - 1) end
  if unspent <= 0 then return "no point to spend yet" end
  return nil
end

function Talents.Plan(count)
  local out = {}
  if type(count) ~= "number" or count <= 0 then return out end
  local d, trees, map, wrong = look()
  if not (d and trees) or #wrong > 0 then return out end
  local ranks, spent = {}, {}
  for id, m in pairs(map) do ranks[id] = m.talent and m.talent.rank or 0 end
  for tab, tree in ipairs(trees) do spent[tab] = tree.spent end
  local unspent = Talents.Unspent()
  local planned, simulated = {}, {}
  for id, rank in pairs(ranks) do simulated[id] = rank end
  for _, id in ipairs(d.build) do
    planned[id] = (planned[id] or 0) + 1
    if simulated[id] < planned[id] then
      local m = map[id]
      local rank = simulated[id] + 1
      simulated[id] = rank
      local why = refusal(d, map, m, rank, ranks, spent, unspent)
      out[#out + 1] = {
        name = nameOf(m), tree = m.tree, rank = rank, max = m.def.max, tab = m.tab, index = m.talent.index,
        learnable = why == nil, why = why,
      }
      if #out >= count then break end
    end
  end
  return out
end

function Talents.Off()
  local out = {}
  local d, trees, map, wrong = look()
  if not (d and trees) or #wrong > 0 then return out end
  local planned = {}
  for _, id in ipairs(d.build) do planned[id] = (planned[id] or 0) + 1 end
  -- Talents of the client that the data does not know count too.
  for tab, tree in ipairs(trees) do
    for _, t in ipairs(tree.talents) do
      if t.rank > 0 then
        local id
        for otherId, m in pairs(map) do
          if m.talent == t then id = otherId end
        end
        if t.rank > (id and planned[id] or 0) then
          out[#out + 1] = { name = t.name or (id and map[id].def.name) or "?", tree = tree.name or d.tabs[tab].name, rank = t.rank, tab = tab, index = t.index }
        end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.tab ~= b.tab then return a.tab < b.tab end
    return a.index < b.index
  end)
  for _, o in ipairs(out) do o.tab, o.index = nil, nil end
  return out
end

-- ---------------------------------------------------------------------------------------------------------------
-- Telling the player
-- ---------------------------------------------------------------------------------------------------------------

local function pickText(pick)
  return string.format("%s %d/%d (%s)", pick.name, pick.rank, pick.max, pick.tree)
end

function Talents.Lines()
  local d = data()
  if not d then return { "There is no talent build for your class." } end
  if not hasApi() then return { "This client gives no talent functions the addon knows, so it cannot read your talents." } end
  local fits, wrong = Talents.Check()
  if not fits then
    return { "The " .. tostring(d.spec) .. " talent build does not fit this client's talent trees: " .. table.concat(wrong, "; ") .. "." }
  end
  local unspent = Talents.Unspent()
  local lines = { string.format("%s build. %d point%s to spend.", d.spec, unspent, unspent == 1 and "" or "s") }
  local plan = Talents.Plan(SHOWN)
  if #plan == 0 then
    lines[#lines + 1] = "Every talent of the build is learned."
  else
    lines[#lines + 1] = "Next:"
    for _, pick in ipairs(plan) do
      lines[#lines + 1] = "  " .. pickText(pick) .. (pick.why and (" - " .. pick.why) or "")
    end
  end
  local off = Talents.Off()
  if #off > 0 then
    local parts = {}
    for i, o in ipairs(off) do parts[i] = string.format("%s %d (%s)", o.name, o.rank, o.tree) end
    lines[#lines + 1] = "Points not in the build: " .. table.concat(parts, ", ") .. ". The plan goes on with the build's talents the game allows."
  end
  return lines
end

function Talents.Print()
  for _, line in ipairs(Talents.Lines()) do Noir.Print(line) end
end

local function option(key)
  local options = Noir.Options
  if not (options and options.Get) then return true end
  return options.Get(key)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Chat reminders
-- ---------------------------------------------------------------------------------------------------------------

local told = nil  -- the pick and point count last told, so each is told once
local pending = 0 -- the reminder scheduled last; an earlier one that comes due is dropped

local function offText(off)
  local parts = {}
  for i, o in ipairs(off) do parts[i] = string.format("%s %d (%s)", o.name, o.rank, o.tree) end
  return table.concat(parts, ", ")
end

local function remind()
  if not State.ready or option("talents") == false then return end
  local d = data()
  if not (d and hasApi()) then return end
  local mine, active = saved(), group()
  if (State.level or 0) >= FIRST_LEVEL and not Talents.Chosen() and not mine.asked[active] then
    mine.asked[active] = true
    Noir.Print("Choose a talent build: open the talent window and pick one above it. Until you do, the "
      .. tostring(d.spec) .. " build is followed.")
  end
  if not Talents.Check() then return end
  local off = Talents.Off()
  if #off > 0 and not mine.warned[active] then
    mine.warned[active] = true
    Noir.Print("Talent points not in your build: " .. offText(off) .. ". The plan goes on with the build's talents the game allows.")
  end
  local unspent = Talents.Unspent()
  if unspent <= 0 then
    told = nil
    return
  end
  local pick = Talents.Plan(1)[1]
  if not (pick and pick.learnable) then return end
  local key = pick.tab .. ":" .. pick.index .. ":" .. pick.rank .. ":" .. unspent
  if key == told then return end
  told = key
  Noir.Print(string.format("Talent point: %s. %d point%s ready.", pickText(pick), unspent, unspent == 1 and "" or "s"))
end

local function schedule(seconds)
  pending = pending + 1
  local mine = pending
  Noir.After(seconds, function()
    if mine == pending then remind() end
  end)
end

-- ---------------------------------------------------------------------------------------------------------------
-- The frames above the talent window
-- ---------------------------------------------------------------------------------------------------------------

local WIDTH = 300
local RING_SIZE = 52      -- around a 32-unit talent button
local LOOK_SECONDS = 0.25 -- how often the shown tab is read again while the window is open

local holder, parts = nil, {}
local refresh -- defined below

-- The tab the talent window shows, read from the game's frame without changing it; nil when it cannot be told.
local function shownTab(frame)
  if PanelTemplates_GetSelectedTab then
    local good, tab = pcall(PanelTemplates_GetSelectedTab, frame)
    if good and type(tab) == "number" then return tab end
  end
  local tab = frame.selectedTab
  return type(tab) == "number" and tab or nil
end

local function openPicker()
  local menu = Noir.Menu
  if not (menu and menu.Open) then return end
  local items = {}
  local builds = Talents.Builds()
  local followed = Talents.Chosen() or (builds[1] and builds[1].id)
  for _, b in ipairs(builds) do
    local id = b.id
    items[#items + 1] = {
      text = b.name,
      checked = function() return (Talents.Chosen() or followed) == id end,
      on = function() Talents.Choose(id) end,
    }
  end
  if #items == 0 then items[1] = { text = "There is no talent build for your class", heading = true } end
  menu.Open(items, { title = "Talent build" })
end

local function pulse(self, elapsed)
  self.t = ((self.t or 0) + (elapsed or 0)) % Talents.PULSE_SECONDS
  local middle = (1 + Talents.PULSE_LOW) / 2
  self:SetAlpha(middle + (1 - middle) * math.cos(2 * math.pi * self.t / Talents.PULSE_SECONDS))
end

local function build(frame)
  local Theme, Panel = Noir.Theme, Noir.Panel
  holder = CreateFrame("Frame", nil, frame)
  holder:SetSize(WIDTH, 4 * Theme.metrics.pad)
  holder:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2)
  local bay = holder:CreateTexture(nil, "BACKGROUND")
  Theme.Paint(bay, "bay", Theme.metrics.alpha)
  bay:SetAllPoints(holder)
  parts.kicker = Panel.Text(holder, "kicker", "lamp")
  parts.picker = Panel.Row(holder, function() openPicker() end)
  parts.info = Panel.Text(holder, "body", "paper")
  local ring = CreateFrame("Frame", nil, holder)
  ring:SetSize(RING_SIZE, RING_SIZE)
  ring:SetFrameStrata("HIGH")
  ring.texture = ring:CreateTexture(nil, "OVERLAY")
  ring.texture:SetTexture(Theme.Texture("pin"))
  Theme.Tint(ring.texture, "lamp")
  ring.texture:SetAllPoints(ring)
  ring:SetScript("OnUpdate", pulse)
  ring:Hide()
  parts.ring = ring
  local since = 0
  holder:SetScript("OnUpdate", function(_, elapsed)
    since = since + (elapsed or 0)
    if since >= LOOK_SECONDS then
      since = 0
      refresh()
    end
  end)
  holder:SetScript("OnShow", function() refresh() end)
end

-- The next-point line, the pick and the tab shown.
local function infoText(frame)
  local d = data()
  if not Talents.Check() then return "The " .. tostring(d.spec) .. " build does not fit this client's talent trees." end
  local pick = Talents.Plan(1)[1]
  if not pick then return "Every talent of the build is learned." end
  local unspent = Talents.Unspent()
  local text = "Next point: " .. pickText(pick)
  if unspent > 0 then
    text = text .. string.format(". %d point%s ready.", unspent, unspent == 1 and "" or "s")
    if not pick.learnable and pick.why then text = text .. " Not yet: " .. pick.why .. "." end
  elseif (State.level or 0) < FIRST_LEVEL then
    text = text .. ", from level " .. FIRST_LEVEL .. "."
  else
    text = text .. ", at your next level."
  end
  local tab = shownTab(frame)
  if tab and tab ~= pick.tab then text = text .. " Open the " .. tostring(pick.tree) .. " tab." end
  return text, pick, tab
end

local drawing = false

function refresh()
  if not holder or drawing then return end
  local frame = rawget(_G, "TalentFrame")
  local wanted = frame and option("talents") ~= false and data() ~= nil and hasApi()
  if not wanted then
    holder:Hide()
    return
  end
  drawing = true
  holder:Show()
  if holder:IsVisible() then
    local text, pick, tab = infoText(frame)
    local chosen = known(Talents.Chosen() or "") or Talents.Builds()[1]
    local layout = Noir.Panel.Layout(holder)
    layout:Text(parts.kicker, "NOIR GUIDES TALENTS")
    layout:Row(parts.picker, "Build: " .. tostring(chosen and chosen.name or "none") .. " (click to choose)")
    layout:Text(parts.info, text)
    layout:Finish()
    local ring = parts.ring
    local button = pick and (tab == nil or tab == pick.tab) and rawget(_G, "TalentFrameTalent" .. tostring(pick.index))
    if type(button) == "table" and button.IsShown and button:IsShown() then
      ring:ClearAllPoints()
      ring:SetPoint("CENTER", button, "CENTER", 0, 0)
      ring:Show()
    else
      ring:Hide()
    end
  end
  drawing = false
end

local function attach()
  local frame = rawget(_G, "TalentFrame")
  if holder or type(frame) ~= "table" then return end
  build(frame)
  refresh()
end

function Talents.Read()
  if not holder then return { shown = false, ring = false } end
  return {
    shown = holder:IsVisible() and true or false,
    build = Noir.Panel.RowText(parts.picker),
    info = parts.info:IsShown() and parts.info:GetText() or nil,
    ring = parts.ring:IsVisible() and true or false,
  }
end

function Talents.Frame() return holder end
function Talents.PickerFrame() return parts.picker end
function Talents.RingFrame() return parts.ring end

-- ---------------------------------------------------------------------------------------------------------------
-- Events and the command
-- ---------------------------------------------------------------------------------------------------------------

local function changed()
  Noir.Fire("NOIR_TALENTS")
end

Noir.On("NOIR_TALENTS", function() refresh() end)
Noir.On("NOIR_READY", function()
  changed()
  attach()
  schedule(Talents.LOGIN_SECONDS)
end)
Noir.On("PLAYER_LEVEL_UP", function()
  changed()
  schedule(Talents.LEVEL_SECONDS)
end)
Noir.On("CHARACTER_POINTS_CHANGED", changed)
Noir.On("PLAYER_TALENT_UPDATE", changed)
if GetActiveTalentGroup then
  Noir.On("ACTIVE_TALENT_GROUP_CHANGED", function()
    told = nil
    changed()
    schedule(Talents.LEVEL_SECONDS)
  end)
end
Noir.On("ADDON_LOADED", function(_, name)
  if name == "Blizzard_TalentUI" then attach() end
end)
Noir.On("NOIR_OPTION", function(_, key)
  if key == "talents" then refresh() end
end)

Noir.Command("talents", "your class's talent build and the next points to spend", Talents.Print)
