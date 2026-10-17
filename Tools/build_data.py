#!/usr/bin/env python3
"""Erzeugt die Data/*.lua-Dateien von ProfessionTooltip aus dem installierten WoW-Forever-Client.

Hauptquelle sind die DB2-Tabellen des Clients (gelesen über casc.py/db2.py):
  SkillLineAbility  Rezept -> Beruf, Farbstufen (gelb/grau)
  SpellReagents     Zutaten und Mengen
  SpellEffect       hergestelltes Item
  SpellName         englischer Rezeptname (Fallback im Addon)
  ItemSparse + ItemEffect + ItemXItemEffect   benötigter Skill laut Rezept-Item

Optionale Web-Ergänzungen (entfallen mit --offline):
  foreverdb.net  benötigter Skill für Lehrer-Rezepte (steht nicht im Client); ohne Treffer
                 bleibt er unbekannt (0) – es wird nichts geschätzt
  seemeta.com    Liste der in Forever erhältlichen Rezepte, um Season-of-Discovery-Rezepte
                 auszufiltern, die zwar im Client stecken, in Forever aber nicht erlernbar sind

Benötigt aus dem Netz außerdem (gecacht): Tabellendefinitionen von WoWDBDefs und die
öffentliche TACT-Key-Liste (zum Entschlüsseln neuer Inhalte).

Aufruf:
  python3 Tools/build_data.py              # normaler Lauf
  python3 Tools/build_data.py --refresh    # Definitionen, Keys und Web-Listen neu laden
  python3 Tools/build_data.py --offline    # nur Client-Daten (+ vorhandener Cache)
"""
import argparse
import html
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import casc  # noqa: E402
import db2  # noqa: E402

PRODUCT = "wow_classic_beta"  # WoW: Forever; nach dem Launch ggf. anpassen (--product)

# Skill-Line -> (Dateiname, seemeta/foreverdb-Name)
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

# Ohne Web-Liste: Classic-Rezepte (< 30000) und Forever-eigene Rezepte (>= 1229000) gelten als
# erhältlich; dazwischen liegen v. a. Season-of-Discovery-Rezepte.
CLASSIC_MAX_SPELL = 30000
FOREVER_MIN_SPELL = 1229000

EFFECT_CREATE_ITEM = 24
TRIGGER_LEARN_SPELL = 6
DAY = 86400
USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0"

DBD_URL = "https://raw.githubusercontent.com/wowdev/WoWDBDefs/master/definitions/{}.dbd"
MANIFEST_URL = "https://raw.githubusercontent.com/wowdev/WoWDBDefs/master/manifest.json"
TACT_KEYS_URL = "https://raw.githubusercontent.com/wowdev/TACTKeys/master/WoW.txt"


# ----------------------------------------------------------------------------
# Web-Cache
# ----------------------------------------------------------------------------
class WebCache:
    def __init__(self, cache_dir, refresh, offline):
        self.cache_dir, self.refresh, self.offline = cache_dir, refresh, offline
        os.makedirs(cache_dir, exist_ok=True)

    def get(self, url, key, max_age=7 * DAY):
        """Datei aus dem Cache bzw. neu laden; None, wenn offline und nicht vorhanden."""
        path = os.path.join(self.cache_dir, key)
        fresh = os.path.exists(path) and time.time() - os.path.getmtime(path) < max_age
        if os.path.exists(path) and (self.offline or (fresh and not self.refresh)):
            with open(path, encoding="utf8") as f:
                return f.read()
        if self.offline:
            return None
        try:
            request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            body = urllib.request.urlopen(request, timeout=60).read().decode("utf8")
        except (urllib.error.URLError, TimeoutError) as e:
            print(f"  Warnung: {url} nicht erreichbar ({e})", flush=True)
            if os.path.exists(path):
                with open(path, encoding="utf8") as f:
                    return f.read()
            return None
        with open(path, "w", encoding="utf8") as f:
            f.write(body)
        time.sleep(0.5)
        return body


