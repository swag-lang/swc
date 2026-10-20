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


class BuildEvidenceTests(unittest.TestCase):
    def test_archived_series_recover_the_fastest_confirmed_pair_and_keep_every_sample(self):
        for samples, expected in (([148.6, 172.3, 172.4, 181.5, 208.6, 195.9], 172.3),
                                  ([163.1, 212.1, 214, 262.6, 250.2, 280.2], 212.1),
                                  ([258.3, 295, 390.2, 403.1, 398.9, 399.9], 390.2)):
            with self.subTest(samples=samples):
                build = {"samples": samples[:], "unverified_wall_ms": min(samples),
                         "repeatability": {"status": "unresolved", "limit_pct": 10}}
                raw = {"tasks": {"fixture": {"swag-release": {"build": build}}}}
                history.settle_campaign(raw)
                self.assertEqual(build["wall_ms"], expected)
                self.assertEqual(build["samples"], samples)
                self.assertEqual(build["raw_min_wall_ms"], min(samples))
                self.assertEqual(build["repeatability"]["supporting_pair_ms"][0], expected)
                settled = copy.deepcopy(raw)
                self.assertEqual(history.settle_campaign(raw), settled)

    def test_an_unconfirmed_series_remains_unresolved_and_older_unchecked_results_stay_intact(self):
        build = {"samples": [3690.5, 4082.5, 4681.6], "wall_ms": 3690.4721}
        history.settle_build(build)
        self.assertNotIn("wall_ms", build)
        self.assertEqual(build["unverified_wall_ms"], 3690.4721)
        old = {"tasks": {"fixture": {"swag-release": {"build": {"samples": [100], "wall_ms": 100}}}}}
        self.assertEqual(history.settle_campaign(copy.deepcopy(old)), old)

    def test_a_supported_recorded_minimum_keeps_its_full_precision(self):
        build = {"samples": [172.3, 172.4, 200], "wall_ms": 172.31234}
        history.settle_build(build)
        self.assertEqual(build["wall_ms"], 172.31234)
        self.assertNotIn("unconfirmed_samples", build)


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
    def test_progress_removes_machine_scale_and_keeps_execution_models_separate(self):
        baseline = campaign("run-01", False)
        scaled = campaign("run-02", False, run_scale=1.5, build_scale=0.8)
        improved = campaign("run-03", False, run_scale=1.5, build_scale=0.8, swag_build=25)
        for task in TASKS:
            improved["tasks"][task]["swag-release"]["run"]["ms"] = 75
        entries = history.build_entries([baseline, scaled, improved])
        native = history.progress_series(entries, "swag-release", "run", TASKS)
        jit = history.progress_series(entries, "swc-jit-release", "run", TASKS)
        self.assertAlmostEqual(native["scores"]["run-01"], 100)
        self.assertAlmostEqual(native["scores"]["run-02"], 100)
        self.assertAlmostEqual(native["scores"]["run-03"], 200)
        self.assertAlmostEqual(jit["scores"]["run-03"], 100)
        builds = history.progress_series(entries, "swag-release", "build", TASKS)
        self.assertAlmostEqual(builds["scores"]["run-02"], 100)
        self.assertAlmostEqual(builds["scores"]["run-03"], 200)

    def test_progress_has_fixed_equal_task_weights_and_ignores_added_workloads(self):
        baseline = campaign("run-01", False)
        improved = add_task(campaign("run-02", False), "third", swag_run=0.01)
        improved["tasks"]["first"]["swag-release"]["run"]["ms"] = 50
        improved["tasks"]["second"]["swag-release"]["run"]["ms"] = 25
        for scale in (1, 1000):
            with self.subTest(scale=scale):
                for result in (baseline, improved):
                    for rec in result["tasks"]["first"].values():
                        rec["run"]["ms"] *= scale
                entries = history.build_entries([baseline, improved])
                progress = history.progress_series(entries, "swag-release", "run", TASKS)
                self.assertAlmostEqual(progress["scores"]["run-02"], 100 * 8 ** 0.5)

    def test_progress_uses_the_first_clean_complete_reference_in_date_order(self):
        entries = history.build_entries([campaign("run-01", True), campaign("run-02", False),
                                         campaign("run-03", False)])
        progress = history.progress_series(list(reversed(entries)), "swag-release", "run", TASKS)
        self.assertEqual(progress["baseline"]["stamp"], "run-02")
        self.assertEqual(progress["scores"]["run-02"], 100)
        self.assertIsNone(history.progress_series(entries[:1], "swag-release", "run", TASKS)["baseline"])

    def test_progress_omits_incomplete_times_and_missing_machine_correction(self):
        source = history.build_entries([campaign("run-01", False), campaign("run-02", False)])
        for invalid in (None, 0, -1, float("nan"), float("inf")):
            for target in ("time", "correction"):
                with self.subTest(invalid=invalid, target=target):
                    entries = copy.deepcopy(source)
                    values = (entries[1]["runtimes"]["swag-release"]["run_adjusted_ms"] if target == "time"
                              else entries[1]["context"]["run_task_factors"])
                    values["second"] = invalid
                    progress = history.progress_series(entries, "swag-release", "run", TASKS)
                    self.assertIsNone(progress["scores"]["run-02"])

    def test_execution_headlines_separate_native_from_jit_and_interpreted(self):
        result = campaign("run-01", False)
        for task, scale in zip(TASKS, (1, 100)):
            result["tasks"][task] = {rt: {"run": {"ms": elapsed * scale}}
                                     for rt, elapsed in (("swag-release", 103), ("cpp-msvc", 100),
                                                         ("swc-jit-release", 200), ("node20", 100),
                                                         ("lua5.4", 1))}
        panel = {"run": TASKS, "build": TASKS}
        headline = history._headline(result, panel)
        self.assertAlmostEqual(headline["exec_native_vs_best"], 1.03)
        self.assertAlmostEqual(headline["exec_jit_vs_best"], 200)
        self.assertEqual(headline["exec_jit_fastest"], "lua5.4")
        for model, runtime, unaffected in (("native", "cpp-msvc", "exec_jit_vs_best"),
                                            ("jit", "node20", "exec_native_vs_best"),
                                            ("jit", "lua5.4", "exec_native_vs_best")):
            with self.subTest(model=model):
                faster = copy.deepcopy(result)
                for task in TASKS:
                    faster["tasks"][task][runtime]["run"]["ms"] *= 0.001
                self.assertAlmostEqual(history._headline(faster, panel)[unaffected], headline[unaffected])
        self.assertNotIn("exec_vs_best", headline)

    def test_execution_group_reference_needs_complete_valid_measurements(self):
        for invalid in (None, 0, -1, float("inf"), float("nan")):
            with self.subTest(invalid=invalid):
                tasks = {task: {"swc-jit-release": {"run": {"ms": 100}},
                                "node20": {"run": {"ms": 1 if task == "first" else invalid}},
                                "cpp-msvc": {"run": {"ms": 0.0001}}} for task in TASKS}
                self.assertEqual(history.execution_ratios(tasks, TASKS, "jit"), {"swc-jit-release": 1.0})

    def test_execution_speedup_counts_advantages_with_separate_non_swag_references(self):
        tasks = {task: {rt: {"run": {"ms": elapsed * scale}}
                        for rt, elapsed in (("swag-release", 100), ("swag-devmode", 0.001),
                                            ("swc-jit-release", 10), ("swc-jit-devmode", 0.001),
                                            ("cpp-msvc", native), ("rust", rust),
                                            ("node20", jit), ("lua5.4", 0.001))}
                 for task, scale, native, rust, jit in (("first", 1, 200, 400, 40),
                                                        ("second", 1000, 400, 100, 10))}
        # The fastest native rival switches by task: sqrt(2 * 1), not a fixed rival.
        self.assertAlmostEqual(history.execution_speedup(tasks, TASKS, "native"), 2 ** 0.5)
        self.assertAlmostEqual(history.execution_speedup(tasks, TASKS, "jit"), 0.0001)
        for task in TASKS:
            tasks[task]["swc-jit-release"]["run"]["ms"] *= 0.001
        self.assertAlmostEqual(history.execution_speedup(tasks, TASKS, "native"), 2 ** 0.5)

    def test_execution_speedup_needs_a_complete_valid_non_swag_rival(self):
        for invalid in (None, 0, -1, float("inf"), float("nan")):
            with self.subTest(invalid=invalid):
                tasks = {task: {"swag-release": {"run": {"ms": 100}},
                                "swag-devmode": {"run": {"ms": 1}},
                                "cpp-msvc": {"run": {"ms": 1 if task == "first" else invalid}},
                                "rust": {"run": {"ms": 1, "error": "failed"}},
                                "node20": {"run": {"ms": 1}}} for task in TASKS}
                self.assertIsNone(history.execution_speedup(tasks, TASKS, "native"))
                for task in TASKS:
                    tasks[task]["rust"]["run"] = {"ms": 50}
                self.assertAlmostEqual(history.execution_speedup(tasks, TASKS, "native"), 0.5)

    def test_split_build_controls_describe_a_historical_divergence(self):
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

        stable = history.build_control_spread(coherent, [baseline])
        unstable = history.build_control_spread(split, [baseline])
        self.assertAlmostEqual(stable["spread_pct"], 0.0)
        self.assertGreater(unstable["spread_pct"], history.BUILD_CONTROL_SPREAD_LIMIT_PCT)
        self.assertEqual(unstable["references"], ["run-01"])

        # A campaign that adds a task is compared with its predecessor on the shared tasks.
        extended = history.build_control_spread(add_task(split, "third"), [baseline])
        self.assertEqual(extended["spread_pct"], unstable["spread_pct"])

        # The quiet campaign after a split one: the median over recent references keeps
        # the disturbed predecessor from making it read as split itself.
        recovered = copy.deepcopy(baseline)
        recovered["meta"]["stamp"] = "run-04"
        alone = history.build_control_spread(recovered, [split])
        among = history.build_control_spread(recovered, [baseline, coherent, split])
        self.assertGreater(alone["spread_pct"], history.BUILD_CONTROL_SPREAD_LIMIT_PCT)
        self.assertLess(among["spread_pct"], history.BUILD_CONTROL_SPREAD_LIMIT_PCT)

    def test_oldest_clean_campaign_is_the_baseline(self):
        dirty = campaign("run-01", True, run_scale=2.0)
        clean = campaign("run-02", False)
        latest = campaign("run-03", False)

        entries = history.build_entries([dirty, latest, clean])

        self.assertEqual(entries[0]["context"]["baseline"], "run-02")
        self.assertEqual(entries[1]["context"]["baseline"], "run-02")
        self.assertEqual(entries[2]["context"]["baseline"], "run-02")

    def test_an_unresolved_build_leaves_a_gap_instead_of_changing_the_aggregate_panel(self):
        baseline = campaign("run-01", False)
        current = campaign("run-02", False)
        build = current["tasks"]["second"]["swag-release"]["build"]
        build["unverified_wall_ms"] = build.pop("wall_ms")
        build["repeatability"] = {"status": "unresolved"}
        entry = history.build_entries([baseline, current])[1]
        native = entry["runtimes"]["swag-release"]
        self.assertIsNone(native["build_geo_adjusted_ms"])
        self.assertIsNone(native["build_geo_index"])
        self.assertEqual(native["build_ms"]["first"], 50)
        self.assertIsNone(native["build_ms"]["second"])
        self.assertIsNotNone(native["run_geo_index"])

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
            entries["swag-devmode"] = {"build": {"wall_ms": 0.01}}
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
        self.assertAlmostEqual(without["headline"]["exec_native_vs_best"],
                               with_task["headline"]["exec_native_vs_best"])
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
