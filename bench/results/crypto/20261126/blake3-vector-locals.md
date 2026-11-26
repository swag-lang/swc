# BLAKE3 named SIMD state

The four-chunk kernel now keeps each compression state word in a separate
SIMD local. Each lane still belongs to one chunk. The round schedule and
ordered tree fold use the same BLAKE3 state and flags, including the
pending final block used to produce root output.

The baseline is Swag `8b59756686`. Both Swag executables used the same
Linux x86-64 Release compiler and benchmark driver. The C reference is
BLAKE3 1.8.7 with SIMD dispatch width 16 and one worker. The campaign
used 11 paired, interleaved rounds at a 20 ms sample target on an AMD EPYC
9V74. The one-worker run measured process CPU time on CPU 1. The
four-worker runs measured wall time on CPUs `0,1,2,4`. The 33.46-second
campaign added zero cgroup throttle events. The cgroup accumulated
41.17 CPU seconds and the benchmark subprocesses used 27.80 of them.

The exact candidate passed all six focused Core tests in Release and
Release-safe, plus the separate official 131-byte output proof in both
configurations with four workers and staggered updates. An independent
differential run checked 1,263 unkeyed, keyed, derive-key and XOF
fixtures at each of one and four workers. The replay harness also checked
56 unkeyed fixtures across one-shot and all three streaming profiles,
with aligned and unaligned input and one, two and four Swag workers.

## One-worker one-shot, process CPU clock

| Operation | Bytes | Baseline GB/s | Candidate GB/s | BLAKE3 C GB/s | Paired speedup with 95% CI |
| --- | ---: | ---: | ---: | ---: | ---: |
| One-shot | 64 B | 0.459 | 0.420 | 0.550 | 0.99× [0.88, 1.25] |
| One-shot | 1 KiB | 0.646 | 0.645 | 0.941 | 1.00× [0.97, 1.01] |
| One-shot | 4 KiB | 0.792 | 1.470 | 2.687 | 1.86× [1.74, 3.05] |
| One-shot | 4,097 B | 0.778 | 1.454 | 2.410 | 1.90× [1.64, 2.63] |
| One-shot | 64 KiB | 0.828 | 1.587 | 6.357 | 1.91× [1.86, 1.95] |
| One-shot | 1 MiB | 0.827 | 1.590 | 6.435 | 1.92× [1.82, 3.64] |
| One-shot | 8 MiB | 0.800 | 1.514 | 6.085 | 1.88× [1.75, 1.99] |

## Four-worker one-shot, wall clock

| Operation | Bytes | Baseline GB/s | Candidate GB/s | BLAKE3 C GB/s | Paired speedup with 95% CI |
| --- | ---: | ---: | ---: | ---: | ---: |
| One-shot | 8 MiB | 2.047 | 3.239 | 6.310 | 1.57× [1.50, 1.76] |
| One-shot | 32 MiB | 1.841 | 3.034 | 4.964 | 1.44× [1.23, 2.22] |

## Four-worker streaming, wall clock

| Operation | Bytes | Baseline GB/s | Candidate GB/s | BLAKE3 C GB/s | Paired speedup with 95% CI |
| --- | ---: | ---: | ---: | ---: | ---: |
| 4 KiB updates | 8 MiB | 0.808 | 1.484 | 2.526 | 1.81× [1.66, 2.13] |
| 4 KiB updates | 32 MiB | 0.747 | 1.407 | 2.207 | 1.89× [1.73, 3.55] |
| 64 KiB updates | 8 MiB | 1.110 | 1.568 | 6.087 | 1.43× [1.17, 1.73] |
| 64 KiB updates | 32 MiB | 1.113 | 1.538 | 4.959 | 1.33× [1.21, 1.54] |
| 1 MiB updates | 8 MiB | 2.053 | 3.300 | 6.362 | 1.60× [1.38, 1.64] |
| 1 MiB updates | 32 MiB | 2.060 | 3.266 | 5.060 | 1.60× [1.55, 1.75] |

At 32 MiB, four-worker one-shot throughput rose from 1.841 to 3.034
GB/s while median process CPU / wall moved from 2.62 to 2.51. At the
same size, 1 MiB streaming updates reached 3.266 GB/s at 2.35
CPU seconds per wall second. The 64- and 1,024-byte rows have paired
intervals spanning parity. The C reference still reaches 6.435 GB/s at
1 MiB on one worker.

[One-worker raw samples](blake3-vector-locals-cpu.json) ·
[Four-worker one-shot raw samples](blake3-vector-locals-wall.json) ·
[Streaming raw samples](blake3-vector-locals-stream.json) ·
[Workload and build instructions](../../../workloads/blake3/README.md)
