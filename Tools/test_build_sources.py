"""Offline regression tests: python3 -m unittest discover -s Tools -p 'test_*.py'."""
from pathlib import Path
import tempfile
import unittest

import build_data
import build_sources

RECIPES = '''-- Data: ForeverDB.net (https://foreverdb.net), build test.
local _, ns = ...
-- [profession] = {{spell, name, ...}}
ns.recipes = {Alchemy={{1,"Trainer Potion",50,55,75,95,20,1,"10:2","t",0,0,1},{2,"Vendor \\"Elixir\\"",150,160,170,180,21,1,"10:1","i500",0,0,0},{3,"Drop Draught",60,90,110,130,22,1,"11:1","i501",0,0,0}},["First Aid"]={{4,"Bandage",1,30,45,60,23,1,"12:1","a",0,1,0},{5,"Quest Tonic",0,0,0,0,24,1,"12:1","i502",0,0,0},{6,"Odd One",0,0,0,0,25,1,"12:1","",0,0,0}}}
ns.names = {[10]="Herb"}
ns.recipeInfo = {[1]={tc=150,tf=1,tn={7,5}},[2]={v=3,rp=529,fav=45,sp="sod"},[3]={dr="Kobold Miner, Rot | Hide Gnoll",dn=11},[5]={tc=10,tn={0,1},q="Wild Eyes"}}
'''
NPCS = '''-- Data: ForeverDB.net (https://foreverdb.net), build test.
local _, ns = ...
ns.npcs = {[900]={"Alliance Alchemist","Alchemy Supplies",1453,55.5,61,"A",1},[901]={"Horde Herbalist","",1454,46,45.8,"H",0},[902]={"Neutral Trader","",1434,28.2,74.5,"",1}}
ns.sold = {[500]={900,1200,1,1,901,1200,1,0,999,5,1,0},[777]={902,800,1,0}}
ns.soldNames = {[500]="Recipe: Vendor Elixir"}
'''
OWN = {1: "Alchemy", 2: "Alchemy", 3: "Alchemy", 4: "FirstAid", 5: "FirstAid", 6: "FirstAid", 7: "FirstAid"}


class LuaTableTests(unittest.TestCase):
    def test_arrays_keys_strings_and_numbers(self):
        tables = build_sources.lua_tables(
            'ns.a = {1, -2.5, "x\\"y", {k=1, ["two words"]=2, [3]={}}, true} -- comment\nns.b = {[5]="five"}\n')
        self.assertEqual(tables["a"], [1, -2.5, 'x"y', {"k": 1, "two words": 2, 3: []}, True])
        self.assertEqual(tables["b"], {5: "five"})

    def test_mixed_table_keeps_array_part_under_its_indexes(self):
        self.assertEqual(build_sources.lua_tables("ns.t = {7, 8, n=2}\n")["t"], {"n": 2, 1: 7, 2: 8})

    def test_broken_table_is_reported_not_guessed(self):
        with self.assertRaises(ValueError):
            build_sources.lua_tables("ns.t = {1, 2\n")
        with self.assertRaises(ValueError):
            build_sources.lua_tables("ns.t = {function() end}\n")


