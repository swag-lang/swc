"""Build a compact, machine-adjusted history from the raw benchmark campaigns.

Every non-Swag runtime is a control: its compiler and benchmark source stay fixed,
so a systematic movement of those measurements describes the machine rather than
the Swag compiler. Per task, the median logarithmic movement of all controls becomes
the context factor. Dividing Swag by that factor removes machine-wide drift while a
single noisy or upgraded toolchain cannot dominate the correction.

The raw campaign files remain authoritative. Rebuilding the history from them keeps
the correction auditable and lets a better normalization be applied retroactively.
"""
import datetime
import glob
import json
import math
import os
import statistics
import subprocess

import toolchains as tc

HISTORY = os.path.join(tc.BENCH, "history.json")
RESULTS = os.path.join(tc.BENCH, "results", "*.json")

# How the measurement was taken. Two campaigns of different protocols are not
# comparable and must never share a history, so the number is stamped into every
# campaign and campaigns of an earlier protocol live in their own folder, kept as
# evidence and read by nothing.
#
#   1  five repetitions, whatever core the scheduler chose, sha256 on 512 KiB and
#      chacha on 1 MiB — durations of a few milliseconds, below what this machine
#      can resolve.
#   2  runs pinned to the performance cores, samples budgeted per runtime and
#      spread across the window, order rotated, every sample kept, sha256 and
#      chacha scaled sixteenfold.
PROTOCOL = 2

# The reference workload is timed before every task, and before and after the sweep.
# When one of those probes departs from its neighbours in time by more than this, the
# machine had a visitor and the driver archives the campaign instead of recording it.
#
# Neighbours, not the whole timeline: a campaign settles as it runs, opening warmer
# than it ends, and that ramp moves a task's Swag measurement and its controls
# together — which is what the per-task correction exists for. The limit sits just
# above the ramp's own size, so it cannot fire on the machine merely cooling. What it
# catches is a visitor arriving and leaving: a parallel build once multiplied every
# compilation of one task by ten and was gone before the closing calibration, which
# left the campaign reading clean from both ends and fiction in the middle. Against
# that timeline it reads 950 %.
DRIFT_LIMIT_PCT = 40.0

TRACKED = ["swag-release", "swc-jit-release", "swag-fast-debug", "swc-jit-fast-debug"]
BUILT = ["swag-release", "swag-fast-debug"]
MIN_CONTROLS = 3
FAMILIES = (("run", "ms"), ("build", "wall_ms"))
BUILD_REFERENCE = "cpp-msvc"


def geo(values):
    values = [v for v in values if v and v > 0]
    if not values:
        return None
    return math.exp(sum(math.log(v) for v in values) / len(values))


def robust_factor(values):
    """Multiplicative median, suitable for ratios spanning several orders of magnitude."""
    values = [v for v in values if v and v > 0]
    if not values:
        return None
    return math.exp(statistics.median(math.log(v) for v in values))


def dispersion(values, center):
    """Median absolute multiplicative deviation from ``center``, expressed as percent."""
    if not center:
        return None
    residuals = [abs(math.log(v / center)) for v in values if v and v > 0]
    if not residuals:
        return None
    return math.expm1(statistics.median(residuals)) * 100.0


def _git(args, cwd):
    try:
        r = subprocess.run(["git"] + args, cwd=cwd, capture_output=True, text=True)
        return r.stdout.strip() if r.returncode == 0 else ""
    except OSError:
        return ""


def describe(swc, label="", settings=None):
    """Identity of a campaign: when, which commit, which binary, and whether the tree
    carried uncommitted changes at the time — which decides whether the commit alone
    reproduces the measurement."""
    root = tc.worktree()
    stat = os.stat(swc) if os.path.exists(swc) else None
    now = datetime.datetime.now(datetime.timezone.utc)
    return {
        "protocol": PROTOCOL,
        "settings": settings or {},
        "stamp": now.strftime("%Y%m%d-%H%M%S"),
        "date": now.isoformat(timespec="seconds"),
        "label": label,
        "commit": _git(["rev-parse", "--short", "HEAD"], root),
        "subject": _git(["log", "-1", "--format=%s"], root),
        "master": _git(["rev-parse", "--short", "master"], root),
        "dirty": bool(_git(["status", "--porcelain", "--untracked-files=no"], root)),
        "swc": swc,
        "swc_bytes": stat.st_size if stat else 0,
    }


def _metric(entry, family, key):
    return (entry.get(family) or {}).get(key)


