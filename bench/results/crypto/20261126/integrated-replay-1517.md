# Integrated 19-operation replay with OpenSSL 4.1 and 3.5.9

This campaign ran the original 19 operations on the same pinned CPU, using the
original native Release baseline binary from revision `d9bfeae85f` and a native
Release build of `8dbd5b55bb`. It includes changes through that revision.

The AMD EPYC 9V74 workload used CPU 4 and 13 interleaved paired
process CPU-time trials per case, calibrated to 25 ms each. The full byte
output matched across builds and references for all 76 algorithm and size
combinations, including every measured round. The table gives 1 MiB results.

| Algorithm | Baseline GB/s | Swag GB/s | Best measured reference | Reference GB/s | Swag / baseline (95% CI) | Swag / reference (95% CI) |
| --- | ---: | ---: | --- | ---: | ---: | ---: |
| adler32 | 10.5 | 32.3 | libdeflate | 87.3 | 3.09 [2.97, 3.1] | 0.362 [0.352, 0.373] |
| crc32 | 14.1 | 24.4 | libdeflate | 57.1 | 1.7 [1.58, 1.78] | 0.428 [0.397, 0.434] |
| crc64-ecma | 0.0403 | 14 | ISA-L | 51.5 | 347 [340, 350] | 0.271 [0.265, 0.274] |
| crc64-iso | 0.0343 | 23.6 | ISA-L | 54.7 | 695 [675, 706] | 0.431 [0.41, 0.461] |
| crc64-xz | 0.0345 | 24.1 | ISA-L | 51.8 | 669 [603, 710] | 0.446 [0.432, 0.508] |
| md5 | 0.447 | 0.694 | OpenSSL4.1 | 0.785 | 1.58 [1.53, 1.81] | 0.884 [0.866, 0.893] |
| sha1 | 0.223 | 1.88 | OpenSSL3.5.9 | 1.87 | 8.55 [7.82, 13.3] | 1.01 [0.987, 1.05] |
| sha224 | 0.212 | 1.74 | OpenSSL | 1.77 | 8.17 [7.93, 8.3] | 0.987 [0.97, 1.01] |
| sha256 | 0.212 | 1.72 | OpenSSL4.1 | 1.75 | 8.14 [8.04, 8.45] | 0.983 [0.976, 0.998] |
| sha384 | 0.297 | 0.637 | OpenSSL4.1 | 0.85 | 2.13 [1.94, 2.2] | 0.75 [0.727, 0.762] |
| sha512 | 0.297 | 0.641 | OpenSSL4.1 | 0.854 | 2.16 [2.09, 2.18] | 0.748 [0.705, 0.764] |
| sha3-256 | 0.11 | 0.447 | OpenSSL | 0.498 | 4.06 [4, 4.07] | 0.895 [0.884, 0.907] |
| blake2b-512 | 0.491 | 0.621 | OpenSSL4.1 | 1 | 1.27 [1.2, 1.29] | 0.617 [0.608, 0.641] |
| blake2s-256 | 0.312 | 0.364 | OpenSSL3.5.9 | 0.623 | 1.17 [1.08, 1.18] | 0.587 [0.519, 0.594] |
| blake3 | 0.405 | 1.5 | BLAKE3 C | 6.36 | 3.87 [3.03, 4.02] | 0.242 [0.193, 0.253] |
| poly1305 | 0.227 | 2.81 | OpenSSL3.5.9 | 12.5 | 12.2 [11.9, 12.9] | 0.23 [0.209, 0.235] |
| chacha20 | 0.814 | 1.29 | OpenSSL | 5.09 | 1.54 [1.1, 1.63] | 0.256 [0.239, 0.27] |
| chacha20-poly1305 | 0.179 | 0.903 | OpenSSL3.5.9 | 3.68 | 5.01 [4.88, 5.11] | 0.246 [0.24, 0.249] |
| aes-256-gcm | 0.000546 | 3.86 | OpenSSL4.1 | 10.2 | 7.07e+03 [6.91e+03, 7.28e+03] | 0.379 [0.378, 0.392] |

References were OpenSSL 3.5.7, OpenSSL 3.5.9, OpenSSL 4.1.0, official BLAKE3 C 1.8.7, libdeflate 1.26, zlib 1.3.1,
ISA-L 2.32.1 and liblzma 5.8.1. The table uses the strongest comparator measured
by this workload. Worker scaling, additional references and hardware-disabled
runs are in the independent campaigns.

[All measured sizes](integrated-replay-1517-sizes.md) · [Raw paired trials](integrated-replay-1517.json) · [Reproduction](../../../workloads/crypto/README.md).
