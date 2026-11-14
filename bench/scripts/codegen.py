"""Preserve and verify static code-generation references, independently of timing history.

    python bench/scripts/codegen.py verify bench/disassembly/<snapshot> --check-sources
    python bench/scripts/codegen.py show bench/disassembly/<snapshot> --task sha256

Collectors call export_entry after compiling and checking a program. The archive contains
compressed complete listings, their provenance and source fingerprints, never compiler
installations or executables. A checksum proves the collected program produced the expected
result; it does not turn instruction counts into a runtime performance measurement.
"""

import argparse
import gzip
import hashlib
import json
from pathlib import Path
import re
import zlib


SCHEMA = 1
COMPONENT = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.+-]*\Z")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def source_fingerprints(root, paths):
    root = Path(root).resolve()
    result = {}
    for path in paths:
        source = Path(path).resolve()
        result[source.relative_to(root).as_posix()] = digest(source.read_bytes())
    return result


def export_entry(output, compiler, task, metadata, assembly, sources, micro=None):
    """Export one validated capture. An existing reference is never overwritten."""
    if not COMPONENT.fullmatch(compiler) or not COMPONENT.fullmatch(task):
        raise ValueError("compiler and task must be single path components")
    if not metadata.get("checksum") or metadata["checksum"] != metadata.get("expected_checksum"):
        raise ValueError("a matching observed and expected checksum is required")
    if metadata.get("build_returncode", 0) or metadata.get("run_returncode", 0):
        raise ValueError("failed builds or executions cannot become references")
    if not assembly.strip() or not sources:
        raise ValueError("a listing and source fingerprints are required")
    if (Path(output) / "snapshot.json").exists():
        raise FileExistsError("snapshot is sealed; collect into a new folder")
    folder = Path(output) / compiler / task
    folder.mkdir(parents=True, exist_ok=False)
    artifacts = {}
    for name, text in (("assembly.txt.gz", assembly), ("micro.txt.gz", micro)):
        if text is None:
            continue
        raw = text.encode("utf-8")
        encoded = gzip.compress(raw, mtime=0)
        (folder / name).write_bytes(encoded)
        artifacts[name] = {
            "sha256": digest(encoded),
            "content_sha256": digest(raw),
            "bytes": len(encoded),
            "content_bytes": len(raw),
        }
    record = {
        "schema": SCHEMA,
        "compiler": compiler,
        "task": task,
        "sources": sources,
        "metadata": metadata,
        "artifacts": artifacts,
    }
    (folder / "manifest.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    return record


def finish_snapshot(output, metadata, supporting_files=()):
    """Seal a collection after exporting its entries; subsequent captures need a new folder."""
    output = Path(output).resolve()
    index = output / "snapshot.json"
    if index.exists():
        raise FileExistsError(index)
    entries = sorted(path.relative_to(output).as_posix() for path in output.glob("*/*/manifest.json"))
    extra = {}
    for name in supporting_files:
        path = (output / name).resolve()
        if not path.is_relative_to(output):
            raise ValueError("supporting file escapes snapshot")
        extra[name] = digest(path.read_bytes())
    snapshot = metadata | {
        "schema": SCHEMA,
        "entries": entries,
        "manifest_sha256": {name: digest((output / name).read_bytes()) for name in entries},
        "supporting_files": extra,
    }
    index.write_text(json.dumps(snapshot, indent=2) + "\n", encoding="utf-8")
    _, errors = verify(output)
    if errors:
        raise ValueError("; ".join(errors))
    return snapshot


def verify(output, source_root=None):
    """Check archive integrity and, optionally, whether current inputs still match."""
    output = Path(output).resolve()
    snapshot = json.loads((output / "snapshot.json").read_text(encoding="utf-8"))
    if snapshot.get("schema") != SCHEMA:
        raise ValueError("unsupported code-generation snapshot schema")
    errors = []
    entries = snapshot.get("entries", [])
    if not entries or len(entries) != len(set(entries)):
        errors.append("the snapshot must name a nonempty set of distinct entries")
    found = {path.relative_to(output).as_posix() for path in output.glob("*/*/manifest.json")}
    if found != set(entries):
        errors.append("snapshot inventory does not match its entry manifests")
    for name, expected in snapshot.get("supporting_files", {}).items():
        path = (output / name).resolve()
        try:
            if not path.is_relative_to(output) or digest(path.read_bytes()) != expected:
                errors.append(f"supporting file changed: {name}")
        except OSError as error:
            errors.append(f"{name}: {error}")
    for entry in entries:
        manifest = (output / entry).resolve()
        if not manifest.is_relative_to(output):
            errors.append(f"entry escapes snapshot: {entry}")
            continue
        try:
            raw_manifest = manifest.read_bytes()
            expected_manifest = snapshot.get("manifest_sha256", {}).get(entry)
            if expected_manifest is not None and digest(raw_manifest) != expected_manifest:
                raise ValueError("manifest changed")
            record = json.loads(raw_manifest.decode("utf-8"))
            if record.get("schema") != SCHEMA:
                raise ValueError("unsupported entry schema")
            meta = record["metadata"]
            if not meta.get("checksum") or meta["checksum"] != meta.get("expected_checksum"):
                raise ValueError("checksum validation is missing or mismatched")
            if meta.get("build_returncode", 0) or meta.get("run_returncode", 0):
                raise ValueError("build or execution failed")
            if "assembly.txt.gz" not in record["artifacts"] or not record["sources"]:
                raise ValueError("listing or source fingerprints are missing")
            for name, expected in record["artifacts"].items():
                path = (manifest.parent / name).resolve()
                if path.parent != manifest.parent:
                    raise ValueError("artifact escapes entry")
                data = path.read_bytes()
                if digest(data) != expected["sha256"] or len(data) != expected["bytes"]:
                    raise ValueError(f"artifact changed: {name}")
                raw = gzip.decompress(data)
                if digest(raw) != expected["content_sha256"] or len(raw) != expected["content_bytes"]:
                    raise ValueError(f"listing content changed: {name}")
            if source_root is not None:
                root = Path(source_root).resolve()
                for name, expected in record["sources"].items():
                    path = (root / name).resolve()
                    if not path.is_relative_to(root) or digest(path.read_bytes()) != expected:
                        raise ValueError(f"source no longer matches: {name}")
        except (KeyError, OSError, ValueError, gzip.BadGzipFile, zlib.error) as error:
            errors.append(f"{entry}: {error}")
    return entries, errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("verify", "show"))
    parser.add_argument("snapshot", type=Path)
    parser.add_argument("--task")
    parser.add_argument("--compiler")
    parser.add_argument("--micro", action="store_true", help="show Swag Micro instead of assembly")
    parser.add_argument("--check-sources", action="store_true", help="also reject stale source fingerprints")
    parser.add_argument("--source-root", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    entries, errors = verify(args.snapshot, args.source_root if args.check_sources else None)
    if errors:
        for error in errors:
            print(error)
        return 1
    if args.action == "verify":
        print(f"Verified {len(entries)} code-generation references; no runtime performance claim.")
        return 0
    matches = []
    for entry in entries:
        path = args.snapshot / entry
        record = json.loads(path.read_text(encoding="utf-8"))
        if args.task and record["task"] != args.task:
            continue
        if args.compiler and record["compiler"] != args.compiler:
            continue
        matches.append((path, record))
    if len(matches) != 1:
        for _, record in matches:
            print(record["compiler"], record["task"], record["metadata"].get("compiler_version", ""))
        return 0 if matches else 1
    path, record = matches[0]
    name = "micro.txt.gz" if args.micro else "assembly.txt.gz"
    if name not in record["artifacts"]:
        parser.error(f"{name} is not available for this reference")
    print(gzip.decompress((path.parent / name).read_bytes()).decode("utf-8"), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
