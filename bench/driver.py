"""Run one full benchmark campaign and append it to the history.

Everything is measured in a single pass, because splitting a campaign in two
produced a 45% level shift between the halves on this machine. Repetitions are
round-robin — repetition 0 of every runtime, then repetition 1, and so on — so a
slow stretch of machine time is shared by everyone instead of landing entirely on
one language. A fixed reference workload is timed before and after the sweep and
the drift between the two is recorded with the results.

    py -3 driver.py [--swc PATH] [--repeats N] [--build-repeats N]
                    [--cooldown SECONDS] [--label TEXT] [--quick]
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time

import history
import toolchains as tc
import winproc

PAT = re.compile(r"CHECK=(-?\d+)\s+MS=([\d.]+)")

AOT_ORDER = ["swag-release", "swag-fast-debug", "cpp-clang-cl", "cpp-msvc",
             "rust", "swift", "csharp-aot", "csharp-jit"]
JIT_ORDER = ["swc-jit-release", "swc-jit-fast-debug", "node20", "luajit2.1",
             "lua5.4", "python3.12"]


def rm(path):
    if os.path.isdir(path):
        shutil.rmtree(path, ignore_errors=True)
    elif os.path.exists(path):
        try:
            os.unlink(path)
        except OSError:
            pass


def prepare(recipe):
    for p in recipe["clean"]:
        rm(p)
    for p in recipe.get("mkdir", []):
        os.makedirs(p, exist_ok=True)


def build_once(recipe, env):
    prepare(recipe)
    r = winproc.run(recipe["cmd"], cwd=recipe["cwd"], env=env)
    if r["exit"] != 0 or not os.path.exists(recipe["exe"]):
        return None, "exit=%d %s" % (r["exit"], (r["stdout"] + r["stderr"])[-900:])
    return r, None


def run_once(cmd, env):
    r = winproc.run(cmd, cwd=tc.BENCH, env=env)
    m = PAT.search(r["stdout"] + r["stderr"])
    if not m:
        return None, (r["stdout"] + r["stderr"])[-400:], r
    return (int(m.group(1)), float(m.group(2))), None, r


def keep_build(acc, r, recipe):
    acc["wall_ms"] = r["wall_ms"] if acc.get("wall_ms") is None else min(acc["wall_ms"], r["wall_ms"])
    acc["peak_bytes"] = max(acc.get("peak_bytes", 0), r["peak_job_bytes"])
    acc["exe_bytes"] = os.path.getsize(recipe["exe"])


def keep_run(acc, got, r):
    check, ms = got
    if acc.get("check") is None:
        acc["check"] = check
    elif acc["check"] != check:
        acc["error"] = "unstable checksum %d vs %d" % (acc["check"], check)
    acc["ms"] = ms if acc.get("ms") is None else min(acc["ms"], ms)
    acc["wall_ms"] = r["wall_ms"] if acc.get("wall_ms") is None else min(acc["wall_ms"], r["wall_ms"])
    acc["peak_bytes"] = max(acc.get("peak_bytes", 0), r["peak_job_bytes"])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--swc", help="compiler under test (default: bin/swc.exe of the main worktree)")
    ap.add_argument("--repeats", type=int, default=5)
    ap.add_argument("--build-repeats", type=int, default=3)
    ap.add_argument("--cooldown", type=int, default=120)
    ap.add_argument("--label", default="", help="short note stored with this campaign")
    ap.add_argument("--quick", action="store_true", help="1 repetition, no cooldown; smoke test only")
    args = ap.parse_args()

    if args.quick:
        args.repeats = 1
        args.build_repeats = 1
        args.cooldown = 0

    t = tc.discover()
    gone = tc.missing(t)
    if gone:
        print("missing toolchains, skipped: %s" % ", ".join(gone))
    swc = tc.swc_path(args.swc)
    if not os.path.exists(swc):
        print("compiler not found: %s" % swc)
        print("build it first, or pass --swc PATH")
        return 1

    env = tc.build_env(t)
    recipes = tc.make_recipes(t, env, swc)
    launchers = tc.make_launchers(t, t["dotnet"])
    runtimes = tc.make_runtimes(t, swc)
    hello_builds = tc.make_hello_builds(t, env, swc)
    hello_runs = tc.make_hello_runs(t, swc)

    aot = [k for k in AOT_ORDER if k not in gone]
    jit = [k for k in JIT_ORDER if k not in gone]
    os.makedirs(tc.OUT, exist_ok=True)

    print("compiler under test : %s" % swc)
    print("campaign            : %d run repetitions, %d build repetitions" %
          (args.repeats, args.build_repeats))

    if args.cooldown:
        print("cooldown %d s so the machine starts the sweep cold..." % args.cooldown)
        sys.stdout.flush()
        time.sleep(args.cooldown)

    # ------------------------------------------------------------- calibration
    calib_recipe = recipes["cpp-clang-cl"]("sha256", "calib_sha256")
    r, err = build_once(calib_recipe, env)
    if err:
        print("calibration build failed: %s" % err[:400])
        return 1

    def calibrate(tag):
        best = None
        for _ in range(max(3, args.repeats)):
            got, _, _ = run_once([calib_recipe["exe"]], env)
            if got:
                best = got[1] if best is None or got[1] < best else best
        if best is None:
            print("  calibration %-5s produced no valid result" % tag)
            return None
        print("  calibration %-5s sha256/C++ = %.3f ms" % (tag, best))
        sys.stdout.flush()
        return best

    results = {"tasks": {}, "hello_build": {}, "hello_run": {}, "calibration": {},
               "skipped": gone}
    results["calibration"]["start"] = calibrate("start")
    if results["calibration"]["start"] is None:
        return 1

    # ------------------------------------------------------- fixed compiler cost
    print("== fixed compiler cost (hello world -> exe) ==")
    for rep in range(args.build_repeats):
        for name in hello_builds:
            if name in gone or (rep >= 2 and name.startswith("csharp")):
                continue
            rec = hello_builds[name]()
            r, err = build_once(rec, env)
            acc = results["hello_build"].setdefault(name, {})
            if err:
                acc["error"] = err
            else:
                keep_build(acc, r, rec)
    for name, acc in results["hello_build"].items():
        if acc.get("error"):
            print("  %-20s ERROR %s" % (name, acc["error"][:150]))
        else:
            print("  %-20s build=%9.1f ms  mem=%7.1f MB" %
                  (name, acc["wall_ms"], acc["peak_bytes"] / 1048576.0))
    sys.stdout.flush()

    # ------------------------------------------------------ time to first output
    print("== time to first output (hello world) ==")
    for rep in range(args.repeats):
        for name in jit:
            r = winproc.run(hello_runs[name], cwd=tc.BENCH, env=env)
            acc = results["hello_run"].setdefault(name, {})
            acc["wall_ms"] = r["wall_ms"] if acc.get("wall_ms") is None else min(acc["wall_ms"], r["wall_ms"])
            acc["peak_bytes"] = max(acc.get("peak_bytes", 0), r["peak_job_bytes"])
    for name in jit:
        acc = results["hello_run"][name]
        print("  %-20s wall=%8.1f ms  mem=%7.1f MB" % (name, acc["wall_ms"], acc["peak_bytes"] / 1048576.0))
    sys.stdout.flush()

    # ------------------------------------------------------------------ the sweep
    for task in tc.TASKS:
        print("== %s ==" % task)
        built = {}
        errors = {}
        for name in aot:
            built[name] = recipes[name](task, "%s_%s" % (task, name.replace("-", "_")))

        acc_build = {name: {} for name in aot}
        for rep in range(args.build_repeats):
            for name in aot:
                if rep >= 2 and name.startswith("csharp"):
                    continue
                r, err = build_once(built[name], env)
                if err:
                    errors[name] = err
                else:
                    keep_build(acc_build[name], r, built[name])

        cmds = {}
        for name in aot:
            if name not in errors:
                cmds[name] = launchers[name](built[name]["exe"])
        for name in jit:
            cmds[name] = runtimes[name](task)

        acc_run = {name: {} for name in cmds}
        for rep in range(args.repeats):
            for name, cmd in cmds.items():
                got, err, r = run_once(cmd, env)
                if not got:
                    acc_run[name]["error"] = err
                else:
                    keep_run(acc_run[name], got, r)

        results["tasks"][task] = {}
        for name in aot + jit:
            entry = {"kind": "aot" if name in aot else "jit"}
            if name in errors:
                entry["build"] = {"error": errors[name]}
                print("  %-20s BUILD ERROR %s" % (name, errors[name][:150]))
            else:
                if name in aot:
                    entry["build"] = acc_build[name]
                entry["run"] = acc_run.get(name, {})
                r = entry["run"]
                if r.get("error"):
                    print("  %-20s RUN ERROR %s" % (name, r["error"][:150]))
                elif name in aot:
                    print("  %-20s run=%10.2f ms  build=%8.1f ms  bmem=%7.1f MB  check=%d"
                          % (name, r["ms"], entry["build"]["wall_ms"],
                             entry["build"]["peak_bytes"] / 1048576.0, r["check"]))
                else:
                    print("  %-20s run=%10.2f ms  rmem=%7.1f MB  check=%d"
                          % (name, r["ms"], r["peak_bytes"] / 1048576.0, r["check"]))
            results["tasks"][task][name] = entry
        sys.stdout.flush()

    results["calibration"]["end"] = calibrate("end")
    if results["calibration"]["end"] is None:
        return 1
    s, e = results["calibration"]["start"], results["calibration"]["end"]
    results["calibration"]["drift_pct"] = (e - s) / s * 100.0
    print("drift over the sweep: %+.1f %%" % results["calibration"]["drift_pct"])

    # --------------------------------------------------------------- checksums
    bad = []
    for task in tc.TASKS:
        seen = {}
        for name, entry in results["tasks"][task].items():
            c = entry.get("run", {}).get("check")
            if c is not None:
                seen.setdefault(c, []).append(name)
        if len(seen) > 1:
            bad.append("%s: %s" % (task, seen))
    if bad:
        print("checksum disagreement across runtimes: %s" % "; ".join(bad))
        print("campaign stopped before recording results")
        return 1
    else:
        print("checksums agree across every runtime on every task")

    results["meta"] = history.describe(swc, args.label)

    if args.quick:
        # Nothing is written at all: mkpage.py reports the most recent file in
        # results/, so leaving a one-repetition campaign there would quietly turn the
        # published page into noise.
        print("quick run: nothing recorded, one repetition proves nothing")
        return 0

    stamp = results["meta"]["stamp"]
    os.makedirs(os.path.join(tc.BENCH, "results"), exist_ok=True)
    raw = os.path.join(tc.BENCH, "results", "%s.json" % stamp)
    with open(raw, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2)
    print("raw campaign written to results/%s.json" % stamp)

    entries = history.append(results)
    current = next(entry for entry in entries if entry["meta"]["stamp"] == stamp)
    context = current["context"]
    print("context adjustment: execution=%+.1f %% from %d control measurements, "
          "compilation=%+.1f %% from %d control measurements" %
          ((context["run_factor"] - 1.0) * 100.0, context["run_controls"],
           (context["build_factor"] - 1.0) * 100.0, context["build_controls"]))
    print("history updated (%d campaigns)" % len(entries))
    return 0


if __name__ == "__main__":
    sys.exit(main())
