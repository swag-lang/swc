"""How samples are scheduled: rounds, pairs, stopping, and interference.

A measurement is a set of *units* sampled in rounds. A unit is one runtime, or a pair:
the compiler under test and the frozen reference. In every round each unit still owed
samples is visited once, in an order drawn at random, and the two members of a pair are
measured back to back in a random order. A slow stretch of machine time is therefore
shared by everyone instead of landing on one runtime, and each member of a pair shares
its minute with the other.

Each series stops on evidence rather than on a count: once it has its minimum number of
samples, it stops when the 95 % interval of its median is narrower than its target, when
it has spent its time budget, or at its maximum count. The first round is a pilot that
prices every series, so a three-second interpreter run and a twenty-millisecond native
run each get a plan they can afford.

A sample taken while somebody else kept more cores busy than the family's running median
plus `machine.FOREIGN_EXCESS_CORES` is set aside, the driver waits for a quiet machine,
and the sample is taken again.
A sample still contended after every attempt is kept and flagged; the campaign counts
them and refuses to publish when there are too many.
"""
import hashlib
import random

import machine
import stats

# A self-timed run cannot be twice as fast as its next fastest sample. Across every
# archived campaign the widest honest gap is 0.57, a JIT's warm run against its cold ones;
# a clock that reads short (Go's time.Now once read 0.5 ms for a 10.5 ms raytrace) reads
# far below. Such a sample is a timer fault and is set aside.
TIMER_FAULT_RATIO = 0.5


class Plan:
    def __init__(self, min_n, max_n, target, budget_ms):
        self.min_n, self.max_n, self.target, self.budget_ms = min_n, max_n, target, budget_ms

    def as_dict(self):
        return {"min": self.min_n, "max": self.max_n, "target": self.target, "budget_ms": self.budget_ms}


def plan_run(tracked, pilot_ms):
    if tracked:
        return Plan(10, 30, 0.01, 4000) if pilot_ms < 1000 else Plan(5, 10, 0.01, 30000)
    return Plan(7, 20, 0.02, 2500) if pilot_ms < 1000 else Plan(3, 5, 0.03, 20000)


def plan_build(tracked, pilot_ms):
    if tracked:
        return Plan(8, 20, 0.015, 5000) if pilot_ms < 2500 else Plan(5, 10, 0.02, 40000)
    return Plan(5, 12, 0.03, 5000) if pilot_ms < 1500 else Plan(3, 5, 0.05, 25000)


def plan_loop(pilot_ms):
    return Plan(5, 12, 0.02, 15000) if pilot_ms < 5000 else Plan(3, 5, 0.03, 60000)


def quick_plan(*_):
    return Plan(1, 1, 1.0, 0)


def honest(values):
    """Set aside the lowest samples that a clock read short, keeping two to judge by."""
    ordered = sorted(values)
    faults = []
    while len(ordered) >= 3 and ordered[0] < TIMER_FAULT_RATIO * ordered[1]:
        faults.append(ordered.pop(0))
    return ordered, faults


class SampleError(Exception):
    """A sample that failed outright: a crash, a missing artifact, a bad checksum."""


class Series:
    """Everything one runtime produced in one measurement."""

    def __init__(self, key):
        self.key = key
        self.samples = []
        self.set_aside = []
        self.error = None
        self.plan = None

    def values(self):
        values = [s[self.key] for s in self.samples]
        return honest(values)[0] if self.key == "ms" else values

    def spent_ms(self):
        return sum(s.get("wall_ms", 0.0) for s in self.samples)

    def estimate(self):
        return stats.estimate(self.values())

    def needs_more(self):
        if self.error or self.plan is None:
            return False
        n = len(self.samples)
        if n < self.plan.min_n:
            return True
        if n >= self.plan.max_n or self.spent_ms() >= self.plan.budget_ms:
            return False
        e = self.estimate()
        return e is None or e.relative_halfwidth > self.plan.target

    def as_dict(self):
        out = {"samples": self.samples}
        if self.set_aside:
            out["set_aside"] = self.set_aside
        if self.error:
            out["error"] = self.error
        if self.plan:
            out["plan"] = self.plan.as_dict()
        if self.key == "ms":
            faults = honest([s["ms"] for s in self.samples])[1]
            if faults:
                out["timer_faults"] = faults
        return out


def guarded(take, waits, baseline, quiet_limit_s=machine.QUIET_WAIT_S, attempts=machine.SAMPLE_ATTEMPTS,
            log=None, name=""):
    """Take one sample, again while somebody else was using the machine.

    `take()` returns a record carrying `foreign_cores`; `baseline` is the family's
    machine.Baseline. Returns (record, set-aside records).
    """
    set_aside = []
    for attempt in range(attempts):
        record = take()
        if not baseline.judge(record):
            record["attempts"] = attempt + 1
            baseline.accept(record)
            return record, set_aside
        set_aside.append(record)
        quiet, waited, load = machine.wait_for_quiet(quiet_limit_s)
        waits.append(waited)
        if log:
            log("  %-20s interference: %.1f foreign cores (limit %.1f), waited %.0f s for quiet%s"
                % (name, record["foreign_cores"], record["foreign_limit"], waited,
                   "" if quiet else ", machine still busy (%.1f)" % load))
    record = set_aside.pop()
    record["attempts"] = attempts
    record["contended"] = True
    return record, set_aside


def run_rounds(units, take, plan_for, key, rng, waits, baseline, log=None):
    """Sample every unit until each of its series has the evidence its plan asks for.

    units: list of tuples of runtime names. take(name, round) returns a record carrying
    `key` and `foreign_cores`, or raises SampleError. plan_for(name, pilot) returns a Plan.
    """
    series = {name: Series(key) for unit in units for name in unit}

    def visit(unit, rnd):
        members = list(unit)
        rng.shuffle(members)
        for name in members:
            s = series[name]
            if s.error:
                continue
            try:
                record, set_aside = guarded(lambda: take(name, rnd), waits, baseline, log=log, name=name)
            except SampleError as error:
                s.error = str(error)
                if log:
                    log("  %-20s ERROR %s" % (name, s.error))
                continue
            record["round"] = rnd
            s.samples.append(record)
            s.set_aside.extend(dict(r, round=rnd) for r in set_aside)
            if s.plan is None:
                s.plan = plan_for(name, record.get("wall_ms", record[key]))

    order = list(units)
    rng.shuffle(order)
    for unit in order:
        visit(unit, 0)
    rnd = 1
    while True:
        due = [u for u in units if any(series[n].needs_more() for n in u)]
        if not due:
            break
        rng.shuffle(due)
        for unit in due:
            visit(unit, rnd)
        rnd += 1
    if log:
        for name, s in series.items():
            e = s.estimate()
            if s.error:
                continue
            log("  %-20s median %10.2f  %s  n=%-3d%s" % (
                name, e.value if e else (s.samples[0][key] if s.samples else 0.0),
                ("+/-%.1f %%" % (100 * e.relative_halfwidth)) if e else "  (one sample)",
                len(s.samples), ("  %d taken again" % len(s.set_aside)) if s.set_aside else ""))
    return series


def campaign_rng(stamp, label):
    """One recorded seed per measurement, so the sampling order can be reproduced."""
    seed = int(hashlib.sha256(("%s/%s" % (stamp, label)).encode("utf-8")).hexdigest()[:8], 16)
    return random.Random(seed), seed
