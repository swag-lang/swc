"""What a campaign concludes, and the history of those conclusions.

Nothing here corrects one campaign by another. Every published number is a ratio between
two series measured in the same campaign, in interleaved rounds:

  * comparisons: a Swag runtime against another language, ratio of medians per task and
    their geometric mean over the panel;
  * progress: a Swag runtime against the frozen reference, median of the per-round ratios
    per task and their geometric mean.

Both come with a 95 % interval (see stats.py), so a reader can tell a measured difference
from noise without trusting anyone. The raw campaigns under results/ remain authoritative:
the history is rebuilt from them whenever the report is generated, so an improved analysis
applies retroactively without touching a measurement.
"""
import datetime
import glob
import json
import os
import subprocess

import allocbench
import sampler
import stats
import toolchains as tc

HISTORY = os.path.join(tc.BENCH, "history.json")
RESULTS = os.path.join(tc.BENCH, "results", "*.json")

# How the measurement was taken. Campaigns of different protocols are not comparable and
# never share a history: earlier ones live in results/protocolN/, kept as evidence.
#
#   1  five repetitions on whatever core the scheduler chose.
#   2  pinned runs, budgeted samples, minimum as the estimator, Swag corrected between
#      campaigns by the median movement of the other languages.
#   3  medians with 95 % intervals, a frozen reference compiler measured beside the
#      compiler under test in every round, every sample checked for interference, every
#      toolchain timed from the same warm state with a clean project, isolated installs.
PROTOCOL = 3

TRACKED = tc.TRACKED
RUN_GROUPS = tc.RUN_GROUPS

# Each progress series: (id, label, section, subject runtime, reference runtime, metric key).
PROGRESS = [
    ("run-release", "native release execution", "run", "swag-release", "ref-release", "ms"),
    ("run-devmode", "native devmode execution", "run", "swag-devmode", "ref-devmode", "ms"),
    ("jit-release", "JIT release execution", "run", "swc-jit-release", "ref-jit-release", "ms"),
    ("jit-devmode", "JIT devmode execution", "run", "swc-jit-devmode", "ref-jit-devmode", "ms"),
    ("build-release", "release compilation", "build", "swag-release", "ref-release", "wall_ms"),
    ("build-devmode", "devmode compilation", "build", "swag-devmode", "ref-devmode", "wall_ms"),
    ("memory-release", "release compiler peak memory", "build", "swag-release", "ref-release", "peak_bytes"),
    ("size-release", "release executable size", "build", "swag-release", "ref-release", "exe_bytes"),
]

# The Swag runtime each comparison leads with, the family its rivals come from, and the
# section and metric it reads.
LEADS = [
    ("swag-release", "native", "run", "ms"),
    ("swag-devmode", "native", "run", "ms"),
    ("swc-jit-release", "jit", "run", "ms"),
    ("swc-jit-devmode", "jit", "run", "ms"),
    ("swag-release", None, "build", "wall_ms"),
    ("swag-devmode", None, "build", "wall_ms"),
]


def _git(args, cwd):
    try:
        r = subprocess.run(["git"] + args, cwd=cwd, capture_output=True, text=True)
        return r.stdout.strip() if r.returncode == 0 else ""
    except OSError:
        return ""


def describe(swc, label="", settings=None, stamp=None, started=None):
    """Identity of a campaign: when, which commit, which binary, and whether the tree
    carried uncommitted changes, which decides whether the commit alone reproduces it."""
    root = tc.worktree()
    started = started or datetime.datetime.now(datetime.timezone.utc)
    return {
        "protocol": PROTOCOL,
        "settings": settings or {},
        "stamp": stamp or started.strftime("%Y%m%d-%H%M%S"),
        "date": started.isoformat(timespec="seconds"),
        "finished": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
        "label": label,
        "commit": _git(["rev-parse", "--short=10", "HEAD"], root),
        "subject": _git(["log", "-1", "--format=%s"], root),
        # The report and the history are this harness's own outputs, regenerated after every
        # campaign; a stale copy of them says nothing about what was measured.
        "dirty": bool(_git(["status", "--porcelain", "--untracked-files=no", "--", ".",
                            ":(exclude)bench/bench.html", ":(exclude)bench/history.json"], root)),
        "swc": swc,
        "swc_bytes": os.path.getsize(swc) if os.path.exists(swc) else 0,
    }


