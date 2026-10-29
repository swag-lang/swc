"""Compare the Swag runtime allocator with mimalloc and the C runtime heap, outside a campaign.

    py -3 run.py [--out DIR] [--reps N] [--only pair,trees:4,...] [--swc PATH] [--no-build]
                 [--against EXE] [--latency]

The campaign (`tools/bench.bat`) measures the same thing and records it; this runner records
nothing and is meant for iterating on the allocator. It builds the three executables with
../allocbench.py, then prints, per workload, the median ns per operation and the largest peak
working set and commit of the rounds. --against adds a column for an allocbench executable
built earlier, typically with the runtime from before a change.

The executables and their intermediates go to --out, which defaults to a directory under the
system temporary directory, never into the checkout. Besides the end-to-end time, the table
shows the slowest worker's time per operation and, for the workloads that print them, the gated
phase, the latency percentiles (--latency) and the retained working sets.
"""
import argparse
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import allocbench  # noqa: E402
import toolchains as tc  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(tempfile.gettempdir(), "swag-allocbench"))
    ap.add_argument("--reps", type=int, default=allocbench.REPS)
    ap.add_argument("--only", default="", help="comma-separated workloads, 'name' or 'name:threads'")
    ap.add_argument("--swc", help="compiler under test (default: bin/swc.exe of this worktree)")
    ap.add_argument("--no-build", action="store_true", help="reuse the executables already in --out")
    ap.add_argument("--against", help="a previously built allocbench executable, shown as 'before'")
    ap.add_argument("--latency", action="store_true", help="record every operation's duration and report p50/p99")
    args = ap.parse_args()

    workloads = [w.strip() for w in args.only.split(",") if w.strip()] or allocbench.WORKLOADS
    if args.no_build:
        exes = {"swag": os.path.join(args.out, "swag", "allocator.exe"),
                "mimalloc": os.path.join(args.out, "allocbench_mimalloc.exe"),
                "crt": os.path.join(args.out, "allocbench_crt.exe")}
    else:
        exes, errors = allocbench.build(os.path.abspath(tc.swc_path(args.swc)),
                                        tc.build_env(tc.discover()), args.out)
        for name, error in errors.items():
            print("%s: build failed\n%s" % (name, error))
        if errors:
            return 1

    names = list(allocbench.IMPLEMENTATIONS)
    if args.against:
        allocbench.IMPLEMENTATIONS += ("before",)
        exes["before"] = os.path.abspath(args.against)
        names.append("before")

    section = allocbench.measure(exes, args.reps, workloads, report=None, latency=args.latency)
    print("%-10s" % "workload" + "".join("%28s" % n for n in names))
    for workload, accs in section.items():
        cells = []
        details = []
        for name in names:
            acc = accs[name]
            if acc.get("error"):
                cells.append("ERROR")
                continue
            cells.append("%10.1f ns %6.1f/%6.1f MB" % (
                acc["ns"], acc["peak_working_set_bytes"] / 1048576.0, acc["peak_bytes"] / 1048576.0))
            extra = []
            if "worker_ns/op" in acc:
                extra.append("worker %.1f ns" % acc["worker_ns/op"])
            if "phase_ns/op" in acc:
                extra.append("phase %.1f ns" % acc["phase_ns/op"])
            if "p99_ns" in acc:
                extra.append("p50 %.0f / p99 %.0f ns per %d ops" % (acc["p50_ns"], acc["p99_ns"], acc["per_ops"]))
            if "os_commits" in acc:
                extra.append("os %d/%d/%d reserve/commit/decommit" % (acc["os_reserves"], acc["os_commits"], acc["os_decommits"]))
            if "retained_idle" in acc:
                extra.append("retained %.1f / %.1f / %.1f MB idle/purged/trimmed" % (
                    acc["retained_idle"] / 1048576.0, acc["retained_purged"] / 1048576.0,
                    acc["retained_trimmed"] / 1048576.0))
            if extra:
                details.append("    %-10s %s" % (name, ", ".join(extra)))
        print("%-10s" % workload + "".join("%28s" % c for c in cells), flush=True)
        for line in details:
            print(line, flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
