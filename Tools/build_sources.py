#!/usr/bin/env python3
"""Generates Data/RecipeSources.lua: where each recipe of Data/*.lua is learned.

Where a recipe comes from (trainer, vendor, drop, quest) is not in the game client – the server
knows it. The source is ForeverDB.net's addon data, which ForeverDB publishes for reuse under
GPL-3.0 with an attribution term ("Data from ForeverDB.net (https://foreverdb.net)"):
  https://foreverdb.net/downloads/addon-manifest.json   list of the data files with SHA-256
  Data/Recipes.lua   how a recipe is learned, trainer cost, drops, quests, reputation
  Data/NPCs.lua      vendors: who sells a recipe item, for how much, and where they stand
  Data/Quest*.lua    quest titles and creature names -> IDs (ForeverDB names drops and quests in English)
Parts of it are Classic data (CMaNGOS classic-db, GPL-3.0) until players confirm them in Forever.

The addon shows vendors, drop sources and quests in the client's language. Their names are not in
the client either, so they come from Wowhead's WoW Forever tooltips (as in build_gathering.py):
  nether.wowhead.com/forever/tooltip/<npc|object|quest>/<id>?locale=<n>
and are written to Data/Names/<locale>.lua. A drop source or quest that ForeverDB only names is
matched to an ID by its English name (ForeverDB's quest data, else Wowhead's search) and only
used if Wowhead's English name for that ID is the same; otherwise the English text is kept.
Names are fetched once and then read from Tools/.cache (they don't change); delete the wh_name_*
files there to fetch them again.

Only recipes that are in Data/*.lua get an entry, so run build_data.py first after a patch.
The recipe item is taken from Data/RecipeItems.lua (game client) where the client knows it.

Nothing is written if a download is incomplete, a checksum doesn't match or the data no longer
looks as expected (too few of the addon's recipes found).

Usage:
  python3 Tools/build_sources.py              # normal run
  python3 Tools/build_sources.py --offline    # existing cache only
  python3 Tools/build_sources.py --dry-run    # check only: shows what would change
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_data  # noqa: E402

SITE = "https://foreverdb.net/"
MANIFEST_URL = SITE + "downloads/addon-manifest.json"
SOURCE_FILES = ("Data/Recipes.lua", "Data/NPCs.lua", "Data/QuestClassic.lua", "Data/QuestForever.lua",
                "Data/Quests.lua")

WOWHEAD_TOOLTIP = "https://nether.wowhead.com/forever/tooltip/{}/{}?locale={}"
WOWHEAD_SEARCH = "https://www.wowhead.com/forever/search/suggestions-template?q={}"
# Client locale -> Wowhead locale ID. esMX, enGB and ptPT use esES, enUS and ptBR (as Locales/ does).
LOCALES = {"enUS": 0, "deDE": 3, "frFR": 2, "esES": 6, "ruRU": 7, "ptBR": 8, "koKR": 1, "zhCN": 4, "zhTW": 10}
LOCALE_CONDITIONS = {"esES": 'not (GetLocale() == "esES" or GetLocale() == "esMX")',
                     "ptBR": 'not (GetLocale() == "ptBR" or GetLocale() == "ptPT")'}
NAME_KINDS = {"n": "npc", "o": "object", "q": "quest"}   # field prefix -> Wowhead tooltip type
SEARCH_TYPES = {1: "n", 2: "o"}                           # Wowhead search result type -> prefix
FETCH_THREADS = 6
# Vendors without a known faction that stand in a capital belong to its faction (uiMapID)
CAPITAL_SIDES = {1453: "A", 1455: "A", 1457: "A", 1454: "H", 1456: "H", 1458: "H"}

CREDIT_LINE = ("-- Data: ForeverDB.net (https://foreverdb.net). Reuse requires this credit "
               "(GPL-3.0 section 7(b)), see README.md.")
GENERATED_LINE = "-- Generated automatically by Tools/build_sources.py"

MAX_VENDORS = 10          # per recipe; the list in the game shows fewer anyway
MIN_MATCH = 0.9           # share of the addon's recipes ForeverDB must know, else the format changed
MIN_TRANSLATED = 0.8      # share of the names every language must have, else nothing is written
KINDS = ("Lehrer", "Händler", "Drop", "Quest", "automatisch", "nur Rezept-Item")


# ----------------------------------------------------------------------------
# Lua table literals -> Python (the data files are Lua source; they are parsed, never executed)
# ----------------------------------------------------------------------------
_TOKEN = re.compile(r'\s*(?:(--[^\n]*)|("(?:[^"\\]|\\.)*")|(-?\d+\.?\d*(?:[eE][-+]?\d+)?)|([A-Za-z_]\w*)|(\S))')
_NAMES = {"true": True, "false": False, "nil": None}


def _tokens(text):
    pos, result = 0, []
    while True:
        match = _TOKEN.match(text, pos)
        if not match:
            return result
        pos = match.end()
        comment, string, number, name, punctuation = match.groups()
        if string:
            result.append(("string", re.sub(r"\\(.)", r"\1", string[1:-1])))
        elif number:
            result.append(("number", float(number) if re.search(r"[.eE]", number) else int(number)))
        elif name:
            result.append(("name", name))
        elif punctuation:
            result.append(("punct", punctuation))


def _value(tokens, pos):
    kind, value = tokens[pos]
    if kind in ("string", "number"):
        return value, pos + 1
    if kind == "name" and value in _NAMES:
        return _NAMES[value], pos + 1
    if (kind, value) != ("punct", "{"):
        raise ValueError(f"unerwartetes Lua-Token {value!r}")
    pos += 1
    array, keyed = [], {}
    while tokens[pos] != ("punct", "}"):
        if tokens[pos] == ("punct", "["):
            key, pos = _value(tokens, pos + 1)
            if tokens[pos] != ("punct", "]") or tokens[pos + 1] != ("punct", "="):
                raise ValueError("Lua-Tabelle: ']=' erwartet")
            keyed[key], pos = _value(tokens, pos + 2)
        elif tokens[pos][0] == "name" and tokens[pos + 1] == ("punct", "="):
            keyed[tokens[pos][1]], pos = _value(tokens, pos + 2)
        else:
            item, pos = _value(tokens, pos)
            array.append(item)
        if tokens[pos] in (("punct", ","), ("punct", ";")):
            pos += 1
    if keyed:
        keyed.update({index: item for index, item in enumerate(array, 1)})
        return keyed, pos + 1
    return array, pos + 1


def lua_tables(text):
    """{name: value} for every top-level "ns.<name> = <table>" of a Lua data file."""
    starts = [(match[1], match.end()) for match in re.finditer(r"(?m)^ns\.(\w+)\s*=\s*", text)]
    result = {}
    for index, (name, start) in enumerate(starts):
        end = text.rfind("\n", 0, starts[index + 1][1]) if index + 1 < len(starts) else len(text)
        try:
            result[name] = _value(_tokens(text[start:end]), 0)[0]
        except (ValueError, IndexError) as error:
            raise ValueError(f"ns.{name}: {error}") from error
    return result


# ----------------------------------------------------------------------------
# Conversion
# ----------------------------------------------------------------------------
def clean(text):
    """Text for a "|"- and ","-separated field inside a Lua string."""
    return re.sub(r"\s+", " ", str(text).replace("|", "/").replace(",", ";")).strip()


def number(value):
    """Lua number without a trailing .0"""
    return str(int(value)) if float(value).is_integer() else str(value)


def as_list(value):
    """Lua array that the parser returned as list (or as dict, if it also had keys)."""
    if isinstance(value, dict):
        return [value[index] for index in sorted(key for key in value if isinstance(key, int))]
    return list(value or ())


def fold(name):
    return re.sub(r"\s+", " ", name).strip().casefold()


class Resolver:
    """English names of drop sources and quests -> IDs, checked against Wowhead's English name.

    creatures / quests: {folded English name: [candidate IDs]} from ForeverDB's quest data.
    names: NameSource (Wowhead), or None to keep every name as English text.
    """

    def __init__(self, creatures=None, quests=None, names=None):
        self.creatures, self.quests, self.names = creatures or {}, quests or {}, names
        self.english = {}  # (kind, id) -> English name, of every ID that is used

    def _confirmed(self, kind, candidates, name):
        """First candidate ID whose English name on Wowhead is `name` (or None)."""
        for candidate in candidates:
            found = self.names and self.names.name(kind, candidate, "enUS")
            if found and fold(found) == fold(name):
                self.english[(kind, candidate)] = found
                return candidate
        return None

    def source(self, name):
        """Drop source -> ("n" or "o", id) or None."""
        numbered = re.fullmatch(r"NPC (\d+)", name)
        if numbered:  # ForeverDB has no name for it either
            found = self.names and self.names.name("n", int(numbered[1]), "enUS")
            if found:
                self.english[("n", int(numbered[1]))] = found
                return "n", int(numbered[1])
            return None
        npc = self._confirmed("n", self.creatures.get(fold(name), ()), name)
        if npc:
            return "n", npc
        for kind, candidate in (self.names.search(name) if self.names else ()):
            if self._confirmed(kind, [candidate], name):
                return kind, candidate
        return None

    def quest(self, title):
        numbered = re.fullmatch(r"Quest (\d+)", title)
        if numbered:
            found = self.names and self.names.name("q", int(numbered[1]), "enUS")
            if found:
                self.english[("q", int(numbered[1]))] = found
                return int(numbered[1])
            return None
        return self._confirmed("q", self.quests.get(fold(title), ()), title)

    def quests_field(self, text):
        """"Title, Other Title" -> ["123", "=Other Title"]. Titles may contain commas themselves,
        so the longest run of pieces that is a known title wins. No duplicates."""
        pieces = [piece.strip() for piece in text.split(",") if piece.strip()]
        tokens, start = [], 0
        while start < len(pieces):
            for end in range(len(pieces), start, -1):
                title = ", ".join(pieces[start:end])
                quest = self.quest(title)
                if quest or end == start + 1:
                    token = str(quest) if quest else "=" + clean(title)
                    if token not in tokens:
                        tokens.append(token)
                    start = end
                    break
        return tokens

    def drops_field(self, text):
        """"Kobold Miner 2.5%, world drop (level 5-25 creatures)" -> ["n40:2.5", "w5-25"]"""
        tokens = []
        for piece in (piece.strip() for piece in text.split(",")):
            world = re.fullmatch(r"world drop \(level (\d+)-(\d+) creatures\)", piece)
            if world:
                tokens.append(f"w{world[1]}-{world[2]}")
                continue
            chance = re.search(r"\s+(\d+(?:\.\d+)?)%$", piece)
            name = piece[:chance.start()] if chance else piece
            if not name:
                continue
            found = self.source(name)
            token = f"{found[0]}{found[1]}" if found else "=" + clean(name)
            tokens.append(token + (f":{chance[1]}" if chance else ""))
        return tokens


def vendor_entries(item_ids, sold, npcs):
    """[(npc, price, limited)] for the recipe items, vendors with a known place only."""
    entries, seen = [], set()
    for item_id in item_ids:
        row = as_list(sold.get(item_id))
        for npc, price, _stack, limited in zip(row[0::4], row[1::4], row[2::4], row[3::4]):
            if npc in npcs and npc not in seen:
                seen.add(npc)
                entries.append((npc, int(price or 0), 1 if limited else 0))
    return entries[:MAX_VENDORS]


def encode_source(row, info, own_items, sold, npcs, resolver):
    """One recipe -> (encoded string or None, set of kinds, vendor NPCs).

    Fields are separated by "|", the first character names the field:
      a                          learned together with the profession
      t<copper>:<A>:<H>:<seen>   trainer: cost, trainers per side, 1 = seen at a Forever trainer
      i<item>                    recipe item
      v<npc>:<copper>:<limited>,…  vendors of the recipe item (may be empty: sold, vendor unknown)
      r<faction>                 reputation the vendor asks for
      f<amount>                  price in Merchant's Favor
      q<quest>,…                 quests that reward the recipe: quest ID, or =<English title>
      d<source>,…                drop sources: n<npc>, o<object>, w<from>-<to> (world drop from
                                 creatures of these levels) or =<English name>; n, o and = may end
                                 in :<chance in percent>
      n<count>                   drop sources in total
      x                          uncertain whether it can be obtained in Forever
    """
    learned = row[9] if len(row) > 9 and isinstance(row[9], str) else ""
    fields, kinds = [], set()
    if learned == "a":
        fields.append("a")
        kinds.add("automatisch")
    if learned == "t" or "tc" in info:
        per_side = (as_list(info.get("tn")) + [0, 0])[:2]
        fields.append(f"t{int(info.get('tc', 0))}:{int(per_side[0])}:{int(per_side[1])}:{1 if info.get('tf') else 0}")
        kinds.add("Lehrer")

    items = list(own_items)
    if learned[:1] == "i" and learned[1:].isdigit() and int(learned[1:]) not in items:
        items.append(int(learned[1:]))
    if items:
        fields.append(f"i{items[0]}")

    vendors = vendor_entries(items, sold, npcs)
    if vendors or info.get("v") or info.get("vf"):
        fields.append("v" + ",".join(f"{npc}:{price}:{limited}" for npc, price, limited in vendors))
        kinds.add("Händler")
    if info.get("rp"):
        fields.append(f"r{int(info['rp'])}")
    if info.get("fav"):
        fields.append(f"f{int(info['fav'])}")
    quests = resolver.quests_field(str(info["q"])) if info.get("q") else []
    if quests:
        fields.append("q" + ",".join(quests))
        kinds.add("Quest")
    drops = resolver.drops_field(str(info["dr"])) if info.get("dr") else []
    if drops:
        fields.append("d" + ",".join(drops))
        if info.get("dn"):
            fields.append(f"n{int(info['dn'])}")
        kinds.add("Drop")
    if items and not kinds:
        kinds.add("nur Rezept-Item")
    if not fields:
        return None, kinds, []
    if info.get("sp"):
        fields.append("x")
    return "|".join(fields), kinds, [npc for npc, _, _ in vendors]


def encode_npc(npc):
    """{name, title, map, x, y, side, seen} -> "name|uiMap|x|y|side|seen" """
    npc = as_list(npc) + [""] * 7
    name, _title, ui_map, x, y, side, seen = npc[:7]
    if side not in ("A", "H"):
        side = CAPITAL_SIDES.get(ui_map, "")
    return "|".join([clean(name), number(ui_map or 0), number(x or 0), number(y or 0), side, "1" if seen else "0"])


def name_index(*tables):
    """Tables {id: "name|…"} -> {folded name: [ids]}, earlier tables first."""
    index = {}
    for table in tables:
        for key, value in (table or {}).items():
            if isinstance(key, int) and isinstance(value, str):
                ids = index.setdefault(fold(value.split("|", 1)[0]), [])
                if key not in ids:
                    ids.append(key)
    return index


def quest_index(texts):
    """ForeverDB's quest files -> ({creature name: [ids]}, {quest title: [ids]})"""
    classic = lua_tables(texts.get("Data/QuestClassic.lua", ""))
    forever = lua_tables(texts.get("Data/QuestForever.lua", ""))
    found = {}
    for row in as_list(lua_tables(texts.get("Data/Quests.lua", "")).get("newQuests")):
        row = as_list(row)
        if len(row) > 1 and isinstance(row[0], int) and isinstance(row[1], str):
            found[row[0]] = row[1]
    return (name_index(classic.get("qcNpc")),
            name_index(forever.get("qfQuests"), found, classic.get("qcQuests")))


