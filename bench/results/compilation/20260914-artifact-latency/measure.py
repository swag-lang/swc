"""Alternate two compilers, including process startup and exit.

Preserved compilers must have their runtime and standard-module resources configured.
Every measured or preparation command passes the shared-machine admission check.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import statistics
import subprocess
import sys
import tempfile
import time

ROOT = next(p for p in Path(__file__).resolve().parents if (p / "swc.sln").is_file())
sys.path.insert(0, str(ROOT / "bench"))
import winproc


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", required=True, type=Path)
    parser.add_argument("--candidate", required=True, type=Path)
    parser.add_argument("--rounds", type=int, default=5)
    parser.add_argument("--tasks", nargs="+", default=["hello", "lex_std", "core_rebuild", "core_noop", "core_touch"],
                        choices=["hello", "lex_std", "core_rebuild", "core_noop", "core_touch"])
    parser.add_argument("--max-cpu", type=int, default=20)
    parser.add_argument("--pin", action="store_true", help="confine both binaries to the same performance cores")
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if args.rounds < 1 or not 1 <= args.max_cpu <= 65:
        parser.error("rounds must be positive and max-cpu must be in 1..65")
    if args.pin and not winproc.PIN_MASK:
        parser.error("performance-core topology could not be determined")
    binaries = {tag: getattr(args, tag).resolve() for tag in ("baseline", "candidate")}
    for binary in binaries.values():
        if not binary.is_file():
            parser.error("both compiler paths must exist")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    scratch = tempfile.TemporaryDirectory(prefix="swc-artifact-latency-")
    output = Path(scratch.name).resolve()
    if output.is_relative_to(ROOT):
        parser.error("the system temporary directory must be outside the checkout")
    data = {"rounds": args.rounds, "cores": 6, "max_cpu": args.max_cpu,
            "affinity": "performance cores" if args.pin else "unrestricted",
            "pin_mask": winproc.PIN_MASK if args.pin else 0,
            "samples": [], "preparations": [], "admissions": [],
            "binaries": {tag: {"path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
                         for tag, path in binaries.items()}}

    def save():
        args.output.write_text(json.dumps(data, indent=2), encoding="utf-8")

    def run(command, task, tag, round_index, preparation=False):
        while True:
            admission = subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                                        str(ROOT / ".agents/skills/modify-swag-codebase/scripts/check-machine-load.ps1"),
                                        "-MaxCpuPercent", str(args.max_cpu)], capture_output=True, text=True)
            data["admissions"].append({"time": time.strftime("%Y-%m-%d %H:%M:%S"),
                                       "exit": admission.returncode, "stdout": admission.stdout, "stderr": admission.stderr})
            save()
            if admission.returncode == 0:
                break
            if admission.returncode != 2:
                raise RuntimeError(admission.stdout + admission.stderr)
            print("Waiting for machine headroom", flush=True)
            time.sleep(10)
        before = winproc._system_times()
        result = winproc.run(command, cwd=str(output), env=dict(os.environ), pin=args.pin)
        after = winproc._system_times()
        if before and after and after[1] > before[1]:
            total = after[1] - before[1]
            result["background_cpu_pct"] = max(0, 100 * (total - (after[0] - before[0]) - result["cpu_ms"]) / total)
        result.update(task=task, tag=tag, round=round_index, command=command)
        data["preparations" if preparation else "samples"].append(result)
        save()
        if result["exit"]:
            raise RuntimeError(result["stdout"] + result["stderr"])
        if not preparation:
            print(f"{round_index + 1} {tag} {task}: {result['wall_ms']:.1f} ms wall, "
                  f"{result['cpu_ms']:.1f} ms CPU, {result['peak_working_set_bytes'] / 1048576:.1f} MiB resident", flush=True)
        return result

    touched = ROOT / "bin/std/modules/core/src/text/utf8.swg"
    for round_index in range(args.rounds):
        for task in args.tasks:
            for tag in (list(binaries) if round_index % 2 == 0 else list(reversed(binaries))):
                compiler = str(binaries[tag])
                common = ["--num-cores", "6", "--log-ascii"]
                if task == "hello":
                    folder = output / tag
                    folder.mkdir(exist_ok=True)
                    command = [compiler, "build", *common, "-bc", "devmode", "--rebuild", "-n", "hello",
                               "-od", str(folder), "-wd", str(folder), "-f", str(ROOT / "bench/src/hello/hello.swg")]
                elif task == "lex_std":
                    command = [compiler, "test", *common, "--lex-only", "-d", str(ROOT / "bin/std/modules")]
                else:
                    command = [compiler, "build", *common, "-bc", "devmode", "-w", str(ROOT / "bin/std"), "-m", "core"]
                    if task == "core_rebuild":
                        command += ["--rebuild"]
                    else:
                        # Versions invalidate manifests: prepare with the binary about to be timed.
                        run(command, task, tag, round_index, preparation=True)
                        if task == "core_touch":
                            os.utime(touched, None)
                result = run(command, task, tag, round_index)
                core_reused = any("up-to-date" in line and re.search(r"\bcore\b", line)
                                  for line in result["stdout"].splitlines())
                if task == "core_noop" and not core_reused:
                    raise RuntimeError("no-op workload rebuilt core")
                if task == "core_touch" and core_reused:
                    raise RuntimeError("touched source did not rebuild core")
                if task == "hello" and not (folder / "hello.exe").is_file():
                    raise RuntimeError("hello artifact was not produced")

    data["summary"] = {}
    for task in args.tasks:
        samples = {tag: [s for s in data["samples"] if s["tag"] == tag and s["task"] == task] for tag in binaries}
        metrics = ["wall_ms", "cpu_ms", "peak_working_set_bytes", "peak_job_bytes"]
        summary = {tag: {key: statistics.median(s[key] for s in group) for key in metrics} for tag, group in samples.items()}
        summary["paired_candidate_over_baseline"] = {
            key: statistics.median(b[key] / a[key] for a, b in zip(samples["baseline"], samples["candidate"]) if a[key])
            for key in metrics}
        data["summary"][task] = summary
    save()
    print(json.dumps(data["summary"], indent=2))


if __name__ == "__main__":
    main()
