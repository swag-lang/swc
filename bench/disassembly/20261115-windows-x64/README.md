# Windows x86-64 code-generation snapshot

This collection preserves the twelve benchmark tasks in **19 configurations (228 references)**.
Every program produced its original expected checksum. These executions validate correctness;
their elapsed times establish no performance ranking and never enter benchmark history.

| Implementation | Version | Captured settings |
| --- | --- | --- |
| Swag | 0.1.1175, Release compiler | Program `release` and `devmode`, three workers; full Micro and final PE disassembly |
| clang-cl | LLVM 20.1.8 | `/O2 /EHsc /std:c++20`, linker map |
| MSVC | Exact compiler banner in each manifest | `/O2 /EHsc /std:c++20`, linker map |
| Rust | 1.97.1 | Optimization 3, one codegen unit, panic abort, linker map |
| Zig | 0.15.2 | ReleaseFast, Windows MSVC target and libc; compiler assembly |
| LDC | 1.43.0 | `-O3 -release -boundscheck=off`, linker map |
| Odin | dev-2026-09-nightly `a2fb372` | `-o:speed`, linker map |
| Go | 1.27.1 | Stock `go build`; complete Go disassembly and symbol table |
| Swift | 6.3.3 | `-O -wmo`, linker map |
| C# NativeAOT | .NET SDK 9.0.316 | Release publish; final native PE and private/public PDB symbols |
| C# CoreCLR | .NET runtime 9.0.18, SDK 9.0.316 | FullOpts, tiering and ReadyToRun disabled; native JIT assembly |
| Java HotSpot | 25.0.4.1 | C2, `-Xbatch`, no tiering, threshold 100; named Bench methods, native code bytes decoded by LLVM |
| Node / V8 | Node 20.15.1 | Complete `--print-code --print-opt-code` native diagnostics |
| CPython | 3.12.4 | Unquickened Python bytecode, recursively including nested functions |
| Ruby | 4.0.7 | RubyVM instruction-sequence bytecode |
| LuaJIT | 2.1.1720049189 | LuaJIT bytecode, not its native traces |
| Lua | 5.4.6 | Complete `luac -l -l -p` bytecode listing |
| PHP | 8.4.26 | Optimized OPcache opcodes, not native JIT code |

The fourteen native/native-JIT configurations and five bytecode configurations have distinct
identifiers. Read each manifest's `kind`, command, options, environment and compiler version
before comparison. The bytecode entries' hashes identify their input source and runtime
launcher; the native entries also identify the actual compiled artifact. No interpreter
opcode is an x86 instruction.

Native builds use the campaign recipes, adding symbol-map or listing output only. No explicit
ISA variants are added here: compiler defaults remain in force, and managed JITs select host
features. Swag, Go, Swift, Rust and managed runtimes have their own internal calling conventions;
Windows foreign calls use the Windows x64 ABI. These contracts differ from Linux SysV and from
each other. Safety, allocation, reclamation and floating-point policies remain those of the ports.

`assembly.txt.gz` contains the complete final PE disassembly for every native executable.
`micro.txt.gz` retains Swag's pre-emit Micro listing. `symbols.txt.gz` reads Swag's actual
non-debug `.swagdbg` table, the linker map, Go symbols or NativeAOT's PDB dump as appropriate.
Swag symbols include absolute image addresses, sizes and source locations; use them to locate
named functions in the linked disassembly. Go additionally retains `go-assembly.txt.gz`, and
Zig retains `compiler-assembly.txt.gz`. A compiler listing or Micro function may be absent from
the final image; establish native reachability before comparing it.

HotSpot's named original dump is in `hotspot-raw.txt.gz`. No hsdis library was installed, so the
collector decodes its exact native bytes with LLVM, preserving their original virtual addresses.
The diagnostic variants can change compilation thresholds and tiering; they are not stock timing
recipes. ASLR addresses and compiler temporary paths are provenance, not stable function IDs.

The Swag compiler executable's SHA-256 is recorded in every entry. Its build number is stable
across ordinary compiler edits and does not establish cache identity. The snapshot's source
commit describes the checkout used for input collection; the executable hash identifies the
actual compiler. Sources were copied into an external build tree and the compiler/runtime into
a private installation. No binaries, PDBs, toolchains or build caches are stored here.

Remaining limits: memory-only Swag JIT code is not captured. The installed Windows PHP tracing
JIT emits no native listing with `opcache.jit_debug=1`; only its opcodes are retained. LuaJIT
native traces and Ruby native JIT code are also absent. Do not substitute their bytecodes for
missing native output or infer a winner from an absent capture.

Reproduce with an absolute external `BENCH_OUTPUT_ROOT`, then verify:

```text
python bench/bench.py capture --output bench/disassembly/<new-windows-snapshot> --swc C:/absolute/path/to/swc.exe
python bench/bench.py codegen verify bench/disassembly/20261115-windows-x64 --check-sources
```

Collection failures leave the folder unsealed. `--resume` verifies existing sources, compiler
hashes and compressed/decompressed artifacts before reusing them. A successful sealed snapshot
is immutable. See the parent [catalogue](../README.md) for reuse rules.
