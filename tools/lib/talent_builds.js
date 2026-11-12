// Noir Guides, GPLv3. See LICENSE.
// One leveling build per class, written for this project against the Forever client's own talent trees (the
// Talent table of the build in data_sources.json; Forever renamed and moved many talents, so classic builds do not
// fit). Each pick is [talent ID, points], taken in this order from level 10; the name after each is for the reader
// and is checked against the data by tools/test/ports.test.js. tools/gen_ports.js refuses a build that cannot be
// learned point by point (lib/talents.js checkBuild) and writes the rest to NoirGuides/Data/Talents.lua.
//
// The choices favour killing alone while questing: damage and mana or rage first, the tree's top talent at 40.
const BUILDS = {
  WARRIOR: {
    spec: "Arms",
    picks: [
      [124, 3, "Improved Heroic Strike"], [127, 3, "Improved Rend"], [126, 2, "Improved Charge"],
      [641, 5, "Improved Tactical Mastery"], [137, 1, "Anger Management"], [121, 3, "Deep Wounds"],
      [136, 5, "Two-Handed Weapon Specialization"], [662, 2, "Impale"], [133, 1, "Sweeping Strikes"],
      [132, 5, "Weaponmaster"], [135, 1, "Mortal Strike"],
      [157, 5, "Cruelty"], [159, 5, "Unbridled Wrath"], [154, 5, "Improved Battle Shout"], [661, 3, "Blood Craze"],
      [1542, 2, "Improved Execute"],
    ],
  },
  PALADIN: {
    spec: "Retribution",
    picks: [
      [1407, 5, "Benediction"], [1631, 2, "Improved Judgement"], [1464, 3, "Improved Seal of the Crusader"],
      [1411, 5, "Conviction"], [1481, 1, "Seal of Command"], [1634, 2, "Pursuit of Justice"], [1632, 2, "Eye for an Eye"],
      [1410, 3, "Two-Handed Weapon Specialization"], [1409, 1, "Sanctity Aura"], [1405, 1, "Improved Retribution Aura"],
      [1402, 5, "Vengeance"], [1441, 1, "Repentance"],
      [1450, 5, "Divine Strength"], [1463, 5, "Improved Seals"], [1435, 1, "Consecration"],
      [1422, 5, "Improved Devotion Aura"], [1630, 3, "Precision"], [1425, 1, "Guardian's Favor"],
    ],
  },
  HUNTER: {
    spec: "Beast Mastery",
    picks: [
      [1382, 5, "Deadly Aspects"], [1395, 3, "Thick Hide"], [1381, 2, "Improved Aspect of the Monkey"],
      [1396, 5, "Unleashed Fury"], [1391, 1, "Bestial Swiftness"], [1393, 5, "Ferocity"], [1387, 1, "Intimidation"],
      [1390, 2, "Bestial Discipline"], [1388, 1, "Spirit Bond"], [1397, 5, "Frenzy"], [1386, 1, "Bestial Wrath"],
      [1342, 5, "Efficiency"], [1344, 5, "Lethal Attacks"], [1345, 1, "Aimed Shot"], [1352, 3, "Hawk Eye"],
      [1346, 1, "Improved Arcane Shot"], [1349, 5, "Mortal Shots"],
    ],
  },
  ROGUE: {
    spec: "Combat",
    picks: [
      [201, 2, "Efficient Strikes"], [186, 3, "Lightning Reflexes"], [181, 5, "Precision"], [204, 2, "Endurance"],
      [187, 3, "Deflection"], [221, 5, "Dual Wield Specialization"], [223, 1, "Blade Flurry"], [182, 5, "Hack and Slash"],
      [1122, 3, "Aggression"], [1703, 2, "Weapon Expertise"], [205, 1, "Adrenaline Rush"],
      [270, 5, "Malice"], [273, 3, "Ruthlessness"], [274, 2, "Murder"], [281, 1, "Relentless Strikes"],
      [269, 5, "Lethality"], [277, 3, "Improved Slice and Dice"],
    ],
  },
  PRIEST: {
    spec: "Shadow",
    picks: [
      [465, 5, "Spirit Tap"], [482, 2, "Improved Shadow Word: Pain"], [463, 3, "Shadow Focus"],
      [481, 5, "Improved Mind Blast"], [501, 1, "Mind Flay"], [881, 1, "Shadow Reach"], [461, 5, "Shadow Weaving"],
      [484, 1, "Vampiric Embrace"], [1638, 2, "Improved Vampiric Embrace"], [462, 5, "Darkness"], [521, 1, "Shadowform"],
      [345, 5, "Wand Specialization"], [343, 3, "Improved Power Word: Shield"], [344, 2, "Improved Power Word: Fortitude"],
      [348, 1, "Inner Focus"], [347, 3, "Meditation"], [352, 1, "Silent Resolve"], [341, 5, "Mental Agility"],
    ],
  },
  SHAMAN: {
    spec: "Enhancement",
    picks: [
      [614, 5, "Ancestral Knowledge"], [613, 5, "Thundering Strikes"], [607, 3, "Improved Lightning Shield"],
      [610, 2, "Enhancing Totems"], [602, 5, "Flurry"], [611, 3, "Elemental Weapons"], [616, 1, "Spirit Weapons"],
      [617, 1, "Two-Handed Axes and Maces"], [1643, 5, "Weapon Mastery"], [901, 1, "Stormstrike"],
      [564, 5, "Convection"], [563, 5, "Concussion"], [561, 3, "Call of Flame"], [574, 1, "Elemental Focus"],
      [575, 5, "Reverberation"], [572, 1, "Earth's Grasp"],
    ],
  },
  MAGE: {
    spec: "Frost",
    picks: [
      [37, 5, "Improved Frostbolt"], [73, 5, "Ice Shards"], [61, 3, "Piercing Ice"], [69, 1, "Cold Snap"],
      [63, 3, "Improved Blizzard"], [66, 3, "Frost Channeling"], [72, 1, "Ice Block"], [64, 3, "Improved Cone of Cold"],
      [62, 2, "Improved Frost Nova"], [67, 5, "Shatter"], [71, 1, "Ice Barrier"],
      [74, 2, "Arcane Subtlety"], [76, 3, "Arcane Focus"], [75, 5, "Arcane Concentration"], [82, 2, "Arcane Geometry"],
      [81, 3, "Arcane Impact"], [1142, 3, "Arcane Meditation"], [88, 1, "Improved Counterspell"],
    ],
  },
  WARLOCK: {
    spec: "Affliction",
    picks: [
      [1003, 5, "Improved Corruption"], [1007, 2, "Improved Life Tap"], [1004, 3, "Soul Siphon"],
      [1284, 3, "Improved Bane of Agony"], [1061, 1, "Amplify Curse"], [1001, 1, "Fel Concentration"],
      [1002, 2, "Nightfall"], [1021, 2, "Grim Reach"], [1121, 1, null], [1041, 1, "Siphon Life"],
      [1005, 4, "Suppression"], [1042, 5, "Shadow Mastery"], [1022, 1, null],
      [1223, 5, "Demonic Embrace"], [1242, 5, "Fel Vitality"], [1226, 1, "Fel Domination"], [1241, 4, null],
      [1262, 5, "Unholy Power"],
    ],
  },
  DRUID: {
    spec: "Feral Combat",
    picks: [
      [796, 5, "Ferocity"], [797, 2, "Brutal Impact"], [794, 3, "Thick Hide"], [807, 2, "Feral Swiftness"],
      [798, 3, "Sharpened Claws"], [804, 1, "Feral Charge (Bear)"], [802, 2, "Shredding Attacks"],
      [803, 3, "Predatory Strikes"], [801, 2, "Blood Frenzy"], [805, 2, "Savage Fury"], [808, 5, "Heart of the Wild"],
      [809, 1, "Leader of the Pack"],
      [761, 1, "Nature's Grasp"], [921, 4, "Overgrowth"], [791, 5, "Natural Weapons"], [788, 1, "Omen of Clarity"],
      [822, 5, "Furor"], [824, 4, "Naturalist"],
    ],
  },
};

module.exports = { BUILDS };
