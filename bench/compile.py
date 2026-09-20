"""Measure the edit-build loop on one compiler, or A/B two of them.

    py -3 compile.py [--swc PATH] [--against PATH] [--reps N] [--only IDS] [--swc-cores N]

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
import shutil
import statistics
import subprocess
import sys
import time

import toolchains as tc
import winproc


AVAILABLE_WORKLOADS = ["core_rebuild", "core_noop", "core_touch", "hello_build",
                       "doc_std", "format_tree"]


def measure(workload, env, admit=None):
    if workload["prepare"]:
        workload["prepare"](env)
    if admit:
        admit()
    r = winproc.run(workload["cmd"], cwd=workload["cwd"], env=env)
    if r["exit"] != 0:
        raise SystemExit("%s failed: exit=%d\n%s" % (" ".join(workload["cmd"]), r["exit"],
                                                   (r["stdout"] + r["stderr"])[-1200:]))
    return r


def make_hello_workload(toolchains, env, swc, cores):
    recipe = tc.make_hello_builds(toolchains, env, swc)["swag-release"]()
    command = list(recipe["cmd"])
    if cores:
        command.extend(["--num-cores", str(cores)])

    out = os.path.realpath(tc.OUT)

    def prepare(_):
        for path in recipe["clean"]:
            target = os.path.realpath(path)
            if os.path.commonpath([out, target]) != out:
                raise RuntimeError("hello build output is outside the benchmark output directory: " + target)
            if os.path.isdir(target):
                shutil.rmtree(target)
            elif os.path.exists(target):
                os.remove(target)
        for path in recipe.get("mkdir", []):
            os.makedirs(path, exist_ok=True)

    return {"cmd": command, "cwd": recipe["cwd"], "prepare": prepare,
            "what": "hello world, source to linked executable"}


def make_admitter():
    script = os.path.join(tc.worktree(), ".agents", "skills", "modify-swag-codebase",
                          "scripts", "check-machine-load.ps1")

    def admit():
        while True:
            result = subprocess.run(
                ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script],
                capture_output=True, text=True)
            if result.returncode == 0:
                return
            if result.returncode != 2:
                raise RuntimeError(result.stdout + result.stderr)
            print("Waiting for compiler headroom", flush=True)
            time.sleep(15)

    return admit


def summary(samples):
    wall = [s["wall_ms"] for s in samples]
    cpu = [s["cpu_ms"] for s in samples]
    peak = max(s["peak_job_bytes"] for s in samples) / 1048576.0
    resident = max(s["peak_working_set_bytes"] for s in samples) / 1048576.0
    return min(wall), statistics.median(wall), statistics.median(cpu), peak, resident


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--swc", help="compiler under test (default: bin/swc.exe of this worktree)")
    ap.add_argument("--against", help="a second compiler to compare with, alternated round by round")
    ap.add_argument("--reps", type=int, default=5, help="rounds; every round measures every workload")
    ap.add_argument("--only", default="",
                    help="comma-separated workload ids (%s)" % ", ".join(AVAILABLE_WORKLOADS))
    ap.add_argument("--swc-cores", type=int, default=0,
                    help="explicit compiler worker cap (default: compiler-selected)")
    ap.add_argument("--admit", action="store_true",
                    help="check shared-machine load before every compiler invocation")
    args = ap.parse_args()

    if args.swc_cores < 0:
        raise SystemExit("--swc-cores must be zero or greater")

    ids = [w.strip() for w in args.only.split(",") if w.strip()] or tc.COMPILER_WORKLOADS
    unknown = [w for w in ids if w not in AVAILABLE_WORKLOADS]
    if unknown:
        raise SystemExit("unknown workload(s): %s" % ", ".join(unknown))

    # Absolute, because a child is created with the driver's own directory, not the workload's.
    binaries = [("A", os.path.abspath(tc.swc_path(args.swc)))]
    if args.against:
        binaries.append(("B", os.path.abspath(args.against)))
    for _, path in binaries:
        if not os.path.exists(path):
            raise SystemExit("compiler not found: %s" % path)

    toolchains = tc.discover()
    env = tc.build_env(toolchains)
    admit = make_admitter() if args.admit else None
    plans = {}
    for tag, path in binaries:
        plans[tag] = tc.make_compiler_workloads(path, args.swc_cores, admit)
        if "hello_build" in ids:
            plans[tag]["hello_build"] = make_hello_workload(toolchains, env, path, args.swc_cores)
    samples = {tag: {wid: [] for wid in ids} for tag, _ in binaries}

    for tag, path in binaries:
        print("%s: %s" % (tag, path))
    workers = "%d compiler worker(s)" % args.swc_cores if args.swc_cores else "compiler-selected worker count"
    print("%d round(s), %s" % (args.reps, workers))
    sys.stdout.flush()

    for rnd in range(args.reps):
        order = binaries if rnd % 2 == 0 else binaries[::-1]
        for tag, _ in order:
            for wid in ids:
                r = measure(plans[tag][wid], env, admit)
                samples[tag][wid].append(r)
                print("  round %d %s %-13s wall=%9.1f ms  cpu=%9.1f ms  commit=%6.1f MiB  ws=%6.1f MiB"
                      % (rnd + 1, tag, wid, r["wall_ms"], r["cpu_ms"],
                         r["peak_job_bytes"] / 1048576.0, r["peak_working_set_bytes"] / 1048576.0))
                sys.stdout.flush()

    print()
    print("%-13s %-3s %10s %10s %10s %10s %10s" %
          ("workload", "", "min ms", "median ms", "cpu ms", "commit MiB", "ws MiB"))
    for wid in ids:
        for tag, _ in binaries:
            lo, med, cpu, peak, resident = summary(samples[tag][wid])
            print("%-13s %-3s %10.1f %10.1f %10.1f %10.1f %10.1f" % (wid, tag, lo, med, cpu, peak, resident))
        if len(binaries) == 2:
            pairs = zip(samples["A"][wid], samples["B"][wid])
            wall = [b["wall_ms"] / a["wall_ms"] for a, b in pairs]
            pairs = zip(samples["A"][wid], samples["B"][wid])
            cpu = [b["cpu_ms"] / a["cpu_ms"] for a, b in pairs if a["cpu_ms"]]
            pairs = zip(samples["A"][wid], samples["B"][wid])
            commit = [b["peak_job_bytes"] / a["peak_job_bytes"] for a, b in pairs if a["peak_job_bytes"]]
            pairs = zip(samples["A"][wid], samples["B"][wid])
            resident = [b["peak_working_set_bytes"] / a["peak_working_set_bytes"]
                        for a, b in pairs if a["peak_working_set_bytes"]]
            print("%-13s B/A %10s %10.3f %10.3f %10.3f %10.3f" %
                  (wid, "", statistics.median(wall), statistics.median(cpu) if cpu else float("nan"),
                   statistics.median(commit) if commit else float("nan"),
                   statistics.median(resident) if resident else float("nan")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
