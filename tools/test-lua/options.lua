-- Noir Guides, GPLv3. See LICENSE.
-- Options: the player's settings in account-wide profiles, with the window places kept per profile, and the
-- migration of the 0.1.x saved variables (schema 1) to schema 2 (plan task E1, spec 6.1).
use("tools/test-lua/sample/helper.lua")

-- Every key and default of spec 6.1 as the plan names them.
local EXPECTED = {
  shown = true, locked = false, hideInRaid = false, minimap = true, minimapAngle = 225, windowHidden = false,
  cardsBelow = false, windowScale = 1, fontSize = "standard", stepList = true, hideFinished = false,
  otherSections = false, highlight = true, itemButtons = true, buttonBackground = true, buttonScale = 1, arrow = true,
  arrowScale = 1, arrowText = 12, minimapPins = true, pinRing = false, worldPins = 8, pinSize = 1, pinMerge = 1,
  pinAlpha = 0.6, autoQuests = true, guideRewards = false, rewardMarker = true, bestReward = false, train = false,
  flights = true, hearth = true, dialogue = true, buy = true, sellJunk = true, targetButtons = true, nameplates = true, markers = true,
  outlevel = true, groupQuests = false, talents = true, neverSkip = false, offerCleanup = true, conflicts = true,
  debug = false, accent = "class", backgroundAlpha = 0.75,
}

local function options(opts)
  local c = sample(opts):login()
  return c, c.G.Noir.Options
end

test("defaults come from DEFAULTS", function()
  local c, Options = options()
  eq(Options.DEFAULTS, EXPECTED)
  for key, value in pairs(EXPECTED) do eq(Options.Get(key), value, key) end
  eq(c.G.Noir.db.profiles, { Default = {} }, "defaults are not written into the profile")
  eq(Options.Get("noSuchKey"), nil)
end)

test("options read the defaults before the saved variables are ready", function()
  local c = sample()
  c:loadAddon()
  eq(c.G.Noir.Options.Get("worldPins"), 8)
  eq({ c.G.Noir.Options.Set("worldPins", 3) }, { false, "the settings are not loaded yet" })
end)

