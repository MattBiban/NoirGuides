-- Noir Guides, GPLv3. See LICENSE.
-- Talents.lua (spec 5.11, gap #37): the class's leveling build from Data/Talents.lua, checked against the client's
-- own talent trees, and the next points to spend. Chat reminders come 5 s after login and 1.5 s after a level-up or
-- a talent group change; in the game's talent window the addon's own frames above it show a build picker, the next
-- point and a pulsing ring on the next talent. The addon only says what to learn; spending a point is the player's
-- (the mock treats LearnTalent from the addon as a forbidden call), and the game's frames are never changed (the
-- mock records any change to the talent frame as a forbidden call).
use("tools/test-lua/sample/ports.lua")

local LOGIN_SECONDS, LEVEL_SECONDS = 5, 1.5

local function start(opts)
  opts = opts or {}
  opts.race, opts.class = opts.race or "Undead", opts.class or "ROGUE"
  local c = ported(opts):login()
  c:advance(LOGIN_SECONDS + 0.1)
  return c, c.G.Noir.Talents, c.G.Noir
end

local function first(T)
  local pick = T.Plan(1)[1]
  if not pick then return nil end
  return { pick.name, pick.tree, pick.rank, pick.max, pick.learnable }
end

test("a rogue below level 10 has no point to spend and is told nothing", function()
  local c, T = start({ level = 9 })
  eq(T.Unspent(), 0)
  eq(first(T), { "Efficient Strikes", "Combat", 1, 2, false })
  no(c:chatText():find("Talent point", 1, true), "no talent message")
  no(c:chatText():find("talent build", 1, true), "not asked to choose before level 10")
end)

test("the reminder comes 5 s after login and 1.5 s after a level-up", function()
  local c = ported({ race = "Undead", class = "ROGUE", level = 12 }):login()
  c:advance(LOGIN_SECONDS - 0.2)
  no(c:chatText():find("Talent point", 1, true), "not before 5 s")
  c:advance(0.3)
  has(c:chatText(), "Talent point: Efficient Strikes 1/2 (Combat)")
  has(c:chatText(), "3 points ready")
  c:learnTalent("Efficient Strikes")
  c:learnTalent("Efficient Strikes")
  c:learnTalent("Lightning Reflexes")
  c:takeChat()
  c:setLevel(13)
  c:advance(LEVEL_SECONDS - 0.2)
  no(c:chatText():find("Talent point", 1, true), "not before 1.5 s")
  c:advance(0.3)
  has(c:chatText(), "Talent point: Lightning Reflexes 2/5 (Combat)")
  has(c:chatText(), "1 point ready")
  eq(c:offScreen(), {})
end)

test("at level 10 the rogue is asked once to choose a build and told the first pick", function()
  local c, T = start({ level = 9 })
  c:takeChat()
  c:setLevel(10)
  c:advance(LEVEL_SECONDS + 0.1)
  eq(T.Unspent(), 1)
  eq(first(T), { "Efficient Strikes", "Combat", 1, 2, true })
  local text = c:chatText()
  has(text, "Talent point: Efficient Strikes 1/2 (Combat)")
  has(text, "Choose a talent build")
  c:takeChat()
  local again = c:relog()
  again:advance(LOGIN_SECONDS + 0.1)
  no(again:chatText():find("Choose a talent build", 1, true), "asked once, kept over a relog")
end)

test("each point the player learns brings the next pick of the build", function()
  local c, T = start({ level = 9 })
  c:setLevel(10)
  c:advance(LEVEL_SECONDS + 0.1)
  c:learnTalent("Efficient Strikes")
  eq(T.Unspent(), 0)
  eq(first(T), { "Efficient Strikes", "Combat", 2, 2, false })
  c:takeChat()
  c:setLevel(11)
  c:advance(LEVEL_SECONDS + 0.1)
  has(c:chatText(), "Talent point: Efficient Strikes 2/2 (Combat)")
  c:learnTalent("Efficient Strikes")
  c:setLevel(12)
  eq(first(T), { "Lightning Reflexes", "Combat", 1, 5, true })
end)

test("the message for a point is said once, not again at every event", function()
  local c = start({ level = 9 })
  c:setLevel(10)
  c:advance(LEVEL_SECONDS + 0.1)
  c:takeChat()
  c:fire("CHARACTER_POINTS_CHANGED", 0)
  c:fire("PLAYER_TALENT_UPDATE")
  c:advance(LEVEL_SECONDS + 0.1)
  no(c:chatText():find("Talent point", 1, true), "said again")
end)

-- The race each class can be in the mock, for a client of every class.
local RACE = { WARRIOR = "Orc", PALADIN = "Human", HUNTER = "Orc", ROGUE = "Orc", PRIEST = "Human", SHAMAN = "Orc",
  MAGE = "Human", WARLOCK = "Orc", DRUID = "NightElf" }

