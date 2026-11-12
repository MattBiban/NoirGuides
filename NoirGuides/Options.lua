-- Noir Guides, GPLv3. See LICENSE.
-- Options: the player's settings (spec 6.1), kept in account-wide profiles in NoirGuidesDB.profiles, each
-- character using one of them (NoirGuidesCharDB.profile). Window places are kept per profile too. Core makes the
-- saved variables (schema 2) and migrates the 0.1.x ones; this file reads and writes them.
--
--   Options.DEFAULTS                      every option key and its default
--   Options.RANGES                        key -> { min, max [, whole] } for numbers, { choices = { ... } } for words
--   Options.Get(key)                      the value in the profile in use, else the default (nil for an unknown key)
--   Options.Set(key, value)               -> true | false, reason; checks type and range; fires NOIR_OPTION(key, value)
--   Options.Profile()                     -> the name of the profile in use
--   Options.Profiles()                    -> the names of all profiles, sorted
--   Options.NewProfile(name [, copyFrom]) -> true | false, reason; an empty profile, or a copy of copyFrom
--   Options.UseProfile(name)              -> true | false, reason; fires NOIR_PROFILE(name)
--   Options.DeleteProfile(name)           -> true | false, reason; never the profile in use or the last one
--   Options.ResetProfile()                -> true; every value of the profile in use back to its default, window
--                                            places included; fires NOIR_PROFILE(name) so windows take their places
--   Options.SetDefaultProfile(name)       -> true | false, reason; the profile new characters start with
--   Options.Position(key)                 -> a copy of { point, relPoint, x, y [, w, h] } saved for a window, or nil
--   Options.SavePosition(key, pos)        -> true | false, reason; pos nil forgets the place
--
-- Before the saved variables are ready (NOIR_INIT), Get returns the defaults and nothing can be changed.
local Noir = Noir

local Options = {}
Noir.Options = Options

Options.DEFAULTS = {
  -- General
  shown = true, locked = false, hideInRaid = false, minimap = true, minimapAngle = 225,
  -- Guide window
  windowHidden = false, cardsBelow = false, windowScale = 1, fontSize = "standard", accent = "class", stepList = true,
  hideFinished = false, otherSections = false, highlight = true, itemButtons = true, buttonBackground = true,
  buttonScale = 1,
  -- Navigation
  arrow = true, arrowScale = 1, arrowText = 12, minimapPins = true, pinRing = false, worldPins = 7, pinSize = 1,
  pinMerge = 1, pinAlpha = 0.6,
  -- Automation
  autoQuests = true, guideRewards = false, rewardMarker = true, bestReward = false, train = false, flights = true,
  hearth = true, dialogue = true, buy = true, targetButtons = true, nameplates = true, markers = true,
  -- Route
  outlevel = true, groupQuests = false, talents = true,
  -- Advanced
  neverSkip = false, offerCleanup = true, conflicts = true, debug = false,
}

Options.RANGES = {
  minimapAngle = { min = 0, max = 360 },
  windowScale = { min = 0.2, max = 2 },
  fontSize = { choices = { "standard", "large" } },
  accent = { choices = { "class", "gold" } },
  buttonScale = { min = 0.8, max = 3 },
  arrowScale = { min = 0.2, max = 2 },
  arrowText = { min = 8, max = 20, whole = true },
  worldPins = { min = 0, max = 20, whole = true },
  pinSize = { min = 0.5, max = 2 },
  pinMerge = { min = 0.05, max = 2 },
  pinAlpha = { min = 0, max = 1 },
}

local POINTS = {
  TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true,
  BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}
local NOT_READY = "the settings are not loaded yet"
local FALLBACK = "Default"

