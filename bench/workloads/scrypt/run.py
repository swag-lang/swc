"""Compare two native Swag scrypt builds and Python's OpenSSL scrypt on Linux."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import re
import ssl
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
import stats

PROFILES = [(1024, 1), (16384, 8), (65536, 8)]
CLOCKS = ("wall_us", "cpu_us")


def run_swag(binary, cost, block):
    stdout = subprocess.run(
        [binary, str(cost), str(block)], cwd=binary.parent, check=True,
        text=True, capture_output=True, timeout=30,
    ).stdout
    result = re.fullmatch(r"([1-9]\d*) ([1-9]\d*) ([0-9a-f]{64})\n?", stdout)
    if result is None:
        raise ValueError(f"Unexpected result from {binary}: {stdout!r}")
    return int(result[1]), int(result[2]), bytes.fromhex(result[3])


def run_openssl(cost, block):
    args = dict(salt=b"benchmark salt!!", n=cost, r=block, p=1, dklen=32, maxmem=1024 ** 3)
    password = b"parallel benchmark"
    warmup = hashlib.scrypt(password, **args)
    wall = time.perf_counter_ns()
    cpu = time.process_time_ns()
    output = hashlib.scrypt(password, **args)
    cpu_us = (time.process_time_ns() - cpu) // 1000
    wall_us = (time.perf_counter_ns() - wall) // 1000
    if output != warmup:
        raise ValueError("OpenSSL produced different outputs for the warm-up and measured calls")
    return wall_us, cpu_us, output


def compare(baseline, candidate, cost, block, rounds, rng):
    runners = {
        "baseline": lambda: run_swag(baseline, cost, block),
        "candidate": lambda: run_swag(candidate, cost, block),
        "openssl": lambda: run_openssl(cost, block),
    }
    samples = {clock: {name: [] for name in runners} for clock in CLOCKS}
    order = list(runners)
    expected = None
    for _ in range(rounds):
        rng.shuffle(order)
        for name in order:
            wall, cpu, tag = runners[name]()
            if expected is None:
                expected = tag
            elif tag != expected:
                raise ValueError(f"{name} produced a different tag for N={cost}, r={block}")
            samples["wall_us"][name].append(wall)
            samples["cpu_us"][name].append(cpu)

    estimates = {}
    for clock, values in samples.items():
        estimates[clock] = {
            "median": {name: stats.estimate(times).as_dict() for name, times in values.items()},
            "candidate_ratio": {
                name: stats.paired_ratio(values["candidate"], times).as_dict()
                for name, times in values.items() if name != "candidate"
            },
        }
    return {
        "n": cost, "r": block, "p": 1, "tag": expected.hex(),
        "samples_us": samples, "estimates": estimates,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", required=True, type=Path)
    parser.add_argument("--candidate", required=True, type=Path)
    parser.add_argument("--cpu", required=True, type=int)
    parser.add_argument("--rounds", type=int, default=9)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if args.rounds < 7:
        parser.error("--rounds needs at least seven paired samples")
    if args.cpu not in os.sched_getaffinity(0):
        parser.error("--cpu needs a CPU in the process affinity")
    args.baseline, args.candidate = args.baseline.resolve(), args.candidate.resolve()
    for binary in (args.baseline, args.candidate):
        if not os.access(binary, os.X_OK):
            parser.error(f"missing executable {binary}")
    os.sched_setaffinity(0, {args.cpu})

    rng = random.Random(0)
    profiles = []
    for cost, block in PROFILES:
        profile = compare(args.baseline, args.candidate, cost, block, args.rounds, rng)
        profiles.append(profile)
        estimates = profile["estimates"]["cpu_us"]["median"]
        timings = " ".join(f"{name}={result['value'] / 1000:.3f} ms"
                           for name, result in estimates.items())
        print(f"N={cost}, r={block}  {timings} process CPU", flush=True)

    args.output.write_text(json.dumps({
        "cpu": args.cpu, "rounds": args.rounds, "reference": ssl.OPENSSL_VERSION,
        "profiles": profiles,
    }, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        sys.exit(str(error))
