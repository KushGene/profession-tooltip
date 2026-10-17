# Development

Notes for working on Profession Tooltip. For what the addon does, see the [README](README.md).

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

## How learned recipes are detected

1. **Scan:** When a profession window is opened, `Scanner.lua` reads all learned recipes.
   Recipes that are not (yet) in the data are added together with their reagents.
2. **Without scan:** `IsPlayerSpell(spellID)` reports learned recipes even if the window was
   never opened.
3. **Color:** Calculated from the current profession skill and the difficulty levels in the
   data, so it stays up to date while skilling – without another scan.

## Testing in game

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

## Regenerating the data

The recipe data is extracted from the WoW: Forever game files with `Tools/build_data.py` and
shipped with the addon. After a game patch: run the script, bump the version, publish an
update. See [Tools/README.md](Tools/README.md) for details.

## Release

1. In `CHANGELOG.md`, rename `## Unreleased` to the new version (e.g. `## 1.1.0 – 2026-11-10`) and commit.
   Only this section is posted as "What's new" on CurseForge, Wago and GitHub
   (`.github/scripts/extract_changelog.py`); the release stops if the section is missing.
2. Create and push a tag – the version in the TOC is taken from the tag automatically:
   ```sh
   git tag v1.0.0
   git push origin v1.0.0
   ```
3. The GitHub Action (`.github/workflows/release.yml`) builds the zip with the BigWigs packager
   (without `Tools/`) and publishes it as a GitHub release.

Additional upload targets are set up once:

| Target | Secret in the GitHub repo (Settings → Secrets → Actions) | Entry in `ProfessionTooltip.toc` |
|---|---|---|
| Wago | `WAGO_API_TOKEN` (wago.io → Account → API Keys) | `## X-Wago-ID: <ID>` |
| CurseForge | `CF_API_KEY` (curseforge.com → Account → API Tokens) | `## X-Curse-Project-ID: <project ID>` |

Alternatively, Wago can pick up the GitHub releases directly via its GitHub integration.
