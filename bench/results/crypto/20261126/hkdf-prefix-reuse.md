# Reusable HKDF expansion prefixes

All four SHA-2 HKDF variants reuse the initialized HMAC inner and outer
states for expansion. A single output block uses a direct HMAC. That path
absorbs all inputs before writing output, including when output overlaps
`info`. Multi-block expansion copies overlapping `info` before writing.

Both builds used the same native Release compiler and library baseline.
The common workload used 15 paired process CPU-time trials on AMD EPYC
9V74 CPU 4, with a 25 ms target. The number of bytes denotes output length.
All 16 timed profiles and 48 unaligned, empty and partial external cases
matched OpenSSL 3.5.7 byte for byte.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| hkdf-sha224 | 28 | 0 | prefix-reuse | OpenSSL | ops/s | 1.55e+06 | 5.39e+05 | 2.9 [2.8, 2.93] |
| hkdf-sha224 | 28 | 0 | prefix-reuse | prefix-per-block | ops/s | 1.55e+06 | 1.55e+06 | 1 [0.972, 1.02] |
| hkdf-sha224 | 112 | 0 | prefix-reuse | OpenSSL | ops/s | 7.66e+05 | 4.2e+05 | 1.81 [1.75, 1.96] |
| hkdf-sha224 | 112 | 0 | prefix-reuse | prefix-per-block | ops/s | 7.66e+05 | 5.95e+05 | 1.3 [1.25, 1.35] |
| hkdf-sha224 | 896 | 0 | prefix-reuse | OpenSSL | ops/s | 1.45e+05 | 1.34e+05 | 1.08 [1.06, 1.11] |
| hkdf-sha224 | 896 | 0 | prefix-reuse | prefix-per-block | ops/s | 1.45e+05 | 8.69e+04 | 1.65 [1.62, 1.75] |
| hkdf-sha224 | 7140 | 0 | prefix-reuse | OpenSSL | ops/s | 1.94e+04 | 2.08e+04 | 0.927 [0.904, 1.1] |
| hkdf-sha224 | 7140 | 0 | prefix-reuse | prefix-per-block | ops/s | 1.94e+04 | 1.13e+04 | 1.71 [1.66, 1.81] |
| hkdf-sha256 | 32 | 0 | prefix-reuse | OpenSSL | ops/s | 1.35e+06 | 5.45e+05 | 2.46 [2.42, 2.55] |
| hkdf-sha256 | 32 | 0 | prefix-reuse | prefix-per-block | ops/s | 1.35e+06 | 1.33e+06 | 0.991 [0.98, 1.06] |
| hkdf-sha256 | 128 | 0 | prefix-reuse | OpenSSL | ops/s | 7.07e+05 | 4.28e+05 | 1.65 [1.46, 1.7] |
| hkdf-sha256 | 128 | 0 | prefix-reuse | prefix-per-block | ops/s | 7.07e+05 | 5.11e+05 | 1.36 [1.25, 1.41] |
| hkdf-sha256 | 1024 | 0 | prefix-reuse | OpenSSL | ops/s | 1.44e+05 | 1.4e+05 | 1.05 [1, 1.08] |
| hkdf-sha256 | 1024 | 0 | prefix-reuse | prefix-per-block | ops/s | 1.44e+05 | 7.77e+04 | 1.87 [1.77, 2] |
| hkdf-sha256 | 8160 | 0 | prefix-reuse | OpenSSL | ops/s | 1.98e+04 | 2.18e+04 | 0.9 [0.869, 0.929] |
| hkdf-sha256 | 8160 | 0 | prefix-reuse | prefix-per-block | ops/s | 1.98e+04 | 1.02e+04 | 1.95 [1.86, 2.04] |
| hkdf-sha384 | 48 | 0 | prefix-reuse | OpenSSL | ops/s | 4.26e+05 | 3.37e+05 | 1.25 [1.23, 1.3] |
| hkdf-sha384 | 48 | 0 | prefix-reuse | prefix-per-block | ops/s | 4.26e+05 | 4.16e+05 | 1.02 [0.998, 1.03] |
| hkdf-sha384 | 192 | 0 | prefix-reuse | OpenSSL | ops/s | 2.46e+05 | 2.4e+05 | 1.03 [1, 1.04] |
| hkdf-sha384 | 192 | 0 | prefix-reuse | prefix-per-block | ops/s | 2.46e+05 | 1.73e+05 | 1.42 [1.38, 1.45] |
| hkdf-sha384 | 1536 | 0 | prefix-reuse | OpenSSL | ops/s | 5.02e+04 | 6.43e+04 | 0.778 [0.755, 0.784] |
| hkdf-sha384 | 1536 | 0 | prefix-reuse | prefix-per-block | ops/s | 5.02e+04 | 2.63e+04 | 1.88 [1.86, 1.94] |
| hkdf-sha384 | 12240 | 0 | prefix-reuse | OpenSSL | ops/s | 6.71e+03 | 9.39e+03 | 0.726 [0.704, 0.734] |
| hkdf-sha384 | 12240 | 0 | prefix-reuse | prefix-per-block | ops/s | 6.71e+03 | 3.41e+03 | 1.96 [1.92, 2] |
| hkdf-sha512 | 64 | 0 | prefix-reuse | OpenSSL | ops/s | 4.24e+05 | 3.31e+05 | 1.27 [1.2, 1.31] |
| hkdf-sha512 | 64 | 0 | prefix-reuse | prefix-per-block | ops/s | 4.24e+05 | 4.19e+05 | 0.992 [0.964, 1.02] |
| hkdf-sha512 | 256 | 0 | prefix-reuse | OpenSSL | ops/s | 2.05e+05 | 2.12e+05 | 0.97 [0.959, 0.994] |
| hkdf-sha512 | 256 | 0 | prefix-reuse | prefix-per-block | ops/s | 2.05e+05 | 1.54e+05 | 1.33 [1.3, 1.35] |
| hkdf-sha512 | 2048 | 0 | prefix-reuse | OpenSSL | ops/s | 3.66e+04 | 4.9e+04 | 0.747 [0.728, 0.755] |
| hkdf-sha512 | 2048 | 0 | prefix-reuse | prefix-per-block | ops/s | 3.66e+04 | 2.24e+04 | 1.63 [1.6, 1.64] |
| hkdf-sha512 | 16320 | 0 | prefix-reuse | OpenSSL | ops/s | 4.68e+03 | 6.63e+03 | 0.707 [0.692, 0.724] |
| hkdf-sha512 | 16320 | 0 | prefix-reuse | prefix-per-block | ops/s | 4.68e+03 | 2.79e+03 | 1.68 [1.65, 1.7] |

One-block profiles were within the paired parity intervals. Four blocks
improved 1.30–1.42×, 32 blocks improved 1.63–1.88×, and the maximum
255 blocks improved 1.68–1.96×. The four Core HKDF cases passed in native
Release and Release-safe, including the overlapping `info` cases.

[Raw trials and output fingerprints](hkdf-prefix-reuse.json) · [External verification](hkdf-prefix-reuse-verification.json) · [Reproduction](../../../workloads/crypto/README.md).
