-- Noir Guides, GPLv3. See LICENSE.
-- The minimap button (plan task E8, gap #4): on the minimap's rim, dragged along it, left click hides and shows
-- every window while the guide keeps following, right click opens the main menu at the cursor, hidden by its
-- setting. The minimap itself is never changed (the mock records any change as a forbidden call).
use("tools/test-lua/sample/helper.lua")

local DEATHKNELL = "undead-01-03-deathknell"
local GUID = "Player-4444-0000002A"
local KEY = "Tester-Mock"

local function saved(options)
  local db = { schema = 2, owner = GUID, guide = { section = DEATHKNELL, how = "hand", wizard = true,
    places = { [DEATHKNELL] = { step = "a363" } } } }
  local account = {}
  if options then
    account.NoirGuidesDB = { schema = 2, profiles = { Default = options }, defaultProfile = "Default" }
  end
  return { account = account, characters = { [KEY] = { NoirGuidesCharDB = db } } }
end

local function at(opts)
  opts = opts or {}
  local c = sample3({ class = "MAGE", level = 2, saved = saved(opts.options), screen = opts.screen })
  c:login()
  c:advance(0.5)
  return c, c.G.Noir, c.G.Noir.MinimapButton
end

local function center(c, frame)
  local left, bottom, right, top = c:rectOf(frame)
  return (left + right) / 2, (bottom + top) / 2
end

-- The button's angle around the minimap's centre in degrees (0 east, 90 north) and its distance.
local function polar(c, M)
  local mx, my = center(c, c.minimapFrame)
  local bx, by = center(c, M.frame)
  local angle = math.deg(math.atan(by - my, bx - mx)) % 360 -- the test VM's Lua 5.3 form of atan2
  return angle, math.sqrt((bx - mx) ^ 2 + (by - my) ^ 2)
end

-- The button's rect is inside UIParent. c:offScreen() leaves out frames hung on the game's own frames (the button
-- is parented to the minimap), so the button is checked by hand.
local function inside(c, M, what)
  local W, H = c:uiSize()
  local left, bottom, right, top = c:rectOf(M.frame)
  ok(left, (what or "") .. ": the button has a place")
  ok(left >= -0.5 and bottom >= -0.5 and right <= W + 0.5 and top <= H + 0.5,
    string.format("%s: inside the screen (%.1f %.1f %.1f %.1f in %.1f x %.1f)", what or "", left, bottom, right, top, W, H))
end

local function placeId(Noir)
  local _, _, _, step = Noir.Progress.Place()
  return step and step.id
end

test("the button sits on the rim at 225 degrees by default", function()
  local c, Noir, M = at()
  eq(M.Read(), { shown = true, angle = 225 })
  ok(M.frame:IsVisible())
  eq(M.frame:GetParent(), c.minimapFrame, "the addon's own frame, hung on the minimap")
  local angle, distance = polar(c, M)
  near(angle, 225, 0.01)
  local half = c.minimapFrame:GetWidth() / 2
  ok(distance > half - 10 and distance < half + 20, "on the rim, not inside the map")
  M.SetAngle(-90)
  eq(M.Read().angle, 270, "angles wrap into 0..360")
  angle = polar(c, M)
  near(angle, 270, 0.01)
  eq(c:offScreen(), {})
end)

test("dragging moves it along the rim and the angle is saved", function()
  local c, Noir, M = at()
  local mx, my = center(c, c.minimapFrame)
  c:setCursor(mx, my + 200) -- straight above the minimap's centre
  ok(c:drag(M.frame, 0, 0), "the button takes the drag")
  near(M.Read().angle, 90, 0.01)
  near(Noir.Options.Get("minimapAngle"), 90, 0.01, "saved in the profile")
  local angle = polar(c, M)
  near(angle, 90, 0.01)
  inside(c, M, "dragged to 90")
  -- While it is dragged it follows the cursor frame by frame.
  M.frame:GetScript("OnDragStart")(M.frame, "LeftButton")
  c:setCursor(mx - 50, my)
  c:advance(0.05)
  near((polar(c, M)), 180, 0.01, "followed the cursor")
  M.frame:GetScript("OnDragStop")(M.frame)
  near(M.Read().angle, 180, 0.01)
  local again = c:relog()
  near(again.G.Noir.MinimapButton.Read().angle, 180, 0.01, "kept over a relog")
  -- Locked windows: the button stays.
  again.G.Noir.Options.Set("locked", true)
  again:setCursor(mx + 100, my)
  again:drag(again.G.Noir.MinimapButton.frame, 0, 0)
  near(again.G.Noir.MinimapButton.Read().angle, 180, 0.01, "locked: not moved")
  inside(again, again.G.Noir.MinimapButton, "after the relog")
  eq(again:offScreen(), {})
  eq(c:offScreen(), {})
end)

test("the button stays inside the screen at every angle, resolution and UI scale", function()
  for _, screen in ipairs({ { 1024, 768, 1 }, { 1920, 1080, 0.64 }, { 800, 600, 1 } }) do
    local c, Noir, M = at({ screen = screen })
    local what = screen[1] .. "x" .. screen[2]
    for degrees = 0, 345, 15 do
      M.SetAngle(degrees)
      eq(M.Read().angle, degrees, "the saved angle is the one asked for, not a pulled one")
      inside(c, M, what .. " at " .. degrees)
      local angle, distance = polar(c, M)
      local half = c.minimapFrame:GetWidth() / 2
      ok(distance > half - 10, what .. " at " .. degrees .. ": still by the rim, not over the map's middle")
    end
    -- Dragged towards a corner: the button follows but stays inside.
    local mx, my = center(c, c.minimapFrame)
    c:setCursor(mx + 300, my + 300)
    c:drag(M.frame, 0, 0)
    inside(c, M, what .. " dragged to the corner")
    -- A smaller screen or a bigger UI scale later: the button is put back inside.
    M.SetAngle(0)
    c:setScreen(800, 600, 1)
    inside(c, M, what .. " after the resolution changed")
    c:setScreen(800, 600, 0.8)
    inside(c, M, what .. " after the UI scale changed")
    eq(c:offScreen(), {})
  end
end)

test("left click hides and shows every window while the guide keeps following", function()
  local c, Noir, M = at()
  local Screen = Noir.Screen
  Noir.Cleanup.Open()
  Noir.Diagnostics.Open()
  Noir.Wizard.Open()
  Screen.Preview(true)
  Screen.Preview(false)
  local frames = {}
  for _, entry in ipairs(Screen.Registered()) do frames[entry.key] = entry.frame end
  for _, key in ipairs({ "window", "cleanup", "bug", "wizard" }) do
    ok(frames[key] and frames[key]:IsShown(), key .. " shown before")
  end
  ok(c:click(M.frame, "LeftButton"))
  eq(Noir.Options.Get("shown"), false)
  for key, frame in pairs(frames) do no(frame:IsShown(), key .. " hidden") end
  -- The guide keeps following the game.
  eq(placeId(Noir), "a363")
  c:acceptQuest(363)
  c:advance(0.5)
  ok(placeId(Noir) ~= "a363", "the place moved on while hidden")
  local now = placeId(Noir)
  ok(c:click(M.frame, "LeftButton"))
  eq(Noir.Options.Get("shown"), true)
  for _, key in ipairs({ "window", "cleanup", "bug", "wizard" }) do ok(frames[key]:IsShown(), key .. " back") end
  eq(placeId(Noir), now)
  eq(c:slashCount(), 0)
  eq(c:offScreen(), {})
end)

test("right click opens the main menu at the cursor", function()
  local c, Noir, M = at()
  c:hover(M.frame)
  local tip = table.concat(c:tooltip(), "\n")
  has(tip, "Left click")
  has(tip, "Right click")
  c:hover(M.frame, true)
  eq(c:tooltip(), {})
  local x, y = center(c, M.frame)
  c:setCursor(x, y)
  ok(c:click(M.frame, "RightButton"))
  ok(Noir.Menu.IsOpen())
  eq(Noir.Menu.Read().levels[1].rows[1].text, "Choose a section")
  local left, _, right, top = c:rectOf(Noir.Menu.Level(1))
  ok(math.abs(left - x) < 1 or math.abs(right - x) < 1, "a corner at the cursor")
  ok(top <= y + 0.5, "opens from the cursor down")
  eq(Noir.Options.Get("shown"), true, "the right click does not hide anything")
  eq(c:offScreen(), {})
end)

test("the setting hides it", function()
  local c, Noir, M = at()
  Noir.Options.Set("minimap", false)
  eq(M.Read().shown, false)
  no(M.frame:IsShown())
  Noir.Options.Set("minimap", true)
  eq(M.Read().shown, true)
  local off = at({ options = { minimap = false } })
  eq(off.G.Noir.MinimapButton.Read().shown, false, "hidden from login")
  -- Hiding every window leaves the button, so the windows can come back.
  Noir.Screen.SetShown(false)
  ok(M.frame:IsShown())
end)
