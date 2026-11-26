# RSA Montgomery multiplication with fused carries

Each 64-bit Montgomery word now retains the two additive carries in the
same full-width operation. This also applies to the off-diagonal products
and reduction rows in the specialized square. The private exponent still
uses a fixed-width window schedule and masked table reads.

The baseline is `3e652f8ade`. Fifteen paired process CPU-time trials ran
on AMD EPYC 9V74 CPU 4 with native Release builds from the same scratch
compiler. OpenSSL 4.1.0 uses the same respective prepared public, CRT and
`n,e,d` contexts as the earlier RSA comparisons.

| Operation | Key bits | Swag build | Ops/s | OpenSSL ops/s | OpenSSL d-only ops/s | Speed over initial (95% CI) |
| --- | ---: | --- | ---: | ---: | ---: | ---: |
| rsa-pss-verify | 2048 | separate | 1.395e+04 | 5.774e+04 | — | — |
| rsa-pss-verify | 2048 | fused | 1.817e+04 | 5.774e+04 | — | 1.3 [1.29, 1.36] |
| rsa-oaep-decrypt | 2048 | separate | 161.6 | 3832 | 478.1 | — |
| rsa-oaep-decrypt | 2048 | fused | 216.1 | 3832 | 478.1 | 1.33 [1.31, 1.38] |
| rsa-pss-verify | 2080 | separate | 1.144e+04 | 2.736e+04 | — | — |
| rsa-pss-verify | 2080 | fused | 1.48e+04 | 2.736e+04 | — | 1.29 [1.26, 1.31] |
| rsa-oaep-decrypt | 2080 | separate | 156.1 | 795 | 238.1 | — |
| rsa-oaep-decrypt | 2080 | fused | 212.2 | 795 | 238.1 | 1.35 [1.27, 1.36] |
| rsa-pss-verify | 3072 | separate | 6317 | 2.742e+04 | — | — |
| rsa-pss-verify | 3072 | fused | 8498 | 2.742e+04 | — | 1.35 [1.34, 1.36] |
| rsa-oaep-decrypt | 3072 | separate | 53.36 | 1417 | 156.6 | — |
| rsa-oaep-decrypt | 3072 | fused | 73.32 | 1417 | 156.6 | 1.38 [1.37, 1.42] |
| rsa-pss-verify | 4096 | separate | 3699 | 1.573e+04 | — | — |
| rsa-pss-verify | 4096 | fused | 5037 | 1.573e+04 | — | 1.36 [1.35, 1.38] |
| rsa-oaep-decrypt | 4096 | separate | 22.82 | 683.7 | 66.87 | — |
| rsa-oaep-decrypt | 4096 | fused | 31.6 | 683.7 | 66.87 | 1.38 [1.34, 1.39] |

The 72-case independent check exercised all four public RSA operations
with six keys at offsets 0, 1 and 7. The native and JIT integrated Core
gates used the combined compiler with the new full-width operation.

[Raw paired timings](rsa-multiply-addends.json) · [Exact differential cases](rsa-multiply-addends-verification.json) · [Reproduction](../../../workloads/rsa/README.md)
