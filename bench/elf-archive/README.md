# ELF archive publication benchmark

Compare SWC's internal GNU archive writer with the previous `ar -DM` MRI path.
Both start from the same in-memory ELF objects, preserve member order, and atomically
publish an indexed archive. The old path includes materializing each object, writing
the MRI script, spawning `sh`/`ar`, reading the archive, and removing temporary files.
Object generation is excluded. Samples alternate execution order after one warm-up
per implementation. Results are medians of seven samples by default; these are warm
filesystem measurements, not whole compiler build times.

Build a DevMode or Release compiler with `tools/linux-build.py`, then run:

```sh
python3 bench/elf-archive/run.py --build-dir /absolute/build/devmode --output /tmp/elf-archive-results.json
```

The harness uses that build's compiler flags and object files, replacing only the
compiler command entry point. It checks matching defined symbols with `nm` and
links and executes a C consumer against both archives. Each object defines a unique
six-byte function; `--counts` controls archive size and `--rounds` controls repetitions.
Use a quiet machine. The JSON records every sample and the GNU ar version.

The writer currently supports GNU 32-bit archive indexes and rejects archives exceeding
that format's 4 GiB limit. GNU 64-bit archive indexes remain a separate extension.

## Recorded run

[2026-11-04 DevMode samples](../results/elf-archive/20261104-devmode.json), GCC 14.2,
GNU ar 2.44, Intel Xeon Platinum 8573C, Linux container with a four-CPU quota.
Seven samples per implementation after warm-up:

| Members | GNU ar MRI (ms) | Internal (ms) | Reduction | Speedup |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 15.365 | 0.034 | 99.78% | 453.3x |
| 100 | 24.876 | 0.199 | 99.20% | 125.2x |
| 1000 | 191.307 | 2.710 | 98.58% | 70.6x |
| 10000 | 2719.309 | 22.331 | 99.18% | 121.8x |

These numbers include the old path's object-file I/O and process launch overhead.
They describe synthetic per-function archives on this filesystem, not total compiler
speedups. Raw samples include the observed variation.

Validation used a full DevMode compiler build, all 1,672 fast C++ tests, and 16
focused ELF/Linux linker tests. The focused cases cover archive index/layout,
rejected ELF objects, static and shared dependency publication, parallel-build
determinism, incremental caches and relinking, runtime symbols and DWARF, PIC
function pointers, read-only relocated constants, GNU linker compatibility, and
global constant pointers consumed by C++.

A temporary runner linked the compiler's normal objects and filtered only test
registration for the focused cases. All 16 passed with an `ar` blocker first in
`PATH`, and no blocker invocation occurred. Tests ran in isolated Linux test
snapshots with at most three compiler workers. No full repository campaign or
Windows execution was selected for this Linux archive change.
