# Linux x86-64 code-generation snapshot

This is a static reference collection for the twelve benchmark tasks, not a timing campaign.
All archived programs produced their original expected checksums. The short executions only
validate results; their elapsed times are not performance evidence.

The collection covers these native implementations and variants:

| Implementation | Version | Captured settings |
| --- | --- | --- |
| Swag | 0.1.1175, compiler source `2f0ab64233`, Release compiler | Program `release`, three workers, full Micro and linked ELF disassembly |
| GCC C++ | 14.2.0 | `-O2` and `-O3`, each with default ISA and explicit `-march=x86-64-v3` |
| Clang C++ | 17.0.0, Swift LLVM build | `-O2` and `-O3`, each with default ISA and explicit `-march=x86-64-v3` |
| Rust | 1.100.0 | Optimization 3, one codegen unit, panic abort; default and x86-64-v3 |
| Zig | 0.15.2 | ReleaseFast, Linux libc; default and x86-64-v3 |
| LDC | 1.43.0, LLVM 22.1.8 | `-O3 -release -boundscheck=off`; default and x86-64-v3 |
| Odin | dev-2026-11-nightly `9a69916` | `-o:speed`; default x86-64-v2 and explicit x86-64-v3 |
| Go | 1.27.4 | Stock `go build`, local toolchain |
| Swift | 6.2.1 | `-O -wmo`; default and explicit Haswell target |

Java HotSpot 21.0.12.1 C2, V8 and .NET CoreCLR 9.0.23 native JIT output are also archived.
The Java entry uses `-Xbatch`, C2 without tiering, and threshold 100 to expose compiled methods.
It preserves OSR and recompilation versions. The JRE had no hsdis, so the actual captured code
bytes were decoded with GNU objdump; the original HotSpot dump accompanies the decoded listing.
CoreCLR uses FullOpts without tiering or ReadyToRun, and retains its Roslyn response file and
runtime configuration. These diagnostic variants are labelled separately from stock benchmark
runtime settings. CPython's unquickened bytecode is included under `python-bytecode`; it is not native code.

Read `snapshot.json` for the exact inventory, versions and limitations, and the per-task
manifests for complete commands and original/compiled source fingerprints. Platform adapters
are in [linux-clock.patch](linux-clock.patch). They replace Windows clock bindings/imports;
the task algorithms, data, timed boundaries and allocation behavior are unchanged.

Swag's final ELF function symbols are intentionally hashed. Each Swag manifest contains a
symbol map obtained by matching unique native source-token hashes against a separate DWARF
build of the same sources. The compared assembly remains the original non-debug code; debug
code is not used as a replacement. Unmatched or ambiguous symbols retain their original names.

ISA and contracts matter. Swag's observed generated code includes AVX2/FMA/BMI operations and
uses its internal calling convention. Other native ports use their Linux language/C ABIs.
CoreCLR and Java select features from the current host. Rust/Swift checks, C++ math contracts,
GC allocation, reference counting and manual reclamation remain their original port behavior.
Haswell and generic x86-64-v3 entries are explicitly distinct targets.

MSVC is not available on this Linux host. NativeAOT package restore was blocked by the managed
sandbox refusing NuGet's named mutex; the captured CoreCLR code is not an AOT substitute. Lua,
LuaJIT, PHP, PHP JIT and Ruby were not captured. Do not infer their code from another compiler
or treat missing captures as losses. The Windows task set still needs its own archived outputs.

See the parent [catalogue](../README.md) for verification, display and future collection.

The collection contains **288 references (24 variants × 12 tasks)**. Read the
[static assessment](analysis.md) for kernel evidence and provisional candidates.
