# Native-word P-256 field storage

Field coordinates, order values and Montgomery inputs all use four 64-bit words.
Addition, subtraction and reduction share the same carry and borrow routines.
Six focused native Release and Release-safe Core tests passed, plus 145 OpenSSL
public-key and deterministic-signature comparisons across offsets 0–15.

Seventeen paired process CPU-time trials on CPU 4 of the AMD EPYC 9V74 measured
the following rates in operations per second. Every output agreed with OpenSSL.

| Operation | Before | After | OpenSSL 3.5.7 | Paired speedup (95% CI) |
| --- | ---: | ---: | ---: | ---: |
| Public key | 3600 | 3990 | 92500 | 1.11 [1.08, 1.14] |
| Sign, 64 B | 3000 | 3380 | 33000 | 1.12 [1.10, 1.15] |
| Sign, 4096 B | 2810 | 3170 | 30100 | 1.11 [1.09, 1.14] |

[Raw trials and output fingerprints](p256-fullwords.json).
