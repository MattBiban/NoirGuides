# Engine notes

What the engine assumes about the WoW Forever client, how it is tested outside the game, and where the test setup differs from the game. Each engine task adds its own section. Everything marked **unverified** has to be confirmed in the game; the list feeds `docs/INGAME-CHECKLIST.md`.

## Running the Lua tests

```
cd tools
npm install        # once: fengari (the Lua VM) and luaparse (the Lua 5.1 parser), both dev dependencies
npm run test:lua   # lint, then every tools/test-lua/*.lua, twice (see "pairs order")
npm test           # the Node tests, including tools/test/harness.test.js for the test tooling itself
node harness/run.js state   # only the test files whose name contains "state"
```

`npm run test:lua` does three things:

1. **Lint** (`tools/harness/lint.js`) over every Lua file under `NoirGuides/`: Lua 5.1 syntax, the license header on line 1, no 5.2+ string escapes, no library function 5.1 lacks, none of the calls the project forbids (macro writes, the combat log, `setfenv`/`getfenv`, `load`, `require`).
2. **Tests** (`tools/test-lua/*.lua`) against the mock client (`tools/harness/wow.lua`), which loads the addon's files in toc order.
3. The same tests a **second time with `pairs` reversed**.

A test fails when an assertion fails, and also when the addon raised a Lua error anywhere (event handler, timer, slash command) or made a forbidden call, even if every assertion held. A test that expects an error takes it with `client:takeErrors()`.

### Writing a test

```lua
use("tools/test-lua/sample/helper.lua")          -- sample(opts): the real engine with the sample data and routes

test("accepting the quest puts it in the state", function()
  local c = sample({ race = "Undead", class = "ROGUE", level = 1 }):login()
  c:acceptQuest(364)
  eq(c.G.Noir.State.HasQuest(364), true)
end)
```

`c.G` is the addon's global table. The player's actions are methods on the client (`acceptQuest`, `progressQuest`, `completeObjectives`, `turnInQuest`, `abandonQuest`, `setLevel`, `gainXP`, `moveTo`, `openTaxi`, `closeTaxi`, `discoverFlight`, `startFlight`, `landFlight`, `bindHearth`, `useHearth`, `setProfession`, `enterCombat`, `leaveCombat`, `collapseHeader`, `slash`, `advance`, `fire`, `logout`, `relog`); each changes the fake server state and fires the events the client fires, in order. The options of `Client.new` are listed above it in `wow.lua`. Later tasks extend the mock in place: widget methods go on `Client.Frame`, new API functions into `Client:buildGlobals`, new events into the `EVENTS` list.

The sample route (`tools/test-lua/sample/horde-undead.lua`) is hand-written format 2: 12 steps, every action once, one step for rogues only and one with a minimum level.

## The test VM is Lua 5.3, the game is Lua 5.1

No Lua interpreter is installed on the build machine, so the tests run in **fengari 0.1.5** (MIT license, GPL-compatible; a Lua 5.3 VM written in JavaScript). There is no maintained Lua 5.1 VM on npm. **luaparse 0.3.1** (MIT) parses the addon as Lua 5.1 for the lint. Both are development tools: nothing of them ships in the addon.

How the difference is contained:

| Lua 5.3 has, Lua 5.1 does not | Contained by |
|---|---|
| `goto`, `//`, `&`, `\|`, `~`, `<<`, `>>`, `<const>` | lint: the file must parse as Lua 5.1 |
| string escapes `\x`, `\z`, `\u{}` | lint |
| `table.unpack`, `table.pack`, `table.move`, `math.type`, `math.tointeger`, `string.pack`, `utf8`, `rawlen`, `load` with a string | absent from the addon's globals (`env.lua`), and lint |
| `xpcall(f, handler, args...)` | the addon's `xpcall` raises an error when given extra arguments |
| floats print as `5.0` | the addon's `tostring`, `print`, `format` and `strjoin` print numbers as 5.1 does (`%.14g`) |
| `%d` rejects a number with a fraction | the addon's `format` truncates, as 5.1 does |

What the addon has that plain 5.3 lacks, provided by `env.lua`: `unpack`, `loadstring`, `table.getn`, `table.maxn`, `math.pow`, `math.log10`, `math.mod`, and the game's aliases (`format`, `strsplit`, `strtrim`, `strjoin`, `tinsert`, `tremove`, `wipe`, `tContains`, `floor`, `bit`, `date`, `time`, ...). The addon gets no `io`, `os`, `debug`, `require` or `package`.

**Differences that remain.** Code that depends on one of these can pass the tests and fail in the game, or the reverse. The engine must not depend on them:

1. **Number to string by `..`.** `10 / 2 .. ""` is `"5"` in the game and `"5.0"` in the VM; the VM's concatenation cannot be replaced. Whole numbers that were never divided are fine in both. Rule: a number that came out of a division or `math.sqrt` goes into text through `string.format`, never through `..`.
2. **`setfenv`/`getfenv`** exist in the game and cannot be emulated; the lint forbids them.
3. **Order of `pairs`.** Unspecified in both and different in practice. The runner plays every test twice, the second time with `pairs` visiting keys in the opposite order, so code that needs one particular order fails one of the runs. `next` is not reversed.
4. **`%.Nf` on exact ties.** `format("%.1f", 2.25)` is `"2.2"` in the game (C rounds the binary value) and `"2.3"` in the VM. Only values exactly halfway are affected.
5. **Integers.** The VM has 64-bit integers next to floats: `2^53 + 1` and integer overflow behave differently from 5.1's doubles. Nothing in the engine goes near those sizes; race masks, the only large numbers in the project, are not used in the addon (one route file per race).
6. **Stricter in the VM** (an error in the tests, fine in the game): `x % 0` on whole numbers, `table.insert` with a position out of range, `string.rep` with a negative count. A failure of this kind is a reason to fix the code, not the test.
7. **Metamethods the VM honors and 5.1 ignores:** `__pairs`, `__ipairs`, `__len` on tables, `__gc` on tables, and `ipairs` respecting `__index`. The engine must not define them.
8. **Patterns:** `%z` exists only in 5.1, `%g` only in 5.3; neither is used. `"\0"` inside a pattern works only in 5.3.
9. **`coroutine`** differences (yield across pcall works in 5.3 only). The engine does not use coroutines.
10. **Error messages** differ in wording ("attempt to index a nil value (field 'x')" against 5.1's "attempt to index field 'x' (a nil value)"). The engine never parses an error message.

## E1: Core, State, Routes

### Load order and globals

`NoirGuides.toc` loads `Core.lua`, `State.lua`, `Routes.lua`, then the generated `Data/*.lua`, then `Routes/*.lua`. The addon creates exactly these globals: `Noir`, `NoirGuidesDB`, `NoirGuidesCharDB`, `SLASH_NOIR1` (plus its `SlashCmdList.NOIR` entry); a test fails on any other.

The toc lists `Data\Names.lua`, `Data\Zones.lua` and `Data\Flights.lua`, which the planner generates. `Core.lua` creates the six `Noir.Data` tables empty, so the engine runs without those files; `tools/test-lua/addon.lua` allows exactly these three to be missing and fails on any other listed file that does not exist.

### What other modules build on

- `Noir.On(event, fn)`, `Noir.Off`, `Noir.Fire("NOIR_...")`: one frame, handlers in registration order, each in `pcall` with errors sent to `geterrorhandler()`. Returns `false` for an event this client does not have.
- `Noir.After(seconds, fn)`, `Noir.Command(name, help, fn)`, `Noir.Print`, `Noir.Problem` (shown by `/noir problems`), `Noir.Table(parent, key)`.
- `Noir.db` (account) and `Noir.char` (character), ready at `NOIR_INIT`; `NOIR_LOGIN` follows once.
- `Noir.State`: see the header of `State.lua`. It fires `NOIR_STATE` with the part that changed, and `NOIR_READY` once the quest log has been read. **Before `NOIR_READY` the quest log is empty and must not be trusted**: fast-forwarding a route has to wait for it.
- `Noir.Routes.Current()` gives the player's steps filtered by class. A step's minimum level (`when.level`) is not filtered there, because the level changes: whoever walks the route calls `Routes.Applies(step, class, level)` when it reaches the step. Every step has `n`, its position in the route file, the same for every class; saved progress and the why-log should refer to steps by `n`.
- A route that fails validation is refused as a whole and reported (`Routes.rejected`, `/noir problems`). Until the planner emits format 2, all ten shipped route files are refused with "it is in format 1".

### Decisions

- **The quest log is never touched.** The engine does not select entries or expand headers. Quests under a collapsed header are not listed by the client, so `State.logHidden` is set and `State.Quest(id)` finds such a quest by ID (`C_QuestLog.IsOnQuest`, `C_QuestLog.GetQuestObjectives`).
- **`complete` is the client's flag only.** `State.Quest(id).complete` is true when the client says the quest is ready to hand in. A quest without objectives may never get that flag on the old API, so "ready to hand in" must not be derived from it for such quests; a turn-in step is done when the quest is handed in.
- **Flight points are remembered** in `NoirGuidesCharDB.flights`, because the client only tells which are known while the flight map is open. A node is never forgotten.
- **The hearthstone's place** is recorded when `HEARTHSTONE_BOUND` arrives (the player stands at the innkeeper). A bind made while the addon was not running keeps the name and has no position.
- **Positions are rounded** to 0.01 map percent, the precision of the route files.
- **`C_SkillInfo`** is named in the plan as one way to read professions. Its functions are not in any documentation at hand, so the engine does not call it; it reads `GetProfessions`/`GetProfessionInfo` (skill line ID is the 7th return), or `C_TradeSkillUI.GetProfessionInfoBySkillLineID`. If Forever has neither, `/noir problems` says so and the profession plan needs the right call added here.

### Unverified assumptions about the Forever client

The mock client models each of these both ways where a test option exists (in brackets), so the engine works either way; the rest need a look in the game.

| # | Assumption | If it is wrong |
|---|---|---|
| 1 | `UnitRace("player")` returns the race ID as third value: 95 High Order, 96 Windshaper (from the client's ChrRaces table). Both have the file name `Skyborne`. [`raceId = false`] | The engine falls back to the file name plus the faction. If the file name differs too, `/noir problems` shows "Unknown race" with what the client returned. |
| 2 | The quest log API is either the old global one (`GetNumQuestLogEntries`, `GetQuestLogTitle` with the quest ID as 8th return) or the newer `C_QuestLog.GetInfo`. [`api`] | "no quest log API the addon knows" in `/noir problems`. |
| 3 | `QUEST_ACCEPTED` carries the quest ID as its last argument; `QUEST_TURNED_IN` as its first; `QUEST_REMOVED` exists. | The log is still re-read on `QUEST_LOG_UPDATE`; only the "handed in this moment" shortcut is lost. |
| 4 | `C_QuestLog.IsOnQuest`, `C_QuestLog.GetQuestObjectives`, `C_QuestLog.IsQuestFlaggedCompleted` exist. [`without`] | Objectives are parsed from the old API's text; quests under a collapsed header are not seen until the header is opened (`State.logHidden` says so). |
| 5 | `GetQuestsCompleted()` or `C_QuestLog.GetAllCompletedQuestIDs()` returns the quests done before the addon was installed. | `State.IsDone` still asks the client per quest. |
| 6 | During `PLAYER_LEVEL_UP` the first argument is the new level (and `UnitLevel` may still show the old one). [`levelLag`] | The level is corrected at the next `PLAYER_XP_UPDATE`. |
| 7 | The flight map: `TAXIMAP_OPENED`, then either `C_TaxiMap.GetAllTaxiNodes` (node IDs; states Current and Reachable mean known) or `NumTaxiNodes`/`TaxiNodeName`/`TaxiNodeGetType` (names; `CURRENT`, `REACHABLE`, `DISTANT` mean known). [`taxiIds`] | With names only, a name must equal the client's TaxiNodes name in `Data/Flights.lua`; names that do not match are kept in `State.unknownTaxiNames` for the diagnostics. Neutral towns have one point per faction under one name (Booty Bay is 18 and 19, Gadgetzan 39 and 40): only the player's faction's points (`factions` in `Data/Flights.lua`) are matched, by name and by a discovery message. |
| 8 | Discovering a flight point sends `UI_INFO_MESSAGE` with the global string `ERR_NEWTAXIPATH`. | The node is learned when the flight map opens, which happens on the same click. |
| 9 | `HEARTHSTONE_BOUND` exists and `GetBindLocation()` returns the inn's place name. [`withoutEvents`] | A changed bind name is noticed at the next zone event, without a position. |
| 10 | `GetProfessions`/`GetProfessionInfo` exist and return the skill line ID. [`professionApi`] | See `C_SkillInfo` above. |
| 11 | `C_Map.GetBestMapForUnit`, `C_Map.GetPlayerMapPosition`, `C_Map.GetMapInfo` exist, and a cave's or building's map has the zone map as an ancestor. [`without`] | No position: the arrow and "reached the place" checks cannot work; `/noir problems` says so. |
| 12 | The client skips a file the toc lists that does not exist (it does on every known build). | Only matters before the planner has written `Data/*.lua`. |
| 13 | `xpcall` passes no extra arguments (plain 5.1). The engine never passes any. | Nothing. |
| 14 | `C_Timer.After` exists. [`without`] | `Noir.After` falls back to an `OnUpdate` clock. |
| 15 | Zone IDs in routes are AreaTable IDs and `Data/Zones.lua` maps each to its uiMap. | `State.zone` stays nil and `State.Position()` returns map coordinates without a zone. |

`/noir state` prints what the engine currently believes (race, class, level, position, quest counts, flight points, hearthstone, professions) and is the quickest way to check most of this table in the game.

## E2: Progress, Automation, the why-log

`NoirGuides.toc` loads `Why.lua`, `Progress.lua` and `Automation.lua` after `Routes.lua`. They add no global. Their saved data: `NoirGuidesCharDB.why` (the log), `NoirGuidesCharDB.progress[routeId]` (the place in each route) and `NoirGuidesDB.options.auto` (the automation switches, per account).

### What other modules build on

- `Noir.Progress.Current()` returns the step to show, the route's place (an index into this character's steps) and the number of steps; `nil` when the route is finished, there is no route, or the quest log has not arrived.
- `Noir.Progress.Info()` returns `{ route, ready, finished, step, index, count, pointer, detour, note }`. `note` is a sentence for the player about the current step (a failed quest, a flight that is not offered, a hearthstone bound elsewhere, no position); the window should show it. `detour` is true when `step` is an earlier step shown in place of `pointer`.
- `Noir.Progress.Upcoming(count)` gives the next steps still to do, for the window's rack.
- `NOIR_STEP` (step, index, count) fires when the step to show or its note changes. `NOIR_WHY` (entry) fires for each new log entry.
- `Noir.Why.Describe(step)` is the log's short label for a step ("accept The Mindless Ones"). It is not the window's text; `UI/Text.lua` builds that.
- `Noir.Progress.Near(point, radius)`: true, false, or nil where the client gives no position.
- Commands: `/noir why`, `/noir skip`, `/noir back`, `/noir reset`, `/noir step`, `/noir auto [name|all on|off]`.

### When a step is done

Only the game's state completes a step:

| Action | Done when |
|---|---|
| `accept` | the quest is in the log, or was handed in |
| `objective` | the quest's objectives are complete (the client's flag, or no objective left open), or the quest was handed in |
| `turnin` | the quest was handed in |
| `getflight` | the flight point is known |
| `fly` | the character stands within 8 map percent of the destination's place in `Data/Flights.lua`; when the data has no place for it, when the character has landed after taking off during the step |
| `transport` | the character is in the destination's zone (within 10 map percent of `to` when both ends are in one zone) |
| `travel` | the character is within 5 map percent of `at`, or anywhere in its zone when `at` is the placeholder 0, 0 |
| `sethearth` | the hearthstone was bound within 8 map percent of `at` |
| `hearth` | the character is within 10 map percent of `to` |
| `grind` | the level is reached |

