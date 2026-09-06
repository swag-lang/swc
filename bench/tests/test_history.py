import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import history


TASKS = ("first", "second")
# Four controls, one more than MIN_CONTROLS: the resolution band corrects each control
# by the median of the others, so it needs a full control set left after removing one.
CONTROLS = ("cpp-a", "cpp-b", "rust", "swift")


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


def add_task(result, task, swag_run=100.0, run_scale=1.0):
    """Give one campaign a task the baseline never measured."""
    entries = {
        "swag-release": {
            "run": {"ms": swag_run * run_scale},
            "build": {"wall_ms": 50.0, "peak_bytes": 1048576, "exe_bytes": 1024},
        },
        "swc-jit-release": {"run": {"ms": swag_run * run_scale}},
    }
    for index, control in enumerate(CONTROLS):
        entries[control] = {"run": {"ms": (20.0 + index) * run_scale},
                            "build": {"wall_ms": (30.0 + index) * run_scale}}
    result["tasks"][task] = entries
    return result


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


class LateTaskTests(unittest.TestCase):
    def test_a_task_added_later_is_indexed_from_its_first_campaign(self):
        baseline = campaign("run-01", False)
        second = add_task(campaign("run-02", False), "third", swag_run=10.0)
        third = add_task(campaign("run-03", False), "third", swag_run=8.0)

        entries = history.build_entries([baseline, second, third])
        index = [e["runtimes"]["swag-release"]["run_index"].get("third") for e in entries]

        self.assertIsNone(index[0])
        self.assertAlmostEqual(index[1], 1.0)
        self.assertAlmostEqual(index[2], 0.8)
        self.assertEqual(entries[2]["context"]["task_baselines"], {"third": "run-02"})

    def test_a_task_added_later_does_not_move_the_aggregate(self):
        baseline = campaign("run-01", False)
        plain = campaign("run-02", False)
        joined = add_task(campaign("run-02", False), "third", swag_run=10.0)

        without = history.build_entries([baseline, plain])[1]
        with_task = history.build_entries([baseline, joined])[1]

        self.assertAlmostEqual(without["runtimes"]["swag-release"]["run_geo_index"],
                               with_task["runtimes"]["swag-release"]["run_geo_index"])
        self.assertAlmostEqual(without["headline"]["exec_vs_best"],
                               with_task["headline"]["exec_vs_best"])
        self.assertEqual(with_task["headline"]["tasks"], 2)


def add_loop(result, wall_ms, hello_ms=None, error=None):
    """Give one campaign an edit-build loop measurement."""
    result["loop"] = {"core_rebuild": {"wall_ms": wall_ms, "peak_bytes": 2097152,
                                       "samples": [wall_ms, wall_ms + 1.0]}}
    if error:
        result["loop"]["doc_std"] = {"error": error}
    if hello_ms is not None:
        result["hello_build"] = {"swag-release": {"wall_ms": hello_ms, "peak_bytes": 1048576}}
    return result


class EditLoopTests(unittest.TestCase):
    def test_resident_memory_is_distinct_from_commit_and_absent_in_old_campaigns(self):
        old = add_loop(campaign("run-01", False), 2000.0)
        current = add_loop(campaign("run-02", False), 2000.0, hello_ms=80.0)
        current["loop"]["core_rebuild"]["peak_working_set_bytes"] = 3145728
        current["hello_build"]["swag-release"]["peak_working_set_bytes"] = 4194304
        entries = history.build_entries([old, current])
        self.assertIsNone(entries[0]["loop"]["core_rebuild"]["peak_working_set_mb"])
        self.assertEqual(entries[1]["loop"]["core_rebuild"]["peak_mb"], 2.0)
        self.assertEqual(entries[1]["loop"]["core_rebuild"]["peak_working_set_mb"], 3.0)
        self.assertEqual(entries[1]["loop"]["hello_build"]["peak_working_set_mb"], 4.0)

    def test_a_workload_is_corrected_by_the_build_context(self):
        baseline = add_loop(campaign("run-01", False), 2000.0, hello_ms=80.0)
        slower = add_loop(campaign("run-02", False, build_scale=1.25), 2500.0, hello_ms=100.0)

        entries = history.build_entries([baseline, slower])
        loop = entries[1]["loop"]

        self.assertAlmostEqual(loop["core_rebuild"]["wall_ms"], 2500.0)
        self.assertAlmostEqual(loop["core_rebuild"]["adjusted_ms"], 2000.0)
        self.assertAlmostEqual(loop["core_rebuild"]["index"], 1.0)
        self.assertAlmostEqual(loop["hello_build"]["adjusted_ms"], 80.0)
        self.assertAlmostEqual(loop["core_rebuild"]["peak_mb"], 2.0)
        self.assertEqual(loop["core_rebuild"]["samples"], 2)
        self.assertEqual(loop["core_rebuild"]["since"], "run-01")

    def test_a_workload_added_later_is_indexed_from_its_first_clean_campaign(self):
        baseline = campaign("run-01", False)
        dirty = add_loop(campaign("run-02", True), 1000.0)
        first = add_loop(campaign("run-03", False), 2000.0)
        faster = add_loop(campaign("run-04", False), 1000.0)

        entries = history.build_entries([baseline, dirty, first, faster])
        index = [(e["loop"].get("core_rebuild") or {}).get("index") for e in entries]

        self.assertEqual(entries[0]["loop"], {})
        self.assertAlmostEqual(index[1], 0.5)
        self.assertAlmostEqual(index[2], 1.0)
        self.assertAlmostEqual(index[3], 0.5)
        self.assertEqual(entries[3]["loop"]["core_rebuild"]["since"], "run-03")

    def test_a_failed_workload_leaves_no_number_behind(self):
        failed = add_loop(campaign("run-01", False), 2000.0, error="exit=1")

        loop = history.build_entries([failed])[0]["loop"]

        self.assertIn("core_rebuild", loop)
        self.assertNotIn("doc_std", loop)


class ResolutionTests(unittest.TestCase):
    def test_an_unchanged_control_reads_one_when_the_machine_only_scales(self):
        baseline = campaign("run-01", False)
        slower = campaign("run-02", False, run_scale=1.25)

        null = history.build_entries([baseline, slower])[1]["null"]["run"]

        self.assertEqual(null["controls"], len(CONTROLS))
        self.assertAlmostEqual(null["geo"][0], 1.0)
        self.assertAlmostEqual(null["geo"][1], 1.0)

    def test_a_noisy_control_widens_the_band_it_does_not_correct_itself(self):
        baseline = campaign("run-01", False)
        noisy = campaign("run-02", False, outlier=1.5)

        null = history.build_entries([baseline, noisy])[1]["null"]["run"]

        self.assertAlmostEqual(null["geo"][1], 1.5)


if __name__ == "__main__":
    unittest.main()