def build(recipes_text, npcs_text, own_recipes, own_recipe_items, resolver=None):
    """-> (sources {spell: string}, npcs {npc: string}, stats {profession file: {kind: count}}, matched)."""
    resolver = resolver or Resolver()
    recipe_tables, npc_tables = lua_tables(recipes_text), lua_tables(npcs_text)
    for name, tables in (("recipes", recipe_tables), ("recipeInfo", recipe_tables),
                         ("npcs", npc_tables), ("sold", npc_tables)):
        if not isinstance(tables.get(name), dict):
            raise ValueError(f"ns.{name} fehlt in den ForeverDB-Daten (Format geändert?)")
    rows = {}
    for profession_rows in recipe_tables["recipes"].values():
        for row in as_list(profession_rows):
            row = as_list(row)
            if row and isinstance(row[0], int):
                rows[row[0]] = row
    info, sold, npcs = recipe_tables["recipeInfo"], npc_tables["sold"], npc_tables["npcs"]

    items_by_spell = {}
    for item_id, spell_id in sorted(own_recipe_items.items()):
        items_by_spell.setdefault(spell_id, []).append(item_id)

    sources, used_npcs, stats, matched = {}, set(), {}, 0
    for spell_id, file_name in sorted(own_recipes.items()):
        counts = stats.setdefault(file_name, {kind: 0 for kind in KINDS + ("unbekannt", "Rezepte")})
        counts["Rezepte"] += 1
        row = rows.get(spell_id)
        matched += row is not None
        encoded, kinds, vendors = encode_source(row or [], info.get(spell_id) or {},
                                                items_by_spell.get(spell_id, ()), sold, npcs, resolver)
        if encoded:
            sources[spell_id] = encoded
            used_npcs.update(vendors)
        for kind in kinds or ("unbekannt",):
            counts[kind] += 1
    return sources, {npc: encode_npc(npcs[npc]) for npc in sorted(used_npcs)}, stats, matched


