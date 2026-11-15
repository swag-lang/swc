"""Archive validated Windows benchmark code without sampling or updating timing history.

    python bench/bench.py capture --output bench/disassembly/<new-snapshot> --swc PATH

Builds and caches use BENCH_OUTPUT_ROOT. Only compressed text and provenance enter the
immutable snapshot. Diagnostic JIT and bytecode variants have their own identifiers.
"""
import argparse
import ctypes
import datetime
import gzip
import json
import os
from pathlib import Path
import platform
import re
import struct
import subprocess
import sys

import codegen
import installs
import process
import smoke
import toolchains as tc

ANSI = re.compile(r"\x1b\[[0-9;]*m")
NATIVE = [*tc.SWAG_AOT, *tc.AOT_CONTROLS]
DIAGNOSTIC = {"csharp-coreclr-fullopts": "csharp-jit", "java-hotspot-c2": "java-hotspot",
              "node-v8": "node20", "python-bytecode": "python3.12",
              "ruby-bytecode": "ruby", "luajit-bytecode": "luajit2.1",
              "lua-bytecode": "lua5.4", "php-opcodes": "php", "php-tracing-jit": "php-jit"}


def run(command, env, cwd=None):
    result = process.run([str(arg) for arg in command], cwd=cwd or tc.BENCH, env=env)
    output = ANSI.sub("", result["stdout"] + result["stderr"])
    if result["exit"]:
        raise RuntimeError("exit %s: %s\n%s" % (result["exit"], command, output[-3000:]))
    return output


def check(output, task):
    values = re.findall(r"CHECK=(-?\d+)", output)
    if not values or any(int(value) != smoke.CHECKS[task] for value in values):
        raise ValueError("checksum mismatch for " + task)
    return str(smoke.CHECKS[task])


def pe_sections(binary):
    data = Path(binary).read_bytes()
    pe = struct.unpack_from("<I", data, 0x3c)[0]
    if data[pe:pe + 4] != b"PE\0\0":
        raise ValueError("expected a PE image")
    count, optional = struct.unpack_from("<H", data, pe + 6)[0], struct.unpack_from("<H", data, pe + 20)[0]
    base = struct.unpack_from("<Q", data, pe + 24 + 24)[0]
    sections = {}
    for i in range(count):
        offset = pe + 24 + optional + i * 40
        name = data[offset:offset + 8].rstrip(b"\0").decode("ascii")
        _, rva, size, raw = struct.unpack_from("<IIII", data, offset + 8)
        sections[name] = (rva, data[raw:raw + size])
    return base, sections


def swag_symbols(binary):
    """Read the names carried by the actual non-debug executable's stack-trace table."""
    base, sections = pe_sections(binary)
    data = sections[".swagdbg"][1]
    magic, version, size, packed = struct.unpack_from("<IIII", data)
    if magic != 0x42445753:
        raise ValueError("invalid Swag symbol table")
    if version == 2:
        output = ctypes.create_string_buffer(size)
        actual = ctypes.c_ulong()
        status = ctypes.windll.ntdll.RtlDecompressBuffer(2, output, size, data[16:16 + packed], packed,
                                                       ctypes.byref(actual))
        if status or actual.value != size:
            raise ValueError("cannot decompress Swag symbol table")
        data = output.raw
    magic, version, count, strings = struct.unpack_from("<IIII", data)
    if magic != 0x42445753 or version != 1 or strings < 16 + count * 20:
        raise ValueError("invalid plain Swag symbol table")
    def text(offset):
        return data[offset:data.index(b"\0", offset)].decode("utf-8") if offset else ""
    return "\n".join("%016x %8x %s %s:%d" % (base + rva, length, text(name), text(file), line)
                     for rva, length, name, file, line in
                     (struct.unpack_from("<IIIII", data, 16 + i * 20) for i in range(count))) + "\n"


