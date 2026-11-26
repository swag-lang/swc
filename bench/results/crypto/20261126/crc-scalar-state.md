# Scalar CRC state and short CRC-64 folding

CRC-32 and CRC-64 carry scalar state through short updates. An independent
carry-less fold handles CRC-64 inputs at the existing 64-byte threshold.
All three focused release tests passed in native and JIT, including runs
with PCLMUL forced off. The checksum references matched on 132 extra empty
and unaligned messages.

The common process CPU-time comparison measured the following paired speedups
from the preceding Swag implementation on AMD EPYC 9V74.

| Operation | Bytes | Before GB/s | After GB/s | Speedup (95% CI) |
| --- | ---: | ---: | ---: | ---: |
| crc32 | 8 | 0.87 | 1.41 | 1.61 [0.427, 1.7] |
| crc32 | 16 | 1.48 | 1.84 | 1.23 [1.2, 1.36] |
| crc32 | 64 | 2.74 | 2.89 | 1.06 [1.03, 1.1] |
| crc32 | 1048576 | 14 | 14.3 | 1.01 [0.999, 1.06] |
| crc64-ecma | 8 | 0.788 | 1.28 | 1.63 [1.57, 1.85] |
| crc64-ecma | 16 | 1.3 | 1.84 | 1.41 [1.26, 1.59] |
| crc64-ecma | 64 | 3 | 3.97 | 1.34 [1.27, 1.36] |
| crc64-ecma | 79 | 1.84 | 2.1 | 1.14 [1.12, 1.18] |
| crc64-ecma | 1048576 | 14 | 13.9 | 1.01 [0.735, 1.07] |
| crc64-iso | 8 | 0.775 | 1.17 | 1.5 [1.48, 1.57] |
| crc64-iso | 16 | 1.28 | 1.85 | 1.44 [1.37, 1.48] |
| crc64-iso | 64 | 2.92 | 4.29 | 1.47 [1.44, 1.49] |
| crc64-iso | 79 | 1.79 | 2.16 | 1.2 [1.17, 1.41] |
| crc64-iso | 1048576 | 14.3 | 14.4 | 1 [0.933, 1.01] |
| crc64-xz | 8 | 0.8 | 1.31 | 1.64 [1.6, 1.64] |
| crc64-xz | 16 | 1.38 | 1.87 | 1.35 [1.28, 1.38] |
| crc64-xz | 64 | 2.93 | 4.31 | 1.46 [1.39, 1.5] |
| crc64-xz | 79 | 1.79 | 2.19 | 1.24 [1.07, 1.29] |
| crc64-xz | 1048576 | 14.3 | 14.4 | 0.998 [0.991, 1.01] |

A separate two-part streaming check measured 1.19–1.32x for 128-byte CRC-64
and 0.98x (95% CI 0.943–0.992x) for 1 KiB GO-ISO. The other selected streaming
controls were close to parity.

[CRC-32 trials](crc32-state.json) · [CRC-64 trials](crc64-state.json) ·
[CRC-64 streaming trials](crc64-state-streaming.json).