def referenced_ids(sources, npcs):
    """Everything the addon needs a name for: {(kind, id)} with kind n (npc), o (object), q (quest)."""
    ids = {("n", npc) for npc in npcs}
    for encoded in sources.values():
        for field in encoded.split("|"):
            if field[:1] == "d":
                ids.update((kind, int(number_)) for kind, number_ in re.findall(r"(?:^d|,)([no])(\d+)", field))
            elif field[:1] == "q":
                ids.update(("q", int(token)) for token in field[1:].split(",") if token.isdigit())
    return ids


# ----------------------------------------------------------------------------
# Names from Wowhead (cached for good: a creature's name doesn't change)
# ----------------------------------------------------------------------------
class NameSource:
    def __init__(self, cache_dir, offline):
        self.cache_dir, self.offline = cache_dir, offline
        self.failed = 0  # requests that failed (not: pages that don't exist)
        os.makedirs(cache_dir, exist_ok=True)

    def _get(self, url, key):
        """Body of the page, "" if it doesn't exist, None if it couldn't be fetched."""
        path = os.path.join(self.cache_dir, key)
        if os.path.exists(path):
            with open(path, encoding="utf8") as f:
                return f.read()
        if self.offline:
            self.failed += 1
            return None
        try:
            request = urllib.request.Request(url, headers={"User-Agent": build_data.USER_AGENT})
            body = build_data.urlopen(request).read().decode("utf8")
        except urllib.error.HTTPError as error:
            if error.code != 404:
                self.failed += 1
                return None
            body = ""
        except (OSError, UnicodeDecodeError, ValueError):
            self.failed += 1
            return None
        temp = f"{path}.{os.getpid()}.{id(body)}.tmp"
        with open(temp, "w", encoding="utf8") as f:
            f.write(body)
        os.replace(temp, path)
        return body

    def name(self, kind, id_, locale):
        body = self._get(WOWHEAD_TOOLTIP.format(NAME_KINDS[kind], id_, LOCALES[locale]),
                         f"wh_name_{kind}{id_}_{LOCALES[locale]}")
        try:
            name = json.loads(body).get("name") if body else None
        except (ValueError, AttributeError):
            return None
        return name.strip() if isinstance(name, str) and name.strip() else None

    def search(self, name):
        """[(kind, id)] of the NPCs and objects called exactly `name`."""
        key = "wh_search_" + hashlib.sha1(fold(name).encode("utf8")).hexdigest()[:16]
        body = self._get(WOWHEAD_SEARCH.format(urllib.parse.quote_plus(name)), key)
        try:
            results = json.loads(body).get("results", []) if body else []
        except (ValueError, AttributeError):
            return []
        return [(SEARCH_TYPES[result["type"]], result["id"]) for result in results
                if isinstance(result, dict) and result.get("type") in SEARCH_TYPES
                and isinstance(result.get("id"), int) and fold(str(result.get("name", ""))) == fold(name)]

    def all_names(self, ids):
        """{locale: {(kind, id): name}} for every language; missing names are left out."""
        jobs = [(kind, id_, locale) for kind, id_ in sorted(ids) for locale in LOCALES]
        with concurrent.futures.ThreadPoolExecutor(FETCH_THREADS) as pool:
            names = list(pool.map(lambda job: self.name(*job), jobs))
        result = {locale: {} for locale in LOCALES}
        for (kind, id_, locale), name in zip(jobs, names):
            if name:
                result[locale][(kind, id_)] = name
        return result


