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
        # Trainers per side only as 1/0, vendors in a fixed order
        self.assertEqual(self.sources[1], "t150:1:1:1")
        self.assertEqual(self.sources[2], "i777|v900:1200:1,901:1200:0,902:800:0|r529|f45|x")
        # 11 drop sources: a world drop, the 3 named ones are not kept
        self.assertEqual(self.sources[3], "i601|W")
        self.assertEqual(self.sources[4], "a")
        self.assertEqual(self.sources[5], "t10:0:1:0|i502|q=Wild Eyes")

    def test_few_drop_sources_are_named(self):
        # Without a name source nothing is matched to an ID: the English names are kept
        text = RECIPES.replace("dn=11", "dn=3")
        sources = build_sources.build(text, NPCS, OWN, {601: 3})[0]
        self.assertEqual(sources[3], "i601|d=Kobold Miner,=Rot / Hide Gnoll|n3")

    def test_drops_have_a_fixed_order(self):
        tokens = ["n9319", "w19-50", "n7805:8.08", "=Odd", "n12203", "n5623:6.26", "o2843"]
        self.assertEqual(sorted(tokens, key=build_sources.drop_order),
                         ["n7805:8.08", "n5623:6.26", "=Odd", "n9319", "n12203", "o2843", "w19-50"])

    def test_world_drop_needs_many_sources_without_a_drop_chance(self):
        self.assertTrue(build_sources.is_world_drop("A, B, C", 4))
        self.assertFalse(build_sources.is_world_drop("A, B, C", 3))
        self.assertFalse(build_sources.is_world_drop("A 2.5%, B, C", 20))  # Classic data with chances
        self.assertFalse(build_sources.is_world_drop("world drop (level 5-25 creatures)", 20))
        self.assertTrue(build_sources.is_world_drop("A, B, C, D", None))

    def test_vendors_keep_their_place_unless_they_really_moved(self):
        old = {1: "Vharr|1434|32.3|28|H|1", 2: "Far|1434|10|10||0", 3: "Map|1434|5|5||1"}
        new = {1: "Vharr|1434|32.4|27.9|H|1", 2: "Far|1434|12.5|10||1", 3: "Map|1435|5|5||1", 4: "New|1|2|3||1"}
        self.assertEqual(build_sources.keep_npc_places(new, old), {
            1: "Vharr|1434|32.3|28|H|1", 2: "Far|1434|12.5|10||1", 3: "Map|1435|5|5||1", 4: "New|1|2|3||1"})

    def test_discounted_trainer_costs_are_reported(self):
        old = {1: "t4500:1:1:1", 2: "t1000:1:0:1", 3: "t500:1:1:1", 4: "t300:1:1:1"}
        new = {1: "t5000:1:1:1", 2: "t1111:1:0:1", 3: "t500:1:1:1", 4: "t400:1:1:1", 5: "t2778:0:1:1|i9",
               6: "t2880:1:1:1", 7: "t4250:1:1:1", 8: "t4500:1:1:1", 9: "t115:1:1:1"}
        found = {(spell, reason.split()[0]) for spell, _, _, reason in
                 build_sources.suspicious_trainer_costs(new, old)}
        self.assertEqual(found, {(1, "Ruf-Rabatt?"), (2, "Ruf-Rabatt?"), (2, "unrunder"), (5, "unrunder"),
                                 (6, "unrunder")})

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
        sources, npcs, _, _ = build_sources.build(RECIPES.replace("Rot | Hide Gnoll", "NPC 250627").replace("dn=11", "dn=3"), NPCS, OWN,
                                                  {601: 3}, self.resolver)
        self.assertEqual(sources[3], "i601|dn40,n250627|n3")
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


