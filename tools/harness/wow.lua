-- Noir Guides, GPLv3. See LICENSE.
-- The mock game client. It loads the addon's files in toc order into a Lua 5.1 style global table (env.lua) and
-- gives them a fake game API: frames and events, the quest log, taxi, maps, professions, saved variables.
-- Test scripts drive it with the methods at the bottom (login, acceptQuest, moveTo, openTaxi, ...), each of which
-- changes the fake server state and then fires the events the real client fires, in the real order.
--
-- Written for this project from the public API documentation. Where the real client's behavior is not certain,
-- the mock takes an option so tests can cover both possibilities; docs/ENGINE-NOTES.md lists those.
--
--   local c = HARNESS.Client.new({ race = "Undead", class = "ROGUE", level = 1 })
--   c:login()
--   c:acceptQuest(364)
--   eq(c.G.Noir.State.quests[364].title, "The Mindless Ones")
local Env = HARNESS.Env
local Client = {}
Client.__index = Client

local ADDON = "NoirGuides"

local RACES = {
  Human = { id = 1, token = "Human", name = "Human", faction = "Alliance" },
  Orc = { id = 2, token = "Orc", name = "Orc", faction = "Horde" },
  Dwarf = { id = 3, token = "Dwarf", name = "Dwarf", faction = "Alliance" },
  NightElf = { id = 4, token = "NightElf", name = "Night Elf", faction = "Alliance" },
  Undead = { id = 5, token = "Scourge", name = "Undead", faction = "Horde" },
  Tauren = { id = 6, token = "Tauren", name = "Tauren", faction = "Horde" },
  Gnome = { id = 7, token = "Gnome", name = "Gnome", faction = "Alliance" },
  Troll = { id = 8, token = "Troll", name = "Troll", faction = "Horde" },
  -- The client's ChrRaces table gives both Skyborne races the same file string and tells them apart by ID.
  HighOrder = { id = 95, token = "Skyborne", name = "High Order Skyborne", faction = "Alliance" },
  Windshaper = { id = 96, token = "Skyborne", name = "Windshaper Skyborne", faction = "Horde" },
}
local CLASSES = {
  WARRIOR = { id = 1, name = "Warrior" }, PALADIN = { id = 2, name = "Paladin" }, HUNTER = { id = 3, name = "Hunter" },
  ROGUE = { id = 4, name = "Rogue" }, PRIEST = { id = 5, name = "Priest" }, SHAMAN = { id = 7, name = "Shaman" },
  MAGE = { id = 8, name = "Mage" }, WARLOCK = { id = 9, name = "Warlock" }, DRUID = { id = 11, name = "Druid" },
}

local EVENTS = {}
for name in string.gmatch([[
  ADDON_LOADED PLAYER_LOGIN PLAYER_LOGOUT PLAYER_ENTERING_WORLD PLAYER_LEAVING_WORLD PLAYER_LEVEL_UP PLAYER_XP_UPDATE
  QUEST_LOG_UPDATE QUEST_ACCEPTED QUEST_REMOVED QUEST_TURNED_IN QUEST_WATCH_UPDATE UNIT_QUEST_LOG_CHANGED
  QUEST_DETAIL QUEST_PROGRESS QUEST_COMPLETE QUEST_GREETING QUEST_FINISHED GOSSIP_SHOW GOSSIP_CLOSED
  TAXIMAP_OPENED TAXIMAP_CLOSED UI_INFO_MESSAGE UI_ERROR_MESSAGE HEARTHSTONE_BOUND CONFIRM_BINDER
  ZONE_CHANGED ZONE_CHANGED_NEW_AREA ZONE_CHANGED_INDOORS SKILL_LINES_CHANGED CHAT_MSG_SKILL CHAT_MSG_SYSTEM
  PLAYER_REGEN_DISABLED PLAYER_REGEN_ENABLED PLAYER_CONTROL_LOST PLAYER_CONTROL_GAINED PLAYER_MONEY BAG_UPDATE
  PLAYER_DEAD PLAYER_ALIVE PLAYER_UNGHOST LEARNED_SPELL_IN_TAB TRAINER_SHOW TRAINER_CLOSED MERCHANT_SHOW
  MERCHANT_CLOSED UNIT_SPELLCAST_SUCCEEDED COMBAT_LOG_EVENT_UNFILTERED COMBAT_LOG_EVENT
  CHARACTER_POINTS_CHANGED PLAYER_TALENT_UPDATE SPELLS_CHANGED ACTIVE_TALENT_GROUP_CHANGED
  DISPLAY_SIZE_CHANGED UI_SCALE_CHANGED GROUP_ROSTER_UPDATE QUEST_ACCEPT_CONFIRM UNIT_SPELLCAST_START
  ADDON_ACTION_BLOCKED PLAYER_TARGET_CHANGED RAID_TARGET_UPDATE CVAR_UPDATE MODIFIER_STATE_CHANGED
  BAG_UPDATE_DELAYED BAG_UPDATE_COOLDOWN QUEST_WATCH_LIST_CHANGED
  UNIT_SPELLCAST_STOP UNIT_SPELLCAST_INTERRUPTED UNIT_SPELLCAST_FAILED SPELL_UPDATE_COOLDOWN PLAYER_EQUIPMENT_CHANGED
]], "%S+") do
  EVENTS[name] = true
end
-- Events the addon must never register (see the plan's global constraints).
local FORBIDDEN_EVENTS = { COMBAT_LOG_EVENT_UNFILTERED = true, COMBAT_LOG_EVENT = true }

local MAP_TYPE = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 }

-- A small world with the game's real map, area and taxi node IDs. Tests add to it through opts.world or addMap.
-- A map's `rect` is where it lies on its parent, as { left, top, right, bottom } in the parent's 0 to 1 space.
-- A continent's `world` is its place in world coordinates, in yards: `top` is the north coordinate of its upper
-- edge and `left` the west coordinate of its left edge (the game's world X axis points north, its Y axis west).
-- The rects and sizes are made up; they only have to be consistent, every map being 3 wide to 2 high.
local function defaultWorld()
  return {
    maps = {
      [946] = { name = "Cosmic", type = MAP_TYPE.Cosmic },
      [947] = { name = "Azeroth", type = MAP_TYPE.World, parent = 946 },
      [1415] = { name = "Eastern Kingdoms", type = MAP_TYPE.Continent, parent = 947, instance = 0,
        world = { top = 5000, left = 4000, width = 12000, height = 8000 } },
      [1414] = { name = "Kalimdor", type = MAP_TYPE.Continent, parent = 947, instance = 1,
        world = { top = 12000, left = 4000, width = 15000, height = 10000 } },
      [1420] = { name = "Tirisfal Glades", type = MAP_TYPE.Zone, parent = 1415, area = 85, rect = { 0.30, 0.10, 0.50, 0.30 } },
      [1421] = { name = "Silverpine Forest", type = MAP_TYPE.Zone, parent = 1415, area = 130, rect = { 0.25, 0.28, 0.40, 0.43 } },
      [1458] = { name = "Undercity", type = MAP_TYPE.Zone, parent = 1415, area = 1497, rect = { 0.44, 0.24, 0.48, 0.28 } },
      [1429] = { name = "Elwynn Forest", type = MAP_TYPE.Zone, parent = 1415, area = 12, rect = { 0.35, 0.70, 0.55, 0.90 } },
      [1411] = { name = "Durotar", type = MAP_TYPE.Zone, parent = 1414, area = 14, rect = { 0.55, 0.40, 0.70, 0.55 } },
      [1454] = { name = "Orgrimmar", type = MAP_TYPE.Zone, parent = 1414, area = 1637, rect = { 0.56, 0.36, 0.61, 0.41 } },
    },
    taxi = {
      [384] = { name = "Brill, Tirisfal Glades", continent = 1415, at = { uiMap = 1420, x = 58.9, y = 51.9 } },
      [10] = { name = "The Sepulcher, Silverpine Forest", continent = 1415, at = { uiMap = 1421, x = 45.6, y = 42.6 } },
      [11] = { name = "Undercity, Tirisfal", continent = 1415, at = { uiMap = 1458, x = 63.3, y = 48.5 } },
      [2] = { name = "Stormwind, Elwynn", continent = 1415, at = { uiMap = 1429, x = 32.0, y = 49.0 } },
      [23] = { name = "Orgrimmar, Durotar", continent = 1414, at = { uiMap = 1454, x = 45.1, y = 63.9 } },
    },
    quests = {
      [364] = { title = "The Mindless Ones", level = 2, header = "Tirisfal Glades", objectives = {
        { text = "Mindless Zombie slain", type = "monster", need = 8 },
        { text = "Wretched Zombie slain", type = "monster", need = 8 },
      } },
      [363] = { title = "Rude Awakening", level = 1, header = "Tirisfal Glades", objectives = {} },
      [376] = { title = "The Damned", level = 2, header = "Tirisfal Glades", objectives = {
        { text = "Scavenger Paw", type = "item", need = 6 },
        { text = "Duskbat Wing", type = "item", need = 6 },
      } },
      [8] = { title = "A Rogue's Deal", level = 5, header = "Tirisfal Glades", objectives = {} },
      [435] = { title = "Escorting Erland", level = 11, header = "Silverpine Forest", objectives = {
        { text = "Erland must reach Rane Yorick", type = "event" },
      } },
    },
    -- Items the client has in its cache: GetItemInfo knows these and returns nil for any other.
    items = { [3265] = "Scavenger Paw", [159] = "Refreshing Spring Water", [2287] = "Haunch of Meat", [6948] = "Hearthstone" },
    -- Spells by ID, for GetSpellInfo; itemSpells: the spell an item casts when used, itemCooldowns its cooldown.
    spells = { [556] = "Astral Recall", [8690] = "Hearthstone" },
    itemSpells = { [6948] = 8690 },
    itemCooldowns = { [6948] = 3600 },
    stacks = { [6948] = 1 },
    -- Who the player can talk to: offers and ends are quest IDs, taxi a node ID, binder the inn's place name,
    -- options further gossip lines ({ type = "vendor", text = "..." }), greeting = true for an NPC that shows the
    -- quest greeting window instead of gossip.
    npcs = {
      [1569] = { name = "Shadow Priest Sarvis", offers = { 364 }, ends = { 364 } },
      [6784] = { name = "Calvin Montague", offers = { 8 } },
      [5688] = { name = "Innkeeper Renee", binder = "Brill", options = { { type = "vendor", text = "Let me browse your goods." } } },
      [4551] = { name = "Michael Garrett", taxi = 384 },
      [1950] = { name = "Rane Yorick", offers = { 435 }, ends = { 435 } },
      [1501] = { name = "Mindless Zombie", enemy = true },
    },
  }
end

local function deepCopy(v, seen)
  if type(v) ~= "table" then return v end
  seen = seen or {}
  if seen[v] then return seen[v] end
  local out = {}
  seen[v] = out
  for k, x in pairs(v) do out[deepCopy(k, seen)] = deepCopy(x, seen) end
  return out
end

-- Saved variables are written to disk as plain data. Anything else in them is silently lost by the real client,
-- so the mock refuses it loudly.
local function checkPlainData(v, where, seen)
  local t = type(v)
  if t == "string" or t == "number" or t == "boolean" or t == "nil" then return end
  if t ~= "table" then error("saved variable " .. where .. " holds a " .. t .. ", which cannot be saved", 0) end
  seen = seen or {}
  if seen[v] then error("saved variable " .. where .. " refers to itself", 0) end
  seen[v] = true
  for k, x in pairs(v) do
    if type(k) ~= "string" and type(k) ~= "number" then error("saved variable " .. where .. " has a " .. type(k) .. " key", 0) end
    checkPlainData(x, where .. "." .. tostring(k), seen)
  end
  seen[v] = nil
end

local function parseToc(text)
  local toc = { files = {}, meta = {} }
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do
    local key, value = line:match("^##%s*([^:]-)%s*:%s*(.-)%s*$")
    if key then
      toc.meta[key] = value
    elseif not line:match("^%s*#") and line:match("%S") then
      toc.files[#toc.files + 1] = (line:gsub("\\", "/"):gsub("^%s+", ""):gsub("%s+$", ""))
    end
  end
  return toc
end
Client.parseToc = parseToc

local function names(list)
  local out = {}
  for name in (list or ""):gmatch("[^,%s]+") do out[#out + 1] = name end
  return out
end

-- ---------------------------------------------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------------------------------------------

-- opts:
--   race, class, level, name      the character (race is the route's race name, e.g. "Undead", "HighOrder")
--   zone / uiMap, x, y            starting place (defaults to Tirisfal Glades 30, 71)
--   api = "classic" | "modern"    which quest log API the client has (default "classic")
--   taxiIds = bool                whether C_TaxiMap.GetAllTaxiNodes exists (default: only on "modern")
--   professionApi                 "book" (GetProfessions, default), "tradeskill" (C_TradeSkillUI by ID) or "none"
--   raceId = false                UnitRace returns no third value
--   levelLag = false              UnitLevel is already right during PLAYER_LEVEL_UP (default: it lags, as in game)
--   turnInLag = false             the quest leaves the log before QUEST_TURNED_IN (default: after it)
--   without = { "C_Timer", "C_QuestLog.IsOnQuest" }   API names to remove
--   withoutEvents = { "HEARTHSTONE_BOUND" }           events this client does not know
--   swap = { { match = "^Routes/", with = { "tools/test-lua/sample/route.lua" } } }
--                                 toc entries matching a pattern are replaced by repo-relative files
--   files = { ... }               load exactly these repo-relative files instead of the toc's
--   afterLoad = function(client)  runs after the addon's files, before the saved variables are restored (for a
--                                 route a test registers as if it were one more route file); kept over a relog
--   gossipApi                     "global" (GetGossipOptions and friends, by index; default on "classic"), "info"
--                                 (C_GossipInfo with quest IDs and option IDs; default on "modern") or "info-index"
--                                 (C_GossipInfo without IDs, everything selected by index)
--   gossipStride = N              how many values per quest the "global" gossip lists return (default 7; 6 for active)
--   greetingIds = false           the quest greeting window gives titles only, no quest IDs
--   oldGuid = true                UnitGUID returns the old hexadecimal form, which carries no readable NPC ID
--   mapCanvas = "field"           the world map has no GetCanvas(): the canvas is WorldMapFrame.ScrollContainer.Child
--                                 and the shown map is WorldMapFrame.mapID
--   fonts = { path = true }       the font files the client has (default: the four the game ships)
--   world                         replaces the default world; server and saved carry state over a relog
--   xpToLevel = { 400, 900, ... }  the experience needed to finish each level (index = level), as UnitXPMax reports
--                                 it; default: 400 times the level
--   talentApi = "none"            the client has no talent functions (default: the Classic Era ones, see Talents)
--   talents = { tabs }            the character's talent trees: { { name, talents = { { name, tier, column, max,
--                                 rank, prereq = { tier, column } } } } }; default: the trees of the addon's
--                                 Noir.Data.talents for the class, read when the addon first asks
--   screen = { w, h, scale }      the resolution in pixels and the UI scale (default 1024, 768, 1). As in the game,
--                                 UIParent is 768 / scale units high and 768 * w / h / scale wide, whatever the
--                                 pixel count; client:setScreen changes it and fires the display events
--   settingsApi                   "modern" (Settings.RegisterCanvasLayoutCategory and friends; default on "modern"),
--                                 "legacy" (InterfaceOptions_AddCategory; default on "classic") or "none"
--   doubleClickTime = 0.5         the longest gap, in seconds, between the clicks of a double click
--   bags = { 16, 0, 0, 0, 0 }     the slots of the backpack (bag 0) and of bags 1 to 4
--   cvars = { name = "value" }    console variables the client has besides rotateMinimap
--   addons = { "TomTom" }         other addons the client has loaded (IsAddOnLoaded)
--   takeoffLag = seconds          TakeTaxiNode closes the flight map at once and the flight starts (PLAYER_CONTROL_LOST)
--                                 that much later (default: at once); read when TakeTaxiNode is called
--   questLogSize = 20             the most quests the log holds (acceptQuest refuses more)
function Client.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Client)
  self.opts = opts
  self.api = opts.api or "classic"
  assert(self.api == "classic" or self.api == "modern", "api must be classic or modern")
  self.world = opts.world or defaultWorld()
  self.saved = opts.saved or { account = {}, characters = {} }
  self.chat, self.errors, self.violations, self.calls = {}, {}, {}, {}
  self.undefined, self.globalsSet, self.missingFiles = {}, {}, {}
  self.frames, self.timers = {}, {}
  self.now = 1000
  self.loaded, self.loggedIn, self.loggedOut = false, false, false
  self.questLogReady = false
  self.selectionChanges = 0
  self.npc, self.dialog, self.rewards = nil, nil, {}
  self.mods = { CTRL = false, SHIFT = false, ALT = false }
  local screen = opts.screen or {}
  self.screen = { w = screen.w or screen[1] or 1024, h = screen.h or screen[2] or 768, scale = screen.scale or screen[3] or 1 }
  self.cursor = { x = 0, y = 0 }
  self.fired, self.slashes, self.reloads = {}, 0, 0
  self.watched, self.nearby, self.marks, self.itemCooldownsAt = {}, {}, {}, {}
  self.optionCategories = {}
  self.cvars = { rotateMinimap = "0" }
  for name, value in pairs(opts.cvars or {}) do self.cvars[name] = tostring(value) end
  self.minimapZoom = 0
  self.knownEvents = deepCopy(EVENTS)
  for _, e in ipairs(opts.withoutEvents or {}) do self.knownEvents[e] = nil end

  if opts.server then
    self.s = opts.server
  else
    local race, class = opts.race or "Undead", opts.class or "WARRIOR"
    assert(RACES[race], "unknown race " .. tostring(race))
    assert(CLASSES[class], "unknown class " .. tostring(class))
    local uiMap = opts.uiMap
    if not uiMap and opts.zone then uiMap = self:mapForArea(opts.zone) end
    self.s = {
      name = opts.name or "Tester", realm = "Mock", race = race, class = class, level = opts.level or 1, xp = 0, money = 0,
      quests = {}, collapsed = {}, completed = {}, flights = {}, professions = {},
      bind = { name = "Deathknell" },
      pos = { uiMap = uiMap or 1420, x = opts.x or 30, y = opts.y or 71 },
      facing = 0,
      combat = false, onTaxi = false,
      talents = opts.talents and deepCopy(opts.talents) or nil,
      spells = {}, equipped = {}, bags = {},
    }
  end
  local s = self.s
  s.spells, s.equipped, s.bags = s.spells or {}, s.equipped or {}, s.bags or {}
  local slots = opts.bags or { 16, 0, 0, 0, 0 }
  for bag = 0, 4 do
    s.bags[bag] = s.bags[bag] or { size = slots[bag + 1] or 0 }
  end
  self.key = self.s.name .. "-" .. self.s.realm
  self:buildGlobals()
  if HARNESS.T then HARNESS.T.track(self) end
  return self
end

function Client:mapForArea(area)
  for id, map in pairs(self.world.maps) do
    if map.area == area then return id end
  end
  error("the mock world has no map for area " .. tostring(area))
end

function Client:addMap(id, map)
  self.world.maps[id] = map
end

-- ---------------------------------------------------------------------------------------------------------------
-- Calling into the addon
-- ---------------------------------------------------------------------------------------------------------------

