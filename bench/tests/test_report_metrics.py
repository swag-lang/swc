import os
import re
import sys
import unittest
from unittest import mock

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
                               ("swag-devmode", 0.01), ("python3.12", other)):
            tasks[task][runtime] = {"run": {"ms": value, "samples": [value, value]},
                                   "build": {"wall_ms": value, "samples": [value, value], "peak_bytes": value * 1024}}
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
        self.assertEqual(metrics.rivals(current, TASKS, "run", "ms", "jit"), ["node20", "python3.12"])
        builds = metrics.rivals(current, TASKS, "build", "wall_ms")
        self.assertNotIn("swag-devmode", builds)
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
            current["tasks"][task]["rust"] = {"run": {"ms": 10, "samples": [10, 10]}}
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
        self.assertIn("-470.0 ms now", note)
        self.assertNotIn("%", note)

    def test_larger_displayed_savings_get_an_up_arrow_even_when_time_ratios_regress(self):
        before = campaign(1, own=(1000,) * 4, rival=(1385,) * 4)
        current = campaign(2, own=(1200,) * 4, rival=(1605,) * 4)
        change = metrics.previous_change(current, [before], TASKS, "swag-release", "run", "ms", "native")
        self.assertEqual(change["previous_saved_ms"], 1540)
        self.assertEqual(change["current_saved_ms"], 1620)
        markup, note = mkpage.trend(change)
        self.assertIn("trend improved", markup)
        self.assertIn("-1.54 s before, -1.62 s now", note)
        for previous, current, state in ((1620, 1540, "regressed"), (-50, -20, "improved"),
                                          (-20, -50, "regressed"), (1540.1, 1540.2, "unchanged")):
            with self.subTest(previous=previous, current=current):
                change.update(previous_saved_ms=previous, current_saved_ms=current, saved_ms=current - previous)
                change.pop("sensitivity_ms", None)
                self.assertIn("trend " + state, mkpage.trend(change)[0])

    def test_a_minimum_sensitive_change_shows_the_measured_direction_and_sensitivity(self):
        before = campaign(1, own=(100,) * 4)
        current = campaign(2, own=(101,) * 4)
        for task in TASKS:
            current["tasks"][task]["cpp-clang-cl"]["run"]["samples"] = [100, 110]
        change = metrics.previous_change(current, [before], TASKS, "swag-release", "run", "ms", "native")
        self.assertEqual(change["saved_ms"], -4)
        self.assertEqual(change["sensitivity_ms"], [-4, 36])
        markup, note = mkpage.trend(change)
        self.assertIn("trend regressed", markup)
        self.assertIn("Time gap increased", note)
        self.assertIn("change from -4.0 ms to +36.0 ms", note)
        self.assertIn("+4.0 ms now", note)

    def test_one_observation_shows_the_measured_direction_and_missing_repeat_evidence(self):
        before = campaign(1, own=(100,) * 4)
        current = campaign(2, own=(50,) * 4)
        current["tasks"]["one"]["swag-release"]["run"]["samples"] = [50]
        change = metrics.previous_change(current, [before], TASKS, "swag-release", "run", "ms", "native")
        self.assertIsNone(change["sensitivity_ms"])
        markup, note = mkpage.trend(change)
        self.assertIn("trend improved", markup)
        self.assertIn("repeated samples are missing", note)

    def test_headline_arrows_follow_printed_gaps_despite_overlapping_sample_ranges(self):
        before = campaign(1, own=(99,) * 4)
        for family, group in (("run", "native"), ("build", None)):
            for own, state, arrow in ((98, "improved", "&uarr;"), (100, "regressed", "&darr;"),
                                      (99.001, "unchanged", "&rarr;")):
                with self.subTest(family=family, own=own):
                    current = campaign(2, own=(own,) * 4)
                    for task in TASKS:
                        current["tasks"][task]["swag-release"][family]["samples"] = [own, own + 10]
                        current["tasks"][task]["cpp-clang-cl"][family]["samples"] = [100, 110]
                    markup = mkpage.competitive_stat(current, [before], TASKS, "swag-release",
                                                     family, group, "Time")
                    self.assertIn('class="trend %s"' % state, markup)
                    self.assertIn(arrow, markup)
                    self.assertIn("removing each selected minimum", markup)

    def test_timer_faults_do_not_inflate_the_sensitivity_range(self):
        current = campaign(2, own=(50,) * 4)
        for task in TASKS:
            current["tasks"][task]["swag-release"]["run"]["samples"] = [1, 50, 51]
        self.assertEqual(metrics.minimum_sensitivity(current, TASKS, "swag-release", "run", "ms"), [200, 204])

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
        self.assertIn("-200.0<em>ms</em>", markup)
        self.assertIn("4 ahead", markup)
        self.assertIn("Swag total: 200.0 ms", markup)
        self.assertIn("Non-Swag rival total: 400.0 ms", markup)
        self.assertIn("trend improved", markup)
        self.assertNotIn("&times;", markup)

    def test_total_headline_handles_losses_parity_and_seconds(self):
        for own, expected in ((200, "+400.0<em>ms</em>"), (100, "0.0<em>ms</em>"),
                              (1000, "+3.60<em>s</em>")):
            with self.subTest(own=own):
                current = campaign(2, own=(own,) * 4)
                markup = mkpage.competitive_stat(current, [], TASKS, "swag-release", "run", "native", "Native execution")
                self.assertIn(expected, markup)
                self.assertNotIn("%", markup)

    def test_jit_headline_names_its_rivals_and_excludes_both_swag_modes(self):
        current = campaign(2, own=(50,) * 4)
        for i, task in enumerate(TASKS):
            current["tasks"][task]["swc-jit-devmode"] = {"run": {"ms": 80}}
            current["tasks"][task]["csharp-jit"] = {"run": {"ms": 80 if i < 2 else 140}}
        markup = mkpage.competitive_stat(current, [], TASKS, "swc-jit-release", "run", "jit", "JIT execution")
        self.assertIn("-200.0<em>ms</em>", markup)
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
    @staticmethod
    def comparison_values(row):
        return [row[1]] + [re.search(r'class="comparison-gap [^"]+">([^<]+)', cell).group(1)
                           if 'class="comparison-gap' in cell else cell for cell in row[2:]]

    def test_direct_comparisons_use_each_competitors_total_against_every_swag_mode(self):
        current = campaign(2, own=(1, 2, 3, 1000), rival=(100,) * 4)
        for task in TASKS:
            current["tasks"][task]["swc-jit-devmode"] = {"run": {"ms": 500}}
            current["tasks"][task]["python3.12"]["run"]["ms"] = 0.01
        current["tasks"]["hello"] = {"cpp-clang-cl": {"run": {"ms": 999999}}}
        with mock.patch.object(mkpage, "simple_table", side_effect=lambda headers, rows: (headers, rows)):
            headers, rows = mkpage.swag_comparison_table(current, TASKS, "run")
        self.assertEqual(len(headers), 6)
        self.assertIn("total 1.01 s", headers[2])
        self.assertIn("total 0.04 ms", headers[3])
        self.assertIn("total 2.00 s", headers[5])
        # All competitors appear, including JIT and interpreted runtimes; Swag only heads columns.
        self.assertEqual(len(rows), 3)
        self.assertEqual(self.comparison_values(rows[0]), ["400.0 ms", "+606.0 ms", "-400.0 ms", "+606.0 ms", "+1.60 s"])
        self.assertEqual(rows[1][1:], rows[0][1:])
        self.assertIn("Node", rows[1][0])
        self.assertIn("CPython", rows[2][0])
        self.assertEqual(self.comparison_values(rows[2]), ["0.04 ms", "+1.01 s", "0.0 ms", "+1.01 s", "+2.00 s"])

    def test_direct_comparisons_never_sum_an_incomplete_or_invalid_panel(self):
        for record in ({}, {"ms": 0}, {"ms": float("nan")}, {"ms": 50, "error": "failed"}):
            with self.subTest(record=record):
                current = campaign(2)
                current["tasks"]["four"]["cpp-clang-cl"]["run"] = record
                del current["tasks"]["four"]["swag-release"]["run"]
                with mock.patch.object(mkpage, "simple_table", side_effect=lambda headers, rows: (headers, rows)):
                    headers, rows = mkpage.swag_comparison_table(current, TASKS, "run")
                self.assertIn("total &mdash;", headers[2])
                self.assertEqual(rows[0][1:], ["&mdash;"] * 5)
                self.assertEqual(rows[1][1], "400.0 ms")
                self.assertEqual(rows[1][2], "&mdash;")
                self.assertIn('class="comparison-gap won">-400.0 ms', rows[1][3])

    def test_direct_build_comparisons_use_build_records_and_both_native_configurations(self):
        current = campaign(2, own=(10,) * 4)
        # An interpreted runtime without a build recipe has no compilation row.
        for task in TASKS:
            del current["tasks"][task]["python3.12"]["build"]
            current["tasks"][task]["cpp-clang-cl"]["build"]["wall_ms"] = 500
            current["tasks"][task]["swag-devmode"]["build"]["wall_ms"] = 100
        with mock.patch.object(mkpage, "simple_table", side_effect=lambda headers, rows: (headers, rows)):
            headers, rows = mkpage.swag_comparison_table(current, TASKS, "build")
        self.assertEqual(len(headers), 4)
        self.assertEqual(len(rows), 2)
        self.assertIn("total 40.0 ms", headers[2])
        self.assertIn("total 400.0 ms", headers[3])
        self.assertEqual(self.comparison_values(rows[0]), ["2.00 s", "-1.96 s", "-1.60 s"])
        self.assertEqual(self.comparison_values(rows[1]), ["400.0 ms", "-360.0 ms", "0.0 ms"])

    def test_direct_comparison_colours_and_arrows_use_the_same_rival_without_old_values(self):
        before = campaign(1, own=(100,) * 4, rival=(200,) * 4)
        current = campaign(3, own=(50,) * 4, rival=(200,) * 4)
        for task in TASKS:
            before["tasks"][task]["python3.12"]["run"]["ms"] = 25
            before["tasks"][task]["python3.12"]["run"]["samples"] = [25, 25]
            current["tasks"][task]["python3.12"]["run"]["ms"] = 10
            current["tasks"][task]["python3.12"]["run"]["samples"] = [10, 10]
        incomplete = campaign(2)
        del incomplete["tasks"]["four"]
        with mock.patch.object(mkpage, "simple_table", side_effect=lambda headers, rows: (headers, rows)):
            _, rows = mkpage.swag_comparison_table(current, TASKS, "run", [before, incomplete])
        self.assertIn('class="comparison-gap won">-600.0 ms', rows[0][2])
        self.assertIn('class="trend improved"', rows[0][2])
        self.assertIn('class="comparison-gap lost">+160.0 ms', rows[2][2])
        self.assertIn('class="trend improved"', rows[2][2])  # A loss can still improve.
        self.assertIn("campaign-01", rows[0][2])
        self.assertNotIn("previous-value", rows[0][2])
        self.assertNotIn("400.0 ms", rows[0][2])
        # The interpreter is the fastest rival, but cannot replace clang in clang's arrow.
        self.assertNotIn('class="trend regressed"', rows[0][2])

    def test_compact_trend_keeps_direction_without_the_previous_number(self):
        base = {"reference": campaign(1)["meta"], "tasks": 4, "previous_saved_ms": 100}
        for current, state, arrow in ((200, "improved", "&uarr;"), (50, "regressed", "&darr;"),
                                       (100.01, "unchanged", "&rarr;")):
            markup, _ = mkpage.trend(dict(base, current_saved_ms=current, saved_ms=current - 100),
                                     show_previous=False)
            self.assertIn('class="trend %s"' % state, markup)
            self.assertIn(arrow, markup)
            self.assertNotIn("100.0 ms", markup)
            self.assertNotIn("previous-value", markup)

    def test_jit_and_interpreters_share_one_reference_in_headlines_totals_and_history(self):
        before = campaign(1, own=(100,) * 4)
        current = campaign(2, own=(50,) * 4)
        for item in (before, current):
            for task in TASKS:
                item["tasks"][task]["python3.12"]["run"]["ms"] = 25
                item["tasks"][task]["python3.12"]["run"]["samples"] = [25, 25]
        summary = metrics.comparison(current, TASKS, "swc-jit-release", "run", "ms",
                                     metrics.rivals(current, TASKS, "run", "ms", "jit"))
        self.assertEqual(summary["reference_runtime"], "python3.12")
        self.assertEqual(summary["saved_ms"], -100)
        headline = mkpage.competitive_stat(current, [before], TASKS, "swc-jit-release", "run", "jit", "JIT")
        self.assertIn("Reference: CPython (interpreted)", headline)
        self.assertIn("+100.0<em>ms</em>", headline)
        self.assertIn("trend improved", headline)
    def test_task_ranking_orders_all_modes_and_shows_only_measured_times(self):
        times = {"swag-devmode": 200, "rust": 150, "node20": 125,
                 "swag-release": 50, "cpp-clang-cl": 100, "go": float("nan")}
        markup = mkpage.performance_table(["one"], list(times), lambda rt, task: times[rt])
        order = [markup.index('<li class="l-%s"' % cls)
                 for cls in ("swag", "clang", "js", "rust", "swagdev", "go")]
        self.assertEqual(order, sorted(order))
        self.assertIn('class="speed-value">50.0 ms', markup)
        self.assertNotIn('comparison-gap', markup)
        self.assertNotIn('Swag delta', markup)
        self.assertIn('title="JavaScript / Node V8 (JIT)"', markup)
        self.assertNotIn('class="speed-name"', markup)
        self.assertNotIn('<br>', markup)
        self.assertEqual(markup.count('<tr><th scope="row"'), 1)
        self.assertIn("No measurement", markup)
        self.assertNotIn("nan", markup)
        self.assertNotIn("non-Swag reference</th>", markup)
        self.assertEqual(markup.count("<table "), 1)

    def test_each_example_is_sorted_independently(self):
        times = {"one": {"swc-jit-release": 10, "csharp-jit": 20, "java-hotspot": 40},
                 "two": {"swc-jit-release": 50, "csharp-jit": 40, "java-hotspot": 20}}
        markup = mkpage.performance_table(times, list(times["one"]), lambda rt, task: times[task][rt])
        rows = markup.split('<tr><th scope="row"')[1:]
        first, second = (row.split('</tr>')[0] for row in rows)
        self.assertLess(first.index('class="l-swagjit"'), first.index('class="l-csjit"'))
        self.assertLess(first.index('class="l-csjit"'), first.index('class="l-java"'))
        self.assertLess(second.index('class="l-java"'), second.index('class="l-csjit"'))
        self.assertLess(second.index('class="l-csjit"'), second.index('class="l-swagjit"'))

    def test_missing_time_stays_blank_beside_measured_times(self):
        markup = mkpage.performance_table(["one"], ["swag-release", "rust"],
                                          lambda rt, task: 50 if rt == "swag-release" else None)
        self.assertIn('class="speed-value">50.0 ms', markup)
        self.assertIn("No measurement", markup)
        self.assertNotIn('class="time-gap', markup)

    def test_execution_tables_separate_families(self):
        times = {"swag-release": 50, "cpp-clang-cl": 100,
                 "swc-jit-release": 10, "node20": 20, "python3.12": 5}
        markup = mkpage.execution_tables(["one"], list(times), lambda rt, task: times[rt])
        native, jit = markup.split('<h3>JIT / interpreted</h3>')
        self.assertIn('<h3>Native / AOT</h3>', native)
        self.assertEqual(markup.count('<table class="performance"'), 2)
        for table in (native, jit):
            self.assertEqual(table.count('<tr><th scope="row"'), 1)
            self.assertNotIn('<br>', table)
        self.assertNotIn('comparison-gap', markup)
        self.assertIn('class="speed-value">50.0 ms', native)
        self.assertIn('class="speed-value">5.0 ms', jit)
        self.assertNotIn('Node', native)
        self.assertNotIn('CPython', native)
        self.assertNotIn('clang-cl', jit)


if __name__ == "__main__":
    unittest.main()
