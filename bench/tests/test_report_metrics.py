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
        self.assertIn("Rival total: 400.0 ms", markup)
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


if __name__ == "__main__":
    unittest.main()
