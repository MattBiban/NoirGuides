-- Noir Guides, GPLv3. See LICENSE.
-- Panel: the pieces the addon's other windows are built from (the menu, the quest cleanup, the bug report), in the
-- guide window's design (DESIGN.md): the game's tooltip panel with pixel-sharp hairlines, text in the design's type,
-- rows that light up in the lamp under the mouse. Plain frames, textures and font strings only: no template, no
-- backdrop, no font object, nothing named.
--
--   Panel.New(width)                      -> a hidden frame on the DIALOG strata, centered, with the bay behind it
--                                            and the window's double hairline (Panel.Border)
--   Panel.Edges(owner, layer, color, inset [, alpha [, around]])  -> four 1-pixel lines around `around` (default
--                                            owner), `inset` pixels in (-1: just outside)
--   Panel.Border(frame [, color])         the double hairline: ink just outside, `color` (default the lamp) just
--                                            inside; -> { outline = edges, border = edges }
--   Panel.Sheen(owner [, alpha])          -> the light on a plate: the sheen texture in paper at 0.07, over owner
--   Panel.Tick(row, tick)                 a row's tick box: nil hides it, true ticks it, false shows it empty
--   Panel.Text(parent, role, color [, justify])   -> a hidden font string in the design's type
--   Panel.Row(parent, onClick)            -> a frame that takes the mouse: row.text, row.box (a tick box, hidden
--                                            until row:SetTick is used), row.lit; onClick(row, button)
--   Panel.Layout(frame)                   -> a writer that stacks blocks from the top: :Text(fontString, words),
--                                            :Row(row, words [, tick]), :Gap(), :Finish()
--   Panel.ScrollList(parent [, opts])     -> a list that scrolls: list.frame (a ScrollFrame the caller anchors),
--                                            list.child (rows go here, from its top left), list.bar (the scrollbar,
--                                            shown when the rows do not fit), list:SetContentHeight(h),
--                                            list:Scroll(offset), list:Offset(), list:Range(), list:View(), list.min
--                                            (the least offset, default 0), list.onScroll(offset); the mouse wheel
--                                            scrolls by opts.step (default 40), a click on the bar pages toward the
--                                            cursor and the thumb can be dragged
--   Panel.Confirm(text, onYes, onNo)      the addon's own question with Yes and No, at Screen.DEFAULTS.dialog;
--                                            questions asked while one is open wait their turn. The game's popups
--                                            are never used
--   Panel.ConfirmRead() -> { shown, text }, Panel.ConfirmButton("yes" | "no") -> the button's frame (for tests)
local Noir = Noir
local Theme = Noir.Theme

local Panel = {}
Noir.Panel = Panel

local function metrics()
  return Theme.metrics
end

