"""Run a complete perf campaign: rebuild, measure, report.

Called by bench.bat. A campaign always rebuilds the compiler first, so what gets
measured is the code currently in the tree rather than whatever binary happened to
be lying around.

    py -3 campaign.py [--label TEXT] [--quick] [--no-build] [--report-only]
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
    vs = tc.discover()["vs"]
    if not vs:
        raise SystemExit("Visual Studio not found; set BENCH_VS_ROOT")
    msbuild = os.path.join(vs, "MSBuild", "Current", "Bin", "amd64", "MSBuild.exe")
    if not os.path.exists(msbuild):
        msbuild = os.path.join(vs, "MSBuild", "Current", "Bin", "MSBuild.exe")
    if not os.path.exists(msbuild):
        raise SystemExit("MSBuild not found under %s" % vs)

    print("building Release x64...")
    sys.stdout.flush()
    r = subprocess.run([msbuild, os.path.join(ROOT, "swc.sln"),
                        "-p:Configuration=Release", "-p:Platform=x64", "-m", "-v:m"],
                       cwd=ROOT, capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    print("\n".join((r.stdout or "").splitlines()[-12:]))
    if r.returncode != 0:
        raise SystemExit("the Release build failed; fix it before measuring")

    swc = os.path.join(ROOT, "bin", "swc.exe")
    if not os.path.exists(swc):
        raise SystemExit("build reported success but %s is missing" % swc)
    print("compiler under test: %s (%d bytes)" % (swc, os.path.getsize(swc)))


def run(script, extra):
    r = subprocess.run([PY, os.path.join(tc.BENCH, script)] + extra, cwd=tc.BENCH)
    if r.returncode != 0:
        raise SystemExit("%s failed" % script)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--label", default="", help="short note stored with this campaign")
    ap.add_argument("--quick", action="store_true",
                    help="1 repetition, no cooldown; smoke test, not recorded")
    ap.add_argument("--no-build", action="store_true", help="measure the binary already built")
    ap.add_argument("--report-only", action="store_true",
                    help="regenerate the page from the existing history, measure nothing")
    args = ap.parse_args()

    if args.report_only:
        step(1, 1, "Report")
        run("mkpage.py", [])
        return 0

    total = 2 if args.no_build else 3
    n = 0

    if not args.no_build:
        n += 1
        step(n, total, "Rebuild the compiler under test")
        build()

    n += 1
    step(n, total, "Measure")
    warn_if_dirty()
    extra = ["--label", args.label] if args.label else []
    if args.quick:
        extra.append("--quick")
    run("driver.py", extra)

    n += 1
    step(n, total, "Report")
    run("mkpage.py", [])

    print("\nCampaign complete. Review bench/bench.html, then commit bench/history.json,")
    print("bench/results/ and bench/bench.html to keep the record.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
