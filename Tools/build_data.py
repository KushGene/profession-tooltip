#!/usr/bin/env python3
"""Generates ProfessionTooltip's Data/*.lua files from the installed WoW Forever client.

The main source is the client's DB2 tables (read via casc.py/db2.py):
  SkillLineAbility  recipe -> profession, color thresholds (yellow/gray)
  SpellReagents     reagents and counts
  SpellEffect       crafted item
  SpellName         English recipe name (fallback in the addon; on non-English clients the
                    localized name – the English names of existing recipes are kept instead)
  ItemEffect + ItemXItemEffect   recipe item -> taught recipe
  ItemSparse        required skill according to the recipe item
Plus the client's hotfix cache (Cache/ADB/<locale>/DBCache.bin): the server sends changes and the
data of items the client doesn't ship yet (e.g. recipe items of new content) only after login
or when you come across them – so the cache, and with it the data, grows with playing.

Optional web additions (skipped with --offline):
  Trainer scans  required skill for trainer recipes, recorded by the addon when visiting a trainer
                 (SavedVariables in the WoW folder)
  foreverdb.net  required skill for trainer recipes (not in the client); without a match
                 it stays unknown (0) – nothing is guessed. Its recipe list also tells which
                 recipes are available in Forever, to filter out Season of Discovery recipes
                 that are in the client but cannot be learned in Forever

Also fetched from the web: table definitions from WoWDBDefs and the public TACT key list
(to decrypt new content).

Every run fetches all web data again; the cache is only a fallback. If a host fails repeatedly,
it is skipped for the rest of the run and the cache is used. If pages are missing even from the
cache, nothing is written (the data would be incomplete).

Usage:
  python3 Tools/build_data.py              # normal run
  python3 Tools/build_data.py --offline    # client data only (+ existing cache)
  python3 Tools/build_data.py --dry-run    # check only: shows what would change
"""
import argparse
import glob
import html
import http.client
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import casc  # noqa: E402
import db2  # noqa: E402

PRODUCT = "wowf"  # WoW: Forever (product name in World of Warcraft/.build.info)

# Skill line -> (file name, foreverdb name)
PROFESSIONS = {
    171: ("Alchemy", "alchemy"),
    164: ("Blacksmithing", "blacksmithing"),
    333: ("Enchanting", "enchanting"),
    202: ("Engineering", "engineering"),
    165: ("Leatherworking", "leatherworking"),
    197: ("Tailoring", "tailoring"),
    186: ("Mining", "mining"),
    182: ("Herbalism", "herbalism"),
    393: ("Skinning", "skinning"),
    185: ("Cooking", "cooking"),
    129: ("FirstAid", "first-aid"),
    356: ("Fishing", "fishing"),
}
TABLES = ["SkillLineAbility", "SpellReagents", "SpellEffect", "SpellName",
          "ItemSparse", "ItemEffect", "ItemXItemEffect"]

# Without a web list: Classic recipes (< 30000) and Forever's own recipes (>= 1229000) count as
# available; in between are mainly Season of Discovery recipes.
CLASSIC_MAX_SPELL = 30000
FOREVER_MIN_SPELL = 1229000

EFFECT_CREATE_ITEM = 24
TRIGGER_LEARN_SPELL = 6

# CASC root locale flag -> locale name (wowdev CASC); enUS = casc.LOCALE_ENUS
LOCALE_NAMES = {
    0x2: "enUS", 0x4: "koKR", 0x10: "frFR", 0x20: "deDE", 0x40: "zhCN", 0x80: "esES",
    0x100: "zhTW", 0x200: "enGB", 0x400: "enCN", 0x800: "enTW", 0x1000: "esMX",
    0x2000: "ruRU", 0x4000: "ptBR", 0x8000: "itIT", 0x10000: "ptPT",
}

USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0"
WEB_TIMEOUT = 20
MAX_HOST_FAILURES = 2  # after that many failed requests a host is skipped for the rest of the run

DBD_URL = "https://raw.githubusercontent.com/wowdev/WoWDBDefs/master/definitions/{}.dbd"
MANIFEST_URL = "https://raw.githubusercontent.com/wowdev/WoWDBDefs/master/manifest.json"
TACT_KEYS_URL = "https://raw.githubusercontent.com/wowdev/TACTKeys/master/WoW.txt"


