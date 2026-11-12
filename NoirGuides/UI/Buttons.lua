-- Noir Guides, GPLv3. See LICENSE.
-- Buttons (spec 4.6, gaps #25, #26 and #31): secure item, spell and target buttons built from the steps on screen.
-- They follow the game by themselves: no command is needed for anything here.
--
--   Buttons.Items() -> { { kind = "item" | "spell", id } }   what the item row shows for the cards now
--   Buttons.Targets() -> { enemy = { name }, friend = { name } } what the target buttons show for the cards now
--   Buttons.Read() -> { items = { shown, buttons = { { kind, id, cooldown = { start, duration } } } },
--                       targets = { shown, enemy = { { name, portrait } }, friend = { ... } }, pending, background }
--   Buttons.Refresh()     builds the buttons again from the cards (out of combat; in combat it waits)
--   Buttons.Preview(on)   sample buttons so the player can place both rows (Screen.Preview)
--   Buttons.Reset()       both rows back at their default places
--   Buttons.items, Buttons.targets   the two row frames
--   Buttons.MAX_ITEMS = 12, Buttons.MAX_TARGETS = 8 (per group), Buttons.PER_ROW = 4, Buttons.NAMED = 4
--   Buttons.FRIEND_MARKS = { 1, 2, 3, 4 } (star, circle, diamond, triangle), Buttons.ENEMY_MARKS = { 8, 7, 6 } (skull,
--   cross, square), by the button's position in its group
--   Buttons.NAMEPLATE_CVAR = "nameplateMaxDistance", Buttons.NAMEPLATE_MAX = "41"
--
-- Item row: from the cards (Progress.Cards): use lines, the steps' items, the item of accept, turnin and objective
-- lines (a quest starter's until the quest is in the log or handed in; an objective's until it is done), the
-- Hearthstone on hearth lines and Astral Recall for a shaman who knows it. Only what can be used now: an item in the
-- bags or worn, a spell that is known. Order: spells, worn items, bag items in bag order. Secure buttons with
-- type = "item" (item = "item:<id>") or type = "spell"; cooldowns shown; the item's or spell's tooltip on hover.
-- Shown only with at least one button and the "itemButtons" option on; scaled by "buttonScale"; the background
-- follows "buttonBackground"; dragged with the left button (and with Alt while "locked" is on).
-- Target buttons: enemies in the top group, friendly NPCs below, PER_ROW to a row, from the cards' `targets` and
-- target lines (the current step's first, then a detour's, then the reminders'), named from Noir.Data.npcs.
-- type = "macro" with the attribute macrotext = "/targetexact <name>": an attribute of the button, not a macro (no
-- macro is ever created). With "markers" on, the macro text also puts the raid marker of the button's position on the
-- unit: "/cleartarget", "/targetexact <name>", "/tm <mark>", so a miss marks nothing. The marker is set by the macro,
-- never by the addon's code: SetRaidTarget is protected on the Forever client (ADDON_ACTION_FORBIDDEN).
-- The portrait shows once the unit was seen as the target, else a placeholder; the tooltip is the name. A friendly NPC the player talks to leaves the list until the place moves.
-- Hidden on a flight, while casting the Hearthstone or Astral Recall, in a raid, without targets, and with
-- "targetButtons" off. "nameplates" raises the nameplate distance to NAMEPLATE_MAX where the client has the setting,
-- and gives the old value back when switched off.
-- In combat nothing secure is built, changed, shown, hidden or moved: the change waits for PLAYER_REGEN_ENABLED.
-- A drag of a row (on the row or on one of its buttons) is refused in combat, and one still going when combat starts
-- ends at PLAYER_REGEN_DISABLED. The nameplate distance asked for in combat is set when combat ends.
-- At its default place the target row hangs from the top a one-row row has there, so more rows grow down.
-- The first NAMED buttons of each kind are the addon's only named frames (NoirGuidesItem1..4, NoirGuidesFriend1..4,
-- NoirGuidesEnemy1..4), bound by Bindings.xml through CLICK bindings.
local Noir = Noir
local State, Progress, Theme, Screen = Noir.State, Noir.Progress, Noir.Theme, Noir.Screen

local Buttons = Noir.Buttons or {}
Noir.Buttons = Buttons

Buttons.MAX_ITEMS = 12
Buttons.MAX_TARGETS = 8
Buttons.PER_ROW = 4
Buttons.NAMED = 4
Buttons.FRIEND_MARKS = { 1, 2, 3, 4 }
Buttons.ENEMY_MARKS = { 8, 7, 6 }
Buttons.NAMEPLATE_CVAR = "nameplateMaxDistance"
Buttons.NAMEPLATE_MAX = "41"

local HEARTHSTONE = 6948
local ASTRAL_RECALL = 556
local HEARTH_SPELLS = { [8690] = true, [556] = true }
local QUESTION_MARK = 134400 -- the client's question mark icon, for an item or spell without an icon yet
local PREVIEW_ITEMS = { { kind = "item", id = HEARTHSTONE } }
local PREVIEW_TARGETS = { enemy = { "Enemy" }, friend = { "Friend" } }

-- The key binding texts: the client reads BINDING_HEADER_<header> and BINDING_NAME_<binding name>.
BINDING_HEADER_NOIRGUIDES = "Noir Guides"
for i = 1, Buttons.NAMED do
  _G["BINDING_NAME_CLICK NoirGuidesItem" .. i .. ":LeftButton"] = "Item button " .. i
  _G["BINDING_NAME_CLICK NoirGuidesFriend" .. i .. ":LeftButton"] = "Friendly target " .. i
  _G["BINDING_NAME_CLICK NoirGuidesEnemy" .. i .. ":LeftButton"] = "Enemy target " .. i
end

local function option(key)
  if Noir.Options then return Noir.Options.Get(key) end
  return nil
end

local function inCombat()
  return InCombatLockdown ~= nil and InCombatLockdown() and true or false
end

-- ---------------------------------------------------------------------------------------------------------------
-- What the cards ask for
-- ---------------------------------------------------------------------------------------------------------------

local removed = {} -- npc ID -> true: a friendly target the player talked to, until the place moves

local function cards()
  return Progress.Cards and Progress.Cards() or {}
end

local function bagSlots()
  local container = C_Container
  local slots = container and container.GetContainerNumSlots or GetContainerNumSlots
  local itemAt = container and container.GetContainerItemID or GetContainerItemID
  return slots, itemAt
end

-- The bag position of each item in the bags: id -> bag * 1000 + slot of its first stack.
local function bagOrder()
  local order = {}
  local slots, itemAt = bagSlots()
  if not (slots and itemAt) then return order end
  for bag = 0, 4 do
    for slot = 1, slots(bag) or 0 do
      local id = itemAt(bag, slot)
      if id and not order[id] then order[id] = bag * 1000 + slot end
    end
  end
  return order
end

local function worn(id)
  return IsEquippedItem ~= nil and IsEquippedItem(id) and true or false
end

function Buttons.Items()
  local wanted, seenItem, seenSpell = {}, {}, {}
  local function addItem(id)
    if type(id) == "number" and id > 0 and not seenItem[id] then
      seenItem[id] = true
      wanted[#wanted + 1] = id
    end
  end
  local spells = {}
  local function addSpell(id)
    if not seenSpell[id] and State.KnowsSpell(id) then
      seenSpell[id] = true
      spells[#spells + 1] = { kind = "spell", id = id }
    end
  end
  local list = cards()
  for c = 1, #list do
    local card = list[c]
    for _, id in ipairs(card.step.items or {}) do addItem(id) end
    for _, entry in ipairs(card.lines or {}) do
      local line = entry.line
      if line and entry.state ~= "hidden" then
        local kind = line.kind
        if kind == "use" then
          addItem(line.item)
        elseif kind == "accept" and line.item then
          if not State.HasQuest(line.quest) and not State.IsDone(line.quest) then addItem(line.item) end
        elseif (kind == "turnin" or kind == "objective") and line.item then
          if entry.state ~= "done" then addItem(line.item) end
        elseif kind == "hearth" then
          addItem(HEARTHSTONE)
          if State.class == "SHAMAN" then addSpell(ASTRAL_RECALL) end
        end
      end
    end
  end
  local order = bagOrder()
  local equipped, inBags = {}, {}
  for _, id in ipairs(wanted) do
    if worn(id) then
      equipped[#equipped + 1] = id
    elseif State.ItemCount(id) > 0 then
      inBags[#inBags + 1] = id
    end
  end
  table.sort(inBags, function(a, b)
    local x, y = order[a] or math.huge, order[b] or math.huge
    if x == y then return a < b end
    return x < y
  end)
  local out = {}
  for _, s in ipairs(spells) do out[#out + 1] = s end
  for _, id in ipairs(equipped) do out[#out + 1] = { kind = "item", id = id } end
  for _, id in ipairs(inBags) do out[#out + 1] = { kind = "item", id = id } end
  while #out > Buttons.MAX_ITEMS do table.remove(out) end
  return out
end

-- Target names with their NPC IDs: { enemy = { { name, npc } }, friend = { ... } }.
local function targetList()
  local out = { enemy = {}, friend = {} }
  local seen = {}
  local function add(group, npc)
    local name = type(npc) == "number" and Noir.Data.npcs[npc]
    if type(name) ~= "string" or name == "" or seen[name] then return end
    if group == "friend" and removed[npc] then return end
    seen[name] = true
    local list = out[group]
    if #list < Buttons.MAX_TARGETS then list[#list + 1] = { name = name, npc = npc } end
  end
  -- Low priority last: the current step's targets, then a detour's, then the reminders'.
  local list, rank = {}, { current = 1, detour = 2, reminder = 3 }
  for i, card in ipairs(cards()) do list[i] = { card = card, i = i } end
  table.sort(list, function(a, b)
    local x, y = rank[a.card.kind] or 4, rank[b.card.kind] or 4
    if x == y then return a.i < b.i end
    return x < y
  end)
  for c = 1, #list do
    local card = list[c].card
    local targets = card.step.targets
    if type(targets) == "table" then
      for _, npc in ipairs(targets.enemy or {}) do add("enemy", npc) end
      for _, npc in ipairs(targets.friend or {}) do add("friend", npc) end
    end
    for _, entry in ipairs(card.lines or {}) do
      local line = entry.line
      if line and line.kind == "target" and entry.state ~= "hidden" then add(line.enemy and "enemy" or "friend", line.npc) end
    end
  end
  return out
end

function Buttons.Targets()
  local list = targetList()
  local out = { enemy = {}, friend = {} }
  for group, entries in pairs(list) do
    for i, e in ipairs(entries) do out[group][i] = e.name end
  end
  return out
end

-- ---------------------------------------------------------------------------------------------------------------
-- Frames
-- ---------------------------------------------------------------------------------------------------------------

local itemsBar, targetsBar
local itemButtons, enemyButtons, friendButtons = {}, {}, {}
local pending = false
local previewing = false
local hearthing = false
local seen = {} -- target name -> true once the unit was the player's target

local function size()
  return Theme.metrics.button
end

local function gap()
  return Theme.metrics.gap
end

local function pad()
  return Theme.metrics.gap
end

local function paintBackground(bar)
  bar.bg:SetShown(option("buttonBackground") ~= false)
end

local function newBar(key)
  local bar = CreateFrame("Frame", nil, UIParent)
  bar:SetSize(size() + 2 * pad(), size() + 2 * pad())
  bar:SetFrameStrata("MEDIUM")
  bar:SetClampedToScreen(true)
  local bg = bar:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(bar)
  Theme.Paint(bg, "bay", Theme.metrics.alpha)
  bar.bg = bg
  paintBackground(bar)
  bar:SetScale(option("buttonScale") or 1)
  bar:Hide()
  Screen.Movable(bar, key, { altWhenLocked = true })
  -- The row holds secure buttons, so the game treats it as protected in combat: StartMoving and StopMovingOrSizing
  -- would be blocked (ADDON_ACTION_BLOCKED). A drag is refused in combat, and a drag still going when combat starts
  -- is ended at PLAYER_REGEN_DISABLED, which comes just before the lockdown.
  local start, stop = bar:GetScript("OnDragStart"), bar:GetScript("OnDragStop")
  bar:SetScript("OnDragStart", function(self, ...)
    if inCombat() then return end
    self.dragging = true
    start(self, ...)
  end)
  bar:SetScript("OnDragStop", function(self, ...)
    if not self.dragging then return end
    self.dragging = nil
    if inCombat() then return end
    stop(self, ...)
  end)
  bar.endDrag = function()
    if not bar.dragging or inCombat() then return end
    bar.dragging = nil
    stop(bar)
  end
  Screen.Place(bar, key)
  return bar
end

-- A drag that starts on a button moves its row.
local function forwardDrag(button, bar)
  button:RegisterForDrag("LeftButton")
  button:SetScript("OnDragStart", function()
    local start = bar:GetScript("OnDragStart")
    if start then start(bar) end
  end)
  button:SetScript("OnDragStop", function()
    local stop = bar:GetScript("OnDragStop")
    if stop then stop(bar) end
  end)
end

local function newButton(bar, name)
  local button = CreateFrame("Button", name, bar, "SecureActionButtonTemplate")
  button:SetSize(size(), size())
  if button.RegisterForClicks then button:RegisterForClicks("AnyUp", "AnyDown") end
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetAllPoints(button)
  icon:SetTexture(QUESTION_MARK)
  button.icon = icon
  forwardDrag(button, bar)
  button:Hide()
  return button
end

local function itemButton(i)
  if itemButtons[i] then return itemButtons[i] end
  local button = newButton(itemsBar, i <= Buttons.NAMED and ("NoirGuidesItem" .. i) or nil)
  local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
  cooldown:SetAllPoints(button)
  button.cooldown = cooldown
  button:SetScript("OnEnter", function(self)
    if not (GameTooltip and self.entry) then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    local e = self.entry
    if e.kind == "item" then
      if GameTooltip.SetItemByID then GameTooltip:SetItemByID(e.id) else GameTooltip:SetHyperlink("item:" .. e.id) end
    elseif GameTooltip.SetSpellByID then
      GameTooltip:SetSpellByID(e.id)
    else
      GameTooltip:AddLine((GetSpellInfo and GetSpellInfo(e.id)) or ("Spell " .. e.id))
    end
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function()
    if GameTooltip then GameTooltip:Hide() end
  end)
  itemButtons[i] = button
  return button
end

local function marks(group)
  return group == "enemy" and Buttons.ENEMY_MARKS or Buttons.FRIEND_MARKS
end

local function targetButton(group, i)
  local list = group == "enemy" and enemyButtons or friendButtons
  if list[i] then return list[i] end
  local prefix = group == "enemy" and "NoirGuidesEnemy" or "NoirGuidesFriend"
  local button = newButton(targetsBar, i <= Buttons.NAMED and (prefix .. i) or nil)
  button:SetAttribute("type", "macro")
  button.group, button.position = group, i
  button:SetScript("OnEnter", function(self)
    if not (GameTooltip and self.target) then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(self.target)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function()
    if GameTooltip then GameTooltip:Hide() end
  end)
  list[i] = button
  return button
end

local function build()
  if itemsBar then return end
  itemsBar = newBar("items")
  targetsBar = newBar("targets")
  Buttons.items, Buttons.targets = itemsBar, targetsBar
  -- The named buttons exist from the start, so their key bindings always find them.
  for i = 1, Buttons.NAMED do
    itemButton(i)
    targetButton("enemy", i)
    targetButton("friend", i)
  end
  Screen.Register("items", itemsBar, function(on) Buttons.Preview(on) end)
  Screen.Register("targets", targetsBar, nil)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Drawing (out of combat only)
-- ---------------------------------------------------------------------------------------------------------------

local function itemIcon(e)
  if e.kind == "spell" then return (GetSpellTexture and GetSpellTexture(e.id)) or QUESTION_MARK end
  local icon = GetItemIcon and GetItemIcon(e.id)
  if not icon and GetItemInfo then icon = select(10, GetItemInfo(e.id)) end
  return icon or QUESTION_MARK
end

local function itemCooldown(e)
  local start, duration
  if e.kind == "spell" then
    if GetSpellCooldown then start, duration = GetSpellCooldown(e.id) end
  else
    local get = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    if get then start, duration = get(e.id) end
  end
  return tonumber(start) or 0, tonumber(duration) or 0
end

local function drawCooldowns()
  for _, button in ipairs(itemButtons) do
    if button.entry and button:IsShown() then
      local start, duration = itemCooldown(button.entry)
      if duration > 0 then
        button.cooldown:SetCooldown(start, duration)
        button.cooldownAt = { start = start, duration = duration }
      else
        if button.cooldown.Clear then button.cooldown:Clear() end
        button.cooldownAt = nil
      end
    end
  end
end

local function layoutRow(bar, count)
  local s, g, p = size(), gap(), pad()
  bar:SetSize(math.max(count, 1) * s + math.max(count - 1, 0) * g + 2 * p, s + 2 * p)
end

local function drawItems(list)
  for i, e in ipairs(list) do
    local button = itemButton(i)
    button.entry = e
    if e.kind == "spell" then
      button:SetAttribute("type", "spell")
      button:SetAttribute("spell", e.id)
      button:SetAttribute("item", nil)
    else
      button:SetAttribute("type", "item")
      button:SetAttribute("item", "item:" .. e.id)
      button:SetAttribute("spell", nil)
    end
    button.icon:SetTexture(itemIcon(e))
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", itemsBar, "TOPLEFT", pad() + (i - 1) * (size() + gap()), -pad())
    button:Show()
  end
  for i = #list + 1, #itemButtons do
    itemButtons[i].entry = nil
    itemButtons[i]:Hide()
  end
  layoutRow(itemsBar, #list)
  local show = #list > 0 and (option("itemButtons") ~= false or previewing) and Screen.Allowed()
  itemsBar:SetShown(show and true or false)
  drawCooldowns()
end

local function placeholder(button)
  button.icon:SetTexture(Theme.Icon(button.group == "enemy" and "kill" or "gossip"))
  button.portrait = false
end

local function drawPortrait(button)
  if UnitName and SetPortraitTexture and UnitName("target") == button.target then
    SetPortraitTexture(button.icon, "target")
    button.portrait = true
  elseif not (button.portrait and button.portraitOf == button.target) then
    placeholder(button)
  end
  if button.portrait then button.portraitOf = button.target end
end

-- The macro text of a target button: target the name, and with "markers" on mark it (see the header).
local function macroText(group, i, name)
  local mark = option("markers") and marks(group)[i]
  if not mark then return "/targetexact " .. name end
  return "/cleartarget\n/targetexact " .. name .. "\n/tm " .. mark
end

local function drawGroup(group, entries, buttons, top)
  local s, g, p = size(), gap(), pad()
  for i, e in ipairs(entries) do
    local button = targetButton(group, i)
    if button.target ~= e.name then
      button.target = e.name
      button.portrait = false
    end
    local text = macroText(group, i, e.name)
    if button.macro ~= text then
      button.macro = text
      button:SetAttribute("macrotext", text)
    end
    if seen[e.name] then drawPortrait(button) elseif not button.portrait then placeholder(button) end
    local row, col = math.floor((i - 1) / Buttons.PER_ROW), (i - 1) % Buttons.PER_ROW
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", targetsBar, "TOPLEFT", p + col * (s + g), -(top + row * (s + g)))
    button:Show()
  end
  for i = #entries + 1, #buttons do
    buttons[i].target = nil
    buttons[i]:Hide()
  end
  local rows = math.ceil(#entries / Buttons.PER_ROW)
  return rows
end

local function targetsHidden()
  if hearthing or State.OnTaxi() then return true end
  if IsInRaid and IsInRaid() then return true end
  if option("targetButtons") == false then return true end
  return false
end

local function drawTargets(list)
  local s, g, p = size(), gap(), pad()
  local enemyRows = drawGroup("enemy", list.enemy, enemyButtons, p)
  local top = p + enemyRows * (s + g)
  if enemyRows > 0 and #list.friend > 0 then top = top + g end
  local friendRows = drawGroup("friend", list.friend, friendButtons, top)
  local rows = enemyRows + friendRows
  local columns = math.min(Buttons.PER_ROW, math.max(#list.enemy, #list.friend, 1))
  local height = 2 * p + math.max(rows, 1) * s + math.max(rows - 1, 0) * g
  if enemyRows > 0 and friendRows > 0 then height = height + g end
  -- At its default place (Screen.DEFAULTS.targets gives the middle of a one-row row) the row hangs from the top a
  -- one-row row has there, so more rows grow down, away from the item buttons above it. A place the player dragged
  -- it to is kept by its top left corner (Screen.Save) and grows down too.
  if not (Noir.Options and Noir.Options.Position("targets")) then
    local d = Screen.DEFAULTS.targets
    local ui, own = UIParent:GetEffectiveScale(), targetsBar:GetEffectiveScale()
    local r = (ui and own and ui > 0 and own > 0) and own / ui or 1
    targetsBar:ClearAllPoints()
    targetsBar:SetPoint("TOP", UIParent, d[2], d[3] / r, d[4] / r + (s + 2 * p) / 2)
  end
  targetsBar:SetSize(columns * s + (columns - 1) * g + 2 * p, height)
  local any = #list.enemy + #list.friend > 0
  local show = any and Screen.Allowed() and (previewing or not targetsHidden())
  targetsBar:SetShown(show and true or false)
end

local function previewTargets()
  local out = { enemy = {}, friend = {} }
  for group, names in pairs(PREVIEW_TARGETS) do
    for i, name in ipairs(names) do out[group][i] = { name = name } end
  end
  return out
end

function Buttons.Refresh()
  if not itemsBar then
    if inCombat() then
      pending = true
      return
    end
    build()
  end
  if inCombat() then
    pending = true
    return
  end
  pending = false
  -- Scale and background: a scale change of a row that holds secure buttons also waits for the end of combat.
  local scale = option("buttonScale") or 1
  for _, bar in ipairs({ itemsBar, targetsBar }) do
    if math.abs(bar:GetScale() - scale) > 1e-6 then
      bar:SetScale(scale)
      Screen.Pull(bar)
    end
    paintBackground(bar)
  end
  if previewing then
    drawItems(PREVIEW_ITEMS)
    drawTargets(previewTargets())
    return
  end
  drawItems(Buttons.Items())
  drawTargets(targetList())
end

function Buttons.Preview(on)
  previewing = on and true or false
  Buttons.Refresh()
end

function Buttons.Reset()
  Screen.Reset("items")
  Screen.Reset("targets")
  Buttons.Refresh() -- the target row hangs from its top again
end

local function readGroup(buttons)
  local out = {}
  for _, button in ipairs(buttons) do
    if button:IsShown() and button.target then out[#out + 1] = { name = button.target, portrait = button.portrait == true } end
  end
  return out
end

function Buttons.Read()
  local items = { shown = itemsBar ~= nil and itemsBar:IsShown(), buttons = {} }
  for _, button in ipairs(itemButtons) do
    if button:IsShown() and button.entry then
      local cd = button.cooldownAt
      items.buttons[#items.buttons + 1] = { kind = button.entry.kind, id = button.entry.id,
        cooldown = cd and { start = cd.start, duration = cd.duration } or nil }
    end
  end
  return {
    items = items,
    targets = { shown = targetsBar ~= nil and targetsBar:IsShown(), enemy = readGroup(enemyButtons), friend = readGroup(friendButtons) },
    pending = pending,
    background = itemsBar ~= nil and itemsBar.bg:IsShown() or false,
  }
end

-- ---------------------------------------------------------------------------------------------------------------
-- The nameplate distance
-- ---------------------------------------------------------------------------------------------------------------

local nameplatesLater = false -- asked for in combat: done at PLAYER_REGEN_ENABLED

local function nameplates()
  if not (GetCVar and SetCVar) then return end
  if inCombat() then
    nameplatesLater = true
    return
  end
  nameplatesLater = false
  local saved = Noir.char and Noir.Table(Noir.char, "buttons")
  if not saved then return end
  local value = GetCVar(Buttons.NAMEPLATE_CVAR)
  if value == nil then return end -- this client has no such setting
  if option("nameplates") then
    if tonumber(value) and tonumber(value) >= tonumber(Buttons.NAMEPLATE_MAX) then return end
    if saved.nameplates == nil then saved.nameplates = value end
    SetCVar(Buttons.NAMEPLATE_CVAR, Buttons.NAMEPLATE_MAX)
  elseif saved.nameplates ~= nil then
    SetCVar(Buttons.NAMEPLATE_CVAR, saved.nameplates)
    saved.nameplates = nil
  end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------------------------------------------

local function refresh()
  Buttons.Refresh()
end

local function npcTalkedTo()
  local guid = UnitGUID and UnitGUID("npc")
  local id = type(guid) == "string" and tonumber(string.match(guid, "^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")) or nil
  if not id or removed[id] then return end
  for _, e in ipairs(targetList().friend) do
    if e.npc == id then
      removed[id] = true
      Buttons.Refresh()
      return
    end
  end
end

Noir.On("NOIR_INIT", function()
  Buttons.Refresh()
  nameplates()
end)
for _, event in ipairs({ "NOIR_STEP", "NOIR_SECTION", "BAG_UPDATE_DELAYED", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB",
  "PLAYER_EQUIPMENT_CHANGED", "GROUP_ROSTER_UPDATE", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED",
  "PLAYER_REGEN_ENABLED" }) do
  Noir.On(event, refresh)
end
Noir.On("PLAYER_REGEN_ENABLED", function()
  if nameplatesLater then nameplates() end
end)
Noir.On("PLAYER_REGEN_DISABLED", function()
  if itemsBar then itemsBar.endDrag() end
  if targetsBar then targetsBar.endDrag() end
end)
Noir.On("NOIR_STATE", function(_, what)
  if what == "quests" or what == "completed" then Buttons.Refresh() end
end)
Noir.On("NOIR_PLACE", function()
  removed = {}
  Buttons.Refresh()
end)
Noir.On("NOIR_OPTION", function(_, key)
  if key == "buttonBackground" then
    if itemsBar then
      paintBackground(itemsBar)
      paintBackground(targetsBar)
    end
  elseif key == "nameplates" then
    nameplates()
  elseif key == "buttonScale" or key == "itemButtons" or key == "targetButtons" or key == "shown" or key == "hideInRaid"
    or key == "markers" then
    Buttons.Refresh()
  end
end)
Noir.On("NOIR_PROFILE", function()
  Buttons.Refresh()
  nameplates()
end)
for _, event in ipairs({ "BAG_UPDATE_COOLDOWN", "SPELL_UPDATE_COOLDOWN" }) do
  Noir.On(event, function() drawCooldowns() end)
end
Noir.On("UNIT_SPELLCAST_START", function(_, unit, _, spell, _, oldSpell)
  if unit ~= "player" then return end
  if type(spell) ~= "number" then spell = oldSpell end
  if HEARTH_SPELLS[spell] then
    hearthing = true
    Buttons.Refresh()
  end
end)
for _, event in ipairs({ "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED" }) do
  Noir.On(event, function(_, unit)
    if unit ~= "player" or not hearthing then return end
    hearthing = false
    Buttons.Refresh()
  end)
end
Noir.On("PLAYER_TARGET_CHANGED", function()
  local name = UnitName and UnitName("target")
  if type(name) ~= "string" then return end
  for _, list in ipairs({ enemyButtons, friendButtons }) do
    for _, button in ipairs(list) do
      if button.target == name then
        seen[name] = true
        drawPortrait(button) -- a texture of the button, not the button: allowed in combat
      end
    end
  end
end)
for _, event in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE",
  "MERCHANT_SHOW", "TRAINER_SHOW", "TAXIMAP_OPENED", "CONFIRM_BINDER" }) do
  Noir.On(event, npcTalkedTo)
end
