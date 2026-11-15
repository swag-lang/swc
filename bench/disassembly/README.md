# Static code-generation references

These snapshots preserve generated code for future optimization campaigns. They are not timing
campaigns and never contribute a `run_index` or an accepted result to `bench/history.json`.

| Snapshot | Coverage |
| --- | --- |
| [20261114-linux-x64](20261114-linux-x64/README.md) | Twelve tasks: native Swag, GCC, Clang, Rust, Zig, LDC, Odin, Go and Swift; explicit ISA variants; Java C2, V8 and CoreCLR native JIT listings; separately labelled CPython bytecode |
| [20261115-windows-x64](20261115-windows-x64/README.md) | Twelve tasks: Swag release/devmode, clang-cl, MSVC, Rust, Zig, LDC, Odin, Go, Swift and NativeAOT; CoreCLR, HotSpot C2 and V8 native JIT diagnostics; separately labelled Python, Ruby, Lua, LuaJIT and PHP bytecodes |

## Reuse a reference

From the repository root:

```text
python bench/scripts/codegen.py verify bench/disassembly/20261114-linux-x64 --check-sources
python bench/scripts/codegen.py show bench/disassembly/20261114-linux-x64 --task sha256
python bench/scripts/codegen.py show bench/disassembly/20261114-linux-x64 --task sha256 --compiler swag-release --micro
python bench/scripts/codegen.py show bench/disassembly/20261114-linux-x64 --task sha256 --compiler cpp-gcc-v3
python bench/bench.py codegen show bench/disassembly/20261115-windows-x64 --task sort --compiler swag-release --listing symbols.txt.gz
```

Verification checks compressed listings, their decompressed content, provenance manifests,
supporting files and, with `--check-sources`, current source fingerprints. It does **not** assert
that an installed compiler has the archived version or that different target/FP/safety/allocator
contracts are equivalent. Read the entry's exact version, options and target before using it.
For Swag, also match the compiler binary hash and source revision; its build number alone is not
a cache identity for an optimization campaign.

Source checks accept LF and CRLF checkout line endings, including fingerprints from older
snapshots. Listings, manifests and supporting files still need their exact archived bytes.

Each `compiler/task/manifest.json` identifies the checked input and command, compiler and binary
hashes, original and compiled source hashes, checksum, target, listing kind and compressed
artifacts. `assembly.txt.gz` is the complete captured listing, including runtime code present in
the executable. Swag entries additionally contain `micro.txt.gz` and symbolization provenance.
A Micro request can lower functions that the linker does not retain; use the native listing to
establish executable reachability.

## Add a snapshot

Build in an external working directory. Preserve the actual recipe and compiler version. Run
the original workload once to validate its checksum; do not publish that execution's elapsed
time as a performance result. Disassemble the validated artifact, retain source adaptations and
symbol mappings, then call the portable exporter:

```python
from pathlib import Path
import sys
sys.path.insert(0, "bench/scripts")
from codegen import export_entry, finish_snapshot, source_fingerprints

# These values come from the real build and successful checksum run.
export_entry(snapshot, compiler_id, task, metadata, assembly_text,
             source_fingerprints(repository, compiled_input_paths), micro_text)
finish_snapshot(snapshot, snapshot_metadata, supporting_files=["linux-clock.patch"])
```

`metadata` must contain matching string `checksum` and `expected_checksum` values. Keep exact
compiler versions, options and commands, target ISA/ABI, and zero build/run exit codes. Record
the compiled source hashes and the original repository hashes when a platform adapter changes
clock bindings or imports. Archive the adapter itself. Algorithms, timed boundaries, ownership,
safety and floating-point contracts must remain unchanged. An explicit ISA/optimization variant
gets its own compiler ID. `finish_snapshot` seals the inventory and provenance hashes; existing
entries and snapshots are never overwritten. A changed input gets a new snapshot.

Keep compiler installations, native binaries, caches and temporary logs outside the repository.
Compress complete listings reproducibly rather than committing executables. Small selected
kernel excerpts may supplement the complete listings. Bytecode and native instructions must
remain distinct kinds; a bytecode opcode is not an x86 instruction.

## Collect on Windows

The Windows timing campaign stores measurements and toolchain metadata. Run the static collector
outside measurement intervals to retain code independently of disposable `bench/out` builds:

```text
python bench/bench.py capture --output bench/disassembly/<new-windows-snapshot> --swc C:/absolute/path/to/swc.exe
python bench/bench.py codegen verify bench/disassembly/<new-windows-snapshot> --check-sources
```

Set `BENCH_OUTPUT_ROOT` to an absolute external directory. Visual Studio's LLVM tools provide
`llvm-objdump` and `llvm-pdbutil`. The collector uses the campaign's build recipes, adding only
listing or symbol-map options to native builds. Swag symbols come from the actual non-debug
executable's `.swagdbg` table; no debug build replaces its code. Go retains its own complete
symbolized disassembly, Zig its compiler assembly, and NativeAOT its PDB symbol dump. The final
linked PE disassembly is always retained too.

Each entry preserves the exact build or diagnostic command, compiler version and executable hash,
source fingerprints, validated checksum and compiled artifact hash. HotSpot's raw native bytes
are decoded by LLVM and retained beside its named method dump. CoreCLR FullOpts, HotSpot C2
and V8 diagnostics are labelled separately from stock timing recipes. Interpreter bytecode is
explicitly labelled `bytecode`. Memory-only Swag JIT and PHP JIT native code remain uncaptured;
the installed Windows PHP prints no assembly with `opcache.jit_debug=1`.

Compare hot executed paths, weighting nested loops and calls by their work. Account for spills,
dependency chains, vector width, checks and allocation/reclamation. Whole-function instruction
totals, empty timing fields or historical timings from another OS do not establish a winner.