# ----------------------------------------------------------------------------
# Download
# ----------------------------------------------------------------------------
def fetch_sources(web):
    """-> ({path: text}, data version). Exits if a file is missing or its checksum is wrong."""
    manifest_text = web.get(MANIFEST_URL, "fdb_addon_manifest.json")
    if manifest_text is None:
        sys.exit("ForeverDB-Dateiliste (addon-manifest.json) nicht erreichbar und nicht im Cache.")
    try:
        data = json.loads(manifest_text)["data"]
        files = {entry["path"]: entry for entry in data["files"]}
    except (ValueError, KeyError, TypeError):
        sys.exit("ForeverDB-Dateiliste hat ein unerwartetes Format.")
    texts = {}
    for path in SOURCE_FILES:
        entry = files.get(path)
        if not entry:
            sys.exit(f"{path} steht nicht mehr in der ForeverDB-Dateiliste.")
        text = web.get(SITE + entry["url"], "fdb_addon_" + os.path.basename(path))
        if text is None:
            sys.exit(f"{path} nicht erreichbar und nicht im Cache – später erneut ausführen.")
        if hashlib.sha256(text.encode("utf8")).hexdigest() != entry.get("sha256"):
            sys.exit(f"{path}: Prüfsumme passt nicht zur Dateiliste (unvollständiger Download oder "
                     "veralteter Cache) – später erneut ausführen. Es wurde nichts geschrieben.")
        texts[path] = text
    return texts, str(data.get("version", "?"))


