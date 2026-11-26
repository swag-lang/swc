"""Prepare pinned font fixtures and compare the time to open and render one glyph."""

import argparse
from functools import partial
import hashlib
import json
import os
from pathlib import Path
import platform
import random
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
import urllib.request


MANIFEST = Path(__file__).with_name("fixtures.json")


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def check_digest(path, entry):
    observed = digest(path)
    if entry.get("sha256", observed) != observed:
        raise ValueError(f"{path}: unexpected SHA-256 {observed}")
    return observed


def prepare(args, entries):
    from fontTools.ttLib import TTFont

    args.corpus.mkdir(parents=True, exist_ok=True)
    for entry in entries:
        path = args.corpus / entry["file"]
        if "source" in entry:
            continue
        if path.exists():
            check_digest(path, entry)
            continue
        if "url" in entry:
            with tempfile.TemporaryDirectory(dir=args.corpus) as temporary:
                staged = Path(temporary) / path.name
                with urllib.request.urlopen(entry["url"], timeout=60) as response, staged.open("wb") as output:
                    shutil.copyfileobj(response, output)
                check_digest(staged, entry)
                staged.replace(path)
        elif args.attachments:
            source = args.attachments / path.name
            check_digest(source, entry)
            if source.resolve() != path.resolve():
                shutil.copyfile(source, path)

    for entry in entries:
        if "source" in entry:
            source = args.corpus / entry["source"]
            with TTFont(source, recalcTimestamp=False) as font:
                font.flavor = "woff"
                font.save(args.corpus / entry["file"])


def measure_swag(executable, path, face, character, size, count, from_memory):
    command = [str(executable), str(path), str(face), str(character), str(size), str(count)]
    if from_memory:
        command.append("memory")
    output = subprocess.check_output(command, text=True).strip()
    if output == "rejected":
        return None
    elapsed_open, elapsed_render, *glyph = map(int, output.split())
    if len(glyph) != 5 or not (glyph[0] and glyph[2] and glyph[3]):
        raise ValueError(f"{path} face {face}: invalid Swag glyph result")
    return elapsed_open, elapsed_render, glyph


def measure_pillow(load, path, face, character, size, count):
    character = chr(character)
    elapsed_open = elapsed_render = 0
    for sample in range(5 + count):
        start = time.perf_counter_ns()
        font = load(path, size, index=face)
        opened = time.perf_counter_ns()
        mask = font.getmask(character, mode="L")
        rendered = time.perf_counter_ns()
        if sample >= 5:
            elapsed_open += opened - start
            elapsed_render += rendered - opened
        if sample + 1 == 5 + count and not mask.getbbox():
            raise ValueError(f"{path} face {face}: empty Pillow glyph mask")
        del mask, font
    return elapsed_open // count, elapsed_render // count


def compare(args, entries):
    if args.cpu is not None:
        os.sched_setaffinity(0, {args.cpu})
    os.environ["SWAG_RUNTIME_THREADS"] = "1"
    engines = {"baseline": args.baseline.resolve(), "candidate": args.candidate.resolve()}
    metadata = {"source": "memory"}
    load_pillow = None
    if not args.collection_memory:
        from PIL import ImageFont, __version__, features

        load_pillow = partial(ImageFont.truetype, layout_engine=ImageFont.Layout.BASIC)
        engines["pillow"] = None
        metadata = {"pillow": __version__, "freetype": features.version("freetype2"), "pillow_layout": "basic"}

    cases = []
    for entry in entries:
        path = (args.corpus / entry["file"]).resolve()
        if args.collection_memory and path.suffix != ".ttc":
            continue
        if not path.exists() and not ("url" in entry or "source" in entry):
            continue
        sha256 = check_digest(path, entry)
        for case in entry["cases"]:
            cases.append({**case, "file": path.name, "face": case.get("face", 0),
                          "bytes": path.stat().st_size, "sha256": sha256, "batches": {}})
    if not cases:
        raise ValueError("no font fixtures were found")

    random_order = random.Random(73)
    for batch in range(args.batches):
        order = list(cases)
        random_order.shuffle(order)
        for case in order:
            path = (args.corpus / case["file"]).resolve()
            count = args.large_samples if case["bytes"] >= 10_000_000 else args.samples
            params = (path, case["face"], case["character"], args.size, count)
            order_engines = list(engines)
            random_order.shuffle(order_engines)
            for engine in order_engines:
                if engine in case["batches"] and case["batches"][engine] is None:
                    continue
                executable = engines[engine]
                if executable is None:
                    opened, rendered = measure_pillow(load_pillow, *params)
                else:
                    result = measure_swag(executable, *params, from_memory=args.collection_memory)
                    if result is None:
                        expected = engine == "baseline" and case["file"] in args.allow_baseline_rejection
                        if not expected or engine in case["batches"]:
                            raise ValueError(f"{case['file']} face {case['face']}: {engine} rejected the font")
                        case["batches"][engine] = None
                        continue
                    opened, rendered, glyph = result
                    if glyph != case.setdefault("swag_glyph", glyph):
                        raise ValueError(f"{case['file']} face {case['face']}: Swag output changed")
                case["batches"].setdefault(engine, []).append([opened, rendered])
        print(f"completed batch {batch + 1}/{args.batches}", file=sys.stderr)

    result = {
        "platform": platform.platform(), "cpu": args.cpu, "pixel_size": args.size,
        "small_batch_size": args.samples, "large_batch_size": args.large_samples,
        **metadata, "cases": cases,
    }
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    for case in cases:
        totals = []
        for engine in engines:
            samples = case["batches"][engine]
            totals.append(f"{statistics.median(sum(sample) for sample in samples) / 1000:9.2f}" if samples else " rejected")
        print(f"{case['file']:31} {case['face']:2} U+{case['character']:04X} "
              + " ".join(totals))


def positive_count(value):
    result = int(value)
    if not 0 < result <= 100_000:
        raise argparse.ArgumentTypeError("expected a positive count up to 100000")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(required=True)
    fetch = commands.add_parser("prepare")
    fetch.add_argument("--corpus", type=Path, required=True)
    fetch.add_argument("--attachments", type=Path)
    fetch.set_defaults(action=prepare)
    run = commands.add_parser("compare")
    for arg in ("corpus", "baseline", "candidate", "output"):
        run.add_argument(f"--{arg}", type=Path, required=True)
    run.add_argument("--cpu", type=int)
    run.add_argument("--collection-memory", action="store_true",
                     help="compare Swag builds on file collections already in memory")
    run.add_argument("--allow-baseline-rejection", action="append", default=[], metavar="FILENAME")
    run.add_argument("--batches", type=positive_count, default=11)
    run.add_argument("--samples", type=positive_count, default=251)
    run.add_argument("--large-samples", type=positive_count, default=15)
    run.add_argument("--size", type=positive_count, default=20)
    run.set_defaults(action=compare)
    args = parser.parse_args()
    args.action(args, json.loads(MANIFEST.read_text(encoding="utf-8")))


if __name__ == "__main__":
    main()
