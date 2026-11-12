-- Noir Guides, GPLv3. See LICENSE.
-- Screen: where the addon's windows open and how they stay on the screen (spec 4.1). Every window an interface
-- module creates is placed with Screen.Place, kept with Screen.Keep and registered with Screen.Register under its
-- key in Screen.DEFAULTS; menus open with Screen.AtCursor. Places are saved per profile through Options.
--
--   Screen.DEFAULTS                 key -> { frame point, UIParent point, x, y } in UIParent units
--   Screen.MAX_SHARE                0.9: the most of the screen's height a frame may take (Screen.Fit)
--   Screen.Place(frame, key)        the saved place of `key` (Options.Position) or its default, then Screen.Keep
--   Screen.Keep(frame)              moves the frame inside UIParent now, clamps it, and again after OnSizeChanged,
--                                   OnShow, DISPLAY_SIZE_CHANGED and UI_SCALE_CHANGED
--   Screen.Pull(frame)              moves a frame inside UIParent once (what Keep does on each of those moments)
--   Screen.Save(frame [, key])      saves the frame's top left corner in UIParent units (and its size when it was
--                                   made resizable by Screen.Movable), so a change of scale keeps the corner
--   Screen.Reset(key)               forgets the saved place of `key` and puts its frames at the default
--   Screen.Fit(frame, contentHeight) -> height: the content's height, capped at MAX_SHARE of the screen (the caller
--                                   scrolls the rest); sets it on the frame
--   Screen.AtCursor(frame, side)    -> the side used: opens the frame at the cursor to the "right" or "left",
--                                   flipping when there is no room, then Keep
--   Screen.Movable(frame, key, opts) -> grip or nil: left-drag moves and saves; refused while the "locked" option
--                                   is on unless opts.altWhenLocked and Alt is held; opts.resizable adds a corner
--                                   grip (returned) and Alt-drag resizing, saving the size; opts.minWidth/minHeight
--   Screen.Register(key, frame, preview) every addon window registers here; preview(on) fills it with sample
--                                   content (may be nil)
--   Screen.Allowed()                -> whether windows may show: "shown" on and not in a raid with "hideInRaid"
--   Screen.SetShown(on)             sets "shown" and hides or shows every registered window; the engine keeps
--                                   following the game while they are hidden
--   Screen.Preview(on), Screen.IsPreview() every window's preview on, so the player can place them, and off again
--   Screen.Registered() -> { { key, frame } } every registered window, in the order they registered
--
-- Commands (each also on the main menu or the minimap button, Menu.MOUSE_PATHS): /noir show, hide, toggle (every
-- registered window) and preview (the preview on or off).
--
-- A window that its module shows while windows may not show is hidden again at once and comes back with them. A
-- protected frame (or one holding secure buttons) is not moved, shown or hidden in combat: that waits for
-- PLAYER_REGEN_ENABLED.
local Noir = Noir

local Screen = {}
Noir.Screen = Screen

Screen.MAX_SHARE = 0.9
Screen.DEFAULTS = {
  window = { "LEFT", "LEFT", 20, 80 },
  arrow = { "TOP", "TOP", 0, -100 },
  arrowReset = { "CENTER", "CENTER", 0, 150 },
  items = { "CENTER", "CENTER", 0, -100 },
  targets = { "CENTER", "CENTER", 0, -170 },
  wizard = { "CENTER", "CENTER", 220, 120 },
  dialog = { "CENTER", "CENTER", 0, 60 },
}

local EPSILON = 0.01
local GRIP_SIZE = 20

local kept = {}        -- frame -> true
local keyOf = {}       -- frame -> window key given to Place
local resizable = {}   -- frame -> true for frames made resizable by Movable
local registered = {}  -- key -> { frame, preview }
local order = {}       -- registered keys in the order they came
local hooked = {}      -- frame -> true once Register hooked its OnShow
local held = {}        -- frame -> true: hidden by Screen, to come back with the other windows
local later = {}       -- frame -> true: to pull once combat ends
local previewing = false
local applying = false
local applyAfterCombat = false

local function option(key)
  local options = Noir.Options
  if options then return options.Get(key) end
  return nil
end

local function inCombat()
  return InCombatLockdown and InCombatLockdown() and true or false
end

-- Protected itself or through a secure frame it holds: the game locks it in combat.
local function protected(frame)
  return frame.IsProtected ~= nil and (frame:IsProtected()) and true or false
end

-- From the frame's own units to UIParent units.
local function ratio(frame)
  local ui, own = UIParent:GetEffectiveScale(), frame:GetEffectiveScale()
  if not (ui and own and ui > 0 and own > 0) then return 1 end
  return own / ui
end

