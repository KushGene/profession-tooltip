#!/usr/bin/env python3
"""Generates Data/Gathering.lua: gathering nodes with their required skill, object IDs and
their names in every client language.

The node list below (profession, required skill, object IDs) is the source. The names come
from Wowhead's WoW Forever tooltips (nether.wowhead.com/forever/tooltip/object/<id>), which
also state the required skill – every object ID is checked against it, so a wrong ID or
skill stops the run instead of ending up in the addon.

Names are needed because not every world tooltip tells the addon the object's ID; then the
tooltip title is matched against the node names of the client language.

Usage:
  python3 Tools/build_gathering.py             # fetch, check, write Data/Gathering.lua
  python3 Tools/build_gathering.py --offline   # cache only
  python3 Tools/build_gathering.py --dry-run   # check only
"""
import argparse
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_data import WebCache, lua_string, write_if_changed  # noqa: E402

HERBALISM, MINING = 182, 186
TOOLTIP_URL = "https://nether.wowhead.com/forever/tooltip/object/{}?locale={}"

# Client locale -> Wowhead locale ID. enGB uses enUS and ptPT uses ptBR (see ALIASES in the
# generated file). Italian has no object names in this data and falls back to object IDs.
LOCALES = {"enUS": 0, "deDE": 3, "frFR": 2, "esES": 6, "esMX": 11, "ruRU": 7, "ptBR": 8,
           "koKR": 1, "zhCN": 4, "zhTW": 10}

# (profession, required skill, object IDs) – the first ID supplies the names
# Only IDs that exist in Forever: 183046 (Blindweed), 181248 (Copper Vein) and 181249 (Tin Vein)
# are Burning Crusade objects and unknown to the Forever data.
NODES = [
    (HERBALISM, 1, [1618, 3724]),            # Peacebloom
    (HERBALISM, 1, [1617, 3725]),            # Silverleaf
    (HERBALISM, 15, [1619, 3726]),           # Earthroot
    (HERBALISM, 50, [1620, 3727]),           # Mageroyal
    (HERBALISM, 70, [1621, 3729]),           # Briarthorn
    (HERBALISM, 85, [2045]),                 # Stranglekelp
    (HERBALISM, 100, [1622, 3730]),          # Bruiseweed
    (HERBALISM, 115, [1623]),                # Wild Steelbloom
    (HERBALISM, 120, [1628]),                # Grave Moss
    (HERBALISM, 125, [1624]),                # Kingsblood
    (HERBALISM, 150, [2041]),                # Liferoot
    (HERBALISM, 160, [2042]),                # Fadeleaf
    (HERBALISM, 170, [2046]),                # Goldthorn
    (HERBALISM, 185, [2043]),                # Khadgar's Whisker
    (HERBALISM, 195, [2044]),                # Wintersbite
    (HERBALISM, 205, [2866]),                # Firebloom
    (HERBALISM, 210, [142140, 180165]),      # Purple Lotus
    (HERBALISM, 220, [142141, 176642]),      # Arthas' Tears
    (HERBALISM, 230, [142142, 176636, 180164]),  # Sungrass
    (HERBALISM, 235, [142143]),      # Blindweed
    (HERBALISM, 245, [142144]),              # Ghost Mushroom
    (HERBALISM, 250, [142145, 176637]),      # Gromsblood
    (HERBALISM, 260, [176583, 176638, 180167]),  # Golden Sansam
    (HERBALISM, 270, [176584, 176639, 180168]),  # Dreamfoil
    (HERBALISM, 280, [176586, 176640, 180166]),  # Mountain Silversage
    (HERBALISM, 285, [176587, 176641]),      # Plaguebloom
    (HERBALISM, 290, [176588]),              # Icecap
    (HERBALISM, 300, [176589]),              # Black Lotus
    (MINING, 1, [1731, 2055, 3763, 103713]),    # Copper Vein
    (MINING, 65, [1732, 2054, 3764, 103711]),   # Tin Vein
    (MINING, 75, [1733, 105569]),            # Silver Vein
    (MINING, 125, [1735]),                   # Iron Deposit
    (MINING, 155, [1734, 150080, 181109]),   # Gold Vein
    (MINING, 175, [2040, 150079, 176645]),   # Mithril Deposit
    (MINING, 230, [2047, 150081, 181108]),   # Truesilver Deposit
    (MINING, 230, [165658]),                 # Dark Iron Deposit
    (MINING, 245, [324, 150082, 176643]),    # Small Thorium Vein
    (MINING, 275, [175404]),                 # Rich Thorium Vein
    (MINING, 175, [123310]),                 # Ooze Covered Mithril Deposit
    (MINING, 230, [123309]),                 # Ooze Covered Truesilver Deposit
    (MINING, 245, [123848]),                 # Ooze Covered Thorium Vein
    (MINING, 275, [177388]),                 # Ooze Covered Rich Thorium Vein
]


