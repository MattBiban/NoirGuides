-- Noir Guides, GPLv3. See LICENSE.
-- A second, tiny format 3 route so the tests can check that each race gets its own: one section of four steps.
Noir.Route("alliance-human", {
  format = 3, race = "Human", faction = "Alliance",
  sections = {
    {
      id = "human-01-05-northshire", name = "1-5 Northshire", group = "Alliance", subgroup = "1-20",
      minLevel = 1, maxLevel = 6, zone = 12, start = true, next = {},
      steps = {
        { id = "a783", at = { zone = 12, x = 48.2, y = 43.6, r = 8 }, lines = { { kind = "accept", quest = 783, npc = 823 } } },
        { id = "t783.a7", at = { zone = 12, x = 48.9, y = 41.6, r = 8 },
          lines = { { kind = "turnin", quest = 783, npc = 197 }, { kind = "accept", quest = 7, npc = 197 } } },
        { id = "o7", at = { zone = 12, x = 48.0, y = 36.0 }, lines = { { kind = "objective", quest = 7, index = 1, npc = 6 } },
          targets = { enemy = { 6 } } },
        { id = "t7", at = { zone = 12, x = 48.9, y = 41.6, r = 8 }, lines = { { kind = "turnin", quest = 7, npc = 197 } } },
      },
    },
  },
})
