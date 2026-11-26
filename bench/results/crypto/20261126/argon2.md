# Argon2id scalar compression and memory traversal

Native Linux x86-64 comparison on AMD EPYC 9V74, November 26, 2026. Both Swag revisions
used the Release compiler built at `d9bfeae85f` and the `release` program configuration.
The baseline standard library was from the same revision. The references were OpenSSL
3.5.7 and upstream libargon2 20190702 (`62358ba212`) built with GCC 14.2 and
`OPTTARGET=znver4`, which selected the AVX-512 kernel.

The [runner](../../../workloads/argon2/README.md#native-comparison-with-libargon2-and-openssl)
alternated the implementations in nine paired rounds per profile and verified every
32-byte tag. One worker used CPU 0 and four workers used CPUs 0–3. The virtual machine
had a four-CPU quota, with concurrent unrelated work and considerable variation at large
working sets. The ratios use the median of paired latencies and its exact 95% interval.
All rows use four lanes, three passes, and Argon2id version 0x13.

| MiB | Workers | Baseline ms | Candidate ms | libargon2 ms | OpenSSL ms | Candidate / baseline | Candidate / libargon2 | Candidate / OpenSSL |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 1 | 3.047 | 2.087 | 0.831 | 1.711 | 0.681 [0.670, 0.724] | 2.527 [2.427, 2.740] | 1.263 [1.150, 1.333] |
| 64 | 1 | 291.828 | 211.790 | 110.358 | 188.772 | 0.730 [0.604, 0.933] | 1.900 [1.627, 1.936] | 1.141 [1.053, 1.255] |
| 256 | 1 | 2201.672 | 1900.456 | 1133.237 | 826.288 | 0.776 [0.559, 1.091] | 1.969 [1.570, 2.400] | 1.327 [1.217, 3.032] |
| 1 | 4 | 3.277 | 2.168 | 8.747 | 16.717 | 0.693 [0.557, 0.776] | 0.255 [0.082, 1.594] | 0.156 [0.079, 0.872] |
| 64 | 4 | 250.424 | 208.843 | 123.362 | 191.153 | 0.810 [0.649, 1.089] | 1.379 [1.137, 2.166] | 1.092 [0.957, 1.317] |
| 256 | 4 | 1323.575 | 1039.853 | 626.810 | 935.373 | 0.767 [0.622, 0.898] | 1.702 [1.434, 1.832] | 1.065 [1.000, 1.191] |

Swag reduced latency by 23–32% where the paired interval excludes parity. The intervals for
256 MiB with one worker and 64 MiB with four workers span parity. At large working sets,
libargon2's AVX-512 kernel remained ahead. At 1 MiB with four workers, Swag had lower complete call latency than OpenSSL.
The interval against libargon2 spans parity.

The scalar permutation now loads its four operands once per mixer and uses direct row
and column offsets. Segment traversal hoists the reference window, avoids division for
common power-of-two lane counts, and wraps the lane offset with at most one subtraction.
The first pass initializes the matrix as it goes. The whole matrix is securely cleared
at exit.

The six Core `argon2.swg` cases passed in native Release, including the RFC 9106 vector,
rounded memory, address boundaries, fewer workers than lanes, and nested parallel calls.
[Raw timings and tags](argon2.json)
