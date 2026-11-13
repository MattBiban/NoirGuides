-- Noir Guides, GPLv3. See LICENSE.
-- SettingsPanel (spec 4.1 entry points, 6.1, gap #3): the addon's settings, one page with tabs, in the game's own
-- options window under AddOns as "Noir Guides", or as a free window on a client without one.
--
--   SettingsPanel.Open([tab])     opens the page on `tab` (default: the tab shown last, at first "General"); in
--                                 combat the request is remembered and done at PLAYER_REGEN_ENABLED
--   SettingsPanel.Read() -> { shown, tab, controls = { { key, kind, value } } }   the controls of the tab shown;
--                                 kind "tick", "slider", "choice", "button" or "text"
--   SettingsPanel.Control(key) -> frame   the control's frame (for "text", the edit box)
--   SettingsPanel.Tab(name) -> frame, SettingsPanel.Track(key) -> frame (a slider's track),
--   SettingsPanel.CloseButton() -> frame (the free window's), SettingsPanel.frame, SettingsPanel.mode
--                                 ("modern", "legacy" or "none")
--   SettingsPanel.TABS = { "General", "Guide window", "Navigation", "Automation", "Route", "Advanced", "Profiles" }
--   SettingsPanel.CONTROLS[tab]   the controls of each tab, in order
--
-- Where it lives: modern Settings.RegisterCanvasLayoutCategory + Settings.RegisterAddOnCategory when the client has
-- them, else InterfaceOptions_AddCategory; without either, Open shows the same page as a free window at
-- Screen.DEFAULTS.dialog (placed, kept on the screen and capped by Screen.Fit; the controls scroll), moved by
-- dragging, closed by its Close row. The free window is not registered with Screen.Register: it is the way back
-- when every window is hidden, so hiding the addon must not hide it.
--
-- Controls are the addon's own (tick box, slider with its value, choice list through Menu.Open, button, a name
-- box): one per Options.DEFAULTS key in its tab per spec 6.1, plus the buttons: General "Open setup wizard", "Open
-- quest cleanup", "Report a problem"; Guide window "Reset item buttons", "Preview window positions"; Navigation
-- "Reset arrow"; Route "Profession to level with the route" (Professions.SetPlanned); Advanced "Find my place
-- again"; Profiles the profile in use, a name box, new, copy, delete, reset, "Use as default for new characters"
-- and "Reset guide progress for this character". Applied at once, with no question and no reload: fontSize and accent ("Theme"). Asked first with Panel.Confirm: outlevel (then the section is loaded again), deleting or resetting a profile and resetting guide progress.
-- "Show Noir Guides" calls Screen.SetShown, "Hide in raids" sets hideInRaid (Screen hides and shows), "Preview
-- window positions" turns Screen.Preview on and off.
--
-- Conflict warning (spec 6.1 Advanced): 20 s after login, when "conflicts" is on and another arrow addon
-- (CONFLICTS) is loaded (C_AddOns.IsAddOnLoaded or IsAddOnLoaded), one chat line, once per session.
local Noir = Noir
local Theme, Screen, Panel = Noir.Theme, Noir.Screen, Noir.Panel

local SettingsPanel = {}
Noir.SettingsPanel = SettingsPanel

SettingsPanel.NAME = "Noir Guides"
SettingsPanel.TABS = { "General", "Guide window", "Navigation", "Automation", "Route", "Advanced", "Profiles" }
SettingsPanel.CONFLICT_SECONDS = 20
SettingsPanel.CONFLICTS = { "TomTom" }
SettingsPanel.WIDTH = 440      -- the free window, and the width the controls are laid out for
SettingsPanel.TAB_WIDTH = 110

SettingsPanel.OUTLEVEL_QUESTION = "Changing this loads the section again, and steps may pass or come back. Go on?"
SettingsPanel.RESET_QUESTION = "Put every setting and window place of the profile %s back to its default?"
SettingsPanel.DELETE_QUESTION = "Delete the profile %s? Its settings and window places are lost."
SettingsPanel.PROGRESS_QUESTION = "Forget this character's section and place in the guide? They are found again from "
  .. "your level, zone and quest log."

local BAR = 6        -- room the scroll bar takes on the right
local NAME_LETTERS = 40

local frame, category
local parts = { tabs = {}, controls = {} }  -- controls: key -> { def, frame, ... }
local list
local shownTab = "General"
local pending          -- a tab to open when combat ends
local warned = false

local function metrics()
  return Theme.metrics
end

local function inCombat()
  return InCombatLockdown and InCombatLockdown() and true or false
end

local function option(key)
  return Noir.Options and Noir.Options.Get(key)
end

local function setOption(key, value)
  local good, reason = Noir.Options.Set(key, value)
  if not good and reason then Noir.Print("That setting was not changed: " .. reason .. ".") end
  return good
end

-- A function of another module, looked up when the control is used.
local function later(module, name)
  return function()
    local m = Noir[module]
    if m and type(m[name]) == "function" then m[name]() end
  end
end

local function rowHeight()
  return Theme.sizes.body + 2 * metrics().gap
end

local function contentWidth()
  local m = metrics()
  return SettingsPanel.WIDTH - 2 * m.pad - SettingsPanel.TAB_WIDTH - m.gap - BAR
end

local draw -- forward

-- ---------------------------------------------------------------------------------------------------------------
-- What the controls do
-- ---------------------------------------------------------------------------------------------------------------

local function professionList()
  local out = {}
  local data = Noir.Data.professions
  if type(data) ~= "table" then return out end
  for id, p in pairs(data) do
    if type(p) == "table" and type(p.name) == "string" then out[#out + 1] = { id = id, name = p.name } end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

local function plannedNames()
  local professions = Noir.Professions
  local names = {}
  if professions and type(professions.IsPlanned) == "function" then
    for _, p in ipairs(professionList()) do
      if professions.IsPlanned(p.id) then names[#names + 1] = p.name end
    end
  end
  if #names == 0 then return "none" end
  return table.concat(names, ", ")
end

local function professionItems()
  local professions = Noir.Professions
  local items = {}
  for _, p in ipairs(professionList()) do
    local id = p.id
    items[#items + 1] = {
      text = p.name, keep = true,
      checked = function() return professions.IsPlanned(id) end,
      on = function()
        professions.SetPlanned(id, not professions.IsPlanned(id))
        draw()
      end,
    }
  end
  if #items == 0 then items[1] = { text = "No profession is known to the addon", heading = true } end
  return items
end

local function typedName()
  local box = parts.controls.profileName and parts.controls.profileName.box
  if not (box and box:GetFont()) then return nil end
  local name = string.gsub(string.gsub(box:GetText() or "", "^%s+", ""), "%s+$", "")
  if name == "" then return nil end
  return name
end

local function clearName()
  local box = parts.controls.profileName and parts.controls.profileName.box
  if box and box:GetFont() then box:SetText("") end
  if box and box.ClearFocus then box:ClearFocus() end
end

local function freeName(base)
  local taken = {}
  for _, name in ipairs(Noir.Options.Profiles()) do taken[name] = true end
  if not taken[base] then return base end
  local n = 2
  while taken[base .. " " .. n] do n = n + 1 end
  return base .. " " .. n
end

local function makeProfile(copyFrom)
  local Options = Noir.Options
  local name = typedName() or freeName(copyFrom and (copyFrom .. " copy") or "Profile")
  local good, reason = Options.NewProfile(name, copyFrom)
  if not good then
    Noir.Print("No profile was made: " .. tostring(reason) .. ".")
    return
  end
  clearName()
  Options.UseProfile(name)
  Noir.Print("The profile " .. name .. " is made and in use.")
  draw()
end

local function deleteProfile()
  local Options = Noir.Options
  local items = {}
  for _, name in ipairs(Options.Profiles()) do
    if name ~= Options.Profile() then
      local chosen = name
      items[#items + 1] = { text = chosen, on = function()
        Panel.Confirm(string.format(SettingsPanel.DELETE_QUESTION, chosen), function()
          local good, reason = Options.DeleteProfile(chosen)
          if not good then Noir.Print("The profile was not deleted: " .. tostring(reason) .. ".") end
          draw()
        end)
      end }
    end
  end
  if #items == 0 then
    Noir.Print("There is no other profile to delete; the profile in use cannot be deleted.")
    return
  end
  Noir.Menu.Open(items, { title = "Delete a profile" })
end

local function profileItems()
  local Options = Noir.Options
  local items = {}
  for _, name in ipairs(Options.Profiles()) do
    local chosen = name
    items[#items + 1] = {
      text = chosen, checked = function() return Options.Profile() == chosen end,
      on = function()
        Options.UseProfile(chosen)
        draw()
      end,
    }
  end
  return items
end

-- The readable names of the "accent" choices (the stored value stays the lowercase key).
SettingsPanel.THEME_LABELS = {
  class = "Class color (automatic)", warrior = "Warrior", paladin = "Paladin", hunter = "Hunter", rogue = "Rogue",
  priest = "Priest", shaman = "Shaman", mage = "Mage", warlock = "Warlock", druid = "Druid", gold = "Gold",
  black = "Black",
}

local function themeLabel(value)
  return SettingsPanel.THEME_LABELS[value] or tostring(value)
end

-- The choices of a word option, applied at once (the theme and the font size repaint and lay out every window
-- live: Theme.Repaint, Theme.Refont; no reload, which the client may refuse). labels: an optional value -> words
-- table for the menu rows.
local function choiceItems(key, labels)
  return function()
    local items = {}
    for _, choice in ipairs(Noir.Options.RANGES[key].choices) do
      local value = choice
      items[#items + 1] = {
        text = labels and labels[value] or value, checked = function() return option(key) == value end,
        on = function()
          if option(key) ~= value then setOption(key, value) end
        end,
      }
    end
    return items
  end
end
local fontItems = choiceItems("fontSize")
local accentItems = choiceItems("accent", SettingsPanel.THEME_LABELS)

local function reloadSection()
  local Guide, Progress = Noir.Guide, Noir.Progress
  local id = Guide and Guide.Current()
  if id and Progress and type(Progress.Load) == "function" then Progress.Load(id) end
end

local function setGroupQuests(on)
  if setOption("groupQuests", on) and Noir.char then
    Noir.Table(Noir.Table(Noir.char, "guide"), "setup").groupQuests = on
  end
end

local function tick(key, text, extra)
  local def = { key = key, kind = "tick", text = text }
  for k, v in pairs(extra or {}) do def[k] = v end
  return def
end

local function slider(key, text, step, unit)
  return { key = key, kind = "slider", text = text, step = step, unit = unit }
end

local function button(key, text, on)
  return { key = key, kind = "button", text = text, on = on }
end

SettingsPanel.CONTROLS = {
  General = {
    tick("shown", "Show Noir Guides", { set = function(on) Screen.SetShown(on) end }),
    tick("locked", "Lock windows"),
    tick("hideInRaid", "Hide in raids"),
    tick("minimap", "Minimap button"),
    slider("minimapAngle", "Minimap button position", 5, "degrees"),
    button("wizard", "Open setup wizard", later("Wizard", "Open")),
    button("cleanup", "Open quest cleanup", later("Cleanup", "Open")),
    button("bug", "Report a problem", later("Diagnostics", "Report")),
  },
  ["Guide window"] = {
    tick("windowHidden", "Hide the guide window (the arrow and pins stay)"),
    tick("cardsBelow", "Current steps below the window"),
    slider("windowScale", "Window scale", 0.05, "percent"),
    { key = "fontSize", kind = "choice", text = "Font size", items = fontItems, value = function() return option("fontSize") end },
    { key = "accent", kind = "choice", text = "Theme", items = accentItems, value = function() return option("accent") end,
      label = themeLabel },
    slider("backgroundAlpha", "Background opacity", 0.05, "percent"),
    tick("stepList", "Show the step list"),
    tick("hideFinished", "Hide finished steps"),
    tick("otherSections", "Show sections for other races and classes"),
    tick("highlight", "Colour named things by meaning"),
    tick("itemButtons", "Item buttons"),
    tick("buttonBackground", "Item button background"),
    slider("buttonScale", "Item and target button scale", 0.1, "percent"),
    button("resetButtons", "Reset item buttons", later("Buttons", "Reset")),
    { key = "preview", kind = "button",
      text = function() return Screen.IsPreview() and "End the preview" or "Preview window positions" end,
      on = function() Screen.Preview(not Screen.IsPreview()) end },
  },
  Navigation = {
    tick("arrow", "Show the arrow"),
    slider("arrowScale", "Arrow scale", 0.05, "percent"),
    slider("arrowText", "Arrow text size", 1),
    tick("minimapPins", "Pins on the minimap"),
    tick("pinRing", "Ring on the current pin"),
    slider("worldPins", "Upcoming steps on the maps", 1),
    slider("pinSize", "Pin size", 0.05, "percent"),
    slider("pinMerge", "Merge distance", 0.05),
    slider("pinAlpha", "Pin background opacity", 0.05, "percent"),
    button("resetArrow", "Reset arrow", later("Arrow", "Reset")),
  },
  Automation = {
    tick("autoQuests", "Accept and hand in quests"),
    tick("guideRewards", "Choose the guide's rewards"),
    tick("rewardMarker", "Mark the reward that sells best"),
    tick("bestReward", "Take the reward that sells best"),
    tick("train", "Train spells"),
    tick("flights", "Take flights"),
    tick("hearth", "Set the hearthstone"),
    tick("dialogue", "Pick dialogue options"),
    tick("buy", "Buy what the steps need"),
    tick("sellJunk", "Sell grey items at vendors"),
    tick("targetButtons", "Target buttons"),
    tick("nameplates", "Longer nameplate range"),
    tick("markers", "Raid markers on targets"),
  },
  Route = {
    tick("outlevel", "Skip content you outlevel", { ask = SettingsPanel.OUTLEVEL_QUESTION, after = reloadSection }),
    tick("groupQuests", "Group quests", { set = setGroupQuests }),
    tick("talents", "Talent guides"),
    { key = "profession", kind = "choice", text = "Profession to level with the route", items = professionItems,
      value = plannedNames, keep = true },
  },
  Advanced = {
    tick("neverSkip", "Never skip steps by themselves"),
    tick("offerCleanup", "Offer quest cleanup after changing section"),
    tick("conflicts", "Warn about conflicting addons"),
    tick("debug", "Debug"),
    button("findPlace", "Find my place again", later("Menu", "FindPlace")),
  },
  Profiles = {
    { key = "profile", kind = "choice", text = "Profile in use", items = profileItems,
      value = function() return Noir.Options.Profile() end },
    { key = "profileName", kind = "text", text = "Name for a new profile" },
    button("newProfile", "New profile", function() makeProfile(nil) end),
    button("copyProfile", "Copy this profile", function() makeProfile(Noir.Options.Profile()) end),
    button("deleteProfile", "Delete a profile", deleteProfile),
    button("resetProfile", "Reset this profile", function()
      Panel.Confirm(string.format(SettingsPanel.RESET_QUESTION, Noir.Options.Profile()), function()
        Noir.Options.ResetProfile()
        draw()
      end)
    end),
    button("defaultProfile", "Use as default for new characters", function()
      local name = Noir.Options.Profile()
      Noir.Options.SetDefaultProfile(name)
      Noir.Print("New characters start with the profile " .. name .. ".")
      draw()
    end),
    button("resetProgress", "Reset guide progress for this character", function()
      Panel.Confirm(SettingsPanel.PROGRESS_QUESTION, function()
        local guide = Noir.Guide
        if guide and type(guide.Reset) == "function" then guide.Reset() end
      end)
    end),
  },
}

local function valueOf(def)
  if def.kind == "tick" or def.kind == "slider" then return option(def.key) end
  if def.kind == "choice" then return def.value() end
  if def.kind == "text" then
    local box = parts.controls[def.key] and parts.controls[def.key].box
    return box and box:GetFont() and box:GetText() or ""
  end
  return nil
end

local function textOf(def)
  if type(def.text) == "function" then return def.text() end
  return def.text
end

local function toggle(def)
  local on = not (option(def.key) == true)
  local function apply()
    if def.set then def.set(on) else setOption(def.key, on) end
    if def.after then def.after() end
    draw()
  end
  if def.ask then Panel.Confirm(def.ask, apply) else apply() end
end

-- A slider value on its step, inside the option's range.
local function snap(def, value)
  local range = Noir.Options.RANGES[def.key]
  local step = def.step
  value = range.min + math.floor((value - range.min) / step + 0.5) * step
  if value < range.min then value = range.min end
  if value > range.max then value = range.max end
  return math.floor(value * 1e6 + 0.5) / 1e6
end

local function setSlider(def, value)
  value = snap(def, value)
  if value ~= option(def.key) then setOption(def.key, value) end
  draw()
end

-- The slider's value under the cursor, or nil when the track has no place yet.
local function fromCursor(control)
  local track = control.track
  local left, width = track:GetLeft(), track:GetWidth()
  local scale = track:GetEffectiveScale()
  if not (left and width and width > 0 and scale and scale > 0 and GetCursorPosition) then return nil end
  local x = GetCursorPosition() / scale
  local fraction = (x - left) / width
  if fraction < 0 then fraction = 0 end
  if fraction > 1 then fraction = 1 end
  local range = Noir.Options.RANGES[control.def.key]
  return range.min + fraction * (range.max - range.min)
end

local function shownValue(def, value)
  if def.unit == "percent" then return string.format("%d%%", math.floor(value * 100 + 0.5)) end
  if def.unit == "degrees" then return string.format("%d", math.floor(value + 0.5)) end
  if def.step >= 1 then return string.format("%d", value) end
  return string.format("%.2f", value)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------------------------------------------------

local function plainRow(parent, onClick)
  local row = Panel.Row(parent, onClick)
  row.right = Panel.Text(row, "body", "dim", "RIGHT")
  return row
end

local function buildSlider(control)
  local m = metrics()
  local def = control.def
  local row = CreateFrame("Frame", nil, list.child)
  row:EnableMouse(true)
  row:EnableMouseWheel(true)
  row:RegisterForDrag("LeftButton")
  row.text = Panel.Text(row, "body", "paper")
  row.right = Panel.Text(row, "body", "dim", "RIGHT")
  local track = CreateFrame("Frame", nil, row)
  track:SetHeight(4)
  -- a well with a black hairline, and a glossy accent fill, as the guide window draws its rail
  local back = track:CreateTexture(nil, "BACKGROUND")
  Theme.Paint(back, "well")
  back:SetAllPoints(track)
  Panel.Edges(track, "BACKGROUND", "ink", -1)
  control.fill = track:CreateTexture(nil, "ARTWORK")
  control.fill:SetTexture(Theme.Texture("bar"))
  Theme.Tint(control.fill, "lamp")
  control.fill:SetPoint("TOPLEFT", track, "TOPLEFT", 0, 0)
  control.fill:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT", 0, 0)
  control.thumb = track:CreateTexture(nil, "OVERLAY")
  Theme.Paint(control.thumb, "paper")
  control.thumb:SetSize(6, 12)
  control.track = track
  row:SetScript("OnMouseUp", function()
    local value = fromCursor(control)
    if value then setSlider(def, value) end
  end)
  row:SetScript("OnMouseWheel", function(_, delta)
    setSlider(def, (option(def.key) or 0) + (delta or 0) * def.step)
  end)
  row:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local value = fromCursor(control)
      if value and snap(def, value) ~= option(def.key) then setSlider(def, value) end
    end)
  end)
  row:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    local value = fromCursor(control)
    if value then setSlider(def, value) end
  end)
  row:Hide()
  control.frame = row
  control.height = rowHeight() + 4 + 2 * m.gap + 4
end

local function buildText(control)
  local m = metrics()
  local row = CreateFrame("Frame", nil, list.child)
  row.text = Panel.Text(row, "body", "dim")
  local box = CreateFrame("EditBox", nil, row)
  box:SetAutoFocus(false)
  if box.SetMaxLetters then box:SetMaxLetters(NAME_LETTERS) end
  if box.SetTextInsets then box:SetTextInsets(4, 4, 2, 2) end
  Theme.Font(box, "body")
  if box.SetTextColor then Theme.TextColor(box, "paper") end
  local back = box:CreateTexture(nil, "BACKGROUND")
  Theme.Paint(back, "strip")
  back:SetAllPoints(box)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  control.box = box
  row:Hide()
  control.frame = row
  control.height = 2 * rowHeight() + m.gap
end

local function buildControl(def)
  local control = { def = def }
  parts.controls[def.key] = control
  if def.kind == "slider" then
    buildSlider(control)
  elseif def.kind == "text" then
    buildText(control)
  else
    control.frame = plainRow(list.child, function(_, mouse)
      if mouse == "RightButton" then return end
      if def.kind == "tick" then
        toggle(def)
      elseif def.kind == "choice" then
        Noir.Menu.Open(def.items(), { title = def.text })
      elseif def.on then
        def.on()
        draw()
      end
    end)
    control.height = rowHeight()
  end
end

local function build()
  if frame then return end
  local m = metrics()
  frame = CreateFrame("Frame", nil, UIParent)
  SettingsPanel.frame = frame
  frame.name = SettingsPanel.NAME -- what the legacy options window lists
  frame:SetSize(SettingsPanel.WIDTH, 400)
  local bay = frame:CreateTexture(nil, "BACKGROUND")
  Theme.Paint(bay, "bay", m.alpha)
  bay:SetAllPoints(frame)
  parts.title = Panel.Text(frame, "name", "paper")
  parts.title:SetPoint("TOPLEFT", frame, "TOPLEFT", m.pad, -m.pad)
  parts.title:SetWidth(SettingsPanel.WIDTH - 2 * m.pad)
  Theme.SetText(parts.title, SettingsPanel.NAME)
  parts.title:Show()
  for _, name in ipairs(SettingsPanel.TABS) do
    local tab = name
    local row = Panel.Row(frame, function() SettingsPanel.Show(tab) end)
    row.now = row:CreateTexture(nil, "BORDER")
    Theme.Paint(row.now, "lamp")
    row.now:SetWidth(m.lamp)
    row.now:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.now:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    parts.tabs[tab] = row
  end
  list = Panel.ScrollList(frame, { step = 3 * rowHeight() })
  list.child:SetWidth(contentWidth() + 2 * m.pad) -- before the first row is made: rows take their width from it
  for _, tab in ipairs(SettingsPanel.TABS) do
    for _, def in ipairs(SettingsPanel.CONTROLS[tab]) do buildControl(def) end
  end
  frame:SetScript("OnShow", function() draw() end)
  -- Hidden until opened: the options window shows its page itself when the player picks it.
  frame:Hide()

  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    SettingsPanel.mode = "modern"
    category = Settings.RegisterCanvasLayoutCategory(frame, SettingsPanel.NAME)
    Settings.RegisterAddOnCategory(category)
  elseif InterfaceOptions_AddCategory then
    SettingsPanel.mode = "legacy"
    InterfaceOptions_AddCategory(frame)
  else
    SettingsPanel.mode = "none"
    frame:SetFrameStrata("HIGH")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
      if not option("locked") then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
      Screen.Pull(self)
    end)
    parts.close = Panel.Row(frame, function() frame:Hide() end)
    frame:Hide()
    Screen.Place(frame, "dialog")
  end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------------------------------------------

