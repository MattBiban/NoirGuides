# Class notes

What task P4 does with class quests and what it found in the data (QuestieDB Forever v1.0.14, wago client tables).
The code is `tools/planner/classes.js`; `tools/build_routes.js` runs it for every race, and the per-character
results are in `docs/routes/REPORT.md` (section "Characters") and `tools/data/build_status.json`.

## How class quests reach a route

Each race has one route file. Its shared steps are the route every class of the race plays (`tools/planner/plan.js`,
which takes no quest with a class mask). `layerClasses` adds each class's quests as steps with
`when = { class = "..." }`, so a character sees the shared steps and its own class's steps and nothing else.

- **Which quests:** a class mask that includes the character's class (`requiredClasses`, or the masks P1's data rules
  fill in), open to the race, not repeatable, not behind a reputation, skill or event, filed under a zone or under a
  class's quest sort (not a holiday or the legendary sort), classic or given on Zephras Isle, not in or needing an
  instance, given and ended by someone the faction can find, every place reachable, and required level below 60.
  "Given on Zephras Isle" is read from where the giver stands (continent 2991 or area 16593), not from the quest's
  zone: a quest filed under a class sort has zone 0. The first build read the zone and so dropped the Skyborne class
  starters 92481 A Student of the Arcane, 92482 The Way of the Hunter, 92483 At Home in the Shadows, 92484 Embracing
  the Elements, 92485 A Student of Nature and 92532 The Warrior's Path without listing them; they are now layered for
  every High Order and Windshaper character of their class, with the isle quests that follow them (94003, 94006,
  94007, 94013, 94050, 94638, 94978, 94979, 93791, 93797, 97243 to 97245, 97257).
  Quests for several classes (792 Vile Familiars is for every class but Warlock) are layered once per class, each in
  that class's own steps.
- **Where:** every part (accept, objective, turn-in) goes into the gap before a shared step where it adds the least
  time: the way there and on to the next shared step, less the way the shared route already walks. A part on another
  continent or far away is reached by the fastest way `travelPlan` finds with the flights learned by then, and the way
  back is written too, all as class steps. Class steps never use the hearthstone.
- **What is kept:** the quest's required level and prerequisites (from the shared route's and the class's turn-ins
  before the gap), creatures at most three levels above the player for the objective, the 20-quest log, exclusive
  quests (of a group of versions, the one with the cheapest detour), and quests that switch each other off
  (`disabledBy`, `availableUntil`). A quest is first fitted within five levels above its own and only later when nothing
  fits there.
- **Checked:** the validator replays every one of the 56 characters on its race's file (`npm run routes`); all 56 are
  valid and reach 60. `tools/test/classes.test.js` repeats this on the real data and checks that no class quest reaches
  a class it is not for.