def _complete(entries, family, key):
    """Whether one task of one campaign carries enough controls to be a reference."""
    controls = [entry for runtime, entry in entries.items() if runtime not in TRACKED]
    return sum(1 for entry in controls if _metric(entry, family, key)) >= MIN_CONTROLS


def _context(results, refs, panel):
    """Return execution and build context factors, each task against its own reference.

    Each task gets its own factor because the sweep lasts long enough for machine
    conditions to change between tasks. The campaign factor is the geometric mean of
    the panel factors and exists for reporting; correction always uses the finer
    per-task value.
    """
    contexts = {}
    for family, key in FAMILIES:
        task_factors = {}
        task_counts = {}
        task_dispersion = {}
        for task, entries in results["tasks"].items():
            reference = refs[family].get(task)
            if not reference:
                continue
            base_entries = reference["tasks"].get(task, {})
            ratios = []
            for runtime, entry in entries.items():
                if runtime in TRACKED:
                    continue
                current = _metric(entry, family, key)
                before = _metric(base_entries.get(runtime, {}), family, key)
                if current and before:
                    ratios.append(current / before)

            if len(ratios) < MIN_CONTROLS:
                continue
            factor = robust_factor(ratios)
            task_factors[task] = factor
            task_counts[task] = len(ratios)
            task_dispersion[task] = dispersion(ratios, factor)

        weighted_dispersion = []
        for task, value in task_dispersion.items():
            weighted_dispersion.extend([value] * task_counts[task])
        # The campaign factor mixes tasks, so it only averages the panel: a task
        # measured against a later reference does not describe the same interval.
        panel_factors = [v for t, v in task_factors.items() if t in panel[family]]
        contexts[family] = {
            "factor": geo(panel_factors or list(task_factors.values())),
            "task_factors": task_factors,
            "controls": sum(task_counts.values()),
            "dispersion_pct": statistics.median(weighted_dispersion)
                              if weighted_dispersion else None,
        }
    return contexts


def _select_baseline(results):
    """Use the oldest reproducible campaign, falling back to the oldest campaign."""
    for result in results:
        if result.get("meta", {}).get("dirty") or result.get("skipped"):
            continue
        if all(_complete(entries, family, key)
               for entries in result.get("tasks", {}).values()
               for family, key in FAMILIES):
            return result
    return results[0]


def _task_references(results, baseline):
    """Per family and task, the campaign that task is measured against.

    A task the baseline measured is indexed against the baseline, as before. A task
    added to the benchmark later has no baseline value, and indexing it against
    nothing would keep it out of the history altogether however many campaigns have
    since measured it. It is indexed instead against the first reproducible campaign
    that measured it, which therefore reads 1.00.
    """
    refs = {}
    for family, key in FAMILIES:
        per_task = {}
        for result in results:
            if result.get("meta", {}).get("dirty") or result.get("skipped"):
                continue
            for task, entries in result.get("tasks", {}).items():
                if task not in per_task and _complete(entries, family, key):
                    per_task[task] = result
        for task, entries in baseline.get("tasks", {}).items():
            if _complete(entries, family, key):
                per_task[task] = baseline
        refs[family] = per_task
    return refs


def _null_indices(results, refs, panel):
    """Apply the whole correction to each unchanged control, as if it were the compiler.

    A control's source and toolchain are identical from one campaign to the next, so its
    corrected index should read exactly 1.00. What it reads instead is the resolution of
    this harness: a movement of the Swag curve inside that band has not been measured.
    Each control is corrected by the median of the *other* controls, never by a set
    containing itself, which would flatten it towards 1.00 for free.
    """
    nulls = {}
    for family, key in FAMILIES:
        per_task = {}
        for task in results["tasks"]:
            reference = refs[family].get(task)
            if not reference:
                continue
            base = reference["tasks"].get(task, {})
            ratios = {}
            for runtime, entry in results["tasks"].get(task, {}).items():
                if runtime in TRACKED:
                    continue
                current = _metric(entry, family, key)
                before = _metric(base.get(runtime, {}), family, key)
                if current and before:
                    ratios[runtime] = current / before
            if len(ratios) <= MIN_CONTROLS:
                continue
            for runtime, ratio in ratios.items():
                factor = robust_factor([v for k, v in ratios.items() if k != runtime])
                if factor:
                    per_task.setdefault(runtime, {})[task] = ratio / factor
        # The band on the aggregate covers the panel, exactly like the aggregate itself.
        indices = {rt: geo([v for t, v in vs.items() if t in panel[family]])
                   for rt, vs in per_task.items()}
        indices = {rt: v for rt, v in indices.items() if v}
        task_spread = {}
        for task in results["tasks"]:
            values = [vs[task] for vs in per_task.values() if task in vs]
            if values:
                task_spread[task] = [min(values), max(values)]
        nulls[family] = {
            "controls": len(indices),
            "geo": [min(indices.values()), max(indices.values())] if indices else None,
            "tasks": task_spread,
        }
    return nulls