# ------------------------------------------------------------------- reading
def record(campaign, task, runtime, family):
    """One series of a task, or None when it is missing or failed."""
    rec = ((campaign.get("tasks") or {}).get(task) or {}).get(runtime, {}).get(family)
    return rec if rec and not rec.get("error") and rec.get("samples") else None


def values(rec, key):
    """The samples of one series that count: timer faults out, scalars repeated."""
    if rec is None:
        return []
    if key == "exe_bytes":
        return [rec["exe_bytes"]] * 2 if rec.get("exe_bytes") else []
    raw = [s[key] for s in rec["samples"] if s.get(key)]
    return sampler.honest(raw)[0] if key in ("ms", "first_ms") else raw


def estimate(rec, key):
    return stats.estimate(values(rec, key))


def paired(a_rec, b_rec, key):
    """Median of the per-round ratios of two series sampled side by side."""
    if a_rec is None or b_rec is None:
        return None
    if key == "exe_bytes":
        if not a_rec.get("exe_bytes") or not b_rec.get("exe_bytes"):
            return None
        r = a_rec["exe_bytes"] / b_rec["exe_bytes"]
        return stats.Estimate(r, r, r, 1, 0.0, True)
    faults = lambda rec: set(sampler.honest([s[key] for s in rec["samples"]])[1]) if key in ("ms", "first_ms") else set()
    fa, fb = faults(a_rec), faults(b_rec)
    by_round = {s["round"]: s[key] for s in b_rec["samples"] if s.get(key) and s[key] not in fb}
    ratios = [s[key] / by_round[s["round"]] for s in a_rec["samples"]
              if s.get(key) and s[key] not in fa and s["round"] in by_round]
    return stats.estimate(ratios)


def tasks_of(campaign):
    return [t for t in tc.TASKS if t in (campaign.get("tasks") or {})]


def progress(campaign):
    """Every progress series of a campaign: per task, and the geometric mean of the panel."""
    out = {}
    tasks = tasks_of(campaign)
    for pid, _, family, subject, reference, key in PROGRESS:
        per_task = {t: paired(record(campaign, t, subject, family), record(campaign, t, reference, family), key)
                    for t in tasks}
        if not any(per_task.values()):
            continue
        complete = all(per_task.values())
        out[pid] = {"tasks": {t: e.as_dict() if e else None for t, e in per_task.items()},
                    "geo": stats.geomean(per_task.values()).as_dict() if complete else None}
    # The edit-build loop and the hello programs, one value each.
    singles = {}
    for wid, roles in (campaign.get("loop") or {}).items():
        a, b = roles.get("subject") or {}, roles.get("reference") or {}
        if a.get("samples") and b.get("samples") and not a.get("error") and not b.get("error"):
            e = paired(a, b, "wall_ms")
            if e:
                singles["loop-" + wid] = e.as_dict()
    for name, ref in (("swag-release", "ref-release"), ("swag-devmode", "ref-devmode")):
        hb = campaign.get("hello_build") or {}
        e = paired(hb.get(name), hb.get(ref), "wall_ms") if hb.get(name) and hb.get(ref) else None
        if e:
            singles["hello-build-" + name.split("-")[1]] = e.as_dict()
    for name, ref in (("swc-jit-release", "ref-jit-release"), ("swc-jit-devmode", "ref-jit-devmode")):
        hr = campaign.get("hello_run") or {}
        e = paired(hr.get(name), hr.get(ref), "first_ms") if hr.get(name) and hr.get(ref) else None
        if e:
            singles["hello-run-" + name.split("-")[-1]] = e.as_dict()
    if singles:
        out["singles"] = singles
    return out


