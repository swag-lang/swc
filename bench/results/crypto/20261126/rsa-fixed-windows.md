# RSA Montgomery setup and private exponent windows

Initialization starts from `R - n`, which represents one in the Montgomery
field for a full-width modulus. A single pass doubles and computes the
subtraction candidate, cutting the number of setup rounds in half. Public
exponentiation starts at its highest set bit. Signing and decryption reuse
one context across their validation and private exponentiation.

The private path consumes four exponent bits at a time. It does four
squares and one product per window, scanning all sixteen table rows with
bit masks and clearing the workspace. The multiplication retains the
high carry from each of the two top-word sums during reduction.

Thirteen paired process CPU trials ran on AMD EPYC 9V74 CPU 4 with native
Release builds of `81378f0775` and the candidate. OpenSSL 4.1.0 uses
prepared EVP key and operation contexts. The Swag entry points take raw
keys and include per-call setup. The OpenSSL private measurements use
both full CRT key parameters and the same `n,e,d` representation available
from the fixture without its CRT parameters.

| Operation | Key bits | Swag build | Ops/s | OpenSSL ops/s | OpenSSL d-only ops/s | Speed over initial (95% CI) |
| --- | ---: | --- | ---: | ---: | ---: | ---: |
| rsa-pss-verify | 2048 | initial | 674 | 5.652e+04 | — | — |
| rsa-pss-verify | 2048 | windows | 2493 | 5.652e+04 | — | 3.69 [3.56, 3.75] |
| rsa-oaep-decrypt | 2048 | initial | 36.33 | 3997 | 495.1 | — |
| rsa-oaep-decrypt | 2048 | windows | 59.68 | 3997 | 495.1 | 1.65 [1.59, 1.71] |
| rsa-pss-verify | 2080 | initial | 673.5 | 2.871e+04 | — | — |
| rsa-pss-verify | 2080 | windows | 2374 | 2.871e+04 | — | 3.52 [3.48, 3.55] |
| rsa-oaep-decrypt | 2080 | initial | 33.7 | 794.1 | 234.8 | — |
| rsa-oaep-decrypt | 2080 | windows | 52.55 | 794.1 | 234.8 | 1.62 [1.48, 1.71] |
| rsa-pss-verify | 3072 | initial | 326.5 | 2.717e+04 | — | — |
| rsa-pss-verify | 3072 | windows | 1171 | 2.717e+04 | — | 3.57 [3.53, 3.6] |
| rsa-oaep-decrypt | 3072 | initial | 11.19 | 1397 | 155.7 | — |
| rsa-oaep-decrypt | 3072 | windows | 18.23 | 1397 | 155.7 | 1.63 [1.6, 1.69] |
| rsa-pss-verify | 4096 | initial | 185.6 | 1.562e+04 | — | — |
| rsa-pss-verify | 4096 | windows | 680.4 | 1.562e+04 | — | 3.61 [3.52, 3.81] |
| rsa-oaep-decrypt | 4096 | initial | 4.768 | 676.5 | 67.39 | — |
| rsa-oaep-decrypt | 4096 | windows | 7.743 | 676.5 | 67.39 | 1.62 [1.6, 1.64] |

Every timed plaintext and verification result matched. At offsets 0, 1
and 7, 48 checks across the four key sizes also matched the OpenSSL
cryptography backend for verification and decryption, or independently
verified newly generated signatures and encrypted messages. Four Core
cases passed in native and JIT Release and Release-safe.

[Raw paired measurements](rsa-fixed-windows.json) · [Differential checks](rsa-fixed-windows-verification.json) · [Fixture hashes](rsa-fixture-manifest.json) · [Reproduction](../../../workloads/rsa/README.md)
