"""Run a complete perf campaign: measure, then report.

Called by tools/bench.bat. A campaign uses bin/swc.exe by default and checks its normal
Release build before measuring. MSBuild updates only outputs that are out of date.

    py -3 campaign.py [--label TEXT] [--quick] [--no-build] [--report-only]
                      [--build | --run]
"""
import argparse
import os
import subprocess
import sys

import toolchains as tc

ROOT = tc.worktree()
PY = sys.executable


def step(n, total, title):
    print("\n[%d/%d] %s" % (n, total, title))
    print("-" * (len(title) + 8))
    sys.stdout.flush()


def warn_if_dirty():
    """Measuring a modified tree is legitimate — it is how you check that a change
    helped — but the campaign is then not reproducible from its commit, so say so.
    The entry is marked dirty in the history either way."""
    r = subprocess.run(["git", "status", "--porcelain", "--untracked-files=no"],
                       cwd=ROOT, capture_output=True, text=True)
    files = [l for l in r.stdout.splitlines() if l.strip()]
    if files:
        print("note: %d file(s) modified since the last commit." % len(files))
        print("      This campaign is recorded as dirty: its commit alone will not")
        print("      reproduce it. Commit first when the result is worth keeping.")


def build():
    release = os.path.join(ROOT, "tools", "release.bat")
    print("running tools/release.bat...")
    sys.stdout.flush()
    command = [os.environ.get("COMSPEC", "cmd.exe"), "/d", "/c", release]
    r = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    if r.stdout:
        print(r.stdout.rstrip())
    if r.returncode != 0:
        if r.stderr:
            print(r.stderr, file=sys.stderr)
        raise SystemExit("tools/release.bat failed; build the Release compiler before measuring")

    swc = os.path.join(ROOT, "bin", "swc.exe")
    if not os.path.exists(swc):
        raise SystemExit("build reported success but %s is missing" % swc)
    print("compiler under test: %s (%d bytes)" % (swc, os.path.getsize(swc)))
    return swc


def run(script, extra):
    env = os.environ.copy()
    env["SWAG_PATH"] = os.path.join(ROOT, "bin")
    r = subprocess.run([PY, os.path.join(tc.BENCH, script)] + extra, cwd=tc.BENCH, env=env)
    if r.returncode != 0:
        raise SystemExit("%s failed" % script)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--label", default="", help="short note stored with this campaign")
    ap.add_argument("--quick", action="store_true",
                    help="1 sample, no warm-up; smoke test, not recorded")
    ap.add_argument("--no-build", action="store_true",
                    help="require and measure bin/swc.exe without building")
    ap.add_argument("--swc-cores", type=int, default=0,
                    help="cap Swag compiler workers; 0 uses the compiler default")
    ap.add_argument("--out", help="also retain raw results and incomplete checkpoints at this path")
    ap.add_argument("--report-only", action="store_true",
                    help="regenerate the page from the existing history, measure nothing")
    phase = ap.add_mutually_exclusive_group()
    phase.add_argument("--build", action="store_true",
                       help="measure compilation only; update only compilation history and report data")
    phase.add_argument("--run", action="store_true",
                       help="measure execution only; update only execution history and report data")
    args = ap.parse_args()
    if args.swc_cores < 0:
        raise SystemExit("--swc-cores needs a nonnegative value")

    if args.report_only:
        step(1, 1, "Report")
        run("mkpage.py", [])
        return 0

    published_swc = os.path.join(ROOT, "bin", "swc.exe")
    needs_build = not args.no_build
    if args.no_build and not os.path.isfile(published_swc):
        raise SystemExit("bin/swc.exe is missing; build it first or run without --no-build")

    total = 1 + int(needs_build) + int(not args.quick)
    n = 0

    swc = published_swc
    if needs_build:
        n += 1
        step(n, total, "Build the compiler under test")
        swc = build()

    n += 1
    step(n, total, "Measure")
    if not args.quick:
        warn_if_dirty()
    extra = ["--swc", swc]
    if args.label:
        extra += ["--label", args.label]
    if args.swc_cores:
        extra += ["--swc-cores", str(args.swc_cores)]
    if args.out:
        extra += ["--out", os.path.abspath(args.out)]
    if args.quick:
        extra.append("--quick")
    if args.build:
        extra.append("--build")
    elif args.run:
        extra.append("--run")
    run("driver.py", extra)

    if args.quick:
        print("\nQuick campaign complete. No history or report files were written.")
        return 0

    n += 1
    step(n, total, "Report")
    run("mkpage.py", [])

    print("\nCampaign complete. Review bench/bench.html, then commit bench/history.json,")
    print("bench/results/ and bench/bench.html to keep the record.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
