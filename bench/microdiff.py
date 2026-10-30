"""Compare the final code two compilers generate for every benchmark task.

    py -3 microdiff.py --base PATH [--new PATH] [--only IDS] [--cfg release] [--show FUNC]

This does not update benchmark history. It answers the question a generated-code change
has to answer before any timing: which functions and loops of which tasks did it change, and
in which direction. Each task is rebuilt once by each compiler from the same task sources, with
`--print-micro "*"` (the pre-emit Micro listing),
and run once to compare checksums.

With --verbose, every function whose listing differs has instruction, memory-operand and call
counts of the whole function and of each loop that changed (a loop is a jump back to an
earlier label, innermost loops included). A loop that got longer or reads memory more often
is marked LOSS. Task functions come first; runtime functions follow, because an allocation-
or dispatch-heavy task runs them in its hot path.

It cannot establish execution counts, placement, or runtime performance. Weigh each loop by
its trip count and inspect changed dependencies and register use even when counts are equal.
Identical listings alone do not explain a timing change.
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
HEX = re.compile(r"0x[0-9A-Fa-f]+")
CHECK = re.compile(r"CHECK=(\d+)")


def build(swc, task, cfg, cores, work):
    """Build one task, return its listing and checksum."""
    wd = os.path.join(work, task)
    shutil.rmtree(wd, ignore_errors=True)
    os.makedirs(wd)
    temp = os.path.join(wd, "temp")
    os.makedirs(temp)
    env = os.environ | {"TEMP": temp, "TMP": temp}
    cmd = [swc, "build", "--num-cores", str(cores), "--build-cfg", cfg, "-n", task,
           "-od", wd, "-wd", wd, "--rebuild", "--print-micro", "*"]
    for dependency in tc.swag_dependency_api_files(cfg):
        cmd += ["--import-api-file", dependency]
    for f in tc.swag_files(task, "swagnat"):
        cmd += ["-f", f]
    r = subprocess.run(cmd, cwd=wd, env=env, capture_output=True, text=True, encoding="utf-8", errors="replace")
    listing = ANSI.sub("", r.stdout + r.stderr)
    Path(wd, "micro.txt").write_text(listing, encoding="utf-8")
    if r.returncode != 0:
        raise SystemExit("%s: build failed with %s\n%s" % (task, swc, listing[-1500:]))
    functions = parse(listing)
    if not any(name.startswith(task.capitalize() + ".__main_") and body for name, body in functions.items()):
        raise SystemExit("%s: %s produced no task main listing" % (task, swc))
    run = subprocess.run([os.path.join(wd, task + ".exe")], cwd=wd, env=env,
                         capture_output=True, text=True, timeout=40)
    check = CHECK.search(run.stdout)
    if run.returncode != 0 or not check:
        raise SystemExit("%s: %s exited with %d, checksum %s\n%s" %
                         (task, swc, run.returncode, check.group(1) if check else "missing",
                          (run.stdout + run.stderr)[-1500:]))
    return listing, check.group(1)


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
            current.append({"ref": int(m.group(2)), "op": m.group(3), "operands": m.group(4),
                            "natural": m.group(5) or ""})
    return functions


def normalized(instructions):
    labels = {i["ref"]: "L%d" % n for n, i in enumerate(instructions) if not i["op"]}
    out = []
    for i in instructions:
        operands = i["operands"]
        # Only pointer operands carry process addresses; arithmetic constants and frame
        # offsets are part of the generated work, regardless of their magnitude.
        if i["op"] in ("load_reg_ptr_reloc", "load_reg_ptr_imm"):
            operands = HEX.sub("0xADDR", operands)
        if i["op"] in ("call_local", "call_extern") and i.get("natural", "").startswith("call ") and i["natural"] != "call <reloc>":
            # The operand is a process-local relocation address. The resolved
            # callee below retains target identity across independent captures.
            operands = re.sub(r"<0x[0-9A-Fa-f]+>", "<0xADDR>", operands)
        text = i["op"] + " " + operands
        if i["op"].startswith("jump"):
            text = re.sub(r"\d+$", lambda m: labels.get(int(m[0]), "unresolved:" + m[0]), text)
        if i["op"] in ("call_local", "call_extern"):
            text += " | " + i.get("natural", "")
        out.append(text)
    return out


def counts(instructions):
    real = [i for i in instructions if i["op"]]
    # Older compilers printed only "7 operand(s)" for indexed extensions.
    indexed_extensions = ("load_signed_ext_amc_reg_mem", "load_zero_ext_amc_reg_mem")
    memory = sum(1 for i in real if not i["op"].startswith("load_addr") and
                 ("[" in i["operands"] or i["op"] in indexed_extensions))
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
    """Rows for changed functions, and the number of equal-count changes omitted."""
    fb, fn = parse(base), parse(new)
    owner = task.capitalize() + "."
    rows = []
    quiet = 0
    for name in sorted(set(fb) | set(fn), key=lambda n: (not n.startswith(owner), n)):
        a, b = fb.get(name), fn.get(name)
        if a is None or b is None:
            rows.append("  %-46s %s (%s)" % (name, "added" if a is None else "removed",
                                             fmt(counts(b if a is None else a))))
            continue
        if normalized(a) == normalized(b):
            continue
        ca, cb = counts(a), counts(b)
        la, lb = loops(a), loops(b)
        # Equal counts can still hide different dependencies, branches or register use.
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
    ap.add_argument("--save-dir", help="keep both listings and build outputs in this new directory")
    ap.add_argument("--verbose", action="store_true",
                    help="also list changed functions whose counts did not move")
    args = ap.parse_args()
    args.base, args.new = os.path.abspath(args.base), os.path.abspath(args.new)

    tasks = [t for t in args.only.split(",") if t] or tc.TASKS
    unknown = sorted(set(tasks) - set(tc.TASKS))
    if unknown:
        ap.error("unknown task(s): " + ", ".join(unknown))
    local = os.environ.get("LOCALAPPDATA") or os.path.join(os.path.expanduser("~"), "AppData", "Local")
    parent = Path(local) / "swc-bench-builds"
    parent.mkdir(parents=True, exist_ok=True)

    mismatch = False
    with tempfile.TemporaryDirectory(prefix="microdiff-", dir=parent) as temporary:
        work = temporary
        if args.save_dir:
            work = os.path.abspath(args.save_dir)
            Path(work).mkdir(parents=True, exist_ok=False)
        for task in tasks:
            base, base_check = build(args.base, task, args.cfg, args.cores, os.path.join(work, "base"))
            new, new_check = build(args.new, task, args.cfg, args.cores, os.path.join(work, "new"))
            for role, listing in (("base", base), ("new", new)):
                incomplete = sum(1 for body in parse(listing).values() for i in body
                                 if re.fullmatch(r"\d+ operand\(s\)", i["operands"]))
                if incomplete:
                    print("== %s: %s has %d instruction(s) with unprinted operands; inspect emitted code for those" %
                          (task, role, incomplete))
            if base_check != new_check:
                mismatch = True
            if args.show:
                fb, fn = parse(base), parse(new)
                if args.show not in fb and args.show not in fn:
                    raise SystemExit("%s: neither listing contains %s" % (task, args.show))
                a = normalized(fb.get(args.show, []))
                b = normalized(fn.get(args.show, []))
                print("== %s %s" % (task, args.show))
                for line in difflib.unified_diff(a, b, "base", "new", lineterm="", n=2):
                    print(line)
                continue
            rows, quiet = compare(task, base, new, args.verbose)
            status = "checksum %s" % new_check if base_check == new_check else \
                "CHECKSUM MISMATCH base %s new %s" % (base_check, new_check)
            changed = sum(1 for r in rows if not r.startswith("      "))
            print("== %s: %s, %d changed/added/removed function(s), %d changed with equal counts (use --verbose)" %
                  (task, status, changed, quiet))
            for row in rows:
                print(row)
            sys.stdout.flush()
    return 1 if mismatch else 0


if __name__ == "__main__":
    sys.exit(main())
