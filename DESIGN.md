# The tooltip panel: the design of Noir Guides' interface

This document is the authority for the addon's colors, type and layout. `NoirGuides/UI/Theme.lua` holds the same values for the code, and `tools/test-lua/theme.lua` fails when the two differ, so a value is changed here and there together or not at all.

The direction is the game's own tooltip panel, executed at full craft: a blue-black panel, lifted plates, a black hairline, white text with the game's drop shadow, gold for facts. The quality bar is ElvUI and the game's own tooltips: every edge one pixel, every edge on a pixel, nothing that the game itself would not draw. The owner chose this direction on 2026-11-13, in place of the earlier flat near-black and warm off-white look.

**Where this document comes from.** The direction is the owner's choice, named above; its look is borrowed from the game's tooltip and from the pixel discipline of ElvUI, and no file of either is used. The layout of the guide window (header, card stack, step list, footer) follows the behavior spec `docs/superpowers/specs/2026-11-11-guide-behavior.md`, sections 4.1 to 4.3. Everything else on this page, including every color, size and measure, was written new for this repository. If the owner confirms other values as his own work, they can replace the ones below: the tables on this page and the token tables at the top of `Theme.lua` are the only places to change.

## The idea

A tooltip in the game says what a thing is, in a few lines, on a dark panel the eye reads without effort. Noir Guides shows a section of the route the same way:

- **The card stack** holds the steps to do now: the current step and the reminders that stay open beside it, one card each. A card is a plate: an edge along its top in the card's color, a badge with the step's title or number, and one row per line of the step with a tick box, a kind icon and the line's words.
- **The step list** below the header holds every step of the section, one row each, in order. Steps already passed are dimmed; the current step is the top row. It is there to look ahead and to go back, not to be read closely.
- **The header** names the section; **the footer** says where the character stands: the level, the share of the section done, and a rail through the section's level range.

Two things live outside the window and belong to the same system: **the arrow**, which points at the place of the steps on the cards, and **the pins**, which mark those places and the next ones on the world map and the minimap.

Rules that follow from the idea:

1. One accent. The lamp color is the theme's (the player's class color by default; see Themes) and marks what is current: the window's inner border, the current card's top edge and badge, the current row of the step list, the rail's fill, the arrow, the current step's pin. Nothing else uses it for long: the top edge of a new current card shows the step's kind for three seconds and then returns to the lamp color.
2. The window says what the game's state says. It never shows a step as done, and it never hides a step, on its own judgment. A line the player ticks is shown ticked; a step the engine passed says why when the mouse is on its row.
3. Text is short and built from parts: an action, a name, a place. A step's own text and its notes are the only sentences.
4. The interface is quiet. No sound and no flashing on a step change. The card slide and the talent ring are the only motion in the interface: a new current card slides in once, and the talent ring turns while talent points wait.
5. Shape before color. Every line kind has its own icon, the tick box is an outline that fills, and the current step's pin differs from the others by its shape, so the difference survives color blindness and a busy map.

## Color

The window sits over the game world, so it is a dark blue-black panel the player sets the opacity of, with plates nearly opaque on it and text in near-white.

| Token | Hex | Used for |
|---|---|---|
| `bay` | `#141922` | The window's panel, at the player's background opacity (see Panel opacity). |
| `strip` | `#222A37` | A plate: a card, the header, the footer, a row of the step list under the mouse. |
| `ink` | `#000000` | The window's outer hairline, the rules between the bands, the outline of the rail. |
| `lamp` | `#F2B33D` | The accent: the window's inner border, the current card's top edge and badge, the current row of the step list, a ticked box, the rail's fill, the arrow, the current step's pin, the addon's name in chat. This is its gold; with another theme it is that theme's color (see Themes). |
| `quest` | `#FFD100` | The quest icons (accept, hand in) and the accept mark on a new card: gold whatever the theme, so the icon colors keep their meaning. |
| `gold` | `#FFD100` | The section's facts in the header: the game's heading gold. |
| `paper` | `#F4F5F7` | Primary text: the lines of the cards and of the steps still to do, the section's name, the arrow's distance. |
| `dim` | `#B9BFCA` | Secondary text: a step's own text, the footer, lines already done. |
| `faint` | `#8D95A3` | A reminder's top edge, the step numbers in the list, the next steps' pins, an empty tick box, the icon of a line done. |
| `track` | `#4A5466` | A card's one-pixel frame, a slider's track, an empty box in the menus. |
| `well` | `#0B0E13` | The rail's track: the well the fill runs in. |
| `warn` | `#FF8A5C` | A note on a card: something stands in the way of the step. |
| `ok` | `#5BD675` | Arrived (the arrow within a few yards), the route complete, the hand-in mark on a new card. |
| `friend` | `#74CCF4` | A friendly NPC named in a line; the trainer mark on a new card. |
| `enemy` | `#FF6F6F` | An enemy to kill named in a line; the objectives mark on a new card. |
| `loot` | `#D9A6FF` | An item to loot or use named in a line. |
| `warning` | `#FF8A5C` | A quest whose prerequisites are not handed in yet. |
| `object` | `#7FE0CC` | An object to click named in a line. |
| `buy` | `#BCE27A` | An item to buy named in a line. |

