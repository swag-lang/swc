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
| `grow` | four million 32-byte blocks allocated before any is freed: live-set growth |
| `xfer` | producer/consumer pairs: one thread allocates, the other frees every block |

`name:N` runs a workload on N threads, each with its own live set (N pairs for `xfer`).

On 2026-10-03 the session that introduced this benchmark measured its final state against the
runtime from before it (`fb9a4c063`) as `--against`, seven rotating rounds, median ns per
operation, on a shared machine:

| workload | before | after | mimalloc | C heap |
| --- | --- | --- | --- | --- |
| `pair` | 36.0 | 32.5 | 5.2 | 34.6 |
| `trees` | 39.5 | 32.7 | 8.2 | 47.8 |
| `churn` | 58.8 | 52.7 | 18.8 | 86.5 |
| `medium` | 345.5 | 74.4 | 60.3 | 624.3 |
| `large` | 137 428 | 2 186 | 1 714 | 10 494 |
| `realloc` | 17 751 | 10 342 | 10 368 | 80 716 |
| `spread` | 2 675 | 2 108 | 2 288 | 3 047 |
| `grow` | 25.5 | 19.6 | 7.1 | 32.1 |
| `spread:8` | 2 041 | 991 | 1 011 | 3 106 |
| `churn:4` | 25.5 | 19.9 | 8.1 | 56.0 |
| `medium:4` | 150.6 | 36.1 | 15.5 | 1 732 |
| `large:4` | 134 065 | 1 374 | 1 049 | 10 337 |
| `xfer:2` | 137.0 | 106.2 | 73.0 | 126.8 |
| `xfer:4` | 114.7 | 91.3 | 71.4 | 105.0 |

Peak working sets: within 4 MB of mimalloc's on the other workloads, about 2.5 MB of which is the
`core` module the Swag program imports, and lower on the large-block ones (`large` 44 MB against
71 MB, `large:4` 119 MB against 235 MB, with the C heap lowest). These are one session's numbers, not a campaign; the campaign history is the
record.
