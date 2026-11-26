# Parallel CRC-32 on large buffers

CRC-32 folds 512 KiB tiles independently and merges their reflected
remainders in byte order. The merge advances the running remainder by
one tile before XORing the independent contribution. A short final tail
stays with a complete tile for the serial finish. The parallel controller
requires carry-less multiplication, at least 4 MiB, and multiple
runtime workers. It uses batches of up to 32 tiles.

The Linux Release comparison used elapsed time, four Swag workers and
CPU affinity 0–3 on AMD EPYC 9V74. A quiet 11-round cutoff sweep with
no cgroup throttling initially used 2 MiB. At 16 MiB it measured
108 GB/s against 41.8 GB/s for the preceding Swag, a paired 2.67×
[2.44, 2.78]. Libdeflate 1.26 used one worker and reached 54.5 GB/s.
The 2 MiB + 1 byte unaligned case measured 0.932× [0.845, 1.03]. This
led to a 4 MiB cutoff.

The final 4 MiB implementation was checked with seven paired wall
rounds at offset 31. Its measurements were as follows.

| Buffer | Previous Swag | Tiled Swag | Paired speed ratio (95% CI) |
| --- | ---: | ---: | ---: |
| 4 MiB | 40.9 GB/s | 80.6 GB/s | 1.95× [1.70, 2.18] |
| 4 MiB + 1 B | 40.9 GB/s | 61.4 GB/s | 1.49× [1.39, 1.54] |
| 4 MiB + 79 B | 40.7 GB/s | 56.0 GB/s | 1.39× [1.11, 1.57] |
| 16 MiB | 40.1 GB/s | 75.0 GB/s | 1.89× [1.79, 2.36] |

The one-worker control intervals included 1. All 21 final threshold
and alignment inputs matched libdeflate and zlib. Core tests passed
in JIT and native Release with four workers, covering seeded split
updates, unaligned input and batches spanning more than 32 tiles.
The carry-less capability-off branch passed the same focused tests
during cutoff selection.

[Quiet cutoff sweep](crc32-workers-cutoff-sweep.json) · [2 MiB unaligned cutoff control](crc32-workers-2mib-boundary.json) · [Final cutoff retest](crc32-workers-final.json) · [One-worker controls](crc32-workers-one-worker.json) · [Differential cases](crc32-workers-verify.json).
