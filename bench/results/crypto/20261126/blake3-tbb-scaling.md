# BLAKE3 one-shot scaling against oneTBB

The Swag Release build `8b59756686` and BLAKE3 C 1.8.7 ran on the same
AMD EPYC 9V74 host with affinity `0,1,2,4` and a four-CPU container quota.
The C implementation dispatched to width 16 and used oneTBB 2022.1.0 for
its parallel update API. Its one-worker run used the serial update API.
The two- and four-worker settings limited oneTBB's concurrency, including
the calling thread. Swag started each configured pool before warmup.

Each row has 11 paired, interleaved wall-time samples at a 25 ms target.
The 17.24-second campaign recorded zero additional cgroup throttle events.
Child processes accumulated 26.33 CPU seconds out of 26.76 measured by the
cgroup. All six configurations produced identical 32-byte digests before
each size was timed. The optional replay build also verified eight
aligned or unaligned fixtures covering empty input and non-block tails.

## Median throughput

| Input | Workers | Swag GB/s | BLAKE3 C GB/s | Swag / C with 95% CI | Swag CPU / wall | C CPU / wall |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 8 MiB | 1 | 0.830 | 6.270 | 0.132 [0.074, 0.136] | 1.00 | 1.00 |
| 8 MiB | 2 | 1.474 | 12.168 | 0.121 [0.119, 0.129] | 1.81 | 1.93 |
| 8 MiB | 4 | 2.221 | 22.923 | 0.096 [0.085, 0.137] | 2.71 | 3.90 |
| 32 MiB | 1 | 0.798 | 4.962 | 0.160 [0.149, 0.164] | 1.00 | 1.00 |
| 32 MiB | 2 | 1.438 | 9.547 | 0.143 [0.102, 0.247] | 1.83 | 1.94 |
| 32 MiB | 4 | 1.965 | 15.954 | 0.126 [0.092, 0.144] | 2.76 | 3.93 |
| 64 MiB | 1 | 0.773 | 4.783 | 0.164 [0.095, 0.171] | 1.00 | 1.00 |
| 64 MiB | 2 | 1.434 | 9.214 | 0.156 [0.138, 0.173] | 1.84 | 1.89 |
| 64 MiB | 4 | 2.020 | 14.969 | 0.135 [0.102, 0.167] | 2.83 | 3.82 |

At 32 MiB, four workers delivered a paired speedup of 2.46× [1.92, 3.07]
from one worker in Swag and 3.29× [3.08, 4.13] in C with oneTBB. Swag
already used 1.00 CPU per wall second with a single worker. The
single-worker throughput measures the kernel gap at the same CPU use.
CPU / wall counts all process activity, including hashing and worker
management.

[Raw wall and process CPU samples](blake3-tbb-wall.json) ·
[Workload and build instructions](../../../workloads/blake3/README.md)