local function screenSize()
  return UIParent:GetWidth(), UIParent:GetHeight()
end

-- The frame's edges in UIParent units, or nil before it has a place.
local function edges(frame)
  local left, bottom, right, top = frame:GetLeft(), frame:GetBottom(), frame:GetRight(), frame:GetTop()
  if not (left and bottom and right and top) then return nil end
  local r = ratio(frame)
  return left * r, bottom * r, right * r, top * r
end

function Screen.Pull(frame)
  if inCombat() and protected(frame) then
    later[frame] = true
    return
  end
  local left, bottom, right, top = edges(frame)
  if not left then return end
  local width, height = screenSize()
  local dx, dy = 0, 0
  if right - left >= width or left < 0 then
    dx = -left
  elseif right > width then
    dx = width - right
  end
  if top - bottom >= height or top > height then
    dy = height - top
  elseif bottom < 0 then
    dy = -bottom
  end
  if math.abs(dx) < EPSILON and math.abs(dy) < EPSILON then return end
  -- Every anchor moves by the same amount, so a frame hung from another keeps its anchor point.
  local r = ratio(frame)
  local points = {}
  for i = 1, frame:GetNumPoints() do points[i] = { frame:GetPoint(i) } end
  frame:ClearAllPoints()
  for i = 1, #points do
    local p = points[i]
    frame:SetPoint(p[1], p[2], p[3], (p[4] or 0) + dx / r, (p[5] or 0) + dy / r)
  end
end

local function pullAll()
  for frame in pairs(kept) do
    if frame:IsShown() then Screen.Pull(frame) end
  end
end

function Screen.Keep(frame)
  if not kept[frame] then
    kept[frame] = true
    if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
    frame:HookScript("OnSizeChanged", function(self) Screen.Pull(self) end)
    frame:HookScript("OnShow", function(self) Screen.Pull(self) end)
  end
  Screen.Pull(frame)
end

function Screen.Place(frame, key)
  local default = Screen.DEFAULTS[key]
  if not default then error("Screen.Place(frame, key): unknown window key " .. tostring(key), 2) end
  keyOf[frame] = key
  if inCombat() and protected(frame) then
    later[frame] = true
    return
  end
  local saved = Noir.Options and Noir.Options.Position(key)
  local r = ratio(frame)
  frame:ClearAllPoints()
  if saved then
    if saved[5] and saved[6] then frame:SetSize(saved[5], saved[6]) end
    frame:SetPoint(saved[1], UIParent, saved[2], saved[3] / r, saved[4] / r)
  else
    frame:SetPoint(default[1], UIParent, default[2], default[3] / r, default[4] / r)
  end
  Screen.Keep(frame)
end

function Screen.Save(frame, key)
  key = key or keyOf[frame]
  if not key or not Noir.Options then return false end
  local left, _, _, top = edges(frame)
  if not left then return false end
  local place = { "TOPLEFT", "BOTTOMLEFT", left, top }
  if resizable[frame] then place[5], place[6] = frame:GetWidth(), frame:GetHeight() end
  return Noir.Options.SavePosition(key, place)
end

function Screen.Reset(key)
  if Noir.Options then Noir.Options.SavePosition(key, nil) end
  for frame, k in pairs(keyOf) do
    if k == key then Screen.Place(frame, key) end
  end
end

function Screen.Fit(frame, contentHeight)
  local _, height = screenSize()
  local most = Screen.MAX_SHARE * height / ratio(frame)
  local fitted = contentHeight
  if fitted > most then fitted = most end
  frame:SetHeight(fitted)
  if kept[frame] then Screen.Pull(frame) end
  return fitted
end

function Screen.AtCursor(frame, side)
  side = (side == "left") and "left" or "right"
  local x, y = GetCursorPosition()
  local ui = UIParent:GetEffectiveScale()
  if not ui or ui <= 0 then ui = 1 end
  x, y = x / ui, y / ui
  local r = ratio(frame)
  local width = frame:GetWidth() * r
  local screenWidth = screenSize()
  local used = side
  if side == "right" and x + width > screenWidth and x - width >= 0 then
    used = "left"
  elseif side == "left" and x - width < 0 and x + width <= screenWidth then
    used = "right"
  end
  frame:ClearAllPoints()
  frame:SetPoint(used == "right" and "TOPLEFT" or "TOPRIGHT", UIParent, "BOTTOMLEFT", x / r, y / r)
  Screen.Keep(frame)
  return used
end

local function altDown()
  return IsAltKeyDown ~= nil and IsAltKeyDown() and true or false
end

local function stop(frame, key)
  frame:StopMovingOrSizing()
  Screen.Pull(frame)
  Screen.Save(frame, key)
