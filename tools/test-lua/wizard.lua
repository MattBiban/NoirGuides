-- Noir Guides, GPLv3. See LICENSE.
-- The setup wizard (plan task E7, spec 2.3, 6.1): it opens by itself for a new character, asks the route
-- questions, lists the sections for the character's level with the recommended one first, and loads the one chosen.
-- Driven by game events and the mouse only; every test ends with nothing off the screen.
use("tools/test-lua/sample/helper.lua")

local DEATHKNELL = "undead-01-03-deathknell"
local TIRISFAL = "undead-03-05-tirisfal-glades"
local GUID = "Player-4444-0000002A"
local KEY = "Tester-Mock"

local function savedWith(guide)
  return { account = {}, characters = { [KEY] = { NoirGuidesCharDB = { schema = 2, owner = GUID, guide = guide } } } }
end

-- A fresh character, nothing saved. opts: level, class, zone, saved, afterLoad.
local function fresh(opts)
  opts = opts or {}
  local c = sample3({ class = opts.class or "MAGE", level = opts.level or 1, zone = opts.zone, saved = opts.saved,
    afterLoad = opts.afterLoad })
  c:login()
  return c, c.G.Noir, c.G.Noir.Wizard
end

local function sectionIds(Z)
  local out = {}
  for i, s in ipairs(Z.Read().sections) do out[i] = s.id end
  return out
end

local function question(Z, key)
  for _, q in ipairs(Z.Read().questions) do
    if q.key == key then return q end
  end
  error("no question " .. key, 2)
end

test("a new level 1 character sees the wizard 2 s after entering the world, without a command", function()
  local c, Noir, Z = fresh()
  eq(Noir.Guide.Current(), DEATHKNELL, "the recommendation is loaded at once")
  c:advance(1.9)
  eq(Z.Read().shown, false, "not before 2 s")
  c:advance(0.2)
  eq(Z.Read().shown, true, "2 s after entering the world")
  eq(Z.Read().page, 1)
  local left, bottom, right, top = c:rectOf(Z.frame)
  local W, H = c.G.GetScreenWidth(), c.G.GetScreenHeight()
  ok((left + right) / 2 > W / 2 and (bottom + top) / 2 > H / 2, "upper right of the centre")
  eq(c:slashCount(), 0)
  eq(c:offScreen(), {})
end)

test("a level 5 character does not", function()
  local c, _, Z = fresh({ level = 5 })
  c:advance(5)
  eq(Z.Read().shown, false)
  -- Nor a level 1 character that closed it before.
  local c2, _, Z2 = fresh({ saved = savedWith({ section = DEATHKNELL, how = "auto", wizard = true }) })
  c2:advance(5)
  eq(Z2.Read().shown, false)
  eq(c:offScreen(), {})
end)

test("Finish loads the chosen section", function()
  local c, Noir, Z = fresh({ level = 3 })
  c:advance(3)
  eq(Noir.Guide.Current(), TIRISFAL, "chosen by itself from the zone")
  eq(Z.Read().shown, false)
  c:setCursor(300, 400)
  c:click(Noir.Window.Header(), "RightButton")
  c:click(Noir.Menu.Row(1, 9))
  eq(Z.Read().shown, true, "opened from the menu")
  ok(c:click(Z.Button("route")), "the open world route card")
  eq(Z.Read().page, 2)
  ok(c:click(Z.Button("next")))
  eq(Z.Read().page, 3)
  eq(sectionIds(Z), { TIRISFAL, DEATHKNELL })
  ok(c:click(Z.SectionRow(DEATHKNELL)), "a section row takes the click")
  eq(Z.Read().sections[2].chosen, true)
  ok(c:click(Z.Button("finish")))
  eq(Noir.Guide.Current(), DEATHKNELL, "the chosen section is loaded")
  eq(Noir.char.guide.how, "wizard")
  eq(Noir.char.guide.wizard, true)
  eq(Z.Read().shown, false, "and the wizard closes")
  -- Back goes a page back.
  Z.Open()
  c:click(Z.Button("route"))
  c:click(Z.Button("back"))
  eq(Z.Read().page, 1)
  eq(c:offScreen(), {})
end)

test("closing keeps the recommended section loaded", function()
  local c, Noir, Z = fresh()
  c:advance(2.1)
  ok(Z.Read().shown)
  ok(c:click(Z.Button("close")))
  eq(Z.Read().shown, false)
  eq(Noir.Guide.Current(), DEATHKNELL)
  eq(Noir.char.guide.wizard, true)
  local again = c:relog()
  again:advance(5)
  eq(again.G.Noir.Wizard.Read().shown, false, "not again after a relog")
  eq(again.G.Noir.Guide.Current(), DEATHKNELL)
  eq(again:offScreen(), {})
end)

