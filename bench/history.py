"""Accumulate one compact entry per campaign so improvements stay visible over time.

Raw milliseconds are not comparable between campaigns: the same machine drifts by
around ten percent within a single sweep, and much more between sessions. So every
swc number is also stored normalised against the reference toolchain measured in
the *same* campaign. A moving normalised number means swc moved; a moving raw
number may only mean the laptop was warm.

Only swc is kept in the history. The other languages are a fixed yardstick, not a
subject: they are re-measured every campaign solely to produce that yardstick.
"""
import datetime
import json
import math
import os
import subprocess

import toolchains as tc

HISTORY = os.path.join(tc.BENCH, "history.json")

TRACKED = ["swag-release", "swc-jit-release", "swag-fast-debug", "swc-jit-fast-debug"]
BUILT = ["swag-release", "swag-fast-debug"]


def geo(values):
    values = [v for v in values if v and v > 0]
    if not values:
        return None
    return math.exp(sum(math.log(v) for v in values) / len(values))


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


def condense(results):
    """Turn a raw campaign into the compact, normalised entry kept in the history."""
    tasks = results["tasks"]
    task_ids = list(tasks)
    ref = tc.REFERENCE

    def ms(rt, task):
        return tasks[task].get(rt, {}).get("run", {}).get("ms")

    def build(rt, task, key):
        return (tasks[task].get(rt, {}).get("build") or {}).get(key)

    ref_ms = {t: ms(ref, t) for t in task_ids}
    ref_build = {t: build(ref, t, "wall_ms") for t in task_ids}

    entry = {
        "meta": results["meta"],
        "drift_pct": results["calibration"].get("drift_pct"),
        "calibration_ms": results["calibration"].get("start"),
        "reference": {"runtime": ref, "run_ms": ref_ms, "build_ms": ref_build},
        "runtimes": {},
    }

    for rt in TRACKED:
        if rt not in tasks[task_ids[0]]:
            continue
        run_ms = {t: ms(rt, t) for t in task_ids}
        ratio = {t: (run_ms[t] / ref_ms[t]) if run_ms[t] and ref_ms[t] else None for t in task_ids}
        rec = {
            "run_ms": run_ms,
            "run_ratio": ratio,
            "run_geo_ratio": geo(list(ratio.values())),
        }
        if rt in BUILT:
            b_ms = {t: build(rt, t, "wall_ms") for t in task_ids}
            b_ratio = {t: (b_ms[t] / ref_build[t]) if b_ms[t] and ref_build[t] else None
                       for t in task_ids}
            rec["build_ms"] = b_ms
            rec["build_ratio"] = b_ratio
            rec["build_geo_ms"] = geo(list(b_ms.values()))
            rec["build_geo_ratio"] = geo(list(b_ratio.values()))
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


def load():
    if not os.path.exists(HISTORY):
        return []
    with open(HISTORY, encoding="utf-8") as f:
        return json.load(f)


def save(entries):
    with open(HISTORY, "w", encoding="utf-8") as f:
        json.dump(entries, f, indent=2)


def append(results):
    entries = load()
    entries.append(condense(results))
    # Parse before sorting: campaigns can carry different UTC offsets, and comparing
    # the strings would then order them wrongly.
    entries.sort(key=lambda e: datetime.datetime.fromisoformat(e["meta"]["date"]))
    save(entries)
    return entries