Named things are colored by meaning while the "highlight" setting is on (the default); with it off every line is in one color.

## Themes

The "Theme" setting (Guide window; option key `accent`) is `class` by default: the lamp becomes the player's own class color. It can also be any class by name, `gold`, or `black`. The theme is set when the interface loads, so changing it asks and reloads. Quest icons stay `quest` gold whatever the theme.

| Theme | Accent | Ratio on strip |
|---|---|---|
| Warrior | `#C69B6D` | 5.7 |
| Paladin | `#F48CBA` | 6.4 |
| Hunter | `#AAD372` | 8.4 |
| Rogue | `#FFF468` | 12.7 |
| Priest | `#B4A7E8` | 6.6 |
| Shaman | `#4FA3F2` | 5.4 |
| Mage | `#3FC7EB` | 7.3 |
| Warlock | `#9A9BF2` | 5.7 |
| Druid | `#FF7C0A` | 5.6 |
| Gold | `#F2B33D` | 7.8 |
| Black | `#D9DDE4` | 13.2 (on its own strip) |

The class accents are the game's class colors with three changes, so every accent reads on a card at 4.5 to 1 or more: the priest's white is a lavender, unlike the text, and the shaman's and the warlock's blues are lighter. A class with no color here keeps the gold.

Black is the monochrome theme: a silver accent in place of a color, and a darker panel. It replaces four colors: lamp `#D9DDE4`, bay `#000000`, strip `#14171C`, track `#3A3F48`. Every other color stays as the Color table gives it.

## Panel opacity

The "Background opacity" slider (Guide window; option key `backgroundAlpha`) sets the opacity of the panel, from 0.2 to 1 in steps of 5%, and is 0.75 by default. It applies at once, with no reload. Only the bay follows it: the cards stay nearly opaque (0.94) so their words always read, whatever the panel shows through.

## Contrast

Contrast ratios (WCAG 2 formula) of each text color on the surface it is drawn on, taking the bay as fully opaque. All are 4.5 to 1 or more. The theme accents on the strip are in the Themes table.

| Text | Surface | Ratio |
|---|---|---|
| lamp | strip | 7.8 |
| quest, gold | strip | 9.9 |
| paper | strip | 13.2 |
| dim | strip | 7.8 |
| faint | strip | 4.8 |
| warn, warning | strip | 6.2 |
| ok | strip | 7.8 |
| friend | strip | 8.0 |
| enemy | strip | 5.3 |
| loot | strip | 7.5 |
| object | strip | 9.2 |
| buy | strip | 9.8 |
| gold | bay | 12.1 |
| paper | bay | 16.2 |
| dim | bay | 9.5 |
| faint | bay | 5.8 |
| enemy | bay | 6.5 |

With the black theme every ratio is higher: paper is 16.5, dim 9.7 and faint 6.0 on its strip.

The bay is as transparent as the player sets it, so over a very bright scene (snow, a white sky) the step list's contrast is lower than the table says; the game's drop shadow under every letter keeps the edges of the text dark. The cards are nearly opaque and are hardly affected.

## Type

One family, four sizes. The family is the game client's default interface font for now: the code asks the client for its default font file (`STANDARD_TEXT_FONT`), which is also the right font on clients in other scripts. The addon's own font file is added later by the owner; setting `Theme.fontFile` to its path is the whole change, and a file that fails to load falls back to the client's font.

| Role | Size | Used for |
|---|---|---|
| `kicker` | 10 | A card's badge, in capitals; "Step N" at a card's top right. |
| `name` | 14 | The section's name in the header. |
| `body` | 11 | The lines of the cards and of the step list, a step's own text. |
| `small` | 10 | The subgroup, the range in view, the step numbers, the footer, the arrow's distance. |