# ----------------------------------------------------------------------------
# Client-Daten
# ----------------------------------------------------------------------------
def load_client_tables(wow_dir, product, web):
    keys_path = os.path.join(web.cache_dir, "tactkeys.txt")
    if web.get(TACT_KEYS_URL, "tactkeys.txt") is None and not os.path.exists(keys_path):
        sys.exit("TACT-Keys fehlen (einmal ohne --offline ausführen)")
    storage = casc.Casc(wow_dir, product, casc.load_tact_keys(keys_path))
    print(f"Client: {storage.build_name}", flush=True)

    manifest = {e["tableName"]: e.get("db2FileDataID") for e in json.loads(web.get(MANIFEST_URL, "manifest.json"))}
    tables = {}
    for name in TABLES:
        definition = web.get(DBD_URL.format(name), f"dbd_{name}.dbd")
        tables[name] = db2.read_table(storage.read_fdid(manifest[name]), definition)
    return storage.build_name, tables


def recipe_items(tables):
    """Rezept-Items ("Recipe: ...") -> (gelehrter Spell, benötigter Skill)."""
    effects, items = tables["ItemEffect"], tables["ItemSparse"]
    result = {}
    for link in tables["ItemXItemEffect"].values():
        effect, item = effects.get(link["ItemEffectID"]), items.get(link["ItemID"])
        if effect and item and effect["TriggerType"] == TRIGGER_LEARN_SPELL and item["RequiredSkill"]:
            result[link["ItemID"]] = (effect["SpellID"], item["RequiredSkillRank"])
    return result


def created_items(tables):
    created = {}
    for effect in tables["SpellEffect"].values():
        if effect["Effect"] == EFFECT_CREATE_ITEM and effect["EffectItemType"]:
            created.setdefault(effect["SpellID"], effect["EffectItemType"])
    return created


# ----------------------------------------------------------------------------
# Web-Ergänzungen
# ----------------------------------------------------------------------------
def foreverdb_skills(web, profession):
    """(item|spell, id) -> benötigter Skill, laut foreverdb (enthält auch Lehrer-Rezepte)."""
    skills = {}
    for page in range(1, 40):
        body = web.get(f"https://foreverdb.net/profession/{profession}?p={page}", f"fdb_{profession}_{page}")
        if not body:
            break
        # Eine Seite kann mehrere Listen enthalten (z. B. "Best in Slot" vor der Rezeptliste)
        entries = []
        for ul in re.findall(r'<ul class="ssr-list">(.*?)</ul>', body, re.S):
            entries += re.findall(r"<li>(.*?)</li>", ul)
        for li in entries:
            ref = re.search(r"/(item|spell)/(\d+)", li)
            skill = re.search(r"(?:, skill|learn it at skill) (\d+)", html.unescape(re.sub(r"<[^>]+>", "", li)))
            if ref and skill:
                skills.setdefault((ref[1], int(ref[2])), int(skill[1]))
        if not entries or "Next" not in body:
            break
    return skills


def seemeta_available(web, profession):
    """Menge der (item|spell, id), die seemeta als in Forever erhältlich führt (oder None)."""
    body = web.get(f"https://seemeta.com/en/wow-forever/professions/{profession}", f"seemeta_{profession}")
    if not body:
        return None
    return {(kind, int(i)) for kind, i in
            re.findall(r'<a data-name href="https://www.wowhead.com/forever/(item|spell)=(\d+)"', body)}


# ----------------------------------------------------------------------------
# Ausgabe
# ----------------------------------------------------------------------------
def lua_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def write_data_file(path, file_name, skill_line, build_name, recipes):
    lines = [
        f"-- Data/{file_name}.lua",
        f"-- Automatisch erzeugt von Tools/build_data.py aus dem Client ({build_name}).",
        "-- Nicht von Hand bearbeiten, sondern das Skript erneut ausführen.",
        "local _, ns = ...",
        "",
        "-- [spellID] = { benötigterSkill (0 = unbekannt), \"Fallback-Name\", { itemID, Menge, ... },",
        "--               hergestelltesItem (0 = keins), gelbAb, grünAb, grauAb }",
        f"ns.RegisterRecipes({skill_line}, {{",
    ]
    for spell_id, recipe in sorted(recipes.items(), key=lambda kv: (kv[1]["skill"], kv[0])):
        reagents = ", ".join(f"{item}, {count}" for item, count in recipe["reagents"])
        levels = "".join(f", {level}" for level in recipe["levels"]) if recipe["levels"] else ""
        lines.append(f"    [{spell_id}] = {{ {recipe['skill']}, {lua_string(recipe['name'])}, {{ {reagents} }}, "
                     f"{recipe['created']}{levels} }},")
    lines.append("})")
    with open(os.path.join(path, file_name + ".lua"), "w", encoding="utf8") as f:
        f.write("\n".join(lines) + "\n")