-- Four 1-pixel lines around a region, as the guide window draws its frames.
function Panel.Edges(owner, layer, color, inset, alpha, around)
  around = around or owner
  inset = inset or 0
  local list = {}
  for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
      { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
    local edge = owner:CreateTexture(nil, layer)
    Theme.Paint(edge, color, alpha)
    local x1 = (side[1]:find("LEFT") and inset) or -inset
    local y1 = (side[1]:find("TOP") and -inset) or inset
    local x2 = (side[2]:find("LEFT") and inset) or -inset
    local y2 = (side[2]:find("TOP") and -inset) or inset
    edge:SetPoint(side[1], around, side[1], x1, y1)
    edge:SetPoint(side[2], around, side[2], x2, y2)
    if side[3] then edge:SetHeight(1) else edge:SetWidth(1) end
    list[#list + 1] = edge
  end
  return list
end

function Panel.Border(frame, color)
  return {
    outline = Panel.Edges(frame, "BORDER", "ink", -1),
    border = Panel.Edges(frame, "BORDER", color or Theme.Border(), 0),
  }
end

function Panel.Sheen(owner, alpha)
  local tex = owner:CreateTexture(nil, "BORDER")
  local path = Theme.Texture("sheen")
  if path then tex:SetTexture(path) end
  Theme.Tint(tex, "paper", alpha or 0.07)
  tex:SetAllPoints(owner)
  return tex
end

function Panel.New(width)
  local frame = CreateFrame("Frame", nil, UIParent)
  frame:SetFrameStrata("DIALOG")
  frame:SetSize(width, 4 * metrics().pad)
  -- Hung from near the top of the screen so it grows downward, kept on the screen, and moved by dragging it.
  frame:SetPoint("TOP", UIParent, "TOP", 0, -120)
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  frame:EnableMouse(true) -- clicks on the panel do not fall through to the world
  local bay = frame:CreateTexture(nil, "BACKGROUND")
  Theme.Paint(bay, "bay", metrics().alpha)
  bay:SetAllPoints(frame)
  frame.edges = Panel.Border(frame)
  frame:Hide()
  return frame
end

function Panel.Text(parent, role, color, justify)
  local fontString = parent:CreateFontString(nil, "OVERLAY")
  Theme.Font(fontString, role)
  Theme.TextColor(fontString, color)
  fontString:SetJustifyH(justify or "LEFT")
  fontString:SetJustifyV("TOP")
  if fontString.SetWordWrap then fontString:SetWordWrap(true) end
  fontString:Hide()
  return fontString
end

local function light(row, on)
  row.lit = on and true or false
  if on then row.glow:Show() else row.glow:Hide() end
end

function Panel.Row(parent, onClick)
  local m = metrics()
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(parent:GetWidth() - 2 * m.pad, Theme.sizes.body + 2 * m.gap)
  row:EnableMouse(true)
  -- Under the mouse: the lamp, faint, behind the row.
  row.glow = row:CreateTexture(nil, "BACKGROUND")
  Theme.Paint(row.glow, "lamp", 0.16)
  row.glow:SetAllPoints(row)
  -- The tick box: a well inside a 1-pixel line, filled with the lamp when ticked.
  row.box = row:CreateTexture(nil, "ARTWORK")
  row.box:SetSize(Theme.sizes.body - 2, Theme.sizes.body - 2)
  row.box:SetPoint("LEFT", row, "LEFT", m.gap, 0)
  row.box:Hide()
  row.boxEdges = Panel.Edges(row, "ARTWORK", "track", 0, nil, row.box)
  for _, edge in ipairs(row.boxEdges) do edge:Hide() end
  row.text = Panel.Text(row, "body", "paper")
  light(row, false)
  row:SetScript("OnEnter", function(self) light(self, true) end)
  row:SetScript("OnLeave", function(self) light(self, false) end)
  row:SetScript("OnMouseUp", function(self, button)
    if onClick then onClick(self, button) end
  end)
  row:Hide()
  return row
end

-- A tick box: nil hides it, true or false shows it ticked (the lamp inside a lamp line) or empty (a well inside a
-- track line).
local function setTick(row, tick)
  row.tick = tick
  local edges = row.boxEdges or {}
  if tick == nil then
    row.box:Hide()
    for _, edge in ipairs(edges) do edge:Hide() end
    return
  end
  Theme.Paint(row.box, tick and "lamp" or "well")
  row.box:Show()
  for _, edge in ipairs(edges) do
    Theme.Paint(edge, tick and "lamp" or "track")
    edge:Show()
  end
end
Panel.Tick = setTick

-- Stacks blocks from the top of a frame down, each as tall as its text, and sets the frame's height at the end.
function Panel.Layout(frame)
  local m = metrics()
  local width = frame:GetWidth() - 2 * m.pad
  local writer = { y = m.pad }

  function writer:Text(fontString, words)
    if not words or words == "" or not fontString:GetFont() then
      fontString:Hide()
      return
    end
    fontString:SetWidth(width)
    Theme.SetText(fontString, words)
    fontString:ClearAllPoints()
    fontString:SetPoint("TOPLEFT", frame, "TOPLEFT", m.pad, -self.y)
    fontString:Show()
    self.y = self.y + fontString:GetStringHeight() + m.gap
  end

  function writer:Row(row, words, tick)
    if not words then
      row:Hide()
      return
    end
    setTick(row, tick)
    local textLeft = m.gap + (tick ~= nil and (Theme.sizes.body + m.gap) or 0)
    local text = row.text
    if text:GetFont() then
      text:SetWidth(width - textLeft - m.gap)
      Theme.SetText(text, words)
      text:ClearAllPoints()
      text:SetPoint("TOPLEFT", row, "TOPLEFT", textLeft, -m.gap)
      text:Show()
    end
    local height = math.max(Theme.sizes.body, text:GetFont() and text:GetStringHeight() or 0) + 2 * m.gap
    row:SetSize(width, height)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", m.pad, -self.y)
    row:Show()
    self.y = self.y + height + 1
  end

  function writer:Gap()
    self.y = self.y + m.gap
  end

  function writer:Finish()
    local height = self.y + m.pad
    frame:SetHeight(height)
    -- A panel taller than the room below its top edge is drawn smaller so all of it stays on the screen.
    local room = (UIParent:GetHeight() or 0) - 160
    local scale = 1
    if room > 0 and height > room then scale = room / height end
    frame:SetScale(scale)
  end

  return writer
end

-- The words a row shows, or nil when it is hidden or has none.
function Panel.RowText(row)
  if not (row and row:IsShown() and row.text:IsShown()) then return nil end
  local words = row.text:GetText()
  if words == nil or words == "" then return nil end
  return words
end

-- ---------------------------------------------------------------------------------------------------------------
-- A list that scrolls
-- ---------------------------------------------------------------------------------------------------------------

local BAR_WIDTH = 4
local THUMB_LEAST = 12

-- The cursor's height in the frame's own units, from the bottom of the screen.
local function cursorY(frame)
  if not GetCursorPosition then return nil end
  local _, y = GetCursorPosition()
  local scale = frame:GetEffectiveScale()
  if not (y and scale and scale > 0) then return nil end
  return y / scale
end

function Panel.ScrollList(parent, opts)
  opts = opts or {}
  local list = { min = 0, offset = 0, content = 0, step = opts.step or 40 }
  local scroll = CreateFrame("ScrollFrame", nil, parent)
  scroll:EnableMouseWheel(true)
  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(1, 1)
  scroll:SetScrollChild(child)
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetWidth(BAR_WIDTH)
  bar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, 0)
  bar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 0, 0)
  bar:EnableMouse(true)
  local track = bar:CreateTexture(nil, "BACKGROUND")
  Theme.Paint(track, "well")
  track:SetAllPoints(bar)
  local thumb = CreateFrame("Frame", nil, bar)
  thumb:SetWidth(BAR_WIDTH)
  thumb:SetHeight(THUMB_LEAST)
  thumb:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
  thumb:EnableMouse(true)
  thumb:RegisterForDrag("LeftButton")
  local fill = thumb:CreateTexture(nil, "ARTWORK")
  local glossy = Theme.Texture("bar")
  if glossy then fill:SetTexture(glossy) end
  Theme.Tint(fill, "faint")
  fill:SetAllPoints(thumb)
  bar:Hide()
  list.frame, list.child, list.bar, list.thumb = scroll, child, bar, thumb

  function list:View()
    return scroll:GetHeight() or 0
  end

  function list:Range()
    return math.max(0, self.content - self:View())
  end

  local function thumbPlace()
    local view, range = list:View(), list:Range()
    if range <= 0 or view <= 0 then
      bar:Hide()
      return
    end
    bar:Show()
    local height = math.max(THUMB_LEAST, view * view / list.content)
    if height > view then height = view end
    thumb:SetHeight(height)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, -(view - height) * list.offset / range)
  end

  function list:Scroll(offset)
    local range = self:Range()
    local least = math.min(self.min or 0, range)
    offset = tonumber(offset) or 0
    if offset < least then offset = least end
    if offset > range then offset = range end
    self.offset = offset
    scroll:SetVerticalScroll(offset)
    thumbPlace()
    if self.onScroll then self.onScroll(offset) end
    return offset
  end

  function list:Offset()
    return self.offset
  end

  function list:SetContentHeight(height)
    self.content = math.max(0, height or 0)
    child:SetWidth(math.max(1, scroll:GetWidth() or 1))
    child:SetHeight(math.max(1, self.content))
    self:Scroll(self.offset)
  end

  scroll:SetScript("OnMouseWheel", function(_, delta)
    list:Scroll(list.offset - (delta or 0) * list.step)
  end)
  -- A click on the bar pages toward the cursor: above the thumb up, below it down.
  bar:SetScript("OnMouseUp", function(self)
    local y = cursorY(self)
    local top = self:GetTop()
    if not (y and top) then return end
    local view, range = list:View(), list:Range()
    if range <= 0 then return end
    local height = thumb:GetHeight()
    local thumbTop = top - (view - height) * list.offset / range
    local page = view * 0.9
    if y < thumbTop - height then
      list:Scroll(list.offset + page)
    elseif y > thumbTop then
      list:Scroll(list.offset - page)
    end
  end)
  -- Dragging the thumb follows the cursor.
  thumb:SetScript("OnDragStart", function(self)
    local startY, startOffset = cursorY(self), list.offset
    if not startY then return end
    self:SetScript("OnUpdate", function()
      local y = cursorY(self)
      local view, range = list:View(), list:Range()
      local free = view - self:GetHeight()
      if not y or range <= 0 or free <= 0 then return end
      list:Scroll(startOffset + (startY - y) * range / free)
    end)
  end)
  thumb:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
  end)
  return list
