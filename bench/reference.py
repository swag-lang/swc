"""Freeze, verify or show the reference compiler every campaign measures Swag against.

    py -3 bench/reference.py show
    py -3 bench/reference.py verify
    py -3 bench/reference.py freeze NAME [--swc PATH] [--force]

Freezing copies the compiler, its runtime, its standard library sources and the Swag
task sources into the reference store (BENCH_REFERENCE_ROOT, by default
%LOCALAPPDATA%\\SwagBench\\references\\NAME) and records their digests in
bench/reference.json, which is committed. A reference is never overwritten: a new one
gets a new name, and the progress history starts a new series with it.
"""
import argparse
import json
import sys

import installs


def main(argv=None):
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="command", required=True)
    sub.add_parser("show")
    sub.add_parser("verify")
    freeze = sub.add_parser("freeze")
    freeze.add_argument("name")
    freeze.add_argument("--swc", help="compiler to freeze (default: bin/swc.exe of this checkout)")
    freeze.add_argument("--force", action="store_true", help="freeze even if sources are modified")
    args = ap.parse_args(argv)

    if args.command == "freeze":
        manifest = installs.freeze_reference(args.name, args.swc, args.force)
        print("reference %s frozen from commit %s at %s" % (manifest["name"], manifest["commit"],
                                                           installs.reference_store()))
        print("commit bench/reference.json to make it the reference of every campaign")
        return 0
    reference, why = installs.load_reference(verify=args.command == "verify")
    if reference is None:
        print(why)
        return 1
    print(json.dumps(reference.meta, indent=2))
    print("location: %s" % reference.root)
    if args.command == "verify":
        print("verified: every frozen file matches its manifest")
    return 0


if __name__ == "__main__":
    sys.exit(main())
