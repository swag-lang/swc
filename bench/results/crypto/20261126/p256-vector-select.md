# Packed P-256 field selection

P-256 applies its field-selection mask to two pairs of native words.
The emitted x64 function uses vector loads and bitwise selection with
a fixed instruction sequence. The caller's table traversal is unchanged.

The native Release experiment used 15 paired process CPU-time samples
per profile on AMD EPYC 9V74 CPU 4. Packed selection increased
public-key generation by a paired 1.07× and shared secrets by 1.04×.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| p256-ecdh | 32 | 0 | vector-select | scalar | ops/s | 3.76e+03 | 3.62e+03 | 1.04 [1.03, 1.05] |
| p256-public | 32 | 0 | vector-select | scalar | ops/s | 1.08e+04 | 9.95e+03 | 1.07 [1.06, 1.13] |
| p256-verify | 64 | 0 | vector-select | scalar | ops/s | 2.82e+03 | 2.68e+03 | 1.06 [1.01, 1.07] |
| p256-verify | 4096 | 0 | vector-select | scalar | ops/s | 2.72e+03 | 2.65e+03 | 1.04 [1.02, 1.07] |

All timed outputs matched OpenSSL. The independent ECDH sweep matched
420 additional shared secrets with OpenSSL 4.1.0. Seven focused cases
passed JIT and native Release and Release-safe.

[Raw paired trials](p256-vector-select.json) · [ECDH verification](p256-vector-select-verification.json).