test("the section list holds only sections for the character's level, the recommended first", function()
  local c, Noir, Z = fresh({ level = 4, saved = savedWith({ section = TIRISFAL, how = "hand", wizard = true }) })
  c:advance(0.5)
  Z.Open()
  local sections = Z.Read().sections
  eq(sectionIds(Z), { TIRISFAL, DEATHKNELL }, "Silverpine (5-8) is not for level 4")
  eq(sections[1].recommended, true, "the recommended one first and marked")
  eq(sections[2].recommended, false)
  eq(sections[1].chosen, true, "and chosen until another is")
  local c1, _, Z1 = fresh()
  c1:advance(2.1)
  eq(sectionIds(Z1), { DEATHKNELL }, "level 1: Deathknell only")
  -- Sections for other races and classes, with the setting on.
  Noir.Options.Set("otherSections", true)
  eq(sectionIds(Z), { TIRISFAL, DEATHKNELL, "human-01-05-northshire" })
  eq(c:offScreen(), {})
  -- The level rule wins over the loaded section: a level 7 character with Deathknell (1-4) loaded by hand, opening
  -- the wizard from the menu, sees only Silverpine (5-8), recommended in place of the loaded section.
  local c7, Noir7, Z7 = fresh({ level = 7, saved = savedWith({ section = DEATHKNELL, how = "hand", wizard = true }) })
  c7:advance(0.5)
  eq(Noir7.Guide.Current(), DEATHKNELL)
  Z7.Open()
  eq(sectionIds(Z7), { "undead-05-06-silverpine-forest" }, "Deathknell is not for level 7")
  eq(Z7.Read().sections[1].recommended, true, "the first section of the level is recommended")
  eq(Z7.Read().sections[1].chosen, true)
  -- No section for the level at all (level 20, the sample ends at 8): the loaded one stays, alone and marked, so
  -- Finish never has nothing to load.
  local c20, _, Z20 = fresh({ level = 20, saved = savedWith({ section = DEATHKNELL, how = "hand", wizard = true }) })
  c20:advance(0.5)
  Z20.Open()
  eq(sectionIds(Z20), { DEATHKNELL }, "nothing holds level 20: the loaded section only")
  eq(Z20.Read().sections[1].recommended, true)
  eq(c7:offScreen(), {})
  eq(c20:offScreen(), {})
end)

test("each question changes its setting", function()
  local c, Noir, Z = fresh({ afterLoad = function(client)
    client.G.Noir.Data.professions = { [171] = { name = "Alchemy", kind = "primary" }, [186] = { name = "Mining", kind = "primary" } }
  end })
  c:advance(2.1)
  c:click(Z.Button("route"))
  local recommended = {}
  for _, q in ipairs(Z.Read().questions) do recommended[q.key] = q.recommended end
  eq(recommended, { auctionHouse = true, groupQuests = false, outlevel = true, profession = false, otherSections = false })
  ok(c:click(Z.Toggle("auctionHouse")))
  eq(Noir.char.guide.setup.auctionHouse, false)
  eq(question(Z, "auctionHouse").on, false)
  c:click(Z.Toggle("groupQuests"))
  eq(Noir.Options.Get("groupQuests"), true)
  eq(Noir.char.guide.setup.groupQuests, true)
  c:click(Z.Toggle("outlevel"))
  eq(Noir.Options.Get("outlevel"), false)
  c:click(Z.Toggle("otherSections"))
  eq(Noir.Options.Get("otherSections"), true)
  -- Level a profession opens the profession choice.
  c:setCursor(500, 500)
  c:click(Z.Toggle("profession"))
  ok(Noir.Menu.IsOpen(), "the profession choice opens at the cursor")
  local names = {}
  for i, r in ipairs(Noir.Menu.Read().levels[1].rows) do names[i] = r.text end
  eq(names, { "Alchemy", "Mining" })
  c:click(Noir.Menu.Row(1, 2))
  eq(Noir.Professions.IsPlanned(186), true, "Mining is planned")
  eq(question(Z, "profession").on, true)
  Noir.Menu.Close()
  -- Reset puts the questions back at their recommended answers.
  ok(c:click(Z.Button("reset")))
  eq(Noir.char.guide.setup.auctionHouse, true)
  eq(Noir.Options.Get("groupQuests"), false)
  eq(Noir.Options.Get("outlevel"), true)
  eq(Noir.Options.Get("otherSections"), false)
  eq(c:slashCount(), 0)
  eq(c:offScreen(), {})
end)

test("the wizard opens from the menu any time", function()
  local c, Noir, Z = fresh({ level = 10 })
  c:advance(3)
  eq(Z.Read().shown, false)
  c:setCursor(300, 400)
  c:click(Noir.Window.Header(), "RightButton")
  local rows = Noir.Menu.Read().levels[1].rows
  local index
  for i, r in ipairs(rows) do if r.text == "Setup wizard" then index = i end end
  c:click(Noir.Menu.Row(1, index))
  eq(Z.Read().shown, true)
  no(Noir.Menu.IsOpen(), "the menu closes")
  eq(c:offScreen(), {})
end)
