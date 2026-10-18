import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import mkpage
import report_metrics as metrics


TASKS = ("one", "two", "three", "four")


def campaign(day, own=(50, 99, 101, 200), rival=(100, 100, 100, 100)):
    tasks = {}
    for task, sw, other in zip(TASKS, own, rival):
        tasks[task] = {}
        for runtime, value in (("swag-release", sw), ("cpp-clang-cl", other),
                               ("swc-jit-release", sw), ("node20", other),
                               ("swag-fast-debug", 0.01), ("python3.12", 0.01)):
            tasks[task][runtime] = {"run": {"ms": value},
                                   "build": {"wall_ms": value, "peak_bytes": value * 1024}}
    return {"meta": {"date": "2026-10-%02dT00:00:00+00:00" % day,
                     "stamp": "campaign-%02d" % day, "protocol": 2}, "tasks": tasks}


class ReportMetricsTests(unittest.TestCase):
    def test_median_gap_counts_and_actual_times_expose_mixed_results(self):
        current = campaign(2)
        competitors = metrics.rivals(current, TASKS, "run", "ms", "native")
        self.assertEqual(competitors, ["cpp-clang-cl"])
        summary = metrics.comparison(current, TASKS, "swag-release", "run", "ms", competitors)
        self.assertAlmostEqual(summary["gap_pct"], 0)
        self.assertEqual((summary["ahead"], summary["close"], summary["behind"]), (1, 2, 1))
        self.assertEqual(summary["median_ms"], 100)
        self.assertEqual(summary["total_ms"], 450)
        self.assertEqual(summary["rival_total_ms"], 400)
        self.assertEqual(summary["saved_ms"], -50)
        self.assertEqual((summary["min_gap_pct"], summary["max_gap_pct"]), (-50, 100))

    def test_group_references_and_all_swag_modes_stay_separate(self):
        current = campaign(2)
        self.assertEqual(metrics.rivals(current, TASKS, "run", "ms", "jit"), ["node20"])
        builds = metrics.rivals(current, TASKS, "build", "wall_ms")
        self.assertNotIn("swag-fast-debug", builds)
        self.assertIn("python3.12", builds)  # Only the recorded build contract matters here.

    def test_missing_errors_and_invalid_values_never_produce_a_comparison(self):
        for record in ({}, {"ms": 0}, {"ms": -1}, {"ms": float("nan")},
                       {"ms": float("inf")}, {"ms": 1, "error": "failed"}):
            with self.subTest(record=record):
                current = campaign(2)
                current["tasks"]["one"]["cpp-clang-cl"]["run"] = record
                self.assertEqual(metrics.rivals(current, TASKS, "run", "ms", "native"), [])
                self.assertIsNone(metrics.comparison(current, TASKS, "swag-release", "run", "ms", []))
                current["tasks"]["one"]["swag-release"]["run"] = record
                self.assertIsNone(metrics.comparison(current, TASKS, "swag-release", "run", "ms", ["node20"]))

    def test_time_arrows_follow_displayed_values_when_competitors_change(self):
        before = campaign(1, own=(100,) * 4)
        current = campaign(2, own=(200,) * 4, rival=(200,) * 4)
        for task in TASKS:
            current["tasks"][task]["rust"] = {"run": {"ms": 10}}
        change = metrics.previous_change(current, [before, current], TASKS,
                                         "swag-release", "run", "ms", "native")
        self.assertAlmostEqual(change["saved_ms"], -760)
        self.assertAlmostEqual(change["current_saved_ms"], -760)
        self.assertAlmostEqual(change["previous_saved_ms"], 0)
        self.assertEqual(change["rivals"], 2)
        self.assertEqual(change["reference"]["stamp"], "campaign-01")
        self.assertIn("trend regressed", mkpage.trend(change)[0])

    def test_change_measures_relative_improvement_and_regression(self):
        before = campaign(1, own=(100,) * 4)
        for own in (160, 240):
            current = campaign(2, own=(own,) * 4, rival=(200,) * 4)
            for lead, group in (("swag-release", "native"), ("swc-jit-release", "jit")):
                change = metrics.previous_change(current, [before], TASKS, lead, "run", "ms", group)
                self.assertEqual(change["saved_ms"], (200 - own) * 4)

    def test_total_trend_weights_longer_tasks_and_reports_current_machine_time(self):
        before = campaign(1, own=(100, 100, 100, 1000), rival=(100, 100, 100, 1000))
        # Three small regressions are outweighed by one large gain.
        current = campaign(2, own=(110, 110, 110, 500), rival=(100, 100, 100, 1000))
        change = metrics.previous_change(current, [before], TASKS, "swag-release", "run", "ms", "native")
        self.assertAlmostEqual(change["saved_ms"], 470)
        markup, note = mkpage.trend(change)
        self.assertIn("trend improved", markup)
        self.assertIn('class="previous-value"', markup)
        self.assertIn(">0.0 ms</small>", markup)
        self.assertIn("Previous measured value, 2026-10-01", markup)
        self.assertIn("+470.0 ms now", note)
        self.assertNotIn("%", note)

    def test_larger_displayed_savings_get_an_up_arrow_even_when_time_ratios_regress(self):
        before = campaign(1, own=(1000,) * 4, rival=(1385,) * 4)
        current = campaign(2, own=(1200,) * 4, rival=(1605,) * 4)
        change = metrics.previous_change(current, [before], TASKS, "swag-release", "run", "ms", "native")
        self.assertEqual(change["previous_saved_ms"], 1540)
        self.assertEqual(change["current_saved_ms"], 1620)
        markup, note = mkpage.trend(change)
        self.assertIn("trend improved", markup)
        self.assertIn("+1.54 s before, +1.62 s now", note)
        for previous, current, state in ((1620, 1540, "regressed"), (-50, -20, "improved"),
                                          (-20, -50, "regressed"), (1540.1, 1540.2, "unchanged")):
            with self.subTest(previous=previous, current=current):
                change.update(previous_saved_ms=previous, current_saved_ms=current, saved_ms=current - previous)
                self.assertIn("trend " + state, mkpage.trend(change)[0])

    def test_previous_comparison_skips_other_protocol_and_incomplete_panel(self):
        before = campaign(1)
        incomplete = campaign(2)
        del incomplete["tasks"]["four"]
        other_protocol = campaign(3)
        other_protocol["meta"]["protocol"] = 1
        current = campaign(4)
        change = metrics.previous_change(current, [before, incomplete, other_protocol, current], TASKS,
                                         "swag-release", "run", "ms", "native")
        self.assertEqual(change["reference"]["stamp"], "campaign-01")
        self.assertIsNone(metrics.previous_change(current, [incomplete, other_protocol, current], TASKS,
                                                 "swag-release", "run", "ms", "native"))

    def test_peak_memory_preserves_the_previous_measured_value(self):
        before = campaign(1, own=(100,) * 4)
        current = campaign(2, own=(160,) * 4, rival=(200,) * 4)
        # Leave one build control so its peak is the memory reference.
        for item in (before, current):
            for entries in item["tasks"].values():
                for runtime in list(entries):
                    if runtime not in ("swag-release", "cpp-clang-cl"):
                        del entries[runtime]
        change = metrics.previous_change(current, [before], TASKS, "swag-release", "build", "peak_bytes", peak=True)
        self.assertEqual(change["previous_peak_bytes"], 100 * 1024)
        self.assertEqual(change["current_peak_bytes"], 160 * 1024)

    def test_arrows_have_direction_colour_state_and_accessible_explanation(self):
        base = {"reference": campaign(1)["meta"], "tasks": 4, "rivals": 1}
        for value, state, arrow in ((-5, "improved", "&uarr;"), (5, "regressed", "&darr;"),
                                    (0, "unchanged", "&rarr;"), (0.1, "unchanged", "&rarr;")):
            markup, note = mkpage.trend(dict(base, previous_peak_bytes=100 * 1048576,
                                            current_peak_bytes=(100 + value) * 1048576))
            self.assertIn('class="trend %s"' % state, markup)
            self.assertIn(arrow, markup)
            self.assertIn('aria-label=', markup)
            self.assertIn("2026-10-01", note)
        markup, note = mkpage.trend(None)
        self.assertIn("unavailable", markup)
        self.assertNotIn("Stable", note)

    def test_headline_gives_elapsed_time_direction_and_task_distribution(self):
        before = campaign(1, own=(100,) * 4)
        current = campaign(2, own=(50,) * 4)
        markup = mkpage.competitive_stat(current, [before], TASKS, "swag-release", "run", "native", "Native execution")
        self.assertIn("+200.0<em>ms</em>", markup)
        self.assertIn("4 ahead", markup)
        self.assertIn("Swag total: 200.0 ms", markup)
        self.assertIn("Non-Swag rival total: 400.0 ms", markup)
        self.assertIn("trend improved", markup)
        self.assertNotIn("&times;", markup)

    def test_total_headline_handles_losses_parity_and_seconds(self):
        for own, expected in ((200, "-400.0<em>ms</em>"), (100, "0.0<em>ms</em>"),
                              (1000, "-3.60<em>s</em>")):
            with self.subTest(own=own):
                current = campaign(2, own=(own,) * 4)
                markup = mkpage.competitive_stat(current, [], TASKS, "swag-release", "run", "native", "Native execution")
                self.assertIn(expected, markup)
                self.assertNotIn("%", markup)

    def test_jit_headline_names_its_rivals_and_excludes_both_swag_modes(self):
        current = campaign(2, own=(50,) * 4)
        for i, task in enumerate(TASKS):
            current["tasks"][task]["swc-jit-fast-debug"] = {"run": {"ms": 80}}
            current["tasks"][task]["csharp-jit"] = {"run": {"ms": 80 if i < 2 else 140}}
        markup = mkpage.competitive_stat(current, [], TASKS, "swc-jit-release", "run", "jit", "JIT execution")
        self.assertIn("+200.0<em>ms</em>", markup)
        self.assertIn("Swag total: 200.0 ms", markup)
        self.assertIn("Non-Swag rival total: 400.0 ms", markup)
        self.assertIn("Reference: JavaScript / Node V8 (JIT)", markup)
        self.assertNotIn("C# CoreCLR", markup)
        self.assertNotIn("swag devmode", markup)

    def test_reference_uses_one_competitors_total_instead_of_mixing_task_winners(self):
        for family, key in (("run", "ms"), ("build", "wall_ms")):
            with self.subTest(family=family):
                current = campaign(2, own=(10,) * 4, rival=(20, 80, 20, 80))
                for task, elapsed in zip(TASKS, (80, 30, 80, 30)):
                    current["tasks"][task]["rust"] = {family: {key: elapsed}}
                summary = metrics.comparison(current, TASKS, "swag-release", family, key,
                                             ["rust", "cpp-clang-cl"])
                self.assertEqual(summary["reference_runtime"], "cpp-clang-cl")
                self.assertEqual(summary["rival_total_ms"], 200)
                self.assertEqual(summary["saved_ms"], 160)
                reference = metrics.measurements(current, TASKS, summary["reference_runtime"], family, key)
                own = metrics.measurements(current, TASKS, "swag-release", family, key)
                self.assertEqual(sum(rival - measured for rival, measured in zip(reference, own)),
                                 summary["saved_ms"])


