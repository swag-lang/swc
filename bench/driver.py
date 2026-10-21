"""Run one benchmark campaign and record it.

    py -3 driver.py [--swc PATH] [--label TEXT] [--quick] [--tasks a,b] [--build | --run]
                    [--swc-cores N] [--warmup SECONDS] [--no-reference]

A campaign measures, in one sitting, the Swag compiler under test, the frozen Swag
reference, and every other toolchain, on the same twelve programs. It publishes two kinds
of numbers, and both are ratios measured inside the same minutes:

  * Swag against each other language: the ratio of their medians on each task, and the
    geometric mean of those ratios over the panel, each with its 95 % interval.
  * Swag against its own reference: the median of the per-round ratios, sample paired with
    sample. This is the progress curve, and it needs no correction between campaigns
    because the reference is measured next to the compiler every time.

Every sample is taken on a machine verified to be otherwise quiet while it ran (see
machine.py), from the same warm toolchain state (see toolchains.py), in rounds whose order
is drawn at random (see sampler.py). README.md states the protocol in full.
"""
import argparse
import datetime
import glob
import json
import os
import re
import sys
import time

import allocbench
import history
import installs
import machine
import sampler
import toolchains as tc
import winproc

# A compiler error reaches this driver verbatim, and swc draws its diagnostics with box
# characters the default Windows console code page cannot encode.
for _stream in (sys.stdout, sys.stderr):
    if hasattr(_stream, "reconfigure"):
        _stream.reconfigure(encoding="utf-8", errors="replace")

PAT = re.compile(r"CHECK=(-?\d+)\s+MS=([\d.]+)")

# A campaign whose accepted samples include more than this share still contended after
# every retry measured a busy machine, and is archived instead of recorded.
CONTENDED_LIMIT = 0.05
QUIET_START_S = 600
CALIBRATION_REPS = 7


def log(message=""):
    print(message)
    sys.stdout.flush()


def process_error(r):
    output = "\n".join(s.rstrip() for s in (r["stdout"], r["stderr"]) if s)
    return "exit=%d\n%s" % (r["exit"], output[-4000:])


