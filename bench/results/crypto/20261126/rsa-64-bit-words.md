# RSA Montgomery multiplication with 64-bit words

Montgomery products process 64 bits per limb and retain each full-width
product and its carries. The key representation stays big-endian at
the API boundary. When the modulus has a partial top word, initialization
advances the Montgomery value by the extra 32 bits of internal padding.
The top four bytes use explicit byte assembly. A Core test covers the
2080-bit PSS fixture and a message that must be rejected.

Fifteen paired native Release process CPU trials ran on AMD EPYC 9V74 CPU 4.
The inputs and operations are those of the 32-bit window campaign. All three
Swag arms use the same Linux compiler with SHA-NI and VPCLMUL support
(SHA-256 `a3f6433553f691628cc2cc55a224516e31b13dfb4caf092b6d270d795ff0b83a`).
The previous 32-bit implementation is `dc87ab5250`. OpenSSL 4.1.0 uses
prepared EVP contexts as documented in the first report.

| Operation | Key bits | Swag build | Ops/s | OpenSSL ops/s | OpenSSL d-only ops/s | Speed over initial (95% CI) |
| --- | ---: | --- | ---: | ---: | ---: | ---: |
| rsa-pss-verify | 2048 | initial | 681.4 | 5.552e+04 | — | — |
| rsa-pss-verify | 2048 | windows | 2374 | 5.552e+04 | — | 3.55 [3, 3.64] |
| rsa-pss-verify | 2048 | limb64 | 3384 | 5.552e+04 | — | 4.95 [4.83, 5.14] |
| rsa-oaep-decrypt | 2048 | initial | 36.88 | 3934 | 504.5 | — |
| rsa-oaep-decrypt | 2048 | windows | 59.8 | 3934 | 504.5 | 1.62 [1.56, 1.65] |
| rsa-oaep-decrypt | 2048 | limb64 | 147.1 | 3934 | 504.5 | 3.98 [3.93, 4] |
| rsa-pss-verify | 2080 | initial | 677.2 | 2.867e+04 | — | — |
| rsa-pss-verify | 2080 | windows | 2370 | 2.867e+04 | — | 3.47 [3.38, 3.51] |
| rsa-pss-verify | 2080 | limb64 | 3199 | 2.867e+04 | — | 4.69 [4.61, 4.75] |
| rsa-oaep-decrypt | 2080 | initial | 34.12 | 787 | 233 | — |
| rsa-oaep-decrypt | 2080 | windows | 53.93 | 787 | 233 | 1.61 [1.55, 1.65] |
| rsa-oaep-decrypt | 2080 | limb64 | 134.6 | 787 | 233 | 3.94 [3.89, 4.12] |
| rsa-pss-verify | 3072 | initial | 329.2 | 2.666e+04 | — | — |
| rsa-pss-verify | 3072 | windows | 1146 | 2.666e+04 | — | 3.5 [3.45, 3.55] |
| rsa-pss-verify | 3072 | limb64 | 1664 | 2.666e+04 | — | 5.02 [4.93, 5.1] |
| rsa-oaep-decrypt | 3072 | initial | 10.92 | 1367 | 153.8 | — |
| rsa-oaep-decrypt | 3072 | windows | 18.02 | 1367 | 153.8 | 1.64 [1.63, 1.76] |
| rsa-oaep-decrypt | 3072 | limb64 | 45.69 | 1367 | 153.8 | 4.14 [4.03, 4.37] |
| rsa-pss-verify | 4096 | initial | 189.4 | 1.476e+04 | — | — |
| rsa-pss-verify | 4096 | windows | 662.3 | 1.476e+04 | — | 3.54 [3.48, 3.63] |
| rsa-pss-verify | 4096 | limb64 | 965.9 | 1.476e+04 | — | 5.08 [4.83, 5.24] |
| rsa-oaep-decrypt | 4096 | initial | 4.781 | 685 | 66.93 | — |
| rsa-oaep-decrypt | 4096 | windows | 7.701 | 685 | 66.93 | 1.62 [1.57, 1.64] |
| rsa-oaep-decrypt | 4096 | limb64 | 19.55 | 685 | 66.93 | 4.12 [3.96, 4.15] |

The retained plaintext and verification byte matched every calibration
and timing sample. A separate 72-case exact check covered all four RSA
operations at offsets 0, 1 and 7. It includes two additional 2080-bit and
4064-bit keys and public exponents 3 and 65537. Five focused Core tests
passed in both JIT and native execution in Release and Release-safe.

[Raw paired samples](rsa-64-bit-words.json) · [Differential verification](rsa-64-bit-words-verification.json) · [Previous campaign](rsa-fixed-windows.md) · [Reproduction](../../../workloads/rsa/README.md)
