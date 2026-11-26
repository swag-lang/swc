# Parallel Adler-32 on large buffers

Adler-32 assigns independent 512 KiB tiles to runtime workers from 2 MiB
of input. Each tile starts from the Adler identity. Combining the two
sums in byte order removes that identity and advances the preceding
weighted sum by the tile length. The implementation batches up to 32
tiles and processes the final partial tile serially. JIT and single-worker
execution use the serial kernel.

Both Swag builds include centered byte weights. They used the same Linux
Release compiler and Release program configuration on AMD EPYC 9V74.
Elapsed wall measurements used 11 paired rounds with affinity to CPUs
0–3 and four Swag runtime workers. The cgroup showed no throttled
periods during the exact run. Libdeflate 1.26 used one worker per call.

| Buffer | Previous Swag | Tiled Swag | libdeflate | Swag speed ratio (95% CI) |
| --- | ---: | ---: | ---: | ---: |
| 2 MiB | 37.9 GB/s | 43.3 GB/s | 87.2 GB/s | 1.23× [0.898, 1.27] |
| 4 MiB | 37.7 GB/s | 47.1 GB/s | 89.6 GB/s | 1.26× [1.18, 1.47] |
| 16 MiB | 37.7 GB/s | 64.1 GB/s | 69.5 GB/s | 1.69× [1.66, 2.23] |
| 32 MiB | 28.5 GB/s | 76.2 GB/s | 34.1 GB/s | 2.73× [2.38, 3.07] |

At offset 31, 2 MiB + 1 byte measured 1.16× [1.05, 1.31] and
2 MiB + 79 bytes measured 1.23× [1.13, 1.35]. The input just below the
cutoff measured 0.997×. All one-worker control intervals included 1.

All 21 threshold and alignment inputs matched libdeflate and zlib.
Core tests passed in JIT and native Release with four workers and
exercised unaligned input, split updates and more than 32 tiles.

[Raw paired trials](adler32-worker-tiles.json) · [Unaligned boundary](adler32-worker-tiles-boundary.json) · [One-worker controls](adler32-worker-tiles-serial.json) · [Differential cases](adler32-worker-tiles-verify.json).
