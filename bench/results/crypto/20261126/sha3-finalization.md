# Direct SHA-3 and SHAKE finalization

The one-shot path now handles the full rate blocks and copies only the remainder. It
absorbs the suffix and terminal bit directly into the Keccak state, including the case
where both land in the same byte. Incremental hashing uses the same final absorption.

Both builds include the four-round Keccak kernel. Twenty paired process CPU-time
trials per profile ran on AMD EPYC 9V74 CPU 3. Times are microseconds per trial.

| Workload | Message bytes | Before | After | Paired speedup (95% CI) |
| --- | ---: | ---: | ---: | ---: |
| One-shot | 16 | 31998 | 28361 | 1.124 [1.041, 1.187] |
| One-shot | 64 | 27631 | 24925 | 1.113 [1.037, 1.130] |
| One-shot | 1024 | 10457 | 10294 | 1.012 [1.005, 1.022] |
| One-shot | 16384 | 9466 | 9414 | 1.006 [0.999, 1.018] |
| One-shot | 65536 | 9365 | 9358 | 1.000 [0.997, 1.007] |
| One-shot | 1048576 | 9397 | 9407 | 0.997 [0.969, 1.003] |
| Two updates | 16 | 36356 | 34992 | 1.026 [1.000, 1.052] |
| Two updates | 64 | 30877 | 30374 | 1.019 [1.008, 1.045] |
| Two updates | 1024 | 10708 | 10691 | 1.005 [0.977, 1.017] |
| Two updates | 16384 | 9500 | 9616 | 0.998 [0.965, 1.007] |
| Two updates | 65536 | 9473 | 9442 | 1.003 [0.993, 1.013] |
| Two updates | 1048576 | 9490 | 9410 | 1.008 [0.996, 1.032] |

The fixed and extendable-output vectors matched 1,440 external digest cases
covering empty messages, rate boundaries, offsets and multi-squeeze outputs.
The 11 focused Core cases passed native Release, Release-safe and JIT.

[Raw one-shot trials](sha3-finalization.json) · [Raw streaming trials](sha3-finalization-stream.json).
