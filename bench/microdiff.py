"""Compare the final code two compilers generate for every benchmark task.

    py -3 microdiff.py --base PATH [--new PATH] [--only IDS] [--cfg release] [--show FUNC]

This is not a campaign and records nothing. It answers the question a generated-code change
has to answer before any timing: which functions and loops of which tasks did it change, and
in which direction. Each task is built once by each compiler from the same sources, with
`--print-micro "*"` (the pre-emit Micro listing, one instruction per machine instruction),
and run once to compare checksums.

For every function whose listing differs, it prints the instruction, memory-operand and call
counts of the whole function and of each loop that changed (a loop is a jump back to an
earlier label, innermost loops included). A loop that got longer or reads memory more often
is marked LOSS. Task functions come first; runtime functions follow, because an allocation-
or dispatch-heavy task runs them in its hot path.

Two things it cannot see, on purpose: execution counts (weigh each loop by its trip count
yourself) and placement. A task whose listings are identical but whose time moved is reading
where its code landed, not what the compiler generated.
"""
import argparse
import difflib
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import toolchains as tc

LINE = re.compile(r"^(\d{3,}) (\d{3,})\s+(\S*)\s*(.*?)\s*(?:\|\s*(.*))?$")
ANSI = re.compile(r"\x1b\[[0-9;]*m")
WIDE_HEX = re.compile(r"0x[0-9A-Fa-f]{5,}")
CHECK = re.compile(r"CHECK=(\d+)")


def build(swc, task, cfg, cores, work):
    """Build one task, return its listing and checksum."""
    wd = os.path.join(work, task)
    shutil.rmtree(wd, ignore_errors=True)
    os.makedirs(wd)
    cmd = [swc, "build", "--num-cores", str(cores), "--build-cfg", cfg, "-n", task,
           "-od", wd, "-wd", wd, "--print-micro", "*"]
    for dependency in tc.swag_dependency_api_files(cfg):
        cmd += ["--import-api-file", dependency]
    for f in tc.swag_files(task, "swagnat"):
        cmd += ["-f", f]
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    listing = ANSI.sub("", r.stdout + r.stderr)
    if r.returncode != 0:
        raise SystemExit("%s: build failed with %s\n%s" % (task, swc, listing[-1500:]))
    run = subprocess.run([os.path.join(wd, task + ".exe")], capture_output=True, text=True)
    check = CHECK.search(run.stdout)
    return listing, check.group(1) if check else "exit %d" % run.returncode


def parse(listing):
    """function name -> list of instructions, labels included (op == "")."""
    functions, current = {}, None
    for raw in listing.splitlines():
        if raw.startswith("  function : "):
            name = base = raw.split(":", 1)[1].strip()
            suffix = 2
            while name in functions:
                name = "%s#%d" % (base, suffix)
                suffix += 1
            current = functions[name] = []
            continue
        m = LINE.match(raw) if current is not None else None
        if m:
            current.append({"ref": int(m.group(2)), "op": m.group(3), "operands": m.group(4)})
    return functions


def normalized(instructions):
    out = []
    for i in instructions:
        text = i["op"] + " " + WIDE_HEX.sub("0xADDR", i["operands"])
        if i["op"].startswith("jump"):
            text = re.sub(r"\d+$", "L", text)
        out.append(text)
    return out


def counts(instructions):
    real = [i for i in instructions if i["op"]]
    memory = sum(1 for i in real if "[" in i["operands"] and not i["op"].startswith("load_addr"))
    calls = sum(1 for i in real if i["op"].startswith("call"))
    return len(real), memory, calls


def loops(instructions):
    labels = {i["ref"]: n for n, i in enumerate(instructions) if not i["op"]}
    found = []
    for n, i in enumerate(instructions):
        target = re.search(r"(\d+)\s*$", i["operands"]) if i["op"].startswith("jump") else None
        if target and int(target.group(1)) in labels and labels[int(target.group(1))] <= n:
            found.append(counts(instructions[labels[int(target.group(1))]:n + 1]))
    return found


