-- Noir Guides, GPLv3. See LICENSE.
-- Diagnostics (gap #39): /noir bug. Everything a bug report needs, in a box the player can select and copy from:
-- the addon's and the client's versions, the character, the route file, the section (ID, name and how it was
-- chosen), the place (index and step ID), every card on screen with each line's state and evidence, the reminders
-- open, what the window shows, the position, the quest log, flight points and hearthstone, professions, talents, the
-- automation switches, the options that differ from the defaults, the profile, the screen size and UI scale, the
-- why-log, the problems and the errors the addon reported.
--
--   Diagnostics.Lines([stepIndex]) -> the report as lines; stepIndex (from the step menu's "Report a problem with
--                                  this step") adds the step it was asked about
--   Diagnostics.Open([stepIndex]), .Close(), .Read() -> { shown, text }
--   Diagnostics.Report()         opens the report and says in chat how to copy it: /noir bug, the main menu's
--                                "Report a problem" and the settings' button
--   Diagnostics.box              the edit box (nil until first opened)
--
-- The window opens at Screen.DEFAULTS.dialog, is kept on the screen and registered as "bug". The box is an EditBox
-- given a font by file with SetFont, as the window's font strings are; it never gets a font object (SetFontObject on
-- an edit box crashes the Forever client). Typing does not change the report.
local Noir = Noir
local State, Routes, Why, Panel, Theme, Screen = Noir.State, Noir.Routes, Noir.Why, Noir.Panel, Noir.Theme, Noir.Screen

local Diagnostics = {}
Noir.Diagnostics = Diagnostics

local WIDTH, BOX_HEIGHT = 420, 260
local KEPT_ERRORS = 10
local WHY_SHOWN = 8

-- Errors the addon hands to the client's error handler through Noir.ReportError, newest last.
local errors = {}
local report = Noir.ReportError
Noir.ReportError = function(err)
  errors[#errors + 1] = tostring(err)
  while #errors > KEPT_ERRORS do table.remove(errors, 1) end
  report(err)
end

-- ---------------------------------------------------------------------------------------------------------------
-- The report
-- ---------------------------------------------------------------------------------------------------------------

local function firstLine(text)
  return (string.match(tostring(text), "^[^\n]*"))
end

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

local function onOff(value)
  return value and "on" or "off"
end

-- The key a line is about, for the report: its quest, item, level, node or place.
local function lineKey(line)
  if line.quest then return tostring(line.quest) end
  if line.item then return "item " .. tostring(line.item) end
  if line.kind == "grind" then return "level " .. tostring(line.level) .. (line.percent and (" " .. line.percent .. "%") or "") end
  if line.node then return "node " .. tostring(line.node) end
  if line.to and type(line.to) ~= "table" then return "to node " .. tostring(line.to) end
  if line.spell then return "spell " .. tostring(line.spell) end
  if line.skill then return "skill " .. tostring(line.skill) .. " rank " .. tostring(line.rank) end
  if line.class then return tostring(line.class) .. " level " .. tostring(line.level) end
  if line.npc then return "npc " .. tostring(line.npc) end
  local at = line.at or line.to
  if type(at) == "table" then return string.format("zone %s %.1f, %.1f", tostring(at.zone), at.x or 0, at.y or 0) end
  return ""
end

-- Spec 2.6 and gap #39: the section, how it was chosen, the place, every card with each line's state and evidence,
-- and the reminders open. stepIndex: the step the step menu's report was asked about.
local function guideLines(add, stepIndex)
  local Guide, Progress = Noir.Guide, Noir.Progress
  local id = Guide and Guide.Current()
  local section = id and Guide.Section(id)
  if not section then
    add("Section: none")
    add("Place: none")
    return
  end
  local how = Noir.char and Noir.char.guide and Noir.char.guide.how
  add(string.format("Section: %s (%s), chosen %s", id, tostring(Guide.Name(section)), tostring(how or "unknown")))
  local placed, index, count, step = Progress.Place()
  if placed == id and step then
    add(string.format("Place: step %d of %d, %s", index, count, tostring(step.id)))
  else
    add("Place: none")
  end
  if stepIndex then
    local steps = Progress.Steps()
    local asked = steps[stepIndex]
    add(string.format("Reported step: %s %s", tostring(stepIndex), asked and tostring(asked.id) or "(not in the section)"))
  end
  local open = {}
  for _, card in ipairs(Progress.Cards()) do
    if card.kind == "reminder" then open[#open + 1] = tostring(card.step.id) end
    add(string.format("Card %s %s:", tostring(card.kind), tostring(card.step.id)))
    for _, l in ipairs(card.lines) do
      local line = l.line or {}
      local words = string.format("  %s %s %s: %s", tostring(l.index), tostring(line.kind), lineKey(line), tostring(l.state))
      words = string.gsub(words, " +:", ":", 1)
      if l.ticked then words = words .. ", ticked" end
      if l.counter and l.counter[1] and l.counter[2] then words = words .. string.format(" %s/%s", tostring(l.counter[1]), tostring(l.counter[2])) end
      if l.why then words = words .. " (" .. tostring(l.why) .. ")" end
      add(words)
    end
  end
  add("Reminders open: " .. (#open > 0 and table.concat(open, ", ") or "none"))
end

local function valueText(value)
  if type(value) == "number" then
    if value == math.floor(value) then return string.format("%d", value) end
    return (string.gsub(string.format("%.3f", value), "0+$", ""))
  end
  return tostring(value)
end

-- The options that differ from the defaults, the profile, the screen's size and the UI scale.
local function settingsLines(add)
  local Options = Noir.Options
  if Options and Options.DEFAULTS then
    local changed = {}
    for _, key in ipairs(sortedKeys(Options.DEFAULTS)) do
      local value = Options.Get(key)
      if value ~= Options.DEFAULTS[key] then changed[#changed + 1] = key .. " = " .. valueText(value) end
    end
    add("Options changed: " .. (#changed > 0 and table.concat(changed, ", ") or "none"))
    add("Profile: " .. tostring(Options.Profile()))
  end
  local width, height = GetScreenWidth and GetScreenWidth(), GetScreenHeight and GetScreenHeight()
  local scale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()
  local physical = ""
  if GetPhysicalScreenSize then
    local w, h = GetPhysicalScreenSize()
    if w and h then physical = string.format("%dx%d pixels, ", w, h) end
  end
  add(string.format("Screen: %s%s x %s interface units, UI scale %s", physical, valueText(math.floor((width or 0) + 0.5)),
    valueText(math.floor((height or 0) + 0.5)), scale and valueText(scale) or "unknown"))
end

function Diagnostics.Lines(stepIndex)
  local lines = {}
  local function add(text) lines[#lines + 1] = text end

  add("Noir Guides " .. tostring(Noir.version) .. " bug report")
  if GetBuildInfo then
    local version, build, _, interface = GetBuildInfo()
    add(string.format("Client: %s (%s), interface %s", tostring(version), tostring(build), tostring(interface)))
  else
    add("Client: unknown (no GetBuildInfo)")
  end
  add(string.format("Character: %s %s (%s), level %d", tostring(State.race), tostring(State.class), tostring(State.faction), State.level or 0))

  add("Route: " .. tostring(Routes.Current() or "none"))
  guideLines(add, stepIndex)
  if Noir.Window and Noir.Window.Read then
    local shown = Noir.Window.Read()
    add(string.format("Window: %s | %s | %s%s", tostring(shown.title), tostring(shown.subtitle), tostring(shown.range), shown.shown and "" or " (hidden)"))
  end

  local zone, x, y, uiMap = State.Position()
  if x then
    add(string.format("Position: zone %s at %.1f, %.1f (map %s)%s", tostring(zone), x, y, tostring(uiMap), State.OnTaxi() and ", on a flight" or ""))
  else
    add("Position: unknown")
  end

  local quests = {}
  for _, id in ipairs(sortedKeys(State.quests)) do
    local q = State.quests[id]
    quests[#quests + 1] = id .. (q.complete and "c" or "") .. (q.failed and "f" or "")
  end
  add(string.format("Quest log (%d): %s%s", #quests, table.concat(quests, " "), State.logHidden and " (part of the log is collapsed)" or ""))
  local known = sortedKeys(State.flights)
  add(string.format("Flight points (%d): %s", #known, table.concat(known, " ")))
  add("Hearthstone: " .. (State.hearth and tostring(State.hearth.name) or "unknown"))

  if Noir.Professions then
    local parts = {}
    local have = Noir.Professions.Known()
    for _, skillLine in ipairs(sortedKeys(have)) do
      local p = have[skillLine]
      parts[#parts + 1] = string.format("%s %d/%d", tostring(p.name), p.rank, p.max)
    end
    add("Professions: " .. (#parts > 0 and table.concat(parts, ", ") or "none"))
  end
  if Noir.Talents then
    local spec = Noir.Talents.Spec()
    if not spec then
      add("Talents: no build for this class")
    else
      local fits = Noir.Talents.Check()
      add(string.format("Talents: %s build %s, %d points to spend", spec, fits and "fits" or "does not fit this client", Noir.Talents.Unspent()))
    end
  end
  if Noir.Automation and Noir.Automation.Enabled then
    local parts = {}
    for _, key in ipairs({ "autoQuests", "flights", "hearth", "dialogue" }) do parts[#parts + 1] = key .. " " .. onOff(Noir.Automation.Enabled(key)) end
    add("Automation: " .. table.concat(parts, ", "))
  end
  settingsLines(add)

  local why = Why.Lines(WHY_SHOWN)
  add(string.format("Why (last %d):", #why))
  for _, line in ipairs(why) do add(line) end
  add(string.format("Problems (%d):", #Noir.problems))
  for _, problem in ipairs(Noir.problems) do add("  " .. problem) end
  add(string.format("Errors (%d):", #errors))
  for _, err in ipairs(errors) do add("  " .. firstLine(err)) end
  return lines
end

-- ---------------------------------------------------------------------------------------------------------------
-- The box
-- ---------------------------------------------------------------------------------------------------------------

local frame, parts, text = nil, {}, ""

local function build()
  frame = Panel.New(WIDTH)
  Diagnostics.frame = frame
  parts.kicker = Panel.Text(frame, "kicker", "lamp")
  parts.body = Panel.Text(frame, "body", "dim")
  local box = CreateFrame("EditBox", nil, frame)
  Diagnostics.box = box
  box:SetMultiLine(true)
  box:SetAutoFocus(false)
  box:SetSize(WIDTH - 2 * Theme.metrics.pad, BOX_HEIGHT)
  if box.SetTextInsets then box:SetTextInsets(4, 4, 4, 4) end
  Theme.Font(box, "small")
  if box.SetTextColor then box:SetTextColor(Theme.Color("paper")) end
  local back = box:CreateTexture(nil, "BACKGROUND")
  Theme.Paint(back, "strip")
  back:SetAllPoints(box)
  box:SetScript("OnEscapePressed", function() Diagnostics.Close() end)
  -- The box is for copying: whatever is typed into it, the report comes back.
  box:SetScript("OnTextChanged", function(self, userInput)
    if userInput and self:GetFont() then self:SetText(text) end
  end)
  parts.close = Panel.Row(frame, function() Diagnostics.Close() end)
  Screen.Place(frame, "dialog")
  Screen.Register("bug", frame)
end

local function draw()
  local layout = Panel.Layout(frame)
  layout:Text(parts.kicker, "BUG REPORT")
  layout:Text(parts.body, "Press Ctrl+A, then Ctrl+C, and paste it into your report.")
  local box = Diagnostics.box
  box:ClearAllPoints()
  box:SetPoint("TOPLEFT", frame, "TOPLEFT", Theme.metrics.pad, -layout.y)
  layout.y = layout.y + BOX_HEIGHT + Theme.metrics.gap
  if box:GetFont() then
    box:SetText(text)
    box:HighlightText()
    box:SetFocus()
  end
  layout:Row(parts.close, "Close")
  layout:Finish()
  Screen.Pull(frame)
end

function Diagnostics.Open(stepIndex)
  if not frame then build() end
  text = table.concat(Diagnostics.Lines(stepIndex), "\n")
  frame:Show()
  draw()
end

function Diagnostics.Close()
  if not frame then return end
  if Diagnostics.box.ClearFocus then Diagnostics.box:ClearFocus() end
  frame:Hide()
end

function Diagnostics.Read()
  if not frame then return { shown = false } end
  local box = Diagnostics.box
  return { shown = frame:IsShown() and true or false, text = box:GetFont() and box:GetText() or nil }
end

function Diagnostics.Report()
  Diagnostics.Open()
  Noir.Print("The bug report is in the box: press Ctrl+A, then Ctrl+C to copy it.")
end

Noir.Command("bug", "a report of what the addon sees, to copy into a bug report", function()
  Diagnostics.Report()
end)
