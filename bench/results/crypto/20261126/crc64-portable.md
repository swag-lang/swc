# Portable CRC-64 tables

Compared the bit-at-a-time implementation at `d9bfeae85f` with the slicing-by-eight
implementation on an AMD EPYC 9V74 under Linux. Both ran as native Release on CPU 0.
Seven paired samples alternate timing order. Each timed batch cycles through eight byte
offsets. Separate checksum comparisons agreed at all eight offsets, and the isolated Core
CRC-64 test passed, including streaming, unaligned buffers and compile-time evaluation.

| Variant | Bytes | Before GB/s | After GB/s | Paired speedup (95% CI) |
| --- | ---: | ---: | ---: | ---: |
| ECMA-182 | 64 | 0.174 | 1.27 | 7.32 [7.01, 7.63] |
| ECMA-182 | 1024 | 0.159 | 1.73 | 10.9 [9.98, 11.2] |
| ECMA-182 | 65536 | 0.0405 | 1.78 | 43.6 [41.9, 45.3] |
| ECMA-182 | 1048576 | 0.0397 | 1.73 | 43 [32, 47.2] |
| GO-ISO | 64 | 0.113 | 1.28 | 11.3 [11.3, 11.7] |
| GO-ISO | 1024 | 0.0407 | 1.72 | 42.7 [31.5, 49.2] |
| GO-ISO | 65536 | 0.0343 | 1.77 | 51.5 [43.2, 52.9] |
| GO-ISO | 1048576 | 0.0336 | 1.72 | 50.9 [50.2, 63.7] |
| XZ | 64 | 0.123 | 1.28 | 10.3 [9.44, 11.5] |
| XZ | 1024 | 0.0437 | 1.67 | 37.5 [35.8, 40.6] |
| XZ | 65536 | 0.0354 | 1.68 | 48 [45, 49.9] |
| XZ | 1048576 | 0.0357 | 1.73 | 48.5 [45.9, 50.9] |
