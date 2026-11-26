# Integrated Core crypto replay at 16:19 CET

This campaign ran the original 19 operations on the same pinned CPU, using the
original native Release baseline binary from revision `d9bfeae85f` and a native
Release build of `bd4cfab5c1`. It includes changes through that revision.

The AMD EPYC 9V74 workload used CPU 4 and 13 interleaved paired
process CPU-time trials per case, calibrated to 25 ms each. The full byte
output matched across builds and references for all 76 algorithm and size
combinations, including every measured round. The table gives 1 MiB results.

| Algorithm | Baseline GB/s | Swag GB/s | Best measured reference | Reference GB/s | Swag / baseline (95% CI) | Swag / reference (95% CI) |
| --- | ---: | ---: | --- | ---: | ---: | ---: |
| adler32 | 9.85 | 30.8 | libdeflate | 86 | 3.09 [2.88, 3.16] | 0.367 [0.339, 0.373] |
| crc32 | 14.3 | 41.9 | libdeflate | 56.5 | 2.93 [2.89, 2.98] | 0.741 [0.716, 0.751] |
| crc64-ecma | 0.041 | 23 | ISA-L | 51.7 | 564 [549, 567] | 0.445 [0.433, 0.448] |
| crc64-iso | 0.0348 | 42.2 | ISA-L | 57 | 1.22e+03 [1.2e+03, 1.23e+03] | 0.741 [0.737, 0.745] |
| crc64-xz | 0.0366 | 42.1 | ISA-L | 56.8 | 1.15e+03 [1.14e+03, 1.17e+03] | 0.739 [0.731, 0.759] |
| md5 | 0.44 | 0.686 | OpenSSL | 0.764 | 1.57 [1.52, 1.71] | 0.889 [0.857, 0.95] |
| sha1 | 0.229 | 1.86 | OpenSSL | 1.88 | 7.94 [7.7, 9.79] | 1 [0.937, 1.02] |
| sha224 | 0.213 | 1.75 | OpenSSL4.1 | 1.77 | 8.15 [7.85, 8.52] | 0.989 [0.93, 0.998] |
| sha256 | 0.214 | 1.75 | OpenSSL3.5.9 | 1.77 | 8.18 [7.93, 8.38] | 0.984 [0.96, 1.02] |
| sha384 | 0.299 | 0.642 | OpenSSL3.5.9 | 0.856 | 2.16 [2.11, 2.18] | 0.749 [0.738, 0.76] |
| sha512 | 0.3 | 0.65 | OpenSSL3.5.9 | 0.859 | 2.18 [2.14, 2.23] | 0.754 [0.747, 0.775] |
| sha3-256 | 0.109 | 0.44 | OpenSSL | 0.494 | 4.01 [3.52, 4.13] | 0.888 [0.766, 0.908] |
| blake2b-512 | 0.484 | 0.666 | OpenSSL4.1 | 1.01 | 1.37 [1.35, 1.46] | 0.662 [0.659, 0.67] |
| blake2s-256 | 0.311 | 0.361 | OpenSSL3.5.9 | 0.619 | 1.16 [1.1, 1.18] | 0.586 [0.559, 0.592] |
| blake3 | 0.41 | 1.57 | BLAKE3 C | 6.42 | 3.87 [3.71, 3.9] | 0.244 [0.241, 0.256] |
| poly1305 | 0.226 | 3.25 | OpenSSL4.1 | 12.6 | 14.4 [14.1, 14.9] | 0.259 [0.254, 0.263] |
| chacha20 | 0.845 | 1.33 | OpenSSL | 5.21 | 1.58 [1.54, 1.62] | 0.255 [0.234, 0.259] |
| chacha20-poly1305 | 0.18 | 0.95 | OpenSSL3.5.9 | 3.7 | 5.28 [5.21, 5.71] | 0.257 [0.232, 0.258] |
| aes-256-gcm | 0.000555 | 3.91 | OpenSSL | 10.3 | 7.05e+03 [6.83e+03, 7.16e+03] | 0.377 [0.366, 0.39] |

References were OpenSSL 3.5.7, OpenSSL 3.5.9, OpenSSL 4.1.0, official BLAKE3 C 1.8.7, libdeflate 1.26, zlib 1.3.1,
ISA-L 2.32.1, liblzma 5.8.1. The table uses the strongest comparator measured
by this workload. Worker scaling, additional references and hardware-disabled
runs are in the independent campaigns.

[All measured sizes](integrated-replay-1619-sizes.md) · [Raw paired trials](integrated-replay-1619.json) · [Reproduction](../../../workloads/crypto/README.md).
