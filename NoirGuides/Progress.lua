-- Noir Guides, GPLv3. See LICENSE.
-- Progress v3 (spec 2.4, 2.5, 3.3 to 3.7): the place in the current section, what is on screen (the current step,
-- open reminders and detours), when the place moves, and where a character that joins mid-way stands. It follows
-- the game by itself: no command is needed for anything here.
--
--   Progress.PASS_SECONDS = 0.1     one update pass; the place moves at most one step per pass
--   Progress.ARRIVAL_SECONDS = 0.33 position checks while a place with a radius (or a move) is on screen
--   Progress.SIGNAL_QUIET = 1       NOIR_STEP_DONE / NOIR_OBJECTIVE_DONE only this long after the last place change
--   Progress.LOOKAHEAD_TEXT = 8     steps after the current one whose text the step list keeps up to date
--   Progress.BEHIND_STEPS = 3       quest steps a saved place must be behind the quest log before it moves ahead
--
--   Progress.Load(sectionId [, how]) (on NOIR_SECTION) the saved place by step id, else by n while the section's
--                                   signature is unchanged, else placement inside the section (Progress.Locate);
--                                   a section reached by playing on (how "next", or "step" for a step's load) with no
--                                   saved place starts at its first step instead (spec 2.4.4: done steps pass by
--                                   themselves)
--   Progress.Cards() -> { { step, index, kind, lines = { { line, state, ticked, text, icon, counter, why, index } } } }
--                                   kind "reminder", "detour", "current"; reminders and detours first in step order,
--                                   then the current step. `index` of a line is its index in step.lines (0 for the
--                                   synthetic grind line a current step under its minLevel gets first)
--   Progress.Place() -> sectionId, index, count, step
--   Progress.Steps() -> the section's steps for this character (Guide.Steps)
--   Progress.StepState(index) -> "done" | "current" | "reminder" | "ahead" | "behind" | "hidden"
--   Progress.Tick(index, lineIndex, on)   tick or untick a line of a step on screen (saved in places[section].ticks)
--   Progress.Jump(index, how)       how "list", "skip", "back": go to any step at once, no confirmation (why "jump")
--   Progress.Skip()                 tick every active line of the current step
--   Progress.Back()                 jump to the nearest earlier step that is not done
--   Progress.Lookahead() -> step or nil   the step after the current one (for the automation)
--   Progress.Locate(chain) -> sectionId, index, score, left
--                                   placement from quest history over the sections of `chain`, in order: a quest in
--                                   the log +4 (at its accept line only), handed in +2, missing -1, a known flight point +2 (an unknown one 0),
--                                   each quest once at its first line; the place is just after the highest score,
--                                   latest on ties (on that step while one of its quest lines is still to do). Steps and sections the character outlevels (above maxLevel while
--                                   "outlevel" is on) and steps under their minLevel are not counted as missing.
--                                   Score 0 means no evidence. left: the quests before the place counted missing
--   Progress.Complete() -> boolean  the last section of the route is done
--   Progress.Refresh()              look at the game again (one pass)
--   Progress.Reached(index, lineIndex) -> boolean, Progress.MarkReached(index, lineIndex)
--                                   arrival at a place with a radius (lineIndex 0: the step's own place), kept
--                                   while the step is on screen
--
-- Events: NOIR_STEP (cards) whenever the cards change; NOIR_PLACE (section, index) when the place changes;
-- NOIR_LINE (section, step id, line index, state) when a line on screen changes state; NOIR_STEP_DONE (section,
-- step id) and NOIR_OBJECTIVE_DONE (section, step id, line index) only when more than SIGNAL_QUIET seconds passed
-- since the last place change.
--
-- Rules, in the order a pass applies them to the current step:
--   * a reminder step never becomes the place: the place moves on and it opens as a reminder card (when its
--     minLevel allows); it ends when the place passes its `ends` step or, when it has active lines, when all of them
--     are done (remembered in places[section].reminders);
--   * a step whose lines are all hidden is passed (no why); one of only passive lines is passed with why "done";
--   * a step above its maxLevel is passed while "outlevel" is on (why "outleveled");
--   * a skip condition that holds passes the step or jumps to its label (why "condition"), never while the addon is
--     hidden and, with "neverSkip" on, only when it is a gate ("notturnedin" on a quest an accept line of the step
--     requires: the game will not offer that accept, so the step would wait forever);
--   * a step whose active lines are all done, skipped or ticked completes, unless its `requires` label is on screen or
--     ahead, or it is under its minLevel (a synthetic grind line shows that). Done before it was ever shown: why
--     "done"; finished by a tick: why "tick";
--   * a movement step whose next work step is already done is passed (why "moot") unless the work left lies that way
--     or the player jumped to it; a movement step is also passed (why "moot") when a later move of its journey
--     (up to the next work step) goes to the zone the player already stands in.
-- An open turn-in shows earlier steps with its quest's open objectives as detour cards, and an open accept those with
-- open objectives or the hand-in of a quest it requires that is still in the log (not on a step the player jumped to). A "missing" objective or turn-in
-- line (skipIfMissing or not) waits when an earlier open line of its own step accepts
-- the quest; else it shows
-- the accept step of its quest as a detour card when an earlier step of the section accepts it; otherwise the line
-- is passed (why "cannot", one chat line). A line done while its step is on
-- screen stays done until the step is entered again; only unticking clears a tick. A line passed by a skip option
-- (skipIfMissing, skipIfIncomplete, ifDone, a profession gate) gets a why entry of kind "condition". When the place changes, steps no
-- longer on screen lose their latches and ticks. At the end of a section: a loop section wraps once; open reminders
-- with work left hold the place on the last step; else Guide.Next() (no cleanup prompt); without a next section the
-- route is complete: the place stays on the last step (saved as places[section].ended, so a relog keeps it). A step with `load` selects that section when it becomes current.
-- At login the saved step is made current and done steps pass one per pass; when Locate over the chain from the
-- current section lands at least BEHIND_STEPS quest steps after the saved place, the place moves there with one chat
-- line. It never moves backward on its own.
local Noir = Noir
local State, Guide, Lines, Why = Noir.State, Noir.Guide, Noir.Lines, Noir.Why

local Progress = {}
Noir.Progress = Progress

Progress.PASS_SECONDS = 0.1
Progress.ARRIVAL_SECONDS = 0.33
Progress.SIGNAL_QUIET = 1
Progress.LOOKAHEAD_TEXT = 8
Progress.BEHIND_STEPS = 3

local EPSILON = 1e-6
local QUEST_LINE = { accept = true, turnin = true, objective = true }
local MOVE_LINE = { ["goto"] = true, fly = true, transport = true, hearth = true }
local JUMP_TEXT = {
  list = "you went to it from the step list",
  skip = "you skipped ahead to it",
  back = "you went back to it",
}
local COMPLETE_TEXT = "You have reached the end of the route."

local current = nil     -- the section's id
local section = nil     -- the section's table
local steps = {}        -- Guide.Steps(current)
local index = 1         -- the place: an index into steps; #steps + 1 past the end
local saved = nil       -- NoirGuidesCharDB.guide.places[current]
local finished = false  -- the route is complete
local screen = {}       -- step id -> { since, latched = { [i] = { state, evidence } }, reached = { [place] = true },
                        --              open = seen incomplete as the current step, tried = { [quest] = true } }
local lineStates = {}   -- step id -> { [line index] = state } as last published
local detours = {}      -- step index -> true: detour cards of the last pass
local pinned = nil      -- id of the step the player jumped to: never passed as moot
local pastEnd = false   -- placement put the place past the last step: index is #steps, the end is still to handle
local looped = {}       -- section id -> true once a loop section wrapped in this session
local lastMove = nil    -- GetTime() of the last place change
local movedSinceLoad = false
local published = nil   -- signature of the cards last sent with NOIR_STEP
local generation = 0    -- raised by every Load, so a pass that loaded another section stops
local loginPending = false
local pendingSection = nil
local pendingHow = nil
local passDue = nil
local arrivalDue = false
local running = false

-- ---------------------------------------------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------------------------------------------

local function now()
  return GetTime()
end

local function level()
  return type(State.level) == "number" and State.level or 0
end

local function option(key)
  local options = Noir.Options
  if not (options and options.Get) then return nil end
  return options.Get(key)
end

local function outlevelOn()
  return option("outlevel") ~= false
end

local function levelOk(step)
  return not (type(step.minLevel) == "number" and level() < step.minLevel)
end

local function applies(line)
  return Lines.Applies(line.when)
end

local function labelIndex(label)
  if type(label) ~= "string" then return nil end
  for i = 1, #steps do
    if steps[i].label == label then return i end
  end
  return nil
end

local function indexOfId(list, id)
  for i = 1, #list do
    if list[i].id == id then return i end
  end
  return nil
end

-- A fingerprint of a section's steps: their ids in order.
local function signature(sec)
  local sum, modulus = 0, 2147483647
  for i = 1, #sec.steps do
    local id = tostring(sec.steps[i].id)
    for k = 1, string.len(id) do sum = (sum * 31 + string.byte(id, k)) % modulus end
    sum = (sum * 31 + 7) % modulus
  end
  return string.format("%d:%d", #sec.steps, sum)
end

local function words(line, step)
  local text = Noir.Text
  if text and text.Line then
    local w = text.Line(line, step)
    if type(w) == "table" then return w.text, w.icon end
  end
  return "", "note"
end

local function why(step, kind, text)
  Why.Add({
    section = current, step = step and step.id or nil, n = step and step.n or nil,
    kind = kind, text = text, label = step and Why.Describe(step) or nil,
  })
end

local function sameZone(a, b)
  if a == nil or b == nil then return false end
  if a == b then return true end
  local za, zb = Noir.Data.zones[a], Noir.Data.zones[b]
  return type(za) == "table" and type(zb) == "table" and za.uiMap ~= nil and za.uiMap == zb.uiMap
end

local function inZone(zone)
  return sameZone(State.zone, zone)
end

-- ---------------------------------------------------------------------------------------------------------------
-- What a step is, judged without its latches (for steps that are not on screen)
-- ---------------------------------------------------------------------------------------------------------------

local function isMove(step)
  local any = false
  for i = 1, #step.lines do
    local line = step.lines[i]
    if Lines.Active(line) and applies(line) then
      if not MOVE_LINE[line.kind] then return false end
      any = true
    end
  end
  return any
end

local function isWork(step)
  for i = 1, #step.lines do
    local line = step.lines[i]
    if Lines.Active(line) and applies(line) and not MOVE_LINE[line.kind] then return true end
  end
  return false
end

local function hasQuestLine(step)
  for i = 1, #step.lines do
    local line = step.lines[i]
    if QUEST_LINE[line.kind] and applies(line) then return true end
  end
  return false
end

-- Every active line is done or skipped now, as the game shows it (ticks of a step on screen count).
local function doneNow(step)
  local ticks = saved and saved.ticks and saved.ticks[step.id] or {}
  local ctx = { since = now(), ticks = ticks }
  for i = 1, #step.lines do
    local line = step.lines[i]
    local state = Lines.Check(line, step, ctx)
    if Lines.Active(line) and state ~= "hidden" and state ~= "done" and state ~= "skip" and not ticks[i] then
      return false
    end
  end
  return true
end

local function allHidden(step)
  for i = 1, #step.lines do
    if Lines.Check(step.lines[i], step, {}) ~= "hidden" then return false end
  end
  return true
end

-- ---------------------------------------------------------------------------------------------------------------
-- Reminders
-- ---------------------------------------------------------------------------------------------------------------

-- The first place at which reminder `r` is no longer open: just past its `ends` step ("next": the step after it).
-- With no end link (format 3 always writes one; a hand-edited route may not), spec 3.6: it ends at the first later
-- step that requires it, so that step is not held by it; else it stays open to the end of the section.
local function closesAt(r)
  local step = steps[r]
  local ends = step.reminder and step.reminder.ends
  if ends == "next" then return r + 2 end
  local at = labelIndex(ends)
  if at then return at + 1 end
  if step.label then
    for j = r + 1, #steps do
      if steps[j].requires == step.label then return j end
    end
  end
  return #steps + 1
end

-- Reminder steps the place has passed whose end has not been passed and that are not finished, in step order.
local function openReminders(shownOnly)
  local out = {}
  local done = saved and saved.reminders or {}
  for r = 1, math.min(index - 1, #steps) do
    local step = steps[r]
    if step.reminder and not done[step.id] and index < closesAt(r) and (not shownOnly or levelOk(step)) then
      out[#out + 1] = r
    end
  end
  return out
end

-- ---------------------------------------------------------------------------------------------------------------
-- Steps on screen: latches, ticks and arrival
-- ---------------------------------------------------------------------------------------------------------------

local function entry(step)
  local e = screen[step.id]
  if not e then
    e = { since = now(), latched = {}, reached = {}, tried = {} }
    screen[step.id] = e
  end
  return e
end

local function ticksOf(step, create)
  local all = saved and saved.ticks
  if type(all) ~= "table" then return nil end
  local t = all[step.id]
  if type(t) ~= "table" then
    if not create then return nil end
    t = {}
    all[step.id] = t
  end
  return t
end

local function onScreenIds()
  local set = {}
  local step = steps[index]
  if step then set[step.id] = true end
  local open = openReminders(true)
  for i = 1, #open do set[steps[open[i]].id] = true end
  return set
end

-- Forgets the latches, ticks and published states of steps that are no longer on screen (and of `also`, a step
-- entered again).
local function dropOffScreen(also)
  local keep = onScreenIds()
  if also then keep[also] = nil end
  for id in pairs(screen) do
    if not keep[id] then screen[id] = nil end
  end
  for id in pairs(lineStates) do
    if not keep[id] then lineStates[id] = nil end
  end
  local ticks = saved and saved.ticks
  if type(ticks) == "table" then
    for id in pairs(ticks) do
      if not keep[id] then ticks[id] = nil end
    end
  end
  detours = {}
end

-- ---------------------------------------------------------------------------------------------------------------
-- Judging a step on screen
-- ---------------------------------------------------------------------------------------------------------------

-- The first earlier step of the section that accepts `quest`.
local function acceptStepFor(quest, before)
  for j = 1, before - 1 do
    local step = steps[j]
    for i = 1, #step.lines do
      local line = step.lines[i]
      if line.kind == "accept" and line.quest == quest and applies(line) then return j end
    end
  end
  return nil
end

-- Earlier steps of the section (before `before`) with an objective line, or with `kinds` lines, of `quest` still to
-- do: they become detour cards of the current step.
local function openWorkFor(quest, before, kinds, into)
  for j = 1, before - 1 do
    local step = steps[j]
    for i = 1, #step.lines do
      local line = step.lines[i]
      if line.quest == quest and kinds[line.kind] and applies(line) and Lines.Check(line, step, {}) == "todo" then
        into[j] = true
        break
      end
    end
  end
end
local OBJECTIVES = { objective = true }
local OBJECTIVES_AND_TURNIN = { objective = true, turnin = true }

-- Whether a line before line `before` of the step still has to accept `quest` (its accept is open).
local function acceptedEarlierIn(step, quest, before)
  for k = 1, before - 1 do
    local line = step.lines[k]
    if line.kind == "accept" and line.quest == quest and applies(line) and Lines.Check(line, step, {}) == "todo" then
      return true
    end
  end
  return false
end

local function cardLine(line, step, i, state, evidence, counter, ticked)
  local text, icon = words(line, step)
  return { line = line, state = state, ticked = ticked and true or false, text = text, icon = icon,
    counter = counter, why = evidence, index = i }
end

-- Evaluates a step on screen. Returns its card lines and a summary { done, active, byTick, evidence, detours }.
-- As the current step, missing quest lines open detours or are passed as impossible.
local function evaluate(step, at, asCurrent)
  local e = entry(step)
  local ticks = ticksOf(step) or {}
  local out = {}
  local sum = { done = true, active = false, byTick = false, evidence = nil, detours = {} }
  if asCurrent and not levelOk(step) then
    local grind = { kind = "grind", level = step.minLevel, synthetic = true }
    local state, evidence, counter = Lines.Check(grind, step, { since = e.since })
    out[1] = cardLine(grind, step, 0, state, evidence, counter, false)
    sum.done, sum.active = false, true
  end
  local ctx = { since = e.since, ticks = ticks }
  for i = 1, #step.lines do
    local line = step.lines[i]
    local state, evidence, counter = Lines.Check(line, step, ctx)
    -- A skipIfMissing line whose quest an earlier open line of this step accepts is not missing: the quest is coming.
    if state == "skip" and line.skipIfMissing and line.quest and not State.HasQuest(line.quest)
      and acceptedEarlierIn(step, line.quest, i) then
      state, evidence = "missing", nil
    end
    if state ~= "hidden" then
      local active = Lines.Active(line)
      local held = e.latched[i]
      if held then
        state, evidence = held.state, held.evidence
      elseif active and line.kind ~= "manual" and (state == "done" or state == "skip") then
        e.latched[i] = { state = state, evidence = evidence }
        -- A skipIfMissing / skipIfIncomplete option or a profession gate passed the line: the game did not do it.
        if state == "skip" then
          why(step, "condition", string.format("line %d (%s) was passed: %s", i, (words(line, step)), tostring(evidence)))
        end
      end
      -- Work an open line waits for that lies behind the place (a joiner placed past it): shown as detours. A hand-in
      -- waits for its quest's objectives; an accept for the hand-in of a quest it requires that is still in the log.
      -- Not on a step the player jumped to: going to a step from the list is a manual skip (spec 3.5).
      if state == "todo" and asCurrent and pinned ~= step.id then
        if line.kind == "turnin" and State.HasQuest(line.quest) then
          openWorkFor(line.quest, at, OBJECTIVES, sum.detours)
        elseif line.kind == "accept" and type(line.requires) == "table" then
          for r = 1, #line.requires do
            if State.HasQuest(line.requires[r]) then openWorkFor(line.requires[r], at, OBJECTIVES_AND_TURNIN, sum.detours) end
          end
        end
      end
      if state == "missing" and asCurrent and acceptedEarlierIn(step, line.quest, i) then
        -- The step itself accepts the quest on an earlier line: the line waits for it (no detour, nothing passed).
        state = "missing"
      elseif state == "missing" and asCurrent then
        local j = acceptStepFor(line.quest, at)
        if j then
          sum.detours[j] = true
        else
          evidence = (Noir.Text and Noir.Text.QuestName and Noir.Text.QuestName(line.quest) or ("Quest " .. tostring(line.quest)))
            .. " is not in your quest log and nothing earlier in this section accepts it"
          e.latched[i] = { state = "skip", evidence = evidence }
          state = "skip"
          why(step, "cannot", evidence)
          Noir.Print(evidence .. "; that line was passed. /noir why lists it.")
        end
      end
      local ticked = ticks[i] == true
      if active then
        sum.active = true
        if state == "done" or state == "skip" then
          if ticked and (line.kind == "manual" or not e.latched[i]) then sum.byTick = true end
          sum.evidence = sum.evidence or evidence
        elseif ticked then
          state, evidence = "done", "ticked by hand"
          sum.byTick = true
        else
          sum.done = false
        end
      end
      out[#out + 1] = cardLine(line, step, i, state, evidence, counter, ticked)
    end
  end
  return out, sum
end

-- Whether the step's `requires` label is on screen or still ahead.
local function waiting(step, onScreen)
  local at = labelIndex(step.requires)
  if not at then return false end
  return at > index or onScreen[at] == true
end

-- ---------------------------------------------------------------------------------------------------------------
-- Movement steps whose purpose is gone
-- ---------------------------------------------------------------------------------------------------------------

local function firstMoveLine(step)
  for i = 1, #step.lines do
    local line = step.lines[i]
    if MOVE_LINE[line.kind] and Lines.Active(line) and applies(line) then return line end
  end
  return nil
end

local function destination(step)
  local line = firstMoveLine(step)
  if not line then return nil end
  if line.kind == "goto" then return line.at and line.at.zone end
  if line.kind == "fly" then
    local f = Noir.Data.flights[line.to]
    return type(f) == "table" and f.zone or nil
  end
  return line.to and line.to.zone
end

local function startZone(step)
  local line = firstMoveLine(step)
  if not line then return nil end
  if line.kind == "fly" then
    local f = Noir.Data.flights[line.from]
    if type(f) == "table" and f.zone then return f.zone end
    return step.at and step.at.zone
  end
  if line.kind == "transport" then return line.at and line.at.zone end
  return nil
end

local function placeOf(step)
  if step.at then return step.at end
  for i = 1, #step.lines do
    if step.lines[i].at then return step.lines[i].at end
  end
  return nil
end

-- A later move of the journey this move starts (the moves after it, up to the first work step still to do) that goes
-- to the zone the player already stands in, while this move goes elsewhere: the player is past this move on the way
-- (it was left behind by work that passed). Returns that step's index or nil.
local function pastOnJourney(step, i)
  local own = destination(step)
  if own and inZone(own) then return nil end
  for j = i + 1, #steps do
    local other = steps[j]
    if not other.reminder then
      if isWork(other) and not doneNow(other) then return nil end
      if isMove(other) then
        local zone = destination(other)
        if zone and inZone(zone) and not sameZone(zone, own) then return j end
      end
    end
  end
  return nil
end

local function nextWork(i)
  for j = i + 1, #steps do
    if not steps[j].reminder and isWork(steps[j]) then return j end
  end
  return nil
end

-- The 0.1.1 rule: a move still leads to the work left when the next open step is a flight or boat leaving from
-- the zone it goes to (and the player is not in that zone), or the next work step still to do lies in that zone and
-- the player is not there yet; or the journey it starts (it and the open moves after it, up to the next work step)
-- ends in the zone of the next work step still to do; or no work is left in the section after it and the next section
-- begins somewhere the player is not (leadsIntoNext).
local function leadsIntoNext(zone)
  local chain = current and Guide.Chain(current) or {}
  local nextId = chain[2]
  if not nextId then return false end
  local list = Guide.Steps(nextId)
  for j = 1, #list do
    local other = list[j]
    if not other.reminder and (isWork(other) or isMove(other)) then
      local open = false
      for k = 1, #other.lines do
        local line = other.lines[k]
        local state = Lines.Check(line, other, { since = now() })
        if Lines.Active(line) and state ~= "hidden" and state ~= "done" and state ~= "skip" then open = true; break end
      end
      if open then
        -- The first open step of the next section: a flight or boat leaves from where this move goes, or the step lies
        -- somewhere the player does not stand yet. Looser than the in-section rule on purpose (X1 review 2, finding 6):
        -- the next section often begins in a zone next to where the move goes (a boat to Wetlands, then a walk into
        -- Hillsbrad), and without a journey across sections a same-zone check would pass that move as moot.
        local from = isMove(other) and startZone(other)
        if from then return sameZone(from, zone) and not inZone(from) end
        local place = placeOf(other)
        return place ~= nil and not inZone(place.zone)
      end
    end
  end
  return false
end

local function stillLeads(step, i)
  local zone = destination(step)
  if not zone then return false end
  -- The journey this move starts: it and the open moves right after it, up to the first work step still to do (a
  -- work step already done in its middle passes by itself). It still leads when the next work step still to do lies
  -- where the journey ends (a boat, then a walk into the city, then a flight to the work left).
  local last = i
  for j = i + 1, #steps do
    local other = steps[j]
    if not other.reminder then
      if isWork(other) and not doneNow(other) then break end
      if isMove(other) and not doneNow(other) then last = j end
    end
  end
  if last > i then
    local ends = destination(steps[last])
    for j = last + 1, #steps do
      local other = steps[j]
      if not other.reminder and isWork(other) and not doneNow(other) then
        local place = placeOf(other)
        if ends and place and sameZone(place.zone, ends) and not inZone(place.zone) then return true end
        break
      end
    end
  end
  for j = i + 1, #steps do
    local other = steps[j]
    if not other.reminder and (isWork(other) or isMove(other)) and not doneNow(other) then
      if isMove(other) then
        local from = startZone(other)
        if from then return sameZone(from, zone) and not inZone(from) end
      end
      break
    end
  end
  for j = i + 1, #steps do
    local other = steps[j]
    if not other.reminder and isWork(other) and not doneNow(other) then
      local place = placeOf(other)
      return place ~= nil and sameZone(place.zone, zone) and not inZone(place.zone)
    end
  end
  -- No work left in the section after it: the move leads into the next section, unless that section begins where
  -- the player already stands.
  return leadsIntoNext(zone)
end

-- ---------------------------------------------------------------------------------------------------------------
-- The cards and what the current step asks for
-- ---------------------------------------------------------------------------------------------------------------

-- Builds the cards. Returns them; when the place should move, { to = index, kind = why kind or nil, text }; and the
-- number of reminders on screen that have work left (they hold the place at the end of the section, spec 2.4).
local function build()
  local cards, holds = {}, 0
  if finished or not current then return cards, nil, 0 end
  local onScreen, shownReminder = {}, {}
  local reminders = {}
  local open = openReminders(true)
  for k = 1, #open do
    local r = open[k]
    local step = steps[r]
    local lines, sum = evaluate(step, r, false)
    if sum.done and sum.active then
      -- Finished early (spec 3.6): remembered for the section.
      saved.reminders[step.id] = true
      screen[step.id], lineStates[step.id] = nil, nil
      if saved.ticks then saved.ticks[step.id] = nil end
    elseif #lines > 0 then
      -- A reminder of only passive lines ("keep an eye out for this rare") has nothing to finish: it lasts until
      -- its ends step is passed, and does not hold the end of the section.
      onScreen[r] = true
      shownReminder[r] = true
      if sum.active then holds = holds + 1 end
      reminders[#reminders + 1] = { step = step, index = r, kind = "reminder", lines = lines }
    end
  end
  local step = steps[index]
  local decision, currentCard = nil, nil
  detours = {}
  if step and pastEnd then
    -- Placement found the work of the whole section done (spec 2.4, 2.5): the end of the section, not this step.
    decision = { to = #steps + 1 }
  elseif step then
    if step.reminder then
      decision = { to = index + 1 }
    else
      local lines, sum = evaluate(step, index, true)
      currentCard = { step = step, index = index, kind = "current", lines = lines }
      for j in pairs(sum.detours) do
        detours[j] = true
        onScreen[j] = true
      end
      local e = entry(step)
      if #lines == 0 then
        decision = { to = index + 1 }
      elseif outlevelOn() and type(step.maxLevel) == "number" and level() > step.maxLevel then
        decision = { to = index + 1, kind = "outleveled",
          text = string.format("you are level %d and the step is for level %d and below", level(), step.maxLevel) }
      else
        local reason, jump
        -- With "neverSkip" on, only a gate still holds: an accept the game will not offer would otherwise wait forever.
        if option("shown") ~= false then reason, jump = Lines.Condition(step, option("neverSkip") == true) end
        if reason then
          local to = labelIndex(jump) or (index + 1)
          decision = { to = to, kind = "condition", text = reason }
        elseif sum.done and not waiting(step, onScreen) then
          if not sum.active then
            decision = { to = index + 1, kind = "done",
              text = "it has only notes and markers on it, nothing to do" }
          elseif sum.byTick then
            decision = { to = index + 1, kind = "tick", text = "you ticked its last open line", signal = true }
          elseif not e.open then
            decision = { to = index + 1, kind = "done",
              text = "already done when the guide came to it: " .. tostring(sum.evidence or "the game shows it done") }
          else
            decision = { to = index + 1, signal = true }
          end
        elseif isMove(step) and pinned ~= step.id then
          local j = nextWork(index)
          local k = pastOnJourney(step, index)
          if j and doneNow(steps[j]) and not stillLeads(step, index) then
            decision = { to = index + 1, kind = "moot",
              text = string.format("the step it leads to (step %s, %s) is already done", tostring(steps[j].n), Why.Describe(steps[j])) }
          elseif k then
            decision = { to = index + 1, kind = "moot",
              text = string.format("you already stand where a later move of the way (step %s, %s) goes", tostring(steps[k].n), Why.Describe(steps[k])) }
          end
        end
      end
      if not decision then e.open = true end
    end
  end
  -- Reminders and detours in step order, then the current step.
  for j in pairs(detours) do
    if steps[j] and not shownReminder[j] then
      local lines = evaluate(steps[j], j, false)
      reminders[#reminders + 1] = { step = steps[j], index = j, kind = "detour", lines = lines }
    end
  end
  table.sort(reminders, function(a, b) return a.index < b.index end)
  for k = 1, #reminders do cards[#cards + 1] = reminders[k] end
  if currentCard then cards[#cards + 1] = currentCard end
  return cards, decision, holds
end

local function cardsSignature(cards)
  local parts = {}
  for k = 1, #cards do
    local card = cards[k]
    local piece = card.kind .. ":" .. card.step.id
    for i = 1, #card.lines do
      local l = card.lines[i]
      local c = l.counter
      piece = piece .. "," .. l.index .. l.state .. (l.ticked and "t" or "") .. (c and (c.have .. "/" .. c.need) or "")
        .. tostring(l.text)
    end
    parts[k] = piece
  end
  return table.concat(parts, ";")
end

local function quiet()
  return lastMove == nil or now() - lastMove > Progress.SIGNAL_QUIET
end

-- Sends NOIR_LINE for lines that changed state, NOIR_OBJECTIVE_DONE for objectives just done, and NOIR_STEP when the
-- cards changed.
local function publish(cards)
  for k = 1, #cards do
    local card = cards[k]
    local known = lineStates[card.step.id]
    if not known then
      known = {}
      lineStates[card.step.id] = known
    end
    for i = 1, #card.lines do
      local l = card.lines[i]
      local before = known[l.index]
      if before ~= l.state then
        known[l.index] = l.state
        Noir.Fire("NOIR_LINE", current, card.step.id, l.index, l.state)
        if before ~= nil and l.state == "done" and l.line.kind == "objective" and quiet() then
          Noir.Fire("NOIR_OBJECTIVE_DONE", current, card.step.id, l.index)
        end
      end
    end
  end
  local sig = (finished and "complete|" or "") .. cardsSignature(cards)
  if sig ~= published then
    published = sig
    Noir.Fire("NOIR_STEP", cards)
  end
end

-- ---------------------------------------------------------------------------------------------------------------
-- The quest tracker
-- ---------------------------------------------------------------------------------------------------------------

local function logIndex(quest)
  local log = C_QuestLog
  if log and log.GetLogIndexForQuestID then
    local i = log.GetLogIndexForQuestID(quest)
    if type(i) == "number" and i > 0 then return i end
  end
  if log and log.GetNumQuestLogEntries and log.GetInfo then
    for i = 1, log.GetNumQuestLogEntries() or 0 do
      local info = log.GetInfo(i)
      if type(info) == "table" and info.questID == quest then return i end
    end
    return nil
  end
  if GetQuestLogIndexByID then
    local i = GetQuestLogIndexByID(quest)
    if type(i) == "number" and i > 0 then return i end
  end
  return nil
end

local function watch(quest)
  local max = MAX_WATCHABLE_QUESTS or 5
  if GetNumQuestWatches and (GetNumQuestWatches() or 0) >= max then return end
  if AddQuestWatch then
    local i = logIndex(quest)
    if not i or (IsQuestWatched and IsQuestWatched(i)) then return end
    AddQuestWatch(i)
  elseif C_QuestLog and C_QuestLog.AddQuestWatch then
    C_QuestLog.AddQuestWatch(quest)
  end
end

-- Each quest of the current step is put on the tracker once while the step is current (the player may untrack it).
local function track()
  local step = steps[index]
  if not step or step.reminder then return end
  local e = entry(step)
  for i = 1, #step.lines do
    local quest = step.lines[i].quest
    if quest and not e.tried[quest] and applies(step.lines[i]) and State.HasQuest(quest) then
      e.tried[quest] = true
      watch(quest)
    end
  end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Passes
-- ---------------------------------------------------------------------------------------------------------------

local pass -- defined below

local function schedule(delay)
  local at = now() + delay
  if passDue and passDue <= at + EPSILON then return end
  passDue = at
  Noir.After(delay, function()
    if passDue and now() + EPSILON >= passDue then
      passDue = nil
      pass()
    end
  end)
end

local function save()
  if not saved then return end
  local step = steps[index]
  saved.step = step and step.id or nil
  saved.n = step and step.n or (#section.steps + 1)
  -- The place passed the last step and the route ended there (spec 2.4.5): kept on the last step, remembered.
  saved.ended = finished or nil
end

-- Whether a place on screen needs position checks: a place with a radius not reached, or a move line not done.
local function needsArrival(cards)
  for k = 1, #cards do
    local card = cards[k]
    local e = screen[card.step.id]
    local places = Lines.Places(card.step, e and e.reached or {}, { since = e and e.since or now() })
    for p = 1, #places do
      local place = places[p].at
      local r = place.r
      if type(r) == "number" and r > 0 then
        if e and Lines.Arrived(place) then e.reached[place] = true else return true end
      end
    end
    for i = 1, #card.lines do
      local l = card.lines[i]
      if MOVE_LINE[l.line.kind] and l.state ~= "done" and l.state ~= "skip" and Lines.Active(l.line) then return true end
    end
  end
  return false
end

local function arrivalCheck(cards)
  if arrivalDue or not needsArrival(cards) then return end
  arrivalDue = true
  Noir.After(Progress.ARRIVAL_SECONDS, function()
    arrivalDue = false
    pass()
  end)
end

local function finish()
  finished = true
  save()
  publish({})
  if movedSinceLoad then Noir.Print(COMPLETE_TEXT) end
end

-- The place has passed the last step of the section.
local function endOfSection()
  if section.loop and not looped[current] then
    looped[current] = true
    index = 1
    pastEnd = false
    save()
    Noir.Fire("NOIR_PLACE", current, index)
    return
  end
  if not Guide.Next() then finish() end
end

-- Moves the place to `to` and announces it. Past the last step the place stays on the last step (spec 2.4: the
-- window stays there while reminders hold it or when the route is complete) and the end of the section is handled.
-- Returns true when another section was loaded.
local function moveTo(to)
  local gen = generation
  local past = to > #steps
  local before = index
  index = past and #steps or to
  pastEnd = false
  if index < 1 then index = 1 end
  lastMove = now()
  movedSinceLoad = true
  if pinned and (not steps[index] or steps[index].id ~= pinned) then pinned = nil end
  dropOffScreen()
  save()
  if index ~= before or not past then Noir.Fire("NOIR_PLACE", current, index) end
  if past then
    endOfSection()
    return gen ~= generation
  end
  local step = steps[index]
  if step.load and Guide.Section(step.load) and step.load ~= current then
    Guide.Select(step.load, "step")
    return gen ~= generation
  end
  return false
end

local function passBody()
  if not current or finished then return end
  local gen = generation
  if #steps == 0 then
    -- No step of the section applies to this character: straight to its end, and the why-log says so.
    Why.Add({ section = current, kind = "section",
      text = "The section " .. tostring(Guide.Name(section)) .. " was passed: no step in it is for this character." })
    endOfSection()
    return
  end
  local cards, decision, holds = build()
  if decision then
    local step = steps[index]
    local hold = false
    -- Open reminders with work left hold the place on the last step (a loop section wraps first).
    if decision.to > #steps and holds > 0 and not (section.loop and not looped[current]) then hold = true end
    if not hold then
      if lastMove and now() - lastMove < Progress.PASS_SECONDS - EPSILON then
        publish(cards)
        schedule(Progress.PASS_SECONDS - (now() - lastMove))
        return
      end
      if decision.signal and quiet() then Noir.Fire("NOIR_STEP_DONE", current, step.id) end
      if decision.kind then why(step, decision.kind, decision.text) end
      if moveTo(decision.to) or gen ~= generation then return end
      if finished then return end
      cards = build()
      schedule(Progress.PASS_SECONDS)
    end
  end
  track()
  publish(cards)
  arrivalCheck(cards)
end

pass = function()
  if running then
    schedule(0)
    return
  end
  running = true
  local good, err = pcall(passBody)
  running = false
  if not good then Noir.ReportError(err) end
end

function Progress.Refresh()
  pass()
end

-- ---------------------------------------------------------------------------------------------------------------
-- Placement
-- ---------------------------------------------------------------------------------------------------------------

-- Content the character would not be shown or has outleveled: not evidence that work was left out.
local function notMissing(step, sec)
  if not levelOk(step) then return true end
  if outlevelOn() then
    if type(step.maxLevel) == "number" and level() > step.maxLevel then return true end
    if type(sec.maxLevel) == "number" and level() > sec.maxLevel then return true end
  end
  return false
end

local function locate(chain)
  local running_, best = 0, 0
  local bestSection, bestStep, bestPos = nil, 0, 0
  local counted, flights, missing = {}, {}, {}
  local order = {}
  local pos = 0
  for c = 1, #(chain or {}) do
    local sec = Guide.Section(chain[c])
    if sec then
      local list = Guide.Steps(sec.id)
      order[#order + 1] = { id = sec.id, steps = list }
      for i = 1, #list do
        local step = list[i]
        pos = pos + 1
        local exempt = notMissing(step, sec)
        for k = 1, #step.lines do
          local line = step.lines[k]
          if applies(line) then
            local evidence = nil
            if QUEST_LINE[line.kind] and line.quest and not counted[line.quest] then
              counted[line.quest] = true
              if State.HasQuest(line.quest) then
                -- In the log says where the quest was taken: only its accept line places the character. At an
                -- objective or hand-in of a quest taken before the counted sections it proves nothing.
                if line.kind == "accept" then evidence = 4 end
              elseif State.IsDone(line.quest) then
                evidence = 2
              elseif not exempt then
                running_ = running_ - 1
                missing[#missing + 1] = pos
              end
            elseif line.kind == "getflight" and line.node and not flights[line.node] then
              flights[line.node] = true
              -- The client tells which flight points are known only while a flight map is open: an unknown one
              -- is no evidence that the character has not been there.
              if State.KnowsFlight(line.node) then evidence = 2 end
            end
            if evidence then
              running_ = running_ + evidence
              if running_ >= best then best, bestSection, bestStep, bestPos = running_, #order, i, pos end
            end
          end
        end
      end
    end
  end
  if best <= 0 or not bestSection then
    return chain and chain[1] or nil, 1, 0, 0
  end
  local left = 0
  for k = 1, #missing do
    if missing[k] <= bestPos then left = left + 1 end
  end
  local found = order[bestSection]
  local id, at = found.id, bestStep + 1
  -- The step of the best evidence still has a quest line to do (one accept of a bundle taken, the others not): the
  -- place stays on it, so nothing on it is passed without a word.
  local bestOne = found.steps[bestStep]
  for k = 1, #bestOne.lines do
    local line = bestOne.lines[k]
    if QUEST_LINE[line.kind] and applies(line) and Lines.Check(line, bestOne, {}) == "todo" then
      at = bestStep
      break
    end
  end
  if at > #found.steps and order[bestSection + 1] then id, at = order[bestSection + 1].id, 1 end
  return id, at, best, left
end
Progress.Locate = locate

-- A place on a reminder step moves on: a reminder never becomes the place.
local function settle(list, at)
  while list[at] and list[at].reminder do at = at + 1 end
  return at
end

-- Puts the place at `at` as placement found it. Past the last step the place waits on the last step and the next
-- pass handles the end of the section (the next section, open reminders, or the end of the route), as moveTo does.
local function placeAt(at)
  if #steps > 0 and at > #steps then
    index, pastEnd = #steps, true
  else
    index, pastEnd = at, false
  end
end

-- The words for a place found by placement: its step number, or past the last step.
local function placeWords(target)
  if target then return "step " .. tostring(target.n) end
  return "past its last step"
end

-- At login: when the quest log shows the character well past the saved place, move there. True when another
-- section was loaded for it.
local function catchUpBehind()
  local chain = Guide.Chain(current)
  local id, at, score = locate(chain)
  if not id or score <= 0 then return false end
  local count, reached = 0, false
  for c = 1, #chain do
    local here = chain[c] == current
    local list = here and steps or Guide.Steps(chain[c])
    local from = here and index or 1
    if chain[c] == id then
      if here and at <= index then return false end
      for i = from, at - 1 do
        if list[i] and hasQuestLine(list[i]) then count = count + 1 end
      end
      reached = true
      break
    end
    for i = from, #list do
      if hasQuestLine(list[i]) then count = count + 1 end
    end
  end
  if not reached or count < Progress.BEHIND_STEPS then return false end
  local sec = Guide.Section(id)
  local list = id == current and steps or Guide.Steps(id)
  at = settle(list, at)
  local target = list[at]
  local text = string.format("Moved ahead to %s %s: your quest log shows the work before it done.",
    tostring(Guide.Name(sec)), placeWords(target))
  Noir.Print(text)
  Why.Add({ section = id, step = target and target.id or nil, n = target and target.n or nil, kind = "place", text = text })
  if id == current then
    placeAt(at)
    lastMove = now()
    dropOffScreen()
    save()
    Noir.Fire("NOIR_PLACE", current, index)
    return false
  end
  local places = Noir.Table(Noir.Table(Noir.char, "guide"), "places")
  places[id] = {
    step = target and target.id or nil, n = target and target.n or (#sec.steps + 1), sig = signature(sec),
    reminders = {}, ticks = {},
  }
  Guide.Select(id, "auto")
  return true
end

-- ---------------------------------------------------------------------------------------------------------------
-- Loading a section
-- ---------------------------------------------------------------------------------------------------------------

-- How a section was selected when the character got there by playing on: no placement inside it.
local PLAYED_ON = { ["next"] = true, step = true }

function Progress.Load(sectionId, how)
  if not State.ready then
    pendingSection, pendingHow = sectionId, how
    return
  end
  pendingSection, pendingHow = nil, nil
  local sec = Guide.Section(sectionId)
  if not sec or not Noir.char then return end
  generation = generation + 1
  current, section = sec.id, sec
  steps = Guide.Steps(sec.id)
  screen, lineStates, detours = {}, {}, {}
  pinned, finished, published, movedSinceLoad, pastEnd = nil, false, nil, false, false
  local places = Noir.Table(Noir.Table(Noir.char, "guide"), "places")
  local place = places[sec.id]
  if type(place) ~= "table" then place = nil end
  local sig = signature(sec)
  local at
  if place then
    if type(place.step) == "string" then at = indexOfId(steps, place.step) end
    if not at and place.sig == sig and type(place.n) == "number" then
      at = #steps + 1
      for i = 1, #steps do
        if steps[i].n >= place.n then
          at = i
          break
        end
      end
    end
    if not at and place.sig ~= nil then
      Why.Add({ section = sec.id, kind = "route",
        text = "The section " .. sec.id .. " changed since your place in it was saved; the place was found again from your quest log." })
    end
  end
  -- The route ended on this section's last step (saved by finish; 0.2 betas saved n = #steps + 1 instead).
  local ended = false
  if at and #steps > 0 and at >= #steps and (place.ended == true or at > #steps) then
    at, ended = #steps, true
  end
  local fresh = at == nil
  saved = place or {}
  places[sec.id] = saved
  saved.sig = sig
  if fresh or type(saved.reminders) ~= "table" then saved.reminders = {} end
  if fresh or type(saved.ticks) ~= "table" then saved.ticks = {} end
  if fresh and PLAYED_ON[how] then
    at = settle(steps, 1)
  elseif fresh then
    local _, found, score = locate({ sec.id })
    at = settle(steps, found or 1)
    if score > 0 then
      local target = steps[at]
      local text = string.format("Found your place in %s from your quest log and the quests you have handed in: %s.",
        tostring(Guide.Name(sec)), placeWords(target))
      Why.Add({ section = sec.id, step = target and target.id or nil, n = target and target.n or nil, kind = "place", text = text })
      Noir.Print(text)
    end
  end
  placeAt(at)
  lastMove = now()
  local login = loginPending
  loginPending = false
  if ended and #Guide.Chain(sec.id) <= 1 then
    -- Still the end of the route: the window stays on the last step and says so; nothing is printed again.
    finished = true
    save()
    Noir.Fire("NOIR_PLACE", current, index)
    publish({})
    return
  end
  save()
  Noir.Fire("NOIR_PLACE", current, index)
  if login and not fresh and catchUpBehind() then return end
  running = false
  pass()
end

-- ---------------------------------------------------------------------------------------------------------------
-- Reading the place
-- ---------------------------------------------------------------------------------------------------------------

function Progress.Cards()
  if finished or not current then return {} end
  local cards = build()
  return cards
end

function Progress.Place()
  return current, index, #steps, steps[index]
end

function Progress.Steps()
  return steps
end

function Progress.Complete()
  return finished
end

function Progress.Lookahead()
  if finished then return nil end
  return steps[index + 1]
end

function Progress.StepState(i)
  local step = steps[i]
  if not step then return nil end
  if allHidden(step) then return "hidden" end
  if i == index and not finished and not pastEnd then return "current" end
  if detours[i] then return "reminder" end
  local open = openReminders(true)
  for k = 1, #open do
    if open[k] == i then return "reminder" end
  end
  if i < index or finished or (pastEnd and i == index) then
    if step.reminder and saved and saved.reminders[step.id] then return "done" end
    return doneNow(step) and "done" or "behind"
  end
  return "ahead"
end

local function placeOfLine(step, lineIndex)
  if lineIndex == 0 then return step.at end
  local line = step.lines[lineIndex]
  return line and line.at
end

function Progress.Reached(i, lineIndex)
  local step = steps[i]
  local e = step and screen[step.id]
  local place = step and placeOfLine(step, lineIndex or 0)
  return (e and place and e.reached[place]) == true
end

function Progress.MarkReached(i, lineIndex)
  local step = steps[i]
  local place = step and placeOfLine(step, lineIndex or 0)
  if not place then return false end
  entry(step).reached[place] = true
  return true
end

-- ---------------------------------------------------------------------------------------------------------------
-- What the player does by hand
-- ---------------------------------------------------------------------------------------------------------------

local function isOnScreen(i)
  if i == index and not pastEnd then return true end
  if detours[i] then return true end
  local open = openReminders(true)
  for k = 1, #open do
    if open[k] == i then return true end
  end
  return false
end

function Progress.Tick(i, lineIndex, on)
  local step = steps[i]
  if not (step and step.lines[lineIndex] and saved) or not isOnScreen(i) then return false end
  local ticks = ticksOf(step, true)
  ticks[lineIndex] = on and true or nil
  if not on and next(ticks) == nil then saved.ticks[step.id] = nil end
  pass()
  return true
end

function Progress.Jump(i, how)
  if not current or type(i) ~= "number" or not steps[i] then return false end
  local step = steps[i]
  finished = false
  index, pastEnd = i, false
  pinned = step.id
  lastMove = now()
  movedSinceLoad = true
  dropOffScreen(step.id)
  save()
  why(step, "jump", JUMP_TEXT[how] or JUMP_TEXT.list)
  Noir.Fire("NOIR_PLACE", current, index)
  if step.load and Guide.Section(step.load) and step.load ~= current then
    Guide.Select(step.load, "step")
    return true
  end
  local cards = build()
  publish(cards)
  schedule(Progress.PASS_SECONDS)
  return true
end

function Progress.Skip()
  local step = steps[index]
  if finished or not step then return false end
  local ticks = ticksOf(step, true)
  for i = 1, #step.lines do
    local line = step.lines[i]
    if Lines.Active(line) and Lines.Check(line, step, {}) ~= "hidden" then ticks[i] = true end
  end
  pass()
  return true
end

function Progress.Back()
  for j = finished and #steps or (index - 1), 1, -1 do
    local step = steps[j]
    if not step.reminder and not allHidden(step) and not doneNow(step) then return Progress.Jump(j, "back") end
  end
  return false
end

-- ---------------------------------------------------------------------------------------------------------------
-- Commands (extras: the window's menu and the step list do the same with the mouse)
-- ---------------------------------------------------------------------------------------------------------------

Noir.Command("step", "the current step", function()
  if not current then
    Noir.Print("No section is loaded.")
    return
  end
  if finished then
    Noir.Print(COMPLETE_TEXT)
    return
  end
  local step = steps[index]
  Noir.Print(string.format("%s, step %d of %d: %s", tostring(Guide.Name(section)), index, #steps,
    step and Why.Describe(step) or "past the last step"))
end)
Noir.Command("skip", "tick every line of the current step (the why-log keeps it; /noir back returns)", function()
  if not Progress.Skip() then Noir.Print("There is no step to skip.") end
end)
Noir.Command("back", "go back to the nearest earlier step that is not done", function()
  if not Progress.Back() then Noir.Print("There is nothing to go back to: every earlier step is done.") end
end)

-- ---------------------------------------------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------------------------------------------

Noir.On("NOIR_LOGIN", function()
  loginPending = true
end)
Noir.On("NOIR_SECTION", function(_, id, how)
  Progress.Load(id, how)
end)
Noir.On("NOIR_READY", function()
  if pendingSection then Progress.Load(pendingSection, pendingHow) end
end)
Noir.On("NOIR_STATE", function()
  pass()
end)
Noir.On("NOIR_OPTION", function(_, key)
  if key == "shown" or key == "neverSkip" or key == "outlevel" then pass() end
end)
for _, event in ipairs({
  "PLAYER_XP_UPDATE", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "TAXIMAP_OPENED", "TAXIMAP_CLOSED",
  "UI_INFO_MESSAGE", "MERCHANT_CLOSED", "TRAINER_CLOSED", "UNIT_SPELLCAST_SUCCEEDED", "BAG_UPDATE_DELAYED",
  "LEARNED_SPELL_IN_TAB", "SPELLS_CHANGED", "HEARTHSTONE_BOUND",
}) do
  Noir.On(event, function() pass() end)
end
