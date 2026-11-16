# Release executable size

Scope keeps every viewer and both applications use the ordinary `release` preset,
without `--debug`. These are whole executable file sizes, excluding external
system libraries and package resources.

| Target | Application | Before, bytes | After, bytes | Saved, bytes | Reduction |
| --- | --- | ---: | ---: | ---: | ---: |
| Linux x86-64 | Swag Scope | 27,716,528 | 18,650,592 | 9,065,936 | 32.71% |
| Linux x86-64 | Swag Capture | 25,799,104 | 16,993,944 | 8,805,160 | 34.13% |
| Windows x86-64 | Swag Scope | 18,388,480 | 17,652,736 | 735,744 | 4.00% |
| Windows x86-64 | Swag Capture | 16,972,288 | 16,342,016 | 630,272 | 3.71% |

The Windows Capture baseline starts **after** the first PE constant-reader fix;
the other baselines precede the initial size batch. Each pair uses matching source
paths, runtime sources, toolchain and worker counts. The recorded after artifacts
come from forced rebuilds; incremental builds can have different padding and
metadata ordering. Artifact and compiler SHA-256 values, source identity, section
sizes and intermediate evidence are in [measurements.json](measurements.json).

## Changes shared by application builds

- ELF omits nonloaded static symbol/string tables when `--debug` is disabled and
  reclaims unused file space after runtime symbol merging. Dynamic symbols,
  reflection, runtime stack traces and unwind information remain present.
  `--debug` retains the external debugger's static symbols.
- PE immutable allocations are folded after archive extraction. A dependency work
  queue revisits readers when their targets become aliases. This also covers
  read-only zero-filled allocations and propagates through duplicate call graphs.
- ELF executables pool standalone compiler-owned immutable allocations and
  identical functions, comparing their relocations and unwind rules. Self references
  use a tagged key, keeping legal foreign names and distinct cycles separate. Shared
  objects keep independently interposable definitions. Both linkers preserve
  distinct functions whose addresses are observed and reject candidates with
  unrelated storage or public definitions.
- DWARF frames use standard short register/location encodings. Native ELF frame
  contributions with the exact known CIE share that record, with adjusted FDE
  references and relocation locations. Other CIEs and symbol-bearing frame
  contributions keep their original representation. This last step alone removes
  815,104 bytes from Linux Scope.

The RealVideo module also stores its 120,194 entropy-tree entries as `u16` rather
than `s32`. Compile-time conversion preserves every edge and leaf; the original
32-bit table and conversion helpers are absent from runtime artifacts. The final
Scope binaries each contain exactly one complete 240,388-byte packed table and
no copy of the original 480,776-byte table. A common instruction combiner absorbs an adjacent doubled-index addition into one LEA,
so the decoder retains its instruction count and dependency path. It introduces
no runtime table expansion. This benefits every application linking the codec.

No viewer, codec or feature was removed. No size-oriented optimization preset,
executable packer or additional runtime decompression was introduced.

## Execution performance evidence

All twelve Release benchmark tasks retain their checksums and runtime Micro
instruction bodies on **both Linux and Windows**. Repeated generic display names
are compared as multisets of normalized bodies. The only remaining listing
change belongs to a JIT-only build-configuration expression, outside the emitted
workload. The benchmark reference compiler includes the initial ELF stripping and
PE reader fix; those earlier steps have their separate code comparisons in
`initial_batches` of the measurements file.

Final Linux workload timings use **200 alternating, randomized before/after pairs**
after two warmups, pinned to one CPU without concurrent build work. All twelve
bootstrap 95% intervals for the median paired after/before ratio include 1:
[runtime-benchmarks.json](runtime-benchmarks.json). No sustained execution
regression was measured; this does not prove identical timing on every workload
or processor.

An earlier 20-pair probe suggested a 0.72% sort increase. An independent 200-pair
confirmation gave a ratio of 0.99978 with interval [0.99861, 1.00119]. The final
accepted binaries give 1.00029 with interval [0.99842, 1.00201]. Both the
[earlier probe](runtime-initial-benchmarks.json) and
[confirmation](sort-confirmation.json) are retained alongside the final results.

