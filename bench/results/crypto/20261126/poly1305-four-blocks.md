# Poly1305 four-block folding

Long Poly1305 updates fold four blocks using consecutive powers of the
key. Short updates and remaining full or partial blocks use the existing
smaller paths. The new authenticated-encryption fixture checks exact
boundaries around dispatch and the trailing blocks.

The common native Release comparison used unaligned input and matched
complete outputs against OpenSSL and libsodium 1.0.22. At 4 MiB standalone
Poly1305 reached 2.88 GB/s from 1.88 GB/s. The 64-byte and 1023-byte
confidence intervals included parity.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| poly1305 | 64 | 1 | four-block | libsodium | GB/s | 0.431 | 1.2 | 0.358 [0.354, 0.446] |
| poly1305 | 64 | 1 | four-block | paired | GB/s | 0.431 | 0.405 | 1.08 [0.994, 1.29] |
| poly1305 | 1023 | 1 | four-block | OpenSSL | GB/s | 1.25 | 4.75 | 0.266 [0.248, 0.277] |
| poly1305 | 1023 | 1 | four-block | paired | GB/s | 1.25 | 1.25 | 1 [0.965, 1.03] |
| poly1305 | 1024 | 1 | four-block | OpenSSL | GB/s | 1.38 | 6.16 | 0.224 [0.216, 0.23] |
| poly1305 | 1024 | 1 | four-block | paired | GB/s | 1.38 | 1.28 | 1.07 [1.03, 1.11] |
| poly1305 | 1072 | 1 | four-block | OpenSSL | GB/s | 1.33 | 5.56 | 0.24 [0.212, 0.25] |
| poly1305 | 1072 | 1 | four-block | paired | GB/s | 1.33 | 1.29 | 1.06 [0.959, 1.15] |
| poly1305 | 1088 | 1 | four-block | OpenSSL | GB/s | 1.39 | 6.08 | 0.229 [0.196, 0.239] |
| poly1305 | 1088 | 1 | four-block | paired | GB/s | 1.39 | 1.26 | 1.11 [0.941, 1.15] |
| poly1305 | 4096 | 1 | four-block | OpenSSL | GB/s | 2.29 | 9.89 | 0.231 [0.219, 0.236] |
| poly1305 | 4096 | 1 | four-block | paired | GB/s | 2.29 | 1.67 | 1.35 [1.33, 1.4] |
| poly1305 | 16384 | 1 | four-block | OpenSSL | GB/s | 2.74 | 11.7 | 0.237 [0.229, 0.25] |
| poly1305 | 16384 | 1 | four-block | paired | GB/s | 2.74 | 1.83 | 1.5 [1.45, 1.54] |
| poly1305 | 4194304 | 1 | four-block | OpenSSL | GB/s | 2.88 | 12.4 | 0.233 [0.228, 0.239] |
| poly1305 | 4194304 | 1 | four-block | paired | GB/s | 2.88 | 1.88 | 1.53 [1.5, 1.58] |
| chacha20-poly1305 | 64 | 1 | four-block | libsodium | GB/s | 0.131 | 0.206 | 0.632 [0.56, 0.701] |
| chacha20-poly1305 | 64 | 1 | four-block | paired | GB/s | 0.131 | 0.125 | 0.997 [0.914, 1.27] |
| chacha20-poly1305 | 1023 | 1 | four-block | OpenSSL | GB/s | 0.467 | 1 | 0.466 [0.436, 0.489] |
| chacha20-poly1305 | 1023 | 1 | four-block | paired | GB/s | 0.467 | 0.469 | 0.997 [0.913, 1.13] |
| chacha20-poly1305 | 1024 | 1 | four-block | OpenSSL | GB/s | 0.559 | 1.27 | 0.442 [0.34, 0.454] |
| chacha20-poly1305 | 1024 | 1 | four-block | paired | GB/s | 0.559 | 0.553 | 0.994 [0.769, 1.05] |
| chacha20-poly1305 | 1072 | 1 | four-block | OpenSSL | GB/s | 0.51 | 1.09 | 0.478 [0.395, 0.517] |
| chacha20-poly1305 | 1072 | 1 | four-block | paired | GB/s | 0.51 | 0.533 | 0.98 [0.786, 1.05] |
| chacha20-poly1305 | 1088 | 1 | four-block | OpenSSL | GB/s | 0.556 | 1.08 | 0.514 [0.423, 0.524] |
| chacha20-poly1305 | 1088 | 1 | four-block | paired | GB/s | 0.556 | 0.547 | 1.01 [0.887, 1.13] |
| chacha20-poly1305 | 4096 | 1 | four-block | OpenSSL | GB/s | 0.81 | 2.51 | 0.321 [0.241, 0.324] |
| chacha20-poly1305 | 4096 | 1 | four-block | paired | GB/s | 0.81 | 0.722 | 1.12 [0.851, 1.18] |
| chacha20-poly1305 | 16384 | 1 | four-block | OpenSSL | GB/s | 0.893 | 3.34 | 0.267 [0.199, 0.27] |
| chacha20-poly1305 | 16384 | 1 | four-block | paired | GB/s | 0.893 | 0.768 | 1.16 [0.85, 1.18] |
| chacha20-poly1305 | 4194304 | 1 | four-block | OpenSSL | GB/s | 0.909 | 3.7 | 0.248 [0.17, 0.254] |
| chacha20-poly1305 | 4194304 | 1 | four-block | paired | GB/s | 0.909 | 0.781 | 1.18 [0.808, 1.48] |

Eighteen focused cases passed in each native Release configuration.
Another 17 unaligned fixtures exercised one-shot and split updates
around 1024 bytes and all one- to three-block remainders.

[Raw trials and output fingerprints](poly1305-four-blocks.json).
