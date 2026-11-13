# Noir Guides: guide behavior specification

Date: 2026-11-11. Status: spec for implementation.

## How to read this

This is the behavior that Noir Guides must reproduce so that it plays like the leveling-guide addon the owner used before (called "the reference addon" below). It was written by reading that addon's behavior, its public material and the owner's own Forever additions. It contains no code, no identifiers, no guide syntax, no guide wording and no visual values from the reference addon. Implementers build from this document and from Noir's own `DESIGN.md`; they do not need, and must not use, the reference addon itself.

- "Must" is a requirement. "Should" is wanted but can come later. "Note" explains why.
- Behavior the owner wrote for Forever on top of the reference addon is marked **(Forever addition)**. It is the owner's own work and can be reproduced as described.
- Numbers given in seconds, yards, levels and counts are behavior and must be kept. Visual sizes and colors are not given; `DESIGN.md` decides them.
- Section 8 grades each behavior against Noir 0.1.1 and says which Noir pieces to replace rather than patch.

### The owner's three requirements after playing Noir 0.1.1

These override anything else in this document that seems to conflict.

1. **Clean, orderly windows that never open off-screen.** Every window has a sensible default place, is kept fully on the screen at all times, can be moved, locked, scaled and reset, and remembers where it was put (section 4.1).
2. **Nothing the player needs depends on typing a command.** Choosing the route, finding the character's place in it, showing the arrow and pins, moving to the next step and loading the next section all happen by themselves. Every action a command offers must also be reachable with the mouse (the window's menu, the step list, the settings panel or the minimap button). Commands are optional extras (section 6.2 lists every automatic behavior).
3. **Behavior parity, not affiliation.** The target is the same behavior and an equally clean look, under Noir's own name, design and data.

---

## 1. Overview of the experience

**Install and first login.**
1. The player installs the addon and logs in. With no extra step, the guide window appears in its default place (left edge of the screen, a little above the middle), the arrow appears near the top middle, and a minimap button appears on the minimap's rim.
2. For a new character (level 1, no guide ever chosen) a short setup wizard opens by itself a few seconds after login. It asks a handful of yes/no questions (section 6.1, "setup wizard") and recommends the starting section for the character's race. One click on Finish loads it. Closing the wizard without choosing also loads the recommended section.
3. For a character that is already past level 1 and has never used the addon, the addon picks the section that fits the character's race, faction and level and places the character inside it from the quests already done and in the log (section 2.5). The player can change the choice from the window's menu.

**A session.**
1. The window shows the current step (one or more lines: accept these quests here, kill these, loot that) with a tick box on each line. Under it is a scrolling list of every step in the section, with done steps dimmed.
2. The arrow points to the current step's place and shows the distance in yards. Pins mark the current step and the next few on the world map and the minimap.
3. When the player talks to a quest giver named by the current or next step, quests are accepted and handed in automatically. At a flight master the right destination is taken. At an innkeeper the hearthstone is bound when the step says so.
4. As each line's condition is met in the game (quest accepted, objective counter full, place reached, flight taken), its box ticks itself. When every line of the step is done, the window moves to the next step within a fraction of a second, and the arrow and pins move with it.
5. Steps that are already done (quest done earlier, quest already in the log, character already past the level) pass by themselves.
6. When the section ends, the next section loads by itself (for example "6-11 Durotar" after "1-6 Valley of Trials").
7. At logout the place is saved per character and per section. At the next login the window opens on the same step.

**Things the player can do by hand, all with the mouse.**
- Tick a line to treat it as done; untick to undo.
- Right-click or double-click any step in the list to go to it.
- Right-click the window header (or click its menu button) to choose another section, reload the section, open settings or report a problem.
- Use the item button next to the window to click a quest item; use the target buttons to target a quest mob or NPC.

---

## 2. Guide model

### 2.1 Sections

A route is divided into **sections** (the reference addon calls them guides). A section is a few hundred steps at most, covers one zone or a short chain of nearby zones, and has a level range.

Each section has:
- **A name made of its level range and its main zone**, for example "1-6 Valley of Trials", "12-17 The Barrens", "22-24 Hillsbrad Foothills". Single-digit levels are padded internally so that sections sort in level order; lookups accept both forms.
- **A display name that may differ by class or race** (one section can read "13-16" to one class and "15-16" to another, because some classes join later).
- **A group** (the faction's main route, the faction's dungeon route, optional side content) and **a subgroup** (a level band such as 1-20, 20-30, 30-40, 40-50, 50-60, or a theme such as "class quests").
- **Who it is for**: faction always; optionally race, class, or a combination (with "not" and "or"). A section that does not apply to the character is not offered.
- **Who it is the default start for**: race and/or class. Sections that are not the default for this character are "unused" and are only listed when the player turns on "show sections for other races and classes" (default off).
- **Its next section**: one or more candidates in order, each optionally conditional on class or race, and optionally in another group. See 2.4.
- **A maximum level** (optional): above it the section is not offered when "skip content you outlevel" is on.
- Optional flags: looping (wraps to its first step at the end), "dungeons off" for open-world sections, a list of quests the automation must never touch in this section.

**Requirement on Noir.** Noir's one flat route per race must be emitted as a chain of sections. The planner already commits to zones; each zone commitment (or a short run of them) becomes a section, named by the character's level range across it and the zone. Per-race starting sections, then shared faction sections, as in 2.3.

### 2.2 The section picker

Reached from the window's menu (right-click the header, or the menu button), and from the setup wizard.

- Top level: the groups that apply to the character, sorted by an order weight, then by name. Unused sections under their own heading, only when the setting is on.
- Inside a group: subgroups as submenus in level order; sections in level order.
- Each entry shows the section's name with its level range set to the right. The section being played is highlighted. An entry whose range contains the character's level is marked as "your level"; ranges already passed are marked as such **(Forever addition: the coloured marker tab per entry)**.
- Submenus open on hover, to the right, or to the left if there is no room. A long list scrolls with the mouse wheel and opens scrolled to the current section. Escape or a click outside closes the whole menu.
- Picking a section loads it at its saved place (or its start). If the section actually changed, the quest cleanup window opens 3 seconds later, but only if at least one quest in the log would start ticked for abandoning, and only if "offer cleanup after changing section" is on (default on) **(Forever addition)**.

### 2.3 Automatic selection

- **New character (level 1, nothing saved):** the setup wizard opens about 2 seconds after entering the world. Its section list shows only sections whose level range contains the character's level, with one marked recommended and placed first. The recommended section is the first of:
  1. the section already loaded;
  2. a section whose name contains the current zone or subzone name, preferring one that is the default for the character's race or class;
  3. the group's default section (the first that applies, by sorted name);
  4. any section that is the default for the character.
- **Requirement on Noir:** because Noir has no hand-authored picker step, a character that is not level 1 and has nothing saved must also get a section automatically: the section of the character's race route whose level range contains the character's level, refined by zone as above, then placed by 2.5. The wizard may still open for it, but closing it without a choice keeps the automatic one.
- The reference addon never switches sections in the background after that, except at a section's end (2.4) or when a step explicitly loads another section.