# ----------------------------------------------------------------------------
# Web cache
# ----------------------------------------------------------------------------
class WebCache:
    def __init__(self, cache_dir, offline):
        self.cache_dir, self.offline = cache_dir, offline
        self.failures = {}  # host -> number of consecutive failed requests
        self.fallbacks = {}  # host -> number of requests answered from the (outdated) cache
        self.missing = {}  # host -> number of requests that failed and weren't in the cache either
        os.makedirs(cache_dir, exist_ok=True)

    def get(self, url, key):
        """Fetch a file (and cache it); falls back to the cache if offline or unreachable, else None."""
        path = os.path.join(self.cache_dir, key)
        cached = os.path.exists(path)
        if self.offline:
            return self._read(path) if cached else None
        host = urllib.parse.urlsplit(url).hostname
        if self.failures.get(host, 0) < MAX_HOST_FAILURES:
            try:
                request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
                body = urllib.request.urlopen(request, timeout=WEB_TIMEOUT).read().decode("utf8")
            except (OSError, http.client.HTTPException, UnicodeDecodeError) as e:
                # OSError covers URLError, timeouts and connection errors; HTTPException a download
                # that breaks off halfway (IncompleteRead)
                self.failures[host] = self.failures.get(host, 0) + 1
                print(f"  Warnung: {url} nicht erreichbar ({e})", flush=True)
                if self.failures[host] == MAX_HOST_FAILURES:
                    print(f"  Warnung: {host} wird für diesen Lauf übersprungen"
                          f" ({MAX_HOST_FAILURES} Fehlschläge), es wird der Cache genutzt", flush=True)
            else:
                self.failures[host] = 0
                with open(path, "w", encoding="utf8") as f:
                    f.write(body)
                time.sleep(0.5)
                return body
        if not cached:
            self.missing[host] = self.missing.get(host, 0) + 1
            return None
        self.fallbacks[host] = self.fallbacks.get(host, 0) + 1
        return self._read(path)

    def failed_hosts(self):
        return sorted(set(self.fallbacks) | set(self.missing))

    @staticmethod
    def _read(path):
        with open(path, encoding="utf8") as f:
            return f.read()


def locale_name(flags):
    """Name of the first set locale bit (or the raw flags if unknown)."""
    for bit in sorted(LOCALE_NAMES):
        if flags & bit:
            return LOCALE_NAMES[bit]
    return f"0x{flags:x}"


# ----------------------------------------------------------------------------
# Client data
# ----------------------------------------------------------------------------
def load_client_tables(wow_dir, product, web):
    keys_path = os.path.join(web.cache_dir, "tactkeys.txt")
    if web.get(TACT_KEYS_URL, "tactkeys.txt") is None and not os.path.exists(keys_path):
        sys.exit("TACT-Keys fehlen (einmal ohne --offline ausführen)")
    storage = casc.Casc(wow_dir, product, casc.load_tact_keys(keys_path))
    hotfixes, hotfix_path = load_hotfixes(wow_dir, storage.build_name)

    manifest_text = web.get(MANIFEST_URL, "manifest.json")
    if manifest_text is None:
        sys.exit("Tabellenliste (WoWDBDefs manifest.json) fehlt (einmal ohne --offline ausführen)")
    manifest = {e["tableName"]: e.get("db2FileDataID") for e in json.loads(manifest_text)}
    tables, non_english = {}, {}
    for name in TABLES:
        definition = web.get(DBD_URL.format(name), f"dbd_{name}.dbd")
        if definition is None:
            sys.exit(f"Tabellendefinition {name}.dbd fehlt (einmal ohne --offline ausführen)")
        fdid = manifest[name]
        tables[name] = db2.read_table(storage.read_fdid(fdid), definition, hotfixes)
        if not storage.locales[fdid] & casc.LOCALE_ENUS:
            non_english[name] = locale_name(storage.locales[fdid])
    return (storage.build_name, tables, hotfix_path,
            sum(len(records) for records in hotfixes.values()), non_english)


