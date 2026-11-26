# CRC-32 on short byte slices

Slicing by eight handles short messages and the scalar tail of the folded path. The
eight lookup slices are generated at compile time. The focused Core CRC-32 test passed
in native Release. The common workload checked its full output against libdeflate 1.26
and zlib 1.3.1, including 21 additional unaligned cases.

The pinned process CPU-time comparison on AMD EPYC 9V74 found the largest gains below
the 64-byte threshold. At 64 bytes to 1 MiB the confidence intervals included parity
against the preceding Swag implementation. Rates are decimal GB/s.

| Bytes | Before | After | libdeflate | Paired speedup (95% CI) |
| ---: | ---: | ---: | ---: | ---: |
| 8 | 0.703 | 0.874 | 1.28 | 1.24 [1.18, 1.26] |
| 16 | 0.718 | 1.50 | 2.41 | 2.08 [1.31, 2.26] |
| 31 | 0.614 | 1.51 | 4.46 | 2.46 [2.35, 2.54] |
| 63 | 0.491 | 1.63 | 8.97 | 3.33 [3.01, 3.46] |
| 1048576 | 14.1 | 14.3 | 56.9 | 1.01 [0.961, 1.04] |

[Raw trials and output fingerprints](crc32-short.json).
