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
   To only check what would change (no files written), add `--dry-run`. The report at the end
   lists new, removed and changed recipes per profession and tells you whether an update is worth it.
3. Check the output (recipes per profession, see below), `/reload` in game and test briefly.
4. Commit the changed data, update `CHANGELOG.md` and publish a release (see the main README).

Requires only Python 3, no extra packages. Every run fetches the web data again, so a run takes
about a minute.

## Options

| Option | Effect |
|---|---|
| `--offline` | No internet; uses only the client and the existing cache |
| `--dry-run` | Only report what would change, don't write any files |
| `--wow-dir PATH` | WoW installation folder (alternatively the environment variable `WOW_DIR`) |
| `--product NAME` | Client product from `World of Warcraft/.build.info` (default: `wowf` = WoW: Forever). Change `PRODUCT` in `build_data.py` if Blizzard renames the product |

## Files

| File | Purpose |
|---|---|
| `build_data.py` | Main script: reads the tables and writes `Data/*.lua` and `Data/RecipeItems.lua` |
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
| Required skill of trainer recipes | Not in the client. 1) Trainer scans: the addon records the skill whenever you talk to a profession trainer (stored in your SavedVariables, read automatically from the WoW folder). 2) foreverdb.net. Without a match `0` = unknown, nothing is estimated |
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

## Reading the output

```
Alchemy          183 Rezepte  (Lernstufe: 137 Rezept-Item, 2 Lehrer-Scan, 30 foreverdb, 14 unbekannt; 13 nicht in Forever)
```

- **Rezept-Item / Lehrer-Scan / foreverdb / unbekannt:** where the required skill comes from (recipe item / trainer scan / foreverdb / unknown)
- **nicht in Forever:** present in the client but filtered out (mostly Season of Discovery)

If "unbekannt" rises noticeably after a patch, foreverdb probably doesn't have the new trainer
recipes yet. Simply run again later.

## Troubleshooting

- **`Layout … nicht in der DBD-Definition`:** WoWDBDefs doesn't know the new client build yet.
  Usually added within hours to days; then run again.
- **`Produkt … nicht in .build.info`:** adjust `--product` (column "Product" in `.build.info`).
- **Suddenly far fewer recipes:** new content may be encrypted with a key that is not public yet.
  Try again later (every run updates the key list).
- **`… wird für diesen Lauf übersprungen`:** a website failed twice in a row. The script stops
  contacting it, uses the cached pages instead and lists the host under "Nicht erreicht" in the
  report. Run again later to get current data.
- **`Web-Daten unvollständig … es wurde nichts geschrieben`:** a website was unreachable and some
  of its pages are not in the cache either. Writing would lose learning ranks and recipes, so the
  existing `Data/*.lua` stay unchanged (exit code 1). Run again later.