def load_hotfixes(wow_dir, build_name):
    """Hotfix cache of the installation that matches the client build; searched in every
    installed locale (_*_/Cache/ADB/<locale>/DBCache.bin), enUS directories first."""
    match = re.search(r"(\d+)", build_name)
    build = int(match[1]) if match else None
    paths = glob.glob(os.path.join(wow_dir, "_*_", "Cache", "ADB", "*", "DBCache.bin"))
    paths.sort(key=lambda p: (os.sep + "enUS" + os.sep not in p, p))
    for path in paths:
        with open(path, "rb") as f:
            hotfixes = db2.read_hotfixes(f.read(), build)
        if hotfixes:
            return hotfixes, path
    return {}, None


def recipe_items(tables):
    """Recipe items ("Recipe: ...") -> (taught spell, required skill or None).
    Many recipe items are missing from ItemSparse (the server sends their data only when you
    come across them), but the link to the taught spell is there – so they count anyway,
    just without a required skill. Only spells that are recipes are used later on."""
    effects, items = tables["ItemEffect"], tables["ItemSparse"]
    result = {}
    for link in tables["ItemXItemEffect"].values():
        effect, item = effects.get(link["ItemEffectID"]), items.get(link["ItemID"])
        if not effect or effect["TriggerType"] != TRIGGER_LEARN_SPELL:
            continue
        if item is None:
            result[link["ItemID"]] = (effect["SpellID"], None)
        elif item["RequiredSkill"]:
            result[link["ItemID"]] = (effect["SpellID"], item["RequiredSkillRank"])
    return result


def created_items(tables):
    created = {}
    for effect in tables["SpellEffect"].values():
        if effect["Effect"] == EFFECT_CREATE_ITEM and effect["EffectItemType"]:
            created.setdefault(effect["SpellID"], effect["EffectItemType"])
    return created


# ----------------------------------------------------------------------------
# Web additions
# ----------------------------------------------------------------------------
def foreverdb_recipes(web, profession):
    """According to foreverdb (includes trainer recipes):
    ({(item|spell, id): required skill}, set of (item|spell, id) available in Forever or None)."""
    skills, available = {}, set()
    for page in range(1, 40):
        body = web.get(f"https://foreverdb.net/profession/{profession}?p={page}", f"fdb_{profession}_{page}")
        if not body:
            break
        # A page can contain several lists (e.g. "Best in Slot" before the recipe list)
        entries = []
        for ul in re.findall(r'<ul class="ssr-list">(.*?)</ul>', body, re.S):
            entries += re.findall(r"<li>(.*?)</li>", ul)
        for li in entries:
            ref = re.search(r"/(item|spell)/(\d+)", li)
            if not ref:
                continue
            ref = (ref[1], int(ref[2]))
            available.add(ref)
            skill = re.search(r"(?:, skill|learn it at skill) (\d+)", html.unescape(re.sub(r"<[^>]+>", "", li)))
            if skill:
                skills.setdefault(ref, int(skill[1]))
        # Pager link to the following page, e.g. <a href="?p=2">Next ›</a>
        if not entries or not re.search(rf'href="[^"]*\?p={page + 1}"', body):
            break
    return skills, available or None


# ----------------------------------------------------------------------------
# Trainer scans from the game (SavedVariables)
# ----------------------------------------------------------------------------
def trainer_scans(wow_dir):
    """Trainer ranks recorded by the addon across all accounts: {spellID: rank}.

    The addon stores them in WTF/Account/<Account>/SavedVariables/ProfessionTooltip.lua.
    If a recipe has several values, the lowest one wins."""
    pattern = os.path.join(wow_dir, "_*_", "WTF", "Account", "*", "SavedVariables", "ProfessionTooltip.lua")
    skills, files = {}, 0
    for path in glob.glob(pattern):
        with open(path, encoding="utf8", errors="replace") as f:
            block = re.search(r'\["trainerSkills"\]\s*=\s*\{([^{}]*)\}', f.read())
        if not block:
            continue
        files += 1
        for spell_id, rank in re.findall(r"\[(\d+)\]\s*=\s*(\d+)", block[1]):
            spell_id, rank = int(spell_id), int(rank)
            if rank > 0 and (spell_id not in skills or rank < skills[spell_id]):
                skills[spell_id] = rank
    return skills, files


