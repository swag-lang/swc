"""Replay Swag KDF profiles against OpenSSL and a second native reference."""

import argparse
import ctypes
import importlib.util
import json
import os
from pathlib import Path
import random
import re
import ssl
import subprocess
import sys
import time

WORKLOADS = Path(__file__).resolve().parents[1]


def import_runner(workload):
    source = WORKLOADS / workload / "run.py"
    spec = importlib.util.spec_from_file_location(f"{workload}_runner", source)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def native_profile(library, workload, profile):
    byte_pair = (ctypes.c_char_p, ctypes.c_size_t)
    common = (*byte_pair, *byte_pair)
    output = (ctypes.c_void_p, ctypes.c_size_t)
    if workload == "scrypt":
        cost, block = profile
        password = b"parallel benchmark"
        salt = b"benchmark salt!!"
        key = (ctypes.c_uint8 * 32)()
        function = library.kdf_scrypt
        function.argtypes = (*common, ctypes.c_uint64, ctypes.c_uint32, ctypes.c_uint32, *output)
        parameters = (password, len(password), salt, len(salt), cost, block, 1, key, len(key))
    else:
        algorithm, iterations, password_size, salt_size, key_size = profile
        password = bytes((i * 31 + 17) & 255 for i in range(password_size))
        salt = bytes((i * 47 + 29) & 255 for i in range(salt_size))
        key = (ctypes.c_uint8 * key_size)()
        function = library.kdf_pbkdf2
        function.argtypes = (ctypes.c_char_p, *common, ctypes.c_uint, *output)
        parameters = (algorithm.encode(), password, len(password), salt, len(salt),
                      iterations, key, len(key))
    function.restype = ctypes.c_int

    def measure():
        if function(*parameters):
            raise ValueError(f"native reference failed for {profile}")
        expected = bytes(key)
        wall_start = time.perf_counter_ns()
        cpu_start = time.process_time_ns()
        status = function(*parameters)
        cpu = (time.process_time_ns() - cpu_start) // 1000
        wall = (time.perf_counter_ns() - wall_start) // 1000
        actual = bytes(key)
        if status or actual != expected:
            raise ValueError(f"native reference produced inconsistent keys for {profile}")
        return wall, cpu, actual

    return measure


def measure_native_openssl(binary, workload, profile):
    arguments = [binary, workload, *map(str, profile)]
    stdout = subprocess.check_output(arguments, text=True, timeout=30)
    match = re.fullmatch(r"([1-9]\d*) ([1-9]\d*) ([0-9a-f]+)\n?", stdout)
    key_size = 32 if workload == "scrypt" else profile[-1]
    if match is None or len(match[3]) != 2 * key_size:
        raise ValueError(f"unexpected result from {binary}: {stdout!r}")
    return int(match[1]), int(match[2]), bytes.fromhex(match[3])


def compare(runner, library, native_openssl, workload, profile, baseline, candidate, rounds, rng):
    def run_swag(binary):
        if workload == "scrypt":
            return runner.run_swag(binary, *profile)
        return runner.run_swag(binary, profile)

    def run_openssl():
        if workload == "scrypt":
            return runner.run_openssl(*profile)
        return runner.run_openssl(profile)

    library_name = "libsodium" if workload == "scrypt" else "Nettle"
    operations = {"baseline": lambda: run_swag(baseline), "candidate": lambda: run_swag(candidate),
                  "OpenSSL": run_openssl, library_name: native_profile(library, workload, profile)}
    operations.update({
        name: lambda path=path: measure_native_openssl(path, workload, profile)
        for name, path in native_openssl.items()
    })
    clocks = {clock: {name: [] for name in operations} for clock in runner.CLOCKS}
    order = list(operations)
    expected = None
    for _ in range(rounds):
        rng.shuffle(order)
        for name in order:
            wall, cpu, tag = operations[name]()
            if expected is None:
                expected = tag
            elif expected != tag:
                raise ValueError(f"{name} disagrees for {profile}")
            clocks["wall_us"][name].append(wall)
            clocks["cpu_us"][name].append(cpu)
    estimates = {
        clock: {
            "median": {name: runner.stats.estimate(timing).as_dict() for name, timing in rows.items()},
            "candidate_ratio": {
                name: runner.stats.paired_ratio(rows["candidate"], timing).as_dict()
                for name, timing in rows.items() if name != "candidate"
            },
        }
        for clock, rows in clocks.items()
    }
    return {"profile": profile, "tag": expected.hex(), "samples_us": clocks, "estimates": estimates}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("workload", choices=("scrypt", "pbkdf2"))
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--openssl-native", action="append", type=Path, default=[],
                        help="include a standalone native OpenSSL reference, repeat to compare versions")
    parser.add_argument("--cpu", type=int, required=True)
    parser.add_argument("--rounds", type=int, default=15)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.cpu not in os.sched_getaffinity(0):
        parser.error("--cpu needs a CPU in the process affinity")
    if args.rounds < 7:
        parser.error("--rounds needs at least seven paired samples")
    baseline, candidate = args.baseline.resolve(), args.candidate.resolve()
    for binary in (baseline, candidate):
        if not os.access(binary, os.X_OK):
            parser.error(f"missing executable {binary}")

    runner = import_runner(args.workload)
    os.sched_setaffinity(0, {args.cpu})
    library = ctypes.CDLL(args.reference.resolve())
    if library.sodium_init() < 0:
        raise ValueError("libsodium initialization failed")
    references = {"OpenSSL": ssl.OPENSSL_VERSION}
    if args.workload == "scrypt":
        library.sodium_version_string.restype = ctypes.c_char_p
        references["libsodium"] = library.sodium_version_string().decode()
    else:
        references["Nettle"] = f"{library.nettle_version_major()}.{library.nettle_version_minor()}"

    native_openssl = {}
    for path in args.openssl_native:
        executable = path.resolve()
        if not os.access(executable, os.X_OK):
            parser.error(f"missing executable {executable}")
        version = subprocess.check_output([executable, "--version"], text=True, timeout=30).strip()
        components = version.split()
        if len(components) < 2 or components[0] != "OpenSSL":
            parser.error(f"invalid OpenSSL version from {executable}")
        name = " ".join(components[:2])
        if name in native_openssl:
            parser.error(f"duplicate native OpenSSL version {name}")
        native_openssl[name] = executable
        references[name] = version

    rng = random.Random(0)
    rows = []
    for profile in runner.PROFILES:
        row = compare(runner, library, native_openssl, args.workload, profile,
                      baseline, candidate, args.rounds, rng)
        rows.append(row)
        cpu = row["estimates"]["cpu_us"]["median"]
        print(profile, {name: round(value["value"], 1) for name, value in cpu.items()}, flush=True)
    result = {"workload": args.workload, "cpu": args.cpu, "rounds": args.rounds,
              "references": references, "profiles": rows}
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")

if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        sys.exit(str(error))
