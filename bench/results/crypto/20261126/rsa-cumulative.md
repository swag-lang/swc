# Cumulative RSA comparison

Seventeen paired native Release process CPU-time trials ran on AMD EPYC
9V74 CPU 4. The baseline library is `81378f0775`. The current RSA source
is `5f68346f72`. Both compiled with the same Linux compiler from
`580d8cc4b7` (SHA-256 `e0e8fb233c045d296d4de002c583b17c276b7340e3a71d3f3a9d4ce714d2e5eb`).
Calibration and timed runs returned the exact expected plaintext or
verification byte for all eight profiles.

OpenSSL 4.1.0 used prepared contexts. Its CRT reference received the
factorization of the test key. The `d-only` reference received `n,e,d`
and kept the provider's private-operation countermeasures. The current
Swag API constructs its context from the raw key arguments per call.

| Operation | Key bits | Swag build | Ops/s | OpenSSL ops/s | OpenSSL d-only ops/s | Speed over initial (95% CI) |
| --- | ---: | --- | ---: | ---: | ---: | ---: |
| rsa-pss-verify | 2048 | baseline | 677.5 | 5.688e+04 | — | — |
| rsa-pss-verify | 2048 | latest | 1.801e+04 | 5.688e+04 | — | 26.4 [25.9, 26.7] |
| rsa-oaep-decrypt | 2048 | baseline | 36.91 | 3985 | 500.2 | — |
| rsa-oaep-decrypt | 2048 | latest | 225.9 | 3985 | 500.2 | 6.12 [5.97, 6.18] |
| rsa-pss-verify | 2080 | baseline | 671 | 2.897e+04 | — | — |
| rsa-pss-verify | 2080 | latest | 1.535e+04 | 2.897e+04 | — | 22.7 [22.5, 23] |
| rsa-oaep-decrypt | 2080 | baseline | 33.64 | 787 | 235.2 | — |
| rsa-oaep-decrypt | 2080 | latest | 211.7 | 787 | 235.2 | 6.3 [6.2, 6.41] |
| rsa-pss-verify | 3072 | baseline | 325.4 | 2.715e+04 | — | — |
| rsa-pss-verify | 3072 | latest | 8384 | 2.715e+04 | — | 25.8 [25.5, 26.4] |
| rsa-oaep-decrypt | 3072 | baseline | 11.07 | 1391 | 153.7 | — |
| rsa-oaep-decrypt | 3072 | latest | 72.18 | 1391 | 153.7 | 6.55 [6.47, 6.6] |
| rsa-pss-verify | 4096 | baseline | 185.6 | 1.542e+04 | — | — |
| rsa-pss-verify | 4096 | latest | 4953 | 1.542e+04 | — | 26.7 [26.3, 26.9] |
| rsa-oaep-decrypt | 4096 | baseline | 4.815 | 677.7 | 66.73 | — |
| rsa-oaep-decrypt | 4096 | latest | 31.72 | 677.7 | 66.73 | 6.59 [6.52, 6.7] |

[Raw paired measurements](rsa-cumulative.json) · [Fixture hashes](rsa-fixture-manifest.json) · [Reproduction](../../../workloads/rsa/README.md)
