-- Noir Guides, GPLv3. See LICENSE.
-- Wizard (spec 2.3, 6.1): the setup wizard. It opens by itself 2 s after entering the world for a level 1
-- character whose guide.wizard is not set, and from the menu and the settings any time. Three pages: the route
-- family, the route questions, and the sections for the character's level with the recommended one first.
--
--   Wizard.Open(), Wizard.Close(), Wizard.Finish()
--   Wizard.Read() -> { shown, page, questions = { { key, text, on, recommended } }, sections = { { id, name,
--     recommended, chosen } } }
--   Wizard.Button(name) -> frame     "back", "reset", "finish", "close", and also "next" (page 2 to 3) and "route"
--                                    (the open world route card of page 1)
--   Wizard.Toggle(key) -> frame      the row of a question: "auctionHouse", "groupQuests", "outlevel", "profession",
--                                    "otherSections"
--   Wizard.SectionRow(id) -> frame   the row of a section on page 3
--   Wizard.Preview(on), Wizard.frame
--   /noir wizard opens it (also the main menu's "Setup wizard" and the settings' button)
--
-- Page 1: the "Open world route" card (the only route family until dungeons exist). Page 2: "Use the auction house"
-- (guide.setup.auctionHouse, recommended on), "Do group quests" (the option groupQuests and guide.setup.groupQuests,
-- off), "Skip content you outlevel" (outlevel, on), "Level a profession" (opens the profession choice at the cursor
-- through Menu.Open; Professions.SetPlanned), "Show sections for other races and classes" (otherSections, off).
-- Page 3: the sections whose level range holds the character's level (Guide.List), the recommendation
-- (Guide.Recommend) first and marked, chosen until another row is clicked. The level rule wins: when the
-- recommendation is out of the level's range (the wizard opened from the menu after leveling past a section loaded
-- by hand), the first listed section of the level is recommended instead; when no section holds the level, the
-- recommendation is listed alone, so Finish always has a section to load. Back, Reset (every question back to its
-- recommended answer and the recommendation chosen; planned professions are kept), Finish (Guide.Select(id,
-- "wizard"); a section of another race or class, listed with "otherSections", is loaded as picked by hand).
-- Finish and closing both set guide.wizard = true; closing keeps the section that is loaded. Default place
-- Screen.DEFAULTS.wizard, moved by dragging, kept on the screen, registered with Screen.Register("wizard").
local Noir = Noir
local Screen, Panel = Noir.Screen, Noir.Panel

local Wizard = Noir.Wizard or {}
Noir.Wizard = Wizard

Wizard.OPEN_SECONDS = 2
Wizard.WIDTH = 320
Wizard.TITLES = { "Set up Noir Guides", "A few questions", "Where to start" }
Wizard.TEXTS = {
  "Choose how you want to level. More route families come later.",
  "Answer as you like; each can be changed later in the settings.",
  "Sections for your level. The recommended one is first.",
}
Wizard.ROUTE_TEXT = "Open world route: quest through the zones, section by section"

local MAX_LEVEL = 60
local frame
local parts = { toggles = {}, buttons = {}, sections = {} }
local page = 1
local chosen = nil
local previewing = false

local function option(key)
  return Noir.Options and Noir.Options.Get(key)
end

local function guideTable()
  if not Noir.char then return nil end
  return Noir.Table(Noir.char, "guide")
end

local function setup()
  local guide = guideTable()
  if not guide then return {} end
  local s = Noir.Table(guide, "setup")
  if type(s.auctionHouse) ~= "boolean" then s.auctionHouse = true end
  if type(s.groupQuests) ~= "boolean" then s.groupQuests = false end
  return s
end

local function level()
  local state = Noir.State
  return state and type(state.level) == "number" and state.level or 1
end

-- ---------------------------------------------------------------------------------------------------------------
-- Questions
-- ---------------------------------------------------------------------------------------------------------------