Position steps are never completed while the character is on a flight. Walking inside a zone fires no event, so while a position step is current the engine looks again once a second (`Noir.After`), and not otherwise.

### When the route moves past a step

The route's place only moves forward, past a step that is done. Completing the step that is shown is the normal case and is not logged. Everything else is, and `/noir why` prints the last 20 entries (100 are kept):

| Kind | Meaning |
|---|---|
| `done` | the step was already done when the route came to it: out-of-order play, catching up at login, the fast-forward of a first login |
| `moot` | a movement step (travel, transport, fly, hearth) whose next task is already done, unless it is still the way on: the next step still to do is a flight or boat leaving from the zone it leads to (and the character is not at that start), or a walk on the continent it leads to while the character is on another (`continent` in `Data/Zones.lua`), or the next task still to do lies in the zone it leads to and the character is not there yet |
| `notpart` | the step's `when.level` is above the character's level when the route reaches it. Format 2 says such a step is not part of the character's route, so it is passed and not counted as a skip; the entry is there so the player can see it happened |
| `cannot` | a quest step whose quest is not in the log and that the route cannot get there (no earlier accept step, the accept step was skipped, or it needs a higher level). Also said in chat |
| `skip`, `back`, `reset` | the player's own commands |
| `route` | the route's file changed since the place was saved; the place was worked out again |

Decisions:

