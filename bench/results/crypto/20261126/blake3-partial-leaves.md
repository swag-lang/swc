# BLAKE3 partial SIMD leaf batches

At 3 KiB, Swag improved from 0.67 to 1.16 GB/s on aligned input,
a **1.72× [1.66, 1.78]** paired ratio. The same three-chunk batch
reached 1.19 GB/s at offset one. BLAKE3 C 1.8.7 reached 1.33 GB/s
on the aligned fixture.

Two or three complete chunks now use the four-lane compression schedule.
Unused lanes read the last complete chunk and their chaining values are
discarded. For an update ending exactly on a batch boundary, the last
valid lane yields its chaining value before the last block, which stays
buffered for root output or a subsequent update.

## One-worker process CPU time

Same Release compiler and worker count, AMD EPYC 9V74, CPU 1, 11
shuffled rounds and a 14 ms target. The baseline includes the aligned
subtree reduction from `21f7190da7`. The table reports aligned GB/s
and paired ratios with 95% confidence intervals. The raw data covers
offset one as well. [CPU samples](blake3-partial-leaves-cpu.json)

| Input | Swag before | Swag partial batch | BLAKE3 C | Paired speed ratio |
| --- | ---: | ---: | ---: | ---: |
| 2 KiB | 0.68 | 0.83 | 1.77 | 1.23 [1.21, 1.25] |
| 3 KiB | 0.67 | 1.16 | 1.33 | 1.72 [1.66, 1.78] |
| 4,095 B | 0.66 | 1.03 | 1.15 | 1.53 [1.47, 1.62] |
| 4 KiB | 1.52 | 1.52 | 2.75 | 1.01 [0.96, 1.04] |
| 7 KiB | 1.01 | 1.40 | 1.86 | 1.37 [1.33, 1.41] |
| 8,191 B | 0.95 | 1.26 | 1.60 | 1.32 [1.23, 1.34] |
| 64 KiB | 1.66 | 1.64 | 6.41 | 0.99 [0.96, 1.04] |
| 1 MiB | 1.67 | 1.67 | 6.42 | 1.00 [0.95, 1.03] |

## Validation

Seven focused native Core tests passed in each of Release and
Release-safe. The new fixture exercises two- and three-chunk boundary
vectors and feeds the first byte of the next chunk in a separate
update. The official 131-byte unkeyed, keyed and derived-key proof
also passed in both configurations. The candidate matched BLAKE3 C
on 216 one-shot and streaming fixtures, with offsets of 0, 1 and 15
and configured worker counts of one and four.
[Differential fixtures](blake3-partial-leaves-verify.json)

Build the baseline and current checkout with the same Release compiler
and use `run.py` with `--algorithm blake3 --clock cpu --rounds 11
--target-ms 14 --offset 0 --offset 1`. Use the byte sizes in the raw
data to repeat the full panel.
[Build and timing commands](../../../workloads/blake3/README.md)