test("Set refuses a value out of range and fires NOIR_OPTION for a good one", function()
  local c, Options = options()
  local fired = {}
  c.G.Noir.On("NOIR_OPTION", function(_, key, value) fired[#fired + 1] = key .. "=" .. tostring(value) end)
  local good, why = Options.Set("worldPins", 21)
  eq(good, false)
  has(why, "0")
  has(why, "20")
  eq({ Options.Set("worldPins", 2.5) }, { false, "worldPins takes a whole number from 0 to 20" })
  eq(Options.Set("windowScale", 0.1), false)
  eq(Options.Set("pinAlpha", -0.1), false)
  eq(Options.Set("locked", "yes"), false, "a switch takes true or false")
  eq(Options.Set("fontSize", "huge"), false)
  eq(Options.Set("noSuchKey", true), false)
  eq(Options.Set("worldPins", 0 / 0), false, "not a number")
  eq(fired, {}, "nothing fired for a refused value")
  eq(Options.Get("worldPins"), 8)
  eq(Options.Set("worldPins", 20), true)
  eq(Options.Set("fontSize", "large"), true)
  eq(Options.Set("locked", true), true)
  eq(Options.Set("windowScale", 0.2), true)
  eq(fired, { "worldPins=20", "fontSize=large", "locked=true", "windowScale=0.2" })
  eq({ Options.Get("worldPins"), Options.Get("fontSize"), Options.Get("locked") }, { 20, "large", true })
  eq(Options.RANGES.worldPins.max, 20)
  local again = c:relog()
  eq(again.G.Noir.Options.Get("worldPins"), 20, "kept over a relog")
end)

test("schema 1 options become the Default profile with the renamed automation keys", function()
  local saved = { account = { NoirGuidesDB = { schema = 1, options = {
    auto = { accept = false, turnin = true, flight = false, hearth = true, gossip = false },
    window = { x = 100, y = 600, scale = 1.5, locked = true, hidden = true },
    arrow = { x = 400, y = 700, off = true },
  } } }, characters = {} }
  local c, Options = options({ saved = saved })
  local db = c.G.Noir.db
  eq(db.schema, 2)
  eq(db.options, nil, "the old table is gone")
  eq(db.defaultProfile, "Default")
  eq(Options.Profile(), "Default")
  eq({ Options.Get("autoQuests"), Options.Get("flights"), Options.Get("hearth"), Options.Get("dialogue") }, { false, false, true, false })
  eq({ Options.Get("windowScale"), Options.Get("locked"), Options.Get("windowHidden"), Options.Get("arrow") }, { 1.5, true, true, false })
  eq(Options.Position("window"), { "TOPLEFT", "BOTTOMLEFT", 100, 600 })
  eq(Options.Position("arrow"), { "TOPLEFT", "BOTTOMLEFT", 400, 700 })
  eq(#c.G.Noir.problems, 0, "a migration is not a problem")
  -- Unusable old values are dropped, not carried over.
  local odd = { account = { NoirGuidesDB = { schema = 1, options = { auto = { accept = "x" }, window = { x = "a", scale = 9 } } } }, characters = {} }
  local d, Odd = options({ saved = odd })
  eq({ Odd.Get("autoQuests"), Odd.Get("windowScale"), Odd.Position("window") }, { true, 1, nil })
  eq(d.G.Noir.db.profiles.Default, {})
end)

test("schema 1 progress is dropped with one why entry", function()
  local saved = { account = {}, characters = { ["Tester-Mock"] = { NoirGuidesCharDB = {
    schema = 1, progress = { ["horde-undead"] = { n = 5 } }, why = { { kind = "done", text = "an old entry" } },
    professions = { planned = { 186 } }, talents = { said = 3 },
  } } } }
  local c = sample({ saved = saved }):login()
  local char = c.G.Noir.char
  eq(char.schema, 2)
  eq(char.progress, nil)
  eq(char.professions.planned, { 186 }, "the rest of the character's data is kept")
  eq(char.talents.said, 3)
  local why = c.G.Noir.Why.List()
  eq(#why, 2)
  eq(why[1].text, "an old entry")
  eq(why[2].kind, "route")
  has(why[2].text, "sections")
  local again = c:relog()
  eq(#again.G.Noir.Why.List(), 2, "migrated once")
end)

test("profiles: new, copy, use, delete, reset, default for new characters", function()
  local c, Options = options({ name = "Anna" })
  local profiles = {}
  c.G.Noir.On("NOIR_PROFILE", function(_, name) profiles[#profiles + 1] = name end)
  Options.Set("worldPins", 3)
  eq(Options.NewProfile("Raid"), true)
  eq({ Options.NewProfile("Raid") }, { false, "there is already a profile named Raid" })
  eq(Options.NewProfile(""), false)
  eq(Options.NewProfile("Copy", "Default"), true)
  eq(Options.NewProfile("Ghost", "Nobody"), false, "copying from a profile that does not exist")
  eq(Options.Profiles(), { "Copy", "Default", "Raid" })
  eq(Options.UseProfile("Raid"), true)
  eq({ Options.Profile(), Options.Get("worldPins") }, { "Raid", 8 })
  eq(Options.UseProfile("Copy"), true)
  eq(Options.Get("worldPins"), 3, "a copy carries the values")
  Options.Set("worldPins", 9)
  eq(Options.UseProfile("Nobody"), false)
  eq(profiles, { "Raid", "Copy" })
  eq(Options.DeleteProfile("Copy"), false, "never the profile in use")
  eq(Options.DeleteProfile("Raid"), true)
  eq(Options.Profiles(), { "Copy", "Default" })
  eq(Options.ResetProfile(), true)
  eq(Options.Get("worldPins"), 8)
  eq(profiles[#profiles], "Copy", "a reset tells the windows to take their places again")
  eq(Options.UseProfile("Default"), true)
  eq(Options.DeleteProfile("Copy"), true)
  eq(Options.DeleteProfile("Default"), false, "never the last profile")
  -- The default for new characters
  Options.NewProfile("Leveling")
  eq(Options.SetDefaultProfile("Leveling"), true)
  eq(Options.SetDefaultProfile("Nobody"), false)
  local saved = c:logout()
  local bert = sample({ name = "Bert", saved = saved }):login()
  eq(bert.G.Noir.Options.Profile(), "Leveling")
  eq(bert.G.Noir.char.profile, "Leveling")
  local anna = sample({ name = "Anna", saved = bert:logout() }):login()
  eq(anna.G.Noir.Options.Profile(), "Default", "an existing character keeps its profile")
end)

test("positions are kept per profile", function()
  local c, Options = options()
  eq(Options.Position("window"), nil)
  Options.SavePosition("window", { "TOPLEFT", "BOTTOMLEFT", 30, 500, 320, 400 })
  eq(Options.Position("window"), { "TOPLEFT", "BOTTOMLEFT", 30, 500, 320, 400 })
  local copy = Options.Position("window")
  copy[3] = 999
  eq(Options.Position("window")[3], 30, "Position gives a copy")
  eq(Options.SavePosition("window", { "TOPLEFT", "NOWHERE", 1, 2 }), false)
  eq(Options.SavePosition("window", { "TOPLEFT", "BOTTOMLEFT", "a", 2 }), false)
  Options.NewProfile("Other")
  Options.UseProfile("Other")
  eq(Options.Position("window"), nil)
  Options.SavePosition("window", { "CENTER", "CENTER", 0, 0 })
  Options.UseProfile("Default")
  eq(Options.Position("window"), { "TOPLEFT", "BOTTOMLEFT", 30, 500, 320, 400 })
  Options.SavePosition("window", nil)
  eq(Options.Position("window"), nil)
  local again = c:relog()
  again.G.Noir.Options.UseProfile("Other")
  eq(again.G.Noir.Options.Position("window"), { "CENTER", "CENTER", 0, 0 })
end)