def sources(task, name):
    language = {"swag-release": "swagnat", "swag-devmode": "swagnat", "cpp-clang-cl": "cpp",
                "cpp-msvc": "cpp", "rust": "rust", "zig": "zig", "d-ldc": "d", "odin": "odin",
                "go": "go", "swift": "swift", "csharp-aot": "cs", "csharp-jit": "cs",
                "java-hotspot": "java", "node20": "js", "python3.12": "py", "ruby": "ruby",
                "lua5.4": "lua", "luajit2.1": "lua", "php": "php", "php-jit": "php"}[name]
    root = Path(tc.BENCH) / "src" / language
    paths = [path for path in root.rglob("*") if path.is_file() and
             not any(part.startswith(".") or part in ("bin", "obj", "target", "__pycache__")
                     for part in path.relative_to(root).parts[:-1]) and
             (path.stem in (task, "common", "bytemap") or task in path.parts)]
    if name.startswith("swag-"):
        paths += list((Path(tc.worktree()) / "bin/runtime").rglob("*.swg"))
        paths += list((Path(tc.worktree()) / "bin/std/modules/win32/src").rglob("*.swg"))
    return paths


def hotspot_blocks(output):
    """Keep contiguous bytes and their addresses from HotSpot's hex-only MachCode dump."""
    blocks, address, data, label = [], None, bytearray(), ""
    for line in output.splitlines():
        if line.startswith("Compiled method") or "# {method}" in line:
            if data:
                blocks.append((address, bytes(data), label))
                address, data = None, bytearray()
            label = line.strip()
        match = re.match(r"\s*0x([0-9a-fA-F]+):\s*(.*)", line)
        if not match:
            continue
        fields = match[2].split(";", 1)[0].replace("|", " ").split()
        if not fields or any(not re.fullmatch(r"[0-9a-fA-F]{2}(?:[0-9a-fA-F]{2})*", value) for value in fields):
            continue
        raw = bytes.fromhex("".join(fields))
        current = int(match[1], 16)
        if address is not None and current != address + len(data):
            blocks.append((address, bytes(data), label))
            address, data = None, bytearray()
        if address is None:
            address = current
        data.extend(raw)
    if data:
        blocks.append((address, bytes(data), label))
    return blocks


def decode_hotspot(output, objdump, env, folder):
    blocks = hotspot_blocks(output)
    if not blocks:
        # An installed hsdis can already provide mnemonics instead of raw hex blocks.
        if "Compiled method (c2)" in output and re.search(r"\b(?:mov|ret|call|jmp)\b", output):
            return output
        raise ValueError("HotSpot produced no decodable native code")
    listings = []
    for index, (address, data, label) in enumerate(blocks):
        # A minimal AMD64 COFF object holds the exact JIT bytes for LLVM's decoder.
        header = struct.pack("<HHIIIHH", 0x8664, 1, 0, 0, 0, 0, 0)
        section = struct.pack("<8sIIIIIIHHI", b".text\0\0\0", 0, 0, len(data), 60, 0, 0, 0, 0, 0x60000020)
        obj = folder / ("hotspot-%d.obj" % index)
        obj.write_bytes(header + section + data)
        listings.append("# " + label + "\n" + run([objdump, "-d", "--x86-asm-syntax=intel",
                                                  "--adjust-vma=" + str(address), obj], env))
    return "\n".join(listings)


def interpreted_capture(name, task, tools, env, objdump):
    base = DIAGNOSTIC[name]
    commands = tc.make_runtimes(tools, {}, 3)
    command, overrides = commands[base](task)
    check(run(command, env | overrides), task)
    source = Path(command[-2] if command[-1] == "--require-jit" else command[-1])
    extra, diagnostic = {}, {}
    if name == "node-v8":
        command = [tools["node"], "--print-code", "--print-opt-code", source]
        listing = run(command, env)
        check(listing, task)
        if "Instructions (size" not in listing:
            raise ValueError("V8 produced no native code")
        kind = "native-jit"
    elif name == "php-tracing-jit":
        command = command[:1] + ["-d", "opcache.jit_debug=1"] + command[1:]
        listing = run(command, env)
        check(listing, task)
        if not re.search(r"TRACE-\d+", listing):
            raise ValueError("PHP produced no native JIT traces")
        kind = "native-jit"
    else:
        kind = "bytecode"
        if name == "python-bytecode":
            command = [tools["py"], "-3", "-c", "import dis,sys; p=sys.argv[1]; dis.dis(compile(open(p, encoding='utf-8').read(),p,'exec'))", source]
        elif name == "ruby-bytecode":
            command = [tools["ruby"], "--disable-gems", "-e", "puts RubyVM::InstructionSequence.compile_file(ARGV[0]).disasm", source]
        elif name == "luajit-bytecode":
            command = [tools["luajit"], "-bl", source]
        elif name == "lua-bytecode":
            command = [Path(tools["lua"]).with_name("luac.exe"), "-l", "-l", "-p", source]
        elif name == "php-opcodes":
            command = tc.php_command(tools, str(source))
            command = command[:-1] + ["-d", "zend_extension=" + tools["php_opcache"], "-d", "opcache.enable_cli=1",
                                      "-d", "opcache.opt_debug_level=0x20000", str(source)]
        listing = run(command, env)
        if name == "php-opcodes":
            check(listing, task)
            if "RETURN" not in listing:
                raise ValueError("PHP produced no opcode listing")
    return command, source, listing, extra, diagnostic, kind