def fetch(web, object_id, locale_id):
    """(name, required skill or None) of an object, or None if the page is missing."""
    body = web.get(TOOLTIP_URL.format(object_id, locale_id), f"wh_object_{object_id}_{locale_id}")
    if not body:
        return None
    try:
        data = json.loads(body)
    except ValueError:
        return None
    name = data.get("name")
    if not name:
        return None
    skills = re.findall(r"\((\d+)\)", re.sub(r"<[^>]+>", " ", data.get("tooltip", "")))
    return name, (int(skills[-1]) if skills else None)


def main():
    tools_dir = os.path.dirname(os.path.abspath(__file__))
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--cache", default=os.path.join(tools_dir, ".cache"))
    parser.add_argument("--offline", action="store_true", help="keine Web-Zugriffe (nur Cache)")
    parser.add_argument("--dry-run", action="store_true", help="nur prüfen, keine Datei schreiben")
    args = parser.parse_args()
    web = WebCache(args.cache, args.offline)

    print("Lese Knotennamen von Wowhead (Forever) …", flush=True)
    errors, names = [], {locale: [] for locale in LOCALES}
    for profession, skill, object_ids in NODES:
        english = None
        for object_id in object_ids:  # every ID must be this node, with this skill
            result = fetch(web, object_id, LOCALES["enUS"])
            if result is None:
                errors.append(f"Objekt {object_id}: keine Daten")
                continue
            name, found_skill = result
            english = english or name
            if name != english:
                errors.append(f"Objekt {object_id} heißt '{name}', erwartet '{english}'")
            if found_skill != skill:
                errors.append(f"Objekt {object_id} ({name}): Fertigkeit {found_skill}, in der Liste {skill}")
        for locale, locale_id in LOCALES.items():
            result = english and (english, skill) if locale == "enUS" else fetch(web, object_ids[0], locale_id)
            if not result:
                errors.append(f"Objekt {object_ids[0]}: kein Name für {locale}")
                names[locale].append(english or "")
            else:
                names[locale].append(result[0])

    for locale, list_ in names.items():  # the same title must not mean two different requirements
        seen = {}
        for (profession, skill, _), name in zip(NODES, list_):
            if name in seen and seen[name] != (profession, skill):
                errors.append(f"{locale}: Name '{name}' steht für verschiedene Knoten")
            seen[name] = (profession, skill)
    untranslated = [locale for locale in LOCALES if locale != "enUS" and names[locale] == names["enUS"]]
    for locale in untranslated:
        errors.append(f"{locale}: nur englische Namen erhalten")

    if errors or web.missing:
        print("\n".join("  ✘ " + e for e in errors))
        sys.exit("Knotendaten unvollständig oder widersprüchlich – es wurde nichts geschrieben.")

    lines = [
        "-- Data/Gathering.lua",
        "-- Generated automatically by Tools/build_gathering.py (node names: Wowhead, WoW Forever).",
        "-- Do not edit by hand; change the node list in the script and run it again.",
        "--",
        "-- Gathering requirements of world objects (not recipe skill ranks). Object IDs are",
        "-- locale-independent; the names cover tooltips that don't tell the object's ID.",
        "local _, ns = ...",
        "ns.GatheringNodes = {}",
        "",
        "-- { profession, required skill, { objectID, ... } }",
        "local NODES = {",
    ]
    for (profession, skill, object_ids), english in zip(NODES, names["enUS"]):
        lines.append(f"    {{ {profession}, {skill}, {{ {', '.join(map(str, object_ids))} }} }}, -- {english}")
    lines += ["}", "", "-- Node names per client language, in the order of NODES", "local NAMES = {"]
    for locale in LOCALES:
        lines.append(f"    {locale} = {{")
        lines += [f"        {lua_string(name)}," for name in names[locale]]
        lines.append("    },")
    lines += [
        "}",
        'local ALIASES = { enGB = "enUS", ptPT = "ptBR" }',
        "",
        "local locale = GetLocale()",
        "local localized = NAMES[ALIASES[locale] or locale]",
        "for index, entry in ipairs(NODES) do",
        "    local node = { profession = entry[1], skill = entry[2] }",
        "    for _, objectID in ipairs(entry[3]) do",
        "        ns.GatheringNodes[objectID] = node",
        "    end",
        "    ns.GatheringNodes[NAMES.enUS[index]] = node -- also for languages without names",
        "    if localized then",
        "        ns.GatheringNodes[localized[index]] = node",
        "    end",
        "end",
    ]
    path = os.path.join(os.path.dirname(tools_dir), "Data", "Gathering.lua")
    count = sum(len(ids) for _, _, ids in NODES)
    if args.dry_run:
        print(f"  ✔ {len(NODES)} Knoten, {count} Objekt-IDs, {len(LOCALES)} Sprachen geprüft (Testlauf, nichts geschrieben).")
    else:
        written = write_if_changed(path, lines)
        print(f"  ✔ {len(NODES)} Knoten, {count} Objekt-IDs, {len(LOCALES)} Sprachen – "
              + ("Data/Gathering.lua geschrieben." if written else "keine Änderung."))


if __name__ == "__main__":
    main()