class Campaign:
    def __init__(self, args, t, env, subject, reference, stamp):
        self.args = args
        self.t = t
        self.env = env
        self.installs = {"subject": subject}
        if reference:
            self.installs["reference"] = reference
        self.quick = args.quick
        self.cores = args.swc_cores
        self.waits = []
        self.rng, self.seed = sampler.campaign_rng(stamp, args.label)
        self.baselines = {family: machine.Baseline() for family in ("build", "run", "hello", "loop")}

    # ------------------------------------------------------------------ plans
    def plan(self, family):
        if self.quick:
            return sampler.quick_plan
        tracked = set(tc.TRACKED) | set(tc.REFERENCES)
        if family == "run":
            return lambda name, pilot: sampler.plan_run(name in tracked, pilot)
        if family == "build":
            return lambda name, pilot: sampler.plan_build(name in tracked, pilot)
        return lambda name, pilot: sampler.plan_loop(pilot)

    def units(self, names):
        """Each Swag runtime paired with its reference counterpart, every other runtime alone."""
        present = set(names)
        units, paired = [], set()
        for name in names:
            if name in paired:
                continue
            partner = tc.REFERENCE_OF.get(name)
            if partner in present:
                units.append((name, partner))
                paired.update((name, partner))
            elif name not in tc.REFERENCES:
                units.append((name,))
        return units

    # ----------------------------------------------------------------- builds
    def _prepare(self, recipe):
        for path in recipe["clean"]:
            tc.rm(path)
        for path in recipe["mkdir"]:
            os.makedirs(path, exist_ok=True)

    def warm_build(self, recipe):
        """One untimed build, which also leaves the toolchain caches the samples restore."""
        state = recipe["state"]
        if state:
            if state.owned:
                state.reset()
            else:
                state.restore()
        self._prepare(recipe)
        r = winproc.run(recipe["cmd"], cwd=recipe["cwd"], env=self.env | recipe["env"])
        if r["exit"] != 0 or not os.path.exists(recipe["exe"]):
            return process_error(r)
        if state and state.capture_on_warm:
            state.capture()
        return None

    def build_sample(self, recipe):
        self._prepare(recipe)
        if recipe["state"]:
            recipe["state"].restore()
        r = machine.timed_run(recipe["cmd"], cwd=recipe["cwd"], env=self.env | recipe["env"])
        if r["exit"] != 0 or not os.path.exists(recipe["exe"]):
            raise sampler.SampleError(process_error(r))
        return {"wall_ms": r["wall_ms"], "cpu_ms": r["job_cpu_ms"], "peak_bytes": r["peak_job_bytes"],
                "peak_working_set_bytes": r["peak_working_set_bytes"], "foreign_cores": r["foreign_cores"]}

    def measure_builds(self, recipes):
        errors = {}
        for name, recipe in recipes.items():
            error = self.warm_build(recipe)
            if error:
                errors[name] = error
                log("  %-20s BUILD ERROR %s" % (name, error.splitlines()[-1] if error else ""))
        names = [n for n in recipes if n not in errors]
        series = sampler.run_rounds(self.units(names), lambda n, _: self.build_sample(recipes[n]),
                                    self.plan("build"), "wall_ms", self.rng, self.waits,
                                    self.baselines["build"], log)
        out = {}
        for name, recipe in recipes.items():
            if name in errors:
                out[name] = {"error": errors[name]}
                continue
            out[name] = series[name].as_dict()
            artifacts = glob.glob(recipe["artifact_glob"]) if recipe["artifact_glob"] else [recipe["exe"]]
            out[name]["exe_bytes"] = sum(os.path.getsize(p) for p in artifacts if os.path.exists(p))
        return out

    # ------------------------------------------------------------------- runs
    def run_sample(self, cmd, overrides):
        r = machine.timed_run(cmd, cwd=tc.BENCH, env=self.env | overrides, pin=True)
        m = PAT.search(r["stdout"] + r["stderr"])
        if r["exit"] != 0 or not m:
            raise sampler.SampleError(process_error(r))
        return {"ms": float(m.group(2)), "check": int(m.group(1)), "wall_ms": r["wall_ms"],
                "peak_bytes": r["peak_job_bytes"], "foreign_cores": r["foreign_cores"]}

    def measure_runs(self, commands):
        series = sampler.run_rounds(self.units(list(commands)),
                                    lambda n, _: self.run_sample(*commands[n]),
                                    self.plan("run"), "ms", self.rng, self.waits,
                                    self.baselines["run"], log)
        out = {}
        for name, s in series.items():
            out[name] = s.as_dict()
            checks = {x["check"] for x in s.samples}
            if len(checks) > 1:
                out[name]["error"] = "unstable checksum: %s" % sorted(checks)
            elif checks:
                out[name]["check"] = checks.pop()
        return out

    def hello_sample(self, spec):
        if spec["state"]:
            spec["state"].restore()
        r = machine.timed_run(spec["cmd"], cwd=tc.BENCH, env=self.env | spec["env"], pin=True,
                              first_stdout_match=spec["marker"])
        if r["exit"] != 0 or r["first_stdout_ms"] is None:
            raise sampler.SampleError(process_error(r))
        return {"first_ms": r["first_stdout_ms"], "wall_ms": r["wall_ms"], "peak_bytes": r["peak_job_bytes"],
                "foreign_cores": r["foreign_cores"]}

    def measure_hello_runs(self, specs):
        for spec in specs.values():
            if spec["state"]:
                spec["state"].reset()
            winproc.run(spec["cmd"], cwd=tc.BENCH, env=self.env | spec["env"])
            if spec["state"]:
                spec["state"].capture()
        series = sampler.run_rounds(self.units(list(specs)), lambda n, _: self.hello_sample(specs[n]),
                                    self.plan("run"), "first_ms", self.rng, self.waits,
                                    self.baselines["hello"], log)
        return {name: s.as_dict() for name, s in series.items()}

    # ------------------------------------------------------------- edit loop
    def loop_sample(self, workload):
        env = self.env | workload["env"]
        if workload["prepare"]:
            workload["prepare"](env)
        r = machine.timed_run(workload["cmd"], cwd=workload["cwd"], env=env)
        if r["exit"] != 0:
            raise sampler.SampleError(process_error(r))
        return {"wall_ms": r["wall_ms"], "cpu_ms": r["job_cpu_ms"], "peak_bytes": r["peak_job_bytes"],
                "peak_working_set_bytes": r["peak_working_set_bytes"], "foreign_cores": r["foreign_cores"]}

    def measure_loop(self):
        plans = {role: tc.make_compiler_workloads(install, self.cores)
                 for role, install in self.installs.items()}
        out = {}
        for wid in tc.COMPILER_WORKLOADS:
            jobs = {role: plans[role][wid] for role in plans}
            errors = {}
            for role, job in jobs.items():
                try:
                    self.loop_sample(job)
                except (sampler.SampleError, RuntimeError) as error:
                    errors[role] = str(error)
            units = [tuple(r for r in ("subject", "reference") if r in jobs and r not in errors)]
            series = sampler.run_rounds([u for u in units if u], lambda n, _: self.loop_sample(jobs[n]),
                                        self.plan("loop"), "wall_ms", self.rng, self.waits,
                                        self.baselines["loop"], log)
            out[wid] = {role: ({"error": errors[role]} if role in errors else series[role].as_dict())
                        for role in jobs}
            line = "  %-14s" % wid
            for role in jobs:
                s = series.get(role)
                e = s.estimate() if s else None
                line += "  %s %s" % (role, ("%.1f ms (n=%d)" % (e.value, e.n)) if e else errors.get(role, "-")[:60])
            log(line)
        return out


