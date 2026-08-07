"""Run one full benchmark campaign and append it to the history.

Everything is measured in a single pass, because splitting a campaign in two
produced a 45% level shift between the halves on this machine. Repetitions are
round-robin — repetition 0 of every runtime, then repetition 1, and so on — so a
slow stretch of machine time is shared by everyone instead of landing entirely on
one language. A fixed reference workload is timed before and after the sweep and
the drift between the two is recorded with the results.

Three properties of that round-robin were each measured to be worth their cost, on
the ratio between two binaries that never change — the only thing this bench is
allowed to claim:

  * every timed run is pinned to the performance cores. Left to the scheduler, a
    short process lands on an E core or a low-power core often enough to move that
    ratio by 10 % between two blocks of measurements; pinned, by 2 %.
  * the order inside a cycle rotates. With a fixed order the runtime listed first
    is always measured at the same point of the machine's thermal ramp, which is a
    systematic advantage rather than a result.
  * each runtime is sampled to a time budget instead of a fixed count, and its
    samples are spread evenly across the whole window rather than bunched at one
    end. A 50 ms task then gets twenty-four samples where CPython gets three, and
    both are spread over the same minutes.

    py -3 driver.py [--swc PATH] [--budget MS] [--build-budget MS]
                    [--warmup SECONDS] [--label TEXT] [--quick]
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

# A runtime is sampled until it has spent this much measured time on a task, within
# these bounds. Below the floor a minimum is meaningless; above the ceiling the extra
# samples stopped paying — measured on this machine, the ratio between two unchanged
# binaries settles by twenty and does not improve after that.
RUN_BUDGET_MS = 4500
RUN_MIN_REPS = 3
RUN_MAX_REPS = 24

# A run this long is already averaging over everything a repetition would average
# over, and CPython on a rescaled task costs half a minute a sample. Two is enough.
RUN_SLOW_MS = 20000

# Builds get the same treatment, on their own budget: swc links a task in 150 ms and
# NativeAOT takes ten seconds, so a flat repetition count either starves the fast
# toolchain — the one actually under test — or spends minutes on the slow one. The
# ceiling is lower than for runs because a build is dominated by file system work,
# which repetition averages far less well than compute.
BUILD_BUDGET_MS = 3000
BUILD_MIN_REPS = 2
BUILD_MAX_REPS = 8

DRIFT_LIMIT_PCT = history.DRIFT_LIMIT_PCT

# Nothing of ours runs while this is sampled, so it is somebody else's work. Idle on
# this machine sits around 5 % with an editor and a browser open; an active build puts
# it over 50 %. Waiting for quiet costs a minute, discovering the contention afterwards
# costs the whole campaign.
QUIET_LIMIT_PCT = 15.0
QUIET_SAMPLES = 3
QUIET_WAIT_S = 300


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
    r = winproc.run(cmd, cwd=tc.BENCH, env=env, pin=True)
    m = PAT.search(r["stdout"] + r["stderr"])
    if not m:
        return None, (r["stdout"] + r["stderr"])[-400:], r
    return (int(m.group(1)), float(m.group(2))), None, r


def plan_reps(wall_ms):
    """How many samples a runtime earns on a task, from one pilot measurement."""
    if not wall_ms:
        return RUN_MIN_REPS
    if wall_ms >= RUN_SLOW_MS:
        return min(2, RUN_MAX_REPS)
    return max(RUN_MIN_REPS, min(RUN_MAX_REPS, int(RUN_BUDGET_MS // wall_ms)))


def plan_builds(wall_ms):
    """How many times a toolchain is rebuilt, from its first build."""
    if not wall_ms:
        return BUILD_MIN_REPS
    return max(BUILD_MIN_REPS, min(BUILD_MAX_REPS, int(BUILD_BUDGET_MS // wall_ms)))


def schedule(reps):
    """Spread `reps` samples evenly over RUN_MAX_REPS cycles.

    Bunching a runtime's samples at one end of the window would measure it in one
    machine state and its neighbour in another; spreading them means every runtime
    covers the same minutes whatever its sample count.
    """
    cycles = []
    for cycle in range(RUN_MAX_REPS):
        if (cycle + 1) * reps // RUN_MAX_REPS > cycle * reps // RUN_MAX_REPS:
            cycles.append(cycle)
    return set(cycles)


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
    # Every sample is kept, not just the minimum that becomes the result: without them
    # a campaign cannot say how sure it is, and a number nobody can question is not a
    # measurement.
    acc.setdefault("samples", []).append(round(ms, 4))


def spread_pct(samples):
    return (max(samples) / min(samples) - 1.0) * 100.0 if samples else 0.0


def wait_for_quiet():
    """Refuse to start until the machine belongs to us. Returns the settled load."""
    deadline = time.time() + QUIET_WAIT_S
    quiet = 0
    busy = winproc.system_busy_pct()
    while time.time() < deadline:
        busy = winproc.system_busy_pct()
        if busy < QUIET_LIMIT_PCT:
            quiet += 1
            if quiet >= QUIET_SAMPLES:
                return busy
        else:
            if quiet:
                print("  machine busy again (%.0f %%), restarting the count" % busy)
                sys.stdout.flush()
            quiet = 0
    return None


def main():
    global RUN_BUDGET_MS, RUN_MIN_REPS, RUN_MAX_REPS
    global BUILD_BUDGET_MS, BUILD_MIN_REPS, BUILD_MAX_REPS

    ap = argparse.ArgumentParser()
    ap.add_argument("--swc", help="compiler under test (default: bin/swc.exe of the main worktree)")
    ap.add_argument("--budget", type=int, default=RUN_BUDGET_MS,
                    help="measured milliseconds each runtime gets per task")
    ap.add_argument("--build-budget", type=int, default=BUILD_BUDGET_MS,
                    help="wall milliseconds each toolchain gets to be rebuilt, per task")
    ap.add_argument("--warmup", type=int, default=30,
                    help="seconds of reference workload before the first calibration")
    ap.add_argument("--label", default="", help="short note stored with this campaign")
    ap.add_argument("--quick", action="store_true", help="1 sample, no warm-up; smoke test only")
    ap.add_argument("--tasks", default="",
                    help="comma-separated subset of the tasks to sweep, for iterating on one of "
                         "them; a partial sweep is never recorded")
    args = ap.parse_args()

    RUN_BUDGET_MS = args.budget
    BUILD_BUDGET_MS = args.build_budget
    if args.quick:
        RUN_BUDGET_MS = 0
        RUN_MIN_REPS = 1
        RUN_MAX_REPS = 1
        BUILD_BUDGET_MS = 0
        BUILD_MIN_REPS = 1
        BUILD_MAX_REPS = 1
        args.warmup = 0

    tasks = tc.TASKS
    if args.tasks:
        tasks = [t.strip() for t in args.tasks.split(",") if t.strip()]
        unknown = [t for t in tasks if t not in tc.TASKS]
        if unknown:
            print("unknown task(s): %s" % ", ".join(unknown))
            print("known tasks: %s" % ", ".join(tc.TASKS))
            return 1

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
    print("campaign            : %d ms of samples per runtime and task (%d..%d), "
          "%d ms per build" %
          (RUN_BUDGET_MS, RUN_MIN_REPS, RUN_MAX_REPS, BUILD_BUDGET_MS))
    print("timed runs pinned to : 0x%x (%d performance cores)" %
          (winproc.PIN_MASK, bin(winproc.PIN_MASK).count("1")))

    if not args.quick:
        idle = wait_for_quiet()
        if idle is None:
            print("the machine has been busy for %d s: something else is compiling or "
                  "indexing." % QUIET_WAIT_S)
            print("a campaign measured against that is not a measurement; nothing was run")
            return 1
        print("machine idle at %.0f %%, starting" % idle)

    # ------------------------------------------------------------- calibration
    calib_recipe = recipes["cpp-clang-cl"]("sha256", "calib_sha256")
    r, err = build_once(calib_recipe, env)
    if err:
        print("calibration build failed: %s" % err[:400])
        return 1

    # The campaign used to idle for two minutes first, so that it "started cold". A
    # sweep lasts a quarter of an hour and spends nearly all of it hot: starting cold
    # only meant the first task was measured in a state no other task would ever see,
    # and it made the opening calibration unrepresentative — 37 ms against the 50 ms
    # the same workload takes once the machine has settled.
    #
    # Long enough to leave the idle state, short enough not to overshoot it: back to
    # back reference runs are a heavier duty cycle than the sweep, which spends much
    # of its time launching processes and waiting on interpreters, so ninety seconds
    # of it opened the campaign 50 % hotter than it ended. The build and startup
    # phases that follow finish the job at the sweep's own pace.
    if args.warmup:
        print("warming up %d s on the reference workload..." % args.warmup)
        sys.stdout.flush()
        deadline = time.time() + args.warmup
        while time.time() < deadline:
            run_once([calib_recipe["exe"]], env)

    def calibrate(tag, reps=12, quiet=False):
        best = None
        for _ in range(1 if args.quick else reps):
            got, _, _ = run_once([calib_recipe["exe"]], env)
            if got:
                best = got[1] if best is None or got[1] < best else best
        if best is None:
            print("  calibration %-8s produced no valid result" % tag)
            return None
        if not quiet:
            print("  calibration %-8s sha256/C++ = %.3f ms" % (tag, best))
            sys.stdout.flush()
        return best

    results = {"tasks": {}, "hello_build": {}, "hello_run": {}, "calibration": {},
               "skipped": gone}
    results["calibration"]["probes"] = {}
    results["calibration"]["start"] = calibrate("start")
    if results["calibration"]["start"] is None:
        return 1

    # ------------------------------------------------------- fixed compiler cost
    print("== fixed compiler cost (hello world -> exe) ==")
    hello_plan = {}
    for rep in range(BUILD_MAX_REPS):
        for name in hello_builds:
            if name in gone or rep >= hello_plan.get(name, BUILD_MAX_REPS):
                continue
            rec = hello_builds[name]()
            r, err = build_once(rec, env)
            acc = results["hello_build"].setdefault(name, {})
            if err:
                acc["error"] = err
                hello_plan[name] = 0
            else:
                keep_build(acc, r, rec)
                hello_plan.setdefault(name, plan_builds(r["wall_ms"]))
    for name, acc in results["hello_build"].items():
        if acc.get("error"):
            print("  %-20s ERROR %s" % (name, acc["error"][:150]))
        else:
            print("  %-20s build=%9.1f ms  mem=%7.1f MB" %
                  (name, acc["wall_ms"], acc["peak_bytes"] / 1048576.0))
    sys.stdout.flush()

    # ------------------------------------------------------ time to first output
    print("== time to first output (hello world) ==")
    for rep in range(1 if args.quick else 12):
        for name in jit:
            r = winproc.run(hello_runs[name], cwd=tc.BENCH, env=env, pin=True)
            acc = results["hello_run"].setdefault(name, {})
            acc["wall_ms"] = r["wall_ms"] if acc.get("wall_ms") is None else min(acc["wall_ms"], r["wall_ms"])
            acc["peak_bytes"] = max(acc.get("peak_bytes", 0), r["peak_job_bytes"])
    for name in jit:
        acc = results["hello_run"][name]
        print("  %-20s wall=%8.1f ms  mem=%7.1f MB" % (name, acc["wall_ms"], acc["peak_bytes"] / 1048576.0))
    sys.stdout.flush()

    # ------------------------------------------------------------------ the sweep
    for task in tasks:
        # The reference workload again, right before the task. Two endpoints cannot see
        # a burst in the middle: a parallel build once multiplied every compilation of
        # one task by ten and was gone before the closing calibration, so the campaign
        # read clean at both ends and was fiction in between. This timeline sees it.
        probe = calibrate(task, reps=6, quiet=True)
        results["calibration"]["probes"][task] = probe
        print("== %s == (machine %.1f ms)" % (task, probe or 0.0))
        built = {}
        errors = {}
        for name in aot:
            built[name] = recipes[name](task, "%s_%s" % (task, name.replace("-", "_")))

        acc_build = {name: {} for name in aot}
        build_plan = {}
        for rep in range(BUILD_MAX_REPS):
            # Rotated for the same reason the runs are: a build left permanently first
            # in the round is permanently measured on a machine the others just left.
            turn = rep % len(aot)
            for name in aot[turn:] + aot[:turn]:
                if rep >= build_plan.get(name, BUILD_MAX_REPS):
                    continue
                r, err = build_once(built[name], env)
                if err:
                    errors[name] = err
                    build_plan[name] = 0
                else:
                    keep_build(acc_build[name], r, built[name])
                    build_plan.setdefault(name, plan_builds(r["wall_ms"]))

        cmds = {}
        for name in aot:
            if name not in errors:
                cmds[name] = launchers[name](built[name]["exe"])
        for name in jit:
            cmds[name] = runtimes[name](task)

        # One pilot sample per runtime prices the task, then each runtime is given the
        # number of samples its own duration affords inside the budget.
        acc_run = {name: {} for name in cmds}
        plan = {}
        for name, cmd in cmds.items():
            got, err, r = run_once(cmd, env)
            if not got:
                acc_run[name]["error"] = err
                plan[name] = set()
            else:
                keep_run(acc_run[name], got, r)
                plan[name] = schedule(plan_reps(r["wall_ms"]) - 1)

        names = [n for n in cmds if not acc_run[n].get("error")]
        for cycle in range(RUN_MAX_REPS):
            due = [n for n in names if cycle in plan[n]]
            if not due:
                continue
            # Rotate: no runtime keeps the head of the cycle, and the head of a cycle
            # is the one that pays for whatever the previous cycle left behind.
            turn = cycle % len(due)
            for name in due[turn:] + due[:turn]:
                got, err, r = run_once(cmds[name], env)
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
                    print("  %-20s run=%10.2f ms (%2dx, %+4.0f%%)  build=%8.1f ms  "
                          "bmem=%7.1f MB  check=%d"
                          % (name, r["ms"], len(r.get("samples") or []),
                             spread_pct(r.get("samples")), entry["build"]["wall_ms"],
                             entry["build"]["peak_bytes"] / 1048576.0, r["check"]))
                else:
                    print("  %-20s run=%10.2f ms (%2dx, %+4.0f%%)  rmem=%7.1f MB  check=%d"
                          % (name, r["ms"], len(r.get("samples") or []),
                             spread_pct(r.get("samples")), r["peak_bytes"] / 1048576.0,
                             r["check"]))
            results["tasks"][task][name] = entry
        sys.stdout.flush()

    results["calibration"]["end"] = calibrate("end")
    if results["calibration"]["end"] is None:
        return 1
    s, e = results["calibration"]["start"], results["calibration"]["end"]
    results["calibration"]["drift_pct"] = (e - s) / s * 100.0

    timeline = [("start", s)] + sorted(results["calibration"]["probes"].items(),
                                       key=lambda kv: tasks.index(kv[0])
                                       if kv[0] in tasks else 0) + [("end", e)]
    timeline = [(tag, value) for tag, value in timeline if value]

    # What matters is a probe out of line with the ones around it, not the spread of
    # the whole timeline. The machine settles across a campaign — it opens 50 % slower
    # than it ends, warm from the warm-up and cooling into the lighter duty cycle of
    # the sweep — and that ramp is intrinsic: it moves a task's Swag measurement and
    # its controls together, which is exactly what the per-task correction is for.
    # Interference does not behave that way. It arrives, hits one task, and leaves,
    # and it hits compilation far harder than execution. So each probe is compared
    # with its neighbours in time: a ramp reads flat, a visitor reads as a spike.
    spike, worst_tag = 0.0, timeline[0][0]
    for index, (tag, value) in enumerate(timeline):
        neighbours = [timeline[j][1] for j in (index - 1, index + 1)
                      if 0 <= j < len(timeline)]
        local = (value / min(neighbours) - 1.0) * 100.0 if neighbours else 0.0
        if local > spike:
            spike, worst_tag = local, tag
    results["calibration"]["spread_pct"] = spike
    results["calibration"]["worst_moment"] = worst_tag
    print("machine timeline: %s" % "  ".join("%s=%.1f" % tv for tv in timeline))
    print("worst departure from its neighbours: %.1f %% (at %s)" % (spike, worst_tag))
    print("drift over the sweep: %+.1f %%" % results["calibration"]["drift_pct"])

    # --------------------------------------------------------------- checksums
    bad = []
    for task in tasks:
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

    results["meta"] = history.describe(swc, args.label, {
        "pin_mask": "0x%x" % winproc.PIN_MASK,
        "pin_cores": bin(winproc.PIN_MASK).count("1"),
        "budget_ms": RUN_BUDGET_MS,
        "min_reps": RUN_MIN_REPS,
        "max_reps": RUN_MAX_REPS,
        "build_budget_ms": BUILD_BUDGET_MS,
        "warmup_s": args.warmup,
    })

    if args.quick:
        # Nothing is written at all: mkpage.py reports the most recent file in
        # results/, so leaving a one-repetition campaign there would quietly turn the
        # published page into noise.
        print("quick run: nothing recorded, one repetition proves nothing")
        return 0

    if len(tasks) != len(tc.TASKS):
        # Same reason: the page and the normalized history both read a campaign as
        # covering every task, and a subset would silently publish gaps.
        print("partial sweep (%s): nothing recorded" % ", ".join(tasks))
        return 0

    stamp = results["meta"]["stamp"]
    spread = results["calibration"]["spread_pct"]
    rejected = spread > DRIFT_LIMIT_PCT
    folder = os.path.join(tc.BENCH, "results", "rejected" if rejected else "")
    os.makedirs(folder, exist_ok=True)
    raw = os.path.join(folder, "%s.json" % stamp)
    with open(raw, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2)

    if rejected:
        # Kept, because deleting a measurement one dislikes is how a benchmark starts
        # lying, but out of the history: something else was using the machine while it
        # measured, so this campaign dates the machine, not the compiler.
        print("the reference workload moved %.1f %% across the campaign, past the %.0f %% "
              "limit, worst around %s" % (spread, DRIFT_LIMIT_PCT,
                                          results["calibration"]["worst_moment"]))
        print("campaign archived in results/rejected/%s.json and NOT recorded" % stamp)
        print("close what else is using the machine and measure again")
        return 0

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