function Client:callAddon(fn, ...)
  local good, err = xpcall(fn, function(e) return debug.traceback(tostring(e), 2) end, ...)
  if not good then self.errors[#self.errors + 1] = err end
  return good
end

-- Returns the errors the addon raised so far and clears them, for tests that expect one.
function Client:takeErrors()
  local out = self.errors
  self.errors = {}
  return out
end

function Client:takeViolations()
  local out = self.violations
  self.violations = {}
  return out
end

function Client:takeChat()
  local out = self.chat
  self.chat = {}
  return out
end

-- All chat lines as one string, for has(c:chatText(), "...").
function Client:chatText()
  return table.concat(self.chat, "\n")
end

-- ---------------------------------------------------------------------------------------------------------------
-- Frames
-- ---------------------------------------------------------------------------------------------------------------

local Frame = {}
Frame.__index = Frame

function Frame:RegisterEvent(event)
  local c = self.__client
  if type(event) ~= "string" or not c.knownEvents[event] then
    error('Frame:RegisterEvent(): Attempt to register unknown event "' .. tostring(event) .. '"', 2)
  end
  if FORBIDDEN_EVENTS[event] then c.violations[#c.violations + 1] = "registered " .. event end
  self.__events[event] = true
  return true
end
function Frame:UnregisterEvent(event) self.__events[event] = nil end
function Frame:UnregisterAllEvents() self.__events = {} end
function Frame:IsEventRegistered(event) return self.__events[event] == true end
function Frame:SetScript(kind, fn)
  assert(fn == nil or type(fn) == "function", "SetScript needs a function or nil")
  self.__scripts[kind] = fn
end
function Frame:GetScript(kind) return self.__scripts[kind] end
function Frame:HookScript(kind, fn)
  local old = self.__scripts[kind]
  self.__scripts[kind] = old and function(...) old(...) fn(...) end or fn
end
function Frame:GetName() return self.__name end
function Frame:GetObjectType() return self.__type end
function Frame:GetParent() return self.__parent end
Client.Frame = Frame

-- ---------------------------------------------------------------------------------------------------------------
-- Widgets: enough of frames, textures and font strings for the addon's interface to run and for tests to read
-- back what it shows. The mock is strict where the game is: text on a font string without a font is an error, a
-- texture or font file of the addon that does not exist is an error, a size or offset that is not a number is an
-- error. Frames the addon must leave alone (the world map, the minimap) record a violation when it changes them.
-- Positions on screen are worked out for frames only, from their first anchor.
-- ---------------------------------------------------------------------------------------------------------------

-- The default screen. Each client has its own (opts.screen, client:setScreen); see Client:uiSize.
local SCREEN = { width = 1024, height = 768 }
local POINT_NAMES = {
  TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true,
  BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}
local STRATA = {
  BACKGROUND = true, LOW = true, MEDIUM = true, HIGH = true, DIALOG = true, FULLSCREEN = true,
  FULLSCREEN_DIALOG = true, TOOLTIP = true,
}
local LAYERS = { BACKGROUND = true, BORDER = true, ARTWORK = true, OVERLAY = true, HIGHLIGHT = true }
local GAME_FONTS = {
  ["fonts\\frizqt__.ttf"] = true, ["fonts\\arialn.ttf"] = true, ["fonts\\morpheus.ttf"] = true, ["fonts\\skurri.ttf"] = true,
}
local ADDON_PATH = "interface\\addons\\noirguides\\"

local function number(v, what)
  if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
    error(what .. " must be a number, got " .. tostring(v), 3)
  end
  return v
end

-- Whether a file the addon names exists. The game's own files are taken to exist; a file under the addon's
-- folder must be in the repository, with one of the given extensions when the path has none.
function Client:fileExists(path, extensions)
  local lower = path:lower()
  if lower:sub(1, #ADDON_PATH) ~= ADDON_PATH then return true end
  local rel = ADDON .. "/" .. path:sub(#ADDON_PATH + 1):gsub("\\", "/")
  for _, extension in ipairs(extensions) do
    if host.exists(rel .. extension) then return true end
  end
  return false
end

function Client:hasFont(path)
  local lower = path:lower()
  if lower:sub(1, #ADDON_PATH) == ADDON_PATH then return self:fileExists(path, { "" }) end
  if self.opts.fonts then
    for known in pairs(self.opts.fonts) do
      if known:lower() == lower then return true end
    end
    return false
  end
  return GAME_FONTS[lower] == true
end

local function visible(region)
  local at, depth = region, 0
  while at and depth < 50 do
    if not at.__shown then return false end
    at, depth = at.__parent, depth + 1
  end
  return true
end

-- Runs OnShow or OnHide for a frame whose visibility changed, and for the shown frames inside it.
local function notify(frame, now)
  local script = frame.__scripts[now and "OnShow" or "OnHide"]
  if script then frame.__client:callAddon(script, frame) end
  for _, child in ipairs(frame.__children) do
    if child.__shown then notify(child, now) end
  end
end

local function setShown(self, shown)
  shown = shown and true or false
  if self.__shown == shown then return end
  local was = visible(self)
  self.__shown = shown
  if self.__children and visible(self) ~= was then notify(self, not was) end
end

local function effectiveScale(region)
  local scale, at, depth = 1, region, 0
  while at and depth < 50 do
    scale = scale * (at.__scale or 1)
    at, depth = at.__parent, depth + 1
  end
  return scale
end

local function fractions(point)
  local fx, fy = 0.5, 0.5
  if point:find("LEFT") then fx = 0 elseif point:find("RIGHT") then fx = 1 end
  if point:find("TOP") then fy = 1 elseif point:find("BOTTOM") then fy = 0 end
  return fx, fy
end

-- Whether two anchors of a frame pin both its edges on one axis (1 = x, 2 = y), so the anchors set its size.
local function spans(frame, axis)
  local first
  for _, p in ipairs(frame.__points) do
    local f = select(axis, fractions(p[1]))
    if first == nil then first = f elseif f ~= first then return true end
  end
  return false
end

-- One axis of a frame's rectangle from its anchors: `list` holds { fraction of the frame, place } per anchor.
-- Two anchors at different fractions give the start and the length; one gives the start for the given length.
local function solve(list, length)
  local a = list[1]
  for i = 2, #list do
    local b = list[i]
    if b[1] ~= a[1] then
      local lo, hi = a, b
      if lo[1] > hi[1] then lo, hi = hi, lo end
      local size = (hi[2] - lo[2]) / (hi[1] - lo[1])
      return lo[2] - lo[1] * size, size
    end
  end
  return a[2] - a[1] * length, length
end

-- A frame's place on the screen: left, bottom, width, height in UIParent units (the bottom left corner is 0, 0),
-- or nil when it has no anchor. Every anchor counts: two anchors on opposite sides set the size on that axis. A
-- scroll child without anchors hangs from its scroll frame's top left corner, moved by the scroll offsets.
local function rect(frame, depth)
  depth = depth or 0
  if depth > 20 then return nil end
  if frame.__screen then
    local w, h = frame.__client:uiSize()
    return 0, 0, w, h
  end
  if frame.__allPoints then return rect(frame.__allPoints, depth + 1) end
  local scale = effectiveScale(frame)
  local owner = frame.__scrollOwner
  if owner and #frame.__points == 0 then
    local left, bottom, _, height = rect(owner, depth + 1)
    if not left then return nil end
    local ownerScale = effectiveScale(owner)
    local w, h = (frame.__w or 0) * scale, (frame.__h or 0) * scale
    local top = bottom + height + (owner.__vscroll or 0) * ownerScale
    return left - (owner.__hscroll or 0) * ownerScale, top - h, w, h
  end
  if #frame.__points == 0 then return nil end
  local xs, ys = {}, {}
  for _, p in ipairs(frame.__points) do
    local relative = p[2] or frame.__parent or rawget(frame.__client.G, "UIParent")
    local left, bottom, width, height = rect(relative, depth + 1)
    if not left then return nil end
    local rx, ry = fractions(p[3])
    local fx, fy = fractions(p[1])
    xs[#xs + 1] = { fx, left + rx * width + p[4] * scale }
    ys[#ys + 1] = { fy, bottom + ry * height + p[5] * scale }
  end
  local left, width = solve(xs, (frame.__w or 0) * scale)
  local bottom, height = solve(ys, (frame.__h or 0) * scale)
  return left, bottom, width, height
end

-- Whether a frame lies under UIParent, so the UI scale applies to it.
local function underUIParent(frame)
  local at, depth = frame, 0
  while at and depth < 50 do
    if at.__screen then return true end
    at, depth = at.__parent, depth + 1
  end
  return false
end

-- Whether a frame is protected or holds a protected frame: the game locks both in combat.
local function locked(frame)
  if frame.__protected then return true end
  for _, child in ipairs(frame.__children or {}) do
    if locked(child) then return true end
  end
  return false
end

-- What frames, textures and font strings share.
local Shared = {}
function Shared:Show() setShown(self, true) end
function Shared:Hide() setShown(self, false) end
function Shared:SetShown(shown) setShown(self, shown) end
function Shared:IsShown() return self.__shown end
function Shared:IsVisible() return visible(self) end
function Shared:SetPoint(point, a, b, c, d)
  if not POINT_NAMES[point] then error("SetPoint: unknown point " .. tostring(point), 2) end
  local relative, relativePoint, x, y
  if type(a) == "number" or a == nil and b == nil then
    x, y = a, b
  else
    relative, relativePoint, x, y = a, b, c, d
  end
  if relative ~= nil and (type(relative) ~= "table" or relative.__points == nil) then
    error("SetPoint: relativeTo must be a frame or a region, got " .. tostring(relative), 2)
  end
  if relative == self then error("SetPoint: a region cannot be anchored to itself", 2) end
  if relativePoint ~= nil and not POINT_NAMES[relativePoint] then error("SetPoint: unknown relative point " .. tostring(relativePoint), 2) end
  local entry = { point, relative, relativePoint or point, number(x or 0, "SetPoint: x"), number(y or 0, "SetPoint: y") }
  self.__allPoints = nil
  for i, old in ipairs(self.__points) do
    if old[1] == point then
      self.__points[i] = entry
      return
    end
  end
  self.__points[#self.__points + 1] = entry
end
function Shared:ClearAllPoints() self.__points, self.__allPoints = {}, nil end
function Shared:SetAllPoints(relative)
  if relative ~= nil and relative ~= true and (type(relative) ~= "table" or relative.__points == nil) then
    error("SetAllPoints: relativeTo must be a frame or a region", 2)
  end
  self.__points = {}
  self.__allPoints = (type(relative) == "table" and relative) or self.__parent
end
function Shared:GetNumPoints() return #self.__points end
function Shared:GetPoint(index)
  local p = self.__points[index or 1]
  if not p then return nil end
  return p[1], p[2], p[3], p[4], p[5]
end
-- A frame whose size changed runs OnSizeChanged(self, width, height). The game runs it on the next frame; the
-- mock runs it at once, which only makes it earlier.
local function resized(self, oldW, oldH)
  if not self.__scripts or (self.__w == oldW and self.__h == oldH) then return end
  local fn = self.__scripts.OnSizeChanged
  if fn then self.__client:callAddon(fn, self, self.__w or 0, self.__h or 0) end
end
function Shared:SetSize(width, height)
  local oldW, oldH = self.__w, self.__h
  number(width, "SetSize: width")
  number(height, "SetSize: height")
  if width < 0 or height < 0 then error("SetSize: a size cannot be negative", 2) end
  self.__w, self.__h = width, height
  resized(self, oldW, oldH)
end
function Shared:SetWidth(width)
  local oldW = self.__w
  number(width, "SetWidth: width")
  if width < 0 then error("SetWidth: a size cannot be negative", 2) end
  self.__w = width
  resized(self, oldW, self.__h)
end
function Shared:SetHeight(height)
  local oldH = self.__h
  number(height, "SetHeight: height")
  if height < 0 then error("SetHeight: a size cannot be negative", 2) end
  self.__h = height
  resized(self, self.__w, oldH)
end
-- The size in the region's own units: what its anchors give when two of them pin both sides, else its own size.
local function measured(self, axis)
  if self.__screen then return (select(axis, self.__client:uiSize())) end
  if self.__allPoints then
    local other = self.__allPoints
    return axis == 1 and other:GetWidth() or other:GetHeight()
  end
  if #self.__points >= 2 and spans(self, axis) then
    local _, _, w, h = rect(self)
    if w then return (axis == 1 and w or h) / effectiveScale(self) end
  end
  return (axis == 1 and self.__w or self.__h) or 0
end
function Shared:GetWidth() return measured(self, 1) end
function Shared:GetHeight() return measured(self, 2) end
function Shared:GetSize() return self:GetWidth(), self:GetHeight() end
function Shared:SetAlpha(alpha)
  number(alpha, "SetAlpha: alpha")
  if alpha < 0 or alpha > 1 then error("SetAlpha: alpha must be from 0 to 1, got " .. alpha, 2) end
  self.__alpha = alpha
end
function Shared:GetAlpha() return self.__alpha end
for name, fn in pairs(Shared) do Frame[name] = fn end

-- Frames
function Frame:SetParent(parent)
  if parent ~= nil and (type(parent) ~= "table" or not parent.__children) then error("SetParent: the parent must be a frame", 2) end
  local old = self.__parent
  if old == parent then return end
  local was = visible(self)
  if old then
    for i, child in ipairs(old.__children) do
      if child == self then
        table.remove(old.__children, i)
        break
      end
    end
  end
  self.__parent = parent
  if parent then parent.__children[#parent.__children + 1] = self end
  if visible(self) ~= was then notify(self, not was) end
end
function Frame:SetScale(scale)
  number(scale, "SetScale: scale")
  if scale <= 0 then error("SetScale: the scale must be above 0, got " .. scale, 2) end
  self.__scale = scale
end
function Frame:GetScale()
  if self.__screen then return self.__client.screen.scale end
  return self.__scale
end
-- The scale from the frame's own units to the screen's: every scale above it, times the UI scale under UIParent.
function Frame:GetEffectiveScale()
  local ui = underUIParent(self) and self.__client.screen.scale or 1
  return effectiveScale(self) * ui
end
function Frame:SetMovable(movable) self.__movable = movable and true or false end
function Frame:IsMovable() return self.__movable == true end
-- The mouse: clicks and motion (OnEnter, OnLeave) are two switches; EnableMouse sets both.
function Frame:EnableMouse(enabled)
  self.__mouseClick, self.__mouseMotion = enabled and true or false, enabled and true or false
end
function Frame:SetMouseClickEnabled(enabled) self.__mouseClick = enabled and true or false end
function Frame:SetMouseMotionEnabled(enabled) self.__mouseMotion = enabled and true or false end
function Frame:IsMouseEnabled() return self.__mouseClick == true or self.__mouseMotion == true end
function Frame:IsMouseClickEnabled() return self.__mouseClick == true end
function Frame:IsMouseMotionEnabled() return self.__mouseMotion == true end
function Frame:EnableMouseWheel(enabled) self.__wheel = enabled and true or false end
function Frame:IsMouseWheelEnabled() return self.__wheel == true end
function Frame:EnableKeyboard(enabled) self.__keyboard = enabled and true or false end
function Frame:IsKeyboardEnabled() return self.__keyboard == true end
-- Restricted in combat on clients built on the modern code, as the Forever client may be (docs/ENGINE-NOTES.md).
function Frame:SetPropagateKeyboardInput(on)
  local c = self.__client
  if c.s.combat then
    c.violations[#c.violations + 1] = "SetPropagateKeyboardInput in combat"
    return
  end
  self.__propagate = on and true or false
end
function Frame:GetPropagateKeyboardInput() return self.__propagate == true end
function Frame:SetClampedToScreen(clamped) self.__clamped = clamped and true or false end
function Frame:IsClampedToScreen() return self.__clamped == true end
function Frame:SetClipsChildren(clips) self.__clips = clips and true or false end
function Frame:DoesClipChildren() return self.__clips == true end
function Frame:RegisterForDrag(...)
  self.__drag = {}
  for i = 1, select("#", ...) do self.__drag[(select(i, ...))] = true end
end
function Frame:StartMoving()
  if not self.__movable then error("StartMoving: the frame is not movable", 2) end
  self.__moving = true
  self.__client.moving = self
end
function Frame:SetResizable(resizable) self.__resizable = resizable and true or false end
function Frame:IsResizable() return self.__resizable == true end
function Frame:SetResizeBounds(minW, minH, maxW, maxH)
  self.__bounds = { number(minW or 0, "SetResizeBounds: min width"), number(minH or 0, "SetResizeBounds: min height"), maxW, maxH }
end
local SIZING_POINTS = { BOTTOMRIGHT = true, RIGHT = true, BOTTOM = true }
function Frame:StartSizing(point)
  if not self.__resizable then error("StartSizing: the frame is not resizable", 2) end
  point = point or "BOTTOMRIGHT"
  if not SIZING_POINTS[point] then error("StartSizing: the mock sizes from BOTTOMRIGHT, RIGHT or BOTTOM, got " .. tostring(point), 2) end
  self.__sizing = point
  self.__client.moving = self
end
function Frame:StopMovingOrSizing() self.__moving, self.__sizing = false, nil end
-- Attributes, as secure buttons read them. Any frame has them; on a protected frame they are locked in combat.
function Frame:SetAttribute(name, value)
  self.__attributes = self.__attributes or {}
  self.__attributes[name] = value
end
function Frame:GetAttribute(name) return self.__attributes and self.__attributes[name] end
-- As in the game: first whether the frame is protected at all (a frame holding a protected one is, implicitly),
-- then whether it is protected itself.
function Frame:IsProtected() return locked(self), self.__protected == true end
function Frame:SetFrameStrata(strata)
  if not STRATA[strata] then error("SetFrameStrata: unknown strata " .. tostring(strata), 2) end
  self.__strata = strata
end
function Frame:GetFrameStrata() return self.__strata or (self.__parent and self.__parent:GetFrameStrata()) or "MEDIUM" end
function Frame:SetFrameLevel(level)
  number(level, "SetFrameLevel: level")
  if level < 0 or level > 10000 or level ~= math.floor(level) then error("SetFrameLevel: the level must be a whole number from 0 to 10000, got " .. level, 2) end
  self.__level = level
end
function Frame:GetFrameLevel() return self.__level end
function Frame:GetLeft()
  local left = rect(self)
  return left and left / effectiveScale(self) or nil
end
function Frame:GetBottom()
  local left, bottom = rect(self)
  return left and bottom / effectiveScale(self) or nil
end
function Frame:GetRight()
  local left, _, width = rect(self)
  return left and (left + width) / effectiveScale(self) or nil
end
function Frame:GetTop()
  local left, bottom, _, height = rect(self)
  return left and (bottom + height) / effectiveScale(self) or nil
end
function Frame:GetCenter()
  local left, bottom, width, height = rect(self)
  if not left then return nil end
  local scale = effectiveScale(self)
  return (left + width / 2) / scale, (bottom + height / 2) / scale
end

local Texture, FontString = {}, {}
Texture.__index, FontString.__index = Texture, FontString
for name, fn in pairs(Shared) do Texture[name], FontString[name] = fn, fn end

local function newRegion(frame, class, kind, name, layer)
  if name ~= nil and type(name) ~= "string" then error("Create" .. kind .. ": the name must be a string or nil", 3) end
  if layer ~= nil and not LAYERS[layer] then error("Create" .. kind .. ": unknown layer " .. tostring(layer), 3) end
  local region = setmetatable({
    __client = frame.__client, __type = kind, __name = name, __parent = frame, __shown = true,
    __points = {}, __alpha = 1, __layer = layer or "ARTWORK",
  }, class)
  frame.__regions[#frame.__regions + 1] = region
  if name then rawset(frame.__client.G, name, region) end
  return region
end
function Frame:CreateTexture(name, layer) return newRegion(self, Texture, "Texture", name, layer) end
function Frame:CreateFontString(name, layer, template)
  local region = newRegion(self, FontString, "FontString", name, layer)
  if template ~= nil then
    local font = type(template) == "string" and rawget(self.__client.G, template)
    if not (type(font) == "table" and font.__type == "Font") then error("CreateFontString: no font object named " .. tostring(template), 2) end
    region.__font = { font.__font[1], font.__font[2], font.__font[3] }
  end
  return region
end

-- A protected frame, or a frame holding one, cannot be changed in combat: the game blocks the call and raises
-- ADDON_ACTION_BLOCKED. The mock records it as a forbidden call and leaves the frame as it was.
for _, name in ipairs({
  "SetAttribute", "Show", "Hide", "SetShown", "SetPoint", "ClearAllPoints", "SetAllPoints", "SetSize", "SetWidth",
  "SetHeight", "SetScale", "SetParent", "EnableMouse", "SetFrameStrata", "SetFrameLevel", "StartMoving",
  "StartSizing", "StopMovingOrSizing",
}) do
  local raw = Frame[name]
  Frame[name] = function(self, ...)
    local c = self.__client
    if c.s.combat and locked(self) then
      c.violations[#c.violations + 1] = "ADDON_ACTION_BLOCKED: " .. name .. " on a protected frame in combat"
      return nil
    end
    return raw(self, ...)
  end
end

-- Changing a guarded frame is what the addon must not do to the world map, the minimap, the talent frame and the
-- quest log frame.
for _, name in ipairs({
  "RegisterEvent", "UnregisterEvent", "UnregisterAllEvents", "SetScript", "HookScript", "Show", "Hide", "SetShown",
  "SetPoint", "ClearAllPoints", "SetAllPoints", "SetSize", "SetWidth", "SetHeight", "SetAlpha", "SetParent", "SetScale",
  "SetMovable", "EnableMouse", "SetClampedToScreen", "RegisterForDrag", "StartMoving", "StopMovingOrSizing",
  "SetFrameStrata", "SetFrameLevel", "CreateTexture", "CreateFontString", "SetMouseClickEnabled",
  "SetMouseMotionEnabled", "EnableMouseWheel", "EnableKeyboard", "SetAttribute", "SetClipsChildren",
}) do
  local raw = Frame[name]
  Frame[name] = function(self, ...)
    if self.__guarded then
      local c = self.__client
      c.violations[#c.violations + 1] = "changed " .. self.__guarded .. " with " .. name
      return nil
    end
    return raw(self, ...)
  end
end

-- Buttons: enabled or not, and Click() as a script would do it.
local Button = setmetatable({}, { __index = Frame })
Button.__index = Button
function Button:Enable() self.__disabled = false end
function Button:Disable() self.__disabled = true end
function Button:SetEnabled(on) self.__disabled = not on end
function Button:IsEnabled() return not self.__disabled end
function Button:RegisterForClicks(...)
  self.__clicks = {}
  for i = 1, select("#", ...) do self.__clicks[(select(i, ...))] = true end
end
function Button:Click(button) self.__client:click(self, button or "LeftButton") end

-- Scroll frames: a scroll child moved by the scroll offsets, and everything outside the scroll frame clipped.
local ScrollFrame = setmetatable({}, { __index = Frame })
ScrollFrame.__index = ScrollFrame
function ScrollFrame:SetScrollChild(child)
  if child ~= nil and (type(child) ~= "table" or not child.__children) then error("SetScrollChild: the child must be a frame", 2) end
  if self.__scrollChild then self.__scrollChild.__scrollOwner = nil end
  self.__scrollChild = child
  if child then child.__scrollOwner = self end
end
function ScrollFrame:GetScrollChild() return self.__scrollChild end
function ScrollFrame:SetVerticalScroll(offset) self.__vscroll = number(offset, "SetVerticalScroll: offset") end
function ScrollFrame:GetVerticalScroll() return self.__vscroll or 0 end
function ScrollFrame:SetHorizontalScroll(offset) self.__hscroll = number(offset, "SetHorizontalScroll: offset") end
function ScrollFrame:GetHorizontalScroll() return self.__hscroll or 0 end
function ScrollFrame:GetVerticalScrollRange()
  local child = self.__scrollChild
  if not child then return 0 end
  return math.max(0, child:GetHeight() - self:GetHeight())
end

-- Cooldown spirals: only what they were told.
local Cooldown = setmetatable({}, { __index = Frame })
Cooldown.__index = Cooldown
function Cooldown:SetCooldown(start, duration)
  self.__cooldown = { number(start, "SetCooldown: start"), number(duration, "SetCooldown: duration") }
end
function Cooldown:Clear() self.__cooldown = nil end
function Cooldown:GetCooldownTimes()
  local cd = self.__cooldown
  if not cd then return 0, 0 end
  return cd[1] * 1000, cd[2] * 1000
end
function Cooldown:GetCooldownDuration()
  local cd = self.__cooldown
  return cd and cd[2] * 1000 or 0
end
function Cooldown:SetReverse(on) self.__reverse = on and true or false end
function Cooldown:SetDrawEdge(on) self.__edge = on and true or false end
function Cooldown:SetHideCountdownNumbers(on) self.__hideNumbers = on and true or false end

-- The game's tooltip: lines that tests read back with client:tooltip().
local Tooltip = setmetatable({}, { __index = Frame })
Tooltip.__index = Tooltip
function Tooltip:SetOwner(owner, anchor)
  if type(owner) ~= "table" or not owner.__children then error("GameTooltip:SetOwner: the owner must be a frame", 2) end
  self.__owner, self.__anchor, self.__lines = owner, anchor or "ANCHOR_RIGHT", {}
end
function Tooltip:GetOwner() return self.__owner end
function Tooltip:IsOwned(frame) return self.__owner == frame end
function Tooltip:ClearLines() self.__lines = {} end
function Tooltip:AddLine(text)
  self.__lines = self.__lines or {}
  self.__lines[#self.__lines + 1] = Env.tostring51(text)
end
function Tooltip:AddDoubleLine(left, right)
  self.__lines = self.__lines or {}
  self.__lines[#self.__lines + 1] = Env.tostring51(left) .. " " .. Env.tostring51(right)
end
function Tooltip:SetText(text) self.__lines = { Env.tostring51(text) } end
function Tooltip:NumLines() return #(self.__lines or {}) end
function Tooltip:SetHyperlink(link)
  local c = self.__client
  local kind, id = tostring(link):match("(%a+):(%d+)")
  id = tonumber(id)
  local text
  if kind == "quest" then
    local def = c.world.quests[id]
    text = def and def.title or ("Quest " .. tostring(id))
  elseif kind == "item" then
    text = c.world.items and c.world.items[id] or ("Item " .. tostring(id))
  else
    error("GameTooltip:SetHyperlink: the mock knows quest and item links, got " .. tostring(link), 2)
  end
  self.__lines = { text }
end

Client.Button, Client.ScrollFrame, Client.Cooldown, Client.Tooltip = Button, ScrollFrame, Cooldown, Tooltip

-- Textures
function Texture:GetObjectType() return "Texture" end
function Texture:GetParent() return self.__parent end
function Texture:GetName() return self.__name end
function Texture:SetTexture(file)
  if file == nil then
    self.__texture, self.__color = nil, nil
    return true
  end
  if type(file) ~= "string" and type(file) ~= "number" then error("SetTexture: a file path or file ID is needed, got " .. type(file), 2) end
  local c = self.__client
  if type(file) == "string" and not c:fileExists(file, { "", ".tga", ".blp" }) then
    c.errors[#c.errors + 1] = "SetTexture: the addon has no texture file " .. file
  end
  self.__texture, self.__color = file, nil
  return true
end
function Texture:GetTexture() return self.__texture end
function Texture:SetColorTexture(r, g, b, a)
  self.__color = { number(r, "SetColorTexture: r"), number(g, "SetColorTexture: g"), number(b, "SetColorTexture: b"), number(a or 1, "SetColorTexture: a") }
  self.__texture = nil
end
function Texture:SetVertexColor(r, g, b, a)
  self.__vertex = { number(r, "SetVertexColor: r"), number(g, "SetVertexColor: g"), number(b, "SetVertexColor: b"), number(a or 1, "SetVertexColor: a") }
end
function Texture:GetVertexColor()
  local v = self.__vertex or { 1, 1, 1, 1 }
  return v[1], v[2], v[3], v[4]
end
function Texture:SetTexCoord(...)
  local count = select("#", ...)
  if count ~= 4 and count ~= 8 then error("SetTexCoord: 4 or 8 numbers are needed, got " .. count, 2) end
  local coords = { ... }
  for i = 1, count do number(coords[i], "SetTexCoord: value " .. i) end
  self.__coords = coords
end
function Texture:GetTexCoord()
  local t = self.__coords or { 0, 1, 0, 1 }
  if #t == 4 then return t[1], t[3], t[1], t[4], t[2], t[3], t[2], t[4] end
  return table.unpack(t, 1, 8)
end
-- Turns the texture by `radians`, counterclockwise, around its middle (the map's path dashes use it).
function Texture:SetRotation(radians)
  self.__rotation = number(radians, "SetRotation: radians")
end
function Texture:GetRotation() return self.__rotation or 0 end
function Texture:SetBlendMode(mode)
  if not ({ DISABLE = true, BLEND = true, ALPHAKEY = true, ADD = true, MOD = true })[mode] then error("SetBlendMode: unknown mode " .. tostring(mode), 2) end
  self.__blend = mode
end
function Texture:SetDrawLayer(layer, sublevel)
  if not LAYERS[layer] then error("SetDrawLayer: unknown layer " .. tostring(layer), 2) end
  self.__layer, self.__sublevel = layer, sublevel
end
function Texture:GetDrawLayer() return self.__layer, self.__sublevel or 0 end

-- Font strings
function FontString:GetObjectType() return "FontString" end
function FontString:GetParent() return self.__parent end
function FontString:GetName() return self.__name end
function FontString:SetFont(path, size, flags)
  if type(path) ~= "string" or type(size) ~= "number" or size <= 0 or size ~= size then return false end
  if flags ~= nil and type(flags) ~= "string" then error("SetFont: the flags must be a string", 2) end
  if not self.__client:hasFont(path) then return false end
  self.__font = { path, size, flags or "" }
  return true
end
function FontString:GetFont()
  if not self.__font then return nil end
  return self.__font[1], self.__font[2], self.__font[3]
end
-- Handing a font string anything but a named font object crashes the game client (a stack overflow in its font
-- code), so the mock treats it as a forbidden call.
function FontString:SetFontObject(font)
  local c = self.__client
  if not (type(font) == "table" and font.__type == "Font" and type(font.__name) == "string") then
    c.violations[#c.violations + 1] = "SetFontObject with something that is not a named font object"
    return
  end
  self.__font = { font.__font[1], font.__font[2], font.__font[3] }
end
function FontString:SetText(text)
  if not self.__font then error("FontString:SetText(): Font not set", 2) end
  if text ~= nil and type(text) ~= "string" and type(text) ~= "number" then error("SetText: the text must be a string, a number or nil, got " .. type(text), 2) end
  self.__text = text ~= nil and Env.tostring51(text) or nil
end
function FontString:GetText() return self.__text end
function FontString:SetTextColor(r, g, b, a)
  self.__color = { number(r, "SetTextColor: r"), number(g, "SetTextColor: g"), number(b, "SetTextColor: b"), number(a or 1, "SetTextColor: a") }
end
function FontString:GetTextColor()
  local v = self.__color or { 1, 1, 1, 1 }
  return v[1], v[2], v[3], v[4]
end
function FontString:SetJustifyH(justify)
  if not ({ LEFT = true, CENTER = true, RIGHT = true })[justify] then error("SetJustifyH: unknown value " .. tostring(justify), 2) end
  self.__justifyH = justify
end
function FontString:SetJustifyV(justify)
  if not ({ TOP = true, MIDDLE = true, BOTTOM = true })[justify] then error("SetJustifyV: unknown value " .. tostring(justify), 2) end
  self.__justifyV = justify
end
function FontString:SetWordWrap(wrap) self.__wrap = wrap and true or false end
function FontString:SetNonSpaceWrap(wrap) self.__nonSpaceWrap = wrap and true or false end
function FontString:SetMaxLines(lines) self.__maxLines = number(lines, "SetMaxLines: lines") end
function FontString:SetSpacing(spacing) self.__spacing = number(spacing, "SetSpacing: spacing") end
function FontString:SetShadowColor(r, g, b, a) self.__shadow = { number(r, "SetShadowColor: r"), number(g, "SetShadowColor: g"), number(b, "SetShadowColor: b"), number(a or 1, "SetShadowColor: a") } end
function FontString:SetShadowOffset(x, y) self.__shadowOffset = { number(x, "SetShadowOffset: x"), number(y, "SetShadowOffset: y") } end

-- The text without color codes, as lines. A rough model of the client's layout: half the font size per
-- character, wrapped at the width when the font string has one.
local function textLines(self)
  local text = self.__text
  if not text or text == "" or not self.__font then return {}, 0 end
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  local size = self.__font[2]
  local lines, widest = {}, 0
  for line in (text .. "\n"):gmatch("(.-)\n") do
    local width = #line * size * 0.5
    local rows = 1
    if self.__w and self.__w > 0 and self.__wrap ~= false and width > self.__w then
      rows = math.ceil(width / self.__w)
      width = self.__w
    end
    if width > widest then widest = width end
    for _ = 1, rows do lines[#lines + 1] = line end
  end
  if self.__maxLines and self.__maxLines > 0 then
    while #lines > self.__maxLines do table.remove(lines) end
  end
  return lines, widest
end
function FontString:GetStringWidth()
  local _, widest = textLines(self)
  return widest
end
function FontString:GetStringHeight()
  local lines = textLines(self)
  if #lines == 0 then return 0 end
  return #lines * (self.__font[2] + (self.__spacing or 0))
end
function FontString:GetNumLines()
  return #(textLines(self))
end

Client.Texture, Client.FontString, Client.SCREEN = Texture, FontString, SCREEN -- SCREEN: the default size only

-- An edit box: a frame that holds text the player can select and copy. Like a font string it needs a font before
-- it takes text, and handing it any font object is the call that crashes the Forever client, so the mock records
-- every SetFontObject on an edit box as a forbidden call.
local EditBox = setmetatable({}, { __index = Frame })
EditBox.__index = EditBox
EditBox.SetFont = FontString.SetFont
EditBox.GetFont = FontString.GetFont
EditBox.SetTextColor = FontString.SetTextColor
EditBox.SetJustifyH = FontString.SetJustifyH
function EditBox:SetFontObject()
  local c = self.__client
  c.violations[#c.violations + 1] = "SetFontObject on an edit box"
end
function EditBox:SetText(text)
  if not self.__font then error("EditBox:SetText(): Font not set", 2) end
  if text ~= nil and type(text) ~= "string" and type(text) ~= "number" then error("SetText: the text must be a string or a number", 2) end
  self.__text = text ~= nil and Env.tostring51(text) or ""
end
function EditBox:GetText() return self.__text or "" end
function EditBox:SetMultiLine(multi) self.__multiLine = multi and true or false end
function EditBox:IsMultiLine() return self.__multiLine == true end
function EditBox:SetAutoFocus(auto) self.__autoFocus = auto and true or false end
function EditBox:SetMaxLetters(count) self.__maxLetters = number(count, "SetMaxLetters: count") end
function EditBox:SetTextInsets(l, r, t, b)
  self.__insets = { number(l, "SetTextInsets: left"), number(r, "SetTextInsets: right"), number(t, "SetTextInsets: top"), number(b, "SetTextInsets: bottom") }
end
function EditBox:SetFocus() self.__focus = true end
function EditBox:ClearFocus() self.__focus = false end
function EditBox:HasFocus() return self.__focus == true end
function EditBox:HighlightText(from, to) self.__highlight = { from or 0, to or -1 } end
Client.EditBox = EditBox

local function isButtonType(frameType) return frameType == "Button" or frameType == "CheckButton" end

local CLASSES_BY_TYPE = {
  EditBox = EditBox, Button = Button, CheckButton = Button, ScrollFrame = ScrollFrame, Cooldown = Cooldown,
  GameTooltip = Tooltip,
}

-- `template` is the template list of CreateFrame. A secure template makes a protected frame (attributes and the
-- frame's place locked in combat; see the protected wrapper above).
function Client:createFrame(frameType, name, parent, template)
  assert(parent == nil or (type(parent) == "table" and parent.__children), "CreateFrame: the parent must be a frame")
  assert(template == nil or type(template) == "string", "CreateFrame: the template must be a string")
  local frame = setmetatable({
    __client = self, __type = frameType or "Frame", __name = name, __parent = parent,
    __events = {}, __scripts = {}, __shown = true, __template = template,
    __children = {}, __regions = {}, __points = {}, __scale = 1, __alpha = 1, __level = parent and (parent.__level + 1) or 0,
  }, CLASSES_BY_TYPE[frameType] or Frame)
  if template and template:find("Secure") then frame.__protected = true end
  -- A button takes the mouse from the start, as in the game; other frames need EnableMouse.
  if isButtonType(frameType) then frame.__mouseClick, frame.__mouseMotion = true, true end
  if parent then parent.__children[#parent.__children + 1] = frame end
  self.frames[#self.frames + 1] = frame
  frame.__serial = #self.frames
  if name then rawset(self.G, name, frame) end
  return frame
end

-- A frame of the client itself (UIParent, the world map, the tooltip, ...): not the addon's, so offScreen skips it.
function Client:gameFrame(frameType, name, parent)
  local frame = self:createFrame(frameType, name, parent)
  frame.__mock = true
  return frame
end

-- ---------------------------------------------------------------------------------------------------------------
-- The screen
-- ---------------------------------------------------------------------------------------------------------------

-- UIParent's size in its own units: 768 / scale high and as wide as the aspect ratio makes it, as in the game.
function Client:uiSize()
  local s = self.screen
  return 768 * s.w / s.h / s.scale, 768 / s.scale
end

-- Changes the resolution or the UI scale and fires the client's events for what changed.
function Client:setScreen(w, h, scale)
  local s = self.screen
  local sized, scaled = (w ~= s.w or h ~= s.h), (scale ~= nil and scale ~= s.scale)
  s.w, s.h, s.scale = w, h, scale or s.scale
  local ui = rawget(self.G, "UIParent")
  ui.__w, ui.__h = self:uiSize()
  if sized then self:fire("DISPLAY_SIZE_CHANGED") end
  if scaled then self:fire("UI_SCALE_CHANGED") end
end

-- A frame's place in UIParent units: left, bottom, right, top, resolving every anchor, size and scale; nil when it
-- has no anchor.
function Client:rectOf(frame)
  local left, bottom, width, height = rect(frame)
  if not left then return nil end
  return left, bottom, left + width, bottom + height
end

local function label(frame)
  if frame.__name then return frame.__name end
  local parts = {}
  local at = frame
  while at and not at.__screen and #parts < 4 do
    parts[#parts + 1] = (at.__name or at.__type) .. " #" .. tostring(at.__serial or "?")
    at = at.__parent
  end
  return table.concat(parts, " in ")
end

-- Every shown frame the addon created whose drawn part leaves UIParent, by name or by a label such as
-- "Frame #12 in Frame #11". Frames of the client itself (and the addon's frames inside them, such as map pins) are
-- left out; a frame inside a scroll frame or a frame that clips counts only for the part that is drawn.
function Client:offScreen()
  local W, H = self:uiSize()
  local out = {}
  local EPSILON = 0.5
  for _, frame in ipairs(self.frames) do
    if not frame.__mock and visible(frame) then
      local game = false
      local at = frame.__parent
      while at and not at.__screen do
        if at.__mock then game = true end
        at = at.__parent
      end
      local left, bottom, width, height = rect(frame)
      if not game and left then
        local right, top = left + width, bottom + height
        at = frame.__parent
        while left and at and not at.__screen do
          if at.__clips or at.__type == "ScrollFrame" then
            local l, b, w, h = rect(at)
            if l then
              left, bottom, right, top = math.max(left, l), math.max(bottom, b), math.min(right, l + w), math.min(top, b + h)
              if left >= right or bottom >= top then left = nil end
            end
          end
          at = at.__parent
        end
        if left and (left < -EPSILON or bottom < -EPSILON or right > W + EPSILON or top > H + EPSILON) then
          out[#out + 1] = label(frame)
        end
      end
    end
  end
  return out
end

-- ---------------------------------------------------------------------------------------------------------------
-- Map helpers
-- ---------------------------------------------------------------------------------------------------------------

function Client:continentOf(uiMap)
  local id, guard = uiMap, 0
  while id and guard < 20 do
    local map = self.world.maps[id]
    if not map then return nil end
    if map.type == MAP_TYPE.Continent then return id end
    id, guard = map.parent, guard + 1
  end
  return nil
end

-- The player's position on `uiMap` in 0 to 1, or nil when that map does not contain the player or the mock does
-- not know how the player's map lies on it.
function Client:positionOn(uiMap)
  local pos = self.s.pos
  if pos.hidden then return nil end
  return self:toAncestor(pos.uiMap, pos.x / 100, pos.y / 100, uiMap)
end

-- A place on `uiMap` (0 to 1) as a place on the map `top` above it, or nil when `top` is not above it or the
-- mock does not know how a map on the way lies on its parent.
function Client:toAncestor(uiMap, x, y, top)
  local id, guard = uiMap, 0
  while id and guard < 20 do
    if id == top then return x, y end
    local map = self.world.maps[id]
    if not map or not map.rect or not map.parent then return nil end
    x = map.rect[1] + x * (map.rect[3] - map.rect[1])
    y = map.rect[2] + y * (map.rect[4] - map.rect[2])
    id, guard = map.parent, guard + 1
  end
  return nil
end

-- Where `uiMap` lies on the map `top` above it: left, top, right, bottom in 0 to 1, or nil.
function Client:rectOn(uiMap, top)
  local left, up = self:toAncestor(uiMap, 0, 0, top)
  local right, down = self:toAncestor(uiMap, 1, 1, top)
  if not (left and right) then return nil end
  return left, up, right, down
end

-- The continent of a map and its place in world coordinates, or nil when the mock has none for it.
function Client:worldOf(uiMap)
  local continent = self:continentOf(uiMap)
  local def = continent and self.world.maps[continent]
  if not (def and def.world) then return nil end
  return continent, def
end

-- ---------------------------------------------------------------------------------------------------------------
-- The quest log as the client shows it: headers, then the quests under each header that is not collapsed
-- ---------------------------------------------------------------------------------------------------------------

function Client:logEntries()
  if not self.questLogReady then return {}, 0 end
  local order, groups = {}, {}
  for _, q in ipairs(self.s.quests) do
    if not groups[q.header] then
      groups[q.header] = {}
      order[#order + 1] = q.header
    end
    table.insert(groups[q.header], q)
  end
  local entries = {}
  for _, header in ipairs(order) do
    local collapsed = self.s.collapsed[header] == true
    entries[#entries + 1] = { header = header, collapsed = collapsed }
    if not collapsed then
      for _, q in ipairs(groups[header]) do entries[#entries + 1] = { quest = q } end
    end
  end
  return entries, #self.s.quests
end

function Client:findQuest(id)
  for i, q in ipairs(self.s.quests) do
    if q.id == id then return q, i end
  end
  return nil
end

local function objectiveDone(o)
  if o.type == "event" then return o.done == true end
  return (o.have or 0) >= o.need
end

local function objectiveText(o)
  if o.type == "event" then return o.text end
  return o.text .. ": " .. (o.have or 0) .. "/" .. o.need
end

-- The client's own "complete" flag. Whether a quest without objectives counts as complete in the old API is
-- not certain, so the mock leaves it unset there and the engine may not rely on it.
local function questComplete(self, q)
  if q.failed then return false end
  if q.complete ~= nil then return q.complete end
  if #q.objectives == 0 then return self.api == "modern" end
  for _, o in ipairs(q.objectives) do
    if not objectiveDone(o) then return false end
  end
  return true
end

-- ---------------------------------------------------------------------------------------------------------------
-- The fake API
-- ---------------------------------------------------------------------------------------------------------------

function Client:buildGlobals()
  local c, s = self, self.s
  local G = Env.new({ print = function(text) c.chat[#c.chat + 1] = text end })
  self.G = G
  local race, class = RACES[s.race], CLASSES[s.class]
  local function record(...) c.calls[#c.calls + 1] = { ... } end

  -- Frames, time, errors, chat
  G.CreateFrame = function(frameType, name, parent, template) return c:createFrame(frameType, name, parent, template) end
  G.UIParent = c:gameFrame("Frame", "UIParent")
  G.GetTime = function() return c.now end
  G.C_Timer = {
    After = function(seconds, fn)
      assert(type(seconds) == "number" and type(fn) == "function", "C_Timer.After(seconds, fn)")
      c.timers[#c.timers + 1] = { at = c.now + seconds, fn = fn }
    end,
  }
  local handler = function(err) c.errors[#c.errors + 1] = tostring(err) end
  G.geterrorhandler = function() return handler end
  G.seterrorhandler = function(fn) handler = fn end
  G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) c.chat[#c.chat + 1] = tostring(text) end }
  G.SlashCmdList = {}
  G.IsLoggedIn = function() return c.loggedIn end
  G.InCombatLockdown = function() return s.combat end
  G.Enum = {
    UIMapType = deepCopy(MAP_TYPE),
    FlightPathState = { Current = 0, Reachable = 1, Unreachable = 2 },
  }
  G.ERR_NEWTAXIPATH = "New flight path discovered!"

  -- The interface: the screen, fonts, the world map and the minimap. The last two are the game's own frames:
  -- the addon may read them and put its own frames inside them, and nothing else.
  local ui = G.UIParent
  ui.__screen = true
  ui.__w, ui.__h = c:uiSize()
  G.GetScreenWidth = function() return (c:uiSize()) end
  G.GetScreenHeight = function() return select(2, c:uiSize()) end
  -- The cursor in screen units at scale 1: divided by UIParent's effective scale it is in UIParent units.
  G.GetCursorPosition = function() return c.cursor.x * c.screen.scale, c.cursor.y * c.screen.scale end
  G.IsControlKeyDown = function() return c.mods.CTRL end
  G.IsShiftKeyDown = function() return c.mods.SHIFT end
  G.IsAltKeyDown = function() return c.mods.ALT end
  G.IsModifierKeyDown = function() return c.mods.CTRL or c.mods.SHIFT or c.mods.ALT end
  local tooltip = c:gameFrame("GameTooltip", "GameTooltip", ui)
  tooltip.__shown, tooltip.__lines = false, {}
  tooltip:SetFrameStrata("TOOLTIP")
  G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
  for _, name in ipairs({ "GameFontNormal", "GameFontNormalSmall", "GameFontHighlight", "GameFontHighlightSmall" }) do
    G[name] = {
      __type = "Font", __name = name, __font = { "Fonts\\FRIZQT__.TTF", 12, "" },
      GetFont = function(font) return font.__font[1], font.__font[2], font.__font[3] end,
    }
  end
  G.GetCVar = function(name) return c.cvars[name] end
  G.SetCVar = function(name, value)
    record("SetCVar", name, value)
    c.cvars[name] = value ~= nil and Env.tostring51(value) or nil
    c:fire("CVAR_UPDATE", name, value)
    return true
  end
  G.ReloadUI = function()
    record("ReloadUI")
    c.reloads = c.reloads + 1
  end
  -- Sounds: recorded, so a test can check that the interface stays quiet (spec 4.7).
  G.PlaySound = function(kit, channel)
    record("PlaySound", kit, channel)
    return true
  end
  G.PlaySoundFile = function(file, channel)
    record("PlaySoundFile", file, channel)
    return true
  end
  local worldMap = c:gameFrame("Frame", "WorldMapFrame", ui)
  worldMap.__shown = false
  worldMap.__w, worldMap.__h = c:uiSize()
  local canvas = c:gameFrame("Frame", nil, worldMap)
  canvas.__w, canvas.__h = 1002, 668
  worldMap.ScrollContainer = { Child = canvas }
  if c.opts.mapCanvas ~= "field" then
    worldMap.GetCanvas = function() return canvas end
    worldMap.GetMapID = function() return c.worldMapId end
  end
  worldMap.__guarded, canvas.__guarded = "the world map", "the world map's canvas"
  local minimap = c:gameFrame("Frame", "Minimap", ui)
  minimap.__w, minimap.__h = 140, 140
  -- Where the game puts it: the top right corner of the screen, under the clock.
  minimap.__points = { { "TOPRIGHT", ui, "TOPRIGHT", -17, -22 } }
  minimap.GetZoom = function() return c.minimapZoom end
  minimap.GetZoomLevels = function() return 6 end
  minimap.__guarded = "the minimap"
  c.worldMapFrame, c.worldMapCanvas, c.minimapFrame = worldMap, canvas, minimap
  -- The quest log frame, hidden until the player opens it (client:openQuestLog). The talent frame comes with
  -- the Blizzard_TalentUI addon the first time it is opened (client:openTalentFrame).
  local questLog = c:gameFrame("Frame", "QuestLogFrame", ui)
  questLog.__shown, questLog.__w, questLog.__h = false, 384, 512
  questLog:SetPoint("TOPLEFT", ui, "TOPLEFT", 0, -104)
  questLog.__guarded = "the quest log frame"
  -- The quest window (detail, progress and reward pages), shown while a quest page is open.
  local questFrame = c:gameFrame("Frame", "QuestFrame", ui)
  questFrame.__shown, questFrame.__w, questFrame.__h = false, 384, 512
  questFrame:SetPoint("TOPLEFT", ui, "TOPLEFT", 16, -116)

  -- The game's options window: the modern Settings API, the legacy interface options, or neither.
  local settingsApi = c.opts.settingsApi or (self.api == "modern" and "modern" or "legacy")
  assert(settingsApi == "modern" or settingsApi == "legacy" or settingsApi == "none", "settingsApi must be modern, legacy or none")
  local function openOptions(name)
    if s.combat then
      c.violations[#c.violations + 1] = "opened the options window in combat (the game refuses it)"
      return
    end
    local category = c.optionsByName and c.optionsByName[name]
    if not category then return end
    for _, other in pairs(c.optionsByName) do
      if other.frame ~= category.frame then setShown(other.frame, false) end
    end
    setShown(category.frame, true)
    setShown(c.optionsWindow, true)
    c.optionsOpen = name
  end
  local function addCategory(name, frame)
    c.optionsByName = c.optionsByName or {}
    c.optionsByName[name] = { name = name, frame = frame }
    c.optionCategories[#c.optionCategories + 1] = name
  end
  if settingsApi == "modern" then
    c.optionsWindow = c:gameFrame("Frame", "SettingsPanel", ui)
    c.optionsWindow.__shown = false
    G.Settings = {
      RegisterCanvasLayoutCategory = function(frame, name)
        assert(type(frame) == "table" and frame.__children and type(name) == "string", "Settings.RegisterCanvasLayoutCategory(frame, name)")
        record("Settings.RegisterCanvasLayoutCategory", name)
        frame:SetParent(c.optionsWindow)
        return { ID = name, name = name, frame = frame, GetID = function(self) return self.ID end }
      end,
      RegisterAddOnCategory = function(category)
        assert(type(category) == "table" and category.frame, "Settings.RegisterAddOnCategory(category)")
        record("Settings.RegisterAddOnCategory", category.name)
        addCategory(category.name, category.frame)
      end,
      OpenToCategory = function(id)
        record("Settings.OpenToCategory", id)
        if type(id) == "table" then id = id.ID end
        openOptions(id)
      end,
    }
  elseif settingsApi == "legacy" then
    c.optionsWindow = c:gameFrame("Frame", "InterfaceOptionsFrame", ui)
    c.optionsWindow.__shown = false
    G.InterfaceOptions_AddCategory = function(panel)
      assert(type(panel) == "table" and panel.__children and type(panel.name) == "string", "InterfaceOptions_AddCategory(panel) needs panel.name")
      record("InterfaceOptions_AddCategory", panel.name)
      panel:SetParent(c.optionsWindow)
      addCategory(panel.name, panel)
    end
    G.InterfaceOptionsFrame_OpenToCategory = function(panel)
      record("InterfaceOptionsFrame_OpenToCategory", type(panel) == "table" and panel.name or panel)
      openOptions(type(panel) == "table" and panel.name or panel)
    end
  end

  -- Other addons the client has loaded.
  local function addonLoaded(name)
    if name == ADDON then return c.loaded end
    for _, other in ipairs(c.opts.addons or {}) do
      if other == name then return true end
    end
    return false
  end
  if self.api == "modern" then G.C_AddOns = { IsAddOnLoaded = addonLoaded } else G.IsAddOnLoaded = addonLoaded end

  -- Addon metadata
  local function metadata(addon, field)
    if addon ~= ADDON or not c.toc then return nil end
    return c.toc.meta[field]
  end
  G.GetAddOnMetadata = metadata

  -- The player
  local function isPlayer(unit) return unit == "player" end
  local function targetDef() return c.target and c.world.npcs[c.target] or nil end
  G.UnitName = function(unit)
    if isPlayer(unit) then return s.name, nil end
    if unit == "target" and targetDef() then return targetDef().name, nil end
  end
  G.UnitExists = function(unit) return isPlayer(unit) or (unit == "target" and c.target ~= nil) end
  G.UnitIsFriend = function(a, b)
    local other = (a == "target" or b == "target") and targetDef()
    if not other then return isPlayer(a) and isPlayer(b) end
    return not other.enemy
  end
  G.UnitCanAttack = function(a, b)
    local other = (a == "target" or b == "target") and targetDef()
    return other ~= nil and other ~= false and other.enemy == true
  end
  G.SetRaidTarget = function(unit, index)
    record("SetRaidTarget", unit, index)
    if unit ~= "target" or not c.target then return end
    c.marks[c.target] = (index and index > 0) and index or nil
    c:fire("RAID_TARGET_UPDATE")
  end
  G.GetRaidTargetIndex = function(unit)
    if unit == "target" and c.target then return c.marks[c.target] end
    return nil
  end
  G.IsInRaid = function() return s.raid == true end
  G.IsInGroup = function() return s.raid == true or s.party == true end
  G.GetNumGroupMembers = function() return s.raid and 10 or 0 end
  G.GetRealmName = function() return s.realm end
  G.UnitLevel = function(unit)
    if not isPlayer(unit) then return 0 end
    return c.levelShown or s.level
  end
  G.UnitClass = function(unit) if isPlayer(unit) then return class.name, s.class, class.id end end
  G.UnitRace = function(unit)
    if not isPlayer(unit) then return nil end
    if c.opts.raceId == false then return race.name, race.token end
    return race.name, race.token, race.id
  end
  G.UnitFactionGroup = function(unit) if isPlayer(unit) then return race.faction, race.faction end end
  G.UnitXP = function(unit) return isPlayer(unit) and s.xp or 0 end
  G.UnitXPMax = function(unit) return isPlayer(unit) and c:xpForLevel(s.level) or 0 end
  G.UnitOnTaxi = function(unit) return isPlayer(unit) and s.onTaxi end
  G.UnitAffectingCombat = function(unit) return isPlayer(unit) and s.combat end
  G.UnitIsDeadOrGhost = function(unit) return isPlayer(unit) and (s.dead == true or s.ghost == true) end
  G.UnitIsGhost = function(unit) return isPlayer(unit) and s.ghost == true end
  G.UnitIsDead = function(unit) return isPlayer(unit) and s.dead == true and not s.ghost end
  G.C_DeathInfo = {
    GetCorpseMapPosition = function(uiMap)
      local corpse = s.corpse
      if not corpse then return nil end
      local x, y = c:toAncestor(corpse.uiMap, corpse.x / 100, corpse.y / 100, uiMap)
      if not x then return nil end
      return { x = x, y = y, GetXY = function(v) return v.x, v.y end }
    end,
  }
  G.GetMoney = function() return s.money end

  -- Spells and items
  G.IsSpellKnown = function(id) return s.spells[id] == true end
  G.GetSpellInfo = function(id)
    local name = c.world.spells and c.world.spells[id]
    if not name then return nil end
    return name, nil, 136243, 0, 0, 0, id
  end
  G.GetItemCount = function(id) return c:itemCount(id) end
  G.IsEquippedItem = function(id) return s.equipped[id] == true end
  local function cooldown(id)
    local cd = c.itemCooldownsAt[id]
    if not cd or c.now >= cd[1] + cd[2] then return 0, 0, 1 end
    return cd[1], cd[2], 1
  end
  G.GetItemCooldown = cooldown
  local function slotInfo(bag, slot)
    local b = s.bags[bag]
    local e = b and slot >= 1 and slot <= b.size and b[slot]
    if not e then return nil end
    return e
  end
  local function itemLink(id)
    local name = c.world.items and c.world.items[id] or ("Item " .. id)
    return "|cffffffff|Hitem:" .. id .. "::::::::|h[" .. name .. "]|h|r"
  end
  c.itemLink = itemLink
  if self.api == "modern" then
    G.C_Container = {
      GetContainerNumSlots = function(bag) return s.bags[bag] and s.bags[bag].size or 0 end,
      GetContainerItemID = function(bag, slot)
        local e = slotInfo(bag, slot)
        return e and e.id or nil
      end,
      GetContainerItemInfo = function(bag, slot)
        local e = slotInfo(bag, slot)
        if not e then return nil end
        return { iconFileID = 134400, stackCount = e.count, itemID = e.id, hyperlink = itemLink(e.id), isLocked = false }
      end,
      GetItemCooldown = cooldown,
    }
  else
    G.GetContainerNumSlots = function(bag) return s.bags[bag] and s.bags[bag].size or 0 end
    G.GetContainerItemID = function(bag, slot)
      local e = slotInfo(bag, slot)
      return e and e.id or nil
    end
    G.GetContainerItemInfo = function(bag, slot)
      local e = slotInfo(bag, slot)
      if not e then return nil end
      return 134400, e.count, false, 1, false, false, itemLink(e.id), false, false, e.id
    end
    G.GetContainerItemLink = function(bag, slot)
      local e = slotInfo(bag, slot)
      return e and itemLink(e.id) or nil
    end
  end

  -- Merchants
  local function merchantItem(i)
    return c.merchant and c.merchant.items[i]
  end
  G.GetMerchantNumItems = function() return c.merchant and #c.merchant.items or 0 end
  G.GetMerchantItemInfo = function(i)
    local e = merchantItem(i)
    if not e then return nil end
    local name = e.name or (c.world.items and c.world.items[e.item]) or ("Item " .. e.item)
    return name, 134400, e.price or 0, e.stack or 1, e.count or -1, true, true, 0
  end
  G.GetMerchantItemLink = function(i)
    local e = merchantItem(i)
    return e and itemLink(e.item) or nil
  end
  G.GetMerchantItemID = function(i)
    local e = merchantItem(i)
    return e and e.item or nil
  end
  G.GetMerchantItemMaxStack = function(i)
    local e = merchantItem(i)
    if not e then return 0 end
    return e.maxStack or (c.world.stacks and c.world.stacks[e.item]) or 20
  end
  -- quantity counts items; the price is for `stack` items (a bundle) and the stock (`count`) counts bundles. More
  -- than the stock or the money is refused whole.
  G.BuyMerchantItem = function(i, quantity)
    quantity = quantity or 1
    record("BuyMerchantItem", i, quantity)
    local e = merchantItem(i)
    if not e then return end
    local cost = math.ceil((e.price or 0) * quantity / (e.stack or 1))
    local bundles = math.ceil(quantity / (e.stack or 1)) -- the stock (count) counts purchases of `stack` items
    if e.count and e.count >= 0 and bundles > e.count then
      c:fire("UI_ERROR_MESSAGE", 54, "That item is sold out.")
      return
    end
    if cost > s.money then
      c:fire("UI_ERROR_MESSAGE", 52, "You don't have enough money.")
      return
    end
    s.money = s.money - cost
    if e.count and e.count >= 0 then e.count = e.count - bundles end
    c:giveItem(e.item, quantity)
    c:fire("PLAYER_MONEY")
  end
  G.CloseMerchant = function()
    record("CloseMerchant")
    c:closeMerchant()
  end

  -- Trainers
  local function service(i) return c.trainer and c.trainer.services[i] end
  G.GetNumTrainerServices = function() return c.trainer and #c.trainer.services or 0 end
  G.GetTrainerServiceInfo = function(i)
    local e = service(i)
    if not e then return nil end
    return e.name, e.rank or "", e.kind or "available", false
  end
  G.GetTrainerServiceCost = function(i)
    local e = service(i)
    return e and e.cost or 0
  end
  -- The skill line a service belongs to: services = { { skillLine = "Beast Training" } } for a pet trainer's.
  G.GetTrainerServiceSkillLine = function(i)
    local e = service(i)
    return e and e.skillLine or nil
  end
  G.GetTrainerServiceLevelReq = function(i)
    local e = service(i)
    return e and e.level or 0
  end
  G.BuyTrainerService = function(i)
    record("BuyTrainerService", i)
    local e = service(i)
    if not e or (e.kind or "available") ~= "available" then return end
    if (e.cost or 0) > s.money then
      c:fire("UI_ERROR_MESSAGE", 52, "You don't have enough money.")
      return
    end
    s.money = s.money - (e.cost or 0)
    e.kind = "used"
    if e.spell then c:learnSpell(e.spell) end
    c:fire("PLAYER_MONEY")
  end
  G.IsTradeskillTrainer = function() return c.trainer ~= nil and c.trainer.tradeskill == true end
  G.CloseTrainer = function()
    record("CloseTrainer")
    c:closeTrainer()
  end

  -- The quest tracker, by quest log index
  G.MAX_WATCHABLE_QUESTS = 5
  local function questAt(index)
    local e = c:logEntries()[index]
    return e and e.quest
  end
  G.AddQuestWatch = function(index)
    record("AddQuestWatch", index)
    local q = questAt(index)
    if not q or c.watched[q.id] then return end
    local count = 0
    for _ in pairs(c.watched) do count = count + 1 end
    if count >= 5 then return end
    c.watched[q.id] = true
    c:fire("QUEST_WATCH_LIST_CHANGED", q.id, true)
  end
  G.RemoveQuestWatch = function(index)
    record("RemoveQuestWatch", index)
    local q = questAt(index)
    if not q or not c.watched[q.id] then return end
    c.watched[q.id] = nil
    c:fire("QUEST_WATCH_LIST_CHANGED", q.id, false)
  end
  G.IsQuestWatched = function(index)
    local q = questAt(index)
    return q ~= nil and c.watched[q.id] == true
  end
  G.GetNumQuestWatches = function()
    local count = 0
    for _ in pairs(c.watched) do count = count + 1 end
    return count
  end
  -- A quest shared by a party member (or an escort's start): QUEST_ACCEPT_CONFIRM, answered by ConfirmAcceptQuest.
  G.ConfirmAcceptQuest = function()
    record("ConfirmAcceptQuest", c.pendingShare)
    local id = c.pendingShare
    c.pendingShare = nil
    if id and not c:findQuest(id) then c:acceptQuest(id) end
  end

  -- Maps and position
  G.C_Map = {
    GetBestMapForUnit = function(unit)
      if not isPlayer(unit) or s.pos.hidden then return nil end
      return s.pos.uiMap
    end,
    GetPlayerMapPosition = function(uiMap, unit)
      if not isPlayer(unit) then return nil end
      local x, y = c:positionOn(uiMap)
      if not x then return nil end
      return { x = x, y = y, GetXY = function(v) return v.x, v.y end }
    end,
    GetMapInfo = function(uiMap)
      local map = c.world.maps[uiMap]
      if not map then return nil end
      return { mapID = uiMap, name = map.name, mapType = map.type, parentMapID = map.parent or 0 }
    end,
  }
  local function zoneName()
    local map = c.world.maps[s.pos.uiMap]
    return map and map.name or ""
  end
  G.GetRealZoneText, G.GetZoneText = zoneName, zoneName
  G.GetSubZoneText = function() return s.pos.subZone or "" end
  G.GetMinimapZoneText = function() return s.pos.subZone or zoneName() end
  G.IsInInstance = function()
    if s.pos.hidden then return true, "party" end
    return false, "none"
  end
  G.GetInstanceInfo = function()
    local continent = c:continentOf(s.pos.uiMap)
    local instance = continent and c.world.maps[continent].instance or 0
    return zoneName(), s.pos.hidden and "party" or "none", 0, "", 0, 0, false, instance
  end
  G.GetBindLocation = function() return s.bind.name end

  -- World coordinates, in yards: the first value (a vector's x) grows to the north, the second to the west.
  local function vector(x, y)
    return { x = x, y = y, GetXY = function(v) return v.x, v.y end }
  end
  G.CreateVector2D = vector
  G.C_Map.GetWorldPosFromMapPos = function(uiMap, at)
    assert(type(at) == "table" and type(at.x) == "number" and type(at.y) == "number", "GetWorldPosFromMapPos(uiMap, vector)")
    local continent, def = c:worldOf(uiMap)
    if not continent then return nil end
    local x, y = c:toAncestor(uiMap, at.x, at.y, continent)
    if not x then return nil end
    return def.instance, vector(def.world.top - y * def.world.height, def.world.left - x * def.world.width)
  end
  G.C_Map.GetMapPosFromWorldPos = function(instance, at, uiMap)
    assert(type(at) == "table" and type(at.x) == "number" and type(at.y) == "number", "GetMapPosFromWorldPos(instance, vector [, uiMap])")
    for id, def in pairs(c.world.maps) do
      if def.type == MAP_TYPE.Continent and def.instance == instance and def.world then
        local x, y = (def.world.left - at.y) / def.world.width, (def.world.top - at.x) / def.world.height
        if not uiMap or uiMap == id then return id, vector(x, y) end
        local left, top, right, bottom = c:rectOn(uiMap, id)
        if not left then return nil end
        return uiMap, vector((x - left) / (right - left), (y - top) / (bottom - top))
      end
    end
    return nil
  end
  G.C_Map.GetMapRectOnMap = function(uiMap, top)
    local left, up, right, down = c:rectOn(uiMap, top)
    if not left then return nil end
    return left, right, up, down
  end
  G.C_Map.GetMapWorldSize = function(uiMap)
    local continent, def = c:worldOf(uiMap)
    if not continent then return nil end
    local left, top, right, bottom = c:rectOn(uiMap, continent)
    if not left then return nil end
    return (right - left) * def.world.width, (bottom - top) * def.world.height
  end
  G.C_Map.GetAreaInfo = function(area)
    for _, map in pairs(c.world.maps) do
      if map.area == area then return map.name end
    end
    return nil
  end
  -- UnitPosition gives the north coordinate first, then the west one.
  G.UnitPosition = function(unit)
    if not isPlayer(unit) or s.pos.hidden then return nil end
    local continent, def = c:worldOf(s.pos.uiMap)
    if not continent then return nil end
    local x, y = c:positionOn(continent)
    if not x then return nil end
    return def.world.top - y * def.world.height, def.world.left - x * def.world.width, 0, def.instance
  end
  -- Facing in radians: 0 is north and the value grows turning left (counterclockwise).
  G.GetPlayerFacing = function()
    if s.pos.hidden then return nil end
    return s.facing or 0
  end
  -- As the classic client: name, link, quality, item level, required level, type, subtype, stack size, equip slot,
  -- texture, sell price (world.prices, copper). Takes an ID or an item link; nil for an item not in the cache.
  G.GetItemInfo = function(id)
    if type(id) == "string" then id = tonumber(id:match("item:(%d+)")) end
    local name = id and c.world.items and c.world.items[id]
    if not name then return nil end
    local stack = (c.world.stacks and c.world.stacks[id]) or 20
    local price = (c.world.prices and c.world.prices[id]) or 0
    return name, "|cffffffff|Hitem:" .. id .. "::::::::|h[" .. name .. "]|h|r", 1, 1, 0, "Miscellaneous", "Junk", stack, "",
      134400, price
  end
  G.GetItemIcon = function(id) return 134400 end
  G.GetSpellTexture = function(id) return (c.world.spells and c.world.spells[id]) and 136243 or nil end
  G.GetSpellCooldown = function(id) return 0, 0, 1 end
  -- The portrait of a unit on a texture: the mock remembers whose it is (texture.__portrait = the target's NPC ID).
  G.SetPortraitTexture = function(texture, unit)
    record("SetPortraitTexture", unit)
    if unit == "target" and c.target then
      texture.__portrait, texture.__texture = c.target, "portrait:" .. c.target
    end
  end

  -- Quests: what every client has
  G.C_QuestLog = {
    IsOnQuest = function(id) return c.questLogReady and c:findQuest(id) ~= nil end,
    IsQuestFlaggedCompleted = function(id) return s.completed[id] == true end,
    GetQuestObjectives = function(id)
      local q = c.questLogReady and c:findQuest(id)
      if not q then return nil end
      local out = {}
      for i, o in ipairs(q.objectives) do
        out[i] = {
          text = objectiveText(o), type = o.type, finished = objectiveDone(o),
          numFulfilled = o.type == "event" and (o.done and 1 or 0) or (o.have or 0),
          numRequired = o.type == "event" and 1 or o.need,
        }
      end
      return out
    end,
  }
  if self.api == "classic" then
    G.GetNumQuestLogEntries = function()
      local entries, quests = c:logEntries()
      return #entries, quests
    end
    G.GetQuestLogTitle = function(index)
      local e = c:logEntries()[index]
      if not e then return nil end
      if e.header then return e.header, 0, nil, true, e.collapsed, nil, nil, 0 end
      local q = e.quest
      local complete = nil
      if q.failed then complete = -1 elseif questComplete(c, q) then complete = 1 end
      return q.title, q.level, nil, false, false, complete, 1, q.id
    end
    G.GetNumQuestLeaderBoards = function(index)
      assert(index, "the mock needs an explicit quest log index: the addon must not depend on the selected quest")
      local e = c:logEntries()[index]
      return (e and e.quest) and #e.quest.objectives or 0
    end
    G.GetQuestLogLeaderBoard = function(objective, index)
      assert(index, "the mock needs an explicit quest log index: the addon must not depend on the selected quest")
      local e = c:logEntries()[index]
      local o = e and e.quest and e.quest.objectives[objective]
      if not o then return nil end
      return objectiveText(o), o.type, objectiveDone(o)
    end
    G.GetQuestLogIndexByID = function(id)
      for i, e in ipairs((c:logEntries())) do
        if e.quest and e.quest.id == id then return i end
      end
      return 0
    end
    G.SelectQuestLogEntry = function(index)
      c.selectionChanges = c.selectionChanges + 1
      local e = c:logEntries()[index]
      c.selectedQuest = e and e.quest and e.quest.id or nil
    end
    -- The quest selected in the quest log and its reward choices: world.quests[id].rewardItems = { { item, name,
    -- price } } (price as for client:showReward).
    G.GetQuestLogSelection = function()
      for i, e in ipairs((c:logEntries())) do
        if e.quest and e.quest.id == c.selectedQuest then return i end
      end
      return 0
    end
    local function logChoices()
      local def = c.selectedQuest and c.world.quests[c.selectedQuest]
      return def and def.rewardItems or {}
    end
    G.GetNumQuestLogChoices = function() return #logChoices() end
    G.GetQuestLogItemLink = function(kind, i)
      local e = kind == "choice" and logChoices()[i]
      if not e then return nil end
      c.world.items = c.world.items or {}
      c.world.prices = c.world.prices or {}
      if e.name and not c.world.items[e.item] then c.world.items[e.item] = e.name end
      if e.price then c.world.prices[e.item] = e.price end
      return c.itemLink(e.item)
    end
    G.ExpandQuestHeader = function() c.violations[#c.violations + 1] = "expanded a quest log header" end
    G.CollapseQuestHeader = function() c.violations[#c.violations + 1] = "collapsed a quest log header" end
    G.IsQuestFlaggedCompleted = G.C_QuestLog.IsQuestFlaggedCompleted
    G.C_QuestLog.GetQuestInfo = function(id)
      local def = c.world.quests[id]
      return def and def.title or nil
    end
    G.GetQuestsCompleted = function(into)
      local out = into or {}
      for id in pairs(s.completed) do out[id] = true end
      return out
    end
  else
    G.C_QuestLog.GetNumQuestLogEntries = function()
      local entries, quests = c:logEntries()
      return #entries, quests
    end
    G.C_QuestLog.GetInfo = function(index)
      local e = c:logEntries()[index]
      if not e then return nil end
      if e.header then
        return { title = e.header, questLogIndex = index, questID = 0, level = 0, isHeader = true, isCollapsed = e.collapsed, isHidden = false }
      end
      local q = e.quest
      return { title = q.title, questLogIndex = index, questID = q.id, level = q.level, isHeader = false, isCollapsed = false, isHidden = false }
    end
    G.C_QuestLog.IsComplete = function(id)
      local q = c:findQuest(id)
      return q ~= nil and questComplete(c, q)
    end
    G.C_QuestLog.IsFailed = function(id)
      local q = c:findQuest(id)
      return q ~= nil and q.failed == true
    end
    G.C_QuestLog.GetAllCompletedQuestIDs = function()
      local out = {}
      for id in pairs(s.completed) do out[#out + 1] = id end
      table.sort(out)
      return out
    end
    G.C_QuestLog.GetTitleForQuestID = function(id)
      local def = c.world.quests[id]
      return def and def.title or nil
    end
    G.GetAddOnMetadata = nil
    G.C_AddOns.GetAddOnMetadata = metadata
    G.GetActiveTalentGroup = function() return s.talentGroup or 1 end
  end

  -- Taxi
  local function taxiList()
    local open = c.taxiOpen
    if not open then return {} end
    local continent = c:continentOf(s.pos.uiMap)
    local ids = {}
    for id, node in pairs(c.world.taxi) do
      if node.continent == continent and (s.flights[id] or c.opts.listUnknownTaxi) then ids[#ids + 1] = id end
    end
    table.sort(ids)
    local list = {}
    for _, id in ipairs(ids) do
      local node = c.world.taxi[id]
      local kind = "REACHABLE"
      if id == open.current then kind = "CURRENT" elseif not s.flights[id] then kind = "NONE" elseif node.distant then kind = "DISTANT" end
      list[#list + 1] = { id = id, node = node, kind = kind }
    end
    return list
  end
  G.NumTaxiNodes = function() return #taxiList() end
  G.TaxiNodeName = function(i)
    local e = taxiList()[i]
    return e and e.node.name or "INVALID"
  end
  G.TaxiNodeGetType = function(i)
    local e = taxiList()[i]
    return e and e.kind or "NONE"
  end
  G.TaxiNodePosition = function(i)
    local e = taxiList()[i]
    if not e then return 0, 0 end
    return e.node.at.x / 100, e.node.at.y / 100
  end
  G.TakeTaxiNode = function(i)
    local e = taxiList()[i]
    c.calls[#c.calls + 1] = { "TakeTaxiNode", i, e and e.id }
    if e and (e.kind == "REACHABLE") then
      local lag = c.opts.takeoffLag
      if lag then
        -- The map closes at once; the flight starts (and control is lost) a moment later.
        local id = e.id
        c:closeTaxi()
        c.timers[#c.timers + 1] = { at = c.now + lag, fn = function() c:startFlight(id) end }
      else
        c:startFlight(e.id)
      end
    end
  end
  G.CloseTaxiMap = function() c:closeTaxi() end
  local taxiIds = c.opts.taxiIds
  if taxiIds == nil then taxiIds = (self.api == "modern") end
  if taxiIds then
    G.C_TaxiMap = {
      GetAllTaxiNodes = function()
        local out = {}
        for i, e in ipairs(taxiList()) do
          local state = 1
          if e.kind == "CURRENT" then state = 0 elseif e.kind == "NONE" or e.kind == "DISTANT" then state = 2 end
          out[i] = { nodeID = e.id, name = e.node.name, state = state, slotIndex = i, position = { x = e.node.at.x / 100, y = e.node.at.y / 100 } }
        end
        return out
      end,
    }
  end

  -- Professions
  local function professionSlots()
    local primary, slots = 0, {}
    for i, p in ipairs(s.professions) do
      local index = i + 5 -- the real indexes are spell book tabs, not 1 and 2
      if p.kind == "fishing" then slots.fishing = index
      elseif p.kind == "cooking" then slots.cooking = index
      elseif p.kind == "firstaid" then slots.firstaid = index
      else
        primary = primary + 1
        slots[primary] = index
      end
    end
    return slots
  end
  local professionApi = c.opts.professionApi or "book"
  if professionApi == "book" then
    G.GetProfessions = function()
      local slots = professionSlots()
      return slots[1], slots[2], nil, slots.fishing, slots.cooking, slots.firstaid
    end
    G.GetProfessionInfo = function(index)
      local p = s.professions[(index or 0) - 5]
      if not p then return nil end
      return p.name, 136243, p.rank, p.max, 1, 0, p.skillLine, 0, nil, nil
    end
  elseif professionApi == "tradeskill" then
    G.C_TradeSkillUI = {
      GetProfessionInfoBySkillLineID = function(id)
        for _, p in ipairs(s.professions) do
          if p.skillLine == id then
            return { professionID = id, professionName = p.name, skillLevel = p.rank, maxSkillLevel = p.max }
          end
        end
        return { professionID = id, professionName = "", skillLevel = 0, maxSkillLevel = 0 }
      end,
    }
  end

  -- Talking to an NPC: gossip, the quest greeting, the quest dialogs, the binder question. See Client:talkTo.
  local function questTitle(id)
    local q = c:findQuest(id)
    local def = c.world.quests[id]
    return (q and q.title) or (def and def.title) or ("Quest " .. id)
  end
  local function questLevel(id)
    local def = c.world.quests[id]
    return def and def.level or 1
  end
  local function window(kind) return c.npc ~= nil and c.npc.window == kind end
  local function isReady(id)
    local q = c:findQuest(id)
    return q ~= nil and questComplete(c, q) or (q ~= nil and #q.objectives == 0)
  end
  G.UnitGUID = function(unit)
    if isPlayer(unit) then return "Player-4444-0000002A" end
    if unit == "npc" and c.npc then
      if c.opts.oldGuid then return string.format("0xF13000%04X00%06X", c.npc.id, 0x1A2B3C) end
      return "Creature-0-4444-0-55-" .. c.npc.id .. "-00001A2B3C"
    end
    if unit == "target" and c.target then return "Creature-0-4444-0-55-" .. c.target .. "-00002B3C4D" end
    return nil
  end
  G.CloseGossip = function() record("CloseGossip") c:closeNpc() end
  G.CloseQuest = function() record("CloseQuest") c:closeNpc() end

  local gossipApi = c.opts.gossipApi or (self.api == "modern" and "info" or "global")
  assert(gossipApi == "global" or gossipApi == "info" or gossipApi == "info-index", "gossipApi must be global, info or info-index")
  local function gossipList(kind) return window("gossip") and c.npc[kind] or {} end
  local OPTION_ICONS = { taxi = 132057, binder = 132052, vendor = 132060, trainer = 132058, banker = 132050, gossip = 132053 }
  if gossipApi == "global" then
    local function flat(kind, fields, stride)
      local out = {}
      for _, id in ipairs(gossipList(kind)) do
        local values = fields(id)
        for i = 1, stride do out[#out + 1] = values[i] end
      end
      return table.unpack(out, 1, #gossipList(kind) * stride)
    end
    G.GetNumGossipAvailableQuests = function() return #gossipList("available") end
    G.GetNumGossipActiveQuests = function() return #gossipList("active") end
    G.GetGossipAvailableQuests = function()
      return flat("available", function(id) return { questTitle(id), questLevel(id), false, 0, false, false, false } end, c.opts.gossipStride or 7)
    end
    G.GetGossipActiveQuests = function()
      return flat("active", function(id) return { questTitle(id), questLevel(id), false, isReady(id), false, false } end, c.opts.gossipStride or 6)
    end
    G.SelectGossipAvailableQuest = function(index)
      record("SelectGossipAvailableQuest", index)
      local id = gossipList("available")[index]
      if id then c:showDetail(id) end
    end
    G.SelectGossipActiveQuest = function(index)
      record("SelectGossipActiveQuest", index)
      local id = gossipList("active")[index]
      if id then c:showActive(id) end
    end
    G.GetNumGossipOptions = function() return #gossipList("options") end
    G.GetGossipOptions = function()
      local out = {}
      for _, o in ipairs(gossipList("options")) do
        out[#out + 1] = o.text
        out[#out + 1] = o.type
      end
      return table.unpack(out)
    end
    G.SelectGossipOption = function(index)
      record("SelectGossipOption", index)
      if gossipList("options")[index] then c:chooseOption(index) end
    end
  else
    local withIds = (gossipApi == "info")
    local function quests(kind)
      local out = {}
      for i, id in ipairs(gossipList(kind)) do
        out[i] = { title = questTitle(id), questLevel = questLevel(id), isTrivial = false, frequency = 0, repeatable = false, isLegendary = false, isIgnored = false }
        if kind == "active" then out[i].isComplete = isReady(id) end
        if withIds then out[i].questID = id end
      end
      return out
    end
    local function pick(kind, key)
      local list = gossipList(kind)
      if not withIds then return list[key] end
      for _, id in ipairs(list) do
        if id == key then return id end
      end
      return nil
    end
    G.C_GossipInfo = {
      GetAvailableQuests = function() return quests("available") end,
      GetActiveQuests = function() return quests("active") end,
      GetNumAvailableQuests = function() return #gossipList("available") end,
      GetNumActiveQuests = function() return #gossipList("active") end,
      SelectAvailableQuest = function(key)
        record("C_GossipInfo.SelectAvailableQuest", key)
        local id = pick("available", key)
        if id then c:showDetail(id) end
      end,
      SelectActiveQuest = function(key)
        record("C_GossipInfo.SelectActiveQuest", key)
        local id = pick("active", key)
        if id then c:showActive(id) end
      end,
      GetOptions = function()
        local out = {}
        for i, o in ipairs(gossipList("options")) do
          if withIds then
            out[i] = { gossipOptionID = 40000 + i, name = o.text, icon = OPTION_ICONS[o.type] or OPTION_ICONS.gossip, orderIndex = i - 1 }
          else
            out[i] = { name = o.text, type = o.type }
          end
        end
        return out
      end,
      SelectOption = function(key)
        record("C_GossipInfo.SelectOption", key)
        local index = withIds and (type(key) == "number" and key - 40000) or key
        if gossipList("options")[index] then c:chooseOption(index) end
      end,
      CloseGossip = function() record("C_GossipInfo.CloseGossip") c:closeNpc() end,
    }
  end

  -- The quest greeting window (an NPC with quests and no gossip text).
  local function greetingList(kind) return window("greeting") and c.npc[kind] or {} end
  local greetingIds = c.opts.greetingIds ~= false
  G.GetNumAvailableQuests = function() return #greetingList("available") end
  G.GetNumActiveQuests = function() return #greetingList("active") end
  G.GetAvailableTitle = function(index)
    local id = greetingList("available")[index]
    return id and questTitle(id) or nil
  end
  G.GetActiveTitle = function(index)
    local id = greetingList("active")[index]
    if not id then return nil end
    return questTitle(id), isReady(id)
  end
  G.GetAvailableQuestInfo = function(index)
    local id = greetingList("available")[index]
    if not id then return nil end
    if greetingIds then return false, 0, false, false, id end
    return false, 0, false, false
  end
  if greetingIds then
    G.GetActiveQuestID = function(index) return greetingList("active")[index] or 0 end
  end
  G.SelectAvailableQuest = function(index)
    record("SelectAvailableQuest", index)
    local id = greetingList("available")[index]
    if id then c:showDetail(id) end
  end
  G.SelectActiveQuest = function(index)
    record("SelectActiveQuest", index)
    local id = greetingList("active")[index]
    if id then c:showActive(id) end
  end

  -- The quest dialogs.
  G.GetQuestID = function() return c.dialog and c.dialog.quest or 0 end
  G.GetTitleText = function() return c.dialog and questTitle(c.dialog.quest) or "" end
  G.AcceptQuest = function()
    record("AcceptQuest", c.dialog and c.dialog.quest)
    if not (c.dialog and c.dialog.kind == "detail") then return end
    if #s.quests >= 20 then
      c:fire("UI_ERROR_MESSAGE", 47, "Your quest log is full.")
      return
    end
    local id = c.dialog.quest
    c.dialog = nil
    c:acceptQuest(id)
    c:closeNpc()
  end
  G.DeclineQuest = function() record("DeclineQuest") c:closeNpc() end
  G.IsQuestCompletable = function() return c.dialog ~= nil and c.dialog.kind == "progress" and isReady(c.dialog.quest) end
  G.CompleteQuest = function()
    record("CompleteQuest", c.dialog and c.dialog.quest)
    if c.dialog and c.dialog.kind == "progress" and isReady(c.dialog.quest) then
      c.dialog.kind = "complete"
      c:fire("QUEST_COMPLETE")
    end
  end
  -- The reward choices: the items client:showReward gave, else a count from the quest's definition.
  local function choiceCount()
    if not c.dialog then return 0 end
    if c.dialog.choices then return #c.dialog.choices end
    local def = c.world.quests[c.dialog.quest]
    return def and def.choices or 0
  end
  G.GetNumQuestChoices = choiceCount
  G.GetNumQuestRewards = function() return 0 end
  local function choiceAt(kind, i)
    if kind ~= "choice" or not (c.dialog and c.dialog.choices) then return nil end
    return c.dialog.choices[i]
  end
  G.GetQuestItemInfo = function(kind, i)
    local e = choiceAt(kind, i)
    if not e then return nil end
    local name = e.name or (c.world.items and c.world.items[e.item]) or ("Item " .. e.item)
    return name, 134400, e.count or 1, e.quality or 1, true, e.item
  end
  G.GetQuestItemLink = function(kind, i)
    local e = choiceAt(kind, i)
    return e and c.itemLink(e.item) or nil
  end
  G.GetQuestReward = function(choice)
    record("GetQuestReward", choice, c.dialog and c.dialog.quest)
    if not (c.dialog and c.dialog.kind == "complete") then return end
    local id = c.dialog.quest
    local def = c.world.quests[id] or {}
    local choices = choiceCount()
    if choices > 0 and not (type(choice) == "number" and choice >= 1 and choice <= choices) then
      c:fire("UI_ERROR_MESSAGE", 50, "You must choose a reward.")
      return
    end
    c.rewards[id] = choices > 0 and choice or 0
    local item = c.dialog.choices and c.dialog.choices[choice]
    local npc = c.npc
    c.dialog = nil
    c:turnInQuest(id, def.xp)
    if item then c:giveItem(item.item, item.count or 1) end
    -- A follow-up quest of the same NPC is offered at once, as the game does for a chain.
    local nextQuest
    for _, offered in ipairs(npc and npc.def.offers or {}) do
      local other = c.world.quests[offered]
      if other and other.after == id and not c:findQuest(offered) and not s.completed[offered] then nextQuest = offered end
    end
    if nextQuest then c:showDetail(nextQuest) else c:closeNpc() end
  end

  -- The innkeeper's question. The client shows it in a popup; the addon may answer it but must not restyle it.
  G.ConfirmBinder = function()
    record("ConfirmBinder")
    if not window("binder") then return end
    local name = c.npc.def.binder
    c.npc = nil
    c:bindHearth(name)
  end
  G.StaticPopup_Hide = function(which) record("StaticPopup_Hide", which) end

  -- Abandoning a quest, as the quest log's Abandon button does it: select the quest, mark it, abandon it.
  -- Classic: SelectQuestLogEntry(index), SetAbandonQuest(), AbandonQuest(). Modern: C_QuestLog.SetSelectedQuest(id),
  -- C_QuestLog.SetAbandonQuest(), C_QuestLog.AbandonQuest(). Abandoning in combat is refused, as the mock's rule.
  local function setAbandon()
    record("SetAbandonQuest", c.selectedQuest)
    c.abandoning = c.selectedQuest
  end
  local function abandon()
    record("AbandonQuest", c.abandoning)
    local id = c.abandoning
    c.abandoning = nil
    if s.combat then
      c.violations[#c.violations + 1] = "abandoned a quest in combat"
      return
    end
    if id and c:findQuest(id) then c:abandonQuest(id) end
  end
  if self.api == "classic" then
    G.SetAbandonQuest, G.AbandonQuest = setAbandon, abandon
  else
    G.C_QuestLog.SetSelectedQuest = function(id)
      c.selectionChanges = c.selectionChanges + 1
      c.selectedQuest = c:findQuest(id) and id or nil
    end
    G.C_QuestLog.GetSelectedQuest = function() return c.selectedQuest or 0 end
    G.C_QuestLog.SetAbandonQuest, G.C_QuestLog.AbandonQuest = setAbandon, abandon
  end

  -- Talents, in the form of the Classic Era client: tabs by index, talents by index inside a tab, the tier and
  -- column 1-based. Spending a point is the player's: the addon calling LearnTalent is a forbidden call.
  if (c.opts.talentApi or "era") ~= "none" then
    local function tab(index) return c:talentTabs()[index] end
    G.GetNumTalentTabs = function() return #c:talentTabs() end
    G.GetTalentTabInfo = function(index)
      local t = tab(index)
      if not t then return nil end
      return t.name, 132292, c:talentPointsIn(t), "Background" .. index
    end
    G.GetNumTalents = function(index)
      local t = tab(index)
      return t and #t.talents or 0
    end
    G.GetTalentInfo = function(index, talent)
      local t = tab(index)
      local x = t and t.talents[talent]
      if not x then return nil end
      return x.name, 136243, x.tier, x.column, x.rank or 0, x.max, x.max == 1, c:canLearnTalent(index, talent)
    end
    G.GetTalentPrereqs = function(index, talent)
      local t = tab(index)
      local x = t and t.talents[talent]
      if not (x and x.prereq) then return nil end
      return x.prereq.tier, x.prereq.column, c:prereqMet(t, x)
    end
    G.UnitCharacterPoints = function(unit)
      if not isPlayer(unit) then return 0, 0 end
      return c:unspentTalentPoints(), 0
    end
    G.LearnTalent = function(index, talent)
      record("LearnTalent", index, talent)
      c.violations[#c.violations + 1] = "spent a talent point for the player"
    end
  end
  G.GetBuildInfo = function() return "1.60.1", "70888", "Nov 1 2026", 16001 end
  -- hooksecurefunc([table,] name, hook): the hook runs after the function with the same arguments, as in the game.
  -- Hooking a function of the client's world map, minimap, talent frame or quest log frame is a violation.
  G.hooksecurefunc = function(a, b, cc)
    local t, name, hook = G, a, b
    if type(a) == "table" then t, name, hook = a, b, cc end
    assert(type(name) == "string" and type(hook) == "function", "hooksecurefunc([table,] name, hook)")
    local original = rawget(t, name)
    assert(type(original) == "function", "hooksecurefunc: no function " .. name)
    if t ~= G and t.__guarded then c.violations[#c.violations + 1] = "hooked " .. name .. " of " .. t.__guarded end
    rawset(t, name, function(...)
      local r = table.pack(original(...))
      hook(...)
      return table.unpack(r, 1, r.n)
    end)
  end

  for _, path in ipairs(c.opts.without or {}) do
    local parent, key = path:match("^(.-)%.([^.]+)$")
    if parent then
      assert(type(G[parent]) == "table", "without: no such table " .. parent)
      G[parent][key] = nil
    else
      G[path] = nil
    end
  end

  -- From here on, reads of names the client does not have and globals the addon creates are recorded.
  setmetatable(G, {
    __index = function(_, k)
      c.undefined[k] = true
      return nil
    end,
    __newindex = function(t, k, v)
      c.globalsSet[k] = true
      rawset(t, k, v)
    end,
  })
end

-- ---------------------------------------------------------------------------------------------------------------
-- Loading the addon and the session life cycle
-- ---------------------------------------------------------------------------------------------------------------

-- The repo-relative files the client will load, after opts.swap and opts.files.
function Client:fileList()
  if self.opts.files then return self.opts.files end
  local list, done = {}, {}
  for _, file in ipairs(self.toc.files) do
    local swapped = false
    for i, rule in ipairs(self.opts.swap or {}) do
      if file:find(rule.match) then
        swapped = true
        if not done[i] then
          done[i] = true
          for _, replacement in ipairs(rule.with) do list[#list + 1] = replacement end
        end
        break
      end
    end
    if not swapped then list[#list + 1] = ADDON .. "/" .. file end
  end
  return list
end

function Client:loadAddon()
  assert(not self.loaded, "the addon is already loaded in this client")
  self.loaded = true
  local tocText = assert(host.read(ADDON .. "/" .. ADDON .. ".toc"))
  self.toc = parseToc(tocText)
  local private = {}
  for _, file in ipairs(self:fileList()) do
    local source = host.read(file)
    if not source then
      self.missingFiles[#self.missingFiles + 1] = file
    else
      local chunk, err = load(source, "@" .. file, "t", self.G)
      if not chunk then
        self.errors[#self.errors + 1] = err
      else
        self:callAddon(chunk, ADDON, private)
      end
    end
  end
  if self.opts.afterLoad then self.opts.afterLoad(self) end
  -- The client restores saved variables after the files have run and before ADDON_LOADED.
  for _, name in ipairs(names(self.toc.meta.SavedVariables)) do
    if self.saved.account[name] ~= nil then rawset(self.G, name, deepCopy(self.saved.account[name])) end
  end
  local mine = self.saved.characters[self.key] or {}
  for _, name in ipairs(names(self.toc.meta.SavedVariablesPerCharacter)) do
    if mine[name] ~= nil then rawset(self.G, name, deepCopy(mine[name])) end
  end
end

-- Loads the addon if needed and fires the login events. `reload` makes it a /reload instead of a first login.
function Client:login(reload)
  assert(not self.loggedIn, "already logged in")
  if not self.loaded then self:loadAddon() end
  self:fire("ADDON_LOADED", "Blizzard_SomethingElse")
  self:fire("ADDON_LOADED", ADDON)
  self.loggedIn = true
  self:fire("PLAYER_LOGIN")
  self:fire("PLAYER_ENTERING_WORLD", not reload, reload and true or false)
  self:fire("ZONE_CHANGED_NEW_AREA")
  self:fire("SKILL_LINES_CHANGED")
  -- The quest log is empty to the API until the server has sent it.
  self.questLogReady = true
  self:fire("QUEST_LOG_UPDATE")
  return self
end

-- Fires PLAYER_LOGOUT and writes the saved variables back, as the client does on logout and on /reload.
function Client:logout()
  assert(self.loggedIn and not self.loggedOut, "not logged in")
  self:fire("PLAYER_LOGOUT")
  self.loggedOut = true
  for _, name in ipairs(names(self.toc.meta.SavedVariables)) do
    local value = rawget(self.G, name)
    checkPlainData(value, name)
    self.saved.account[name] = deepCopy(value)
  end
  local mine = self.saved.characters[self.key] or {}
  self.saved.characters[self.key] = mine
  for _, name in ipairs(names(self.toc.meta.SavedVariablesPerCharacter)) do
    local value = rawget(self.G, name)
    checkPlainData(value, name)
    mine[name] = deepCopy(value)
  end
  return self.saved
end

-- Logs out and returns a new, logged-in client for the same character with the saved variables carried over.
-- `overrides` replaces client options (api, without, ...); `overrides.reload = true` makes it a /reload.
function Client:relog(overrides)
  overrides = overrides or {}
  if not self.loggedOut then self:logout() end
  local opts = {}
  for k, v in pairs(self.opts) do opts[k] = v end
  for k, v in pairs(overrides) do opts[k] = v end
  local reload = opts.reload
  opts.reload = nil
  opts.server, opts.saved, opts.world = self.s, self.saved, self.world
  local nextClient = Client.new(opts)
  nextClient.now = self.now + (reload and 5 or 600)
  return nextClient:login(reload)
end

function Client:fire(event, ...)
  assert(EVENTS[event], "the mock does not know the event " .. tostring(event))
  local times = self.fired[event] or {}
  times[#times + 1] = self.now
  self.fired[event] = times
  local frames = {}
  for i, frame in ipairs(self.frames) do frames[i] = frame end
  for _, frame in ipairs(frames) do
    if frame.__events[event] and frame.__scripts.OnEvent then
      self:callAddon(frame.__scripts.OnEvent, frame, event, ...)
    end
  end
end

-- Lets `seconds` pass in frames of `step` seconds: timers that are due run, then every shown frame's OnUpdate.
function Client:advance(seconds, step)
  step = step or 0.1
  local target = self.now + seconds
  while self.now < target - 1e-9 do
    local dt = math.min(step, target - self.now)
    self.now = self.now + dt
    local due, rest = {}, {}
    for _, t in ipairs(self.timers) do
      if t.at <= self.now + 1e-9 then due[#due + 1] = t else rest[#rest + 1] = t end
    end
    self.timers = rest
    table.sort(due, function(a, b) return a.at < b.at end)
    for _, t in ipairs(due) do self:callAddon(t.fn) end
    local frames = {}
    for i, frame in ipairs(self.frames) do frames[i] = frame end
    for _, frame in ipairs(frames) do
      if frame.__scripts.OnUpdate and frame:IsVisible() then self:callAddon(frame.__scripts.OnUpdate, frame, dt) end
    end
  end
end

-- Types a slash command the way the chat box resolves it: through the SLASH_<KEY><n> globals.
function Client:slash(text)
  local command, rest = text:match("^(/%S+)%s*(.-)%s*$")
  assert(command, "a slash command starts with /")
  self.slashes = self.slashes + 1
  for key, fn in pairs(self.G.SlashCmdList) do
    local i = 1
    while true do
      local alias = rawget(self.G, "SLASH_" .. key .. i)
      if not alias then break end
      if alias:lower() == command:lower() then
        self:callAddon(fn, rest, nil)
        return true
      end
      i = i + 1
    end
  end
  error("no addon registered the slash command " .. command, 2)
end

-- ---------------------------------------------------------------------------------------------------------------
-- What the player does. Each method changes the server state and fires the client's events.
-- ---------------------------------------------------------------------------------------------------------------

-- Adds a quest to the log. `def` overrides the world's definition: { title, level, header, objectives }.
function Client:acceptQuest(id, def)
  assert(not self:findQuest(id), "quest " .. id .. " is already in the log")
  assert(#self.s.quests < (self.opts.questLogSize or 20), "the quest log is full")
  def = deepCopy(def or self.world.quests[id] or {})
  local q = {
    id = id, title = def.title or ("Quest " .. id), level = def.level or self.s.level,
    header = def.header or "Miscellaneous", objectives = def.objectives or {},
  }
  table.insert(self.s.quests, q)
  if self.api == "classic" then
    local index = 0
    for i, e in ipairs((self:logEntries())) do
      if e.quest == q then index = i end
    end
    self:fire("QUEST_ACCEPTED", index, id)
  else
    self:fire("QUEST_ACCEPTED", id)
  end
  self:fire("QUEST_LOG_UPDATE")
  self:fire("UNIT_QUEST_LOG_CHANGED", "player")
end

-- Sets one objective's count (or, for an event objective, whether it is done).
function Client:progressQuest(id, objective, have)
  local q = assert(self:findQuest(id), "quest " .. id .. " is not in the log")
  local o = assert(q.objectives[objective], "quest " .. id .. " has no objective " .. objective)
  if o.type == "event" then o.done = have and true or false else o.have = math.min(have, o.need) end
  self:fire("UI_INFO_MESSAGE", 287, objectiveText(o))
  self:fire("QUEST_WATCH_UPDATE", id)
  self:fire("QUEST_LOG_UPDATE")
  self:fire("UNIT_QUEST_LOG_CHANGED", "player")
end

function Client:completeObjectives(id)
  local q = assert(self:findQuest(id), "quest " .. id .. " is not in the log")
  for i, o in ipairs(q.objectives) do
    self:progressQuest(id, i, o.type == "event" and true or o.need)
  end
end

function Client:failQuest(id)
  local q = assert(self:findQuest(id), "quest " .. id .. " is not in the log")
  q.failed = true
  self:fire("QUEST_LOG_UPDATE")
end

-- Hands the quest in. Gives `xp` experience, which can raise the level.
function Client:turnInQuest(id, xp)
  local _, index = self:findQuest(id)
  assert(index, "quest " .. id .. " is not in the log")
  local lag = self.opts.turnInLag ~= false
  if not lag then table.remove(self.s.quests, index) end
  self.s.completed[id] = true
  self.watched[id] = nil
  self:fire("QUEST_TURNED_IN", id, xp or 0, 0)
  if lag then
    local _, at = self:findQuest(id)
    table.remove(self.s.quests, at)
  end
  self:fire("QUEST_REMOVED", id)
  self:fire("QUEST_LOG_UPDATE")
  self:fire("UNIT_QUEST_LOG_CHANGED", "player")
  if xp and xp > 0 then self:gainXP(xp) end
end

function Client:abandonQuest(id)
  local _, index = self:findQuest(id)
  assert(index, "quest " .. id .. " is not in the log")
  table.remove(self.s.quests, index)
  self.watched[id] = nil
  self:fire("QUEST_REMOVED", id)
  self:fire("QUEST_LOG_UPDATE")
  self:fire("UNIT_QUEST_LOG_CHANGED", "player")
end

-- Marks a quest done on the server without it ever being in the log (done before the addon was installed).
function Client:markCompleted(id)
  self.s.completed[id] = true
end

function Client:collapseHeader(header, collapsed)
  self.s.collapsed[header] = collapsed and true or nil
  self:fire("QUEST_LOG_UPDATE")
end

-- Raises the level. During PLAYER_LEVEL_UP the real UnitLevel still returns the old level.
function Client:setLevel(level)
  assert(level > self.s.level, "levels only go up")
  if self.opts.levelLag ~= false then self.levelShown = self.s.level end
  self.s.level, self.s.xp = level, 0
  self:fire("PLAYER_LEVEL_UP", level, 0, 0, 0, 0, 0, 0, 0, 0)
  self.levelShown = nil
  self:fire("PLAYER_XP_UPDATE", "player")
  if level >= 10 then self:fire("CHARACTER_POINTS_CHANGED", 1) end
end

-- The experience needed to finish a level.
function Client:xpForLevel(level)
  local table_ = self.opts.xpToLevel
  return table_ and table_[level] or level * 400
end

function Client:gainXP(amount)
  local s = self.s
  s.xp = s.xp + amount
  while s.level < 60 and s.xp >= self:xpForLevel(s.level) do
    local left = s.xp - self:xpForLevel(s.level)
    self:setLevel(s.level + 1)
    s.xp = left
  end
  self:fire("PLAYER_XP_UPDATE", "player")
end

-- Moves the player: { zone = areaId, x =, y = } or { uiMap =, x =, y = } in map percent, { subZone = "Brill" },
-- or { hidden = true } for a place without a map position (an instance).
function Client:moveTo(place)
  local s = self.s
  local old = s.pos
  local uiMap = place.uiMap or (place.zone and self:mapForArea(place.zone)) or old.uiMap
  s.pos = { uiMap = uiMap, x = place.x or old.x, y = place.y or old.y, subZone = place.subZone, hidden = place.hidden }
  if uiMap ~= old.uiMap or (place.hidden or false) ~= (old.hidden or false) then
    self:fire("ZONE_CHANGED_NEW_AREA")
    self:fire("ZONE_CHANGED")
  elseif place.subZone ~= old.subZone then
    self:fire("ZONE_CHANGED")
  end
end

-- Turns the character: 0 faces north, a quarter turn to the left (math.pi / 2) faces west.
function Client:face(radians)
  self.s.facing = radians
end

-- Opens the world map on a map (the player's own when none is given), shows another map on it, closes it.
function Client:openWorldMap(uiMap)
  local frame = assert(self.worldMapFrame and rawget(self.G, "WorldMapFrame"), "this client has no world map")
  self:setWorldMap(uiMap or self.s.pos.uiMap)
  setShown(frame, true)
end

function Client:setWorldMap(uiMap)
  assert(self.world.maps[uiMap], "the mock world has no map " .. tostring(uiMap))
  self.worldMapId = uiMap
  if self.opts.mapCanvas == "field" then self.worldMapFrame.mapID = uiMap end
end

function Client:closeWorldMap()
  setShown(self.worldMapFrame, false)
end

-- Drags a frame by (dx, dy) UIParent units with a mouse button, y pointing up: OnDragStart, then the move or the
-- resize of whichever frame OnDragStart started moving (StartMoving) or sizing (StartSizing; a corner grip sizes
-- its parent), then OnDragStop. A clamped frame stops at the screen's edges, as in the game. Returns false when the
-- frame does not take the drag (the mouse passes through it).
function Client:drag(frame, dx, dy, button)
  button = button or "LeftButton"
  assert(visible(frame), "a hidden frame cannot be dragged")
  if not (frame.__mouseClick and frame.__drag and frame.__drag[button]) then return false end
  self.moving = nil
  local start = frame.__scripts.OnDragStart
  if start then self:callAddon(start, frame, button) end
  local target = self.moving
  local W, H = self:uiSize()
  local ui = rawget(self.G, "UIParent")
  if target and target.__moving then
    local left, bottom, width, height = rect(target)
    assert(left, "a frame without an anchor cannot be dragged")
    left, bottom = left + dx, bottom + dy
    if target.__clamped then
      left = math.max(0, math.min(left, W - width))
      bottom = math.max(0, math.min(bottom, H - height))
    end
    local scale = effectiveScale(target)
    target.__allPoints = nil
    target.__points = { { "TOPLEFT", ui, "TOPLEFT", left / scale, (bottom + height - H) / scale } }
  elseif target and target.__sizing then
    local left, bottom, width, height = rect(target)
    assert(left, "a frame without an anchor cannot be resized")
    local scale = effectiveScale(target)
    local top = bottom + height
    local w, h = width, height
    if target.__sizing ~= "BOTTOM" then w = width + dx end
    if target.__sizing ~= "RIGHT" then h = height - dy end
    if target.__clamped then
      w = math.min(w, W - left)
      h = math.min(h, top)
    end
    w, h = w / scale, h / scale
    local bounds = target.__bounds or { 1, 1 }
    w = math.max(w, bounds[1] or 1, 1)
    h = math.max(h, bounds[2] or 1, 1)
    if bounds[3] then w = math.min(w, bounds[3]) end
    if bounds[4] then h = math.min(h, bounds[4]) end
    target.__allPoints = nil
    target.__points = { { "TOPLEFT", ui, "TOPLEFT", left / scale, (top - H) / scale } }
    local oldW, oldH = target.__w, target.__h
    target.__w, target.__h = w, h
    resized(target, oldW, oldH)
  end
  local stop = frame.__scripts.OnDragStop
  if stop then self:callAddon(stop, frame) end
  if target and (target.__moving or target.__sizing) then
    target.__moving, target.__sizing = false, nil
    self.errors[#self.errors + 1] = "the frame was still moving after OnDragStop: StopMovingOrSizing was not called"
  end
  return true
end

-- Every font string and texture of a frame and of the frames inside it, for tests that look at what is drawn.
function Client:regionsOf(frame, into)
  into = into or {}
  for _, region in ipairs(frame.__regions) do into[#into + 1] = region end
  for _, child in ipairs(frame.__children) do self:regionsOf(child, into) end
  return into
end

-- Talks to a flight master. An unknown node is discovered first, as in the game.
function Client:openTaxi(node)
  assert(self.world.taxi[node], "the mock world has no taxi node " .. tostring(node))
  if not self.s.flights[node] then self:discoverFlight(node) end
  self.taxiOpen = { current = node }
  self:fire("TAXIMAP_OPENED", 1)
end

function Client:closeTaxi()
  if self.taxiOpen then
    self.taxiOpen = nil
    self:fire("TAXIMAP_CLOSED")
  end
end

function Client:discoverFlight(node)
  self.s.flights[node] = true
  self:fire("UI_INFO_MESSAGE", 282, self.G.ERR_NEWTAXIPATH)
end

-- Gives the character a flight point without any event (learned before the addon was installed).
function Client:knowFlight(node)
  self.s.flights[node] = true
end

function Client:startFlight(node)
  self.flightTo = node
  self.s.onTaxi = true
  self:closeTaxi()
  self:fire("PLAYER_CONTROL_LOST")
end

function Client:landFlight()
  local node = assert(self.flightTo, "not on a flight")
  self.flightTo = nil
  self.s.onTaxi = false
  local at = self.world.taxi[node].at
  self:moveTo({ uiMap = at.uiMap, x = at.x, y = at.y })
  self:fire("PLAYER_CONTROL_GAINED")
end

-- Binds the hearthstone at an innkeeper where the player stands.
function Client:bindHearth(name)
  self.s.bind = { name = name, pos = deepCopy(self.s.pos) }
  self:fire("HEARTHSTONE_BOUND")
  self:fire("CHAT_MSG_SYSTEM", name .. " is now your home.")
end

function Client:useHearth()
  local pos = assert(self.s.bind.pos, "the mock does not know where the hearthstone is bound")
  self:moveTo({ uiMap = pos.uiMap, x = pos.x, y = pos.y, subZone = self.s.bind.name })
end

-- Learns or raises a profession. kind: "primary" (default), "fishing", "cooking", "firstaid".
function Client:setProfession(skillLine, name, rank, max, kind)
  for _, p in ipairs(self.s.professions) do
    if p.skillLine == skillLine then
      p.rank, p.max = rank, max or p.max
      self:fire("SKILL_LINES_CHANGED")
      return
    end
  end
  table.insert(self.s.professions, { skillLine = skillLine, name = name, rank = rank, max = max or 75, kind = kind or "primary" })
  self:fire("SKILL_LINES_CHANGED")
end

-- The character's talent trees. Without opts.talents they are the addon's own data for the class (a client whose
-- trees are what the data says), with no point spent; without that data, no trees.
function Client:talentTabs()
  if self.s.talents then return self.s.talents end
  local noir = rawget(self.G, "Noir")
  local data = type(noir) == "table" and type(noir.Data) == "table" and type(noir.Data.talents) == "table" and noir.Data.talents[self.s.class]
  if type(data) ~= "table" then return {} end
  local tabs, where = {}, {}
  for i, t in ipairs(data.tabs) do
    tabs[i] = { name = t.name, talents = {} }
    for j, x in ipairs(t.talents) do
      tabs[i].talents[j] = { name = x.name, tier = x.tier, column = x.column, max = x.max, rank = 0, prereqId = x.prereq }
      where[x.id] = { tier = x.tier, column = x.column }
    end
  end
  for _, t in ipairs(tabs) do
    for _, x in ipairs(t.talents) do
      if x.prereqId then x.prereq = where[x.prereqId] end
      x.prereqId = nil
    end
  end
  self.s.talents = tabs
  return tabs
end

-- Replaces the trees (for a test of a client whose trees differ from the data).
function Client:setTalents(tabs)
  self.s.talents = deepCopy(tabs)
end

function Client:talentPointsIn(t)
  local n = 0
  for _, x in ipairs(t.talents) do n = n + (x.rank or 0) end
  return n
end

function Client:unspentTalentPoints()
  local spent = 0
  for _, t in ipairs(self:talentTabs()) do spent = spent + self:talentPointsIn(t) end
  return math.max(0, math.max(0, self.s.level - 9) - spent)
end

function Client:prereqMet(t, x)
  if not x.prereq then return true end
  for _, other in ipairs(t.talents) do
    if other.tier == x.prereq.tier and other.column == x.prereq.column then return (other.rank or 0) >= other.max end
  end
  return false
end

function Client:canLearnTalent(index, talent)
  local t = self:talentTabs()[index]
  local x = t and t.talents[talent]
  if not x then return false end
  return self:unspentTalentPoints() > 0 and (x.rank or 0) < x.max and self:talentPointsIn(t) >= (x.tier - 1) * 5
    and self:prereqMet(t, x)
end

-- The player spends a point in a talent, by tab and talent index or by name. Fails (an assertion) when the game
-- would not let them.
function Client:learnTalent(index, talent)
  if type(index) == "string" then
    for i, t in ipairs(self:talentTabs()) do
      for j, x in ipairs(t.talents) do
        if x.name == index then index, talent = i, j end
      end
    end
  end
  assert(self:canLearnTalent(index, talent), "the game would not let the player learn that talent now")
  local x = self:talentTabs()[index].talents[talent]
  x.rank = (x.rank or 0) + 1
  self:fire("CHARACTER_POINTS_CHANGED", -1)
  self:fire("PLAYER_TALENT_UPDATE")
end

local function isButton(frame) return frame.__type == "Button" or frame.__type == "CheckButton" end

-- Clicks a frame: OnMouseDown, then OnMouseUp, then for an enabled Button PreClick, OnClick and PostClick. A
-- protected button whose OnClick the addon left to the template performs its secure action (see secureAction)
-- between PreClick and PostClick. Returns false when the click does not reach the frame (hidden, or it takes no
-- clicks).
function Client:click(frame, button)
  button = button or "LeftButton"
  if not (visible(frame) and frame.__mouseClick) then return false end
  for _, kind in ipairs({ "OnMouseDown", "OnMouseUp" }) do
    local fn = frame.__scripts[kind]
    if fn then self:callAddon(fn, frame, button) end
  end
  self.lastSecure = nil
  if isButton(frame) and not frame.__disabled then
    local scripts = frame.__scripts
    if scripts.PreClick then self:callAddon(scripts.PreClick, frame, button, false) end
    if scripts.OnClick then
      self:callAddon(scripts.OnClick, frame, button, false)
    elseif frame.__protected then
      self.lastSecure = self:secureAction(frame)
    end
    if scripts.PostClick then self:callAddon(scripts.PostClick, frame, button, false) end
  end
  frame.__lastClick = self.now
  return true
end

-- Two clicks `gap` seconds apart. Within opts.doubleClickTime (0.5 s, the Windows default) the second click runs
-- OnDoubleClick instead of the click scripts when the frame has one.
function Client:doubleClick(frame, gap, button)
  button = button or "LeftButton"
  gap = gap or 0.2
  if not self:click(frame, button) then return false end
  self:advance(gap)
  local fn = frame.__scripts.OnDoubleClick
  if fn and gap <= (self.opts.doubleClickTime or 0.5) and visible(frame) and frame.__mouseClick then
    for _, kind in ipairs({ "OnMouseDown", "OnMouseUp" }) do
      local script = frame.__scripts[kind]
      if script then self:callAddon(script, frame, button) end
    end
    self:callAddon(fn, frame, button)
    return true
  end
  return self:click(frame, button)
end

-- Turns the mouse wheel over a frame (delta 1 up, -1 down). False when it takes no wheel.
function Client:wheel(frame, delta)
  if not (visible(frame) and frame.__wheel) then return false end
  local fn = frame.__scripts.OnMouseWheel
  if fn then self:callAddon(fn, frame, delta) end
  return true
end

-- Puts the cursor at (x, y) in UIParent units from the bottom left corner.
function Client:setCursor(x, y)
  self.cursor = { x = x, y = y }
end

-- The lines of the game's tooltip while it is shown, else {}.
function Client:tooltip()
  local tip = rawget(self.G, "GameTooltip")
  if not (tip and visible(tip)) then return {} end
  local out = {}
  for i, line in ipairs(tip.__lines or {}) do out[i] = line end
  return out
end

-- Holds a modifier key down or lets it go: "CTRL", "SHIFT" or "ALT".
function Client:hold(key, down)
  assert(self.mods[key] ~= nil, "hold: CTRL, SHIFT or ALT")
  down = down and true or false
  if self.mods[key] == down then return end
  self.mods[key] = down
  self:fire("MODIFIER_STATE_CHANGED", "L" .. key, down and 1 or 0)
end

-- Presses a key: the newest shown frame that takes the keyboard gets OnKeyDown, and passes it on to the next only
-- when it propagates keyboard input. Returns whether any frame took it.
function Client:pressKey(key)
  local took = false
  for i = #self.frames, 1, -1 do
    local frame = self.frames[i]
    if frame.__keyboard and visible(frame) then
      took = true
      local fn = frame.__scripts.OnKeyDown
      if fn then self:callAddon(fn, frame, key) end
      if not frame.__propagate then break end
    end
  end
  return took
end

-- Moves the mouse onto a frame (OnEnter) or off it again (`leave` true: OnLeave). Needs mouse motion.
function Client:hover(frame, leave)
  if not (visible(frame) and frame.__mouseMotion) then return false end
  local fn = frame.__scripts[leave and "OnLeave" or "OnEnter"]
  if fn then self:callAddon(fn, frame, true) end
  return true
end

function Client:enterCombat()
  self.s.combat = true
  self:fire("PLAYER_REGEN_DISABLED")
end

function Client:leaveCombat()
  self.s.combat = false
  self:fire("PLAYER_REGEN_ENABLED")
end

-- ---------------------------------------------------------------------------------------------------------------
-- Talking to NPCs. world.npcs[id] says what an NPC has; the client decides which window opens, as the game does:
-- a single gossip option or a single quest is opened directly, anything more shows the gossip (or greeting) list.
-- ---------------------------------------------------------------------------------------------------------------

-- Right-clicks an NPC. `def` overrides the world's definition.
function Client:talkTo(id, def)
  def = def or (self.world.npcs and self.world.npcs[id])
  assert(def, "the mock world has no NPC " .. tostring(id))
  self:closeNpc()
  local available, active, options = {}, {}, {}
  for _, quest in ipairs(def.offers or {}) do
    if self:offerable(quest) then available[#available + 1] = quest end
  end
  for _, quest in ipairs(def.ends or {}) do
    if self:findQuest(quest) then active[#active + 1] = quest end
  end
  if def.taxi then options[#options + 1] = { type = "taxi", text = "I need a ride." } end
  if def.binder then options[#options + 1] = { type = "binder", text = "Make this inn your home." } end
  for _, o in ipairs(def.options or {}) do options[#options + 1] = o end
  self.npc = { id = id, def = def, available = available, active = active, options = options }
  local quests = #available + #active
  if quests == 0 and #options == 0 then
    self.npc = nil
    return
  end
  if not def.alwaysGossip then
    if quests == 0 and #options == 1 then return self:chooseOption(1) end
    if quests == 1 and #options == 0 then
      if #available == 1 then return self:showDetail(available[1]) end
      return self:showActive(active[1])
    end
  end
  if #options == 0 and def.greeting then
    self.npc.window = "greeting"
    self:fire("QUEST_GREETING")
  else
    self.npc.window = "gossip"
    self:fire("GOSSIP_SHOW")
  end
end

-- Whether an NPC that hands out the quest offers it to this character now: true, or false and why not.
-- A quest definition may carry what the game checks: after (one quest before it), pre (all of these turned in),
-- preAny (one of these), exclusive (none of these taken or done), minLevel, maxLevel, closed (a reason the quest
-- is never open to this character, such as another class), locked.
function Client:offerable(quest)
  local s, q = self.s, self.world.quests[quest] or {}
  if self:findQuest(quest) then return false, "quest " .. quest .. " is in the quest log" end
  if s.completed[quest] then return false, "quest " .. quest .. " is done" end
  if q.closed then return false, q.closed end
  if q.locked then return false, "quest " .. quest .. " is locked" end
  if q.after and not s.completed[q.after] then return false, "it needs quest " .. q.after .. " turned in first" end
  for _, id in ipairs(q.pre or {}) do
    if not s.completed[id] then return false, "it needs quest " .. id .. " turned in first" end
  end
  if q.preAny and #q.preAny > 0 then
    local any = false
    for _, id in ipairs(q.preAny) do
      if s.completed[id] then any = true end
    end
    if not any then return false, "it needs one of the quests " .. table.concat(q.preAny, ", ") .. " turned in first" end
  end
  for _, id in ipairs(q.exclusive or {}) do
    if s.completed[id] or self:findQuest(id) then return false, "it is not offered once quest " .. id .. " is taken" end
  end
  if q.minLevel and s.level < q.minLevel then return false, "it needs level " .. q.minLevel .. " and the character is level " .. s.level end
  if q.maxLevel and q.maxLevel > 0 and s.level > q.maxLevel then return false, "it is offered up to level " .. q.maxLevel .. " and the character is level " .. s.level end
  return true
end

-- Closes whatever NPC window is open, firing the client's closing event.
function Client:closeNpc()
  local npc, dialog = self.npc, self.dialog
  self.npc, self.dialog = nil, nil
  local questFrame = rawget(self.G, "QuestFrame")
  if questFrame then setShown(questFrame, false) end
  if dialog or (npc and (npc.window == "greeting" or npc.window == "quest")) then
    self:fire("QUEST_FINISHED")
  elseif npc and npc.window == "gossip" then
    self:fire("GOSSIP_CLOSED")
  end
end

-- The gossip list gives way to another window of the same NPC (a quest page, the flight map): the client's gossip
-- frame hides and its OnHide calls CloseGossip, so GOSSIP_CLOSED fires before the new window's event, as in Classic.
local function gossipGivesWay(c)
  if c.npc and c.npc.window == "gossip" then
    c.npc.window = nil
    c:fire("GOSSIP_CLOSED")
  end
end

function Client:chooseOption(index)
  local npc = assert(self.npc, "not talking to anyone")
  local option = assert(npc.options[index], "no gossip option " .. tostring(index))
  self.gossipChosen = option.type
  if option.type == "taxi" then
    gossipGivesWay(self)
    self.npc = nil
    self:openTaxi(npc.def.taxi)
  elseif option.type == "binder" then
    npc.window = "binder"
    self:fire("CONFIRM_BINDER", npc.def.binder)
  else
    npc.window = option.type
  end
end

function Client:showDetail(quest)
  assert(self.npc, "not talking to anyone")
  gossipGivesWay(self)
  self.npc.window = "quest"
  self.dialog = { kind = "detail", quest = quest }
  setShown(rawget(self.G, "QuestFrame"), true)
  self:fire("QUEST_DETAIL")
end

-- An active quest opens on its progress page while it is unfinished or asks for items, else on the reward page.
function Client:showActive(quest)
  assert(self.npc, "not talking to anyone")
  local q = assert(self:findQuest(quest), "quest " .. quest .. " is not in the log")
  gossipGivesWay(self)
  self.npc.window = "quest"
  setShown(rawget(self.G, "QuestFrame"), true)
  local needsItems = false
  for _, o in ipairs(q.objectives) do
    if o.type == "item" then needsItems = true end
  end
  local ready = #q.objectives == 0 or questComplete(self, q)
  if needsItems or not ready then
    self.dialog = { kind = "progress", quest = quest }
    self:fire("QUEST_PROGRESS")
  else
    self.dialog = { kind = "complete", quest = quest }
    self:fire("QUEST_COMPLETE")
  end
end

-- The calls the addon made to one API function, e.g. c:callsTo("AcceptQuest") -> { { "AcceptQuest", 364 } }.
function Client:callsTo(name)
  local out = {}
  for _, call in ipairs(self.calls) do
    if call[1] == name then out[#out + 1] = call end
  end
  return out
end

-- The times (GetTime) an event fired, oldest first.
function Client:events(name)
  local out = {}
  for i, t in ipairs(self.fired[name] or {}) do out[i] = t end
  return out
end

-- How many slash commands the test typed.
function Client:slashCount()
  return self.slashes
end

-- ---------------------------------------------------------------------------------------------------------------
-- The options window (opts.settingsApi)
-- ---------------------------------------------------------------------------------------------------------------

function Client:optionsOpenedTo()
  return self.optionsOpen
end

function Client:optionsCategories()
  local out = {}
  for i, name in ipairs(self.optionCategories) do out[i] = name end
  return out
end

function Client:closeOptions()
  if self.optionsWindow then setShown(self.optionsWindow, false) end
  self.optionsOpen = nil
end

-- ---------------------------------------------------------------------------------------------------------------
-- Bags, items, spells
-- ---------------------------------------------------------------------------------------------------------------

function Client:itemCount(id)
  local n = 0
  for bag = 0, 4 do
    local b = self.s.bags[bag]
    for slot = 1, b and b.size or 0 do
      local e = b[slot]
      if e and e.id == id then n = n + e.count end
    end
  end
  return n
end

-- Puts `count` of an item into the bags: onto stacks of it first (up to world.stacks[id] or 20 a stack), then into
-- empty slots, bag by bag. What does not fit is lost with the game's message. Fires BAG_UPDATE per bag, then
-- BAG_UPDATE_DELAYED.
function Client:giveItem(id, count)
  count = count or 1
  local max = (self.world.stacks and self.world.stacks[id]) or 20
  local touched = {}
  for pass = 1, 2 do
    for bag = 0, 4 do
      local b = self.s.bags[bag]
      for slot = 1, b.size do
        if count <= 0 then break end
        local e = b[slot]
        if pass == 1 and e and e.id == id and e.count < max then
          local add = math.min(max - e.count, count)
          e.count, count = e.count + add, count - add
          touched[bag] = true
        elseif pass == 2 and not e then
          local add = math.min(max, count)
          b[slot], count = { id = id, count = add }, count - add
          touched[bag] = true
        end
      end
    end
  end
  if count > 0 then self:fire("UI_ERROR_MESSAGE", 3, "Inventory is full.") end
  for bag = 0, 4 do
    if touched[bag] then self:fire("BAG_UPDATE", bag) end
  end
  self:fire("BAG_UPDATE_DELAYED")
end

-- Takes `count` of an item out of the bags, from the last slots first.
function Client:takeItem(id, count)
  count = count or 1
  local touched = {}
  for bag = 4, 0, -1 do
    local b = self.s.bags[bag]
    for slot = b.size, 1, -1 do
      local e = b[slot]
      if count > 0 and e and e.id == id then
        local take = math.min(e.count, count)
        e.count, count = e.count - take, count - take
        if e.count == 0 then b[slot] = nil end
        touched[bag] = true
      end
    end
  end
  for bag = 0, 4 do
    if touched[bag] then self:fire("BAG_UPDATE", bag) end
  end
  self:fire("BAG_UPDATE_DELAYED")
end

function Client:equip(id, on)
  self.s.equipped[id] = (on ~= false) or nil
end

function Client:learnSpell(id)
  self.s.spells[id] = true
  self:fire("LEARNED_SPELL_IN_TAB", id, 1)
  self:fire("SPELLS_CHANGED")
end

-- Casts a spell to its end: UNIT_SPELLCAST_START, then UNIT_SPELLCAST_SUCCEEDED. The Hearthstone (8690) and Astral
-- Recall (556) then take the player to the bound inn when the mock knows where it is.
function Client:castSpell(spell)
  local guid = "Cast-3-4444-0-1-" .. spell .. "-00000A1B2C"
  self:fire("UNIT_SPELLCAST_START", "player", guid, spell)
  self:fire("UNIT_SPELLCAST_SUCCEEDED", "player", guid, spell)
  if (spell == 8690 or spell == 556) and self.s.bind.pos then self:useHearth() end
end

-- Uses an item from the bags: nothing without one or while it cools down; else its cooldown starts and the
-- spell it casts (world.itemSpells) is cast. Returns true when it was used.
function Client:useItem(id)
  if self:itemCount(id) <= 0 then return false end
  local cd = self.itemCooldownsAt[id]
  if cd and self.now < cd[1] + cd[2] then return false end
  self.calls[#self.calls + 1] = { "UseItem", id }
  local duration = self.world.itemCooldowns and self.world.itemCooldowns[id]
  if duration then
    self.itemCooldownsAt[id] = { self.now, duration }
    self:fire("BAG_UPDATE_COOLDOWN")
  end
  local spell = self.world.itemSpells and self.world.itemSpells[id]
  if spell then self:castSpell(spell) end
  return true
end

-- ---------------------------------------------------------------------------------------------------------------
-- Secure buttons
-- ---------------------------------------------------------------------------------------------------------------

-- An NPC is near enough to target (on true) or not; /targetexact finds only NPCs that are near.
function Client:near(npc, on)
  self.nearby[npc] = (on ~= false) or nil
end

-- What a protected button does when clicked, from its attributes: type "item" uses the item ("item:6948", a name or
-- an ID), "spell" casts a known spell, "macro" runs a macrotext of the form "/targetexact <name>". Returns
-- "item <id>", "spell <id>", "target <npc>" or nil when nothing happened.
function Client:secureAction(frame)
  local kind = frame:GetAttribute("type")
  if kind == "item" then
    local value = frame:GetAttribute("item")
    local id = tonumber(tostring(value):match("^item:(%d+)") or value)
    if not id then
      for itemId, name in pairs(self.world.items or {}) do
        if name == value then id = itemId end
      end
    end
    if id and self:useItem(id) then return "item " .. id end
    return nil
  elseif kind == "spell" then
    local value = frame:GetAttribute("spell")
    local id = tonumber(value)
    if not id then
      for spellId, name in pairs(self.world.spells or {}) do
        if name == value then id = spellId end
      end
    end
    if id and self.s.spells[id] then
      self:castSpell(id)
      return "spell " .. id
    end
    return nil
  elseif kind == "macro" then
    local text = frame:GetAttribute("macrotext") or ""
    local name = text:match("^/targetexact (.+)$")
    assert(name, "the mock runs only /targetexact <name> macro texts, got " .. tostring(text))
    for npc in pairs(self.nearby) do
      local def = self.world.npcs[npc]
      if def and def.name == name then
        self.target = npc
        self:fire("PLAYER_TARGET_CHANGED")
        return "target " .. npc
      end
    end
    return nil
  end
  return nil
end

-- Clicks a protected button and returns what its secure action did (see secureAction).
function Client:secureClick(frame, button)
  assert(frame.__protected, "secureClick needs a frame made with a secure template")
  self:click(frame, button or "LeftButton")
  return self.lastSecure
end

-- ---------------------------------------------------------------------------------------------------------------
-- Merchants, trainers, reward pages, shared quests
-- ---------------------------------------------------------------------------------------------------------------

local function talkingTo(self, npc, window)
  self:closeNpc()
  self.npc = { id = npc, def = (self.world.npcs and self.world.npcs[npc]) or {}, window = window, available = {}, active = {}, options = {} }
end

-- Opens a merchant: items = { { item = id, price = copper for `stack` items, stack = 1, count = stock or -1,
-- maxStack, name } }.
function Client:openMerchant(npc, items)
  talkingTo(self, npc, "merchant")
  self.merchant = { npc = npc, items = deepCopy(items or {}) }
  self:fire("MERCHANT_SHOW")
end

function Client:closeMerchant()
  if not self.merchant then return end
  self.merchant = nil
  if self.npc and self.npc.window == "merchant" then self.npc = nil end
  self:fire("MERCHANT_CLOSED")
end

-- Opens a trainer: services = { { name, rank, kind = "available" | "unavailable" | "used", cost, spell, level } };
-- opts.tradeskill for a profession trainer.
function Client:openTrainer(npc, services, opts)
  talkingTo(self, npc, "trainer")
  self.trainer = { npc = npc, services = deepCopy(services or {}), tradeskill = opts and opts.tradeskill == true }
  self:fire("TRAINER_SHOW")
end

function Client:closeTrainer()
  if not self.trainer then return end
  self.trainer = nil
  if self.npc and self.npc.window == "trainer" then self.npc = nil end
  self:fire("TRAINER_CLOSED")
end

-- Opens the reward page of a quest in the log with these choices: { { item = id, count, name, quality, price } }
-- (price: the sell price in copper, which GetItemInfo then reports).
function Client:showReward(quest, choices)
  assert(self:findQuest(quest), "quest " .. quest .. " is not in the log")
  if not self.npc then talkingTo(self, 0, "quest") end
  self.npc.window = "quest"
  setShown(rawget(self.G, "QuestFrame"), true)
  self.dialog = { kind = "complete", quest = quest, choices = deepCopy(choices or {}) }
  for _, choice in ipairs(choices or {}) do
    self.world.items = self.world.items or {}
    self.world.prices = self.world.prices or {}
    if choice.name and not self.world.items[choice.item] then self.world.items[choice.item] = choice.name end
    if choice.price then self.world.prices[choice.item] = choice.price end
  end
  self:fire("QUEST_COMPLETE")
end

-- A party member shares a quest (or an escort starts): QUEST_ACCEPT_CONFIRM with their name and the title.
function Client:shareQuest(quest, from)
  self.pendingShare = quest
  local def = self.world.quests[quest]
  self:fire("QUEST_ACCEPT_CONFIRM", from or "Friend", def and def.title or ("Quest " .. quest))
end

-- ---------------------------------------------------------------------------------------------------------------
-- Death, groups, the game's frames
-- ---------------------------------------------------------------------------------------------------------------

function Client:die()
  local s = self.s
  s.dead, s.corpse = true, deepCopy(s.pos)
  self:fire("PLAYER_DEAD")
end

-- Releases to the graveyard (`place` as for moveTo, or where the player is).
function Client:releaseSpirit(place)
  assert(self.s.dead, "the player is not dead")
  self.s.ghost = true
  self:fire("PLAYER_ALIVE")
  if place then self:moveTo(place) end
end

-- Back to life: at the corpse after releasing (PLAYER_UNGHOST), or a resurrection before releasing (PLAYER_ALIVE).
function Client:resurrect()
  local s = self.s
  local ghost = s.ghost
  s.dead, s.ghost, s.corpse = false, false, nil
  self:fire(ghost and "PLAYER_UNGHOST" or "PLAYER_ALIVE")
end

function Client:joinRaid(on)
  self.s.raid = on and true or false
  self:fire("GROUP_ROSTER_UPDATE")
end

-- Opens the talent frame: the first time the client loads Blizzard_TalentUI, which makes TalentFrame.
function Client:openTalentFrame()
  local frame = rawget(self.G, "TalentFrame")
  if not frame then
    frame = self:gameFrame("Frame", "TalentFrame", rawget(self.G, "UIParent"))
    frame.__shown, frame.__w, frame.__h = false, 384, 512
    frame.__points = { { "TOPLEFT", rawget(self.G, "UIParent"), "TOPLEFT", 0, -104 } }
    frame.__guarded = "the talent frame"
    self:fire("ADDON_LOADED", "Blizzard_TalentUI")
  end
  setShown(frame, true)
end

-- Switches the active talent group (dual talents, api = "modern" only) and fires the client's event for it.
function Client:setTalentGroup(group)
  local before = self.s.talentGroup or 1
  self.s.talentGroup = group
  self:fire("ACTIVE_TALENT_GROUP_CHANGED", group, before)
end

function Client:closeTalentFrame()
  local frame = rawget(self.G, "TalentFrame")
  if frame then setShown(frame, false) end
end

function Client:openQuestLog() setShown(rawget(self.G, "QuestLogFrame"), true) end
function Client:closeQuestLog() setShown(rawget(self.G, "QuestLogFrame"), false) end

Client.RACES, Client.CLASSES = RACES, CLASSES
HARNESS.Client = Client
