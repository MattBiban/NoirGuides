# Travel notes

What task P2 built for travel, where each fact comes from, and what is still unconfirmed. The code is
`tools/lib/travel.js`, the hand-written facts are `tools/planner/transports.json`, the tests are
`tools/test/travel.test.js`. Data: QuestieDB Forever v1.0.14 and wago client tables for build 1.60.1.70888.
P2 added four client tables to `tools/fetch_data.js`: `TaxiPathNode`, `AreaTrigger`, `Map`, `TransportAnimation`.

## 1. What "verified" means

`verified = true` on a transport link means that **nothing about the link is assumed**:

- the client has a transport path (the `TaxiPathNode` rows of the `TaxiPath` named in `path`) that stops within 60
  yards of both ends. `buildGraph` refuses to load a verified link for which that is not true, and a test checks it
  again from the CSV;
- who may board, and how, is a public fact of the original game.

A link with `verified = false` says what is not confirmed in `assumed`, a list of:

| `assumed` | What is not confirmed |
| --- | --- |
| `route` | That it runs between these two ends: there is no client path, or the client paths disagree. |
| `factions` | Who may board. Forever's own routes have no public fact for it. |
| `boarding` | The conditions in `requires` and `oneWay`. |
| `arrival` | The exact place it arrives at. |
| `kind` | What it is: a ship, or the portal object at the same dock. |

`buildGraph` refuses a link that is verified and names an assumption, a link that is unverified and names none, and a
link without a path that does not name `route`. A test refuses a verified link whose note speaks of an assumption, and
a verified link on one of Forever's own paths (IDs from 11,000). Every link also gets `pathVerified`: the client path
is there and `route` is not assumed. So "path in the client, faction assumed" and "nothing known" can be told apart.

`travelPlan` copies `verified`, `pathVerified` and `assumed` onto every transport leg. With the option
`{ verifiedOnly: true }` it plans without the unverified links; that is how P3 can test that a route stays playable
without an assumed link (for the goblin boat it does, for the skycutters it cannot: they are the only way off the isle).

Verified does not mean anybody saw the transport in game. The client also carries paths that never sailed (path 253,
"Southshore Ferry, Hillsbrad" to Menethil, has no stops at all), so a path is evidence, not proof. Travel times are
estimates for every link and are not part of `verified`.

Every pass (the walking connections between zones) is `verified = false`.

## 2. Flight graph

From `TaxiNodes`, `TaxiPath`, `TaxiPathNode` and QuestieDB's flight master NPCs.

- **Who can use a node:** `TaxiNodes.Flags` bit 1 shows a node on the Alliance flight map, bit 2 on the Horde one. A
  faction keeps a node only when a flight master friendly to it stands within 40 yards (`friendlyToFaction`).
- **Which nodes can be learned:** only nodes with a `CharacterBitNumber` (their bit in the character's known-nodes
  mask) and at least one path to another usable node. That leaves out, by the data alone: transport nodes
  (34, 35, 46, 47, 50, 51, 54), unused nodes (1, 3, 9, 15, 24, 36, 57, 78, the three "zzOLD" nodes 3206 to 3208, 3205
  Tidegear Coast, 3274 and 3275 Powderfuse Port), the battleground nodes 59 and 60, the druid-only Nighthaven nodes
  62 and 63, the Plaguelands towers 84 to 87, and the quest paths (2913, 2914, 2930, 3260 to 3262, 3361).
