# CRC-32 short inputs and bounded SIMD tails

CRC-32 consumes the last two or four scalar bytes with sliced table
steps. The PCLMUL path uses a three-product final reduction and processes
a fractional last block with in-bounds loads. Hardware dispatch becomes
profitable at 36 bytes in the measured short-input path.

The workload used 11 paired native Release process CPU-time rounds on
AMD EPYC 9V74 CPU 2. All outputs matched the external references. The
1 MiB throughput was about 14.3 GB/s, against 56 GB/s for libdeflate.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| crc32 | 1 | 0 | candidate | baseline | GB/s | 0.209 | 0.221 | 0.942 [0.914, 1.54] |
| crc32 | 2 | 0 | candidate | baseline | GB/s | 0.425 | 0.424 | 1 [0.989, 1.01] |
| crc32 | 3 | 0 | candidate | baseline | GB/s | 0.602 | 0.57 | 1.05 [1.03, 1.06] |
| crc32 | 4 | 0 | candidate | baseline | GB/s | 0.837 | 0.669 | 1.24 [1.17, 1.28] |
| crc32 | 5 | 0 | candidate | baseline | GB/s | 1.05 | 0.779 | 1.35 [1.33, 1.38] |
| crc32 | 6 | 0 | candidate | baseline | GB/s | 1.28 | 0.826 | 1.54 [1.51, 1.59] |
| crc32 | 7 | 0 | candidate | baseline | GB/s | 1.35 | 0.937 | 1.43 [1.42, 1.45] |
| crc32 | 8 | 0 | candidate | baseline | GB/s | 1.64 | 1.56 | 1.06 [1.01, 1.17] |
| crc32 | 15 | 0 | candidate | baseline | GB/s | 1.53 | 1.2 | 1.23 [1.21, 1.39] |
| crc32 | 16 | 0 | candidate | baseline | GB/s | 1.85 | 1.9 | 0.993 [0.821, 1] |
| crc32 | 31 | 0 | candidate | baseline | GB/s | 1.88 | 1.6 | 1.18 [1.09, 1.72] |
| crc32 | 32 | 0 | candidate | baseline | GB/s | 1.91 | 1.94 | 0.979 [0.718, 1.02] |
| crc32 | 33 | 0 | candidate | baseline | GB/s | 1.78 | 1.85 | 0.975 [0.889, 1.04] |
| crc32 | 35 | 0 | candidate | baseline | GB/s | 1.83 | 1.82 | 1 [0.947, 1.03] |
| crc32 | 36 | 0 | candidate | baseline | GB/s | 1.9 | 1.78 | 1.07 [0.988, 1.47] |
| crc32 | 40 | 0 | candidate | baseline | GB/s | 2.11 | 1.93 | 1.09 [1.04, 1.81] |
| crc32 | 48 | 0 | candidate | baseline | GB/s | 2.9 | 1.88 | 1.57 [1.5, 1.66] |
| crc32 | 63 | 0 | candidate | baseline | GB/s | 3.32 | 1.84 | 1.82 [1.77, 2.18] |
| crc32 | 64 | 0 | candidate | baseline | GB/s | 3.95 | 2.95 | 1.33 [0.899, 1.38] |
| crc32 | 79 | 0 | candidate | baseline | GB/s | 4.04 | 1.9 | 2.13 [1.48, 2.26] |
| crc32 | 95 | 0 | candidate | baseline | GB/s | 3.86 | 2.16 | 1.81 [1.52, 1.88] |
| crc32 | 128 | 0 | candidate | baseline | GB/s | 6.01 | 5.44 | 1.09 [1.08, 1.13] |
| crc32 | 4096 | 0 | candidate | baseline | GB/s | 14.1 | 13.9 | 0.999 [0.852, 1.02] |
| crc32 | 1048576 | 0 | candidate | baseline | GB/s | 14.3 | 14.2 | 1 [0.98, 1.02] |

The focused suite passed in JIT and native Release, including the
forced-portable cases. Guard pages on both ends checked 516 seeded and
one-shot layouts. An additional tail sweep matched 288 external cases.

[Raw trials and output fingerprints](crc32-padded-tail.json).