The packed RealVideo tree's isolated entropy workload is about 6.1% faster in
40 paired trials, with an identical checksum. The affected `Bits.code` path
retains 35 instructions, three memory accesses and one call. A complete decode
of 3,000 I/P/B frames, including backward seeks, has an after/before median ratio
of **1.00070** in 20 paired trials: no full-decoder speedup is claimed. See
[tree timings](realvideo-tree-timing.json) and
[complete decode timings](realvideo-decode-timing.json).

Two further comparisons check emitted native code separately from timings:

- The PE function-graph step reduces 24,016 function records to 22,766. Every
  original body has a relocation-normalized equivalent among the survivors,
  except compile-time clock immediates in `ViewerWindow.showAbout`.
- The ELF unwind-compaction step keeps all 23,014 function records and their
  6,928,552 body bytes. Every body remains equivalent with addresses normalized,
  with the same compile-time clock exception.

Both exceptions retain the same instruction sequence. These comparisons isolate
those linker steps; they do not assert byte identity across the entire change.

## Validation

The final Linux DevMode compiler passed all **1,835 C++ tests** with `--dev-full`.
The complete native suite passed **4,084 JIT and 4,084 native tests**, covering
1,141 sources, plus its expected-error owning and pointer stages. Release
symbolization, panic unwinding and optimizer regressions passed seven native
tests on each platform; the optimizer JIT test also passed on Windows.

RealVideo passed twelve JIT and twelve native tests on each platform, including
an exhaustive check of all table edges and the unchanged FFmpeg YUV references,
file/memory decoding and backward seeks. Scope also passed all thirty native
video-consumer tests on each platform. Both Release applications passed
three-frame smokes on each platform under Xorg's dummy driver. Linux host unwind
tests passed in DevMode and Release, including C++ cleanup through generated
frames, short-encoding boundaries, signals, stack overflow and concurrent frame
removal. `readelf --debug-dump=frames-interp` completed with empty stderr.

The experimental removal of full-literal default clears was deferred. Its small
size gain did not justify keeping it while Linux asynchronous video-consumer tests
were less reliable in that variant. The accepted compiler passes that consumer
after a complete rebuild; the size table records this accepted implementation.
Some asynchronous waits also failed with the reference compiler.

## Reproduction and Windows boundary

The Windows compiler is built on Linux with LLVM-MinGW 20261104 and runs under
Wine 10.0. It compiles and links the actual Windows applications using Microsoft
Windows SDK CPP x64 10.0.26100.9457 import libraries. The Win32 host calls execute
through Wine; they do not require removing Windows functionality. The Linux
compiler uses GCC 14. See [tools/README.md](../../../../tools/README.md) for the
cross-build, SDK and Wine environment setup.

```sh
python3 tools/linux-build.py --build-dir /absolute/build --configuration release \
  --cxx g++-14 --jobs 3 --skip-machine-load-admission
python3 tools/linux-build.py --build-dir /absolute/build --target windows --configuration release \
  --cxx /absolute/llvm-mingw/bin/x86_64-w64-mingw32-clang++ --jobs 3 \
  --skip-machine-load-admission

SWAG_PATH="$PWD/bin" /absolute/linux/compiler/swc build --workspace bin/apps \
  --workspace-module swagscope -bc release --num-cores 1 --rebuild
SWAG_PATH="$PWD/bin" /absolute/linux/compiler/swc build --workspace bin/apps \
  --workspace-module swagcapture -bc release --num-cores 3 --rebuild
```

The load-admission bypass above is for managed cloud workspaces. Use one worker
for both Windows application measurements. Preserve each artifact before building
the other side, with separate output/cache roots or forced rebuilds: the compiler
version remains 0.1.1175. Build times from overlapping validation are not runtime
performance measurements.

The owner's roughly **17 MB native Windows Scope** remains a separate reference.
Wine leaves optional embedded runtime symbols in plain SWDB v1; native Windows
can pack them as SWDB v2 with LZNT1. The table measures matching Wine conditions
and cannot be used to infer the exact resulting size of that native release.
Native Windows hardware timing and the Windows-only PDB consumer were not tested.

Remaining opportunities are recorded in
[compiler.optimization.135 and .136](../../../../backlog/compiler.optimization.md):
literal/field-by-field return-local dead clears and reflection retention/relocation demand.
