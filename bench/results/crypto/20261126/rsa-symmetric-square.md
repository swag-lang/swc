# Symmetric RSA Montgomery squaring

The square forms the off-diagonal products once, doubles their sum, then
adds the diagonal products. Montgomery reduction discharges each row's
high carry into the next row's top word. The final modulus subtraction
uses the same masked selection as ordinary multiplication. Each loop
uses bounds from the public modulus width and clears its scratch words.

The comparison uses the 64-bit word implementation in `e56294f34d` as
its baseline. Fifteen process CPU-time rounds per row used the same
compiler, raw keys, AMD EPYC 9V74 CPU 4, and OpenSSL 4.1.0 references as
the 64-bit word campaign. OAEP decryptions gained 12–15%.

| Operation | Key bits | Swag build | Ops/s | OpenSSL ops/s | OpenSSL d-only ops/s | Speed over initial (95% CI) |
| --- | ---: | --- | ---: | ---: | ---: | ---: |
| rsa-pss-verify | 2048 | limb64 | 3535 | 5.804e+04 | — | — |
| rsa-pss-verify | 2048 | symmetric | 3601 | 5.804e+04 | — | 1.02 [1.01, 1.02] |
| rsa-oaep-decrypt | 2048 | limb64 | 148.6 | 3997 | 506.6 | — |
| rsa-oaep-decrypt | 2048 | symmetric | 166 | 3997 | 506.6 | 1.12 [1.1, 1.12] |
| rsa-pss-verify | 2080 | limb64 | 3196 | 2.864e+04 | — | — |
| rsa-pss-verify | 2080 | symmetric | 3236 | 2.864e+04 | — | 1.01 [1, 1.03] |
| rsa-oaep-decrypt | 2080 | limb64 | 137.8 | 798.3 | 236.7 | — |
| rsa-oaep-decrypt | 2080 | symmetric | 154.7 | 798.3 | 236.7 | 1.12 [1.11, 1.13] |
| rsa-pss-verify | 3072 | limb64 | 1635 | 2.704e+04 | — | — |
| rsa-pss-verify | 3072 | symmetric | 1705 | 2.704e+04 | — | 1.04 [1.02, 1.09] |
| rsa-oaep-decrypt | 3072 | limb64 | 45.28 | 1378 | 153.9 | — |
| rsa-oaep-decrypt | 3072 | symmetric | 52.15 | 1378 | 153.9 | 1.14 [1.12, 1.16] |
| rsa-pss-verify | 4096 | limb64 | 971.5 | 1.578e+04 | — | — |
| rsa-pss-verify | 4096 | symmetric | 999.9 | 1.578e+04 | — | 1.02 [1.02, 1.04] |
| rsa-oaep-decrypt | 4096 | limb64 | 19.66 | 684 | 66.69 | — |
| rsa-oaep-decrypt | 4096 | symmetric | 22.67 | 684 | 66.69 | 1.15 [1.13, 1.17] |

Every timed operation matched the expected plaintext or verification
result. An additional 72 independent outputs checked encrypt, decrypt,
sign and verify for six keys at offsets 0, 1 and 7. All five focused Core
cases passed native and JIT in Release and Release-safe.

[Raw paired timings](rsa-symmetric-square.json) · [Differential cases](rsa-symmetric-square-verification.json) · [Reproduction](../../../workloads/rsa/README.md)
