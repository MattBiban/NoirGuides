# Data notes

What task P1 found in the fetched data (QuestieDB Forever v1.0.14 and its Vanilla flavor, wago client tables for
build 1.60.1.70888) and what the tools now do about it. Every rule here comes from the data itself; where the data
does not settle a question the note says so and marks the fact `verified = false`.

The rules live in `tools/lib/db.js` (`applyDataRules`, run by `loadDb`), `tools/lib/characters.js` (`isleRaces`) and
`tools/lib/quests.js` (`levelingQuests`, `canAccept`, `objectivePoint`). A quest keeps the masks as fetched in
`quest.asData` and the reason for a changed mask in `quest.inferred`.

## 1. Class quests without a class mask

### Quest 8 "A Rogue's Deal" is not a class quest in the data

The plan expected quest 8 to be Rogue only. Nothing in the data supports that, so no rule restricts it:

| Checked | Quest 8 | Quest 590 (same name, needs 8) |
| --- | --- | --- |
| `requiredClasses`, Forever and Vanilla flavor | none in both | none in both |
| Quest sort | zone 154 (Deathknell), not the Rogue sort -162 | zone 154 |
| Giver | 6784 Calvin Montague, no trainer title | 6784 |
| Prerequisites | none | 8 |
| `requiredSpell`, `requiredSkill` | none | none |

The name refers to Calvin, not to the player's class. `tools/test/rules.test.js` pins this (quests 8 and 590 keep no
class restriction). If the owner sees in game that Forever offers it to Rogues only, that is a fact from outside the
data: `verified = false`, to be confirmed in game before any rule is written for it.

### Rule: a quest filed under a class's quest sort belongs to that class

Of the 705 quests under the nine class sorts, 698 carry a class mask. The other seven now get the class of their sort:

| Quest | Name | Sort | Class |
| --- | --- | --- | --- |
| 8249 | Junkboxes Needed | -162 | ROGUE |
| 93797 | Boughs in the Wind | -161 | MAGE |
| 96136 | Call of Air | -82 | SHAMAN |
| 98341 | The Great Windborne Cat Spirit | -263 | DRUID |
| 98404 | The Great Windborne Cat Spirit | -263 | DRUID |
| 98517 | Call of Fire | -82 | SHAMAN |
| 98738 | Blessings of the Great Windborne Cat Spirit | -263 | DRUID |

### Rule: a quest that can only be reached through class quests is open to those classes only

When every quest of `preQuestSingle` has a class mask the quest gets all their classes together; each masked quest of
`preQuestGroup` narrows it. A result that covers all nine classes is no restriction. Seven quests are affected:

| Quest | Name | After | Classes |
| --- | --- | --- | --- |
| 5127 | The Demon Forge | 5126 | WARRIOR PALADIN SHAMAN |
| 8922 | A Supernatural Device | 8905 to 8912 | all but SHAMAN |
| 8923 | A Supernatural Device | 8913 to 8920 | all but PALADIN |
| 8929 | In Search of Anthion | 8926, 8931 to 8937 | all but SHAMAN |
| 8930 | In Search of Anthion | 8927, 8938 to 8944 | all but PALADIN |
| 8960 | Bodley's Unfortunate Fate | 8951 to 8956, 8958, 8959 | all but SHAMAN |
| 9032 | Bodley's Unfortunate Fate | 8957, 9016 to 9022 | all but PALADIN |

The six dungeon-set quests matter on Forever because Dwarf Shaman and Undead Paladin exist (CharBaseInfo rows 905
and 877) and the data has no version of the earlier step for them. Four quests (794, 8921, 8945, 8961) follow class
versions that together cover every class; they and everything after them stay unrestricted.

### Signals that were checked and are not rules

- **A class trainer as the only giver** (18 quests without a mask): unreliable. 2861 Tabetha's Task (Mage trainers)
  is next to 3785 Morrowgrain Research, 6762 Rabine Saturna and 7068 Shadowshard Fragments, which the same data
  gives race masks for whole factions. The Forever-only ones (91772, 94484, 96130, 98065, 98219, 98389, 98391, 99108,
  99152, 99158) cannot be told apart from those. `verified = false`.
- **A class in the name** (20 quests, among them 8, 590, 183, 208, 861, 2541): names of people and places.
- **The next quest in the chain is a class quest** (336 A Noble Brew leads to 397): doing the first one harms nobody.
- **Class mask present in Vanilla, missing in Forever**: no such quest.

