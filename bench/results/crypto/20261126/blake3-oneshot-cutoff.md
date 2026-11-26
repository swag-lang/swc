# BLAKE3 one-shot worker cutoff

One-shot hashing now lets the caller finish inputs of up to 32 chunks.
This avoids dispatch and temporary chaining-value storage on small inputs
when the process has two or more workers configured. The runtime worker
budget and the streaming update threshold are independent of this cutoff.

The baseline is Swag `c4d8ac822e`. The exact candidate and baseline used
the same Release compiler and Linux x86-64 benchmark executable source
on an AMD EPYC 9V74. BLAKE3 C 1.8.7 with dispatch width 16 supplied the
byte-equivalent serial reference. Each worker budget was measured at
11 paired interleaved rounds with a 15 ms wall-time target and affinity
`0,1,2,4`. The 10.695-second run added zero cgroup throttle events and
recorded 13.532 cgroup CPU seconds against 13.023 child CPU seconds.

All timed configurations matched the reference before sampling. A
separate verification run matched 32 aligned and unaligned size/budget
combinations, including both sides of the 32 KiB boundary. The focused
Core BLAKE3 suite passed 6 tests in Release and 6 in Release-safe.

| Input | Swag 2 workers before → after GB/s | Paired ratio with 95% CI | Swag 4 workers before → after GB/s | Paired ratio with 95% CI |
| --- | ---: | ---: | ---: | ---: |
| 8 KiB | 0.898 → 1.536 | 1.75× [1.38, 1.80] | 0.914 → 1.563 | 1.72× [1.66, 1.75] |
| 16 KiB | 1.139 → 1.565 | 1.38× [1.28, 1.41] | 1.139 → 1.582 | 1.39× [1.32, 1.43] |
| 32 KiB | 1.053 → 1.605 | 1.53× [1.38, 1.62] | 1.036 → 1.598 | 1.53× [1.37, 1.58] |
| 32,769 B | 1.621 → 1.675 | 1.02× [0.93, 1.18] | 1.407 → 1.355 | 0.96× [0.90, 1.09] |
| 65,535 B | 1.601 → 1.620 | 1.02× [0.89, 1.14] | 1.459 → 1.413 | 1.00× [0.92, 1.21] |
| 64 KiB | 1.594 → 1.555 | 0.97× [0.92, 1.12] | 1.373 → 1.425 | 1.05× [0.99, 1.14] |
| 128 KiB | 1.738 → 1.754 | 0.99× [0.93, 1.06] | 2.162 → 2.157 | 0.99× [0.91, 1.01] |
| 1 MiB | 2.509 → 2.486 | 1.00× [0.99, 1.10] | 3.286 → 3.282 | 0.99× [0.91, 1.11] |

Every measured interval above 32 KiB spans parity. An earlier 64 KiB
cutoff trial gave a 0.89× paired median [0.85, 1.00] at 65,535 bytes
with two workers. The 32-chunk cutoff retains the measured gains on
8, 16 and 32 KiB. At 1 MiB the official serial reference measured
6.490 and 6.518 GB/s in the two timed groups.

[Two-worker raw samples](blake3-oneshot-cutoff-2.json) ·
[Four-worker raw samples](blake3-oneshot-cutoff-4.json) ·
[Workload and build instructions](../../../workloads/blake3/README.md)
