"""Rounds, pairing, stopping rules and interference handling, with simulated samples."""
import os
import random
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import machine
import sampler


def quiet_record(value, foreign=1.0):
    return {"ms": value, "wall_ms": value, "foreign_cores": foreign}


class RoundTests(unittest.TestCase):
    def setUp(self):
        patcher = mock.patch.object(machine, "wait_for_quiet", return_value=(True, 0.0, 0.5))
        patcher.start()
        self.addCleanup(patcher.stop)

    def run_units(self, units, take, plan):
        return sampler.run_rounds(units, take, lambda name, pilot: plan, "ms", random.Random(1), [],
                                  machine.Baseline())

    def test_pairs_share_every_round(self):
        rng = random.Random(5)
        series = self.run_units([("a", "ref"), ("c",)],
                                lambda name, rnd: quiet_record(10 + rng.random()),
                                sampler.Plan(6, 9, 0.0001, 10 ** 9))
        self.assertEqual([s["round"] for s in series["a"].samples], [s["round"] for s in series["ref"].samples])
        self.assertGreaterEqual(len(series["c"].samples), 6)

    def test_a_precise_series_stops_at_its_minimum(self):
        series = self.run_units([("a",)], lambda name, rnd: quiet_record(10.0), sampler.Plan(5, 30, 0.05, 10 ** 9))
        self.assertEqual(len(series["a"].samples), 5)

    def test_a_noisy_series_samples_up_to_its_maximum(self):
        rng = random.Random(2)
        series = self.run_units([("a",)], lambda name, rnd: quiet_record(10.0 * (1 + rng.random())),
                                sampler.Plan(5, 12, 0.001, 10 ** 9))
        self.assertEqual(len(series["a"].samples), 12)

    def test_the_budget_stops_a_slow_series(self):
        series = self.run_units([("a",)], lambda name, rnd: quiet_record(1000.0 + rnd),
                                sampler.Plan(3, 30, 0.0, 3500))
        self.assertEqual(len(series["a"].samples), 4)

    def test_a_failure_stops_only_its_series(self):
        def take(name, rnd):
            if name == "bad":
                raise sampler.SampleError("exit=3")
            return quiet_record(5.0)
        series = self.run_units([("good",), ("bad",)], take, sampler.Plan(3, 3, 1.0, 10 ** 9))
        self.assertEqual(series["bad"].error, "exit=3")
        self.assertEqual(len(series["good"].samples), 3)

    def test_a_visitor_is_set_aside_and_measured_again(self):
        readings = iter([1.0] * 6 + [9.0, 1.2] + [1.0] * 20)

        def take(name, rnd):
            return quiet_record(10.0, next(readings))
        series = self.run_units([("a",)], take, sampler.Plan(8, 8, 1.0, 10 ** 9))
        s = series["a"]
        self.assertEqual(len(s.samples), 8)
        self.assertEqual(len(s.set_aside), 1)
        self.assertEqual(s.set_aside[0]["foreign_cores"], 9.0)
        self.assertFalse(any(x.get("contended") for x in s.samples))

    def test_a_sample_still_contended_is_kept_and_flagged(self):
        readings = iter([1.0] * 5 + [9.0] * machine.SAMPLE_ATTEMPTS + [1.0] * 10)
        series = self.run_units([("a",)], lambda name, rnd: quiet_record(10.0, next(readings)),
                                sampler.Plan(6, 6, 1.0, 10 ** 9))
        s = series["a"]
        self.assertEqual(sum(1 for x in s.samples if x.get("contended")), 1)
        self.assertEqual(len(s.set_aside), machine.SAMPLE_ATTEMPTS - 1)


class BaselineTests(unittest.TestCase):
    def test_the_limit_follows_the_family_median(self):
        b = machine.Baseline()
        self.assertEqual(b.limit(), machine.FOREIGN_CEILING_CORES)
        for v in (3.0, 3.5, 2.5, 3.0, 3.2):
            b.accept({"foreign_cores": v})
        self.assertAlmostEqual(b.limit(), 3.0 + machine.FOREIGN_EXCESS_CORES)
        self.assertTrue(b.judge({"foreign_cores": 6.0}))
        self.assertFalse(b.judge({"foreign_cores": 5.0}))


class TimerFaultTests(unittest.TestCase):
    def test_a_clock_that_reads_short_is_set_aside(self):
        self.assertEqual(sampler.honest([0.5, 10.5, 11.0, 12.0])[1], [0.5])
        self.assertEqual(sampler.honest([0.5, 10.5])[1], [])
        self.assertEqual(sampler.honest([6.0, 10.5, 11.0])[1], [])

    def test_the_seed_is_reproducible(self):
        a, seed_a = sampler.campaign_rng("20261021-120000", "x")
        b, seed_b = sampler.campaign_rng("20261021-120000", "x")
        self.assertEqual(seed_a, seed_b)
        self.assertEqual(a.random(), b.random())


if __name__ == "__main__":
    unittest.main()