def _headline(results, panel):
    """The ratios the report leads with, recomputed for every campaign.

    They compare Swag with runtimes measured in the same campaign, so they carry no
    machine drift and take no correction. They are computed over the panel only: a
    task that joined the benchmark later would otherwise move the geometric mean on
    the campaign it first appeared in, which would read as a compiler movement.
    """
    tasks = results["tasks"]
    task_ids = [t for t in tasks if t in panel] or list(tasks)

    def ms(rt, task):
        return (tasks[task].get(rt, {}).get("run") or {}).get("ms")

    def wall(rt, task):
        return (tasks[task].get(rt, {}).get("build") or {}).get("wall_ms")

    present = [rt for rt in tasks[task_ids[0]] if all(ms(rt, t) for t in task_ids)]
    if not present:
        return {}
    best = {t: min(ms(rt, t) for rt in present) for t in task_ids}
    run_geo = {rt: geo([ms(rt, t) / best[t] for t in task_ids]) for rt in present}
    build_geo = {rt: geo([wall(rt, t) for t in task_ids])
                 for rt in present if all(wall(rt, t) for t in task_ids)}
    native = run_geo.get("swag-release")
    jit = run_geo.get("swc-jit-release")
    swag_build = build_geo.get("swag-release")
    reference_build = build_geo.get(BUILD_REFERENCE)
    return {
        "tasks": len(task_ids),
        "exec_vs_best": native,
        "exec_fastest": min(run_geo, key=lambda rt: run_geo[rt]) if run_geo else None,
        "jit_gap_pct": (jit / native - 1.0) * 100.0 if native and jit else None,
        "build_edge": (reference_build / swag_build
                       if swag_build and reference_build else None),
    }


