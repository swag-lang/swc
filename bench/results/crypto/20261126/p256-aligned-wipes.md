# P-256 aligned local word clearing

The Montgomery multiply clears all nine local scratch words with
aligned native-word stores. Both pre-emit Micro listings contain nine
volatile stores in each field and order specialization. The volatile
operation preserves the wipe during dead-store elimination.

Seventeen paired native Release process CPU-time trials ran on CPU 4 of
the AMD EPYC 9V74. The common workload compared complete public keys,
shared secrets, signatures and verification outputs with OpenSSL
3.5.7. Seven focused Core cases passed Release and Release-safe.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| p256-public | 32 | 0 | inline-stores | platform-clear | ops/s | 9.87e+03 | 9.46e+03 | 1.04 [1.04, 1.05] |
| p256-ecdh | 32 | 0 | inline-stores | platform-clear | ops/s | 3.46e+03 | 3.29e+03 | 1.05 [1.04, 1.05] |
| p256-sign | 64 | 0 | inline-stores | platform-clear | ops/s | 8.07e+03 | 7.84e+03 | 1.03 [1.03, 1.07] |
| p256-sign | 4096 | 0 | inline-stores | platform-clear | ops/s | 7.93e+03 | 7.59e+03 | 1.04 [1.03, 1.08] |
| p256-verify | 64 | 0 | inline-stores | platform-clear | ops/s | 2.56e+03 | 2.45e+03 | 1.05 [1.03, 1.06] |
| p256-verify | 4096 | 0 | inline-stores | platform-clear | ops/s | 2.55e+03 | 2.44e+03 | 1.04 [1.03, 1.07] |

[Raw paired trials and output fingerprints](p256-aligned-wipes.json).
