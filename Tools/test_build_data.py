"""Offline regression tests: python3 -m unittest discover -s Tools -p 'test_*.py'."""
import contextlib
import io
import os
from pathlib import Path
import struct
import tempfile
import unittest

import build_data


class LearningRankTests(unittest.TestCase):
    def test_missing_sources_keep_mooncloth_boots_rank(self):
        self.assertEqual(build_data.learning_rank(None, None, None, 285), (285, "Bestand"))

    def test_current_sources_override_previous_rank_in_priority_order(self):
        for ranks, expected in (
            ((280, 275, 270, 285), (280, "Rezept-Item")),
            ((None, 275, 270, 285), (275, "Lehrer-Scan")),
            ((None, None, 270, 285), (270, "foreverdb")),
            ((300, None, None, 285), (300, "Rezept-Item")),
        ):
            with self.subTest(ranks=ranks):
                self.assertEqual(build_data.learning_rank(*ranks), expected)

    def test_unknown_sources_do_not_erase_or_mask_known_values(self):
        self.assertEqual(build_data.learning_rank(0, 0, 0, 285), (285, "Bestand"))
        self.assertEqual(build_data.learning_rank(0, 250, 0, 285), (250, "Lehrer-Scan"))

    def test_new_or_previously_unknown_recipes_stay_unknown(self):
        for previous in (None, 0):
            with self.subTest(previous=previous):
                self.assertEqual(build_data.learning_rank(None, None, None, previous),
                                 (0, "unbekannt"))

    def test_retained_rank_survives_read_write_round_trip(self):
        recipe = {"skill": 285, "name": "Mooncloth Boots", "reagents": [(14048, 6)],
                  "created": 15802, "levels": (285, 300, 315)}
        with tempfile.TemporaryDirectory() as directory:
            build_data.write_data_file(directory, "Tailoring", 197, "test", {19435: recipe})
            path = Path(directory) / "Tailoring.lua"
            old = build_data.read_data_file(path)
            recipe["skill"], source = build_data.learning_rank(None, None, None, old[19435][0])
            self.assertEqual(source, "Bestand")
            self.assertEqual(build_data.compare(old, {19435: recipe})["geändert"], 0)
            self.assertFalse(build_data.write_data_file(directory, "Tailoring", 197, "new", {19435: recipe}))
            self.assertEqual(build_data.read_data_file(path)[19435][0], 285)

    def test_report_counts_retained_ranks_separately(self):
        sources = {"Rezept-Item": 0, "Lehrer-Scan": 0, "foreverdb": 0,
                   "Bestand": 1, "unbekannt": 0}
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            build_data.print_recipe_table([("Tailoring", 1, sources, 0)])
        self.assertIn("Bestand", output.getvalue())
        self.assertIn("Summe", output.getvalue())


class AddressOrderTests(unittest.TestCase):
    V4, V6 = build_data.socket.AF_INET, build_data.socket.AF_INET6

    def infos(self, *families):
        return [(family, 1, 6, "", (f"addr{i}", 443)) for i, family in enumerate(families)]

    def test_ipv4_comes_first_even_when_dns_lists_ipv6_first(self):
        # broken IPv6 must not delay every request by 4 dead addresses
        order = build_data.address_order(self.infos(self.V6, self.V6, self.V6, self.V4, self.V4), self.V4)
        self.assertEqual([info[0] for info in order], [self.V4, self.V6, self.V4, self.V6, self.V6])

    def test_family_that_last_worked_is_tried_first(self):
        order = build_data.address_order(self.infos(self.V4, self.V6), self.V6)
        self.assertEqual([info[0] for info in order], [self.V6, self.V4])

    def test_single_family_hosts_keep_dns_order(self):
        infos = self.infos(self.V6, self.V6)
        self.assertEqual(build_data.address_order(infos, self.V4), infos)


