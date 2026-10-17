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
3. Check the output (recipes per profession, see below), `/reload` in game and test briefly.
4. Commit the changed data, update `CHANGELOG.md` and publish a release (see the main README).

Requires only Python 3, no extra packages. A run takes about 15 seconds.

## Options

| Option | Effect |
|---|---|
| `--refresh` | Reload the web data (see below) even if the cache is still fresh |
| `--offline` | No internet; uses only the client and the existing cache |
| `--wow-dir PATH` | WoW installation folder (alternatively the environment variable `WOW_DIR`) |
| `--product NAME` | Client product from `World of Warcraft/.build.info` (default: `wow_classic_beta`). Adjust after launch if needed, or change `PRODUCT` in `build_data.py` |

## Files

| File | Purpose |
|---|---|
| `build_data.py` | Main script: reads the tables and writes `Data/*.lua` and `Data/RecipeItems.lua` |
| `casc.py` | Reads files from the local game storage (`World of Warcraft/Data`), including decryption |
| `db2.py` | Reads the game tables (DB2/WDC5) |
| `.cache/` | Downloaded helper data; can be deleted at any time and is recreated |

## Where does the data come from?

| Value | Source |
|---|---|
| Recipes, reagents, quantities, difficulty levels, names, crafted item | Game client |
| Required skill | Recipe item in the game client |
| Required skill of trainer recipes | foreverdb.net (not in the client); without a match `0` = unknown, nothing is estimated |
| Available in Forever? | Classic recipes (spell ID < 30000), Forever recipes (≥ 1229000) and everything listed on seemeta.com. This filters out Season of Discovery recipes that exist in the client but cannot be learned in Forever |

Also downloaded and cached for 7 days: the table definitions
(github.com/wowdev/WoWDBDefs) and the public key list for encrypted game data
(github.com/wowdev/TACTKeys).

## Reading the output

```
Alchemy          183 Rezepte  (Skill: 137 Rezept-Item, 30 foreverdb, 16 unbekannt; 13 nicht in Forever)
```

- **Rezept-Item / foreverdb / unbekannt:** where the required skill comes from (recipe item / foreverdb / unknown)
- **nicht in Forever:** present in the client but filtered out (mostly Season of Discovery)

If "unbekannt" rises noticeably after a patch, foreverdb probably doesn't have the new trainer
recipes yet. Simply run again later with `--refresh`.

## Troubleshooting

- **`Layout … nicht in der DBD-Definition`:** WoWDBDefs doesn't know the new client build yet.
  Usually added within hours to days; then run again with `--refresh`.
- **`Produkt … nicht in .build.info`:** adjust `--product` (column "Product" in `.build.info`).
- **Suddenly far fewer recipes:** new content may be encrypted with a key that is not public yet.
  Try again later with `--refresh` (updates the key list).