- **Result:** 65 nodes: 33 Alliance, 30 Horde, 2 for both (80 Ratchet, 79 Marshal's Refuge). Every one has a flight
  master in the data, and every path between them has `TaxiPathNode` rows.
- **Flight masters:** by QuestieDB `npcFlags` bit 8. Forever's own NPCs carry no flags, so the title counts too
  ("Gryphon Master", "Wind Rider Master", "Hippogryph Master", "Flight Master", "Flight Mistress", "Bat Handler"):
  255993 Grakna at Rog'mar (3203), 257087 Gretchen Mayberry at Farholde Keep (3276), 41861 Fayran Elthas at the Summit of
  Eternity (559), 260626 Bluebell at the Tainted Foothills (3242). The `getflight` step goes to the flight master's
  own position, not the node's.
- **Time:** the length of the path's `TaxiPathNode` polyline at 32 yards a second, plus 10 seconds to board. A flight
  over several nodes is the sum of its paths; every node on the way must be learned.

Unconfirmed:

| Fact | Why | Effect |
| --- | --- | --- |
| Mount Hyjal nodes 559 and 3242 for the Horde | The client shows both nodes to both factions and joins 3242 to the Horde's Everlook node (53), but the only flight masters in the data there are friendly to the Alliance. | Left out for the Horde. `graph.notes` lists both. |
| Flight speed 32 yards a second | Not in the client data. | All flight times scale with it. |
| Which flight points a new character knows | Not in the data. | `travelPlan` takes `state.flights` as given; P3 decides the starting set. |

## 3. Transport links

Each end is the transport's stop in the client path, converted to map percent and rounded to a tenth. Times: the loop
is the path length at 30 yards a second plus the stops' delays; a trip is half a loop of waiting plus the ride.

| Link | Kind | From | To | Factions | Verified (assumed) | Path | Loop s | There s | Back s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| zeppelin-orgrimmar-undercity | zeppelin | Durotar 51.0, 13.9 | Tirisfal Glades 60.6, 58.9 | Horde | yes | 302 | 310 | 265 | 234 |
| zeppelin-orgrimmar-gromgol | zeppelin | Durotar 50.5, 12.7 | Stranglethorn Vale 31.2, 30.4 | Horde | yes | 285 | 255 | 181 | 208 |
| zeppelin-undercity-gromgol | zeppelin | Tirisfal Glades 61.9, 58.9 | Stranglethorn Vale 31.5, 29.1 | Horde | yes | 301 | 285 | 217 | 234 |
| boat-ratchet-bootybay | boat | The Barrens 63.8, 38.8 | Stranglethorn Vale 25.7, 73.1 | both | yes | 241 | 314 | 250 | 259 |
| boat-menethil-theramore | boat | Wetlands 4.7, 63.7 | Dustwallow Marsh 71.7, 56.6 | Alliance | yes | 292 | 286 | 224 | 227 |
| boat-menethil-auberdine | boat | Wetlands 4.5, 56.6 | Darkshore 32.3, 44.1 | Alliance | **no** (route) | 295 | 251 | 197 | 184 |
| boat-auberdine-rutheran | boat | Darkshore 33.3, 39.8 | Teldrassil 54.8, 97.2 | Alliance | yes | 293 | 270 | 211 | 209 |
| boat-stormwind-auberdine | boat | Stormwind City 21.8, 56.8 | Darkshore 30.5, 40.9 | Alliance | **no** (factions) | 11616 | 215 | 149 | 160 |
| boat-steamwheedle-powderfuse | boat | Tanaris 68.6, 23.0 | Riverglades 80.6, 54.6 | both | **no** (factions) | 11391 | 225 | 164 | 165 |
| boat-feathermoon-ferry | boat | Feralas 43.1, 42.8 | Feralas 31.0, 39.5 | Alliance | yes | 303 | 270 | 241 | 165 |
| tram-stormwind-ironforge | tram | Stormwind City 69.6, 30.3 | Ironforge 78.0, 51.4 | Alliance | **no** (route) | none | | 130 | 130 |
| skycutter-zephras-dalaran | boat | Zephras Isle 65.8, 83.8 | Alterac Mountains 12.8, 51.2 | Alliance | **no** (boarding, arrival, kind) | 11398 | 321 | 271 | one way |
| skycutter-zephras-mulgore | boat | Zephras Isle 57.7, 81.0 | Mulgore 34.3, 26.1 | Horde | **no** (boarding, arrival, kind) | 11457 | 290 | 271 | one way |

Notes on single links:

- **Menethil Harbor to Auberdine is not verified** because the client disagrees with itself: path 295 sails directly,
  path 11167 is the same loop with a stop at Southshore (Hillsbrad 50.7, 70.5) on the way out. Which one sails is not
  in the data. The link uses path 295's time; the Southshore stop is not a link.
- **Stormwind Harbor to Auberdine (11616)** and **Steamwheedle Port to Powderfuse Port (11391)** are Forever routes:
  the paths and their stops are in the client, nothing else is known about them. That the first is for the Alliance
  only (both docks are in Alliance towns) and that both factions may board the goblin boat are assumptions, so both
  links are `verified = false` with `assumed = ["factions"]`. Neither is needed: Auberdine is also reached by the boat
  between Booty Bay and Ratchet, Riverglades on foot from the Burning Steppes.
- **Deeprun Tram** has no transport path, so it stays unverified. Evidence that is in the client: `Map` 369 "Deeprun
  Tram" has its entrance (`Corpse_0`, `Corpse_1`) at Stormwind -8349, 517; `AreaTrigger` 2173 lies 4 yards from there
  and 2175 at Ironforge -4840, -1330; inside map 369 the triggers 2166 and 2171 are 2,480 yards apart, and the tram
  cars (`TransportAnimation` 176080 to 176085) travel 2,482 yards in a loop of 143.3 seconds. Where a trigger leads is
  decided by the server. The 130 seconds are an estimate: half a loop for the ride, a quarter for the wait, 22 seconds
  on foot through the stations.
- **Zeppelins** are marked Horde and the Menethil, Auberdine and Rut'theran boats Alliance because their docks are in
  that faction's towns. The game does not stop the other faction from boarding; the guards do. These are the original
  game's transports, so the planner's narrower choice rests on public facts and the links stay verified.
- **Feathermoon ferry:** both ends are in Feralas, and walking inside a zone is a straight line, so the planner does
  not yet know that Sardor Isle needs the ferry.

Seen in the client and not used: path 253 "Southshore Ferry" (no stops), 436 at Naxxramas, 12030 (a 230 node loop on
Kalimdor with no stops), the Darkspear Islands (their own map 2997, a battleground-type map with no link to it).
Not in the data at all: the portal between Darnassus and Rut'theran Village. Both are in zones joined on foot in the
pass table (Rut'theran is part of Teldrassil's map), so the walk is a straight-line estimate there.

## 4. Off Zephras Isle (updates DATA-NOTES section 3)

P1 could not tell whether the way out is a ship or a portal. The client data settles the route:

- `Map` has two transport-type maps (MapType 3), 3217 "Dalaran Skycuter" and 3218 "Mulgore Skycuter".
- Path 11398 stops at Zephras Isle 65.8, 83.8 (60 s) and at Alterac Mountains 12.8, 51.2 (60 s). Object 716301
  "Portal To Dalaran" (65.7, 83.3) and the High Order Dockmaster stand at the isle stop; the turn-in NPC of quest
  94946, Denaaris Stargale (Alterac Mountains 12.3, 56.3), is 100 yards from the other. `Map` 2980 "Dalaran City" is a
  child of the Eastern Kingdoms map, which fits a Dalaran placed at Alterac coordinates.
- Path 11457 stops at Zephras Isle 57.7, 81.0 (30 s) and at Mulgore 34.3, 26.1 (60 s). Object 716302 "Portal to
  Thunder Bluff" (58.0, 80.4) stands at the isle stop; Alaana Stormwalker (Mulgore 33.4, 22.5), quest 95349's turn-in,
  is about 150 yards from the other.

So both links are `kind = "boat"` (the quest text says "skycutter ship"). Their paths are in the client and each exit
quest belongs to one faction's race, so the route and the faction stand (`pathVerified`). The links are still
`verified = false`, with `assumed = ["boarding", "arrival", "kind"]`: a portal object stands at each dock, the arrival
point is the path's stop and nothing more, and the two conditions below are choices, not facts:

- `oneWay = true`. Both paths are loops, so the ship does come back to the isle, but nothing shows that a character
  may ride it back. The planner keeps P1's rule: the isle is left once.
- `requires = { level: 7, quest: 94946 }` (Horde: 95349). Whether the ship can be boarded without the quest is not in
  the data. `travelPlan` checks both: the level, and that the quest is in `state.quests`. A caller that passes no
  `state.quests` has no quests and is never put on a skycutter; the plan then comes back unreachable with
  `blocked = [{ link, requires }]`, so the mistake shows at once instead of as a route that boards too early.

Also in the client: path 11350, 12,305 yards from Dalaran (world 80, 258) to Stormwind (-8848, 499) with no stops and
no taxi nodes at its ends. That looks like the flight of "Welcome to Azeroth" (94947), which ends in Stormwind. It is
not a link, because nothing in the data says how it starts. Without it a High Order character walks from Alterac to
Menethil Harbor and sails; P3 should give that quest its own handling.

## 5. Passes: walking between zones

Walking inside a zone is a straight line. Between zones it goes through passes: 51 hand-written points where one zone
is left for the next, joined into a graph. This is what keeps a route from walking over the mountains from Menethil to
Ironforge or across the sea from Teldrassil. Zones joined only to each other (Teldrassil and Darnassus) cannot be
walked to; a zone map with no pass at all would be a straight-line guess (`guess = true` on the leg, and a line in
`graph.notes`). Today every zone map of the two continents has a pass, and a test fails when one does not.

Such a guess is a straight line from anywhere on the continent, so a place in a zone without a pass can join land the
pass table keeps apart (an island to the mainland). `travelPlan` then keeps the two guessed walks as two legs, each
marked `guess`; it does not fold them into one walk that does not exist. The same rule covers the 500 yard border
rule below: walks in a row become one leg only when that walk is no longer than its parts.

- `source = "map"`: placed from the public world map, to about 300 yards. A wrong point changes a time estimate,
  never a step: passes are not written into routes, a `travel` step names only its destination.
- `source = "spawns"`: placed where the creature and object lists of both zones come closest in QuestieDB. That is the
  only evidence for the three Forever zones: Riverglades from the east end of the Burning Steppes, Mount Hyjal from
  Winterspring (Darkwhisper Gorge), Shen'dralas from south-east Desolace.
- The test checks geometry only: each pass is on (or within a tenth of a map of) both zones' maps, and each continent's
  mainland is joined.
- Two places less than 500 yards apart in neighbouring zones are walked straight, not through the pass: borders along a
  river or open country can be crossed anywhere.

Not known: other ways into Riverglades and Shen'dralas, and whether the Hinterlands can be entered from the Western
Plaguelands (only the Hillsbrad path is listed).

## 6. Estimates

All in `ESTIMATES` at the top of `tools/lib/travel.js`.

| Constant | Value | From |
| --- | --- | --- |
| RUN_SPEED | 7 yd/s | The original game's run speed. |
| MOUNT_LEVEL, MOUNT_SPEED | 40, 11.2 yd/s | First mount at 40, +60%. Assumes the character buys it. |
| WALK_DETOUR | 1.25 | A guess for roads against the straight line. |
| NEAR_BORDER | 500 yd | A guess, see section 5. |
| FLIGHT_SPEED | 32 yd/s | The figure open server projects use. Not in the client. |
| FLIGHT_PATH_RATIO | 1.36 | Measured: median path length over straight distance in the client's taxi paths. Only for a path without nodes; none today. |
| BOARD_SECONDS, LEARN_SECONDS | 10, 5 | Guesses. |
| TRANSPORT_SPEED | 30 yd/s | The server setting in open server projects. Not in the client. |
| HEARTH_SECONDS | 15 | The 10 second cast plus a loading screen. |
| PICKUP_SECONDS | 45 | A choice: the longest detour worth a new flight point. |

## 7. For P3

```js
const { loadTravel, travelPlan, toSteps } = require("./lib/travel");
const graph = loadTravel(db, dataDir);                       // once
const plan = travelPlan(db, graph, state, from, to);         // { legs, seconds }
steps.push(...toSteps(plan.legs));                           // format 2 steps
```

- `state = { faction, level, flights: Set, hearth: point | null }`, optionally `hearthReady: false` (the cooldown is
  not modelled; the caller tracks it) and `quests: Set`.
- **Pass `state.quests` for the Skyborne races**: the quests the character has accepted or done. The skycutters need
  94946 (High Order) and 95349 (Windshaper), and without the set a plan off Zephras Isle is unreachable (section 4).
  The planner must therefore accept the exit quest before it asks for the way off the isle, and the validator should
  fail a `transport` step out of zone 16593 that comes before the accept step of that quest. The leg carries
  `requires = { level, quest }` for that check.
- `seconds` is `Infinity` and `legs` empty when the place cannot be reached; `blocked` is then present when a link was
  reached and could not be boarded for its level or quest. Same place: no legs, 0 seconds.
- Legs: `walk` (inside a zone, no step), `travel`, `getflight`, `fly` (`from`, `via`, `to`, `land`), `transport`
  (`link`, `verified`, `pathVerified`, `assumed`, `requires`), `hearth`. Points in legs are full points (`wx`, `wy`,
  `continent`), so the last leg's `at`, `land` or `to` is the new position.
- A transport leg whose `assumed` contains `"factions"` is one the faction may not be able to use: the validator's
  rule "a transport the faction cannot use" should report it, and `{ verifiedOnly: true }` gives the plan without
  every unverified link (section 1).
- After a plan is used, add the `node` of every `getflight` leg to `state.flights`.
- `{ pickups: false }` gives the plain fastest way, for comparing costs. With pickups (the default) a flight point
  within 45 seconds of the way is learned, and the plan's `seconds` include the detour.
- A plan takes well under a millisecond; walking distances between flight masters and docks are cached on the graph.

## 8. For the owner, in game

| Check | Now assumed |
| --- | --- |
| Do the skycutters leave from the docks at Zephras Isle 65.8, 83.8 and 57.7, 81.0, and is it a ship or the portal object beside it? | Ship, at those docks. |
| Can a Skyborne character board before the exit quest, and ride back to the isle? | No to both. |
| Where exactly does the Alliance skycutter arrive? | Alterac Mountains 12.8, 51.2. |
| Does the Menethil boat stop at Southshore? | Not used. |
| Do the Stormwind Harbor to Auberdine boat and the Steamwheedle to Powderfuse boat sail, and for whom? | Yes; Alliance; both factions. |
| Is there a Horde flight master on Mount Hyjal? | No. |
| Does the Deeprun Tram work as in the original game? | Yes. |
| How are Riverglades, Mount Hyjal and Shen'dralas entered on foot? | From the Burning Steppes, Winterspring, Desolace. |
