# Profession Tooltip (WoW: Forever)

Shows in the item tooltip which recipes of your professions use an ingredient, whether you know
them (difficulty color) and the skill they require. Successor of Cooking Tooltip and Alchemy
Tooltip, covering all professions of WoW: Forever (interface 16001).

Commands: `/pt` or `/proftip` open the settings.

Download: [CurseForge](https://www.curseforge.com/wow/addons/profession-tooltip)

## Structure

| File | Purpose |
|---|---|
| `Core.lua` | Namespace, event bus (`ns.RegisterEvent`), internal messages (`ns.On`/`ns.Fire`), SavedVariables, spell name cache |
| `Locales/*.lua` | Texts; `enUS` is the base, other languages only override what they translate |
| `Professions.lua` | List of professions (skill line ID, icon, order), detection via `GetProfessions()` |
| `Database.lua` | Recipe registry, indexes ingredient → recipes and item → recipes (built once, on demand) |
| `Data/<Profession>.lua` | **Generated** recipe data, one file per profession |
| `Data/RecipeItems.lua` | **Generated**: recipe item → taught spell |
| `Characters.lua` | Account-wide snapshot per character (for "Known by" / "Learnable by") |
| `Scanner.lua` | Reads learned recipes and their difficulty from the open profession window |
| `Tooltip.lua` | Builds the tooltip sections (recipe item, crafted with, ingredient); lines are cached per item and Shift state |
| `Legacy.lua` | Transition from Cooking Tooltip / Alchemy Tooltip (take over settings, disable old addons) |
| `UI/Widgets.lua` | Reusable UI building blocks (`Column:Header/Check/Choice`) |
| `UI/ConfigWindow.lua` | Settings window with tabs and live preview |
| `UI/MinimapButton.lua`, `UI/SettingsPanel.lua` | Minimap button, entry under Options → AddOns |
| `Tools/` | Data generator for `Data/*.lua` (not loaded by WoW, not part of the release) |

Data flow: data files register recipes → `Database` builds the ingredient index → `Scanner`
remembers per character which spells are learned → `Tooltip` combines both.
Changes to settings or scan data fire `SETTINGS_CHANGED` or `DATA_CHANGED`; the tooltip cache
and the settings window listen to them.

Recipe format in `Data/*.lua`:

```lua
[spellID] = { requiredSkill (0 = unknown), "Fallback name", { itemID, count, ... },
               createdItem (0 = none), yellowAt, greenAt, grayAt },
```

The tooltip shows the localized spell name from the client; the fallback name is only used if
the client does not know the spell.

## Settings

By default only the core feature is enabled (recipe list of your own professions, skill level,
quantity, icons of other professions). Everything else can be enabled in the window (`/pt`):

| Tab | Content |
|---|---|
| Tooltip | Recipe list, known/unknown sections, max. recipes, filter for unknown recipes, Shift behavior |
| Design | Profession line (icon/name), own skill, known count, spacing, hints |
| Professions | Only own professions, icons of other professions, toggle single professions |
| Extras | Alts, recipe items, crafted items, stock, auction value (Auctionator), character list |
| General | Minimap button, scan data, transition from Cooking Tooltip / Alchemy Tooltip |

## Detecting learned recipes

1. **Scan:** When a profession window is opened, `Scanner.lua` reads all learned recipes.
   Recipes that are not (yet) in the data are added together with their reagents.
2. **Without scan:** `IsPlayerSpell(spellID)` reports learned recipes even if the window was
   never opened.
3. **Color:** Calculated from the current profession skill and the difficulty levels in the
   data, so it stays up to date while skilling – without another scan.

## Regenerating the data

The recipe data is extracted from the WoW: Forever game files with `Tools/build_data.py` and
shipped with the addon. After a game patch: run the script, bump the version, publish an
update. See [Tools/README.md](Tools/README.md) for details.

## Development

To test in game, link the repository into the AddOns folder of the Forever client:

```sh
ln -s /path/to/ProfessionTooltip \
      "/path/to/World of Warcraft/_classic_beta_/Interface/AddOns/ProfessionTooltip"
```

When the addon runs directly from the repository, the settings window shows the version "dev".
Inside the repository the data generator needs to know the WoW folder:

```sh
WOW_DIR="/path/to/World of Warcraft" python3 Tools/build_data.py
```

## License

[GPL-3.0](LICENSE)
