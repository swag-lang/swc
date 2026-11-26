# Poly1305 keyed-state cleanup

Poly1305 securely clears the whole active state in one call and skips redundant
cleanup of an already cleared value. All 17 focused native Release and Release-safe
tests passed. A live reset starts a fresh MAC while clearing the previous key state.

Twenty paired process CPU-time samples ran on CPU 3 of the AMD EPYC 9V74. Each
sample processed 8 MiB, and the outputs agreed. Rates are GiB/s.

| Operation | Bytes | Before | After | Paired speedup (95% CI) |
| --- | ---: | ---: | ---: | ---: |
| Poly1305 | 64 | 0.254 | 0.341 | 1.35 [1.32, 1.38] |
| Poly1305 | 1024 | 1.09 | 1.18 | 1.08 [1.06, 1.11] |
| Poly1305 | 16384 | 1.37 | 1.38 | 1.01 [1, 1.02] |
| Poly1305 | 262144 | 1.4 | 1.39 | 0.996 [0.976, 1.01] |
| Poly1305 | 4194304 | 1.38 | 1.39 | 0.999 [0.991, 1.02] |
| ChaCha20-Poly1305 seal | 64 | 0.0892 | 0.109 | 1.21 [1.11, 1.36] |
| ChaCha20-Poly1305 seal | 1024 | 0.454 | 0.481 | 1.06 [1.03, 1.08] |
| ChaCha20-Poly1305 seal | 16384 | 0.568 | 0.583 | 1.03 [0.967, 1.08] |
| ChaCha20-Poly1305 seal | 262144 | 0.584 | 0.582 | 1.02 [0.962, 1.11] |
| ChaCha20-Poly1305 seal | 4194304 | 0.593 | 0.596 | 1.01 [0.945, 1.07] |

[Raw trials](poly1305-cleanup.json).