test("every class's build can be learned in the game point by point, from level 10 to 60", function()
  for class, race in pairs(RACE) do
    local c, T, Noir = start({ race = race, class = class, level = 9, zone = race == "Human" and 12 or 14 })
    ok(T.Check(), class .. " build fits the client's trees")
    eq(T.Spec(), Noir.Data.talents[class].spec, class)
    for level = 10, 60 do
      c:setLevel(level)
      local pick = T.Plan(1)[1]
      ok(pick and pick.learnable, class .. " level " .. level .. " has a learnable pick")
      c:learnTalent(pick.tab, pick.index) -- the mock refuses what the game would refuse
    end
    eq(T.Unspent(), 0, class)
    eq(T.Plan(5), {}, class .. ": nothing left to learn")
    eq(T.Off(), {}, class)
  end
end)

test("talents the player spent off the build are listed, the player is warned once, and the plan still follows the build", function()
  local c, T = start({ level = 9 })
  c:setLevel(10)
  c:learnTalent("Master of Deception")
  eq(T.Off(), { { name = "Master of Deception", tree = "Subtlety", rank = 1 } })
  c:takeChat()
  c:setLevel(11)
  c:advance(LEVEL_SECONDS + 0.1)
  eq(first(T), { "Efficient Strikes", "Combat", 1, 2, true })
  has(c:chatText(), "not in your build: Master of Deception 1 (Subtlety)")
  c:takeChat()
  c:setLevel(12)
  c:advance(LEVEL_SECONDS + 0.1)
  no(c:chatText():find("not in your build", 1, true), "warned once")
  c:slash("/noir talents")
  has(c:chatText(), "Master of Deception")
  has(c:chatText(), "not in the build")
end)

test("a pick the game does not allow yet is shown as not learnable, with the reason", function()
  -- Five points away from Combat: Precision would be the next pick, but tier 2 of Combat needs 5 points there.
  local c, T = start({ level = 9 })
  for level = 10, 14 do
    c:setLevel(level)
    c:learnTalent("Master of Deception")
  end
  c:setLevel(15)
  local pick = T.Plan(1)[1]
  eq({ pick.name, pick.learnable }, { "Efficient Strikes", true })
  local later = T.Plan(3)[3]
  eq(later.name, "Lightning Reflexes")
  local all = T.Plan(6)
  eq(all[6].name, "Precision")
  no(all[6].learnable)
  has(all[6].why, "5 points in Combat")
end)

test("a client whose trees differ from the data gets no suggestions and a problem that says why", function()
  local c0 = ported({ race = "Undead", class = "ROGUE" })
  c0:loadAddon()
  local tabs = c0:talentTabs()
  -- Forever changes talents between patches: here Efficient Strikes has three ranks instead of two.
  for _, t in ipairs(tabs[2].talents) do
    if t.name == "Efficient Strikes" then t.max = 3 end
  end
  local c = ported({ race = "Undead", class = "ROGUE", level = 20, talents = tabs }):login()
  local T, Noir = c.G.Noir.Talents, c.G.Noir
  no(T.Check())
  eq(T.Plan(3), {})
  has(table.concat(Noir.problems, "\n"), "talent build")
  has(table.concat(Noir.problems, "\n"), "Efficient Strikes")
  c:takeChat()
  c:slash("/noir talents")
  has(c:chatText(), "does not fit")
end)

test("a client without talent functions raises no error, and /noir talents says so", function()
  local c, T = start({ level = 20, talentApi = "none" })
  eq(T.Plan(3), {})
  c:openTalentFrame()
  c:takeChat()
  c:slash("/noir talents")
  has(c:chatText(), "cannot read")
end)

test("without talent data for the class, nothing is suggested and nothing breaks", function()
  local c = sample({ race = "Undead", class = "ROGUE", level = 20 }):login()
  c:advance(LOGIN_SECONDS + 0.1)
  local T = c.G.Noir.Talents
  eq(T.Plan(3), {})
  eq(T.Builds(), {})
  c:openTalentFrame()
  c:slash("/noir talents")
  has(c:chatText(), "no talent build")
end)

test("/noir talents lists the next picks", function()
  local c = start({ level = 12 })
  c:takeChat()
  c:slash("/noir talents")
  local text = c:chatText()
  has(text, "Combat build")
  has(text, "3 points to spend")
  has(text, "Efficient Strikes 1/2 (Combat)")
  has(text, "Lightning Reflexes 1/5 (Combat)")
end)

test("with talent guides off there is no reminder and nothing in the talent window", function()
  local c = ported({ race = "Undead", class = "ROGUE", level = 12 }):login()
  c.G.Noir.Options.Set("talents", false)
  c:advance(LOGIN_SECONDS + 0.1)
  no(c:chatText():find("Talent point", 1, true), "no reminder")
  c:openTalentFrame()
  no(c.G.Noir.Talents.Read().shown, "nothing above the talent window")
end)

-- ---------------------------------------------------------------------------------------------------------------
-- The talent window
-- ---------------------------------------------------------------------------------------------------------------

