# Profession Tooltip

**All your professions. One tooltip.** – for WoW: Forever

Profession Tooltip shows in every item tooltip which recipes of your professions use that item,
whether you already know them and which skill they require. It is the successor of
**Cooking Tooltip** and **Alchemy Tooltip** and covers all professions in one addon.

Is that stack of *Light Leather*, *Copper Bar* or *Peacebloom* worth keeping, or should it go to
the Auction House? Hover over it and you know.

**Download:** [CurseForge](https://www.curseforge.com/wow/addons/profession-tooltip) ·
[Wago](https://addons.wago.io/addons/profession-tooltip-recipes-reagents-for-all-professions) · [GitHub Releases](https://github.com/KushGene/profession-tooltip/releases)

## Features

- **All professions:** Alchemy, Blacksmithing, Enchanting, Engineering, Leatherworking, Tailoring,
  Mining (smelting), Cooking, First Aid and the camp recipes of Herbalism, Skinning and Fishing –
  more than 2,200 recipes.
- **Your professions first:** recipes of your own professions are listed in detail; other
  professions appear as small icons, so you still see that an item is worth selling.
- **Known or not:** learned recipes in their difficulty color (orange, yellow, green, gray),
  updating live while you skill up. Unknown recipes in gray with the required skill – red if your
  skill is still too low.
- **Quantity:** how many of the item a recipe needs, e.g. ×4.
- **Gathering requirements:** red Herbalism, Mining and Skinnable labels show the required
  skill on mouseover, without clicking. Covers Classic nodes in every supported
  language and creatures with a known level; unknown requirements are left unchanged.
- **No setup needed:** learned recipes are detected automatically. Opening each profession window
  once gives the most accurate result; talking to a trainer fills in missing skill levels.
- **Missing recipes and where to get them:** a window lists every recipe of a profession you
  have not learned yet – with the required skill and its source: trainer and cost, vendors with
  zone, coordinates and price, reputation, quests or drops. Filter by source or by what you can
  learn right now.
- **Clean and fast:** long lists are shortened – hold **Shift** to see everything.

### Optional extras

All off by default and can be enabled in the settings:

- **Alts:** which of your characters already know a recipe or could learn it
- **Recipe items:** "Recipe: …" items show whether you know them, can learn them or need more skill
- **Crafted items:** which recipe makes an item and which reagents it needs
- **Stock:** "enough for 3" – how often you can craft with what is in your bags and bank
- **Auction value** of the crafted item via Auctionator
- **Filters** for unknown recipes: all, learnable now, or without gray ones
- **Sources in tooltips:** unknown recipes are tagged with where to get them, e.g. [Vendor];
  crafted items list the details

## Usage

Open the settings with `/pt` (or `/proftip`), the minimap button or *Options → AddOns*.
A live preview shows every change instantly.

| Tab | What you can change |
|---|---|
| Tooltip | Recipe list, skill level, known/unknown sections, max. recipes per profession, filters, Shift behavior |
| Design | Profession as icon and/or name, your skill (e.g. 70/150), known count (e.g. 16/82 known), spacing, hints |
| Professions | Only your professions, icons of other professions, single professions on/off |
| Extras | Alts, recipe items, crafted items, stock, auction value, Darkmoon Faire turn-ins, character list with surnames |
| General | Minimap button, scan data, import from Cooking Tooltip / Alchemy Tooltip |

**Missing recipes:** `/pt recipes`, a right-click on the minimap button or the button at the top
of the settings window opens the list of recipes you have not learned yet. Pick a profession,
filter by source (trainer, vendor, drop, quest) and hover over a recipe for the details. Click a
recipe to open the world map on its vendor and set a map pin (plus a TomTom waypoint if you use
TomTom). Vendors of the other faction are never listed.
Open each profession window once so the addon knows exactly which recipes you have.

**Coming from Cooking Tooltip or Alchemy Tooltip?** Profession Tooltip detects them and offers
to take over your settings and disable them, so nothing shows up twice.

## Languages

English, German, French, Spanish, Russian, Portuguese, Korean, Simplified and Traditional Chinese.

## Feedback

Found a bug or have an idea? Please open an [issue](https://github.com/KushGene/profession-tooltip/issues).

Working on the addon itself? See [DEVELOPMENT.md](DEVELOPMENT.md).

## Credits and data sources

- Recipes, reagents and skill levels are read from the WoW: Forever game client.
- Where recipes come from (trainers, vendors, drops, quests) and the required skill of trainer
  recipes: **Data from ForeverDB.net (https://foreverdb.net)**, used under GPL-3.0 with
  ForeverDB's attribution term.
- Parts of that data are Classic data from [CMaNGOS classic-db](https://github.com/cmangos/classic-db)
  (GPL-3.0) until players confirm them in Forever.
- Darkmoon Faire turn-ins (amounts, rewards, levels): [CMaNGOS classic-db](https://github.com/cmangos/classic-db)
  (GPL-3.0), quest table.
- Gathering node names and the localized names of vendors, drop sources and quests: Wowhead's
  WoW: Forever tooltips.

World of Warcraft and WoW: Forever are trademarks of Blizzard Entertainment, Inc. This addon is
not affiliated with or endorsed by Blizzard Entertainment or ForeverDB.net.

## License

[GPL-3.0](LICENSE)