local function professionNames()
  local list = {}
  local data = Noir.Data.professions
  if type(data) ~= "table" then return list end
  for id, p in pairs(data) do
    if type(p) == "table" and type(p.name) == "string" then list[#list + 1] = { id = id, name = p.name } end
  end
  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end

local function anyPlanned()
  local professions = Noir.Professions
  if not (professions and professions.IsPlanned) then return false end
  for _, p in ipairs(professionNames()) do
    if professions.IsPlanned(p.id) then return true end
  end
  return false
end

local function openProfessions()
  local professions, menu = Noir.Professions, Noir.Menu
  if not (professions and menu and menu.Open) then return end
  local items = {}
  for _, p in ipairs(professionNames()) do
    local id = p.id
    items[#items + 1] = {
      text = p.name, keep = true,
      checked = function() return professions.IsPlanned(id) end,
      on = function() professions.SetPlanned(id, not professions.IsPlanned(id)) end,
    }
  end
  if #items == 0 then items[1] = { text = "No profession is known to the addon", heading = true } end
  menu.Open(items, { title = "Level a profession" })
end

local function setOption(key, value)
  if Noir.Options then Noir.Options.Set(key, value) end
end

local QUESTIONS = {
  { key = "auctionHouse", text = "Use the auction house", recommended = true,
    get = function() return setup().auctionHouse end,
    set = function(on) setup().auctionHouse = on end },
  { key = "groupQuests", text = "Do group quests", recommended = false,
    get = function() return option("groupQuests") == true end,
    set = function(on)
      setOption("groupQuests", on)
      setup().groupQuests = on
    end },
  { key = "outlevel", text = "Skip content you outlevel", recommended = true,
    get = function() return option("outlevel") ~= false end,
    set = function(on) setOption("outlevel", on) end },
  { key = "profession", text = "Level a profession", recommended = false, get = anyPlanned },
  { key = "otherSections", text = "Show sections for other races and classes", recommended = false,
    get = function() return option("otherSections") == true end,
    set = function(on) setOption("otherSections", on) end },
}

-- ---------------------------------------------------------------------------------------------------------------
-- Sections
-- ---------------------------------------------------------------------------------------------------------------

local function holds(section, at)
  return at >= (section.minLevel or 1) and at <= (section.maxLevel or MAX_LEVEL)
end

local function sectionList()
  local Guide = Noir.Guide
  local out = {}
  if not Guide then return out end
  local recommended = Guide.Recommend and Guide.Recommend()
  local first = recommended and Guide.Section(recommended)
  local at = level()
  if first and not holds(first, at) then first = nil end
  if first then out[1] = first end
  for _, group in ipairs(Guide.List(option("otherSections") == true)) do
    for _, sub in ipairs(group.subgroups) do
      for _, section in ipairs(sub.sections) do
        if holds(section, at) and (not first or section.id ~= first.id) then out[#out + 1] = section end
      end
    end
  end
  if not first then
    first = out[1] or (recommended and Guide.Section(recommended))
    if first and not out[1] then out[1] = first end
  end
  return out, first and first.id or nil
end

local function chosenId(list, recommended)
  if chosen then
    for _, section in ipairs(list) do
      if section.id == chosen then return chosen end
    end
  end
  return recommended or (list[1] and list[1].id)
end

local function range(section)
  if section.maxLevel then return (section.minLevel or 1) .. "-" .. section.maxLevel end
  return (section.minLevel or 1) .. "+"
end

-- ---------------------------------------------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------------------------------------------

local function onOff(on)
  return on and "on" or "off"
end

local function draw()
  if not frame then return end
  local layout = Panel.Layout(frame)
  layout:Text(parts.title, Wizard.TITLES[page])
  layout:Text(parts.text, Wizard.TEXTS[page])
  layout:Row(parts.buttons.route, page == 1 and Wizard.ROUTE_TEXT or nil)
  for _, q in ipairs(QUESTIONS) do
    local row = parts.toggles[q.key]
    if page == 2 then
      layout:Row(row, q.text .. "  (recommended: " .. onOff(q.recommended) .. ")", q.get() and true or false)
    else
      layout:Row(row, nil)
    end
  end
  local list, recommended = {}, nil
  if page == 3 then list, recommended = sectionList() end
  local pick = chosenId(list, recommended)
  for i, section in ipairs(list) do
    local row = parts.sections[i]
    if not row then
      row = Panel.Row(frame, function(self) Wizard.Choose(self.id) end)
      parts.sections[i] = row
    end
    row.id = section.id
    local words = Noir.Guide.Name(section) .. "  " .. range(section)
    if section.id == recommended then words = words .. "  (recommended)" end
    layout:Row(row, words, section.id == pick)
  end
  for i = #list + 1, #parts.sections do
    parts.sections[i].id = nil
    layout:Row(parts.sections[i], nil)
  end
  layout:Gap()
  local b = parts.buttons
  layout:Row(b.next, page == 2 and "Next" or nil)
  layout:Row(b.finish, page >= 2 and "Finish" or nil)
  layout:Row(b.back, page >= 2 and "Back" or nil)
  layout:Row(b.reset, page >= 2 and "Reset to the recommended answers" or nil)
  layout:Row(b.close, "Close")
  layout:Finish()
  Screen.Pull(frame)
end

local function build()
  if frame then return end
  frame = Panel.New(Wizard.WIDTH)
  Wizard.frame = frame
  parts.title = Panel.Text(frame, "name", "paper")
  parts.text = Panel.Text(frame, "body", "dim")
  local b = parts.buttons
  b.route = Panel.Row(frame, function() Wizard.Page(2) end)
  for _, q in ipairs(QUESTIONS) do
    local question = q
    parts.toggles[q.key] = Panel.Row(frame, function()
      if question.set then
        question.set(not question.get())
        draw()
      else
        openProfessions()
      end
    end)
  end
  b.next = Panel.Row(frame, function() Wizard.Page(3) end)
  b.back = Panel.Row(frame, function() Wizard.Page(page - 1) end)
  b.reset = Panel.Row(frame, function() Wizard.Reset() end)
  b.finish = Panel.Row(frame, function() Wizard.Finish() end)
  b.close = Panel.Row(frame, function() Wizard.Close() end)
  Screen.Place(frame, "wizard")
  Screen.Movable(frame, "wizard")
  Screen.Register("wizard", frame, Wizard.Preview)
  frame:Hide()
end

-- ---------------------------------------------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------------------------------------------

function Wizard.Open()
  build()
  previewing = false
  page, chosen = 1, nil
  frame:Show()
  draw()
end

function Wizard.Page(n)
  if not frame then return end
  if n < 1 then n = 1 end
  if n > 3 then n = 3 end
  page = n
  draw()
end

function Wizard.Choose(id)
  chosen = id
  draw()
end

function Wizard.Reset()
  for _, q in ipairs(QUESTIONS) do
    if q.set then q.set(q.recommended) end
  end
  chosen = nil
  draw()
end

local function done()
  local guide = guideTable()
  if guide then guide.wizard = true end
  previewing = false
  if frame then frame:Hide() end
end

function Wizard.Finish()
  local list, recommended = sectionList()
  local id = chosenId(list, recommended)
  local Guide = Noir.Guide
  if id and Guide then
    if not Guide.Select(id, "wizard") then Guide.Select(id, "hand") end
  end
  done()
end

function Wizard.Close()
  done()
end

function Wizard.Read()
  local shown = frame ~= nil and frame:IsShown() and not previewing
  local questions = {}
  for i, q in ipairs(QUESTIONS) do
    questions[i] = { key = q.key, text = q.text, on = q.get() and true or false, recommended = q.recommended }
  end
  local list, recommended = sectionList()
  local pick = chosenId(list, recommended)
  local sections = {}
  for i, section in ipairs(list) do
    sections[i] = { id = section.id, name = Noir.Guide.Name(section), recommended = section.id == recommended,
      chosen = section.id == pick }
  end
  return { shown = shown and true or false, page = page, questions = questions, sections = sections }
end

function Wizard.Button(name)
  build()
  return parts.buttons[name]
end

function Wizard.Toggle(key)
  build()
  return parts.toggles[key]
end

function Wizard.SectionRow(id)
  for _, row in ipairs(parts.sections) do
    if row.id == id and row:IsShown() then return row end
  end
  return nil
end

-- Sample content for placing the windows (Screen.Preview): the first page, gone again afterwards unless the
-- wizard was open already.
function Wizard.Preview(on)
  build()
  if on then
    if frame:IsShown() then return end
    previewing = true
    page = 1
    frame:Show()
    draw()
  elseif previewing then
    previewing = false
    frame:Hide()
  end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------------------------------------------

local function redraw()
  if frame and frame:IsShown() then draw() end
end

Noir.Command("wizard", "open the setup wizard", function() Wizard.Open() end)

Noir.On("NOIR_INIT", build)
Noir.On("NOIR_READY", function()
  Noir.After(Wizard.OPEN_SECONDS, function()
    local guide = guideTable()
    if not guide or guide.wizard or level() ~= 1 then return end
    if frame and frame:IsShown() and not previewing then return end
    Wizard.Open()
  end)
end)
Noir.On("NOIR_OPTION", redraw)
Noir.On("NOIR_SECTION", redraw)
Noir.On("NOIR_PROFESSIONS", redraw)
