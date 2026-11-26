# BLAKE3 four-chunk batches

Four independent chunks now share a packed compression pass. The six focused native
Release Core tests passed. BLAKE3 C 1.8.7 also matched 1,263 differential cases under
four runtime workers, including unaligned input, split updates, keyed hashing and XOF.
The timed baseline already includes the preceding packed-round change.

On CPU 2 of the AMD EPYC 9V74, the common workload used 21 paired process CPU-time
trials per size. Every measured output matched. Rates are decimal GB/s.

| Bytes | Before | After | BLAKE3 C | Paired speedup (95% CI) |
| ---: | ---: | ---: | ---: | ---: |
| 64 | 0.45 | 0.454 | 0.567 | 1.01 [0.979, 1.03] |
| 4096 | 0.615 | 0.673 | 2.72 | 1.09 [1.07, 1.09] |
| 4097 | 0.592 | 0.785 | 2.41 | 1.33 [1.31, 1.34] |
| 65536 | 0.62 | 0.81 | 6.38 | 1.31 [1.29, 1.32] |
| 1048576 | 0.608 | 0.813 | 6.33 | 1.33 [1.28, 1.35] |

[Raw trials and output fingerprints](blake3-four-chunks.json).
