# Parallel CRC-64 on large buffers

Large inputs can use independent folded tiles and ordered polynomial composition.
A seeded streaming stress test and the focused CRC-64 tests passed in native and
JIT Release. A separate check exercised the stress case with exactly four workers.
The reference comparison matched 42 additional unaligned cases.

Eleven paired wall-time trials used CPUs 0–3 of the AMD EPYC 9V74 and the
[configurable workload](../../../workloads/crypto/README.md). The baseline uses one
worker with the previous hardware fold. One-worker timings for the new path were
within 3% of that baseline over the measured sizes. Rates are decimal GB/s.

| Variant, 16 MiB | Baseline | Four Swag workers | ISA-L, one thread | Paired speedup (95% CI) |
| --- | ---: | ---: | ---: | ---: |
| ECMA-182 | 14.3 | 38.4 | 47.1 | 2.68 [2.26, 2.77] |
| GO-ISO | 14.2 | 26.6 | 47.4 | 2.11 [1.69, 2.76] |
| XZ | 14.2 | 24.4 | 50.7 | 1.75 [1.44, 1.88] |

At 4 MiB the four-worker ratios ranged from 1.13x to 2.32x. At 2 MiB they
ranged from 1.02x to 1.39x.

[Raw timings for one, two and four workers](crc64-parallel.json).
