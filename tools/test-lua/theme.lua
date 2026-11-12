-- Noir Guides, GPLv3. See LICENSE.
-- UI/Theme.lua against DESIGN.md. The design document is the authority for colors, type sizes and measures: a
-- value changed in one place and not the other fails here.
use("tools/test-lua/sample/helper.lua")

-- The tables of DESIGN.md by section heading: rows whose first cell is a name in backticks, name -> second cell.
local function designTables()
  local text = assert(host.read("DESIGN.md"))
  local out, section = {}, nil
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do
    local heading = line:match("^## (.+)$")
    if heading then
      section = heading
      out[section] = out[section] or {}
    elseif section then
      local key, value = line:match("^| `([%w%-]+)` | `?#?([%w%.]+)`? |")
      if key then out[section][key] = value end
    end
  end
  return out
end

local function keys(t)
  local out = {}
  for key in pairs(t) do out[#out + 1] = key end
  table.sort(out)
  return out
end

-- A character whose profile has the given accent ("gold" by default: the design's own colors).
local function login(class, accent)
  local saved = { account = {}, characters = {} }
  if accent ~= false then
    saved.account.NoirGuidesDB = { schema = 2, defaultProfile = "Default",
      profiles = { Default = { accent = accent or "gold" } } }
  end
  local c = sample({ race = "Undead", class = class or "ROGUE", saved = saved }):login()
  return c.G.Noir.Theme, c
end

local function theme()
  return login("ROGUE", "gold")
end

-- The border textures of the guide window: its 1-pixel edges, painted on the BORDER layer of the frame itself.
local function borderColor(c)
  local frame = c.G.Noir.Window.frame
  for _, region in ipairs(frame.__regions) do
    if region.GetDrawLayer and region:GetDrawLayer() == "BORDER" and region.__color then
      local w, h = region:GetWidth(), region:GetHeight()
      if w == 1 or h == 1 then return region.__color end
    end
  end
end

test("every color of the theme is the color the design gives it, and the design names no other", function()
  local Theme = theme()
  local design = designTables()["Color"]
  ok(design and next(design), "DESIGN.md has a Color table")
  eq(keys(Theme.colors), keys(design))
  for name, hex in pairs(design) do
    eq(Theme.Hex(name), hex:upper(), name)
    local r, g, b, a = Theme.Color(name)
    near(r, tonumber(hex:sub(1, 2), 16) / 255, 1e-9, name .. " red")
    near(g, tonumber(hex:sub(3, 4), 16) / 255, 1e-9, name .. " green")
    near(b, tonumber(hex:sub(5, 6), 16) / 255, 1e-9, name .. " blue")
    eq(a, 1, name .. " alpha")
  end
  eq({ Theme.Color("no-such-color") }, { 1, 1, 1, 1 }, "an unknown name is white, not an error")
  eq(select(4, Theme.Color("bay", 0.5)), 0.5, "an alpha can be given")
end)

test("the type sizes and the measures are the design's", function()
  local Theme = theme()
  local design = designTables()
  eq(keys(Theme.sizes), keys(design["Type"]))
  for role, size in pairs(design["Type"]) do eq(Theme.sizes[role], tonumber(size), role) end
  eq(keys(Theme.metrics), keys(design["Measures"]))
  for name, value in pairs(design["Measures"]) do eq(Theme.metrics[name], tonumber(value), name) end
end)

test("the textures the design lists are the files the addon ships and the theme names", function()
  local Theme = theme()
  local design = designTables()["Textures"]
  eq(keys(Theme.textures), keys(design))
  local shipped = {}
  for _, file in ipairs(host.list("NoirGuides/Textures")) do shipped[#shipped + 1] = (file:gsub("%.tga$", "")) end
  table.sort(shipped)
  eq(shipped, keys(design), "NoirGuides/Textures holds exactly the design's textures, as .tga")
  for name in pairs(design) do
    eq(Theme.Texture(name), "Interface\\AddOns\\NoirGuides\\Textures\\" .. name)
  end
  eq(Theme.Texture("no-such-texture"), nil)
end)

test("text is set with the client's default font file, never with a font object", function()
  local Theme, c = theme()
  local frame = c.G.CreateFrame("Frame", nil, c.G.UIParent)
  local text = frame:CreateFontString(nil, "OVERLAY")
  eq(Theme.Font(text, "name"), true)
  eq({ text:GetFont() }, { "Fonts\\FRIZQT__.TTF", Theme.sizes.name, "" })
  Theme.SetText(text, "hello")
  eq(text:GetText(), "hello")
  local none = frame:CreateFontString(nil, "OVERLAY")
  Theme.SetText(none, "never shown") -- no font was set: the text is dropped instead of raising the client's error
  eq(none:GetText(), nil)
  eq(Theme.Font(text, "no-such-role"), true, "an unknown role gets the body size")
  eq(select(2, text:GetFont()), Theme.sizes.body)
  eq(c.violations, {})
end)

test("a font file of the addon's own is used once it is set, and the default when it cannot be loaded", function()
  local Theme, c = theme()
  local text = c.G.CreateFrame("Frame", nil, c.G.UIParent):CreateFontString(nil, "OVERLAY")
  Theme.fontFile = "Interface\\AddOns\\NoirGuides\\Fonts\\NotThere.ttf"
  eq(Theme.Font(text, "body"), true)
  eq((text:GetFont()), "Fonts\\FRIZQT__.TTF")
  Theme.fontFile = "Fonts\\MORPHEUS.TTF"
  eq(Theme.Font(text, "body"), true)
  eq((text:GetFont()), "Fonts\\MORPHEUS.TTF")
end)

test("a solid color is painted with whichever call the client has", function()
  local Theme, c = theme()
  local frame = c.G.CreateFrame("Frame", nil, c.G.UIParent)
  local modern = frame:CreateTexture(nil, "BACKGROUND")
  Theme.Paint(modern, "lamp")
  eq(modern.__color, { Theme.Color("lamp") })
  local old = frame:CreateTexture(nil, "BACKGROUND")
  old.SetColorTexture = false -- a client from before SetColorTexture
  Theme.Paint(old, "lamp", 0.5)
  eq(old:GetTexture(), "Interface\\Buttons\\WHITE8X8")
  eq({ old:GetVertexColor() }, { Theme.Color("lamp", 0.5) })
  eq(c.errors, {})
end)

test("chat lines carry the addon's name in the lamp color", function()
  local Theme, c = theme()
  c:takeChat()
  c:slash("/noir version")
  has(c:chatText(), "|cff" .. Theme.Hex("lamp") .. "Noir|r")
end)

test("the toc loads the interface after the engine, in dependency order, and lists every interface file", function()
  local toc = HARNESS.Client.parseToc(assert(host.read("NoirGuides/NoirGuides.toc")))
  local at = {}
  for i, file in ipairs(toc.files) do at[file] = i end
  local order = { "Automation.lua", "UI/Theme.lua", "UI/Text.lua", "UI/Window.lua", "UI/Arrow.lua", "UI/Map.lua" }
  for i = 1, #order do ok(at[order[i]], order[i] .. " is in the toc") end
  for i = 2, #order do ok(at[order[i - 1]] < at[order[i]], order[i - 1] .. " loads before " .. order[i]) end
  for _, name in ipairs(host.list("NoirGuides/UI")) do
    ok(at["UI/" .. name], "UI/" .. name .. " is in the toc")
  end
end)

test("the design names a color for each meaning a line's words can have", function()
  local Theme = theme()
  local design = designTables()["Color"]
  for _, meaning in ipairs({ "friend", "enemy", "loot", "warning", "object", "buy" }) do
    ok(design[meaning], "DESIGN.md has the " .. meaning .. " color")
    ok(Theme.colors[meaning], "and so does the theme")
  end
end)

test("the large type adds the design's step to every size", function()
  local Theme, c = theme()
  local text = c.G.CreateFrame("Frame", nil, c.G.UIParent):CreateFontString(nil, "OVERLAY")
  eq(Theme.Font(text, "body", true), true)
  eq(select(2, text:GetFont()), Theme.sizes.body + Theme.metrics.large)
  eq(Theme.Font(text, "body"), true)
  eq(select(2, text:GetFont()), Theme.sizes.body)
end)

test("the design describes the card stack and the step list, and names the only motion", function()
  local text = assert(host.read("DESIGN.md"))
  for _, heading in ipairs({ "## The idea", "## Layout", "## States", "## The words of a step" }) do
    has(text, heading)
  end
  has(text, "card stack")
  has(text, "step list")
  has(text, "The card slide and the talent ring are the only motion in the interface")
  ok(not text:find("%f[%a][Rr]ack%f[%A]"), "the Strip Bay rack is gone")
end)

test("the accent is the class color by default, and the design's gold with the gold accent", function()
  local Theme, c = login("MAGE", false)
  eq(c.G.Noir.Options.Get("accent"), "class")
  eq(Theme.Hex("lamp"), "3FC7EB", "a mage's accent is the mage color")
  eq(Theme.Border(), "lamp", "the window's border takes the class color")
  eq(Theme.Hex("quest"), "F2B33D", "quest icons stay gold")
  c:takeChat()
  c:slash("/noir version")
  has(c:chatText(), "|cff3FC7EBNoir|r", "the addon's name in chat too")
  local Gold = login("MAGE", "gold")
  eq(Gold.Hex("lamp"), "F2B33D")
  eq(Gold.Border(), "track", "gold: the window as it was, grey border included")
end)

test("every class has an accent that reads on the window, and the priest's is not white", function()
  local Theme = theme()
  local function luminance(hex)
    local sum = 0
    for i, weight in ipairs({ 0.2126, 0.7152, 0.0722 }) do
      local v = tonumber(hex:sub(i * 2 - 1, i * 2), 16) / 255
      v = v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4
      sum = sum + weight * v
    end
    return sum
  end
  local function ratio(a, b)
    local x, y = luminance(a), luminance(b)
    if x < y then x, y = y, x end
    return (x + 0.05) / (y + 0.05)
  end
  for _, class in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
    local hex = Theme.CLASS_COLORS[class]
    ok(hex, class .. " has a color")
    ok(ratio(hex, Theme.Hex("strip")) >= 4.5, class .. " reads on a card (4.5 to 1)")
    local Class = login(class, "class")
    eq(Class.Hex("lamp"), hex, class)
  end
  ok(Theme.CLASS_COLORS.PRIEST ~= "FFFFFF", "the priest's accent is not white")
end)

test("a class without a color keeps the gold accent", function()
  local Theme, c = login("MAGE", "class")
  eq(Theme.Hex("lamp"), "3FC7EB")
  Theme.CLASS_COLORS.MAGE = nil -- a class the table does not know
  Theme.ApplyAccent()
  eq(Theme.Hex("lamp"), "F2B33D")
  eq({ Theme.Color("lamp") }, { Theme.Color("quest") })
  eq(Theme.Border(), "track")
  eq(c.errors, {})
end)

test("the window's border is grey with gold, in the class color with the class accent", function()
  local _, gold = login("MAGE", "gold")
  local _, class = login("MAGE", "class")
  local GoldTheme, ClassTheme = gold.G.Noir.Theme, class.G.Noir.Theme
  local g, k = borderColor(gold), borderColor(class)
  ok(g and k, "the border is found")
  eq(g, { GoldTheme.Color("track") })
  eq(k, { ClassTheme.Color("lamp") })
end)
