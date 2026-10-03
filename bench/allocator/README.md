# Allocator

The Swag runtime allocator against mimalloc and the C runtime heap, on the same workloads:
`src/allocbench.swg` allocates through `Memory.alloc`/`Memory.free`, `src/allocbench.c` is
compiled once over the vendored mimalloc and once over the C runtime heap. Every campaign
measures and records it (see "The allocator" in [../README.md](../README.md)); this directory
also runs on its own while iterating on the allocator:

```powershell
py -3 bench/allocator/run.py                    # build the three, five rounds, print the table
py -3 bench/allocator/run.py --only pair,churn:4 --reps 9
py -3 bench/allocator/run.py --no-build --against C:\temp\before\allocator.exe
```

`--against` adds a column for an `allocbench` executable built earlier, typically with the
runtime from before a change: build it from a checkout of that runtime with

```powershell
bin/swc.exe build -f src/allocbench.swg --module-file bench/allocator/module.swg -bc release -od <dir> -wd <dir>
```

Executables and intermediates go to a directory under the system temporary directory unless
`--out` says otherwise. Admit every build and run with the repository's machine-load check, and
use a quiet machine: the multi-thread workloads move with scheduling.

| workload | what it does |
| --- | --- |
| `pair` | one 32-byte block allocated, touched and freed, 20 million times |
| `trees` | binary trees of 16-byte nodes, depth 14, built and freed 40 times |
| `churn` | 50 000 live blocks of mostly small, mixed sizes, one replaced at random per operation |
| `medium` | 256 live blocks of 4 KiB to 64 KiB, replaced at random |
| `large` | 32 live blocks of 64 KiB to 1 MiB, replaced at random, one byte touched per 4 KiB |
| `realloc` | a buffer doubled from 16 bytes to 4 MiB by reallocation, 2 000 times |
| `spread` | ten live blocks of each of twelve sizes, as a long-running application holds them |
| `xfer` | producer/consumer pairs: one thread allocates, the other frees every block |

`name:N` runs a workload on N threads, each with its own live set (N pairs for `xfer`).

On 2026-10-03 the session that introduced this benchmark measured, with the runtime from
before it (`fb9a4c063`) as `--against`, median ns per operation:

| workload | before | after | mimalloc | C heap |
| --- | --- | --- | --- | --- |
| `pair` | 28.4 | 26.5 | 4.3 | 29.9 |
| `trees` | 34.4 | 26.6 | 7.3 | 44.3 |
| `churn` | 53.7 | 49.2 | 17.9 | 68.3 |
| `medium` | 212.9 | 51.4 | 36.5 | 373.5 |
| `large` | 137 408 | 1 976 | 1 545 | 10 200 |
| `realloc` | 17 139 | 11 910 | 10 380 | 83 181 |
| `spread:8` | 1 577 | 739 | 867 | 2 150 |
| `churn:4` | 28.3 | 22.7 | 8.2 | 65.1 |
| `medium:4` | 161.8 | 25.0 | 14.0 | 1 452 |
| `large:4` | 73 530 | 1 422 | 672 | 5 113 |
| `xfer:4` | 112.9 | 94.8 | 71.3 | 97.9 |

These are one shared-machine session's numbers, not a campaign; the campaign history is the
record.