# ----------------------------------------------------------------------------
# Comparison with the existing data
# ----------------------------------------------------------------------------
def read_data_file(path):
    """Existing data file -> {spellID: (skill, name, reagents, created, levels)}"""
    if not os.path.exists(path):
        return {}
    result = {}
    with open(path, encoding="utf8") as f:
        for line in f:
            m = re.match(r'\s*\[(\d+)\] = \{ (\d+), "((?:[^"\\]|\\.)*)", \{ ([^}]*) \}, (\d+)((?:, \d+)*) \},', line)
            if m:
                numbers = [int(x) for x in m[4].split(",")]
                result[int(m[1])] = (int(m[2]), m[3], tuple(zip(numbers[::2], numbers[1::2])), int(m[5]),
                                     tuple(int(x) for x in m[6].split(",")[1:]))
    return result


def lua_unescape(text):
    """Undoes the escapes lua_string writes (only \\" and \\\\ occur in the data files)."""
    return re.sub(r"\\(.)", r"\1", text)


def as_tuple(recipe):
    return (recipe["skill"], recipe["name"].replace("\\", "\\\\").replace('"', '\\"'), tuple(recipe["reagents"]),
            recipe["created"], tuple(recipe["levels"] or ()))


CHANGE_KINDS = ("Zutaten", "Lernstufe", "Farbstufen", "Name", "Endprodukt")


def compare(old, new):
    """Zählt neue, entfernte und geänderte Rezepte (nach Art der Änderung)."""
    stats = {"neu": len(set(new) - set(old)), "entfernt": len(set(old) - set(new)), "geändert": 0}
    stats.update({kind: 0 for kind in CHANGE_KINDS})
    for spell_id in set(old) & set(new):
        a, b = old[spell_id], as_tuple(new[spell_id])
        diffs = [kind for kind, i in (("Lernstufe", 0), ("Name", 1), ("Zutaten", 2), ("Endprodukt", 3), ("Farbstufen", 4))
                 if a[i] != b[i]]
        if diffs:
            stats["geändert"] += 1
            for kind in diffs:
                stats[kind] += 1
    return stats


# Colors only in a terminal (not in log files); NO_COLOR turns them off
USE_COLOR = sys.stdout.isatty() and not os.environ.get("NO_COLOR")
DISPLAY_NAMES = {
    "Alchemy": "Alchimie", "Blacksmithing": "Schmiedekunst", "Enchanting": "Verzauberkunst",
    "Engineering": "Ingenieurskunst", "Leatherworking": "Lederverarbeitung", "Tailoring": "Schneiderei",
    "Mining": "Bergbau", "Herbalism": "Kräuterkunde", "Skinning": "Kürschnerei", "Cooking": "Kochkunst",
    "FirstAid": "Erste Hilfe", "Fishing": "Angeln", "RecipeItems": "Rezept-Items",
}


def color(text, code):
    return f"\033[{code}m{text}\033[0m" if USE_COLOR else text


def bold(text): return color(text, "1")
def dim(text): return color(text, "2")
def green(text): return color(text, "32")
def yellow(text): return color(text, "33")


def heading(text):
    print("\n" + bold(text.upper()))
    print(dim("─" * 78))


def print_header(build_name, hotfix_path, hotfix_count, trainer_count, trainer_files, web, dry_run,
                 non_english=None, localized_names=0):
    title = "Profession Tooltip – Datenprüfung" + (" (Testlauf, es wird nichts geschrieben)" if dry_run else "")
    print(bold(title))
    print(dim("═" * 78))
    print(f"  {'Datum':14} {time.strftime('%d.%m.%Y %H:%M')}")
    print(f"  {'Spielclient':14} {build_name}")
    print(f"  {'Hotfixes':14} " + (f"{hotfix_count} Einträge aus {hotfix_path}" if hotfix_path
                                    else yellow("keine passende DBCache.bin gefunden")))
    if non_english:
        locale = next(iter(non_english.values()))
        if "SpellName" in non_english:
            note = (f"Client-Sprache {locale}: englische Ersatznamen aus den bestehenden Daten "
                    f"übernommen, {localized_names} neue Rezepte mit {locale}-Namen.")
        else:
            note = (f"Client-Sprache {locale}: {', '.join(sorted(non_english))} ohne enUS-Variante "
                    "gelesen (nur Zahlen betroffen).")
        print(f"  {'Sprache':14} " + yellow(note))
    print(f"  {'Lehrer-Scans':14} {trainer_count} Rezepte aus {trainer_files} SavedVariables-Datei(en)")
    for host in web.failed_hosts():
        print(f"  {'Nicht erreicht':14} " + yellow(f"{host} – {web.fallbacks.get(host, 0)} Seite(n) aus dem Cache, "
                                                  f"{web.missing.get(host, 0)} fehlen"))


