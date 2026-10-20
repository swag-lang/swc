r"""Exercise machine-code archives across compiler processes and changed inputs.

    py -3 bench/cachecheck.py --scratch C:\path\outside-checkout [--dm]

Every compiler invocation has independent load admission and at most six workers.
Fixtures, native outputs, private caches and logs stay in the supplied scratch root.
"""
import argparse
import concurrent.futures
from contextlib import contextmanager, ExitStack
import ctypes
from ctypes import wintypes
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import time

from parsecache import ROOT, admit


@contextmanager
def pinned_archives(paths):
    """Retain old generations with the same sharing flags as compiler readers."""
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, ctypes.c_void_p, wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE]
    kernel.CreateFileW.restype = wintypes.HANDLE
    kernel.CreateFileMappingW.argtypes = [wintypes.HANDLE, ctypes.c_void_p, wintypes.DWORD, wintypes.DWORD, wintypes.DWORD, wintypes.LPCWSTR]
    kernel.CreateFileMappingW.restype = wintypes.HANDLE
    kernel.MapViewOfFile.argtypes = [wintypes.HANDLE, wintypes.DWORD, wintypes.DWORD, wintypes.DWORD, ctypes.c_size_t]
    kernel.MapViewOfFile.restype = ctypes.c_void_p
    kernel.UnmapViewOfFile.argtypes = [ctypes.c_void_p]
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    snapshots = []
    with ExitStack() as handles:
        for path in paths:
            original = path.read_bytes()
            file = kernel.CreateFileW(str(path), 0x80000000, 7, None, 3, 0x80, None)
            if file == ctypes.c_void_p(-1).value:
                raise ctypes.WinError(ctypes.get_last_error())
            handles.callback(kernel.CloseHandle, file)
            mapping = kernel.CreateFileMappingW(file, None, 2, 0, 0, None)
            if not mapping:
                raise ctypes.WinError(ctypes.get_last_error())
            handles.callback(kernel.CloseHandle, mapping)
            view = kernel.MapViewOfFile(mapping, 4, 0, 0, 0)
            if not view:
                raise ctypes.WinError(ctypes.get_last_error())
            handles.callback(kernel.UnmapViewOfFile, view)
            snapshots.append((view, original))
        yield
        for view, original in snapshots:
            assert ctypes.string_at(view, len(original)) == original


API = """#global export
#global namespace CacheApi

#[Swag.NoInline]
public func(T) advance(value: T)->T
{
    var result = value
    for 32
    {
        result = (result + 1) % 97
    }
    return result
}

#[Swag.NoInline]
public func(T) label(value: T)->string
{
    if value == 10 do
        return "cached"
    return "other"
}
"""

SOURCE = """const COMPILETIME = #run CacheApi.advance(cast(s32, 10))
#assert(COMPILETIME == EXPECTED)

var padding: [PADDING] u64
var input = 10

#main
{
    input += cast(s32, padding[0])
    Swag.print(CacheApi.advance(input))
    Swag.print(" ")
    Swag.print(CacheApi.label(input))
    Swag.print("\\n")
}
"""

EFFECT_API = """
#[Swag.NoInline]
public func(T) observe(value: *T, counter: *T)->T
{
    counter[] += 1
    let before = value[]
    touch(value)
    return value[] - before
}

#[Swag.NoInline]
public func(T) touch(value: *T)
{
    EFFECT
}
"""

EFFECT_SOURCE = """func evaluate()->s32
{
    var value = 0
    var counter = 0
    return CacheApi.observe(&value, &counter)
}

const COMPILETIME = #run evaluate()
#assert(COMPILETIME == EXPECTED)

#main
{
    Swag.print(evaluate())
    Swag.print("\\n")
}
"""


