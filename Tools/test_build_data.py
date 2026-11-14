"""Offline regression tests: python3 -m unittest discover -s Tools -p 'test_*.py'."""
import contextlib
import io
from pathlib import Path
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


if __name__ == "__main__":
    unittest.main()