def print_recipe_table(rows):
    heading("Rezepte pro Beruf")
    print(dim(f"  {'':18} {'':>7}   {'Lernstufe bekannt aus':^30}   {'':>9}  {'nicht in':>8}"))
    print(dim(f"  {'Beruf':18} {'Rezepte':>7}   {'Item':>6} {'Lehrer':>7} {'foreverdb':>10}   {'unbekannt':>9}  {'Forever':>8}"))
    totals = {"count": 0, "Rezept-Item": 0, "Lehrer-Scan": 0, "foreverdb": 0, "unbekannt": 0, "skipped": 0}
    for name, count, sources, skipped in rows:
        unknown = sources["unbekannt"]
        print(f"  {DISPLAY_NAMES.get(name, name):18} {count:>7}   {sources['Rezept-Item']:>6} {sources['Lehrer-Scan']:>7} "
              f"{sources['foreverdb']:>10}   {(yellow if unknown else str)(f'{unknown:>9}')}  {dim(f'{skipped:>8}')}")
        totals["count"] += count
        totals["skipped"] += skipped
        for key in ("Rezept-Item", "Lehrer-Scan", "foreverdb", "unbekannt"):
            totals[key] += sources[key]
    print(dim("  " + "─" * 76))
    print(bold(f"  {'Summe':18} {totals['count']:>7}   {totals['Rezept-Item']:>6} {totals['Lehrer-Scan']:>7} "
               f"{totals['foreverdb']:>10}   {totals['unbekannt']:>9}  {totals['skipped']:>8}"))


def print_report(rows, total_changes, item_count, dry_run, incomplete):
    print(f"\n  Rezept-Items (\"Recipe: …\"): {item_count}")
    heading("Änderungen gegenüber den vorhandenen Daten")
    changed = [(name, st) for name, st in rows if st["neu"] or st["entfernt"] or st["geändert"]]
    if not changed:
        print("  " + green("✔ Keine Änderungen – die Daten sind aktuell."))
    else:
        print(dim(f"  {'Beruf':18} {'neu':>5} {'entfernt':>9} {'geändert':>9}   davon"))
        for name, st in changed:
            detail = ", ".join(f"{st[kind]}× {kind}" for kind in CHANGE_KINDS if st[kind])
            print(f"  {DISPLAY_NAMES.get(name, name):18} {st['neu']:>5} {st['entfernt']:>9} {st['geändert']:>9}   {dim(detail)}")

    heading("Ergebnis")
    if incomplete:
        print("  " + yellow(f"✘ Web-Daten unvollständig ({', '.join(incomplete)} nicht erreichbar, Seiten fehlen "
                            "auch im Cache) – die Änderungen oben sind nicht verlässlich."))
        print("  " + ("Testlauf, es wurde nichts geschrieben." if dry_run else
                      "Es wurde nichts geschrieben, die vorhandenen Daten bleiben unverändert."))
        print("  Später erneut ausführen.")
    elif total_changes == 0:
        print("  " + green("✔ Ein Addon-Update ist nicht nötig."))
    elif dry_run:
        print("  " + yellow(f"➜ {total_changes} Änderung(en) – ein Addon-Update lohnt sich."))
        print("\n  Nächste Schritte:")
        print("    1. Ohne --dry-run ausführen, um die Daten zu übernehmen")
        print("    2. Im Spiel testen (/reload)")
        print("    3. CHANGELOG.md ergänzen, committen, Release-Tag setzen")
    else:
        print("  " + yellow(f"➜ {total_changes} Änderung(en) übernommen – Dateien in Data/ wurden aktualisiert."))
        print("\n  Nächste Schritte:")
        print("    1. Im Spiel testen (/reload)")
        print("    2. CHANGELOG.md ergänzen, committen, Release-Tag setzen")
    print()


# ----------------------------------------------------------------------------
# Output
# ----------------------------------------------------------------------------
def lua_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


GENERATED_LINE = "-- Generated automatically by Tools/build_data.py from the client"