local function drawRowText(row, words, color, left, right)
  local m = metrics()
  row.text:ClearAllPoints()
  row.text:SetPoint("TOPLEFT", row, "TOPLEFT", left, -m.gap)
  row.text:SetWidth(math.max(10, row:GetWidth() - left - (right or 0) - m.gap))
  if row.text.SetWordWrap then row.text:SetWordWrap(false) end
  Theme.SetText(row.text, words or "")
  Theme.TextColor(row.text, color)
  row.text:Show()
end

local function drawControl(control, y, width)
  local m = metrics()
  local def, row = control.def, control.frame
  row:SetSize(width, control.height)
  row:ClearAllPoints()
  row:SetPoint("TOPLEFT", list.child, "TOPLEFT", 0, -y)
  local value = valueOf(def)
  if def.kind == "tick" then
    Theme.Paint(row.box, value and "lamp" or "track")
    row.box:Show()
    drawRowText(row, textOf(def), "paper", m.gap + Theme.sizes.body + m.gap)
    row.right:Hide()
  elseif def.kind == "button" then
    row.box:Hide()
    drawRowText(row, textOf(def), "lamp", m.gap)
    row.right:Hide()
  elseif def.kind == "choice" then
    row.box:Hide()
    local rightWidth = math.floor(width * 0.4)
    drawRowText(row, textOf(def), "paper", m.gap, rightWidth)
    row.right:ClearAllPoints()
    row.right:SetPoint("TOPRIGHT", row, "TOPRIGHT", -m.gap, -m.gap)
    row.right:SetWidth(rightWidth)
    if row.right.SetWordWrap then row.right:SetWordWrap(false) end
    local words = def.label and def.label(value) or tostring(value)
    Theme.SetText(row.right, words .. "  >")
    row.right:Show()
  elseif def.kind == "slider" then
    local valueWidth = 50
    drawRowText(row, textOf(def), "paper", m.gap, valueWidth)
    row.right:ClearAllPoints()
    row.right:SetPoint("TOPRIGHT", row, "TOPRIGHT", -m.gap, -m.gap)
    row.right:SetWidth(valueWidth)
    Theme.SetText(row.right, shownValue(def, value))
    row.right:Show()
    local track = control.track
    local trackWidth = width - 2 * m.gap
    track:ClearAllPoints()
    track:SetPoint("TOPLEFT", row, "TOPLEFT", m.gap, -(rowHeight() + m.gap))
    track:SetWidth(trackWidth)
    local range = Noir.Options.RANGES[def.key]
    local fraction = (value - range.min) / (range.max - range.min)
    control.fill:SetWidth(math.max(1, fraction * trackWidth))
    control.thumb:ClearAllPoints()
    control.thumb:SetPoint("CENTER", track, "LEFT", fraction * trackWidth, 0)
  elseif def.kind == "text" then
    drawRowText(row, textOf(def), "dim", m.gap)
    local box = control.box
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", row, "TOPLEFT", m.gap, -rowHeight())
    box:SetSize(width - 2 * m.gap, rowHeight())
  end
  row:Show()
