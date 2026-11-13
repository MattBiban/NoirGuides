# In-game checklist

Everything here passed the tests and the simulator, and none of it has been seen in the game: the tests run against a mock client (`tools/harness/wow.lua`) that was written from documentation of other Classic builds, and the routes rest on QuestieDB and the client tables. Only the owner, playing WoW Forever, can confirm these. Each line says what to do and what to expect; a number in brackets, such as (#7), is the assumption of that number in `docs/ENGINE-NOTES.md`, where the table also says what happens when it is wrong.

Most of section 2 needs nothing more than `/noir state` and `/noir problems` after logging in. When something is wrong, `/noir bug` gives a report to paste.

## 1. Install

- [ ] Unpack `dist/NoirGuides-0.2.0.zip` (`npm run package` in `tools/`) into `World of Warcraft\_classic_\Interface\AddOns\` (or the Forever client's `Interface\AddOns`). There must be one new folder, `NoirGuides`, holding `NoirGuides.toc` directly.
- [ ] The character select screen's AddOns list shows "Noir Guides" and does not mark it out of date (`## Interface: 16001`).
- [ ] After login, the chat shows no Lua error and `/noir problems` lists nothing. The client skips no file the toc lists (#12).
- [ ] `/noir state` shows race, class, faction, level and zone correctly.
- [ ] First login (0.2.0), with no command typed: the guide window opens at the left edge a little above the middle, the arrow near the top middle, and the minimap button on the minimap's rim at the bottom left (#52, #98).
- [ ] A new level 1 character: the setup wizard opens by itself a few seconds after login; Finish loads the recommended section, and closing the wizard keeps it too.
- [ ] A character above level 1 that never used Noir: a section for its level is loaded by itself, and chat says where in it the character was placed from its quest log.

## 2. Client API assumptions

### Character, quest log, levels

- [ ] Race: a High Order and a Windshaper character are recognized (race IDs 95 and 96 as the third value of `UnitRace`, file name `Skyborne`) (#1).
- [ ] The quest log is read: `/noir state` counts the quests in the log, with the log open and closed (#2).
- [ ] Accepting, handing in and abandoning a quest each update the window at once (#3).
- [ ] With a quest log header collapsed, the window still knows the quests under it, or says that part of the log is hidden (#4).
- [ ] On a character with quests done before the addon was installed, the route starts past them (#5).
- [ ] At a level up the window's level and a `grind` step to that level complete at once (#6).

### Flights, hearthstone, professions, position

- [ ] Opening a flight master's map adds its known flight points to `/noir state` (#7).
- [ ] Discovering a new flight point completes a `getflight` step without opening the map (#8).
- [ ] Binding the hearthstone at an innkeeper completes a `sethearth` step; `/noir state` names the inn (#9).
- [ ] `/noir state` and `/noir professions` list the character's professions by skill line (#10); a profession reported by its Forever tier line (2937 to 2948) is counted as that profession (#46).
- [ ] `/noir state` shows a position in the open world, in a building and in a cave (#11).
- [ ] Nothing in the chat about `xpcall` (#13) or a missing timer (#14).
- [ ] The zone in `/noir state` is the zone the game shows; route steps in that zone are found (#15).

### Automation (NPC dialogs)

- [ ] Talking to a quest giver with several quests opens the route's quest, not another (#16, #17, #18, #22).
- [ ] At a flight master or innkeeper with gossip, the addon picks the flight or bind line, never another (#19).
- [ ] Talking to an NPC that is not the step's NPC: the window says so when that NPC does not offer the step (#20).
- [ ] Accept, progress and complete dialogs are answered for route quests and left alone for others; a quest with one reward choice is handed in with it, one with several choices waits for the player (#21).
- [ ] A follow-up quest offered right after a hand-in is accepted when the current or next step names it, and its page is closed when no step does (#23).
- [ ] At a flight master for a `fly` step, the flight starts by itself shortly after the map opens (#24).
- [ ] The innkeeper's "make this your home" question is answered for a `sethearth` step (#25).
- [ ] A `fly` step completes on landing, not during the flight (#26).
- [ ] Holding Shift while talking to an NPC stops the flight, bind and dialogue automation for that dialog; Ctrl stops the quest automation (#27).
- [ ] `travel` steps complete when standing at the place in a large zone (The Barrens) and in a city (Orgrimmar or Stormwind) (#28).

### Window, arrow, map

- [ ] The window shows text in the default font (#29).
- [ ] The window can be dragged, also in combat, and stays where it was left after `/reload` (#30).
- [ ] The arrow turns smoothly as the character turns (#31) and points the right way: stand north of the step's place and face north; the arrow must point down the screen (#32, #33).
- [ ] The arrow and the distance work towards a place in another zone of the same continent (#34).
- [ ] Map pins appear on the zone map and on the continent map (#35), above the game's own pins, and opening the world map in combat raises no blocked-action message (#36).
- [ ] Minimap pins sit at the right distance at every zoom level, outdoors, with and without a rotating minimap (#37).
- [ ] Quest, NPC and item names in the window are names, not "Quest 364" (#38).
- [ ] No Lua error when the first pin is drawn (#39).
- [ ] The arrow and the pins are drawn, not shown as green squares (#40).

### Talents, professions, quest cleanup, bug report

- [ ] `/noir talents` reads the character's trees and suggests the next point of the class's build (#41); the count of points to spend is right (#42); a message comes when a point is gained (#43).
- [ ] `/noir professions`: Journeyman training at level 10, Expert at 20, Artisan at 35 (#45). The skill gates 50, 125 and 200 are the owner's own finding and are taken as true.
- [ ] `/noir cleanup`: tick an off-route quest and press Abandon; only that quest leaves the log (#44). Rows and menu entries react to the mouse (#47).
- [ ] A grey off-route quest says "Grey, and not on your route" when it no longer gives experience (#50).
- [ ] Another class's quest, if one can be in the log, is named with the client's class name (#51).
- [ ] `/noir bug` opens a box with readable text that can be selected and copied (#48); the report names the client version (#49).

### Screen, options window, buttons (rebuild)

- [ ] Change the resolution and the UI scale in the game's options: every Noir window stays fully on the screen, and the guide window opens at the left edge a little above the middle (#52, #53).
- [ ] The game's options window has a "Noir Guides" page under AddOns; trying to open it in combat does nothing until combat ends (#54).
- [ ] In combat, the item and target buttons do not move or hide and no blocked-action message appears; they update when combat ends (#55, #56).
- [ ] A double click on a step in the step list opens the step menu (#57); map pins let clicks through to the map, long lists are cut at their frame, and the window cannot be resized smaller than its content (#58).
- [ ] No XML error at login from `Bindings.xml`; the key bindings menu has a "Noir Guides" header (#59).
- [ ] As a ghost the arrow points to the corpse (#60).
- [ ] A vendor step buys the count it says, and a reward page with choices marks the best one (#61).

### Lines of a step (rebuild)

- [ ] Pick a destination at a flight master: the fly line ticks as the flight takes off, not only on landing (#62, #63).
- [ ] Use the Hearthstone (and Astral Recall on a shaman) on a hearth step: the line ticks when the cast ends (#64).
- [ ] A vendor or trainer step ticks only after that NPC's window is opened and closed, not another vendor's (#65, #68).
- [ ] A go-to line with a radius ticks within about that many yards of its place, not earlier or much later (#66).
- [ ] With the hearthstone set at an inn before Noir was installed, a step that skips "if your hearthstone is set in" that zone skips after binding there once more (#67).

### Progress (rebuild)

- [ ] When a step with a quest you have becomes current, the game's quest tracker starts following that quest; untrack it and it stays untracked until the next step; with the tracker full, nothing else is added (#69).

### Guide window (rebuild)

- [ ] Hover an "Accept" or "Turn in" line on a card: the game's own quest tooltip shows, not just the line's words (#70).
- [ ] When a new step comes up, its card slides in from the right without drawing outside the card stack, and the card stack never leaves the screen (#71).
- [ ] Double-click a row of the step list quickly: the step menu opens once; click it twice slowly (more than half a second apart): nothing opens; right-click a row: the step menu opens (#72).
- [ ] The step list scrolls with the mouse wheel and the scrollbar, and after every step change the current step is the top row (#73).

### Arrow and map pins (rebuild)

- [ ] Hover a pin on the world map and on the minimap: a tooltip lists each step and line of the pin; click the same pin: the map takes the click (it zooms or pans as without the addon) (#74, #77).
- [ ] With a step on a card that has a path, open the world map on its zone: the path shows as dashes, not dots (#75).
- [ ] Stand in the Eastern Kingdoms with the current step in Kalimdor: the arrow freezes pointing up with "On another continent" and one chat line says so (#76).
- [ ] Places closer than about 60 yards share one world map pin with a "+", and later steps' pins fade; the current pins are larger and opaque.

### Menus (rebuild)

- [ ] Out of combat, open the window's menu and a submenu, then press Escape: the whole menu closes and the game menu does not open. With a menu open, press W: the character walks and the menu stays open (#78).
- [ ] In combat, open the menu and press Escape: the menu closes, and the game also sees Escape (the game menu opens or the target clears); that double action is expected, as the game does not let an addon keep Escape in combat (#78).
- [ ] With a menu open, click anywhere outside it: the whole menu closes and the click does nothing else; click a row of the menu or of a submenu: the row takes the click and the menu does not close first (#79).

### Automation and buttons (rebuild)

- [ ] Hold Ctrl and talk to a quest giver of the step: nothing is accepted or handed in. Hold Shift at a flight master or innkeeper of the step: no dialogue line is picked and no flight is taken; quests are still accepted with Shift held (#80).
- [ ] A party member shares a quest of the current or next step: it is accepted and the popup goes away; a quest of no step is left to you (#81).
- [ ] Hand in a quest with several reward choices: the page stays open and a coin marks the choice that sells for most; select that quest in the quest log before handing it in: the coin marks the same choice there (#82, #83).
- [ ] With "train" on, open your class trainer: within a few seconds every spell you can learn is bought, cheapest level first; a profession trainer and (on a hunter) the pet trainer are left alone (#84). On a class training step, the trainer's dialogue line is picked (#85).
- [ ] Item buttons: on a step with an item to use, the item shows on a button, a click uses it, its cooldown shows; on a hearth step the Hearthstone (and Astral Recall on a shaman) is there (#86).
- [ ] Target buttons: click one near the named mob: it is targeted and marked (skull, cross, square by position; star, circle, diamond, triangle for friendly NPCs); the portrait replaces the placeholder (#86, #88). `/macro` shows no macro made by Noir.
- [ ] The key bindings menu has a "Noir Guides" header with four item and four of each target binding; a bound key clicks the button once (#87).
- [ ] With the nameplate option on, the nameplate distance is raised; switching it off gives the old distance back (#89).
- [ ] While the Hearthstone is being cast the target buttons hide, and they come back when the cast ends or is cancelled (#90).
- [ ] Hold Ctrl and talk to a quest giver that shows a list, let go of Ctrl and click a guide quest in the list: the quest page (accept, or hand-in and reward) is left to you. The same with Shift at a flight master's list and its flight line: no flight is taken. On a vendor step for an item sold in bundles (for example arrows), the right number of whole bundles is bought (#91).
- [ ] Start dragging the item row and get attacked before letting go: the row stops at once, no blocked-action popup shows; in combat the rows do not move at all (#92).
- [ ] Open the talent window at level 10 or above: above it, the addon's own strip shows "Build:" and the next point; on the build's tab a pulsing ring sits on that talent's button and moves to the next one after you learn the point; on another tab the ring hides and the line says which tab to open (#93). Nothing of the talent window itself moves or changes.
- [ ] On a client with two talent groups, switch groups: 1.5 s later the chat asks to choose a build for that group once, and the build picker keeps one choice per group (#94).
- [ ] Have a class quest and a profession quest in the log (for example the first class quest, and a First Aid or Fishing quest), then open the quest cleanup: neither is listed (#95).
- [ ] Open the quest log: a "Quest cleanup" button sits beside its right edge, near the top, and a click opens the cleanup window; it hides with the quest log (#96).

### Settings, minimap button, commands (rebuild)

- [ ] Open the game's options window, AddOns: "Noir Guides" is listed and shows the tabs General to Profiles; type /noir alone and the options window opens at that page. Do the same in combat: nothing opens until combat ends, then the page opens by itself (#97).
- [ ] The minimap button sits on the minimap's edge at the bottom left; drag it around the edge and it follows the cursor along the rim and stays there after /reload; left click hides every Noir window and a second click brings them back; right click opens the main menu at the cursor (#98).
- [ ] With TomTom loaded, 20 seconds after login one chat line warns about the second arrow; with the warning switched off (Advanced) it does not come (#99).

### Grey items and profession skill reminders (0.4.0)

- [ ] At level 2 to 20 with grey items in the bags and under 10 silver, a class trainer visit shows "Sell your grey items at <vendor> before training" with an arrow to that vendor; `/noir state` prints the money and the grey items it sees (#100). After the trainer window has been opened once at that level, the line says "training costs about ..." with the sum of the spells that were available, also on another character of the same class (#102).
- [ ] Open any vendor with grey items: one slot is sold every 0.2 s, whites and better stay, and one chat line gives the count and the total; hold Shift (or Ctrl or Alt) while opening the vendor and nothing is sold (#101).
- [ ] With a planned or learned profession, a reminder "Raise <profession> to 50" with the skill counter shows from the start of the section that holds the Journeyman trainer step, ticks itself at 50, and is gone once the trainer step is passed.

## 3. Skyborne start (High Order and Windshaper)

The two Skyborne races, `HighOrder` (Alliance) and `Windshaper` (Horde), start on Zephras Isle (AreaTable area 16593, its own continent 2991). Their routes rest on the most assumptions.

- [ ] A new High Order and a new Windshaper character get their route (`alliance-highorder`, `horde-windshaper`), starting on Zephras Isle.
- [ ] The isle quests the chains require are offered: 92514 and 92595 to Windshapers (the data gives them mask 32, the High Order bit alone), 92460 to both races (`docs/routes/DATA-NOTES.md` section 2).
- [ ] The way off the isle (`skycutter-zephras-dalaran` for the Alliance, `skycutter-zephras-mulgore` for the Horde) is a ship at the docks Zephras Isle 65.8, 83.8 and 57.7, 81.0, not the portal object beside it; it can be boarded only after the exit quest (94946, Horde 95349) and level 7; there is no ride back.
- [ ] The Alliance skycutter arrives at Alterac Mountains 12.8, 51.2 (Dalaran), the Horde one at Mulgore 34.3, 26.1.
- [ ] High Order: the Skyborne Portal to Stormwind (`portal-dalaran-stormwind`, object 631299 at Alterac Mountains 12.04, 56.21) for quest 94947 "Welcome to Azeroth" works and arrives in Stormwind.

## 4. Transports and travel

Links the planner uses or knows that are not verified (`tools/planner/transports.json`, `docs/routes/TRAVEL-NOTES.md` sections 3, 4 and 8):

- [ ] `boat-menethil-auberdine`: does the Menethil Harbor boat sail straight to Auberdine, or stop at Southshore on the way?
- [ ] `boat-stormwind-auberdine`: does the Stormwind Harbor boat to Auberdine sail, and only for the Alliance?
- [ ] `boat-steamwheedle-powderfuse`: does the Steamwheedle Port to Powderfuse Port boat sail, and for both factions?
- [ ] `tram-stormwind-ironforge`: does the Deeprun Tram run as in the original game, about two minutes station to station?
- [ ] `skycutter-zephras-dalaran`, `skycutter-zephras-mulgore`, `portal-dalaran-stormwind`: see section 3.
- [ ] Is there a Horde flight master on Mount Hyjal? The routes assume not.
- [ ] Each walking pass between zones is placed to about 300 yards from the public map, and only the time estimates depend on them. The three Forever zones are entered on foot as the data suggests: Riverglades from the east end of the Burning Steppes, Mount Hyjal from Winterspring, Shen'dralas from south-east Desolace.

## 5. Quest data

- [ ] Is quest 8 "A Rogue's Deal" offered to every Undead class? The data says yes; the routes give it to all of them (`docs/routes/DATA-NOTES.md` section 1).
- [ ] Forever-only class quests (220 entries over 38 characters, `docs/routes/CLASS-NOTES.md`) are left out of the routes. **Owner decision:** should the routes take them?
- [ ] The Paladin tome chains (1641/1642, 1645/1646, 1649 and their follow-ups) are left out because they start with a repeatable donation quest; are they playable on Forever?
- [ ] Quests 4964 and 4975 have negative prerequisites in the data (-4962, -4963) and are never routed; are they offered in the game?
- [ ] The simulator's 56 of 56 assume the quests behave as the data says; one full play of a starting zone per faction is the cheapest check of that.