With the font size setting on "large", every size is `large` (see Measures) bigger. Text is left-aligned and wraps inside the window; the range in view and the step numbers are right-aligned. Every letter has the game's own drop shadow: one pixel down and right, black at 0.9 opacity (`Theme.Shadow`), so text reads over any part of the world. There is no outline.

Fonts are set by file only. A font object is never handed to a font string, because the Forever client crashes when `SetFontObject` receives anything but one of its own named font objects.

## Measures

In interface units (the client's scaled pixels). The window is `width` wide until the player resizes it, and as tall as the header, the step list and the footer.

| Name | Value | Meaning |
|---|---|---|
| `width` | 260 | The window's width. |
| `pad` | 10 | From the window's edge to its content. |
| `gap` | 4 | Between two blocks of text, between the icon and the words, between the cards. |
| `lamp` | 2 | The thickness of a card's top edge in its color. |
| `rail` | 5 | The rail's thickness. |
| `arrow` | 48 | The arrow's side. |
| `pin` | 14 | A next step's pin. |
| `active` | 20 | The current step's pin. |
| `alpha` | 0.95 | The panel's opacity before the player sets the background opacity (`backgroundAlpha`); the buttons' background. |
| `icon` | 12 | A kind icon. |
| `tick` | 12 | A tick box. |
| `header` | 36 | The header's height. |
| `footer` | 26 | The footer's height. |
| `list` | 240 | The step list's height until the player resizes it. |
| `slide` | 0.25 | Seconds a new current card takes to slide in. |
| `mark` | 3 | Seconds a new current card's top edge shows the step's kind. |
| `large` | 2 | Added to every type size with the large font size. |
| `button` | 32 | An item, spell or target button's side. |

## Layout

```
+----------------------------------------------+
|==============================================|   card stack: one card per step on screen,
| REMINDER BADGE                       Step 4  |   reminders farthest from the window
| [ ] (icon) Rattlecage Bone: 2/5              |   (top edge faint),
+----------------------------------------------+
|==============================================|   the current card nearest to it (top edge
| SARVIS                               Step 5  |   in the accent): badge, step number,
| Shadow Priest Sarvis stands by the crypt...  |   the step's own text, one row per line:
| [x] (icon) Turn in Rude Awakening            |   tick box, kind icon, the line's words
| [ ] (icon) Accept The Mindless Ones          |
+----------------------------------------------+
| 1-3 Deathknell                    (menu)     |   header: the section's name, the menu button,
| 1-20                         Steps 2-7 of 10 |   the subgroup and the range of steps in view
|==============================================|   ink rule, then a 1px accent line
|# (icon) Accept Rude Awakening             1  |   step list: one row per step, its lines indented,
|  (icon) Turn in Rude Awakening            2  |   the step number at the corner; the current row
|  (icon) Accept The Mindless Ones             |   on an accent tint with an accent line; rows
|  ...                                         |   behind the place at half opacity; a scrollbar
|----------------------------------------------|   on the right when the rows do not fit
| 0.2.0       Level 2, 18% done           //  |   footer: version, level and share, resize grip,
| [####|####|####|..........................]  |   the level rail: a glossy accent bar in a well
+----------------------------------------------+
```

- **The window** is the bay at the player's opacity inside a double hairline: one pixel of ink outside, one pixel of the accent inside.
- **The card stack** is attached to the window above its header; with "cards below" on, below the window. When that side has no room on the screen the stack flips to the other side; when neither side has room for every card, the cards farthest from the window (the oldest reminders) are left out until the stack fits, and the current card is always shown. The current card is always the one nearest to the window.
- **A card** is a plate: the strip, nearly opaque, with the sheen over its top, a one-pixel frame in track (tinted with the accent for the current card), and an edge `lamp` high along its top in the card's color: the accent for the current card, faint for a reminder, the color of the step's kind for `mark` seconds on a new current card. Its content starts `pad` from its edges. The badge comes first, with "Step N" at the top right, then the step's own text when it has one, then one row per visible line: the tick box, `gap`, the kind icon, `gap`, the words, which wrap. A line the player cannot tick (a note, a marker, the grind line the engine adds under a step's level) has no tick box.
- **The header** is `header` high, a plate with the sheen: the section's name in paper on the first line, its facts (the subgroup) in gold under it, the range of step numbers in view on the right, and the menu button in the top right corner. Under it runs a rule of ink and then a one-pixel accent line. With no section the header invites the player to choose one and the window is the header alone.
- **The step list** fills the room between the header and the footer; its height is the player's (resize grip or Alt-drag) and is saved per profile. Each row is the step's lines, each with its icon and words, indented by `pad`, and the step number in the top right corner. The current row has a background tinted with the accent and a one-pixel accent line along its edge. The mouse wheel and the scrollbar scroll it; "hide finished steps" stops it at the current step. With "show the step list" off, the window is the header and the cards.
- **The footer** is `footer` high, below a rule of ink: the version on the left, the level and the share of the section done in the middle, the resize grip in the corner, and under them the level rail across the window between the paddings. The rail is `rail` high: a glossy bar in the accent (the `bar` texture) in a black well, with an ink outline. Its fill is the character's level and experience within the section's level range, with a tick per level when the range is 20 levels or fewer.