# ----------------------------------------------------------------------------
# Output
# ----------------------------------------------------------------------------
def output_lines(sources, npcs, version):
    lines = [
        "-- Data/RecipeSources.lua",
        CREDIT_LINE,
        f"{GENERATED_LINE} from ForeverDB's addon data ({version}).",
        "-- Do not edit by hand; run the script again instead.",
        "-- Parts are Classic data (CMaNGOS classic-db, GPL-3.0) until players confirm them in Forever.",
        "local _, ns = ...",
        "",
        "-- [spellID] = \"field|field|…\", the first character names the field:",
        "--   a automatic, t<copper>:<trainers A>:<trainers H>:<seen in Forever>, i<recipe item>,",
        "--   v<npc>:<copper>:<limited>,… vendors, r<faction> reputation, f<Merchant's Favor>,",
        "--   q<quest ID or =English title>,…  d<drop source>,… with n<npc>, o<object>,",
        "--   w<from>-<to> (world drop, creature levels) or =<English name>, each optionally",
        "--   :<chance in percent>; n<drop sources in total>, x uncertain in Forever.",
        "--   Names of NPCs, objects and quests: Data/Names/<locale>.lua",
        "ns.RegisterRecipeSources({",
    ]
    for spell_id, encoded in sorted(sources.items()):
        lines.append(f"    [{spell_id}] = {build_data.lua_string(encoded)},")
    lines += ["})", "", "-- [npc] = \"name|uiMapID|x|y|side (A/H/empty)|seen in Forever\"",
              "ns.RegisterSourceNPCs({"]
    for npc, encoded in sorted(npcs.items()):
        lines.append(f"    [{npc}] = {build_data.lua_string(encoded)},")
    lines.append("})")
    return lines


