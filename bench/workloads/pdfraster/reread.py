import argparse
import json
import os
from pathlib import Path
import statistics
import subprocess


def measure(executable, path, copies, cpu):
    command = ["taskset", "-c", str(cpu), str(executable), str(path), str(copies), "1"]
    with subprocess.Popen(command, stdout=subprocess.PIPE, text=True) as process:
        output = process.stdout.read()
        _, status, usage = os.wait4(process.pid, 0)
        process.returncode = os.waitstatus_to_exitcode(status)
        if process.returncode:
            raise subprocess.CalledProcessError(process.returncode, command)

    frequency, ticks, count = map(int, output.split())
    if count != copies:
        raise RuntimeError(f"{executable} retained {count} pages, expected {copies}")
    return {"ns": round(ticks * 1_000_000_000 / frequency), "peak_rss_kib": usage.ru_maxrss}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--file", type=Path, required=True)
    parser.add_argument("--cpu", type=int, required=True)
    parser.add_argument("--copies", type=int, default=16)
    parser.add_argument("--batches", type=int, default=9)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.copies < 1 or args.batches < 1:
        parser.error("--copies and --batches must be positive")

    programs = {"baseline": args.baseline, "candidate": args.candidate}
    samples = {name: [] for name in programs}
    for batch in range(args.batches):
        order = list(programs) if batch % 2 == 0 else reversed(programs)
        for name in order:
            samples[name].append(measure(programs[name], args.file, args.copies, args.cpu))

    report = {"file": args.file.name, "cpu": args.cpu, "copies": args.copies, "measurements": {}}
    for name, series in samples.items():
        report["measurements"][name] = {
            "median_ms": statistics.median(sample["ns"] for sample in series) / 1_000_000,
            "peak_rss_kib": max(sample["peak_rss_kib"] for sample in series),
            "samples": series,
        }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
