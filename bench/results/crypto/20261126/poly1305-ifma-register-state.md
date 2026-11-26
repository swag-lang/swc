# Poly1305 IFMA register-state recurrence

The recurring pair loop keeps its three accumulators and product halves in
named vector values. It computes the large wrapped carry before propagating
the middle and top carries. The latter two limbs can remain temporarily
above their masks because the extra carries fit inside the source operand
bounds. The first power and the final lane merge still use the fully
propagated reduction. Key-derived state written into scratch is cleared
after use.

The first experiment isolated the deferred carries. It matched all 22
layouts and increased Poly1305 throughput at 4 MiB from 3.29 to 3.46 GB/s.
Keeping the recurrence in registers then raised the 4 MiB result from
3.41 to 4.67 GB/s in a separate paired run. OpenSSL 4.1.0 measured
12.5 GB/s at that size. The register experiment used 11 interleaved CPU-time
samples on one EPYC 9V74 core, with a one-byte input offset. All 22 layouts
matched OpenSSL 4.1.0 and libsodium 1.0.22. The paired table compares
register state to deferred carries alone.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| poly1305 | 320 | 1 | registers | baseline | GB/s | 1.32 | 1.13 | 1.13 [1.04, 1.25] |
| poly1305 | 512 | 1 | registers | baseline | GB/s | 1.71 | 1.57 | 1.1 [0.998, 1.47] |
| poly1305 | 1024 | 1 | registers | baseline | GB/s | 2.65 | 2.18 | 1.19 [1.09, 1.34] |
| poly1305 | 4096 | 1 | registers | baseline | GB/s | 4.01 | 3.01 | 1.31 [1.27, 1.35] |
| poly1305 | 16384 | 1 | registers | baseline | GB/s | 4.51 | 3.27 | 1.35 [1.33, 1.55] |
| poly1305 | 4194304 | 1 | registers | baseline | GB/s | 4.67 | 3.41 | 1.36 [1.32, 1.45] |
| chacha20-poly1305 | 320 | 1 | registers | baseline | GB/s | 0.369 | 0.381 | 1.03 [0.803, 1.11] |
| chacha20-poly1305 | 512 | 1 | registers | baseline | GB/s | 0.556 | 0.518 | 1.08 [1.03, 1.11] |
| chacha20-poly1305 | 1024 | 1 | registers | baseline | GB/s | 0.728 | 0.687 | 1.07 [0.945, 1.14] |
| chacha20-poly1305 | 4096 | 1 | registers | baseline | GB/s | 0.918 | 0.863 | 1.07 [1.03, 1.16] |
| chacha20-poly1305 | 16384 | 1 | registers | baseline | GB/s | 1.03 | 0.949 | 1.09 [1.08, 1.09] |
| chacha20-poly1305 | 4194304 | 1 | registers | baseline | GB/s | 1.03 | 0.944 | 1.09 [0.783, 1.26] |

Release and Release-safe passed 20 targeted native tests with one and
four workers. Both configurations also matched 1,547 independent tags
through one-shot and split updates with four workers.


## Four-worker comparison

Both Swag builds used four workers across CPUs 0–3. The baseline predates
IFMA and the candidate includes the register-state recurrence. Each case
used seven interleaved wall-time samples alongside one-thread external
references. All four layouts matched both references. The cgroup recorded
five throttled periods out of 55 during the run, totaling 84.6 ms.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| poly1305 | 4194304 | 1 | ifma | baseline | GB/s | 9.9 | 6.11 | 1.42 [0.685, 1.93] |
| poly1305 | 16777216 | 1 | ifma | baseline | GB/s | 12.7 | 7.08 | 1.59 [1.43, 2.14] |
| chacha20-poly1305 | 4194304 | 1 | ifma | baseline | GB/s | 2.74 | 2.34 | 1.13 [0.91, 1.74] |
| chacha20-poly1305 | 16777216 | 1 | ifma | baseline | GB/s | 3.04 | 2.49 | 1.21 [1.07, 1.85] |

For Poly1305 at 16 MiB, median aggregate CPU time fell from 7.06 to 4.13 ms
per operation. OpenSSL 4.1.0 measured 12.6 GB/s on one thread, with a
candidate-to-OpenSSL paired ratio of 1.03 [0.83, 1.34]. For
ChaCha20-Poly1305 at 16 MiB, median aggregate CPU time fell from 20.84 to
18.75 ms. OpenSSL measured 3.59 GB/s.

[Register-state raw results](poly1305-ifma-register-state.json) ·
[Deferred carry experiment](poly1305-ifma-deferred-carries.json) ·
[Four-worker raw results](poly1305-ifma-workers.json).
