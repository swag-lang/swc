# BLAKE3 register-resident compression

The revised compression keeps each round's state in SIMD rows. Single-block messages
use the short root path, and key setup reads exactly the supplied 32 bytes.
Six native Release Core tests passed, including official unkeyed, keyed and derive-key
vectors. An independent run checked 1,263 outputs against BLAKE3 C 1.8.7 over unaligned
input, multiple chunk boundaries and output lengths, including extendable output.

The [common workload](../../../workloads/crypto/README.md) compared native Release
Swag with the dispatch-enabled official BLAKE3 C build on CPU 2 of an AMD EPYC 9V74.
The rates are process CPU-time GB/s.

| Bytes | Before | After | BLAKE3 C | Paired speedup (95% CI) |
| ---: | ---: | ---: | ---: | ---: |
| 64 | 0.164 | 0.455 | 0.558 | 2.72 [2.52, 2.89] |
| 4096 | 0.388 | 0.610 | 2.70 | 1.58 [1.52, 1.64] |
| 65536 | 0.409 | 0.624 | 6.34 | 1.53 [1.50, 1.64] |
| 1048576 | 0.403 | 0.620 | 6.32 | 1.54 [1.50, 1.66] |

[Raw trials and output fingerprints](blake3.json).
