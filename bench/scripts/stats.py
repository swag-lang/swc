"""The statistics every published number goes through.

A benchmark result is an estimate, and an estimate without its uncertainty cannot be
compared with anything. Every value this bench publishes is therefore a median with a
95 % confidence interval, and every comparison is a ratio with one:

  * one series: the median of its samples. The interval comes from order statistics,
    which assume nothing about the distribution: for n samples, [x(j), x(n-j+1)] covers
    the true median with a probability the binomial distribution gives exactly. Timing
    distributions are skewed and heavy-tailed, so a mean and a standard deviation would
    describe them badly; the median and this interval do not depend on the shape.
  * two independent series (Swag against another language): the ratio of their medians.
    Its uncertainty adds in log space, which is where ratios live.
  * two paired series (the compiler under test against the frozen reference, sampled
    side by side in every round): the median of the per-round ratios. Pairing is what
    cancels the machine's drift, since both members of a pair share the same minute.
  * a panel of tasks: the geometric mean of the per-task ratios, as SPEC does, with the
    per-task uncertainties combined. The interval describes measurement noise on this
    fixed panel, not how representative the panel is of all programs.

A comparison is called faster or slower only when its whole interval lies on one side of
parity; otherwise it is a tie. This is the only verdict the report draws.
"""
import math
import statistics

LEVEL = 0.95
Z = statistics.NormalDist().inv_cdf(0.5 + LEVEL / 2)

# A series whose samples are all equal has a zero-width interval, which would claim a
# precision no timer has. Every log-space standard error is floored at this, 0.2 %.
SE_FLOOR = 0.002


def median(values):
    return statistics.median(values) if values else None


def _binomial_cdf(k, n):
    """P(X <= k) for X ~ Binomial(n, 1/2)."""
    if k < 0:
        return 0.0
    return sum(math.comb(n, i) for i in range(min(k, n) + 1)) / 2.0 ** n


def median_interval(values, level=LEVEL):
    """Distribution-free interval for the median: (low, high, coverage).

    The narrowest symmetric pair of order statistics whose coverage reaches `level`.
    Below six samples no such pair exists; the full range is returned with the smaller
    coverage it actually has, and the caller widens it (see `estimate`).
    """
    ordered = sorted(values)
    n = len(ordered)
    if n == 0:
        return None
    if n == 1:
        return ordered[0], ordered[0], 0.0
    best = 1
    for j in range(1, n // 2 + 1):
        if 1.0 - 2.0 * _binomial_cdf(j - 1, n) >= level:
            best = j
        else:
            break
    coverage = 1.0 - 2.0 * _binomial_cdf(best - 1, n)
    return ordered[best - 1], ordered[n - best], coverage


class Estimate:
    """A positive quantity: its point value, its interval and its log-space error."""

    __slots__ = ("value", "low", "high", "n", "se", "exact")

    def __init__(self, value, low, high, n, se, exact):
        self.value, self.low, self.high, self.n, self.se, self.exact = value, low, high, n, se, exact

    @property
    def relative_halfwidth(self):
        return (self.high - self.low) / (2.0 * self.value) if self.value else math.inf

    def verdict(self):
        """For a ratio Swag / other: 'faster', 'slower' or 'tie'."""
        if self.high < 1.0:
            return "faster"
        if self.low > 1.0:
            return "slower"
        return "tie"

    def as_dict(self):
        return {"value": self.value, "low": self.low, "high": self.high, "n": self.n,
                "se": self.se, "exact": self.exact}

    @staticmethod
    def from_dict(d):
        return Estimate(d["value"], d["low"], d["high"], d["n"], d["se"], d["exact"]) if d else None

    def __repr__(self):
        return "Estimate(%.4g [%.4g, %.4g] n=%d)" % (self.value, self.low, self.high, self.n)


def _from_log(log_value, se, n, exact_bounds=None):
    se = max(se, SE_FLOOR)
    if exact_bounds:
        low, high = exact_bounds
        exact = True
    else:
        low, high = math.exp(log_value - Z * se), math.exp(log_value + Z * se)
        exact = False
    return Estimate(math.exp(log_value), low, high, n, se, exact)


def estimate(values):
    """The median of one series of positive samples, with its 95 % interval.

    With six samples or more the interval is the exact order-statistic one. With fewer,
    the observed range has a known smaller coverage; it is converted into a log-space
    standard error and widened to 95 %, so a two-sample series reads as uncertain as it
    is instead of as precise as its two values happen to look. One sample has no
    interval at all and is returned as None.
    """
    values = [v for v in values if v is not None and math.isfinite(v) and v > 0]
    if len(values) < 2:
        return None
    mid = statistics.median(values)
    low, high, coverage = median_interval(values)
    z = statistics.NormalDist().inv_cdf(0.5 + coverage / 2) if coverage > 0 else None
    span = math.log(high) - math.log(low)
    se = span / (2.0 * z) if z else math.inf
    exact = coverage >= LEVEL and se >= SE_FLOOR
    return _from_log(math.log(mid), se, len(values), (max(low, 0.0), high) if exact else None)


def ratio(a, b):
    """Ratio of two independent medians, a / b."""
    if a is None or b is None:
        return None
    se = math.sqrt(a.se ** 2 + b.se ** 2)
    return _from_log(math.log(a.value) - math.log(b.value), se, min(a.n, b.n))


def paired_ratio(a_values, b_values):
    """Median of the per-round ratios a_i / b_i of two series sampled side by side."""
    pairs = [x / y for x, y in zip(a_values, b_values)
             if x and y and math.isfinite(x) and math.isfinite(y) and x > 0 and y > 0]
    return estimate(pairs)


def geomean(estimates):
    """Geometric mean of independent ratios, with their combined uncertainty."""
    estimates = list(estimates)
    if not estimates or any(e is None for e in estimates):
        return None
    count = len(estimates)
    log_value = sum(math.log(e.value) for e in estimates) / count
    se = math.sqrt(sum(e.se ** 2 for e in estimates)) / count
    return _from_log(log_value, se, min(e.n for e in estimates))


def tally(estimates):
    """How many of the per-task ratios are faster, tied or slower."""
    counts = {"faster": 0, "tie": 0, "slower": 0}
    for e in estimates:
        if e is not None:
            counts[e.verdict()] += 1
    return counts