class FactionTests(unittest.TestCase):
    TOOLTIP = ('{"name":"Vharr","tooltip":"<table><tr><td><b class=\\"q\\">Vharr</b></td></tr>'
               '<tr><td>Superior Weaponsmith</td></tr><tr><td>Level 40 Humanoid (Normal)</td></tr>'
               '<tr><td>Orgrimmar</td></tr></table>"}')
    NO_FACTION = ('{"name":"Vendor-Tron 1000","tooltip":"<table><tr><td>Vendor-Tron 1000</td></tr>'
                  '<tr><td>Level 38 Humanoid (Normal)</td></tr></table>"}')
    SEARCH = '{"results":[{"type":7,"id":1637,"name":"Orgrimmar"},{"type":8,"id":76,"name":"Orgrimmar"}]}'

    def test_faction_from_the_tooltip_row_after_the_level(self):
        import hashlib
        with tempfile.TemporaryDirectory() as directory:
            (Path(directory) / "wh_name_n1146_0").write_text(self.TOOLTIP, encoding="utf8")
            (Path(directory) / "wh_name_n12245_0").write_text(self.NO_FACTION, encoding="utf8")
            key = "wh_search_" + hashlib.sha1(b"orgrimmar").hexdigest()[:16]
            (Path(directory) / key).write_text(self.SEARCH, encoding="utf8")
            names = build_sources.NameSource(directory, offline=True)
            self.assertEqual(names.factions({1146, 12245}), {1146: 76})
            self.assertEqual(names.failed, 0)

    def test_vendor_strings_and_trainer_factions(self):
        npcs = {1146: "Vharr|1434|32.3|28|H|1", 12245: "Vendor-Tron 1000|1443|40|60||1|9"}
        self.assertEqual(build_sources.add_factions(npcs, {1146: 76}),
                         {1146: "Vharr|1434|32.3|28|H|1|76", 12245: "Vendor-Tron 1000|1443|40|60||1|"})
        text = "ns.profTrainers = {Alchemy={1,2,3},[\"First Aid\"]={4},Unknown={1}}\n"
        self.assertEqual(build_sources.trainer_factions(text, {1: 76, 2: 72, 3: 76, 4: 81}),
                         {171: "72,76", 129: "81"})
        self.assertEqual(build_sources.trainer_npcs(text), {1, 2, 3, 4})

    def test_trainer_factions_are_written_and_not_read_as_vendors(self):
        with tempfile.TemporaryDirectory() as directory:
            path = str(Path(directory) / "RecipeSources.lua")
            npcs = {1146: "Vharr|1434|32.3|28|H|1|76"}
            lines = build_sources.output_lines({1: "t100:1:1:1"}, npcs, "v1", {171: "72,76"})
            self.assertIn("ns.RegisterTrainerFactions({", lines)
            self.assertIn('    [171] = "72,76",', lines)
            build_data.write_if_changed(path, lines, build_sources.GENERATED_LINE)
            self.assertEqual(build_sources.read_existing(path), ({1: "t100:1:1:1"}, npcs))


class DiscountTests(unittest.TestCase):
    SV = '''ProfessionTooltipDB = {
["trainerSkills"] = {
[2153] = 50,
},
["discountSeen"] = {
["v1146:2532"] = "6:0.90",
["v1146:2533"] = "6:0.90",
["t3365:2153"] = "6:0.897",
["v3005:4355"] = "5:1.00",
["v12:1"] = "7:0.85",
["v12:2"] = "7:0.85",
["v12:3"] = "7:0.85",
["v12:4"] = "7:0.85",
["v12:5"] = "7:0.85",
["v12:6"] = "7:1.11",
["v99:1"] = "8:0.30",
},
}
'''

    def test_observations_are_read_and_bucketed(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "ProfessionTooltip.lua"
            path.write_text(self.SV, encoding="utf8")
            counts, files = build_sources.discount_observations([str(path), str(Path(directory) / "missing.lua")])
        self.assertEqual(files, 1)
        # 0.897 (a trainer rounds down) is 90 %, 1.11 and 0.30 are left out
        self.assertEqual(counts, {6: {90: 3}, 5: {100: 1}, 7: {85: 5}})

    def test_discounts_need_enough_agreeing_observations(self):
        discounts, sources = build_sources.derive_discounts({6: {90: 3}, 5: {100: 1}, 7: {85: 5}}, {})
        self.assertEqual(discounts, {4: 100, 5: 100, 6: 90, 7: 85, 8: 90})
        self.assertTrue(sources[7].startswith("beobachtet"))
        self.assertIn("zu wenig", sources[6])
        # Previous values stay without new evidence
        self.assertEqual(build_sources.derive_discounts({}, {7: 85, 8: 80})[0][8], 80)
        # Disagreeing observations change nothing
        self.assertEqual(build_sources.derive_discounts({8: {80: 3, 90: 3}}, {})[0][8], 90)

    def test_a_higher_standing_never_pays_more(self):
        discounts, sources = build_sources.derive_discounts({6: {80: 6}, 7: {90: 6}}, {})
        self.assertEqual((discounts[6], discounts[7]), (80, 90))
        discounts, sources = build_sources.derive_discounts({7: {100: 6}}, {})
        self.assertEqual(discounts[7], 90)
        self.assertTrue(sources[7].startswith("Widerspruch"))

    def test_discounts_and_npc_factions_round_trip(self):
        with tempfile.TemporaryDirectory() as directory:
            path = str(Path(directory) / "RecipeSources.lua")
            lines = build_sources.output_lines({1: "a"}, {}, "v1", {171: "76"}, {3365: 76}, {6: 90, 7: 85})
            build_data.write_if_changed(path, lines, build_sources.GENERATED_LINE)
            self.assertEqual(build_sources.read_discounts(path), {6: 90, 7: 85})
            self.assertEqual(build_sources.read_number_table(path, "RegisterNPCFactions"), {3365: 76})
            self.assertEqual(build_sources.read_existing(path), ({1: "a"}, {}))

    def test_reagent_vendors(self):
        text = "ns.npcs = {[1]={},[2]={},[3]={}}\nns.sold = {[10]={1,5,1,0,2,5,1,1,9,5,1,0},[11]={3,5,1,0}}\n"
        self.assertEqual(build_sources.reagent_vendor_npcs(text, {10: 5}), {1})