### Left for P4

`levelingQuests` leaves out every quest with a class mask, even a mask that covers all classes a race can be (792 Vile
Familiars is for every class but Warlock; 1499 is the Warlock version). P4 layers those back in per class.

## 2. Zephras Isle quests and their race masks

135 quests start on continent 2991 (every giver with a known position stands on the isle; or, when no giver has
one, the quest is filed under an isle area). The data's masks for them, and what `isleRaces` makes of each:

| Mask in the data | Quests | Now open to | Why |
| --- | --- | --- | --- |
| none | 62 | both Skyborne | Only Skyborne characters are on the isle. Before, all ten races had these in their lists. |
| 4294967296 (the High Order bit alone) | 29 | both Skyborne | See the proof below. |
| 4294967373 (Alliance) | 18 | HighOrder | The mask names the Alliance Skyborne race. |
| 8589934770 (Horde) | 21 | Windshaper | The mask names the Horde Skyborne race. |
| 32 (Tauren alone) | 2: 92514, 92595 | Windshaper | A Horde race and no Skyborne one: see below. |
| 176 (Undead, Tauren, Troll) | 1: 98284 | Windshaper | Horde races only. |
| 4294967332, 4294967328 | 2: 93165, 98285 | HighOrder | Names the High Order among other races. |
| 8589934592, 12884901888 | 3: 92598, 96996, 97205 | unchanged | Already Skyborne only. |

**The lone High Order bit does not mean High Order only.** 92579 "To Valanaar" has the Horde mask and needs both 92550
"Havoc in the Highlands" and 93927 "A Last Request"; 92550 carries the lone bit, and 93927 needs 93926 "The Western
Watch", which carries it too. 93320 "Tower Defense" carries it and follows either 92860 (Alliance) or 92871 (Horde).
With the bit read literally, 15 Horde-masked isle quests could never be taken (92579, 92646, 92700, 92708, 92871,
93090, 93735, 93736, 93737, 93738, 93740, 93746, 93836, 94411, 95349), and a Windshaper would have no level 1 quest:
the first quest, 92460 "Coming of Age", carries the lone bit. Quests that really are for the Alliance side and carry
the lone bit (92709, 92727, 92834, 92840, 92849) stay out of a Windshaper's reach through their Alliance-masked
prerequisites (92699, 99260) and their Alliance-only givers.

**Mask 32 on 92514 and 92595 is the Horde side.** 92514 "Welcome to Shen'dar Village" has a twin, 93461, with the
Alliance mask; 92515 and six more quests (92516, 92517, 92553, 93318, 93319, 93951) accept either twin as prerequisite. 92595 "The Windshapers" is given by a
Horde-only NPC (251902), is available once 92514 is taken (`availableStartingWith`) and leads to the Horde-masked
94411; its twin 92596 "The High Order" is tied to 93461 the same way. `verified = false` for why the data says
Tauren; the reading as "Windshaper" is the only one under which the Horde chain works.

Outside the isle a mask means what it says: 94947 "Welcome to Azeroth" (lone High Order bit, given in Dalaran) stays
High Order only.

## 3. Why Windshaper skipped the isle, and why High Order jumps to Alterac

- **Windshaper:** root cause is the mask above. With the lone bit read literally a Windshaper could take 26 of the 111
  isle quests, none of them at level 1, so the planner started in Mulgore. Faction inference (`friendlyToFaction` is
  "AH" for the shared givers), the positions and the map row (UiMap 2521, area 16593, continent 2991) were all fine.
  Now a Windshaper has 84 isle leveling quests from level 1 and the route does 221 steps there before it leaves.
- **High Order:** the jump is real. It is how a character leaves the isle (next section): the last isle quest is
  turned in at an NPC the data places in Alterac Mountains. High Order has 86 isle leveling quests and leaves
  after 227 steps.
- **Both routes went back to the isle around level 58** to turn in 92553 "Restocking the Larders". Root cause:
  `objectivePoint` took the first source the data lists for an item, and Small Egg (6889) lists Westfall's
  Fleshrippers before the isle's own creatures. Fixed in section 6; neither route returns to the isle now.

### How a character leaves Zephras Isle (for P2)

There is no flight point: the only TaxiNodes row on continent 2991 is 3361 "Quest Path 12018: 1.60.1 - Zephras Isle -
Spires Wind Bridge", linked only to itself (TaxiPath 12018), and no isle NPC has the flight master flag. The way out
is a quest per faction, both requiring level 7 (quest level 13), each the end of the isle's main chain:

| | Alliance (HighOrder) | Horde (Windshaper) |
| --- | --- | --- |
| Chain | 93835 → 94369 → 93089 → **94946** | 92646 → 93836 → 93090 → **95349** |
| Exit quest | 94946 "The Magical City of Dalaran" | 95349 "The Earthen Ring" |
| Quest text | "Take the skycutter ship from Zephras Isle to Dalaran City and speak with Danaaris Stargale when you arrive." | "Take the skycutter ship from Zephras Isle to Mulgore and speak with Alaana Stormwalker when you arrive." |
| Accept at | 252475 Elaadrin Evengale, Zephras Isle 66.63, 79.94 | 251968 Ayessa Dawnsinger, Zephras Isle 59.15, 79.78 |
| Departure | object 716301 "Portal To Dalaran", Zephras Isle 65.7, 83.3, beside NPC 275269 "High Order Dockmaster" (65.11 to 65.71, 81.48 to 83.25) | object 716302 "Portal to Thunder Bluff", Zephras Isle 58.0, 80.4, beside NPC 275270 "Windshapers Dockmaster" (58.05 to 59.47, 78.55 to 81.07) |
| Turn in at | 259084 Denaaris Stargale, placed in Alterac Mountains (zone 36) 12.3, 56.3 | 259119 Alaana Stormwalker (or 259118 Muln Earthfury), Mulgore (zone 215) 33.39, 22.51 |
| Next quest there | 94947 "Welcome to Azeroth", ends at NPC 1748 in Stormwind (zone 1519) | 95350 "Welcome to Azeroth", ends at NPC 4949 in Orgrimmar (zone 1637) |

Not in the data, so `verified = false` for `transports.json`:

- Whether the link is a ship or a portal: the quest text says "skycutter ship", the objects at the docks are named
  portals. Suggested `kind = "portal"` at the object positions above.
- Whether it can be used before the exit quest is accepted, and whether it costs anything.
- Where the character arrives. Denaaris Stargale's position is in Alterac Mountains, but AreaTable also has a "City
  of Dalaran" on its own map (areas 16544 and 16560, continent 2959) with no UiMapAssignment row, so the arrival may be
  inside that city and the Alterac position only where QuestieDB pins it.
- **Any way back.** Object 716304 "Portal to Valanaar" has no spawn; 617084 and 617085 of the same name stand on the
  isle itself (75.2, 53.3). Treat the isle as one-way: everything worth doing there has to be done before the exit
  quest is turned in. `tools/test/plan.test.js` checks that the two routes never return.

Also for P3: `levelingQuests` still leaves out Forever-only quests that are not on the isle, so "Welcome to Azeroth"
(94947, 95350), the natural next step after arriving, is not in any route yet.

## 4. UiMapAssignment

`loadDb` kept the first full-map row it read for an area while its comment promised the lowest OrderIndex. It now
tracks the lowest (first read wins among equals). In the current table this changes nothing: of 61 rows 54 are
full-map rows with an area, no area has two, and the only OrderIndex above 0 is a continent row without an area
(ID 46784). The rule is covered by a test with a table written for it and by a check against the real file.

## 5. Quests that cannot be completed

### 8309 and 8310 are ordinary quests

The Night Elf route of commit `e834870` ended with 8309 "Glyph Chasing" and 8310 "Breaking the Code" in the log
because the planner stops the moment the character reaches level 60: its last three steps were the two accepts and
one objective. Neither quest is repeatable, reputation gated or event gated, both have a giver, a turn-in and
placeable objectives, and in commit `37a4f8c` the same route turns both in (and ends with 3627 in the log instead;
Human, Dwarf and Gnome ended with 5527 for the same reason). The cause is the stop rule in `tools/planner/plan.js`,
which belongs to P3; it is not a data fault and nothing was filtered for it. With today's data no route ends with a
quest in the log, but nothing guarantees that until P3 makes the planner finish its log.

One thing about 8309 for later: its third crystal (object 180453, item 20456) is listed under area 10073, one of
QuestieDB's own area IDs (10000 and up) that AreaTable does not have. Such areas are treated as unknown, not as
instances. 17 area IDs used by spawns are not in AreaTable: 1585 and sixteen between 10000 and 10089.