def quality(results):
    """How many accepted samples were still contended, and how many were taken again."""
    accepted = contended = set_aside = 0

    def walk(node):
        nonlocal accepted, contended, set_aside
        if isinstance(node, dict):
            if "samples" in node and isinstance(node["samples"], list):
                accepted += len(node["samples"])
                contended += sum(1 for s in node["samples"] if s.get("contended"))
                set_aside += len(node.get("set_aside") or [])
            for value in node.values():
                if isinstance(value, (dict, list)):
                    walk(value)
        elif isinstance(node, list):
            for value in node:
                if isinstance(value, dict):
                    walk(value)

    for section in ("hello_build", "hello_run", "loop", "tasks"):
        walk(results.get(section) or {})
    return {"accepted": accepted, "contended": contended, "set_aside": set_aside,
            "contended_share": contended / accepted if accepted else 0.0}


def campaign_errors(results):
    """A campaign in which an available port failed or disagreed has measured nothing."""
    errors = []
    for family in ("hello_build", "hello_run"):
        for name, entry in (results.get(family) or {}).items():
            if entry.get("error"):
                errors.append("%s/%s: %s" % (family, name, entry["error"].splitlines()[-1]))
    for wid, roles in (results.get("loop") or {}).items():
        for role, entry in roles.items():
            if entry.get("error"):
                errors.append("loop/%s/%s: %s" % (wid, role, entry["error"].splitlines()[-1]))
    errors += ["allocator/%s" % e for e in allocbench.errors(results.get("allocator"))]
    for task, entries in results["tasks"].items():
        seen = {}
        for name, entry in entries.items():
            for family in ("build", "run"):
                record = entry.get(family) or {}
                if record.get("error"):
                    errors.append("%s/%s/%s: %s" % (task, name, family, record["error"].splitlines()[-1]))
            check = (entry.get("run") or {}).get("check")
            if check is not None:
                seen.setdefault(check, []).append(name)
        if len(seen) > 1:
            errors.append("%s: checksums disagree %s" % (task, seen))
    return errors