end

draw = function()
  if not frame then return end
  local m = metrics()
  local top = m.pad + Theme.sizes.name + 2 * m.gap
  local h = rowHeight()
  for i, name in ipairs(SettingsPanel.TABS) do
    local row = parts.tabs[name]
    row:SetSize(SettingsPanel.TAB_WIDTH, h)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", m.pad, -(top + (i - 1) * (h + 1)))
    drawRowText(row, name, name == shownTab and "lamp" or "dim", m.gap + m.lamp)
    if name == shownTab then row.now:Show() else row.now:Hide() end
    row:Show()
  end
  local tabsHeight = #SettingsPanel.TABS * (h + 1)
  local width = contentWidth()
  local y = 0
  for _, def in ipairs(SettingsPanel.CONTROLS[shownTab]) do
    local control = parts.controls[def.key]
    drawControl(control, y, width)
    y = y + control.height + 1
  end
  local shown = {}
  for _, def in ipairs(SettingsPanel.CONTROLS[shownTab]) do shown[def.key] = true end
  for key, control in pairs(parts.controls) do
    if not shown[key] then control.frame:Hide() end
  end
  local bottom = m.pad
  if parts.close then
    bottom = m.pad + h + m.gap
  end
  if SettingsPanel.mode == "none" then
    local wanted = top + math.max(tabsHeight, y) + bottom
    Screen.Fit(frame, wanted)
  end
  local left = m.pad + SettingsPanel.TAB_WIDTH + m.gap
  list.frame:ClearAllPoints()
  list.frame:SetPoint("TOPLEFT", frame, "TOPLEFT", left, -top)
  list.frame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -m.pad, bottom)
  list.child:SetWidth(width + BAR)
  list:SetContentHeight(y)
  if parts.close then
    local close = parts.close
    close:SetSize(SettingsPanel.TAB_WIDTH, h)
    close:ClearAllPoints()
    close:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", m.pad, m.pad)
    drawRowText(close, "Close", "lamp", m.gap)
    close:Show()
  end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------------------------------------------