### What `levelingQuests` now leaves out

Already left out before: repeatable quests (`specialFlags` bit 1), quests behind a skill, reputation, spell,
specialization, rank or parent quest, quests under a negative sort (seasonal events, professions, class), quests
without a giver or turn-in usable by the faction, quests with no placeable objective.

New, each from the data:

- **Filed under an instance.** An area is instanced when it or a parent is on the hand-written dungeon list or its
  AreaTable continent is not 0, 1 or 2991. The list alone missed the battlegrounds and area 1417:
  - Alterac Valley (area 2597, continent 30), 18 quests that need a battleground queue: 7081, 7082, 7121, 7122,
    7123, 7124, 7141, 7142, 7223, 7224, 7241, 7261, 7281, 7282, 7301, 7302, 8271, 8272. The Human route used to go
    there.
  - Sunken Temple (area 1417, continent 109): 1445, 1475, 3380. Two of them are errands to the temple door; they
    go out with the rest of the dungeon's quests, as the errands filed under the listed dungeons always did.
- **An objective found only inside an instance.** A creature or object whose every known spawn is in an instance, or
  an item whose every known drop is and that no vendor sells: 1221 Blueleaf Tubers (Razorfen Kraul), 5166 and 5167
  (Blackrock Spire drops). The planner used to send the player to the first objective it could place and the quest
  could never be finished there.
- **Class quests found by section 1:** 8922, 8923, 8929, 8930.

Checked and kept: the raid quest flag (`questFlags` 64) is on 18 leveling quests such as 6402 Stormwind Rendezvous
and 8315 The Calling. It allows a raid group, it does not prove one is needed, so it is no filter. Whether a quest
needs a group is not in the data.

### Conditions that take a quest away again

`canAccept` now honours four fields the planner ignored (the validator in `tools/planner/validate.js` does not check
them yet; that file is P3's):

| Field | Meaning (QuestieDB's field notes) | Leveling quests affected |
| --- | --- | --- |
| `disabledByQuest` | off while the named quest is in the log | 287, 334, 808, 823, 826, 918, 919, 1008, 1105, 1135, 6541, 6542, 9419, 9422 |
| `availableUntilCompleted` | gone once the named quest is turned in | 1282, 1301, 3451, 4023, 6382, 92464 |
| `availableStartingWith` | not before the named quest is taken | 92595 (after 92514), 92596 (after 93461) |
| `requiredMaxLevel` | not above this level | none of the leveling quests (42 quests overall) |

## 6. Where an objective is done

`objectivePoint` took the first creature the data lists for an item and, for a creature living in several zones, the
zone with the most spawns. For 187 of the 2,010 leveling quests that was not the place nearest the quest (42 in
another zone, 14 on another continent): 179 Dwarven Outfitters sent a Dwarf to Elwynn Forest for wolf meat, 385
Crocolisk Hunting sent Loch Modan players to Stranglethorn Vale, 92553 sent Skyborne players to Westfall.

Now every source of the objective is a candidate (one per zone it spawns in) and the cheapest wins: distance from the
quest giver, plus up to one respawn's wait where a place has fewer spawns than an objective needs. The second term is
an estimate (8 kills per objective, as `lib/xp.js` assumes; a 5 minute respawn at 7 yards a second) and only keeps
a single named creature beside the giver from beating a herd close by: 1032 Satyr Slaying! goes to the Felmusk
satyrs, not to Aligar the Tormentor over the Darkshore border; 703 goes to the buzzards, not to Zaricotl. Objective
counts and drop chances are not in the data.

With all of P1's changes and the unchanged planner, total straight-line travel fell for nine races (Human 1,327,001 to 1,198,277
yards, Undead 1,232,768 to 1,085,823) and rose 0.4% for HighOrder (1,299,878 to 1,305,701), whose old figure left
out the round trip to the isle.

### Format 3 bundling (rebuild task P1, `tools/planner/bundle.js`)

Assumptions the data does not settle, all `verified = false`; a route stays playable if one is wrong:

- **Objective index order.** An `objective` line's `index` is the quest log's objective number. QuestieDB keeps a
  quest's creatures, objects and items in separate lists, so `lib/quests.js objectiveList` numbers them creatures,
  objects, items, kill credit, explore trigger. 49 Forever quests have both creature and item objectives and 11 have
  kill-credit objectives; for a quest that mixes creatures and objects in the game the numbers may differ. Every
  objective line of a quest is still done when the quest is complete.
- **Usable items.** The data has no flag for an item with a use effect. A step's item buttons are the quest-starter
  items of its accepts and each quest's source item and required source items (QuestieDB `sourceItemId`,
  `requiredSourceItems`) other than the objectives' own items; 408 quests have a source item, 103 required source items.