def archives(cache):
    result = {}
    for path in cache.glob("*.bin"):
        data = path.read_bytes()
        if len(data) < 16 or data[:8] != b"SWMCSET2":
            continue
        entries = {}
        cursor = 16
        count = struct.unpack_from("<I", data, 8)[0]
        body_cursor = 16 + count * 68
        for _ in range(count):
            key = data[cursor:cursor + 64].decode("ascii")
            length = struct.unpack_from("<I", data, cursor + 64)[0]
            cursor += 68
            entries[key] = (body_cursor, length)
            body_cursor += length
        assert body_cursor == len(data), path
        result[path] = (data, entries)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scratch", required=True, type=Path)
    parser.add_argument("--dm", action="store_true")
    parser.add_argument("--rebuild-only", action="store_true")
    args = parser.parse_args()
    scratch = args.scratch.resolve()
    if scratch.is_relative_to(ROOT):
        parser.error("Use a scratch directory outside the checkout")
    run = scratch / time.strftime("cachecheck-%Y%m%d-%H%M%S")
    run.mkdir(parents=True)
    temp = run / "temp"
    temp.mkdir()
    env = dict(os.environ, TEMP=str(temp), TMP=str(temp))
    compiler = ROOT / ("bin/swc.dm.exe" if args.dm else "bin/swc.exe")
    api = run / "api.swg"
    api.write_text(API, encoding="utf-8")
    source = run / "consumer.swg"
    source.write_text(SOURCE.replace("EXPECTED", "42").replace("PADDING", "7"), encoding="utf-8")
    cache = temp / "swag/machine"
    checks = []

    def invoke(label, expected="42 cached", rebuild=False, stats=False, config="devmode", cores=6, admission=True):
        if admission:
            admit()
        output = run / label
        command = [str(compiler), "run", "-f", str(source), "--import-api-file", str(api),
                   "--num-cores", str(cores), "-bc", config, "-n", "consumer",
                   "-od", str(output), "-wd", str(output)]
        if rebuild:
            command.append("--rebuild")
        if stats:
            command.append("--optimizer-stats")
        process = subprocess.run(command, cwd=str(run), env=env, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=60)
        result = {"exit": process.returncode, "stdout": process.stdout, "stderr": process.stderr}
        text = result["stdout"] + result["stderr"]
        (run / (label + ".log")).write_text(text, encoding="utf-8")
        if expected is None:
            assert result["exit"] != 0 and "missingValue" in text and "api.swg" in text, text
        else:
            assert result["exit"] == 0 and re.search(r"(?:^|[\r\n])" + re.escape(expected) + r"\s", text), text
        print(label, "passed", flush=True)
        return result

    invoke("cold")
    assert archives(cache)
    warm = invoke("warm")
    assert "reused function" in warm["stdout"], warm["stdout"]
    checks.append("cold and warm native/JIT calls return the same values")
    checks.append("ordinary compiler commands reuse archives without a cache option")

    # An unused, syntactically valid record detects full archive replacement.
    sentinel = "f" * 64
    for directory in [cache]:
        for path, (data, index) in archives(directory).items():
            assert sentinel not in index
            offset, length = next(iter(index.values()))
            index_end = 16 + len(index) * 68
            seeded = bytearray(data[:index_end] + sentinel.encode("ascii") + struct.pack("<I", length) + data[index_end:] + data[offset:offset + length])
            struct.pack_into("<I", seeded, 8, len(index) + 1)
            path.write_bytes(seeded)
    with pinned_archives(archives(cache)):
        rebuilt = invoke("rebuild", rebuild=True)
    assert "reused function" not in rebuilt["stdout"]
    for directory in [cache]:
        for _, index in archives(directory).values():
            assert sentinel not in index
    after_rebuild = invoke("after-rebuild")
    assert "reused function" in after_rebuild["stdout"]
    checks.append("--rebuild bypasses existing entries and replaces the machine archive")
    checks.append("rebuild preserves old mapped readers while publishing fresh generations")

    with pinned_archives(archives(cache)):
        invoke("rebuild-stats", rebuild=True, stats=True)
        assert not archives(cache)
    invoke("after-stats")
    checks.append("--rebuild invalidates old machine records even when statistics bypass publication")

    if args.rebuild_only:
        (run / "verification.json").write_text(json.dumps({"compiler": str(compiler), "selection": "forced rebuild with mapped readers", "checks": checks}, indent=2), encoding="utf-8")
        print("Results:", run / "verification.json", flush=True)
        return

    source.write_text(SOURCE.replace("EXPECTED", "42").replace("PADDING", "113"), encoding="utf-8")
    invoke("layout")
    checks.append("a new consumer layout keeps current globals and constant pointers")
    api.write_text(API.replace("for 32", "for 33").replace('"cached"', '"changed"'), encoding="utf-8")
    source.write_text(SOURCE.replace("EXPECTED", "43").replace("PADDING", "113"), encoding="utf-8")
    invoke("api-change", expected="43 changed")
    checks.append("changed generic API body and literal invalidate generated code")
    api.write_text(API, encoding="utf-8")
    source.write_text(SOURCE.replace("EXPECTED", "42").replace("PADDING", "7"), encoding="utf-8")
    invoke("restore")

    for directory in [cache]:
        entries = archives(directory)
        if not entries:
            continue
        target = next(iter(entries))
        data, index = entries[target]
        damaged = bytearray(data)
        for offset, length in index.values():
            damaged[offset + length - 1] ^= 0x80
        target.write_bytes(damaged)
        invoke("corrupt-" + directory.name)
        assert target.read_bytes() != damaged
        target.write_bytes(target.read_bytes()[:20])
        invoke("truncated-" + directory.name)
        assert archives(directory)
    checks.append("damaged bodies and truncated archives fall back and repair the machine archive")

    api.write_text(API.replace("return result", "return missingValue"), encoding="utf-8")
    invoke("diagnostic", expected=None)
    checks.append("source errors retain the imported source location")
    api.write_text(API, encoding="utf-8")
    invoke("release", config="release")
    invoke("release-warm", config="release")
    checks.append("program configuration changes preserve native and JIT behavior")

    api.write_text(API + EFFECT_API.replace("EFFECT", "discard value[]"), encoding="utf-8")
    source.write_text(EFFECT_SOURCE.replace("EXPECTED", "0"), encoding="utf-8")
    invoke("readonly", expected="0")
    invoke("readonly-warm", expected="0")
    api.write_text(API + EFFECT_API.replace("EFFECT", "value[] += 1"), encoding="utf-8")
    source.write_text(EFFECT_SOURCE.replace("EXPECTED", "1"), encoding="utf-8")
    invoke("callee-effect", expected="1")
    checks.append("a callee that starts writing invalidates cached caller optimizations")
    api.write_text(API, encoding="utf-8")
    source.write_text(SOURCE.replace("EXPECTED", "42").replace("PADDING", "7"), encoding="utf-8")

    stamp = compiler.stat()
    try:
        before = set(archives(cache))
        os.utime(compiler, ns=(stamp.st_atime_ns, stamp.st_mtime_ns + 2_000_000_000))
        invoke("compiler-change")
        assert set(archives(cache)) - before
        checks.append("compiler identity changes use another archive")
    finally:
        os.utime(compiler, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))

    # The two publishers share a six-worker budget and one admitted test scenario.
    for directory in [cache]:
        for path in directory.glob("*.bin"):
            assert path.resolve().parent == directory.resolve()
            path.unlink()
    admit()
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        futures = [pool.submit(invoke, "publisher-" + str(i), cores=3, admission=False) for i in range(2)]
        for future in futures:
            future.result()
    invoke("after-publication")
    checks.append("concurrent publication leaves a readable merged archive")
    (run / "verification.json").write_text(json.dumps({"compiler": str(compiler), "checks": checks}, indent=2), encoding="utf-8")
    print("Results:", run / "verification.json", flush=True)


if __name__ == "__main__":
    main()
