# BLAKE3 streaming updates and full SIMD batches

The streaming path uses the existing four-chunk compression for an exact
4 KiB final update and uses the worker pool for large updates. Native Release
and Release-safe each passed six focused cases. The external sweep checked
80 fixtures at one, two and four workers against official BLAKE3 C 1.8.7.
A separate four-worker run checked 131-byte XOF, keyed hashing and key
derivation with 1025-byte updates in both configurations.

The paired wall-clock experiment used 11 rounds per case, 25 ms target
per sample, AMD EPYC 9V74 CPUs 0, 1, 2 and 4, and four Swag workers.
The official C reference used its single-threaded default with AVX-512
dispatch enabled. The quiet window lasted 22.4 seconds and added zero
cgroup throttle events.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| blake3-stream-4096 | 8388608 | 0 | combined | current | GB/s | 0.8 | 0.675 | 1.17 [0.823, 1.21] |
| blake3-stream-4096 | 33554432 | 0 | combined | current | GB/s | 0.777 | 0.677 | 1.16 [1.14, 1.17] |
| blake3-stream-65536 | 8388608 | 0 | combined | current | GB/s | 1.08 | 0.797 | 1.42 [1.24, 1.62] |
| blake3-stream-65536 | 33554432 | 0 | combined | current | GB/s | 1.26 | 0.784 | 1.59 [1.37, 1.69] |
| blake3-stream-1048576 | 8388608 | 0 | combined | current | GB/s | 1.78 | 0.799 | 2.19 [2.08, 3.91] |
| blake3-stream-1048576 | 33554432 | 0 | combined | current | GB/s | 1.82 | 0.79 | 2.29 [2.13, 2.59] |
| blake3 | 8388608 | 0 | combined | current | GB/s | 1.93 | 2.08 | 0.933 [0.802, 1.03] |
| blake3 | 33554432 | 0 | combined | current | GB/s | 2.02 | 1.84 | 1.14 [0.897, 1.27] |
| blake3 | 67108864 | 0 | combined | current | GB/s | 2.19 | 2.05 | 1.12 [0.858, 1.26] |

All one-shot confidence intervals include parity. For 32 MiB streams,
64 KiB and 1 MiB updates take less elapsed time and consume more aggregate
CPU time. Relative throughput per CPU second is 0.741× at 64 KiB and
0.862× at 1 MiB.

[Raw streaming trials](blake3-stream-updates.json) · [Raw one-shot trials](blake3-stream-one-shot.json) · [External verification](blake3-stream-verification.json) · [Measured CPU usage](blake3-stream-usage.json).
