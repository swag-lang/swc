# Integrated Linux ELF linking

SWC resolves x86-64 ELF objects, extracts indexed archive members on demand and writes
executable/shared images internally. The link job owns typed library inputs and search
paths; no command line, response file, temporary object directory or tool process is
needed. Executable startup calls glibc directly from a generated System V entry stub,
without GCC CRT objects or development packages.

The reader preserves local/global/weak/common definitions, debug-section contributions
and versioned dynamic imports. The writer builds GOT slots and eager import trampolines,
SysV symbol hashes, version requirements, dynamic relocations, runtime symbols, DWARF
contributions and an indexed unwind header. Separate read-only, executable, RELRO and
writable load segments preserve memory protections. Constructor/destructor arrays merge
by priority. Shared modules bind their own symbols locally and retain `$ORIGIN` lookup.
Archives use the shared mapped reader, and a work queue avoids rescanning long chains
of archive dependencies.

The target is Linux x86-64 with glibc. Image sizes and archive indexes retain the backend's
current 32-bit limits. Foreign static TLS inputs, direct TLS-variable references and local
IFUNC resolvers are rejected explicitly; imported DSOs can use TLS and IFUNC internally.
Further foreign-archive ABI coverage is tracked in `platform.portability.095`.

## Reproduce the timing comparison

Preserve a compiler built before the ELF linker change and build the new compiler with
`tools/linux-build.py`. Use matching compiler configurations on both sides, then run:

```sh
python3 bench/workloads/elf-linker/run.py \
  --build-dir /absolute/build/devmode \
  --compiler /absolute/build/devmode/swc.dm \
  --baseline-compiler /absolute/baseline/swc.dm \
  --output /tmp/elf-linker-results.json
```

The isolated link benchmark starts with identical in-memory ELF objects. The old path
materializes objects, writes a response file, runs `cc` with the former GNU flags, reads
the image and publishes it atomically. The new path resolves and writes the image in
memory, then publishes it atomically. Both include permission updates and cleanup;
object generation and subsequent execution checks are outside the timed region. The
fixtures include a real libc import, and every output is executed or loaded and called.

The full rebuild benchmark compares the preserved compiler with the integrated one on
a standalone generic program, a static dependency workspace and a transitive shared
workspace. It forces source rebuilds, includes parsing/code generation/dependency linking,
and validates program output outside timing. Each compiler has isolated sources,
resources, workspaces and caches. Compiler workers are capped at three.

One warm-up per side precedes seven measured repetitions by default. Execution order
alternates, and the JSON retains every sample, compiler binary digests and tool versions.
These are warm filesystem measurements on one host. Link-only gains do not imply the
same reduction in total compilation time.

## Measured results (2026-11-04)

Linux x86-64, Xeon Platinum 8573C, four-CPU quota, GCC 14.2, glibc 2.41.
Both compilers and generated programs use DevMode; these are not Release compiler
measurements. The baseline is commit `1d663082027ae0781391e52cd9b18f0fe9333a7f`,
which already uses the internal archive writer. Values are median milliseconds from
seven repetitions after warm-up, with alternating execution order.

| Isolated link | Former GNU path | Internal | Speedup |
| --- | ---: | ---: | ---: |
| Executable, 1 object | 66.64 | 6.68 | 9.98x |
| Executable, 100 objects | 76.04 | 6.35 | 11.98x |
| Executable, 1,000 objects | 180.53 | 11.76 | 15.36x |
| Shared library, 1 object | 58.92 | 5.70 | 10.33x |
| Shared library, 100 objects | 65.24 | 6.30 | 10.35x |
| Shared library, 1,000 objects | 161.18 | 10.78 | 14.95x |

| Complete forced rebuild | Former compiler | Internal | Time reduction |
| --- | ---: | ---: | ---: |
| Standalone program | 836.80 | 876.04 | -4.69% |
| Static dependency workspace | 3,154.35 | 2,664.79 | 15.52% |
| Transitive shared workspace | 4,050.55 | 4,044.72 | 0.14% |

Full rebuild samples fluctuate substantially on this shared host. A separate eight-pair,
balanced standalone confirmation measured medians of 1,194.00 ms and 1,014.44 ms
(15.04% reduction), reversing the first comparison's small slowdown. Consequently,
these runs do not establish a stable standalone improvement or regression; the shared
workspace also shows no established total-time gain. The isolated link improvement is
much larger than the observed total-build differences. All original samples and the
confirmation, including compiler output, are retained in
[the raw report](../../results/elf-linker/20261104-devmode.json).

## Validation

The final DevMode compiler passed 1,674 fast C++ tests, 4,049 native language tests,
22 focused ELF/archive/linker tests, and 21 core tests selected for threads, events,
concurrent allocation, SIMD and Linux locale behavior. Swag-driven tests used at most
three workers. Executable/shared benchmark outputs were executed or loaded and called.
External compiler, assembler, archiver and linker commands were blocked during native
and core suites; focused native C++ fixtures retained their C++ setup toolchain while
blocking SWC's former `cc` path. No blocked tool was invoked. Windows execution and a
whole-repository campaign were outside this Linux linker validation.

After integrating upstream master `e03ae65f22`, the DevMode compiler was rebuilt
and all 22 focused ELF/linker tests passed again with no blocked tool invocation.
Timing samples above precede this integration; their binary digests remain in the report.
