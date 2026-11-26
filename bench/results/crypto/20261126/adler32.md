# Packed Adler-32 byte sums

The packed loop accumulates byte sums and per-position weights across 64-byte spans
before doing a horizontal reduction. The nine native Release Adler-32 and zlib
tests passed. All checksums matched libdeflate 1.26 and zlib 1.3.1.

The [common workload](../../../workloads/crypto/README.md) used 11 paired process CPU-time
samples per size on CPU 0 of the AMD EPYC 9V74. Rates are decimal GB/s.

| Bytes | Before | After | libdeflate | Paired speedup (95% CI) |
| ---: | ---: | ---: | ---: | ---: |
| 16 | 1.8 | 1.98 | 2.7 | 1.1 [1.07, 1.23] |
| 32 | 3.34 | 3.74 | 5.38 | 1.12 [1.1, 1.13] |
| 64 | 5.85 | 6.71 | 11.3 | 1.14 [1.13, 1.29] |
| 128 | 8.05 | 10.6 | 23.8 | 1.31 [1.3, 1.33] |
| 1024 | 10 | 26.3 | 67.6 | 2.58 [1.99, 3.81] |
| 4096 | 10.4 | 30.6 | 94.1 | 2.98 [2.41, 3.47] |
| 65536 | 10.3 | 31.8 | 93.2 | 3.09 [2.46, 3.19] |
| 1048576 | 10.2 | 31 | 84.2 | 3.03 [2.82, 3.1] |

[Raw trials and matching checksum fingerprints](adler32.json).