end

-- ---------------------------------------------------------------------------------------------------------------
-- The addon's own confirmation dialog
-- ---------------------------------------------------------------------------------------------------------------

local CONFIRM_WIDTH = 300
local confirm = { frame = nil, parts = nil, queue = {}, asking = nil }

local function confirmFrame()
  if confirm.frame then return confirm.frame end
  local frame = Panel.New(CONFIRM_WIDTH)
  local parts = {}
  parts.text = Panel.Text(frame, "body", "paper")
  parts.yes = Panel.Row(frame, function() Panel.Answer(true) end)
  parts.no = Panel.Row(frame, function() Panel.Answer(false) end)
  confirm.frame, confirm.parts = frame, parts
  -- Placed and kept on the screen, but not registered with Screen.Register: a question is the answer to something
  -- the player just did (often in the settings, which stay usable while every window is hidden), so hiding the
  -- addon's windows must not hide it and leave the change waiting unseen.
  local Screen = Noir.Screen
  if Screen then Screen.Place(frame, "dialog") end
  frame:Hide()
  return frame
end

local function showNext()
  local nextOne = table.remove(confirm.queue, 1)
  confirm.asking = nextOne
  local frame = confirmFrame()
  if not nextOne then
    frame:Hide()
    return
  end
  local parts = confirm.parts
  local layout = Panel.Layout(frame)
  layout:Text(parts.text, nextOne.text)
  layout:Gap()
  layout:Row(parts.yes, "Yes")
  layout:Row(parts.no, "No")
  layout:Finish()
  frame:Show()
end

-- Answers the question on screen (the Yes and No rows call this).
function Panel.Answer(yes)
  local asked = confirm.asking
  if not asked then return end
  confirm.asking = nil
  if confirm.frame then confirm.frame:Hide() end
  local fn = yes and asked.onYes or asked.onNo
  if type(fn) == "function" then
    local good, err = pcall(fn)
    if not good and Noir.ReportError then Noir.ReportError(err) end
  end
  if not confirm.asking then showNext() end
end

function Panel.Confirm(text, onYes, onNo)
  confirm.queue[#confirm.queue + 1] = { text = tostring(text or ""), onYes = onYes, onNo = onNo }
  if not confirm.asking then showNext() end
end

function Panel.ConfirmRead()
  local frame = confirm.frame
  local shown = frame ~= nil and frame:IsShown() and confirm.asking ~= nil
  return { shown = shown and true or false, text = confirm.asking and confirm.asking.text or nil }
end

function Panel.ConfirmButton(which)
  confirmFrame()
  return which == "no" and confirm.parts.no or confirm.parts.yes
end
