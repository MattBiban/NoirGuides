-- Noir Guides, GPLv3. See LICENSE.
-- Cleanup (spec 5.9, 6.1, gap #38): the quest log against the rest of the route, for a player who changed section or
-- left a zone behind.
--
-- The rest of the route is the current section from the current step on (and the steps on screen as reminders or
-- detours), then every later section of Guide.Chain. Data/Cleanup.lua gives the facts per quest
-- (Noir.Data.questTies: classes, skill, instance, event, item); the quest log gives each quest's header.
--   never listed     a class quest (any class), a profession quest, a dungeon or raid quest, or a quest under the
--                    header of a class or a profession
--   "drop", ticked   failed (it has to be dropped to be taken again), or not on the rest of the route ("grey" in the
--                    words when below the green range)
--   "check", unticked  still on the route but grey, ready to hand in (the work is lost), offered only during an
--                    event, or started by an item that may not drop again
--   not listed       anything else the rest of the route names
-- Rows are sorted by group, then off-route quests first, then by level, title and ID. Nothing is abandoned before the
-- player presses the button; then a quest is checked again just before it goes (still in the log and still listed),
-- the quests go from the bottom of the quest log up, one every STEP_SECONDS, and combat stops them.
--
--   Cleanup.STEP_SECONDS = 0.2
--   Cleanup.RouteQuests()   -> set of quest IDs the rest of the route names, and whether there is a route and place
--   Cleanup.Scan()          -> rows { quest, title, level, group, reason, ticked, offRoute }, and whether there is a route
--   Cleanup.Offer()         -> true when it opened the window: only when at least one row starts ticked (the menu calls
--                              it after a section picked by hand, when "offerCleanup" is on)
--   Cleanup.Open(), .Close(), .Read() -> { shown, rows = { text }, button, close }
--   Cleanup.Ticked()        -> the ticked quest IDs, sorted
--   Cleanup.Abandon()       -> how many ticked quests it is going to abandon
--   Cleanup.RowFrame(quest), .ButtonFrame(), .CloseFrame(), .LogButton(), .List()   the window's parts, for clicks
-- The window opens at Screen.DEFAULTS.dialog, is kept on the screen and capped by Screen.Fit; its rows scroll. The
-- button beside the quest log frame is the addon's own frame, a child of QuestLogFrame anchored to its right edge:
-- the quest log frame itself is never changed or hooked (ENGINE-NOTES #96). /noir cleanup opens the window.
local Noir = Noir
local State, Panel, Theme, Screen = Noir.State, Noir.Panel, Noir.Theme, Noir.Screen

local Cleanup = {}
Noir.Cleanup = Cleanup

Cleanup.STEP_SECONDS = 0.2

local WIDTH = 360
local GROUPS = { "drop", "check" }
local HEADINGS = { drop = "OFF YOUR ROUTE", check = "CHECK BEFORE DROPPING" }
local CLASS_TOKENS = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local LEAST_LIST = 60 -- the list's least height when the screen is small

local ticked = {}      -- quest ID -> true / false: the tick of each row the window has shown
local queue, busy = {}, false
local frame, parts = nil, { rows = {} }

-- ---------------------------------------------------------------------------------------------------------------
-- What the rest of the route names
-- ---------------------------------------------------------------------------------------------------------------

local function when(cond)
  local guide = Noir.Guide
  return not (guide and guide.When) or guide.When(cond)
end

local function addStep(need, step)
  if type(step) ~= "table" or type(step.lines) ~= "table" then return end
  for _, line in ipairs(step.lines) do
    if line.quest and when(line.when) then need[line.quest] = true end
  end
end

function Cleanup.RouteQuests()
  local need = {}
  local Guide, Progress = Noir.Guide, Noir.Progress
  local section = Guide and Guide.Current()
  if not (section and Guide.Section(section)) then return need, false end
  local placed, index = nil, nil
  if Progress and Progress.Place then placed, index = Progress.Place() end
  local steps = Guide.Steps(section)
  if placed ~= section then index = 1 end
  for i = index or 1, #steps do addStep(need, steps[i]) end
  if Progress and Progress.Cards and placed == section then
    for _, card in ipairs(Progress.Cards()) do addStep(need, card.step) end
    -- Steps put off until a level (work ahead) are behind the place but still to do.
    if Progress.Deferred then
      for _, d in ipairs(Progress.Deferred()) do addStep(need, steps[d.index]) end
    end
  end
  local chain = Guide.Chain(section)
  for i = 2, #chain do
    for _, step in ipairs(Guide.Steps(chain[i])) do addStep(need, step) end
  end
  return need, true
end

-- ---------------------------------------------------------------------------------------------------------------
-- What a quest is tied to
-- ---------------------------------------------------------------------------------------------------------------

local function tiesOf(id)
  local all = Noir.Data.questTies
  local ties = type(all) == "table" and all[id] or nil
  return type(ties) == "table" and ties or {}
end

local function lower(text)
  return type(text) == "string" and string.lower(text) or nil
end

-- The headers that hold class and profession quests, in lower case: the client's class names (both forms), the
-- class tokens in title case, and the professions' names from the data and from the client (ENGINE-NOTES #95).
local function trainingHeaders()
  local out = {}
  local function add(name)
    local key = lower(name)
    if key and key ~= "" then out[key] = true end
  end
  for _, token in ipairs(CLASS_TOKENS) do
    add(string.upper(string.sub(token, 1, 1)) .. string.lower(string.sub(token, 2)))
    for _, names in ipairs({ LOCALIZED_CLASS_NAMES_MALE, LOCALIZED_CLASS_NAMES_FEMALE }) do
      if type(names) == "table" then add(names[token]) end
    end
  end
  if UnitClass then add((UnitClass("player"))) end
  local data = Noir.Data.professions
  if type(data) == "table" then
    for _, p in pairs(data) do
      if type(p) == "table" then add(p.name) end
    end
  end
  for _, p in pairs(State.professions or {}) do
    if type(p) == "table" then add(p.name) end
  end
  return out
end

-- quest ID -> the header it is under in the quest log (quests under a collapsed header are not there).
local function headers()
  local out = {}
  local log = C_QuestLog
  if log and log.GetNumQuestLogEntries and log.GetInfo then
    local header
    for i = 1, (log.GetNumQuestLogEntries()) or 0 do
      local info = log.GetInfo(i)
      if type(info) == "table" then
        if info.isHeader then header = info.title elseif info.questID then out[info.questID] = header end
      end
    end
    return out
  end
  if GetNumQuestLogEntries and GetQuestLogTitle then
    local header
    for i = 1, (GetNumQuestLogEntries()) or 0 do
      local title, _, _, isHeader, _, _, _, questId = GetQuestLogTitle(i)
      if isHeader then header = title elseif questId then out[questId] = header end
    end
  end
  return out
end

-- Never listed: the character's training or content the route does not judge.
local function protected(ties, header, training)
  if ties.classes or ties.skill or ties.instance then return true end
  local key = lower(header)
  return key ~= nil and training[key] == true
end

-- The highest quest level labelled "Grey": the grey level classic clients use for creatures (ENGINE-NOTES
-- assumption 50, unverified for quests on Forever).
local function greyLevel(level)
  if level <= 5 then return 0 end
  if level <= 39 then return level - 5 - math.floor(level / 10) end
  if level <= 59 then return level - 1 - math.floor(level / 5) end
  return level - 9
end

-- -> group, reason, offRoute; nil when the quest is not listed.
local function weigh(q, ties, onRoute, grey)
  local isGrey = (q.level or 0) > 0 and (q.level or 0) <= grey
  if q.failed then return "drop", "Failed: take it again from its giver", not onRoute end
  if onRoute then
    if isGrey then return "check", "Grey, but your route still uses it", false end
    return nil
  end
  if q.complete then return "check", "Ready to hand in: dropping it loses the work", true end
  if ties.event then return "check", "Offered only during " .. ties.event, true end
  if ties.item then return "check", "Starts from " .. ties.item .. ", which may not drop again", true end
  if isGrey then return "drop", "Grey, and not on your route", true end
  return "drop", "Not on your route", true
end

-- The row a quest of the log would have, or nil. `ctx` holds what is shared by one scan.
local function classify(id, q, ctx)
  local ties = tiesOf(id)
  if protected(ties, ctx.headers[id], ctx.training) then return nil end
  local group, reason, offRoute = weigh(q, ties, ctx.need[id] == true, ctx.grey)
  if not group then return nil end
  return {
    quest = id, group = group, reason = reason, offRoute = offRoute and true or false, starts = group == "drop",
    level = q.level or 0, title = q.title or Noir.Data.quests[id] or ("Quest " .. id),
  }
end

local function context()
  local need, hasRoute = Cleanup.RouteQuests()
  return { need = need, hasRoute = hasRoute, headers = headers(), training = trainingHeaders(), grey = greyLevel(State.level or 1) }
end

local function order(x, y)
  if x.offRoute ~= y.offRoute then return x.offRoute end
  if x.level ~= y.level then return x.level < y.level end
  if x.title ~= y.title then return x.title < y.title end
  return x.quest < y.quest
end

function Cleanup.Scan()
  local ctx = context()
  if not ctx.hasRoute then return {}, false end
  local buckets = { drop = {}, check = {} }
  for id, q in pairs(State.quests) do
    local row = classify(id, q, ctx)
    if row then
      if ticked[id] == nil then row.ticked = row.starts else row.ticked = ticked[id] end
      local bucket = buckets[row.group]
      bucket[#bucket + 1] = row
    end
  end
  local rows = {}
  for _, group in ipairs(GROUPS) do
    table.sort(buckets[group], order)
    for _, row in ipairs(buckets[group]) do rows[#rows + 1] = row end
  end
  return rows, true
end

function Cleanup.Ticked()
  local out = {}
  for id, on in pairs(ticked) do
    if on then out[#out + 1] = id end
  end
  table.sort(out)
  return out
end

-- ---------------------------------------------------------------------------------------------------------------
-- Abandoning
-- ---------------------------------------------------------------------------------------------------------------

local function inCombat()
  return State.inCombat or (InCombatLockdown and InCombatLockdown()) and true or false
end

-- A quest may go when it is in the log and still listed.
local function mayGo(id)
  local q = State.Quest(id)
  if not q then return false end
  return classify(id, q, context()) ~= nil
end

-- The quest's index in the old quest log API, or nil (a quest under a collapsed header has none).
local function logIndex(id)
  if GetQuestLogIndexByID then
    local index = GetQuestLogIndexByID(id)
    if type(index) == "number" and index > 0 then return index end
  end
  local log = C_QuestLog
  if log and log.GetLogIndexForQuestID then
    local index = log.GetLogIndexForQuestID(id)
    if type(index) == "number" and index > 0 then return index end
  end
  if GetNumQuestLogEntries and GetQuestLogTitle then
    for i = 1, GetNumQuestLogEntries() or 0 do
      local _, _, _, isHeader, _, _, _, questId = GetQuestLogTitle(i)
      if not isHeader and questId == id then return i end
    end
  end
  if log and log.GetNumQuestLogEntries and log.GetInfo then
    for i = 1, (log.GetNumQuestLogEntries()) or 0 do
      local info = log.GetInfo(i)
      if type(info) == "table" and not info.isHeader and info.questID == id then return i end
    end
  end
  return nil
end

local reportedApi = false

local function abandonOne(id)
  local log = C_QuestLog
  if log and log.SetSelectedQuest and log.SetAbandonQuest and log.AbandonQuest then
    log.SetSelectedQuest(id)
    log.SetAbandonQuest()
    log.AbandonQuest()
    return true
  end
  if SelectQuestLogEntry and SetAbandonQuest and AbandonQuest then
    local index = logIndex(id)
    if not index then return false end
    SelectQuestLogEntry(index)
    SetAbandonQuest()
    AbandonQuest()
    return true
  end
  if not reportedApi then
    reportedApi = true
    Noir.Problem("This client has no way to abandon a quest that the addon knows; the quest cleanup can only list quests.")
  end
  return false
end

local done, failed = 0, {}
local refresh -- the window, defined below

local function finish(stopped)
  busy = false
  if stopped then
    Noir.Print(string.format("Stopped: you are in combat. %d ticked quest%s %s not abandoned; press the button again after the fight.",
      #queue, #queue == 1 and "" or "s", #queue == 1 and "was" or "were"))
  else
    Noir.Print(string.format("Abandoned %d quest%s.", done, done == 1 and "" or "s"))
  end
  if #failed > 0 then Noir.Print("Could not abandon: " .. table.concat(failed, ", ") .. ". Expand the quest log's headers and try again.") end
  queue, failed = {}, {}
  refresh()
end

local function step()
  if inCombat() then return finish(true) end
  local id = table.remove(queue, 1)
  if id then
    ticked[id] = nil
    if mayGo(id) then
      local q = State.Quest(id)
      local title = (q and q.title) or ("Quest " .. id)
      if abandonOne(id) then done = done + 1 else failed[#failed + 1] = title end
    end
  end
  if #queue > 0 then
    Noir.After(Cleanup.STEP_SECONDS, step)
  else
    finish(false)
  end
end

function Cleanup.Abandon()
  if busy then return 0 end
  if inCombat() then
    Noir.Print("Quests cannot be abandoned in combat. Try again after the fight.")
    return 0
  end
  local list = {}
  for _, id in ipairs(Cleanup.Ticked()) do
    if mayGo(id) then list[#list + 1] = id else ticked[id] = nil end
  end
  if #list == 0 then
    Noir.Print("Tick the quests to abandon first: nothing is abandoned unless it is ticked.")
    refresh()
    return 0
  end
  -- Bottom of the quest log first; a quest the log does not show (under a collapsed header) last.
  local at = {}
  for _, id in ipairs(list) do at[id] = logIndex(id) or -1 end
  table.sort(list, function(a, b)
    if at[a] ~= at[b] then return at[a] > at[b] end
    return a < b
  end)
  local count = #list
  queue, busy, done, failed = list, true, 0, {}
  step()
  return count
end

-- ---------------------------------------------------------------------------------------------------------------
-- The review window
-- ---------------------------------------------------------------------------------------------------------------

local function rowWords(row)
  return string.format("%d  %s - %s", row.level, row.title, row.reason)
end

local function build()
  frame = Panel.New(WIDTH)
  Cleanup.frame = frame
  parts.kicker = Panel.Text(frame, "kicker", "lamp")
  parts.name = Panel.Text(frame, "name", "paper")
  parts.body = Panel.Text(frame, "body", "dim")
  parts.note = Panel.Text(frame, "body", "warn")
  local list = Panel.ScrollList(frame)
  list.frame:SetWidth(WIDTH)
  list.frame:SetHeight(LEAST_LIST)
  list.child:SetWidth(WIDTH)
  parts.list = list
  parts.headings = {}
  for _, group in ipairs(GROUPS) do parts.headings[group] = Panel.Text(list.child, "kicker", "dim") end
  parts.button = Panel.Row(frame, function() Cleanup.Abandon() end)
  parts.close = Panel.Row(frame, function() Cleanup.Close() end)
  Screen.Place(frame, "dialog")
  Screen.Register("cleanup", frame)
end

local function rowFor(i)
  local row = parts.rows[i]
  if not row then
    row = Panel.Row(parts.list.child, function(self)
      if not self.quest then return end
      ticked[self.quest] = not ticked[self.quest]
      refresh()
    end)
    parts.rows[i] = row
  end
  return row
end

function refresh()
  if not (frame and frame:IsShown()) then return end
  local list, hasRoute = Cleanup.Scan()
  -- Ticks of quests that are no longer listed are dropped; a row seen for the first time keeps the tick it started
  -- with.
  local listed = {}
  for _, row in ipairs(list) do
    listed[row.quest] = true
    if ticked[row.quest] == nil then ticked[row.quest] = row.ticked end
  end
  for id in pairs(ticked) do
    if not listed[id] and not busy then ticked[id] = nil end
  end
  local m = Theme.metrics
  local head = Panel.Layout(frame)
  head:Text(parts.kicker, "QUEST CLEANUP")
  if not hasRoute then
    head:Text(parts.name, "No route")
    head:Text(parts.body, "Without a route the cleanup cannot tell which quests you still need, so it lists none.")
  elseif #list == 0 then
    head:Text(parts.name, "Nothing to clean up")
    head:Text(parts.body, "Every quest in your log is on the rest of your route or part of your class or profession training.")
  else
    head:Text(parts.name, string.format("%d quest%s to look at", #list, #list == 1 and "" or "s"))
    head:Text(parts.body, "Ticked quests are off the rest of your route. Nothing is abandoned until you press the button.")
  end
  head:Text(parts.note, State.logHidden and "Part of your quest log is collapsed; quests under it are not listed." or nil)
  local top = head.y

  -- The rows, in the list that scrolls.
  local scroll = parts.list
  local body = Panel.Layout(scroll.child)
  body.y = 0
  local i = 0
  for _, group in ipairs(GROUPS) do
    local first = true
    for _, row in ipairs(list) do
      if row.group == group then
        if first then body:Text(parts.headings[group], HEADINGS[group]) end
        first = false
        i = i + 1
        local r = rowFor(i)
        r.quest = row.quest
        body:Row(r, rowWords(row), ticked[row.quest] == true)
      end
    end
    if first then body:Text(parts.headings[group], nil) end
  end
  for j = i + 1, #parts.rows do
    parts.rows[j].quest = nil
    parts.rows[j]:Hide()
  end
  local content = body.y

  -- The buttons under the list, measured first so the list gets the room that is left.
  local count = 0
  for _, row in ipairs(list) do
    if ticked[row.quest] then count = count + 1 end
  end
  local buttonWords = #list > 0 and string.format("Abandon %d quest%s", count, count == 1 and "" or "s") or nil
  local measure = Panel.Layout(frame)
  measure.y = 0
  measure:Row(parts.button, buttonWords)
  measure:Row(parts.close, #list > 0 and "Keep everything" or "Close")
  local buttons = measure.y
  local gap = content > 0 and m.gap or 0
  local total = top + content + gap + buttons + m.pad
  local fitted = Screen.Fit(frame, total)
  local listHeight = content - (total - fitted)
  if listHeight < math.min(content, LEAST_LIST) then listHeight = math.min(content, LEAST_LIST) end
  scroll.frame:ClearAllPoints()
  scroll.frame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -top)
  scroll.frame:SetHeight(math.max(1, listHeight))
  if content > 0 then scroll.frame:Show() else scroll.frame:Hide() end
  scroll:SetContentHeight(content)
  local foot = Panel.Layout(frame)
  foot.y = top + listHeight + gap
  foot:Row(parts.button, buttonWords)
  foot:Row(parts.close, #list > 0 and "Keep everything" or "Close")
  frame:SetHeight(foot.y + m.pad)
  Screen.Pull(frame)
end

function Cleanup.Open()
  if not frame then build() end
  ticked = {}
  frame:Show()
  refresh()
end

function Cleanup.Offer()
  local list, hasRoute = Cleanup.Scan()
  if not hasRoute then return false end
  local any = false
  for _, row in ipairs(list) do
    if row.starts then any = true end
  end
  if not any then return false end
  Cleanup.Open()
  return true
end

function Cleanup.Close()
  if frame then frame:Hide() end
end

function Cleanup.Read()
  if not frame then return { shown = false, rows = {} } end
  local rows = {}
  for _, row in ipairs(parts.rows) do
    local words = Panel.RowText(row)
    if words then rows[#rows + 1] = words end
  end
  return {
    shown = frame:IsShown() and true or false, rows = rows,
    button = Panel.RowText(parts.button), close = Panel.RowText(parts.close),
  }
end

function Cleanup.RowFrame(quest)
  for _, row in ipairs(parts.rows) do
    if row.quest == quest and row:IsShown() then return row end
  end
  return nil
end

function Cleanup.ButtonFrame()
  return parts.button
end

function Cleanup.CloseFrame()
  return parts.close
end

function Cleanup.List()
  return parts.list
end

-- ---------------------------------------------------------------------------------------------------------------
-- The button beside the quest log
-- ---------------------------------------------------------------------------------------------------------------

local logButton = nil
local LOG_BUTTON_WIDTH = 110

local function attachLogButton()
  local questLog = rawget(_G, "QuestLogFrame")
  if logButton or type(questLog) ~= "table" then return end
  -- A child of the quest log frame, so it shows and hides with it; anchored to its right edge, near the top.
  local button = Panel.Row(questLog, function() Cleanup.Open() end)
  local back = button:CreateTexture(nil, "BACKGROUND")
  Theme.Paint(back, "bay", Theme.metrics.alpha)
  back:SetAllPoints(button)
  -- A small plate: the light on it, ink just outside, the track just inside.
  Panel.Sheen(button)
  button.edges = Panel.Border(button, "track")
  button:SetSize(LOG_BUTTON_WIDTH, Theme.sizes.body + 4 * Theme.metrics.gap)
  button:ClearAllPoints()
  button:SetPoint("TOPLEFT", questLog, "TOPRIGHT", 2, -40)
  if button.text:GetFont() then
    Theme.SetText(button.text, "Quest cleanup")
    button.text:ClearAllPoints()
    button.text:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.text:Show()
  end
  button:Show()
  logButton = button
end

function Cleanup.LogButton()
  return logButton
end

-- ---------------------------------------------------------------------------------------------------------------
-- Events and the command
-- ---------------------------------------------------------------------------------------------------------------

Noir.On("NOIR_READY", attachLogButton)
Noir.On("ADDON_LOADED", function() attachLogButton() end)
Noir.On("NOIR_STATE", function(_, what)
  if what == "quests" or what == "level" then refresh() end
end)
Noir.On("NOIR_PLACE", function() refresh() end)
-- A new resolution or UI scale changes the room: the window is fitted again (Screen.Keep only moves it).
Noir.On("DISPLAY_SIZE_CHANGED", function() refresh() end)
Noir.On("UI_SCALE_CHANGED", function() refresh() end)

Noir.Command("cleanup", "review the quests the rest of your route does not need and abandon the ones you tick", Cleanup.Open)
