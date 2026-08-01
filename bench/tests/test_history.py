import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import history


TASKS = ("first", "second")
CONTROLS = ("cpp-a", "cpp-b", "rust")


def campaign(stamp, dirty, run_scale=1.0, build_scale=1.0, swag_run=100.0,
             swag_build=50.0, outlier=1.0):
    tasks = {}
    for task in TASKS:
        entries = {
            "swag-release": {
                "run": {"ms": swag_run * run_scale},
                "build": {"wall_ms": swag_build * build_scale,
                          "peak_bytes": 1048576, "exe_bytes": 1024},
            },
            "swc-jit-release": {"run": {"ms": swag_run * run_scale}},
        }
        for index, control in enumerate(CONTROLS):
            noise = outlier if index == len(CONTROLS) - 1 else 1.0
            entries[control] = {
                "run": {"ms": (20.0 + index) * run_scale * noise},
                "build": {"wall_ms": (30.0 + index) * build_scale * noise},
            }
        tasks[task] = entries
    return {
        "meta": {"stamp": stamp, "date": "2026-01-%sT00:00:00+00:00" % stamp[-2:],
                 "commit": stamp, "dirty": dirty},
        "calibration": {"start": 1.0, "drift_pct": 0.0},
        "tasks": tasks,
        "hello_run": {},
        "hello_build": {},
    }


class HistoryAdjustmentTests(unittest.TestCase):
    def test_oldest_clean_campaign_is_the_baseline(self):
        dirty = campaign("run-01", True, run_scale=2.0)
        clean = campaign("run-02", False)
        latest = campaign("run-03", False)

        entries = history.build_entries([dirty, latest, clean])

        self.assertEqual(entries[0]["context"]["baseline"], "run-02")
        self.assertEqual(entries[1]["context"]["baseline"], "run-02")
        self.assertEqual(entries[2]["context"]["baseline"], "run-02")

    def test_machine_scale_is_removed_from_swag(self):
        baseline = campaign("run-01", False)
        slower = campaign("run-02", False, run_scale=1.25, build_scale=0.8)

        entry = history.build_entries([baseline, slower])[1]
        native = entry["runtimes"]["swag-release"]

        self.assertAlmostEqual(entry["context"]["run_factor"], 1.25)
        self.assertAlmostEqual(entry["context"]["build_factor"], 0.8)
        self.assertAlmostEqual(native["run_geo_adjusted_ms"], 100.0)
        self.assertAlmostEqual(native["build_geo_adjusted_ms"], 50.0)
        self.assertAlmostEqual(native["run_geo_index"], 1.0)
        self.assertAlmostEqual(native["build_geo_index"], 1.0)

    def test_one_control_outlier_does_not_move_the_median(self):
        baseline = campaign("run-01", False)
        noisy = campaign("run-02", False, run_scale=1.1, build_scale=1.1,
                         swag_run=100.0, swag_build=50.0, outlier=8.0)

        entry = history.build_entries([baseline, noisy])[1]

        self.assertAlmostEqual(entry["context"]["run_factor"], 1.1)
        self.assertAlmostEqual(entry["context"]["build_factor"], 1.1)


if __name__ == "__main__":
    unittest.main()
