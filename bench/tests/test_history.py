import copy
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
    def test_split_build_controls_reject_a_false_compiler_speedup(self):
        baseline = campaign("run-01", False)
        for task in TASKS:
            for index in range(5):
                baseline["tasks"][task]["extra-%d" % index] = {
                    "build": {"wall_ms": 40.0 + index}}

        coherent = copy.deepcopy(baseline)
        split = copy.deepcopy(baseline)
        for task in TASKS:
            for runtime, entry in coherent["tasks"][task].items():
                if runtime != "swag-release" and entry.get("build"):
                    entry["build"]["wall_ms"] *= 1.1
            for runtime, entry in split["tasks"][task].items():
                if runtime in ("cpp-a", "cpp-b", "rust", "extra-0", "extra-1"):
                    entry["build"]["wall_ms"] *= 1.55

        stable = history.build_control_spread(coherent, baseline)
        unstable = history.build_control_spread(split, baseline)
        self.assertAlmostEqual(stable["spread_pct"], 0.0)
        self.assertGreater(unstable["spread_pct"], history.BUILD_CONTROL_SPREAD_LIMIT_PCT)

        # A campaign that adds a task is compared with its predecessor on the shared tasks.
        extended = history.build_control_spread(add_task(split, "third"), baseline)
        self.assertEqual(extended["spread_pct"], unstable["spread_pct"])

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

    def test_build_speedup_is_unchanged_when_the_machine_scales(self):
        baseline = campaign("run-01", False)
        same_builds_on_slower_machine = campaign("run-02", False, build_scale=1.5)

        first, second = history.build_entries([baseline, same_builds_on_slower_machine])

        self.assertAlmostEqual(first["headline"]["build_speedup"], 0.6)
        self.assertAlmostEqual(second["headline"]["build_speedup"], 0.6)

    def test_build_speedup_uses_each_tasks_fastest_rival_and_geometric_mean(self):
        result = campaign("run-01", False)
        for task, swag, first, second in (("first", 10.0, 20.0, 80.0),
                                          ("second", 100.0, 800.0, 400.0)):
            entries = result["tasks"][task]
            entries["swag-release"]["build"]["wall_ms"] = swag
            for control in CONTROLS:
                entries[control]["build"]["wall_ms"] = 10000.0
            entries["cpp-a"]["build"]["wall_ms"] = first
            entries["cpp-b"]["build"]["wall_ms"] = second
            entries["cpp-msvc"] = {"build": {"wall_ms": 20000.0}}
            entries["swag-fast-debug"] = {"build": {"wall_ms": 0.01}}
            entries["swc-jit-release"]["build"] = {"wall_ms": 0.01}

        entry = history.build_entries([result])[0]

        # The winner switches between tasks: ratios 2 and 4 give sqrt(8), not 3.
        self.assertAlmostEqual(entry["headline"]["build_speedup"], 8.0 ** 0.5)
        self.assertEqual(entry["headline"]["build_tasks"], 2)
        self.assertNotIn("build_edge", entry["headline"])

        # Changing task duration cannot change its weight in the aggregate.
        for task, scale in (("first", 100.0), ("second", 0.1)):
            for measurement in result["tasks"][task].values():
                if measurement.get("build"):
                    measurement["build"]["wall_ms"] *= scale
        self.assertAlmostEqual(history.build_speedup(result["tasks"], TASKS), 8.0 ** 0.5)

    def test_build_speedup_uses_current_rivals_instead_of_the_baseline(self):
        baseline = campaign("run-01", False)
        current = campaign("run-02", False)
        for entries in current["tasks"].values():
            entries["cpp-a"]["build"]["wall_ms"] = 15.0

        first, second = history.build_entries([baseline, current])

        self.assertAlmostEqual(first["headline"]["build_speedup"], 0.6)
        self.assertAlmostEqual(second["headline"]["build_speedup"], 0.3)

    def test_build_speedup_needs_complete_valid_measurements(self):
        for incomplete in (None, {}, {"wall_ms": 0}, {"wall_ms": -1},
                           {"wall_ms": 0.01, "error": "compiler exited"}):
            with self.subTest(incomplete=incomplete):
                result = campaign("run-01", False)
                result["tasks"]["first"]["partial"] = {"build": {"wall_ms": 0.01}}
                result["tasks"]["second"]["partial"] = {"build": incomplete}
                self.assertAlmostEqual(history.build_speedup(result["tasks"], TASKS), 0.6)
                result["tasks"]["second"]["swag-release"]["build"] = incomplete
                self.assertIsNone(history.build_speedup(result["tasks"], TASKS))

    def test_build_speedup_has_no_value_without_a_rival_or_build_measurements(self):
        result = campaign("run-01", False)
        for entries in result["tasks"].values():
            for control in CONTROLS:
                entries.pop(control)
        self.assertIsNone(history.build_speedup(result["tasks"], TASKS))
        for entries in result["tasks"].values():
            for measurement in entries.values():
                measurement.pop("build", None)
        self.assertIsNone(history.build_entries([result])[0]["headline"]["build_speedup"])
        self.assertIsNone(history.build_speedup({}, []))

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
        joined["tasks"]["third"]["swag-release"]["build"]["wall_ms"] = 1.0
        with_task = history.build_entries([baseline, joined])[1]
        self.assertAlmostEqual(without["headline"]["build_speedup"],
                               with_task["headline"]["build_speedup"])
        self.assertNotAlmostEqual(with_task["headline"]["build_speedup"],
                                  history.build_speedup(joined["tasks"], list(joined["tasks"])))
        self.assertEqual(with_task["headline"]["build_tasks"], 2)
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