def parse_args(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--swc", help="compiler under test (default: bin/swc.exe of this checkout)")
    ap.add_argument("--swc-cores", type=int, default=0, help="cap Swag compiler workers; 0 = compiler default")
    ap.add_argument("--warmup", type=int, default=30, help="seconds of reference workload before measuring")
    ap.add_argument("--label", default="", help="short note stored with this campaign")
    ap.add_argument("--quick", action="store_true", help="one sample of everything; proves the plumbing, records nothing")
    ap.add_argument("--tasks", default="", help="comma-separated subset of tasks; a partial sweep is never recorded")
    ap.add_argument("--no-reference", action="store_true",
                    help="measure without the frozen reference; such a campaign has no progress values")
    ap.add_argument("--out", help="also write the raw campaign to this file; it is never recorded from there")
    phase = ap.add_mutually_exclusive_group()
    phase.add_argument("--build", action="store_true", help="measure compilation only")
    phase.add_argument("--run", action="store_true", help="measure execution only")
    return ap.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    if args.swc_cores < 0:
        raise SystemExit("--swc-cores needs a nonnegative value")
    measure_build, measure_run = not args.run, not args.build
    tasks = [t.strip() for t in args.tasks.split(",") if t.strip()] or list(tc.TASKS)
    unknown = [t for t in tasks if t not in tc.TASKS]
    if unknown:
        raise SystemExit("unknown task(s): %s (known: %s)" % (", ".join(unknown), ", ".join(tc.TASKS)))

    started = datetime.datetime.now(datetime.timezone.utc)
    stamp = started.strftime("%Y%m%d-%H%M%S")
    described = machine.describe()
    problem = machine.power_problem(described["power"])
    if problem and not args.quick:
        log("cannot measure: %s" % problem)
        return 1

    t = tc.discover()
    gone = tc.missing(t)
    if gone:
        log("missing toolchains, skipped: %s" % ", ".join(gone))
    swc = os.path.abspath(tc.swc_path(args.swc))
    if not os.path.exists(swc):
        log("compiler not found: %s" % swc)
        return 1

    os.makedirs(tc.OUT, exist_ok=True)
    log("machine             : %s, %s, %s, power mode %s"
        % (described["cpu"], described["os"], "AC" if described["power"]["ac"] else "battery",
           described["power"]["mode"]))
    log("compiler under test : %s" % swc)
    subject = installs.snapshot_subject(swc)
    log("  installed as      : %s (sha256 %s)" % (subject.root, subject.meta["swc_sha256"][:16]))
    reference = None
    if not args.no_reference:
        reference, why = installs.load_reference()
        if reference is None:
            log("reference           : %s" % why)
            log("freeze one with `py -3 bench/reference.py freeze <name>`, or pass --no-reference")
            return 1
        log("reference           : %s, commit %s, frozen %s" % (reference.meta["name"], reference.meta["commit"],
                                                                 reference.meta["frozen"][:10]))
    env = tc.build_env(t)
    log("preparing Swag dependencies outside the clock...")
    for install in [subject] + ([reference] if reference else []):
        error = install.publish_dependencies(env, args.swc_cores)
        if error:
            log("dependency preparation failed for %s: %s" % (install.role, error))
            return 1
        missing_tasks = [task for task in tasks if not install.has_task(task)]
        if missing_tasks:
            log("%s has no sources for %s" % (install.role, ", ".join(missing_tasks)))
            return 1

    campaign = Campaign(args, t, env, subject, reference, stamp)
    shared = {}
    if measure_build or measure_run:
        shared["zig"] = tc.zig_global_cache()
        if "go" not in gone:
            log("warming Go's standard-library build cache outside the clock...")
            shared["go"] = tc.go_std_cache(t, env, [tc.go_files(task) for task in tasks] +
                                           [[os.path.join(tc.SRC, "hello", "hello.go")]])
    roles = campaign.installs
    recipes = tc.make_recipes(t, env, roles, args.swc_cores, shared)
    launchers = tc.make_launchers(t)
    runtimes = tc.make_runtimes(t, roles, args.swc_cores)
    aot = [n for n in tc.SWAG_AOT + ["ref-release", "ref-devmode"] + tc.AOT_CONTROLS
           if n in recipes and n not in gone]
    jit = [n for n in tc.SWAG_JIT + ["ref-jit-release", "ref-jit-devmode"] + tc.JIT_CONTROLS
           if n in runtimes and n not in gone]

    versions = {name: machine.tool_version(cmd, env) for name, cmd in tc.version_commands(t).items()
                if name not in gone}

    if not args.quick:
        quiet, waited, load = machine.wait_for_quiet(QUIET_START_S, seconds=3)
        if not quiet:
            log("the machine stayed busy for %d s (%.1f foreign cores); nothing was measured" % (waited, load))
            return 1
        log("machine quiet (%.1f foreign cores), starting" % load)

    calib = recipes["cpp-clang-cl"]("sha256", "calib_sha256")
    error = campaign.warm_build(calib)
    if error:
        log("calibration build failed: %s" % error)
        return 1

    def probe():
        values = []
        for _ in range(1 if args.quick else CALIBRATION_REPS):
            try:
                values.append(campaign.run_sample([calib["exe"]], {})["ms"])
            except sampler.SampleError:
                pass
        return sorted(values)[len(values) // 2] if values else None

    if args.warmup and not args.quick:
        log("warming up %d s on the reference workload..." % args.warmup)
        deadline = time.time() + args.warmup
        while time.time() < deadline:
            winproc.run([calib["exe"]], cwd=tc.BENCH, env=env, pin=True)

    results = {"tasks": {}, "calibration": {"probes": {"start": probe()}}, "skipped": gone}

    if measure_build:
        log("== hello world, source to executable ==")
        hello = tc.make_hello_builds(t, env, roles, args.swc_cores, shared)
        results["hello_build"] = campaign.measure_builds({n: make() for n, make in hello.items() if n not in gone})
        log("== the edit-build loop ==")
        results["loop"] = campaign.measure_loop()
    if measure_run:
        log("== hello world, time to first output ==")
        specs = {n: s for n, s in tc.make_hello_runs(t, roles, args.swc_cores).items() if n not in gone}
        results["hello_run"] = campaign.measure_hello_runs(specs)

    for task in tasks:
        results["calibration"]["probes"][task] = probe()
        log("== %s == (reference workload %.1f ms)" % (task, results["calibration"]["probes"][task] or 0))
        built = {name: recipes[name](task, "%s_%s" % (task, name.replace("-", "_"))) for name in aot}
        entries = {name: {"kind": "aot"} for name in aot} | {name: {"kind": "jit"} for name in jit}
        failed = set()
        if measure_build:
            for name, record in campaign.measure_builds(built).items():
                entries[name]["build"] = record
                if record.get("error"):
                    failed.add(name)
        else:
            for name, recipe in built.items():
                error = campaign.warm_build(recipe)
                if error:
                    entries[name]["run"] = {"error": error}
                    failed.add(name)
        if measure_run:
            commands = {name: (launchers[name](built[name]["exe"]), {}) for name in aot if name not in failed}
            commands |= {name: runtimes[name](task) for name in jit}
            for name, record in campaign.measure_runs(commands).items():
                entries[name]["run"] = record
        results["tasks"][task] = entries
        summary = []
        for name in tc.TRACKED:
            for family, key in (("build", "wall_ms"), ("run", "ms")):
                record = entries.get(name, {}).get(family)
                if record and record.get("samples"):
                    values = [s[key] for s in record["samples"]]
                    summary.append("%s %s %.1f" % (name, family, sorted(values)[len(values) // 2]))
        log("  " + "  ".join(summary))

    if measure_run:
        results["calibration"]["probes"]["allocator"] = probe()
        log("== allocator ==")
        alloc_env = subject.env(env, subject.temp("allocator"))
        exes, build_errors = allocbench.build(subject.swc, env, os.path.join(tc.OUT, "allocator"),
                                              args.swc_cores, swag_env=alloc_env)
        results["allocator"] = allocbench.measure(exes, 1 if args.quick else allocbench.REPS)
        for name, error in build_errors.items():
            log("  %-20s BUILD ERROR %s" % (name, error))
            for accs in results["allocator"].values():
                accs[name] = {"error": error}

    results["calibration"]["probes"]["end"] = probe()
    results["quality"] = quality(results)
    results["quality"]["quiet_waits_s"] = round(sum(campaign.waits), 1)
    results["quality"]["foreign_median_cores"] = {family: b.median() for family, b in campaign.baselines.items()}
    results["meta"] = history.describe(swc, args.label, {
        "phases": (["build"] if measure_build else []) + (["run"] if measure_run else []),
        "swc_cores": args.swc_cores, "pin_mask": "0x%x" % winproc.PIN_MASK,
        "pin_cores": bin(winproc.PIN_MASK).count("1"), "warmup_s": args.warmup,
        "foreign_excess_cores": machine.FOREIGN_EXCESS_CORES, "seed": campaign.seed,
        "tasks": tasks, "quick": args.quick,
    }, stamp=stamp, started=started)
    results["meta"]["machine"] = described
    results["meta"]["machine"]["power_end"] = machine.power()
    results["meta"]["installs"] = {"subject": subject.meta,
                                   "reference": reference.meta if reference else None}
    results["meta"]["toolchains"] = versions

    q = results["quality"]
    log("samples: %d accepted, %d taken again after interference, %d still contended (%.1f %%), "
        "%.0f s waited for quiet" % (q["accepted"], q["set_aside"], q["contended"], 100 * q["contended_share"],
                                     q["quiet_waits_s"]))
    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            json.dump(results, f, indent=1)
        log("raw campaign also written to %s" % args.out)
    bad = campaign_errors(results)
    if bad:
        log("campaign contains build, run or checksum errors:")
        for line in bad:
            log("  " + line)
        log("nothing recorded")
        return 1
    log("checksums agree across every runtime on every task")

    if args.quick:
        log("quick run: nothing recorded, one sample proves nothing")
        return 0
    if len(tasks) != len(tc.TASKS):
        log("partial sweep (%s): nothing recorded" % ", ".join(tasks))
        return 0
    if reference is None:
        log("no reference: nothing recorded, a campaign without its reference cannot be compared")
        return 0

    rejected = q["contended_share"] > CONTENDED_LIMIT or problem or machine.power_problem(
        results["meta"]["machine"]["power_end"])
    folder = os.path.join(tc.BENCH, "results", "rejected" if rejected else "")
    os.makedirs(folder, exist_ok=True)
    raw = os.path.join(folder, "%s.json" % stamp)
    with open(raw, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=1)
    if rejected:
        log("campaign archived in results/rejected/%s.json and NOT recorded: the machine was busy or "
            "changed power state" % stamp)
        return 0
    log("raw campaign written to results/%s.json" % stamp)
    entries = history.append(results)
    log("history updated (%d campaigns)" % len(entries))
    return 0


if __name__ == "__main__":
    sys.exit(main())
