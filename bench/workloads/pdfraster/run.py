"""Fetch pinned PDFs and compare Swag's CPU bitmap path with PDFium."""

import argparse
import ctypes
import hashlib
import json
import math
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
import zlib


MANIFEST = Path(__file__).with_name("fixtures.json")
STAGES = ("open", "load", "render")


def check_digest(path, entry):
    with path.open("rb") as stream:
        observed = hashlib.file_digest(stream, "sha256").hexdigest()
    if observed != entry["sha256"]:
        raise ValueError(f"{path}: unexpected SHA-256 {observed}")


def prepare(args, entries):
    args.corpus.mkdir(parents=True, exist_ok=True)
    for entry in entries:
        path = args.corpus / entry["file"]
        if path.exists():
            check_digest(path, entry)
            continue
        if "url" not in entry and args.filesamples is None:
            continue

        with tempfile.TemporaryDirectory(dir=args.corpus) as temporary:
            staged = Path(temporary) / path.name
            if "url" in entry:
                with urllib.request.urlopen(entry["url"], timeout=60) as response, staged.open("wb") as output:
                    shutil.copyfileobj(response, output)
            else:
                shutil.copyfile(args.filesamples / path.name, staged)
            check_digest(staged, entry)
            staged.replace(path)


def get_swag_samples(executable, path, page_index, side, samples):
    try:
        program = subprocess.run([executable, path, str(page_index), str(side), str(samples)],
                                 capture_output=True, text=True, timeout=180)
    except subprocess.TimeoutExpired:
        return {"error": "Swag worker exceeded 180 s"}
    if program.returncode:
        return {"error": f"Swag exited with {program.returncode}",
                "diagnostic": (program.stderr or program.stdout).strip()}

    output = []
    for line in program.stdout.splitlines():
        fields = line.split()
        if not fields:
            continue
        if fields[0] == "error":
            if output:
                raise RuntimeError(f"{path.name}: Swag failed after producing samples")
            return {"error": line.removeprefix("error ")}
        tag, *numbers = fields
        frequency, opened, loaded, rendered, width, height, crc, ink, text, paths, images = map(int, numbers)
        if tag != "ok" or not frequency or not (0 < width <= side + 1 and 0 < height <= side + 1):
            raise ValueError(f"{path.name}: unexpected Swag measurement {line}")
        times = [tick * 1_000_000_000 // frequency for tick in (opened, loaded, rendered)]
        output.append((times, {"width": width, "height": height, "crc32": crc, "ink_samples": ink,
                               "objects": {"text": text, "path": paths, "image": images}}))
    if len(output) != samples:
        raise ValueError(f"{path.name}: expected {samples} Swag samples, got {len(output)}")
    return validate_samples(output, path, "Swag")


def get_pdfium_samples(pdf, path, page_index, side, samples):
    encoded_path = os.fsencode(path)
    output = []
    for iteration in range(samples + 1):
        begin = time.perf_counter_ns()
        document = pdf.FPDF_LoadDocument(encoded_path, None)
        if not document:
            return {"error": f"open PDFium error {pdf.FPDF_GetLastError()}"}
        page = bitmap = None
        try:
            opened = time.perf_counter_ns()
            page = pdf.FPDF_LoadPage(document, page_index)
            if not page:
                return {"error": f"load PDFium error {pdf.FPDF_GetLastError()}"}
            loaded = time.perf_counter_ns()

            page_width = pdf.FPDF_GetPageWidthF(page)
            page_height = pdf.FPDF_GetPageHeightF(page)
            if min(page_width, page_height) <= 0 or not all(map(math.isfinite, (page_width, page_height))):
                return {"error": "render invalid page dimensions"}
            scale = ctypes.c_float(side / max(page_width, page_height)).value
            width = max(1, math.ceil(ctypes.c_float(page_width * scale).value))
            height = max(1, math.ceil(ctypes.c_float(page_height * scale).value))
            bitmap = pdf.FPDFBitmap_CreateEx(width, height, pdf.FPDFBitmap_BGRA, None, 0)
            if not bitmap:
                return {"error": "render could not allocate PDFium bitmap"}
            if not pdf.FPDFBitmap_FillRect(bitmap, 0, 0, width, height, 0xffffffff):
                return {"error": "render could not clear PDFium bitmap"}
            pdf.FPDF_RenderPageBitmap(bitmap, page, 0, 0, width, height, 0, 0)
            rendered = time.perf_counter_ns()

            if iteration:
                if pdf.FPDFBitmap_GetStride(bitmap) != width * 4:
                    raise ValueError(f"{path.name}: unexpected PDFium stride")
                pixels = ctypes.string_at(pdf.FPDFBitmap_GetBuffer(bitmap), width * height * 4)
                ink = 0
                for y in range(32):
                    row = (y * height // 32) * width * 4
                    for x in range(32):
                        pixel = row + (x * width // 32) * 4
                        ink += pixels[pixel:pixel + 3] != b"\xff\xff\xff"

                object_names = {pdf.FPDF_PAGEOBJ_TEXT: "text", pdf.FPDF_PAGEOBJ_PATH: "path",
                                pdf.FPDF_PAGEOBJ_IMAGE: "image", pdf.FPDF_PAGEOBJ_FORM: "form"}
                objects = {}
                for index in range(pdf.FPDFPage_CountObjects(page)):
                    kind = pdf.FPDFPageObj_GetType(pdf.FPDFPage_GetObject(page, index))
                    name = object_names.get(kind, "other")
                    objects[name] = objects.get(name, 0) + 1
                output.append(([opened - begin, loaded - opened, rendered - loaded],
                               {"width": width, "height": height, "crc32": zlib.crc32(pixels),
                                "ink_samples": ink, "objects": objects}))
        finally:
            if bitmap:
                pdf.FPDFBitmap_Destroy(bitmap)
            if page:
                pdf.FPDF_ClosePage(page)
            pdf.FPDF_CloseDocument(document)
    return validate_samples(output, path, "PDFium")


def validate_samples(samples, path, engine):
    first = samples[0][1]
    if any(image != first for _, image in samples):
        raise ValueError(f"{path.name}: {engine} changed output within a batch")
    return {"image": first, "samples_ns": [value for value, _ in samples]}


def compare(args, entries):
    import pypdfium2 as pdfium2

    if args.cpu is not None:
        os.sched_setaffinity(0, {args.cpu})
    engines = {"swag": args.candidate.resolve(), "pdfium": None}
    if args.baseline:
        engines["baseline"] = args.baseline.resolve()
    for executable in engines.values():
        if executable is not None and not executable.is_file():
            raise ValueError(f"missing Swag executable: {executable}")

    if args.file:
        unknown = set(args.file) - {entry["file"] for entry in entries}
        if unknown:
            raise ValueError(f"unknown PDF fixtures: {', '.join(sorted(unknown))}")

    cases = []
    for entry in entries:
        if args.file and entry["file"] not in args.file:
            continue
        path = (args.corpus / entry["file"]).resolve()
        if not path.exists() and "url" not in entry:
            continue
        check_digest(path, entry)
        for page in entry["pages"]:
            cases.append({**entry, "page": page, "results": {}})
    if not cases:
        raise ValueError("no PDF fixtures were found")

    random_order = random.Random(73)
    for batch in range(args.batches):
        order = list(cases)
        random_order.shuffle(order)
        for case in order:
            path = (args.corpus / case["file"]).resolve()
            order_engines = list(engines)
            random_order.shuffle(order_engines)
            for engine in order_engines:
                if "error" in case["results"].get(engine, {}):
                    continue
                executable = engines[engine]
                params = (path, case["page"] - 1, args.side, args.samples)
                measured = (get_swag_samples(executable, *params) if executable is not None
                            else get_pdfium_samples(pdfium2.raw, *params))
                previous = case["results"].get(engine)
                if previous is None:
                    case["results"][engine] = measured
                elif "error" in measured:
                    raise ValueError(f"{path.name}: {engine} rejected a page after successful measurement")
                elif previous["image"] != measured["image"]:
                    raise ValueError(f"{path.name}: {engine} changed output between batches")
                else:
                    previous["samples_ns"].extend(measured["samples_ns"])
        print(f"Completed batch {batch + 1}/{args.batches}", file=sys.stderr, flush=True)

    for case in cases:
        case.pop("pages")
        for result in case["results"].values():
            if "samples_ns" not in result:
                continue
            times = result["samples_ns"]
            result["median_ms"] = {stage: statistics.median(values) / 1_000_000
                                   for stage, values in zip(STAGES, zip(*times))}
            result["median_ms"]["total"] = statistics.median(map(sum, times)) / 1_000_000
        images = [result["image"] for result in case["results"].values() if "image" in result]
        case["same_dimensions"] = len(images) == len(engines) and len({
            (image["width"], image["height"]) for image in images}) == 1
        print(case["file"], f"p{case['page']}", " / ".join(
            f"{engine} {result['median_ms']['total']:.3f} ms" if "median_ms" in result
            else f"{engine} {result['error']}" for engine, result in case["results"].items()),
              "" if case["same_dimensions"] else "(no matched comparison)")

    affinity = sorted(os.sched_getaffinity(0)) if hasattr(os, "sched_getaffinity") else None
    result = {"platform": platform.platform(), "cpu_affinity": affinity, "side": args.side,
              "pdfium": str(pdfium2.PDFIUM_INFO), "pypdfium2": str(pdfium2.PYPDFIUM_INFO),
              "batches": args.batches, "samples_per_batch": args.samples, "cases": cases}
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")


def positive_count(value):
    result = int(value)
    if not 1 <= result <= 8191:
        raise argparse.ArgumentTypeError("expected an integer in 1..8191")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(required=True)
    fetch = commands.add_parser("prepare")
    fetch.add_argument("--corpus", type=Path, required=True)
    fetch.add_argument("--filesamples", type=Path)
    fetch.set_defaults(action=prepare)
    run = commands.add_parser("compare")
    for arg in ("corpus", "candidate", "output"):
        run.add_argument(f"--{arg}", type=Path, required=True)
    run.add_argument("--baseline", type=Path)
    run.add_argument("--cpu", type=int)
    run.add_argument("--file", action="append", help="compare only this manifest filename")
    run.add_argument("--side", type=positive_count, default=1200)
    run.add_argument("--batches", type=positive_count, default=7)
    run.add_argument("--samples", type=positive_count, default=2)
    run.set_defaults(action=compare)
    args = parser.parse_args()
    args.action(args, json.loads(MANIFEST.read_text(encoding="utf-8")))


if __name__ == "__main__":
    main()