class BuildTests(unittest.TestCase):
    def setUp(self):
        # Recipe 3's item comes from the game client (RecipeItems.lua), 777 is a second item for recipe 2
        self.sources, self.npcs, self.stats, self.matched = build_sources.build(
            RECIPES, NPCS, OWN, {601: 3, 777: 2})

    def test_every_kind_is_encoded(self):
        self.assertEqual(self.sources[1], "t150:7:5:1")
        self.assertEqual(self.sources[2], "i777|v902:800:0,900:1200:1,901:1200:0|r529|f45|x")
        # Without a name source nothing is matched to an ID: the English names are kept
        self.assertEqual(self.sources[3], "i601|d=Kobold Miner,=Rot / Hide Gnoll|n11")
        self.assertEqual(self.sources[4], "a")
        self.assertEqual(self.sources[5], "t10:0:1:0|i502|q=Wild Eyes")

    def test_recipes_without_any_information_get_no_entry(self):
        self.assertNotIn(6, self.sources)  # known to ForeverDB, nothing about its origin
        self.assertNotIn(7, self.sources)  # not known to ForeverDB
        self.assertEqual(self.matched, 6)
        self.assertEqual(self.stats["FirstAid"]["unbekannt"], 2)

    def test_only_vendors_with_a_known_place_are_kept(self):
        self.assertEqual(sorted(self.npcs), [900, 901, 902])  # 999 has no NPC entry
        self.assertEqual(self.npcs[900], "Alliance Alchemist|1453|55.5|61|A|1")
        self.assertEqual(self.npcs[902], "Neutral Trader|1434|28.2|74.5||1")

    def test_vendor_without_a_faction_in_a_capital_belongs_to_its_faction(self):
        self.assertEqual(build_sources.encode_npc(["Wulmort Jinglepocket", "", 1455, 33.7, 67.2, "", 0]),
                         "Wulmort Jinglepocket|1455|33.7|67.2|A|0")
        self.assertEqual(build_sources.encode_npc(["Kithas", "", 1454, 53.9, 38, "", 1]).split("|")[4], "H")
        self.assertEqual(build_sources.encode_npc(["Zixil", "", 1424, 50, 50, "", 1]).split("|")[4], "")
        self.assertEqual(build_sources.encode_npc(["Spy", "", 1455, 1, 1, "H", 1]).split("|")[4], "H")

    def test_statistics_count_each_kind(self):
        alchemy = self.stats["Alchemy"]
        self.assertEqual((alchemy["Rezepte"], alchemy["Lehrer"], alchemy["Händler"], alchemy["Drop"]), (3, 1, 1, 1))
        self.assertEqual(self.stats["FirstAid"]["automatisch"], 1)

    def test_changed_format_is_an_error(self):
        with self.assertRaises(ValueError):
            build_sources.build("ns.recipes = {}\n", NPCS, OWN, {})

    def test_vendor_list_is_limited(self):
        sold = {1: [n for npc in range(1, 40) for n in (npc, 10, 1, 0)]}
        npcs = {npc: ["N", "", 1, 0, 0, "", 1] for npc in range(1, 40)}
        self.assertEqual(len(build_sources.vendor_entries([1], sold, npcs)), build_sources.MAX_VENDORS)

    def test_output_round_trip_and_unchanged_data_is_not_rewritten(self):
        with tempfile.TemporaryDirectory() as directory:
            path = str(Path(directory) / "RecipeSources.lua")
            lines = build_sources.output_lines(self.sources, self.npcs, "v1")
            self.assertTrue(lines[1].startswith("-- Data: ForeverDB.net (https://foreverdb.net)"))
            self.assertTrue(build_data.write_if_changed(path, lines, build_sources.GENERATED_LINE))
            self.assertEqual(build_sources.read_existing(path), (self.sources, self.npcs))
            newer = build_sources.output_lines(self.sources, self.npcs, "v2")
            self.assertFalse(build_data.write_if_changed(path, newer, build_sources.GENERATED_LINE))
            self.assertEqual(build_sources.count_changes(self.sources, self.sources), (0, 0, 0))


class FakeNames:
    """Stands in for Wowhead: English names by (kind, id) and search results by name."""
    NAMES = {("n", 40): "Kobold Miner", ("n", 41): "Kobold Digger", ("n", 3128): "Kul Tiras Sailor",
             ("o", 2843): "Battered Chest", ("n", 250627): "Camp Raider", ("q", 700): "Wild Eyes, Wild Hearts",
             ("q", 701): "Liquid Stone", ("q", 95217): "This Is Spinal Axe", ("n", 77): "Renamed in Forever"}
    SEARCH = {"kul tiras sailor": [("n", 3128)], "battered chest": [("n", 9), ("o", 2843)]}

    def name(self, kind, id_, locale):
        name = self.NAMES.get((kind, id_))
        return name and (name if locale == "enUS" else f"{locale}:{name}")

    def search(self, name):
        return self.SEARCH.get(name.casefold(), [])