local function validTab(tab)
  for _, name in ipairs(SettingsPanel.TABS) do
    if name == tab then return true end
  end
  return false
end

-- Shows a tab on the page as it is (opened or not).
function SettingsPanel.Show(tab)
  if validTab(tab) and tab ~= shownTab then
    shownTab = tab
    list:Scroll(0)
  end
  draw()
end

function SettingsPanel.Open(tab)
  build()
  if validTab(tab) then shownTab = tab end
  if inCombat() then
    pending = shownTab
    return
  end
  pending = nil
  if SettingsPanel.mode == "modern" then
    local id = category
    if type(category) == "table" then
      id = (type(category.GetID) == "function" and category:GetID()) or category.ID or category
    end
    Settings.OpenToCategory(id)
  elseif SettingsPanel.mode == "legacy" then
    -- The first call can land on the options window's first page when the AddOns list was never shown; the
    -- second one then finds the page.
    InterfaceOptionsFrame_OpenToCategory(frame)
    InterfaceOptionsFrame_OpenToCategory(frame)
  else
    frame:Show()
    Screen.Keep(frame)
  end
  list:Scroll(0)
  draw()
end

function SettingsPanel.Read()
  if not frame then return { shown = false, tab = shownTab, controls = {} } end
  local controls = {}
  for i, def in ipairs(SettingsPanel.CONTROLS[shownTab]) do
    controls[i] = { key = def.key, kind = def.kind, value = valueOf(def) }
  end
  return { shown = frame:IsVisible() and true or false, tab = shownTab, controls = controls }
