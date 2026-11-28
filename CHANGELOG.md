# Changelog

Changes for players, newest version first. On release, only the section of the released
version is posted as "What's new" on CurseForge, Wago and GitHub.

## Unreleased

## 1.4.0 – 2026-11-28

### New
- Reputation discount on vendor and trainer prices: with Honored or better at a vendor's faction, the recipe shows the price you actually pay, e.g. "10s 80c (−10% reputation: Orgrimmar)". Trainer costs show the discounted price at the trainers of your factions next to the full price
- Missing recipes window: click a recipe without a vendor (or right-click any recipe) to get its ForeverDB.net link, ready to copy with Ctrl+C – the page lists every creature it drops from, every vendor and quest
- The addon notes the prices you pay at vendors and trainers, so future versions can learn the discounts of Revered and Exalted

### Improved
- Recipes that drop from many different creatures (197 recipes) now say "various creatures (full list on ForeverDB)" instead of three creatures that changed with every data update
- Updated recipe sources from ForeverDB.net's latest WoW: Forever data: first known drop sources for 29 recipes (e.g. Savory Turtle Stew, Cleric's Elixir), new quests for Orcish War Leggings, Steaming Stag Steak and Minor Discolored Healing Potion, and Heavy Scorpid Bracers, Heavy Scorpid Helm and Great Rage Potion are no longer marked as limited supply at some vendors

### Fixed
- Corrected trainer costs for 7 Alchemy recipes that showed a reputation-discounted price, e.g. Draught of Detect Undead now 50s instead of 45s and Stonescale Oil 1g 50s instead of 1g 35s

## 1.3.0 – 2026-11-27

### New
- Added "Show crafting cost" under Extras (disabled by default, requires Auctionator): shows the material cost to craft an item in its tooltip using Auctionator scan prices, vendor prices for basic unlimited vendor reagents, and recipe yields for multi-output crafts
- New settings options are highlighted with a "NEW" badge (and a small dot on their tab) until you have visited the tab

### Improved
- Updated recipe data for WoW: Forever build 1.60.1.71139: corrected the reagents of Skywall Souffle and Pincer Bites

### Fixed
- SAF-T Tabs and SAF-T Copper Bomb showed Linen Cloak instead of Linen Cloth as their cloth reagent

## 1.2.4 – 2026-11-25

### Improved
- Updated recipe sources in the Missing recipes window from ForeverDB.net's latest WoW: Forever data: more trainers and drop sources for about 200 recipes, Smudge Thunderwood in Alterac Mountains as a new vendor for Recipe: Thistle Tea, and Kurll's quest in Azshara as a second source for Recipe: Potion of Beast Slaying

### Fixed
- Corrected trainer costs for 17 recipes, e.g. Green Iron Leggings now 50s instead of 55s 56c and Green Iron Bracers 10s instead of 11s 11c
- Three vendors were shown in the wrong zone: Malygen and Meilosh are in Felwood, Zannok Hidepiercer is in Silithus

## 1.2.3 – 2026-11-24

### Improved
- Updated recipe sources in the Missing recipes window from ForeverDB.net's latest WoW: Forever data: trainers, vendors, drops and quests for about 770 recipes, trainer costs confirmed in Forever for 55 recipes (e.g. Green Iron Leggings 55s 56c instead of 9s) and nine newly seen vendors. Centaur Hoofwarmers now shows its two vendors in Desolace

### Fixed
- Centaur Hoofwarmers had a German fallback name; it now uses the English name like all other recipes

## 1.2.2 – 2026-11-22

### Improved
- Updated recipe data for WoW: Forever build 1.60.1.71037, adding one new Leatherworking recipe

## 1.2.1 – 2026-11-18

### Improved
- Corrected required skill levels for two recipes based on WoW: Forever build 1.60.1.70959: Orcish War Leggings now requires 205 and Icy Scale Bracers 320; both were shown without a required skill before

## 1.2.0 – 2026-11-17

