# Curve25519 field inversion and squaring

X25519 and Ed25519 use a fixed addition chain for inversion, a symmetric square,
and shared field-product code. All nine focused Core tests passed in native
Release and Release-safe, including RFC 7748 iterations 1 and 1,000 and acceptance
of a noncanonical coordinate. The independent comparison matched OpenSSL on
24 input, key and signature cases.

Twenty paired process CPU-time samples per operation ran on AMD EPYC 9V74 CPU 3.
P-256 public-key derivation served as an independent control.

| Operation | Before (µs) | After (µs) | Paired speedup (95% CI) |
| --- | ---: | ---: | ---: |
| X25519 public key | 1395.45 | 1276.93 | 1.100 [1.089, 1.114] |
| X25519 shared secret | 1410.71 | 1284.60 | 1.100 [1.080, 1.135] |
| Ed25519 public key | 2633.29 | 2415.74 | 1.094 [1.060, 1.107] |
| Ed25519 sign | 5415.59 | 4840.01 | 1.119 [1.090, 1.158] |
| Ed25519 verify | 11731.57 | 10482.76 | 1.131 [1.106, 1.146] |
| P-256 control | 1531.97 | 1518.46 | 1.004 [0.963, 1.035] |

[Raw trials](curve25519-inverse.json).
