# CSV aggregation, nbody and sort

Prompt 2 starts at `2e8511af06`. The benchmark sources, workloads, checksums and
measured boundaries remain unchanged. DevMode compiler, Release benchmark programs.
Temporary installations, caches, listings and build outputs are outside the checkout.

## Overlapping dynamic comparison tails

`Swag.memcmp` compares the remaining range with a head and a tail of the largest
fitting scalar width. Both reads stay in the requested range; the head mismatch
wins when their ranges overlap. Exact-width ranges skip the redundant tail read.
Keeping the consumed offset rather than the original remaining length across the
head comparison avoids adding an integer clobber to this leaf's calling contract.

The equal-key paths in the emitted x64 code have these executed instruction and
memory-operand counts, including entry and return, excluding alignment NOPs:

| Key length | Before instructions | After instructions | Before reads | After reads |
| --- | ---: | ---: | ---: | ---: |
| 1 | 25 | 20 | 2 | 2 |
| 2 | 28 | 24 | 2 | 2 |
| 3 | 32 | 26 | 4 | 4 |
| 4 | 28 | 22 | 2 | 2 |
| 5 | 32 | 29 | 4 | 4 |
| 6 | 35 | 29 | 4 | 4 |
| 7 | 39 | 29 | 6 | 4 |

CSV's eight region strings have lengths 4, 4, 4, 5, 6, 6, 7 and 4. Its successful
comparison therefore saves an average 6.125 instructions and 0.25 memory operands
per row, about 2.45 million instructions and 100,000 reads over 400,000 rows. A
mismatch in the head retains its ordering and skips the overlapping tail.

All twelve Release benchmark checksums pass. Task kernels and their callers are
unchanged, including their saved registers and spills; only the shared dynamic
comparison body changes after overload ordinals and generated names are paired.
The vector loop retains its work. The six focused `memory_dynamic` tests pass
through JIT and native in DevMode, including all mismatch positions, unaligned
sizes through 65 bytes, and opposite-order mismatches in overlapping ranges.

A 24-round pinned alternating comparison of the final binaries is exploratory:
CSV candidate/base median 1.0418 with range 0.8181..1.7084 and unchanged A/A median
0.9721; wordfreq candidate/base median 0.9816 with range 0.7625..1.2412 and A/A
median 0.9866. These dispersed observations do not establish a speedup or a
reproducible slowdown. The batch is accepted on executed static work and remains
**landed, unconfirmed** until the grouped campaign.
