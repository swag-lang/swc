# P-256 four-bit order inversion

The inverse modulo the group order uses windows of the fixed public exponent
n - 2. The table stores intermediate powers and is cleared after use. All six
native P-256 tests passed in Release and Release-safe.

The common workload compared complete deterministic signatures against OpenSSL
3.5.7 in 17 paired process CPU-time trials on AMD EPYC 9V74 CPU 4. All signatures
matched. Rates are operations per second.

| Input | Before | After | OpenSSL | Paired speedup (95% CI) |
| ---: | ---: | ---: | ---: | ---: |
| 64 B | 3320 | 3470 | 31900 | 1.04 [1.04, 1.06] |
| 4096 B | 3120 | 3290 | 30100 | 1.05 [1.02, 1.07] |

[Raw trials and signature fingerprints](p256-order.json).
