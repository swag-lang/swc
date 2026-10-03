"""The allocator benchmark: the Swag runtime allocator against mimalloc and the C runtime heap.

One Swag program (allocator/src/allocbench.swg) and one C program (allocator/src/allocbench.c)
run the same workloads. The C program is compiled twice with MSVC, once over the vendored
mimalloc and once over the C runtime heap. Every workload runs in a fresh process, pinned to the
performance cores, the three executables alternating their order from round to round, so the
three see the same machine. Each program reports its own `ns/op`; the process's peak working set
and peak commit come from the job object.

The competitors are measured in the same campaign as Swag, so the ratio Swag / mimalloc needs no
machine correction: it is the number the history follows.
"""
import math
import os
import re
import statistics
import subprocess

import toolchains as tc
import winproc

HERE = os.path.join(tc.BENCH, "allocator")
IMPLEMENTATIONS = ("swag", "mimalloc", "crt")

# 'name' runs on one thread, 'name:N' on N threads (N producer/consumer pairs for xfer).
WORKLOADS = ["pair", "trees", "churn", "medium", "large", "realloc", "spread", "spread:8",
             "churn:4", "medium:4", "large:4", "xfer:2", "xfer:4"]
REPS = 5

PAT = re.compile(r"ns/op=([\d.]+)")


def build(swc, env, out, cores=0):
    """Build the three executables under `out`. Returns ({implementation: exe}, errors)."""
    os.makedirs(out, exist_ok=True)
    mimalloc = os.path.join(tc.worktree(), "src", "Support", "Memory", "mimalloc")
    source = os.path.join(HERE, "src", "allocbench.c")
    cl = tc.resolve(env, "cl")
    exes, errors = {}, {}
    for name, extra in (("mimalloc", ["/DUSE_MIMALLOC", "/I" + os.path.join(mimalloc, "include"),
                                      os.path.join(mimalloc, "src", "static.c"), "advapi32.lib"]),
                        ("crt", [])):
        objdir = os.path.join(out, "obj_" + name)
        os.makedirs(objdir, exist_ok=True)
        exe = os.path.join(out, "allocbench_" + name + ".exe")
        cmd = [cl, "/nologo", "/O2", "/DNDEBUG", source, *extra, "/Fo:" + objdir + os.sep, "/Fe:" + exe]
        done = subprocess.run(cmd, env=env, cwd=out, capture_output=True, text=True, errors="replace")
        if done.returncode != 0 or not os.path.exists(exe):
            errors[name] = (done.stdout + done.stderr).strip()[-400:] or "build failed"
        else:
            exes[name] = exe

    swagdir = os.path.join(out, "swag")
    cmd = [swc, "build", *tc.swc_worker_args(cores), "-f", "src/allocbench.swg",
           "--module-file", os.path.join(HERE, "module.swg"), "-bc", "release",
           "-od", swagdir, "-wd", swagdir]
    done = subprocess.run(cmd, cwd=tc.worktree(), capture_output=True, text=True, errors="replace")
    exe = os.path.join(swagdir, "allocator.exe")
    if done.returncode != 0 or not os.path.exists(exe):
        errors["swag"] = (done.stdout + done.stderr).strip()[-400:] or "build failed"
    else:
        exes["swag"] = exe
    return exes, errors


def run_once(exe, workload):
    """One sample: (ns per operation, winproc result), or (None, error text)."""
    name, _, threads = workload.partition(":")
    r = winproc.run([exe, name, threads or "1"], cwd=tc.BENCH, pin=True)
    m = PAT.search(r["stdout"])
    if r["exit"] != 0 or not m:
        return None, (r["stdout"] + r["stderr"]).strip()[-300:] or "exit code %d" % r["exit"]
    return (float(m.group(1)), r), None


def measure(exes, reps, workloads=None, report=print):
    """Every workload on every executable, `reps` rounds with rotating order.

    Returns {workload: {implementation: {"ns", "samples", "peak_bytes",
    "peak_working_set_bytes"} or {"error"}}}. The median is kept, not the minimum: the
    multi-thread workloads swing with scheduling, and a median of rounds that interleave the
    three allocators is the comparison they share."""
    names = [n for n in IMPLEMENTATIONS if n in exes]
    section = {}
    for workload in workloads or WORKLOADS:
        accs = {n: {} for n in names}
        for rep in range(reps):
            turn = rep % len(names)
            for name in names[turn:] + names[:turn]:
                acc = accs[name]
                if acc.get("error"):
                    continue
                got, err = run_once(exes[name], workload)
                if err:
                    acc["error"] = err
                    continue
                ns, r = got
                acc.setdefault("samples", []).append(round(ns, 3))
                acc["peak_bytes"] = max(acc.get("peak_bytes", 0), r["peak_job_bytes"])
                acc["peak_working_set_bytes"] = max(acc.get("peak_working_set_bytes", 0),
                                                    r["peak_working_set_bytes"])
        for acc in accs.values():
            if acc.get("samples") and not acc.get("error"):
                acc["ns"] = statistics.median(acc["samples"])
        section[workload] = accs
        if report:
            report("  %-10s %s" % (workload, "  ".join(
                "%s=%s" % (n, "ERROR" if accs[n].get("error") else "%.1f ns %.1f MB" %
                           (accs[n]["ns"], accs[n]["peak_working_set_bytes"] / 1048576.0))
                for n in names)))
    return section


def errors(section):
    """Every failed measurement of a raw section, as 'workload/implementation: message'."""
    return ["%s/%s: %s" % (workload, name, acc["error"])
            for workload, accs in (section or {}).items()
            for name, acc in accs.items() if acc.get("error")]


def _geo(values):
    values = [v for v in values if v]
    return math.exp(sum(math.log(v) for v in values) / len(values)) if values else None


def condense(section):
    """The history's view of a raw section: per workload, each implementation's time and peak
    working set, and Swag's ratio to each competitor; then the geometric means of those ratios
    over the workloads every implementation completed. None when nothing was measured."""
    if not section:
        return None
    workloads = {}
    for workload, accs in section.items():
        rec = {}
        for name in IMPLEMENTATIONS:
            acc = accs.get(name) or {}
            if acc.get("error") or not acc.get("ns"):
                continue
            rec[name + "_ns"] = acc["ns"]
            rec[name + "_ws_mb"] = (acc.get("peak_working_set_bytes") or 0) / 1048576.0 or None
            rec[name + "_commit_mb"] = (acc.get("peak_bytes") or 0) / 1048576.0 or None
        for rival in ("mimalloc", "crt"):
            if rec.get("swag_ns") and rec.get(rival + "_ns"):
                rec["vs_" + rival] = rec["swag_ns"] / rec[rival + "_ns"]
            if rec.get("swag_ws_mb") and rec.get(rival + "_ws_mb"):
                rec["ws_vs_" + rival] = rec["swag_ws_mb"] / rec[rival + "_ws_mb"]
        workloads[workload] = rec
    complete = [rec for rec in workloads.values() if all(rec.get("vs_" + r) for r in ("mimalloc", "crt"))]
    return {
        "workloads": workloads,
        "geo_vs_mimalloc": _geo([rec["vs_mimalloc"] for rec in complete]),
        "geo_vs_crt": _geo([rec["vs_crt"] for rec in complete]),
        "geo_ws_vs_mimalloc": _geo([rec.get("ws_vs_mimalloc") for rec in complete]),
        "geo_ws_vs_crt": _geo([rec.get("ws_vs_crt") for rec in complete]),
        "count": len(complete),
    }