end

function SettingsPanel.Control(key)
  build()
  local control = parts.controls[key]
  if not control then return nil end
  return control.box or control.frame
end

function SettingsPanel.Tab(name)
  build()
  return parts.tabs[name]
end

function SettingsPanel.Track(key)
  build()
  local control = parts.controls[key]
  return control and control.track
end

function SettingsPanel.CloseButton()
  build()
  return parts.close
end

-- ---------------------------------------------------------------------------------------------------------------
-- The conflict warning
-- ---------------------------------------------------------------------------------------------------------------

local function addonLoaded(name)
  local check = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  if type(check) ~= "function" then return false end
  local good, loaded = pcall(check, name)
  return good and loaded and true or false
end

local function warnConflicts()
  if warned or option("conflicts") == false then return end
  for _, name in ipairs(SettingsPanel.CONFLICTS) do
    if addonLoaded(name) then
      warned = true
      Noir.Print(name .. " is loaded: its arrow and Noir's can point to different places. Turn one of them off, or "
        .. "this warning in the settings (Advanced).")
      return
    end
  end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------------------------------------------

local function redraw()
  if frame and frame:IsVisible() then draw() end
end

Noir.On("NOIR_INIT", build)
Noir.On("NOIR_LOGIN", function()
  Noir.After(SettingsPanel.CONFLICT_SECONDS, warnConflicts)
end)
Noir.On("PLAYER_REGEN_ENABLED", function()
  if pending then SettingsPanel.Open(pending) end
end)
Noir.On("NOIR_OPTION", redraw)
Noir.On("NOIR_PROFILE", redraw)
Noir.On("NOIR_PROFESSIONS", redraw)
