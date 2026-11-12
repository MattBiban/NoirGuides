-- Noir Guides, GPLv3. See LICENSE.
-- Menu (spec 2.2, 4.1 menus, 4.3, gap #1, #5, #7, #49): cascading menus at the mouse cursor. The main menu (the
-- window's header, its menu button, the minimap button), the step menu (the step list) and the section picker are
-- built from items; every level is the addon's own frame, so menus work in combat.
--
--   Menu.Open(items, opts)       opts = { title, current }: a title over the rows, and the index of the row to
--                                scroll to (else the first row marked current)
--   Menu.OpenMain(), Menu.OpenStep(index), Menu.OpenPicker()
--   Menu.Close(), Menu.IsOpen()
--   Menu.Read() -> { levels = { { rows = { { text, right, checked, sub, current, marker, heading, lit } }, scroll } } }
--   Menu.Row(level, i) -> frame  a row of an open level (row.marker is the colored tab of a picker row)
--   Menu.Level(level) -> frame, Menu.List(level) -> the level's scroll frame, Menu.Catcher() -> the full-screen
--                                frame under the menu that takes a click outside it (for tests)
--   Menu.FindPlace()             "Find my place again" (also /noir sync and the settings' Advanced button)
--   Menu.MOUSE_PATHS[command] -> { "main", "<row text>", ... } the rows to click for each /noir command, from the
--                                main menu (opened by the window's header, its menu button or a right click on the
--                                minimap button) through each submenu; { "minimap", "LeftButton" } is a click on the
--                                minimap button. "/noir" alone is the main menu's "Options"
--   Item: { text, right, checked = fn, on = fn, sub = fn -> items, keep, current, marker = "level" | "passed",
--     heading }. A click on a row with `on` closes the whole menu, then calls it (with `keep` the menu stays open and
--     its ticks are read again); a row with `sub` opens its submenu on hover or click; a heading takes no click.
--
-- Placement: the first level opens at the cursor (Screen.AtCursor), a submenu beside its row to the right, to the
-- left when the right has no room; each level is capped by Screen.Fit and scrolls with the mouse wheel, and opens
-- scrolled to its current row. Escape (the catcher takes the keyboard and passes every other key on) or a click
-- outside (the catcher) closes the whole menu.
--
-- Main menu: "Choose a section" > (picker), "Reload section", "Find my place again" (Progress.Locate over the current
-- chain, after Panel.Confirm), "Step" > ("Skip this step", "Back to the last open step"), "Show the arrow" (tick),
-- "Show all map pins" (tick: on while minimapPins is on and worldPins above 0; unticking turns the minimap pins off
-- and worldPins to 0, which leaves only the cards' own pins on the world map, since 0 is not an off switch there,
-- ENGINE-NOTES #77; the options have no key that hides them), "Lock windows" (tick), "Options", "Setup wizard", "Quest
-- cleanup", "Talents", "Professions", "Report a problem" (Diagnostics.Report), "Preview window positions" (tick,
-- Screen.Preview), "More" > ("Why steps were passed", "What the addon knows", "Problems", "Version", "Commands": the
-- extras' chat output), "Hide Noir Guides" (Screen.SetShown(false); while hidden the row reads "Show Noir Guides";
-- the minimap button shows them again too). "Step" > also has "Show the current step".
-- Step menu (spec 4.3): "Go to this step", "Skip this step" (on the current step only), "Back to the last open step",
-- "Choose another section" >, "Reload section", "Options", "Report a problem with this step" (Diagnostics.Open(index),
-- so the report can name the step), "Close".
-- Picker (spec 2.2): Guide.List(Options.Get("otherSections")) as groups > subgroups > sections; each section row its
-- name with its level range on the right; the section played (and the group and subgroup holding it) highlighted;
-- marker "level" (lamp tab) on ranges holding the character's level, "passed" (dim tab) on ranges below it. Picking
-- calls Guide.Select(id, "hand"); when the section changed and "offerCleanup" is on, Noir.Cleanup.Offer() 3 s later.
-- "Find my place again" that lands in another section is a change made by hand too and makes the same offer.
-- Functions of other modules (SettingsPanel, Cleanup, Talents, Diagnostics, Wizard) are looked up at click time.
local Noir = Noir
local Theme, Screen, Panel = Noir.Theme, Noir.Screen, Noir.Panel

local Menu = Noir.Menu or {}
Noir.Menu = Menu

Menu.WIDTH = 230           -- a level's width
Menu.RIGHT_WIDTH = 44      -- the column of the text on the right (level ranges)
Menu.OFFER_SECONDS = 3     -- from picking another section to the cleanup offer
Menu.FIND_QUESTION = "Find your place again from your quest log and the quests you have handed in?"
Menu.FIND_NOTHING = "Your quest log shows no work on this route yet, so your place stays where it is."
Menu.FIND_TEXT = "Found your place again from your quest log (from the menu): %s step %d."

local STRATA = "FULLSCREEN_DIALOG"
local BAR = 6              -- room the scroll bar takes on the right

local levels = {}          -- pooled levels: { frame, list, title, rows = {}, items = {}, open }
local catcher
local open = 0             -- levels open

local function metrics()
  return Theme.metrics
end

local function rowHeight()
  return Theme.sizes.body + 2 * metrics().gap
end

local function inCombat()
  return InCombatLockdown and InCombatLockdown() and true or false
end

local function option(key)
  return Noir.Options and Noir.Options.Get(key)
end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local results = { pcall(fn, ...) }
  if not results[1] then
    Noir.ReportError(results[2])
    return nil
  end
  return unpack(results, 2)
end

-- A function of another module, looked up when the row is clicked.
local function later(module, name, ...)
  local args = { ... }
  return function()
    local m = Noir[module]
    if m and type(m[name]) == "function" then call(m[name], unpack(args)) end
  end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Frames
-- ---------------------------------------------------------------------------------------------------------------

local function restoreKeys()
  if catcher and not inCombat() and not catcher:GetPropagateKeyboardInput() then
    catcher:SetPropagateKeyboardInput(true)
  end
end

local function makeCatcher()
  catcher = CreateFrame("Frame", nil, UIParent)
  catcher:SetFrameStrata(STRATA)
  catcher:SetFrameLevel(1)
  catcher:SetAllPoints(UIParent)
  catcher:EnableMouse(true)
  catcher:EnableKeyboard(true)
  catcher:SetPropagateKeyboardInput(true)
  catcher:SetScript("OnMouseDown", function() Menu.Close() end)
  catcher:SetScript("OnKeyDown", function(self, key)
    if key ~= "ESCAPE" then return end
    -- Out of combat Escape stops here, so the game's own menu does not open as well; in combat the game does not
    -- let an addon change that, and Escape goes on to the game after closing the menu.
    if not inCombat() then self:SetPropagateKeyboardInput(false) end
    Menu.Close()
  end)
  catcher:Hide()
end

local function newRow(level, k)
  local row = Panel.Row(level.list.child, function(self, button) Menu.Activate(self.level, self.index, button) end)
  row.level, row.index = level.index, k
  row.now = row:CreateTexture(nil, "BACKGROUND")
  Theme.Paint(row.now, "strip", 0.6)
  row.now:SetAllPoints(row)
  row.now:Hide()
  row.marker = row:CreateTexture(nil, "ARTWORK")
  row.marker:SetColorTexture(1, 1, 1, 1)
  row.marker:SetWidth(metrics().lamp)
  row.marker:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
  row.marker:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
  row.marker:Hide()
  row.right = Panel.Text(row, "small", "dim", "RIGHT")
  row.arrow = Panel.Text(row, "small", "dim", "RIGHT")
  row:HookScript("OnEnter", function(self) Menu.Hover(self.level, self.index) end)
  row:EnableMouseWheel(false)
  return row
end

local function newLevel(i)
  local m = metrics()
  local level = { index = i, rows = {}, items = {} }
  local frame = CreateFrame("Frame", nil, UIParent)
  frame:SetFrameStrata(STRATA)
  frame:SetFrameLevel(10 + 10 * i)
  frame:SetWidth(Menu.WIDTH)
  frame:SetHeight(4 * m.pad)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  frame:EnableMouse(true) -- clicks on the menu do not fall through to the catcher
  frame:EnableMouseWheel(true)
  local bay = frame:CreateTexture(nil, "BACKGROUND")
  Theme.Paint(bay, "bay", m.alpha)
  bay:SetAllPoints(frame)
  local edge = frame:CreateTexture(nil, "BORDER")
  Theme.Paint(edge, "lamp")
  edge:SetHeight(1)
  edge:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  edge:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
  level.title = Panel.Text(frame, "kicker", "dim")
  level.list = Panel.ScrollList(frame, { step = 3 * rowHeight() })
  frame:SetScript("OnMouseWheel", function(_, delta)
    level.list:Scroll(level.list:Offset() - (delta or 0) * level.list.step)
  end)
  frame:Hide()
  level.frame = frame
  levels[i] = level
  return level
end

local function levelAt(i)
  return levels[i] or newLevel(i)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Drawing a level
-- ---------------------------------------------------------------------------------------------------------------

local function checkedOf(item)
  if type(item.checked) ~= "function" then return nil end
  return call(item.checked) and true or false
end

local function drawRow(level, k, item, width)
  local m = metrics()
  local row = level.rows[k] or newRow(level, k)
  level.rows[k] = row
  row.item = item
  local h = rowHeight()
  row:SetSize(width, h)
  row:ClearAllPoints()
  row:SetPoint("TOPLEFT", level.list.child, "TOPLEFT", 0, -(k - 1) * h)
  local checked = checkedOf(item)
  row.checked = checked
  -- Tick box (Panel's) for ticks; the text starts after it.
  if checked == nil then
    row.box:Hide()
  else
    Theme.Paint(row.box, checked and "lamp" or "track")
    row.box:Show()
  end
  local textLeft = m.gap + metrics().lamp + (checked ~= nil and (Theme.sizes.body + m.gap) or 0)
  local rightWidth = (item.right or item.sub) and Menu.RIGHT_WIDTH or 0
  row.text:ClearAllPoints()
  row.text:SetPoint("TOPLEFT", row, "TOPLEFT", textLeft, -m.gap)
  row.text:SetWidth(math.max(10, width - textLeft - rightWidth - m.gap))
  if row.text.SetWordWrap then row.text:SetWordWrap(false) end
  Theme.SetText(row.text, item.text or "")
  row.text:SetTextColor(Theme.Color(item.heading and "dim" or (item.current and "lamp" or "paper")))
  row.text:Show()
  row.right:ClearAllPoints()
  row.right:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(m.gap + (item.sub and 10 or 0)), -m.gap)
  row.right:SetWidth(Menu.RIGHT_WIDTH)
  if item.right then
    Theme.SetText(row.right, tostring(item.right))
    row.right:Show()
  else
    row.right:Hide()
  end
  row.arrow:ClearAllPoints()
  row.arrow:SetPoint("TOPRIGHT", row, "TOPRIGHT", -m.gap, -m.gap)
  row.arrow:SetWidth(10)
  if item.sub then
    Theme.SetText(row.arrow, ">")
    row.arrow:Show()
  else
    row.arrow:Hide()
  end
  if item.marker == "level" or item.marker == "passed" then
    Theme.Tint(row.marker, item.marker == "level" and "lamp" or "dim")
    row.marker:Show()
  else
    row.marker:Hide()
  end
  if item.current then row.now:Show() else row.now:Hide() end
  row:Show()
end

-- Lays out level i with `items` (sized and capped, not placed). Returns the level.
local function fill(i, items, opts)
  opts = opts or {}
  local m = metrics()
  local level = levelAt(i)
  level.items = items
  local frame, list = level.frame, level.list
  local titleHeight = 0
  if opts.title and opts.title ~= "" and Theme.SetText(level.title, opts.title) then
    level.title:ClearAllPoints()
    level.title:SetPoint("TOPLEFT", frame, "TOPLEFT", m.pad, -m.pad)
    level.title:SetWidth(Menu.WIDTH - 2 * m.pad)
    level.title:Show()
    titleHeight = Theme.sizes.kicker + 2 * m.gap
  else
    level.title:Hide()
  end
  local h = rowHeight()
  local content = #items * h
  frame:SetWidth(Menu.WIDTH)
  Screen.Fit(frame, content + 2 * m.pad + titleHeight)
  list.frame:ClearAllPoints()
  list.frame:SetPoint("TOPLEFT", frame, "TOPLEFT", m.pad, -(m.pad + titleHeight))
  list.frame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -m.pad, m.pad)
  local width = Menu.WIDTH - 2 * m.pad - BAR
  list.child:SetWidth(Menu.WIDTH - 2 * m.pad) -- before the first row is made: rows take their width from it
  for k = 1, #items do drawRow(level, k, items[k], width) end
  for k = #items + 1, #level.rows do level.rows[k]:Hide() end
  list.offset = 0
  list:SetContentHeight(content)
  -- Open scrolled to the current row when it would be out of view.
  local target = type(opts.current) == "number" and opts.current or nil
  if not target then
    for k = 1, #items do
      if items[k].current then
        target = k
        break
      end
    end
  end
  if target and target * h > list:View() then
    list:Scroll((target - 1) * h)
  else
    list:Scroll(0)
  end
  level.titleHeight = titleHeight
  return level
end

local function showLevel(level)
  level.open = true
  level.frame:Show()
  Screen.Keep(level.frame)
end

local function closeFrom(i)
  for k = #levels, i, -1 do
    local level = levels[k]
    if level.open then
      level.open = false
      level.frame:Hide()
    end
  end
  if open >= i then open = i - 1 end
end

-- Places level i beside row k of level i - 1: to the right, or to the left when the right has no room.
local function placeBeside(i, k)
  local m = metrics()
  local parent, frame = levels[i - 1], levels[i].frame
  local pf = parent.frame
  local left, right, top = pf:GetLeft(), pf:GetRight(), pf:GetTop()
  if not (left and right and top) then return end
  local h = rowHeight()
  local rowTop = top - m.pad - (parent.titleHeight or 0) - ((k - 1) * h - parent.list:Offset())
  local bottomOfList = pf:GetBottom() + m.pad
  if rowTop < bottomOfList + h then rowTop = bottomOfList + h end
  if rowTop > top - m.pad then rowTop = top - m.pad end
  local screenWidth = UIParent:GetWidth()
  local width = frame:GetWidth()
  local toRight
  if right + width <= screenWidth then
    toRight = true
  elseif left - width >= 0 then
    toRight = false
  else
    toRight = (screenWidth - right) >= left
  end
  frame:ClearAllPoints()
  if toRight then
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", right, rowTop + m.pad)
  else
    frame:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", left, rowTop + m.pad)
  end
end

local function refreshLevel(level)
  local width = Menu.WIDTH - 2 * metrics().pad - BAR
  for k = 1, #level.items do drawRow(level, k, level.items[k], width) end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Opening, hovering, clicking
-- ---------------------------------------------------------------------------------------------------------------

-- Opens a menu beside a frame instead of at the cursor: to its right when the menu fits there, else to its left,
-- top edges level, so the menu never covers the frame it belongs to (the guide window's menu button). Kept on the
-- screen like every other frame.
function Menu.PlaceBeside(menuFrame, anchor)
  local ui = UIParent:GetEffectiveScale() or 1
  local right = (anchor:GetRight() or 0) * (anchor:GetEffectiveScale() or 1) / ui
  local width = (menuFrame:GetWidth() or 0) * (menuFrame:GetEffectiveScale() or 1) / ui
  local gap = metrics().gap
  menuFrame:ClearAllPoints()
  if right + gap + width <= (UIParent:GetWidth() or 0) then
    menuFrame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", gap, 0)
  else
    menuFrame:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -gap, 0)
  end
  if Screen.Keep then Screen.Keep(menuFrame) end
end

function Menu.Open(items, opts)
  Menu.Close()
  if not catcher then makeCatcher() end
  restoreKeys()
  catcher:Show()
  local level = fill(1, items or {}, opts)
  if opts and opts.anchor then Menu.PlaceBeside(level.frame, opts.anchor) else Screen.AtCursor(level.frame, "right") end
  showLevel(level)
  open = 1
  return true
end

function Menu.Close()
  local was = open > 0
  closeFrom(1)
  open = 0
  if catcher then catcher:Hide() end
  if was then Noir.After(0, restoreKeys) end
end

function Menu.IsOpen()
  return open > 0
end

local function openSub(i, k)
  local level = levels[i]
  local item = level and level.items[k]
  if not (item and type(item.sub) == "function") then return end
  closeFrom(i + 1)
  local items = call(item.sub) or {}
  local sub = fill(i + 1, items)
  placeBeside(i + 1, k)
  showLevel(sub)
  open = i + 1
end

-- The mouse entered row k of level i: its submenu opens, any deeper level of another row closes.
function Menu.Hover(i, k)
  if not (levels[i] and levels[i].open) then return end
  local item = levels[i].items[k]
  if item and item.sub then
    openSub(i, k)
  else
    closeFrom(i + 1)
  end
end

function Menu.Activate(i, k)
  local level = levels[i]
  local item = level and level.open and level.items[k]
  if not item or item.heading then return end
  if item.sub then
    openSub(i, k)
    return
  end
  if item.keep then
    call(item.on)
    if level.open then refreshLevel(level) end
    return
  end
  Menu.Close()
  call(item.on)
end

function Menu.Read()
  local out = { levels = {} }
  for i = 1, open do
    local level = levels[i]
    local rows = {}
    for k, item in ipairs(level.items) do
      local row = level.rows[k]
      rows[k] = {
        text = item.text, right = item.right, checked = row and row.checked,
        sub = item.sub ~= nil, current = item.current and true or false, marker = item.marker,
        heading = item.heading and true or false, lit = row and row.lit or false,
      }
    end
    out.levels[i] = { rows = rows, scroll = level.list:Offset() }
  end
  return out
end

function Menu.Row(i, k)
  local level = levels[i]
  if not (level and level.open and level.items[k]) then return nil end
  return level.rows[k]
end

function Menu.Level(i)
  return levelAt(i).frame
end

function Menu.List(i)
  return levelAt(i).list.frame
end

function Menu.Catcher()
  if not catcher then makeCatcher() end
  return catcher
end

-- ---------------------------------------------------------------------------------------------------------------
-- The picker
-- ---------------------------------------------------------------------------------------------------------------

local function range(section)
  local low, high = section.minLevel or 1, section.maxLevel
  if high then return low .. "-" .. high end
  return low .. "+"
end

local function level()
  local state = Noir.State
  return state and type(state.level) == "number" and state.level or 1
end

local function markerOf(section)
  local at = level()
  if section.maxLevel and at > section.maxLevel then return "passed" end
  if at >= (section.minLevel or 1) and at <= (section.maxLevel or 60) then return "level" end
  return nil
end

-- Loads section id by hand (spec 2.2, 6.2 item 12): when the section changed and "offerCleanup" is on, the quest
-- cleanup is offered OFFER_SECONDS later. Returns whether the section was loaded.
local function selectByHand(id)
  local Guide = Noir.Guide
  local before = Guide.Current()
  if not Guide.Select(id, "hand") then return false end
  if Guide.Current() ~= before and option("offerCleanup") ~= false then
    Noir.After(Menu.OFFER_SECONDS, function()
      local cleanup = Noir.Cleanup
      if cleanup and type(cleanup.Offer) == "function" then cleanup.Offer() end
    end)
  end
  return true
end

local function pick(id)
  selectByHand(id)
end

local function sectionItems(sections)
  local Guide = Noir.Guide
  local current = Guide.Current()
  local items = {}
  for _, section in ipairs(sections) do
    local id = section.id
    items[#items + 1] = {
      text = Guide.Name(section), right = range(section), current = id == current, marker = markerOf(section),
      on = function() pick(id) end,
    }
  end
  return items
end

local function holds(list, current)
  for _, section in ipairs(list) do
    if section.id == current then return true end
  end
  return false
end

function Menu.PickerItems()
  local Guide = Noir.Guide
  local current = Guide.Current()
  local items = {}
  for _, group in ipairs(Guide.List(option("otherSections") == true)) do
    local subgroups = group.subgroups
    local inGroup = false
    for _, sub in ipairs(subgroups) do
      if holds(sub.sections, current) then inGroup = true end
    end
    items[#items + 1] = {
      text = group.group, current = inGroup,
      sub = function()
        local out = {}
        for _, sub in ipairs(subgroups) do
          local sections = sub.sections
          out[#out + 1] = { text = sub.name, current = holds(sections, current),
            sub = function() return sectionItems(sections) end }
        end
        return out
      end,
    }
  end
  if #items == 0 then items[1] = { text = "No section for this character", heading = true } end
  return items
end

function Menu.OpenPicker()
  return Menu.Open(Menu.PickerItems(), { title = "Choose a section" })
end

-- ---------------------------------------------------------------------------------------------------------------
-- The main menu and the step menu
-- ---------------------------------------------------------------------------------------------------------------

local function reload()
  local id = Noir.Guide.Current()
  if id then Noir.Progress.Load(id) end
end

local function skip()
  if not Noir.Progress.Skip() then Noir.Print("There is no step to skip.") end
end

local function back()
  if not Noir.Progress.Back() then Noir.Print("There is nothing to go back to: every earlier step is done.") end
end

-- Spec 2.5 by hand: placement from the quest log over the chain from the current section, after a question.
local function findPlace()
  local Guide, Progress = Noir.Guide, Noir.Progress
  local current = Guide.Current()
  if not current then return end
  Panel.Confirm(Menu.FIND_QUESTION, function()
    local id, at, score = Progress.Locate(Guide.Chain(Guide.Current()))
    if not id or type(score) ~= "number" or score <= 0 then
      Noir.Print(Menu.FIND_NOTHING)
      return
    end
    if id ~= Guide.Current() and not selectByHand(id) then return end
    local steps = Progress.Steps()
    if at > #steps then at = #steps end
    if at < 1 then return end
    Progress.Jump(at, "list")
    local step = steps[at]
    local text = string.format(Menu.FIND_TEXT, tostring(Guide.Name(Guide.Section(id))), step.n)
    Noir.Why.Add({ section = id, step = step.id, n = step.n, kind = "place", text = text })
    Noir.Print(text)
  end)
end

Menu.FindPlace = findPlace

local function toggle(key)
  return function() Noir.Options.Set(key, not option(key)) end
end

local function pinsShown()
  return option("minimapPins") ~= false and (option("worldPins") or 0) > 0
end

local lastWorldPins
local function togglePins()
  local Options = Noir.Options
  if pinsShown() then
    lastWorldPins = option("worldPins")
    Options.Set("minimapPins", false)
    Options.Set("worldPins", 0)
  else
    Options.Set("minimapPins", true)
    if (option("worldPins") or 0) <= 0 then
      Options.Set("worldPins", lastWorldPins or Options.DEFAULTS.worldPins)
    end
  end
end

-- A row that does what typing the command does (its chat output), for the extras that only print.
local function command(name)
  return function() Noir.RunCommand(name) end
end

local function stepItems()
  return {
    { text = "Show the current step", on = command("step") },
    { text = "Skip this step", on = skip },
    { text = "Back to the last open step", on = back },
  }
end

local function moreItems()
  return {
    { text = "Why steps were passed", on = command("why") },
    { text = "What the addon knows", on = command("state") },
    { text = "Problems", on = command("problems") },
    { text = "Version", on = command("version") },
    { text = "Commands", on = command("help") },
  }
end

local function showHide()
  if option("shown") == false then
    return { text = "Show Noir Guides", on = function() Screen.SetShown(true) end }
  end
  return { text = "Hide Noir Guides", on = function() Screen.SetShown(false) end }
end

function Menu.MainItems()
  return {
    { text = "Choose a section", sub = Menu.PickerItems },
    { text = "Reload section", on = reload },
    { text = "Find my place again", on = findPlace },
    { text = "Step", sub = stepItems },
    { text = "Show the arrow", checked = function() return option("arrow") ~= false end, on = toggle("arrow"), keep = true },
    { text = "Show all map pins", checked = pinsShown, on = togglePins, keep = true },
    { text = "Lock windows", checked = function() return option("locked") == true end, on = toggle("locked"), keep = true },
    { text = "Options", on = later("SettingsPanel", "Open") },
    { text = "Setup wizard", on = later("Wizard", "Open") },
    { text = "Quest cleanup", on = later("Cleanup", "Open") },
    { text = "Talents", on = later("Talents", "Print") },
    { text = "Professions", on = later("Professions", "Print") },
    { text = "Report a problem", on = later("Diagnostics", "Report") },
    { text = "Preview window positions", checked = function() return Screen.IsPreview() end,
      on = function() Screen.Preview(not Screen.IsPreview()) end },
    { text = "More", sub = moreItems },
    showHide(),
  }
end

Menu.MOUSE_PATHS = {
  show = { "main", "Show Noir Guides" },
  hide = { "main", "Hide Noir Guides" },
  toggle = { "minimap", "LeftButton" },
  wizard = { "main", "Setup wizard" },
  cleanup = { "main", "Quest cleanup" },
  talents = { "main", "Talents" },
  professions = { "main", "Professions" },
  bug = { "main", "Report a problem" },
  preview = { "main", "Preview window positions" },
  help = { "main", "More", "Commands" },
  why = { "main", "More", "Why steps were passed" },
  state = { "main", "More", "What the addon knows" },
  problems = { "main", "More", "Problems" },
  version = { "main", "More", "Version" },
  step = { "main", "Step", "Show the current step" },
  skip = { "main", "Step", "Skip this step" },
  back = { "main", "Step", "Back to the last open step" },
  sync = { "main", "Find my place again" },
}

function Menu.OpenMain(anchor)
  return Menu.Open(Menu.MainItems(), { title = "Noir Guides", anchor = anchor })
end

function Menu.StepItems(index)
  local Progress = Noir.Progress
  local items = { { text = "Go to this step", on = function() Progress.Jump(index, "list") end } }
  if Progress.StepState(index) == "current" then items[#items + 1] = { text = "Skip this step", on = skip } end
  items[#items + 1] = { text = "Back to the last open step", on = back }
  items[#items + 1] = { text = "Choose another section", sub = Menu.PickerItems }
  items[#items + 1] = { text = "Reload section", on = reload }
  items[#items + 1] = { text = "Options", on = later("SettingsPanel", "Open") }
  items[#items + 1] = { text = "Report a problem with this step", on = later("Diagnostics", "Open", index) }
  items[#items + 1] = { text = "Close", on = function() end }
  return items
end

function Menu.OpenStep(index)
  local step = Noir.Progress.Steps()[index]
  if not step then return false end
  return Menu.Open(Menu.StepItems(index), { title = "Step " .. tostring(step.n) })
end

Noir.Command("sync", "find your place again from your quest log (asks first)", function() Menu.FindPlace() end)

makeCatcher()
Noir.On("PLAYER_REGEN_ENABLED", restoreKeys)
