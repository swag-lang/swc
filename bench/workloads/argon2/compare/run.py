"""Compare native Swag Argon2id with libargon2 and OpenSSL on Linux."""

import argparse
import json
import os
from pathlib import Path
import random
import re
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "scripts"))
import stats


def run_trial(command, memory, workers):
    result = subprocess.run(
        [*command, str(memory), str(workers)], cwd=command[0].parent,
        text=True, capture_output=True, timeout=60, check=True,
    )
    output = re.fullmatch(r"([1-9]\d*) ([1-9]\d*) ([0-9a-f]{64})\n?", result.stdout)
    if output is None:
        raise ValueError(f"Unexpected benchmark result from {command}: {result.stdout!r}")
    return int(output[1]), int(output[2]), output[3]


def compare(commands, memory, workers, rounds, rng):
    records = {clock: {name: [] for name in commands} for clock in ("wall_us", "cpu_us")}
    expected = None
    order = list(commands)
    for _ in range(rounds):
        rng.shuffle(order)
        for name in order:
            wall, cpu, tag = run_trial(commands[name], memory, workers)
            if expected is None:
                expected = tag
            elif tag != expected:
                raise ValueError(f"{name} gave a different tag at {memory} KiB with {workers} workers")
            records["wall_us"][name].append(wall)
            records["cpu_us"][name].append(cpu)

    estimates = {}
    for clock, samples in records.items():
        estimates[clock] = {
            "median": {name: stats.estimate(times).as_dict() for name, times in samples.items()},
            "candidate_ratio": {
                name: stats.paired_ratio(samples["candidate"], times).as_dict()
                for name, times in samples.items() if name != "candidate"
            },
        }
    return {
        "memory_kib": memory, "workers": workers, "tag": expected,
        "samples_us": records, "estimates": estimates,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--cpus", type=int, nargs=4, required=True)
    parser.add_argument("--rounds", type=int, default=9)
    parser.add_argument("--memory", type=int, nargs="+", default=[1024, 65536, 262144])
    parser.add_argument("--workers", type=int, choices=[1, 4], nargs="+", default=[1, 4])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    allowed = os.sched_getaffinity(0)
    if len(set(args.cpus)) != 4 or not set(args.cpus) <= allowed:
        parser.error("--cpus needs four distinct CPUs in the process affinity")
    if args.rounds < 7 or any(memory < 32 for memory in args.memory):
        parser.error("the campaign needs seven rounds and at least 32 KiB per profile")
    args.reference = args.reference.resolve()
    commands = {
        "baseline": [args.baseline.resolve()],
        "candidate": [args.candidate.resolve()],
        "libargon2": [args.reference, "libargon2"],
        "openssl": [args.reference, "openssl"],
    }
    for command in commands.values():
        if not os.access(command[0], os.X_OK):
            parser.error(f"missing executable {command[0]}")

    rng = random.Random(0)
    results = []
    for workers in args.workers:
        os.sched_setaffinity(0, args.cpus[:workers])
        for memory in args.memory:
            result = compare(commands, memory, workers, args.rounds, rng)
            results.append(result)
            timings = " ".join(f"{key}={val['value'] / 1000:.3f} ms"
                               for key, val in result["estimates"]["wall_us"]["median"].items())
            print(f"{memory} KiB, {workers} workers  {timings}", flush=True)

    args.output.write_text(json.dumps({
        "cpus": args.cpus, "rounds": args.rounds, "profiles": results,
    }, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        sys.exit(str(error))