- **An abandoned quest does not move the place back.** While the step at the route's place is an objective or turn-in whose quest is not in the log, the quest's accept step is shown in its stead (`Info().detour`), and the objective step while a turn-in's objectives are open again. Moving the place back would walk the player through every movement step in between a second time.
- **The fast-forward claims nothing it cannot see.** On a first login (no saved place), after `/noir reset` or after the route's file changed, the place starts at step 1 and passes what is done. It stops at the first step that is not: a quest the character never took, a flight point the addon has never seen on the flight map (the client only shows them while the map is open), a bind it cannot check. Only then is a bind step passed as moot when the step after it is done. A character far into a route it did not play with this addon will therefore stop early; a "start from here" choice belongs to the route menu (X2).
- **`/noir skip` is the only skip.** It marks the step in the saved place; the steps that depended on it (the skipped quest's objective and turn-in) are then passed as `cannot` with that reason. `/noir back` returns to the nearest earlier step that is not done (a skipped step, or a movement step passed as moot) and keeps it shown until it is done or skipped again.
- **The place is saved by step number `n`** together with a fingerprint of the route file. A fingerprint that does not match discards the place and the skips.
- **`when.level`** follows the format 2 text, not the design spec's older sentence ("the engine shows grind to level N"): the planner has the `grind` action for that.
- A step that is shown but blocked is not passed: its note says what is in the way. An accept step whose quest the NPC does not offer is reported once in chat (only where the client lists quests by ID, so the claim is certain) and stays.

### Automation

Each of `accept`, `turnin`, `gossip`, `flight`, `hearth` has a switch (default on); holding Shift suspends all. Only the step that Progress shows is automated.

- Quests are recognized by ID (`GetQuestID`, the gossip and greeting lists where they carry IDs). Where the client gives titles only, the title must equal the quest's title (from the quest log for a quest in it, else from `Data/Names.lua`) on exactly one entry; otherwise nothing is picked. On a client in another language, accepting from a title-only list therefore does nothing, which is the safe failure.
- The reward page is completed only when the quest offers no choice (`GetNumQuestChoices() == 0`, `GetQuestReward(0)` as the client's own button does). With one item to "choose" the page is still left to the player.
- A gossip line is picked by its kind (flight master, innkeeper), never by its text, only when exactly one line of that kind exists and the NPC is not certainly another one than the step's.
- The flight is taken 0.2 seconds after the flight map opened, if the map is still open, the map's current node is the step's `from` and the destination is offered.
- The bind question is answered with `ConfirmBinder()` and the client's popup is closed with `StaticPopup_Hide("CONFIRM_BINDER")`; the popup is not changed in any way.

### The mock client's NPC model

`world.npcs[id] = { offers = { quest IDs }, ends = { quest IDs }, taxi = node, binder = "inn name", options = { { type, text } }, greeting = bool, alwaysGossip = bool }`. `client:talkTo(id [, def])` opens what the game opens: a single gossip line or a single quest directly, otherwise the gossip list (or the quest greeting). `client:closeNpc()`, `client:chooseOption(i)`, `client:callsTo("AcceptQuest")` (the calls the addon made), `client.rewards`, `client.shift`. Options `gossipApi` (`global`, `info`, `info-index`), `gossipStride`, `greetingIds`, `oldGuid` and `afterLoad` select the API shapes below. A quest definition may carry `choices` (number of reward choices), `after` (the quest that must be done first; offered at once after handing that one in) and `locked`.

### Unverified assumptions about the Forever client (continued)

| # | Assumption | If it is wrong |
|---|---|---|
| 16 | Gossip is read through `C_GossipInfo` (`GetAvailableQuests`, `GetActiveQuests`, `GetOptions`, `Select...`) or the older globals (`GetGossipAvailableQuests`, `GetNumGossipAvailableQuests`, `SelectGossipAvailableQuest`, the same for active quests, `GetGossipOptions`, `SelectGossipOption`). [`gossipApi`] | No gossip automation; the player clicks. |
| 17 | When `C_GossipInfo` entries carry `questID`, `SelectAvailableQuest`/`SelectActiveQuest` take that ID; when they carry none, they take the position in the list. Likewise `SelectOption` takes `gossipOptionID` when entries have one, else the position. [`info`, `info-index`] | The wrong entry or none is opened. The quest dialogs still check the quest ID before accepting or completing, so no wrong quest is accepted; the player closes the dialog. Switch off with `/noir auto accept off`. |
| 18 | The old `GetGossipAvailableQuests()` returns the same number of values for every quest, the title first; `GetGossipActiveQuests()` has "is complete" as the fourth value when it returns at least four per quest. [`gossipStride`] | A list that cannot be split evenly is ignored. |
| 19 | Gossip lines have a kind: the string `taxi` or `binder` from `GetGossipOptions`/`type`, or the icon file IDs 132057 (taxi) and 132052 (binder), or an icon path containing `TaxiGossipIcon`/`BinderGossipIcon`. | The line is not picked; a flight master or innkeeper with a single line opens directly anyway. |
| 20 | `UnitGUID("npc")` has the form `Creature-0-...-<npc ID>-...`. [`oldGuid`] | The NPC is "unknown": gossip lines are picked by kind alone and "does not offer" is never reported. |
| 21 | `QUEST_DETAIL`, `QUEST_PROGRESS`, `QUEST_COMPLETE`, `QUEST_GREETING`, `GOSSIP_SHOW` exist; `GetQuestID()` returns the dialog's quest (else `GetTitleText()` is compared); `AcceptQuest`, `IsQuestCompletable`, `CompleteQuest`, `GetNumQuestChoices`, `GetQuestReward` behave as in Classic. [`without`] | That automation does nothing. |
| 22 | The greeting window: `GetNumAvailableQuests`, `GetAvailableTitle`, `GetAvailableQuestInfo` (quest ID as fifth value), `GetNumActiveQuests`, `GetActiveTitle` (title, is complete), `GetActiveQuestID`, `SelectAvailableQuest`, `SelectActiveQuest`. [`greetingIds`] | Titles are used; see above. |
| 23 | `QUEST_TURNED_IN` arrives before the `QUEST_DETAIL` of a follow-up quest the NPC offers at once. | The follow-up is not auto-accepted (the current step is still the turn-in at that moment); the player presses Accept. |
| 24 | `TakeTaxiNode(slot)` may be called from a timer shortly after `TAXIMAP_OPENED`, with the slot from `C_TaxiMap` (`slotIndex`) or the index of `TaxiNodeName`. | No flight is taken; the player clicks the node. |
| 25 | `CONFIRM_BINDER` fires when the innkeeper asks; `ConfirmBinder()` answers yes; `StaticPopup_Hide` exists. | The popup stays for the player. |
| 26 | `UnitOnTaxi("player")` is true during a flight and false by `PLAYER_CONTROL_GAINED` or within a second of it. | A fly step completes up to a second late (the position clock). |
| 27 | `IsShiftKeyDown()` exists. | Shift does not suspend; the switches still work. |
| 28 | Map percent distances are comparable to the radii above on every zone map. A very large zone makes 5 percent a long way, a city makes it short. | A travel step completes early or needs the player to walk onto the spot; `/noir skip` passes it. |

## E3: Window, Arrow, Map

`NoirGuides.toc` loads `UI\Theme.lua`, `UI\Text.lua`, `UI\Window.lua`, `UI\Arrow.lua` and `UI\Map.lua` after `Automation.lua`, in that order (each uses the ones before it). They add no global: no frame has a name. Their saved data, all for the account: `NoirGuidesDB.options.window` (`x`, `y`, `scale`, `locked`, `hidden`), `NoirGuidesDB.options.arrow` (`x`, `y`, `off`) and `NoirGuidesDB.options.map` (`off`). Values of the wrong type are dropped when read.

`DESIGN.md` (repository root) is the authority for colors, type sizes, measures and textures. `tools/test-lua/theme.lua` reads its tables and fails when `UI/Theme.lua` differs; `tools/test/textures.test.js` fails when a file in `NoirGuides/Textures/` is not byte for byte what `tools/gen_textures.js` draws (`npm run textures`).

### The port rule: nothing was ported

The plan asks for `DESIGN.md` and the textures generator to be ported from the fork under the port rule. Neither file meets it, so neither was opened, and both were written new:

| Fork file | `git log --follow --format='%h %an %ad'` in the fork | Rule (a): added after the initial import commit | Rule (b): no text of the other addon |
|---|---|---|---|
| `DESIGN.md` | `95b4d2c` 2026-11-10 (a later change), `ccf0aaf` 2026-11-08 (added) | No: `ccf0aaf` is the fork's first commit, the import itself | No: a count of lines matching the other addon's name or prefix gives 6 |
| `tools/gen_noir_textures.js` | `ccf0aaf` 2026-11-08 (added) | No: same commit | Yes: the same count gives 0 |

Every file that existed in the fork at its first commit fails (a) in the same way, whoever wrote it: the history cannot tell the owner's files from the imported ones. The only things done to the two files were the history query and a count of matching lines (to check (b)); their contents were not read. The fork's texture and font files were not opened either.

What that means for the result:

- The name Strip Bay and its three parts (lit strip, rack, level rail) are from this repository's design spec. Every color, size, measure and shape in `DESIGN.md`, `UI/Theme.lua` and `tools/gen_textures.js` is new and is **not** the fork's design.
- If the owner confirms the two fork files as his own work (which the spec says they are), carrying his values over is a small change: the four tables in `DESIGN.md`, the token tables at the top of `UI/Theme.lua`, and the shapes in `tools/gen_textures.js`. The tests keep the three in step.

### What other modules build on

- `Noir.Theme`: `Color(name [, alpha])`, `Hex(name)`, `sizes`, `metrics`, `Texture(name)`, `Font(fontString, role)`, `SetText(fontString, text)`, `Paint(texture, name [, alpha])`, `Tint(texture, name [, alpha])`, `fontFile`. A menu or list built later should take its colors and fonts from here.
- `Noir.Text.Step(step)` gives `{ kicker, name, where, lines, line }`; `Text.Line(step)` the one-line form. `Text.QuestName`, `ZoneName`, `FlightName`, `NpcName`, `ItemName`, `ObjectName`, `Place`, `Distance`.
- `Noir.Window`: `Read()` returns what the font strings hold (`shown`, `kicker`, `name`, `where`, `lines`, `note`, `rack`, `level`, `count`, `fill`); the simulator and `/noir bug` can use it to see what the player sees. `SetShown`, `SetLocked`/`IsLocked`, `SetScale`/`GetScale`, `Center`, and `Movable`/`Place` for another frame that should be dragged and remembered the same way.
- `Noir.Arrow`: `Target(step)` (the place where a step is done, nil for a hearthstone step or a place known only by zone), `Solve(point)` (bearing, yards, method), `Project(point, uiMap)`, `Read()`, `SetEnabled`/`IsEnabled`.
- `Noir.Map`: `Read()` (the pins as drawn), `Refresh()`, `SetEnabled`/`IsEnabled`.
- `NOIR_UI` fires with `"lock"` or `"center"`.
- `Core.lua` now keeps the chat prefix in `Noir.prefix`; the theme sets it to the addon's name in the accent color.
- Commands: `/noir show`, `/noir hide`, `/noir lock`, `/noir unlock`, `/noir scale <0.5 to 2>`, `/noir center`, `/noir arrow [on|off]`, `/noir pins [on|off]`.

### Decisions

- **Fonts by file, never by object.** `Theme.Font` calls `SetFont` with `Theme.fontFile` (nil until the owner adds the font), then the client's `STANDARD_TEXT_FONT`, then `Fonts\FRIZQT__.TTF`. `SetFontObject` is not called anywhere. A font string that got no font is never given text (the client raises "Font not set"); `/noir problems` then says that no font could be loaded.
- **No templates, no backdrop.** The frames are plain `Frame`s with textures and font strings. `SetBackdrop` and `BackdropTemplate` differ between client builds and are not used. Solid colors use `SetColorTexture`, or a white texture with a vertex color where that call is missing.
- **The arrow is turned by texture coordinates** (the eight-value `SetTexCoord`), which every client version has; `SetRotation` is not used. The art therefore stays inside the circle that fits the texture.
- **Two ways to a direction.** World coordinates when the client has them (`UnitPosition` and `C_Map.GetWorldPosFromMapPos`), else positions on one map: the zone's when the player stands on the place's own map, the continent's otherwise (`C_Map.GetMapRectOnMap`). Yards then come from `C_Map.GetMapWorldSize`; without it the direction is still right (every map is 3 wide to 2 high) and the distance is left out. A place on another continent, a place known only by zone (0, 0), a zone missing from `Data/Zones.lua`, no position or no facing: the arrow is hidden.
- **The game's map frames are only read.** `WorldMapFrame` and `Minimap` are asked for their canvas, shown map, size and zoom, and get child frames of the addon's own. No method that changes them is called, no script is set on them, nothing is hooked (not even with `hooksecurefunc`); a change of the shown map is noticed by an `OnUpdate` on the addon's own layer, which runs only while the map is open. The frames inside them are created outside combat. Pins take no mouse input. The mock records a violation for any changing call on those frames, and every test fails on a violation.
- **Pins:** the current step and the next three steps still to do, steps at one place sharing a pin. On the minimap an out-of-range place keeps only the current step's pin, on the rim.
- **A place is kept in screen units** (the top left corner from the screen's bottom left), so scaling the window does not move its corner, and a place outside the screen is brought back inside. `SetUserPlaced` is not used (it needs a named frame).
- **Hidden means not drawn, not stopped.** `/noir hide` hides the window; the route keeps following the game, and the window is drawn again when shown.
- **English only.** All wording for steps is in `UI/Text.lua`, the window's own five strings in `UI/Window.lua`. Names come from the data or the client, so on another language's client the names are right wherever the client supplies them and the fixed words stay English.

### The mock client's interface model

- **Widgets** (`tools/harness/wow.lua`, "Widgets"): frames, textures and font strings with anchors, sizes, scale, visibility through parents, `OnShow`/`OnHide`/`OnUpdate`, mouse and drag. `client:drag(frame, dx, dy)` plays a drag; `client:regionsOf(frame)` lists what a frame draws. The mock is strict where the game is: text on a font string without a font is an error, `SetFont` with a file the client or the addon does not have returns false, a texture file of the addon that is not in the repository is an error, a size or offset that is not a number is an error, `SetFontObject` with anything but a named font object is a violation.
- **Guarded frames:** `WorldMapFrame` (with its canvas) and `Minimap` record a violation for every changing method. `client:openWorldMap(uiMap)`, `setWorldMap`, `closeWorldMap`, `client.minimapZoom`, `client.cvars.rotateMinimap`. Option `mapCanvas = "field"` removes `GetCanvas`/`GetMapID` (the canvas is then `ScrollContainer.Child`, the map `mapID`); option `fonts` sets which font files exist.
- **World geometry:** each default zone has a `rect` on its continent and each continent a `world` rectangle in yards, so `UnitPosition`, `C_Map.GetWorldPosFromMapPos`, `GetMapPosFromWorldPos`, `GetMapRectOnMap`, `GetMapWorldSize`, `GetAreaInfo`, `GetPlayerFacing` and `CreateVector2D` are consistent with each other. The numbers are made up (every map is 3 to 2). `client:face(radians)` turns the character.
- **Names by ID:** `C_QuestLog.GetQuestInfo` (classic API) or `GetTitleForQuestID` (modern), `GetItemInfo` for the items in `world.items`.
- `env.lua` gives the addon Lua 5.1's `math.atan2` and a one-argument `math.atan`.
- `Client:advance` now runs `OnUpdate` only for frames that are visible through all their parents, as the game does.
- **For the simulator** (`tools/harness/sim.lua`, `npm run sim`): option `xpToLevel` gives the game's experience table; `client:offerable(quest)` decides whether an NPC offers a quest from the definition's `minLevel`, `maxLevel`, `pre`, `preAny`, `exclusive`, `closed`; `AcceptQuest` with 20 quests in the log fails with the game's message.

### Unverified assumptions about the Forever client (continued)

| # | Assumption | If it is wrong |
|---|---|---|
| 29 | `STANDARD_TEXT_FONT` names the default font file, or `Fonts\FRIZQT__.TTF` exists. `FontString:SetFont(file, size, flags)` returns true on success, or nothing on an old client. [`fonts`, `without`] | No text in the window; `/noir problems` says no font could be loaded. |
| 30 | A frame created with `CreateFrame("Frame", nil, UIParent)` and no template can be moved with `StartMoving`/`StopMovingOrSizing` after `SetMovable(true)`, also in combat, and `GetLeft`/`GetTop` give its place in its own scale. | The window stays where it first was; `/noir center` restores that place. |
| 31 | `Texture:SetTexCoord` takes eight values (upper left, lower left, upper right, lower right) and samples outside 0 to 1 repeat the texture's clear edge. | The arrow is drawn wrong when turned. |
| 32 | `GetPlayerFacing()` returns radians, 0 facing north, growing counterclockwise; nil where the client hides it. [`without`] | The arrow turns the wrong way or is offset; it hides where the value is nil. |
| 33 | `UnitPosition("player")` returns the north coordinate first and the west coordinate second, then z and the instance ID, in the same yards and the same instance ID as `C_Map.GetWorldPosFromMapPos(uiMap, CreateVector2D(x, y))` returns (instance, vector with north in `x`, west in `y`). [`without`] | Direction and distance are wrong while both exist. Removing either makes the engine use the map method (#34). To check in game: stand north of a step's place; the arrow must point down the screen when facing north. |
| 34 | `C_Map.GetMapRectOnMap(uiMap, topMap)` returns minX, maxX, minY, maxY of a zone on its continent, and `C_Map.GetMapWorldSize(uiMap)` its width and height in yards. Every zone and continent map is 3 wide to 2 high. [`without`] | No arrow across zones without the world coordinates; no distance without the size. |
| 35 | `C_Map.GetMapPosFromWorldPos(instance, vector, uiMap)` returns the place on the given map (second value), also outside 0 to 1 when the place is not on it. [`without`] | Pins are missing on maps other than the place's own zone map. |
| 36 | The world map is `WorldMapFrame` with `GetCanvas()` (or `ScrollContainer.Child`) and `GetMapID()` (or `mapID`); a plain frame parented to the canvas is drawn over the map, moves and scales with it, and may be created from addon code without tainting the map. Frame level canvas + 100 is above the game's own pins. [`mapCanvas`, `without`] | No pins on the world map (`/noir problems` says so when there is no canvas), or pins under the game's pins. If opening the map in combat ever raises a blocked-action message, switch the pins off with `/noir pins off` and report it. |
| 37 | The minimap is `Minimap` with `GetZoom()` 0 to 5 showing 466 2/3, 400, 333 1/3, 266 2/3, 200 and 133 1/3 yards across outdoors; `GetCVar("rotateMinimap")` is `"1"` when it rotates. Indoors the minimap shows less ground, which the addon does not know. [`without`] | Minimap pins sit at the wrong distance (always in the right direction); indoors they sit too close to the middle. |
| 38 | `C_Map.GetAreaInfo(areaId)` returns an area's name; `C_QuestLog.GetQuestInfo(questId)` or `C_QuestLog.GetTitleForQuestID(questId)` a quest's title; `GetItemInfo(itemId)` an item's name once the client has seen the item. [`without`] | A name missing from the data shows as "Quest 364" or is left out. |
| 39 | Frames may be given extra fields (`pin.icon`, `frame.dragging`), as every Classic client allows. | A Lua error on the first pin; nothing else depends on it. |
| 40 | TGA files (uncompressed, 32-bit, sides a power of two, rows bottom to top) load as textures when named without an extension. | The arrow and the pins show as the client's missing-texture green; the window is not affected. |

## X2: Ports (Menu, Cleanup, Talents, Professions, Diagnostics)

`NoirGuides.toc` loads `UI\Panel.lua` after `UI\Map.lua`, then `Talents.lua`, `Professions.lua`, `Cleanup.lua`, `Diagnostics.lua` and `Menu.lua` (the menu reaches all the others), and after the route data the files `tools/gen_ports.js` writes: `Data\Talents.lua`, `Data\Professions.lua`, `Data\Cleanup.lua` (`npm run ports`; `tools/test/ports.test.js` fails when they are not current). They add no global and no named frame.

The port rule left nothing to port: every fork file that could have served failed rule (a) or rule (b). `docs/INDEPENDENCE-REVIEW.md` lists each fork file looked at, how far it was read and why it was not used. All five modules, the panel helper, the generator and its data were written new for this engine.

### What other modules build on

- `Noir.Panel`: `New(width)`, `Text(parent, role, color [, justify])`, `Row(parent, onClick)` (a mouse row with `text`, a tick box and `lit`), `Layout(frame)` (`:Text`, `:Row`, `:Gap`, `:Finish`), `RowText(row)`. The windows after the Strip Bay are built from these.
- `Noir.Talents`: `Spec()`, `Check()`, `Unspent()`, `Plan(count)` (`name`, `tree`, `rank`, `max`, `tab`, `index`, `learnable`, `why`), `Off()`, `Lines()`, `Print()`. Fires `NOIR_TALENTS`.
- `Noir.Professions`: `RANKS`, `Known()`, `Plan()` (`skillLine`, `name`, `kind`, `rank`, `max`, `action` = learn, raise, train, wait or max, `next`, `text`), `SetPlanned`/`IsPlanned`, `Lines()`, `Print()`. Fires `NOIR_PROFESSIONS`. Saved per character in `NoirGuidesCharDB.professions` (`plan[skillLine]`, and `told[skillLine]`, the rank last announced).
- `Noir.Cleanup`: `RouteQuests()`, `Scan()`, `Open`/`Close`/`Read`, `Ticked()`, `Abandon()`, `RowFrame(quest)`, `ButtonFrame()`, `CloseFrame()`.
- `Noir.Diagnostics`: `Lines()`, `Open`/`Close`/`Read`, `box`. It wraps `Noir.ReportError` to keep the last ten errors for the report.
- `Noir.Menu`: `Open([items, title])`, `Close()`, `IsOpen()`, `Read()`, `RowFrame(i)`, `Main()`.
- Commands: `/noir talents`, `/noir professions`, `/noir cleanup`, `/noir bug`, `/noir menu` (and `/noir options`). A right click on the window opens the menu while the window is unlocked; a locked window lets the mouse through (`Window.SetLocked`), so then only `/noir menu` opens it, and locking says so in chat.

### Decisions

- **Talents are advice.** The addon never calls `LearnTalent` (the mock treats it as a forbidden call). The build is one talent ID per point (`Data/Talents.lua`), written in `tools/lib/talent_builds.js` against the Forever client's own trees: Forever renamed and moved many talents (the rogues' weapon specializations are "Hack and Slash", the Warlock's Curse of Agony talent is "Improved Bane of Agony"), so no classic build fits. The generator refuses a build that is not learnable point by point; the engine checks it again against the client's trees (each talent at its tier and column with the same number of ranks), reports a mismatch once in `/noir problems` and then suggests nothing.
- **Talent messages** come once per point: when there is a point to spend and the build's next pick is learnable, "Talent point: Name r/max (Tree)". Points spent off the build are listed by `/noir talents`; the plan goes on with the build's talents.
- **Professions by skill line.** `State.professions` is keyed by the skill line the client returns. Forever files each profession's ranks as a child line (Skinning 2947 under 393; all twelve sit at `ParentTierIndex` 4 in `SkillLine`); `Data/Professions.lua` maps those to their profession, so either answer counts.
- **The cleanup never decides for the player.** Every row starts unticked. Since X3 (see `docs/INDEPENDENCE-REVIEW.md`) it weighs one question per quest: dropped, can it be taken again from its giver? `Data/Cleanup.lua` gives the facts (`Noir.Data.questTies`: classes, skill, instance, event, starting item), `Cleanup.lua` the verdict. Not listed: a quest the rest of the route mentions (from the step shown on, including an earlier step shown in its stead) and the character's own training (a quest of its class, or one that needs a profession it has, Forever's tier lines counted). Listed under CAN BE TAKEN AGAIN: off the route, failed, grey, done in a dungeon or raid, needs a profession the character lacks, another class's quest. Listed under HARD TO TAKE AGAIN: ready to hand in, offered only during an event, started by an item. Each ticked quest is checked again just before it is abandoned, one every 0.3 seconds; combat refuses or stops it. After a route is chosen by hand, the chat says how many quests the new route does not need.
- **The bug report** is an `EditBox` with a font set by file (`Theme.Font`), never a font object. Typing into it puts the report back; Escape closes it while the box has the keyboard.
- **Escape does not close the menu or the cleanup window** (known gap). The game's Escape handling closes the frames named in `UISpecialFrames`, which needs a global frame name, and DESIGN.md says the addon names no frame. Taking the keyboard instead needs `SetPropagateKeyboardInput`, which modern-based clients restrict in combat. Each panel has a Close row, and a right click on the unlocked window toggles the menu. If the owner allows named frames, registering the three panels in `UISpecialFrames` fixes it.
- **Every caught error is reported through `Noir.ReportError`.** Core's event bus, `Noir.After` and `/noir` commands look the field up when an error happens, so the wrapper in Diagnostics keeps errors from all of them for `/noir bug`.
- **The menu** is a drill-down list (a submenu replaces the list, with Back on top) rather than cascading dropdowns, so it needs no dropdown template.

### The mock client's additions

- Talents in the Classic Era form: `GetNumTalentTabs`, `GetTalentTabInfo`, `GetNumTalents`, `GetTalentInfo` (name, icon, tier, column, rank, max), `GetTalentPrereqs`, `UnitCharacterPoints`, and `LearnTalent`, which records a violation. The trees default to the addon's `Noir.Data.talents` for the class; `opts.talents` or `client:setTalents(tabs)` give other trees, `opts.talentApi = "none"` removes the functions. `client:learnTalent(tab, index)` or `client:learnTalent("Name")` spends a point as the player and refuses what the game refuses. `setLevel` fires `CHARACTER_POINTS_CHANGED` from level 10.
- Abandoning: `SelectQuestLogEntry` remembers the selection; `SetAbandonQuest`/`AbandonQuest` (classic) and `C_QuestLog.SetSelectedQuest`/`SetAbandonQuest`/`AbandonQuest` (modern) abandon the selected quest; abandoning in combat is a violation.
- `client:click(frame, button)` (OnMouseDown, OnMouseUp, and OnClick for a Button) and `client:hover(frame [, leave])`; both need a visible frame that takes the mouse.
- `CreateFrame("EditBox")`: `SetFont`, `SetText`/`GetText`, `SetMultiLine`, `SetAutoFocus`, `SetTextInsets`, `SetFocus`/`ClearFocus`/`HasFocus`, `HighlightText`; `SetFontObject` on it is a violation.
- `GetBuildInfo()` returns "1.60.1", "70888", a date and 16001.

### Unverified assumptions about the Forever client (continued)

| # | Assumption | If it is wrong |
|---|---|---|
| 41 | `GetNumTalentTabs`, `GetNumTalents(tab)` and `GetTalentInfo(tab, index)` exist; `GetTalentInfo` returns name, icon, tier, column, rank, max rank, with tier and column 1-based; the tabs come in the order of `TalentTab.OrderIndex`. [`talentApi`] | `/noir talents` says it cannot read talents, or the build is reported as not fitting the client's trees and nothing is suggested. |
| 42 | `UnitCharacterPoints("player")` (or `GetUnspentTalentPoints()`) returns the points to spend; without either they are worked out as level - 9 minus the points spent. | Only the count in `/noir talents` can be off. |
| 43 | `CHARACTER_POINTS_CHANGED` fires when a point is gained or spent. | The talent message comes at the next level up instead. |
| 44 | A quest is abandoned with `C_QuestLog.SetSelectedQuest(id)`, `C_QuestLog.SetAbandonQuest()`, `C_QuestLog.AbandonQuest()`, or with `SelectQuestLogEntry(index)`, `SetAbandonQuest()`, `AbandonQuest()`, the index from `GetQuestLogIndexByID` or the 8th return of `GetQuestLogTitle`; none of them is protected out of combat. [`api`] | The cleanup lists quests but cannot abandon them; `/noir problems` says so when the functions are missing. |
| 45 | The profession ranks need levels 10 (Journeyman), 20 (Expert) and 35 (Artisan), as on other Classic clients; `Professions.RANKS` marks those ranks `verified = false`. The skill gates 50, 125 and 200 are the owner's Forever finding. | A "wait" or "train" in the plan comes at the wrong level; the gates are unaffected. |
| 46 | `GetProfessionInfo` returns either the profession's skill line or its Forever tier line (2937 to 2948). | Another ID shows as an unknown profession in the plan; `/noir bug` lists what was read. |
| 47 | A plain `Frame` with `EnableMouse(true)` gets `OnMouseUp(self, button)`, `OnEnter` and `OnLeave`; `HookScript` works on the addon's own frames. | The rows of the menu and the cleanup do not react; the commands still work. |
| 48 | An `EditBox` takes a font by `SetFont(file, size, flags)` and supports `SetMultiLine`, `SetAutoFocus`, `HighlightText`, `SetFocus`, `OnEscapePressed` and `OnTextChanged(self, userInput)`. | The bug report box shows no text; the report is still in `Noir.Diagnostics.Lines()`. |
| 49 | `GetBuildInfo()` returns version, build, date and interface. | The report says the client is unknown. |
| 50 | A quest stops giving experience at the grey level classic clients use for creatures (level 6 to 39: level - 5 - floor(level / 10); 40 to 59: level - 1 - floor(level / 5)). | A cleanup row says "Not on your route" where "Grey, and not on your route" was due, or the other way round; what is listed and what is abandoned are unaffected. |
| 51 | `LOCALIZED_CLASS_NAMES_MALE` maps class tokens to the client's class names. | A cleanup row names another class's quest by its token in title case ("A Mage quest"); nothing else depends on it. |

## Rebuild E1: mock client v3, options and profiles, screen keeping, final toc

Plan: `docs/superpowers/plans/2026-11-11-guide-rebuild.md`, task E1.

### What other modules build on

- `Noir.Options` (`Options.lua`): `Get`, `Set` (type and range checked, fires `NOIR_OPTION`), `DEFAULTS` (spec 6.1), `RANGES`, the profile functions (`NOIR_PROFILE` on use and reset) and the window places (`Position`, `SavePosition`). Options are account-wide profiles; each character uses one (`NoirGuidesCharDB.profile`), new characters the default profile.
- `Noir.Screen` (`UI/Screen.lua`): `DEFAULTS`, `Place`, `Keep`, `Pull`, `Save`, `Reset`, `Fit`, `AtCursor`, `Movable`, `Register`, `Allowed`, `SetShown`, `Preview`, `IsPreview`. Every window an E task creates goes through `Place`, `Keep` and `Register`; menus through `AtCursor`. A window that its module shows while windows may not show (`shown` off, or a raid with `hideInRaid`) is hidden again at once and comes back with the others. A protected frame, or one holding secure buttons, is not moved, shown or hidden in combat; that waits for `PLAYER_REGEN_ENABLED`.
- Saved variables schema 2 (Core): `NoirGuidesDB = { schema, profiles, defaultProfile }`, `NoirGuidesCharDB = { schema, profile, owner, ... }`. Schema 1 is migrated: the options become the Default profile (automation switches renamed, window and arrow places become `positions`), the format 2 places are dropped with one why entry of kind `route`. `Noir.char.owner` is the player's GUID, saved at login when missing.
- The toc is final: later tasks fill the skeletons `Guide.lua`, `Lines.lua`, `UI/Buttons.lua`, `UI/Wizard.lua`, `UI/SettingsPanel.lua`, `UI/MinimapButton.lua` and `Bindings.xml` without touching the toc.

### Decisions

- **Places are saved as the top left corner in UIParent units** (`{ "TOPLEFT", "BOTTOMLEFT", x, y [, w, h] }`), so a change of the window's scale keeps the corner where it was; defaults are anchors in UIParent units, divided by the frame's own scale when placed.
- **Screen moves frames itself.** It does not rely on the client clamping a frame placed by `SetPoint` (the mock clamps only during a drag): `Keep` moves a frame inside UIParent when it is placed, shown or resized, and after a resolution or UI scale change, by shifting every anchor's offsets, so a frame hung from another keeps its anchor point. A frame larger than the screen keeps its top left corner on the screen; `Fit` caps heights at 90% of it.
- **Lint**: `SetBinding*` and `SetOverrideBinding*` calls, writes to `StaticPopupDialogs` and any method call on, or field write to, `StaticPopup1` to `StaticPopup4` are refused.

### The mock client's additions

- The screen: `opts.screen = { w, h, scale }` and `client:setScreen(w, h, scale)` (fires `DISPLAY_SIZE_CHANGED` and `UI_SCALE_CHANGED` for what changed). UIParent is 768 / scale units high and 768 * w / h / scale wide; `GetScreenWidth`/`GetScreenHeight` give that size, `UIParent:GetEffectiveScale()` the UI scale. `client:rectOf(frame)` resolves every anchor (two anchors on opposite sides set the size), size and scale; `client:offScreen()` lists every shown frame of the addon that leaves UIParent, counting only the part a scroll frame or a clipping frame draws, and leaving out the client's own frames and what the addon put inside them (map pins).
- Frames: `OnSizeChanged` on a size change (at once; the game runs it on the next frame), `SetMouseClickEnabled`/`SetMouseMotionEnabled` (clicks and `OnEnter` follow them), `EnableMouseWheel`, `EnableKeyboard`, `SetPropagateKeyboardInput` (a violation in combat), `SetClipsChildren`, `SetResizable`/`SetResizeBounds`/`StartSizing` (a drag on a grip resizes from the bottom right corner, keeping the top left one), `ScrollFrame` (`SetScrollChild`, scroll offsets), `Cooldown`, `Button` (`Enable`/`Disable`, `PreClick`/`OnClick`/`PostClick`; buttons take the mouse from the start), attributes on every frame.
- Secure frames: a template containing "Secure" makes a protected frame. A protected frame, or a frame holding one, records an `ADDON_ACTION_BLOCKED` violation for `SetAttribute`, `Show`, `Hide`, `SetPoint`, `SetSize` and the like in combat and does not change. `IsProtected()` returns the implicit and the explicit flag. `client:secureClick(frame)` clicks it and returns what its attributes did: `type = "item"` uses the item (its cooldown starts, its spell is cast), `"spell"` casts a known spell, `"macro"` with `macrotext = "/targetexact <name>"` targets an NPC of exactly that name that `client:near(npc)` put near. An addon `OnClick` on a secure button replaces the template's, as in the game, and the action does not happen.
- Mouse and keys: `client:setCursor(x, y)` (UIParent units; `GetCursorPosition` returns them times the UI scale), `client:doubleClick(frame, gap)` (`OnDoubleClick` within `opts.doubleClickTime`, 0.5 s), `client:wheel(frame, delta)`, `GameTooltip` (`SetOwner`, `AddLine`, `AddDoubleLine`, `SetText`, `SetHyperlink("quest:<id>")`; `client:tooltip()` reads its lines while shown), `client:hold("CTRL"|"SHIFT"|"ALT", down)` with `IsControlKeyDown`, `IsShiftKeyDown`, `IsAltKeyDown`, `IsModifierKeyDown`, `client:pressKey(key)` (the newest shown frame with the keyboard gets `OnKeyDown`; it passes the key on only when it propagates).
- The options window: `opts.settingsApi = "modern" | "legacy" | "none"` (default modern on `api = "modern"`, legacy on classic); `client:optionsCategories()`, `client:optionsOpenedTo()`, `client:closeOptions()`. Opening it in combat is a violation.
- Merchants and trainers: `client:openMerchant(npc, items)` with `GetMerchantNumItems`, `GetMerchantItemInfo`, `GetMerchantItemLink`, `GetMerchantItemID`, `GetMerchantItemMaxStack`, `BuyMerchantItem(index, quantity)` (quantity in items; more than the stock or the money is refused whole), `CloseMerchant`; `client:openTrainer(npc, services, { tradeskill })` with `GetNumTrainerServices`, `GetTrainerServiceInfo`, `GetTrainerServiceCost`, `GetTrainerServiceLevelReq`, `BuyTrainerService`, `IsTradeskillTrainer`, `CloseTrainer`.
- Quest pages and the tracker: `client:showReward(quest, choices)` with `GetNumQuestChoices`, `GetQuestItemInfo("choice", i)` (name, texture, count, quality, usable, item ID), `GetQuestItemLink`, `GetQuestReward(i)` (the chosen item goes to the bags); `client:shareQuest(quest, from)` fires `QUEST_ACCEPT_CONFIRM`, answered by `ConfirmAcceptQuest`; `AddQuestWatch`, `RemoveQuestWatch`, `IsQuestWatched` (by quest log index), `GetNumQuestWatches`, `MAX_WATCHABLE_QUESTS = 5`; `client:events(name)` lists the times an event fired.
- The character: bags (`client:giveItem`, `client:takeItem`, `GetItemCount`, `GetContainerNumSlots`/`GetContainerItemID`/`GetContainerItemInfo`, under `api = "modern"` in `C_Container`), `GetItemCooldown`, `IsEquippedItem`; `IsSpellKnown`, `GetSpellInfo`, `client:learnSpell(id)`, `client:castSpell(id)` (`UNIT_SPELLCAST_START`, then `UNIT_SPELLCAST_SUCCEEDED`; the Hearthstone and Astral Recall take the player home); `client:die()`, `client:releaseSpirit(place)`, `client:resurrect()` with `UnitIsDeadOrGhost`, `UnitIsGhost`, `C_DeathInfo.GetCorpseMapPosition`; `IsInRaid`, `IsInGroup`, `client:joinRaid(on)` (`GROUP_ROSTER_UPDATE`); `UnitExists`, `UnitName`, `UnitGUID`, `UnitIsFriend` for the target; `SetRaidTarget`, `GetRaidTargetIndex`; `SetCVar` (`CVAR_UPDATE`); `ReloadUI` counted in `client.reloads`; `IsAddOnLoaded` (`C_AddOns` on modern) for `opts.addons`; `client:openTalentFrame()` (loads `Blizzard_TalentUI`; `TalentFrame` guarded like the map); `QuestLogFrame` (guarded; `client:openQuestLog()`); `GetActiveTalentGroup` on modern; `client:slashCount()`.

### Unverified assumptions about the Forever client (continued)

| # | Assumption | If it is wrong |
|---|---|---|
| 52 | UIParent is 768 / UI scale units high and as wide as the aspect ratio makes it; `GetScreenWidth`/`GetScreenHeight` give its size; `GetCursorPosition()` divided by `UIParent:GetEffectiveScale()` is in UIParent units. [`screen`] | Default places and menus at the cursor are off by the scale; `Screen.Keep` measures UIParent itself, so windows still stay on the screen. |
| 53 | `DISPLAY_SIZE_CHANGED` and `UI_SCALE_CHANGED` fire after a resolution or UI scale change, and `OnSizeChanged` runs when a frame's size changes. | A window can stay partly off the screen after such a change until it is shown again or dragged. |
| 54 | The options window has `Settings.RegisterCanvasLayoutCategory`, `Settings.RegisterAddOnCategory` and `Settings.OpenToCategory`, or the older `InterfaceOptions_AddCategory` and `InterfaceOptionsFrame_OpenToCategory`; it cannot be opened in combat. [`settingsApi`] | The settings open as a free window instead (task E8). |
| 55 | `Frame:IsProtected()` reports a frame that holds a secure button as protected, and the game blocks moving, showing or hiding it in combat. | Screen waits for the end of combat more often than needed, or a move of a button bar in combat raises a blocked-action message. |
| 56 | `SetPropagateKeyboardInput` is restricted in combat, as on clients built on the modern code. | Nothing: the addon does not call it in combat either way. |
| 57 | A double click is two clicks within 0.5 seconds (the Windows default) and runs `OnDoubleClick`. [`doubleClickTime`] | The step list's double click (task E5) opens the step menu at another speed. |
| 58 | Frames have `SetMouseClickEnabled`, `SetMouseMotionEnabled`, `SetClipsChildren` and `SetResizeBounds`. | Each is feature-detected; without them pins take clicks, scrolled lists are not clipped, and the window can be made smaller than its content. |
| 59 | A `Bindings.xml` beside the toc is read by the client without being listed, and an empty `<Bindings>` element loads without an error. | An XML error line at login until task E9 fills the file; nothing else. |
| 60 | `C_DeathInfo.GetCorpseMapPosition(uiMap)` returns the corpse's place on a map while the player is dead or a ghost. | The arrow does not point to the corpse (task E6). |
| 61 | `BuyMerchantItem(index, quantity)` counts items, and `GetQuestItemInfo("choice", i)` gives the item ID as its sixth value. | The vendor buys the wrong amount, or the reward marker falls back to the item link (task E9). |

## Rebuild E3: lines, conditions, step text

Plan: `docs/superpowers/plans/2026-11-11-guide-rebuild.md`, task E3.

### What other modules build on

- `Noir.Lines` (`Lines.lua`): `Active`, `Check(line, step, ctx)` (`"done"`, `"todo"`, `"skip"`, `"missing"`, `"hidden"`, with an evidence sentence and a counter `{ have, need }` that is also readable as `counter.have`/`counter.need`), `Applies` (= `Guide.When`), `Condition(step)` (reason, jump), `Places(step, reached [, ctx])`, `Yards(place)`, `Arrived(place)`, `GrindCounter(line)`, `ProfessionName(skill)`, and the constants `ACCEPT_GRACE`, `TURNIN_GRACE`, `FLY_GRACE`, `FLY_ARRIVE_YARDS`, `RANK_CAP`, `RANK_GATE`.
- `ctx` is Progress's (task E4): `since` (GetTime when the step became current; without it every recorded event counts), `ticks = { [line index] = true }` (a `manual` line is done only when ticked), `done = { [line index] = true }` (latched lines, for `Places`), `bound` (the bind name of this step's inn when known). `reached` for `Places` is a set keyed by the place tables.
- `Noir.Text` (`UI/Text.lua`): `Line(line, step)` (`text`, `icon`, `quest`, `spans` as byte ranges `{ kind, from, to }`, `tooltip` for missing prerequisites), `StepTitle`, `QuestName`, `NpcName`, `ItemName`, `ZoneName`, `FlightName`, `SpellName`, `Place`, `Distance`, `RANKS`.
- `Noir.State` additions: `ItemCount`, `KnowsSpell`, `RecentAccept`, `RecentTurnIn` (and the times in `acceptedAt`, `turnedInAt`), `IsGhost`, `Corpse`, `InInstance`, `InRaid`, `lastCast`, `merchant`, `trainer`, `taxiPick`, `controlLost`, `flightStart`, `discoveredAt`, `boundAt`, `levelAt`.

### Decisions

- **Passive lines count as done in `Check`** (use, target, note, goto without a positive radius), but keep their places in `Places` while the step is shown: a passive goto is an arrow and pin target, never a blocker.
- **A class trainer visit** counts from the moment this session saw the character reach the line's level (`State.levelAt`), else from when the step became current. A level read at login is not "reached" then.
- **A grind line's counter** is the XP of the level it counts toward: at `level` for "until P% into level L", at L - 1 for "grind to level L". At any other level it has no counter.
- **sethearth** is done when the hearthstone was bound during the step and the bind's place (State records it at the innkeeper) is within 40 yards of the line's or step's place, or when the bind already lies there. A bind elsewhere during the step does not count.
- **fly**: a pick on the flight map whose destination is known and is not the line's `to` never counts as this flight; arriving within 60 yards of the destination still does.
- **`complete` (skip condition)** also holds once the quest is handed in.
- **Profession names** come from `Data/Professions.lua`, then the skill the client listed, then "skill <id>"; Forever's tier lines (`Data.professionLines`) count as their profession for `train` and `skill`.

### The mock client's additions

- `hooksecurefunc([table,] name, hook)`: the hook runs after the function with its arguments; hooking a function of a guarded client frame is a violation.
- `opts.takeoffLag = seconds`: `TakeTaxiNode` closes the flight map at once and the flight starts (`PLAYER_CONTROL_LOST`, `UnitOnTaxi`) that much later.

### Unverified assumptions about the Forever client (continued)

| # | Assumption | If it is wrong |
|---|---|---|
| 62 | `hooksecurefunc("TakeTaxiNode", fn)` works and `TakeTaxiNode(slot)` takes the slot `NumTaxiNodes`/`TaxiNodeName` (or `C_TaxiMap` `slotIndex`) gave. | A fly line completes only on the flight itself (`UnitOnTaxi`) or at the destination, not in the moment of taking off; getflight misses "just flown from or to". |
| 63 | `PLAYER_CONTROL_LOST` fires when a flight starts, and `UnitOnTaxi("player")` is true then or within 1.5 seconds of the pick. | As 62: the fly line completes on landing near the destination's flight master. |
| 64 | `UNIT_SPELLCAST_SUCCEEDED` gives (unit, cast GUID, spell ID); older clients give the spell ID fifth. The Hearthstone casts spell 8690. | A hearth line completes only on arrival at its destination. |
| 65 | `UnitGUID("npc")` is `Creature-0-<server>-<instance>-<zone>-<npc ID>-<spawn>` while a merchant or trainer window is open. | Vendor and trainer lines accept any merchant or trainer instead of the named one. |
| 66 | `C_Map.GetMapWorldSize(uiMap)` exists, or `C_Map.GetWorldPosFromMapPos` gives the world places of a map's corners. | Distances in yards are unknown: goto lines with a radius complete only by zone, `Arrived` returns nil and nearest places keep the first. |
| 67 | `GetBindLocation()` names the inn's subzone; a hearthstone bound before the addon saw the bind has no known zone, so the `bound` skip condition compares the name with the zone's name. | A `bound` condition holds only after the next bind with the addon running. |
| 68 | `MERCHANT_SHOW`/`MERCHANT_CLOSED` and `TRAINER_SHOW`/`TRAINER_CLOSED` fire once per visit (a second close is ignored). | None: the first close is kept. |

## Rebuild E4: Progress v3 and the why-log v2

Plan: `docs/superpowers/plans/2026-11-11-guide-rebuild.md`, task E4.

### What other modules build on

- `Noir.Progress` (`Progress.lua`): `Load`, `Cards` (each card line also carries `index`, its index in `step.lines`, 0 for the synthetic grind line, which is what `Tick` takes), `Place`, `Steps`, `StepState`, `Tick`, `Jump`, `Skip`, `Back`, `Lookahead`, `Locate`, `Complete` (the route is done; `Cards()` is empty then, and `Place()` stays on the last step, spec 2.4.5), `Refresh`, `Reached`, `MarkReached`, and the events `NOIR_STEP`, `NOIR_PLACE`, `NOIR_LINE`, `NOIR_STEP_DONE`, `NOIR_OBJECTIVE_DONE`.
- `Noir.Why` (`Why.lua`): `Add({ section, step, n, kind, text [, label] })`, `ForStep(section, stepId)`, `List`, `Lines`, `Words(kind)`, `Describe(step)`, `KINDS`.

### Decisions

- **Placement scoring** is 0.1.1/0.1.2's (+4 in the log, +2 handed in, -1 missing, a known flight point +2 and an unknown one 0, one count per quest at its first line, latest highest score wins). New: steps above their `maxLevel` and sections above theirs (while "outlevel" is on) and steps under their `minLevel` are not counted as missing, because the engine would pass or hold them anyway. A placement that lands on a reminder step moves to the next step (a reminder never becomes the place).
- **With no evidence above level 1**, `Guide` picks the section by the zone rule, then `Guide.ForLevel` (task E4 found that falling back to `Recommend` put a level 12 on the race's first quest, the 0.1.0 complaint).
- **A saved place** is found by step id even when the section's signature changed (an edited section keeps the place); by `n` only while the signature is unchanged; otherwise placement runs and a why entry of kind `route` says so.
- **Passes**: events and position checks start a pass at once, but the place moves at most once per `PASS_SECONDS`; a run of done steps therefore passes at 0.1 s intervals. A pass that loads another section (end of section, `load`) stops there.
- **A step with only passive lines** (notes, markers, item and target buttons) passes at once, as spec 3.2 says, with a why entry of kind `done` ("only notes and markers, nothing to do") so the player can find it; a step done before it was ever shown as current also gets kind `done`.
- **Lines passed by a skip option** (`skipIfMissing`, `skipIfIncomplete`, an `ifDone` accept, a profession gate) get a why entry of kind `condition` when they are passed, naming the line.
- **Reminders**: one with active lines ends early when they are all done; one of only passive lines ("keep an eye out for this rare") lasts until its `ends` step is passed and does not hold the end of a section. Without an `ends` link (the validators require one, so only a hand-edited route) a reminder ends at the first later step that requires it, and that step is not held by it.
- **The end of the route**: the place stays on the last step; `places[section].ended = true` is saved, so a relog keeps the route complete (as long as the section still has no next section). A finished section picked again by hand opens on its last step. Places saved by the first E4 build past the end (`n = #steps + 1`) are read the same way.
- **Detours** come only from the current step's missing lines; a missing line with no earlier accept in the section is passed with kind `cannot` and one chat line.
- **Outleveled steps** (`maxLevel`) pass while "outlevel" is on, whatever "neverSkip" says; skip conditions obey "neverSkip" (except a gate, see "Rebuild X1 review 2") and wait while the addon is hidden.
- **The quest tracker**: each quest of the current step is watched once while the step is current, so a player who untracks it is not overruled.
- **Loop sections** wrap once per session (not saved).
- **Placement past the last step** (the best evidence is the section's last step, or the steps after it are all reminders) is the end of the section, in a fresh placement and in the login catch-up alike: the place waits on the last step without showing it as current, and the next pass handles the end as spec 2.4 says (the next section, open reminders holding it, or the end of the route, printed once). The chat line and the why entry say "past its last step", never a step number past the end.
- **A section with no step for the character** passes to its end with a why entry of kind `section` saying so.
- **A reminder that ends on the section's last step** (spec 2.4.2 read against 3.6): reaching the last step does not end it; only passing that step would, and the place passes the last step only through the end of the section. So such a reminder with active lines left holds the end of the section until its lines are done or ticked (test "open reminders hold the place at the end of a section"). A route that wants "collect while you go" to stop holding at the end should end the reminder on an earlier step; a reminder of only passive lines never holds.

### Unverified assumptions about the Forever client (continued)

| # | Assumption | If it is wrong |
|---|---|---|
| 69 | `AddQuestWatch(questLogIndex)`, `IsQuestWatched(index)`, `GetNumQuestWatches()` and `MAX_WATCHABLE_QUESTS` exist as in Classic Era; the index comes from `GetQuestLogIndexByID` (or `C_QuestLog.GetLogIndexForQuestID`, or a walk of `C_QuestLog.GetInfo`). `C_QuestLog.AddQuestWatch(questID)` is used only without the global. | The tracker does not follow the current quests; nothing else depends on it. |

## Rebuild E5: window v2, card stack and step list

Plan: `docs/superpowers/plans/2026-11-11-guide-rebuild.md`, task E5.

### What other modules build on

- `Noir.Window` (`UI/Window.lua`): `frame`, `Refresh`, `Read` (as the plan gives it, plus `side` ("above" or "below"), `preview`, a card's `text`, `mark`, `slide` and `hidden`, and the footer's `rail = { fill, ticks }`), the click targets `Tick`, `Row`, `Header`, `MenuButton`, `Grip`, and also `Footer`, `Card`, `Line`, `LineText`, `ListFrame`, `ScrollBar`; `Preview(on)`, registered with `Screen.Register("window", ...)`. `Tick(cardIndex, lineIndex)` and `Line` count the lines a card shows (its `lines` in `Read`), not `step.lines`.
- `Noir.Panel` (`UI/Panel.lua`): `Confirm(text, onYes, onNo)` (questions wait their turn; at `Screen.DEFAULTS.dialog`, registered as "dialog"), `ConfirmRead`, `ConfirmButton("yes" | "no")`, `Answer(yes)`, and `ScrollList(parent, opts)`.
- `Noir.Theme`: `Font(fontString, role, large)`, `Icon(name)`, `ICONS`, `MARKS`, the meaning colors `friend`, `enemy`, `loot`, `warning`, `object`, `buy`, and the measures `icon`, `tick`, `header`, `footer`, `list`, `slide`, `mark`, `large` (DESIGN.md).

### Decisions

- **Kind icons**: 17 textures, the spec's 16 (4.2) and `note`, the icon `UI/Text.lua` gives note and manual lines; the timer icon waits for the flight bar.
- **Cards that do not fit** above or below the window (both sides too small) are left out from the farthest end (the oldest reminders), never the current card, which is always nearest to the window; `Read` marks them `hidden`. Below the window the stack is therefore in reverse order (current first).
- **The step list's height** is saved as the window's height in its position (`Screen.Save`); while the window shows only its header (no section, or the step list off) a move saves the full height instead, so the list keeps its height.
- **A tick box** is shown only on active lines (Lines.Active); notes, markers and the grind line the engine adds under a step's level have none.
- **Double clicks**: a row opens the step menu on `OnDoubleClick` or on two left clicks within 0.5 s; a single click does nothing (it could be the first of two).
- **The new current card**: its side bar shows the step's most prominent kind (hand in, accept, train, objectives, travel) for 3 s in the `MARKS` colors, then the lamp color; it slides in over 0.25 s from 16 units to the right, inside the card stack, which clips its children. No sound.
- **Rows** of steps the character outlevels (ahead, above `maxLevel` while "outlevel" is on) and hidden steps are left out of the list; rows behind the place and finished reminders are at half alpha.
- **The mock client** records `PlaySound` and `PlaySoundFile`, so a test can check the window stays quiet.

### Unverified assumptions about the Forever client (continued)

| # | Assumption | If it is wrong |
|---|---|---|
| 70 | `GameTooltip:SetHyperlink("quest:<id>")` shows a quest's tooltip, as in Classic Era. | The call is made in `pcall`; the tooltip shows the line's words instead. |
| 71 | `Frame:SetClipsChildren(true)` exists and clips child frames to the frame. | Feature-detected: a sliding card may draw up to 16 units outside the stack for a quarter of a second. |
| 72 | A `Button` gets `OnClick(self, "RightButton")` after `RegisterForClicks("LeftButtonUp", "RightButtonUp")`, and `OnDoubleClick` for the second click of a double click. | Two left clicks within 0.5 s still open the step menu through `OnClick`. |
| 73 | A `ScrollFrame` with `SetScrollChild`, `SetVerticalScroll` and `OnMouseWheel` (with `EnableMouseWheel`) behaves as in Classic Era, and rows without wheel input pass the wheel to it. | The step list does not scroll with the wheel; the scrollbar and the scroll after each step change still work. |

## Rebuild E6: arrow v2 and map pins v2

Plan: `docs/superpowers/plans/2026-11-11-guide-rebuild.md`, task E6.

### What other modules build on

- `Noir.Arrow` (`UI/Arrow.lua`): `Target`, `Solve`, `Project`, `Read`, `Reset`, as the plan gives them, and also `CardPlaces(card)` (the places of a card from `Progress.Cards`, without done, ticked or reached ones), `Between(a, b)` (yards between two places), `Elsewhere(point)`, `Update`, `Retarget`, `Preview(on)` (registered with `Screen.Register("arrow", ...)`), `frame`, `parts.arrow`, `parts.label`. `Read` also gives `title` and `draws` (how many times it was drawn).
- `Noir.Map` (`UI/Map.lua`): `Pins(kind)`, `Refresh()` (asks for a rebuild; at most one every 0.33 s), `Read()` (`builds`, `builtAt`, `world = { shown, map, pins, lines }`, `minimap = { pins }`), `parts.world`, `parts.minimap` (pin frames with `back`, `mark`, `ring`, `label`, `glyph`, `plus`), `parts.lines` (path dashes).

### Decisions

- **The world map limit counts steps that have a place**: the cards' steps first, then the next steps still ahead (not hidden, not outleveled) until the limit; the limit is raised to the number of card steps with a place, so `worldPins = 0` still shows the cards' places.
- **Merging** compares a place with each pin's first place, in order (cards first); a merged pin keeps the most opaque alpha of its places and shows the first step's number (or, for a step with a title, its first line's kind icon) with a "+".
- **"Current" pins** are the pins of every card (current step, reminders and detours): larger, opaque, and ringed with `pinRing`. On the minimap only a pin holding the current step waits on the rim when out of range.
- **A step's own place** stands, in its tooltip line, for its first open line without a place of its own.
- **The arrow does not point at** places with `r = 0` (pin only) or zone-only places (`x = y = 0`); a looping path's step place is replaced by the loop's current point. Arrival marks the place reached through `Progress.MarkReached` at once (Progress also checks every 0.33 s).
- **Another continent** is told by the place's world instance against `UnitPosition`'s, else the data's `continent` against `GetInstanceInfo()`'s eighth value. The chat line is printed once per target (section, step, line) per session.
- **Rebuilds** happen on the engine's events (`NOIR_STEP`, `NOIR_PLACE`, `NOIR_LINE`, `NOIR_SECTION`), quest log updates, zone changes and option changes, at most every 0.33 s, and when a card place becomes reached (checked every 0.33 s, as no event says so). A change of the shown map draws the last build at once.
- **The mock client** has `Texture:SetRotation` / `GetRotation`.

### Unverified assumptions about the Forever client (continued)

| # | Assumption | If it is wrong |
|---|---|---|
| 74 | `Frame:SetMouseMotionEnabled(true)` with `SetMouseClickEnabled(false)` gives a pin `OnEnter`/`OnLeave` while clicks pass through to the map under it. | Feature-detected: without the two methods pins take no mouse at all and show no tooltip. If clicks were caught, a click on a pin would not reach the map. |
| 75 | `Texture:SetRotation(radians)` turns a texture counterclockwise around its middle. | Feature-detected: without it each path dash is drawn as a dot at its middle, so paths show dotted. |
| 76 | `select(8, GetInstanceInfo())` is the instance ID of the continent the player is on (0 Eastern Kingdoms, 1 Kalimdor), the same numbers as the data's `continent`. Used only when world coordinates are missing. | Without world coordinates, a place on another continent may not be told; the arrow then hides instead of saying "On another continent". |
| 77 | A frame created as a child of `WorldMapFrame`'s canvas or of `Minimap` may get `OnEnter`/`OnLeave` scripts and mouse motion without tainting the map, outside combat. | Map errors while hovering pins. The minimap pins can be switched off ("minimapPins"); the world map pins have no off switch (0 still shows the cards' places), so report it. |

## Rebuild E7: menus at the cursor, the section picker, the setup wizard

Plan: `docs/superpowers/plans/2026-11-11-guide-rebuild.md`, task E7.

### What other modules build on

- `Noir.Menu` (`Menu.lua`): `Open(items, opts)`, `OpenMain`, `OpenStep(index)`, `OpenPicker`, `Close`, `IsOpen`, `Read`, `Row(level, i)` as the plan gives them, and also `Level(level)` (a level's frame), `List(level)` (its scroll frame), `Catcher()` (the full-screen frame under the menu), `Hover(level, i)`, `Activate(level, i)`, and the item builders `MainItems()`, `StepItems(index)`, `PickerItems()` (task E8 can follow `MOUSE_PATHS` through them). A row frame's `marker` is the colored tab of a picker row.
- `Noir.Wizard` (`UI/Wizard.lua`): `Open`, `Close`, `Finish`, `Read`, `Button(name)`, `Toggle(key)` as the plan gives them, and also `Button("next")` and `Button("route")` (the page 1 card), `SectionRow(id)`, `Page(n)`, `Choose(id)`, `Reset()`, `Preview(on)` (registered with `Screen.Register("wizard", ...)`), `frame`. `Read().sections[i].chosen` says which section Finish loads.

### Decisions

- **Clicks**: a row with `on` closes the whole menu first and then calls it (so it may open another window or menu); a tick row (`keep`) stays open and reads its ticks again. A row with a submenu opens it on hover and on click.
- **"Show all map pins"** (the plan's "Show map pins", renamed for what it can do) is one tick for both maps: it is ticked while `minimapPins` is on and `worldPins` is above 0. Unticking sets `minimapPins = false` and `worldPins = 0`, which leaves the cards' own pins on the world map (0 is not an off switch there, #77, and the options have no key that hides them); ticking sets `minimapPins = true` and, when `worldPins` is 0, puts it back to the count it had this session, else the default 7. The exact count is set in the settings. A real off switch for the world map needs a new option key, which the plan's fixed key list leaves to the owner (and task E8).
- **"Find my place again"** asks with `Panel.Confirm`, then runs `Progress.Locate` over `Guide.Chain` from the current section; another section is selected by hand and, like a pick in the picker, offers the quest cleanup 3 s later when "offerCleanup" is on (spec 6.2 item 12); the place is set with `Progress.Jump` and a why entry of kind `place` (newer than the jump's) says it came from the menu. Without evidence the place stays and one chat line says so.
- **"Report a problem with this step"** calls `Diagnostics.Open(index)` with the step's index in the list, so the report (task E10) can name the step; the general "Report a problem" calls it with no index.
- **"Skip this step"** is in the step menu only for the current step (`Progress.Skip` works on the current step).
- **"Preview window positions"** is a tick (preview on and off); "Hide Noir Guides" calls `Screen.SetShown(false)`.
- **The picker** marks the group and subgroup rows holding the section played as current too, so the path to it is lit; a level opens scrolled so its current row is the top row when it would otherwise be out of view. With "outlevel" on, outleveled sections are not offered (`Guide.List`), so the "passed" marker shows only with "outlevel" off.
- **The wizard's section list** is the recommendation (`Guide.Recommend`, which is the loaded section when there is one) first, then every section of `Guide.List` whose range holds the level. The level rule wins over the loaded section (spec 2.3 and the plan: "only sections whose range contains the level"): when the recommendation is out of range, as when the wizard is opened from the menu after leveling past a section loaded by hand, it is left out and the first listed section of the level is recommended; when no section holds the level, the recommendation is listed alone, so Finish always has something to load. Closing still keeps the loaded section. Finish selects with how `"wizard"`; a section of another race or class (listed with "otherSections") is not one `Guide.Select` takes with `"wizard"`, so it is loaded with how `"hand"`. Reset puts the questions back at their recommended answers and leaves planned professions alone.
- **The wizard opens** 2 s after `NOIR_READY` (the first moment the level is known after entering the world) when the character is level 1 and `guide.wizard` is not set.

### Unverified assumptions about the Forever client (continued)

| # | Assumption | If it is wrong |
|---|---|---|
| 78 | A shown frame with `EnableKeyboard(true)` gets `OnKeyDown` with the key name `"ESCAPE"`, and `SetPropagateKeyboardInput(true)` passes every other key on to the game; changing the propagation inside `OnKeyDown` decides for that key. Out of combat Escape is kept from the game; in combat (where the game refuses the change) the menu still closes and the game also sees Escape. | Escape does not close the menu (a click outside still does), or keys are eaten while a menu is open; report it. In combat Escape closing the menu and also opening the game menu (or clearing the target) is the expected double action, on the checklist. |
| 79 | A full-screen frame on the `FULLSCREEN_DIALOG` strata under the menu levels takes a click anywhere outside the menu, and the menu's own levels (higher frame levels on the same strata) take theirs. | A click outside does not close the menu, or a click on the menu closes it. |

## Rebuild E9: automation v2 and secure buttons

Plan: `docs/superpowers/plans/2026-11-11-guide-rebuild.md`, task E9. Supersedes the E2 rules above where they differ: Shift no longer suspends everything (#27), a follow-up quest the guide wants is accepted (#23), and a reward page with one choice is taken (#21).

### What other modules build on

- `Noir.Automation` (`Automation.lua`): `Enabled(key)` as the plan gives it, and also `Read()` (`marker` and `logMarker` = `{ quest, choice, shown }` while the coin marks a reward choice on the reward page or in the quest log; `training`; `talk` = the modifiers of the NPC conversation in progress) and the timing constants `FOLLOW_UP_SECONDS`, `GETFLIGHT_SECONDS`, `FLIGHT_DELAY`, `TRAIN_SECONDS`, `TRAIN_EVERY`. It has no command (task E8 owns commands); every part has its option.
- `Noir.Buttons` (`UI/Buttons.lua`): `Items`, `Targets`, `Read`, `Preview`, `Reset` as the plan gives them, and also `Refresh()`, the row frames `items` and `targets` (registered as `Screen.Register("items", ...)` and `("targets", ...)`; the items row's preview fills both), and the constants `MAX_ITEMS`, `MAX_TARGETS`, `PER_ROW`, `NAMED`, `FRIEND_MARKS`, `ENEMY_MARKS`, `NAMEPLATE_CVAR`, `NAMEPLATE_MAX`. `Read()` gives `items = { shown, buttons = { { kind, id, cooldown } } }`, `targets = { shown, enemy = { { name, portrait } }, friend = ... }`, `pending` (a change waits for the end of combat) and `background`.
- `Theme.metrics.button` (32, also in `DESIGN.md`) is the side of a button.
- The mock client has `QuestFrame` (shown while a quest page is open), `GetItemInfo` with all eleven classic values (sell price from `world.prices`), `GetItemIcon`, `GetSpellTexture`, `GetSpellCooldown`, `SetPortraitTexture`, `GetTrainerServiceSkillLine` (`services[i].skillLine`), the classic quest log's `GetQuestLogSelection`, `GetNumQuestLogChoices` and `GetQuestLogItemLink` (`world.quests[id].rewardItems`), reward choices with a `price`, and the events `UNIT_SPELLCAST_STOP`, `UNIT_SPELLCAST_INTERRUPTED`, `UNIT_SPELLCAST_FAILED`, `SPELL_UPDATE_COOLDOWN` and `PLAYER_EQUIPMENT_CHANGED`. It still has no macro or binding function: calling one raises an error.

### Decisions

- **A conversation** starts at the first NPC window event (gossip, greeting, a quest page, the flight map, the bind question, a merchant, a trainer) and keeps the modifiers held at that moment until a closing event (`GOSSIP_CLOSED`, `QUEST_FINISHED`, `TAXIMAP_CLOSED`, `MERCHANT_CLOSED`, `TRAINER_CLOSED`), another NPC's GUID, or a minute without a window event. `GOSSIP_CLOSED` is the exception: the client's gossip frame calls `CloseGossip` from its `OnHide`, so it also fires when the gossip list gives way to a quest page, the flight map, a merchant or a trainer of the same NPC. The conversation is then kept for `Automation.HANDOVER_SECONDS` (0.5 s) and goes on into any non-gossip window of that NPC opened in that time; a new gossip list, or nothing within the 0.5 s, ends it. The mock fires `GOSSIP_CLOSED` before the quest page or the flight map that takes the list's place. Ctrl keeps accept, hand-in and reward automation away; Shift the flight, the bind and the dialogue lines; no dialogue line is picked while any modifier is held (spec 5.8), so Ctrl also leaves the flight master's line alone. Buying at a vendor and the trainer follow only their options.
- **The "talk to this NPC" quest** (third in the dialogue order) is a quest in the log with one objective, named by an open objective line with index 1 whose `npc` is the NPC the player talks to.
- **Dialogue lines** are picked by type only, and only when exactly one line of that type is offered: `taxi` for an open `fly` line (once per step, keyed by section and step) or `getflight` line (at most every 10 s), `binder` for an open `sethearth` line, `trainer` for an open `train` line (with the `dialogue` option). A line with an `npc` is only acted on at that NPC when the client gives the NPC ID.
- **After accepting** on a quest page, the page is closed with `CloseQuest` only when `GetQuestID()` still names the quest (the client usually closes it by itself).
- **The coin** is the client's gold coin icon on an own frame, anchored to the client's reward button of the choice (`QuestInfoRewardsFrameQuestInfoItem<i>`, else `QuestRewardItem<i>`) or, without one, inside the quest window's top right corner with the item's name beside it; in the quest log to `QuestLogItem<i>` or the quest log frame. The value of a choice is its sell price times its count; with no price known nothing is marked. The marker is shown for any reward page with choices (it acts for nobody); taking a choice is only done for guide quests.
- **Vendor**: the merchant closes on the first bag update after which the bags hold what was bought; when a purchase is refused (no money, sold out) the merchant stays open for the player. An item sold in bundles (the fourth value of `GetMerchantItemInfo`) is bought in whole bundles, the count rounded up, each purchase the most whole bundles within `GetMerchantItemMaxStack`, and the stock (fifth value) is read as a number of bundles (#91). "The linked quest is done" is read as: a `collect` line of the same item on the cards is done.
- **Trainer**: one service per 0.2 s (the client refreshes the list after each purchase), lowest level first; at a class trainer every available service (weapon masters too, as they are not profession trainers), at a profession trainer only the services a `train` line on a card names (a `spell` by the client's spell name, a `skill` rank by the profession's name and the rank names Apprentice, Journeyman, Expert, Artisan up to the line's rank); nothing at a pet trainer.
- **Item buttons** list only what can be used now (in the bags, worn, or a known spell); an objective's or turn-in's item until the line is done; a quest starter's until the quest is in the log or handed in.
- **Target buttons** list the current card's targets first, then a detour's, then the reminders' ("low-priority names last"); a friendly target the player talks to (any NPC window) is left out until the place moves.
- **The rows** hold secure buttons, so the rows themselves are protected: they are built, sized, scaled, shown and hidden only out of combat, and every change asked for in combat runs at `PLAYER_REGEN_ENABLED`. Portraits and cooldowns (textures and a cooldown frame, not protected) change in combat too. The twelve named buttons are created at login, so the key bindings always find them. Dragging a row (on the row or forwarded from one of its buttons) is refused in combat, since `StartMoving` and `StopMovingOrSizing` on a protected frame are blocked; a drag still going when combat starts is ended at `PLAYER_REGEN_DISABLED` (#92). The mock now blocks `StartMoving`, `StartSizing` and `StopMovingOrSizing` on protected frames in combat.
- **The target row's place**: `Screen.DEFAULTS.targets` (`CENTER`, 0, -170) is the middle of a one-row target row. At that default the row hangs by its `TOP` from where a one-row row's top is, so rows added for more targets or the friendly group grow down, away from the item row, instead of growing up over it. A dragged place is kept by its top left corner and grows down too.
- **Nameplates**: with the option on, `nameplateMaxDistance` is raised to 41 when it is lower, and the old value is kept in `NoirGuidesCharDB.buttons.nameplates` and given back when the option is switched off. A client without that setting is left alone. A change asked for in combat (also at a login or `/reload` in combat) waits for `PLAYER_REGEN_ENABLED`. **Open for the owner:** `NoirGuidesCharDB.buttons` is not in the plan's "Saved variables (schema 2)" layout; it is the only key E9 adds. Either the plan's schema gets the line `buttons = { nameplates = "<old CVar value>" or nil }`, or the old value moves elsewhere.
- **For E10/X1, not covered by E9's plan task:** spec 5.2 "auto-complete popups for guide quests are clicked" (quests completed away from an NPC, `QUEST_AUTOCOMPLETE` / the watch frame popup) and spec 4.6's moon marker for rare and scan units are not done by `Automation.lua` or `UI/Buttons.lua`.

### Unverified assumptions about the Forever client (continued)

| # | Assumption | If it is wrong |
|---|---|---|
| 80 | `IsControlKeyDown`, `IsShiftKeyDown`, `IsAltKeyDown` and `IsModifierKeyDown` tell the keys held when an NPC window event arrives, and every NPC window ends with one of `GOSSIP_CLOSED`, `QUEST_FINISHED`, `TAXIMAP_CLOSED`, `MERCHANT_CLOSED`, `TRAINER_CLOSED`. | Ctrl or Shift does not keep the automation away, or a modifier held at one NPC still counts at the next (for at most a minute or until another NPC). |
| 81 | `QUEST_ACCEPT_CONFIRM` carries the sharer's name and the quest's title; `ConfirmAcceptQuest()` accepts a shared quest or an escort start, and `StaticPopup_Hide("QUEST_ACCEPT")` closes only that popup. | A shared guide quest is left for the player to accept, or its popup stays on screen after accepting. |
| 82 | On a reward page, `GetQuestItemLink("choice", i)` gives the choice's link, `select(3, GetQuestItemInfo("choice", i))` its count and `select(11, GetItemInfo(link))` its sell price; the reward buttons are `QuestInfoRewardsFrameQuestInfoItem1..6` (or `QuestRewardItem1..6`); the file ID 237618 is the gold coin icon. | No coin, the coin on the wrong choice, or a coin in the corner of the quest window with the name of the best choice beside it. `bestReward` may take another choice. |
| 83 | In the quest log, `GetQuestLogSelection()` and `select(8, GetQuestLogTitle(i))` give the selected quest, `GetNumQuestLogChoices()`, `GetQuestLogItemLink("choice", i)` and `GetQuestLogChoiceInfo(i)` its choices, and the choice buttons are `QuestLogItem1..`; an own frame on `QuestLogFrame` runs `OnUpdate` while the quest log is shown without tainting it. | No coin in the quest log; nothing else (the quest log is only read). |
| 84 | At a trainer, `GetTrainerServiceInfo(i)` gives (name, rank, "available" / "unavailable" / "used" / "header"), `GetTrainerServiceLevelReq(i)` the level, `BuyTrainerService(i)` buys one service, `IsTradeskillTrainer()` tells a profession trainer, and a hunter's pet trainer's services have the skill line "Beast Training" or "Pet Training" (`GetTrainerServiceSkillLine`). | With "train" on: services bought in another order, a profession trainer's services bought without a train line, or a pet trainer's services bought. "train" is off by default. |
| 85 | A trainer's dialogue line has the type `trainer`, the icon 132058 or an icon path containing `TrainerGossipIcon`. | The trainer line of a `train` step is not picked; the player clicks it. |
| 86 | `SecureActionButtonTemplate` buttons run `type = "item"` with `item = "item:<id>"`, `type = "spell"` with a spell ID, and `type = "macro"` with a `macrotext` attribute of `/targetexact <name>`, without any macro being created; `RegisterForClicks("AnyUp", "AnyDown")` lets a click and a key binding both run them whichever way the client's "cast on key down" is set. | A button does nothing, or does it twice per key press; report which. The items and targets can still be used by hand. |
| 87 | `Bindings.xml` `CLICK <button>:LeftButton` entries with `header="NOIRGUIDES"` show under "Noir Guides" in the key bindings menu with the names from the `BINDING_HEADER_NOIRGUIDES` and `BINDING_NAME_CLICK ...` globals, and pressing the key clicks the named button. | The bindings are missing or unnamed in the menu, or the key does nothing. |
| 88 | `SetRaidTarget("target", index)` from a secure button's `PostClick` marks the unit the click targeted, and `SetPortraitTexture(texture, "target")` draws the target's portrait on an own texture. | No marker (the targeting still works), or the placeholder icon stays instead of the portrait. |
| 89 | The console variable `nameplateMaxDistance` exists on Forever, `GetCVar` returns nil for a variable the client does not have, and 41 yards is the most it takes. | The nameplate distance is not raised, or is raised less than possible; the old value is still given back. |
| 90 | `UNIT_SPELLCAST_START` gives (unit, cast GUID, spell ID) and every cast ends with `UNIT_SPELLCAST_SUCCEEDED`, `_STOP`, `_INTERRUPTED` or `_FAILED`. | The target buttons stay visible while hearthing, or stay hidden after a cancelled hearth until the next cast ends. |
| 91 | `GetMerchantItemInfo(i)` gives the bundle size as its fourth value and the stock (-1 unlimited) as its fifth, counted in bundles; `BuyMerchantItem(i, n)` buys `n` single items, `n` a multiple of the bundle, and `GetMerchantItemMaxStack(i)` is the most items one purchase may take. Also: the gossip frame's `OnHide` fires `GOSSIP_CLOSED` when a quest page, the flight map, a merchant or a trainer of the same NPC takes its place, and the new window's event comes within 0.5 s of it. | Bundled vendor items bought one bundle too many or too few, or a limited stock bought past (the purchase is refused and the merchant stays open). A Ctrl or Shift held at the gossip list stops counting on the page after it (the automation of that page runs). |
| 92 | `PLAYER_REGEN_DISABLED` fires before the combat lockdown starts, so a drag of a row can still be stopped (`StopMovingOrSizing`) in its handler. | A row being dragged when combat starts follows the mouse until combat ends, and the game may show its blocked popup when the drag ends. |
| 93 | Blizzard_TalentUI names its talent buttons `TalentFrameTalent<n>`, where `n` is the talent's index in `GetTalentInfo(tab, n)` for the tab shown, and the tab shown is `PanelTemplates_GetSelectedTab(TalentFrame)` (or `TalentFrame.selectedTab`). Own frames that are children of `TalentFrame` show and hide with it. | The ring is on the wrong talent or missing (the next-point line above the window still names the talent), or the frames above the window stay hidden. |
| 94 | `GetActiveTalentGroup()` and `ACTIVE_TALENT_GROUP_CHANGED` exist only on clients with dual talents; without them every character has one talent group. | A Forever client with talent loadouts but other functions keeps one build choice for all loadouts. |
| 95 | The quest log files class quests under a header named like the class (as `LOCALIZED_CLASS_NAMES_MALE`/`_FEMALE` or `UnitClass` give it) and profession quests under a header named like the profession (as the Professions book or the skill list names it). | A class or profession quest without ties in `Data/Cleanup.lua` may be listed by the quest cleanup (never pre-ticked unless off the route; nothing goes without the button). |
| 96 | `QuestLogFrame` exists after login (or after an `ADDON_LOADED` that creates it), and a frame the addon makes as its child, anchored to its right edge, shows with it and takes clicks. | The quest cleanup has no button beside the quest log; the menu and the settings still open it. |
| 97 | On Forever, `Settings.RegisterCanvasLayoutCategory(frame, name)` + `Settings.RegisterAddOnCategory(category)` list the page under AddOns, size and anchor the frame themselves, and `Settings.OpenToCategory(category:GetID())` opens the options window at it; where only the legacy `InterfaceOptions_AddCategory` exists, `InterfaceOptionsFrame_OpenToCategory(panel)` may need a second call to land on the page. Neither opens in combat. | The settings page opens on the options window's first page (the player picks "Noir Guides" under AddOns), or is laid out at its built size; the minimap button and the menu still reach every control. |
| 98 | The minimap is round (or drawn round) and `Minimap:GetCenter()`/`GetWidth()` describe it, so a button at half its width plus 10 sits on the rim; an own button parented to `Minimap` shows above it at frame level 8. | With a square minimap addon the button sits slightly off the corner; it can still be dragged anywhere on the circle. |
| 99 | TomTom is the other arrow addon Forever players run; other arrow or map addons are not detected by the conflict warning. | Two arrows on screen without a warning for an addon not in `SettingsPanel.CONFLICTS`. |

## Rebuild X1 review 2: ifDone, any-of prerequisites, gates under "never auto-skip"

### Decisions

- **The same-step rule for `ifDone` is part of route format 3** (approved in X1 review 2, written into the plan's Lines table). An accept with `ifDone = A` is passed at once while A is not handed in, except while an earlier line of the same step still hands A in or accepts A: then it waits for that line. The planner bundles "hand in A, accept B" at one NPC (P1) and carries `ifDone` down quest chains, so about 1900 of the 2349 `ifDone` accepts share a step with A's hand-in; without the rule every one of them would be passed before A could be handed in. An earlier hand-in of A in state `missing` (no `skipIfMissing`, waiting on a detour to A's accept) holds B too, because the detour brings A back. A hand-in passed by `skipIfMissing`, or a hand-in in another step, does not.
- **A passed `ifDone` accept is a `skip`**, not `done`: the quest is not taken, so the line gets a why entry of kind `condition` ("only wanted once A is handed in") like every other skip option (never skip silently).
- **Any-of prerequisites** (QuestieDB `preQuestSingle`, `preAny`): `requires` lists `preAll` and the `preAny` members the route hands in earlier, so the planner (`sections.js` `gateLines`) works the gate out from the quest data, not from `requires`. When every any-of member is uncertain (taken in an earlier section, or capped by its XP level), the accept becomes one line per member, each with its own `ifDone`, so any one handed in opens it; one certain member opens it with no gate. Uncertain `preAll` members gate as before: `ifDone` on the first (when no any-of line took it), and a step of its own with `notturnedin` for the others. The engine hides a later accept line of the same quest while an earlier one on its step is not passed, so the card shows the accept once; `flatten` gives one accept action for such lines. The one real case today is March of the Silithid (4494, either 32 or 7732) on the Orc and Troll routes.
- **Gates under "never auto-skip"**: with `neverSkip` on, `Lines.Condition(step, true)` still applies a `notturnedin` condition on a quest an accept line of the step `requires`. The game will not offer that accept, so without this the step would wait for ever (a joiner lacking the second quest of an all-of gate). Every other condition still waits while `neverSkip` is on.
- **`isolateGated`** keeps a step's `load` on its first part only, and refuses (a planner error) to split a step that has a `reminder`, which would remind once per part. No current route step hits either; the guard is for later routes.

### Left as documented (findings 5 and 6 of the review)

- **Placement scoring differs from plan E4's numbers** (finding 5): a quest in the log counts only at its accept line, a known flight point adds +2, steps above `maxLevel` or under `minLevel` are not counted as missing, and the place stays on the best step while one of its quest lines is still to do. Each change came from a simulator or review finding and is described in the E4 decisions above and in Progress.lua's header. The plan says numbers do not change without the owner, so plan E4's text waits for the owner; the code is not changed back.
- **`leadsIntoNext` does not ask that the next section begin in the move's destination zone** (finding 6). The same-zone check of the in-section rule was tried: it fails the simulator-found case of a boat to Wetlands followed by a next section that begins with a walk into Hillsbrad (test "a move near the end of a section with no work left after it is not moot"). Without a journey model that crosses sections, the looser check (the next section begins somewhere the player is not) is kept. The cost is a move kept as "leading on" when the next section begins in an unrelated zone; the player can pass it by hand, and the simulator has not met such a case.

## Rebuild X2: packaging 0.2.0, clean-room check

X2 adds no engine code (only the toc's version). It checks that every client assumption the rebuild made is numbered above and carried into `docs/INGAME-CHECKLIST.md`; none was missing, so no number is added. The assumptions the plan names for X2, and where each is:

- the options window API: #54 (the two APIs, nothing in combat) and #97 (the modern page on Forever);
- the secure button `macrotext` (`/targetexact <name>`, no macro created): #86, with the raid marker from `PostClick` in #88;
- mouse motion on pins (tooltips while clicks pass to the map): #74, and the map and minimap children's scripts without taint: #77;
- the corpse position API (`C_DeathInfo.GetCorpseMapPosition`): #60;
- the nameplate distance console variable (`nameplateMaxDistance`): #89;
- `Bindings.xml` (read without a toc line; the "Noir Guides" header and click bindings): #59 and #87;
- the talent window anchoring (own frames on `TalentFrame`, its button names and selected tab): #93;
- the profession rank levels 10, 20 and 35 (`verified = false`): #45.

`tools/test/cleanroom.test.js` (new) keeps the clean room: no file under `NoirGuides/` or `tools/` (outside `tools/data/`) names the old fork's folder, no tool names an absolute path outside the repository (only the 7-Zip and Windows `tar.exe` programs that unpack downloads), and every addon source starts with the license line. `tools/compare_fork.js` and its test are deleted: the clean room forbids reading the fork, which was all that tool did.
