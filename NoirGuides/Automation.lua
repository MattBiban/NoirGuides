-- Noir Guides, GPLv3. See LICENSE.
-- Automation v2 (spec 5, gaps #27 to #32 and #35): at an NPC, do what the steps on screen say, and nothing else. It
-- follows the game by itself: no command is needed for anything here.
--
--   Automation.Enabled(key) -> boolean   the option of that name: autoQuests, guideRewards, rewardMarker, bestReward,
--                                        flights, hearth, dialogue, buy, sellJunk, train (false for any other key)
--   Automation.Read() -> { marker, logMarker, training, talk }
--                                        marker / logMarker = { quest, choice, shown } while the coin marks a choice
--                                        on the reward page / in the quest log's detail pane; training = true while
--                                        the trainer automation runs; selling = true while grey items are being
--                                        sold; talk = { ctrl, shift, any } for the NPC conversation in progress
--   Automation.FOLLOW_UP_SECONDS = 0.5   a quest page this soon after a hand-in is a follow-up
--   Automation.GETFLIGHT_SECONDS = 10    a flight point line re-picks the flight master option at most this often
--   Automation.FLIGHT_DELAY = 0.2        the flight is taken this long after the flight map opens
--   Automation.TRAIN_SECONDS = 15, Automation.TRAIN_EVERY = 0.2   the trainer automation's span and pace
--   Automation.HANDOVER_SECONDS = 0.5    after the gossip list closes, another window of the NPC opened this soon
--                                        is the same conversation
--   Automation.SELL_EVERY = 0.2          grey items are sold one bag slot per this many seconds
--
-- Rules:
--   * Holding Ctrl when an NPC window opens keeps accept, hand-in and reward automation away for that conversation;
--     holding Shift keeps flight, bind and dialogue automation away; no dialogue line is picked while any modifier
--     is held. A conversation lasts from the first NPC window until the last one closes (or another NPC talks).
--     The gossip list closing (GOSSIP_CLOSED) does not end it at once: the client also closes the list when a quest
--     page, the flight map, a merchant or a trainer of the same NPC takes its place, so the conversation carries
--     on into such a window opened within HANDOVER_SECONDS (0.5 s); a new gossip list starts a new conversation.
--   * Accept: quests of accept lines on the cards and on Progress.Lookahead(), not manual, not in the section's
--     noAuto. Hand-in: quests of turnin lines on the cards, not manual, not in noAuto; a turnin line once on a card
--     keeps its quest eligible for the session. A quest is matched by ID; by title only where the client gives only
--     titles, and only when the title belongs to exactly one entry and one quest.
--   * Dialogue list: a complete quest the guide hands in, then a quest it accepts, then an unfinished guide quest
--     whose only objective is an objective line naming this NPC. Without any, the dialogue line for a fly line (once
--     per step), a getflight line (at most every GETFLIGHT_SECONDS), a sethearth line or a train line on a card,
--     recognised by its type (flight, bind, trainer), never by its text, and only at the line's NPC when both are
--     known.
--   * Quest pages: detail -> accept (and close the page if it stays open); a page that is no guide quest within
--     FOLLOW_UP_SECONDS of a hand-in is closed. Progress -> continue when completable. Reward -> no or one choice:
--     take it; the line's reward with guideRewards: take it; else the best sell price (count times price): taken
--     with bestReward, else marked with the coin (rewardMarker) and the page left to the player. The coin also marks
--     the best choice of the quest selected in the quest log (own frame on the quest log frame, which is read, never
--     changed or hooked). Shared quests and escort starts (QUEST_ACCEPT_CONFIRM) are confirmed under the accept rule.
--   * Flights: at the flight map with a fly line on a card, from the line's node (or where the client does not say),
--     the destination by node ID, else the first reachable node whose name holds the destination's name.
--   * Bind: CONFIRM_BINDER with a sethearth line on a card is answered on the next frame; only that popup is closed.
--   * Vendor: a merchant opened with a vendor line (buy) on a card, at its NPC, buys what the bags lack up to the
--     count, capped by the stock, in full stacks, and closes once the bags hold it; nothing when a collect line of the
--     same item on the cards is done. An item sold in bundles is bought in whole bundles (the count rounded up), and
--     its stock counts bundles.
--   * Grey items (sellJunk, on by default): at any merchant, unless a modifier key was held when its window opened,
--     one bag slot of quality 0 (poor) items is sold every SELL_EVERY until none is left, then one chat line gives
--     the total. Nothing above quality 0 is sold (each slot is read again just before), and no item a collect line
--     on the cards still needs. A vendor line that closes the merchant once it bought waits for the selling to end.
--   * Trainer (train off by default): for TRAIN_SECONDS after TRAINER_SHOW, every TRAIN_EVERY, buys one available
--     service, lowest level first: every one at a class trainer, only those named by a train line on a card at a
--     profession trainer; nothing at a pet trainer. No gold check.
-- Nothing here is a protected call, writes a macro or changes a popup.
local Noir = Noir
local State, Guide, Progress, Lines = Noir.State, Noir.Guide, Noir.Progress, Noir.Lines

local Automation = {}
Noir.Automation = Automation

Automation.FOLLOW_UP_SECONDS = 0.5
Automation.GETFLIGHT_SECONDS = 10
Automation.FLIGHT_DELAY = 0.2
Automation.TRAIN_SECONDS = 15
Automation.TRAIN_EVERY = 0.2
Automation.HANDOVER_SECONDS = 0.5
Automation.SELL_EVERY = 0.2

local KEYS = {
  autoQuests = true, guideRewards = true, rewardMarker = true, bestReward = true, flights = true, hearth = true,
  dialogue = true, buy = true, sellJunk = true, train = true,
}
-- A conversation with no window event for this long has ended even if the client never said so.
local STALE_SECONDS = 60
-- The client's gold coin icon (Interface\MoneyFrame\UI-GoldIcon). Unverified on Forever: docs/ENGINE-NOTES.md.
local COIN_TEXTURE = 237618
local COIN_SIZE = 16
local LOG_EVERY = 0.2
local PET_SKILL_LINES = { ["Beast Training"] = true, ["Pet Training"] = true }
local RANK_NAMES = { "Apprentice", "Journeyman", "Expert", "Artisan" }

local function now()
  return GetTime and GetTime() or 0
end

function Automation.Enabled(key)
  if not KEYS[key] or not Noir.Options then return false end
  return Noir.Options.Get(key) == true
end

-- ---------------------------------------------------------------------------------------------------------------
-- The conversation and the NPC
-- ---------------------------------------------------------------------------------------------------------------

local talk = nil -- { ctrl, shift, any, guid, at }

local function npcGuid()
  local guid = UnitGUID and UnitGUID("npc")
  return type(guid) == "string" and guid or nil
end

-- The NPC ID inside the GUID of the unit the player talks to; nil for the old hexadecimal GUIDs.
local function npcId()
  local guid = npcGuid()
  if not guid then return nil end
  local kind, id = string.match(guid, "^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
  if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
  return nil
end

local function down(fn)
  return fn ~= nil and fn() and true or false
end

local questOpen = false -- a quest page or the quest greeting is open

-- The conversation in progress, or a new one with the modifiers held now. `fresh` is true for the gossip list: after
-- the gossip closed, only another window of the same NPC (a quest page, the flight map, ...) carries on with it.
local function begin(fresh)
  local guid = npcGuid()
  if talk and (now() - talk.at > STALE_SECONDS or (guid and talk.guid and guid ~= talk.guid)) then talk = nil end
  if talk and talk.closedAt then
    if fresh or now() - talk.closedAt > Automation.HANDOVER_SECONDS then
      talk = nil
    else
      talk.closedAt = nil
    end
  end
  if not talk then
    talk = {
      ctrl = down(IsControlKeyDown), shift = down(IsShiftKeyDown),
      any = down(IsModifierKeyDown) or down(IsControlKeyDown) or down(IsShiftKeyDown) or down(IsAltKeyDown),
      guid = guid,
    }
  end
  talk.guid = talk.guid or guid
  talk.at = now()
  return talk
end

local function finish()
  talk = nil
end

-- The client's gossip frame calls CloseGossip from its OnHide, so GOSSIP_CLOSED also fires when the gossip list gives
-- way to a quest page, the flight map, a merchant or a trainer of the same NPC (before or after that window's event).
-- The conversation is kept for HANDOVER_SECONDS; it ends then unless another window of the NPC took over.
local function gossipClosed()
  if not talk or questOpen then return end
  local closing = talk
  closing.closedAt = now()
  Noir.After(Automation.HANDOVER_SECONDS, function()
    if talk == closing and closing.closedAt then talk = nil end
  end)
end

-- True only when it is certain that the player talks to another NPC than the line names.
local function otherNpc(line)
  if type(line.npc) ~= "number" then return false end
  local id = npcId()
  return id ~= nil and id ~= line.npc
end

-- ---------------------------------------------------------------------------------------------------------------
-- What the steps on screen ask for
-- ---------------------------------------------------------------------------------------------------------------

local eligible = {} -- quest -> turnin line: once on a card, eligible for the session

local function blocked()
  local set = {}
  local section = Guide.Current and Guide.Section(Guide.Current() or "")
  if section and type(section.noAuto) == "table" then
    for i = 1, #section.noAuto do set[section.noAuto[i]] = true end
  end
  return set
end

-- Each card line that is not hidden: fn(line, entry, card).
local function eachCardLine(fn)
  local cards = Progress.Cards and Progress.Cards() or {}
  for c = 1, #cards do
    local card = cards[c]
    for l = 1, #(card.lines or {}) do
      local entry = card.lines[l]
      if entry.line and entry.state ~= "hidden" then
        local stop = fn(entry.line, entry, card)
        if stop then return end
      end
    end
  end
end

local function open(entry)
  return entry.state == "todo" and not entry.ticked
end

-- accepts[quest] and turnins[quest] = the line, objectives = { line, ... } (lines that are not done).
local function wanted()
  local no = blocked()
  local accepts, turnins, objectives = {}, {}, {}
  eachCardLine(function(line, entry)
    local quest = line.quest
    if type(quest) ~= "number" or no[quest] then return end
    if line.kind == "accept" and not line.manual then
      accepts[quest] = accepts[quest] or line
    elseif line.kind == "turnin" and not line.manual then
      eligible[quest] = eligible[quest] or line
    elseif line.kind == "objective" and open(entry) then
      objectives[#objectives + 1] = line
    end
  end)
  local after = Progress.Lookahead and Progress.Lookahead()
  if after then
    for _, line in ipairs(after.lines or {}) do
      local quest = line.quest
      if line.kind == "accept" and not line.manual and type(quest) == "number" and not no[quest] and Lines.Applies(line.when) then
        accepts[quest] = accepts[quest] or line
      end
    end
  end
  for quest, line in pairs(eligible) do
    if not no[quest] then turnins[quest] = line end
  end
  return accepts, turnins, objectives
end

-- The first open card line of a kind (and the card), or nil.
local function cardLine(kind, test)
  local found, foundCard
  eachCardLine(function(line, entry, card)
    if line.kind == kind and open(entry) and (not test or test(line)) then
      found, foundCard = line, card
      return true
    end
  end)
  return found, foundCard
end

-- ---------------------------------------------------------------------------------------------------------------
-- Quests by ID or title
-- ---------------------------------------------------------------------------------------------------------------

local function titleOf(quest)
  local inLog = State.Quest(quest)
  if inLog and type(inLog.title) == "string" and inLog.title ~= "" then return inLog.title end
  local name = Noir.Data.quests[quest]
  if type(name) == "string" and name ~= "" then return name end
  return nil
end

-- The quest of `set` with this title, when exactly one has it.
local function byTitle(set, title)
  if type(title) ~= "string" or title == "" then return nil end
  local found, count = nil, 0
  for quest in pairs(set) do
    if titleOf(quest) == title then
      found, count = quest, count + 1
    end
  end
  if count == 1 then return found end
  return nil
end

-- The quest of `set` an entry of a list ({ id, title }) is, or nil. A title only counts when no other entry of the
-- list carries it.
local function entryQuest(entries, entry, set)
  if type(entry.id) == "number" and entry.id > 0 then return set[entry.id] and entry.id or nil end
  local same = 0
  for i = 1, #entries do
    if entries[i].title == entry.title then same = same + 1 end
  end
  if same ~= 1 then return nil end
  return byTitle(set, entry.title)
end

-- The quest of the quest page that is open, among `set` (by ID when the client gives one, else by title).
local function dialogQuest(set)
  local id = GetQuestID and GetQuestID()
  if type(id) == "number" and id > 0 then return id end
  return byTitle(set, GetTitleText and GetTitleText())
end

local function readyInLog(quest)
  local q = State.Quest(quest)
  if not q or q.failed then return false end
  if q.complete then return true end
  if #q.objectives == 0 then return false end
  for i = 1, #q.objectives do
    if not q.objectives[i].done then return false end
  end
  return true
end

-- ---------------------------------------------------------------------------------------------------------------
-- Gossip and the quest greeting: the shapes of the API
-- ---------------------------------------------------------------------------------------------------------------

-- Splits the flat returns of the old gossip functions into one table per quest; the values per quest differ
-- between builds, so the stride is worked out from the count the client reports.
local function unflatten(count, ...)
  local values, total = { ... }, select("#", ...)
  local rows = {}
  if type(count) ~= "number" or count <= 0 or total == 0 or total % count ~= 0 then return rows, 0 end
  local stride = total / count
  for i = 1, count do
    local row = {}
    for j = 1, stride do row[j] = values[(i - 1) * stride + j] end
    rows[i] = row
  end
  return rows, stride
end

-- The NPC's quests of one kind ("available" or "active") as { id, title, complete, pick }.
local function gossipQuests(kind)
  local out = {}
  local info = C_GossipInfo
  local get = info and (kind == "active" and info.GetActiveQuests or info.GetAvailableQuests)
  local choose = info and (kind == "active" and info.SelectActiveQuest or info.SelectAvailableQuest)
  if get and choose then
    local list = get()
    if type(list) ~= "table" then return out end
    for i = 1, #list do
      local e = list[i]
      local key = (type(e.questID) == "number" and e.questID > 0) and e.questID or i
      out[i] = { id = e.questID, title = e.title, complete = e.isComplete, pick = function() choose(key) end }
    end
    return out
  end
  local list = kind == "active" and GetGossipActiveQuests or GetGossipAvailableQuests
  local number = kind == "active" and GetNumGossipActiveQuests or GetNumGossipAvailableQuests
  local pick = kind == "active" and SelectGossipActiveQuest or SelectGossipAvailableQuest
  if not (list and number and pick) then return out end
  local rows, stride = unflatten(number(), list())
  for i = 1, #rows do
    local complete = nil
    if kind == "active" and stride >= 4 then complete = rows[i][4] and true or false end
    out[i] = { title = rows[i][1], complete = complete, pick = function() pick(i) end }
  end
  return out
end

local function greetingQuests(kind)
  local out = {}
  local number = kind == "active" and GetNumActiveQuests or GetNumAvailableQuests
  local title = kind == "active" and GetActiveTitle or GetAvailableTitle
  local pick = kind == "active" and SelectActiveQuest or SelectAvailableQuest
  if not (number and title and pick) then return out end
  for i = 1, number() or 0 do
    local name, complete = title(i)
    local id
    if kind == "active" then
      id = GetActiveQuestID and GetActiveQuestID(i) or nil
      if complete ~= nil then complete = complete and true or false end
    else
      complete = nil
      if GetAvailableQuestInfo then id = select(5, GetAvailableQuestInfo(i)) end
    end
    if id == 0 then id = nil end
    out[i] = { id = id, title = name, complete = complete, pick = function() pick(i) end }
  end
  return out
end

-- The client's icons for dialogue lines on builds that give an icon instead of a type. Unverified on Forever: see
-- docs/ENGINE-NOTES.md.
local OPTION_ICONS = { [132057] = "taxi", [132052] = "binder", [132058] = "trainer" }
local OPTION_PATHS = { taxigossipicon = "taxi", bindergossipicon = "binder", trainergossipicon = "trainer" }

local function optionKind(kind, icon)
  if type(kind) == "string" then return string.lower(kind) end
  if type(icon) == "number" then return OPTION_ICONS[icon] end
  if type(icon) == "string" then
    local path = string.lower(icon)
    for piece, name in pairs(OPTION_PATHS) do
      if string.find(path, piece, 1, true) then return name end
    end
  end
  return nil
end

-- The NPC's dialogue lines as { kind, pick }.
local function gossipOptions()
  local out = {}
  local info = C_GossipInfo
  if info and info.GetOptions and info.SelectOption then
    local list = info.GetOptions()
    if type(list) ~= "table" then return out end
    for i = 1, #list do
      local e = list[i]
      local key = e.gossipOptionID or i
      out[i] = { kind = optionKind(e.type, e.icon), pick = function() info.SelectOption(key) end }
    end
    return out
  end
  if not (GetGossipOptions and SelectGossipOption) then return out end
  local values = { GetGossipOptions() } -- text 1, type 1, text 2, type 2, ...
  for i = 1, math.floor(#values / 2) do
    out[i] = { kind = optionKind(values[i * 2]), pick = function() SelectGossipOption(i) end }
  end
  return out
end

-- ---------------------------------------------------------------------------------------------------------------
-- The dialogue list
-- ---------------------------------------------------------------------------------------------------------------

local flownPicked = {}   -- "section:step" -> true once the flight line was picked for that step's fly line
local getflightAt = nil  -- when the flight master line was last picked for a getflight line

local function placeKey(card)
  return tostring(Guide.Current and Guide.Current()) .. ":" .. tostring(card and card.step and card.step.id)
end

local function pickQuest(quests)
  if not Automation.Enabled("autoQuests") then return false end
  local accepts, turnins, objectives = wanted()
  local active = quests("active")
  for i = 1, #active do
    local quest = entryQuest(active, active[i], turnins)
    if quest then
      local ready = active[i].complete
      if ready == nil then ready = readyInLog(quest) end
      if ready then
        active[i].pick()
        return true
      end
    end
  end
  local available = quests("available")
  for i = 1, #available do
    if entryQuest(available, available[i], accepts) then
      available[i].pick()
      return true
    end
  end
  local talkTo = {}
  local here = npcId()
  for i = 1, #objectives do
    local line = objectives[i]
    local q = State.Quest(line.quest)
    if here and line.npc == here and q and #q.objectives == 1 and line.index == 1 then talkTo[line.quest] = line end
  end
  for i = 1, #active do
    local quest = entryQuest(active, active[i], talkTo)
    if quest and not readyInLog(quest) then
      active[i].pick()
      return true
    end
  end
  return false
end

-- The dialogue line kind the cards want here, or nil, and what to remember when it is picked.
local function wantedOption()
  if Automation.Enabled("flights") then
    local line, card = cardLine("fly", function(l) return not otherNpc(l) end)
    if line and not flownPicked[placeKey(card)] then
      return "taxi", function() flownPicked[placeKey(card)] = true end
    end
    line = cardLine("getflight", function(l) return not otherNpc(l) end)
    if line and (not getflightAt or now() - getflightAt >= Automation.GETFLIGHT_SECONDS) then
      return "taxi", function() getflightAt = now() end
    end
  end
  if Automation.Enabled("hearth") and cardLine("sethearth", function(l) return not otherNpc(l) end) then
    return "binder"
  end
  if Automation.Enabled("dialogue") and cardLine("train", function(l) return not otherNpc(l) end) then
    return "trainer"
  end
  return nil
end

local function pickOption(options)
  local kind, remember = wantedOption()
  if not kind then return end
  local list = options()
  local found, count = nil, 0
  for i = 1, #list do
    if list[i].kind == kind then
      found, count = list[i], count + 1
    end
  end
  if count ~= 1 then return end
  if remember then remember() end
  found.pick()
end

local function atList(quests, options, fresh)
  local t = begin(fresh)
  if not t.ctrl and pickQuest(quests) then return end
  if options and not t.any and not t.shift then pickOption(options) end
end

-- ---------------------------------------------------------------------------------------------------------------
-- The coin marker
-- ---------------------------------------------------------------------------------------------------------------

-- The choice with the best sell price (price times count), or nil when no choice has a known price.
local function bestChoice(count, linkOf, countOf)
  local best, bestValue = nil, 0
  for i = 1, count do
    local link = linkOf(i)
    local price = link and GetItemInfo and select(11, GetItemInfo(link)) or 0
    local value = (tonumber(price) or 0) * (tonumber(countOf(i)) or 1)
    if value > bestValue then best, bestValue = i, value end
  end
  return best
end

local function newCoin(parent)
  local frame = CreateFrame("Frame", nil, parent or UIParent)
  frame:SetSize(COIN_SIZE, COIN_SIZE)
  frame:SetFrameStrata("DIALOG")
  local coin = frame:CreateTexture(nil, "OVERLAY")
  coin:SetAllPoints(frame)
  coin:SetTexture(COIN_TEXTURE)
  frame.coin = coin
  local label = frame:CreateFontString(nil, "OVERLAY")
  label:SetPoint("RIGHT", frame, "LEFT", -2, 0)
  if Noir.Theme and Noir.Theme.Font(label, "small") then Noir.Theme.TextColor(label, "lamp") end
  frame.label = label
  frame:Hide()
  return frame
end

-- Puts a coin on `button` (the client's frame of the choice) or, without one, inside the top right corner of
-- `holder` with the item's name beside it.
local function placeCoin(frame, button, holder, name)
  frame:ClearAllPoints()
  if button then
    frame:SetParent(button)
    frame:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
    if frame.label:GetFont() then frame.label:SetText("") end
  elseif holder then
    frame:SetParent(holder)
    frame:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -40, -40)
    if frame.label:GetFont() then frame.label:SetText(name or "") end
  else
    frame:Hide()
    return false
  end
  frame:SetFrameStrata("DIALOG")
  frame:Show()
  if Noir.Screen then Noir.Screen.Keep(frame) end
  return true
end

local marker, markerFrame = nil, nil

local function hideMarker()
  marker = nil
  if markerFrame then markerFrame:Hide() end
end

local function showMarker(quest, choice)
  markerFrame = markerFrame or newCoin()
  local name = GetQuestItemInfo and GetQuestItemInfo("choice", choice)
  local button = _G["QuestInfoRewardsFrameQuestInfoItem" .. choice] or _G["QuestRewardItem" .. choice]
  local holder = _G.QuestFrame
  local shown = placeCoin(markerFrame, button, holder, name)
  marker = { quest = quest, choice = choice, shown = shown }
end

-- The quest log's detail pane: read every LOG_EVERY seconds while the quest log is shown.
local logFrame, logCoin, logMarker = nil, nil, nil
local logWait = 0

local function selectedLogQuest()
  if C_QuestLog and C_QuestLog.GetSelectedQuest then
    local id = C_QuestLog.GetSelectedQuest()
    if type(id) == "number" and id > 0 then return id end
  end
  local index = GetQuestLogSelection and GetQuestLogSelection()
  if type(index) ~= "number" or index <= 0 or not GetQuestLogTitle then return nil end
  local id = select(8, GetQuestLogTitle(index))
  return type(id) == "number" and id > 0 and id or nil
end

local function readLog()
  logMarker = nil
  local quest = selectedLogQuest()
  local count = quest and GetNumQuestLogChoices and GetNumQuestLogChoices() or 0
  local best
  if quest and count >= 2 and GetQuestLogItemLink and Automation.Enabled("rewardMarker") then
    best = bestChoice(count, function(i) return GetQuestLogItemLink("choice", i) end, function(i)
      return GetQuestLogChoiceInfo and select(3, GetQuestLogChoiceInfo(i)) or 1
    end)
  end
  if not best then
    if logCoin then logCoin:Hide() end
    return
  end
  logCoin = logCoin or newCoin(logFrame)
  local name = GetQuestLogChoiceInfo and GetQuestLogChoiceInfo(best)
  local shown = placeCoin(logCoin, _G["QuestLogItem" .. best], QuestLogFrame, name)
  logMarker = { quest = quest, choice = best, shown = shown }
end

local function watchLog()
  if logFrame or not QuestLogFrame then return end
  logFrame = CreateFrame("Frame", nil, QuestLogFrame)
  logFrame:SetSize(1, 1)
  logFrame:SetPoint("TOPLEFT", QuestLogFrame, "TOPLEFT", 0, 0)
  logFrame:SetScript("OnUpdate", function(_, elapsed)
    logWait = logWait - (elapsed or 0)
    if logWait > 0 then return end
    logWait = LOG_EVERY
    readLog()
  end)
  logFrame:SetScript("OnHide", function()
    logMarker = nil
    logWait = 0
    if logCoin then logCoin:Hide() end
  end)
end

-- ---------------------------------------------------------------------------------------------------------------
-- The quest pages
-- ---------------------------------------------------------------------------------------------------------------

local lastTurnIn = nil

local function onDetail()
  local t = begin()
  hideMarker()
  if t.ctrl or not Automation.Enabled("autoQuests") then return end
  local accepts = wanted()
  local quest = dialogQuest(accepts)
  if quest and accepts[quest] then
    if AcceptQuest then AcceptQuest() end
    -- The page closes by itself on most clients; where it stays open on the quest, it is closed.
    local still = GetQuestID and GetQuestID()
    if still == quest and CloseQuest then CloseQuest() end
    return
  end
  if lastTurnIn and now() - lastTurnIn < Automation.FOLLOW_UP_SECONDS and CloseQuest then CloseQuest() end
end

local function onProgress()
  local t = begin()
  if t.ctrl or not Automation.Enabled("autoQuests") then return end
  local _, turnins = wanted()
  local quest = dialogQuest(turnins)
  if quest and turnins[quest] and CompleteQuest and IsQuestCompletable and IsQuestCompletable() then CompleteQuest() end
end

local function onReward()
  local t = begin()
  hideMarker()
  local _, turnins = wanted()
  local quest = dialogQuest(turnins)
  local count = GetNumQuestChoices and GetNumQuestChoices() or 0
  local line = quest and turnins[quest]
  local auto = line and not t.ctrl and Automation.Enabled("autoQuests") and GetQuestReward
  if auto and count <= 1 then
    GetQuestReward(count)
    return
  end
  if auto and type(line.reward) == "number" and line.reward <= count and Automation.Enabled("guideRewards") then
    GetQuestReward(line.reward)
    return
  end
  if count < 2 then return end
  local best = bestChoice(count, function(i) return GetQuestItemLink and GetQuestItemLink("choice", i) end, function(i)
    return GetQuestItemInfo and select(3, GetQuestItemInfo("choice", i)) or 1
  end)
  if not best then return end
  if auto and Automation.Enabled("bestReward") then
    GetQuestReward(best)
  elseif Automation.Enabled("rewardMarker") then
    showMarker(quest, best)
  end
end

local function onShare(_, _, title)
  if not Automation.Enabled("autoQuests") then return end
  local accepts = wanted()
  if byTitle(accepts, title) and ConfirmAcceptQuest then
    ConfirmAcceptQuest()
    if StaticPopup_Hide then StaticPopup_Hide("QUEST_ACCEPT") end
  end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Flights and the bind
-- ---------------------------------------------------------------------------------------------------------------

-- The flight map slot of the first reachable node whose name holds the destination's name.
local function slotByName(node)
  local flight = Noir.Data.flights[node]
  local name = type(flight) == "table" and flight.name
  if type(name) ~= "string" or not (NumTaxiNodes and TaxiNodeName) then return nil end
  local short = string.match(name, "^([^,]+)") or name
  for i = 1, NumTaxiNodes() or 0 do
    local kind = TaxiNodeGetType and TaxiNodeGetType(i)
    local text = TaxiNodeName(i)
    if (kind == nil or kind == "REACHABLE") and type(text) == "string"
      and (string.find(text, name, 1, true) or string.find(text, short, 1, true)) then
      return i
    end
  end
  return nil
end

local function takeFlight(line)
  if not (TakeTaxiNode and State.taxiOpen) or State.OnTaxi() then return end
  if State.taxiNode ~= nil and State.taxiNode ~= line.from then return end
  local slot = State.taxiSlots[line.to] or slotByName(line.to)
  if slot then TakeTaxiNode(slot) end
end

local function onTaxi()
  local t = begin()
  if t.shift or not Automation.Enabled("flights") then return end
  local line = cardLine("fly")
  if line then Noir.After(Automation.FLIGHT_DELAY, function() takeFlight(line) end) end
end

local function onBinder()
  local t = begin()
  if t.shift or not Automation.Enabled("hearth") then return end
  if not cardLine("sethearth", function(l) return not otherNpc(l) end) then return end
  Noir.After(0, function()
    if ConfirmBinder then ConfirmBinder() end
    if StaticPopup_Hide then StaticPopup_Hide("CONFIRM_BINDER") end
  end)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Vendors
-- ---------------------------------------------------------------------------------------------------------------

local closing = nil -- { item, target } while waiting for the bags before closing the merchant

local function merchantIndex(item)
  for i = 1, GetMerchantNumItems and GetMerchantNumItems() or 0 do
    local id = GetMerchantItemID and GetMerchantItemID(i)
    if not id and GetMerchantItemLink then
      id = tonumber(string.match(GetMerchantItemLink(i) or "", "item:(%d+)"))
    end
    if id == item then return i end
  end
  return nil
end

local selling = nil -- { serial, copper, count } while grey items are being sold
local sellSerial = 0

local function merchantOpen()
  local merchant = State.merchant
  return merchant and merchant.opened and not merchant.closed
end

-- Closes the merchant once the bags hold what a vendor line bought, unless grey items are still being sold.
local function closeIfBought()
  if not closing or selling or not merchantOpen() then return end
  if State.ItemCount(closing.item) >= closing.target then
    closing = nil
    if CloseMerchant then CloseMerchant() end
  end
end

-- Items a collect line on the cards still needs (not done): never sold.
local function collected()
  local keep = {}
  eachCardLine(function(line, entry)
    if line.kind == "collect" and type(line.item) == "number" and entry.state ~= "done" then keep[line.item] = true end
  end)
  return keep
end

local function useSlot(bag, slot)
  if C_Container and C_Container.UseContainerItem then
    C_Container.UseContainerItem(bag, slot)
  elseif UseContainerItem then
    UseContainerItem(bag, slot)
  end
end

local function money(copper)
  local text = Noir.Text
  if text and text.Money then return text.Money(copper) end
  return tostring(copper) .. "c"
end

local function stopSelling()
  local done = selling
  selling = nil
  if done and done.count > 0 then
    Noir.Print("Sold " .. done.count .. (done.count == 1 and " grey item" or " grey items") .. " for " .. money(done.copper) .. ".")
  end
  closeIfBought()
end

-- One bag slot of grey items a tick; the slot is taken from a fresh read of the bags, so only quality 0 is sold.
local function sellTick(serial)
  if not selling or selling.serial ~= serial then return end
  if not merchantOpen() then return stopSelling() end
  local keep = collected()
  local list = State.JunkSlots()
  local pick
  for i = 1, #list do
    local slot = list[i]
    if not (slot.item and keep[slot.item]) and not (selling.tried[slot.bag .. ":" .. slot.slot]) then
      pick = slot
      break
    end
  end
  if not pick then return stopSelling() end
  selling.tried[pick.bag .. ":" .. pick.slot] = true
  useSlot(pick.bag, pick.slot)
  selling.count = selling.count + pick.count
  selling.copper = selling.copper + pick.value
  Noir.After(Automation.SELL_EVERY, function() sellTick(serial) end)
end

local function startSelling(conversation)
  selling = nil
  if not Automation.Enabled("sellJunk") or conversation.any then return end
  if not ((C_Container and C_Container.UseContainerItem) or UseContainerItem) then return end
  local _, stacks = State.Junk()
  if stacks == 0 then return end
  sellSerial = sellSerial + 1
  selling = { serial = sellSerial, copper = 0, count = 0, tried = {} }
  local serial = sellSerial
  Noir.After(Automation.SELL_EVERY, function() sellTick(serial) end)
end

local onMerchantBuy

local function onMerchant()
  local conversation = begin()
  closing = nil
  startSelling(conversation)
  onMerchantBuy()
end

onMerchantBuy = function()
  if not Automation.Enabled("buy") or not BuyMerchantItem then return end
  local line = cardLine("vendor", function(l) return type(l.buy) == "table" and not otherNpc(l) end)
  if not line then return end
  local item, count = line.buy.item, line.buy.count
  local collected = false
  eachCardLine(function(other, entry)
    if other.kind == "collect" and other.item == item and entry.state == "done" then collected = true end
  end)
  if collected then return end
  local have = State.ItemCount(item)
  local need = count - have
  local index = merchantIndex(item)
  if need <= 0 or not index then return end
  -- An item may be sold in bundles (GetMerchantItemInfo's quantity): whole bundles are bought, the count rounded
  -- up, and a limited stock counts bundles (docs/ENGINE-NOTES.md #91).
  local _, _, _, bundle, stock = GetMerchantItemInfo(index)
  if type(bundle) ~= "number" or bundle < 1 then bundle = 1 end
  bundle = math.floor(bundle)
  need = math.ceil(need / bundle) * bundle
  if type(stock) == "number" and stock >= 0 and stock * bundle < need then need = stock * bundle end
  local stack = GetMerchantItemMaxStack and GetMerchantItemMaxStack(index) or 1
  if type(stack) ~= "number" or stack < 1 then stack = 1 end
  stack = math.max(bundle, math.floor(stack / bundle) * bundle)
  if need <= 0 then return end
  closing = { item = item, target = have + need }
  while need > 0 do
    local amount = math.min(need, stack)
    BuyMerchantItem(index, amount)
    need = need - amount
  end
end

local function bagsChanged()
  if not closing then return end
  Noir.After(0, closeIfBought)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Trainers
-- ---------------------------------------------------------------------------------------------------------------

local training = nil -- { untilAt, serial }
local trainSerial = 0

-- Whether a train line on a card names this service.
local function named(name, rank)
  local found = false
  eachCardLine(function(line, entry)
    if line.kind ~= "train" or not open(entry) then return end
    if line.spell and GetSpellInfo and GetSpellInfo(line.spell) == name then found = true end
    if line.skill and line.rank and Lines.ProfessionName(line.skill) == name then
      for r = 1, line.rank do
        if RANK_NAMES[r] == rank then found = true end
      end
    end
    return found
  end)
  return found
end

local function petTrainer()
  if not GetTrainerServiceSkillLine then return false end
  for i = 1, GetNumTrainerServices() or 0 do
    if PET_SKILL_LINES[GetTrainerServiceSkillLine(i) or ""] then return true end
  end
  return false
end

local function buyOne()
  if not (GetNumTrainerServices and GetTrainerServiceInfo and BuyTrainerService) or petTrainer() then return end
  local tradeskill = IsTradeskillTrainer and IsTradeskillTrainer() and true or false
  local best, bestLevel
  for i = 1, GetNumTrainerServices() or 0 do
    local name, rank, kind = GetTrainerServiceInfo(i)
    if kind == "available" and (not tradeskill or named(name, rank)) then
      local level = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i) or 0
      if not best or (level or 0) < bestLevel then best, bestLevel = i, level or 0 end
    end
  end
  if best then BuyTrainerService(best) end
end

local function trainTick(serial)
  if not training or training.serial ~= serial then return end
  if now() > training.untilAt + 1e-6 then
    training = nil
    return
  end
  buyOne()
  Noir.After(Automation.TRAIN_EVERY, function() trainTick(serial) end)
end

local function onTrainer()
  begin()
  training = nil
  if not Automation.Enabled("train") then return end
  trainSerial = trainSerial + 1
  training = { untilAt = now() + Automation.TRAIN_SECONDS, serial = trainSerial }
  local serial = trainSerial
  Noir.After(Automation.TRAIN_EVERY, function() trainTick(serial) end)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Reading
-- ---------------------------------------------------------------------------------------------------------------

local function copyOf(t)
  if not t then return nil end
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

function Automation.Read()
  local log = nil
  if logMarker and logFrame and logFrame:IsVisible() then log = copyOf(logMarker) end
  local shownMarker = nil
  if marker then
    shownMarker = copyOf(marker)
    shownMarker.shown = markerFrame ~= nil and markerFrame:IsVisible() and marker.shown or false
  end
  return {
    marker = shownMarker, logMarker = log, training = training ~= nil, selling = selling ~= nil,
    talk = talk and { ctrl = talk.ctrl, shift = talk.shift, any = talk.any } or nil,
  }
end

-- ---------------------------------------------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------------------------------------------

for _, event in ipairs({ "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE" }) do
  Noir.On(event, function() questOpen = true end) -- registered first: runs before the handlers below
end
Noir.On("GOSSIP_SHOW", function() atList(gossipQuests, gossipOptions, true) end)
Noir.On("QUEST_GREETING", function() atList(greetingQuests, nil) end)
Noir.On("QUEST_DETAIL", onDetail)
Noir.On("QUEST_PROGRESS", onProgress)
Noir.On("QUEST_COMPLETE", onReward)
Noir.On("QUEST_ACCEPT_CONFIRM", onShare)
Noir.On("TAXIMAP_OPENED", onTaxi)
Noir.On("CONFIRM_BINDER", onBinder)
Noir.On("MERCHANT_SHOW", onMerchant)
Noir.On("TRAINER_SHOW", onTrainer)
Noir.On("BAG_UPDATE_DELAYED", bagsChanged)

Noir.On("QUEST_TURNED_IN", function() lastTurnIn = now() end)
Noir.On("QUEST_FINISHED", function()
  questOpen = false
  hideMarker()
  finish()
end)
Noir.On("GOSSIP_CLOSED", gossipClosed)
Noir.On("TAXIMAP_CLOSED", finish)
Noir.On("MERCHANT_CLOSED", function()
  closing = nil
  if selling then stopSelling() end
  finish()
end)
Noir.On("TRAINER_CLOSED", function()
  training = nil
  finish()
end)
-- Keep every hand-in line that reaches a card eligible, whether or not the player is at an NPC then.
Noir.On("NOIR_STEP", function() wanted() end)
Noir.On("NOIR_INIT", watchLog)
