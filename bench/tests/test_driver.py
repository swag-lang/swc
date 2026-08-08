import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import campaign
import driver
import winproc


class CampaignTests(unittest.TestCase):
    def test_quick_campaign_does_not_rebuild_the_published_report(self):
        with (
            mock.patch.object(sys, "argv", ["campaign.py", "--quick"]),
            mock.patch.object(campaign, "build"),
            mock.patch.object(campaign, "run") as run,
            mock.patch.object(campaign, "warn_if_dirty") as warn_if_dirty,
        ):
            self.assertEqual(campaign.main(), 0)

        self.assertEqual(run.call_args_list, [mock.call("driver.py", ["--quick"])])
        warn_if_dirty.assert_not_called()


class SampleBudgetTests(unittest.TestCase):
    def test_a_fast_runtime_gets_the_ceiling_and_a_slow_one_the_floor(self):
        self.assertEqual(driver.plan_reps(1), driver.RUN_MAX_REPS)
        self.assertEqual(driver.plan_reps(driver.RUN_SLOW_MS - 1), driver.RUN_MIN_REPS)

    def test_a_very_slow_runtime_is_sampled_twice_and_no_more(self):
        self.assertEqual(driver.plan_reps(driver.RUN_SLOW_MS), 2)
        self.assertEqual(driver.plan_reps(driver.RUN_SLOW_MS * 4), 2)

    def test_the_count_never_rises_with_the_duration(self):
        counts = [driver.plan_reps(d) for d in (1, 10, 100, 1000, 5000, 19000)]
        self.assertEqual(counts, sorted(counts, reverse=True))

    def test_a_missing_pilot_falls_back_to_the_floor(self):
        self.assertEqual(driver.plan_reps(None), driver.RUN_MIN_REPS)
        self.assertEqual(driver.plan_builds(None), driver.BUILD_MIN_REPS)


class ScheduleTests(unittest.TestCase):
    def test_every_planned_sample_gets_exactly_one_cycle(self):
        for reps in range(driver.RUN_MAX_REPS + 1):
            self.assertEqual(len(driver.schedule(reps)), reps, reps)

    def test_samples_are_spread_over_the_window_not_bunched(self):
        """Three samples must not all land in the first quarter of the sweep: the
        point of the budget is that every runtime covers the same minutes."""
        for reps in (2, 3, 6, 12):
            cycles = sorted(driver.schedule(reps))
            gaps = [b - a for a, b in zip(cycles, cycles[1:])]
            self.assertLessEqual(max(gaps) - min(gaps), 1, cycles)
            self.assertGreaterEqual(cycles[-1], driver.RUN_MAX_REPS - reps)


class PinTests(unittest.TestCase):
    def test_the_mask_is_one_logical_processor_per_performance_core(self):
        cpus = winproc.topology()
        if not cpus:
            self.skipTest("no CPU set information on this machine")
        best = max(efficiency for _, _, efficiency in cpus)
        cores = {core for _, core, efficiency in cpus if efficiency == best}
        self.assertEqual(bin(winproc.PIN_MASK).count("1"), len(cores))
        for logical, _, efficiency in cpus:
            if winproc.PIN_MASK & (1 << logical):
                self.assertEqual(efficiency, best)


if __name__ == "__main__":
    unittest.main()
