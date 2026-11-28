# Tools – generating the recipe data

Generates `Data/*.lua` (recipes, reagents, quantities, difficulty levels, required skill) from
the installed WoW: Forever client. Not loaded by WoW and excluded from releases via `.pkgmeta`.

## After a Forever patch

1. Let the Battle.net launcher update the client.
2. Run from the addon folder:
   ```sh
   python3 Tools/build_data.py
   ```
   Inside the repository, tell the script where WoW is installed:
   ```sh
   WOW_DIR="/path/to/World of Warcraft" python3 Tools/build_data.py
   ```
   Files are only rewritten if their data changed; a new client build alone leaves them (and the
   build named in their header) untouched.
   To only check what would change (no files written), add `--dry-run`. The report at the end
   lists new, removed and changed recipes per profession and tells you whether an update is worth it.
3. Check the output (recipes per profession, see below), `/reload` in game and test briefly.
4. Commit the changed data, update `CHANGELOG.md` and publish a release (see the main README).

Requires only Python 3, no extra packages. Every run fetches the web data again, so a run takes
about a minute.

## Recipe sources

`Data/RecipeSources.lua` (where a recipe is learned: trainer and cost, vendors and their places,
drops, quests, reputation) is generated separately, after `build_data.py`:

```sh
python3 Tools/build_sources.py            # add --dry-run to only see what would change
```

The game client doesn't know where recipes come from, so the source is ForeverDB.net's addon
data (`Data/Recipes.lua` and `Data/NPCs.lua` from https://foreverdb.net/downloads/addon-manifest.json).
ForeverDB publishes these files for reuse under GPL-3.0 with an attribution term – keep the
"Data: ForeverDB.net" line in the generated file and the credit in the README and in the game.
Parts are Classic data (CMaNGOS classic-db) until players confirm them in Forever.

ForeverDB's data is crowd-sourced and changes almost daily. To keep only changes players would
notice, the script stores what is stable:
- **Drops:** ForeverDB names 3 of the creatures players have seen a recipe drop from. If it knows
  more than 3 (and none has a Classic drop chance), the 3 named ones are an arbitrary pick that
  changes with every report, so the recipe gets field `W` ("various creatures") instead. In the
  "Missing recipes" window a click shows the link to the item's ForeverDB page with all of them.
  The other drop lists are sorted (highest chance first, then by ID).
- **Trainers:** only whether a side has trainers (1/0), not how many players have found.
- **Vendors:** sorted by NPC ID; a vendor keeps its position unless it moved more than 1.0
  (positions are averaged sightings and move by tenths every day).
- **Trainer costs** come from what players saw, sometimes with a reputation discount that ForeverDB
  converts back. The report lists costs that changed by exactly a discount factor or look like a
  converted discount (e.g. 28s 80c = 90 % of 32s); check those at a trainer before releasing.

**Reputation discount.** In Forever, vendors and trainers take 10 % off from Honored with their
faction on; Friendly gives nothing (checked against prices players paid at vendors and trainers,
which ForeverDB's own addon records unchanged). Vendors round the price up to whole copper,
trainers down. The script stores each vendor's faction (7th field of its NPC string) and, per
profession, the factions of its trainers (`ns.RegisterTrainerFactions`). Both come from Wowhead's
English NPC tooltip (the row after the level names the faction) and Wowhead's search (name -> ID).
ForeverDB doesn't say which trainer teaches which recipe, so the addon shows the full trainer cost
and the discounted one "at trainers of <faction>".

The discount of each standing is learned from what players paid: whenever a vendor or trainer
window opens, the addon compares the prices with the base prices of the data and stores
`reaction:paid/base` per vendor item and trainer recipe in `ns.db.discountSeen` (SavedVariables,
account-wide; prices below 1s are skipped, the rounding hides the discount there). The script
reads these from every account's `ProfessionTooltip.lua` in the WoW folder (set `WOW_DIR`) and
from files other players send in:

```sh
WOW_DIR=… python3 Tools/build_sources.py --discounts path/to/their/ProfessionTooltip.lua
```

A standing takes the value at least 75 % of at least 5 observations agree on, and a higher
standing never pays more than a lower one; otherwise the previous value stays (default: Friendly
100 %, Honored 90 %, Revered and Exalted assumed 90 %). The result is `ns.RegisterDiscounts` in
`Data/RecipeSources.lua`, shown in the report under "Ruf-Rabatt".

Vendors, drop sources and quests are stored by ID and shown in the client's language. ForeverDB
names drops and quests in English only, so the script matches them to IDs (ForeverDB's quest
data, else Wowhead's search), keeps a match only if Wowhead's English name for the ID is the same,
and fetches the names of all nine languages from Wowhead's WoW: Forever tooltips into
`Data/Names/<locale>.lua`. What can't be matched stays English ("Ohne ID" in the report). The first
run takes several minutes; afterwards the names come from `Tools/.cache` (delete `wh_name_*`
there to fetch them again). Vendors without a known faction that stand in a capital get that
capital's faction, so the addon never lists the other faction's vendors.

The files are Lua source; the script parses them and never executes them. Only recipes that are
in `Data/*.lua` get an entry, and the recipe item is taken from `Data/RecipeItems.lua` where the
client knows it. Nothing is written if a download fails, a checksum doesn't match the manifest or
ForeverDB knows fewer than 90 % of the addon's recipes (the format probably changed). The report
lists per profession how many recipes have a trainer, vendor, drop or quest source, and for how
many only the recipe item ("nur Item") or nothing ("unbekannt") is known.

## Gathering nodes

`Data/Gathering.lua` (herb and ore nodes, their required skill, object IDs and names in every
client language) is generated separately:

```sh
python3 Tools/build_gathering.py
```

The node list (profession, skill, object IDs) lives in the script. Names come from Wowhead's
WoW: Forever tooltips; every object ID is checked there against the expected node and skill,
and nothing is written if anything disagrees. Only needed when nodes are added or changed.

## Options

| Option | Effect |
|---|---|
| `--offline` | No internet; uses only the client and the existing cache |
| `--dry-run` | Only report what would change, don't write any files |
| `--wow-dir PATH` | WoW installation folder (alternatively the environment variable `WOW_DIR`) |

Only the WoW: Forever client is ever read: product `wowf` in `.build.info` and its installation
folder `_forever_` (found via `_*_/.flavor.info`). Game tables, hotfix cache and trainer scans all
come from that client; the script stops if it can't find it, so a second installed client
(e.g. `_retail_`) never contributes data. If Blizzard renames the product, change `PRODUCT`
(and `FLAVOR_DIR`) in `build_data.py`.

## Files

| File | Purpose |
|---|---|
| `build_data.py` | Main script: reads the tables and writes `Data/*.lua` and `Data/RecipeItems.lua` |
| `build_sources.py` | Writes `Data/RecipeSources.lua` from ForeverDB.net's addon data |
| `build_gathering.py` | Writes `Data/Gathering.lua` |
| `casc.py` | Reads files from the local game storage (`World of Warcraft/Data`), including decryption |
| `db2.py` | Reads the game tables (DB2/WDC5) |
| `.cache/` | Last downloaded web data, only used when a website is unreachable (or with `--offline`); can be deleted at any time and is recreated |

## Where does the data come from?

| Value | Source |
|---|---|
| Recipes, reagents, quantities, difficulty levels, names, crafted item | Game client |
| Recipe item → taught recipe | Game client (`ItemEffect`), also for items whose other data the client doesn't have yet |
| Required skill | Recipe item in the game client (`ItemSparse`), if the client has its data |
| Hotfixes | Hotfix cache of the client (`_forever_/Cache/ADB/<locale>/DBCache.bin`), applied on top of the tables |
| Required skill of trainer recipes | Not in the client. 1) Trainer scans: the addon records the skill whenever you talk to a profession trainer (stored in your SavedVariables, read automatically from the WoW folder). 2) foreverdb.net. If no source supplies a positive rank, the existing known rank is kept; otherwise `0` = unknown, nothing is estimated |
| Available in Forever? | Classic recipes (spell ID < 30000), Forever recipes (≥ 1229000) and everything listed in the recipe lists on foreverdb.net. This filters out Season of Discovery recipes that exist in the client but cannot be learned in Forever |

Also downloaded on every run: the table definitions
(github.com/wowdev/WoWDBDefs) and the public key list for encrypted game data
(github.com/wowdev/TACTKeys).

On non-English clients the tables have no enUS variant; the script then reads the installed
language instead. Recipe names are supposed to be English (the addon shows the client's
localized names anyway), so it keeps the existing English names from `Data/*.lua` for known
recipes – only new recipes get a localized name (reported under "Sprache" in the output).
Replace those by hand with the English name (e.g. from foreverdb.net/spell/<spellID>); later
runs keep it.

## Hotfix cache and data that is still missing

The client doesn't ship the data of every item. The server sends it, together with hotfixes,
after login or when you come across an item, and the client stores it in `DBCache.bin`. The
cache is used automatically if its build matches the client (shown under "Hotfixes" in the
output). The more you have played, the more required skills of recipe items are known; running
the script again later can fill in more of them.

Recipe items whose data the client doesn't have yet are still included (the link to the taught
recipe is always there), only their required skill stays unknown unless a trainer scan or
foreverdb knows it.