end

function Screen.Movable(frame, key, opts)
  opts = opts or {}
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  keyOf[frame] = keyOf[frame] or key
  local grip
  if opts.resizable then
    resizable[frame] = true
    frame:SetResizable(true)
    if frame.SetResizeBounds then frame:SetResizeBounds(opts.minWidth or 120, opts.minHeight or 60) end
    grip = CreateFrame("Frame", nil, frame)
    grip:SetSize(GRIP_SIZE, GRIP_SIZE)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    -- above everything else in the frame (a scrolling list's rows sit on higher levels and would take its mouse)
    grip:SetFrameLevel((frame:GetFrameLevel() or 0) + 50)
    grip:EnableMouse(true)
    grip:RegisterForDrag("LeftButton")
    grip:SetScript("OnDragStart", function()
      if not option("locked") then frame:StartSizing("BOTTOMRIGHT") end
    end)
    grip:SetScript("OnDragStop", function() stop(frame, key) end)
  end
  frame:SetScript("OnDragStart", function(self)
    local locked = option("locked")
    if opts.resizable and altDown() then
      if not locked then self:StartSizing("BOTTOMRIGHT") end
    elseif not locked or (opts.altWhenLocked and altDown()) then
      self:StartMoving()
    end
  end)
  frame:SetScript("OnDragStop", function(self) stop(self, key) end)
  return grip
end

-- ---------------------------------------------------------------------------------------------------------------
-- Registered windows: hide all, preview, hide in raids
-- ---------------------------------------------------------------------------------------------------------------

function Screen.Allowed()
  if option("shown") == false then return false end
  if option("hideInRaid") and IsInRaid and IsInRaid() then return false end
  return true
end

local function apply()
  local allowed = Screen.Allowed()
  for _, key in ipairs(order) do
    local frame = registered[key].frame
    if inCombat() and protected(frame) then
      applyAfterCombat = true
    elseif allowed then
      if held[frame] then
        held[frame] = nil
        applying = true
        frame:Show()
        applying = false
      end
    elseif frame:IsShown() then
      held[frame] = true
      frame:Hide()
    end
  end
end

function Screen.Register(key, frame, preview)
  if not registered[key] then order[#order + 1] = key end
  registered[key] = { frame = frame, preview = preview }
  if not hooked[frame] then
    hooked[frame] = true
    frame:HookScript("OnShow", function(self)
      if applying or Screen.Allowed() then return end
      if inCombat() and protected(self) then
        applyAfterCombat = true
        return
      end
      held[self] = true
      self:Hide()
    end)
  end
  apply()
end

function Screen.SetShown(on)
  if Noir.Options then Noir.Options.Set("shown", on and true or false) end
  apply()
end

function Screen.Registered()
  local out = {}
  for i, key in ipairs(order) do out[i] = { key = key, frame = registered[key].frame } end
  return out
end

function Screen.IsPreview()
  return previewing
end

function Screen.Preview(on)
  previewing = on and true or false
  for _, key in ipairs(order) do
    local preview = registered[key].preview
    if preview then
      local good, err = pcall(preview, previewing)
      if not good then Noir.ReportError(err) end
    end
  end
end

-- Puts every placed window at its place in the profile in use (after a profile switch or reset, and once the
-- saved variables are ready).
local function placeAll()
  for frame, key in pairs(keyOf) do Screen.Place(frame, key) end
end

Noir.Command("show", "show every window of the addon", function() Screen.SetShown(true) end)
Noir.Command("hide", "hide every window of the addon (the guide keeps following the game)", function()
  Screen.SetShown(false)
end)
Noir.Command("toggle", "hide or show every window of the addon", function()
  Screen.SetShown(option("shown") == false)
end)
Noir.Command("preview", "fill every window with sample content to place them, or end that", function()
  Screen.Preview(not previewing)
end)

Noir.On("DISPLAY_SIZE_CHANGED", pullAll)
Noir.On("UI_SCALE_CHANGED", pullAll)
Noir.On("GROUP_ROSTER_UPDATE", apply)
Noir.On("PLAYER_REGEN_ENABLED", function()
  for frame in pairs(later) do
    later[frame] = nil
    if keyOf[frame] and not kept[frame] then Screen.Place(frame, keyOf[frame]) else Screen.Pull(frame) end
  end
  if applyAfterCombat then
    applyAfterCombat = false
    apply()
  end
end)
Noir.On("NOIR_OPTION", function(_, key)
  if key == "shown" or key == "hideInRaid" then apply() end
end)
Noir.On("NOIR_PROFILE", function()
  placeAll()
  apply()
end)
Noir.On("NOIR_INIT", function()
  placeAll()
  apply()
end)