def names_lines(locale, names):
    """Data/Names/<locale>.lua: the names of one language ({(kind, id): name})."""
    lines = [
        f"-- Data/Names/{locale}.lua",
        f"{GENERATED_LINE}: names of vendors, drop sources and quests",
        "-- from Wowhead's WoW Forever tooltips (wowhead.com). Do not edit by hand.",
    ]
    if locale != "enUS":
        condition = LOCALE_CONDITIONS.get(locale, f'GetLocale() ~= "{locale}"')
        lines.append(f"if {condition} then return end")
    lines += ["local _, ns = ...", "", "-- n = NPCs, o = objects, q = quests: [ID] = name", "ns.RegisterSourceNames({"]
    for kind in sorted(NAME_KINDS):
        lines.append(f"    {kind} = {{")
        for (_, id_), name in sorted((key, name) for key, name in names.items() if key[0] == kind):
            lines.append(f"        [{id_}] = {build_data.lua_string(name)},")
        lines.append("    },")
    lines.append("})")
    return lines


def read_existing(path):
    """Existing file -> ({spell: string}, {npc: string})"""
    if not os.path.exists(path):
        return {}, {}
    with open(path, encoding="utf8") as f:
        text = f.read()
    parts = text.split("ns.RegisterSourceNPCs(", 1)
    entry = re.compile(r'(?m)^\s*\[(\d+)\] = "((?:[^"\\]|\\.)*)",')
    return tuple({int(key): build_data.lua_unescape(value) for key, value in entry.findall(part)}
                 for part in (parts[0], parts[1] if len(parts) > 1 else ""))