def native_capture(name, task, recipe, tools, env, objdump, pdbutil):
    command = list(recipe["cmd"])
    folder = Path(recipe["exe"]).parent
    mapfile = folder / (Path(recipe["exe"]).stem + ".map")
    if name in ("cpp-msvc", "cpp-clang-cl"):
        command += ["/link", "/MAP:" + str(mapfile)]
    elif name == "rust":
        command += ["-C", "link-arg=/MAP:" + str(mapfile)]
    elif name == "swift":
        command += ["-Xlinker", "/MAP:" + str(mapfile)]
    elif name == "d-ldc":
        command += ["-L=/MAP:" + str(mapfile)]
    elif name == "odin":
        command += ["-extra-linker-flags:/MAP:" + str(mapfile)]
    elif name == "zig":
        command += ["-femit-asm=" + str(folder / "compiler.s")]
    elif name.startswith("swag-"):
        command += ["--print-micro", "*"]
    for path in recipe["clean"]:
        tc.rm(path)
    for path in recipe["mkdir"]:
        Path(path).mkdir(parents=True, exist_ok=True)
    if recipe["state"]:
        recipe["state"].restore()
    build_env = env | recipe["env"]
    build_output = run(command, build_env, recipe["cwd"])
    binary = Path(recipe["exe"])
    output = run(tc.make_launchers(tools)[name](str(binary)), build_env)
    check(output, task)
    if name == "csharp-jit":
        diagnostic = {"COMPlus_JitDisasm": "*", "COMPlus_JitDisasmAssemblies": task + "_csjit",
                      "COMPlus_TieredCompilation": "0", "COMPlus_ReadyToRun": "0"}
        output = run([tools["dotnet"], binary], build_env | diagnostic)
        check(output, task)
        if "Assembly listing for method" not in output:
            raise ValueError("CoreCLR produced no native listing")
        return command, binary, output, None, {"build.txt.gz": build_output}, diagnostic
    if name == "java-hotspot":
        command_run = [tools["java"], "-Xbatch", "-XX:-TieredCompilation", "-XX:CompileThreshold=100",
                       "-XX:+UnlockDiagnosticVMOptions", "-XX:CompileCommand=print,Bench::*", "-cp", binary.parent, "Bench"]
        output = run(command_run, build_env)
        check(output, task)
        assembly = decode_hotspot(output, objdump, env, folder)
        return command, binary, assembly, None, {"hotspot-raw.txt.gz": output, "build.txt.gz": build_output}, {"run_command": list(map(str, command_run))}
    assembly = run([objdump, "--disassemble", "--demangle", "--x86-asm-syntax=intel", binary], env)
    extra = {"build.txt.gz": build_output}
    if name.startswith("swag-"):
        extra["symbols.txt.gz"] = swag_symbols(binary)
    elif name == "go":
        extra["symbols.txt.gz"] = run([tools["go"], "tool", "nm", binary], env)
        extra["go-assembly.txt.gz"] = run([tools["go"], "tool", "objdump", binary], env)
    elif name == "zig":
        extra["compiler-assembly.txt.gz"] = (folder / "compiler.s").read_text(encoding="utf-8")
    elif name == "csharp-aot":
        extra["symbols.txt.gz"] = run([pdbutil, "dump", "-publics", "-symbols", binary.with_suffix(".pdb")], env)
    else:
        extra["symbols.txt.gz"] = mapfile.read_text(encoding="utf-8", errors="replace")
    micro = build_output if name.startswith("swag-") else None
    if micro and "  function : " not in micro:
        raise ValueError("Swag produced no Micro listing")
    return command, binary, assembly, micro, extra, {}