class InstallationDirTests(unittest.TestCase):
    def test_flavor_dir_of_product_is_used(self):
        with tempfile.TemporaryDirectory() as directory:
            for flavor, product in (("_retail_", "wow"), ("_forever_", "wowf"),
                                    ("_classic_era_", "wow_classic_era")):
                os.makedirs(Path(directory) / flavor)
                (Path(directory) / flavor / ".flavor.info").write_text(
                    f"Product Flavor!STRING:0\n{product}\n", encoding="utf8")
            self.assertEqual(build_data.installation_dir(directory, "wowf"),
                             str(Path(directory) / "_forever_"))
            self.assertEqual(build_data.installation_dir(directory, "wow"),
                             str(Path(directory) / "_retail_"))

    def test_missing_product_returns_none(self):
        with tempfile.TemporaryDirectory() as directory:
            os.makedirs(Path(directory) / "_retail_")
            (Path(directory) / "_retail_" / ".flavor.info").write_text(
                "Product Flavor!STRING:0\nwow\n", encoding="utf8")
            self.assertIsNone(build_data.installation_dir(directory, "wowf"))
            self.assertIsNone(build_data.installation_dir(directory, "wowf-nope"))


class HotfixCacheTests(unittest.TestCase):
    @staticmethod
    def _cache(directory, build, locale="deDE"):
        path = Path(directory) / "Cache" / "ADB" / locale / "DBCache.bin"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"XFTH" + struct.pack("<II", 9, build) + b"\0" * 32)
        return path

    def test_cache_of_another_build_is_ignored_and_reported(self):
        with tempfile.TemporaryDirectory() as directory:
            self._cache(directory, 70938)
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                hotfixes, path = build_data.load_hotfixes(directory, "WOW-70959patch1.60.1_Retail")
            self.assertEqual((hotfixes, path), ({}, None))
            self.assertIn("70938", output.getvalue())

    def test_only_the_given_flavor_directory_is_searched(self):
        with tempfile.TemporaryDirectory() as directory:
            self._cache(Path(directory) / "_retail_", 70959)
            install = Path(directory) / "_forever_"
            install.mkdir()
            hotfixes, path = build_data.load_hotfixes(str(install), "WOW-70959patch1.60.1_Retail")
            self.assertEqual((hotfixes, path), ({}, None))


class CreatedCountsTests(unittest.TestCase):
    def test_extracts_multi_output_recipes_and_filters_others(self):
        tables = {
            "SpellEffect": {
                1: {"SpellID": 2659, "Effect": build_data.EFFECT_CREATE_ITEM, "EffectItemType": 2841,
                    "EffectBasePointsF": 2.0, "EffectBasePoints": 0},
                2: {"SpellID": 3920, "Effect": build_data.EFFECT_CREATE_ITEM, "EffectItemType": 8067,
                    "EffectBasePointsF": 200.0, "EffectBasePoints": 0},
                3: {"SpellID": 7183, "Effect": build_data.EFFECT_CREATE_ITEM, "EffectItemType": 5997,
                    "EffectBasePointsF": 1.0, "EffectBasePoints": 0},
                4: {"SpellID": 818, "Effect": build_data.EFFECT_CREATE_ITEM, "EffectItemType": 0,
                    "EffectBasePointsF": 5.0, "EffectBasePoints": 0},
                5: {"SpellID": 9999, "Effect": build_data.EFFECT_CREATE_ITEM, "EffectItemType": 1234,
                    "EffectBasePointsF": 0.0, "EffectBasePoints": 2},
                6: {"SpellID": 8888, "Effect": build_data.EFFECT_CREATE_ITEM, "EffectItemType": 5678,
                    "EffectBasePointsF": 4.0, "EffectBasePoints": 0},
            }
        }
        counts = build_data.created_counts(tables, {2659, 3920, 7183, 818, 9999})
        self.assertEqual(counts, {2659: 2, 3920: 200, 9999: 3})

    def test_created_counts_round_trip_and_unchanged_build_skip(self):
        counts = {2659: 2, 3920: 200}
        with tempfile.TemporaryDirectory() as directory:
            self.assertTrue(build_data.write_created_counts(directory, "build1", counts))
            path = Path(directory) / "CreatedCounts.lua"
            self.assertEqual(build_data.read_created_counts(path), counts)
            self.assertFalse(build_data.write_created_counts(directory, "build2", counts))


if __name__ == "__main__":
    unittest.main()