def write_if_changed(path, lines):
    """Writes the file unless only the client build in the header would change – a new build
    without data changes must not touch every data file. Returns True if written."""
    def body(text_lines):
        return [line for line in text_lines if not line.startswith(GENERATED_LINE)]
    if os.path.exists(path):
        with open(path, encoding="utf8") as f:
            if body(f.read().splitlines()) == body(lines):
                return False
    temp = path + ".tmp"
    with open(temp, "w", encoding="utf8") as f:
        f.write("\n".join(lines) + "\n")
    os.replace(temp, path)  # never leave a half-written data file behind
    return True


def write_data_file(path, file_name, skill_line, build_name, recipes):
    lines = [
        f"-- Data/{file_name}.lua",
        f"{GENERATED_LINE} ({build_name}).",
        "-- Do not edit by hand; run the script again instead.",
        "local _, ns = ...",
        "",
        "-- [spellID] = { requiredSkill (0 = unknown), \"fallback name\", { itemID, count, ... },",
        "--               createdItem (0 = none), yellowAt, greenAt, grayAt }",
        f"ns.RegisterRecipes({skill_line}, {{",
    ]
    for spell_id, recipe in sorted(recipes.items(), key=lambda kv: (kv[1]["skill"], kv[0])):
        reagents = ", ".join(f"{item}, {count}" for item, count in recipe["reagents"])
        levels = "".join(f", {level}" for level in recipe["levels"]) if recipe["levels"] else ""
        lines.append(f"    [{spell_id}] = {{ {recipe['skill']}, {lua_string(recipe['name'])}, {{ {reagents} }}, "
                     f"{recipe['created']}{levels} }},")
    lines.append("})")
    return write_if_changed(os.path.join(path, file_name + ".lua"), lines)


def write_recipe_items(path, build_name, items):
    lines = [
        "-- Data/RecipeItems.lua",
        f"{GENERATED_LINE} ({build_name}).",
        "local _, ns = ...",
        "",
        "-- [recipe item] = taught spell",
        "ns.RegisterRecipeItems({",
    ]
    for item_id, spell_id in sorted(items.items()):
        lines.append(f"    [{item_id}] = {spell_id},")
    lines.append("})")
    return write_if_changed(os.path.join(path, "RecipeItems.lua"), lines)


def read_recipe_items(path):
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf8") as f:
        return {int(a): int(b) for a, b in re.findall(r"\[(\d+)\] = (\d+),", f.read())}