## States

| What the window shows | Header | Cards | Step list | Footer |
|---|---|---|---|---|
| A section being played | the section's name and subgroup, the range in view | the current card and open reminders | every step for the character, the current row tinted with the accent | version, level and share, rail |
| A new current step | as above | the new card slides in; its top edge shows the step's kind for `mark` seconds: hand in (ok), accept (quest), train (friend), objectives (enemy), travel (dim), in that order of prominence | scrolled so the new step is the top row | as above |
| A line done or ticked | as above | its tick box filled with the lamp color; its words in dim, named things included, and its icon faint | the row unchanged | as above |
| A row under the mouse | as above | as above | the row on the strip color; its tooltip tells why the step was passed when the engine passed it | as above |
| Route complete | as above | one card: You have reached the end of the route. | every row dimmed | share 100% |
| No section | Choose a section | none | none | none |

Rows of steps behind the place, finished steps and finished reminders are at half opacity; the current and later steps are full. Steps hidden for the character (another class or race, a profession not planned) are not shown, nor are steps the character has outleveled.

## The words of a step

`NoirGuides/UI/Text.lua` builds the words of every line from the line and the generated data; routes contain no sentences except a step's own text and its notes. Each line has a kind icon.

| Line | Icon | Words |
|---|---|---|
| accept | `accept` (`error` while a prerequisite is not handed in) | Accept *quest* |
| turnin | `turnin` | Turn in *quest* |
| objective | `kill`, `item` or `objective` | the quest log's objective with its counter: *Rattlecage Bone: 2/5* |
| collect | `item` | Collect *item* *have/need* |
| goto | `goto` | Go to *zone x, y* |
| getflight | `flightpoint` | Get the *name* flight point |
| fly | `flight` | Fly to *destination* |
| transport | `flight` | Take the *zeppelin, boat, tram, portal* to *zone* |
| sethearth | `bind` | Set your hearthstone at *zone* |
| hearth | `hearth` | Hearth to *zone* |
| grind | `xp` | Grind to level *n*, or Grind until *p*% into level *n*, with the experience counter |
| train | `trainer` | Learn *spell*, Learn *rank* *profession*, or Visit *trainer* to learn your level *n* spells |
| vendor | `vendor` | Visit *vendor*, buy *count* *item* |
| use | `item` | Use *item* |
| target | `kill` or `gossip` | Kill *enemy*, or Talk to *NPC* |
| note, manual | `note` | the note's own words |

Quest names on accept and hand-in lines are links: with the mouse on the line, the game's quest tooltip shows. A line's tooltip also lists prerequisites not handed in, the why-log entry of a line the engine passed, and the option that will pass it (pass when the quest is missing, pass when it is not ready). The mouse on a tick box says what the box does. A name comes from the generated data, then from the client, then a plain label ("Quest 364").

## The arrow

- A single arrowhead, `arrow` units square, in the lamp color, with the distance in yards under it in `small` type.
- It turns to show the direction relative to where the character faces: up is straight ahead.
- Within 8 yards of the place it turns to the ok color.
- It is hidden, not greyed, whenever the direction is not known: the step has no place, the place is on another continent, the client gives no position (instances) or no facing. When only the distance is unknown, the arrow shows without the number.
- It is a separate frame, placed under the top middle of the screen at first, and can be dragged like the window.

## The pins

- The current step's pin is a disc inside a ring, `active` units, in the lamp color. The next steps' pins are plain rings, `pin` units, in the faint color.
- Pinned are the steps on the cards and the next steps still to do; steps at the same place share one pin.
- On the world map the pins sit on whatever map is shown: the zone's own, or the continent's. A place that is not on the shown map has no pin.
- On the minimap, a place out of range keeps the current step's pin on the rim in its direction; the other pins are left out until they are in range.
- Pins take no mouse input: a click on a pin is a click on the map.

## The buttons

