# Cumulative public-key comparison

The saved original native Release build uses source `d9bfeae85f`. The current
native Release library source is `fc9bfd08a9`, built with the compiler through
`580d8cc4b7`. Fifteen process CPU-time trials ran on AMD EPYC 9V74 CPU 4.
The reference driver ran OpenSSL 3.5.7, 3.5.9 and 4.1.0. The comparison
selects the highest measured OpenSSL median for each profile. All six
profiles produced byte-identical public keys, shared secrets or signatures
in every measured repetition.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| x25519-public | 32 | 0 | baseline | OpenSSL4.1 | ops/s | 719 | 3.27e+04 | 0.0219 [0.0216, 0.0225] |
| x25519-public | 32 | 0 | fc9bfd08a9 | OpenSSL4.1 | ops/s | 3.82e+04 | 3.27e+04 | 1.16 [1.14, 1.18] |
| x25519-public | 32 | 0 | fc9bfd08a9 | baseline | ops/s | 3.82e+04 | 719 | 53 [51.9, 53.5] |
| x25519-shared | 32 | 0 | baseline | OpenSSL4.1 | ops/s | 723 | 1.62e+04 | 0.0446 [0.0441, 0.045] |
| x25519-shared | 32 | 0 | fc9bfd08a9 | OpenSSL4.1 | ops/s | 1.4e+04 | 1.62e+04 | 0.862 [0.857, 0.868] |
| x25519-shared | 32 | 0 | fc9bfd08a9 | baseline | ops/s | 1.4e+04 | 723 | 19.3 [19.3, 19.5] |
| ed25519-public | 32 | 0 | baseline | OpenSSL4.1 | ops/s | 392 | 3.24e+04 | 0.0121 [0.012, 0.0122] |
| ed25519-public | 32 | 0 | fc9bfd08a9 | OpenSSL4.1 | ops/s | 3.77e+04 | 3.24e+04 | 1.17 [1.15, 1.18] |
| ed25519-public | 32 | 0 | fc9bfd08a9 | baseline | ops/s | 3.77e+04 | 392 | 95.8 [95.3, 96.8] |
| ed25519-sign | 64 | 0 | baseline | OpenSSL3.5.9 | ops/s | 192 | 1.59e+04 | 0.0122 [0.0119, 0.0125] |
| ed25519-sign | 64 | 0 | fc9bfd08a9 | OpenSSL3.5.9 | ops/s | 1.81e+04 | 1.59e+04 | 1.14 [1.13, 1.15] |
| ed25519-sign | 64 | 0 | fc9bfd08a9 | baseline | ops/s | 1.81e+04 | 192 | 93.8 [91.4, 95.6] |
| ed25519-sign | 4096 | 0 | baseline | OpenSSL4.1 | ops/s | 193 | 1.39e+04 | 0.0139 [0.0137, 0.0141] |
| ed25519-sign | 4096 | 0 | fc9bfd08a9 | OpenSSL4.1 | ops/s | 1.47e+04 | 1.39e+04 | 1.07 [1.05, 1.08] |
| ed25519-sign | 4096 | 0 | fc9bfd08a9 | baseline | ops/s | 1.47e+04 | 193 | 76.8 [74.6, 77.4] |
| p256-public | 32 | 0 | baseline | OpenSSL3.5.9 | ops/s | 670 | 9.4e+04 | 0.0072 [0.00709, 0.00724] |
| p256-public | 32 | 0 | fc9bfd08a9 | OpenSSL3.5.9 | ops/s | 1.39e+04 | 9.4e+04 | 0.148 [0.146, 0.149] |
| p256-public | 32 | 0 | fc9bfd08a9 | baseline | ops/s | 1.39e+04 | 670 | 20.5 [20.4, 20.9] |

[Raw paired measurements](asymmetric-cumulative.json) · [Initial baseline](asymmetric-baseline.md) · [Curve25519 generator comparisons](x25519-generator-comb.md) · [Reproduction](../../../workloads/crypto/README.md)