def fmt(c):
    return "%d instr / %d mem / %d calls" % c if c else "-"


def compare(task, base, new, verbose):
    """Rows for the changed functions, and how many changed without moving any count."""
    fb, fn = parse(base), parse(new)
    owner = task.capitalize() + "."
    rows = []
    quiet = 0
    for name in sorted(set(fb) | set(fn), key=lambda n: (not n.startswith(owner), n)):
        a, b = fb.get(name), fn.get(name)
        if a is None or b is None:
            if verbose:
                rows.append("  %-46s %s" % (name, "added" if a is None else "removed"))
            else:
                quiet += 1
            continue
        if normalized(a) == normalized(b):
            continue
        ca, cb = counts(a), counts(b)
        la, lb = loops(a), loops(b)
        # Renamed registers, reordered instructions or a renumbered lambda: the same work, listed differently.
        if ca == cb and la == lb and not verbose:
            quiet += 1
            continue
        detail = []
        for k in range(max(len(la), len(lb))):
            x = la[k] if k < len(la) else None
            y = lb[k] if k < len(lb) else None
            if x == y:
                continue
            loss = x and y and (y[0] > x[0] or y[1] > x[1] or y[2] > x[2])
            detail.append("      loop %d: %s -> %s%s" % (k, fmt(x), fmt(y), "   LOSS" if loss else ""))
        loss = cb[0] > ca[0] or cb[1] > ca[1] or cb[2] > ca[2]
        rows.append("  %-46s %s -> %s%s" % (name, fmt(ca), fmt(cb), "   LOSS" if loss else ""))
        rows.extend(detail)
    return rows, quiet


def main():
    ap = argparse.ArgumentParser(description="Compare the final code of every bench task between two compilers")
    ap.add_argument("--base", required=True, help="the reference swc.exe")
    ap.add_argument("--new", default=os.path.join(tc.worktree(), "bin", "swc.exe"), help="the compiler under test")
    ap.add_argument("--only", default="", help="comma-separated task ids")
    ap.add_argument("--cfg", default="release", help="program configuration, as the campaign builds it")
    ap.add_argument("--cores", type=int, default=6, help="compiler workers")
    ap.add_argument("--show", default="", help="print the listing diff of this function")
    ap.add_argument("--verbose", action="store_true",
                    help="also list functions whose counts did not move, and added or removed ones")
    args = ap.parse_args()

    tasks = [t for t in args.only.split(",") if t] or tc.TASKS
    local = os.environ.get("LOCALAPPDATA") or os.path.join(os.path.expanduser("~"), "AppData", "Local")
    parent = Path(local) / "swc-bench-builds"
    parent.mkdir(parents=True, exist_ok=True)

    mismatch = False
    with tempfile.TemporaryDirectory(prefix="microdiff-", dir=parent) as work:
        for task in tasks:
            base, base_check = build(args.base, task, args.cfg, args.cores, os.path.join(work, "base"))
            new, new_check = build(args.new, task, args.cfg, args.cores, os.path.join(work, "new"))
            if base_check != new_check:
                mismatch = True
            if args.show:
                a = normalized(parse(base).get(args.show, []))
                b = normalized(parse(new).get(args.show, []))
                print("== %s %s" % (task, args.show))
                for line in difflib.unified_diff(a, b, "base", "new", lineterm="", n=2):
                    print(line)
                continue
            rows, quiet = compare(task, base, new, args.verbose)
            status = "checksum %s" % new_check if base_check == new_check else \
                "CHECKSUM MISMATCH base %s new %s" % (base_check, new_check)
            changed = sum(1 for r in rows if not r.startswith("      "))
            print("== %s: %s, %d function(s) with different counts, %d only listed differently" %
                  (task, status, changed, quiet))
            for row in rows:
                print(row)
            sys.stdout.flush()
    return 1 if mismatch else 0


if __name__ == "__main__":
    sys.exit(main())
