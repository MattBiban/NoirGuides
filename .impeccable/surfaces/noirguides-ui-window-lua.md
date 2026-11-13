---
version: 1
slug: "noirguides-ui-window-lua"
primary_target: "NoirGuides/UI/Window.lua"
related_targets: ["NoirGuides/UI/Theme.lua"]
---

Scope: the Noir Guides guide window (NoirGuides/UI/Window.lua) and the windows that share its theme (menus, settings panel, wizard, arrow, pins, buttons). Mode: Operate.

Audience and task: WoW Forever players leveling 1 to 60, new and returning, reading the current step in glances while playing. Constraints: WoW client Lua frames only, fonts by file, nothing secure in combat, structure kept (header, card stack, step list, footer), class color accent kept.

## Direction contract

THESIS: The category standard, played straight and finished better than anyone ships it: the game's own tooltip panel, sharpened to ElvUI's pixel discipline. It refuses the flat near-black slab of 0.2.x and any invented ornament.

OWN-WORLD: Tooltip blue-black panel at player-chosen opacity (default lighter, world showing through); ElvUI double hairline border, black outside, cool steel inside; the player's class color on the current card's 1px frame, the rail and the arrow; tooltip type colors: white lines, NORMAL gold headings, quality green for done; the client's own Friz Quadrata with the game's 1px drop shadow; glossy status-bar fills.

STORY: The player glances, sees the current card framed in their class color with the next place and distance on one line, does it, watches the tick fill and the rail advance, and never wonders where they are.

FIRST VIEWPORT: Left side of the screen, 260 wide: header band with section name in white and progress in gold at right; the current card on top framed in class color, its lines with tick boxes and kind icons; the step list below in quieter rows; footer with level and a glossy class-colored rail.

FORM: canon (category standard, user-chosen), seed key ec2cb86b. Quality bar: ElvUI and WoW's own tooltips; the user asked for the best UX/UI in that frame.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
