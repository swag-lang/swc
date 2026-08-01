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

TRACKED = ["swag-release", "swc-jit-release", "swag-fast-debug", "swc-jit-fast-debug"]
BUILT = ["swag-release", "swag-fast-debug"]
MIN_CONTROLS = 3


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


def describe(swc, label=""):
    """Identity of a campaign: when, which commit, which binary, and whether the tree
    carried uncommitted changes at the time — which decides whether the commit alone
    reproduces the measurement."""
    root = tc.worktree()
    stat = os.stat(swc) if os.path.exists(swc) else None
    now = datetime.datetime.now(datetime.timezone.utc)
    return {
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


def _context(results, baseline):
    """Return execution and build context factors relative to ``baseline``.

    Each task gets its own factor because the sweep lasts long enough for machine
    conditions to change between tasks. The campaign factor is their geometric mean
    and exists for reporting; correction always uses the finer per-task value.
    """
    contexts = {}
    for family, key in (("run", "ms"), ("build", "wall_ms")):
        task_factors = {}
        task_counts = {}
        task_dispersion = {}
        for task, entries in results["tasks"].items():
            base_entries = baseline["tasks"].get(task, {})
            ratios = []
            for runtime, entry in entries.items():
                if runtime in TRACKED:
                    continue
                current = _metric(entry, family, key)
                reference = _metric(base_entries.get(runtime, {}), family, key)
                if current and reference:
                    ratios.append(current / reference)

            if len(ratios) < MIN_CONTROLS:
                continue
            factor = robust_factor(ratios)
            task_factors[task] = factor
            task_counts[task] = len(ratios)
            task_dispersion[task] = dispersion(ratios, factor)

        weighted_dispersion = []
        for task, value in task_dispersion.items():
            weighted_dispersion.extend([value] * task_counts[task])
        contexts[family] = {
            "factor": geo(list(task_factors.values())),
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
        complete = True
        for entries in result.get("tasks", {}).values():
            controls = [entry for runtime, entry in entries.items() if runtime not in TRACKED]
            run_count = sum(1 for entry in controls if _metric(entry, "run", "ms"))
            build_count = sum(1 for entry in controls if _metric(entry, "build", "wall_ms"))
            if run_count < MIN_CONTROLS or build_count < MIN_CONTROLS:
                complete = False
                break
        if complete:
            return result
    return results[0]


def condense(results, baseline=None):
    """Turn one raw campaign into the compact, adjusted entry kept in the history."""
    baseline = baseline or results
    tasks = results["tasks"]
    task_ids = list(tasks)
    baseline_tasks = baseline["tasks"]
    context = _context(results, baseline)

    def ms(rt, task):
        return tasks[task].get(rt, {}).get("run", {}).get("ms")

    def build(rt, task, key):
        return (tasks[task].get(rt, {}).get("build") or {}).get(key)

    def baseline_metric(rt, task, family, key):
        return _metric(baseline_tasks.get(task, {}).get(rt, {}), family, key)

    def factor(family, task):
        family_context = context[family]
        return family_context["task_factors"].get(task) or family_context["factor"] or 1.0

    entry = {
        "meta": results["meta"],
        "drift_pct": results["calibration"].get("drift_pct"),
        "calibration_ms": results["calibration"].get("start"),
        "context": {
            "baseline": baseline["meta"].get("stamp"),
            "baseline_commit": baseline["meta"].get("commit"),
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
        rec = {
            "run_ms": run_ms,
            "run_adjusted_ms": adjusted_ms,
            "run_geo_adjusted_ms": geo(list(adjusted_ms.values())),
            "run_index": run_index,
            "run_geo_index": geo(list(run_index.values())),
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
            rec["build_geo_adjusted_ms"] = geo(list(b_adjusted.values()))
            rec["build_index"] = b_index
            rec["build_geo_index"] = geo(list(b_index.values()))
            peaks = [build(rt, t, "peak_bytes") for t in task_ids]
            peaks = [p for p in peaks if p]
            rec["build_peak_mb"] = max(peaks) / 1048576.0 if peaks else None
            sizes = [build(rt, t, "exe_bytes") for t in task_ids]
            rec["exe_kb"] = geo(sizes) / 1024.0 if geo(sizes) else None
        entry["runtimes"][rt] = rec

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
            results.append(json.load(stream))
    results.sort(key=lambda result: datetime.datetime.fromisoformat(result["meta"]["date"]))
    return results


def build_entries(results):
    if not results:
        return []
    results = sorted(results,
                     key=lambda result: datetime.datetime.fromisoformat(result["meta"]["date"]))
    baseline = _select_baseline(results)
    return [condense(result, baseline) for result in results]


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
