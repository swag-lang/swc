# Fixed-width Barrett reduction for Ed25519 scalars

The scalar reducer uses fixed-size wide products and two masked
subtractions of the group order. Verification checks that the encoded
signature scalar is canonical, including the boundary exactly at the order.
An independent integer model matched 10,008 input and arithmetic cases.

The common native Release workload compared complete outputs with OpenSSL
3.5.7 and libsodium 1.0.18. At 64 bytes the new signing rate was 11,400
operations per second. The same seed-based operation ran at 7,480 before
the change.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| x25519-public | 32 | 0 | ed-barrett-fast | libsodium | ops/s | 2.34e+04 | 3.5e+04 | 0.679 [0.611, 0.706] |
| x25519-public | 32 | 0 | ed-barrett-fast | radix16 | ops/s | 2.34e+04 | 2.3e+04 | 1.03 [0.977, 1.22] |
| ed25519-public | 32 | 0 | ed-barrett-fast | libsodium | ops/s | 2.35e+04 | 6.14e+04 | 0.385 [0.375, 0.448] |
| ed25519-public | 32 | 0 | ed-barrett-fast | radix16 | ops/s | 2.35e+04 | 2.31e+04 | 1 [0.988, 1.04] |
| ed25519-sign | 64 | 0 | ed-barrett-fast | libsodium | ops/s | 1.14e+04 | 2.96e+04 | 0.387 [0.381, 0.395] |
| ed25519-sign | 64 | 0 | ed-barrett-fast | radix16 | ops/s | 1.14e+04 | 7.48e+03 | 1.53 [1.48, 1.57] |
| ed25519-sign | 4096 | 0 | ed-barrett-fast | libsodium | ops/s | 9.33e+03 | 2.08e+04 | 0.453 [0.441, 0.504] |
| ed25519-sign | 4096 | 0 | ed-barrett-fast | radix16 | ops/s | 9.33e+03 | 6.45e+03 | 1.43 [1.41, 1.51] |

Ten native focused cases passed in each Release configuration. Another 24
independent OpenSSL cases matched. The larger scalar multiplication variant
had equivalent measured throughput.

[Raw trials and output fingerprints](ed25519-barrett.json).