- Item and spell buttons sit in one row, target buttons in two groups (enemies on top, friendly NPCs under them), four to a row. Each button is `button` units square with `gap` between buttons and around the row, on the bay color at the bay's opacity ("Button background" turns it off).
- An item or spell button shows its icon and its cooldown; a target button shows the unit's portrait once it was the target, else the kill or gossip icon.
- The rows are dragged like the window; while windows are locked, Alt-drag still moves them. "Button scale" sizes both rows from 80% to 300%.
- On a reward page with a choice, a coin marks the choice that sells for most (in the quest log too).

## Moving, locking, scaling

- The window is dragged with the left mouse button by its header or its body and resized by the grip in its corner or by Alt-dragging; its place and size are saved per profile.
- "Lock windows" stops all moving and resizing.
- "Window scale" sets its size from 20% to 200%. The window's top left corner stays where it was placed.
- "Hide the guide window" hides it while the arrow, the pins and the engine go on; hiding Noir Guides hides every window of the addon.
- "Reset profile" puts every window back in its first place at normal size.
- A window is never off the screen: it is kept inside when it opens, is dragged, grows, or when the resolution or the UI scale changes. A saved place that is off the screen (a smaller monitor, a changed UI scale) is brought back inside.

## Textures

Drawn by `tools/gen_textures.js` (`npm run textures` in `tools/`) into `NoirGuides/Textures/`; the files are never edited by hand, and a test fails when they differ from what the generator draws. Each is white with its shape in the alpha channel and is tinted with a color of this page, so one file serves every color. Each shape stays inside the circle that fits its square, so it can be turned without being cut. Two files are not shapes but gradients, `sheen` and `bar`: their alpha runs from the top of the square to the bottom and fills it edge to edge, and they are stretched over a region and never turned, so the circle rule does not apply to them. Format: uncompressed 32-bit TGA, sides a power of two.

| File | Size | Used for |
|---|---|---|
| `arrow` | 64 | The arrow: an arrowhead pointing up. |
| `pin` | 32 | A next step's pin: a ring. |
| `pin-active` | 32 | The current step's pin: a disc inside a ring. |
| `box` | 32 | A tick box: a square outline, tinted faint when empty and lamp when ticked. |
| `tick` | 32 | The tick inside a ticked box. |
| `grip` | 32 | The resize grip: three diagonal strokes. |
| `menu` | 32 | The header's menu button: three bars. |
| `sheen` | 32 | A gradient: the light on a plate (a card, the header), full at the top and gone two thirds down; drawn white at alpha 0.07 over the plate. |
| `bar` | 32 | A gradient: the glossy fill of a status bar (the rail), a bright top edge over a lighter upper half and a deeper lower half; tinted with the accent. |
| `icon-accept` | 32 | Accept: an exclamation mark. |
| `icon-turnin` | 32 | Hand in: a question mark. |
| `icon-objective` | 32 | An objective: a target. |
| `icon-kill` | 32 | An enemy to kill: a cross. |
| `icon-item` | 32 | An item: a bag. |
| `icon-vendor` | 32 | A vendor: a coin. |
| `icon-trainer` | 32 | A trainer: an open book. |
| `icon-gossip` | 32 | Talk to someone: a speech bubble. |
| `icon-flight` | 32 | A flight, boat, zeppelin or portal: a plane seen from above. |
| `icon-flightpoint` | 32 | A flight point to learn: a flag. |
| `icon-hearth` | 32 | Use the hearthstone: a house. |
| `icon-bind` | 32 | Set the hearthstone: a stone. |
| `icon-goto` | 32 | Go to a place: a map pin. |
| `icon-xp` | 32 | Experience and levels: a star. |
| `icon-error` | 32 | Something stands in the way: a warning triangle. |
| `icon-note` | 32 | A note: a page. |
| `icon-timer` | 32 | A timer (the flight bar): a clock. |

Flat areas (the bay, the plates, the hairlines and rules, a card's top edge, the rail's well) are solid colors and need no file.

## What the interface never does

- It never changes the game's own frames. The world map and the minimap are read (size, zoom, shown map) and given child frames; nothing of theirs is moved, resized, re-parented, hooked or scripted. Popups are not restyled: confirmations use the addon's own dialog.
- It never makes a protected call. The window, the cards, the arrow and the pins are the addon's own unprotected frames, so showing, hiding, moving and updating them is allowed in combat; frames inside the map frames are created outside combat.
- It never calls `SetFontObject`.
- It plays no sound on a step or quest change.
- It creates no global: no frame has a name.