### New
- **Missing recipes:** a new window lists the recipes of a profession you have not learned yet, sorted by required skill, and shows where to get each one: trainer and cost, vendors with zone, coordinates and price, required reputation or Merchant's Favor, quests and drop sources. Each recipe shows its icon, and hovering it shows the item's own tooltip next to the details (the recipe item, otherwise the crafted item; enchants show the spell). Filter by source or show only recipes your skill already allows. Click a recipe to open the world map on its vendor and set a map pin (and a TomTom waypoint if TomTom is installed). Only vendors of your own faction are listed. Open it with `/pt recipes`, a right-click on the minimap button or the button in the settings window. You can browse professions you have not learned, too
- Added "Show sources in item tooltips" (in the Missing recipes window, disabled by default): unknown recipes in item tooltips are tagged with their source, e.g. [Vendor], and crafted items list where to get their recipe if "Info on crafted items" is enabled
- Added "Show Darkmoon Faire turn-ins" under Extras, enabled by default: items that Darkmoon Faire quests take, such as Small Furry Paw, Torn Bear Pelt or Copper Modulator, show the amount, the reward and the required level, e.g. "5× for 4 tickets (level 10+)". The level is shown in red while your character is too low. The amounts are Classic data until players confirm them in Forever
- Added "Show surnames" under Extras, enabled by default: the character list and "Known by"/"Learnable by" show the WoW: Forever surname after the first name. Each character needs to log in once
- Vendors, drop sources and quests are shown in your client's language (all nine supported languages)

### Improved
- The minimap button now uses bundled LibDBIcon and LibDataBroker libraries for better compatibility with minimap button collectors, without requiring another addon. Existing position and visibility settings are preserved
- The character list under Extras shows four characters per page to make room for the new options
- Corrected required skill levels for 17 Leatherworking recipes based on WoW: Forever build 1.60.1.70938, e.g. Green Leather Belt now requires 135 instead of 155, and Thick Armor Kit 175 instead of 195

### Fixed
- Two of your characters with the same first name on one realm no longer overwrite each other in the character list and in "Known by". Each character is listed under its full name after its next login

## 1.1.5 – 2026-11-14

### New
- Added "Show requirements for unlearned professions" under Professions, disabled by default. The game's red profession requirements (e.g. disenchanting, Herbalism, Mining and Skinning) are now hidden if you have not learned the profession; requirements for your own professions remain visible. Custom requirement lines added by other addons are not covered

### Improved
- Corrected required skill levels for 21 Leatherworking recipes based on WoW: Forever build 1.60.1.70938

### Fixed
- Profession headers now use a font-safe bullet between the profession skill and known recipe count, avoiding a missing-glyph square on Russian clients

## 1.1.4 – 2026-11-13

### Fixed
- The required skill on red Skinnable labels now actually appears; the addon looked for a text the game does not provide
- Bruiseweed, Wild Steelbloom and Kingsblood no longer show each other's required Herbalism skill
- Herb and ore nodes that exist under several object IDs (e.g. Copper Vein, Sungrass, Dreamfoil) are all recognized
- Recipes of a profession you unlearned no longer count as known, neither for you nor under "Known by" on your other characters
- "Learnable by" no longer lists characters for recipes whose required skill is unknown
- Recipes missing from the database are updated when their names, reagents or quantities change, not only when the number of reagents changes
- Class trainers are no longer scanned, avoiding unnecessary spell-list rebuilds that could briefly freeze the game; profession trainer filters are only changed when needed

### Improved
- Gathering requirements on herb and ore nodes now work in every supported client language (English, German, French, Spanish, Russian, Portuguese, Korean, Simplified and Traditional Chinese), not only English and German
- Tooltips are no longer rebuilt for every item the game loads (e.g. while browsing the Auction House), only for items whose names the addon is waiting for
- Profession Tooltip appears in the addon compartment and, if a LibDataBroker display is installed, as a launcher there
- Recipe data generation is faster, handles missing offline caches and interrupted downloads more clearly, and no longer rewrites data files just because the client build changed
- Gathering node names and requirements can now be regenerated and checked against Wowhead's Forever data
- Offline regression tests now run on pushes, pull requests and before publishing a release

## 1.1.3 – 2026-11-12