def count_changes(old, new):
    return (len(set(new) - set(old)), len(set(old) - set(new)),
            sum(1 for key in set(old) & set(new) if old[key] != new[key]))


def print_report(stats, version, sources, npcs, old_sources, old_npcs, dry_run):
    bold, dim, green, yellow = build_data.bold, build_data.dim, build_data.green, build_data.yellow
    print(bold("Profession Tooltip – Bezugsquellen der Rezepte"
               + (" (Testlauf, es wird nichts geschrieben)" if dry_run else "")))
    print(dim("═" * 78))
    print(f"  {'Quelle':14} ForeverDB.net, Addon-Daten {version}")
    build_data.heading("Bezugsquellen pro Beruf")
    print(dim(f"  {'Beruf':18} {'Rezepte':>7} {'Lehrer':>7} {'Händler':>8} {'Drop':>6} {'Quest':>6} "
              f"{'autom.':>7} {'nur Item':>9} {'unbekannt':>10}"))
    total = {}
    for file_name, counts in stats.items():
        unknown = counts["unbekannt"]
        print(f"  {build_data.DISPLAY_NAMES.get(file_name, file_name):18} {counts['Rezepte']:>7} "
              f"{counts['Lehrer']:>7} {counts['Händler']:>8} {counts['Drop']:>6} {counts['Quest']:>6} "
              f"{counts['automatisch']:>7} {counts['nur Rezept-Item']:>9} "
              f"{(yellow if unknown else str)(f'{unknown:>10}')}")
        for kind, count in counts.items():
            total[kind] = total.get(kind, 0) + count
    print(dim("  " + "─" * 86))
    print(bold(f"  {'Summe':18} {total.get('Rezepte', 0):>7} {total.get('Lehrer', 0):>7} "
               f"{total.get('Händler', 0):>8} {total.get('Drop', 0):>6} {total.get('Quest', 0):>6} "
               f"{total.get('automatisch', 0):>7} {total.get('nur Rezept-Item', 0):>9} "
               f"{total.get('unbekannt', 0):>10}"))
    print(dim("  Ein Rezept kann mehrere Quellen haben. „nur Item“: das Rezept-Item ist bekannt, "
              "seine Herkunft nicht."))

    build_data.heading("Änderungen gegenüber den vorhandenen Daten")
    changes = 0
    for label, old, new in (("Rezepte", old_sources, sources), ("Händler-NPCs", old_npcs, npcs)):
        added, removed, changed = count_changes(old, new)
        changes += added + removed + changed
        print(f"  {label:14} {len(new):>5} Einträge   {added} neu, {removed} entfernt, {changed} geändert")
    print()
    if changes == 0:
        print("  " + green("✔ Keine Änderungen – die Daten sind aktuell."))
    elif dry_run:
        print("  " + yellow(f"➜ {changes} Änderung(en) – ohne --dry-run ausführen, um sie zu übernehmen."))
    else:
        print("  " + yellow(f"➜ {changes} Änderung(en) übernommen – Data/RecipeSources.lua wurde aktualisiert."))
    print()


