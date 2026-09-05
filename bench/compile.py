"""Measure the edit-build loop on one compiler, or A/B two of them.

    py -3 compile.py [--swc PATH] [--against PATH] [--reps N] [--cores N] [--only IDS]

This is not a campaign and records nothing. It answers the question a round of
compile-speed work actually asks — did this change move this workload — in a few
minutes, with the numbers the campaign would later confirm or deny:

  * the order alternates every round (A then B, then B then A), because the binary
    measured second inherits the first one's cache and thermal state, and that bias
    alone once read as a 16 % difference between two identical binaries;
  * the verdict is the median of the per-round ratios, not a ratio of minimums: the
    machine drifts between rounds, and a pair measured back to back shares that drift;
  * both wall and CPU time are printed. Wall is the target — it is what a person waits
    for — but CPU cannot be inflated by another process stealing cores, so when the two
    disagree in sign the difference is under the noise floor.

A single compiler prints its own min and median, which is what the campaign records.
"""
import argparse
import os
import statistics
import sys

import toolchains as tc
import winproc


def measure(workload, env):
    if workload["prepare"]:
        workload["prepare"](env)
    r = winproc.run(workload["cmd"], cwd=workload["cwd"], env=env)
    if r["exit"] != 0:
        raise SystemExit("%s failed: exit=%d\n%s" % (" ".join(workload["cmd"]), r["exit"],
                                                   (r["stdout"] + r["stderr"])[-1200:]))
    return r


def summary(samples):
    wall = [s["wall_ms"] for s in samples]
    cpu = [s["cpu_ms"] for s in samples]
    peak = max(s["peak_job_bytes"] for s in samples) / 1048576.0
    return min(wall), statistics.median(wall), statistics.median(cpu), peak


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--swc", help="compiler under test (default: bin/swc.exe of this worktree)")
    ap.add_argument("--against", help="a second compiler to compare with, alternated round by round")
    ap.add_argument("--reps", type=int, default=5, help="rounds; every round measures every workload")
    ap.add_argument("--cores", type=int, default=0,
                    help="cap on the compiler's worker pool; 0 leaves the compiler to its own count")
    ap.add_argument("--only", default="",
                    help="comma-separated workload ids (%s)" % ", ".join(tc.COMPILER_WORKLOADS))
    args = ap.parse_args()

    ids = [w.strip() for w in args.only.split(",") if w.strip()] or tc.COMPILER_WORKLOADS
    unknown = [w for w in ids if w not in tc.COMPILER_WORKLOADS]
    if unknown:
        raise SystemExit("unknown workload(s): %s" % ", ".join(unknown))

    # Absolute, because a child is created with the driver's own directory, not the workload's.
    binaries = [("A", os.path.abspath(tc.swc_path(args.swc)))]
    if args.against:
        binaries.append(("B", os.path.abspath(args.against)))
    for _, path in binaries:
        if not os.path.exists(path):
            raise SystemExit("compiler not found: %s" % path)

    env = tc.build_env(tc.discover())
    plans = {tag: tc.make_compiler_workloads(path, args.cores) for tag, path in binaries}
    samples = {tag: {wid: [] for wid in ids} for tag, _ in binaries}

    for tag, path in binaries:
        print("%s: %s" % (tag, path))
    print("%d round(s), %s" % (args.reps, ("%d cores" % args.cores) if args.cores else "own core count"))
    sys.stdout.flush()

    for rnd in range(args.reps):
        order = binaries if rnd % 2 == 0 else binaries[::-1]
        for tag, _ in order:
            for wid in ids:
                r = measure(plans[tag][wid], env)
                samples[tag][wid].append(r)
                print("  round %d %s %-13s wall=%9.1f ms  cpu=%9.1f ms  mem=%6.1f MB"
                      % (rnd + 1, tag, wid, r["wall_ms"], r["cpu_ms"],
                         r["peak_job_bytes"] / 1048576.0))
                sys.stdout.flush()

    print()
    print("%-13s %-3s %10s %10s %10s %8s" % ("workload", "", "min ms", "median ms", "cpu ms", "peak MB"))
    for wid in ids:
        for tag, _ in binaries:
            lo, med, cpu, peak = summary(samples[tag][wid])
            print("%-13s %-3s %10.1f %10.1f %10.1f %8.1f" % (wid, tag, lo, med, cpu, peak))
        if len(binaries) == 2:
            pairs = zip(samples["A"][wid], samples["B"][wid])
            wall = [b["wall_ms"] / a["wall_ms"] for a, b in pairs]
            pairs = zip(samples["A"][wid], samples["B"][wid])
            cpu = [b["cpu_ms"] / a["cpu_ms"] for a, b in pairs if a["cpu_ms"]]
            print("%-13s B/A %10s %10.3f %10.3f" % (wid, "", statistics.median(wall),
                                                    statistics.median(cpu) if cpu else float("nan")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