- **Measured:** the report's "Characters" table measures each character's own steps (shared and its class's) with
  `tools/planner/measure.js` and shows what the class steps add to the shared route's zone changes and travel time.
  The P3 acceptance lines stay measured on the shared route, which is what P3 planned.

## Forever-only class quests: not routed, listed as left out

The Forever data has 1,425 quests that are not in the Vanilla data (of 5,682). The shared route takes none of them
except those of Zephras Isle (`levelingQuests` in `tools/lib/quests.js`), and class steps follow the same rule, so a
class does not take quests its race's shared route would refuse. The first build dropped these class quests without a
word; each character now lists every class quest that passes every other rule but this one, with the reason "not a
classic quest and not given on Zephras Isle", in its `left` list, in `build_status.json` and in the report.

On the current data that is 220 entries (115 quests) over 38 characters. By character:

| Character | Quests left out by this rule | Examples |
| --- | --- | --- |
| Dwarf Shaman | 21: 79358, 94373 to 94375, 94449, 94465 to 94468, 94494, 94495, 94501 to 94503, 94505, 94616, 94789, 96016, 96135, 96243, 98581 | Call of Earth, Call of Fire, Call of Water, Call of Air (the totem quests), Storm, Earth, and Fire |
| Undead Paladin | 31, the chain from 90902 Rediscovering the Light (Tirisfal, NPC 244808) | 91208 Coming to Terms, 94427 to 94441 A Lesson in Divinity, 94971 A Paladin's Steed |
| Human, Dwarf Paladin | 12 each | 78088 to 78093, 79939, 79940, 81764, 81765, 81790, 84150 |
| Human, Dwarf, Night Elf, High Order Hunter | 5 each, Human 6 | 94792 Taming the Beast, 94793 Training the Beast, 94863, 94864 (Elwynn NPC 251507, the pet quests), 78830; Human also 92479 |
| Human Priest; Gnome Priest | 5; 6 | 94773 to 94777 Divine Grace; 94817 to 94824 Confounding Flash and 98574 |
| Orc, Tauren, Troll Shaman | 8 each | 79358, 79361 to 79366, 79442 (Windshaper: 79358, 79364, 79366) |
| every Rogue (all nine races) | 5 each | 78261, 78270, 80526, 96779, 96783 |

Two Dwarf Shaman quests the review named, 94497 and 94499 Call of Water, are not on that list because they also fail
another rule: their objective items (265734, 265748) have no creature or object in the data that drops them.

**Not decided here (owner):** whether class steps should take Forever-only quests. The data does not say which of the
1,425 the Forever server offers, and the same question stands for the shared route. Until it is decided these
characters play the shared route plus their classic class quests, and the report says what they miss.

## A change to the shared route: grinding does not ready the hearthstone

The first build left 21 characters with a hearthstone used within the hour, all on the same step: each race's route
ends with a grind to 60 and then a hearth, and the planner had counted the grind's hours towards the cooldown. A class
with its own quests is already 60 there, skips the grind and its time, and finds the hearthstone not ready. The root
cause is in the planner, so `planRoute` no longer counts grind time towards the hearthstone's cooldown
(`tools/planner/plan.js`, the grind branch of `emit`). That file is P3's, outside P4's file list; the change is made
there because that is where the cause is, and it only makes the shared route stricter (the validator still counts
grind time). The shared routes changed by a step or two at the end; the P3
acceptance in the report is still met.

## What the data does not allow (left out, with the reason in the report)

| Finding | Quests | Why it is left out |
| --- | --- | --- |
| Paladin tome chains start with a repeatable donation quest whose reward item starts the next quest | 1641/1642, 1645/1646, 1649, and everything after them (1643, 1644, 1647, 1648, 1650 to 1654, 1778 to 1788, 1806) | repeatable and item-started quests are not routed (P1 rules); the data does not say which quest rewards the item. `verified = false`: the chain may be playable in game |
| Dungeon set upgrades and their follow-ups | 8922, 8923, 8929, 8930 (after 8905 to 8920, 8926, 8927, 8931 to 8944) | the earlier quests need dungeons |
| Level 60 quests | for example 7633, 7634, 7636 (Hunter), 7637 to 7641, 7646, 7648, 7670 (Paladin), 7562 to 7564 (Warlock), 9257, 9269, 9270, 9362, 9364 | a route ends at 60 |
| Holiday quests filed with a class mask | 8767, 8788 (A Gently Shaken Gift, sort -22) | seasonal |
| Prerequisites stored as negative IDs | 4964 (needs -4962), 4975 (needs -4963) | the meaning of a negative ID in `preQuestGroup` is not in the data; `canAccept` reads it literally, so the quest is never offered. `verified = false` |
| Chains whose first quest is not routable | 1951 then 1952; 1956 then 1957, 1958; 1701 then 1782 and the 1704 to 1710 Warrior chain; 1838 then 1839 to 1848; 1796 then 4781 to 4786; 336 then 397; 29 then 272 | checked one by one against the rules of `classQuests`: 1951 Rituals of Power and 1956 Power in Uldaman need an instance and their objective items (7274, 8053) have no creature or object in the data that drops them; 1701 Fire Hardened Mail and 1838 Brutal Armor need an instance; 1796's objective item 5770 has no source in the data; 336 A Noble Brew has no class mask and the shared route does not take it, so the Warlock's 397 is never offered; 29 Trial of the Lake is a Night Elf quest, so High Order Druids never get 272 |
| Forever-only class quests | 220 entries, see the section above | not classic and not given on Zephras Isle |

"An exclusive quest is taken instead" is not a loss: these are versions of one quest (one per race's trainer, or
one per pet or reward) of which the game gives one.
