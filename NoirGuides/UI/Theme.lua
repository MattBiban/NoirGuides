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
--   Theme.CLASS_COLORS            class token -> the hex the lamp takes for that class
--   Theme.THEMES                  the "accent" option's choices: "class" (the player's own), each class by name,
--                                 "gold" and "black" (monochrome: a black panel, a silver accent)
--   Theme.ApplyAccent()           sets the lamp (and, for black, the panel colors) as the "accent" option says; runs
--                                 on NOIR_INIT before any window is built, so a change takes a reload
--   Theme.Border()                -> the guide window's inner border color name (the lamp)
--   Theme.Shadow(fontString)      the game's 1-pixel drop shadow under text (Theme.Font sets it)
--
-- Fonts are only ever set by file, with SetFont. A font object is never handed to a font string: the Forever
-- client crashes when SetFontObject is given anything but one of its own named font objects.
local Noir = Noir

local Theme = {}
Noir.Theme = Theme

-- ---------------------------------------------------------------------------------------------------------------
-- Tokens
-- ---------------------------------------------------------------------------------------------------------------

-- The game's tooltip, sharpened: a blue-black panel the player sets the opacity of, lifted plates for cards, a black
-- outer hairline, white text with a drop shadow, gold for the section's facts, bright named things.
local HEX = {
  bay = "141922",     -- the window's panel, at the player's "backgroundAlpha"
  strip = "222A37",   -- a plate: a card, the header, the footer, a row of the step list under the mouse
  ink = "000000",     -- the outer hairline and the rules between bands
  lamp = "F2B33D",    -- the accent: the current card's edge and badge, the window's border, the rail, the arrow
  quest = "FFD100",   -- the quest icons (accept, hand in) and the accept mark: gold whatever the accent
  gold = "FFD100",    -- the section's facts in the header (the game's heading gold)
  paper = "F4F5F7",   -- primary text
  dim = "B9BFCA",     -- secondary text
  faint = "8D95A3",   -- a reminder's top edge, the step numbers, the next steps' pins, an empty tick box
  track = "4A5466",   -- a card's frame, a slider's track, an empty box in menus
  well = "0B0E13",    -- the rail's track
  warn = "FF8A5C",    -- notes: something stands in the way of the step
  ok = "5BD675",      -- arrived, route complete, the hand-in mark
  -- Named things in a line's words, by meaning (the "highlight" option)
  friend = "74CCF4",  -- a friendly NPC
  enemy = "FF6F6F",   -- an enemy to kill
  loot = "D9A6FF",    -- an item to loot or use
  warning = "FF8A5C", -- a quest whose prerequisites are not handed in
  object = "7FE0CC",  -- an object to click
  buy = "BCE27A",     -- an item to buy
}

local function rgb(hex)
  return {
    tonumber(string.sub(hex, 1, 2), 16) / 255,
    tonumber(string.sub(hex, 3, 4), 16) / 255,
    tonumber(string.sub(hex, 5, 6), 16) / 255,
  }
end

Theme.colors = {}
for name, hex in pairs(HEX) do Theme.colors[name] = rgb(hex) end
local BASE = {}
for name, hex in pairs(HEX) do BASE[name] = hex end
local GOLD = HEX.lamp
-- The black theme: a black panel, darker plates and frames, and a silver accent in place of a color.
local BLACK = { lamp = "D9DDE4", bay = "000000", strip = "14171C", track = "3A3F48" }

-- The game's class colors, except where one would not read as an accent on the window (DESIGN.md, Accent): the
-- priest's white is a lavender, unlike the text; the shaman's and the warlock's blues are lighter, to 4.5 to 1.
Theme.CLASS_COLORS = {
  WARRIOR = "C69B6D", PALADIN = "F48CBA", HUNTER = "AAD372", ROGUE = "FFF468", PRIEST = "B4A7E8",
  SHAMAN = "4FA3F2", MAGE = "3FC7EB", WARLOCK = "9A9BF2", DRUID = "FF7C0A",
}
Theme.THEMES = { "class", "warrior", "paladin", "hunter", "rogue", "priest", "shaman", "mage", "warlock", "druid",
  "gold", "black" }

Theme.sizes = { kicker = 10, name = 14, body = 11, small = 10 }

Theme.metrics = {
  width = 260,  -- the window
  pad = 10,     -- from the window's edge to its content
  gap = 4,      -- between two blocks of text
  lamp = 2,     -- a card's top edge in the accent
  rail = 5,     -- the rail's thickness
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
Theme.textures = { arrow = true, pin = true, ["pin-active"] = true, box = true, tick = true, grip = true, menu = true,
  sheen = true, bar = true }
-- The kind icons of a line, as UI/Text.lua names them, and the timer of the flight bar: textures "icon-<name>".
Theme.ICONS = { "accept", "turnin", "objective", "kill", "item", "vendor", "trainer", "gossip", "flight", "flightpoint",
  "hearth", "bind", "goto", "xp", "error", "note", "timer" }
for _, icon in ipairs(Theme.ICONS) do Theme.textures["icon-" .. icon] = true end

-- The side bar of a new current card shows the step's kind for metrics.mark seconds, in this color (spec 4.2).
Theme.MARKS = { turnin = "ok", accept = "quest", train = "friend", objective = "enemy", travel = "dim" }

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

-- The game's own text shadow: one pixel down and right, nearly black, so text reads over any part of the world.
function Theme.Shadow(fontString)
  if fontString.SetShadowOffset then fontString:SetShadowOffset(1, -1) end
  if fontString.SetShadowColor then fontString:SetShadowColor(0, 0, 0, 0.9) end
end

function Theme.Font(fontString, role, large)
  local size = (Theme.sizes[role] or Theme.sizes.body) + (large and Theme.metrics.large or 0)
  if try(fontString, Theme.fontFile, size) or try(fontString, STANDARD_TEXT_FONT, size) or try(fontString, USUAL_FONT, size) then
    Theme.Shadow(fontString)
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

-- ---------------------------------------------------------------------------------------------------------------
-- Accent
-- ---------------------------------------------------------------------------------------------------------------

local function set(name, hex)
  HEX[name] = hex
  Theme.colors[name] = rgb(hex)
end

function Theme.ApplyAccent()
  for name, hex in pairs(BASE) do set(name, hex) end
  local Options = Noir.Options
  local choice = Options and Options.Get("accent") or "class"
  local hex = GOLD
  if choice == "black" then
    for name, value in pairs(BLACK) do set(name, value) end
    hex = BLACK.lamp
  elseif choice == "class" then
    local token = UnitClass and select(2, UnitClass("player"))
    hex = type(token) == "string" and Theme.CLASS_COLORS[token] or GOLD
  elseif choice ~= "gold" then
    hex = Theme.CLASS_COLORS[string.upper(tostring(choice))] or GOLD
  end
  set("lamp", hex)
  -- Chat lines start with the addon's name in the accent color.
  Noir.prefix = "|cff" .. hex .. "Noir|r: "
end

function Theme.Border()
  return "lamp"
end

Theme.ApplyAccent()
-- Registered here, before any interface file registers its own: the lamp is set before a window is built.
Noir.On("NOIR_INIT", Theme.ApplyAccent)
