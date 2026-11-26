# Integrated comparison on the original 19 operations

This campaign ran the original 19 operations on the same pinned CPU, using the
original native Release baseline binary from revision `d9bfeae85f` and a native
Release build of `2b0d102d16`. It includes changes through that revision.

The AMD EPYC 9V74 workload used CPU 4 and 13 interleaved paired
process CPU-time trials per case, calibrated to 25 ms each. The full byte
output matched across builds and references for all 76 algorithm and size
combinations, including every measured round. The table gives 1 MiB results.

| Algorithm | Baseline GB/s | Swag GB/s | Best measured reference | Reference GB/s | Swag / baseline (95% CI) | Swag / reference (95% CI) |
| --- | ---: | ---: | --- | ---: | ---: | ---: |
| adler32 | 10.3 | 31.7 | libdeflate | 86.9 | 3.06 [2.97, 3.13] | 0.365 [0.354, 0.376] |
| crc32 | 13.9 | 13.8 | libdeflate | 54.3 | 0.997 [0.958, 1.08] | 0.253 [0.249, 0.26] |
| crc64-ecma | 0.0409 | 14.3 | ISA-L | 52 | 349 [347, 370] | 0.276 [0.27, 0.279] |
| crc64-iso | 0.0343 | 14.2 | ISA-L | 56.4 | 413 [403, 418] | 0.251 [0.234, 0.263] |
| crc64-xz | 0.0363 | 14.1 | ISA-L | 56.4 | 390 [382, 395] | 0.251 [0.246, 0.256] |
| md5 | 0.453 | 0.51 | OpenSSL | 0.799 | 1.13 [1.12, 1.15] | 0.638 [0.626, 0.668] |
| sha1 | 0.239 | 1.89 | OpenSSL | 1.88 | 7.89 [7.74, 7.98] | 1 [0.972, 1.02] |
| sha224 | 0.212 | 1.75 | OpenSSL | 1.76 | 8.2 [7.98, 8.32] | 0.989 [0.972, 1.01] |
| sha256 | 0.21 | 1.73 | OpenSSL | 1.74 | 8.22 [8.13, 8.39] | 0.991 [0.978, 1.02] |
| sha384 | 0.295 | 0.526 | OpenSSL | 0.84 | 1.77 [1.73, 1.82] | 0.628 [0.614, 0.635] |
| sha512 | 0.297 | 0.527 | OpenSSL | 0.842 | 1.78 [1.73, 1.81] | 0.626 [0.608, 0.642] |
| sha3-256 | 0.109 | 0.442 | OpenSSL | 0.493 | 4.07 [4, 4.14] | 0.898 [0.892, 0.911] |
| blake2b-512 | 0.468 | 0.569 | OpenSSL | 0.929 | 1.21 [1.19, 1.26] | 0.622 [0.597, 0.631] |
| blake2s-256 | 0.312 | 0.344 | OpenSSL | 0.552 | 1.1 [1.05, 1.11] | 0.62 [0.581, 0.629] |
| blake3 | 0.403 | 0.782 | BLAKE3 C | 6.34 | 2.02 [1.89, 2.07] | 0.127 [0.115, 0.136] |
| poly1305 | 0.226 | 1.89 | OpenSSL | 12.3 | 8.34 [8.19, 8.47] | 0.153 [0.15, 0.155] |
| chacha20 | 0.846 | 1.14 | OpenSSL | 5.02 | 1.38 [1.25, 1.4] | 0.228 [0.212, 0.238] |
| chacha20-poly1305 | 0.179 | 0.726 | OpenSSL | 3.67 | 4.05 [4.01, 4.47] | 0.198 [0.196, 0.2] |
| aes-256-gcm | 0.000556 | 3.32 | OpenSSL | 10.3 | 5.96e+03 [5.88e+03, 6.11e+03] | 0.322 [0.317, 0.324] |

References were OpenSSL 3.5.7, official BLAKE3 C 1.8.7, libdeflate 1.26, zlib 1.3.1,
ISA-L 2.32.1 and liblzma 5.8.1. The table uses the strongest comparator measured
by this workload. Worker scaling, additional references and hardware-disabled
runs are in the independent campaigns.

[All measured sizes](integrated-checkpoint-sizes.md) · [Raw paired trials](integrated-checkpoint.json) · [Reproduction](../../../workloads/crypto/README.md).