- **Kill credit.** QuestieDB's objectives slot 5 is `[[creatures that count], credited creature, text, icon]`. The line
  names the credited creature when it is one of the creatures that count (the quest log is assumed to name it), else
  the first that counts: the credited one is then a stand-in (quest 273 credits 15885, "Pat's Firework Guy - BLUE
  BIG", for Miran and Huldar). Only the creatures that count are target candidates. Which name the Forever quest log
  shows is not verified.
- **"Any one of" prerequisites.** An accept line's `requires` lists all of `preQuestGroup` and only those of
  `preQuestSingle` that the route hands in before it (for the same characters): listing every alternative, such as
  another race's version, would ask for a quest the character can never do.

Before and after bundling, with the unchanged planner and class layering: Undead 2,120 actions to 1,502 steps (71%),
Human 2,073 to 1,452 (70%). 407 of Undead's steps are a single objective: the planner's objective loops place
consecutive objectives more than 150 yards apart.

### Format 3 sections (rebuild task P2, `tools/planner/sections.js`)

- **Which grey rule caps an accept step.** The plan says "the last level before the quest turns grey by `lib/xp.js`'s
  grey rule". `lib/xp.js` has two: `questXp` (a quest gives nothing more than 8 levels under the player) and
  `greyLevel` (creatures, not exported, greyer sooner: a level 5 quest would be capped at 10, not 13; a level 30 one at
  37, not 38). The planner's level estimate uses `questXp`, so `maxLevel` does too: the cap is where the planner itself
  stops counting the quest's XP. Not confirmed with the owner; the in-game grey colour of a quest is not in the data.
- **Notes the planner writes.** `splitSections(..., notes)` lists accept steps whose quests stop giving XP below the
  step's `minLevel` (no cap is written) or below the estimated level where the route takes them (the step is skipped
  for everyone with "skip content you outlevel"), and zones with no name in the area table (the section is then named
  "Zone <id>"). P3 writes them into the build report. Today two Undead accept steps are grey at their estimated level
  (a1424: XP up to 51, taken at 54; a1560: up to 58, taken at 59); Human has none.
- **Class grinds.** A grind before a class step is checked at each class's own estimated level and lifts only those
  classes; the shared estimate, and the grinds later shared steps need, are unchanged by it.

### Format 3 texts, reminders, trainers and the build (rebuild task P3)

The build (`tools/build_routes.js`) now writes format 3: plan, layer classes, validate format 2, `bundleSteps`,
`splitSections`, `addReminders`, `addProfessionSteps`, `addClassTraining`, `stepText`, `validate3` for all 56
characters, `emitRoute3`. All 56 characters are valid on the format 3 routes and reach level 60. What the data or the
plan does not settle, all `verified = false`:

