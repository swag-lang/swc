# BLAKE3 native AVX2 width experiment

The hybrid Swag prototype reached **1.91 GB/s at 1 MiB** with one worker,
compared with 1.57 GB/s for the four-lane control and 6.40 GB/s for BLAKE3 C
1.8.7. The paired speed ratio was **1.23× [1.19, 1.26]**. Its four-lane
batch path kept 4 KiB throughput at 1.52 GB/s. The eight-lane-only variant
processed this same input at 0.68 GB/s through the per-chunk path.
[Exact source and replay](../../../workloads/blake3/native-width/README.md)

## One worker

The table reports GB/s and the hybrid-to-control paired ratio with a 95%
confidence interval. All three Swag binaries use the same Release compiler,
driver, 32-chunk scheduling cutoff, and standard-module snapshot. The two
wide variants use eight independent message chunks per AVX2 batch and a
transpose built from lane interleaves and 128-bit half permutations. The
hybrid also uses the four-lane batch between 4 KiB and 8 KiB.

Linux x86-64 on AMD EPYC 9V74, GCC 14.2.0, CPU 1, 13 shuffled rounds with
an 18 ms target. The timer measures process CPU time. BLAKE3 C dispatched
to width 16 on the same machine. [CPU samples](blake3-native-width-cpu.json)

| Input | Offset | Swag 4 lanes | Swag 8 lanes | Swag hybrid | BLAKE3 C | Hybrid / 4 lanes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 4 KiB | 0 | 1.51 | 0.68 | 1.52 | 2.76 | 1.01 [1.00, 1.03] |
| 8,191 B | 0 | 0.93 | 0.67 | 0.93 | 1.60 | 0.99 [0.95, 1.00] |
| 8 KiB | 0 | 1.53 | 1.87 | 1.87 | 4.76 | 1.21 [1.13, 1.45] |
| 64 KiB | 0 | 1.54 | 1.94 | 1.93 | 6.31 | 1.26 [1.19, 1.30] |
| 1 MiB | 0 | 1.57 | 1.85 | 1.91 | 6.40 | 1.23 [1.19, 1.26] |
| 1 MiB | 1 | 1.54 | 1.86 | 1.84 | 6.38 | 1.20 [1.07, 1.25] |
| 8 MiB | 0 | 1.42 | 1.78 | 1.75 | 5.56 | 1.23 [1.21, 1.28] |
| 8 MiB | 1 | 1.45 | 1.61 | 1.67 | 5.46 | 1.15 [1.08, 1.21] |

## Four workers

The one-shot wall-time replay used CPUs 0–3, aligned inputs, 11 shuffled
rounds and a 17 ms target. The C reference was BLAKE3 1.8.7 with oneTBB
2022.1.0 and a four-worker concurrency limit. In the replay the cgroup
recorded zero throttled periods. The first run overlapped with compilation,
recorded 30 throttled periods, and had paired confidence intervals that
included parity at both sizes.
[Replay samples](blake3-native-width-wall.json) ·
[First-run samples](blake3-native-width-wall-contended.json) ·
[Scheduler and CPU usage](blake3-native-width-wall-scheduler.json)

| Input | Swag 4 lanes | Swag 8 lanes | Swag hybrid | C oneTBB 4 | Hybrid / 4 lanes |
| --- | ---: | ---: | ---: | ---: | ---: |
| 8 MiB | 3.15 | 3.94 | 3.86 | 20.18 | 1.21 [1.12, 1.29] |
| 32 MiB | 3.44 | 3.80 | 3.91 | 17.73 | 1.16 [1.07, 1.35] |

Median process CPU divided by wall time was 2.26 and 2.36 for the hybrid
and 3.91 and 3.62 for C oneTBB at 8 and 32 MiB, respectively. This is the
observed CPU use under the same configured worker budget.

## Validation and scope

Each of the three binaries matched official C across 128 fixtures in
Release and 128 in Release-safe, repeated with one and four workers.
The fixtures covered one-shot input and streaming slices of 4 KiB,
64 KiB and 1 MiB, with offset zero or one. The hybrid also matched
131-byte outputs for unkeyed, keyed and derived-key modes with staggered
updates in both configurations. The separate compiler probes checked raw
leaf chaining values, loads and stores with 22 live wide values, constant
stores, rotates, and immediate and dynamic shuffles.
[Replay and fixtures](../../../workloads/blake3/native-width/README.md)

The compiler prototype uses YMM for eight u32 lanes. Swag's internal
calling convention preserves selected XMM registers for the caller, which
preserves only their lower 128 bits. A live 256-bit value crossing an
ordinary call must be spilled and reloaded at full width, including when
assigned to one of those XMM registers. In the raw leaf probe an uninlined
transpose exposed the missing upper-half preservation. The experimental
allocator spills wide values across calls and limits loop residency when a
loop contains a call. The probes use memory at function boundaries. General
wide by-value arguments and results, and liveness across opaque instructions
that clear upper vector halves, still need separate validation before using
this compiler support more broadly.
