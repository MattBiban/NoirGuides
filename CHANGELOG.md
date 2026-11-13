# Changelog

## 0.3.0

- **A new look.** The guide is restyled after the game's own tooltips, with ElvUI-sharp edges: a lighter blue-black panel you can see the world through, a black-and-accent double border, cards as lifted plates with a soft sheen, the game's text shadow, a gold line of section facts in the header, and a glossy progress bar. Menus, dialogs, the setup wizard, quest cleanup, the bug report and the item and target buttons share the look.
- **Themes.** Settings, Guide window, Theme: your class color (the default), any of the nine class colors (a mage can wear rogue yellow), Gold, or Black (a black panel with a silver accent). Changing it reloads the interface.
- **Background opacity.** A new slider in Settings, Guide window, from 20% to 100% (75% by default). It applies at once; the cards stay nearly solid so their words always read.
- **Step numbers on cards.** Each card shows "Step N" in its top right corner, as the step list does.
- **Clearer cards.** The current card is framed in your theme color with a colored top edge; reminders have a grey edge. A finished line is greyed out completely, names included. The current row in the step list keeps its highlight when the mouse passes over it.

## 0.2.2

- **The skin takes your class color.** The accent (the current step's side bar and badge, ticked boxes, the rail, the arrow, the current map pin, menus, the minimap button and "Noir" in chat) and the guide window's border are now in your class color. The priest's white is a lavender, so it stands apart from the text, and the shaman's and warlock's blues are a little lighter so they stay readable. Quest icons stay gold. To go back to the gold look: Settings, Guide window, Accent color, gold (the interface reloads).
- **Fixed: target buttons no longer cause an "AddOn tried to call the protected function SetRaidTarget()" error.** The raid marker is now set by the button's own click, which the game allows. A click on a mob that is out of range now clears your target instead of marking whatever you had targeted before.

## 0.2.1

- **Smooth arrow.** It looked where the player is 20 times a second; it now does every frame, and its direction eases toward the true one, so turning glides instead of stepping.
- **The guide window can be resized.** The corner grip lay under the step list, which took its mouse; it is now above it, larger, and lights up under the mouse.
- **The menu no longer covers the window.** The main menu (the menu button, a right-click on the header or footer) opens beside the window, to the right, or to the left when there is no room.
- **Easier to read.** A lighter window with a border, the header and footer as their own bands, the current step lit in the step list with a gold bar, and line icons colored by kind: gold to take and hand in quests, red to kill, purple for items, blue for travel, green for trainers.

## 0.2.0

The guide rebuilt from the behavior specification (`docs/superpowers/specs/2026-11-11-guide-behavior.md`), in a clean room: no other guide addon, and not the earlier fork, was opened to write it (`docs/INDEPENDENCE-REVIEW.md`). Nothing the player needs depends on a command any more.

- **Sections.** Each race's route (route format 3) is split into 29 to 38 sections named by level range and zone ("1-8 Tirisfal Glades"), grouped by faction and level band. The right section is chosen by itself for any character, and the next one loads by itself at the end of a section; the section picker in the menu changes it by hand.
- **Bundled steps.** Accepts, hand-ins and objectives at one place are one step with one line each (61 to 65% as many steps as the 0.1 actions). Steps carry their own short instruction text, reminders that stay on screen until their hand-in, grind targets where the route is above the estimated level, class trainer visits, and profession trainer steps for planned professions.
- **Card stack and step list.** The window shows the steps on screen as a stack of cards, each line with a tick box that ticks itself when the game confirms it, and under it a scrolling step list of the whole section with done steps dimmed; hovering a step shows why it was passed. Right-click or double-click a step for the step menu.
- **Settings panel** in the game's options window (AddOns, "Noir Guides"), with the tabs General, Guide window, Navigation, Automation, Route, Advanced and Profiles; account-wide profiles. Saved variables move to schema 2 and are migrated, not reset.
- **Minimap button** on the minimap's rim: left click hides or shows every window, right click opens the main menu, drag it along the rim.
- **Menus at the cursor**: the main menu, the step menu and the section picker open where you click, stay on the screen, and close with Escape or a click outside.
- **Setup wizard** for a new character, opening by itself a few seconds after the first login.
- **Pins and arrow per the spec**: the arrow points to the first open place of the current card (the corpse while dead), says when the step is on another continent, and follows paths; pins mark the current and next steps on the world map and the minimap, merge when close, fade for later steps and list their steps in a tooltip.
- **Joiners placed by themselves.** A character that joins the route mid-way, at any level, gets the section for its level and its place from the quest log and the quests handed in, with no command; chat says where it landed.
- **Item buttons and target buttons** beside the window: quest items, the Hearthstone on a hearth step, and quest mobs and NPCs to target and mark, all key-bindable (`Bindings.xml`).
- **Automation v2**: accept and hand in, reward choice marked, flights, the hearthstone, dialogue, vendor lines and class training, each with its own switch; Ctrl or Shift holds it for one NPC.
- **Windows never leave the screen**: every window has a default place, is kept fully on the screen when it opens, is dragged, grows, or when the resolution or UI scale changes, and can be moved, locked, scaled and reset.
- **Checked outside the game**: the simulator plays all 56 characters from level 1 and 50 joiners at levels 1, 12, 25, 40 and 55 to level 60 with no stuck step, no unexplained skip, no command and no window off the screen (`docs/routes/SIM.md`). What only the game can confirm is in `docs/INGAME-CHECKLIST.md`.
- **Packaging:** `npm run package` builds `dist/NoirGuides-0.2.0.zip`.

## 0.1.2

- **The menu stays on the screen.** It was centred and grew both ways, so a long menu ran off the top of the screen. It now hangs from near the top, is kept on the screen, is drawn smaller when it would not fit, and can be dragged.
- **No /noir sync needed.** A place saved by 0.1.0 (which always began at step 1) is worked out again by itself at the next login.

## 0.1.1

- **Finds your place when you join mid-route.** A character that did not play the route from its first step (an existing character, or one carried along by another guide) was held on the first step it had not done, often a level 2 quest in the starting zone, with the arrow hidden because that step lay on another continent. At the first login with a route, the place is now worked out from the quest log and the quests handed in, and chat and `/noir why` say where it landed and how many earlier steps were left undone (`/noir back` returns to them).
- **`/noir sync`** works the place out again at any time, for example after playing without the addon.

## 0.1.0

The first release of Noir Guides as its own addon, written new and independent of the earlier fork (`docs/INDEPENDENCE-REVIEW.md`).

- **Routes** for all ten WoW Forever races, generated from QuestieDB and the client's tables by the planner in `tools/` and checked by an independent validator: level 1 to 60 for each of the 56 class and race combinations, with class quests layered in, flights, boats, zeppelins, the tram and the Skyborne skycutters. Format 2: plain data, no sentences (`docs/routes/REPORT.md`).
- **Engine:** the current step follows the game (quest log, level, flight points, hearthstone, position); a step is never passed without a reason, and `/noir why` shows the last 20 reasons. `/noir skip`, `/noir back`, `/noir reset`.
- **Automation** of quest dialogs, gossip, flights and the innkeeper for route steps, each switch on its own (`/noir auto`), Shift to hold it for one dialog.
- **Interface:** the step window, the arrow, and pins on the world map and the minimap, in the Strip Bay design (`DESIGN.md`).
- **Menu** (`/noir menu`), **talent builds** with a legality check for every class (`/noir talents`), the **profession plan** with Forever's trainer gates 50, 125 and 200 (`/noir professions`), the **quest cleanup** (`/noir cleanup`: nothing is abandoned unless the player ticks it), and a **bug report** (`/noir bug`).
- **Checked outside the game:** Lua tests against a mock client, and a simulator in which the real engine plays all 56 routes to level 60 with no stuck step (`docs/routes/SIM.md`). What only the game can confirm is listed in `docs/INGAME-CHECKLIST.md`.
- **Packaging:** `npm run package` builds `dist/NoirGuides-0.1.0.zip`.
