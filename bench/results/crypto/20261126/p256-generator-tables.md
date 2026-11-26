# P-256 generator comb with four tables

Each fixed-base comb table holds four columns spaced by 64 bits. Splitting
the 64 iterations across shifted tables reduces the number of explicit
accumulator doublings to 16. Every selection still scans 15 affine entries
using a mask. The four tables take 3,840 bytes of field coordinates.

The independent affine integer model regenerated the original table
exactly and generated the shifted tables from the standard P-256 generator.
OpenSSL 3.5.7 matched 326 public keys and 39 ECDSA signatures, including
all single-bit scalars, order boundaries, deterministic random scalars,
partial message blocks and input offsets. All six targeted cases passed
native Release and Release-safe.

Fifteen paired process CPU-time trials on AMD EPYC 9V74 CPU 4 compared the
one-, two- and four-table candidates. The native Release builds used the
same full-width multiplication compiler. The four-table candidate was
selected.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| p256-public | 32 | 0 | comb-2 | prior | ops/s | 7.41e+03 | 6.41e+03 | 1.16 [1.13, 1.18] |
| p256-public | 32 | 0 | comb-4 | prior | ops/s | 8e+03 | 6.41e+03 | 1.25 [1.19, 1.3] |
| p256-sign | 64 | 0 | comb-2 | prior | ops/s | 6.39e+03 | 5.68e+03 | 1.13 [1.1, 1.15] |
| p256-sign | 64 | 0 | comb-4 | prior | ops/s | 6.78e+03 | 5.68e+03 | 1.19 [1.16, 1.23] |
| p256-sign | 4096 | 0 | comb-2 | prior | ops/s | 6.2e+03 | 5.61e+03 | 1.08 [1.05, 1.14] |
| p256-sign | 4096 | 0 | comb-4 | prior | ops/s | 6.65e+03 | 5.61e+03 | 1.2 [1.14, 1.22] |

OpenSSL reached about 90,000 public keys per second and 30,000–33,000
signatures per second in this workload.

[Raw paired trials](p256-generator-tables.json) · [External verification](p256-generator-tables-verification.json).