### Improved
- Updated recipe data for WoW: Forever build 1.60.1.70888: corrected difficulty colors across all professions, reagent quantities for five Tailoring bags, and required skill levels for Draught of Water Walking (180) and Tanning Rack (125)

## 1.1.2 – 2026-11-11

### Improved
- Updated recipe data for WoW: Forever build 1.60.1.70888: corrected required skill levels for 10 Leatherworking recipes and added the required skill of 285 for Mooncloth Boots

### Fixed
- Onyxia Scale Breastplate no longer shows an incorrect required skill of 320

## 1.1.1 – 2026-11-08

### New
- Red Herbalism, Mining and Skinnable labels now show the required gathering skill directly on mouseover, without clicking. Includes Classic herb and ore nodes; unknown nodes and unknown creature levels remain unchanged

## 1.1.0 – 2026-11-08

### New
- Required skill labels, e.g. (100), now use orange, yellow, green or gray difficulty colors based on your current profession skill, even for unlearned recipes. Enabled by default and independently toggleable under Design → Recipe colors; insufficient skill remains red
- Optional difficulty colors for the names of unlearned recipes. Recipes remain marked as not learned, and their skill labels can be colored independently. Enable this under Design → Recipe colors; disabled by default
- Recipes without difficulty data or a current profession skill keep their neutral gray color

### Improved
- New recipe color settings are translated into all supported languages

## 1.0.4 – 2026-11-07

### Improved
- Corrected required skill levels for 151 recipes based on the WoW: Forever trainers, mostly Tailoring, Leatherworking and Blacksmithing (e.g. sharpening stones, Linen Bag, Bolt of Runecloth). Lodestone, Smelt Azerothium, First Aid Kit and other recipes without a known skill level now show one

### Fixed
- Scanning a profession no longer removes learned recipes whose profession is unknown
- Trainer scans no longer assign skill requirements to an arbitrary recipe when multiple recipes share a name
- The character list in the Extras tab now has page buttons so every saved character can be removed

## 1.0.3 – 2026-11-05

### Improved
- Recipe data updated for the WoW: Forever launch build (1.60.1.70790): 9 new recipes such as Enchant Boots - Speed and the Tinker schematics, 10 new recipe items and corrected skill levels for 39 recipes

### Fixed
- Visiting a profession trainer can no longer leave the trainer window's filters changed
- Learned recipes are detected with the current spell API instead of a deprecated one
- Recipe items now respect the required skill reported by the trainer
- Reagent names in tooltips appear as soon as the item data is loaded
- Scanning no longer rebuilds all tooltips after every craft

## 1.0.2 – 2026-10-18

### Fixed
- 130 more recipe items (plans, patterns, schematics, recipes) are recognized, e.g. Ironforge Chain, the Stormcloth patterns, the Gnomish and Goblin schematics and many new Forever recipes such as Veteran's Chain Shirt or Prowler Steak
- Recipe items that are still missing from the data are now matched to their recipe by name

## 1.0.1 – 2026-10-17

### New
- Talking to a profession trainer now records the required skill of the recipes they teach. Recipes without a known skill level fill in automatically.

## 1.0.0 – 2026-10-17

First release – successor of Cooking Tooltip and Alchemy Tooltip for all professions in WoW: Forever.

### New
- Shows for every ingredient which recipes of your professions use it, whether you know them (difficulty color) and the skill they require
- All professions: Alchemy, Blacksmithing, Enchanting, Engineering, Leatherworking, Tailoring, Mining, Cooking, First Aid and the camp recipes of Herbalism, Skinning and Fishing (2,200+ recipes, extracted from the game files)
- Other professions appear as icons, so you see at a glance that an item is worth selling
- Learned recipes are detected automatically; colors update live while skilling
- Optional extras (off by default): alts that know a recipe, info on recipe items, crafted items with reagents, "enough for N" from bags and bank, auction value via Auctionator, filter for unknown recipes
- Settings window with live preview: tooltip, design, professions, extras
- Takes over settings from Cooking Tooltip / Alchemy Tooltip and offers to disable them
- Available in English, German, French, Spanish, Russian, Portuguese, Korean and Chinese