def competitors(campaign, family, group, key):
    """Non-Swag runtimes with a valid series on every task of the panel."""
    tasks = tasks_of(campaign)
    pool = set(RUN_GROUPS[group]) if group else {rt for t in tasks for rt in campaign["tasks"][t]}
    excluded = set(TRACKED) | set(tc.REFERENCES)
    return sorted(rt for rt in pool if rt not in excluded and tasks and
                  all(estimate(record(campaign, t, rt, family), key) for t in tasks))


def compare(campaign, lead, rival, family, key):
    """Lead / rival on every task, their geometric mean and the faster / tie / slower tally."""
    tasks = tasks_of(campaign)
    per_task = {t: stats.ratio(estimate(record(campaign, t, lead, family), key),
                               estimate(record(campaign, t, rival, family), key)) for t in tasks}
    if not tasks or not all(per_task.values()):
        return None
    return {"tasks": per_task, "geo": stats.geomean(per_task.values()), "tally": stats.tally(per_task.values())}


def comparisons(campaign):
    """lead -> family -> rival -> comparison, plus the strongest rival of each lead."""
    out = {}
    for lead, group, family, key in LEADS:
        if not all(record(campaign, t, lead, family) for t in tasks_of(campaign)):
            continue
        rivals = {}
        for rival in competitors(campaign, family, group, key):
            c = compare(campaign, lead, rival, family, key)
            if c:
                rivals[rival] = c
        if not rivals:
            continue
        # The strongest rival is the one against which Swag's geometric mean is worst.
        strongest = max(rivals, key=lambda r: rivals[r]["geo"].value)
        out.setdefault(lead, {})[family] = {"rivals": rivals, "strongest": strongest, "group": group}
    return out


# ----------------------------------------------------------------- history
def condense(campaign):
    """The compact entry the history keeps for one campaign."""
    comps = comparisons(campaign)
    headline = {}
    for lead, families in comps.items():
        for family, c in families.items():
            best = c["rivals"][c["strongest"]]
            headline["%s/%s" % (lead, family)] = {"rival": c["strongest"], "geo": best["geo"].as_dict(),
                                                 "tally": best["tally"]}
    return {
        "meta": campaign["meta"],
        "quality": campaign.get("quality"),
        "progress": progress(campaign),
        "headline": headline,
        "probes": (campaign.get("calibration") or {}).get("probes"),
        "allocator": allocbench.condense(campaign.get("allocator")),
    }


def load_results():
    """Every recorded campaign of the current protocol, oldest first."""
    results = []
    for path in sorted(glob.glob(RESULTS)):
        with open(path, encoding="utf-8") as stream:
            campaign = json.load(stream)
        if campaign.get("meta", {}).get("protocol") == PROTOCOL:
            results.append(campaign)
    results.sort(key=lambda c: datetime.datetime.fromisoformat(c["meta"]["date"]))
    return results


def build_entries(results):
    return [condense(r) for r in sorted(results, key=lambda c: datetime.datetime.fromisoformat(c["meta"]["date"]))]


def load():
    if not os.path.exists(HISTORY):
        return []
    with open(HISTORY, encoding="utf-8") as f:
        return json.load(f)


def save(entries):
    with open(HISTORY, "w", encoding="utf-8", newline="\r\n") as f:
        json.dump(entries, f, indent=1)


def rebuild():
    """Recompute the history from the raw campaigns."""
    entries = build_entries(load_results())
    save(entries)
    return entries


def append(results):
    raw = load_results()
    if not any(r["meta"]["stamp"] == results["meta"]["stamp"] for r in raw):
        raw.append(results)
    entries = build_entries(raw)
    save(entries)
    return entries