def main():
    tools_dir = os.path.dirname(os.path.abspath(__file__))
    addon_dir = os.path.dirname(tools_dir)
    data_dir = os.path.join(addon_dir, "Data")
    # If the addon sits in the game (.../World of Warcraft/_forever_/Interface/AddOns/ProfessionTooltip),
    # the WoW folder follows from that; in the repository, pass --wow-dir or set WOW_DIR.
    default_wow_dir = os.environ.get("WOW_DIR") or os.path.abspath(os.path.join(addon_dir, "..", "..", "..", ".."))

    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--wow-dir", default=default_wow_dir,
                        help="WoW-Installationsverzeichnis (mit .build.info); alternativ Umgebungsvariable WOW_DIR")
    parser.add_argument("--product", default=PRODUCT)
    parser.add_argument("--cache", default=os.path.join(tools_dir, ".cache"))
    parser.add_argument("--offline", action="store_true", help="keine Web-Zugriffe (nur Client + Cache)")
    parser.add_argument("--dry-run", action="store_true", help="nur prüfen und berichten, keine Dateien schreiben")
    args = parser.parse_args()

    if not os.path.exists(os.path.join(args.wow_dir, ".build.info")):
        sys.exit(f"WoW-Ordner nicht gefunden: {args.wow_dir}\n"
                 "Bitte mit --wow-dir oder der Umgebungsvariable WOW_DIR angeben, "
                 "z. B. WOW_DIR=\"$HOME/Games/World of Warcraft\"")

    print(dim("Lese Spieldaten und Web-Listen …"), flush=True)
    web = WebCache(args.cache, args.offline)
    build_name, tables, hotfix_path, hotfix_count, non_english = load_client_tables(
        args.wow_dir, args.product, web)
    trainer, trainer_files = trainer_scans(args.wow_dir)

    teaching_items = recipe_items(tables)
    item_ranks = {}
    for spell_id, rank in teaching_items.values():
        if rank is not None:  # several items can teach the same recipe: the lowest rank counts
            item_ranks[spell_id] = min(rank, item_ranks.get(spell_id, rank))
    all_recipes = set()
    created = created_items(tables)
    reagents_by_spell = {r["SpellID"]: r for r in tables["SpellReagents"].values()}
    names = tables["SpellName"]

    report, recipe_rows, outputs, total_changes, localized_names = [], [], [], 0, 0
    spell_names_english = "SpellName" not in non_english
    for skill_line, (file_name, web_name) in PROFESSIONS.items():
        fdb, available = foreverdb_recipes(web, web_name)
        old = read_data_file(os.path.join(data_dir, file_name + ".lua"))
        recipes, skipped = {}, 0
        sources = {"Rezept-Item": 0, "Lehrer-Scan": 0, "foreverdb": 0, "unbekannt": 0}
        for ability in tables["SkillLineAbility"].values():
            spell_id = ability["Spell"]
            if ability["SkillLine"] != skill_line or spell_id not in reagents_by_spell:
                continue
            item_id = created.get(spell_id)
            refs = {("spell", spell_id)} | ({("item", item_id)} if item_id else set())
            listed = available is not None and bool(refs & available)
            if not (listed or spell_id < CLASSIC_MAX_SPELL or spell_id >= FOREVER_MIN_SPELL):
                skipped += 1
                continue

            row = reagents_by_spell[spell_id]
            reagents = [(item, count) for item, count in zip(row["Reagent"], row["ReagentCount"]) if item]
            if not reagents:
                continue
            low, high = ability["TrivialSkillLineRankLow"], ability["TrivialSkillLineRankHigh"]
            levels = (low, (low + high + 1) // 2, high) if 0 < low <= high else None

            # Sources of the learning rank, in this order; without a match 0 = unknown (don't guess)
            fdb_skill = next((fdb[r] for r in refs if r in fdb), None)
            if spell_id in item_ranks:
                skill, source = item_ranks[spell_id], "Rezept-Item"
            elif spell_id in trainer:
                skill, source = trainer[spell_id], "Lehrer-Scan"
            elif fdb_skill is not None:
                skill, source = fdb_skill, "foreverdb"
            else:
                skill, source = 0, "unbekannt"
            sources[source] += 1

            client_name = names.get(spell_id, {}).get("Name_lang")
            if spell_names_english:
                name = client_name or f"Spell {spell_id}"
            elif spell_id in old:
                name = lua_unescape(old[spell_id][1])  # keep the English name of known recipes
            else:
                name = client_name or f"Spell {spell_id}"
                localized_names += bool(client_name)
            recipes[spell_id] = {"skill": skill, "name": name, "reagents": reagents,
                                 "created": item_id or 0, "levels": levels}
            all_recipes.add(spell_id)

        stats = compare(old, recipes)
        total_changes += stats["neu"] + stats["entfernt"] + stats["geändert"]
        report.append((file_name, stats))
        outputs.append((file_name, skill_line, recipes))
        recipe_rows.append((file_name, len(recipes), sources, skipped))

    items = {item: spell for item, (spell, _) in teaching_items.items() if spell in all_recipes}
    old_items = read_recipe_items(os.path.join(data_dir, "RecipeItems.lua"))
    item_stats = {"neu": len(set(items) - set(old_items)), "entfernt": len(set(old_items) - set(items)),
                  "geändert": sum(1 for i in set(items) & set(old_items) if items[i] != old_items[i])}
    item_stats.update({kind: 0 for kind in CHANGE_KINDS})
    total_changes += item_stats["neu"] + item_stats["entfernt"] + item_stats["geändert"]
    report.append(("RecipeItems", item_stats))

    # Missing web pages would drop learning ranks and recipes – then keep the existing data
    incomplete = sorted(web.missing)
    if not args.dry_run and not incomplete:
        for file_name, skill_line, recipes in outputs:
            write_data_file(data_dir, file_name, skill_line, build_name, recipes)
        write_recipe_items(data_dir, build_name, items)

    print_header(build_name, hotfix_path, hotfix_count, len(trainer), trainer_files, web,
                 args.dry_run, non_english, localized_names)
    print_recipe_table(recipe_rows)
    print_report(report, total_changes, len(items), args.dry_run, incomplete)
    if incomplete:
        sys.exit(1)


if __name__ == "__main__":
    main()
