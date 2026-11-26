# BLAKE2b direct round schedule addressing

BLAKE2b now computes the schedule pointer once per round so each G pair reads its message indexes at fixed offsets. The Release benchmark executable's `.text` changes by -96 bytes. The baseline is `56c8f34386`, and both Swag arms use the same Release compiler and runtime from `44e09064f1`. The fastest source in the previous comparison was libsodium 1.0.22, used again in this panel. [Previous BLAKE2b campaign](blake2b-paired-compression.md)

The CPU 3 comparison uses three rotated runs with five batches each, Linux x86-64 on an AMD EPYC 9V74, and `CLOCK_THREAD_CPUTIME_ID`. Its 24 profiles use the same inputs, keys, digest sizes and split points as the previous comparison. Each batch checks the complete digest with Python hashlib. All medians improve by 0.7–17.3%, with the four 1 MiB rows improving by 5.9–8.0%. Other cores showed variation in the small one-shot results. [CPU 3 samples](blake2b-round-schedule-cpu3.json)

| Key bytes | Input mode | Input bytes | Previous Swag | Current Swag | libsodium | Swag speedup [rotation interval] |
| ---: | --- | ---: | ---: | ---: | ---: | ---: |
| 0 | one-shot | 64 | 4552 | 4286 | 2295 | 1.062× [0.974, 1.222] |
| 0 | one-shot | 1048576 | 6465 | 6043 | 4020 | 1.070× [1.062, 1.074] |
| 0 | two updates | 64 | 5252 | 5216 | 2393 | 1.007× [0.966, 1.064] |
| 0 | two updates | 1048576 | 6425 | 6068 | 4020 | 1.059× [1.030, 1.075] |
| 32 | one-shot | 64 | 7815 | 7360 | 4532 | 1.062× [1.032, 1.147] |
| 32 | one-shot | 1048576 | 6458 | 6093 | 4021 | 1.060× [1.046, 1.076] |
| 32 | two updates | 64 | 8626 | 8235 | 4706 | 1.047× [1.031, 1.077] |
| 32 | two updates | 1048576 | 6644 | 6150 | 4083 | 1.080× [1.012, 1.334] |

The table shows median microseconds per batch. The rotation interval spans the smallest and largest five-batch median speedups. libsodium remains about 1.50–1.52× faster at 1 MiB.

Packed 32-bit or 64-bit message-index tables lost on several short profiles. Loading selected message words inside each G pair and compiling a separate bulk compression entry point brought smaller gains across the full panel than the round pointer alone. Skipping zero-padding writes in the fresh unkeyed buffer also regressed several profiles. [Packed schedule pilot](blake2b-round-schedule-cpu0.json) · [Compression entry point pilot](blake2b-round-schedule-cpu1.json)

Six focused BLAKE2b Core cases passed in each of native Release, native Release-safe and JIT. The selected change matched 896 additional Python hashlib digests, including unaligned one-shot and split input, shortened digests, and keyed input.
