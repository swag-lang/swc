"""The estimators every published number goes through."""
import math
import os
import random
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import stats


class MedianIntervalTests(unittest.TestCase):
    def test_order_statistics_reach_the_level_from_six_samples(self):
        self.assertEqual(stats.median_interval(list(range(1, 7)))[:2], (1, 6))
        low, high, coverage = stats.median_interval(list(range(1, 21)))
        self.assertEqual((low, high), (6, 15))
        self.assertGreaterEqual(coverage, 0.95)

    def test_small_series_report_their_true_coverage(self):
        self.assertAlmostEqual(stats.median_interval([3, 1, 2])[2], 0.75)
        self.assertAlmostEqual(stats.median_interval([1, 2])[2], 0.5)

    def test_one_sample_is_not_an_estimate(self):
        self.assertIsNone(stats.estimate([5.0]))
        self.assertIsNone(stats.estimate([]))

    def test_small_series_are_widened_not_trusted(self):
        e = stats.estimate([10.0, 10.5, 11.0])
        self.assertFalse(e.exact)
        self.assertLess(e.low, 10.0)
        self.assertGreater(e.high, 11.0)

    def test_identical_samples_keep_a_floor(self):
        e = stats.estimate([4.0] * 12)
        self.assertGreater(e.high, e.low)
        self.assertAlmostEqual(e.value, 4.0)

    def test_invalid_values_are_ignored(self):
        e = stats.estimate([1.0, 2.0, float("nan"), None, -1.0, 3.0])
        self.assertEqual(e.n, 3)


class CoverageTests(unittest.TestCase):
    """The intervals cover the truth at least as often as they claim."""

    def test_median_interval_coverage(self):
        rng = random.Random(7)
        hits = 0
        for _ in range(800):
            e = stats.estimate([math.exp(rng.gauss(0, 0.05)) for _ in range(12)])
            hits += e.low <= 1.0 <= e.high
        self.assertGreater(hits / 800, 0.93)

    def test_paired_ratio_cancels_shared_drift(self):
        rng = random.Random(11)
        hits = 0
        for _ in range(400):
            drift = [math.exp(rng.gauss(0, 0.15)) for _ in range(12)]
            a = [d * math.exp(rng.gauss(0, 0.01)) for d in drift]
            b = [d * math.exp(rng.gauss(0, 0.01)) for d in drift]
            e = stats.paired_ratio(a, b)
            hits += e.low <= 1.0 <= e.high
            self.assertLess(e.relative_halfwidth, 0.05)
        self.assertGreater(hits / 400, 0.93)

    def test_geomean_coverage(self):
        rng = random.Random(3)
        hits = 0
        for _ in range(300):
            ratios = [stats.ratio(stats.estimate([math.exp(rng.gauss(0, 0.04)) for _ in range(10)]),
                                  stats.estimate([math.exp(rng.gauss(0, 0.04)) for _ in range(10)]))
                      for _ in range(12)]
            g = stats.geomean(ratios)
            hits += g.low <= 1.0 <= g.high
        self.assertGreater(hits / 300, 0.93)


class VerdictTests(unittest.TestCase):
    def test_verdict_needs_the_whole_interval(self):
        self.assertEqual(stats.Estimate(0.9, 0.85, 0.95, 10, 0.02, True).verdict(), "faster")
        self.assertEqual(stats.Estimate(1.1, 1.05, 1.15, 10, 0.02, True).verdict(), "slower")
        self.assertEqual(stats.Estimate(0.97, 0.93, 1.01, 10, 0.02, True).verdict(), "tie")

    def test_tally_counts_each_verdict(self):
        es = [stats.Estimate(0.9, 0.85, 0.95, 10, 0.02, True), stats.Estimate(1.0, 0.98, 1.02, 10, 0.01, True), None]
        self.assertEqual(stats.tally(es), {"faster": 1, "tie": 1, "slower": 0})

    def test_ratio_and_geomean_values(self):
        a = stats.estimate([20.0, 20.2, 19.8, 20.1, 19.9, 20.0])
        b = stats.estimate([10.0, 10.1, 9.9, 10.0, 10.05, 9.95])
        r = stats.ratio(a, b)
        self.assertAlmostEqual(r.value, 2.0, places=2)
        self.assertEqual(r.verdict(), "slower")
        g = stats.geomean([r, stats.ratio(b, a)])
        self.assertAlmostEqual(g.value, 1.0, places=6)
        self.assertIsNone(stats.geomean([r, None]))

    def test_round_trip(self):
        e = stats.estimate([1.0, 1.1, 1.2, 1.3, 1.4, 1.5])
        self.assertEqual(stats.Estimate.from_dict(e.as_dict()).as_dict(), e.as_dict())


if __name__ == "__main__":
    unittest.main()
