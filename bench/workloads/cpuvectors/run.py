import argparse
import json
from pathlib import Path
import statistics
import subprocess


def measure(program, case, cpu):
    command = ["taskset", "-c", str(cpu), str(program), case, "1"]
    frequency, recorded, drawn, coverage = map(int, subprocess.check_output(command, text=True).split())
    return {
        "record_ms": recorded * 1000 / frequency,
        "draw_ms": drawn * 1000 / frequency,
        "total_ms": (recorded + drawn) * 1000 / frequency,
        "coverage": coverage,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--swag", type=Path, required=True)
    parser.add_argument("--agg", type=Path, required=True)
    parser.add_argument("--cpu", type=int, required=True)
    parser.add_argument("--batches", type=int, default=13)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.batches < 1:
        parser.error("--batches must be positive")

    report = {"cpu": args.cpu, "batches": args.batches, "cases": {}}
    for case in ("fills", "strokes"):
        programs = {"swag-scanlines": (args.swag, case), "agg": (args.agg, case)}
        if case == "fills":
            programs["swag-triangles"] = (args.swag, "fills-triangles")
        samples = {name: [] for name in programs}
        for batch in range(args.batches):
            order = list(programs) if batch % 2 == 0 else reversed(programs)
            for name in order:
                executable, scenario = programs[name]
                samples[name].append(measure(executable, scenario, args.cpu))

        medians = {}
        for name, values in samples.items():
            if len({sample["coverage"] for sample in values}) != 1:
                raise RuntimeError(f"{name} coverage varies in {case}")
            medians[name] = {key: statistics.median(sample[key] for sample in values) for key in values[0]}
        report["cases"][case] = {"medians": medians, "samples": samples}

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