class ReportTableTests(unittest.TestCase):
    def test_totals_use_elapsed_sums_and_the_headlines_shared_rivals(self):
        current = campaign(2, own=(1, 2, 3, 1000), rival=(100, 100, 100, 100))
        markup = mkpage.comparison_table(current, TASKS,
                                         ["swag-release", "swag-fast-debug", "cpp-clang-cl"], "run", "native")
        # Uneven task lengths must not turn this into a mean of per-task ratios.
        self.assertIn("1.01 s", markup)
        self.assertIn("-606.0 ms", markup)
        self.assertIn("3 / 0 / 1", markup)
        # Devmode's much smaller times cannot set the shared non-Swag reference.
        self.assertIn("+400.0 ms", markup)
        self.assertIn("4 / 0 / 0", markup)
        self.assertIn("0.0 ms", markup)  # A rival winning every task saves zero vs itself.
        self.assertNotIn("%", markup)
        self.assertNotIn("&times;", markup)

    def test_missing_times_and_peaks_are_independent_and_never_partial(self):
        for family, key, group in (("run", "ms", "native"), ("build", "wall_ms", None)):
            with self.subTest(family=family):
                current = campaign(2, own=(50,) * 4)
                for task in TASKS:
                    current["tasks"][task]["swag-release"][family]["peak_bytes"] = 8 * 1048576
                complete = mkpage.comparison_table(current, TASKS, ["swag-release"], family, group)
                self.assertIn("8.0 MiB", complete)  # Four process peaks must not sum to 32 MiB.
                del current["tasks"]["four"]["swag-release"][family][key]
                missing_time = mkpage.comparison_table(current, TASKS, ["swag-release"], family, group)
                self.assertEqual(missing_time.count("&mdash;"), 3)
                self.assertIn("8.0 MiB", missing_time)
                current["tasks"]["four"]["swag-release"][family][key] = 50
                del current["tasks"]["four"]["swag-release"][family]["peak_bytes"]
                missing_peak = mkpage.comparison_table(current, TASKS, ["swag-release"], family, group)
                self.assertEqual(missing_peak.count("&mdash;"), 1)
                self.assertIn("200.0 ms", missing_peak)
                self.assertNotIn("MiB</td>", missing_peak)

    def test_jit_totals_ignore_native_rivals(self):
        current = campaign(2, own=(50,) * 4, rival=(100,) * 4)
        for task in TASKS:
            current["tasks"][task]["cpp-clang-cl"]["run"]["ms"] = 0.001
        markup = mkpage.comparison_table(current, TASKS, ["swc-jit-release"], "run", "jit")
        self.assertIn("200.0 ms", markup)
        self.assertIn("+200.0 ms", markup)

    def test_task_rows_show_measured_durations_and_signed_time_differences(self):
        times = {"swag-release": 50, "cpp-clang-cl": 100, "rust": 150, "go": float("nan")}
        markup = mkpage.performance_table(["one"], list(times), lambda rt, task: times[rt],
                                          "cpp-clang-cl")
        self.assertIn('class="speed-value">50.0 ms', markup)
        self.assertIn('class="time-gap">+50.0 ms', markup)
        self.assertIn('class="time-gap">0.0 ms', markup)
        self.assertIn('class="time-gap">-50.0 ms', markup)
        self.assertIn("No measurement", markup)
        self.assertNotIn("%", markup)
        self.assertNotIn("nan", markup)

    def test_jit_task_reference_stays_the_same_when_another_rival_wins_a_task(self):
        current = campaign(2, own=(1,) * 4)
        for i, task in enumerate(TASKS):
            current["tasks"][task]["csharp-jit"] = {"run": {"ms": 20 if i % 2 else 40}}
            current["tasks"][task]["java-hotspot"] = {"run": {"ms": 40 if i % 2 else 20}}
        runtimes = ["swc-jit-release", "swc-jit-fast-debug", "csharp-jit", "java-hotspot"]
        rivals = metrics.rivals(current, TASKS, "run", "ms", "jit")
        reference = metrics.reference_runtime(current, TASKS, "run", "ms", rivals)
        self.assertEqual(reference, "csharp-jit")
        markup = mkpage.performance_table(
            TASKS, runtimes, lambda rt, task: current["tasks"][task].get(rt, {}).get("run", {}).get("ms"), reference)
        for elapsed in ("20.0", "40.0"):
            expected = '<td class="rival-reference">%s %s ms</td>' % (mkpage.runtime_badge(reference), elapsed)
            self.assertEqual(markup.count(expected), 2)
        self.assertIn('class="time-gap">+19.0 ms', markup)
        self.assertIn('class="time-gap">+39.0 ms', markup)


if __name__ == "__main__":
    unittest.main()