def main():
    tools_dir = os.path.dirname(os.path.abspath(__file__))
    addon_dir = os.path.dirname(tools_dir)
    # Liegt das Addon im Spiel (.../World of Warcraft/_classic_beta_/Interface/AddOns/ProfessionTooltip),
    # ergibt sich der WoW-Ordner von selbst; im Repository über --wow-dir oder WOW_DIR angeben.
    default_wow_dir = os.environ.get("WOW_DIR") or os.path.abspath(os.path.join(addon_dir, "..", "..", "..", ".."))

    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--wow-dir", default=default_wow_dir,
                        help="WoW-Installationsverzeichnis (mit .build.info); alternativ Umgebungsvariable WOW_DIR")
    parser.add_argument("--product", default=PRODUCT)
    parser.add_argument("--cache", default=os.path.join(tools_dir, ".cache"))
    parser.add_argument("--refresh", action="store_true", help="Definitionen, Keys und Web-Listen neu laden")
    parser.add_argument("--offline", action="store_true", help="keine Web-Zugriffe (nur Client + Cache)")
    args = parser.parse_args()

    if not os.path.exists(os.path.join(args.wow_dir, ".build.info")):
        sys.exit(f"WoW-Ordner nicht gefunden: {args.wow_dir}\n"
                 "Bitte mit --wow-dir oder der Umgebungsvariable WOW_DIR angeben, "
                 "z. B. WOW_DIR=\"$HOME/Games/World of Warcraft\"")

    print(time.strftime("%Y-%m-%d %H:%M"), flush=True)
    web = WebCache(args.cache, args.refresh, args.offline)
    build_name, tables = load_client_tables(args.wow_dir, args.product, web)
    teaching_items = recipe_items(tables)
    item_ranks = {}
    for spell_id, rank in teaching_items.values():
        item_ranks.setdefault(spell_id, rank)
    all_recipes = set()
    created = created_items(tables)
    reagents_by_spell = {r["SpellID"]: r for r in tables["SpellReagents"].values()}
    names = tables["SpellName"]

    for skill_line, (file_name, web_name) in PROFESSIONS.items():
        fdb = foreverdb_skills(web, web_name)
        available = seemeta_available(web, web_name)
        recipes, sources, skipped = {}, {"item": 0, "foreverdb": 0, "unknown": 0}, 0
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

            fdb_skill = next((fdb[r] for r in refs if r in fdb), None)
            if spell_id in item_ranks:
                skill, source = item_ranks[spell_id], "item"
            elif fdb_skill is not None:
                skill, source = fdb_skill, "foreverdb"
            elif ability["MinSkillLineRank"] > 1:
                skill, source = ability["MinSkillLineRank"], "item"
            else:  # Lehrer-Rezept ohne Daten: unbekannt, wird im Addon nicht angezeigt
                skill, source = 0, "unknown"
            sources[source] += 1

            name = names.get(spell_id, {}).get("Name_lang") or f"Spell {spell_id}"
            recipes[spell_id] = {"skill": skill, "name": name, "reagents": reagents,
                                 "created": item_id or 0, "levels": levels}
            all_recipes.add(spell_id)

        write_data_file(os.path.join(addon_dir, "Data"), file_name, skill_line, build_name, recipes)
        print(f"{file_name:15} {len(recipes):4} Rezepte  (Skill: {sources['item']} Rezept-Item, "
              f"{sources['foreverdb']} foreverdb, {sources['unknown']} unbekannt; {skipped} nicht in Forever)",
              flush=True)

    write_recipe_items(os.path.join(addon_dir, "Data"), build_name,
                       {item: spell for item, (spell, _) in teaching_items.items() if spell in all_recipes})


def write_recipe_items(path, build_name, items):
    lines = [
        "-- Data/RecipeItems.lua",
        f"-- Automatisch erzeugt von Tools/build_data.py aus dem Client ({build_name}).",
        "local _, ns = ...",
        "",
        "-- [Rezept-Item] = gelehrter Spell",
        "ns.RegisterRecipeItems({",
    ]
    for item_id, spell_id in sorted(items.items()):
        lines.append(f"    [{item_id}] = {spell_id},")
    lines.append("})")
    with open(os.path.join(path, "RecipeItems.lua"), "w", encoding="utf8") as f:
        f.write("\n".join(lines) + "\n")
    print(f"RecipeItems     {len(items):4} Rezept-Items", flush=True)


if __name__ == "__main__":
    main()
