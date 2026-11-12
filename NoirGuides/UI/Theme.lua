-- Noir Guides, GPLv3. See LICENSE.
-- Theme: the design's colors, type sizes, measures and textures, and the few calls that apply them.
-- DESIGN.md is the authority for every value here; tools/test-lua/theme.lua fails when the two differ.
--
--   Theme.Color(name [, alpha])   -> r, g, b, a (0 to 1); white for a name the design does not have
--   Theme.Hex(name)               -> "F2B33D", for color codes in chat text
--   Theme.sizes[role]             type sizes: kicker, name, body, small
--   Theme.metrics[name]           measures in interface units
--   Theme.Texture(name)           -> the path of one of the addon's textures, or nil
--   Theme.Font(fontString, role [, large])  sets the font file and size (large: metrics.large more); false when
--                                 the client has no usable font
--   Theme.Icon(name)              -> the path of a kind icon's texture ("icon-" .. name), the note's for an unknown one
--   Theme.ICONS, Theme.MARKS      the kind icons; the side bar's color per step kind
--   Theme.SetText(fontString, text)   sets text only on a font string that has a font
--   Theme.Paint(texture, name [, alpha])   a solid color
--   Theme.Tint(texture, name [, alpha])    colors one of the addon's white textures
--   Theme.fontFile                the addon's own font file, once it ships one (nil: the client's default font)
--
-- Fonts are only ever set by file, with SetFont. A font object is never handed to a font string: the Forever
-- client crashes when SetFontObject is given anything but one of its own named font objects.
local Noir = Noir

local Theme = {}
Noir.Theme = Theme

-- ---------------------------------------------------------------------------------------------------------------
-- Tokens
-- ---------------------------------------------------------------------------------------------------------------

local HEX = {
  bay = "1C2027",     -- the window's background
  strip = "2E343E",   -- a card's background, a lit row of the step list
  lamp = "F2B33D",    -- the accent: the current card's side bar, the badge, the rail, the arrow, the current pin
  paper = "ECE7DB",   -- primary text
  dim = "A6A195",     -- secondary text
  faint = "8F8A80",   -- a reminder's side bar, the step numbers, the next steps' pins
  track = "454C58",   -- the rail's track, an empty tick box
  warn = "F0825A",    -- notes: something stands in the way of the step
  ok = "7FC97F",      -- arrived, route complete, the hand-in mark
  -- Named things in a line's words, by meaning (the "highlight" option)
  friend = "7FC9E8",  -- a friendly NPC
  enemy = "F07A7A",   -- an enemy to kill
  loot = "D7A8F0",    -- an item to loot or use
  warning = "F0825A", -- a quest whose prerequisites are not handed in
  object = "8FD6C8",  -- an object to click
  buy = "B8D97A",     -- an item to buy
}

Theme.colors = {}
for name, hex in pairs(HEX) do
  Theme.colors[name] = {
    tonumber(string.sub(hex, 1, 2), 16) / 255,
    tonumber(string.sub(hex, 3, 4), 16) / 255,
    tonumber(string.sub(hex, 5, 6), 16) / 255,
  }
end

Theme.sizes = { kicker = 10, name = 14, body = 11, small = 10 }

Theme.metrics = {
  width = 260,  -- the window
  pad = 10,     -- from the window's edge to its content
  gap = 4,      -- between two blocks of text
  lamp = 3,     -- a card's side bar
  rail = 3,     -- the rail's thickness
  arrow = 48,   -- the arrow's side
  pin = 14,     -- a next step's pin
  active = 20,  -- the current step's pin
  alpha = 0.95, -- the bay's opacity
  icon = 12,    -- a kind icon
  tick = 12,    -- a tick box
  header = 36,  -- the header's height
  footer = 26,  -- the footer's height
  list = 240,   -- the step list's height until the player resizes it
  slide = 0.25, -- seconds a new current card takes to slide in
  mark = 3,     -- seconds a new current card's side bar shows the step's kind
  large = 2,    -- added to every type size with the large font size
  button = 32,  -- an item, spell or target button's side
}

local TEXTURE_PATH = "Interface\\AddOns\\NoirGuides\\Textures\\"
Theme.textures = { arrow = true, pin = true, ["pin-active"] = true, box = true, tick = true, grip = true, menu = true }
-- The kind icons of a line, as UI/Text.lua names them, and the timer of the flight bar: textures "icon-<name>".
Theme.ICONS = { "accept", "turnin", "objective", "kill", "item", "vendor", "trainer", "gossip", "flight", "flightpoint",
  "hearth", "bind", "goto", "xp", "error", "note", "timer" }
for _, icon in ipairs(Theme.ICONS) do Theme.textures["icon-" .. icon] = true end

-- The side bar of a new current card shows the step's kind for metrics.mark seconds, in this color (spec 4.2).
Theme.MARKS = { turnin = "ok", accept = "lamp", train = "friend", objective = "enemy", travel = "dim" }

function Theme.Color(name, alpha)
  local color = Theme.colors[name]
  if not color then return 1, 1, 1, alpha or 1 end
  return color[1], color[2], color[3], alpha or 1
end

function Theme.Hex(name)
  return HEX[name] or "FFFFFF"
end

function Theme.Texture(name)
  if not Theme.textures[name] then return nil end
  return TEXTURE_PATH .. name
end

function Theme.Icon(name)
  return Theme.Texture("icon-" .. tostring(name)) or Theme.Texture("icon-note")
end

-- ---------------------------------------------------------------------------------------------------------------
-- Fonts
-- ---------------------------------------------------------------------------------------------------------------

local USUAL_FONT = "Fonts\\FRIZQT__.TTF" -- where the client's default font has been since the first release
local reported = false

-- SetFont answers true or false on newer clients and nothing on older ones; there, a font string that now has a
-- font counts as success.
local function try(fontString, file, size)
  if type(file) ~= "string" or file == "" then return false end
  local result = fontString:SetFont(file, size, "")
  if result == nil then return fontString:GetFont() ~= nil end
  return result and true or false
end

function Theme.Font(fontString, role, large)
  local size = (Theme.sizes[role] or Theme.sizes.body) + (large and Theme.metrics.large or 0)
  if try(fontString, Theme.fontFile, size) or try(fontString, STANDARD_TEXT_FONT, size) or try(fontString, USUAL_FONT, size) then
    return true
  end
  if not reported then
    reported = true
    Noir.Problem("The client loaded no font for the addon's window, so it cannot show text.")
  end
  return false
end

function Theme.SetText(fontString, text)
  if not fontString:GetFont() then return false end
  fontString:SetText(text or "")
  return true
end

-- ---------------------------------------------------------------------------------------------------------------
-- Textures
-- ---------------------------------------------------------------------------------------------------------------

function Theme.Paint(texture, name, alpha)
  local r, g, b, a = Theme.Color(name, alpha)
  if texture.SetColorTexture then
    texture:SetColorTexture(r, g, b, a)
  else
    texture:SetTexture("Interface\\Buttons\\WHITE8X8")
    texture:SetVertexColor(r, g, b, a)
  end
end

function Theme.Tint(texture, name, alpha)
  texture:SetVertexColor(Theme.Color(name, alpha))
end

-- Chat lines start with the addon's name in the accent color.
Noir.prefix = "|cff" .. HEX.lamp .. "Noir|r: "