What the client ships encrypted with a key that is not public yet can't be read at all; such
recipes are missing until the key is published (the next run picks it up) or the content goes live.

Missing learning ranks never overwrite an existing positive rank with `0`. Such retained ranks
are reported under **Bestand**; current positive values from recipe items, trainer scans or
foreverdb still take priority, including corrections to lower ranks. This fallback only applies
to recipes present in the current build, not to removed recipes.

## Reading the output

```
Alchemy          183 Rezepte  (Lernstufe: 137 Rezept-Item, 2 Lehrer-Scan, 30 foreverdb, 14 unbekannt; 13 nicht in Forever)
```

- **Rezept-Item / Lehrer-Scan / foreverdb / Bestand / unbekannt:** where the required skill comes from (recipe item / trainer scan / foreverdb / existing data / unknown)
- **nicht in Forever:** present in the client but filtered out (mostly Season of Discovery)

If "unbekannt" rises noticeably after a patch, foreverdb probably doesn't have the new trainer
recipes yet. Simply run again later.

## Troubleshooting

- **`Layout … nicht in der DBD-Definition`:** WoWDBDefs doesn't know the new client build yet.
  Usually added within hours to days; then run again.
- **`Produkt … nicht in .build.info`:** Blizzard renamed the Forever product; change `PRODUCT` in `build_data.py` (column "Product" in `.build.info`).
- **Suddenly far fewer recipes:** new content may be encrypted with a key that is not public yet.
  Try again later (every run updates the key list).
- **`… wird für diesen Lauf übersprungen`:** a website failed twice in a row. The script stops
  contacting it, uses the cached pages instead and lists the host under "Nicht erreicht" in the
  report. Run again later to get current data.
- **`Web-Daten unvollständig … es wurde nichts geschrieben`:** a website was unreachable and some
  of its pages are not in the cache either. Writing would lose learning ranks and recipes, so the
  existing `Data/*.lua` stay unchanged (exit code 1). Run again later.