- **Steps after bundling: 70% to 73% of the actions under P1's rules, 61% to 65% with hub bundling.** The project
  lead decided the follow-up (P3 follow-up 1): `BUNDLE_YARDS` raised from 30 to 60, a hub of 80 yards
  (`HUB_YARDS`) and a hub order in `planner/bundle.js`. What the data showed first (all races, P1 rules):
  - 191 to 314 neighbouring steps per race stand within 60 yards of each other. For Undead (293): 102 are two talk
    steps with the same condition, 35 two talk steps with different conditions (a class's lines between shared
    ones), 57 a talk step next to an objective step (an accept, an objective done beside the giver, the turn-in),
    the rest gotos, flights and transports next to their NPC or dock.
  - The distances between neighbouring talk steps with the same condition (Undead): 64 at 30 to 45 yards, 38 at 45 to
    60, 52 at 60 to 80, 44 at 80 to 100. A town's quest givers mostly stand 30 to 80 yards apart.
  - A hub split by unrelated actions and visited again within seven actions (about 160 per race): about 25 times
    only other talk actions stand between, about 135 times an objective trip (the planner sends the player out and
    back), 15 to 32 times a flight or a goto. Only the first kind may be reordered; the others are the planner's
    route.
  - Measured shares (Undead / Troll, the worst race): P1 rules 70.8 / 72.7; `BUNDLE_YARDS` 60 alone 66.5 / 69.1;
    with the hub order of talk actions 66.4 / 68.8; talk actions joined within 80 yards (the hub) 64.3 / 66.9;
    objectives within 60 yards of a giver joining its step 61.8 / 64.7; everything with the hub order 61.6 / 64.6
    (in the build, which gives the hub order the level estimate). The hub order itself gains 0.1 to 0.3 points: most hub returns follow an objective trip, which it may not move.
  - The rules now: talk actions within `HUB_YARDS` (80) of the step's first action share its step; a talk and an
    objective action share a step within `BUNDLE_YARDS` (60); objectives with objectives within `OBJECTIVE_YARDS`
    (150) as before; a line more than `OWN_PLACE_YARDS` (30, P1's old distance) from the step's place keeps its own
    place. The hub order moves an action of a hub run (talk and objective actions within 80 yards of the run's
    first, in one zone) up to the first one's step past the run's other actions, never past its own quest, a
    prerequisite, the quest it needs taken first, the quest that turns it off or one it excludes, never before the
    level its accept needs (the lowest estimate of the race's classes), never over 20 quests in the log, and never
    between a getflight and its fly. The first action outside the run ends it; the planner's order is otherwise kept.
  - Per race, actions to steps, before (P1 rules) and after: Human 2,073: 1,452 (70.0%) to 1,294 (62.4%); Orc 2,161:
    1,570 (72.6%) to 1,389 (64.3%); Dwarf 1,917: 1,344 (70.1%) to 1,204 (62.8%); NightElf 1,960: 1,375 (70.1%) to
    1,236 (63.1%); Undead 2,120: 1,502 (70.8%) to 1,306 (61.6%); Tauren 1,943: 1,397 (71.8%) to 1,216 (62.6%); Gnome
    2,014: 1,418 (70.4%) to 1,270 (63.1%); Troll 2,206: 1,605 (72.7%) to 1,424 (64.6%); HighOrder 2,141: 1,492
    (69.7%) to 1,303 (60.9%); Windshaper 2,108: 1,493 (70.8%) to 1,294 (61.4%). Troll is closest to the line: the
    races with the most class quests (Troll 470 class actions, Orc 425) bundle worst, because a class's lines never
    share a step with shared ones.
  - Not verified in game: whether a step whose givers stand up to 80 yards apart reads well; each giver over 30 yards
    from the first keeps its own pin.
- **Shared estimate.** The shared level at an action is the lowest level any class of the race has there
  (`validateRoute` per class on the layered route); profession steps are placed by it, class visits by each class's
  own replay of the sections (`validate3.estimateSteps`).
- **Class trainers** are NPCs whose sub name is "<Class> Trainer", friendly to the faction (QuestieDB `subName`, now
  kept by `lib/db.js`). The 120 second detour of a visit on the way is measured as the walk from the step's place to
  the trainer and back (`travelPlan`, on foot, no flights): it errs long when the trainer lies on the way. A forced
  visit (6 levels without one) is written at the level reached, which can be odd (23, 57).
- **Class training trips** (the project lead's P3 follow-up 2, `planner/training.js`). Under the P3 rules alone the
  route left long stretches without a trainer: Human and Gnome priests 10 to 23 to 56, Windshaper druids 16 to 44 to
  56; 105 stretches of more than 6 levels over the 56 characters, the longest 36 levels. Now, once 4 levels have
  passed since the last visit, a visit may be a trip: the way from the step before to a trainer and on to the step,
  by `travelPlan` with the flight points the class has learned by then (getflight and fly lines before the step),
  that takes a flight or the hearthstone and adds at most 300 seconds to the way from the step before to the step.
  Within the level it falls due at, the first step that passes a flight master (a getflight or fly line) and fits is
  taken, else the first step that fits; a walk is never a trip (that stays the 120 second rule). A trip step says how
  it goes ("Fly to Orgrimmar for class training, then return."). The hearthstone is used only where the class's
  replay has a clock (`validate.js` now returns `clocks`, `validate3.estimateSteps` a `clock` per step): an hour
  after the route's or a trip's last hearth, an hour and 300 seconds before the route's next one, bound at the route's
  last sethearth. Result: 206 trips (202 by flight, 3 flying there and hearthing back, 1 hearthing there), 75
  stretches of more than 6 levels (from 105), the longest 19 levels (from 36). Every stretch of more than 6 levels
  between level 4 and 58 is listed in REPORT.md ("Class trainer gaps") with the cheapest trip found while one was
  due: 38 of the 75 cheapest trips add 301 to 400 seconds, 37 more than 400, so the 300 second limit (the lead's
  number) leaves them, not a missing trainer. `tools/test/training.test.js` checks that the report lists
  every such stretch of the shipped routes. Not verified in game (`verified = false`): the flight times are
  `lib/travel.js` estimates (32 yards a second, 10 seconds to board), and the clock is the planner's estimate of
  play time.
- **Profession trainers** by sub name: "<Profession> Trainer" or "<Crafter> Trainer" for every rank, "Journeyman /
  Expert / Artisan / Master <Crafter>" up to that title's rank. The plan names only the first form; with it alone the
  crafting professions (whose Vanilla trainers are titled "Journeyman Blacksmith" and so on) would get almost no step.
  Steps are placed only at steps every character has. Ranks without a step are listed in `PROFESSION-NOTES.md`.
- **Reminders.** "Kill and item objectives" are objective lines that name a creature or an item. A turn-in step that
  already carries a label (from an earlier reminder) keeps it and the next reminder ends there too. A turn-in step
  with a condition the objective's step does not have ends no reminder (its label would be missing for some
  characters). The moved lines take their enemy targets along (their creature, their item's droppers) and their
  quest's item buttons (its usable source items, spec 4.6); the step left behind keeps the items its remaining lines'
  quests still use.
- **Texts** follow the plan's templates, except the objective text's grammar (the project lead's P3 follow-up 3): the
  plan's "The <first target> are ..." read "The Meven Korgal are east of Executor Arren.". The subject is now the
  step's first objective line that names a creature, object or item (else its first enemy target): "Meven Korgal is
  east of Executor Arren." for one named creature; "Scarlet Armband is ..." for an object or item ("Devlin's Remains
  are ..." when the name reads as a plural); "The Mindless Zombies are ..." only for a kill objective that needs more
  than one; "The Ornery Galestrider is ..." for one creature that is not a named one. How many an objective needs is
  not in the data (QuestieDB has no counts): it is read from the quest's objective text (`objectivesText`, now kept
  by `lib/db.js`), where a number above 1 within the four words before the creature's name, or its plural, means
  more than one. A creature is a named one when the text names it without an article ("Kill Captain Perrine"), or,
  where the text does not name it, when every creature of that name together has at most 3 spawns. Plurals come from
  English rules on the last word (wolf to wolves, -man to -men except shaman, -y to -ies, vermin unchanged). Over
  the shipped routes: 681 texts read "The ... are", 72 "The ... is", 2,195 "<Name> is/are". Not verified
  (`verified = false`): the counts and plurals are read from English text, and an item's text names the item rather
  than the creatures that drop it, as the lead asked. Without an NPC on the step before, the objective text says "of
  your last stop". Compass directions are from world positions; a goto across continents has none ("Head into
  <zone>.").
- **`planner/emit.js`** writes the data files from format 3 routes; its format 2 `emitLua` stays only for
  `tools/sim_all.js` and `tools/test/sim.test.js` until task X1.

## 7. Housekeeping

- Five test files had a path comment on line 1; the license line is now first in every file under `tools/`
  (`tools/test/hygiene.test.js` checks all JavaScript there).
- `.gitattributes` forces LF for `*.lua`, `*.js` and `*.md`. `tools/planner/plan.js` was CRLF in the working copy
  (LF in git); the same test fails on any CRLF in those file types.

## 8. Open points

| For | Point |
| --- | --- |
| Owner, in game | Is quest 8 "A Rogue's Deal" offered to every Undead class on Forever? The data says yes. |
| Owner, in game | Skyborne exit: ship or portal, arrival point in Dalaran, and whether there is a way back to the isle. |
| Owner, in game | Are 92514 and 92595 (mask 32 in the data) offered to Windshapers, and 92460 to both Skyborne races? The quest chains require it. |
| P2 | `transports.json` entries for the two isle exits with `verified = false`, one-way. |
| P3 | The planner must finish its log before it stops, treat the isle as one-way, and the validator should replay the four availability fields of section 5. Routes are still format 1. |
| P3 | Every route now ends with one grind step from 59 to 60: the battleground quests it used to count are gone. |
| P4 | Class quests are filtered by any class mask; masks that cover every class of a race need layering back in. |
