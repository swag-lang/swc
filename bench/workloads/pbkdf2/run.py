"""Compare PBKDF2-HMAC on native Swag and OpenSSL through Python on Linux."""

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

# Algorithm, iterations, password bytes, salt bytes, derived bytes.
PROFILES = [
    ("sha224", 20_000, 8, 16, 80),
    ("sha256", 100_000, 8, 16, 32),
    ("sha256", 25_000, 200, 150, 96),
    ("sha384", 20_000, 200, 150, 100),
    ("sha512", 20_000, 8, 16, 64),
]
CLOCKS = ("wall_us", "cpu_us")


def run_swag(binary, profile):
    stdout = subprocess.run(
        [binary, *map(str, profile)], cwd=binary.parent, check=True,
        text=True, capture_output=True, timeout=30,
    ).stdout
    result = re.fullmatch(r"([1-9]\d*) ([1-9]\d*) ([0-9a-f]+)\n?", stdout)
    if result is None or len(result[3]) != 2 * profile[-1]:
        raise ValueError(f"Unexpected result from {binary}: {stdout!r}")
    return int(result[1]), int(result[2]), bytes.fromhex(result[3])


def run_openssl(profile):
    algorithm, iterations, password_size, salt_size, output_size = profile
    password = bytes((i * 31 + 17) & 255 for i in range(password_size))
    salt = bytes((i * 47 + 29) & 255 for i in range(salt_size))
    args = (algorithm, password, salt, iterations, output_size)
    warmup = hashlib.pbkdf2_hmac(*args)
    wall = time.perf_counter_ns()
    cpu = time.process_time_ns()
    output = hashlib.pbkdf2_hmac(*args)
    cpu_us = (time.process_time_ns() - cpu) // 1000
    wall_us = (time.perf_counter_ns() - wall) // 1000
    if output != warmup:
        raise ValueError("OpenSSL produced different outputs for the warm-up and measured calls")
    return wall_us, cpu_us, output


def compare(baseline, candidate, profile, rounds, rng):
    runners = {
        "baseline": lambda: run_swag(baseline, profile),
        "candidate": lambda: run_swag(candidate, profile),
        "openssl": lambda: run_openssl(profile),
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
                raise ValueError(f"{name} produced a different tag for {profile}")
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
        "parameters": profile, "derived_key": expected.hex(),
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
    for profile in PROFILES:
        result = compare(args.baseline, args.candidate, profile, args.rounds, rng)
        profiles.append(result)
        estimates = result["estimates"]["cpu_us"]["median"]
        timings = " ".join(f"{name}={result['value'] / 1000:.3f} ms"
                           for name, result in estimates.items())
        print(f"{profile}  {timings} process CPU", flush=True)

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