def condense(results, refs=None, baseline=None):
    """Turn one raw campaign into the compact, adjusted entry kept in the history."""
    baseline = baseline or results
    refs = refs or _task_references([results], baseline)
    tasks = results["tasks"]
    task_ids = list(tasks)
    panel = {family: {t for t, r in refs[family].items() if r is baseline}
             for family, _ in FAMILIES}
    context = _context(results, refs, panel)

    def ms(rt, task):
        return tasks[task].get(rt, {}).get("run", {}).get("ms")

    def build(rt, task, key):
        return (tasks[task].get(rt, {}).get("build") or {}).get(key)

    def baseline_metric(rt, task, family, key):
        reference = refs[family].get(task)
        if not reference:
            return None
        return _metric(reference["tasks"].get(task, {}).get(rt, {}), family, key)

    def factor(family, task):
        family_context = context[family]
        return family_context["task_factors"].get(task) or family_context["factor"] or 1.0

    entry = {
        "meta": results["meta"],
        "drift_pct": results["calibration"].get("drift_pct"),
        "machine_spread_pct": results["calibration"].get("spread_pct"),
        "worst_moment": results["calibration"].get("worst_moment"),
        "calibration_ms": results["calibration"].get("start"),
        "context": {
            "baseline": baseline["meta"].get("stamp"),
            "baseline_commit": baseline["meta"].get("commit"),
            "task_baselines": {t: refs["run"][t]["meta"].get("commit")
                               for t in task_ids
                               if t in refs["run"] and t not in panel["run"]},
            "run_factor": context["run"]["factor"],
            "run_task_factors": context["run"]["task_factors"],
            "run_controls": context["run"]["controls"],
            "run_dispersion_pct": context["run"]["dispersion_pct"],
            "build_factor": context["build"]["factor"],
            "build_task_factors": context["build"]["task_factors"],
            "build_controls": context["build"]["controls"],
            "build_dispersion_pct": context["build"]["dispersion_pct"],
        },
        "runtimes": {},
    }

    for rt in TRACKED:
        if rt not in tasks[task_ids[0]]:
            continue
        run_ms = {t: ms(rt, t) for t in task_ids}
        adjusted_ms = {t: (run_ms[t] / factor("run", t)) if run_ms[t] else None
                       for t in task_ids}
        run_index = {}
        for task in task_ids:
            base = baseline_metric(rt, task, "run", "ms")
            run_index[task] = adjusted_ms[task] / base if adjusted_ms[task] and base else None
        # Aggregates cover the panel only, so a task joining the benchmark cannot
        # step the curve. Per-task values below cover everything measured.
        rec = {
            "run_ms": run_ms,
            "run_adjusted_ms": adjusted_ms,
            "run_geo_adjusted_ms": geo([adjusted_ms[t] for t in panel["run"]
                                        if t in adjusted_ms]),
            "run_index": run_index,
            "run_geo_index": geo([run_index[t] for t in panel["run"] if t in run_index]),
        }
        if rt in BUILT:
            b_ms = {t: build(rt, t, "wall_ms") for t in task_ids}
            b_adjusted = {t: (b_ms[t] / factor("build", t)) if b_ms[t] else None
                          for t in task_ids}
            b_index = {}
            for task in task_ids:
                base = baseline_metric(rt, task, "build", "wall_ms")
                b_index[task] = b_adjusted[task] / base if b_adjusted[task] and base else None
            rec["build_ms"] = b_ms
            rec["build_adjusted_ms"] = b_adjusted
            rec["build_geo_adjusted_ms"] = geo([b_adjusted[t] for t in panel["build"]
                                                if t in b_adjusted])
            rec["build_index"] = b_index
            rec["build_geo_index"] = geo([b_index[t] for t in panel["build"]
                                          if t in b_index])
            peaks = [build(rt, t, "peak_bytes") for t in task_ids]
            peaks = [p for p in peaks if p]
            rec["build_peak_mb"] = max(peaks) / 1048576.0 if peaks else None
            sizes = [build(rt, t, "exe_bytes") for t in task_ids]
            rec["exe_kb"] = geo(sizes) / 1024.0 if geo(sizes) else None
        entry["runtimes"][rt] = rec

    entry["headline"] = _headline(results, panel["run"])
    entry["null"] = _null_indices(results, refs, panel)

    # How far apart a runtime's own repeated samples landed, inside this campaign. The
    # null band says what the bench can resolve between campaigns; this says how quiet
    # the machine was during this one, and the two answer different questions.
    spreads = []
    for entries in results["tasks"].values():
        for runtime, data in entries.items():
            samples = (data.get("run") or {}).get("samples") or []
            if len(samples) > 1 and min(samples) > 0:
                spreads.append((max(samples) / min(samples) - 1.0) * 100.0)
    entry["sample_spread_pct"] = statistics.median(spreads) if spreads else None

    hello = results.get("hello_run", {}).get("swc-jit-release", {})
    entry["hello_jit_ms"] = hello.get("wall_ms")
    hb = results.get("hello_build", {}).get("swag-release", {})
    entry["hello_build_ms"] = hb.get("wall_ms")
    entry["hello_build_peak_mb"] = (hb.get("peak_bytes") or 0) / 1048576.0 or None
    return entry


def load_results():
    results = []
    for path in sorted(glob.glob(RESULTS)):
        with open(path, encoding="utf-8") as stream:
            campaign = json.load(stream)
        if campaign.get("meta", {}).get("protocol") == PROTOCOL:
            results.append(campaign)
    results.sort(key=lambda result: datetime.datetime.fromisoformat(result["meta"]["date"]))
    return results


def build_entries(results):
    if not results:
        return []
    results = sorted(results,
                     key=lambda result: datetime.datetime.fromisoformat(result["meta"]["date"]))
    baseline = _select_baseline(results)
    refs = _task_references(results, baseline)
    return [condense(result, refs, baseline) for result in results]


def load():
    if not os.path.exists(HISTORY):
        return []
    with open(HISTORY, encoding="utf-8") as f:
        return json.load(f)


def save(entries):
    with open(HISTORY, "w", encoding="utf-8", newline="\n") as f:
        json.dump(entries, f, indent=2)


def rebuild():
    """Recompute the complete adjusted history from its raw campaign archive."""
    results = load_results()
    if not results:
        return load()
    entries = build_entries(results)
    save(entries)
    return entries


def append(results):
    raw = load_results()
    stamp = results.get("meta", {}).get("stamp")
    if not any(result.get("meta", {}).get("stamp") == stamp for result in raw):
        raw.append(results)
    entries = build_entries(raw)
    save(entries)
    return entries