local function finite(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = copy(v) end
  return out
end

local function profiles()
  local db = Noir.db
  return db and type(db.profiles) == "table" and db.profiles or nil
end

function Options.Profile()
  local all = profiles()
  if not all then return FALLBACK end
  local name = Noir.char and Noir.char.profile
  if type(name) == "string" and type(all[name]) == "table" then return name end
  name = Noir.db.defaultProfile
  if type(name) == "string" and type(all[name]) == "table" then return name end
  return FALLBACK
end

local function current()
  local all = profiles()
  if not all then return nil end
  local profile = all[Options.Profile()]
  if type(profile) ~= "table" then
    profile = {}
    all[Options.Profile()] = profile
  end
  return profile
end

-- Whether a value fits a key: true, or false and the reason in words.
local function check(key, value)
  local default = Options.DEFAULTS[key]
  if default == nil then return false, "there is no option named " .. tostring(key) end
  local range = Options.RANGES[key]
  if type(default) == "boolean" then
    if type(value) ~= "boolean" then return false, key .. " takes true or false" end
    return true
  end
  if range and range.choices then
    for _, choice in ipairs(range.choices) do
      if value == choice then return true end
    end
    return false, key .. " takes one of " .. table.concat(range.choices, ", ")
  end
  if type(default) == "number" then
    local words = (range and range.whole) and "a whole number" or "a number"
    local span = range and (" from " .. tostring(range.min) .. " to " .. tostring(range.max)) or ""
    local reason = key .. " takes " .. words .. span
    if not finite(value) then return false, reason end
    if range and (value < range.min or value > range.max) then return false, reason end
    if range and range.whole and value ~= math.floor(value) then return false, reason end
    return true
  end
  if type(value) ~= type(default) then return false, key .. " takes a " .. type(default) end
  return true
end

function Options.Get(key)
  local default = Options.DEFAULTS[key]
  if default == nil then return nil end
  local profile = current()
  local value = profile and profile[key]
  if value == nil or not check(key, value) then return default end
  return value
end

function Options.Set(key, value)
  if Options.DEFAULTS[key] == nil then return false, "there is no option named " .. tostring(key) end
  local profile = current()
  if not profile then return false, NOT_READY end
  local good, reason = check(key, value)
  if not good then return false, reason end
  profile[key] = value
  Noir.Fire("NOIR_OPTION", key, value)
  return true
end

function Options.Profiles()
  local names = {}
  for name in pairs(profiles() or {}) do names[#names + 1] = name end
  table.sort(names)
  return names
end

local function validName(name)
  if type(name) ~= "string" then return nil end
  name = string.gsub(string.gsub(name, "^%s+", ""), "%s+$", "")
  if name == "" or string.len(name) > 40 then return nil end
  return name
end

function Options.NewProfile(name, copyFrom)
  local all = profiles()
  if not all then return false, NOT_READY end
  name = validName(name)
  if not name then return false, "a profile needs a name of 1 to 40 characters" end
  if all[name] then return false, "there is already a profile named " .. name end
  if copyFrom ~= nil and type(all[copyFrom]) ~= "table" then return false, "there is no profile named " .. tostring(copyFrom) end
  all[name] = copyFrom ~= nil and copy(all[copyFrom]) or {}
  return true
end

function Options.UseProfile(name)
  local all = profiles()
  if not all then return false, NOT_READY end
  if type(all[name]) ~= "table" then return false, "there is no profile named " .. tostring(name) end
  Noir.char.profile = name
  Noir.Fire("NOIR_PROFILE", name)
  return true
end

function Options.DeleteProfile(name)
  local all = profiles()
  if not all then return false, NOT_READY end
  if type(all[name]) ~= "table" then return false, "there is no profile named " .. tostring(name) end
  if name == Options.Profile() then return false, "the profile in use cannot be deleted" end
  if #Options.Profiles() <= 1 then return false, "the last profile cannot be deleted" end
  all[name] = nil
  if Noir.db.defaultProfile == name then Noir.db.defaultProfile = Options.Profile() end
  return true
end

function Options.ResetProfile()
  local profile = current()
  if not profile then return false, NOT_READY end
  for key in pairs(profile) do profile[key] = nil end
  Noir.Fire("NOIR_PROFILE", Options.Profile())
  return true
end

function Options.SetDefaultProfile(name)
  local all = profiles()
  if not all then return false, NOT_READY end
  if type(all[name]) ~= "table" then return false, "there is no profile named " .. tostring(name) end
  Noir.db.defaultProfile = name
  return true
end

-- A saved place: two anchor point names, two finite offsets, and optionally a positive width and height.
local function validPosition(pos)
  if type(pos) ~= "table" then return false end
  if not (POINTS[pos[1]] and POINTS[pos[2]] and finite(pos[3]) and finite(pos[4])) then return false end
  if pos[5] ~= nil or pos[6] ~= nil then
    if not (finite(pos[5]) and finite(pos[6]) and pos[5] > 0 and pos[6] > 0) then return false end
  end
  return true
end

function Options.Position(key)
  local profile = current()
  local positions = profile and profile.positions
  local pos = type(positions) == "table" and positions[key]
  if not validPosition(pos) then return nil end
  return { pos[1], pos[2], pos[3], pos[4], pos[5], pos[6] }
end

function Options.SavePosition(key, pos)
  if type(key) ~= "string" then return false, "a window place needs a window key" end
  local profile = current()
  if not profile then return false, NOT_READY end
  if pos == nil then
    if type(profile.positions) == "table" then profile.positions[key] = nil end
    return true
  end
  if not validPosition(pos) then return false, "a window place is { point, relative point, x, y [, width, height] }" end
  Noir.Table(profile, "positions")[key] = { pos[1], pos[2], pos[3], pos[4], pos[5], pos[6] }
  return true
end