def verify_partial_entry(manifest):
    """Resume only byte-exact complete entries whose source and compiler still match."""
    record = json.loads(manifest.read_text(encoding="utf-8"))
    metadata = record["metadata"]
    if metadata["checksum"] != str(smoke.CHECKS[record["task"]]) or metadata["checksum"] != metadata["expected_checksum"]:
        raise ValueError("the existing entry has no matching checksum")
    for name, fingerprint in record["sources"].items():
        path = Path(tc.worktree()) / name
        if not path.resolve().is_relative_to(Path(tc.worktree()).resolve()) or not codegen.source_matches(path, fingerprint):
            raise ValueError("the existing entry has changed sources: " + name)
    compiler = Path(metadata["command"][0])
    if installs.sha256(compiler) != metadata["compiler_executable_sha256"]:
        raise ValueError("the existing entry has a different compiler")
    for name, fingerprint in record["artifacts"].items():
        path = manifest.parent / name
        if path.resolve().parent != manifest.parent.resolve():
            raise ValueError("an existing artifact escapes the entry")
        data = path.read_bytes()
        raw = gzip.decompress(data)
        if (codegen.digest(data) != fingerprint["sha256"] or len(data) != fingerprint["bytes"] or
                codegen.digest(raw) != fingerprint["content_sha256"] or len(raw) != fingerprint["content_bytes"]):
            raise ValueError("an existing artifact changed: " + name)
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path, help="new immutable snapshot directory")
    parser.add_argument("--swc", default=tc.swc_path())
    parser.add_argument("--tasks", default=",".join(tc.TASKS))
    parser.add_argument("--toolchains", help="comma-separated capture identifiers")
    parser.add_argument("--resume", action="store_true", help="verify and reuse complete entries in an unsealed snapshot")
    args = parser.parse_args()
    if os.name != "nt":
        parser.error("this collector needs Windows; use the portable exporter for Linux captures")
    if (args.output / "snapshot.json").exists() or (args.output.exists() and not args.resume):
        parser.error("the snapshot directory already exists")
    tasks = args.tasks.split(",")
    if not tasks or set(tasks) - set(tc.TASKS):
        parser.error("unknown or empty task selection")
    selected = args.toolchains.split(",") if args.toolchains else [
        *NATIVE, *[n for n in DIAGNOSTIC if n not in
                  ("csharp-coreclr-fullopts", "java-hotspot-c2", "php-tracing-jit")]]
    selected = ["csharp-jit" if name == "csharp-coreclr-fullopts" else "java-hotspot" if name == "java-hotspot-c2" else name for name in selected]
    if set(selected) - (set(NATIVE) | set(DIAGNOSTIC)):
        parser.error("unknown capture identifier")
    tc.prepare_sources()
    tools = tc.discover()
    env = tc.build_env(tools)
    objdump = Path(tools["clang_cl"]).with_name("llvm-objdump.exe")
    pdbutil = objdump.with_name("llvm-pdbutil.exe")
    subject = installs.snapshot_subject(args.swc)
    error = subject.publish_dependencies(env, 3)
    if error:
        raise SystemExit(error)
    shared = {"zig": tc.zig_global_cache()}
    if "go" in selected:
        shared["go"] = tc.go_std_cache(tools, env, [tc.go_files(task) for task in tasks])
    recipes = tc.make_recipes(tools, env, {"subject": subject}, 3, shared)
    versions = {name: run(command, env).strip() for name, command in tc.version_commands(tools).items()
                if name not in tc.missing(tools) and name != "cpp-msvc"}
    if "cpp-msvc" in selected:
        version = subprocess.run([tc.resolve(env, "cl")], env=env, capture_output=True, text=True)
        versions["cpp-msvc"] = (version.stdout + version.stderr).strip()
    swag_version = run([subject.swc, "--help"], env).splitlines()[0]
    versions.update({name: swag_version for name in tc.SWAG_AOT})
    failures = []
    args.output.mkdir(parents=True, exist_ok=args.resume)
    for task in tasks:
        for name in selected:
            base = DIAGNOSTIC.get(name, name)
            identity = {"csharp-jit": "csharp-coreclr-fullopts", "java-hotspot": "java-hotspot-c2"}.get(name, name)
            if base in tc.missing(tools):
                failures.append(task + "/" + name + ": toolchain is missing")
                continue
            try:
                manifest = args.output / identity / task / "manifest.json"
                if args.resume and manifest.exists():
                    verify_partial_entry(manifest)
                    print(task, identity, "verified; reused", flush=True)
                    continue
                if name in DIAGNOSTIC:
                    command, binary, assembly, extra, diagnostic, kind = interpreted_capture(name, task, tools, env, objdump)
                    micro, recipe = None, {"cwd": tc.BENCH, "env": {}}
                else:
                    recipe = recipes[name](task, "capture_" + task + "_" + name.replace("-", "_"))
                    command, binary, assembly, micro, extra, diagnostic = native_capture(
                        name, task, recipe, tools, env, objdump, pdbutil)
                    kind = "native-jit" if diagnostic else "native"
                fingerprints = codegen.source_fingerprints(tc.worktree(), sources(task, base))
                compiler = Path(tc.resolve(env, command[0]))
                metadata = {"command": list(map(str, command)), "cwd": recipe["cwd"], "environment": recipe["env"] | diagnostic,
                            "build_returncode": 0, "run_returncode": 0,
                            "checksum": str(smoke.CHECKS[task]), "expected_checksum": str(smoke.CHECKS[task]),
                            "binary_sha256": installs.sha256(binary), "binary_bytes": binary.stat().st_size,
                            "compiler_executable_sha256": installs.sha256(compiler),
                            "compiler_version": versions[base], "target": "x86_64-pc-windows-msvc",
                            "abi": "Swag internal; Windows x64 foreign calls" if name.startswith("swag-") else "Windows x64",
                            "kind": kind, "timing_claim": False,
                            "diagnostic_variant": diagnostic, "compiled_source_sha256": fingerprints}
                if name in DIAGNOSTIC:
                    metadata["input_artifact_sha256"] = metadata.pop("binary_sha256")
                    metadata["input_artifact_bytes"] = metadata.pop("binary_bytes")
                    metadata["runtime_executable_sha256"] = installs.sha256(compiler)
                codegen.export_entry(args.output, identity, task, metadata, assembly, fingerprints, micro, extra)
                print(task, identity, "ok", flush=True)
            except (OSError, ValueError, RuntimeError, KeyError) as error:
                failures.append(task + "/" + name + ": " + str(error))
                print(task, name, "FAILED:", error, flush=True)
    metadata = {"purpose": "Static generated-code references; no timing or runtime ranking claim",
                "date": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                "source_commit": installs._git(["rev-parse", "HEAD"]),
                "source_dirty": bool(installs._git(["status", "--porcelain", "--untracked-files=no"])),
                "platform": {"os": platform.platform(), "architecture": platform.machine()},
                "compiler_versions": versions, "tasks": tasks, "failures": failures,
                "limitations": ["JIT diagnostics use explicitly recorded settings, separate from stock timing recipes",
                                "Memory-only Swag JIT and interpreter native code are not captured",
                                "The installed Windows PHP tracing JIT prints no native assembly with opcache.jit_debug=1; its opcodes are captured separately"]}
    if failures:
        Path(tc.OUT, "capture-errors.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
        print("Capture incomplete; fix the failures and use --resume. No snapshot was sealed.", flush=True)
        return 1
    codegen.finish_snapshot(args.output, metadata)
    print("Snapshot:", args.output, flush=True)
    return int(bool(failures))


if __name__ == "__main__":
    raise SystemExit(main())