**Starting sections per race (Forever).** The route each race starts on, and where it joins the shared faction route:
- Human: Northshire, then Elwynn Forest, then Loch Modan and Westfall (hunters go to Darkshore instead of Westfall).
- Dwarf and Gnome: Coldridge Valley, then Dun Morogh, then a class/race-dependent hop (Elwynn, a warlock pet quest, Loch Modan), then Westfall or Darkshore.
- Night Elf: Shadowglen, then Teldrassil, then Darkshore.
- Orc and Troll: Valley of Trials, then Durotar in two parts, then either Tirisfal and Silverpine (most classes) or The Barrens (hunters and shamans).
- Undead: Deathknell, then Tirisfal, then Silverpine or The Barrens.
- Tauren: Camp Narache, then Mulgore, then The Barrens.
- High Order and Windshaper (Forever's two Skyborne races, told apart by faction) **(Forever addition)**: Zephras Isle 1-9, then 9-13 (9-12 for Horde), then the faction route (Alliance: Westfall, or Darkshore for hunters; Horde: Silverpine, or The Barrens for hunters).
- Shared Alliance: Westfall, Darkshore, then Redridge and Ashenvale, then the 20-60 chain. Shared Horde: The Barrens, Stonetalon and Ashenvale, Hillsbrad, then the 20-60 chain.

### 2.4 Loading the next section automatically

When the current step passes the last step of a section:
1. A looping section goes back to its first step (once).
2. Otherwise, if any reminder step (3.6) is still open, the window stays on the last step until the reminders are done.
3. Otherwise the next section loads: walk the candidates in order and take the first that exists and applies to the character. If none applies, take the last listed. If the chosen one is excluded by a setting, follow that section's own next list instead.
4. The new section starts at its saved place (or its start), and steps already done pass by themselves (3.4). No cleanup prompt is shown for this automatic change.
5. If there is no next section, the window stays on the last step and says the route is complete.

A step may also carry "load this section when this step becomes current" (used where a route forks), and a line may be clickable text that loads a named section.

The dungeon and open-world families each chain within themselves. The choice between them is made once, when the first section is picked (wizard, "dungeon route" or "open world route").

### 2.5 Joining mid-way and finding the place

The reference addon does this without any command:
- the wizard and picker offer only sections that contain the character's level;
- inside the chosen section, quest steps whose quest is already in the log or already handed in complete the moment they become current, so the window runs forward on its own through work already done;
- steps the character has outleveled are skipped (3.7);
- the player can right-click any step in the list and go to it.

**Requirement on Noir.** Keep Noir's automatic placement from quest history (since 0.1.1) and run it without any command:
- on the first login with the addon, when the route or section changes, and when a saved place no longer matches the route file;
- also when the character's quest log shows clearly that they are elsewhere: at login, if the saved place is behind work the character has already done (several later quest steps done or in the log), move forward and say so in one chat line; never move backward on its own.
- The result is shown in the step list (the current step highlighted and scrolled into view) so the player sees where they are and can click another step if they disagree.

### 2.6 Saved state per character

- Current section; for every section played, the place in it (by a stable step identity, not only its number, so an edited section keeps the place) and the reminder steps already finished.
- Steps the player ticked by hand.
- Flight points known, explored subzones, quest names cache.
- The identity of the character that saved it. At level 1, if the saved data belongs to a different character with the same name (deleted and recreated), a confirmation asks whether to reset.
- Switching to another section and back resumes where the player was in each.

---

## 3. Steps

### 3.1 What a step contains

A step is everything the player does at one place or in one go. It has one or more **lines** (elements). Each line is one condition or one piece of information.

**Requirements on the step data:**
- A step can bundle several quest actions at one place: accept two or three quests from the same NPC or hub, hand in several, accept the follow-ups, and so on. It is complete when all its lines are complete.
- A step can bundle the objectives of several quests that are done in the same area ("kill boars and collect tusks for both quests").
- A step may carry a short instruction note (one or two lines), for example where to stand or which way to enter a cave. Notes are display-only.
- A step may carry a title shown on its badge, a minimum level, a stable identity, and a label other steps can refer to.
- A step may be limited to a class, race, faction, or a combination (with "not" and "or"); a single line inside a step may be limited the same way. A step or line that does not apply simply does not exist for the character.

Noir builds its text from data, which is right and should stay: a bundled step reads as several generated lines ("Accept Quest A", "Accept Quest B", "Turn in Quest C"), each with its own tick box, plus any note.

### 3.2 Kinds of line and when each completes

Every line is one of three kinds:
- **Active**: has a tick box and must be satisfied for the step to complete.
- **Passive**: display only (notes, pins, target lists, item buttons). Never blocks the step and counts as done.
- **Step-level conditions**: invisible or display-only checks that skip the whole step when they hold (3.5).

A line with no text is invisible and counts as done.

The step is complete when every line is done, ticked by the player, or passive; or when a step-level condition forces it complete; or when its "ends with" link is satisfied (3.6).

Once a line has completed while its step is current, it stays done until the step is entered again, even if the condition goes away for a moment (a latch). Unticking by hand is the only way to clear it.

**Quest lines**

| Line | Data | Shows | Done when |
|---|---|---|---|
| Accept quest | quest; optional "don't auto-accept"; optional "only if quest X was handed in" | an accept icon and "Accept" plus the quest name (filled in when the name arrives from the client); if prerequisites are known to be missing, an error icon with a tooltip listing them (never skips) | the quest is in the log, or is handed in, or an accept event for it arrived; an accept within the last 2 seconds counts. With the "only if X" option, done at once when X is not handed in |
| Hand in quest | quest; optional reward choice; optional "don't auto-turn-in"; optional "skip if not in log" or "skip if not complete" | a hand-in icon and "Turn in" plus the name | a hand-in event for the quest, or the quest is flagged handed in; a hand-in within the last 5 seconds counts. The skip options complete it when the quest is missing from the log or not ready |
| Quest objective | quest; objective number; optional cap on the count; optional "skip if not in log" | the live objective text with its counter (have/need), a kill icon for kill objectives, a bag icon for items; a quest with no objectives shows a single 0/1 | the objective is finished, or the count reaches the cap, or the quest is complete or handed in |
| Objective as step skip | same, hidden | nothing | when the objective or quest is done, the whole step is skipped with a tooltip saying why |
| Abandon quest | one or more quests | "Abandon" plus the name | none of them is in the log (the player abandons by hand) |
| Several quests at once | a list | one line per quest | each as above |

**Travel and place lines**

| Line | Data | Shows | Done when |
|---|---|---|---|
| Go to | zone, coordinates, arrival radius in yards, optional text | "Go to x, y (zone)" and an arrow target and pin | the player comes within the radius. With no radius: arrow and pin only, done when the line it belongs to is done. Radius zero: pin only, no arrow |
| Path point | zone, coordinates, radius | nothing in the window; arrow only | reached within the radius while it is the arrow's target, so path points are visited in order |
| Nearest of several | several places marked "nearest" | arrow to the closest one | as go-to |
| Persistent point | place and radius | arrow only | never; hidden while inside the radius, back when outside |
| Zone arrival | zone | "Go to zone" | the player is in that zone; this completes the whole step |
| Subzone arrival | area | text | the player's subzone matches (or does not, if inverted) |
| Explore | area | text | the area is discovered |
| Get flight point | flight point name | "Get the X flight point" | the point is known (or was just flown from or to), or the discovery message arrives. A known point with no text skips the step |
| Fly to | destination | "Fly to X" | the player is on the flight (or lost control within 1.5 seconds of the flight starting) |
| Set hearthstone | inn's area | "Set your hearthstone to X" | the bind is confirmed, or the hearthstone is already set there |
| Use hearthstone | destination text | "Hearth to X"; puts the hearthstone (and Astral Recall for shamans) on the item button | a successful hearthstone or recall cast |
| Die and respawn | none | text; the arrow points to the nearest spirit healer while a ghost | the spirit healer's resurrection is taken |

Note: in the reference addon, the hearthstone and fly lines only self-complete when their automation is switched on. Noir must not copy this quirk: they complete from the game's state whether or not the automation did the work.

**NPC and service lines**

| Line | Done when |
|---|---|
| Visit vendor / trainer / stable (optional NPC) | that window closes after being opened (at that NPC if given) |
| Learn spell | the spell is known (a profession rank counts as known while the profession's skill cap covers it); while open, the spell is added to the trainer's auto-buy list |
| Talk through N dialogue pages with an NPC | N pages were opened |
| Pick a dialogue option (by option) | the option was seen or picked |
| Tame a beast | the tame cast succeeds |
| Cast a spell | a successful cast of the spell |
| Emote at an NPC | performed automatically when that NPC is targeted |
| Enter or leave a vehicle | on entering or leaving |

**Item lines**

| Line | Data | Done when |
|---|---|---|
| Collect item | item (alternatives counted together), count, quest, which objectives it serves, options (count the bank, subtract objective progress, ignore quest completion, profession-based count) | count in bags (and bank if asked) reaches the required count; when the quest is complete or handed in the line shows full and completes. Required count zero hides the line |
| Collect a total for several quests | item | sum of what each unfinished quest needs |
| Quest-starter item | item, quest | the item goes on the item button until the quest is in the log |
| Buy from vendor | item, count, optional quest/objective | passive; when a vendor selling it opens while the step is current, it is bought (see 5.6) |
| Throw away item | item | none left; while open, the item is marked as junk |
| Use item / spell | item or spell | passive; it goes on the item button while the step is current |
| Bank deposit / withdraw | items | none left on the source side (moved automatically while the bank is open) |
| Take from mail | item, count | passive; taken automatically from the mailbox |

**Character lines (each can complete the line or, as a condition, skip the step)**

| Line | Rule |
|---|---|
| Reach level / XP | target level L with an optional amount: "N xp away from L", "N xp into L", "P% into L", or plain "reach L". While the player is at that level the text adds current/needed. Reached when the level is above L, or at L with XP at or past the amount (for "away from": at L-1 with at most N XP left). As a line it completes when reached. As a condition it skips the step, or jumps to a labelled step, when reached (or when not reached, if reversed) |
| Maximum level | when the player is above level L, skip the step or jump to a label; the text "skip this if you are level L+1 or higher" appears only once it applies |
| Skill | profession or riding at or above (or below) a value, current skill or skill cap |
| Reputation | standing (plus an amount into it) with a faction |
| Money | more or less than an amount (optionally counting sellable junk) |
| Item count | have (or not have) N of an item |
| Equipped / item stat | slot holds an item, or a stat compared to a value |
| Buff | an aura present (or absent), with optional time left or stacks |
| Cooldown | an item or spell cooldown above or below N seconds (rechecked when it crosses) |
| Bag slots, alive or dead, countdown, logout | as their names say; countdown completes after N seconds on the step |

**Display and helper lines (passive)**

- Note text; a note hidden from the step list; a "manual" line that is text with a tick box the player must tick.
- Group note ("do not try unless in a group of N"): the step only exists when group quests are on. Solo note: only when they are off.
- Clickable link that opens a copy box with a web address.
- Target lists: friendly NPCs to talk to, enemies to kill, rare or dangerous units to watch (feed the target buttons, 4.5).
- Timer: a countdown bar that starts when its parent line completes.
- Pins without arrows, lines drawn on the world map (a path or a patrol loop), and a loop of points the arrow follows around.

### 3.3 How the current step is chosen

- The section has a **place**: one step number.
- **Several steps can be on screen at once**: the step at the place plus any open reminder steps from earlier (3.6), deferred steps that have come back at their level (3.7), detours, and nearby objective steps (below). Each shows as its own card with its own badge, in this order: deferred, reminders and detours (step order), nearby (step order), the current step last (nearest the window, with the accent frame).
- **Nearby objectives together:** while the current step is an objective step (only kill, collect and objective lines), the objective steps right after it whose areas lie within 150 yards of its area (the planner's objective bundling radius), whose quests are in the log, that are at or above their level and need nothing the current step does, show as "nearby" cards, at most 3. Steps already done are passed over; the first step that does not qualify ends the run, so a hub turn-in or a move is never pulled forward ("travel back" comes after the area is done). Lines finished on a nearby card stay latched; when the place reaches that step it passes as done, with no why entry (the player did it in front of the window). A nearby step whose lines are all done is no longer shown.
- **Moving the place:**
  - When the step at the place completes, the place moves to the next step on the next update.
  - A step whose minimum level is above the character's is not shown: with "work ahead" on (the default), it is deferred and the place moves past it to work that can be done now, as 3.7 describes. With nothing to do ahead (or "work ahead" off, or a step the player went to from the list) it stays the place with a grind line first, and the arrow points at the grind area, never at the gated step.
  - A step that requires another labelled step waits while that step is still on screen or still ahead.
  - The place never moves by more than one step per update pass, but passes are frequent (several per second), so a run of done steps flashes past in about a second.
- **"Step complete" and "objective complete" signals** (used for party announcements and sounds) are only raised when more than 1 second has passed since the last step change, so a catch-up run makes no noise.
- **When the place changes**, every line of the steps that are no longer on screen loses its done and ticked state, so they are judged again if the player comes back to them.
- **Lookahead:** quests on the step right after the current one are already accepted automatically, and the text of the next 8 steps is kept up to date in the list.
- **Quest tracking:** when a step names a quest, the game's quest tracker is set to follow it.

### 3.4 Catching up at login and on reload

No replay of the whole section happens. The saved step is made current, its lines are checked at once along with the open reminders, and each step already satisfied completes and passes. The window therefore runs forward through finished work in about a second after login. Steps before the saved place are not re-checked, except reminders.

### 3.5 Skipping

**Automatic skips:**
- Quest lines complete themselves when the quest is already accepted or already handed in.
- Step-level conditions skip a step when they hold: on a quest, not on a quest, quest complete, quest not complete, quest handed in, quest not handed in, an NPC does not offer the quest (checked while talking to it), any of the listed spells known, level or XP reached, outleveled, skill, reputation, money, item count, cooldown, buff, zone or subzone, hearthstone already bound there. When a condition skips a step, its tooltip says why.
- Condition checks only run while the step is current, never while the window is hidden, and never when "never auto-skip steps" is on (Advanced, default off).
- Missing prerequisites are shown (error icon and tooltip) but do not skip.

**Manual skips:** tick every line, or go to another step from the list (3.8). Noir's why-log idea should be kept: every step passed without the player doing it in front of the window gets a reason the player can read (in the step's tooltip in the list, and in the log).

### 3.6 Reminder steps and "ends with" links

- A step can be marked to **end when another step is reached** (the next one, or a labelled one). Such a step becomes a **reminder**: it stays on screen above the current step while the player works on later steps, and ends when the place passes the named step. Typical use: "collect 10 hides while you do the next five steps", "keep an eye out for this rare".
- A reminder only shows once the character meets its minimum level and its own requirement.
- A reminder finished early is remembered for the section.
- A reminder never becomes "the place" itself.
- When a normal step requires a reminder that has no end link, the reminder ends at that normal step.

### 3.7 Outleveling and level logic

- **"Skip content you outlevel"** (default on; changing it asks for confirmation and reloads the section): sections and steps with a maximum level below the character's are left out, and maximum-level and XP conditions skip steps at runtime. Turning it off keeps every quest ("discovery" mode in the wizard).
- **Grind targets:** a step can say "grind to level L" or "until N% into level L" in a named area, with the live counter. It completes when reached.
- **Level gates on later content:** a step that needs a level has that level as its minimum (trainer visits, quest accepts). If the character is under it when the place reaches it, the window does not stall silently and the arrow never points at it:
  - **Work ahead** (setting "Work ahead while under level", Route, default on). The engine looks at the next steps, up to 8 past the earliest step still waiting for its level and never past the end of the section. Steps that pass by themselves (hidden, reminders, done, outleveled, a skip condition holds) are passed over; steps under their own level are deferred too; so is every step that needs a deferred one (it uses a quest a deferred step still has to accept, accepts a quest whose prerequisite a deferred step still hands in or accepts, or requires its label), so no detour ever points back at a gated step. The first other step is taken if it is work (not a move) in the gated step's zone within 300 yards of the player or of the gated step; any other step ends the look with nothing found. When something is found, the gated step is deferred (why-log "deferred until level L"), remembered per section with its level, and the place moves on. While a deferred step waits for its level, a later step at the place that needs it is deferred the same way, and one the look would not take (too far in steps or yards, a move, a hub elsewhere) is not shown: a grind card stands in until the level comes.
  - **Coming back.** A deferred step is hidden while under its level; the moment the level is reached it comes back as a "deferred" card, first in the stack, so the arrow points at it. It closes when its lines are done (no why entry), or with a why entry when it was already done when it came back, is outleveled, or a skip condition holds. Deferred steps with work left hold the end of the section like reminders, so deferral never crosses into the next section. A reminder whose "ends with" step is deferred stays open until that step is done.
  - **Grinding.** With nothing to do ahead, a grind line ("Grind to level L") with the live XP counter shows first: on the gated step's own card when the place is on it (its lines follow), else on a card of its own with the gated step's badge. Its place is the gated step's own objective area if it has one, else the area of the last objective, collect or grind step before it in the section in the same zone (deferred steps left out), else none; never the gated step's NPC. With "work ahead" off, the gated step always waits this way.
  - Placement for a character joining mid-way is unchanged: steps under their minimum level are not counted as missing. Note: Noir's planner currently passes such steps as "not part of the route"; parity needs grind steps wherever the planner's level estimate and the step's minimum disagree, not one grind at 59.
- **XP rate:** a setting (100% to 200%, auto-detected from equipped bonus-XP gear where the client has it) lets sections drop or add steps written for other XP rates. Should for Noir, later.
- There is no "you are X% behind" display in the reference addon. The level rail Noir already has is fine to keep.

### 3.8 Optional and conditional steps

- Class, race, faction and level conditions on steps and lines (3.1).
- Profession conditions: a step that only exists when a chosen profession is set in settings, or skips unless the character has the profession or a skill at a value. **(Forever addition)** Profession skill is read by skill line from the Professions book and the skill list, ignoring Forever's tier lines that have a parent; a profession not learned reads as "none". Forever trainers require skill 50 for Journeyman, 125 for Expert, 200 for Artisan; rank caps are 75, 150, 225, 300. A training step skips while the skill is below its gate and once the cap already covers its rank.
- Quest-state conditions (3.5).
- Dungeon conditions: a step that only exists when its dungeon is enabled in settings (or only when it is not).
- Group-quest and solo steps; auction-house-only and self-found-only steps; dailies.
- Steps with no lines hide the step before them from the window and are themselves hidden from the list.

---

## 4. User interface

### 4.1 Windows: placement, anchoring, moving, locking, scaling, remembering

**Every window and where it opens by default:**

| Window | Default place |
|---|---|
| Guide window (current steps, header, step list) | left edge of the screen, a little above the vertical middle |
| Current-step cards | attached to the guide window, above its header (option: below the window); if that side would leave the screen, they flip to the other side automatically |
| Tip card | free, bottom-left of the screen |
| Arrow | top middle of the screen; "reset arrow" puts it slightly above the screen's centre |
| Item buttons | centre of the screen |
| Target buttons | centre of the screen, a little below the item buttons |
| Menus (picker, step menu, settings menus) | at the mouse cursor, cascading to the right (left when there is no room), each level capped to most of the screen height and scrolling |
| Setup wizard | upper right of centre |
| Settings | inside the game's own options window, under AddOns, as the addon's own page |
| Leveling report | docked to the character panel |
| Quest cleanup, bug report, small dialogs | centre of the screen |

**Rules for every window (must):**
- **Never off-screen.** Every window is kept fully inside the screen at all times: when it opens, when it is dragged, when it grows (more steps, more buttons), when the UI scale or resolution changes. A saved place that is now outside the screen is pulled back in at login. A menu or panel taller than the screen is capped to the screen and scrolls; it never extends past an edge.
- **Moved** by dragging with the left mouse button (the guide window by its header or body; others by their frame).
- **Resized** (guide window only) by dragging the corner grip or Alt-dragging; the step list's height is saved.
- **Locked** by one setting ("lock windows", default off) that stops all moving and resizing. Alt-drag still moves the item and target buttons when locked.
- **Scaled** by settings: guide window 20% to 200%, arrow 20% to 200%, item and target buttons 80% to 300%. Scaling keeps the window's corner where it was.
- **Remembered** per profile at logout and before a profile switch: position and size of each window. Restored at login.
- **Reset**: buttons in settings to reset the arrow and the item buttons, and "reset profile" restores every window's default place.
- **Preview positions**: a button fills every window with sample content so the player can place them all, then returns to the real section.
- **Hide in raids** (default off) hides everything in a raid group and shows it again after.
- A global show/hide (minimap button left click) hides every addon window; the guide keeps following the game while hidden.

**The settings entry points (must):** the game's own options window (AddOns page), the minimap button (right click opens the main menu, which has Options), the window's menu (Options), and an optional command with no arguments. The settings panel cannot open in combat; the request is remembered and it opens when combat ends.

### 4.2 The guide window

- **Header:** the section's title (its name), with its subgroup on a second line when it has one. A menu button opens the main menu; right-clicking the header or footer also opens it. With no section loaded, the header invites the player to pick one and the window collapses to the header.
- **Current-step cards:** one card per step on screen (current step plus open reminders), stacked. Each card has a badge with the step's title or its number, and one row per visible line: tick box, kind icon, text. Hovering a line shows its tooltip (for example missing prerequisites, why a step will skip); hovering a tick box says it skips that line.
- **Quest names are links** on accept and hand-in lines (when the name is known): hovering shows the quest tooltip.
- **Words for named things are highlighted by meaning**: friendly NPC, enemy, item to loot, warning, object to click, item to buy. The player can recolour each or turn this off.
- **Kind icons** for: accept, hand in, objective, item, kill, vendor, trainer, gossip, flight, flight point, hearthstone, bind, go to, XP/level, error, timer.
- **Footer:** version text, the resize grip; while a timer bar runs (flight), the bar takes the footer's place.
- **(Forever addition)** The header shows the range of step numbers in view; the footer shows the character's level and the share of the section done; a thin rail beside the window shows progress through the section's level range with a tick per level when the range is 20 levels or fewer. A new current step slides in and its side bar marks the step's kind for 3 seconds; kinds in order of prominence: hand in, accept, train, objectives, travel.
- **Tip card:** a separate movable card for tips written into the section; right-click to hide tips; a menu toggle shows them again.
- **Combat:** the window keeps updating in combat (it is not a protected frame).

### 4.3 The step list

- Below the header: every step of the section, one row per step, with each line's icon and text indented, and the step number at the corner.
- **States:** steps before the place, finished steps and finished reminders are dimmed to about half; the current and later steps are full; hidden, optional and above-level steps are not shown.
- **Hover** brightens the row.
- **Right-click, or double-click within 0.5 seconds**, opens the step menu: go to this step (jumps at once, forward or back, no confirmation), choose another section, reload section, options, report a problem with this step, close.
- **Scrolling:** mouse wheel and scrollbar; when the place changes the list scrolls so the current step is at the top. With "hide finished steps" on, the list cannot scroll above the current step.
- **Show the step list** (default on): off collapses the window to the cards and header.
- No keyboard navigation of the list.

### 4.4 The arrow

- Points to the current target, turning with the character's facing (small jitters ignored); the label under it is the target's title (or the step's title or number) and the distance in whole yards.
- **Target choice:** while a ghost, the corpse (or the nearest spirit healer if a step says die and respawn; a step can suppress the corpse arrow). Otherwise the first eligible place in the cards on screen, in card order (deferred steps first, then reminders and detours) then line order: not hidden, its line not done, not already reached. When nearby objective cards are shown (3.3), the places of the current and nearby cards are one group and the arrow points at the nearest of them; it moves to another only when that one is nearer by more than 15 yards and by more than 20% of the distance, so two near-equal places do not make it flip. A card that asks for a grind gives only its grind place: the arrow never points at a step the character's level does not allow yet. If none, the low-priority places. Among places marked "nearest", only the closest is eligible.
- **Arrival:** checked about three times a second. Inside the radius the place is marked reached (remembered for that step while it is on screen), its line completes if it is a go-to, any attached timer starts, and the arrow moves to the next place. A place with no radius never completes on arrival.
- **Loops:** when all points of a looping set are reached they reset; on a patrol loop the arrow follows to the neighbouring point the character is heading for and resets after straying more than 1.3 times the leg length (at least 1000 yards).
- **Other continent:** the arrow freezes and shows that the target is elsewhere; one chat line says so.
- **Hidden** when the arrow setting is off, when there is no target, in instances, or when the client gives no position.
- Draggable, saved, lockable; settings for scale and label size; "reset arrow" re-enables it and recentres it.
- The arrow is on by default and needs no command.

### 4.5 Pins and lines on the maps

- **World map:** pins for the steps on screen, then the following steps, up to a limit ("Upcoming steps on the maps", default 8, setting 0 to 20; raised so every pinned line of the steps on screen fits). Pins also appear on sub-zone maps that contain the place. Not drawn in instances.
- **Minimap:** the same steps as the world map (setting to turn off). Out of range, only the current step's pin waits on the rim; the others are left out.
- **Merging:** pins closer than about 60 yards (scaled by a setting, 0.05 to 2) share one pin on the world map; about 25 yards on the minimap. A merged pin shows a "+".
- **Pin label:** the step's icon or number. The current steps' pins are larger and fully opaque; later pins fade a little per step. Optional ring around the current pin. Settings for pin size and background opacity.
- **Tooltip** on hover: for each merged line, the step's title or number and the line's text.
- **Lines** drawn on the world map (paths, patrol routes, dashed segments) for the steps on screen, when that zone's map is shown.
- Reached places, ticked lines and lines whose parent is done have no pin. Pins rebuild about three times a second at most and when the map's zone changes.
- **Dangerous mobs** (setting, needs tips on): per-zone elites, rares and patrols as pins or patrol lines with a tooltip (name, level, kind, movement, note), shown only when the mob's top level is at least the character's level minus 1 (normal) or minus 3 (elite or rare). Never on the minimap.

### 4.6 Item, spell and target buttons

**Item buttons** (a single row of buttons beside the window):
- Built from the steps on screen: items named by use lines, items tied to accept/hand-in/objective lines, quest-starter items until the quest is taken, the hearthstone (and Astral Recall for shamans) on hearth lines, spells the player knows, macros the step defines.
- Order: spells, macros, equipped items, bag items in bag order, toys.
- Click uses the item; cooldowns are shown; hover shows the tooltip.
- Shown only when there is at least one button. Not rebuilt in combat; rebuilt when combat ends.
- Key bindings for the first four buttons.

**Target buttons** (two groups: enemies from the top, friendly NPCs from the bottom, four per row):
- From the target lists of the steps on screen, low-priority names last.
- Each button shows the unit's portrait once seen, else a placeholder; tooltip is the name.
- Click targets that exact name and, if marking is on, puts a raid marker on it (friendly: star, circle, diamond, triangle by position; enemies: skull, cross, square; rare and scan units: moon). In a group with other users, each user gets their own marker.
- A friendly target the player talks to is removed from the list.
- Hidden on a flight, while hearthing, in raids, and when there are no targets.
- Key bindings for the first four friendly and four enemy buttons.
- Raises the nameplate distance (setting, default on) so marked mobs are seen from further.
- **(Forever)** The client forbids addons from writing macros; the buttons themselves are secure buttons carrying their own targeting action, which is allowed. No account macro is created.

### 4.7 Notifications and sounds

- **No sound or popup on step or quest completion** by default. The reference addon is quiet; Noir's quiet design matches.
- Optional chat announcements to the party (5.10).
- **Drowning warning** (default on): when breath falls below a threshold (default 20%, 5% to 50%), at most once a second: screen flash, taskbar flash, a message in the error text area, a warning sound. Each part can be turned off.
- **Low health** (default on): below a threshold (default 20%), emergency items and spells on the action bars glow; optional screen flash.
- **Rare nearby**: one chat line per rare, one sound per refresh (chosen sound and channel), optional taskbar flash. Hidden on clients where scanning is not possible.
- **Flight timer bar**: starts when a flight begins within 1.5 seconds of picking a destination, labelled with the destination, counting down; hidden on landing. The flight map's node tooltips show the flight time.
- **Chat lines**: the target is on another continent; a step requirement loop; a newer addon version or section version seen in the group (once).

---

## 5. Automation and helpers

General rules:
- Every automation has a switch in settings.
- **Holding Ctrl** when an NPC window opens skips quest accept, hand-in and reward automation for that interaction. **Holding Shift** skips flight, bind and dialogue automation. Noir currently uses Shift for all; it should follow this split so the keys feel the same.
- Automation only acts for quests and places the guide names; anything else is left to the player.

### 5.1 Accepting quests (default on)
- Only quests named by accept lines of a step on screen **or the step right after the current one**, and not excluded by the step or the section.
- Matched by quest identity, or by title where the client gives only titles.
- In the NPC's dialogue list: first a complete quest the guide hands in, then a quest the guide accepts, then an incomplete quest whose only objective is talking to this NPC.
- On the quest's detail page: accept and close. If a hand-in happened less than 0.5 seconds before and the offered follow-up is not a guide quest, close it.
- A shared quest from a party member and an escort start confirmation are accepted under the same rule.

### 5.2 Handing in (default on)
- Any quest named by a hand-in line of a step on screen, unless the line says manual. A hand-in line that has been on screen keeps its quest eligible for the session.
- On the progress page, continue if the quest can be completed. On the reward page, see 5.3.
- Auto-complete popups for guide quests are clicked.

### 5.3 Reward choice
- No choice or one choice: take it.
- The step names a reward and "choose the guide's rewards" is on (default off): take it.
- Otherwise mark the reward with the best vendor value with a coin icon (default on) and leave the page to the player. (The reference addon's upgrade scoring is not part of this spec.) An optional, default-off auto-pick takes the best-value reward for guide quests.
- The same markers appear in the quest log when a quest with choices is selected.

### 5.4 Flights (default on)
- At a flight master, when a fly line is on screen, the flight option in the dialogue is picked once per step; when the flight map opens, the first node whose name contains the destination is taken.
- **Requirement on Noir:** match by flight point identity first (Noir has node IDs), by name only as fallback.
- **Flight point discovery:** every time the flight map opens, all known nodes are recorded for the character; the "new flight path" message marks the current zone's point known. A get-flight-point line re-picks the flight master option at most once every 10 seconds.
- **(Forever addition)** New Forever flight points (Riverglades, Mount Hyjal) have no known flight times; flights to them work and are announced without an arrival time.

### 5.5 Hearthstone (default on)
- On a bind line, the innkeeper's "make this your home" option is picked, and the bind confirmation is answered on the next frame (only that popup is closed).
- Hearth lines put the hearthstone on the item button.
- **Hearthstone batching** (Advanced, default off): if the player starts a hearth while the bind confirmation is up, the bind is accepted a few milliseconds (setting 1 to 50, default 6) before the 10-second cast ends, so the old home is used for the teleport and the new bind takes effect in the same server update. Should, later.

### 5.6 Vendors and inventory
- **Buy lines:** when a vendor opens on a step on screen, buy the item up to the count still needed (variants: buy N regardless of what is carried; buy as many as money allows up to N), capped by the vendor's stock, in full stacks; the vendor closes after the bags update. Skipped if the linked quest or objective is already done.
- **Junk** (master switch default on): grey items, plus a per-character list the player edits (modifier + right-click on a bag slot, default Ctrl). The hearthstone is never junk. Warlocks: soul shards above a keep count (default 100) are junk.
  - Sell junk at vendors (default off): everything junk with a value is sold, lowest quality and cheapest first; one chat line gives the total.
  - Destroy the cheapest junk when bags are full (default off): done on the player's next click on the game world (deleting needs a hardware event), never in combat or while dead. If loot fails for full bags, the next click deletes junk and loots.
  - A key binding destroys the cheapest junk.
- The reference addon has **no repair reminder and no auto repair**. Noir should add a repair line at vendor steps that can repair when durability is low (should, later).

### 5.7 Trainers (default off)
- For 15 seconds after a trainer opens, every 0.2 seconds: buy the class and race spells the character can learn at its level (lowest level group first), plus any spell named by a learn line on screen (at or below its rank). Pet trainers are skipped. No gold check; the game refuses what cannot be paid.
- **(Forever addition)** Profession trainers: a learn line for a profession rank is satisfied when the profession's cap covers that rank (ranks replace each other on Forever).

### 5.8 Dialogue (default on)
- A "skip dialogue" line picks option 1 when the NPC offers no quests (or a given option number, or a sequence of options cycling per page; class trainers with a respec option are left alone; nothing happens if the arrow points to another zone).
- A line can pick a specific dialogue option and confirm its confirmation popup.
- Options are recognised by type (flight, bind, trainer, spirit healer) before any text or icon fallback; no fallback while a modifier is held.

### 5.9 Quest log
- **Quest cleanup** (Forever addition, replaces the reference addon's orphan list): see 6.1. Opened from the menu, the settings, a button by the quest log, and automatically after a hand-picked section change (2.2). Nothing is abandoned until the player presses the button; quests are abandoned bottom first, one every 0.2 seconds, stopped by combat.
- The quest log's detail pane gets a button whose tooltip lists which sections pick up or hand in the quest; item tooltips list the sections that need the item.
- No automatic abandoning to stay under the quest log limit.

### 5.10 Party
- Hidden addon messages on login and when a group forms: name, class, level, XP, addon and section versions. Newer versions are announced once.
- **Share quests** (default off): when a guide accept line completes, the quest is pushed to the party if shareable.
- Party chat announcements, each with its own switch: finished objectives (off), collected items (off), flights with arrival time (on), level-ups to party, guild or as an emote with the time the level took (all off). Not in instances, not within 1 second of a step change, never repeated, never in combat, optionally only when another user is in the group.
- **Group mode** (default off) turns the group options on in one click.
- Party members' current steps in a small window (beta). Should, later.

### 5.11 Talents (Forever addition)
- Three builds per class (27), levels 10 to 60, one point per level, checked for legality at build time and matched to the live talent tree by name.
- A build is chosen per character and per talent loadout. Chat reminders only (5 seconds after login, 1.5 seconds after a level-up or loadout change): asked once to choose a build at level 10; told how many points are ready and the next one; warned once about points spent off the build.
- In the game's talent window: a build picker, an info line with the next point, and a pulsing ring on the next talent, all in the addon's own frames above the window without touching the game's frames. Points are only bought on the player's explicit request.

### 5.12 Leveling tracker (should, later)
Per level: time taken (from played time), XP from quests and kills by zone, solo vs group XP, deaths, XP per hour; a report docked to the character panel. A level-splits window (time at each level-up, compared with another character).

---

## 6. Settings and commands

### 6.1 Settings that matter to a player

Settings live in one panel in the game's options window, with tabs. Defaults in brackets.

**General:** show the addon [on]; lock windows [off]; hide in raids [off]; minimap button [on]; open setup wizard; open quest cleanup; report a problem; tips and warnings [on] with drowning [on, 20%] and low health [on, 20%].

**Guide window:** hide the window (arrow and pins stay) [off]; current steps above or below [above]; window scale [100%]; font size [standard; changing reloads the UI after confirmation]; show the step list [on]; hide finished steps [off]; show sections for other races and classes [off]; text highlight colours by meaning, or one plain colour; item buttons: hide, hide background, scale, reset position; preview window positions.

**Navigation:** hide the arrow [off]; arrow scale; arrow text size; reset arrow; minimap pins [on]; ring on current pin [off]; pins on the world map [7]; pin size; merge distance; pin background opacity; dangerous mobs on the map; flight timers [on].

**Automation:** accept and hand in quests [on]; choose the guide's rewards [off]; train spells [off]; take flights [on]; set the hearthstone [on]; pick dialogue options [on]; junk: manage [on], mark in bags [off], sell [off], destroy when full [off], modifier for marking, soul shards to keep [100], clear junk list; targeting: find quest targets [on], longer nameplate range [on], raid markers [on], target buttons [on]; group: group mode, share quests, version check, announcements.

**Route:** skip content you outlevel [on]; work ahead while under level [on] (3.7); XP rate [100%, auto-detect on]; solo self-found [off]; group quests [off]; dungeons to include (multi-select, with "all"); talent guides [on]; profession to level with the route.

**Advanced:** never auto-skip steps [off]; offer cleanup after changing section [on]; warn about conflicting addons [on] (checked 20 seconds after login: other arrow/map addons); update interval; hearthstone batching [off]; debug [off].

**Profiles:** account-wide profiles (new, copy, delete, reset); reset guide progress for this character; set the current profile as the default for new characters. Window positions are saved per profile.

**Setup wizard** (opens by itself only at level 1 with nothing chosen; reachable from the menu and settings any time): cards for open-world route, dungeon route, import, endgame (within 5 levels of the cap). Questions with "recommended" tags: use the auction house, group quests, skip content you outlevel, level a profession, show other sections. Dungeon page: presets (fastest, best upgrades, all, custom) with required dungeons locked on. Then the section list (2.3). Back, Reset, Finish.

**Quest cleanup window (Forever addition):** two groups with tick boxes, level, title and reason per quest; a button "abandon N quests" and a "keep everything" button; rows sorted with off-route quests first, then by level. Kept: anything the rest of the route mentions (this section to the end of the chain); never listed: class, profession, dungeon and raid quests and anything under the class or a profession header. Listed and pre-ticked: failed quests and quests off the route ("grey" when below the client's green range). Listed but not ticked: grey quests still on the route, quests ready to hand in, event quests, quests started by an item. (Noir 0.1.1 starts every row unticked; either is acceptable as long as nothing is abandoned without the button.)

### 6.2 What happens automatically (no command needed)

Every one of these must work with no command typed:

1. The setup wizard opens for a new character; a section is chosen for any character that has none (2.3).
2. The character's place in the section is found from quest history on first use, after a section or route change, and when the saved place is behind work done (2.5).
3. Steps already done pass by themselves at login and during play (3.4, 3.5).
4. Outleveled steps and sections are skipped (3.7).
5. The next step becomes current when the step is done; the next section loads at the end of a section (2.4).
6. The arrow is shown and points to the current target; pins are drawn; both follow the step.
7. Quests are accepted and handed in, flights taken, hearthstone bound, dialogue picked, items bought, spells trained (each per its switch).
8. Item buttons and target buttons appear when a step needs them.
9. Flight points are recorded whenever the flight map opens.
10. Window positions are saved and restored; off-screen windows are pulled back.
11. Talent and profession reminders arrive in chat at the right moments.
12. Quest cleanup is offered after a hand-picked section change.
13. Version notices, conflict warnings and the recreated-character check run by themselves.

### 6.3 Commands (optional extras)

One command word with subcommands, all of which must also exist as a menu entry or button: open settings (no argument), show/hide/toggle the addon, open the setup wizard, quest cleanup, talents, report a problem, preview window positions, help. Noir may keep its diagnostic commands (why, state, problems, step, skip, back) as extras, with "skip" and "back" also reachable from the step menu.

---

## 7. Data each step needs, and where the planner gets it

QuestieDB is the Forever quest database the planner reads; wago means the client tables fetched from wago.tools.

| Requirement | Exists in | Notes |
|---|---|---|
| Quest identity, name, level, required level, race and class limits | QuestieDB | already used |
| Who starts and ends a quest (NPC, object, item) and their positions | QuestieDB | already used |
| Objectives: kind (kill, item, object, event), creature/item/object, count, spawn positions | QuestieDB | already used; counts come from the client at run time |
| Prerequisites, exclusive groups, breadcrumbs, follow-ups | QuestieDB | already used |
| Required skill, reputation, spell, maximum level | QuestieDB | read by the planner; must be emitted as step conditions |
| Items needed to start or use for a quest (quest-starter and usable quest items) | QuestieDB (source item, required source items) | must be emitted on steps for the item button |
| Item drop sources (which mobs drop an objective item) | QuestieDB | for target lists and pins |
| Quest XP | QuestieDB support files (classic XP table, partial Forever traces) | present but unused by the planner; needed for grind targets and level estimates |
| XP per level | known table (already in the planner) | |
| NPC services (vendor, trainer, innkeeper, flight master, repair) and positions | QuestieDB NPC flags and spawns | for vendor, trainer, repair and bind steps |
| What a vendor sells (for buy steps) | QuestieDB item vendor lists (partial) | otherwise hand authoring |
| Flight points, their positions and connections | wago (flight nodes, paths) | already used |
| Flight times | wago path node geometry, computed | not given directly; Forever new nodes need measuring |
| Zones, subzones, map IDs, continents | wago (area and map tables) | already used |
| Inn areas for bind steps | wago area table plus innkeeper positions | |
| Class and race spells per level (trainer lists) | not fetched yet: needs the client's spell level and skill line ability tables from wago | needed for trainer automation and learn steps |
| Profession ranks, gates and caps | wago skill lines plus the owner's Forever finding (50/125/200; 75/150/225/300) | already in Noir |
| Talent trees and builds | wago talent tables plus the owner's builds | already in Noir |
| Bundling of actions into steps by place | planner (derived) | group consecutive actions at one NPC or within a small radius |
| Section boundaries, names and level ranges | planner (derived from zone commitments and the level estimate) | |
| Next-section links and race/class starting sections | planner (derived) | |
| Reminder steps ("collect while doing the next steps") | planner (derived from item objectives done across a hub) | |
| Arrival radius per place | planner default by step kind, hand tuning for caves and buildings | |
| Grind places and targets | planner (zone and level) with hand tuning | |
| Short instruction notes (cave entrances, escort tips, jumps) | hand authoring | optional; must be data, never required for a step to work |
| Dialogue option sequences for special NPCs | hand authoring | few |
| Dungeon steps and group quests | hand authoring | later |
| Dangerous mobs per zone | hand authoring (none exist for Forever's new zones) | later |
| Reward choice per quest | hand authoring | optional |
| Quests the cleanup protects (class, profession, dungeon, event, item-started) | QuestieDB (already generated into Noir's cleanup data) | |

---

## 8. Gap table

Priority: **core** (needed for the addon to play like the reference), **should**, **later**. Noir status against 0.1.1: **has**, **partial**, **missing**. "Replace" marks a Noir UI piece that should be rebuilt to this spec rather than patched.

| # | Behavior | Priority | Noir | Noir file | Notes |
|---|---|---|---|---|---|
| 1 | Windows never open off-screen; menus and panels capped to the screen and scrolling | core | partial | `UI/Window.lua`, `UI/Panel.lua`, `Menu.lua` | **Replace** the menu and panel placement: they open at a fixed top-middle place and run off-screen |
| 2 | Default places for every window, reset buttons, positions per profile | core | partial | `UI/Window.lua` | window and arrow only |
| 3 | Settings panel in the game's options window | core | missing | none | new |
| 4 | Minimap button (left: show/hide, right: menu) | core | missing | none | new |
| 5 | Cascading menu at the cursor (picker, step menu, main menu) | core | partial | `Menu.lua` | **Replace**: drill-down list at a fixed place |
| 6 | Sections named by zone and level, grouped, chained by next links | core | missing | `Routes.lua`, planner `emit.js` | one flat route per race today |
| 7 | Section picker filtered by faction, race, class, level | core | partial | `Menu.lua` | route per race only |
| 8 | Auto-select the section by race, level and zone; setup wizard at level 1 | core | partial | `Routes.lua` | race route chosen automatically; no wizard |
| 9 | Next section loads automatically at the end | core | missing | none | |
| 10 | Mid-way placement from quest history with no command | core | partial | `Progress.lua` | runs on first login; must also run on route change and when behind, and show in the list |
| 11 | Steps bundle several actions at one place | core | missing | planner, `Routes.lua`, `UI/Text.lua` | single-action steps |
| 12 | Several steps on screen at once; reminder steps | core | missing | `Progress.lua` | |
| 13 | Tick box per line; manual tick completes a line | core | missing | `UI/Window.lua` | only `/noir skip` |
| 14 | Step list: scroll, dim finished, click or double-click to go to a step | core | missing | `UI/Window.lua` | **Replace** the Strip Bay rack (4 lines) with the card stack plus the scrolling step list; keep the look's cleanliness |
| 15 | Current step chosen and advanced from game state, done steps pass | core | has | `Progress.lua` | forward-only; going back must be possible from the list |
| 16 | Accept lines latch on accept (2 s grace) and hand-ins (5 s grace) | core | partial | `Progress.lua`, `State.lua` | no grace windows |
| 17 | Objective line with live counter | core | partial | `UI/Text.lua` | shown as lines of the strip; no per-objective completion |
| 18 | Collect-item lines with counts | core | missing | none | |
| 19 | Go-to lines with arrival radius in yards | core | partial | `Progress.lua` | radii in map percent, fixed per kind |
| 20 | Step-level skip conditions (quest state, level, outleveled, skill, item) | core | partial | `Progress.lua`, `Routes.lua` | only class and minimum level; "never auto-skip" setting missing |
| 21 | Outleveling: skip content above a maximum level, setting with confirmation | core | missing | none | |
| 22 | Grind targets wherever the character is under a step's level | core | partial | planner | one grind step 59 to 60; under-level steps pass as "not part" |
| 23 | Arrow: targets, arrival, nearest, loops, corpse and spirit healer | core | partial | `UI/Arrow.lua` | one target per step; no corpse or loops. Patch |
| 24 | World map and minimap pins: limit setting, merging, tooltips, lines | should | partial | `UI/Map.lua` | current plus three, no tooltips. Patch |
| 25 | Item buttons from steps | core | missing | none | new |
| 26 | Target buttons with markers | should | missing | none | new; secure buttons only, no macros |
| 27 | Auto accept with one-step lookahead; follow-ups; escort and shared quests | core | partial | `Automation.lua` | current step only |
| 28 | Auto hand-in; reward page left to player unless one choice; value marker | core | partial | `Automation.lua` | no value marker; one-choice page is left open |
| 29 | Ctrl skips quest automation, Shift skips travel automation | should | partial | `Automation.lua` | Shift for all |
| 30 | Auto flight by node identity; flight point recording | core | has | `Automation.lua`, `State.lua` | |
| 31 | Hearthstone bind; hearth on item button | core | partial | `Automation.lua` | no item button |
| 32 | Buy lines at vendors | should | missing | none | |
| 33 | Junk selling and destroying | later | missing | none | |
| 34 | Repair at vendor steps | later | missing | none | not in the reference addon either |
| 35 | Trainer automation (class spells by level, learn lines) | should | missing | none | needs spell level data (section 7) |
| 36 | Profession plan and gates (Forever addition) | should | has | `Professions.lua` | needs steps in the route, not only chat |
| 37 | Talent builds and reminders (Forever addition) | should | partial | `Talents.lua` | chat advice; no talent window ring |
| 38 | Quest cleanup (Forever addition) | should | has | `Cleanup.lua` | Patch: place on screen |
| 39 | Bug report with full context (Forever addition) | should | has | `Diagnostics.lua` | |
| 40 | Why a step was passed, readable without a command | should | partial | `Why.lua` | command only; show in the step tooltip |
| 41 | Drowning and low-health warnings | later | missing | none | |
| 42 | Flight timer bar and flight time in tooltips | later | missing | none | |
| 43 | Party: quest sharing, announcements, version check | later | missing | none | |
| 44 | Leveling tracker and splits | later | missing | none | |
| 45 | Dungeon route family and dungeon settings | later | missing | none | |
| 46 | Optional side sections (class quests, Forever new quests, library books) (Forever addition) | later | missing | none | |
| 47 | Dangerous mobs on the map | later | missing | none | |
| 48 | Recreated-character check and per-section saved places | should | partial | `Progress.lua` | per route; no character identity check |
| 49 | Every command reachable by mouse | core | partial | `Menu.lua` | skip, back, sync, arrow and pins need menu entries |

---

## What could not be determined

- The reference addon's public help pages refused automated reading, so the wording of its help articles could not be checked; behavior here comes from the addon itself and its store page.
- The exact default sizes of the reference windows are visual and were deliberately not taken.
- Whether Forever offers bonus-XP gear the XP-rate detection could read.
- Profession rank level requirements on Forever (10, 20, 35 assumed from other Classic clients).
- How much of QuestieDB's quest XP table matches Forever's actual rewards.
