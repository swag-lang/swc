# Poly1305 paired block products

Large Poly1305 updates combine two block products with one carry step. The
scalar path serves short updates. Eleven native Release and Release-safe
tests passed. Eight independent OpenSSL comparisons cover unaligned input
and split updates across the dispatch threshold.

On the AMD EPYC 9V74, eleven paired process CPU-time trials were pinned to
CPU 3. All full tags or ciphertext/tag pairs matched. Rates are GB/s.

| Operation | Bytes | Before | After | OpenSSL | Speedup (95% CI) |
| --- | ---: | ---: | ---: | ---: | ---: |
| poly1305 | 64 | 0.368 | 0.367 | 0.798 | 1 [0.811, 1.16] |
| poly1305 | 2048 | 1.38 | 1.53 | 8.39 | 1.11 [1.02, 1.14] |
| poly1305 | 16384 | 1.48 | 1.85 | 11.9 | 1.26 [1.24, 1.27] |
| poly1305 | 4194304 | 1.49 | 1.86 | 12.1 | 1.25 [1.23, 1.29] |
| chacha20-poly1305 | 64 | 0.116 | 0.122 | 0.105 | 1.03 [0.988, 1.1] |
| chacha20-poly1305 | 2048 | 0.596 | 0.621 | 1.92 | 1.05 [1.03, 1.28] |
| chacha20-poly1305 | 16384 | 0.646 | 0.712 | 3.3 | 1.12 [1.07, 1.33] |
| chacha20-poly1305 | 4194304 | 0.66 | 0.725 | 3.67 | 1.1 [1.02, 1.18] |

[Raw trials and output fingerprints](poly1305-paired.json).