def compile_only(result):
    """Keep only the compilation family of a synthetic campaign."""
    for entries in result["tasks"].values():
        for entry in entries.values():
            entry.pop("run", None)
    result["hello_run"] = {}
    result["meta"]["settings"] = {"phases": ["build"]}
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

    def test_compile_only_campaign_updates_build_history_without_execution_data(self):
        baseline = campaign("run-01", False)
        partial = compile_only(campaign("run-02", False, build_scale=0.8))

        entries = history.build_entries([baseline, partial])

        self.assertAlmostEqual(entries[1]["runtimes"]["swag-release"]["build_geo_adjusted_ms"], 50.0)
        self.assertIsNone(entries[1]["runtimes"]["swag-release"]["run_geo_adjusted_ms"])
        self.assertAlmostEqual(entries[0]["runtimes"]["swag-release"]["run_geo_adjusted_ms"], 100.0)
        self.assertAlmostEqual(entries[1]["headline"]["build_speedup"], 0.6)


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


def allocator_section(swag_ns, mimalloc_ns, crt_ns, swag_ws=8.0):
    """A raw allocator section with one workload per entry of the three lists."""
    section = {}
    for index, (s, m, c) in enumerate(zip(swag_ns, mimalloc_ns, crt_ns)):
        section["w%d" % index] = {
            "swag": {"ns": s, "samples": [s], "peak_bytes": 4194304,
                     "peak_working_set_bytes": int(swag_ws * 1048576)},
            "mimalloc": {"ns": m, "samples": [m], "peak_bytes": 4194304,
                         "peak_working_set_bytes": 4194304},
            "crt": {"ns": c, "samples": [c], "peak_bytes": 4194304,
                    "peak_working_set_bytes": 4194304},
        }
    return section


class AllocatorTests(unittest.TestCase):
    def test_ratios_to_the_competitors_measured_in_the_same_rounds(self):
        result = campaign("20260101", False)
        result["allocator"] = allocator_section([20.0, 50.0], [10.0, 50.0], [40.0, 100.0])
        alloc = history.build_entries([result])[0]["allocator"]
        self.assertAlmostEqual(alloc["workloads"]["w0"]["vs_mimalloc"], 2.0)
        self.assertAlmostEqual(alloc["workloads"]["w1"]["vs_crt"], 0.5)
        self.assertAlmostEqual(alloc["geo_vs_mimalloc"], 2.0 ** 0.5)
        self.assertAlmostEqual(alloc["geo_vs_crt"], 0.5)
        self.assertAlmostEqual(alloc["geo_ws_vs_mimalloc"], 2.0)
        self.assertEqual(alloc["count"], 2)

    def test_the_ratios_ignore_machine_scale_and_old_campaigns_have_none(self):
        old = campaign("20260101", False)
        new = campaign("20260102", False, run_scale=1.5)
        new["allocator"] = allocator_section([30.0], [15.0], [60.0])
        entries = history.build_entries([old, new])
        self.assertIsNone(entries[0]["allocator"])
        self.assertAlmostEqual(entries[1]["allocator"]["geo_vs_mimalloc"], 2.0)

    def test_a_failed_implementation_leaves_its_workload_out_of_the_means(self):
        result = campaign("20260101", False)
        result["allocator"] = allocator_section([20.0, 50.0], [10.0, 50.0], [40.0, 100.0])
        result["allocator"]["w1"]["crt"] = {"error": "exit code 5"}
        alloc = history.build_entries([result])[0]["allocator"]
        self.assertNotIn("crt_ns", alloc["workloads"]["w1"])
        self.assertNotIn("vs_crt", alloc["workloads"]["w1"])
        self.assertAlmostEqual(alloc["geo_vs_mimalloc"], 2.0)
        self.assertEqual(alloc["count"], 1)


if __name__ == "__main__":
    unittest.main()
