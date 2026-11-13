-- Noir Guides, GPLv3. See LICENSE.
-- Map pins v2 (spec 4.5, gap #24): pins on the world map and the minimap for the places of the steps on the cards and
-- of the steps after them, merged when close, with a tooltip per pin, and the paths of the steps on the cards drawn
-- on their zone's map. It follows the game by itself: no command is needed for anything here.
--
--   Map.Pins(kind) -> { { x, y, zone, at, steps = { { index, line, text, title, id } }, current, alpha, size, merged,
--       plus, ring, label, icon } } for kind "world" or "minimap"; x, y are the place in percent of its zone's map
--       (the first place of the pin). label: the first step's number, or nil when the step has a title (icon: the
--       kind icon of the first line instead); plus: merged, the pin shows a "+".
--   Map.Refresh()  asks for a rebuild: at once when the last one is REBUILD_SECONDS old, else when it is
--   Map.Read() -> { builds, builtAt, world = { shown, map, pins = { pin with x, y on the shown map (0 to 1) },
--       lines = { { x1, y1, x2, y2 } } }, minimap = { pins = { pin with x, y offset from the minimap's middle, edge } } }
--   Map.parts.world, Map.parts.minimap   the pin frames in drawing order (each with .back, .mark, .ring, .label,
--       .glyph, .plus); Map.parts.lines the path dashes (textures)
--
-- Rules (spec 4.5):
--   * World map and minimap: the places of the cards first, then the following steps in order, up to the "worldPins"
--     option ("Upcoming steps on the maps", default 8, 0 to 20) counted in steps with a place; the limit is raised so
--     every place of the cards fits. World map pins on any shown map that contains the place (zone, sub-zone,
--     continent: Arrow.Project); none in instances. The minimap's pins show while "minimapPins" is on; out of range,
--     the current step's pin waits on the rim in its direction and the other pins are left out.
--   * Merging: places closer than WORLD_YARDS * pinMerge (world map) or MINIMAP_YARDS * pinMerge (minimap) to a pin's
--     first place share that pin, which shows a "+" beside the first step's number or icon.
--   * Look: the cards' pins are metrics.active large and fully opaque; each following step's pins are FADE more
--     transparent, never below MIN_ALPHA; a ring around the cards' pins when "pinRing"; size times "pinSize"; the
--     background's opacity "pinAlpha".
--   * Tooltip on hover: one line per merged place, "<step title or number>: <line text>". Pins take mouse motion only
--     (SetMouseMotionEnabled(true), SetMouseClickEnabled(false), feature-detected; without them no mouse and no
--     tooltip), so clicks reach the map.
--   * Paths: a card step's path is drawn on the world map while its zone's map is shown, as dashes of DASH_YARDS with
--     GAP_YARDS skipped; a looping path is closed.
--   * Reached places, ticked lines and done lines have no pin (Lines.Places, Arrow.CardPlaces). Pins rebuild at most
--     every REBUILD_SECONDS (on the engine's events, when a place is reached), and are drawn again at once when the
--     shown map changes. The world map and the minimap are only read; frames of the addon's own are put inside them,
--     never in combat.
local Noir = Noir
local State, Progress, Lines, Theme, Arrow = Noir.State, Noir.Progress, Noir.Lines, Noir.Theme, Noir.Arrow

local Map = Noir.Map or {}
Noir.Map = Map
Map.parts = { world = {}, minimap = {}, lines = {} }

Map.REBUILD_SECONDS = 0.33
Map.WORLD_YARDS = 60
Map.MINIMAP_YARDS = 25
Map.FADE = 0.1
Map.MIN_ALPHA = 0.4
Map.DASH_YARDS = 8
Map.GAP_YARDS = 6
Map.MINIMAP_INTERVAL = 0.1  -- seconds between two placements of the minimap's pins (the player walks)
Map.WATCH_INTERVAL = 0.1    -- seconds between two looks at which map the world map shows
Map.RING = 1.6              -- the ring's size, times the pin's
Map.LINE = 2                -- a dash's thickness on the screen

local LEVELS_ABOVE = 100    -- frame levels between the map's canvas and the pins, above the game's own pins
local EPSILON = 1e-9

-- How many yards the minimap shows from edge to edge outdoors: 1400/3 at zoom 0, and each of the five zoom steps takes
-- 200/3 off (ENGINE-NOTES assumption 37). A zoom outside 0 to 5 counts as 0.
local function minimapYards(zoom)
  if type(zoom) ~= "number" or zoom < 0 or zoom > 5 or zoom ~= math.floor(zoom) then zoom = 0 end
  return (7 - zoom) * 200 / 3
end

local parts = Map.parts
local overlay, canvas, worldMap = nil, nil, nil
local minimap, clock = nil, nil
local built = false
local reported = {}
local pins = { world = {}, minimap = {} }   -- the last build
local paths = {}                           -- card steps with a path, at the last build
local lastCards = {}
local reachedSig = ""
local builds, builtAt, pending = 0, nil, false
local drawn = { world = {}, lines = {}, minimap = {}, map = nil }

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

local function inCombat()
  return InCombatLockdown and InCombatLockdown() and true or false
end

-- ---------------------------------------------------------------------------------------------------------------
-- Which places get a pin
-- ---------------------------------------------------------------------------------------------------------------

local function mappable(at)
  if type(at) ~= "table" or not (isNumber(at.x) and isNumber(at.y)) then return false end
  if at.x == 0 and at.y == 0 then return false end
  local zone = Noir.Data.zones[at.zone]
  return type(zone) == "table" and isNumber(zone.uiMap)
end

local function lineWords(line, step)
  local text = Noir.Text
  if not (text and text.Line) then return "" end
  local words = text.Line(line, step)
  return words and words.text or ""
end

local function lineIcon(line, step)
  local text = Noir.Text
  if not (text and text.Line) or not line then return nil end
  local words = text.Line(line, step)
  return words and words.icon
end

local function stepTitle(step)
  local text = Noir.Text
  if text and text.StepTitle then return text.StepTitle(step) end
  return tostring(step.n)
end

-- The line a step's own place stands for: the first open line without a place of its own (a card's line states
-- tell which are open), else the first line without a place.
local function placeLine(step, card)
  if card then
    for _, l in ipairs(card.lines or {}) do
      if type(l.index) == "number" and l.index > 0 and not l.line.at
        and l.state ~= "done" and l.state ~= "skip" and not l.ticked then
        return l.line
      end
    end
  end
  for _, line in ipairs(step.lines or {}) do
    if not line.at then return line end
  end
  return step.lines and step.lines[1]
end

local function entries(list, step, index, places, rank, card)
  local added = false
  for _, p in ipairs(places) do
    if mappable(p.at) then
      added = true
      local line = p.line > 0 and step.lines[p.line] or placeLine(step, card)
      list[#list + 1] = {
        at = p.at, index = index, line = p.line, id = step.id, step = step, title = stepTitle(step),
        text = line and lineWords(line, step) or (step.text or ""), rank = rank, current = rank == 0,
        primary = card ~= nil and card.kind == "current",
      }
    end
  end
  return added
end

local function outleveled(step)
  if option("outlevel") == false then return false end
  local level = State.level or (UnitLevel and UnitLevel("player")) or 1
  return type(step.maxLevel) == "number" and level > step.maxLevel
end

local function collect(cards, kind)
  local list = {}
  if kind == "minimap" and option("minimapPins") == false then return list end
  if State.InInstance() then return list end
  local onCard, cardSteps = {}, 0
  for _, card in ipairs(cards) do
    if card.index then onCard[card.index] = true end
    if entries(list, card.step, card.index, Arrow.CardPlaces(card), 0, card) then cardSteps = cardSteps + 1 end
  end
  local limit = math.max(option("worldPins") or 8, cardSteps)
  local count, rank = cardSteps, 0
  local _, at = Progress.Place()
  local steps = Progress.Steps() or {}
  if not at or #cards == 0 then return list end
  for i = at, #steps do
    if count >= limit then break end
    local step = steps[i]
    if not onCard[i] and not outleveled(step) then
      local state = Progress.StepState(i)
      if state == "ahead" or state == "current" then
        local places = Lines.Places(step, {}, { since = now() })
        local found = false
        for _, p in ipairs(places) do
          if mappable(p.at) then found = true end
        end
        if found then
          count, rank = count + 1, rank + 1
          entries(list, step, i, places, rank, nil)
        end
      end
    end
  end
  return list
end

local function merge(list, yards)
  local out = {}
  local m = Theme.metrics
  local scale = option("pinSize") or 1
  local ring = option("pinRing") and true or false
  for _, e in ipairs(list) do
    local into = nil
    for _, pin in ipairs(out) do
      local d = Arrow.Between(pin.at, e.at)
      if d and d < yards then
        into = pin
        break
      end
    end
    local alpha = e.current and 1 or math.max(Map.MIN_ALPHA, 1 - Map.FADE * e.rank)
    local step = { index = e.index, line = e.line, text = e.text, title = e.title, id = e.id }
    if into then
      into.steps[#into.steps + 1] = step
      into.merged, into.plus = true, true
      if alpha > into.alpha then into.alpha = alpha end
      into.current = into.current or e.current
      into.primary = into.primary or e.primary
    else
      local titled = type(e.step.title) == "string" and e.step.title ~= ""
      local first = e.line > 0 and e.step.lines[e.line] or placeLine(e.step, nil)
      out[#out + 1] = {
        x = e.at.x, y = e.at.y, zone = e.at.zone, at = e.at, steps = { step }, current = e.current,
        primary = e.primary, alpha = alpha, merged = false, plus = false,
        label = (not titled) and tostring(e.step.n) or nil, icon = titled and lineIcon(first, e.step) or nil,
      }
    end
  end
  for _, pin in ipairs(out) do
    pin.size = (pin.current and m.active or m.pin) * scale
    pin.ring = ring and pin.current or false
  end
  return out
end

local function pinsOf(cards, kind)
  local yards = (kind == "minimap" and Map.MINIMAP_YARDS or Map.WORLD_YARDS) * (option("pinMerge") or 1)
  return merge(collect(cards, kind), yards)
end

function Map.Pins(kind)
  return pinsOf((Progress.Cards and Progress.Cards()) or {}, kind)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Pin frames
-- ---------------------------------------------------------------------------------------------------------------

local function showTip(self)
  if not (GameTooltip and self.steps) then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  for _, s in ipairs(self.steps) do
    GameTooltip:AddLine(tostring(s.title) .. ": " .. tostring(s.text))
  end
  GameTooltip:Show()
end

local function hideTip(self)
  if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end

local function newText(pin)
  local fs = pin:CreateFontString(nil, "OVERLAY")
  Theme.Font(fs, "small")
  fs:SetJustifyH("CENTER")
  return fs
end

local function newPin(parent)
  local pin = CreateFrame("Frame", nil, parent)
  if pin.SetMouseMotionEnabled and pin.SetMouseClickEnabled then
    pin:SetMouseMotionEnabled(true)
    pin:SetMouseClickEnabled(false)
    pin:SetScript("OnEnter", showTip)
    pin:SetScript("OnLeave", hideTip)
  else
    pin:EnableMouse(false)
  end
  pin.ring = pin:CreateTexture(nil, "BACKGROUND")
  pin.ring:SetTexture(Theme.Texture("pin"))
  pin.ring:SetPoint("CENTER", pin, "CENTER", 0, 0)
  pin.back = pin:CreateTexture(nil, "BORDER")
  pin.back:SetTexture(Theme.Texture("pin-active"))
  pin.back:SetAllPoints(pin)
  pin.mark = pin:CreateTexture(nil, "ARTWORK")
  pin.mark:SetAllPoints(pin)
  pin.glyph = pin:CreateTexture(nil, "OVERLAY")
  pin.glyph:SetPoint("CENTER", pin, "CENTER", 0, 0)
  pin.label = newText(pin)
  pin.label:SetPoint("CENTER", pin, "CENTER", 0, 0)
  pin.plus = newText(pin)
  pin.plus:SetPoint("BOTTOMLEFT", pin, "TOPRIGHT", -3, -3)
  pin:Hide()
  return pin
end

-- The pin frame at `i` of a pool, created when needed and allowed (never in combat).
local function pinFrame(pool, i, parent, level)
  local pin = pool[i]
  if pin then return pin end
  if inCombat() then return nil end
  pin = newPin(parent)
  if isNumber(level) then pin:SetFrameLevel(math.min(level, 9000)) end
  pool[i] = pin
  return pin
end

local function dress(pin, data, size)
  pin.steps = data.steps
  pin:SetSize(size, size)
  pin:SetAlpha(data.alpha)
  Theme.Tint(pin.back, "bay", option("pinAlpha") or 0.6)
  pin.mark:SetTexture(Theme.Texture(data.current and "pin-active" or "pin"))
  Theme.Tint(pin.mark, data.current and "lamp" or "faint")
  if data.ring then
    pin.ring:SetSize(size * Map.RING, size * Map.RING)
    Theme.Tint(pin.ring, "lamp")
    pin.ring:Show()
  else
    pin.ring:Hide()
  end
  if data.icon then
    pin.glyph:SetTexture(Theme.Icon(data.icon))
    pin.glyph:SetSize(size * 0.6, size * 0.6)
    Theme.Tint(pin.glyph, data.current and "bay" or "paper")
    pin.glyph:Show()
    pin.label:Hide()
  else
    pin.glyph:Hide()
    if Theme.SetText(pin.label, data.label or "") then
      Theme.TextColor(pin.label, data.current and "bay" or "paper")
      pin.label:Show()
    end
  end
  if data.plus and Theme.SetText(pin.plus, "+") then
    Theme.TextColor(pin.plus, "paper")
    pin.plus:Show()
  else
    pin.plus:Hide()
  end
end

local function hideFrom(list, first)
  for i = first, #list do
    if list[i]:IsShown() then list[i]:Hide() end
  end
end

local function copyPin(pin, x, y, edge)
  local steps = {}
  for i, s in ipairs(pin.steps) do
    steps[i] = { index = s.index, line = s.line, text = s.text, title = s.title, id = s.id }
  end
  return { x = x, y = y, edge = edge, steps = steps, current = pin.current, alpha = pin.alpha, size = pin.size,
    merged = pin.merged, plus = pin.plus, ring = pin.ring, label = pin.label, icon = pin.icon, zone = pin.zone }
end

-- ---------------------------------------------------------------------------------------------------------------
-- The world map
-- ---------------------------------------------------------------------------------------------------------------

-- The world map's canvas (the frame its own pins live in) and the frame itself, or nil on a client without one.
local function findCanvas()
  local map = WorldMapFrame
  if type(map) ~= "table" then return nil end
  local found
  if type(map.GetCanvas) == "function" then found = map:GetCanvas() end
  if not found and type(map.ScrollContainer) == "table" then found = map.ScrollContainer.Child end
  if type(found) ~= "table" or type(found.GetWidth) ~= "function" then return nil end
  return found, map
end

local function shownMap()
  if not worldMap then return nil end
  local id
  if type(worldMap.GetMapID) == "function" then id = worldMap:GetMapID() else id = worldMap.mapID end
  return isNumber(id) and id or nil
end

-- Dashes along a path: { { a = place, b = place } } in the step's zone, DASH_YARDS long every DASH + GAP yards.
local function dashes(step)
  local out = {}
  local points = step.path and step.path.points
  if type(points) ~= "table" or #points < 2 or not step.at then return out end
  local zone = step.at.zone
  local count = #points
  local legs = step.path.loop and count or count - 1
  local period = Map.DASH_YARDS + Map.GAP_YARDS
  for k = 1, legs do
    local p, q = points[k], points[k % count + 1]
    local a, b = { zone = zone, x = p.x, y = p.y }, { zone = zone, x = q.x, y = q.y }
    local length = Arrow.Between(a, b)
    if length and length > 0 and length ~= math.huge then
      local s = 0
      while s < length - EPSILON do
        local e = math.min(s + Map.DASH_YARDS, length)
        local f, g = s / length, e / length
        out[#out + 1] = {
          x1 = (p.x + (q.x - p.x) * f) / 100, y1 = (p.y + (q.y - p.y) * f) / 100,
          x2 = (p.x + (q.x - p.x) * g) / 100, y2 = (p.y + (q.y - p.y) * g) / 100,
        }
        s = s + period
      end
    end
  end
  return out
end

local function drawPaths(uiMap, width, height, zoom)
  local used = 0
  if not State.InInstance() then
    for _, step in ipairs(paths) do
      local zone = Noir.Data.zones[step.at.zone]
      if type(zone) == "table" and zone.uiMap == uiMap then
        for _, d in ipairs(dashes(step)) do
          local tex = parts.lines[used + 1]
          if not tex then
            tex = overlay:CreateTexture(nil, "ARTWORK")
            parts.lines[used + 1] = tex
          end
          used = used + 1
          Theme.Paint(tex, "lamp", 0.8)
          local ax, ay, bx, by = d.x1 * width, -d.y1 * height, d.x2 * width, -d.y2 * height
          local dx, dy = bx - ax, by - ay
          local thick = Map.LINE / zoom
          tex:ClearAllPoints()
          tex:SetPoint("CENTER", overlay, "TOPLEFT", (ax + bx) / 2, (ay + by) / 2)
          if tex.SetRotation then
            tex:SetSize(math.max(math.sqrt(dx * dx + dy * dy), thick), thick)
            tex:SetRotation(math.atan2(dy, dx))
          else
            tex:SetSize(thick, thick) -- without rotation each dash is drawn as a dot at its middle
          end
          tex:Show()
          drawn.lines[used] = { x1 = d.x1, y1 = d.y1, x2 = d.x2, y2 = d.y2 }
        end
      end
    end
  end
  for i = used + 1, #parts.lines do parts.lines[i]:Hide() end
end

local function drawWorld()
  drawn.world, drawn.lines, drawn.map = {}, {}, nil
  if not overlay then return end
  local uiMap = overlay:IsVisible() and shownMap() or nil
  local width, height = canvas:GetWidth(), canvas:GetHeight()
  if not (uiMap and isNumber(width) and isNumber(height) and width > 0 and height > 0) then
    hideFrom(parts.world, 1)
    for i = 1, #parts.lines do parts.lines[i]:Hide() end
    return
  end
  drawn.map = uiMap
  -- The canvas grows and shrinks as the map is zoomed; the pins keep their size on the screen.
  local zoom = 1
  if canvas.GetEffectiveScale and UIParent and UIParent.GetEffectiveScale then
    local ours, screen = canvas:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if isNumber(ours) and isNumber(screen) and ours > 0 and screen > 0 then zoom = ours / screen end
  end
  local level = overlay:GetFrameLevel() or 0
  local used = 0
  for _, pin in ipairs(pins.world) do
    local x, y = Arrow.Project(pin.at, uiMap)
    if x then
      local frame = pinFrame(parts.world, used + 1, overlay, level + 1)
      if not frame then break end
      used = used + 1
      dress(frame, pin, pin.size / zoom)
      frame:ClearAllPoints()
      frame:SetPoint("CENTER", overlay, "TOPLEFT", x * width, -y * height)
      frame:Show()
      drawn.world[used] = copyPin(pin, x, y)
    end
  end
  hideFrom(parts.world, used + 1)
  drawPaths(uiMap, width, height, zoom)
end

local function buildWorld()
  if overlay then return true end
  canvas, worldMap = findCanvas()
  if not canvas then
    if not reported.world then
      reported.world = true
      Noir.Problem("This client's world map has no canvas the addon knows; pins are not drawn on the world map.")
    end
    return false
  end
  overlay = CreateFrame("Frame", nil, canvas)
  overlay:SetAllPoints(canvas)
  overlay:EnableMouse(false)
  local level = canvas.GetFrameLevel and canvas:GetFrameLevel() or 0
  if isNumber(level) then overlay:SetFrameLevel(math.min(level + LEVELS_ABOVE, 9000)) end
  -- A frame inside the canvas is shown and hidden with the map: OnShow draws the pins when the map opens, and
  -- OnUpdate, which only runs while the map is open, notices when it shows another map or is zoomed.
  local waited, lastMap, lastWidth = 0, nil, nil
  overlay:SetScript("OnShow", function()
    waited = 0
    drawWorld()
    lastMap, lastWidth = drawn.map, canvas:GetWidth()
  end)
  overlay:SetScript("OnUpdate", function(_, elapsed)
    waited = waited + (elapsed or 0)
    if waited + EPSILON < Map.WATCH_INTERVAL then return end
    waited = 0
    local map, width = shownMap(), canvas:GetWidth()
    if map ~= lastMap or width ~= lastWidth then
      drawWorld()
      lastMap, lastWidth = map, width
    end
  end)
  return true
end

-- ---------------------------------------------------------------------------------------------------------------
-- The minimap
-- ---------------------------------------------------------------------------------------------------------------

local function drawMinimap()
  drawn.minimap = {}
  if not minimap then return end
  local width = minimap:GetWidth()
  local zoom = type(minimap.GetZoom) == "function" and minimap:GetZoom() or 0
  local across = minimapYards(zoom)
  if not (isNumber(width) and width > 0) or #pins.minimap == 0 then
    hideFrom(parts.minimap, 1)
    return
  end
  local radius = width / 2
  local perYard = radius / (across / 2)
  -- A rotating minimap keeps the character's facing at the top.
  local turn = 0
  if GetCVar and GetCVar("rotateMinimap") == "1" then
    turn = GetPlayerFacing and GetPlayerFacing() or nil
    if not isNumber(turn) then
      hideFrom(parts.minimap, 1)
      return
    end
  end
  local level = minimap.GetFrameLevel and minimap:GetFrameLevel() or 0
  local used = 0
  for _, pin in ipairs(pins.minimap) do
    local bearing, yards = Arrow.Solve(pin.at)
    if bearing and yards then
      local distance, edge = yards * perYard, false
      if distance > radius then distance, edge = radius, true end
      -- Out of range: the current step's pin waits on the rim in its direction, the others are left out.
      if not edge or pin.primary then
        local frame = pinFrame(parts.minimap, used + 1, minimap, (isNumber(level) and level or 0) + 5)
        if not frame then break end
        used = used + 1
        local x, y = -math.sin(bearing - turn) * distance, math.cos(bearing - turn) * distance
        dress(frame, pin, pin.size)
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", minimap, "CENTER", x, y)
        frame:Show()
        drawn.minimap[used] = copyPin(pin, x, y, edge)
      end
    end
  end
  hideFrom(parts.minimap, used + 1)
end

local function buildMinimap()
  if minimap then return true end
  local found = Minimap
  if type(found) ~= "table" or type(found.GetWidth) ~= "function" then
    if not reported.minimap then
      reported.minimap = true
      Noir.Problem("This client has no minimap frame the addon knows; pins are not drawn on the minimap.")
    end
    return false
  end
  minimap = found
  return true
end

-- ---------------------------------------------------------------------------------------------------------------
-- Building and refreshing
-- ---------------------------------------------------------------------------------------------------------------

-- Which card places Progress marked reached: a rebuild is due when that changes (no engine event says so).
local function reachedSignature(cards)
  local out = {}
  for _, card in ipairs(cards) do
    if card.index then
      for i = 0, #(card.step.lines or {}) do
        if Progress.Reached(card.index, i) then out[#out + 1] = card.step.id .. "/" .. i end
      end
    end
  end
  return table.concat(out, ",")
end

local function build()
  if built then return true end
  if inCombat() then return false end
  built = true
  buildWorld()
  buildMinimap()
  clock = CreateFrame("Frame")
  local waited, sinceReached = 0, 0
  clock:SetScript("OnUpdate", function(_, elapsed)
    elapsed = elapsed or 0
    waited, sinceReached = waited + elapsed, sinceReached + elapsed
    if sinceReached + EPSILON >= Map.REBUILD_SECONDS then
      sinceReached = 0
      if reachedSignature(lastCards) ~= reachedSig then Map.Refresh() end
    end
    if waited + EPSILON < Map.MINIMAP_INTERVAL then return end
    waited = 0
    drawMinimap()
  end)
  clock:Show()
  return true
end

local function rebuild()
  if not build() then return end
  builds, builtAt = builds + 1, now()
  local cards = (Progress.Cards and Progress.Cards()) or {}
  lastCards = cards
  reachedSig = reachedSignature(cards)
  pins.world = pinsOf(cards, "world")
  pins.minimap = pinsOf(cards, "minimap")
  paths = {}
  for _, card in ipairs(cards) do
    local step = card.step
    if type(step.path) == "table" and step.at then paths[#paths + 1] = step end
  end
  drawWorld()
  drawMinimap()
end

function Map.Refresh()
  if not Noir.char then return end
  if pending then return end
  local wait = builtAt and (builtAt + Map.REBUILD_SECONDS - now()) or 0
  if wait <= EPSILON then
    rebuild()
    return
  end
  pending = true
  Noir.After(wait, function()
    pending = false
    rebuild()
  end)
end

function Map.Read()
  local function copyAll(list)
    local out = {}
    for i, pin in ipairs(list) do out[i] = pin end
    return out
  end
  local lines = {}
  for i, d in ipairs(drawn.lines) do lines[i] = { x1 = d.x1, y1 = d.y1, x2 = d.x2, y2 = d.y2 } end
  return {
    builds = builds, builtAt = builtAt,
    world = { shown = (overlay ~= nil and overlay:IsVisible()) and true or false, map = drawn.map,
      pins = copyAll(drawn.world), lines = lines },
    minimap = { pins = copyAll(drawn.minimap) },
  }
end

-- ---------------------------------------------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------------------------------------------

local PIN_OPTIONS = { worldPins = true, minimapPins = true, pinMerge = true, pinSize = true, pinAlpha = true,
  pinRing = true, outlevel = true }

for _, event in ipairs({ "NOIR_READY", "NOIR_STEP", "NOIR_PLACE", "NOIR_SECTION", "NOIR_LINE", "NOIR_ROUTE_DONE",
  "NOIR_PROFILE", "QUEST_LOG_UPDATE", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
  Noir.On(event, function() Map.Refresh() end)
end
Noir.On("NOIR_OPTION", function(_, key)
  if PIN_OPTIONS[key] then Map.Refresh() end
end)
Noir.On("PLAYER_REGEN_ENABLED", function()
  -- Frames inside the map frames are made out of combat only: what waited is drawn now.
  if not built then Map.Refresh() return end
  drawWorld()
  drawMinimap()
end)
