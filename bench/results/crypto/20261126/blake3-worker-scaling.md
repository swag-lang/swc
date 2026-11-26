# BLAKE3 worker scaling

Measured on 2026-11-26 in the Linux x86-64 environment with AMD EPYC 9V74 vCPUs.
Swag used the Release compiler and a native Release program. Core's BLAKE3
source matches `f23b0f4bec`. The reference was upstream BLAKE3 C 1.8.7,
running on one worker and reporting a SIMD dispatch width of 16.

All implementations used the affinity mask 0, 1, 2, 4. CPUs 0 and 1 share
their reported L1 and L2 caches. The cgroup allowed four CPU equivalents and
its throttling counter stayed unchanged throughout the campaign. The runner
interleaved 11 rounds per input and verified the complete 32-byte digest
for every call. The timer covered repeated hashes of a warmed in-memory
message, including initialization, worker scheduling, and finalization. It
excluded file reads and the worker pool's startup.

## One-shot wall throughput

| Input | Swag 1 worker | Swag 2 workers | Swag 4 workers | BLAKE3 C |
| ---: | ---: | ---: | ---: | ---: |
| 1 MiB | 0.831 GB/s | 1.392 GB/s | 1.816 GB/s | 6.425 GB/s |
| 8 MiB | 0.803 GB/s | 1.441 GB/s | 1.974 GB/s | 6.283 GB/s |
| 32 MiB | 0.792 GB/s | 1.346 GB/s | 2.025 GB/s | 5.047 GB/s |
| 64 MiB | 0.773 GB/s | 1.364 GB/s | 1.930 GB/s | 4.722 GB/s |

At 32 MiB, four configured Swag workers give a paired 2.57× speedup over
one worker, with a 95% interval of 2.22–2.71×. Median process CPU time
divided by wall time was 1.00, 1.83, and 2.87 CPU equivalents for the
respective Swag worker counts. At 64 MiB the four-worker ratio was 2.61.
The ratios measure the time spent on CPU across the complete operation.

## Streaming wall throughput

| Input | Update size | Swag 1 worker | Swag 2 workers | Swag 4 workers | BLAKE3 C |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 8 MiB | 4 KiB | 0.673 GB/s | 0.673 GB/s | 0.673 GB/s | 2.488 GB/s |
| 8 MiB | 64 KiB | 0.795 GB/s | 0.766 GB/s | 0.784 GB/s | 5.869 GB/s |
| 8 MiB | 1 MiB | 0.824 GB/s | 0.788 GB/s | 0.813 GB/s | 6.331 GB/s |
| 32 MiB | 4 KiB | 0.662 GB/s | 0.656 GB/s | 0.655 GB/s | 2.260 GB/s |
| 32 MiB | 64 KiB | 0.777 GB/s | 0.778 GB/s | 0.768 GB/s | 4.803 GB/s |
| 32 MiB | 1 MiB | 0.796 GB/s | 0.788 GB/s | 0.805 GB/s | 5.108 GB/s |

Streaming includes a constructor, repeated calls to `update` with the
listed slice size, and one finalization. Median process CPU time divided
by wall time stayed at 1.00 for each measured worker setting. An independent
verification used 56 fixtures covering both alignments, empty input, and
one-byte tails around update boundaries, with each fixture verified at all
three Swag worker counts.

## Reproduce one-shot timing

Build the benchmark programs with the crypto comparison workload,
then point `SWAG` and `REFERENCE` to their executables and `WORK` to external scratch.

```sh
python3 -B "$REPO/bench/workloads/crypto/run.py" \
  --algorithm blake3 --swag "w1=$SWAG" --swag "w2=$SWAG" --swag "w4=$SWAG" \
  --workers w2=2 --workers w4=4 --reference "$REFERENCE" \
  --cpu 0 --cpu 1 --cpu 2 --cpu 4 --clock wall --rounds 11 --target-ms 35 \
  --size 1048576 --size 8388608 --size 33554432 --size 67108864 \
  --scratch "$WORK" --output "$WORK/blake3-oneshot-wall.json"
```

## Reproduce streaming timing

The dedicated workload implements the same digest checks and timing protocol
for all three streaming sizes. To replay this table, run its documented
command with `--algorithm blake3-stream-4096`,
`--algorithm blake3-stream-65536`, and `--algorithm blake3-stream-1048576`.
[Workload build and run instructions](../../../workloads/blake3/README.md).

[One-shot samples](blake3-oneshot-wall.json) and [streaming samples](blake3-stream-wall.json).