def main():
    tools_dir = os.path.dirname(os.path.abspath(__file__))
    data_dir = os.path.join(os.path.dirname(tools_dir), "Data")
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--cache", default=os.path.join(tools_dir, ".cache"))
    parser.add_argument("--offline", action="store_true", help="keine Web-Zugriffe (nur der Cache)")
    parser.add_argument("--dry-run", action="store_true", help="nur prüfen und berichten, keine Dateien schreiben")
    args = parser.parse_args()

    own_recipes = {}
    for file_name, _ in build_data.PROFESSIONS.values():
        for spell_id in build_data.read_data_file(os.path.join(data_dir, file_name + ".lua")):
            own_recipes[spell_id] = file_name
    if not own_recipes:
        sys.exit("Keine Rezepte in Data/*.lua gefunden – zuerst Tools/build_data.py ausführen.")
    own_recipe_items = build_data.read_recipe_items(os.path.join(data_dir, "RecipeItems.lua"))

    print(build_data.dim("Lade ForeverDB-Addon-Daten …"), flush=True)
    texts, version = fetch_sources(build_data.WebCache(args.cache, args.offline))
    name_source = NameSource(args.cache, args.offline)
    print(build_data.dim("Ordne Drop-Quellen und Quests zu, lade Namen von Wowhead "
                         "(beim ersten Lauf einige Minuten) …"), flush=True)
    try:
        creatures, quests = quest_index(texts)
        sources, npcs, stats, matched = build(texts["Data/Recipes.lua"], texts["Data/NPCs.lua"],
                                              own_recipes, own_recipe_items,
                                              Resolver(creatures, quests, name_source))
    except ValueError as error:
        sys.exit(f"ForeverDB-Daten nicht lesbar: {error}. Es wurde nichts geschrieben.")
    if matched < MIN_MATCH * len(own_recipes):
        sys.exit(f"ForeverDB kennt nur {matched} von {len(own_recipes)} Rezepten – das Datenformat hat sich "
                 "vermutlich geändert. Es wurde nichts geschrieben.")

    ids = referenced_ids(sources, npcs)
    names = name_source.all_names(ids)
    if name_source.failed:
        sys.exit(f"{name_source.failed} Namensabfrage(n) bei Wowhead fehlgeschlagen – später erneut ausführen "
                 "(bereits geladene Namen bleiben im Cache). Es wurde nichts geschrieben.")
    poor = [locale for locale in LOCALES if len(names[locale]) < MIN_TRANSLATED * len(ids)]
    if poor:
        sys.exit(f"Zu wenige Namen für {', '.join(poor)} erhalten. Es wurde nichts geschrieben.")

    path = os.path.join(data_dir, "RecipeSources.lua")
    old_sources, old_npcs = read_existing(path)
    names_changed = []
    if not args.dry_run:
        build_data.write_if_changed(path, output_lines(sources, npcs, version), GENERATED_LINE)
        os.makedirs(os.path.join(data_dir, "Names"), exist_ok=True)
        for locale in LOCALES:
            if build_data.write_if_changed(os.path.join(data_dir, "Names", locale + ".lua"),
                                           names_lines(locale, names[locale]), GENERATED_LINE):
                names_changed.append(locale)
    print_report(stats, version, sources, npcs, old_sources, old_npcs, args.dry_run)
    english_only = sum(len(re.findall(r"(?:^[dq]|,)=", field)) for encoded in sources.values()
                       for field in encoded.split("|") if field[:1] in ("d", "q"))
    print(f"  Namen: {len(ids)} NPCs, Objekte und Quests; je Sprache: "
          + ", ".join(f"{locale} {len(names[locale])}" for locale in LOCALES))
    print(f"  Ohne ID (bleiben englisch): {english_only} Angaben")
    if names_changed:
        print(f"  Data/Names aktualisiert: {', '.join(names_changed)}")
    print()


if __name__ == "__main__":
    main()
