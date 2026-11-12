-- Noir Guides, GPLv3. See LICENSE.
-- Window v2 (spec 4.1 to 4.3, gap #13, #14): the guide window. A header names the section; the card stack above
-- it (below with "cardsBelow") holds one card per step on screen, each line with a tick box, a kind icon and its
-- words; the step list under the header holds every step of the section and scrolls so the current step is the top
-- row; the footer gives the version, the level, the share of the section done, the level rail and the resize grip.
-- The layout is DESIGN.md's. Everything here follows the game by itself and works with the mouse.
--
--   Window.frame                     the window (created at NOIR_INIT)
--   Window.Refresh()                 draws what the engine says now
--   Window.Read() -> { shown, title, subtitle, range, side, preview, cards = { { badge, kind, text, mark, slide,
--       hidden, lines = { { text, icon, ticked, done, counter } } } }, list = { { n, text, dim, current, lit } },
--       footer = { version, level, share, rail = { fill, ticks } } }
--                                    kind: "current", "reminder", "detour" (Progress.Cards), "info" (route complete);
--                                    mark: the step's kind on a new current card's side bar for Theme.metrics.mark
--                                    seconds ("turnin", "accept", "train", "objective", "travel"); slide: how far the
--                                    new card still has to slide; hidden: left out because the screen has no room;
--                                    side: "above" or "below" (where the cards are); share: 0 to 100
--   Click targets for tests and the simulator: Window.Tick(cardIndex, lineIndex) -> frame, Window.Row(listIndex) ->
--       frame, Window.Header() -> frame, Window.MenuButton() -> frame, Window.Grip() -> frame, Window.Footer(),
--       Window.Card(cardIndex), Window.Line(cardIndex, lineIndex), Window.LineText(cardIndex, lineIndex) -> font
--       string, Window.ListFrame() -> the step list's scroll frame, Window.ScrollBar()
--   Window.Preview(on)               fills the window with sample content for placing (Screen.Preview)
--
-- Interfaces consumed: Progress.Cards/Place/Steps/StepState/Tick/Complete, Guide.Current/Section/Name, Text.*,
-- Why.ForStep/Words, Screen.Place/Keep/Movable/Save/Register, Options, and Noir.Menu.OpenMain() and
-- Noir.Menu.OpenStep(index), looked up at click time.
--
-- Rules: the window is the addon's own unprotected frame, so it updates in combat. No sound. No font object: fonts
-- are set by file (Theme.Font). The card slide is the window's only motion.
local Noir = Noir
local Theme, Screen, Panel = Noir.Theme, Noir.Screen, Noir.Panel

local Window = Noir.Window or {}
Noir.Window = Window

Window.DOUBLE_CLICK = 0.5   -- seconds between the two clicks of a double click on a row
Window.SLIDE_DISTANCE = 16  -- units a new current card slides in from
Window.MIN_LIST = 60        -- the least height of the step list
Window.MIN_WIDTH = 200
Window.MAX_WIDTH = 600
Window.NUMBER_WIDTH = 24    -- the step number's column in the list
Window.EMPTY_TITLE = "Choose a section"
Window.COMPLETE_TEXT = "You have reached the end of the route."
Window.TICK_TIP = "Tick to treat this line as done"
Window.UNTICK_TIP = "Untick to show this line as open again"
Window.MENU_TIP = "Menu"
Window.SKIP_TIPS = {
  skipIfMissing = "Passed when the quest is not in your quest log",
  skipIfIncomplete = "Passed when the quest is not ready to hand in",
}

-- The kind of step a new current card's side bar shows, by line kind; lower numbers are more prominent.
local PROMINENCE = { turnin = 1, accept = 2, train = 3, objective = 4, travel = 5 }
local MARK_OF = {
  turnin = "turnin", accept = "accept", train = "train",
  objective = "objective", collect = "objective", grind = "objective", vendor = "objective", manual = "objective",
  ["goto"] = "travel", fly = "travel", transport = "travel", hearth = "travel", getflight = "travel",
  sethearth = "travel",
}
local QUEST_LINK = { accept = true, turnin = true }

local frame, header, footer, list, cardsBox, grip
local parts = {}
local cardFrames = {}   -- pooled cards
local rowFrames = {}    -- pooled rows of the step list
local railTicks = {}    -- pooled level ticks
local model = nil       -- what is drawn
local previewing = false
local busy = false      -- inside a layout: size changes are ours
local collapsed = nil   -- the window shows only its header
local listHeight = nil
local textCache = {}    -- step id -> row lines, for the section in textSection
local textSection = nil
local lastPlace = nil   -- "section:index" last scrolled to
local currentId = nil   -- the step id of the current card last drawn
local slideStart, markUntil, markKind = nil, nil, nil
local side = "above"

-- ---------------------------------------------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------------------------------------------

local function metrics()
  return Theme.metrics
end

local function option(key)
  local options = Noir.Options
  if options and options.Get then return options.Get(key) end
  return nil
end

local function now()
  return GetTime and GetTime() or 0
end

local function large()
  return option("fontSize") == "large"
end

local function newText(parent, role, color, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  Theme.Font(fs, role, large())
  fs:SetTextColor(Theme.Color(color))
  fs:SetJustifyH(justify or "LEFT")
  fs:SetJustifyV("TOP")
  if fs.SetWordWrap then fs:SetWordWrap(true) end
  return fs
end

local function setText(fs, text)
  if not Theme.SetText(fs, text or "") then return 0 end
  if text == nil or text == "" then return 0 end
  return fs:GetStringHeight() or 0
end

local function texture(parent, layer, name, color)
  local tex = parent:CreateTexture(nil, layer)
  local path = Theme.Texture(name)
  if path then tex:SetTexture(path) end
  Theme.Tint(tex, color)
  return tex
end

local function escape(text)
  return (string.gsub(text, "|", "||"))
end

-- The words with named things in their meaning's color (the "highlight" option), else plain.
local function colored(text, spans)
  text = tostring(text or "")
  if option("highlight") == false or type(spans) ~= "table" or #spans == 0 then return escape(text) end
  local sorted = {}
  for i = 1, #spans do sorted[i] = spans[i] end
  table.sort(sorted, function(a, b) return a.from < b.from end)
  local out, pos = {}, 1
  for i = 1, #sorted do
    local s = sorted[i]
    if s.from >= pos and s.to >= s.from and Theme.colors[s.kind] then
      out[#out + 1] = escape(string.sub(text, pos, s.from - 1))
      out[#out + 1] = "|cff" .. Theme.Hex(s.kind) .. escape(string.sub(text, s.from, s.to)) .. "|r"
      pos = s.to + 1
    end
  end
  out[#out + 1] = escape(string.sub(text, pos))
  return table.concat(out)
end

local function openMenu(name, ...)
  local menu = Noir.Menu
  local fn = menu and menu[name]
  if type(fn) == "function" then fn(...) end
end

-- Each line kind's icon has a color of its own, the way the game marks quests: gold for taking and handing in,
-- red for what to kill, purple for items, blue for travel, green for trainers. Shape still tells them apart too.
Window.ICON_COLORS = {
  accept = "quest", turnin = "quest", objective = "enemy", kill = "enemy", item = "loot", vendor = "buy",
  trainer = "ok", xp = "ok", gossip = "friend", flight = "friend", flightpoint = "friend", hearth = "friend",
  bind = "friend", ["goto"] = "friend", error = "warning", note = "dim",
}
local function iconColor(kind, done)
  if done then return "faint" end
  return Window.ICON_COLORS[kind] or "dim"
end

local function hideTooltip()
  if GameTooltip then GameTooltip:Hide() end
end

-- From the frame's own units to UIParent units.
local function ratio()
  local ui, own = UIParent:GetEffectiveScale(), frame:GetEffectiveScale()
  if not (ui and own and ui > 0 and own > 0) then return 1 end
  return own / ui
end

-- ---------------------------------------------------------------------------------------------------------------
-- The model: what the engine says, or the preview's sample
-- ---------------------------------------------------------------------------------------------------------------

local function markOf(lines)
  local best, rank = nil, 99
  for i = 1, #lines do
    local kind = MARK_OF[lines[i].kind]
    if kind and PROMINENCE[kind] < rank then best, rank = kind, PROMINENCE[kind] end
  end
  return best
end

local function counterText(counter)
  if type(counter) ~= "table" or counter.have == nil or counter.need == nil then return nil end
  return tostring(counter.have) .. "/" .. tostring(counter.need)
end

local function cardModel(card)
  local Text, Lines = Noir.Text, Noir.Lines
  local step = card.step
  local out = { kind = card.kind, index = card.index, stepId = step.id, badge = Text.StepTitle(step), text = step.text,
    lines = {} }
  local kinds = {}
  for i = 1, #card.lines do
    local l = card.lines[i]
    local words = Text.Line(l.line, step)
    out.lines[i] = {
      text = words.text or l.text or "", icon = words.icon or l.icon or "note", spans = words.spans,
      tooltip = words.tooltip, quest = words.quest, ticked = l.ticked and true or false,
      done = (l.state == "done" or l.state == "skip"), counter = counterText(l.counter), state = l.state,
      why = l.why, lineIndex = l.index, line = l.line, kind = l.line.kind,
      tickable = l.index ~= nil and l.index > 0 and Lines.Active(l.line) and true or false,
    }
    kinds[#kinds + 1] = { kind = l.line.kind }
  end
  out.mark = markOf(kinds)
  return out
end

-- The lines of a step's row in the list: icon and words of every line the character sees.
local function rowLines(step)
  local Text, Lines = Noir.Text, Noir.Lines
  local out = {}
  for i = 1, #step.lines do
    local line = step.lines[i]
    if Lines.Check(line, step, {}) ~= "hidden" then
      local words = Text.Line(line, step)
      out[#out + 1] = { icon = words.icon or "note", text = words.text or "", spans = words.spans }
    end
  end
  return out
end

local function outleveled(step)
  local level = Noir.State and Noir.State.level
  return option("outlevel") ~= false and type(step.maxLevel) == "number" and type(level) == "number"
    and level > step.maxLevel
end

local function rail(sec)
  local State = Noir.State
  local level = type(State.level) == "number" and State.level or 1
  local low, high = sec.minLevel or 1, sec.maxLevel or sec.minLevel or 1
  local xp, most = UnitXP and UnitXP("player"), UnitXPMax and UnitXPMax("player")
  local frac = (type(xp) == "number" and type(most) == "number" and most > 0) and math.min(1, xp / most) or 0
  local span = high + 1 - low
  local fill = span > 0 and (level + frac - low) / span or 0
  if fill < 0 then fill = 0 elseif fill > 1 then fill = 1 end
  local ticks = (high - low <= 20) and (high - low) or 0
  return { fill = fill, ticks = ticks, low = low, high = high }
end

local function engineModel()
  local Guide, Progress = Noir.Guide, Noir.Progress
  local id = Guide and Guide.Current()
  local sec = id and Guide.Section(id)
  local m = { cards = {}, rows = {}, footer = nil }
  if not sec then
    m.title, m.empty = Window.EMPTY_TITLE, true
    return m
  end
  m.section, m.title, m.subtitle = id, Guide.Name(sec), sec.subgroup
  local _, index = Progress.Place()
  m.place = index
  local complete = Progress.Complete()
  if complete then
    m.cards[1] = { kind = "info", badge = "DONE", text = Window.COMPLETE_TEXT, lines = {} }
  else
    local cards = Progress.Cards()
    for k = 1, #cards do
      m.cards[k] = cardModel(cards[k])
      if cards[k].kind == "current" then m.currentId = cards[k].step.id end
    end
  end
  if textSection ~= id then
    textCache, textSection = {}, id
  end
  local steps = Progress.Steps()
  local lookahead = Progress.LOOKAHEAD_TEXT or 8
  for i = 1, #steps do
    local step = steps[i]
    local state = Progress.StepState(i)
    if state ~= "hidden" and not (state == "ahead" and outleveled(step)) then
      local cached = textCache[step.id]
      if not cached or (i >= (index or 1) and i <= (index or 1) + lookahead) then
        cached = rowLines(step)
        textCache[step.id] = cached
      end
      m.rows[#m.rows + 1] = { index = i, n = step.n, stepId = step.id, lines = cached, state = state,
        dim = complete or state == "done" or state == "behind", current = (state == "current") }
    end
  end
  local count = #steps
  local share = 0
  if complete then
    share = 100
  elseif count > 0 then
    share = math.floor(100 * ((index or 1) - 1) / count + 0.5)
  end
  m.count = count
  m.footer = { version = Noir.version, level = Noir.State.level, share = share, rail = rail(sec) }
  return m
end

local function previewModel()
  local function line(icon, text, extra)
    local l = { icon = icon, text = text, ticked = false, done = false, tickable = true, lineIndex = 1 }
    for k, v in pairs(extra or {}) do l[k] = v end
    return l
  end
  return {
    preview = true, section = nil, title = "1-6 Sample Valley", subtitle = "1-20", place = 3, count = 6,
    cards = {
      { kind = "reminder", badge = "2", lines = { line("item", "Rattlecage Bone: 2/5", { counter = "2/5" }) } },
      { kind = "current", badge = "3", text = "The quest giver stands by the crypt doors.",
        lines = { line("turnin", "Turn in Sample Quest", { done = true, ticked = true }), line("accept", "Accept Next Quest") } },
    },
    rows = {
      { index = 1, n = 1, dim = true, lines = { { icon = "accept", text = "Accept Sample Quest" } } },
      { index = 2, n = 2, dim = true, lines = { { icon = "item", text = "Rattlecage Bone: 2/5" } } },
      { index = 3, n = 3, current = true, lines = { { icon = "turnin", text = "Turn in Sample Quest" }, { icon = "accept", text = "Accept Next Quest" } } },
      { index = 4, n = 4, lines = { { icon = "kill", text = "Kill ten wolves" } } },
      { index = 5, n = 5, lines = { { icon = "goto", text = "Go to Sample Valley 40.0, 50.0" } } },
      { index = 6, n = 6, lines = { { icon = "xp", text = "Grind to level 6" } } },
    },
    footer = { version = Noir.version, level = 3, share = 33, rail = { fill = 0.4, ticks = 5 } },
  }
end

-- ---------------------------------------------------------------------------------------------------------------
-- Tooltips
-- ---------------------------------------------------------------------------------------------------------------

local function knownQuest(id)
  local Text = Noir.Text
  return type(id) == "number" and Text.QuestName(id) ~= ("Quest " .. tostring(id))
end

local function lineTooltip(owner, l)
  if not (GameTooltip and l) then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  local linked = false
  if QUEST_LINK[l.kind] and knownQuest(l.quest) and GameTooltip.SetHyperlink then
    linked = pcall(GameTooltip.SetHyperlink, GameTooltip, "quest:" .. tostring(l.quest))
  end
  if not linked then GameTooltip:SetText(l.text or "") end
  if type(l.tooltip) == "table" then
    for i = 1, #l.tooltip do GameTooltip:AddLine(l.tooltip[i]) end
  end
  if l.state == "skip" and l.why then
    GameTooltip:AddLine("Passed: " .. tostring(l.why))
  end
  local line = l.line
  if type(line) == "table" then
    for key, words in pairs(Window.SKIP_TIPS) do
      if line[key] then GameTooltip:AddLine(words) end
    end
  end
  GameTooltip:Show()
end

local function rowTooltip(owner, row)
  if not (GameTooltip and row and row.stepId and model and model.section) then return end
  local entry = Noir.Why.ForStep(model.section, row.stepId)
  if not entry then
    hideTooltip()
    return
  end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetText(string.format("Step %s: %s", tostring(row.n), Noir.Why.Words(entry.kind)))
  if entry.text and entry.text ~= "" then GameTooltip:AddLine(entry.text) end
  GameTooltip:Show()
end

-- ---------------------------------------------------------------------------------------------------------------
-- Building the frames
-- ---------------------------------------------------------------------------------------------------------------

-- A child that takes the mouse moves the window when dragged, as the window's body does.
local function forwardDrag(child)
  child:RegisterForDrag("LeftButton")
  child:SetScript("OnDragStart", function()
    local fn = frame:GetScript("OnDragStart")
    if fn then fn(frame, "LeftButton") end
  end)
  child:SetScript("OnDragStop", function()
    local fn = frame:GetScript("OnDragStop")
    if fn then fn(frame) end
  end)
end

local function newLineRow(card)
  local m = metrics()
  local row = CreateFrame("Frame", nil, card)
  row:EnableMouse(true)
  forwardDrag(row)
  row.tick = CreateFrame("Button", nil, row)
  row.tick:SetSize(m.tick, m.tick)
  row.tick:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
  row.tick.box = texture(row.tick, "ARTWORK", "box", "faint")
  row.tick.box:SetAllPoints(row.tick)
  row.tick.mark = texture(row.tick, "OVERLAY", "tick", "lamp")
  row.tick.mark:SetAllPoints(row.tick)
  row.icon = texture(row, "ARTWORK", "icon-note", "dim")
  row.icon:SetSize(m.icon, m.icon)
  row.text = newText(row, "body", "paper")
  row:SetScript("OnEnter", function(self) lineTooltip(self, self.model) end)
  row:SetScript("OnLeave", hideTooltip)
  row.tick:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local l = self:GetParent().model
    GameTooltip:SetText((l and l.ticked) and Window.UNTICK_TIP or Window.TICK_TIP)
    GameTooltip:Show()
  end)
  row.tick:SetScript("OnLeave", hideTooltip)
  row.tick:SetScript("OnClick", function(self)
    local r = self:GetParent()
    local l, c = r.model, r:GetParent().model
    if not (l and c and l.tickable) or (model and model.preview) then return end
    Noir.Progress.Tick(c.index, l.lineIndex, not l.ticked)
    Window.Refresh()
  end)
  return row
end

local function newCard()
  local m = metrics()
  local card = CreateFrame("Frame", nil, cardsBox)
  card:EnableMouse(true)
  forwardDrag(card)
  card:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then openMenu("OpenMain", frame) end
  end)
  card.bg = card:CreateTexture(nil, "BACKGROUND")
  Theme.Paint(card.bg, "strip")
  card.bg:SetAllPoints(card)
  card.bar = card:CreateTexture(nil, "BORDER")
  Theme.Paint(card.bar, "lamp")
  card.bar:SetWidth(m.lamp)
  card.bar:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
  card.bar:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 0, 0)
  card.badge = newText(card, "kicker", "lamp")
  card.text = newText(card, "body", "dim")
  card.lines = {}
  return card
end

local function newRow()
  local m = metrics()
  local row = CreateFrame("Button", nil, list.child)
  if row.RegisterForClicks then row:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  forwardDrag(row)
  row.glow = row:CreateTexture(nil, "BACKGROUND")
  Theme.Paint(row.glow, "strip")
  row.glow:SetAllPoints(row)
  row.glow:Hide()
  row.bar = row:CreateTexture(nil, "ARTWORK")
  Theme.Paint(row.bar, "lamp")
  row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
  row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
  row.bar:SetWidth(3)
  row.bar:Hide()
  row.number = newText(row, "small", "faint", "RIGHT")
  row.icons, row.texts = {}, {}
  local function open(self)
    self.lastClick = nil
    if model and not model.preview and self.model then openMenu("OpenStep", self.model.index) end
  end
  row:SetScript("OnClick", function(self, button)
    if button == "RightButton" then
      open(self)
      return
    end
    local t = now()
    if self.lastClick and t - self.lastClick <= Window.DOUBLE_CLICK then
      open(self)
    else
      self.lastClick = t
    end
  end)
  row:SetScript("OnDoubleClick", function(self)
    if self.lastClick and now() - self.lastClick <= Window.DOUBLE_CLICK then open(self) end
  end)
  row:SetScript("OnEnter", function(self)
    self.lit = true
    self.glow:Show()
    self:SetAlpha(1)
    rowTooltip(self, self.model)
  end)
  row:SetScript("OnLeave", function(self)
    self.lit = false
    self.glow:Hide()
    self:SetAlpha((self.model and self.model.dim) and 0.5 or 1)
    hideTooltip()
  end)
  row.number:SetWidth(Window.NUMBER_WIDTH)
  return row
end

local function create()
  local m = metrics()
  frame = CreateFrame("Frame", nil, UIParent)
  Window.frame = frame
  frame:SetFrameStrata("MEDIUM")
  frame:SetSize(m.width, m.header + m.list + m.footer)
  frame:SetScale(option("windowScale") or 1)
  frame:EnableMouse(true)
  local bay = frame:CreateTexture(nil, "BACKGROUND")
  Theme.Paint(bay, "bay", m.alpha)
  bay:SetAllPoints(frame)
  -- a one-pixel border, so the window reads as one panel against the world; in the class color with that accent
  for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
      { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
    local edge = frame:CreateTexture(nil, "BORDER")
    Theme.Paint(edge, Theme.Border())
    edge:SetPoint(side[1], frame, side[1], 0, 0)
    edge:SetPoint(side[2], frame, side[2], 0, 0)
    if side[3] then edge:SetHeight(1) else edge:SetWidth(1) end
  end

  header = CreateFrame("Frame", nil, frame)
  header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
  header:SetHeight(m.header)
  header:EnableMouse(true)
  -- the header is its own band, with a lamp line under it: the section name is the window's title
  local band = header:CreateTexture(nil, "BACKGROUND")
  Theme.Paint(band, "strip")
  band:SetAllPoints(header)
  local rule = header:CreateTexture(nil, "BORDER")
  Theme.Paint(rule, "lamp", 0.8)
  rule:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
  rule:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
  rule:SetHeight(1)
  forwardDrag(header)
  header:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then openMenu("OpenMain", frame) end
  end)
  parts.title = newText(header, "name", "paper")
  parts.title:SetPoint("TOPLEFT", header, "TOPLEFT", m.pad, -m.gap)
  if parts.title.SetMaxLines then parts.title:SetMaxLines(1) end
  parts.subtitle = newText(header, "small", "dim")
  parts.subtitle:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", m.pad, m.gap)
  parts.range = newText(header, "small", "dim", "RIGHT")
  parts.range:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -m.pad, m.gap)
  parts.menu = CreateFrame("Button", nil, header)
  parts.menu:SetSize(m.icon + m.gap, m.icon + m.gap)
  parts.menu:SetPoint("TOPRIGHT", header, "TOPRIGHT", -m.gap, -m.gap)
  parts.menu.icon = texture(parts.menu, "ARTWORK", "menu", "dim")
  parts.menu.icon:SetAllPoints(parts.menu)
  parts.menu:SetScript("OnClick", function() openMenu("OpenMain", frame) end)
  parts.menu:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(Window.MENU_TIP)
    GameTooltip:Show()
  end)
  parts.menu:SetScript("OnLeave", hideTooltip)

  footer = CreateFrame("Frame", nil, frame)
  footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
  footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
  footer:SetHeight(m.footer)
  footer:EnableMouse(true)
  local footBand = footer:CreateTexture(nil, "BACKGROUND")
  Theme.Paint(footBand, "strip", 0.7)
  footBand:SetAllPoints(footer)
  forwardDrag(footer)
  footer:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then openMenu("OpenMain", frame) end
  end)
  parts.version = newText(footer, "small", "dim")
  parts.version:SetPoint("TOPLEFT", footer, "TOPLEFT", m.pad, -m.gap)
  parts.level = newText(footer, "small", "dim", "CENTER")
  parts.level:SetPoint("TOP", footer, "TOP", 0, -m.gap)
  parts.track = footer:CreateTexture(nil, "BORDER")
  Theme.Paint(parts.track, "track")
  parts.track:SetHeight(m.rail)
  parts.track:SetPoint("BOTTOMLEFT", footer, "BOTTOMLEFT", m.pad, m.gap)
  parts.track:SetPoint("BOTTOMRIGHT", footer, "BOTTOMRIGHT", -m.pad, m.gap)
  parts.fill = footer:CreateTexture(nil, "ARTWORK")
  Theme.Paint(parts.fill, "lamp")
  parts.fill:SetHeight(m.rail)
  parts.fill:SetPoint("BOTTOMLEFT", footer, "BOTTOMLEFT", m.pad, m.gap)

  list = Panel.ScrollList(frame, { step = 3 * (Theme.sizes.body + 2 * m.gap) })
  list.frame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
  list.frame:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", 0, 0)
  list.onScroll = function() Window.UpdateRange() end

  cardsBox = CreateFrame("Frame", nil, frame)
  cardsBox:SetSize(m.width, 1)
  if cardsBox.SetClipsChildren then cardsBox:SetClipsChildren(true) end

  grip = Screen.Movable(frame, "window", { resizable = true, minWidth = Window.MIN_WIDTH,
    minHeight = m.header + Window.MIN_LIST + m.footer })
  if grip then
    grip.icon = texture(grip, "ARTWORK", "grip", "faint")
    grip.icon:SetAllPoints(grip)
    -- the grip lights up under the mouse, so it can be found
    grip:HookScript("OnEnter", function() Theme.Tint(grip.icon, "lamp") end)
    grip:HookScript("OnLeave", function() Theme.Tint(grip.icon, "faint") end)
    grip:HookScript("OnDragStop", function() Window.AfterMove() end)
  end
  frame:HookScript("OnDragStop", function() Window.AfterMove() end)
  frame:HookScript("OnSizeChanged", function(self)
    if busy then return end
    if not collapsed then
      listHeight = math.max(Window.MIN_LIST, (self:GetHeight() or 0) - m.header - m.footer)
    end
    Window.Layout()
  end)
  frame:HookScript("OnShow", function(self)
    if option("windowHidden") and not previewing then self:Hide() end
  end)
  Screen.Place(frame, "window")
  Screen.Register("window", frame, Window.Preview)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------------------------------------------

-- The list height saved in the profile (the window's saved height less the header and footer), else the default.
local function loadSize()
  local m = metrics()
  local pos = Noir.Options and Noir.Options.Position("window")
  local width = pos and pos[5] or m.width
  if width < Window.MIN_WIDTH then width = Window.MIN_WIDTH elseif width > Window.MAX_WIDTH then width = Window.MAX_WIDTH end
  listHeight = pos and pos[6] and math.max(Window.MIN_LIST, pos[6] - m.header - m.footer) or m.list
  busy = true
  frame:SetWidth(width)
  busy = false
end

-- The height of the whole window with the step list shown.
local function fullHeight()
  local m = metrics()
  return m.header + (listHeight or m.list) + m.footer
end

local function layoutCard(card, c, width)
  local m = metrics()
  card.model = c
  card:SetWidth(width)
  local y = m.gap * 2
  local left = m.lamp + m.pad
  local inner = width - left - m.pad
  card.badge:ClearAllPoints()
  card.badge:SetPoint("TOPLEFT", card, "TOPLEFT", left, -y)
  card.badge:SetWidth(inner)
  y = y + setText(card.badge, string.upper(tostring(c.badge or ""))) + m.gap
  if c.text and c.text ~= "" then
    card.text:ClearAllPoints()
    card.text:SetPoint("TOPLEFT", card, "TOPLEFT", left, -y)
    card.text:SetWidth(inner)
    y = y + setText(card.text, escape(c.text)) + m.gap
    card.text:Show()
  else
    setText(card.text, "")
    card.text:Hide()
  end
  for i = 1, math.max(#c.lines, #card.lines) do
    local l = c.lines[i]
    local row = card.lines[i]
    if l then
      if not row then
        row = newLineRow(card)
        card.lines[i] = row
      end
      row.model = l
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", card, "TOPLEFT", left, -y)
      row:SetWidth(inner)
      local textLeft = m.tick + m.gap + m.icon + m.gap
      if l.tickable then
        row.tick:Show()
        Theme.Tint(row.tick.box, (l.ticked or l.done) and "lamp" or "faint")
        if l.ticked or l.done then row.tick.mark:Show() else row.tick.mark:Hide() end
      else
        row.tick:Hide()
      end
      local path = Theme.Icon(l.icon)
      if path then row.icon:SetTexture(path) end
      Theme.Tint(row.icon, iconColor(l.icon, l.done))
      row.icon:ClearAllPoints()
      row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", m.tick + m.gap, 0)
      row.text:ClearAllPoints()
      row.text:SetPoint("TOPLEFT", row, "TOPLEFT", textLeft, 0)
      row.text:SetWidth(math.max(1, inner - textLeft))
      row.text:SetTextColor(Theme.Color(l.done and "dim" or "paper"))
      local h = math.max(m.tick, setText(row.text, colored(l.text, l.spans)))
      row:SetHeight(h)
      row:Show()
      y = y + h + m.gap
    elseif row then
      row.model = nil
      row:Hide()
    end
  end
  local height = y + m.gap
  card:SetHeight(height)
  return height
end

local function barColor(c, isNew)
  if c.kind == "info" then return "ok" end
  if c.kind ~= "current" then return "faint" end
  if isNew and markKind and markUntil and now() < markUntil then return Theme.MARKS[markKind] or "lamp" end
  return "lamp"
end

local function slideOffset()
  if not slideStart then return 0 end
  local duration = metrics().slide
  local t = (now() - slideStart) / duration
  if t >= 1 then
    slideStart = nil
    return 0
  end
  return Window.SLIDE_DISTANCE * (1 - t)
end

-- Places the cards above or below the window, flipping or leaving out the farthest cards when the screen has no
-- room, and the slide of a new current card.
local function placeCards()
  local m = metrics()
  local cards = model and model.cards or {}
  if collapsed == "empty" or #cards == 0 then
    cardsBox:Hide()
    return
  end
  local width = frame:GetWidth()
  local heights, total = {}, 0
  for k = 1, #cards do
    local card = cardFrames[k]
    heights[k] = card:GetHeight()
    total = total + heights[k] + (k > 1 and m.gap or 0)
  end
  local screenTop = UIParent:GetHeight() / ratio()
  local top, bottom = frame:GetTop() or 0, frame:GetBottom() or 0
  local above, below = screenTop - top - m.gap, bottom - m.gap
  local want = option("cardsBelow") and "below" or "above"
  local other = want == "above" and "below" or "above"
  local room = { above = above, below = below }
  if total <= room[want] then
    side = want
  elseif total <= room[other] then
    side = other
  else
    side = room[want] >= room[other] and want or other
  end
  -- Leave out the cards farthest from the window (the first ones) until the rest fit; the current card stays.
  local first = 1
  local used = total
  while used > room[side] and first < #cards do
    used = used - heights[first] - m.gap
    first = first + 1
  end
  local boxHeight = math.max(1, math.min(used, math.max(room[side], 1)))
  cardsBox:ClearAllPoints()
  cardsBox:SetSize(width, boxHeight)
  if side == "above" then
    cardsBox:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, m.gap)
  else
    cardsBox:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -m.gap)
  end
  local slide = slideOffset()
  local y = 0
  -- Nearest the window first: the current card (the last one), then up the stack.
  for k = #cards, 1, -1 do
    local card = cardFrames[k]
    local c = cards[k]
    c.hidden = k < first or nil
    if k < first then
      card:Hide()
    else
      local x = (c.kind == "current" and c.stepId == currentId) and slide or 0
      card:ClearAllPoints()
      if side == "above" then
        card:SetPoint("BOTTOMLEFT", cardsBox, "BOTTOMLEFT", x, y)
      else
        card:SetPoint("TOPLEFT", cardsBox, "TOPLEFT", x, -y)
      end
      c.slide = x
      Theme.Paint(card.bar, barColor(c, c.stepId == currentId))
      card:Show()
      y = y + heights[k] + m.gap
    end
  end
  cardsBox:Show()
end

local function animating()
  return slideStart ~= nil or (markUntil ~= nil and now() < markUntil)
end

local function startMotion()
  cardsBox:SetScript("OnUpdate", function(self)
    placeCards()
    if not animating() then
      markUntil = nil
      placeCards()
      self:SetScript("OnUpdate", nil)
    end
  end)
end

local function layoutRows()
  local m = metrics()
  local rows = model.rows or {}
  local width = math.max(1, frame:GetWidth() - 4)
  local textLeft = m.pad + m.icon + m.gap
  local textWidth = math.max(1, width - textLeft - Window.NUMBER_WIDTH - m.gap)
  local y = 0
  local currentTop = nil
  for i = 1, math.max(#rows, #rowFrames) do
    local r = rows[i]
    local row = rowFrames[i]
    if r then
      if not row then
        row = newRow()
        rowFrames[i] = row
      end
      row.model = r
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", list.child, "TOPLEFT", 0, -y)
      row:SetWidth(width)
      row.number:ClearAllPoints()
      row.number:SetPoint("TOPRIGHT", row, "TOPRIGHT", -m.gap, -m.gap)
      setText(row.number, tostring(r.n or ""))
      local ly = m.gap
      for k = 1, math.max(#r.lines, #row.texts) do
        local l = r.lines[k]
        local icon, text = row.icons[k], row.texts[k]
        if l then
          if not icon then
            icon = texture(row, "ARTWORK", "icon-note", "dim")
            icon:SetSize(m.icon, m.icon)
            row.icons[k] = icon
            text = newText(row, "body", "paper")
            row.texts[k] = text
          end
          local path = Theme.Icon(l.icon)
          if path then icon:SetTexture(path) end
          Theme.Tint(icon, iconColor(l.icon, r.dim))
          icon:ClearAllPoints()
          icon:SetPoint("TOPLEFT", row, "TOPLEFT", m.pad, -ly)
          icon:Show()
          text:ClearAllPoints()
          text:SetPoint("TOPLEFT", row, "TOPLEFT", textLeft, -ly)
          text:SetWidth(textWidth)
          local h = math.max(m.icon, setText(text, colored(l.text, l.spans)))
          text:Show()
          ly = ly + h + 1
        elseif icon then
          icon:Hide()
          setText(text, "")
          text:Hide()
        end
      end
      local height = ly + m.gap
      row:SetHeight(height)
      row.top, row.height = y, height
      if r.current then currentTop = y end
      -- the current step stands out: a lit background and the lamp bar on its left edge
      if r.current then row.bar:Show() else row.bar:Hide() end
      if row.lit or r.current then
        row.glow:Show()
        row:SetAlpha(1)
      else
        row.glow:Hide()
        row:SetAlpha(r.dim and 0.5 or 1)
      end
      row:Show()
      y = y + height
    elseif row then
      row.model, row.lit = nil, false
      row:Hide()
    end
  end
  return y, currentTop
end

-- The range of step numbers in view, in the header.
function Window.UpdateRange()
  if not (model and parts.range) then return end
  local rows = model.rows or {}
  local text = ""
  if #rows > 0 and not collapsed then
    local offset, view = list:Offset(), list:View()
    local first, last
    for i = 1, #rows do
      local row = rowFrames[i]
      if row and row.top then
        if not first and row.top + row.height > offset + 0.5 then first = rows[i].n end
        if row.top < offset + view - 0.5 then last = rows[i].n end
      end
    end
    if first and last then text = string.format("Steps %s-%s of %s", tostring(first), tostring(last), tostring(model.count or #rows)) end
  end
  model.range = text
  setText(parts.range, text)
end

local function layoutFooter()
  local m = metrics()
  local f = model.footer
  if not f then return end
  setText(parts.version, tostring(f.version or ""))
  setText(parts.level, string.format("Level %s, %d%% done", tostring(f.level or "?"), f.share or 0))
  local width = math.max(1, frame:GetWidth() - 2 * m.pad)
  local r = f.rail or { fill = 0, ticks = 0 }
  parts.fill:SetWidth(math.max(0.01, width * (r.fill or 0)))
  if (r.fill or 0) <= 0 then parts.fill:Hide() else parts.fill:Show() end
  local ticks = r.ticks or 0
  for i = 1, math.max(ticks, #railTicks) do
    local tick = railTicks[i]
    if i <= ticks then
      if not tick then
        tick = footer:CreateTexture(nil, "OVERLAY")
        Theme.Paint(tick, "bay")
        tick:SetSize(1, m.rail)
        railTicks[i] = tick
      end
      tick:ClearAllPoints()
      tick:SetPoint("BOTTOMLEFT", footer, "BOTTOMLEFT", m.pad + width * i / (ticks + 1), m.gap)
      tick:Show()
    elseif tick then
      tick:Hide()
    end
  end
end

-- Lays the window out for the model: header, cards, list, footer, and the window's height.
function Window.Layout()
  if not (frame and model) then return end
  local m = metrics()
  busy = true
  local width = frame:GetWidth()
  setText(parts.title, escape(model.title or ""))
  parts.title:SetWidth(math.max(1, width - 2 * m.pad - m.icon - 2 * m.gap))
  setText(parts.subtitle, escape(model.subtitle or ""))
  local showList = not model.empty and option("stepList") ~= false
  collapsed = model.empty and "empty" or (not showList and "list") or nil
  -- The window is never taller than the screen allows.
  local most = Screen.MAX_SHARE * UIParent:GetHeight() / ratio()
  if listHeight and m.header + listHeight + m.footer > most then
    listHeight = math.max(Window.MIN_LIST, most - m.header - m.footer)
  end
  if collapsed then
    frame:SetHeight(m.header)
    list.frame:Hide()
    list.bar:Hide()
    footer:Hide()
    if grip then grip:Hide() end
  else
    frame:SetHeight(fullHeight())
    list.frame:Show()
    footer:Show()
    if grip then grip:Show() end
  end
  -- Cards
  local cards = model.cards or {}
  for k = 1, math.max(#cards, #cardFrames) do
    local c = cards[k]
    local card = cardFrames[k]
    if c and collapsed ~= "empty" then
      if not card then
        card = newCard()
        cardFrames[k] = card
      end
      layoutCard(card, c, width)
    elseif card then
      card.model = nil
      card:Hide()
    end
  end
  placeCards()
  -- The step list
  if not collapsed then
    local height, currentTop = layoutRows()
    list.min = (option("hideFinished") and currentTop) or 0
    list:SetContentHeight(height)
    local key = tostring(model.section) .. ":" .. tostring(model.place)
    if key ~= lastPlace and currentTop then
      lastPlace = key
      list:Scroll(currentTop)
    else
      list:Scroll(list:Offset())
    end
    layoutFooter()
  else
    for i = 1, #rowFrames do rowFrames[i]:Hide() end
  end
  Window.UpdateRange()
  busy = false
end

-- ---------------------------------------------------------------------------------------------------------------
-- Refresh, read, preview
-- ---------------------------------------------------------------------------------------------------------------

function Window.Refresh()
  if not frame then return end
  model = previewing and previewModel() or engineModel()
  -- A new current card slides in and marks its kind.
  local newId = model.currentId
  if model.preview then
    -- The sample changes nothing: the real current card does not slide in again afterwards.
  elseif newId and newId ~= currentId then
    currentId = newId
    slideStart = now()
    markUntil = now() + metrics().mark
    for k = 1, #model.cards do
      if model.cards[k].stepId == newId then markKind = model.cards[k].mark end
    end
  elseif not newId then
    currentId = nil
  end
  Window.Layout()
  if animating() then startMotion() end
end

-- Saves the window's place after a move or resize; while it shows only its header the saved height stays the
-- full window's, so the step list keeps its height.
function Window.AfterMove()
  if not frame then return end
  if collapsed and Noir.Options then
    local pos = Noir.Options.Position("window")
    if pos then
      pos[5], pos[6] = frame:GetWidth(), fullHeight()
      Noir.Options.SavePosition("window", pos)
    end
  end
  placeCards()
end

local function applyScale()
  local scale = option("windowScale") or 1
  if frame:GetScale() == scale then return end
  local left, top = frame:GetLeft(), frame:GetTop()
  local before = frame:GetEffectiveScale()
  frame:SetScale(scale)
  if left and top then
    local after = frame:GetEffectiveScale()
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * before / after, top * before / after)
  end
  Screen.Pull(frame)
  Screen.Save(frame, "window")
  Window.AfterMove()
  Window.Layout()
end

local function applyHidden()
  if option("windowHidden") and not previewing then
    frame:Hide()
  elseif Screen.Allowed() then
    frame:Show()
  end
end

function Window.Preview(on)
  previewing = on and true or false
  if not frame then return end
  applyHidden()
  Window.Refresh()
end

local function readCard(c)
  local lines = {}
  for i = 1, #c.lines do
    local l = c.lines[i]
    lines[i] = { text = l.text, icon = l.icon, ticked = l.ticked and true or false, done = l.done and true or false,
      counter = l.counter }
  end
  local mark = nil
  if c.kind == "current" and c.stepId == currentId and markUntil and now() < markUntil then mark = markKind end
  return { badge = c.badge, kind = c.kind, text = c.text, mark = mark, slide = c.slide or 0, hidden = c.hidden,
    lines = lines }
end

function Window.Read()
  if not (frame and model) then return { shown = false, cards = {}, list = {} } end
  local cards, rows = {}, {}
  if model.cards and collapsed ~= "empty" then
    -- The slide is read as it is now.
    if slideStart then placeCards() end
    for k = 1, #model.cards do cards[k] = readCard(model.cards[k]) end
  end
  if not collapsed then
    for i = 1, #(model.rows or {}) do
      local r = model.rows[i]
      local texts = {}
      for k = 1, #r.lines do texts[k] = r.lines[k].text end
      local row = rowFrames[i]
      rows[i] = { n = r.n, text = table.concat(texts, "\n"), dim = r.dim and true or false,
        current = r.current and true or false, lit = (row and row.lit) and true or false }
    end
  end
  return {
    shown = frame:IsShown() and true or false, title = model.title, subtitle = model.subtitle, range = model.range,
    side = side, preview = model.preview or nil, cards = cards, list = rows, footer = model.footer,
  }
end

-- ---------------------------------------------------------------------------------------------------------------
-- Click targets
-- ---------------------------------------------------------------------------------------------------------------

function Window.Card(cardIndex)
  return cardFrames[cardIndex]
end

function Window.Line(cardIndex, lineIndex)
  local card = cardFrames[cardIndex]
  return card and card.lines[lineIndex]
end

function Window.LineText(cardIndex, lineIndex)
  local row = Window.Line(cardIndex, lineIndex)
  return row and row.text
end

function Window.Tick(cardIndex, lineIndex)
  local row = Window.Line(cardIndex, lineIndex)
  return row and row.tick
end

function Window.Row(listIndex)
  return rowFrames[listIndex]
end

function Window.Header()
  return header
end

function Window.Footer()
  return footer
end

function Window.MenuButton()
  return parts.menu
end

function Window.Grip()
  return grip
end

function Window.ListFrame()
  return list and list.frame
end

function Window.ScrollBar()
  return list and list.bar
end

-- ---------------------------------------------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------------------------------------------

local REFRESH_OPTIONS = { highlight = true, stepList = true, hideFinished = true, cardsBelow = true, outlevel = true }

Noir.On("NOIR_INIT", function()
  if not frame then create() end
  loadSize()
  Window.Refresh()
  applyHidden()
end)
Noir.On("NOIR_PROFILE", function()
  if not frame then return end
  loadSize()
  applyScale()
  Window.Refresh()
  applyHidden()
end)
Noir.On("NOIR_OPTION", function(_, key)
  if not frame then return end
  if key == "windowScale" then
    applyScale()
  elseif key == "windowHidden" then
    applyHidden()
  elseif REFRESH_OPTIONS[key] then
    if key == "hideFinished" then lastPlace = nil end
    Window.Refresh()
  end
end)
for _, event in ipairs({ "NOIR_STEP", "NOIR_PLACE", "NOIR_SECTION", "NOIR_READY", "NOIR_ROUTE_DONE",
  "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP" }) do
  Noir.On(event, function() Window.Refresh() end)
end
for _, event in ipairs({ "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED" }) do
  Noir.On(event, function()
    if frame and model then Window.Layout() end
  end)
end
