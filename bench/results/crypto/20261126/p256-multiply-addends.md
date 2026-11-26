# P-256 Montgomery multiplication with fused carries

The field and order multiplication share one full-width operation that
retains both low-word carries. The point formulas and the fixed-window
schedules use the same input and output representation.

The baseline is `b0868ce735`. Seventeen paired native Release CPU-time
trials ran on AMD EPYC 9V74 CPU 4. The same scratch compiler with the new
intrinsic built both variants. OpenSSL 4.1.0 was also measured wherever
the common replay supports it. The deterministic signing rows used
OpenSSL 3.5.7 for timings and independently matched OpenSSL 4.1.0 bytes.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| p256-public | 32 | 0 | scalar | OpenSSL4.1 | ops/s | 1.22e+04 | 9.35e+04 | 0.131 [0.124, 0.132] |
| p256-public | 32 | 0 | adc | OpenSSL4.1 | ops/s | 1.35e+04 | 9.35e+04 | 0.146 [0.122, 0.147] |
| p256-public | 32 | 0 | adc | scalar | ops/s | 1.35e+04 | 1.22e+04 | 1.11 [1.06, 1.12] |
| p256-ecdh | 32 | 0 | scalar | OpenSSL | ops/s | 3.78e+03 | 2.15e+04 | 0.176 [0.174, 0.181] |
| p256-ecdh | 32 | 0 | adc | OpenSSL | ops/s | 4.29e+03 | 2.15e+04 | 0.2 [0.197, 0.203] |
| p256-ecdh | 32 | 0 | adc | scalar | ops/s | 4.29e+03 | 3.78e+03 | 1.13 [1.12, 1.14] |
| p256-sign | 64 | 0 | scalar | OpenSSL | ops/s | 9.29e+03 | 3.24e+04 | 0.289 [0.275, 0.292] |
| p256-sign | 64 | 0 | adc | OpenSSL | ops/s | 1.08e+04 | 3.24e+04 | 0.336 [0.326, 0.342] |
| p256-sign | 64 | 0 | adc | scalar | ops/s | 1.08e+04 | 9.29e+03 | 1.17 [1.13, 1.2] |
| p256-sign | 4096 | 0 | scalar | OpenSSL | ops/s | 9.22e+03 | 3.06e+04 | 0.306 [0.302, 0.31] |
| p256-sign | 4096 | 0 | adc | OpenSSL | ops/s | 1.05e+04 | 3.06e+04 | 0.352 [0.347, 0.361] |
| p256-sign | 4096 | 0 | adc | scalar | ops/s | 1.05e+04 | 9.22e+03 | 1.15 [1.14, 1.17] |
| p256-verify | 64 | 0 | scalar | OpenSSL4.1 | ops/s | 3.31e+03 | 1.46e+04 | 0.226 [0.225, 0.232] |
| p256-verify | 64 | 0 | adc | OpenSSL4.1 | ops/s | 3.75e+03 | 1.46e+04 | 0.256 [0.255, 0.26] |
| p256-verify | 64 | 0 | adc | scalar | ops/s | 3.75e+03 | 3.31e+03 | 1.14 [1.12, 1.16] |
| p256-verify | 4096 | 0 | scalar | OpenSSL4.1 | ops/s | 3.26e+03 | 1.42e+04 | 0.232 [0.228, 0.233] |
| p256-verify | 4096 | 0 | adc | OpenSSL4.1 | ops/s | 3.72e+03 | 1.42e+04 | 0.261 [0.26, 0.264] |
| p256-verify | 4096 | 0 | adc | scalar | ops/s | 3.72e+03 | 3.26e+03 | 1.13 [1.12, 1.15] |

All 326 public keys and 39 deterministic signatures matched OpenSSL
4.1.0. Separately, 793 valid or invalid verification decisions matched
OpenSSL 4.0.1 in each of native Release and Release-safe. The native
and JIT integrated Core gates used the Release compiler with the combined
CRC-512, IFMA and wide multiplication lowering.

[Paired timings](p256-multiply-addends.json) · [Public keys and signatures](p256-multiply-addends-verification.json) · [Verification corpus](p256-verify-wnaf-fixtures.json)