-- The client's talent buttons of the shown tab, as Blizzard_TalentUI makes them: TalentFrameTalent<index>, placed
-- on the tree's grid. The test plays the client here; the addon only reads them.
local function talentButtons(c, tab)
  local frame = c.G.TalentFrame
  frame.selectedTab = tab
  for index, t in ipairs(c:talentTabs()[tab].talents) do
    local name = "TalentFrameTalent" .. index
    local button = rawget(c.G, name) or c:gameFrame("Button", name, frame)
    button.__w, button.__h = 32, 32
    button.__points = { { "TOPLEFT", frame, "TOPLEFT", 35 + (t.column - 1) * 63, -(20 + (t.tier - 1) * 63) - 60 } }
  end
end

local function center(c, frame)
  local l, b, r, t = c:rectOf(frame)
  return (l + r) / 2, (b + t) / 2
end

test("the build picker and next-point line appear above the talent window", function()
  local c, T, Noir = start({ level = 12 })
  no(T.Read().shown, "nothing before the talent window opens")
  c:openTalentFrame()
  local view = T.Read()
  ok(view.shown, "shown with the talent window")
  has(view.build, "Combat")
  has(view.info, "Efficient Strikes 1/2 (Combat)")
  has(view.info, "3 points")
  -- Above the window: the holder's bottom is at or above the talent window's top.
  local _, _, _, frameTop = c:rectOf(c.G.TalentFrame)
  local _, holderBottom = c:rectOf(T.Frame())
  ok(holderBottom >= frameTop - 0.5, "above the talent window")
  -- The picker opens the addon's menu with the class's builds; picking one chooses it.
  ok(c:click(T.PickerFrame()), "the picker takes the click")
  ok(Noir.Menu.IsOpen(), "the build menu opens")
  local rows = Noir.Menu.Read().levels[1].rows
  eq(rows[1].text, "Combat")
  ok(rows[1].checked, "the build followed is ticked")
  c:click(Noir.Menu.Row(1, 1))
  eq(T.Chosen(), "combat")
  -- Learning a point updates the line; closing the window hides the addon's frames with it.
  c:learnTalent("Efficient Strikes")
  has(T.Read().info, "Efficient Strikes 2/2 (Combat)")
  c:closeTalentFrame()
  no(T.Read().shown, "hidden with the talent window")
  eq(c:offScreen(), {})
end)

test("the ring sits on the next talent and the game's frames are not changed", function()
  local c, T = start({ level = 12 })
  c:openTalentFrame()
  talentButtons(c, 2)
  c:fire("PLAYER_TALENT_UPDATE")
  local pick = T.Plan(1)[1]
  local ring = T.RingFrame()
  ok(T.Read().ring, "the ring is shown on the Combat tab")
  local rx, ry = center(c, ring)
  local bx, by = center(c, c.G["TalentFrameTalent" .. pick.index])
  near(rx, bx, 0.5, "the ring is on the button across")
  near(ry, by, 0.5, "the ring is on the button up and down")
  -- It pulses between 0.4 and 1 over 1.2 s.
  local least, most = 1, 0
  for _ = 1, 24 do
    c:advance(0.05, 0.05)
    local alpha = ring:GetAlpha()
    if alpha < least then least = alpha end
    if alpha > most then most = alpha end
  end
  ok(least >= 0.4 - 1e-6 and most <= 1 + 1e-6, "between 0.4 and 1")
  ok(least < 0.45 and most > 0.95, "the whole range in one 1.2 s period")
  -- Learning the point moves the ring to the next pick's button.
  c:learnTalent("Efficient Strikes")
  c:learnTalent("Efficient Strikes")
  local nextPick = T.Plan(1)[1]
  eq(nextPick.name, "Lightning Reflexes")
  rx, ry = center(c, ring)
  bx, by = center(c, c.G["TalentFrameTalent" .. nextPick.index])
  near(rx, bx, 0.5)
  near(ry, by, 0.5)
  -- Another tab shown: the ring hides, and the line says which tab to open.
  talentButtons(c, 1)
  c:fire("PLAYER_TALENT_UPDATE")
  no(T.Read().ring, "no ring on another tab")
  has(T.Read().info, "Combat tab")
  eq(c:callsTo("LearnTalent"), {}, "no point is spent by the addon")
  eq(c:offScreen(), {})
end)

test("the choice is kept per talent group", function()
  local c, T = start({ level = 12, api = "modern" })
  local builds = T.Builds()
  eq(builds, { { id = "combat", name = "Combat" } })
  eq(T.Chosen(), nil, "nothing chosen yet")
  ok(T.Choose("combat"))
  no(T.Choose("no-such-build"), "an unknown build is refused")
  eq(T.Chosen(), "combat")
  -- The second talent group has its own choice.
  c:takeChat()
  c:setTalentGroup(2)
  eq(T.Chosen(), nil, "the second group has no choice yet")
  c:advance(LEVEL_SECONDS - 0.2)
  no(c:chatText():find("Choose a talent build", 1, true), "not before 1.5 s")
  c:advance(0.3)
  has(c:chatText(), "Choose a talent build")
  c:setTalentGroup(1)
  eq(T.Chosen(), "combat")
  local again = c:relog()
  eq(again.G.Noir.Talents.Chosen(), "combat", "kept over a relog")
  again:setTalentGroup(2)
  eq(again.G.Noir.Talents.Chosen(), nil, "and the second group's own choice is kept too")
end)
