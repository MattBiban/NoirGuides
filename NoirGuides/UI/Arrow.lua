-- Noir Guides, GPLv3. See LICENSE.
-- Arrow v2 (spec 4.4, gap #23): which way and how far it is to the next place of the steps on the cards. It follows
-- the game by itself: no command is needed for anything here.
--
--   Arrow.Target() -> { at, title, index, line [, loop] [, corpse] [, elsewhere] } or nil
--       while a ghost, the corpse (State.Corpse); else the first place of Lines.Places over the cards, in card order
--       then line order (Lines.Places leaves out hidden lines, done and ticked lines, reached places, and all but the
--       closest of a "nearest" group). Places with r = 0 (a pin, no arrow) and zone-only places (x = y = 0) are not
--       pointed at. Places on another continent are skipped for choosing; when no other place is left, the first of
--       them is returned with elsewhere = true. A step place with a looping path gives the loop's current point
--       (loop = its index).
--   Arrow.CardPlaces(card) -> Lines.Places of a card from Progress.Cards, with the card's done and ticked lines and the
--       places Progress marked reached (shared with UI/Map.lua)
--   Arrow.Solve(point) -> bearing, yards, method: the direction from the player as an angle from north turning left
--       (west is +pi/2), the distance in yards (nil when only the direction is known) and "world" or "map"; nil when
--       the direction is unknown or the place is on another continent. World position first, map projection second.
--   Arrow.Project(point, uiMap) -> x, y (0 to 1) of the place on another map, or nil when it is not on that map
--   Arrow.Between(a, b) -> yards between two places, math.huge on two continents, nil when unknown
--   Arrow.Elsewhere(point) -> true when the place is on another continent than the player
--   Arrow.Bearing(north, west), Arrow.TexCoords(angle)
--   Arrow.Read() -> { shown, angle, yards, text, frozen, title, draws }
--   Arrow.Update()   looks where the player is and draws (the clock calls it every INTERVAL seconds)
--   Arrow.Retarget() chooses the target again (on the engine's events and every ARRIVAL_SECONDS)
--   Arrow.Reset()    re-enables the arrow and places it at Screen.DEFAULTS.arrowReset
--   Arrow.Preview(on) sample content for placing the windows (Screen.Preview)
--   Arrow.frame, Arrow.parts (arrow, label)
--
-- Rules: redraws only when the angle moved more than TURN_DEGREES or the whole-yard distance (or the label) changed.
-- Arrival: inside a place's radius the place is marked reached (Progress.MarkReached) and the arrow moves on.
-- Loops: a step's path with loop = true is followed point by point, each reached within the step's at.r (LOOP_YARDS
-- when nil); after the last point it starts again; farther than STRAY_LEGS times the current leg (at least
-- STRAY_YARDS) from the point it restarts from the nearest point. Another continent: frozen pointing straight up with
-- ELSEWHERE_TEXT, one chat line per target. Hidden when the "arrow" option is off, without a target, in an instance,
-- without a position or a facing, and while the windows are hidden (Screen.Allowed). Placed at
-- Screen.DEFAULTS.arrow, draggable (Screen.Movable), saved, locked by "locked", scaled by "arrowScale" keeping its
-- corner, label size "arrowText".
local Noir = Noir
local State, Progress, Lines, Theme, Screen = Noir.State, Noir.Progress, Noir.Lines, Noir.Theme, Noir.Screen

local Arrow = Noir.Arrow or {}
Noir.Arrow = Arrow
Arrow.parts = Arrow.parts or {}

Arrow.INTERVAL = 0            -- seconds between two looks at where the player is: every frame, so the arrow is smooth
Arrow.SMOOTH = 20             -- how fast the drawn direction catches up with the true one (per second; 0 = snap)
Arrow.ARRIVAL_SECONDS = 0.33  -- seconds between two choices of the target (arrival, loops, nearest)
Arrow.TURN_DEGREES = 0.1      -- smaller turns are not drawn
Arrow.LOOP_YARDS = 20         -- a loop's point is reached this near when the step's place has no radius
Arrow.STRAY_LEGS = 1.3
Arrow.STRAY_YARDS = 1000
Arrow.ARRIVE_YARDS = 8        -- this near, the arrow shows in the "ok" color
Arrow.ELSEWHERE_TEXT = "On another continent"
Arrow.CORPSE_TITLE = "Your corpse"
Arrow.PREVIEW_TEXT = "Arrow"

local TWO_PI = math.pi * 2
local TURN = math.rad(Arrow.TURN_DEGREES)
local LABEL_WIDTH = 160

local parts = Arrow.parts
local frame, clock = nil, nil
local target = nil
local drawn = { shown = false, draws = 0 }
local draws = 0
local previewing = false
local loops = {}      -- step id -> { i, places = { [k] = place } }
local reported = {}   -- target key -> true once the chat line about another continent was printed

local function isNumber(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function option(key)
  local options = Noir.Options
  if options and options.Get then return options.Get(key) end
  return nil
end

local function now()
  return GetTime and GetTime() or 0
end

-- ---------------------------------------------------------------------------------------------------------------
-- Places
-- ---------------------------------------------------------------------------------------------------------------

local function zoneOnly(point)
  return (point.x or 0) == 0 and (point.y or 0) == 0
end

-- The uiMap of a route place and the place on it in 0 to 1, or nil when the place cannot be put on a map: no zone in
-- the data, or the "zone only" placeholder 0, 0.
local function onMap(point)
  if type(point) ~= "table" or not (isNumber(point.x) and isNumber(point.y)) then return nil end
  if zoneOnly(point) then return nil end
  local zone = Noir.Data.zones[point.zone]
  local uiMap = type(zone) == "table" and zone.uiMap or nil
  if not isNumber(uiMap) then return nil end
  return uiMap, point.x / 100, point.y / 100
end

local function xy(vector)
  if type(vector) ~= "table" then return nil end
  local x, y
  if vector.GetXY then x, y = vector:GetXY() else x, y = vector.x, vector.y end
  if not (isNumber(x) and isNumber(y)) then return nil end
  return x, y
end

local function vector(x, y)
  if CreateVector2D then return CreateVector2D(x, y) end
  return nil
end

-- A place in world coordinates: instance, yards north, yards west. A place never moves, so it is asked for once.
local worldCache = setmetatable({}, { __mode = "k" })

local function worldOf(key, uiMap, x, y)
  local known = key and worldCache[key]
  if known and known.x == x and known.y == y and known.uiMap == uiMap then return known.instance, known.north, known.west end
  if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
  local instance, position = C_Map.GetWorldPosFromMapPos(uiMap, vector(x, y))
  local north, west = xy(position)
  if not north or instance == nil then return nil end
  if key then worldCache[key] = { uiMap = uiMap, x = x, y = y, instance = instance, north = north, west = west } end
  return instance, north, west
end

local function playerWorld()
  if not UnitPosition then return nil end
  local north, west, _, instance = UnitPosition("player")
  if not (isNumber(north) and isNumber(west)) or instance == nil then return nil end
  return instance, north, west
end

local function mapYards(uiMap)
  if not (C_Map and C_Map.GetMapWorldSize) then return nil end
  local w, h = C_Map.GetMapWorldSize(uiMap)
  if isNumber(w) and isNumber(h) and w > 0 and h > 0 then return w, h end
  return nil
end

function Arrow.Between(a, b)
  local ua, ax, ay = onMap(a)
  local ub, bx, by = onMap(b)
  if not (ua and ub) then return nil end
  local ia, na, wa = worldOf(a, ua, ax, ay)
  local ib, nb, wb = worldOf(b, ub, bx, by)
  if na and nb then
    if ia ~= ib then return math.huge end
    local dn, dw = nb - na, wb - wa
    return math.sqrt(dn * dn + dw * dw)
  end
  if ua == ub then
    local w, h = mapYards(ua)
    if not w then return nil end
    local dx, dy = (bx - ax) * w, (by - ay) * h
    return math.sqrt(dx * dx + dy * dy)
  end
  return nil
end

-- The instance (continent) of a place and of the player: world coordinates first, the data's continent and the
-- client's instance second.
local function placeInstance(point)
  local uiMap, x, y = onMap(point)
  if uiMap then
    local instance = worldOf(point, uiMap, x, y)
    if instance ~= nil then return instance, "world" end
  end
  local zone = type(point) == "table" and Noir.Data.zones[point.zone]
  if type(zone) == "table" and zone.continent ~= nil then return zone.continent, "data" end
  return nil
end

local function playerInstance(how)
  if how == "world" then
    local instance = playerWorld()
    if instance ~= nil then return instance end
  end
  if GetInstanceInfo then
    local instance = select(8, GetInstanceInfo())
    if instance ~= nil then return instance end
  end
  return nil
end

function Arrow.Elsewhere(point)
  local there, how = placeInstance(point)
  if there == nil then return false end
  local here = playerInstance(how)
  return here ~= nil and here ~= there
end

-- ---------------------------------------------------------------------------------------------------------------
-- Direction and distance
-- ---------------------------------------------------------------------------------------------------------------

function Arrow.Bearing(north, west)
  if north == 0 and west == 0 then return 0 end
  return math.atan2(west, north)
end

local function byMap(uiMap, x, y)
  if not (C_Map and C_Map.GetPlayerMapPosition) then return nil end
  local _, px, py, playerMap = State.Position()
  if not px then return nil end
  local common, fromX, fromY, toX, toY
  if playerMap == uiMap then
    common, fromX, fromY, toX, toY = uiMap, px / 100, py / 100, x, y
  else
    local continent = State.Continent()
    if not (continent and C_Map.GetMapRectOnMap) then return nil end
    local cx, cy = xy(C_Map.GetPlayerMapPosition(continent, "player"))
    local left, right, top, bottom = C_Map.GetMapRectOnMap(uiMap, continent)
    if not (cx and isNumber(left) and isNumber(right) and isNumber(top) and isNumber(bottom)) then return nil end
    common, fromX, fromY = continent, cx, cy
    toX, toY = left + x * (right - left), top + y * (bottom - top)
  end
  local width, height = mapYards(common)
  local sized = width ~= nil
  if not sized then width, height = 3, 2 end
  -- On a map, x grows to the east and y to the south.
  local north, west = (fromY - toY) * height, (fromX - toX) * width
  return Arrow.Bearing(north, west), sized and math.sqrt(north * north + west * west) or nil, "map"
end

function Arrow.Solve(point)
  local uiMap, x, y = onMap(point)
  if not uiMap then return nil end
  local instance, north, west = playerWorld()
  if north then
    local there, toNorth, toWest = worldOf(point, uiMap, x, y)
    if toNorth then
      if there ~= instance then return nil end -- another continent
      local dNorth, dWest = toNorth - north, toWest - west
      return Arrow.Bearing(dNorth, dWest), math.sqrt(dNorth * dNorth + dWest * dWest), "world"
    end
  end
  return byMap(uiMap, x, y)
end

-- The instance a map belongs to, to tell that a place is not on a map of another continent.
local instanceOfMap = {}

function Arrow.Project(point, uiMap)
  local own, x, y = onMap(point)
  if not own or not isNumber(uiMap) then return nil end
  if own == uiMap then return x, y end
  if not C_Map then return nil end
  if C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D then
    local instance, north, west = worldOf(point, own, x, y)
    if north then
      if instanceOfMap[uiMap] == nil then
        local other = C_Map.GetWorldPosFromMapPos(uiMap, CreateVector2D(0.5, 0.5))
        instanceOfMap[uiMap] = other == nil and false or other
      end
      local other = instanceOfMap[uiMap]
      if other ~= false and other ~= instance then return nil end
      local _, at = C_Map.GetMapPosFromWorldPos(instance, CreateVector2D(north, west), uiMap)
      local px, py = xy(at)
      if px then
        if px < 0 or px > 1 or py < 0 or py > 1 then return nil end
        return px, py
      end
    end
  end
  if C_Map.GetMapRectOnMap then
    local left, right, top, bottom = C_Map.GetMapRectOnMap(own, uiMap)
    if isNumber(left) and isNumber(right) and isNumber(top) and isNumber(bottom) then
      local px, py = left + x * (right - left), top + y * (bottom - top)
      if px < 0 or px > 1 or py < 0 or py > 1 then return nil end
      return px, py
    end
  end
  return nil
end

-- A texture is turned by handing the client its four corners, which every client version can do. The corners go:
-- upper left, lower left, upper right, lower right, each as x then y, with y down.
function Arrow.TexCoords(angle)
  local cos, sin = math.cos(angle), math.sin(angle)
  local function corner(x, y)
    return 0.5 + (x * cos + y * sin), 0.5 - (y * cos - x * sin)
  end
  local ulx, uly = corner(-0.5, 0.5)
  local llx, lly = corner(-0.5, -0.5)
  local urx, ury = corner(0.5, 0.5)
  local lrx, lry = corner(0.5, -0.5)
  return ulx, uly, llx, lly, urx, ury, lrx, lry
end

-- ---------------------------------------------------------------------------------------------------------------
-- The target
-- ---------------------------------------------------------------------------------------------------------------

local function stepTitle(step)
  local text = Noir.Text
  if text and text.StepTitle then return text.StepTitle(step) end
  return tostring(step.n)
end

function Arrow.CardPlaces(card)
  local step = card.step
  local done = {}
  -- Passive lines (notes, markers) count as done but keep their places while the step is shown (Lines.Places).
  for _, l in ipairs(card.lines or {}) do
    if type(l.index) == "number" and l.index > 0 and Lines.Active(l.line)
      and (l.state == "done" or l.state == "skip" or l.ticked) then
      done[l.index] = true
    end
  end
  local reached = {}
  if card.index and Progress.Reached then
    if step.at and Progress.Reached(card.index, 0) then reached[step.at] = true end
    for i, line in ipairs(step.lines or {}) do
      if line.at and Progress.Reached(card.index, i) then reached[line.at] = true end
    end
  end
  return Lines.Places(step, reached, { since = now(), done = done })
end

-- A place the arrow can point at: on a map, and not a pin-only place (r = 0).
local function pointable(point)
  if not onMap(point) then return false end
  return point.r ~= 0
end

local function yardsTo(point)
  local _, yards = Arrow.Solve(point)
  return yards
end

-- The current point of a step's looping path, moved on when reached and back to the nearest when far off.
local function loopTarget(card, base)
  local step = card.step
  local points = step.path.points
  if type(points) ~= "table" or #points == 0 then return base end
  local r = (isNumber(step.at.r) and step.at.r > 0) and step.at.r or Arrow.LOOP_YARDS
  local state = loops[step.id]
  if not state or state.zone ~= step.at.zone then
    state = { i = 1, places = {}, zone = step.at.zone }
    loops[step.id] = state
  end
  local function place(k)
    local p = state.places[k]
    if not p then
      p = { zone = step.at.zone, x = points[k].x, y = points[k].y, r = r }
      state.places[k] = p
    end
    return p
  end
  local count = #points
  if state.i > count then state.i = 1 end
  -- Reached: on to the next point; after the last one the loop starts again.
  for _ = 1, count do
    local yards = yardsTo(place(state.i))
    if yards and yards <= r then state.i = state.i % count + 1 else break end
  end
  -- Far off the loop: restart from the nearest point.
  local yards = yardsTo(place(state.i))
  if yards then
    local previous = (state.i - 2) % count + 1
    local leg = Arrow.Between(place(previous), place(state.i)) or 0
    if leg == math.huge then leg = 0 end
    if yards > math.max(Arrow.STRAY_LEGS * leg, Arrow.STRAY_YARDS) then
      local best, bestYards = state.i, yards
      for k = 1, count do
        local d = yardsTo(place(k))
        if d and d < bestYards then best, bestYards = k, d end
      end
      state.i = best
    end
  end
  base.at, base.loop = place(state.i), state.i
  return base
end

function Arrow.Target()
  if State.IsGhost and State.IsGhost() then
    local zone, x, y = State.Corpse()
    if zone then return { at = { zone = zone, x = x, y = y }, title = Arrow.CORPSE_TITLE, corpse = true } end
  end
  local cards = (Progress.Cards and Progress.Cards()) or {}
  local elsewhere = nil
  for _, card in ipairs(cards) do
    local places = Arrow.CardPlaces(card)
    for _, p in ipairs(places) do
      if pointable(p.at) then
        local t = { at = p.at, title = stepTitle(card.step), index = card.index, line = p.line, step = card.step }
        local path = card.step.path
        if p.line == 0 and type(path) == "table" and path.loop then t = loopTarget(card, t) end
        if Arrow.Elsewhere(t.at) then
          t.elsewhere = true
          elsewhere = elsewhere or t
        else
          return t
        end
      end
    end
  end
  return elsewhere
end

-- ---------------------------------------------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------------------------------------------

local function hide()
  if previewing then return end
  if frame and frame:IsShown() then frame:Hide() end
  drawn = { shown = false, draws = draws }
end

local function normalize(angle)
  angle = angle % TWO_PI
  if angle > math.pi then angle = angle - TWO_PI end
  return angle
end

local function setLabel(text)
  local label = parts.label
  if label:GetFont() then
    Theme.SetText(label, text)
    label:Show()
  else
    label:Hide()
  end
end

local function draw(angle, yards, title, frozen)
  local whole = yards and math.floor(yards + 0.5) or nil
  local text
  if frozen then
    text = title .. "\n" .. Arrow.ELSEWHERE_TEXT
  elseif whole then
    text = title .. "\n" .. Noir.Text.Distance(yards)
  else
    text = title
  end
  local same = drawn.shown and drawn.text == text and (drawn.frozen or false) == (frozen or false)
  if same and math.abs(normalize(angle - drawn.angle)) <= TURN then
    if not frame:IsShown() then frame:Show() end
    drawn.yards = yards
    return
  end
  draws = draws + 1
  parts.arrow:SetTexCoord(Arrow.TexCoords(angle))
  local arrived = (not frozen) and yards ~= nil and yards <= Arrow.ARRIVE_YARDS
  Theme.Tint(parts.arrow, frozen and "faint" or (arrived and "ok" or "lamp"))
  setLabel(text)
  if not frame:IsShown() then frame:Show() end
  drawn = { shown = true, angle = angle, yards = yards, text = text, frozen = frozen and true or false,
    title = title, draws = draws }
end

local function targetKey(t)
  local section = Progress.Place and Progress.Place() or ""
  return tostring(section) .. ":" .. tostring(t.step and t.step.id) .. ":" .. tostring(t.line)
end

-- elapsed: seconds since the last frame, given by the clock. Without it (an event, a test) the arrow snaps to the
-- true direction; with it the drawn direction eases toward the true one, so turning the camera or the character
-- glides instead of stepping.
function Arrow.Update(elapsed)
  if not frame or previewing then return end
  if option("arrow") == false or not Screen.Allowed() then return hide() end
  local t = target
  if not t or State.InInstance() then return hide() end
  if t.elsewhere then
    local key = targetKey(t)
    if not reported[key] then
      reported[key] = true
      Noir.Print(string.format("The arrow's target, step %s, is on another continent.", tostring(t.title)))
    end
    return draw(0, nil, t.title, true)
  end
  local facing = GetPlayerFacing and GetPlayerFacing() or nil
  local bearing, yards = Arrow.Solve(t.at)
  if not (bearing and isNumber(facing)) then return hide() end
  -- Arrival: the place is reached and the arrow moves on to the next one.
  local r = t.at.r
  if yards and isNumber(r) and r > 0 and yards <= r and t.index and not t.loop and not t.corpse then
    if Progress.MarkReached(t.index, t.line) then
      Arrow.Retarget(true)
      t = target
      if not t or t.elsewhere then return Arrow.Update() end
      bearing, yards = Arrow.Solve(t.at)
      if not bearing then return hide() end
    end
  end
  local angle = normalize(bearing - facing)
  if elapsed and Arrow.SMOOTH > 0 and drawn.shown and not drawn.frozen and drawn.angle then
    local k = math.min(1, elapsed * Arrow.SMOOTH)
    angle = normalize(drawn.angle + normalize(angle - drawn.angle) * k)
  end
  draw(angle, yards, t.title, false)
end

function Arrow.Retarget(quiet)
  target = Arrow.Target()
  if not quiet then Arrow.Update() end
end

function Arrow.Read()
  return { shown = drawn.shown and true or false, angle = drawn.angle, yards = drawn.yards, text = drawn.text,
    frozen = drawn.frozen and true or false, title = drawn.title, draws = draws }
end

-- ---------------------------------------------------------------------------------------------------------------
-- The frame
-- ---------------------------------------------------------------------------------------------------------------

local function ratio()
  local ui, own = UIParent:GetEffectiveScale(), frame:GetEffectiveScale()
  if not (ui and own and ui > 0 and own > 0) then return 1 end
  return own / ui
end

local function applyText()
  local label = parts.label
  if not Theme.Font(label, "small") then return end
  local size = option("arrowText") or 12
  local file, _, flags = label:GetFont()
  if file then label:SetFont(file, size, flags or "") end
  local m = Theme.metrics
  frame:SetHeight(m.arrow + m.gap + 2 * (size + 2))
  if drawn.text then setLabel(drawn.text) end
end

local function applyScale()
  local scale = option("arrowScale") or 1
  if frame:GetScale() ~= scale then
    frame:SetScale(scale)
    Screen.Place(frame, "arrow")
  end
end

function Arrow.Reset()
  if Noir.Options then
    Noir.Options.Set("arrow", true)
    Noir.Options.SavePosition("arrow", nil)
  end
  if frame then
    local d = Screen.DEFAULTS.arrowReset
    local r = ratio()
    frame:ClearAllPoints()
    frame:SetPoint(d[1], UIParent, d[2], d[3] / r, d[4] / r)
    Screen.Keep(frame)
    Screen.Save(frame, "arrow")
  end
  Arrow.Retarget()
end

function Arrow.Preview(on)
  if not frame then return end
  previewing = on and true or false
  if previewing then
    parts.arrow:SetTexCoord(Arrow.TexCoords(0.6))
    Theme.Tint(parts.arrow, "lamp")
    setLabel(Arrow.PREVIEW_TEXT .. "\n" .. Noir.Text.Distance(120))
    frame:Show()
  else
    drawn = { shown = false, draws = draws }
    if frame:IsShown() then frame:Hide() end
    Arrow.Retarget()
  end
end

local function build()
  local m = Theme.metrics
  frame = CreateFrame("Frame", nil, UIParent)
  Arrow.frame = frame
  frame:SetSize(LABEL_WIDTH, m.arrow + m.gap + 2 * (Theme.sizes.small + 2))
  frame:Hide()
  parts.arrow = frame:CreateTexture(nil, "ARTWORK")
  parts.arrow:SetTexture(Theme.Texture("arrow"))
  parts.arrow:SetSize(m.arrow, m.arrow)
  parts.arrow:SetPoint("TOP", frame, "TOP", 0, 0)
  Theme.Tint(parts.arrow, "lamp")
  parts.label = frame:CreateFontString(nil, "OVERLAY")
  parts.label:SetTextColor(Theme.Color("paper"))
  parts.label:SetJustifyH("CENTER")
  parts.label:SetJustifyV("TOP")
  parts.label:SetWidth(LABEL_WIDTH)
  parts.label:SetPoint("TOP", frame, "TOP", 0, -(m.arrow + m.gap))
  parts.label:Hide()
  applyText()
  frame:SetScale(option("arrowScale") or 1)
  Screen.Movable(frame, "arrow")
  Screen.Place(frame, "arrow")
  Screen.Register("arrow", frame, Arrow.Preview)

  -- The arrow hides itself, and a hidden frame gets no OnUpdate: the clock is a frame of its own.
  clock = CreateFrame("Frame")
  local waited, sinceTarget = 0, 0
  clock:SetScript("OnUpdate", function(_, elapsed)
    elapsed = elapsed or 0
    waited, sinceTarget = waited + elapsed, sinceTarget + elapsed
    if waited + 1e-9 < Arrow.INTERVAL then return end
    local step = waited
    waited = 0
    if sinceTarget + 1e-9 >= Arrow.ARRIVAL_SECONDS then
      sinceTarget = 0
      target = Arrow.Target()
    end
    Arrow.Update(step)
  end)
  clock:Show()
end

-- ---------------------------------------------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------------------------------------------

Noir.On("NOIR_INIT", function()
  if not frame then build() end
end)

for _, event in ipairs({ "NOIR_READY", "NOIR_STEP", "NOIR_PLACE", "NOIR_SECTION", "NOIR_LINE", "NOIR_ROUTE_DONE",
  "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "ZONE_CHANGED_NEW_AREA" }) do
  Noir.On(event, function()
    if frame then Arrow.Retarget() end
  end)
end

Noir.On("NOIR_OPTION", function(_, key)
  if not frame then return end
  if key == "arrowScale" then
    applyScale()
  elseif key == "arrowText" then
    applyText()
  elseif key == "arrow" or key == "shown" or key == "hideInRaid" then
    Arrow.Retarget()
  end
end)

Noir.On("NOIR_PROFILE", function()
  if not frame then return end
  applyText()
  applyScale()
  Arrow.Retarget()
end)
