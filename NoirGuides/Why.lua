-- Noir Guides, GPLv3. See LICENSE.
-- Why (v2): the log behind the engine's rule that a step is never skipped silently. Whenever the place moves past a
-- step, or a line completes, without the game confirming it in front of the player, the reason is recorded here. The
-- step list shows a step's latest entry in its tooltip (Why.ForStep) and /noir why prints the last 20.
--
--   Why.Add(entry) -> entry          entry = { section, step = step id, n, kind, text [, label] }; section, step and
--                                    n may be nil for a note about the route as a whole. The character's level is
--                                    added. Fires NOIR_WHY with the stored entry.
--   Why.ForStep(sectionId, stepId) -> the newest entry for that step, or nil
--   Why.List()                       the entries, oldest first (the saved table itself: read, do not change)
--   Why.Lines([count])               the last `count` entries (default 20) as text lines, oldest first
--   Why.Words(kind) -> words         what a kind means, in a few words ("already done")
--   Why.Describe(step) -> label      a short label for a format 3 step: the words of its first line
--   Why.KINDS                        kind -> words, below
--
-- The log is kept per character in NoirGuidesCharDB.why, at most 100 entries.
local Noir = Noir

local Why = {}
Noir.Why = Why

local MAX_KEPT = 100
local SHOWN = 20

Why.KINDS = {
  done = "already done",          -- the game showed the step done when the place came to it
  moot = "no longer needed",      -- a movement step whose next task is already done
  cannot = "cannot be done",      -- its quest is not in the log and nothing earlier in the section accepts it
  condition = "skip condition",   -- one of the step's skip conditions held
  outleveled = "above its level", -- the character is above the step's maximum level
  deferred = "saved for later",   -- under its level: the place moved on to work it can do now; it comes back at the level
  tick = "ticked by hand",        -- the player ticked its last open line (or used skip)
  jump = "moved by hand",         -- the player went to another step
  place = "place found",          -- the place was worked out from the quest log
  section = "section changed",    -- the section was chosen again
  route = "route changed",        -- the route file changed and the place was found again
}

local entries = {} -- replaced by the saved table at NOIR_INIT

function Why.Words(kind)
  return Why.KINDS[kind] or tostring(kind)
end

-- A short label for a step: the words of its first line that is shown, from UI/Text.lua (looked up when called).
function Why.Describe(step)
  if type(step) ~= "table" then return "" end
  local text, lines = Noir.Text, Noir.Lines
  local list = type(step.lines) == "table" and step.lines or {}
  if text and text.Line then
    for i = 1, #list do
      local hidden = lines and lines.Check and lines.Check(list[i], step, {}) == "hidden"
      if not hidden then
        local words = text.Line(list[i], step)
        if type(words) == "table" and type(words.text) == "string" and words.text ~= "" then return words.text end
      end
    end
  end
  return tostring(step.id or "")
end

local function optional(value, kind)
  if type(value) == kind then return value end
  return nil
end

function Why.Add(entry)
  if type(entry) ~= "table" then entry = {} end
  local stored = {
    section = optional(entry.section, "string"),
    step = optional(entry.step, "string"),
    n = optional(entry.n, "number"),
    kind = tostring(entry.kind),
    text = tostring(entry.text),
    label = optional(entry.label, "string"),
    level = Noir.State and Noir.State.level or nil,
  }
  entries[#entries + 1] = stored
  while #entries > MAX_KEPT do table.remove(entries, 1) end
  Noir.Fire("NOIR_WHY", stored)
  return stored
end

function Why.ForStep(sectionId, stepId)
  for i = #entries, 1, -1 do
    local e = entries[i]
    if e.step == stepId and e.section == sectionId then return e end
  end
  return nil
end

function Why.List()
  return entries
end

local function line(entry)
  local reason = Why.Words(entry.kind) .. ": " .. entry.text
  if entry.n or entry.step then
    local where = entry.n and ("step " .. entry.n) or ("step " .. entry.step)
    if entry.section then where = entry.section .. " " .. where end
    if entry.label and entry.label ~= "" then where = where .. " (" .. entry.label .. ")" end
    return "  " .. where .. ": " .. reason
  end
  return "  " .. reason
end

function Why.Lines(count)
  count = count or SHOWN
  local lines = {}
  local first = #entries - count + 1
  if first < 1 then first = 1 end
  for i = first, #entries do lines[#lines + 1] = line(entries[i]) end
  return lines
end

-- Keeps the entries of a saved log that are still usable.
local function restore(saved)
  local kept = {}
  if type(saved) ~= "table" then return kept end
  for i = 1, #saved do
    local e = saved[i]
    if type(e) == "table" and type(e.kind) == "string" and type(e.text) == "string"
      and (e.n == nil or type(e.n) == "number") and (e.label == nil or type(e.label) == "string")
      and (e.step == nil or type(e.step) == "string") and (e.section == nil or type(e.section) == "string") then
      kept[#kept + 1] = e
    end
  end
  while #kept > MAX_KEPT do table.remove(kept, 1) end
  return kept
end

Noir.On("NOIR_INIT", function()
  entries = restore(Noir.char.why)
  Noir.char.why = entries
end)

Noir.Command("why", "why the guide moved past steps: the last " .. SHOWN .. " reasons", function()
  local lines = Why.Lines(SHOWN)
  if #lines == 0 then
    Noir.Print("Nothing has been passed or skipped: every step so far was done as the guide showed it.")
    return
  end
  if #entries > #lines then
    Noir.Print("The last " .. #lines .. " of " .. #entries .. " steps the guide moved past, oldest first:")
  else
    Noir.Print(#lines .. " step(s) the guide moved past, oldest first:")
  end
  for i = 1, #lines do Noir.Print(lines[i]) end
end)
