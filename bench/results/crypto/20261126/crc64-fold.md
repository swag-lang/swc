# CPU-gated carry-less CRC folding

CRC-64 uses four independent polynomial folds and Barrett reduction. CRC-32 and
CRC-64 only use carry-less multiplication when the CPU advertises it. Native and
JIT Release tests passed with normal discovery and with the feature forced off.
Independent byte comparisons passed 120 unaligned and boundary cases.

At 1 MiB the CPU-time workload on AMD EPYC 9V74 measured the following rates
in decimal GB/s. The Swag baseline already uses the portable lookup tables.

| Variant | Before | After | ISA-L | Paired speedup (95% CI) |
| --- | ---: | ---: | ---: | ---: |
| crc64-ecma | 1.88 | 13.8 | 49.8 | 7.55 [6.67, 8.36] |
| crc64-iso | 1.89 | 14.2 | 56.7 | 7.54 [7.28, 7.59] |
| crc64-xz | 1.85 | 14.2 | 54.5 | 7.65 [7.49, 7.94] |

The 64-byte cutover retains the short-message table path. CRC-32 keeps its existing
fold geometry when the feature is available.

[Raw CRC-64 trials](crc64-fold.json) · [Raw CRC-32 dispatch trials](crc32-cpu-gate.json).