class ResolverTests(unittest.TestCase):
    def setUp(self):
        self.resolver = build_sources.Resolver(
            {"kobold miner": [39, 40], "old name": [77]},
            {"wild eyes, wild hearts": [700], "liquid stone": [701]}, FakeNames())

    def test_drops_are_matched_by_name_and_checked_against_the_english_name(self):
        tokens = self.resolver.drops_field(
            "Kobold Miner 2.56%, Kul Tiras Sailor, Battered Chest 0.5%, world drop (level 5-25 creatures), "
            "NPC 250627, NPC 999, Old Name, Unknown, Beast 1%")
        self.assertEqual(tokens, ["n40:2.56", "n3128", "o2843:0.5", "w5-25", "n250627", "=NPC 999",
                                  "=Old Name", "=Unknown", "=Beast:1"])
        self.assertEqual(self.resolver.english[("n", 40)], "Kobold Miner")
        self.assertNotIn(("n", 77), self.resolver.english)  # the ID's name differs: not trusted

    def test_quest_titles_with_commas_and_duplicates(self):
        self.assertEqual(self.resolver.quests_field("Wild Eyes, Wild Hearts"), ["700"])
        self.assertEqual(self.resolver.quests_field("Liquid Stone, Liquid Stone"), ["701"])
        self.assertEqual(self.resolver.quests_field("Klaven's Tower, Wild Eyes, Wild Hearts, Quest 95217, Quest 1"),
                         ["=Klaven's Tower", "700", "95217", "=Quest 1"])

    def test_ids_and_name_files(self):
        sources, npcs, _, _ = build_sources.build(RECIPES.replace("Rot | Hide Gnoll", "NPC 250627"), NPCS, OWN,
                                                  {601: 3}, self.resolver)
        self.assertEqual(sources[3], "i601|dn40,n250627|n11")
        ids = build_sources.referenced_ids(sources, npcs)
        self.assertEqual(ids, {("n", 900), ("n", 901), ("n", 40), ("n", 250627)})
        names = {key: FakeNames().name(key[0], key[1], "deDE") for key in ids if key in FakeNames.NAMES}
        lines = build_sources.names_lines("deDE", names)
        self.assertIn('if GetLocale() ~= "deDE" then return end', lines)
        self.assertIn('        [40] = "deDE:Kobold Miner",', lines)
        self.assertNotIn("return end", "\n".join(build_sources.names_lines("enUS", names)))
        self.assertIn('GetLocale() == "esMX"', "\n".join(build_sources.names_lines("esES", names)))

    def test_name_index_prefers_earlier_tables(self):
        index = build_sources.name_index({5: "Title|x"}, {6: "title|y", 5: "Title|x"})
        self.assertEqual(index["title"], [5, 6])


class VendorPricesTests(unittest.TestCase):
    def test_extracts_unlimited_multi_vendor_reagents_with_unit_price(self):
        npcs_lua = '''-- test
local _, ns = ...
ns.npcs = {[10]={"A","",1453,0,0,"A",1},[11]={"B","",1454,0,0,"H",1},[12]={"C","",1455,0,0,"A",1}}
ns.sold = {
    [3371] = {10, 20, 5, 0, 11, 20, 5, 0},          -- Empty Vial: 2 unlimited vendors, 20c / 5 = 4c
    [2678] = {10, 10, 5, 0, 11, 10, 5, 1, 12, 10, 5, 0}, -- Mild Spices: 2 unlimited (11 is limited) -> 2c
    [13468] = {10, 500000, 1, 0},                    -- Black Lotus: single vendor -> excluded
    [7001] = {10, 50, 1, 1, 11, 50, 1, 1},           -- limited only -> excluded
    [7002] = {10, 50, 1, 0, 999, 50, 1, 0},          -- 999 not in npcs -> only 1 known vendor -> excluded
    [7003] = {10, 100, 1, 0, 11, 100, 1, 0},         -- not in reagent_ids -> excluded
}
'''
        prices = build_sources.vendor_reagent_prices(npcs_lua, {3371, 2678, 13468, 7001, 7002})
        self.assertEqual(prices, {3371: 4, 2678: 2})

    def test_vendor_prices_round_trip_and_credit_line(self):
        prices = {2678: 2, 3371: 4}
        with tempfile.TemporaryDirectory() as directory:
            path = str(Path(directory) / "VendorPrices.lua")
            lines = build_sources.vendor_prices_lines(prices, "v1")
            self.assertTrue(lines[1].startswith("-- Data: ForeverDB.net (https://foreverdb.net)"))
            self.assertTrue(build_data.write_if_changed(path, lines, build_sources.GENERATED_LINE))
            self.assertEqual(build_sources.read_vendor_prices(path), prices)
            newer = build_sources.vendor_prices_lines(prices, "v2")
            self.assertFalse(build_data.write_if_changed(path, newer, build_sources.GENERATED_LINE))


if __name__ == "__main__":
    unittest.main()
