# AES-KW and AES-KWP inverse round chain

AES-NI unwrapping keeps the integrity value in a vector across successive decryptions. A
lane-local XOR applies the RFC 3394 counter before each block decryption. The unwrap path
clears the vector after saving the final integrity value. AES-KW and AES-KWP both use this
loop before checking integrity and releasing the recovered key.

At 16 bytes, median throughput rose from 0.0332 to 0.0394 GB/s for AES-KW and from 0.0344
to 0.0394 GB/s for AES-KWP. At 4 KiB, the paired gains were 1.14× and 1.11×. The wrapping
controls stayed within roughly 2% of the previous measurements.

## Method

Both builds use the same Release compiler, standard-library sources and harness, with only
`aeskeywrap.swg` replaced in the candidate. Trials compare the [previous packed rounds](aes-key-wrap.md),
the vector chain and the OpenSSL 4.1.0 EVP provider. Each implementation uses one worker
pinned to CPU 2 of an AMD EPYC 9V74. The harness prepares valid wrapped inputs before timing,
interleaves 11 trials targeting 17 ms of process CPU time per implementation and measures the
original unwrapped key-data length. [Workload and build instructions](../../../workloads/crypto/README.md)

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| aes-256-kw | 16 | 0 | packed | OpenSSL | GB/s | 0.0393 | 0.0101 | 3.92 [3.81, 4.01] |
| aes-256-kw | 16 | 0 | vector-chain | OpenSSL | GB/s | 0.0399 | 0.0101 | 3.97 [3.84, 4.04] |
| aes-256-kw | 16 | 0 | vector-chain | packed | GB/s | 0.0399 | 0.0393 | 1.02 [0.972, 1.06] |
| aes-256-kw | 64 | 0 | packed | OpenSSL | GB/s | 0.0509 | 0.0103 | 4.97 [4.38, 5.5] |
| aes-256-kw | 64 | 0 | vector-chain | OpenSSL | GB/s | 0.0501 | 0.0103 | 4.92 [4.69, 5.36] |
| aes-256-kw | 64 | 0 | vector-chain | packed | GB/s | 0.0501 | 0.0509 | 0.98 [0.964, 1.03] |
| aes-256-kw | 4096 | 0 | packed | OpenSSL | GB/s | 0.0575 | 0.0107 | 5.35 [5.29, 5.41] |
| aes-256-kw | 4096 | 0 | vector-chain | OpenSSL | GB/s | 0.0568 | 0.0107 | 5.32 [5.2, 5.36] |
| aes-256-kw | 4096 | 0 | vector-chain | packed | GB/s | 0.0568 | 0.0575 | 0.986 [0.977, 1] |
| aes-256-kw-unwrap | 16 | 0 | packed | OpenSSL | GB/s | 0.0332 | 0.00678 | 4.88 [4.39, 5.15] |
| aes-256-kw-unwrap | 16 | 0 | vector-chain | OpenSSL | GB/s | 0.0394 | 0.00678 | 5.84 [5.68, 5.91] |
| aes-256-kw-unwrap | 16 | 0 | vector-chain | packed | GB/s | 0.0394 | 0.0332 | 1.18 [1.14, 1.32] |
| aes-256-kw-unwrap | 64 | 0 | packed | OpenSSL | GB/s | 0.0473 | 0.00726 | 6.55 [6.47, 8.77] |
| aes-256-kw-unwrap | 64 | 0 | vector-chain | OpenSSL | GB/s | 0.0524 | 0.00726 | 7.25 [5.96, 9.31] |
| aes-256-kw-unwrap | 64 | 0 | vector-chain | packed | GB/s | 0.0524 | 0.0473 | 1.1 [0.922, 1.13] |
| aes-256-kw-unwrap | 4096 | 0 | packed | OpenSSL | GB/s | 0.0541 | 0.00744 | 7.28 [7.16, 8.23] |
| aes-256-kw-unwrap | 4096 | 0 | vector-chain | OpenSSL | GB/s | 0.0616 | 0.00744 | 8.27 [8.11, 8.75] |
| aes-256-kw-unwrap | 4096 | 0 | vector-chain | packed | GB/s | 0.0616 | 0.0541 | 1.14 [1.06, 1.2] |
| aes-256-kwp | 16 | 0 | packed | OpenSSL | GB/s | 0.0325 | 0.0101 | 3.35 [3.15, 3.52] |
| aes-256-kwp | 16 | 0 | vector-chain | OpenSSL | GB/s | 0.0335 | 0.0101 | 3.36 [3.13, 3.87] |
| aes-256-kwp | 16 | 0 | vector-chain | packed | GB/s | 0.0335 | 0.0325 | 1.02 [0.968, 1.12] |
| aes-256-kwp | 64 | 0 | packed | OpenSSL | GB/s | 0.048 | 0.0104 | 4.55 [4.07, 4.66] |
| aes-256-kwp | 64 | 0 | vector-chain | OpenSSL | GB/s | 0.0482 | 0.0104 | 4.64 [4.52, 4.86] |
| aes-256-kwp | 64 | 0 | vector-chain | packed | GB/s | 0.0482 | 0.048 | 1.02 [0.983, 1.14] |
| aes-256-kwp | 4096 | 0 | packed | OpenSSL | GB/s | 0.0552 | 0.0104 | 5.26 [5.03, 5.35] |
| aes-256-kwp | 4096 | 0 | vector-chain | OpenSSL | GB/s | 0.0551 | 0.0104 | 5.38 [5.15, 5.45] |
| aes-256-kwp | 4096 | 0 | vector-chain | packed | GB/s | 0.0551 | 0.0552 | 1.01 [0.965, 1.03] |
| aes-256-kwp-unwrap | 16 | 0 | packed | OpenSSL | GB/s | 0.0344 | 0.0068 | 5.1 [4.93, 5.21] |
| aes-256-kwp-unwrap | 16 | 0 | vector-chain | OpenSSL | GB/s | 0.0394 | 0.0068 | 5.73 [5.35, 5.94] |
| aes-256-kwp-unwrap | 16 | 0 | vector-chain | packed | GB/s | 0.0394 | 0.0344 | 1.15 [1.06, 1.17] |
| aes-256-kwp-unwrap | 64 | 0 | packed | OpenSSL | GB/s | 0.047 | 0.00728 | 6.51 [6.27, 6.68] |
| aes-256-kwp-unwrap | 64 | 0 | vector-chain | OpenSSL | GB/s | 0.0529 | 0.00728 | 7.31 [7.01, 7.95] |
| aes-256-kwp-unwrap | 64 | 0 | vector-chain | packed | GB/s | 0.0529 | 0.047 | 1.12 [1.1, 1.16] |
| aes-256-kwp-unwrap | 4096 | 0 | packed | OpenSSL | GB/s | 0.054 | 0.00737 | 7.29 [7.16, 7.46] |
| aes-256-kwp-unwrap | 4096 | 0 | vector-chain | OpenSSL | GB/s | 0.0601 | 0.00737 | 8.16 [7.9, 8.49] |
| aes-256-kwp-unwrap | 4096 | 0 | vector-chain | packed | GB/s | 0.0601 | 0.054 | 1.11 [1.09, 1.16] |

## Verification

The external comparison matched complete OpenSSL outputs for 40 unaligned inputs in each of
the four directions. A dedicated AES-KWP comparison matched 56 inputs per direction around
the one-block padding boundary, including lengths 1, 7, 8 and 9. The three focused Core cases
passed in Release and Release-safe both on the host and under QEMU with AES and PCLMUL
disabled.

[Raw paired trials](aes-key-unwrap-chain.json) · [KW and KWP verification](aes-key-unwrap-chain-verification.json) · [KWP boundary verification](aes-key-unwrap-chain-padded-verification.json)
