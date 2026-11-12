-- Noir Guides, GPLv3. See LICENSE.
-- A hand-written format 3 route for the engine's tests: three sections chained by next (hunters go straight from
-- the first to the third), 33 steps that use every line kind and every step field at least once. The IDs and places
-- look like Tirisfal's but this is test data, not a route to play.
Noir.Route("horde-undead", {
  format = 3, race = "Undead", faction = "Horde",
  sections = {
    {
      id = "undead-01-03-deathknell", name = "1-3 Deathknell", group = "Horde", subgroup = "1-20",
      minLevel = 1, maxLevel = 4, zone = 85, start = true,
      next = {
        { section = "undead-05-06-silverpine-forest", when = { class = "HUNTER" } },
        { section = "undead-03-05-tirisfal-glades" },
      },
      steps = {
        { id = "a363", at = { zone = 85, x = 30.2, y = 71.6, r = 8 },
          text = "Undertaker Mordo waits beside the crypt you woke in.",
          lines = { { kind = "accept", quest = 363, npc = 1568 } } },
        -- Two accepts and a turn-in at one NPC.
        { id = "t363.a364.a376", title = "Sarvis", at = { zone = 85, x = 30.84, y = 66.2, r = 10 },
          text = "Shadow Priest Sarvis stands by the crypt doors, north of the graveyard.",
          lines = {
            { kind = "turnin", quest = 363, npc = 1569 },
            { kind = "accept", quest = 364, npc = 1569, requires = { 363 } },
            { kind = "accept", quest = 376, npc = 1569, requires = { 363 } },
          } },
        { id = "a3901", at = { zone = 85, x = 31.1, y = 65.1, r = 8 },
          lines = { { kind = "accept", quest = 3901, npc = 1570 } } },
        -- A reminder that stays on screen until the step labelled turnin3901.
        { id = "r3901", reminder = { ends = "turnin3901" },
          lines = { { kind = "objective", quest = 3901, index = 1, npc = 1890 } },
          targets = { enemy = { 1890 } } },
        -- Objectives of two quests in one step, walked as a loop.
        { id = "o364.o376", at = { zone = 85, x = 32.63, y = 63.5 },
          path = { points = { { x = 32.6, y = 63.5 }, { x = 35.0, y = 61.0 }, { x = 33.5, y = 58.5 } }, loop = true },
          lines = {
            { kind = "objective", quest = 364, index = 1, npc = 1501 },
            { kind = "objective", quest = 364, index = 2, npc = 1502 },
            { kind = "objective", quest = 376, index = 1, npc = 1508, cap = 10 },
          },
          targets = { enemy = { 1501, 1502, 1508 } }, items = { 2856 } },
        { id = "c2834", at = { zone = 85, x = 34.0, y = 60.0 },
          lines = { { kind = "collect", item = 2834, count = 4, quest = 376 }, { kind = "use", item = 2856 } } },
        { id = "t364.t376", at = { zone = 85, x = 30.84, y = 66.2, r = 10 },
          lines = {
            { kind = "turnin", quest = 364, npc = 1569 },
            { kind = "turnin", quest = 376, npc = 1569, skipIfIncomplete = true },
          } },
        { id = "t3901", label = "turnin3901", at = { zone = 85, x = 31.1, y = 65.1, r = 8 },
          lines = { { kind = "turnin", quest = 3901, npc = 1570, reward = 1 } } },
        -- Rogues only: their first class quest and a visit to their trainer.
        { id = "a8.train", when = { class = "ROGUE" }, at = { zone = 85, x = 32.6, y = 65.6, r = 8 },
          lines = {
            { kind = "accept", quest = 8, npc = 2122 },
            { kind = "train", class = "ROGUE", level = 2, npc = 2122 },
          } },
        { id = "l3@85", at = { zone = 85, x = 33.0, y = 62.0 }, lines = { { kind = "grind", level = 3, percent = 30 } } },
        { id = "g.road", lines = {
            { kind = "goto", at = { zone = 85, x = 38.2, y = 56.8, r = 15 } },
            { kind = "note", text = "Follow the road north-east out of the valley." },
          } },
      },
    },
    {
      id = "undead-03-05-tirisfal-glades", name = "3-5 Tirisfal Glades", group = "Horde", subgroup = "1-20",
      minLevel = 3, maxLevel = 6, zone = 85, noAuto = { 370 },
      next = { { section = "undead-05-06-silverpine-forest" } },
      steps = {
        -- Passed straight to the inn once Fields of Grief is handed in.
        { id = "a365", at = { zone = 85, x = 59.4, y = 52.4, r = 10 },
          skip = { { kind = "turnedin", quest = 365, jump = "brill_inn" } },
          lines = { { kind = "accept", quest = 365, npc = 1518 } } },
        { id = "fp384", at = { zone = 85, x = 58.9, y = 51.9, r = 10 },
          lines = { { kind = "getflight", node = 384, npc = 4551 } } },
        { id = "inn", label = "brill_inn", at = { zone = 85, x = 61.7, y = 52.0, r = 10 },
          lines = {
            { kind = "sethearth", npc = 5688 },
            { kind = "vendor", npc = 5688, buy = { item = 159, count = 5 } },
          } },
        -- Two fields; the arrow shows the nearer one.
        { id = "o365", lines = {
            { kind = "objective", quest = 365, index = 1, at = { zone = 85, x = 36.0, y = 50.0, nearest = true } },
            { kind = "objective", quest = 365, index = 2, at = { zone = 85, x = 52.0, y = 30.0, nearest = true } },
          } },
        { id = "t365", requires = "brill_inn", at = { zone = 85, x = 59.4, y = 52.4, r = 10 },
          lines = { { kind = "turnin", quest = 365, npc = 1518, skipIfMissing = true } } },
        { id = "train.mining", when = { profession = 186 }, at = { zone = 1497, x = 50.0, y = 68.0, r = 10 },
          lines = { { kind = "train", skill = 186, rank = 1, npc = 3175 } } },
        { id = "train.spell", when = { class = "MAGE" }, at = { zone = 85, x = 61.9, y = 52.5, r = 8 },
          lines = { { kind = "train", spell = 1459, npc = 2124 } } },
        { id = "l5@85", at = { zone = 85, x = 48.0, y = 40.0 }, lines = { { kind = "grind", level = 5 } } },
        -- Above the section's estimate: shown with a grind line first until level 7.
        { id = "a367", minLevel = 7, at = { zone = 85, x = 59.2, y = 52.5, r = 10 },
          lines = { { kind = "accept", quest = 367, npc = 1518 } } },
        -- Passed when the character is above level 5.
        { id = "a370", maxLevel = 5, at = { zone = 85, x = 60.0, y = 52.0, r = 10 },
          lines = { { kind = "accept", quest = 370, npc = 1500, manual = true } } },
        { id = "m.chest", lines = { { kind = "manual", text = "Open the chest by the windmill and take the letter." } } },
        { id = "fly10", load = "undead-05-06-silverpine-forest", at = { zone = 85, x = 58.9, y = 51.9, r = 10 },
          lines = { { kind = "fly", from = 384, to = 10 } } },
      },
    },
    {
      id = "undead-05-06-silverpine-forest", name = "5-6 Silverpine Forest", group = "Horde", subgroup = "1-20",
      minLevel = 5, maxLevel = 8, zone = 130, next = {},
      steps = {
        { id = "z130", lines = { { kind = "goto", at = { zone = 130, x = 0, y = 0, r = 5 } } } },
        { id = "fp10", at = { zone = 130, x = 45.6, y = 42.6, r = 10 }, lines = { { kind = "getflight", node = 10, npc = 2226 } } },
        { id = "a435", at = { zone = 130, x = 56.2, y = 9.2, r = 10 }, lines = { { kind = "accept", quest = 435, npc = 1950 } } },
        { id = "tg1950", lines = {
            { kind = "target", npc = 1950 },
            { kind = "target", npc = 1765, enemy = true },
            { kind = "note", text = "Erland walks slowly; keep the wolves off him." },
          } },
        { id = "l6@130", at = { zone = 130, x = 50.0, y = 30.0 }, lines = { { kind = "grind", level = 6 } } },
        { id = "pin", at = { zone = 130, x = 44.0, y = 40.0, r = 0 }, lines = { { kind = "note", text = "The Sepulcher is the safe camp." } } },
        { id = "t435", at = { zone = 85, x = 61.7, y = 52.0 }, lines = { { kind = "turnin", quest = 435, npc = 1951 } } },
        { id = "hs", items = { 6948 }, lines = {
            { kind = "hearth", to = { zone = 85, x = 61.7, y = 52.0, r = 20 } },
            { kind = "use", item = 6948 },
          } },
        { id = "zep", at = { zone = 85, x = 60.7, y = 58.8, r = 15 },
          lines = { { kind = "transport", mode = "zeppelin", at = { zone = 85, x = 60.7, y = 58.8 }, to = { zone = 14, x = 50.8, y = 13.6, r = 50 } } } },
        { id = "g14", at = { zone = 14, x = 50.8, y = 13.6 },
          lines = { { kind = "goto", at = { zone = 14, x = 52.0, y = 28.0, r = 10 } } } },
      },
    },
  },
})
