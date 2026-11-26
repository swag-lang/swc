# Final integrated hash, CRC and crypto comparison

This campaign ran the original 19 operations on the same pinned CPU, using the
original native Release baseline binary from revision `d9bfeae85f` and a native
Release build of `10bf72c650`. It includes changes through that revision.

The AMD EPYC 9V74 workload used CPU 4 and 13 interleaved paired
process CPU-time trials per case, calibrated to 25 ms each. The full byte
output matched across builds and references for all 76 algorithm and size
combinations, including every measured round. Each speed ratio against the
starting point either favored the final build or included parity. The table
gives 1 MiB results.

| Algorithm | Baseline GB/s | Swag GB/s | Best measured reference | Reference GB/s | Swag / baseline (95% CI) | Swag / reference (95% CI) |
| --- | ---: | ---: | --- | ---: | ---: | ---: |
| adler32 | 10.4 | 37.4 | libdeflate | 87.4 | 3.57 [3.54, 3.62] | 0.426 [0.423, 0.431] |
| crc32 | 14.2 | 41.8 | libdeflate | 56.6 | 2.94 [2.91, 3.05] | 0.738 [0.727, 0.752] |
| crc64-ecma | 0.041 | 19.6 | ISA-L | 51.6 | 479 [474, 483] | 0.379 [0.376, 0.385] |
| crc64-iso | 0.0346 | 41.4 | ISA-L | 56.2 | 1.19e+03 [1.19e+03, 1.21e+03] | 0.737 [0.724, 0.747] |
| crc64-xz | 0.0368 | 42.2 | ISA-L | 57.3 | 1.15e+03 [1.14e+03, 1.16e+03] | 0.738 [0.728, 0.742] |
| md5 | 0.452 | 0.707 | OpenSSL | 0.8 | 1.57 [1.53, 1.58] | 0.887 [0.872, 0.891] |
| sha1 | 0.242 | 1.9 | OpenSSL4.1 | 1.9 | 7.86 [7.83, 7.91] | 0.998 [0.994, 1.01] |
| sha224 | 0.216 | 1.77 | OpenSSL3.5.9 | 1.79 | 8.21 [8.07, 8.25] | 0.994 [0.985, 1] |
| sha256 | 0.217 | 1.77 | OpenSSL4.1 | 1.78 | 8.15 [8.1, 8.21] | 0.993 [0.989, 0.997] |
| sha384 | 0.302 | 0.647 | OpenSSL3.5.9 | 0.863 | 2.14 [2.04, 2.16] | 0.749 [0.707, 0.757] |
| sha512 | 0.301 | 0.649 | OpenSSL3.5.9 | 0.865 | 2.16 [2.08, 2.24] | 0.751 [0.726, 0.758] |
| sha3-256 | 0.11 | 0.45 | OpenSSL | 0.5 | 4.08 [4.02, 4.11] | 0.896 [0.885, 0.899] |
| blake2b-512 | 0.487 | 0.694 | libsodium | 1.03 | 1.42 [1.38, 1.45] | 0.675 [0.661, 0.681] |
| blake2s-256 | 0.308 | 0.415 | OpenSSL3.5.9 | 0.612 | 1.34 [1.32, 1.39] | 0.678 [0.663, 0.687] |
| blake3 | 0.404 | 1.64 | BLAKE3 C | 6.34 | 4.08 [3.92, 4.25] | 0.26 [0.247, 0.279] |
| poly1305 | 0.229 | 4.84 | OpenSSL4.1 | 12.7 | 21.1 [21, 21.5] | 0.382 [0.38, 0.389] |
| chacha20 | 0.856 | 1.34 | OpenSSL4.1 | 5.26 | 1.56 [1.54, 1.57] | 0.255 [0.251, 0.258] |
| chacha20-poly1305 | 0.177 | 1.03 | OpenSSL4.1 | 3.66 | 5.79 [5.49, 6.04] | 0.283 [0.278, 0.285] |
| aes-256-gcm | 0.00056 | 3.94 | OpenSSL | 10.3 | 6.96e+03 [6.93e+03, 7.14e+03] | 0.381 [0.378, 0.397] |

References were OpenSSL 3.5.7, OpenSSL 3.5.9, OpenSSL 4.1.0, official BLAKE3 C 1.8.7, libdeflate 1.26, zlib 1.3.1,
ISA-L 2.32.1, liblzma 5.8.1, libb2 0.98.1 and libsodium 1.0.22. The table uses the strongest comparator measured
by this workload. Worker scaling, additional references and hardware-disabled
runs are in the independent campaigns.

The separately reproduced CRC-64/ECMA-182 checkpoint variation is
documented with the [linked code placement measurements](crc64-ecma-code-placement.md).

[All measured sizes](integrated-final-sizes.md) · [Raw paired trials](integrated-final.json) · [Integrated validation](integrated-validation-final.md) · [Reproduction](../../../workloads/crypto/README.md).
