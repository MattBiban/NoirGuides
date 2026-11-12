-- Noir Guides, GPLv3. See LICENSE.
-- MinimapButton (gap #4, spec 4.1): a round button on the minimap's rim.
--
--   MinimapButton.frame               the button (the addon's own frame, parented to the minimap)
--   MinimapButton.SetAngle(degrees)   puts it at that angle (0 east, 90 north), wrapped into 0..360, and saves it
--                                     in the option "minimapAngle"
--   MinimapButton.Read() -> { shown, angle }
--   MinimapButton.RADIUS_OUT          how far outside the minimap's edge its centre sits
--
-- On the rim at "minimapAngle" (225, bottom left, by default); a left-drag moves it along the rim, following the
-- cursor, and saves the angle (not while "locked" is on); left click hides or shows every addon window
-- (Screen.SetShown; the guide keeps following the game); right click opens the main menu at the cursor
-- (Menu.OpenMain); the tooltip names both clicks; hidden while "minimap" is off. It is not registered with
-- Screen.Register: it stays when the windows are hidden, so they can be brought back. The minimap frame itself is
-- never changed, only read (its size and centre).
--
-- Never off-screen: the game puts the minimap in the top right corner, so near east or north the rim is closer to
-- the screen's edge than the button's half width. Every placement ends with Screen.Pull, which moves the button just
-- inside UIParent (the saved angle stays the one asked for), and it is placed again when the resolution or the UI
-- scale changes. Screen.Keep also clamps it and pulls it when it is shown.
local Noir = Noir
local Theme, Screen = Noir.Theme, Noir.Screen

local MinimapButton = {}
Noir.MinimapButton = MinimapButton

MinimapButton.SIZE = 28
MinimapButton.RADIUS_OUT = 10
MinimapButton.TIP = {
  "Noir Guides",
  "Left click: hide or show the windows",
  "Right click: menu",
  "Drag: move the button around the minimap",
}

local frame
local dragging = false

local function option(key)
  return Noir.Options and Noir.Options.Get(key)
end

local function wrap(degrees)
  degrees = (tonumber(degrees) or 0) % 360
  if degrees < 0 then degrees = degrees + 360 end
  return degrees
end

local function radius()
  local width = Minimap:GetWidth() or 140
  return width / 2 + MinimapButton.RADIUS_OUT
end

local function place(degrees)
  if not frame then return end
  local a = math.rad(degrees)
  local r = radius()
  frame:ClearAllPoints()
  frame:SetPoint("CENTER", Minimap, "CENTER", r * math.cos(a), r * math.sin(a))
  Screen.Pull(frame)
end

-- The cursor's angle around the minimap's centre, or nil while the minimap has no place.
local function cursorAngle()
  local cx, cy = Minimap:GetCenter()
  local scale = Minimap:GetEffectiveScale()
  if not (cx and cy and scale and scale > 0 and GetCursorPosition) then return nil end
  local x, y = GetCursorPosition()
  x, y = x / scale - cx, y / scale - cy
  if x == 0 and y == 0 then return nil end
  return wrap(math.deg(math.atan2(y, x)))
end

function MinimapButton.SetAngle(degrees)
  degrees = wrap(degrees)
  if Noir.Options and option("minimapAngle") ~= degrees then Noir.Options.Set("minimapAngle", degrees) end
  place(degrees)
end

function MinimapButton.Read()
  return { shown = frame ~= nil and frame:IsShown() and true or false, angle = option("minimapAngle") }
end

local function refresh()
  if not frame then return end
  if not dragging then place(wrap(option("minimapAngle") or 225)) end
  frame:SetShown(option("minimap") ~= false)
end

local function follow()
  local angle = cursorAngle()
  if angle then place(angle) end
end

local function build()
  if frame or not Minimap then return end
  frame = CreateFrame("Button", nil, Minimap)
  MinimapButton.frame = frame
  frame:SetSize(MinimapButton.SIZE, MinimapButton.SIZE)
  frame:SetFrameStrata("MEDIUM")
  frame:SetFrameLevel(8)
  Screen.Keep(frame)
  local back = frame:CreateTexture(nil, "BACKGROUND")
  Theme.Paint(back, "bay", Theme.metrics.alpha)
  back:SetAllPoints(frame)
  local edge = frame:CreateTexture(nil, "BORDER")
  Theme.Paint(edge, "lamp")
  edge:SetHeight(2)
  edge:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
  edge:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
  local icon = frame:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(Theme.Texture("arrow"))
  Theme.Tint(icon, "lamp")
  icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -4)
  icon:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -5, 6)
  frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
      local menu = Noir.Menu
      if menu and type(menu.OpenMain) == "function" then menu.OpenMain() end
    else
      Screen.SetShown(option("shown") == false)
    end
  end)
  frame:SetScript("OnDragStart", function(self)
    if option("locked") then return end
    dragging = true
    if GameTooltip then GameTooltip:Hide() end
    self:SetScript("OnUpdate", follow)
  end)
  frame:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    if not dragging then return end
    dragging = false
    local angle = cursorAngle()
    if angle then MinimapButton.SetAngle(angle) else refresh() end
  end)
  frame:SetScript("OnEnter", function(self)
    if not GameTooltip or dragging then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    for i, line in ipairs(MinimapButton.TIP) do
      if i == 1 then GameTooltip:AddLine(line) else GameTooltip:AddLine(line, 1, 1, 1) end
    end
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function()
    if GameTooltip then GameTooltip:Hide() end
  end)
  refresh()
end

Noir.On("NOIR_INIT", build)
Noir.On("NOIR_OPTION", function(_, key)
  if key == "minimap" or key == "minimapAngle" then refresh() end
end)
Noir.On("NOIR_PROFILE", refresh)
Noir.On("DISPLAY_SIZE_CHANGED", refresh)
Noir.On("UI_SCALE_CHANGED", refresh)
