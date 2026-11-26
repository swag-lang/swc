# SHA-512 round-state rotation

The hot loop rotates working-word roles across each group of eight rounds and keeps
the existing packed input schedule. Thirteen native Release SHA-512 and consumer
tests passed. The five SHA-512 variant tests also passed in native Release-safe.

CPU 3 on the AMD EPYC 9V74 was pinned for alternating CPU-time series. Both builds
matched Python hashlib and the baseline includes the preceding packed schedule.

| Bytes | Before (µs) | After (µs) | Speedup (95% CI) |
| ---: | ---: | ---: | ---: |
| 16 | 74260 | 72196 | 1.029 [1.000, 1.058] |
| 64 | 49005 | 47866 | 1.024 [0.948, 1.106] |
| 1024 | 26220 | 24018 | 1.092 [1.054, 1.131] |
| 16384 | 22981 | 21616 | 1.063 [1.027, 1.101] |
| 65536 | 22985 | 21535 | 1.067 [1.027, 1.109] |
| 1048576 | 22657 | 21232 | 1.067 [1.042, 1.093] |

[Raw trials and digest fingerprints](sha512-rounds.json).
