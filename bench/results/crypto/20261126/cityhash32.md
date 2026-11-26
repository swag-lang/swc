# CityHash32 word loads and state rotation

CityHash32 loads words directly and rotates its scalar state without taking addresses
of hot local variables. The native Release test passed, including the stable short
unsigned-byte outputs, seeded input and unaligned lengths 0–80. An additional 152
size/alignment pairs matched upstream CityHash at commit f5dc54147f.

On CPU 2 of the AMD EPYC 9V74, the common workload used 21 paired process CPU-time
trials per size. Every measured output matched. Rates are decimal GB/s.

| Bytes | Before | After | CityHash C++ | Paired speedup (95% CI) |
| ---: | ---: | ---: | ---: | ---: |
| 5 | 0.363 | 0.471 | 1.09 | 1.29 [1.28, 1.33] |
| 8 | 0.593 | 0.768 | 1.77 | 1.29 [1.27, 1.32] |
| 24 | 1.15 | 1.72 | 3.32 | 1.5 [1.48, 1.5] |
| 25 | 1.28 | 1.71 | 2.19 | 1.33 [1.32, 1.35] |
| 32 | 1.63 | 2.16 | 2.81 | 1.33 [1.31, 1.35] |
| 64 | 1.9 | 3.09 | 3.46 | 1.62 [1.59, 1.69] |
| 4096 | 2.8 | 5.74 | 5.53 | 2.06 [1.99, 2.09] |
| 65536 | 2.84 | 5.84 | 5.65 | 2.05 [2.02, 2.11] |
| 1048576 | 2.77 | 5.79 | 5.46 | 2.09 [2.01, 2.16] |

[Raw trials and output fingerprints](cityhash32.json).
