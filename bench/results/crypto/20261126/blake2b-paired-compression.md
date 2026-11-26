# BLAKE2b compression interleave and short final blocks

The candidate runs independent G functions in pairs and reads message words directly from each little-endian input block. Big-endian conversion still uses a scratch buffer. One-shot messages up to 128 bytes use the final block directly, with zero padding for shorter messages and dedicated handling for a pending keyed block. Digest serialization clears the state on both one-shot and streaming paths. The Release benchmark executable grows by 448 bytes in its `.text` section.

## Method

The baseline is the BLAKE2b implementation from `51fc17f2fe4c6e506cc40605d4f79dad28a042d1`. Both Swag arms use the same Release compiler and runtime from `44e09064f1cef5af4258c0decaeb670e38053378`. The references use libsodium 1.0.22 BLAKE2b functions and the OpenSSL 4.1.0 default provider with `BLAKE2B-512` and `BLAKE2BMAC`. OpenSSL reuses the context allocation for each benchmark profile and resets the digest or MAC within every timed operation.

The benchmark uses 64-byte digests on inputs of 16, 64, 128, 1024, 65536 and 1048576 bytes. It tests one-shot mode and two updates split at half the input, with no key or a 32-byte key. Input starts one byte into storage, where byte `i` is `(37*i + 11) & 255`. Key byte `i` is `(19*i + 3) & 255`. Each batch performs `min(16000, 4194304 / input_bytes)` operations. Python hashlib checks the complete digest after every batch.

Timing uses `CLOCK_THREAD_CPUTIME_ID` pinned to CPU 3 on Linux x86-64 and an AMD EPYC 9V74. The final retest paused both compiler builds while an unrelated single-core test was active. It rotates order across all four implementations with five batches per rotation. All rows report median microseconds per batch. The rotation interval is the smallest and largest speedup calculated from the median of five batches in each rotation. [Final retest](blake2b-paired-compression-cpu3.json)

| Key bytes | Input mode | Input bytes | Previous Swag | Current Swag | libsodium | OpenSSL 4.1 | Swag speedup [rotation interval] |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | one-shot | 64 | 4909 | 4368.5 | 2298 | 3128.5 | 1.124× [1.074, 1.272] |
| 0 | one-shot | 1048576 | 7371.5 | 6345.5 | 4018 | 4082.5 | 1.162× [0.747, 1.465] |
| 0 | two updates | 64 | 5827 | 5358 | 2293 | 3204.5 | 1.088× [1.045, 1.292] |
| 0 | two updates | 1048576 | 6761.5 | 6495 | 4009.5 | 4121 | 1.041× [1.029, 1.068] |
| 32 | one-shot | 64 | 8781.5 | 7590 | 4458.5 | 5348 | 1.157× [1.098, 1.186] |
| 32 | one-shot | 1048576 | 6897.5 | 6327 | 4012.5 | 4089 | 1.090× [1.056, 1.155] |
| 32 | two updates | 64 | 9058.5 | 8764.5 | 4553 | 5415.5 | 1.034× [0.992, 1.081] |
| 32 | two updates | 1048576 | 6736 | 6516 | 4078.5 | 4078 | 1.034× [0.960, 1.066] |

The candidate's median CPU speedup is 1.026–1.185× among the 24 profiles. At 1 MiB the fastest external reference remains 1.58–1.62× faster. The rotation intervals show host variability, particularly for the unkeyed 1 MiB one-shot row.

The first CPU 3 comparison included the compression-only arm. Per-rotation CPU timings varied substantially under concurrent jobs, so the final retest supplies the headline results. The initial comparison still retains the full digests and samples for each of its five arms. [Initial CPU 3 comparison](blake2b-paired-compression-initial.json)

A second run during the reserved slot still overlapped two compiler builds at its start. All 24 medians favored the candidate by 1.060–1.135×. The headline comparison repeats the same four arms after pausing both builds. [Retest with initial build overlap](blake2b-paired-compression-overlap.json)

The packed SSE pair-state prototypes passed the same 896 extra digest checks but ran slower in the pilot. They achieved 0.29–0.31× previous one-shot throughput at 1 MiB. [SIMD pilot](blake2b-paired-compression-simd-pilot.json)

## Validation

Six focused Core BLAKE2b cases passed in each of native Release, native Release-safe and JIT. The combined candidate also matched 896 Python hashlib digests across four lengths, four key sizes, 14 payload lengths and four update profiles, using unaligned input. Each check compares every output byte.
